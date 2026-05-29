import XCTest
@testable import HeyClaudeKit

final class IslandModelTests: XCTestCase {
    func test_armedIsRestingSeam() {
        let m = IslandModel(state: .armed, transcript: nil)
        XCTAssertEqual(m.shape, .seam)
        XCTAssertEqual(m.content, .none)
    }
    func test_hotShowsListeningWithLevel() {
        let m = IslandModel(state: .hot, transcript: nil)
        XCTAssertEqual(m.shape, .expanded)
        XCTAssertEqual(m.content, .listening)
    }
    func test_workingShowsLaunching() {
        XCTAssertEqual(IslandModel(state: .working, transcript: "x").content, .launching)
    }
    func test_revealShowsTranscript() {
        // a .hot state carrying a finalized transcript reveals it
        let m = IslandModel(state: .hot, transcript: "refactor the auth module", revealing: true)
        XCTAssertEqual(m.content, .transcript("refactor the auth module"))
    }
    func test_mutedAndPausedTreatments() {
        XCTAssertTrue(IslandModel(state: .muted, transcript: nil).showsSlash)
        XCTAssertTrue(IslandModel(state: .paused, transcript: nil).dimmed)
        XCTAssertTrue(IslandModel(state: .off, transcript: nil).hidden)
    }
}
