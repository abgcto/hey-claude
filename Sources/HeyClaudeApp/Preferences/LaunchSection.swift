import SwiftUI
import AppKit
import HeyClaudeKit

/// Launch tab: where Claude Code opens — the target app + the working folder.
/// Both route to controller setters that restart the pipeline so the next launch
/// uses the new choice. Installed editors missing the Claude Code extension are
/// shown disabled, so they read as "an option once you add the extension."
struct LaunchSection: View {
    let controller: AppController

    /// Detecting targets hits Launch Services + scans editor extension dirs, so
    /// compute it ONCE on appear (and on re-activation, in case the user installed an
    /// editor/extension while away) instead of on every SwiftUI rebuild — and once
    /// for both lists rather than re-scanning per rebuild.
    @State private var targets: [LaunchTarget] = []
    @State private var unavailable: [EditorKind] = []

    private var current: LaunchTarget { controller.settings.preferredTarget }
    private var folder: String {
        (controller.settings.projectDirectory as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesTheme.sectionGap) {
            SettingsSection("Open Claude Code in",
                            "The terminal or editor a launch opens in. Editors missing the Claude Code extension are shown greyed.") {
                VStack(spacing: PreferencesTheme.listSpacing) {
                    ForEach(targets, id: \.self) { targetRow($0) }
                    ForEach(unavailable, id: \.self) { disabledRow($0) }
                }
                .padding(.top, 14)
            }

            SettingsSection("Working folder") {
                SettingsRow("Project folder", folder, showsDivider: false,
                            truncatesDescription: true) {
                    DashboardButton("Choose", style: .secondary) { chooseFolder() }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: refreshTargets)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTargets()
        }
    }

    private func refreshTargets() {
        targets = controller.availableTargets
        unavailable = controller.unavailableEditors
    }

    /// Returns the label to display for `target`, appending a disambiguator when
    /// both Cursor editor and Cursor terminal are present in `targets`.
    private func rowLabel(for target: LaunchTarget) -> String {
        let hasBothCursorModes = targets.contains(.editor(.cursor))
            && targets.contains(.terminal(.cursorTerminal))
        if hasBothCursorModes {
            switch target {
            case .editor(.cursor):    return "Cursor \u{2014} Editor"
            case .terminal(.cursorTerminal): return "Cursor \u{2014} Terminal"
            default: break
            }
        }
        return target.displayLabel
    }

    private func targetRow(_ target: LaunchTarget) -> some View {
        let selected = target == current
        return Button { controller.setPreferredTarget(target) } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? PreferencesTheme.ink : PreferencesTheme.inkFaint)
                Text(rowLabel(for: target))
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
                .accessibilityHidden(true)   // decorative; the row reads as one element
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
        // One VoiceOver element ("VS Code, Needs the Claude Code extension") instead
        // of three disconnected fragments.
        .accessibilityElement(children: .combine)
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
