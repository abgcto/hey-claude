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

/// Hosts `IslandView` but only "catches" the pointer over the island's actual
/// shape — the band, plus the dropped panel when expanded. Everywhere else on the
/// full-width transparent canvas returns `nil`, so clicks fall straight through to
/// the app beneath (the canvas never steals events). The interactive frame is
/// configured by `NotchIslandPanel` from the same `IslandGeometry` the view draws
/// with, and its height tracks the live panel height reported by SwiftUI.
private final class IslandHostingView: NSHostingView<AnyView> {
    var islandWidth: CGFloat = 0
    var bandHeight: CGFloat = 0
    var panelHeight: CGFloat = 0      // dropped control panel; 0 when collapsed
    var interactive = false           // false during onboarding / hidden → fully click-through

    required init(rootView: AnyView) { super.init(rootView: rootView) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    private var interactiveRect: NSRect {
        guard interactive, islandWidth > 0 else { return .zero }
        let total = bandHeight + panelHeight
        let x = (bounds.width - islandWidth) / 2
        // The island is pinned to the TOP of the canvas; `isFlipped` tells us which
        // edge of our own coordinate space that is.
        let y = isFlipped ? 0 : bounds.height - total
        return NSRect(x: x, y: y, width: islandWidth, height: total)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard interactiveRect.contains(local) else { return nil }
        return super.hitTest(point)
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
    private let host: IslandHostingView
    /// The island blooms open on the panel's FIRST update (app launch), then never
    /// again — ordinary state changes shouldn't re-trigger the entrance.
    private var hasBloomed = false

    /// The notch screen's frame, refreshed each `update`; the mouse-tracking math
    /// maps the island's footprint into screen coordinates with it.
    private var screenFrame: CGRect = .zero
    /// Global + local `.mouseMoved` monitors driving `syncClickThrough()`. Removed
    /// on `deinit`. `nonisolated(unsafe)`: only mutated on the main actor (in
    /// `startMouseTracking`), only read again from the nonisolated `deinit` once all
    /// references are gone — no concurrent access.
    nonisolated(unsafe) private var mouseMonitors: [Any] = []

    init() {
        host = IslandHostingView(rootView: AnyView(EmptyView()))
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
        // Click-through by DEFAULT: this full-width canvas overlaps the entire menu
        // bar, so the panel must not swallow events outside its own shape.
        // `ignoresMouseEvents` is toggled live by `syncClickThrough()` — ON only
        // while the pointer is over the island's footprint, OFF (click-through)
        // everywhere else. A view `hitTest` returning nil is NOT sufficient: the
        // window server picks the target window (frame + level + ignoresMouseEvents)
        // BEFORE AppKit consults the view, so a higher-level full-width panel would
        // otherwise eat menu-bar / status-item clicks. Stays non-activating, so
        // hovering/clicking never steals focus from the editor.
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true       // needed for SwiftUI .onHover tracking
        panel.contentView = host
        // Set level LAST: `isFloatingPanel`/other config can reset it. Must be
        // ABOVE the menu bar (.mainMenu) to draw up in the notch region — at the
        // default floating level the menu bar covers the top and the island
        // appears below the notch.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        startMouseTracking()
    }

    /// Toggle `ignoresMouseEvents` so the panel only catches the pointer over the
    /// island's live footprint and is fully click-through everywhere else — most
    /// importantly the menu bar, whose status items a higher-level full-width window
    /// would otherwise block. Both monitors are needed: the GLOBAL one fires while
    /// other apps are frontmost (the normal case for this non-activating panel); the
    /// LOCAL one fires while Hey Claude itself is frontmost (e.g. Preferences open).
    private func startMouseTracking() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.syncClickThrough()
        }
        if let global { mouseMonitors.append(global) }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.syncClickThrough()
            return event
        }
        if let local { mouseMonitors.append(local) }
        syncClickThrough()
    }

    /// The island's live footprint in screen coordinates (band + any dropped control
    /// panel). `.zero` when presence-only (onboarding) or before the first layout, so
    /// the panel then stays fully click-through.
    private var islandScreenRect: CGRect {
        guard host.interactive, host.islandWidth > 0, !screenFrame.isEmpty else { return .zero }
        let total = host.bandHeight + host.panelHeight
        // A buffer around the visible footprint. The click-through toggle is driven
        // by coalesced `.mouseMoved` samples, so a fast cursor can briefly sample
        // "outside" and flip to click-through mid-interaction (hover flickers). The
        // margin keeps the region interactive through that slop. Top stays pinned to
        // the screen edge; sides + bottom get the buffer (the panel grows downward).
        let m: CGFloat = 16
        return CGRect(x: screenFrame.midX - host.islandWidth / 2 - m,
                      y: screenFrame.maxY - total - m,
                      width: host.islandWidth + m * 2,
                      height: total + m)
    }

    /// Set `ignoresMouseEvents` from the current pointer position. Cheap; called on
    /// every mouse-move and at the end of each `update`.
    private func syncClickThrough() {
        let shouldIgnore = !islandScreenRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents != shouldIgnore { panel.ignoresMouseEvents = shouldIgnore }
    }

    deinit { mouseMonitors.forEach { NSEvent.removeMonitor($0) } }

    /// Re-host for the new model, resize + reposition under the notch, and
    /// order front (or out when the island should be hidden, e.g. `off`).
    ///
    /// `mascot` / `mascotColorHex` are the user-selected mascot + body color
    /// (resolved by `AppController` from `Settings`). The color crosses the
    /// app/Kit boundary as a hex string and is converted to `Color` here, in the
    /// SwiftUI layer. Both default to Classic + clay so the onboarding call sites
    /// — which run before any selection exists — compile and render unchanged.
    /// `controls` carries the hover-panel actions/data (mute, target, settings,
    /// quit). When `nil` the island is presence-only (onboarding) and the hit-region
    /// stays empty — fully click-through, exactly as before this feature.
    func update(_ model: IslandModel,
                mascot: Mascot = MascotCatalog.byID("classic"),
                mascotColorHex: String = "#D87757",
                mascotIdleAnimations: Bool = true,
                controls: IslandControls? = nil) {
        guard let screen = Self.notchScreen() else { panel.orderOut(nil); return }
        let notch = screen.notchSize
        let f = screen.frame
        screenFrame = f         // keep the mouse-tracking geometry in sync
        // A full-width, tall, transparent canvas pinned to the screen TOP. The
        // island shape is centered at the top within it (the vibe-notch model) —
        // far more robust than positioning a tiny window exactly on the notch.
        let canvasHeight: CGFloat = 260
        panel.setFrame(NSRect(x: f.origin.x, y: f.maxY - canvasHeight,
                              width: f.width, height: canvasHeight), display: true)
        let bloom = !hasBloomed
        hasBloomed = true

        // Configure the click-through hit-region: the band is always interactive
        // (so it can receive hover); the dropped panel's height is filled in live by
        // the view via `onPanelHeight`.
        host.islandWidth = IslandGeometry.islandWidth(notchWidth: notch.width)
        host.bandHeight = notch.height
        host.interactive = !model.hidden && controls != nil

        host.rootView = AnyView(
            VStack(spacing: 0) {
                IslandView(model: model, topInset: notch.height, notchWidth: notch.width, bloom: bloom,
                           mascot: mascot, mascotColor: Color(hex: mascotColorHex),
                           mascotIdleAnimations: mascotIdleAnimations,
                           controls: controls,
                           onPanelHeight: { [weak self] h in
                               guard let self else { return }
                               // The dropped panel changed height (e.g. the target list
                               // expanded). Re-evaluate click-through NOW so the grown
                               // region catches the new rows immediately — otherwise a
                               // click on a just-revealed target falls through until the
                               // next mouse-move.
                               self.host.panelHeight = h
                               self.syncClickThrough()
                           })
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
        )
        if model.hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        // Interactive footprint may have changed (width per mascot/state, or the
        // panel collapsing); re-evaluate click-through for the pointer's spot now.
        syncClickThrough()
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
