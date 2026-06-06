import AppKit
import Foundation

/// Ghostty has limited AppleEvents support (spec §6). Strategy: open the app,
/// then deliver the command via the clipboard + a keystroke fallback. Best
/// effort; degrades to "opened, command not auto-run" rather than crashing.
public struct GhosttyLauncher: TerminalLauncher {
    public init() {}

    public func isAvailable() -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.mitchellh.ghostty") != nil
    }

    public func launch(_ spec: LaunchSpec) throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.mitchellh.ghostty")
        else { throw TerminalLaunchError.notInstalled }
        // Open a new Ghostty window, then type the command via System Events.
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, _ in }
        // Keystroke fallback documented in build notes; requires Accessibility perm.
        try AppleScriptRunner.run(GhosttyLauncher.keystrokeScript(for: spec))
    }

    public static func keystrokeScript(for spec: LaunchSpec) -> String {
        let cmd = spec.appleScriptLiteral()
        return """
        delay 0.5
        tell application "System Events"
            keystroke "u" using {control down}
            keystroke "\(cmd)"
            key code 36
        end tell
        """
    }
}
