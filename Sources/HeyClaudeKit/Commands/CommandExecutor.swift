import AppKit
import Foundation

/// Executes a resolved Command. Side effects are injected so it's testable
/// (mock launcher, openApp, runShell) and the real defaults live in one place.
public struct CommandExecutor {
    private let settings: Settings
    private let launcherFor: (TerminalKind) -> TerminalLauncher
    private let openApp: (String) -> Void
    private let runShell: (String) -> Void

    public init(settings: Settings,
                launcherFor: @escaping (TerminalKind) -> TerminalLauncher,
                openApp: @escaping (String) -> Void = CommandExecutor.defaultOpenApp,
                runShell: @escaping (String) -> Void = CommandExecutor.defaultRunShell) {
        self.settings = settings
        self.launcherFor = launcherFor
        self.openApp = openApp
        self.runShell = runShell
    }

    public func execute(_ command: Command, prompt: String?) throws {
        switch command.kind {
        case .runCLI(let template):
            let rendered = Self.render(template, prompt: command.acceptsPrompt ? prompt : nil)
            let term = command.terminal ?? settings.preferredTerminal
            try launcherFor(term).launch(LaunchSpec(
                directory: settings.projectDirectory,
                executable: rendered.executable,
                prompt: rendered.prompt))
        case .openApp(let bundleID):
            openApp(bundleID)
        case .runShell(let script):
            runShell(script)
        }
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
}
