import SwiftUI
import HeyClaudeKit

/// Actions + data the notch control panel needs. Built by `AppController`, threaded
/// through `NotchIslandPanel` into `IslandView`. Optional on the island — `nil`
/// means non-interactive (e.g. during onboarding, before controls exist).
struct IslandControls {
    var targets: [LaunchTarget]
    var current: LaunchTarget
    var isMuted: Bool
    var toggleMute: () -> Void
    var setTarget: (LaunchTarget) -> Void
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

/// The hover-revealed control panel that drops below the notch: Mute · Open in…
/// (inline target list) · Settings… · Quit. Rendered inside the island's black
/// `NotchShape` (clipped), so it reads as the band growing downward — the same
/// space the reveal line uses. No native `Menu` (which would need the panel to
/// become key); the target list discloses inline so plain taps suffice.
struct IslandControlPanel: View {
    let controls: IslandControls
    var ink: Color
    var dim: Color
    /// Collapse the whole island panel — called when an item that shifts focus
    /// elsewhere is chosen (Settings/Quit/target), so the dropdown doesn't linger.
    var collapse: () -> Void = {}
    @State private var showTargets = false

    var body: some View {
        VStack(spacing: 0) {
            hairline.padding(.bottom, 3)

            row(icon: controls.isMuted ? "mic.slash.fill" : "pause.fill",
                title: controls.isMuted ? "Resume" : "Mute",
                action: controls.toggleMute)

            row(icon: "arrow.up.forward.app", title: "Open in…",
                trailing: controls.current.label,
                chevron: showTargets ? "chevron.up" : "chevron.down") {
                withAnimation(.easeInOut(duration: 0.18)) { showTargets.toggle() }
            }
            if showTargets {
                ForEach(controls.targets, id: \.self) { t in targetRow(t) }
            }

            hairline.padding(.vertical, 3).padding(.horizontal, 10)
            row(icon: "gearshape", title: "Settings…") { collapse(); controls.openSettings() }
            row(icon: "power", title: "Quit") { collapse(); controls.quit() }
        }
        .padding(.vertical, 5)
        .background(GeometryReader { p in
            Color.clear.preference(key: PanelHeightKey.self, value: p.size.height)
        })
    }

    private var hairline: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    private func row(icon: String, title: String, trailing: String? = nil,
                     chevron: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
            .padding(.horizontal, 13).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    private func targetRow(_ t: LaunchTarget) -> some View {
        Button {
            controls.setTarget(t)
            withAnimation(.easeInOut(duration: 0.18)) { showTargets = false }
            collapse()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: t == controls.current ? "checkmark" : "")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(ink).frame(width: 15)
                Text(t.label)
                    .font(.system(size: 11.5)).foregroundStyle(t == controls.current ? ink : dim)
                Spacer(minLength: 6)
            }
            .padding(.leading, 26).padding(.trailing, 13).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// Row press feedback — a subtle highlight, no default button chrome.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.09) : Color.clear)
    }
}
