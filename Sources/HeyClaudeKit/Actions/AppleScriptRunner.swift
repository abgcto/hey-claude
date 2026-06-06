import AppKit
import Foundation

/// Runs AppleScript via NSAppleScript on the main thread.
/// NSAppleScript is not thread-safe and UI-automation scripts (System Events
/// keystrokes, menu clicks) silently do nothing when called off-main. Callers
/// on background queues (e.g. the audio queue) are safe: we sync to main,
/// which is free while the audio queue is executing a launch.
enum AppleScriptRunner {
    static func run(_ source: String) throws {
        var thrownError: Error?
        let block = {
            var errorDict: NSDictionary?
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&errorDict)
            if let errorDict {
                let msg = errorDict[NSAppleScript.errorMessage] as? String ?? "unknown"
                let code = errorDict[NSAppleScript.errorNumber] as? Int ?? 0
                thrownError = TerminalLaunchError.automationFailed("[\(code)] \(msg)")
            }
        }
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
        if let e = thrownError { throw e }
    }
}
