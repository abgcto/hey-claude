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
    public var maxUtteranceSeconds: Double        // safety cap on one utterance; the
                                                  // silence endpoint is the real
                                                  // terminator — this only bounds a clip
                                                  // when the VAD never detects silence
    public var endpointSilenceMs: Int             // trailing silence that marks end-of-
                                                  // speech (you stopped talking)
    public var claudeExecutable: String           // "claude" or absolute path
    public var commands: [Command]                // the voice-triggerable command registry
    public var defaultCommandID: String           // bare "hey claude"
    public var promptCommandID: String            // freeform prompt fallthrough
    public var islandVisible: Bool                // show the notch island (3B-2)
    public var onboardingCompleted: Bool          // first-run wake enrollment + setup done

    public init(projectDirectory: String = NSHomeDirectory(),
                preferredTerminal: TerminalKind = .terminalApp,
                wakeKeywordsScore: Float = 2.0,
                wakeKeywordsThreshold: Float = 0.25,
                cooldownSeconds: Double = 2.0,
                maxUtteranceSeconds: Double = 30.0,
                endpointSilenceMs: Int = 800,
                claudeExecutable: String = "claude",
                commands: [Command] = Command.seededDefaults,
                defaultCommandID: String = "claude-desktop",
                promptCommandID: String = "claude-code",
                islandVisible: Bool = true,
                onboardingCompleted: Bool = false) {
        self.projectDirectory = projectDirectory
        self.preferredTerminal = preferredTerminal
        self.wakeKeywordsScore = wakeKeywordsScore
        self.wakeKeywordsThreshold = wakeKeywordsThreshold
        self.cooldownSeconds = cooldownSeconds
        self.maxUtteranceSeconds = maxUtteranceSeconds
        self.endpointSilenceMs = endpointSilenceMs
        self.claudeExecutable = claudeExecutable
        self.commands = commands
        self.defaultCommandID = defaultCommandID
        self.promptCommandID = promptCommandID
        self.islandVisible = islandVisible
        self.onboardingCompleted = onboardingCompleted
    }

    /// Custom decoding so legacy settings JSON written before the command
    /// registry existed still loads: any missing command keys fall back to
    /// the seeded chat-vs-code defaults rather than failing to decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectDirectory = try container.decode(String.self, forKey: .projectDirectory)
        self.preferredTerminal = try container.decode(TerminalKind.self, forKey: .preferredTerminal)
        self.wakeKeywordsScore = try container.decode(Float.self, forKey: .wakeKeywordsScore)
        self.wakeKeywordsThreshold = try container.decode(Float.self, forKey: .wakeKeywordsThreshold)
        self.cooldownSeconds = try container.decode(Double.self, forKey: .cooldownSeconds)
        self.maxUtteranceSeconds = try container.decodeIfPresent(Double.self, forKey: .maxUtteranceSeconds)
            ?? 30.0
        self.endpointSilenceMs = try container.decodeIfPresent(Int.self, forKey: .endpointSilenceMs)
            ?? 800
        self.claudeExecutable = try container.decode(String.self, forKey: .claudeExecutable)
        self.commands = try container.decodeIfPresent([Command].self, forKey: .commands)
            ?? Command.seededDefaults
        self.defaultCommandID = try container.decodeIfPresent(String.self, forKey: .defaultCommandID)
            ?? "claude-desktop"
        self.promptCommandID = try container.decodeIfPresent(String.self, forKey: .promptCommandID)
            ?? "claude-code"
        self.islandVisible = try container.decodeIfPresent(Bool.self, forKey: .islandVisible)
            ?? true
        self.onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)
            ?? false
    }

    public static let `default` = Settings()
}
