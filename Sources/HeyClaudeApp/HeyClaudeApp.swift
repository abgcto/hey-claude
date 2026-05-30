import SwiftUI
import AppKit
import Observation
import HeyClaudeKit

// TEMP DIAGNOSTIC: trace the status-item lifecycle to a file (NSLog isn't reliably
// queryable for this app). Remove once the menu-bar icon is confirmed working.
func appTrace(_ s: String) {
    let line = "\(Date()) \(s)\n"
    let url = URL(fileURLWithPath: "/tmp/hc_app_trace.log")
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

// TEMP DIAGNOSTIC: start each launch with a fresh trace file.
func appTraceReset() {
    try? "".write(to: URL(fileURLWithPath: "/tmp/hc_app_trace.log"), atomically: true, encoding: .utf8)
}

// TEMP DIAGNOSTIC: where did macOS actually place the status button, and on which
// screen? On a notched Mac, `auxiliaryTopRightArea` is the usable menu-bar strip to
// the RIGHT of the notch — if the button's x exceeds that (or its window is nil /
// on another screen) the icon is being clipped/hidden by macOS, not a render bug.
@MainActor
func appTraceGeometry(_ item: NSStatusItem, _ tag: String) {
    appTrace("[\(tag)] barThickness=\(NSStatusBar.system.thickness)")
    if let b = item.button {
        appTrace("[\(tag)] button.frame=\(b.frame) button.isHidden=\(b.isHidden)")
        if let w = b.window {
            let scr = w.screen.map { NSScreen.screens.firstIndex(of: $0).map(String.init) ?? "?" } ?? "nil"
            appTrace("[\(tag)] win.frame=\(w.frame) win.isVisible=\(w.isVisible) win.screenIdx=\(scr)")
        } else {
            appTrace("[\(tag)] button.window=NIL  (item not attached to a status bar)")
        }
    } else {
        appTrace("[\(tag)] button=NIL")
    }
    for (i, s) in NSScreen.screens.enumerated() {
        appTrace("[\(tag)] screen[\(i)] frame=\(s.frame) safeTop=\(s.safeAreaInsets.top) auxL=\(s.auxiliaryTopLeftArea.map { "\($0)" } ?? "nil") auxR=\(s.auxiliaryTopRightArea.map { "\($0)" } ?? "nil")")
    }
    for w in NSApp.windows {
        appTrace("[\(tag)] window class=\(type(of: w)) level=\(w.level.rawValue) frame=\(w.frame) visible=\(w.isVisible)")
    }
}

/// Hey Claude menu-bar app (Phase 3A). Pure AppKit entry point: a plain
/// `NSApplication` in `.accessory` mode with an `NSStatusItem` — NOT a SwiftUI
/// `MenuBarExtra` and NOT a SwiftUI `App` scene.
///
/// Why: `MenuBarExtra` is the app's only scene, so when macOS can't place its
/// status item (full menu bar, or launch-throttling) it removes the item and the
/// whole app self-terminates. A SwiftUI `App` with an inert `Settings` scene +
/// `NSApplicationDelegateAdaptor` turned out not to host an `NSStatusItem`
/// reliably either. A bare AppKit status-item app is the proven, robust pattern
/// (Bartender/iStat): the item just hides if there's no room; the app keeps running.
@main
@MainActor
enum HeyClaudeMain {
    /// Strong reference for the app's lifetime — `NSApplication.delegate` is weak.
    static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let d = AppDelegate()
        delegate = d
        app.delegate = d
        // NOTE: activation policy is now set inside applicationDidFinishLaunching
        // (DIAGNOSTIC): the status-bar server may not adopt an item when the app
        // boots straight into .accessory before finishing launch.
        app.run()
    }
}

/// Owns the status item, its menu, onboarding, and the voice-pipeline lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()
    private var onboarding: OnboardingWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appTraceReset()
        appTrace("didFinishLaunching ENTER policy=\(NSApp.activationPolicy().rawValue)")
        NSApp.setActivationPolicy(.accessory)   // DIAGNOSTIC: set here, not in main()
        appTrace("after setActivationPolicy policy=\(NSApp.activationPolicy().rawValue)")
        // Onboarding first, so the menu's "Set up…" item and the controller's
        // first-run hook can both reference it.
        let ob = OnboardingWindowController(controller: controller)
        onboarding = ob
        controller.onNeedsOnboarding = { [weak ob] in ob?.show() }

        // The status item. If the menu bar is full it hides — but the app stays
        // alive (the whole reason we left MenuBarExtra).
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        item.button?.image = MenuBarIcon.image(for: controller.state)
        item.button?.title = "HC"   // TEMP PROBE — remove once the icon is confirmed
        item.menu = NSHostingMenu(rootView: MenuContentView(controller: controller, onboarding: ob))
        statusItem = item
        appTrace("statusItem: button=\(item.button != nil) image=\(item.button?.image != nil) visible=\(item.isVisible)")
        appTraceGeometry(item, "sync")
        // The button's window often isn't realized until the run loop spins.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, let item = self.statusItem else { return }
            appTraceGeometry(item, "delayed")
        }

        controller.start()
        observeState()
        appTrace("didFinishLaunching DONE")
    }

    /// Keep the menu-bar icon in sync with `AppState`. `withObservationTracking`
    /// fires once per change, so we re-arm it inside the handler.
    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.statusItem?.button?.image = MenuBarIcon.image(for: self.controller.state)
                self.observeState()
            }
        }
    }
}
