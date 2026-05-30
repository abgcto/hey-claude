import AppKit
import SwiftUI
import HeyClaudeKit

/// A borderless, non-activating, always-on-top panel hosting `IslandView`,
/// positioned centered under the notch (or top-center on non-notch displays).
///
/// Presence-only: it never activates, never steals focus, and ignores mouse
/// events entirely, so it floats over the editor without intercepting clicks.
/// `update(_:)` re-hosts the SwiftUI view for the new model, repositions to the
/// new capsule size, and orders the panel front (or out, when `hidden`).
@MainActor
final class NotchIslandPanel {
    private let panel: NSPanel
    private let host: NSHostingView<AnyView>

    init() {
        host = NSHostingView(rootView: AnyView(EmptyView()))
        host.layer?.backgroundColor = .clear

        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true            // presence-only; never steals focus/clicks
        panel.contentView = host
    }

    /// Re-host for the new model, resize + reposition under the notch, and
    /// order front (or out when the island should be hidden, e.g. `off`).
    func update(_ model: IslandModel) {
        host.rootView = AnyView(IslandView(model: model))
        let size = Self.size(for: model.shape)
        reposition(width: size.width, height: size.height)
        if model.hidden {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Capsule footprint per shape — the SwiftUI view pins itself to the top of
    /// this frame, so the panel must be at least as tall as the expanded pill.
    private static func size(for shape: IslandModel.Shape) -> CGSize {
        switch shape {
        case .seam:     return CGSize(width: 150, height: 14)
        case .expanded: return CGSize(width: 320, height: 44)
        }
    }

    /// Centered horizontally and pinned to the very top of the notch screen so
    /// the capsule fuses to the notch's lower lip. Prefers the screen that
    /// actually has a notch (`safeAreaInsets.top > 0`); on non-notch Macs this
    /// degrades to a top-center floating bar.
    private func reposition(width: CGFloat, height: CGFloat) {
        guard let screen = Self.notchScreen() else { return }
        let frame = screen.frame
        let x = frame.midX - width / 2
        let y = frame.maxY - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    /// The screen bearing the notch, if any; otherwise the focused/main screen.
    private static func notchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
    }
}
