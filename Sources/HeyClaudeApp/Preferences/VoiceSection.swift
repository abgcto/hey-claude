import SwiftUI
import HeyClaudeKit

/// Voice tab: wake sensitivity + re-train. Sensitivity maps inversely to the
/// engine's keyword threshold (more sensitive = lower threshold = more eager
/// wake). The change restarts the audio pipeline — costly — so it's applied only
/// on slider release (`onEditingChanged`), never per drag tick.
struct VoiceSection: View {
    let controller: AppController

    // Sensitivity ↔ threshold mapping. position 0 = Less (threshold high/strict),
    // 1 = More (threshold low/eager).
    private static let thresholdLess: Float = 0.30
    private static let thresholdMore: Float = 0.08

    @State private var position: Double
    @State private var ptEnabled: Bool
    @State private var ptKey: PushToTalkKey
    @State private var hasInputMonitoring: Bool = PushToTalkController.hasPermission

    init(controller: AppController) {
        self.controller = controller
        _position = State(initialValue: Self.position(for: controller.settings.wakeKeywordsThreshold))
        _ptEnabled = State(initialValue: controller.settings.pushToTalkEnabled)
        _ptKey = State(initialValue: controller.settings.pushToTalkKey)
    }

    private static func position(for threshold: Float) -> Double {
        let p = (thresholdLess - threshold) / (thresholdLess - thresholdMore)
        return Double(min(max(p, 0), 1))
    }
    private static func threshold(for position: Double) -> Float {
        thresholdLess - Float(position) * (thresholdLess - thresholdMore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.groupSpacing) {
            SettingsGroup("WAKE SENSITIVITY") {
                HStack(spacing: 12) {
                    Text("Less").font(PreferencesTheme.caption).foregroundStyle(PreferencesTheme.inkSoft)
                    Slider(value: $position, in: 0...1) { editing in
                        // Apply only when the drag ends — each change reboots the pipeline.
                        if !editing { controller.setWakeThreshold(Self.threshold(for: position)) }
                    }
                    .tint(PreferencesTheme.ink)
                    Text("More").font(PreferencesTheme.caption).foregroundStyle(PreferencesTheme.inkSoft)
                }
                Text("Catches your voice more easily, but may misfire.")
                    .font(PreferencesTheme.caption)
                    .foregroundStyle(PreferencesTheme.inkSoft)
            }
            SettingsGroup("WAKE WORD") {
                Text("Re-record it in your voice if waking is unreliable.")
                    .font(PreferencesTheme.caption)
                    .foregroundStyle(PreferencesTheme.inkSoft)
                DashboardButton("Re-train wake word") { controller.requestRetrain() }
            }
            SettingsGroup("PUSH TO TALK") {
                // Toggle + its explanation, grouped tight (6pt) so they read as one
                // unit — mirrors AppearanceSection's `idleToggle`. Uses the pane's
                // monochrome DashboardToggle, not the system blue switch.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("Hold a key to talk")
                            .font(PreferencesTheme.body)
                            .foregroundStyle(PreferencesTheme.ink)
                        DashboardToggle(isOn: $ptEnabled)
                    }
                    .accessibilityElement(children: .combine)
                    .onChange(of: ptEnabled) { _, on in
                        if on && !PushToTalkController.hasPermission {
                            PushToTalkController.requestPermission()
                        }
                        controller.setPushToTalkEnabled(on)
                        hasInputMonitoring = PushToTalkController.hasPermission
                    }
                    Text("Hold your key, speak, release. Pauses never cut you off.")
                        .font(PreferencesTheme.caption)
                        .foregroundStyle(PreferencesTheme.inkSoft)
                }

                // The key control + permission. Kept ALWAYS visible (just dimmed +
                // disabled when the toggle is off) so flipping the toggle never makes
                // the row vanish — that read as "the feature broke". Sits `rowSpacing`
                // (12) below the toggle block — a clear tier break. The permission
                // hint only matters when push-to-talk is actually on.
                VStack(alignment: .leading, spacing: PreferencesTheme.listSpacing) {
                    // Built-in label ("Key") + menu — the exact form that rendered
                    // originally. Do NOT add `.fixedSize()`: a `.menu` Picker reports
                    // an ideal width of ~0 before its menu is built, so `.fixedSize()`
                    // collapses it to a zero-size (invisible) control. Likewise avoid
                    // `.labelsHidden()` with an empty label — same collapse.
                    Picker("Key", selection: $ptKey) {
                        ForEach(PushToTalkKey.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: ptKey) { _, k in controller.setPushToTalkKey(k) }

                    if ptEnabled && !hasInputMonitoring {
                        HStack(spacing: 8) {
                            Text("Needs Input Monitoring access.")
                                .font(PreferencesTheme.caption)
                                .foregroundStyle(PreferencesTheme.inkSoft)
                            DashboardButton("Grant access") {
                                PushToTalkController.requestPermission()
                                SystemSettingsLink.inputMonitoring.open()
                            }
                        }
                    }
                }
                .disabled(!ptEnabled)
                .opacity(ptEnabled ? 1 : 0.4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
