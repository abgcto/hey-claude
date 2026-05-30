import XCTest
@testable import HeyClaudeKit

final class IslandModelTests: XCTestCase {
    // MARK: - Existing shape/content/treatment mapping (kept meaningful)

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

    // MARK: - Visual mapping (the per-state right content the view renders)

    func test_offIsHiddenVisual() {
        XCTAssertEqual(IslandModel(state: .off, transcript: nil).visual, .hidden)
    }
    func test_armedIsIdleVisual() {
        XCTAssertEqual(IslandModel(state: .armed, transcript: nil).visual, .idle)
    }
    func test_hotIsListeningVisual() {
        // hot without a revealed transcript shows the listening meter
        XCTAssertEqual(IslandModel(state: .hot, transcript: nil).visual, .listening)
    }
    func test_hotNotRevealingStaysListeningVisual() {
        // text present but not yet revealing -> still listening
        let m = IslandModel(state: .hot, transcript: "buffered text", revealing: false)
        XCTAssertEqual(m.visual, .listening)
    }
    func test_hotRevealingWithTextIsTranscriptVisual() {
        let m = IslandModel(state: .hot, transcript: "refactor the auth module", revealing: true)
        XCTAssertEqual(m.visual, .transcript("refactor the auth module"))
    }
    func test_hotRevealingWithEmptyTextFallsBackToListeningVisual() {
        let m = IslandModel(state: .hot, transcript: "", revealing: true)
        XCTAssertEqual(m.visual, .listening)
    }
    func test_workingIsLaunchingVisual() {
        XCTAssertEqual(IslandModel(state: .working, transcript: "x").visual, .launching("x"))
    }
    func test_workingCarriesTranscriptIntoLaunching() {
        // launching reuses the reveal band and keeps the spoken line visible
        XCTAssertEqual(IslandModel(state: .working, transcript: "open the repo").visual,
                       .launching("open the repo"))
    }
    func test_workingWithoutTranscriptIsEmptyLaunching() {
        XCTAssertEqual(IslandModel(state: .working, transcript: nil).visual, .launching(""))
    }
    func test_mutedIsMutedVisual() {
        XCTAssertEqual(IslandModel(state: .muted, transcript: nil).visual, .muted)
    }
    func test_pausedIsPausedVisual() {
        XCTAssertEqual(IslandModel(state: .paused, transcript: nil).visual, .paused)
    }
}
