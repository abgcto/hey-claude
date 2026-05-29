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

    /// Fires on the synthetic `say -v Samantha "hey claude"` clip with the
    /// canonical keyword `▁HE Y ▁C LA U DE` at the calibrated defaults
    /// (keywordsScore 2.0, keywordsThreshold 0.25). The earlier "never fires"
    /// symptom was a streaming-flush bug, not a model limitation: the tail pad
    /// in `detects(in:)` was too short (0.2s) to drain the zipformer's final
    /// chunk on a ~0.7s clip, so the last tokens (`U DE`) were never decoded.
    /// A 1s tail pad flushes them and the keyword trips. See
    /// internal design notes ("Wake-word calibration").
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
