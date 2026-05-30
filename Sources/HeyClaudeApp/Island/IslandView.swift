import SwiftUI
import HeyClaudeKit

/// The dynamic-island band: a pure-black `NotchShape` fused to the underside of
/// the camera notch. It keeps the notch HEIGHT and widens sideways; the mascot
/// lives LEFT of the camera, the centre gap is the camera (kept clear), and the
/// per-state content sits RIGHT.
///
/// Ported from internal design notes. Renders a
/// pure `IslandModel` — every "which content / which treatment / which size"
/// decision is derived from `model.visual`, never re-decided here. All motion
/// (live-dot pulse, equalizer, mascot bob) is gated on `accessibilityReduceMotion`
/// so a reduced-motion system freezes to a still band.
struct IslandView: View {
    let model: IslandModel
    /// Height of the notch/menu-bar lip. The island's black body fills UP through
    /// this region (behind the physical notch) so the two fuse into one shape.
    var topInset: CGFloat = 0
    /// Physical notch width — kept clear in the centre so nothing renders over the
    /// camera. Total island width = leftArea + notchWidth + rightArea.
    var notchWidth: CGFloat = 189
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Skin (the locked palette).
    private let coral = Color(red: 1.0, green: 0.541, blue: 0.420)    // #ff8a6b
    private let violet = Color(red: 0.482, green: 0.361, blue: 1.0)   // #7b5cff
    private let inkText = Color(red: 0.953, green: 0.949, blue: 0.937) // #f3f2ef

    // MARK: - Per-state geometry

    private var isTranscript: Bool {
        if case .transcript = model.visual { return true }
        return false
    }

    private var isMuted: Bool { model.visual == .muted }

    /// Snug well for the ~22px mascot (mascot + breathing room).
    private let leftArea: CGFloat = 34

    /// Right-of-camera content width, sized to the state (mockup proportions).
    private var rightArea: CGFloat {
        switch model.visual {
        case .hidden, .idle, .muted: return 34
        case .listening:             return 78
        case .transcript:            return 190
        case .launching, .paused:    return 96
        }
    }

    private var islandWidth: CGFloat { leftArea + notchWidth + rightArea }

    /// Only the transcript state breaks the notch height, growing down + out.
    private var bandHeight: CGFloat { isTranscript ? topInset + 14 : topInset }

    var body: some View {
        HStack(spacing: 0) {
            // Left of the camera: the mascot, present in every visible state.
            MascotView()
                .frame(width: 22, height: 14)
                .offset(y: mascotBob)
                .animation(mascotBobAnimation, value: mascotBobActive)
                .frame(width: leftArea)
            // The camera gap — kept clear (the physical notch sits here).
            Color.clear.frame(width: notchWidth)
            // Right of the camera: the per-state content.
            ZStack(alignment: .leading) { rightContent }
                .frame(width: rightArea, alignment: .leading)
        }
        .frame(width: islandWidth, height: bandHeight)
        // Pure black so it fuses with the camera notch into one dynamic-island shape.
        .background(
            NotchShape(topCornerRadius: 6, bottomCornerRadius: 10)
                .fill(Color.black)
        )
        .compositingGroup()
        // Paused dims hard (~60%); muted is only slightly dimmed.
        .opacity(model.dimmed ? 0.6 : (isMuted ? 0.78 : 1))
        .opacity(model.hidden ? 0 : 1)
        .animation(shapeAnimation, value: islandWidth)
        .animation(shapeAnimation, value: bandHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.dimmed)
    }

