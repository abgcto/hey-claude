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

    func close() {
        window?.orderOut(nil)
        window = nil
        model = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
