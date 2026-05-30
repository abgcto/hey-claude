import SwiftUI
import AppKit
import HeyClaudeKit

/// The menu-bar dropdown: a live status line, a working mute toggle, a
/// privacy-safe recent-actions list, and quit. Renders the same `AppState` the
/// icon does.
struct MenuContentView: View {
    let controller: AppController
    var preferences: PreferencesWindowController?

    private var statusLine: String {
        switch controller.state {
        case .armed:   return "○ Listening for \u{201C}Hey Claude\u{201D}"   // ○ waiting → ● hearing
        case .hot:     return "● Listening\u{2026}"
        case .working: return "→ Launching Claude\u{2026}"
        case .failed:  return "✕ Couldn\u{2019}t launch — see below"
        case .muted:   return "⏸ Muted — click to resume"
        case .paused:  return "◔ Paused during a call"
        case .off:     return "⚠ Microphone access needed"
        }
    }

    /// `Cursor · ~/Desktop/Sy/hey-claude` — the path is tilde-abbreviated so the
    /// common home-relative case stays short and fits within the menu's width cap.
    private var locationLine: String {
        let path = (controller.settings.projectDirectory as NSString).abbreviatingWithTildeInPath
        return "\(controller.settings.preferredTarget.label) · \(path)"
    }

    var body: some View {
        Text(statusLine)
            .font(.system(size: 12, weight: .medium))
        Text(locationLine)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .truncationMode(.middle)

        // Mic-revoked recovery: the only actionable thing in the `.off` state, so
        // the status line above ("Microphone access needed") isn't a dead end.
        if controller.state == .off {
            Button("Open Microphone Settings\u{2026}") { SystemSettingsLink.microphone.open() }
        }

        // Persistent failure detail — held until the next successful launch, so the
        // error survives the brief island beat and stays inspectable + actionable.
        if let failure = controller.lastFailure {
            Divider()
            // Headline carries the specifics; rows tail-truncate so an overflow
            // degrades to the front-loaded (actionable) words rather than clipping
            // mid-instruction — and the settings button below is un-truncatable.
            // ✕ is the single "launch failed" mark (status line, island, Recent too).
            Text("✕ \(failure.errorDescription ?? "Last launch failed")")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            // The remedy is either an action button OR a text hint — never both, so
            // we don't say "Allow Automation" twice.
            if let url = failure.settingsURL, let label = failure.settingsActionLabel {
                Button(label) { NSWorkspace.shared.open(url) }
            } else if let fix = failure.recoverySuggestion {
                Text(fix)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Divider()

        // A Picker (not a hand-rolled Menu of Buttons) so SwiftUI draws the
        // native single-selection checkmark on exactly the chosen target and
        // sizes the submenu to its widest label. Hand-rolled rows hit two
        // NSMenu quirks: mixed Label/Text row types truncate longer labels, and
        // `.opacity` on a Label icon is dropped (every row shows a checkmark).
        Picker("Open Claude Code in\u{2026}", selection: Binding(
            get: { controller.settings.preferredTarget },
            set: { controller.setPreferredTarget($0) }
        )) {
            ForEach(controller.availableTargets, id: \.self) { target in
                Text(target.label).tag(target)
            }
        }
        .pickerStyle(.menu)

        Button(controller.state == .muted ? "Resume" : "Mute") {
            controller.toggleMute()
        }

        if !controller.recent.entries.isEmpty {
            Divider()
            Text("Recent")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(Array(controller.recent.entries.enumerated()), id: \.offset) { _, entry in
                // Honest outcome log, read as a matched pair: ✓ ran, ✕ failed.
                // The working folder lives in the location line above — not repeated
                // per row.
                let marker = entry.outcome == .failed ? "✕" : "✓"
                Text("\(marker) \(entry.label)")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.outcome == .failed ? .secondary : .primary)
            }
        }

        Divider()

        // One settings door: the dashboard owns launch-at-login, wake re-training,
        // target/folder, and appearance — so "Set Up…" and the launch-at-login
        // toggle are gone from the menu.
        Button("Settings\u{2026}") {
            preferences?.show()
        }
        .keyboardShortcut(",")

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
