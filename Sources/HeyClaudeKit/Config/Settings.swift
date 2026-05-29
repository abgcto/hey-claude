import Foundation

/// Which terminal "launch CLI" targets.
public enum TerminalKind: String, Codable, CaseIterable, Sendable {
    case terminalApp = "Terminal"
    case iterm2 = "iTerm2"
    case ghostty = "Ghostty"
}

/// User-configurable settings. Persisted as JSON (SettingsStore).
public struct Settings: Codable, Equatable, Sendable {
    public var projectDirectory: String          // default working dir for `claude`
    public var preferredTerminal: TerminalKind
    public var wakeKeywordsScore: Float
    public var wakeKeywordsThreshold: Float
    public var cooldownSeconds: Double            // ignore re-fires within this window
    public var claudeExecutable: String           // "claude" or absolute path

    public init(projectDirectory: String = NSHomeDirectory(),
                preferredTerminal: TerminalKind = .terminalApp,
                wakeKeywordsScore: Float = 2.0,
                wakeKeywordsThreshold: Float = 0.25,
                cooldownSeconds: Double = 2.0,
                claudeExecutable: String = "claude") {
        self.projectDirectory = projectDirectory
        self.preferredTerminal = preferredTerminal
        self.wakeKeywordsScore = wakeKeywordsScore
        self.wakeKeywordsThreshold = wakeKeywordsThreshold
        self.cooldownSeconds = cooldownSeconds
        self.claudeExecutable = claudeExecutable
    }

    public static let `default` = Settings()
}
