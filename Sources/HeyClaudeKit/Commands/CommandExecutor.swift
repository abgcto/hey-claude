import AppKit
import Foundation

/// Executes a resolved Command. Side effects are injected so it's testable
/// (mock launcher, openApp, runShell, openURL) and the real defaults live in
/// one place.
public struct CommandExecutor: Sendable {
    private let settings: Settings
    private let launcherFor: @Sendable (TerminalKind) -> TerminalLauncher
    private let openApp: @Sendable (String) -> Void
    private let runShell: @Sendable (String) -> Void
    private let openURL: @Sendable (URL) -> Void

    public init(settings: Settings,
                launcherFor: @escaping @Sendable (TerminalKind) -> TerminalLauncher,
                openApp: @escaping @Sendable (String) -> Void = CommandExecutor.defaultOpenApp,
                runShell: @escaping @Sendable (String) -> Void = CommandExecutor.defaultRunShell,
                openURL: @escaping @Sendable (URL) -> Void = CommandExecutor.defaultOpenURL) {
        self.settings = settings
        self.launcherFor = launcherFor
        self.openApp = openApp
        self.runShell = runShell
        self.openURL = openURL
    }

    public func execute(_ command: Command, prompt: String?) throws {
        switch command.kind {
        case .runCLI(let template):
            let prompt = command.acceptsPrompt ? prompt : nil
            let target = command.target ?? settings.preferredTarget
            switch target {
            case .terminal(let kind):
                try launchTerminal(kind: kind, template: template, prompt: prompt)
            case .editor(let editor):
                // Editor targets require the tool's integration data. If a command
                // somehow lacks it, fall back to a terminal rather than fail.
                guard let integration = command.editorIntegration else {
                    try launchTerminal(kind: fallbackTerminal, template: template, prompt: prompt)
                    return
                }
                openURL(DeepLinkBuilder.url(editor: editor, integration: integration, prompt: prompt))
            }
        case .openApp(let bundleID):
            openApp(bundleID)
        case .runShell(let script):
            runShell(script)
        }
    }

    private func launchTerminal(kind: TerminalKind, template: String, prompt: String?) throws {
        let rendered = Self.render(template, prompt: prompt)
        try launcherFor(kind).launch(LaunchSpec(
            directory: settings.projectDirectory,
            executable: rendered.executable,
            prompt: rendered.prompt))
    }

    /// The terminal app to fall back to when an editor target can't be used.
    private var fallbackTerminal: TerminalKind {
        if case .terminal(let kind) = settings.preferredTarget { return kind }
        return .terminalApp
    }

    /// Splits a rendered template into (executable, prompt) for LaunchSpec.
    /// "claude {prompt}" + "fix" → ("claude", "fix"); + nil → ("claude", nil).
    static func render(_ template: String, prompt: String?) -> (executable: String, prompt: String?) {
        if let p = prompt, !p.isEmpty {
            // Replace {prompt} with a marker we then peel back into LaunchSpec.prompt
            // so shell-escaping stays in LaunchSpec. If no placeholder, append.
            if template.contains("{prompt}") {
                let exe = template.replacingOccurrences(of: "{prompt}", with: "").trimmingCharacters(in: .whitespaces)
                return (exe, p)
            }
            return (template.trimmingCharacters(in: .whitespaces), p)
        }
        let exe = template.replacingOccurrences(of: "{prompt}", with: "").trimmingCharacters(in: .whitespaces)
        return (exe, nil)
    }

    public static func defaultOpenApp(_ bundleID: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
        }
    }
    public static func defaultRunShell(_ script: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", script]
        try? p.run()
    }
    /// Opens the editor deep link. Opening a custom-scheme URL activates the
    /// handling editor, so the Claude Code panel lands in its focused window.
    public static func defaultOpenURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
