import SwiftUI
import AppKit
import Observation
import HeyClaudeKit

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
        app.setActivationPolicy(.accessory)   // menu-bar agent: no Dock icon, no app menu
        app.run()
    }
}

/// Owns the status item, its menu, onboarding, and the voice-pipeline lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()
    private var onboarding: OnboardingWindowController?
    private var preferences: PreferencesWindowController?
    private var retrain: RetrainWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Onboarding owns its own window; the controller triggers it on first run.
        let ob = OnboardingWindowController(controller: controller)
        onboarding = ob
        controller.onNeedsOnboarding = { [weak ob] in ob?.show() }

        // Settings dashboard owns its own window, opened from the menu.
        let prefs = PreferencesWindowController(controller: controller)
        preferences = prefs

        // Wake-word re-training (Settings ▸ Voice) opens onboarding's train step in
        // a dedicated retrain-only window.
        let rt = RetrainWindowController(controller: controller)
        retrain = rt
        controller.onRetrainRequested = { [weak rt] in rt?.show() }

        // The status item, created FIRST with only its image. The image is plain
        // button content (like a title) and places fine synchronously.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        item.button?.image = MenuBarIcon.image(for: controller.state)
        statusItem = item

        // CRITICAL — DO NOT make the menu attach or `controller.start()` synchronous.
        // macOS places a new `NSStatusItem` ASYNCHRONOUSLY over the run loop. Two
        // distinct operations, if performed DURING that placement pass, knock the
        // item's window out of the menu bar (to ≈y−6, off-screen) so the icon never
        // appears — observed on macOS 26:
        //   1. assigning an `NSHostingMenu` (SwiftUI-hosted menu), and
        //   2. ordering ANY window front — the notch island (via `controller.start()`)
        //      or the onboarding window.
        // A bare item (image only) places correctly. So we gate BOTH the menu attach
        // AND the pipeline start behind confirmed placement.
        whenStatusItemPlaced(item) { [weak self] in
            guard let self, let item = self.statusItem else { return }
            item.menu = NSHostingMenu(rootView: MenuContentView(controller: self.controller, preferences: prefs))
            self.controller.start()
            self.observeState()
        }
    }

    /// Run `body` once the status item's window has actually been placed into the
    /// menu bar. macOS positions a new `NSStatusItem` asynchronously over the run
    /// loop; until then its window sits at the screen origin / off-screen. We poll
    /// the button window's position (placed ⇒ up in the menu-bar strip, in the top
    /// half of its own screen) every 50 ms, with a ~3 s safety cap so we never hang
    /// if the item can't place (full bar): in that case we proceed anyway.
    private func whenStatusItemPlaced(_ item: NSStatusItem, attempt: Int = 0, _ body: @escaping () -> Void) {
        let placed: Bool = {
            guard let win = item.button?.window, let screen = win.screen else { return false }
            return win.frame.origin.y > screen.frame.midY
        }()
        if placed || attempt >= 60 {        // 60 × 50 ms ≈ 3 s safety cap
            body()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.whenStatusItemPlaced(item, attempt: attempt + 1, body)
        }
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
