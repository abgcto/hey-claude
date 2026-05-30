import SwiftUI

/// General tab: app-level settings — launch at login + an About line.
struct GeneralSection: View {
    let controller: AppController

    // Local mirror so the toggle reflects taps immediately; the source of truth is
    // SMAppService (LoginItem), re-read on appear.
    @State private var launchAtLogin: Bool = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.groupSpacing) {
            SettingsGroup("STARTUP") {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in LoginItem.setEnabled(on); launchAtLogin = LoginItem.isEnabled }
                )) {
                    Text("Launch at login")
                        .font(PreferencesTheme.body)
                        .foregroundStyle(PreferencesTheme.ink)
                }
                .toggleStyle(.switch)
                .tint(PreferencesTheme.ink)
            }

            Spacer(minLength: 0)

            // About line, pinned to the bottom.
            VStack(alignment: .leading, spacing: 4) {
                Text("Hey Claude")
                    .font(PreferencesTheme.bodyMedium)
                    .foregroundStyle(PreferencesTheme.ink)
                Text("Version \(controller.appVersion)")
                    .font(PreferencesTheme.caption)
                    .foregroundStyle(PreferencesTheme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}
