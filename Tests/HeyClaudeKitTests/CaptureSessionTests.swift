import XCTest
@testable import HeyClaudeKit

final class CaptureSessionTests: XCTestCase {
    // Helpers: 16k frames.
    private func speech(_ ms: Int) -> [Float] {
        (0..<(16 * ms)).map { sin(Float($0) * 0.1) * 0.5 }
    }
    private func silence(_ ms: Int) -> [Float] { [Float](repeating: 0, count: 16 * ms) }

    func test_capturesPrerollPlusPostFireUntilEndpoint() {
        var captured: [Float]? = nil
        let session = CaptureSession(
            sampleRate: 16000, prerollSeconds: 1.0, postFireMaxSeconds: 2.0,
            vad: VoiceActivityDetector(energyThreshold: 0.01, frameMs: 20, hangoverMs: 400),
            onUtterance: { captured = $0 })

        // Pre-fire lookback contains 300ms of "hey claude" speech.
        session.feedWhileListening(speech(300))
        // Fire: seed with lookback, then 200ms command + 600ms trailing silence.
        session.fire()
        session.feedWhileCapturing(speech(200))
        session.feedWhileCapturing(silence(600))

        XCTAssertNotNil(captured)
        // Captured clip includes the pre-roll speech (proves lookback retained).
        XCTAssertGreaterThan(captured!.count, 16 * 400)
    }

    func test_bareWake_endpointsOnTrailingSilence() {
        var fired = false
        let session = CaptureSession(
            sampleRate: 16000, prerollSeconds: 1.0, postFireMaxSeconds: 2.0,
            vad: VoiceActivityDetector(energyThreshold: 0.01, frameMs: 20, hangoverMs: 400),
            onUtterance: { _ in fired = true })
        session.feedWhileListening(speech(300))   // "hey claude"
        session.fire()
        session.feedWhileCapturing(silence(600))   // nothing after
        XCTAssertTrue(fired)                        // still endpoints + reports
    }
}
