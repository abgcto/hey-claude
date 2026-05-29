import XCTest
@testable import HeyClaudeKit

final class RecentActionsTests: XCTestCase {
    func test_recordsLabelAndDirectory_notTranscript() {
        let log = RecentActions(capacity: 5)
        log.record(label: "Claude Code", directory: "/tmp/app", at: 100)
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries[0].label, "Claude Code")
        XCTAssertEqual(log.entries[0].directory, "/tmp/app")
        // The transcript must NOT be stored anywhere on the entry.
        XCTAssertFalse(log.entries[0].label.contains("refactor"))
    }

    func test_capacityEvictsOldest_newestFirst() {
        let log = RecentActions(capacity: 2)
        log.record(label: "Claude Code", directory: "/a", at: 1)
        log.record(label: "Claude Code", directory: "/b", at: 2)
        log.record(label: "Claude Code", directory: "/c", at: 3)
        XCTAssertEqual(log.entries.map(\.directory), ["/c", "/b"])   // newest first, oldest evicted
    }
}
