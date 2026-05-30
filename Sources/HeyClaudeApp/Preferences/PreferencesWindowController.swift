import AppKit
import SwiftUI

/// Hosts `PreferencesView` in a real NSWindow. Mirrors `OnboardingWindowController`:
/// the app is a menu-bar agent (`LSUIElement`) which suppresses SwiftUI `Window`
/// scenes and keeps windows from focusing, so we create the window manually and
/// flip the activation policy to `.regular` while it's up, reverting to
/// `.accessory` on close. The window is reused across re-opens.
@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private let controller: AppController
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
        super.init()
    }

    func show() {
        if let window {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingView(rootView: PreferencesView(controller: controller))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Hey Claude Settings"
        win.backgroundColor = .black
        // Code-created windows default to releasing on close; we hold a strong
        // ref for reuse, so disable that (a released window would dangle).
        win.isReleasedWhenClosed = false
        win.contentView = host
        win.delegate = self
        win.center()
        window = win

        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The red close button / ⌘W path. Revert to the accessory policy so the app
    /// drops back to a pure menu-bar agent. The window is kept (not nilled) for
    /// reuse on the next `show()`.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
