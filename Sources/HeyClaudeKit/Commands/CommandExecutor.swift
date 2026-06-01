import AppKit
import Foundation

/// Executes a resolved Command. Side effects are injected so it's testable
/// (mock launcher, runShell, openURL) and the real defaults live in one place.
///
/// `execute` reports its outcome through a `completion` closure rather than a
/// synchronous `throws`: launch failures arrive on two clocks — terminal/editor
/// failures are synchronous, but deep-link success is best-effort. One `Result`
/// channel captures both. The typed `LaunchFailure` crosses to the caller intact
/// (it's `Sendable`) so the UI can show a specific, actionable message — never a
/// bare `Bool`.
public struct CommandExecutor: Sendable {
    private let settings: Settings
    private let launcherFor: @Sendable (TerminalKind) -> TerminalLauncher
    private let runShell: @Sendable (String) throws -> Void
    private let openURL: @Sendable (URL) -> Bool

    public init(settings: Settings,
                launcherFor: @escaping @Sendable (TerminalKind) -> TerminalLauncher,
                runShell: @escaping @Sendable (String) throws -> Void = CommandExecutor.defaultRunShell,
                openURL: @escaping @Sendable (URL) -> Bool = CommandExecutor.defaultOpenURL) {
        self.settings = settings
        self.launcherFor = launcherFor
        self.runShell = runShell
        self.openURL = openURL
    }

    /// Runs the command and reports success or a typed failure via `completion`.
    /// All paths call `completion` inline (synchronous).
    public func execute(_ command: Command, prompt: String?,
                        completion: @escaping @Sendable (Result<Void, LaunchFailure>) -> Void) {
        switch command.kind {
        case .runCLI(let template):
            let prompt = command.acceptsPrompt ? prompt : nil
            let target = command.target ?? settings.preferredTarget
            switch target {
            case .terminal(let kind):
                completion(launchTerminal(kind: kind, template: template, prompt: prompt))
            case .editor(let editor):
                // Editor targets require the tool's integration data. Missing data
                // is a defensive (backfilled) case — fail honestly, no fallback.
                guard let integration = command.editorIntegration else {
                    completion(.failure(.editorIntegrationMissing(editor)))
                    return
                }
                let url = DeepLinkBuilder.url(editor: editor, integration: integration, prompt: prompt)
                completion(openURL(url) ? .success(())
                                        : .failure(.editorDeepLinkRejected(editor)))
            }
        case .openApp(let bundleID):
            // Legacy path — the "open Claude desktop app" command was removed.
            // Retained as a decodable case for backward compat with old settings
            // files; any that survive migration fail here rather than crashing.
            completion(.failure(.appNotFound(bundleID)))
        case .runShell(let script):
            do { try runShell(script); completion(.success(())) }
            catch { completion(.failure(.shellFailed(error.localizedDescription))) }
        }
    }

    private func launchTerminal(kind: TerminalKind, template: String, prompt: String?)
        -> Result<Void, LaunchFailure> {
        let rendered = Self.render(template, prompt: prompt)
        do {
            try launcherFor(kind).launch(LaunchSpec(
                directory: settings.projectDirectory,
                executable: rendered.executable,
                prompt: rendered.prompt))
            return .success(())
        } catch let e as TerminalLaunchError {
            switch e {
            case .notInstalled:          return .failure(.terminalNotInstalled(kind))
            case .automationFailed(let m): return .failure(.terminalAutomationFailed(kind, m))
            }
        } catch {
            return .failure(.terminalAutomationFailed(kind, error.localizedDescription))
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

    public static func defaultRunShell(_ script: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", script]
        try p.run()
    }
    /// Opens the editor deep link. Returns whether a handler claimed the scheme —
    /// best-effort (the OS doesn't report whether the editor honored the link).
    public static func defaultOpenURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
