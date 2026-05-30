import XCTest
@testable import HeyClaudeKit

final class CommandExecutorTests: XCTestCase {
    final class MockLauncher: TerminalLauncher, @unchecked Sendable {
        var launched: [LaunchSpec] = []
        func isAvailable() -> Bool { true }
        func launch(_ spec: LaunchSpec) throws { launched.append(spec) }
    }

    private func exec(_ mock: MockLauncher, openedApps: @escaping @Sendable (String) -> Void = { _ in },
                      ranShell: @escaping @Sendable (String) -> Void = { _ in }) -> CommandExecutor {
        CommandExecutor(settings: .default, launcherFor: { _ in mock },
                        openApp: openedApps, runShell: ranShell)
    }

    func test_runCLI_substitutesPrompt() throws {
        let mock = MockLauncher()
        let cmd = Command(id: "c", label: "Code", triggers: ["code"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"), acceptsPrompt: true)
        try exec(mock).execute(cmd, prompt: "fix the bug")
        XCTAssertEqual(mock.launched.first?.shellCommand().contains("claude 'fix the bug'"), true)
    }
    func test_runCLI_noPrompt_dropsPlaceholder() throws {
        let mock = MockLauncher()
        let cmd = Command(id: "c", label: "Code", triggers: ["code"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"), acceptsPrompt: true)
        try exec(mock).execute(cmd, prompt: nil)
        let sh = mock.launched.first!.shellCommand()
        XCTAssertTrue(sh.contains("claude") && !sh.contains("{prompt}") && !sh.contains("''"))
    }
    func test_openApp_callsOpenWithBundleID() throws {
        let opened = Box<String?>(nil)
        try exec(MockLauncher(), openedApps: { opened.value = $0 })
            .execute(Command(id: "a", label: "App", triggers: [], kind: .openApp(bundleID: "com.x.y")), prompt: nil)
        XCTAssertEqual(opened.value, "com.x.y")
    }
    func test_runShell_callsRunWithScript() throws {
        let ran = Box<String?>(nil)
        try exec(MockLauncher(), ranShell: { ran.value = $0 })
            .execute(Command(id: "s", label: "Sh", triggers: ["t"], kind: .runShell(script: "npm test")), prompt: nil)
        XCTAssertEqual(ran.value, "npm test")
    }

    func test_runCLI_editorTarget_opensDeepLinkInsteadOfTerminal() throws {
        let mock = MockLauncher()
        let opened = Box<URL?>(nil)
        let executor = CommandExecutor(settings: .default, launcherFor: { _ in mock },
                                       openURL: { opened.value = $0 })
        let cmd = Command(id: "claude-code", label: "Claude Code", triggers: ["code"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"),
                          target: .editor(.cursor), acceptsPrompt: true,
                          editorIntegration: .claudeCode)
        try executor.execute(cmd, prompt: "fix the bug")
        XCTAssertTrue(mock.launched.isEmpty)   // no terminal launched
        XCTAssertEqual(opened.value?.absoluteString,
                       "cursor://anthropic.claude-code/open?prompt=fix%20the%20bug")
    }

    func test_runCLI_editorTarget_missingIntegration_fallsBackToTerminal() throws {
        let mock = MockLauncher()
        let opened = Box<URL?>(nil)
        let executor = CommandExecutor(settings: .default, launcherFor: { _ in mock },
                                       openURL: { opened.value = $0 })
        let cmd = Command(id: "x", label: "X", triggers: ["x"],
                          kind: .runCLI(commandTemplate: "claude {prompt}"),
                          target: .editor(.cursor), acceptsPrompt: true,
                          editorIntegration: nil)   // no editor integration
        try executor.execute(cmd, prompt: "hi")
        XCTAssertNil(opened.value)                 // no deep link
        XCTAssertEqual(mock.launched.count, 1)     // terminal fallback used
    }
}
