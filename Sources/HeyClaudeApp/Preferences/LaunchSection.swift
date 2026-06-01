import SwiftUI
import AppKit
import HeyClaudeKit

/// Launch tab: where Claude Code opens — the target app + the working folder.
/// Both route to controller setters that restart the pipeline so the next launch
/// uses the new choice. Installed editors missing the Claude Code extension are
/// shown disabled, so they read as "an option once you add the extension."
struct LaunchSection: View {
    let controller: AppController

    private var current: LaunchTarget { controller.settings.preferredTarget }
    private var folder: String {
        (controller.settings.projectDirectory as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.sectionGap) {
            VStack(spacing: 0) {
                SettingsHeader("Open Claude Code in",
                               "The terminal or editor a launch opens in. Editors missing the Claude Code extension are shown greyed.")
                VStack(spacing: PreferencesTheme.listSpacing) {
                    ForEach(controller.availableTargets, id: \.self) { targetRow($0) }
                    ForEach(controller.unavailableEditors, id: \.self) { disabledRow($0) }
                }
                .padding(.top, 14)
            }

            VStack(spacing: 0) {
                SettingsHeader("Working folder")
                SettingsRow("Project folder", folder, showsDivider: false) {
                    DashboardButton("Choose", style: .secondary) { chooseFolder() }
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
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? PreferencesTheme.ink.opacity(0.10) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(selected ? PreferencesTheme.ink.opacity(0.4) : PreferencesTheme.hairStrong,
                            lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Unselected rows get the hover fill; the selected row keeps its fill.
        .dashboardHover(cornerRadius: 9, enabled: !selected, lift: false)
    }

    /// An installed editor that can't be a target yet (no Claude Code extension) —
    /// shown disabled so it's discoverable, with the reason on the trailing edge.
    private func disabledRow(_ editor: EditorKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 13)).foregroundStyle(PreferencesTheme.inkFaint)
            Text(LaunchTarget.editor(editor).label)
                .font(PreferencesTheme.body).foregroundStyle(PreferencesTheme.ink)
            Spacer(minLength: 12)
            Text("Needs the Claude Code extension")
                .font(PreferencesTheme.caption).foregroundStyle(PreferencesTheme.inkFaint)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 9).stroke(PreferencesTheme.hairStrong, lineWidth: 1))
        .opacity(0.5)
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
