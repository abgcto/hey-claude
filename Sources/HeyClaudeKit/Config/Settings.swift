import Foundation

/// Which terminal "launch CLI" targets.
public enum TerminalKind: String, Codable, CaseIterable, Sendable {
    case terminalApp = "Terminal"
    case iterm2 = "iTerm2"
    case ghostty = "Ghostty"

    /// App bundle identifier — for availability checks and app-icon lookup.
    public var bundleID: String {
        switch self {
        case .terminalApp: return "com.apple.Terminal"
        case .iterm2:      return "com.googlecode.iterm2"
        case .ghostty:     return "com.mitchellh.ghostty"
        }
    }
}

/// User-configurable settings. Persisted as JSON (SettingsStore).
public struct Settings: Codable, Equatable, Sendable {
    public var projectDirectory: String          // default working dir for `claude`
    public var preferredTarget: LaunchTarget      // default target (terminal or editor)
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
    public var onboardingCompleted: Bool          // first-run wake enrollment + setup done
    public var mascotID: String                    // selected mascot (MascotCatalog id)
    public var mascotColorHex: String              // mascot body color, e.g. "#D87757"

    public init(projectDirectory: String = NSHomeDirectory(),
                preferredTarget: LaunchTarget = .terminal(.terminalApp),
                wakeKeywordsScore: Float = 2.0,
                wakeKeywordsThreshold: Float = 0.25,
                cooldownSeconds: Double = 2.0,
                maxUtteranceSeconds: Double = 30.0,
                endpointSilenceMs: Int = 800,
                claudeExecutable: String = "claude",
                commands: [Command] = Command.seededDefaults,
                defaultCommandID: String = "claude-code",
                promptCommandID: String = "claude-code",
                onboardingCompleted: Bool = false,
                mascotID: String = "classic",
                mascotColorHex: String = "#D87757") {
        self.projectDirectory = projectDirectory
        self.preferredTarget = preferredTarget
        self.wakeKeywordsScore = wakeKeywordsScore
        self.wakeKeywordsThreshold = wakeKeywordsThreshold
        self.cooldownSeconds = cooldownSeconds
        self.maxUtteranceSeconds = maxUtteranceSeconds
        self.endpointSilenceMs = endpointSilenceMs
        self.claudeExecutable = claudeExecutable
        self.commands = commands
        self.defaultCommandID = defaultCommandID
        self.promptCommandID = promptCommandID
        self.onboardingCompleted = onboardingCompleted
        self.mascotID = mascotID
        self.mascotColorHex = mascotColorHex
    }

    /// Pre-`LaunchTarget` settings stored the default destination as a bare
    /// `TerminalKind` under `preferredTerminal`. Migrated into `preferredTarget`.
    private enum LegacyKeys: String, CodingKey { case preferredTerminal }

    /// Custom decoding so legacy settings JSON still loads: missing command keys
    /// fall back to the seeded defaults, the old `preferredTerminal` migrates to
    /// `preferredTarget`, and the retired `claude-desktop` routing is dropped
    /// (the app is now Claude-Code-only — see design §5.6).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectDirectory = try container.decode(String.self, forKey: .projectDirectory)

        if let t = try container.decodeIfPresent(LaunchTarget.self, forKey: .preferredTarget) {
            self.preferredTarget = t
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
            .decodeIfPresent(TerminalKind.self, forKey: .preferredTerminal) {
            self.preferredTarget = .terminal(legacy)
        } else {
            self.preferredTarget = .terminal(.terminalApp)
        }

        self.wakeKeywordsScore = try container.decode(Float.self, forKey: .wakeKeywordsScore)
        self.wakeKeywordsThreshold = try container.decode(Float.self, forKey: .wakeKeywordsThreshold)
        self.cooldownSeconds = try container.decode(Double.self, forKey: .cooldownSeconds)
        self.maxUtteranceSeconds = try container.decodeIfPresent(Double.self, forKey: .maxUtteranceSeconds)
            ?? 30.0
        self.endpointSilenceMs = try container.decodeIfPresent(Int.self, forKey: .endpointSilenceMs)
            ?? 800
        self.claudeExecutable = try container.decode(String.self, forKey: .claudeExecutable)

        let decodedCommands = try container.decodeIfPresent([Command].self, forKey: .commands)
            ?? Command.seededDefaults
        let withoutDesktop = decodedCommands.filter { $0.id != "claude-desktop" }
        let base = withoutDesktop.isEmpty ? Command.seededDefaults : withoutDesktop
        // Backfill editor integration onto commands persisted before the field
        // existed, using the seeded tool definition for the same id. Without this
        // a migrated `claude-code` has no `editorIntegration`, so an editor target
        // silently falls back to a terminal. (design §5.6 migration)
        let seededByID = Dictionary(Command.seededDefaults.map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
        self.commands = base.map { cmd in
            guard cmd.editorIntegration == nil,
                  let ei = seededByID[cmd.id]?.editorIntegration else { return cmd }
            var c = cmd; c.editorIntegration = ei; return c
        }

        let rawDefault = try container.decodeIfPresent(String.self, forKey: .defaultCommandID)
            ?? "claude-code"
        self.defaultCommandID = (rawDefault == "claude-desktop") ? "claude-code" : rawDefault
        self.promptCommandID = try container.decodeIfPresent(String.self, forKey: .promptCommandID)
            ?? "claude-code"
        // (legacy `islandVisible` keys in old settings JSON are ignored — the island
        // is always present now.)
        self.onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)
            ?? false
        self.mascotID = try container.decodeIfPresent(String.self, forKey: .mascotID)
            ?? "classic"
        self.mascotColorHex = try container.decodeIfPresent(String.self, forKey: .mascotColorHex)
            ?? "#D87757"
    }

    public static let `default` = Settings()
}
