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

    // MARK: cold-launch double-window regression
    //
    // When the terminal app was not already running, launching it auto-opens a
    // window; the old scripts then unconditionally opened a SECOND one. The fix
    // captures `wasRunning` before `activate` and, when cold, reuses the launch
    // window. Verified live for iTerm (cold 2→1 windows); these pin the script
    // structure so the guard can't be refactored away.

    private func spec() -> LaunchSpec {
        LaunchSpec(directory: "/tmp", executable: "claude", prompt: nil)
    }

    func test_iterm2_gatesWindowCreationOnWasRunning() {
        let script = ITerm2Launcher.appleScript(for: spec())
        // wasRunning must be read BEFORE the tell-block's activate launches iTerm.
        let setIdx = script.range(of: #"set wasRunning to application "iTerm" is running"#)
        let tellIdx = script.range(of: #"tell application "iTerm""#)
        XCTAssertNotNil(setIdx)
        XCTAssertNotNil(tellIdx)
        if let s = setIdx, let t = tellIdx { XCTAssertTrue(s.lowerBound < t.lowerBound) }
    }

    func test_iterm2_coldBranchReusesLaunchWindow_warmBranchCreatesWindow() {
        let script = ITerm2Launcher.appleScript(for: spec())
        XCTAssertTrue(script.contains("set targetWindow to current window"),       // cold: reuse
                      script)
        XCTAssertTrue(script.contains("create window with default profile"),       // warm: new
                      script)
    }

    func test_terminalApp_gatesWindowCreationOnWasRunning() {
        let script = TerminalAppLauncher.appleScript(for: spec())
        let setIdx = script.range(of: #"set wasRunning to application "Terminal" is running"#)
        let tellIdx = script.range(of: #"tell application "Terminal""#)
        XCTAssertNotNil(setIdx)
        XCTAssertNotNil(tellIdx)
        if let s = setIdx, let t = tellIdx { XCTAssertTrue(s.lowerBound < t.lowerBound) }
    }

    func test_terminalApp_coldBranchTargetsLaunchWindow() {
        // `do script … in window 1` reuses Terminal's auto-opened launch window;
        // a bare `do script …` (warm branch) opens a fresh window on purpose.
        let script = TerminalAppLauncher.appleScript(for: spec())
        XCTAssertTrue(script.contains(#"in window 1"#), script)
    }
}
