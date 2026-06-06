import SwiftUI
import HeyClaudeKit

/// One recent-launch row (honest outcome log), mirrored from `RecentActions`.
struct RecentItem {
    let label: String
    let failed: Bool
}

/// A persistent launch failure surfaced in the panel: the message plus EITHER an
/// actionable remedy (button) OR a text hint — never both.
struct FailureItem {
    let message: String
    let remedyLabel: String?
    let remedy: (() -> Void)?
    let hint: String?
}

/// Everything the notch is now the home for (the menu bar is gone): the actions +
/// the data the dropdown renders. Built by `AppController`, threaded through
/// `NotchIslandPanel`. `nil` on the island → non-interactive (onboarding).
struct IslandControls {
    var isOff: Bool                 // mic denied — show recovery, not the usual controls
    var isMuted: Bool
    var targets: [LaunchTarget]
    var current: LaunchTarget
    var recent: [RecentItem]
    var failure: FailureItem?
    var toggleMute: () -> Void
    var setTarget: (LaunchTarget) -> Void
    var fixMic: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void
}

/// Reports the dropdown's rendered height up to `NotchIslandPanel` so the AppKit
/// hit-region grows to match EXACTLY — the panel only catches clicks where it
/// actually draws, everything else stays click-through.
struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The hover-revealed control panel that drops below the notch — now the app's
/// complete control surface (there is no menu bar). Rendered inside the island's
/// black `NotchShape` (clipped), so it reads as the band growing downward. No
/// native `Menu` (which would need the panel to become key); lists disclose inline
/// so plain taps suffice.
///
/// Off (mic denied): attention + Fix mic access · Settings · Quit.
/// Normal: [failure block] · Mute · Open in… (inline targets + folder) · Settings ·
/// Quit. (Recent is recorded but hidden until the resume feature makes it
/// clickable — see `showRecent`.)
struct IslandControlPanel: View {
    let controls: IslandControls
    var ink: Color
    var dim: Color
    var accent: Color
    /// Collapse the whole island panel — called when an item that shifts focus
    /// elsewhere is chosen, so the dropdown doesn't linger.
    var collapse: () -> Void = {}
    @State private var showTargets = false

    /// Recent rows are display-only today — they cost panel height without paying
    /// for it, so they stay hidden until the "resume a recent session" feature
    /// lands and makes them clickable. `RecentActions` keeps recording underneath,
    /// so flipping this back on restores the history with zero data loss.
    private static let showRecent = false

    var body: some View {
        VStack(spacing: 0) {
            hairline.padding(.bottom, 3)
            if controls.isOff { offContent } else { normalContent }
        }
        .padding(.vertical, 5)
        .background(GeometryReader { p in
            Color.clear.preference(key: PanelHeightKey.self, value: p.size.height)
        })
    }

    // MARK: - Off (mic denied)

    @ViewBuilder private var offContent: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent).frame(width: 15)
            Text("Microphone access needed").font(.system(size: 12)).foregroundStyle(ink)
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        row(icon: "arrow.up.forward", title: "Fix mic access…") { collapse(); controls.fixMic() }
        divider()
        settingsAndQuit
    }

    // MARK: - Normal

    @ViewBuilder private var normalContent: some View {
        if let f = controls.failure {
            failureBlock(f)
            divider()
        }
        // Hint that the mascot itself is a one-click toggle — so people learn they
        // don't have to open this panel just to mute/resume.
        row(icon: controls.isMuted ? "mic.slash.fill" : "pause.fill",
            title: controls.isMuted ? "Resume" : "Mute",
            trailing: "click clawd",
            action: controls.toggleMute)

        row(icon: "arrow.up.forward.app", title: "Open in…",
            trailing: controls.current.displayLabel,
            chevron: showTargets ? "chevron.up" : "chevron.down") {
            // Instant (no animation): the panel's height jumps in one layout pass so
            // the AppKit hit-region tracks the new rows exactly — an animated grow
            // makes the region lag the visible list and clicks fall through.
            showTargets.toggle()
        }
        if showTargets {
            ForEach(controls.targets, id: \.self) { t in targetRow(t) }
        }

        if Self.showRecent, !controls.recent.isEmpty {
            divider()
            sectionLabel("Recent")
            ForEach(Array(controls.recent.enumerated()), id: \.offset) { _, r in
                recentRow(r)
            }
        }

        divider()
        settingsAndQuit
    }

    private var settingsAndQuit: some View {
        Group {
            row(icon: "gearshape", title: "Settings…") { collapse(); controls.openSettings() }
            row(icon: "power", title: "Quit") { collapse(); controls.quit() }
        }
    }

    // MARK: - Pieces

    @ViewBuilder private func failureBlock(_ f: FailureItem) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("✕").font(.system(size: 11, weight: .bold)).foregroundStyle(accent)
            Text(f.message).font(.system(size: 11.5, weight: .medium)).foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 2)
        if let label = f.remedyLabel, let remedy = f.remedy {
            row(icon: "arrow.up.forward", title: label) { collapse(); remedy() }
        } else if let hint = f.hint {
            Text(hint).font(.system(size: 10.5)).foregroundStyle(dim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.top, 1)
        }
    }

    private func recentRow(_ r: RecentItem) -> some View {
        HStack(spacing: 8) {
            Text(r.failed ? "✕" : "✓").font(.system(size: 10.5))
                .foregroundStyle(r.failed ? dim : ink).frame(width: 15)
            Text(r.label).font(.system(size: 11)).foregroundStyle(r.failed ? dim : ink.opacity(0.85))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 18).padding(.vertical, 3)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(dim)
            .textCase(.uppercase).kerning(0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 2).padding(.bottom, 1)
    }

    private var hairline: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }
    private func divider() -> some View {
        hairline.padding(.vertical, 4).padding(.horizontal, 10)
    }

    private func row(icon: String, title: String, trailing: String? = nil,
                     chevron: String? = nil, action: @escaping () -> Void) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(dim).frame(width: 15)
            Text(title).font(.system(size: 12)).foregroundStyle(ink)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing).font(.system(size: 10.5)).foregroundStyle(dim).lineLimit(1)
            }
            if let chevron {
                Image(systemName: chevron).font(.system(size: 9, weight: .semibold)).foregroundStyle(dim)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .contentShape(Rectangle())
        .modifier(HoverFill())
        .onTapGesture(perform: action)
    }

    private func targetRow(_ t: LaunchTarget) -> some View {
        HStack(spacing: 9) {
            Image(systemName: t == controls.current ? "checkmark" : "")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(ink).frame(width: 15)
            Text(t.displayLabel)
                .font(.system(size: 11.5)).foregroundStyle(t == controls.current ? ink : dim)
            Spacer(minLength: 6)
        }
        .padding(.leading, 31).padding(.trailing, 18).padding(.vertical, 5)
        .contentShape(Rectangle())
        .modifier(HoverFill())
        .onTapGesture {
            controls.setTarget(t)
            showTargets = false
            collapse()
        }
    }
}

/// Hover highlight for a tappable row. Rows use `.onTapGesture` rather than `Button`
/// because this non-activating, non-key panel does NOT fire SwiftUI `Button` actions
/// — but a raw tap gesture works (the same reason the mascot's tap-to-mute works).
private struct HoverFill: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            // Rounded "pill" highlight, inset from the panel edges so the corners
            // read cleanly (macOS-menu style) instead of a full-width square bar.
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.07) : Color.clear)
                    .padding(.horizontal, 12)
            )
            .onHover { hovering = $0 }
    }
}
