import XCTest
@testable import HeyClaudeKit

final class RecentActionsTests: XCTestCase {
    func test_recordsActionTypeNotTranscript() {
        let log = RecentActions(capacity: 5)
        log.record(.launchCLI(prompt: "refactor the auth module"), directory: "/tmp/app", at: 100)
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries[0].label, "Launched Claude")
        XCTAssertEqual(log.entries[0].directory, "/tmp/app")
        // The transcript must NOT be stored anywhere on the entry.
        XCTAssertFalse(log.entries[0].label.contains("refactor"))
    }
    func test_openDesktopLabel() {
        let log = RecentActions(capacity: 5)
        log.record(.openDesktopApp, directory: nil, at: 100)
        XCTAssertEqual(log.entries[0].label, "Opened Claude Desktop")
    }
    func test_capacityEvictsOldest_newestFirst() {
        let log = RecentActions(capacity: 2)
        log.record(.launchCLI(prompt: nil), directory: "/a", at: 1)
        log.record(.launchCLI(prompt: nil), directory: "/b", at: 2)
        log.record(.launchCLI(prompt: nil), directory: "/c", at: 3)
        XCTAssertEqual(log.entries.map(\.directory), ["/c", "/b"])   // newest first, oldest evicted
    }
}
