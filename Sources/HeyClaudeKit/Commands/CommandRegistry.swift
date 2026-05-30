import Foundation

/// Resolves a trailing transcript to a command + optional prompt.
/// Rules (generalizing the old §5 table):
///   1. no speech            → defaultCommand, no prompt
///   2. starts with a trigger → that command; remainder → prompt (if acceptsPrompt)
///   3. otherwise (freeform)  → promptCommand with the full text as prompt
public struct CommandRegistry {
    public var commands: [Command]
    public var defaultCommandID: String   // bare "hey claude"
    public var promptCommandID: String    // freeform fallthrough

    public init(commands: [Command], defaultCommandID: String, promptCommandID: String) {
        self.commands = commands
        self.defaultCommandID = defaultCommandID
        self.promptCommandID = promptCommandID
    }

    public struct Resolution: Equatable, Sendable { public let command: Command; public let prompt: String? }

    private func command(_ id: String) -> Command? { commands.first { $0.id == id } }
    private static func norm(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func resolve(transcript: String?) -> Resolution? {
        guard let raw = transcript, !Self.norm(raw).isEmpty else {
            return command(defaultCommandID).map { Resolution(command: $0, prompt: nil) }
        }
        let text = Self.norm(raw)

        // 2. trigger-prefix match (longest trigger first, so "code review" beats "code")
        let candidates = commands
            .flatMap { c in c.triggers.map { (trigger: $0, command: c) } }
            .sorted { $0.trigger.count > $1.trigger.count }
        for (trigger, c) in candidates {
            if text == trigger {
                return Resolution(command: c, prompt: nil)
            }
            if text.hasPrefix(trigger + " ") {
                let rest = String(text.dropFirst(trigger.count + 1)).trimmingCharacters(in: .whitespaces)
                return Resolution(command: c, prompt: c.acceptsPrompt && !rest.isEmpty ? rest : nil)
            }
        }
        // 3. freeform → prompt command with full text
        return command(promptCommandID).map {
            Resolution(command: $0, prompt: $0.acceptsPrompt ? text : nil)
        }
    }
}
