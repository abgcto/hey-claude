import AppKit
import CoreGraphics
import HeyClaudeKit

/// Owns a global CGEventTap that turns the configured push-to-talk key into
/// press/release calls on `AppController`. Listen-only: bare modifiers type
/// nothing, so the tap passes every event through (`return Unmanaged.passUnretained`).
///
/// Why CGEventTap and not `NSEvent.addGlobalMonitorForEvents`: the passive
/// monitor cannot be made reliable — a window switch can deliver `.flagsChanged`
/// to the wrong window and the key-up is missed, leaving capture stuck on. The
/// tap also lets us recover from the "silent disable race" (`...DisabledBy*`).
@MainActor
final class PushToTalkController {
    private weak var controller: AppController?
    private var key: PushToTalkKey
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var isHeld = false

    init(controller: AppController, key: PushToTalkKey) {
        self.controller = controller
        self.key = key
    }

    /// True once Input Monitoring is granted (the tap can actually receive keys).
    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Trigger the system Input-Monitoring prompt (no-op if already granted).
    static func requestPermission() { _ = CGRequestListenEventAccess() }

    /// Install the tap. Safe to call repeatedly; rebuilds on a key change.
    func start() {
        stop()
        guard PushToTalkController.hasPermission else { return }   // inert until granted

        // `.flagsChanged` drives the hold; `.keyDown` lets us detect Esc to cancel.
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        // `self` is passed via the refcon pointer (not a Swift closure capture)
        // so the callback stays a bare `@convention(c)` function pointer.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            // Listen-only → needs only Input Monitoring (a consuming `.defaultTap`
            // would require the heavier Accessibility grant). Esc still cancels the
            // hold — we detect it below — it just isn't swallowed, so it also reaches
            // the focused app. A passive tap on the main run loop is also safe (it
            // can't gate system-wide input).
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<PushToTalkController>.fromOpaque(refcon).takeUnretainedValue()
                me.handle(type: type, event: event)            // returns instantly
                return Unmanaged.passUnretained(event)          // listen-only: never consume
            }, userInfo: refcon)
        else { return }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Silent-disable-race recovery: re-enable if macOS disables the tap.
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let tap = self.tap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            }
        }
    }

    func stop() {
        healthTimer?.invalidate(); healthTimer = nil
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        runLoopSource = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        // If the key was held when we tore down, don't leave capture stuck.
        if isHeld { isHeld = false; controller?.pushToTalkReleased() }
    }

    /// Swap the trigger key (from Settings) — rebuilds the tap state machine.
    func setKey(_ newKey: PushToTalkKey) { key = newKey; isHeld = false }

    // Delivered on the main run loop (we added the source to `CFRunLoopGetMain()`),
    // so this is effectively main-actor work; hop explicitly to satisfy isolation.
    // Must return immediately — `pushToTalk*` only flip a flag and dispatch any
    // heavy mic work off this callback.
    private nonisolated func handle(type: CGEventType, event: CGEvent) {
        let flags = event.flags
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        MainActor.assumeIsolated {
            switch type {
            case .flagsChanged:
                self.decodeEdge(flags: flags, keycode: keycode)
            case .keyDown:
                // Esc (53) while holding → cancel the in-flight hold. Listen-only,
                // so Esc is NOT swallowed; it also reaches the focused app. Esc when
                // not holding is ignored here.
                if keycode == 53, self.isHeld {
                    self.isHeld = false
                    self.controller?.pushToTalkCancelled()
                }
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            default:
                break
            }
        }
    }

    /// Decide press vs release from the modifier flags + which key changed.
    /// Held = the trigger's keycode changed AND all required modifier flags are
    /// present. Released = any required flag dropped while we were held.
    private func decodeEdge(flags: CGEventFlags, keycode: Int64) {
        let primaryDown = flags.contains(key.requiredModifierFlag)
        let secondaryDown = key.secondaryModifierFlag.map { flags.contains($0) } ?? true
        let allDown = primaryDown && secondaryDown
        let isOurKey = keycode == key.keycode

        if !isHeld {
            // Rising edge: our key's flagsChanged with all required modifiers set.
            if allDown && isOurKey { isHeld = true; controller?.pushToTalkPressed() }
        } else {
            // Falling edge: a required modifier dropped.
            if !allDown { isHeld = false; controller?.pushToTalkReleased() }
        }
    }
}
