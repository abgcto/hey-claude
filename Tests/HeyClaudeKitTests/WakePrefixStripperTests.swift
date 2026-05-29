import XCTest
@testable import HeyClaudeKit

final class WakePrefixStripperTests: XCTestCase {
    func test_bareWake_returnsNil() {
        XCTAssertNil(WakePrefixStripper.command(from: "hey claude"))
        XCTAssertNil(WakePrefixStripper.command(from: "hey cloud."))
        XCTAssertNil(WakePrefixStripper.command(from: "cl hey cloud."))
    }
    func test_codeCommand() {
        XCTAssertEqual(WakePrefixStripper.command(from: "hey, cloud code."), "code")
        XCTAssertEqual(WakePrefixStripper.command(from: "hey claude code"), "code")
    }
    func test_multiWordPrompt() {
        XCTAssertEqual(
            WakePrefixStripper.command(from: "hey claude refactor the auth module"),
            "refactor the auth module")
    }
    func test_claudeVariantsStripped() {
        XCTAssertEqual(WakePrefixStripper.command(from: "hey claud open the app"), "open the app")
        XCTAssertEqual(WakePrefixStripper.command(from: "hey clawed code"), "code")
    }
}
