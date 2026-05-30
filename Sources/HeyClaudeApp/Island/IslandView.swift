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
    /// camera. Total island width = 2 × sideArea + notchWidth (symmetric).
    var notchWidth: CGFloat = 189
    /// Bloom open (widen from a sliver) on first appear — set by the panel only on
    /// its FIRST update each launch, so the island makes an entrance every time the
    /// app opens, but never re-blooms on ordinary state changes.
    var bloom: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the bloom-in entrance.
    @State private var entered = false

    // Skin (the locked palette).
    private let coral = Color(red: 1.0, green: 0.541, blue: 0.420)    // #ff8a6b
    private let violet = Color(red: 0.482, green: 0.361, blue: 1.0)   // #7b5cff
    private let inkText = Color(red: 0.953, green: 0.949, blue: 0.937) // #f3f2ef

    // MARK: - Per-state geometry

    /// Reveal = hearing OR launching: the two-tier band with a spoken line below
    /// the notch. Both share one size so hearing → launching never resizes.
    private var isReveal: Bool {
        switch model.visual {
        case .transcript, .launching: return true
        default: return false
        }
    }

    private var isMuted: Bool { model.visual == .muted }

    /// Onboarding placeholder — the black band at resting width with no mascot or
    /// content (the empty shell the mascot later flies into).
    private var isEmpty: Bool { model.visual == .empty }

    /// The notch-row side zones (mascot left of the camera, compact content right).
    /// CONSTANT across every state so the band width never ping-pongs — the only
    /// width move is the single bloom into the reveal band and the collapse back.
    private let sideArea: CGFloat = 26

    /// Gap between an icon's INNER edge and the camera. Small, so the icons hug
    /// the notch — leaving the larger remainder as outer padding (outer > inner).
    private let innerGap: CGFloat = 3

    /// `NotchShape`'s top corner radius — the solid black body is inset by this on
    /// each outer side (the top flare connects body to screen edge), so the band
    /// is widened by it on each side and the body fully covers the side sections.
    private let bodyInset: CGFloat = 6

    /// The band width is CONSTANT across every state — the width never animates.
    /// Only the HEIGHT changes (reveal states grow a row downward). The spoken
    /// line lives below the notch within this same width (truncating if long).
    private var islandWidth: CGFloat { 2 * sideArea + notchWidth + 2 * bodyInset }

    var body: some View {
        islandContent
            // Constant width; the HEIGHT is intrinsic — it grows down to fit the
            // reveal line (1 or 2 lines) and shrinks back, animated on state change.
            .frame(width: islandWidth)
            // Pure black so it fuses with the camera notch into one dynamic-island shape.
            .background(
                NotchShape(topCornerRadius: 6, bottomCornerRadius: 10)
                    .fill(Color.black)
            )
            // Clip to the same shape so the reveal line glides into view under the
            // rounded bottom edge as the band grows open.
            .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 10))
            .compositingGroup()
            // Paused dims hard (~60%); muted is only slightly dimmed.
            .opacity(model.dimmed ? 0.6 : (isMuted ? 0.78 : 1))
            .opacity(model.hidden ? 0 : 1)
            // Empty-shell entrance: the placeholder blooms open — widening from a
            // sliver (with a slight overshoot) the first time it appears in the
            // notch during onboarding. Normal island states skip this (full size).
            .scaleEffect(x: (entered || !bloom) ? 1 : 0.42,
                         y: (entered || !bloom) ? 1 : 0.82, anchor: .top)
            .opacity((entered || !bloom) ? 1 : 0)
            .onAppear {
                guard bloom, !reduceMotion else { entered = true; return }
                withAnimation(.timingCurve(0.34, 1.2, 0.3, 1.0, duration: 0.55).delay(0.06)) {
                    entered = true
                }
            }
            // One easing drives the grow/shrink AND the line cross-fade on any state change.
            .animation(shapeAnimation, value: model.visual)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.dimmed)
    }

    /// Always the notch strip (mascot · camera · compact content). Reveal states
    /// (hearing + launching) add ONE line below the notch — no kicker, no subtitle.
    /// It grows the band to fit, then collapses back.
    private var islandContent: some View {
        Group {
            if isEmpty {
                // The empty resting-width shell — the body frames it to the band
                // width and fills it black, so this is just the bare pill.
                Color.clear.frame(height: topInset)
            } else {
                VStack(spacing: 0) {
                    notchRow { rightContent }
                    if isReveal {
                        revealLine
                    }
                }
            }
        }
    }

    /// The single below-notch line: the spoken sentence during hearing, morphing
    /// (cross-fade) into "→ Launching Claude" on launch. Its identity changes with
    /// the phase so the swap cross-fades; insertion/removal fades the open/close.
    @ViewBuilder private var revealLine: some View {
        revealLineContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .id(isLaunching)
            .transition(.opacity)
    }

    @ViewBuilder private var revealLineContent: some View {
        if isLaunching {
            // Launch: the action replaces the sentence — one coral line, arrow
            // nudging. The full command already went to Claude Code (not echoed).
            HStack(spacing: 5) {
                NudgingArrow(color: coral, reduce: reduceMotion)
                Text("Launching Claude")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(coral)
                    .lineLimit(1)
            }
        } else {
            // Hearing: the spoken sentence — wraps to 2 lines max, then ellipsis.
            Text(revealText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(inkText)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isLaunching: Bool {
        if case .launching = model.visual { return true }
        return false
    }

    private var revealText: String {
        switch model.visual {
        case .transcript(let t), .launching(let t): return t
        default: return ""
        }
    }

    /// One notch-height row: mascot (left of the camera) · clear camera gap ·
    /// per-state icon content (right of the camera). Height is exactly the lip.
    private func notchRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            // Left of the camera: the mascot sits CLOSE to the notch (small inner
            // gap), leaving more padding on the outer side — not dead-centered.
            MascotView()
                .frame(width: 16, height: 10)
                .offset(y: mascotBob)
                .animation(mascotBobAnimation, value: mascotBobActive)
                .padding(.trailing, innerGap)
                .frame(width: sideArea, alignment: .trailing)
            // The camera gap — kept clear (the physical notch sits here).
            Color.clear.frame(width: notchWidth)
            // Right of the camera: mirrors the left — content hugs the notch on
            // its inner (leading) side, more padding on the outer side.
            ZStack { content() }
                .padding(.leading, innerGap)
                .frame(width: sideArea, alignment: .leading)
        }
        .frame(width: 2 * sideArea + notchWidth)   // compact; centered when the band is taller
        .frame(height: topInset)
    }

    private var shapeAnimation: Animation? {
        // The mockup's band easing: cubic-bezier(.4, 1.1, .3, 1) over 0.5s — a
        // smooth ease-out with a slight overshoot so the island expands and grows
        // open (no abrupt cut), then settles.
        reduceMotion ? nil : .timingCurve(0.4, 1.1, 0.3, 1.0, duration: 0.5)
    }

    // MARK: - Right content (one branch per visual state)

    @ViewBuilder private var rightContent: some View {
        switch model.visual {
        case .hidden, .idle, .transcript, .launching, .empty:
            // hidden/armed show nothing on the right; transcript & launching put
            // their content BELOW the notch (see `revealLayout`), not here. The
            // mascot's presence alone signals "armed, listening for the wake word."
            EmptyView()

        case .listening:
            // Equalizer only — it already reads as "live, listening"; a separate
            // pulsing dot would be redundant in this tiny space.
            LevelBars(color: coral, reduce: reduceMotion)

        case .muted:
            // White mic glyph crossed by a coral diagonal slash (mockup's
            // slashed-mic SVG): a plain mic + an explicit coral stroke.
            ZStack {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(inkText.opacity(0.7))
                MutedSlash(color: coral)
                    .frame(width: 15, height: 15)
            }
            .frame(width: 15, height: 15)

        case .paused:
            // Compact pause glyph only — the label wouldn't fit the snug section;
            // the dimmed violet treatment carries the "on hold" meaning.
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(violet)
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

/// The launching arrow that gently nudges right (mockup's `arrow--nudge`) to
/// give the hand-off a sense of forward motion. Frozen under reduced motion.
private struct NudgingArrow: View {
    let color: Color
    let reduce: Bool
    @State private var nudge = false

    var body: some View {
        Text("→")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .offset(x: nudge ? 3 : 0)
            .animation(reduce ? nil
                       : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                       value: nudge)
            .onAppear { if !reduce { nudge = true } }
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
        // Center-aligned bars so the equalizer's vertical midline matches the
        // mascot's (both are centered in the notch row). Growing from the center
        // also keeps it visually balanced as bars animate.
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    // 2px bars × 5 + 1.5px gaps × 4 = 16px total — matches the
                    // mascot's 16px width so the two mirror across the camera.
                    .frame(width: 2, height: bars[i].height)
                    .scaleEffect(y: animating ? 1.0 : 0.4, anchor: .center)
                    .animation(
                        reduce ? nil
                        : .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(bars[i].delay),
                        value: animating)
            }
        }
        .frame(height: 14)
        .onAppear { if !reduce { animating = true } }
    }
}
