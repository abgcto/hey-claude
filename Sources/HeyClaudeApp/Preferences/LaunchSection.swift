import SwiftUI
import AppKit
import HeyClaudeKit

/// Launch tab: where Claude Code opens — the target app + the working folder.
/// Both route to controller setters that restart the pipeline so the next launch
/// uses the new choice.
struct LaunchSection: View {
    let controller: AppController

    private var current: LaunchTarget { controller.settings.preferredTarget }
    private var folder: String {
        (controller.settings.projectDirectory as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.groupSpacing) {
            SettingsGroup("OPEN CLAUDE CODE IN") {
                VStack(spacing: PreferencesTheme.listSpacing) {
                    ForEach(controller.availableTargets, id: \.self) { target in
                        targetRow(target)
                    }
                }
            }
            SettingsGroup("WORKING FOLDER") {
                HStack(spacing: 12) {
                    Text(folder)
                        .font(PreferencesTheme.body)
                        .foregroundStyle(PreferencesTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    DashboardButton("Choose\u{2026}") { chooseFolder() }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetRow(_ target: LaunchTarget) -> some View {
        let selected = target == current
        return Button { controller.setPreferredTarget(target) } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? PreferencesTheme.ink : PreferencesTheme.inkFaint)
                Text(target.label)
                    .font(selected ? PreferencesTheme.bodyMedium : PreferencesTheme.body)
                    .foregroundStyle(PreferencesTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? PreferencesTheme.ink.opacity(0.08) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(selected ? PreferencesTheme.ink.opacity(0.4) : PreferencesTheme.hairStrong,
                            lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Folder picker — same NSOpenPanel config as onboarding's `chooseFolder`.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: controller.settings.projectDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            controller.setProjectDirectory(url.path)
        }
    }
}
