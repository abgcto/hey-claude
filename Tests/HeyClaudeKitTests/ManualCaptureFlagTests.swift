import XCTest
@testable import HeyClaudeKit

final class ManualCaptureFlagTests: XCTestCase {
    func test_defaultsInactive() {
        let flag = ManualCaptureFlag()
        XCTAssertFalse(flag.active)
        XCTAssertFalse(flag.shouldCancel)
    }

    func test_pressActivates_releaseDeactivates_noCancel() {
        let flag = ManualCaptureFlag()
        flag.press()
        XCTAssertTrue(flag.active)
        XCTAssertFalse(flag.shouldCancel)
        flag.release()
        XCTAssertFalse(flag.active)
        XCTAssertFalse(flag.shouldCancel, "a normal release must NOT set cancel (the clip is sent)")
    }

    func test_cancelDeactivatesAndSetsCancel() {
        let flag = ManualCaptureFlag()
        flag.press()
        flag.cancel()
        XCTAssertFalse(flag.active)
        XCTAssertTrue(flag.shouldCancel, "Esc cancel must set the discard bit")
    }

    func test_pressClearsAPriorCancel() {
        let flag = ManualCaptureFlag()
        flag.cancel()
        XCTAssertTrue(flag.shouldCancel)
        flag.press()
        XCTAssertTrue(flag.active)
        XCTAssertFalse(flag.shouldCancel, "a fresh press resets the lingering cancel bit")
    }

    func test_concurrentAccessIsSafe() {
        let flag = ManualCaptureFlag()
        let exp = expectation(description: "no crash under concurrent r/w")
        exp.expectedFulfillmentCount = 2
        DispatchQueue.global().async { for _ in 0..<100_000 { flag.press(); flag.release() }; exp.fulfill() }
        DispatchQueue.global().async { for _ in 0..<100_000 { _ = flag.active; _ = flag.shouldCancel }; exp.fulfill() }
        wait(for: [exp], timeout: 10)
    }
}
