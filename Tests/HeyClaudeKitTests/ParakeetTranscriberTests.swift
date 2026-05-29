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
