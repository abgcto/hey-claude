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

    func test_defaultSettings_seedChatVsCode() {
        let s = Settings.default
        XCTAssertEqual(s.defaultCommandID, "claude-desktop")   // "hey claude" → desktop
        XCTAssertEqual(s.promptCommandID, "claude-code")        // prompts → code
        XCTAssertTrue(s.commands.contains { $0.id == "claude-code" })
    }

    func test_decodingLegacyBlob_missingCommands_fallsBackToSeeded() throws {
        let legacy = #"{"projectDirectory":"/tmp","preferredTerminal":"iTerm2","wakeKeywordsScore":2,"wakeKeywordsThreshold":0.25,"cooldownSeconds":2,"claudeExecutable":"claude"}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertFalse(s.commands.isEmpty)        // seeded, not empty
        XCTAssertEqual(s.defaultCommandID, "claude-desktop")
    }
}
