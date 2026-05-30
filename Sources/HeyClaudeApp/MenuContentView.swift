import SwiftUI
import AppKit
import HeyClaudeKit

/// The menu-bar dropdown: a live status line, a working mute toggle, a
/// privacy-safe recent-actions list, and quit. Renders the same `AppState` the
/// icon does.
struct MenuContentView: View {
    let controller: AppController
    var onboarding: OnboardingWindowController?

    private var statusLine: String {
        switch controller.state {
        case .armed:   return "◆ Listening for \u{201C}Hey Claude\u{201D}"
        case .hot:     return "● Listening\u{2026}"
        case .working: return "→ Launching Claude\u{2026}"
        case .muted:   return "⏸ Muted — click to resume"
        case .paused:  return "◔ Paused during a call"
        case .off:     return "⚠ Microphone access needed"
        }
    }

    var body: some View {
        Text(statusLine)
            .font(.system(size: 12, weight: .medium))
        Text("\(controller.settings.preferredTarget.label) · \(controller.settings.projectDirectory)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

        Divider()

        Menu("Open Claude Code in\u{2026}") {
            ForEach(Array(controller.availableTargets.enumerated()), id: \.offset) { _, target in
                Button {
                    controller.setPreferredTarget(target)
                } label: {
                    if target == controller.settings.preferredTarget {
                        Label(target.label, systemImage: "checkmark")
                    } else {
                        Text(target.label)
                    }
                }
            }
        }

        Button(controller.state == .muted ? "Resume Hey Claude" : "Mute Hey Claude") {
            controller.toggleMute()
        }

        if !controller.recent.entries.isEmpty {
            Divider()
            Text("Recent")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(Array(controller.recent.entries.enumerated()), id: \.offset) { _, entry in
                Text("↳ \(entry.label)\(entry.directory.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11))
            }
        }

        Divider()

        Button("Set up Hey Claude\u{2026}") {
            onboarding?.show()
        }

        Button("Quit Hey Claude") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
