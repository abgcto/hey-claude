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
    public var target: LaunchTarget?      // terminal or editor; nil → settings default
    public var acceptsPrompt: Bool        // whether trailing speech is passed as {prompt}

    /// How this command's tool integrates with an editor (deep-link host/path/
    /// param + extension glob). `nil` → terminal-only: editor targets are not
    /// offered for it. Carries Claude Code's values for the seeded command; a
    /// future "codex" command carries Codex's. See design §5.8.
    public var editorIntegration: EditorIntegration?

    public init(id: String, label: String, triggers: [String], kind: CommandKind,
                target: LaunchTarget? = nil, acceptsPrompt: Bool = false,
                editorIntegration: EditorIntegration? = nil) {
        self.id = id; self.label = label
        self.triggers = triggers.map { $0.lowercased() }
        self.kind = kind; self.target = target; self.acceptsPrompt = acceptsPrompt
        self.editorIntegration = editorIntegration
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, triggers, kind, target, acceptsPrompt, editorIntegration
    }
    /// Pre-`LaunchTarget` settings stored the launch destination as a bare
    /// `TerminalKind` under `terminal`. Decoded into `target` for migration.
    private enum LegacyKeys: String, CodingKey { case terminal }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.label = try c.decode(String.self, forKey: .label)
        self.triggers = (try c.decodeIfPresent([String].self, forKey: .triggers) ?? [])
            .map { $0.lowercased() }
        self.kind = try c.decode(CommandKind.self, forKey: .kind)
        self.acceptsPrompt = try c.decodeIfPresent(Bool.self, forKey: .acceptsPrompt) ?? false
        self.editorIntegration = try c.decodeIfPresent(EditorIntegration.self, forKey: .editorIntegration)

        if let t = try c.decodeIfPresent(LaunchTarget.self, forKey: .target) {
            self.target = t
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
            .decodeIfPresent(TerminalKind.self, forKey: .terminal) {
            self.target = .terminal(legacy)   // migrate old `terminal` → `target`
        } else {
            self.target = nil
        }
    }

    /// The seeded out-of-box command set: bare "Hey Claude" and any prompt go to
    /// Claude Code. (The legacy "open Claude desktop chat app" command was
    /// removed — the app is now purely a Claude Code launcher. See design §5.6.)
    public static let seededDefaults: [Command] = [
        Command(id: "claude-code", label: "Claude Code", triggers: ["code"],
                kind: .runCLI(commandTemplate: "claude {prompt}"),
                acceptsPrompt: true,
                editorIntegration: .claudeCode),
    ]
}
