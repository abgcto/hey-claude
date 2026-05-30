import AppKit
import SwiftUI
import HeyClaudeKit

/// A transient, full-screen, click-through overlay that flies the mascot from the
/// onboarding window up to the notch (landing in the empty island shell). It owns
/// nothing permanent: `fly` shows it, runs one arc, then orders itself out and
/// calls `onLand`. Coordinates are SwiftUI top-left, relative to `screen.frame`.
@MainActor
final class MascotFlightWindow {
    private var panel: NSPanel?

    /// Arc the mascot from `start` to `end` (top-left points within `screen`),
    /// scaling `fromWidth` → `toWidth`, then dismiss and call `onLand`.
    func fly(on screen: NSScreen,
             from start: CGPoint, to end: CGPoint,
             fromWidth: CGFloat, toWidth: CGFloat,
             onLand: @escaping () -> Void) {
        let p = NSPanel(contentRect: screen.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // Above the island panel so the mascot flies over everything.
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        let host = NSHostingView(rootView: FlightView(
            start: start, end: end, fromWidth: fromWidth, toWidth: toWidth,
            onLand: { [weak self] in onLand(); self?.dismiss() }))
        host.layer?.backgroundColor = .clear
        if #available(macOS 13.3, *) { host.safeAreaRegions = [] }
        p.contentView = host
        p.setFrame(screen.frame, display: true)
        p.orderFrontRegardless()
        panel = p
    }

    func dismiss() { panel?.orderOut(nil); panel = nil }
}

/// The flying mascot: arcs (separate x/y keyframe tracks bow the path) and shrinks
/// to island size, then calls `onLand`. Honors reduced motion (jumps to the end).
private struct FlightView: View {
    let start: CGPoint
    let end: CGPoint
    let fromWidth: CGFloat
    let toWidth: CGFloat
    let onLand: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var go = false
    private let duration = 0.72

    private struct F { var x: CGFloat; var y: CGFloat; var w: CGFloat }

    // Arc control: rise toward the notch ahead of the sideways drift, with a small
    // lateral lean for character.
    private var ctrlX: CGFloat { start.x * 0.30 + end.x * 0.70 }
    private var ctrlY: CGFloat { end.y + (start.y - end.y) * 0.30 }

    var body: some View {
        MascotView(mascot: MascotCatalog.byID("classic"))
            .keyframeAnimator(initialValue: F(x: start.x, y: start.y, w: fromWidth),
                              trigger: go) { content, v in
                content.frame(width: v.w, height: v.w * 0.625).position(x: v.x, y: v.y)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    CubicKeyframe(ctrlX, duration: duration * 0.45)
                    CubicKeyframe(end.x, duration: duration * 0.55)
                }
                KeyframeTrack(\.y) {
                    CubicKeyframe(ctrlY, duration: duration * 0.45)
                    CubicKeyframe(end.y, duration: duration * 0.55)
                }
                KeyframeTrack(\.w) {
                    LinearKeyframe(toWidth, duration: duration)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                if reduce { onLand(); return }
                go.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) { onLand() }
            }
    }
}
