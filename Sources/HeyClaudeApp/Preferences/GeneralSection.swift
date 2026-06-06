import SwiftUI

/// General tab: app-level behavior — launch at login — with an About block.
struct GeneralSection: View {
    let controller: AppController

    // Local mirror so the toggle reflects taps immediately; the source of truth is
    // SMAppService (LoginItem), re-read on appear.
    @State private var launchAtLogin: Bool = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.sectionGap) {
            SettingsSection("General") {
                SettingsRow("Launch at login",
                            "Automatically start Hey Claude when you log in to your Mac.",
                            showsDivider: false) {
                    DashboardToggle(isOn: Binding(
                        get: { launchAtLogin },
                        set: { on in LoginItem.setEnabled(on); launchAtLogin = LoginItem.isEnabled }))
                }
                .accessibilityElement(children: .combine)   // one VO element: label + switch
            }

            // About — a quiet footer set off by a hairline.
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hey Claude")
                        .font(PreferencesTheme.bodyMedium)
                        .foregroundStyle(PreferencesTheme.ink)
                    Text("Version \(controller.appVersion)")
                        .font(PreferencesTheme.caption)
                        .foregroundStyle(PreferencesTheme.inkSoft)
                }
                Spacer(minLength: 16)
                DashboardButton("Check for Updates\u{2026}", style: .secondary) {
                    controller.checkForUpdates()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            .overlay(Rectangle().fill(PreferencesTheme.hairline).frame(height: 1), alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}
