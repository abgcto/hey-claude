import AppKit
import SwiftUI
import HeyClaudeKit

/// A panel that does NOT let AppKit constrain it below the menu bar — required
/// to sit up in the notch. By default `NSWindow.constrainFrameRect(_:to:)`
/// pushes borderless windows down so their top clears the menu bar, which is
/// exactly the gap we must avoid: the island has to fuse to the notch lip.
private final class NonConstrainingPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

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
    /// The island blooms open on the panel's FIRST update (app launch), then never
    /// again — ordinary state changes shouldn't re-trigger the entrance.
    private var hasBloomed = false

    init() {
        host = NSHostingView(rootView: AnyView(EmptyView()))
        host.layer?.backgroundColor = .clear
        // Critical: without this, NSHostingView insets content by the notch
        // safe area, pushing the whole island DOWN below the notch (so it can
        // never fuse). Let it fill up into the notch region instead.
        if #available(macOS 13.3, *) { host.safeAreaRegions = [] }

        panel = NonConstrainingPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true            // presence-only; never steals focus/clicks
        panel.contentView = host
        // Set level LAST: `isFloatingPanel`/other config can reset it. Must be
        // ABOVE the menu bar (.mainMenu) to draw up in the notch region — at the
        // default floating level the menu bar covers the top and the island
        // appears below the notch.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    }

    /// Re-host for the new model, resize + reposition under the notch, and
    /// order front (or out when the island should be hidden, e.g. `off`).
    ///
    /// `mascot` / `mascotColorHex` are the user-selected mascot + body color
    /// (resolved by `AppController` from `Settings`). The color crosses the
    /// app/Kit boundary as a hex string and is converted to `Color` here, in the
    /// SwiftUI layer. Both default to Classic + clay so the onboarding call sites
    /// — which run before any selection exists — compile and render unchanged.
    func update(_ model: IslandModel,
                mascot: Mascot = MascotCatalog.byID("classic"),
                mascotColorHex: String = "#D87757") {
        guard let screen = Self.notchScreen() else { panel.orderOut(nil); return }
        let notch = screen.notchSize
        let f = screen.frame
        // A full-width, tall, transparent canvas pinned to the screen TOP. The
        // island shape is centered at the top within it (the vibe-notch model) —
        // far more robust than positioning a tiny window exactly on the notch.
        let canvasHeight: CGFloat = 260
        panel.setFrame(NSRect(x: f.origin.x, y: f.maxY - canvasHeight,
                              width: f.width, height: canvasHeight), display: true)
        let bloom = !hasBloomed
        hasBloomed = true
        host.rootView = AnyView(
            VStack(spacing: 0) {
                IslandView(model: model, topInset: notch.height, notchWidth: notch.width, bloom: bloom,
                           mascot: mascot, mascotColor: Color(hex: mascotColorHex))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
        )
        if model.hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// The screen bearing the notch, if any; otherwise the focused/main screen.
    private static func notchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
    }
}

private extension NSScreen {
    /// Notch footprint (width × height). Width = full width minus the menu-bar
    /// areas left/right of the notch (+4 to match the genre's alignment); height
    /// = `safeAreaInsets.top`. Falls back to typical MacBook notch dims on
    /// non-notch displays so the island still renders a sensible bar.
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else { return CGSize(width: 224, height: 38) }
        let h = safeAreaInsets.top
        let left = auxiliaryTopLeftArea?.width ?? 0
        let right = auxiliaryTopRightArea?.width ?? 0
        guard left > 0, right > 0 else { return CGSize(width: 200, height: h) }
        return CGSize(width: frame.width - left - right + 4, height: h)
    }
}
