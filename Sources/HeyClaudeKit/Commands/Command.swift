import Foundation

/// How a command performs its action.
public enum CommandKind: Codable, Equatable, Sendable {
    /// Run a command in a terminal. `commandTemplate` may contain `{prompt}`,
    /// replaced by the spoken trailing prompt (or removed if none).
    case runCLI(commandTemplate: String)
    /// Open an app by bundle identifier.
    case openApp(bundleID: String)
    /// Run an arbitrary shell command (no terminal window).
    case runShell(script: String)
}

/// A voice-triggerable command. Stored as data in Settings — adding a tool
/// (Codex, "open Linear", a script) is a new Command, not new code.
public struct Command: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String              // human label ("Claude Code")
    public var triggers: [String]         // spoken phrases that select it (lowercased). [] = eligible only as a default.
    public var kind: CommandKind
    public var terminal: TerminalKind?    // for runCLI; nil → settings.preferredTerminal
    public var acceptsPrompt: Bool        // whether trailing speech is passed as {prompt}

    public init(id: String, label: String, triggers: [String], kind: CommandKind,
                terminal: TerminalKind? = nil, acceptsPrompt: Bool = false) {
        self.id = id; self.label = label
        self.triggers = triggers.map { $0.lowercased() }
        self.kind = kind; self.terminal = terminal; self.acceptsPrompt = acceptsPrompt
    }

    /// The seeded out-of-box command set: bare "Hey Claude" → desktop app,
    /// "Hey Claude Code"/prompts → Claude Code.
    public static let seededDefaults: [Command] = [
        Command(id: "claude-desktop", label: "Claude desktop", triggers: [],
                kind: .openApp(bundleID: "com.anthropic.claudefordesktop")),
        Command(id: "claude-code", label: "Claude Code", triggers: ["code"],
                kind: .runCLI(commandTemplate: "claude {prompt}"), acceptsPrompt: true),
    ]
}
