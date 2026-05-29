import XCTest
@testable import HeyClaudeKit

final class ActionExecutorTests: XCTestCase {
    final class MockLauncher: TerminalLauncher, @unchecked Sendable {
        var launched: [LaunchSpec] = []
        var available = true
        func isAvailable() -> Bool { available }
        func launch(_ spec: LaunchSpec) throws { launched.append(spec) }
    }

    func test_launchCLI_noPrompt_buildsSpecFromSettings() throws {
        let mock = MockLauncher()
        var s = Settings.default
        s.projectDirectory = "/tmp/proj"
        s.claudeExecutable = "claude"
        let exec = ActionExecutor(settings: s, launcher: mock, openDesktopApp: { XCTFail("no app") })
        try exec.execute(.launchCLI(prompt: nil))
        XCTAssertEqual(mock.launched.count, 1)
        XCTAssertEqual(mock.launched[0], LaunchSpec(directory: "/tmp/proj", executable: "claude", prompt: nil))
    }

    func test_launchCLI_withPrompt() throws {
        let mock = MockLauncher()
        let exec = ActionExecutor(settings: .default, launcher: mock, openDesktopApp: {})
        try exec.execute(.launchCLI(prompt: "fix the bug"))
        XCTAssertEqual(mock.launched[0].prompt, "fix the bug")
    }

    func test_openDesktopApp_callsHook_notLauncher() throws {
        let mock = MockLauncher()
        var opened = false
        let exec = ActionExecutor(settings: .default, launcher: mock, openDesktopApp: { opened = true })
        try exec.execute(.openDesktopApp)
        XCTAssertTrue(opened)
        XCTAssertTrue(mock.launched.isEmpty)
    }
}
