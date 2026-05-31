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

    func test_deepLink_encodesQueryDelimiters_soPromptSurvivesRoundTrip() {
        // Regression guard for the URLComponents footgun: query-delimiter chars
        // (& # =) MUST be percent-encoded in the value, else the receiving editor
        // parses a truncated/second param. URLQueryItem does this correctly;
        // switching to `percentEncodedQuery` would silently break it.
        for prompt in ["rock & roll", "issue #42", "set a=b", "a & b # c = d"] {
            let url = DeepLinkBuilder.url(editor: .cursor, integration: .claudeCode, prompt: prompt)
            let echoed = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "prompt" }?.value
            XCTAssertEqual(echoed, prompt, "prompt did not survive round-trip: \(url.absoluteString)")
            XCTAssertFalse(url.absoluteString.contains("prompt=rock & roll"))   // not left raw
        }
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

    func test_availability_installedMissingExtension_drivesDisabledPickerRows() throws {
        // The onboarding picker shows editors that are installed but lack the
        // tool extension as *disabled* rows. cursor has the ext (ready);
        // antigravity is installed without it (disabled); vscode isn't installed
        // at all (absent). This split is `installedMissingExtension` vs `readyEditors`.
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("hc-avail-\(ProcessInfo.processInfo.globallyUniqueString)")
        let cursorExt = home.appendingPathComponent(".cursor/extensions/anthropic.claude-code-2.1.0")
        try FileManager.default.createDirectory(at: cursorExt, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".antigravity/extensions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let avail = EditorAvailability(
            home: home,
            appInstalled: { $0 == EditorKind.cursor.bundleID || $0 == EditorKind.antigravity.bundleID })

        XCTAssertEqual(avail.readyEditors(integration: .claudeCode), [.cursor])
        XCTAssertEqual(avail.installedMissingExtension(integration: .claudeCode), [.antigravity])
    }
}
