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
        s.preferredTarget = .editor(.cursor)
        s.cooldownSeconds = 3.5
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func test_defaultSettings_areClaudeCodeOnly() {
        let s = Settings.default
        XCTAssertEqual(s.defaultCommandID, "claude-code")   // bare "hey claude" → code
        XCTAssertEqual(s.promptCommandID, "claude-code")     // prompts → code
        XCTAssertEqual(s.preferredTarget, .terminal(.terminalApp))
        XCTAssertTrue(s.commands.contains { $0.id == "claude-code" })
    }

    func test_decodingLegacyBlob_missingCommands_fallsBackToSeeded() throws {
        let legacy = #"{"projectDirectory":"/tmp","preferredTerminal":"iTerm2","wakeKeywordsScore":2,"wakeKeywordsThreshold":0.25,"cooldownSeconds":2,"claudeExecutable":"claude"}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertFalse(s.commands.isEmpty)                       // seeded, not empty
        XCTAssertEqual(s.defaultCommandID, "claude-code")        // migrated
        XCTAssertEqual(s.preferredTarget, .terminal(.iterm2))    // preferredTerminal → preferredTarget
    }

    func test_decodingLegacyBlob_dropsClaudeDesktopRouting() throws {
        // A settings file from before Claude-Code-only: bare wake → desktop app.
        let legacy = """
        {"projectDirectory":"/tmp","preferredTerminal":"Terminal","wakeKeywordsScore":2,\
        "wakeKeywordsThreshold":0.25,"cooldownSeconds":2,"claudeExecutable":"claude",\
        "defaultCommandID":"claude-desktop","promptCommandID":"claude-code",\
        "commands":[\
        {"id":"claude-desktop","label":"Claude desktop","triggers":[],"kind":{"openApp":{"bundleID":"com.anthropic.claudefordesktop"}},"acceptsPrompt":false},\
        {"id":"claude-code","label":"Claude Code","triggers":["code"],"kind":{"runCLI":{"commandTemplate":"claude {prompt}"}},"acceptsPrompt":true}\
        ]}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.defaultCommandID, "claude-code")               // remapped
        XCTAssertFalse(s.commands.contains { $0.id == "claude-desktop" }) // dropped
        XCTAssertTrue(s.commands.contains { $0.id == "claude-code" })
    }

    func test_saveThenLoad_roundTripsMascotFields() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)
        var s = Settings.default
        s.mascotID = "birthday"
        s.mascotColorHex = "#86A886"
        try store.save(s)
        let loaded = store.load()
        XCTAssertEqual(loaded.mascotID, "birthday")
        XCTAssertEqual(loaded.mascotColorHex, "#86A886")
        XCTAssertEqual(loaded, s)
    }

    func test_decodingBlob_withoutMascotKeys_yieldsDefaults() throws {
        // A settings file from before mascot customization existed.
        let legacy = #"{"projectDirectory":"/tmp","preferredTerminal":"Terminal","wakeKeywordsScore":2,"wakeKeywordsThreshold":0.25,"cooldownSeconds":2,"claudeExecutable":"claude"}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.mascotID, "classic")
        XCTAssertEqual(s.mascotColorHex, "#D87757")
    }

    func test_decodingLegacyBlob_backfillsEditorIntegration() throws {
        // claude-code persisted before `editorIntegration` existed → must be
        // backfilled, else an editor target silently falls back to a terminal.
        let legacy = #"{"projectDirectory":"/tmp","preferredTarget":{"type":"editor","value":"Cursor"},"wakeKeywordsScore":2,"wakeKeywordsThreshold":0.25,"cooldownSeconds":2,"claudeExecutable":"claude","defaultCommandID":"claude-code","promptCommandID":"claude-code","commands":[{"acceptsPrompt":true,"id":"claude-code","kind":{"runCLI":{"commandTemplate":"claude {prompt}"}},"label":"Claude Code","triggers":["code"]}]}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.commands.first { $0.id == "claude-code" }?.editorIntegration, .claudeCode)
    }

    func test_saveThenLoad_roundTripsMascotIdleAnimations() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)
        var s = Settings.default
        s.mascotIdleAnimations = false
        try store.save(s)
        XCTAssertEqual(store.load().mascotIdleAnimations, false)
        XCTAssertEqual(store.load(), s)
    }

    func test_decodingBlob_withoutMascotIdleAnimations_defaultsTrue() throws {
        // A settings file from before the idle-animation toggle existed → default ON.
        let legacy = #"{"projectDirectory":"/tmp","preferredTerminal":"Terminal","wakeKeywordsScore":2,"wakeKeywordsThreshold":0.25,"cooldownSeconds":2,"claudeExecutable":"claude"}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        XCTAssertTrue(s.mascotIdleAnimations)
    }
}
