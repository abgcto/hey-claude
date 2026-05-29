import XCTest
@testable import HeyClaudeKit

final class VoiceSessionTests: XCTestCase {
    private func registry() -> CommandRegistry {
        CommandRegistry(commands: Command.seededDefaults,
                        defaultCommandID: "claude-desktop",
                        promptCommandID: "claude-code")
    }

    func test_triggerWord_resolvesCodeCommand_noPrompt() {
        var executed: [(Command, String?)] = []
        let session = VoiceSession(
            transcribe: { _ in "hey claude code" },
            now: { 100.0 },
            cooldownSeconds: 0,
            registry: registry(),
            execute: { executed.append(($0, $1)) })
        session.handle(utterance: [0.1, 0.2, 0.3])
        XCTAssertEqual(executed.count, 1)
        XCTAssertEqual(executed.first?.0.id, "claude-code")
        XCTAssertNil(executed.first?.1)
    }

    func test_freeformPrompt_resolvesCodeCommand_withPrompt() {
        var executed: [(Command, String?)] = []
        let session = VoiceSession(
            transcribe: { _ in "hey claude refactor the auth module" },
            now: { 100.0 },
            cooldownSeconds: 0,
            registry: registry(),
            execute: { executed.append(($0, $1)) })
        session.handle(utterance: [0.1])
        XCTAssertEqual(executed.first?.0.id, "claude-code")
        XCTAssertEqual(executed.first?.1, "refactor the auth module")
    }

    func test_bareWake_resolvesDefaultDesktop_noPrompt() {
        var executed: [(Command, String?)] = []
        let session = VoiceSession(
            transcribe: { _ in "hey claude" },
            now: { 100.0 },
            cooldownSeconds: 0,
            registry: registry(),
            execute: { executed.append(($0, $1)) })
        session.handle(utterance: [0.1])
        XCTAssertEqual(executed.first?.0.id, "claude-desktop")
        XCTAssertNil(executed.first?.1)
    }

    func test_cooldown_suppressesRapidRefires() {
        var count = 0
        let session = VoiceSession(
            transcribe: { _ in "hey claude" },
            now: { 100.0 },                      // same timestamp both calls
            cooldownSeconds: 2.0,
            registry: registry(),
            execute: { _, _ in count += 1 })
        session.handle(utterance: [0.1])
        session.handle(utterance: [0.1])         // within cooldown -> ignored
        XCTAssertEqual(count, 1)
    }
}
