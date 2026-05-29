import XCTest
@testable import HeyClaudeKit

final class SettingsStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("heyclaude-test-\(ProcessInfo.processInfo.globallyUniqueString).json")
    }

    func test_loadReturnsDefaultWhenMissing() throws {
        let store = SettingsStore(fileURL: tempURL())
        XCTAssertEqual(store.load(), .default)
    }

    func test_saveThenLoadRoundTrips() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)
        var s = Settings.default
        s.projectDirectory = "/tmp/proj"
        s.preferredTerminal = .iterm2
        s.cooldownSeconds = 3.5
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }
}
