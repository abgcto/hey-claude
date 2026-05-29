import XCTest
@testable import HeyClaudeKit

final class TerminalLauncherTests: XCTestCase {
    func test_shellCommand_noPrompt() {
        let spec = LaunchSpec(directory: "/Users/me/proj", executable: "claude", prompt: nil)
        XCTAssertEqual(spec.shellCommand(), "cd '/Users/me/proj' && claude")
    }
    func test_shellCommand_withPrompt() {
        let spec = LaunchSpec(directory: "/tmp", executable: "claude",
                              prompt: "refactor the auth module")
        XCTAssertEqual(spec.shellCommand(),
                       "cd '/tmp' && claude 'refactor the auth module'")
    }
    func test_shellCommand_escapesSingleQuotes() {
        let spec = LaunchSpec(directory: "/tmp/it's mine", executable: "claude",
                              prompt: "don't break")
        XCTAssertEqual(spec.shellCommand(),
                       "cd '/tmp/it'\\''s mine' && claude 'don'\\''t break'")
    }
    func test_iterm2_appleScript_containsCommandAndCreatesWindow() {
        let script = ITerm2Launcher.appleScript(for:
            LaunchSpec(directory: "/tmp", executable: "claude", prompt: nil))
        XCTAssertTrue(script.contains("create window with default profile"))
        XCTAssertTrue(script.contains("cd '/tmp' && claude"))
    }
    func test_terminalApp_appleScript_doScript() {
        let script = TerminalAppLauncher.appleScript(for:
            LaunchSpec(directory: "/tmp", executable: "claude", prompt: nil))
        XCTAssertTrue(script.contains("do script"))
        XCTAssertTrue(script.contains("cd '/tmp' && claude"))
    }
}
