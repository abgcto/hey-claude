import AppKit
import Foundation

public struct TerminalAppLauncher: TerminalLauncher {
    public init() {}

    public func isAvailable() -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal") != nil
    }

    /// AppleScript that opens Terminal and runs the command in a new tab/window.
    public static func appleScript(for spec: LaunchSpec) -> String {
        let cmd = spec.shellCommand().replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Terminal"
            activate
            do script "\(cmd)"
        end tell
        """
    }

    public func launch(_ spec: LaunchSpec) throws {
        guard isAvailable() else { throw TerminalLaunchError.notInstalled }
        try AppleScriptRunner.run(TerminalAppLauncher.appleScript(for: spec))
    }
}
