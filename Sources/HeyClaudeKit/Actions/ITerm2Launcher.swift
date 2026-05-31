import AppKit
import Foundation

public struct ITerm2Launcher: TerminalLauncher {
    public init() {}

    public func isAvailable() -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.googlecode.iterm2") != nil
    }

    public static func appleScript(for spec: LaunchSpec) -> String {
        let cmd = spec.appleScriptLiteral()
        // Cold-launch double-window fix: iTerm opens a window on launch, so
        // unconditionally creating one yields TWO windows when iTerm wasn't
        // already running. Capture `wasRunning` BEFORE `activate` (which
        // launches it); when cold, reuse the launch window instead of making a
        // second. The bounded wait handles window-restoration latency, and the
        // fallback `create window` covers users who disabled the launch window.
        return """
        set wasRunning to application "iTerm" is running
        tell application "iTerm"
            activate
            if wasRunning then
                set targetWindow to (create window with default profile)
            else
                set waited to 0
                repeat until (count of windows) > 0 or waited > 40
                    delay 0.05
                    set waited to waited + 1
                end repeat
                if (count of windows) > 0 then
                    set targetWindow to current window
                else
                    set targetWindow to (create window with default profile)
                end if
            end if
            tell current session of targetWindow to write text "\(cmd)"
        end tell
        """
    }

    public func launch(_ spec: LaunchSpec) throws {
        guard isAvailable() else { throw TerminalLaunchError.notInstalled }
        try AppleScriptRunner.run(ITerm2Launcher.appleScript(for: spec))
    }
}
