import AppKit
import Foundation

/// Opens a new terminal panel inside the running Cursor editor and runs the
/// command there. Requires Cursor to already be open (we never cold-launch it
/// — that would open an empty window with no workspace context).
///
/// Uses the "Terminal › New Terminal" menu item rather than a keyboard shortcut
/// so it works regardless of the user's key-binding configuration.
/// Requires Accessibility permission (same as GhosttyLauncher).
public struct CursorTerminalLauncher: TerminalLauncher {
    public init() {}

    public func isAvailable() -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.todesktop.230313mzl4w4u92") != nil
    }

    public static func appleScript(for spec: LaunchSpec) -> String {
        let cmd = spec.appleScriptLiteral()
        // Activate Cursor via System Events (no direct Apple Events to Cursor needed,
        // avoiding a separate Automation grant for com.todesktop.230313mzl4w4u92).
        return """
        tell application "System Events"
            set frontmost of (first application process whose bundle identifier is "com.todesktop.230313mzl4w4u92") to true
            delay 0.3
            tell process "Cursor"
                click menu item "New Terminal" of menu "Terminal" of menu bar 1
                delay 0.8
                keystroke "u" using {control down}
                keystroke "\(cmd)"
                key code 36
            end tell
        end tell
        """
    }

    public func launch(_ spec: LaunchSpec) throws {
        guard isAvailable() else { throw TerminalLaunchError.notInstalled }
        // Cursor must already be running — opening it cold would produce an
        // empty window with no workspace, making `cd <dir>` the wrong context.
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.todesktop.230313mzl4w4u92"
        }) else {
            throw TerminalLaunchError.automationFailed("Cursor is not running")
        }
        try AppleScriptRunner.run(CursorTerminalLauncher.appleScript(for: spec))
    }
}
