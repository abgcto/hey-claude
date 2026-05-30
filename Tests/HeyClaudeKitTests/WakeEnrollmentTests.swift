import XCTest
@testable import HeyClaudeKit

final class WakeEnrollmentTests: XCTestCase {
    // MARK: - Pure token → keyword mapping

    func test_keywordLine_mapsLeadingSpaceToWordBoundary() {
        let tokens = [" HE", "Y", " C", "LO", "U", "D"]
        XCTAssertEqual(WakeEnrollment.keywordLine(from: tokens), "▁HE Y ▁C LO U D")
    }

    func test_keywordLine_dropsEmptyTokens() {
        XCTAssertEqual(WakeEnrollment.keywordLine(from: [" HE", "", "  ", "Y"]), "▁HE Y")
    }

    func test_isPlausibleWake_acceptsClaudeRejectsGlitch() {
        XCTAssertTrue(WakeEnrollment.isPlausibleWake(tokens: [" HE", "Y", " C", "LO", "U", "D"]))
        XCTAssertFalse(WakeEnrollment.isPlausibleWake(tokens: [" OUT"]))   // the glitch we saw
    }

    func test_derivedLines_dedupesAgreeingSamples() {
        let a = [" HE", "Y", " C", "LO", "U", "D"]
        XCTAssertEqual(WakeEnrollment.derivedLines(isolated: [a, a]), ["▁HE Y ▁C LO U D"])
    }

    func test_derivedLines_keepsDistinctVariants() {
        let cloud = [" HE", "Y", " C", "LO", "U", "D"]
        let claude = [" HE", "Y", " C", "LA", "U", "DE"]
        XCTAssertEqual(WakeEnrollment.derivedLines(isolated: [cloud, claude]),
                       ["▁HE Y ▁C LO U D", "▁HE Y ▁C LA U DE"])
    }

    // MARK: - Orchestration (mock decode + fires)

    private func sample(_ kind: WakeEnrollment.Sample.Kind, _ tag: Float) -> WakeEnrollment.Sample {
        .init(audio: [tag], kind: kind)   // audio content is opaque to the mock
    }

    func test_enroll_derivesKeyword_firesAtTopThreshold() {
        let enroll = WakeEnrollment(
            decode: { _ in [" HE", "Y", " C", "LO", "U", "D"] },
            fires: { _, _, _ in true })
        let r = enroll.enroll(samples: [sample(.isolated, 1), sample(.isolated, 2), sample(.natural, 3)])
        XCTAssertEqual(r.keywordLines, ["▁HE Y ▁C LO U D", "▁HE Y ▁C LA U DE"]) // derived + fallback
        XCTAssertEqual(r.threshold, 0.25)        // highest threshold that fires all
        XCTAssertTrue(r.allFired)
        XCTAssertFalse(r.usedFallbackOnly)
    }

    func test_enroll_tunesThresholdDownUntilAllFire() {
        // Only fires once threshold drops to <= 0.15 (e.g. the natural clip is hard).
        let enroll = WakeEnrollment(
            decode: { _ in [" HE", "Y", " C", "LO", "U", "D"] },
            fires: { _, t, _ in t <= 0.15 })
        let r = enroll.enroll(samples: [sample(.isolated, 1), sample(.isolated, 2), sample(.natural, 3)])
        XCTAssertEqual(r.threshold, 0.15)
        XCTAssertTrue(r.allFired)
    }

    func test_enroll_fallbackOnly_whenDecodeYieldsNothing() {
        let enroll = WakeEnrollment(
            decode: { _ in [] },                 // model emitted nothing usable
            fires: { lines, _, _ in lines == ["▁HE Y ▁C LA U DE"] })
        let r = enroll.enroll(samples: [sample(.isolated, 1), sample(.isolated, 2)])
        XCTAssertEqual(r.keywordLines, ["▁HE Y ▁C LA U DE"])   // fallback only
        XCTAssertTrue(r.usedFallbackOnly)
    }

    func test_enroll_reportsNotAllFired_whenNothingWorks() {
        let enroll = WakeEnrollment(decode: { _ in [" C", "LO", "U", "D"] },
                                    fires: { _, _, _ in false })
        let r = enroll.enroll(samples: [sample(.isolated, 1), sample(.natural, 2)])
        XCTAssertFalse(r.allFired)
        XCTAssertEqual(r.threshold, 0.10)        // fell through to the lowest
    }
}
