import AppKit
import SwiftUI

/// Hosts the onboarding `OnboardingView` in a real NSWindow. The app is a
/// menu-bar agent (`LSUIElement`), which suppresses SwiftUI `Window` scenes and
/// keeps windows from focusing — so we create the window manually (like
/// `NotchIslandPanel`) and flip the activation policy to `.regular` while it's
/// up, reverting to `.accessory` on close.
@MainActor
final class OnboardingWindowController {
    private let controller: AppController
    private var window: NSWindow?
    private var model: OnboardingModel?
    private let flight = MascotFlightWindow()

    init(controller: AppController) { self.controller = controller }

    func show() {
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
}
