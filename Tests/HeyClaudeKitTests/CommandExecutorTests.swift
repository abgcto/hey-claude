import XCTest
@testable import HeyClaudeKit

final class CommandExecutorTests: XCTestCase {
    final class MockLauncher: TerminalLauncher, @unchecked Sendable {
        var launched: [LaunchSpec] = []
        func isAvailable() -> Bool { true }
        func launch(_ spec: LaunchSpec) throws { launched.append(spec) }
    }

    private func exec(_ mock: MockLauncher, openedApps: @escaping (String) -> Void = { _ in },
                      ranShell: @escaping (String) -> Void = { _ in }) -> CommandExecutor {
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
        var opened: String?
        try exec(MockLauncher(), openedApps: { opened = $0 })
            .execute(Command(id: "a", label: "App", triggers: [], kind: .openApp(bundleID: "com.x.y")), prompt: nil)
        XCTAssertEqual(opened, "com.x.y")
    }
    func test_runShell_callsRunWithScript() throws {
        var ran: String?
        try exec(MockLauncher(), ranShell: { ran = $0 })
            .execute(Command(id: "s", label: "Sh", triggers: ["t"], kind: .runShell(script: "npm test")), prompt: nil)
        XCTAssertEqual(ran, "npm test")
    }
}
