import AppKit
import SwiftUI

/// Hosts wake-word re-training from Settings ▸ Voice — the onboarding `train` step
/// reused via `OnboardingModel(mode: .retrainOnly)`, in its own window so it stays
/// clear of the first-run wizard's commit/finale semantics.
///
/// Lifecycle: `show()` suspends the live pipeline (so `EnrollmentRecorder` can own
/// the mic), then any exit — enrollment saved, "Skip for now", or a raw window
/// close — funnels through `finishRetrain()`, which resumes the pipeline once
/// (picking up a freshly saved keyword, or the prior one if cancelled).
@MainActor
final class RetrainWindowController: NSObject, NSWindowDelegate {
    private let controller: AppController
    private var window: NSWindow?
    private var model: OnboardingModel?

    init(controller: AppController) {
        self.controller = controller
        super.init()
    }

    /// `matchingFrame`: when supplied (the live Settings window frame), open exactly
    /// over it — same position and size — so re-training reads as the Settings panel
    /// drilling in rather than a new window popping up. Falls back to centering.
    func show(matchingFrame: NSRect? = nil) {
        controller.suspendForOnboarding()   // free the mic tap for the recorder

        if let window, let model {
            if let matchingFrame { window.setFrame(matchingFrame, display: false) }
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            model.startRetrain()
            return
        }

        let model = OnboardingModel(controller: controller, mode: .retrainOnly)
        self.model = model
        model.onRetrainComplete = { [weak self] in self?.finishRetrain() }

        let host = NSHostingView(rootView: OnboardingView(model: model))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
                           styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.standardWindowButton(.zoomButton)?.isHidden = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.isMovableByWindowBackground = true
        win.backgroundColor = .black
        win.isReleasedWhenClosed = false
        win.contentView = host
        win.delegate = self
        if let matchingFrame { win.setFrame(matchingFrame, display: false) } else { win.center() }
        window = win

        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.startRetrain()
    }

    /// Single exit path: close the window and resume listening. Guarded so the
    /// programmatic close (`orderOut`, which doesn't fire `windowWillClose`) and a
    /// raw red-button close can't both run it.
    private func finishRetrain() {
        guard window != nil else { return }
        window?.orderOut(nil)
        window = nil
        model = nil
        controller.resumeAfterRetrain()
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) { finishRetrain() }

    /// Returning from System Settings after granting mic access → auto-advance.
    func windowDidBecomeKey(_ notification: Notification) {
        model?.revalidateMicIfWaiting()
    }
}
