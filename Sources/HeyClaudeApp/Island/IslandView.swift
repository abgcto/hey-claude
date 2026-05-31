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
    /// The user-selected mascot + body color (resolved upstream from `Settings`).
    /// Default to Classic + clay so the notch matches a fresh install until the
    /// user picks otherwise.
    var mascot: Mascot = MascotCatalog.byID("classic")
    var mascotColor: Color = Color(red: 0.847, green: 0.463, blue: 0.341)  // #D87757 clay
    /// Hover-panel actions/data. `nil` → non-interactive (onboarding). When present,
    /// hovering the band drops the control panel and clicking the mascot mutes.
    var controls: IslandControls? = nil
    /// Reports the dropped panel's height so the panel's hit-region tracks it.
    var onPanelHeight: ((CGFloat) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the bloom-in entrance.
    @State private var entered = false

    /// Bumped each time the island leaves the muted state, firing the mascot's
    /// one-shot "wake up" squash-and-stretch (see `notchRow`).
    @State private var wakeTrigger = 0

    /// Bumped each time the island enters the muted state, firing the mascot's
    /// one-shot "settle down" droop — the calm inverse of the wake pop.
    @State private var sleepTrigger = 0

    /// Hover-driven: the control panel is dropped below the notch.
    @State private var isExpanded = false
    /// Debounces collapse so brushing past the band (or the band→panel gap) doesn't
    /// snap it shut.
    @State private var collapseWork: DispatchWorkItem?

    // Skin (the locked palette).
    private let coral = Color(red: 1.0, green: 0.541, blue: 0.420)    // #ff8a6b
    private let violet = Color(red: 0.482, green: 0.361, blue: 1.0)   // #7b5cff
    private let inkText = Color(red: 0.953, green: 0.949, blue: 0.937) // #f3f2ef

    /// The dimmed gray worn by the muted `mic.slash.fill` glyph — thin strokes, so
    /// it carries the light tint without reading as washed out.
    private var mutedTint: Color { inkText.opacity(0.7) }

    /// The muted mascot body gray. Darker than `mutedTint` on purpose: the mascot is
    /// a solid fill, so the same tint would read much lighter than the thin mic
    /// glyph — this lower value balances their visual weight.
    private var mutedMascot: Color { inkText.opacity(0.4) }

    // MARK: - Per-state geometry

    /// Reveal = hearing OR launching: the two-tier band with a spoken line below
    /// the notch. Both share one size so hearing → launching never resizes.
    private var isReveal: Bool {
        switch model.visual {
        case .transcript, .launching, .failed: return true
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
    private let sideArea = IslandGeometry.sideArea

    /// Gap between an icon's INNER edge and the camera. Small, so the icons hug
    /// the notch — leaving the larger remainder as outer padding (outer > inner).
    private let innerGap: CGFloat = 3

    /// `NotchShape`'s top corner radius — the solid black body is inset by this on
    /// each outer side (the top flare connects body to screen edge), so the band
    /// is widened by it on each side and the body fully covers the side sections.
    private let bodyInset = IslandGeometry.bodyInset

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
            // Paused dims the whole band (~60%). Muted keeps the band fully black —
            // its "off" reading comes from the gray mascot + mic glyph tint, not from
            // washing the background out against the desktop.
            .opacity(model.dimmed ? 0.6 : 1)
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
            // Hover-to-expand: pointer over the band/panel drops the controls; the
            // dropped panel reports its height so the hit-region tracks it exactly.
            .onHover { handleHover($0) }
            .onPreferenceChange(PanelHeightKey.self) { onPanelHeight?($0) }
            // A transient state (wake fired, launching, failure) must close the panel.
            .onChange(of: model.visual) { _, _ in if isExpanded && !canExpand { collapseNow() } }
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
                    } else if showControlPanel, let controls {
                        IslandControlPanel(controls: controls,
                                           ink: inkText, dim: inkText.opacity(0.6),
                                           collapse: { collapseNow() })
                            .transition(.opacity)
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
            .id(revealPhase)
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
        } else if isFailed {
            // Failure: a coral ✕ + the short reason. Distinct from launching's →,
            // on the locked palette (no new red). Detail lives in the menu.
            HStack(spacing: 5) {
                Text("✕")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(coral)
                Text(revealText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(coral)
                    .lineLimit(1)
                    .truncationMode(.tail)
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

    private var isFailed: Bool {
        if case .failed = model.visual { return true }
        return false
    }

    /// Identity for the reveal line so a phase change cross-fades: hearing (0) →
    /// launching (1) or failed (2).
    private var revealPhase: Int { isLaunching ? 1 : (isFailed ? 2 : 0) }

    private var revealText: String {
        switch model.visual {
        case .transcript(let t), .launching(let t), .failed(let t): return t
        default: return ""
        }
    }

    /// One notch-height row: mascot (left of the camera) · clear camera gap ·
    /// per-state icon content (right of the camera). Height is exactly the lip.
    private func notchRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            // Left of the camera: the mascot sits CLOSE to the notch (small inner
            // gap), leaving more padding on the outer side — not dead-centered.
            MascotView(mascot: mascot, bodyColor: isMuted ? mutedMascot : mascotColor)
                .frame(width: mascotSize.width, height: mascotSize.height)
                .offset(y: mascotBob + mascotCenterShift)
                .animation(mascotBobAnimation, value: mascotBobActive)
                // Resume from mute → the mascot pops awake: a quick stretch-up,
                // squash, and bouncy settle (anchored at its feet) with a small hop,
                // so unmuting reads as the mascot coming back to life. One-shot,
                // driven by `wakeTrigger`; skipped under reduced motion.
                .keyframeAnimator(initialValue: MascotWake(), trigger: wakeTrigger) { view, w in
                    view.scaleEffect(w.scale, anchor: .bottom).offset(y: w.lift)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.18, duration: 0.16, spring: .snappy)
                        SpringKeyframe(0.92, duration: 0.12, spring: .snappy)
                        SpringKeyframe(1.06, duration: 0.12)
                        SpringKeyframe(1.0, duration: 0.20, spring: .bouncy)
                    }
                    KeyframeTrack(\.lift) {
                        CubicKeyframe(-3, duration: 0.18)
                        CubicKeyframe(0, duration: 0.42)
                    }
                }
                // Mute → the mascot settles: a soft squash (widen + shorten, anchored
                // at its feet) with a small sink, then an unhurried ease back. Slower
                // and bounce-free so it reads as powering down, not popping. One-shot.
                .keyframeAnimator(initialValue: MascotSleep(), trigger: sleepTrigger) { view, s in
                    view.scaleEffect(x: s.scaleX, y: s.scaleY, anchor: .bottom).offset(y: s.sink)
                } keyframes: { _ in
                    KeyframeTrack(\.scaleY) {
                        CubicKeyframe(0.84, duration: 0.22)
                        CubicKeyframe(1.0, duration: 0.50)
                    }
                    KeyframeTrack(\.scaleX) {
                        CubicKeyframe(1.08, duration: 0.22)
                        CubicKeyframe(1.0, duration: 0.50)
                    }
                    KeyframeTrack(\.sink) {
                        CubicKeyframe(1.5, duration: 0.22)
                        CubicKeyframe(0, duration: 0.50)
                    }
                }
                .onChange(of: isMuted) { _, nowMuted in
                    // Fire on each toggle, only when motion is allowed: mute → settle,
                    // resume → wake. The two animators rest at identity when idle, so
                    // stacking them never conflicts.
                    guard !reduceMotion else { return }
                    if nowMuted { sleepTrigger += 1 } else { wakeTrigger += 1 }
                }
                .padding(.trailing, innerGap)
                .frame(width: sideArea, alignment: .trailing)
                // Click the mascot side → toggle mute (the #1 action, no menu). The
                // whole side zone is the target so it's easy to hit at notch size.
                .contentShape(Rectangle())
                .onTapGesture { controls?.toggleMute() }
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
        case .hidden, .transcript, .launching, .failed, .empty:
            // transcript, launching & failed put their content BELOW the notch
            // (see `revealLine`), not here; hidden shows nothing.
            EmptyView()

        case .idle:
            // Armed — five short, flat bars: the level meter "at rest" (aligns with
            // the 5 listening bars). NOT a mic. Taps to mute.
            RestingBars(color: inkText.opacity(0.5))
                .frame(width: 16)
                .contentShape(Rectangle())
                .onTapGesture { controls?.toggleMute() }

        case .listening:
            // Equalizer — it already reads as "live, listening"; a separate
            // pulsing dot would be redundant in this tiny space.
            LevelBars(color: coral, reduce: reduceMotion)

        case .muted:
            // Native slashed-mic SF Symbol — mic + slash as one Apple glyph,
            // dimmed to read as a calm "off" state. Tap to resume.
            micGlyph("mic.slash.fill", tint: mutedTint)

        case .paused:
            // Compact pause glyph only — the label wouldn't fit the snug section;
            // the dimmed violet treatment carries the "on hold" meaning.
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(violet)
        }
    }

    /// The right-side mic glyph (on / off). 16px to mirror the mascot's footprint;
    /// taps toggle mute so the same affordance flips between states.
    private func micGlyph(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 16)
            .contentShape(Rectangle())
            .onTapGesture { controls?.toggleMute() }
    }

    // MARK: - Hover expansion

    /// Resting-ish states only — never grow the panel mid-reveal or when hidden/off.
    private var canExpand: Bool {
        guard controls != nil else { return false }
        switch model.visual {
        case .idle, .listening, .muted: return true
        default: return false
        }
    }

    /// Show the dropdown only while expanded, interactive, and not showing a reveal
    /// line (the two below-notch contents are mutually exclusive).
    private var showControlPanel: Bool {
        isExpanded && controls != nil && !isEmpty && !isReveal
    }

    private func handleHover(_ hovering: Bool) {
        guard canExpand else { return }
        if hovering {
            collapseWork?.cancel()
            if !isExpanded {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { isExpanded = true }
            }
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { collapseNow() }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func collapseNow() {
        guard isExpanded else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { isExpanded = false }
    }

    // MARK: - Mascot sizing

    /// The mascot slot width (left of the camera). Height scales with the grid's
    /// aspect so every mascot's cells render at the SAME size — a tall grid (e.g.
    /// Birthday's candle) grows the frame upward rather than shrinking the body to
    /// fit a fixed box. Standard 10-row mascots resolve to the original 16×10.
    private static let mascotSlotW: CGFloat = 16
    private var mascotSize: CGSize {
        let h = Self.mascotSlotW * CGFloat(mascot.rows) / CGFloat(max(mascot.cols, 1))
        return CGSize(width: Self.mascotSlotW, height: h)
    }

    /// Vertically center each mascot's INKED rows in the notch row, so its visual
    /// mass lines up with the right-side glyph (mic / bars / pause) regardless of
    /// grid height. The old rule pinned every mascot's feet to the 10-row classic
    /// baseline, which left a taller grid (Birthday's hat + candle, 16×17) floating
    /// ~2pt high above the mic. 10-row mascots are unaffected — their ink already
    /// centers, so the shift stays 0 for Classic/Sleepy/Wink/etc.
    private var mascotCenterShift: CGFloat {
        let unit = mascotSize.height / CGFloat(max(mascot.rows, 1))
        let inkedRows = mascot.pattern.indices.filter { r in
            mascot.pattern[r].contains { $0 != "." }
        }
        guard let top = inkedRows.first, let bottom = inkedRows.last else { return 0 }
        let inkMidRow = (CGFloat(top) + CGFloat(bottom) + 1) / 2
        // The row centers the frame; offset so the inked band's middle sits on center.
        return mascotSize.height / 2 - inkMidRow * unit
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

/// Animatable transform for the mascot's one-shot "wake up" on resume.
private struct MascotWake {
    var scale: CGFloat = 1
    var lift: CGFloat = 0
}

/// Animatable transform for the mascot's one-shot "settle down" on mute.
private struct MascotSleep {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var sink: CGFloat = 0
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
/// Five short, equal-height bars — the level meter at rest (armed). Same count,
/// width and pitch as `LevelBars`, just flat and low, so it springs straight up
/// into the equalizer when listening begins.
private struct RestingBars: View {
    let color: Color
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { _ in
                Capsule().fill(color).frame(width: 2, height: 5)
            }
        }
        .frame(height: 14)
    }
}

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
