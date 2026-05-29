import XCTest
@testable import HeyClaudeKit

final class CommandRegistryTests: XCTestCase {
    private func registry() -> CommandRegistry {
        CommandRegistry(commands: Command.seededDefaults,
                        defaultCommandID: "claude-desktop",
                        promptCommandID: "claude-code")
    }

    func test_silence_resolvesDefault_noPrompt() {
        let r = registry().resolve(transcript: nil)
        XCTAssertEqual(r?.command.id, "claude-desktop")
        XCTAssertNil(r?.prompt)
    }
    func test_triggerWord_resolvesThatCommand() {
        let r = registry().resolve(transcript: "code")
        XCTAssertEqual(r?.command.id, "claude-code")
        XCTAssertNil(r?.prompt)
    }
    func test_triggerWithTrailing_passesPrompt() {
        let r = registry().resolve(transcript: "code refactor the auth module")
        XCTAssertEqual(r?.command.id, "claude-code")
        XCTAssertEqual(r?.prompt, "refactor the auth module")
    }
    func test_freeform_goesToPromptCommand_withFullText() {
        let r = registry().resolve(transcript: "refactor the auth module")
        XCTAssertEqual(r?.command.id, "claude-code")
        XCTAssertEqual(r?.prompt, "refactor the auth module")
    }
    func test_addedCommand_resolvesByTrigger() {
        var r = registry()
        r.commands.append(Command(id: "codex", label: "Codex", triggers: ["codex"],
                                  kind: .runCLI(commandTemplate: "codex"), acceptsPrompt: false))
        XCTAssertEqual(r.resolve(transcript: "codex")?.command.id, "codex")
    }
    func test_caseAndWhitespaceInsensitive() {
        XCTAssertEqual(registry().resolve(transcript: "  Code  ")?.command.id, "claude-code")
    }
}
