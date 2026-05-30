import AppKit
import SwiftUI

/// Hosts the onboarding `OnboardingView` in a real NSWindow. The app is a
/// menu-bar agent (`LSUIElement`), which suppresses SwiftUI `Window` scenes and
/// keeps windows from focusing — so we create the window manually (like
/// `NotchIslandPanel`) and flip the activation policy to `.regular` while it's
/// up, reverting to `.accessory` on close.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let controller: AppController
    private var window: NSWindow?
    private var model: OnboardingModel?
    private let flight = MascotFlightWindow()
    /// Set in `runFinale()` once the real "Done" path has committed, so the
    /// `windowWillClose` handler knows not to commit a second time.
    private var committed = false

    init(controller: AppController) {
        self.controller = controller
        super.init()
    }

    func show() {
        // Tear down any live pipeline before the window/enrollment opens, so a
        // re-run's mic tap can't coexist with `EnrollmentRecorder`'s second
        // `AVAudioEngine` tap. No-op on first run (nothing started yet).
        controller.suspendForOnboarding()

        if let window {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = OnboardingModel(controller: controller)
        self.model = model
        model.onDone = { [weak self] in self?.runFinale() }
        let host = NSHostingView(rootView: OnboardingView(model: model,
                                                          onClose: { [weak self] in self?.close() }))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
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
        win.center()
        window = win

        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The finale: close the window AT ONCE, then fly the mascot from where it was
    /// up into the notch shell on a separate overlay (so the window doesn't linger),
    /// and commit (resident island + pipeline) the moment it lands.
    private func runFinale() {
        // Mark committed up front: the finale owns the commit from here on, so any
        // window close (`orderOut` below, or a stray close event) won't re-commit.
        committed = true
        guard let window, let model, let screen = window.screen ?? NSScreen.main else {
            self.model?.commitFinish(); close(); return
        }
        let sf = screen.frame
        let wf = window.frame
        // Start: the window's upper-centre (where the Ready mascot sits).
        let start = CGPoint(x: wf.midX - sf.minX, y: sf.maxY - (wf.midY + wf.height * 0.20))
        // End: the island shell's mascot slot — top-centre, a touch left. (Tunable.)
        let end = CGPoint(x: sf.width / 2 - 26, y: 18)

        // Window vanishes immediately; the flight overlay carries on independently.
        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)

        flight.fly(on: screen, from: start, to: end, fromWidth: 64, toWidth: 22) { [weak self] in
            guard let self else { model.commitFinish(); return }
            // Resident mascot fills the notch THE INSTANT the flight lands — before
            // the pipeline's slow synchronous model load — so there's no gap as the
            // flight overlay dismisses.
            self.controller.setOnboardingIsland(.resting)
            self.window = nil
            self.model = nil
            // Boot the pipeline a beat later so the model load doesn't block the hand-off.
            DispatchQueue.main.async { model.commitFinish() }
        }
    }

    func close() {
        flight.dismiss()
        window?.orderOut(nil)
        window = nil
        model = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// The red close button / ⌘W path. AppKit fires this *as* the window closes;
    /// the "Not now" button and the finale both use `orderOut`, which does NOT
    /// fire this — so this only catches a raw window dismissal.
    ///
    /// If the finale already committed, do nothing. Otherwise treat it like
    /// "Skip for now": `model?.skip()` leaves the app functional (bundled keyword
    /// + booted pipeline), then we tear down our own state and revert the
    /// activation policy. We must NOT call `close()`/`orderOut` here — the window
    /// is already closing, and re-closing would recurse.
    func windowWillClose(_ notification: Notification) {
        if committed { return }
        model?.skip()
        flight.dismiss()
        model = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
