import AppKit
import Foundation

public struct ITerm2Launcher: TerminalLauncher {
    public init() {}

    public func isAvailable() -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.googlecode.iterm2") != nil
    }

    public static func appleScript(for spec: LaunchSpec) -> String {
        let cmd = spec.shellCommand().replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "\(cmd)"
            end tell
        end tell
        """
    }

    public func launch(_ spec: LaunchSpec) throws {
        guard isAvailable() else { throw TerminalLaunchError.notInstalled }
        try AppleScriptRunner.run(ITerm2Launcher.appleScript(for: spec))
    }
}
