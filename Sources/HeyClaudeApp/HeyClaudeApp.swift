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

/// Owns onboarding, Settings/retrain windows, and the voice-pipeline lifecycle.
/// There is NO menu-bar status item — the notch island is the app's sole surface.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()
    private var onboarding: OnboardingWindowController?
    private var preferences: PreferencesWindowController?
    private var retrain: RetrainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Onboarding owns its own window; the controller triggers it on first run.
        let ob = OnboardingWindowController(controller: controller)
        onboarding = ob
        controller.onNeedsOnboarding = { [weak ob] in ob?.show() }

        // Settings dashboard owns its own window, opened from the notch control panel.
        let prefs = PreferencesWindowController(controller: controller)
        preferences = prefs
        controller.onOpenSettings = { [weak prefs] in prefs?.show() }

        // Wake-word re-training (Settings ▸ Voice) opens onboarding's train step in
        // a dedicated retrain-only window.
        let rt = RetrainWindowController(controller: controller)
        retrain = rt
        controller.onRetrainRequested = { [weak rt] in rt?.show() }

        // No menu-bar status item. The notch island is the app's only, always-on
        // surface — it carries mute, target, Recent, failures, mic recovery, Settings
        // and Quit (when mic is denied it stays visible and tappable to recover, so
        // the app is never unreachable). This also removes the fragile NSStatusItem
        // placement dance the menu-bar item needed on macOS 26.
        controller.start()
    }
}
