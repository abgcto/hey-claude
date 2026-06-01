import SwiftUI
import HeyClaudeKit

/// The Settings dashboard shell: a pure-black canvas with a left nav rail
/// (Voice · Launch · Appearance · General) and a detail pane — the System
/// Settings shape, kept on-theme (custom rail, not a system `NavigationSplitView`,
/// whose chrome would clash with the black palette). Section views read/write live
/// via the `@Observable` controller, so panes always mirror the running app.
struct PreferencesView: View {
    let controller: AppController

    enum Tab: String, CaseIterable, Identifiable {
        case voice = "Voice", launch = "Launch", appearance = "Appearance"
        case general = "General", system = "System"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .voice:      return "waveform"
            case .launch:     return "terminal"
            case .appearance: return "paintpalette"
            case .general:    return "gearshape"
            case .system:     return "lock.shield"
            }
        }
        /// Feature tabs sit above the rail divider; app/OS tabs below it.
        static let featureTabs: [Tab] = [.voice, .launch, .appearance]
        static let appTabs: [Tab] = [.general, .system]
    }
    @State private var tab: Tab = .voice

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: 0) {
                rail
                Rectangle().fill(PreferencesTheme.hairStrong).frame(width: 1)
                ScrollView {
                    content
                        .padding(.horizontal, 40)
                        .padding(.top, 46)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(width: 820, height: 580)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Settings")
                .font(PreferencesTheme.gs(14, .semibold))
                .foregroundStyle(PreferencesTheme.ink)
                .padding(.leading, 12)
                .padding(.bottom, 18)
            ForEach(Tab.featureTabs) { navButton($0) }
            railDivider
            ForEach(Tab.appTabs) { navButton($0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .frame(width: 188)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Separates the feature tabs (Voice/Launch/Appearance) from the app/OS tabs
    /// (General/System) — the "what it does" vs "the app & its permissions" split.
    private var railDivider: some View {
        Rectangle().fill(PreferencesTheme.hairline)
            .frame(height: 1)
            .padding(.horizontal, 11).padding(.vertical, 7)
    }

    private func navButton(_ t: Tab) -> some View {
        Button { tab = t } label: {
            HStack(spacing: 10) {
                Image(systemName: t.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(tab == t ? PreferencesTheme.ink : PreferencesTheme.inkFaint)
                Text(t.rawValue)
                    .font(tab == t ? PreferencesTheme.bodyMedium : PreferencesTheme.body)
                    .foregroundStyle(tab == t ? PreferencesTheme.ink : PreferencesTheme.inkSoft)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(tab == t ? PreferencesTheme.ink.opacity(0.10) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Hover only the unselected tabs — the active one already wears the selected
        // fill. Flat hover (no slip-up): full-width list rows wobble if they lift.
        .dashboardHover(cornerRadius: 9, enabled: tab != t, lift: false)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .voice:      VoiceSection(controller: controller)
        case .launch:     LaunchSection(controller: controller)
        case .appearance: AppearanceSection(controller: controller)
        case .general:    GeneralSection(controller: controller)
        case .system:     SystemSection(controller: controller)
        }
    }
}
