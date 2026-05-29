import XCTest
@testable import HeyClaudeKit

final class AudioSamplesTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "wav")!
    }

    func test_loads16kMonoFloatSamples() throws {
        let samples = try AudioSamples.load(fixtureURL("hey_claude_only"))
        XCTAssertGreaterThan(samples.count, 8000)        // > ~0.5s at 16k
        XCTAssertTrue(samples.allSatisfy { $0 >= -1.0 && $0 <= 1.0 })
    }
}

final class ParakeetTranscriberTests: XCTestCase {
    private func modelsDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Models")
    }
    private func fixture(_ n: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(n)", withExtension: "wav")!
    }

    func test_transcribesPromptClip() throws {
        let t = try ParakeetTranscriber(
            modelDir: modelsDir().appendingPathComponent("sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"))
        let text = try t.transcribe(try AudioSamples.load(fixture("hey_claude_prompt")))
        XCTAssertTrue(text.contains("refactor"), "got: \(text)")
        XCTAssertTrue(text.contains("auth"), "got: \(text)")
    }
}
