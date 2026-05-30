import XCTest
@testable import HeyClaudeKit

final class EditorRoutingTests: XCTestCase {

    // MARK: DeepLinkBuilder

    func test_deepLink_encodesPromptAndStructure() {
        let url = DeepLinkBuilder.url(editor: .cursor, integration: .claudeCode,
                                      prompt: "fix the bug — now 🚀")
        XCTAssertEqual(url.scheme, "cursor")
        XCTAssertEqual(url.host, "anthropic.claude-code")
        XCTAssertEqual(url.path, "/open")
        XCTAssertEqual(url.absoluteString,
                       "cursor://anthropic.claude-code/open?prompt=fix%20the%20bug%20%E2%80%94%20now%20%F0%9F%9A%80")
    }

    func test_deepLink_noPrompt_hasNoQuery() {
        let url = DeepLinkBuilder.url(editor: .vscode, integration: .claudeCode, prompt: nil)
        XCTAssertEqual(url.absoluteString, "vscode://anthropic.claude-code/open")
    }

    func test_deepLink_emptyPrompt_hasNoQuery() {
        let url = DeepLinkBuilder.url(editor: .vscode, integration: .claudeCode, prompt: "")
        XCTAssertEqual(url.absoluteString, "vscode://anthropic.claude-code/open")
    }

    // MARK: LaunchTarget Codable

    func test_launchTarget_roundTrips() throws {
        for t: LaunchTarget in [.terminal(.iterm2), .terminal(.ghostty), .editor(.cursor), .editor(.antigravity)] {
            let data = try JSONEncoder().encode(t)
            XCTAssertEqual(try JSONDecoder().decode(LaunchTarget.self, from: data), t)
        }
    }

    // MARK: DefaultTargetResolver

    func test_resolver_oneActiveEditor_picksEditor() {
        let target = DefaultTargetResolver.resolve(
            candidates: [.cursor, .vscode], active: [.cursor])
        XCTAssertEqual(target, .editor(.cursor))
    }

    func test_resolver_noActiveEditor_picksTerminal() {
        let target = DefaultTargetResolver.resolve(
            candidates: [.cursor, .vscode], active: [])
        XCTAssertEqual(target, .terminal(.terminalApp))
    }

    func test_resolver_multipleActive_picksTerminal() {
        let target = DefaultTargetResolver.resolve(
            candidates: [.cursor, .vscode], active: [.cursor, .vscode])
        XCTAssertEqual(target, .terminal(.terminalApp))
    }

    func test_resolver_activeButNotCandidate_picksTerminal() {
        // editor in use but extension not installed → not a candidate → Terminal
        let target = DefaultTargetResolver.resolve(
            candidates: [.vscode], active: [.cursor])
        XCTAssertEqual(target, .terminal(.terminalApp))
    }

    func test_activeEditors_mapsIdeNames() {
        let active = DefaultTargetResolver.activeEditors(
            fromIdeNames: ["Cursor", "Visual Studio Code"], among: [.cursor, .vscode, .antigravity])
        XCTAssertEqual(active, [.cursor, .vscode])
    }

    // MARK: EditorAvailability (temp home)

    func test_availability_appAndExtensionPresent() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("hc-avail-\(ProcessInfo.processInfo.globallyUniqueString)")
        let cursorExt = home.appendingPathComponent(".cursor/extensions/anthropic.claude-code-2.1.0")
        try FileManager.default.createDirectory(at: cursorExt, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let avail = EditorAvailability(home: home, appInstalled: { $0 == EditorKind.cursor.bundleID })
        XCTAssertTrue(avail.isReady(.cursor, integration: .claudeCode))
        XCTAssertFalse(avail.isReady(.vscode, integration: .claudeCode))   // app not installed + no ext
        XCTAssertEqual(avail.readyEditors(integration: .claudeCode), [.cursor])
    }

    func test_availability_appInstalledButExtensionMissing_notReady() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("hc-avail-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".antigravity/extensions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        // Antigravity installed, but no Claude Code extension folder → not ready.
        let avail = EditorAvailability(home: home, appInstalled: { _ in true })
        XCTAssertFalse(avail.isReady(.antigravity, integration: .claudeCode))
    }
}
