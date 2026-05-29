import XCTest
@testable import HeyClaudeKit

final class VoiceSessionTests: XCTestCase {
    func test_endToEnd_routesAndExecutes() throws {
        var executed: [Action] = []
        let session = VoiceSession(
            transcribe: { _ in "hey claude code" },
            now: { 100.0 },
            cooldownSeconds: 0,
            execute: { executed.append($0) })
        session.handle(utterance: [0.1, 0.2, 0.3])   // simulates a captured clip
        XCTAssertEqual(executed, [.launchCLI(prompt: nil)])   // "code" -> bare CLI
    }

    func test_cooldown_suppressesRapidRefires() {
        var count = 0
        let session = VoiceSession(
            transcribe: { _ in "hey claude" },
            now: { 100.0 },                      // same timestamp both calls
            cooldownSeconds: 2.0,
            execute: { _ in count += 1 })
        session.handle(utterance: [0.1])
        session.handle(utterance: [0.1])         // within cooldown -> ignored
        XCTAssertEqual(count, 1)
    }
}
