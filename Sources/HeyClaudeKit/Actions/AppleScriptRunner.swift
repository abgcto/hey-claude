import Foundation

/// Runs AppleScript via NSAppleScript. Surfaces TCC/automation errors.
enum AppleScriptRunner {
    static func run(_ source: String) throws {
        var errorDict: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&errorDict)
        if let errorDict, let msg = errorDict[NSAppleScript.errorMessage] as? String {
            throw TerminalLaunchError.automationFailed(msg)
        }
    }
}
