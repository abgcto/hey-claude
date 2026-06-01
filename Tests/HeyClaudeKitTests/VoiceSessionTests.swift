import XCTest
@testable import HeyClaudeKit

final class VoiceSessionTests: XCTestCase {
    private func registry() -> CommandRegistry {
        CommandRegistry(commands: Command.seededDefaults,
                        defaultCommandID: "claude-code",
                        promptCommandID: "claude-code")
    }

    func test_triggerWord_resolvesCodeCommand_noPrompt() {
        let executed = Box<[(Command, String?)]>([])
        let session = VoiceSession(
            transcribe: { _ in "hey claude code" },
            now: { 100.0 },
            cooldownSeconds: 0,
            registry: registry(),
            execute: { executed.value.append(($0, $1)) })
        session.handle(utterance: [0.1, 0.2, 0.3])
        XCTAssertEqual(executed.value.count, 1)
        XCTAssertEqual(executed.value.first?.0.id, "claude-code")
        XCTAssertNil(executed.value.first?.1)
    }

    func test_freeformPrompt_resolvesCodeCommand_withPrompt() {
        let executed = Box<[(Command, String?)]>([])
        let session = VoiceSession(
            transcribe: { _ in "hey claude refactor the auth module" },
            now: { 100.0 },
            cooldownSeconds: 0,
            registry: registry(),
            execute: { executed.value.append(($0, $1)) })
        session.handle(utterance: [0.1])
        XCTAssertEqual(executed.value.first?.0.id, "claude-code")
        XCTAssertEqual(executed.value.first?.1, "refactor the auth module")
    }

    func test_bareWake_resolvesClaudeCode_noPrompt() {
        // Claude-Code-only: bare "hey claude" opens Claude Code with no prompt.
        let executed = Box<[(Command, String?)]>([])
        let session = VoiceSession(
            transcribe: { _ in "hey claude" },
            now: { 100.0 },
            cooldownSeconds: 0,
            registry: registry(),
            execute: { executed.value.append(($0, $1)) })
        session.handle(utterance: [0.1])
        XCTAssertEqual(executed.value.first?.0.id, "claude-code")
        XCTAssertNil(executed.value.first?.1)
    }

    func test_cooldown_suppressesRapidRefires() {
        let count = Box(0)
        let session = VoiceSession(
            transcribe: { _ in "hey claude" },
            now: { 100.0 },                      // same timestamp both calls
            cooldownSeconds: 2.0,
            registry: registry(),
            execute: { _, _ in count.value += 1 })
        session.handle(utterance: [0.1])
        session.handle(utterance: [0.1])         // within cooldown -> ignored
        XCTAssertEqual(count.value, 1)
    }

    func test_handleManual_emptyClip_doesNotExecute() {
        let executed = Box(false)
        let session = VoiceSession(
            transcribe: { _ in "   " },           // silence -> blank transcript
            now: { 0 },
            cooldownSeconds: 0,
            registry: registry(),
            execute: { _, _ in executed.value = true })
        let fired = session.handleManual(utterance: [0, 0, 0])
        XCTAssertFalse(fired, "empty hold returns false so the caller settles the capturing UI")
        XCTAssertFalse(executed.value, "an empty hold must not launch")
    }

    func test_handleManual_speech_launchesWithFullTranscriptAsPrompt() {
        let executed = Box<[(Command, String?)]>([])
        let session = VoiceSession(
            transcribe: { _ in "fix the auth bug in session handling" },
            now: { 0 },
            cooldownSeconds: 0,
            registry: registry(),
            execute: { executed.value.append(($0, $1)) })
        let fired = session.handleManual(utterance: [0.1, 0.2])
        XCTAssertTrue(fired, "a spoken hold fires → the launch flow settles the UI")
        XCTAssertEqual(executed.value.first?.0.id, "claude-code")
        XCTAssertEqual(executed.value.first?.1, "fix the auth bug in session handling")
    }

    func test_handleManual_isNotSuppressedByWakeCooldown() {
        // A deliberate hold must fire even right after a wake-word fire, at the real
        // default 2s cooldown. The press/release edges already dedupe holds; sharing
        // the wake cooldown would silently swallow this capture.
        let now = Box(100.0)
        let manualPrompts = Box<[String?]>([])
        let session = VoiceSession(
            transcribe: { _ in now.value == 100.0 ? "hey claude" : "open the auth file" },
            now: { now.value },
            cooldownSeconds: 2.0,
            registry: registry(),
            execute: { manualPrompts.value.append($1) })
        session.handle(utterance: [0.1])            // wake fire at t=100 (prompt nil)
        now.value = 101.0                            // 1s later — within the 2s cooldown
        session.handleManual(utterance: [0.1])       // the hold must still fire
        XCTAssertEqual(manualPrompts.value.count, 2, "the hold was swallowed by the wake cooldown")
        XCTAssertEqual(manualPrompts.value[1], "open the auth file")
    }
}
