import SwiftUI
import HeyClaudeKit

/// Voice tab: wake sensitivity + re-train + push-to-talk. Sensitivity maps
/// inversely to the engine's keyword threshold (more sensitive = lower threshold =
/// more eager wake). The change restarts the audio pipeline — costly — so it's
/// applied only on slider release (`onEditingChanged`), never per drag tick.
///
/// The Input Monitoring *permission* lives on the System tab now; this section just
/// points there when push-to-talk is on but not yet granted.
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
        VStack(alignment: .leading, spacing: PreferencesTheme.sectionGap) {
            // ---- Wake word -------------------------------------------------
            VStack(spacing: 0) {
                SettingsHeader("Wake word", "How Hey Claude listens for “Hey Claude.”")
                SettingsRow("Wake sensitivity",
                            "Higher catches your voice more easily, but may misfire.") {
                    sensitivitySlider
                }
                SettingsRow("Re-train wake word",
                            "Re-record it in your own voice if waking is unreliable.",
                            showsDivider: false) {
                    DashboardButton("Re-train", style: .secondary) { controller.requestRetrain() }
                }
            }

            // ---- Push to talk ---------------------------------------------
            VStack(spacing: 0) {
                SettingsHeader("Push to talk", "Hold a key, speak, release — pauses never cut you off.")
                SettingsRow("Hold a key to talk",
                            "An alternative to the wake word, always available.") {
                    DashboardToggle(isOn: $ptEnabled)
                }
                // Combine title + the unlabeled switch into one VoiceOver element,
                // matching the General/Appearance toggle rows.
                .accessibilityElement(children: .combine)
                SettingsRow("Trigger key", "The key you hold down to start talking.",
                            showsDivider: false) {
                    keyMenu
                }
                // Pointer to the System tab — shown only when it's actionable:
                // push-to-talk is on but Input Monitoring isn't granted yet. Hidden
                // once granted or when push-to-talk is off, so it never reads as a
                // permanent unresolved warning.
                if ptEnabled && !hasInputMonitoring {
                    Text("Push to talk needs Input Monitoring access — manage it under System.")
                        .font(PreferencesTheme.caption)
                        .foregroundStyle(PreferencesTheme.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(PreferencesTheme.ink.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(PreferencesTheme.hairline, lineWidth: 1)))
                        .padding(.top, 16)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .onChange(of: ptEnabled) { _, on in
            if on && !PushToTalkController.hasPermission {
                PushToTalkController.requestPermission()
            }
            controller.setPushToTalkEnabled(on)
            hasInputMonitoring = PushToTalkController.hasPermission
        }
        .onChange(of: ptKey) { _, k in controller.setPushToTalkKey(k) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Returning from System Settings (where the user may have just granted
            // Input Monitoring) → refresh so the pointer banner clears without
            // needing to toggle push-to-talk off and on.
            hasInputMonitoring = PushToTalkController.hasPermission
        }
    }

    private var sensitivitySlider: some View {
        HStack(spacing: 12) {
            Text("Less").font(PreferencesTheme.caption).foregroundStyle(PreferencesTheme.inkSoft)
            Slider(value: $position, in: 0...1) { editing in
                // Apply only when the drag ends — each change reboots the pipeline.
                if !editing { controller.setWakeThreshold(Self.threshold(for: position)) }
            }
            .tint(PreferencesTheme.ink)
            .frame(width: 200)
            Text("More").font(PreferencesTheme.caption).foregroundStyle(PreferencesTheme.inkSoft)
        }
    }

    /// Custom `Menu` (not a `.menu` Picker): a Picker with a hidden/empty label
    /// collapses to zero width on this pane (its ideal width is ~0 before the menu
    /// builds). A Menu with a concrete label has a real intrinsic size, so it
    /// renders as the dropdown pill the mockup shows.
    private var keyMenu: some View {
        Menu {
            ForEach(PushToTalkKey.allCases, id: \.self) { k in
                Button(k.label) { ptKey = k }
            }
        } label: {
            HStack(spacing: 8) {
                Text(ptKey.label).font(PreferencesTheme.caption).foregroundStyle(PreferencesTheme.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PreferencesTheme.inkFaint)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(PreferencesTheme.ink.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .stroke(PreferencesTheme.hairStrong, lineWidth: 1)))
        }
        // `.button` menu style + `.plain` button style renders OUR label as-is
        // (the bordered pill). `.borderlessButton` discarded the custom background
        // and showed a system disclosure instead, which is why the pill vanished.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!ptEnabled)
        .opacity(ptEnabled ? 1 : 0.4)
    }
}
