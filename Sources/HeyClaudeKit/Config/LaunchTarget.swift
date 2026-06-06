import Foundation

/// A code editor that can host Claude Code via its
/// `<scheme>://anthropic.claude-code/open?prompt=…` deep link.
///
/// These are the *editor surface* facts (URL scheme, bundle ID, extensions
/// directory, lockfile name). The *tool* half (deep-link host/path/param,
/// extension glob) lives in `EditorIntegration` — so adding a second coding
/// tool (e.g. Codex) is additive data, not new editor cases.
public enum EditorKind: String, Codable, CaseIterable, Sendable {
    case vscode = "VS Code"
    case cursor = "Cursor"
    case antigravity = "Antigravity"

    /// The URL scheme the editor app registers — the deep link's scheme.
    public var urlScheme: String {
        switch self {
        case .vscode:      return "vscode"
        case .cursor:      return "cursor"
        case .antigravity: return "antigravity"
        }
    }

    /// The app's bundle identifier (for availability + activation).
    public var bundleID: String {
        switch self {
        case .vscode:      return "com.microsoft.VSCode"
        case .cursor:      return "com.todesktop.230313mzl4w4u92"
        case .antigravity: return "com.google.antigravity"
        }
    }

    /// Where the editor keeps installed extensions, relative to the user's home
    /// directory (e.g. `.cursor/extensions`).
    public var extensionsSubpath: String {
        switch self {
        case .vscode:      return ".vscode/extensions"
        case .cursor:      return ".cursor/extensions"
        case .antigravity: return ".antigravity/extensions"
        }
    }

    /// Whether an `ideName` from a `~/.claude/ide/*.lock` file denotes this
    /// editor. Lenient on purpose — the exact string varies by editor/version
    /// (e.g. "Cursor", "Visual Studio Code").
    public func matchesIdeName(_ ideName: String) -> Bool {
        let n = ideName.lowercased()
        switch self {
        case .cursor:      return n.contains("cursor")
        case .antigravity: return n.contains("antigravity")
        case .vscode:      return n.contains("visual studio code") || n == "vs code" || n == "code"
        }
    }
}

/// The tool-specific (NOT editor-specific) half of an editor launch. Combined
/// with `EditorKind.urlScheme` to form the deep link, and with
/// `EditorKind.extensionsSubpath` to check availability.
///
/// Stored as data on a `Command` so a future tool (Codex, …) is a new seeded
/// command, not new code. See internal design notes §5.8.
public struct EditorIntegration: Codable, Equatable, Sendable {
    public var deepLinkHost: String     // e.g. "anthropic.claude-code"
    public var deepLinkPath: String     // e.g. "/open"
    public var promptParam: String      // e.g. "prompt"
    public var extensionGlob: String    // e.g. "anthropic.claude-code-*"

    public init(deepLinkHost: String, deepLinkPath: String,
                promptParam: String, extensionGlob: String) {
        self.deepLinkHost = deepLinkHost
        self.deepLinkPath = deepLinkPath
        self.promptParam = promptParam
        self.extensionGlob = extensionGlob
    }

    /// Claude Code's editor integration — the one tool shipped in v1.
    /// Verified live (Cursor + VS Code, 2026-05-30); extension v2.1.72+.
    public static let claudeCode = EditorIntegration(
        deepLinkHost: "anthropic.claude-code",
        deepLinkPath: "/open",
        promptParam: "prompt",
        extensionGlob: "anthropic.claude-code-*")
}

/// Where a command sends its request: a terminal app, or an editor (via deep
/// link). Replaces the old per-command `TerminalKind`.
public enum LaunchTarget: Codable, Hashable, Sendable {
    case terminal(TerminalKind)
    case editor(EditorKind)

    /// Human label for menus / the recent-actions list.
    public var label: String {
        switch self {
        case .terminal(let k): return k.rawValue
        case .editor(let k):   return k.rawValue
        }
    }

    /// Display label for pickers. Collapses `.cursorTerminal` → "Cursor" so
    /// the two Cursor surfaces appear as one entry when only the terminal
    /// fallback is available (no Claude Code extension).
    public var displayLabel: String {
        if case .terminal(let k) = self, k == .cursorTerminal { return "Cursor" }
        return label
    }

    /// App bundle identifier of the target — for app-icon lookup.
    public var bundleID: String {
        switch self {
        case .terminal(let k): return k.bundleID
        case .editor(let k):   return k.bundleID
        }
    }

    // Tagged-object Codable: {"type":"terminal","value":"iTerm2"} /
    // {"type":"editor","value":"Cursor"}.
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Tag: String, Codable { case terminal, editor }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .terminal: self = .terminal(try c.decode(TerminalKind.self, forKey: .value))
        case .editor:   self = .editor(try c.decode(EditorKind.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terminal(let k):
            try c.encode(Tag.terminal, forKey: .type); try c.encode(k, forKey: .value)
        case .editor(let k):
            try c.encode(Tag.editor, forKey: .type);   try c.encode(k, forKey: .value)
        }
    }
}
