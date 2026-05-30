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

    init(controller: AppController) {
        self.controller = controller
        _position = State(initialValue: Self.position(for: controller.settings.wakeKeywordsThreshold))
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
