import SwiftUI
import AVFoundation
import HeyClaudeKit

/// System tab: the OS-permission hub. One place to see what macOS has granted Hey
/// Claude and to jump to System Settings to fix it — Microphone (the core
/// requirement, previously reachable only from the notch's denied state) and Input
/// Monitoring (for push-to-talk). Status is read live on appear.
struct SystemSection: View {
    let controller: AppController

    @State private var micGranted: Bool = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var inputMonitoring: Bool = PushToTalkController.hasPermission

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.sectionGap) {
            VStack(spacing: 0) {
                SettingsHeader("Permissions",
                               "What macOS must allow Hey Claude to do. Granted in System Settings ▸ Privacy & Security.")

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
        // Granting Input Monitoring doesn't install the event tap by itself. On the
        // not-granted → granted transition, start the tap when push-to-talk is
        // enabled, so PTT works immediately instead of only after a relaunch.
        if nowIM && !inputMonitoring && controller.settings.pushToTalkEnabled {
            controller.pushToTalk?.start()
        }
        inputMonitoring = nowIM
    }
}
