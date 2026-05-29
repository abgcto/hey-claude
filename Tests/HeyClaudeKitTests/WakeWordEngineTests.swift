import XCTest
@testable import HeyClaudeKit

final class WakeWordEngineTests: XCTestCase {
    private func modelsDir() -> URL {
        URL(fileURLWithPath: #filePath)            // …/Tests/HeyClaudeKitTests/WakeWordEngineTests.swift
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()           // repo root
            .appendingPathComponent("Models")
    }
    private func fixture(_ n: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(n)", withExtension: "wav")!
    }

    /// KNOWN CALIBRATION ITEM — expected to FAIL on the synthetic `say`
    /// fixture. The 3.3M gigaspeech KWS model does not emit the "claude" token
    /// path for the `say -v Samantha` clip (it hears "A CLA"), so the keyword
    /// cannot fire at any threshold. This is a model/voice acoustic limitation,
    /// not a bug — the engine fires correctly on the model's own validated
    /// keyword+wav, and the negative test passes. Real-voice tuning is the
    /// Phase 2 / manual-spike step. See internal design notes
    /// ("Wake-word calibration"). Kept faithful to the plan rather than skipped.
    func test_detectsHeyClaudeInPositiveClip() throws {
        let engine = try WakeWordEngine(
            modelDir: modelsDir().appendingPathComponent("sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"),
            keywordsFile: modelsDir().appendingPathComponent("keywords.txt"))
        let samples = try AudioSamples.load(fixture("hey_claude_only"))
        XCTAssertTrue(engine.detects(in: samples))
    }

    func test_doesNotFireOnNegativeSpeech() throws {
        let engine = try WakeWordEngine(
            modelDir: modelsDir().appendingPathComponent("sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"),
            keywordsFile: modelsDir().appendingPathComponent("keywords.txt"))
        let samples = try AudioSamples.load(fixture("negative_speech"))
        XCTAssertFalse(engine.detects(in: samples))
    }
}
