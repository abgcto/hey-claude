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
        case voice = "Voice", launch = "Launch", appearance = "Appearance", general = "General"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .voice:      return "waveform"
            case .launch:     return "terminal"
            case .appearance: return "paintpalette"
            case .general:    return "gearshape"
            }
        }
    }
    @State private var tab: Tab = .voice

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: 0) {
                rail
                Rectangle().fill(PreferencesTheme.hairStrong).frame(width: 1)
                content
                    .padding(.horizontal, 40)
                    .padding(.top, 38)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 600, height: 520)
    }

    private var rail: some View {
        VStack(spacing: 3) {
            ForEach(Tab.allCases) { t in
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
                // Hover only the unselected tabs — the active one already wears the
                // selected fill, and stacking the hover state on top would read as a third state.
                .dashboardHover(cornerRadius: 9, enabled: tab != t)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .voice:      VoiceSection(controller: controller)
        case .launch:     LaunchSection(controller: controller)
        case .appearance: AppearanceSection(controller: controller)
        case .general:    GeneralSection(controller: controller)
        }
    }
}