    private var shapeAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)
    }

    // MARK: - Right content (one branch per visual state)

    @ViewBuilder private var rightContent: some View {
        switch model.visual {
        case .hidden:
            EmptyView()

        case .idle:
            // A single calm dim grey dot.
            Circle()
                .fill(inkText.opacity(0.22))
                .frame(width: 6, height: 6)
                .padding(.leading, 2)

        case .listening:
            HStack(spacing: 7) {
                StatusDot(live: true, color: coral, reduce: reduceMotion)
                LevelBars(color: coral, reduce: reduceMotion)
            }
            .padding(.leading, 2)

        case .transcript(let text):
            VStack(alignment: .leading, spacing: 2) {
                // Coral mono kicker with a leading live dot.
                HStack(spacing: 5) {
                    Circle()
                        .fill(coral)
                        .frame(width: 5, height: 5)
                        .shadow(color: coral.opacity(0.8), radius: 3)
                    Text("HEARING")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(coral)
                }
                // The spoken line — single line, truncates with a tail ellipsis.
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(inkText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 2)
            .padding(.trailing, 6)

        case .launching:
            HStack(spacing: 7) {
                Text("→")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(coral)
                Text("LAUNCHING").modifier(LabelStyle(color: coral))
            }
            .padding(.leading, 2)

        case .muted:
            // White mic glyph crossed by a coral diagonal slash (mockup's
            // slashed-mic SVG). Drawn as a plain mic + an explicit coral stroke
            // so it reads in colour on macOS 13 (no hierarchical two-tone API).
            ZStack {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(inkText.opacity(0.7))
                MutedSlash(color: coral)
                    .frame(width: 15, height: 15)
            }
            .frame(width: 15, height: 15)
            .padding(.leading, 2)

        case .paused:
            HStack(spacing: 7) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(violet)
                Text("PAUSED").modifier(LabelStyle(color: violet))
            }
            .padding(.leading, 2)
        }
    }

    // MARK: - Mascot bob (gentle, listening only)

    private var mascotBobActive: Bool {
        if reduceMotion { return false }
        if case .listening = model.visual { return true }
        return false
    }
    private var mascotBob: CGFloat { mascotBobActive ? -1 : 0 }
    private var mascotBobAnimation: Animation? {
        mascotBobActive
            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
            : (reduceMotion ? nil : .easeInOut(duration: 0.3))
    }
}

// MARK: - Helper views

/// The coral diagonal slash crossing the muted mic, top-left to bottom-right.
/// Matches the mockup's `<line x1="3" y1="3" x2="21" y2="21" stroke="#ff8a6b">`.
private struct MutedSlash: View {
    var color: Color
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let inset = geo.size.width * 0.12
                p.move(to: CGPoint(x: inset, y: inset))
                p.addLine(to: CGPoint(x: geo.size.width - inset,
                                      y: geo.size.height - inset))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// Mono ~9px uppercase status label — the island's text role besides the
/// transcript. Matches the mockup's `.label`.
private struct LabelStyle: ViewModifier {
    var color: Color
    func body(content: Content) -> some View {
        content
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The leading live status dot. The coral variant pulses; pulse is suppressed
/// under reduced motion. Matches the mockup's `.live-dot--pulse`.
private struct StatusDot: View {
    let live: Bool
    let color: Color
    let reduce: Bool
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: live ? color.opacity(0.8) : .clear, radius: live ? 4 : 0)
            .scaleEffect(live && on ? 1.0 : (live ? 0.78 : 1.0))
            .opacity(live ? (on ? 1.0 : 0.45) : 1.0)
            .onAppear {
                guard live, !reduce else { return }
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

/// A five-bar equalizer that animates like a live meter while listening.
/// Matches the mockup's `.eq--live` (5 bars, staggered phases). Reduced motion
/// freezes the bars at representative resting heights.
private struct LevelBars: View {
    let color: Color
    let reduce: Bool
    @State private var animating = false

    // Per-bar resting height + animation phase delay (mockup's bar1…bar5).
    private let bars: [(height: CGFloat, delay: Double)] = [
        (9, 0.0), (13, 0.18), (6, 0.30), (11, 0.10), (7, 0.24),
    ]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: bars[i].height)
                    .scaleEffect(y: animating ? 1.0 : 0.4, anchor: .bottom)
                    .animation(
                        reduce ? nil
                        : .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(bars[i].delay),
                        value: animating)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .onAppear { if !reduce { animating = true } }
    }
}
