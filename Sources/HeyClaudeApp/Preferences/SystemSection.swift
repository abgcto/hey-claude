import SwiftUI
import AVFoundation
import HeyClaudeKit

/// System tab: the OS-permission hub. One place to see what macOS has granted Hey
/// Claude and to jump to System Settings to fix it — Microphone (the core
/// requirement, previously reachable only from the notch's denied state) and Input
/// Monitoring (for push-to-talk). Status is read live on appear.
struct SystemSection: View {
    let controller: AppController

    // Probed once per appear in refreshPermissions() (not in the @State defaults, to
    // avoid a redundant double-probe on first render). `loaded` distinguishes the
    // initial populate from a later grant so we don't restart the tap on every appear.
    @State private var micGranted = false
    @State private var inputMonitoring = false
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.sectionGap) {
            SettingsSection("Permissions",
                            "What macOS must allow Hey Claude to do. Granted in System Settings ▸ Privacy & Security.") {
                SettingsRow("Microphone",
                            "Required to hear the wake word and your spoken prompt. Audio never leaves your Mac.") {
                    HStack(spacing: 10) {
                        PermissionBadge(granted: micGranted)
                        DashboardButton("Open Settings", style: .secondary) {
                            SystemSettingsLink.microphone.open()
                        }
                    }
                }

                SettingsRow("Input Monitoring",
                            "Lets push-to-talk detect when you hold your trigger key.",
                            showsDivider: false) {
                    HStack(spacing: 10) {
                        PermissionBadge(granted: inputMonitoring)
                        if inputMonitoring {
                            DashboardButton("Open Settings", style: .secondary) {
                                SystemSettingsLink.inputMonitoring.open()
                            }
                        } else {
                            DashboardButton("Grant Access", style: .primary) {
                                PushToTalkController.requestPermission()
                                SystemSettingsLink.inputMonitoring.open()
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Re-read each time the pane appears (tab switch) and whenever the app
        // regains focus — the user may have granted permission in System Settings
        // and Cmd-Tabbed back without leaving the System tab, so .onAppear alone
        // won't fire. Both paths call the same refresh so no duplication.
        .onAppear { refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let nowIM = PushToTalkController.hasPermission
        // Granting Input Monitoring doesn't install the event tap by itself. When it
        // flips to granted while this pane is already loaded (the user granted it in
        // System Settings and returned), start the tap so PTT works immediately
        // instead of only after a relaunch. Skip on the initial load — don't restart
        // a tap that launch already set up.
        if loaded && nowIM && !inputMonitoring && controller.settings.pushToTalkEnabled {
            controller.pushToTalk?.start()
        }
        inputMonitoring = nowIM
        loaded = true
    }
}
