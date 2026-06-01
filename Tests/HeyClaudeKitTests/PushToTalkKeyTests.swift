import XCTest
@testable import HeyClaudeKit

final class PushToTalkKeyTests: XCTestCase {
    func test_rightOption_isBareModifier_withCorrectKeycode() {
        let k = PushToTalkKey.rightOption
        XCTAssertEqual(k.keycode, 61)          // kVK_RightOption
        XCTAssertTrue(k.isBareModifier)         // no consume needed; types nothing
        XCTAssertEqual(k.requiredModifierFlag, .maskAlternate)
        XCTAssertTrue(k.secondaryModifierFlag == nil)
    }

    func test_controlOption_isChord_withTwoFlags() {
        let k = PushToTalkKey.controlOption
        XCTAssertFalse(k.isBareModifier)
        XCTAssertEqual(k.requiredModifierFlag, .maskControl)
        XCTAssertEqual(k.secondaryModifierFlag, .maskAlternate)
    }

    func test_isCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(PushToTalkKey.rightCommand)
        XCTAssertEqual(try JSONDecoder().decode(PushToTalkKey.self, from: data), .rightCommand)
    }
}
