import XCTest
@testable import HeyClaudeKit

final class AppStateTests: XCTestCase {
    func test_startsArmed() {
        XCTAssertEqual(AppStateMachine().state, .armed)
    }
    func test_wakeGoesHot_thenWorking_thenSettlesArmed() {
        let m = AppStateMachine()
        m.apply(.wakeFired);       XCTAssertEqual(m.state, .hot)
        m.apply(.launching);       XCTAssertEqual(m.state, .working)
        m.apply(.settled);         XCTAssertEqual(m.state, .armed)
    }
    func test_muteIsStickyAndOverrides() {
        let m = AppStateMachine()
        m.apply(.muted);           XCTAssertEqual(m.state, .muted)
        m.apply(.wakeFired);       XCTAssertEqual(m.state, .muted)   // ignored while muted
        m.apply(.unmuted);         XCTAssertEqual(m.state, .armed)
    }
    func test_callPauseIsTemporary_resumesToArmed() {
        let m = AppStateMachine()
        m.apply(.callPaused);      XCTAssertEqual(m.state, .paused)
        m.apply(.callResumed);     XCTAssertEqual(m.state, .armed)
    }
    func test_micDeniedIsOff() {
        let m = AppStateMachine()
        m.apply(.micDenied);       XCTAssertEqual(m.state, .off)
    }
    func test_lastHeard_capturedOnReveal() {
        let m = AppStateMachine()
        m.apply(.wakeFired)
        m.apply(.heard("refactor the auth module"))
        XCTAssertEqual(m.lastHeard, "refactor the auth module")
    }
}
