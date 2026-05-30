import SwiftUI
import HeyClaudeKit

/// The "Seam" island: a warm plum capsule fused to the underside of the notch,
/// with the canonical mascot living in a left well and a single content slot
/// that carries each voice state (Listening + level meter, the transcript
/// reveal, "→ Launching Claude"). Renders a pure `IslandModel`; all "which
/// content / which treatment" decisions live there, never here.
///
/// Ported from internal design notes. Shape changes
/// spring; the level meter and live dot pulse — all motion is gated on
/// `accessibilityReduceMotion` so a reduced-motion system freezes to a still seam.
struct IslandView: View {
    let model: IslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Skin (the locked palette).
    private let plum = Color(red: 0.043, green: 0.027, blue: 0.071)   // #0b0712
    private let coral = Color(red: 1.0, green: 0.541, blue: 0.420)    // #ff8a6b
    private let violet = Color(red: 0.482, green: 0.361, blue: 1.0)   // #7b5cff
    private let inkText = Color(red: 0.953, green: 0.949, blue: 0.937) // #f3f2ef

    private var expanded: Bool { model.shape == .expanded }

    var body: some View {
        HStack(spacing: expanded ? 12 : 0) {
            // Mascot well. At rest the head peeks above the seam's lower lip;
            // expanded it sits flush in its 24×15 left well. Never clipped — the
            // peek is intentional, so the well sits at the top edge.
            MascotView()
                .frame(width: 24, height: 15)

            if expanded {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, expanded ? 12 : 0)
        .padding(.trailing, expanded ? 18 : 0)
        .frame(width: expanded ? 320 : 150, height: expanded ? 44 : 14, alignment: .top)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 17 : 12,
                                   bottomTrailingRadius: expanded ? 17 : 12)
                .fill(plum)
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 17 : 12,
                                           bottomTrailingRadius: expanded ? 17 : 12)
                        .strokeBorder(coral.opacity(0.15), lineWidth: 1)
                )
        )
        .overlay(alignment: .leading) { if model.dimmed { curtain } }
        .overlay { if model.showsSlash { slash } }
        .compositingGroup()
        .opacity(model.dimmed ? 0.6 : 1)
        .opacity(model.hidden ? 0 : 1)
        .animation(shapeAnimation, value: model.shape)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.dimmed)
    }

    private var shapeAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)
    }

    // MARK: - Content slot

    @ViewBuilder private var content: some View {
        switch model.content {
        case .listening:
            HStack(spacing: 8) {
                label("Listening…", live: true)
                LevelBars(color: coral, reduce: reduceMotion)
            }
        case .transcript(let text):
            // Live transcripts carry no per-word markup, so the whole phrase is
            // rendered plainly (the mockup's hardcoded coral italic on one word
            // can't be derived from arbitrary speech). Serif italic gives the
            // "handed back to you" feel without a bundled Newsreader face.
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(inkText)
                .lineLimit(1)
                .truncationMode(.tail)
        case .launching:
            HStack(spacing: 7) {
                Text("→")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(coral)
                Text("LAUNCHING CLAUDE").modifier(LabelStyle())
            }
        case .none:
            // Paused holds an expanded-but-empty slot (dimmed treatment carries it).
            EmptyView()
        }
    }

    /// A mono uppercase status label with a leading status dot.
    private func label(_ text: String, live: Bool) -> some View {
        HStack(spacing: 7) {
            StatusDot(live: live, color: live ? coral : Color(white: 0.44),
                      reduce: reduceMotion)
            Text(text.uppercased()).modifier(LabelStyle())
        }
    }

    // MARK: - Treatments

    /// Muted: a thin slash drawn across the seam.
    private var slash: some View {
        GeometryReader { geo in
            Path { p in
                let inset = geo.size.width * 0.09
                let y = geo.size.height / 2
                p.move(to: CGPoint(x: inset, y: y + 3))
                p.addLine(to: CGPoint(x: geo.size.width - inset, y: y - 3))
            }
            .stroke(inkText.opacity(0.45), lineWidth: 1.4)
        }
        .allowsHitTesting(false)
    }

    /// Paused: a violet edge curtain down the leading side.
    private var curtain: some View {
        Rectangle()
            .fill(violet.opacity(0.30))
            .frame(width: 5)
            .allowsHitTesting(false)
    }
}

// MARK: - Helper views

/// Mono 9.5px uppercase status label — the island's only text role besides the
/// transcript. Matches `.lbl` in the mockup.
private struct LabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Color(red: 0.953, green: 0.949, blue: 0.937).opacity(0.45))
            .lineLimit(1)
            .fixedSize()
    }
}

/// The leading status dot. The live (coral) variant pulses; the resting variant
/// is a calm grey. Pulse is suppressed under reduced motion.
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
            .scaleEffect(live && on ? 1.12 : 0.9)
            .opacity(live ? (on ? 1.0 : 0.55) : 1.0)
            .onAppear {
                guard live, !reduce else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

/// A six-bar level meter that animates like a live equalizer while listening.
/// Matches the mockup's `.bars` (heights/phases) and `@keyframes eq` (scaleY
/// .38 → 1). Reduced motion freezes the bars at their resting heights.
private struct LevelBars: View {
    let color: Color
    let reduce: Bool
    @State private var animating = false

    // Per-bar resting height + animation phase delay (from the mockup).
    private let bars: [(height: CGFloat, delay: Double)] = [
        (7, 0.0), (14, 0.12), (17, 0.22), (10, 0.16), (14, 0.05), (8, 0.20),
    ]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: bars[i].height)
                    .scaleEffect(y: animating ? 1.0 : 0.38, anchor: .bottom)
                    .animation(
                        reduce ? nil
                        : .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(bars[i].delay),
                        value: animating)
            }
        }
        .frame(height: 17, alignment: .bottom)
        .onAppear { if !reduce { animating = true } }
    }
}
