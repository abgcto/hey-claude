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
