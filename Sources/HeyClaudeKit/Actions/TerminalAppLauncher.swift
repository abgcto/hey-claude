import AppKit
import Foundation

public struct TerminalAppLauncher: TerminalLauncher {
    public init() {}

    public func isAvailable() -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal") != nil
    }

    /// AppleScript that opens Terminal and runs the command in a single window.
    ///
    /// Cold-launch double-window fix: Terminal opens a default window on launch,
    /// and `do script` *always* opens another window unless targeted with
    /// `in window`. Cold-launching therefore produced TWO windows. We capture
    /// `wasRunning` BEFORE `activate` (which launches Terminal); when cold, run
    /// the command `in window 1` — the window Terminal just opened — instead of
    /// spawning a second. When already running, a fresh window is the intended
    /// behaviour (don't hijack the user's existing session).
    public static func appleScript(for spec: LaunchSpec) -> String {
        let cmd = spec.appleScriptLiteral()
        return """
        set wasRunning to application "Terminal" is running
        tell application "Terminal"
            activate
            if wasRunning then
                do script "\(cmd)"
            else
                set waited to 0
                repeat until (count of windows) > 0 or waited > 40
                    delay 0.05
                    set waited to waited + 1
                end repeat
                if (count of windows) > 0 then
                    do script "\(cmd)" in window 1
                else
                    do script "\(cmd)"
                end if
            end if
        end tell
        """
    }

    public func launch(_ spec: LaunchSpec) throws {
        guard isAvailable() else { throw TerminalLaunchError.notInstalled }
        try AppleScriptRunner.run(TerminalAppLauncher.appleScript(for: spec))
    }
}
