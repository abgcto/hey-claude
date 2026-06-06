import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// A typed, user-actionable launch failure. Replaces the old "swallow the error,
/// log to stderr, pretend it worked" path: every failure mode a `CommandExecutor`
/// can hit maps to one case carrying enough context to tell the user *what* broke
/// and *how to fix it*.
///
/// `LocalizedError` gives the menu its two lines (`errorDescription` +
/// `recoverySuggestion`); `islandMessage` is the short form the notch shows during
/// the failure beat. `Sendable` so it can cross from the audio queue (where the
/// launch runs) to the main actor intact — never collapsed to a `Bool`.
public enum LaunchFailure: Error, Equatable, Sendable, LocalizedError {
    /// The chosen terminal isn't installed.
    case terminalNotInstalled(TerminalKind)
    /// Automation (AppleScript) to drive the terminal failed — almost always a
    /// missing Automation permission. The string is the underlying message.
    case terminalAutomationFailed(TerminalKind, String)
    /// No app claimed the editor's deep-link scheme. Best-effort: `NSWorkspace.open`
    /// only reports "no handler", not "editor launched but ignored the link".
    case editorDeepLinkRejected(EditorKind)
    /// A `runCLI` editor target reached the executor without integration data.
    /// Defensive — `Settings` backfills this; should not happen in practice.
    case editorIntegrationMissing(EditorKind)
    /// A legacy `openApp` command was decoded from an old settings file; the app
    /// path is no longer supported, so the bundle ID is reported and execution stops.
    case appNotFound(String)
    /// A `runShell` command failed to spawn.
    case shellFailed(String)

    /// One-line headline (menu primary line + log).
    public var errorDescription: String? {
        switch self {
        case .terminalNotInstalled(let k):
            return "Couldn’t open \(k.rawValue) — it isn’t installed."
        case .terminalAutomationFailed(let k, let detail):
            if k.needsAccessibility && detail.contains("assistive access") {
                return "Couldn’t open \(k.rawValue) — Accessibility permission is required."
            }
            return "Couldn’t control \(k.rawValue). \(detail)"
        case .editorDeepLinkRejected(let e):
            return "No app opened the \(e.rawValue) link."
        case .editorIntegrationMissing(let e):
            return "Missing Claude Code integration for \(e.rawValue)."
        case .appNotFound:
            return "This command type is no longer supported."
        case .shellFailed(let msg):
            return "The command failed to run — \(msg)"
        }
    }

    /// What the user can do about it — kept short and front-loaded so it survives
    /// NSMenu's single-line width clamp (long instructions clip; the deep-link
    /// `settingsURL` below carries the un-truncatable action instead).
    public var recoverySuggestion: String? {
        switch self {
        case .terminalNotInstalled:
            return "Choose a different terminal above."
        case .terminalAutomationFailed(let k, _):
            return k.needsAccessibility
                ? "Allow Accessibility, then try again."
                : "Allow Automation, then try again."
        case .editorDeepLinkRejected(let e):
            return "Needs \(e.rawValue) + the Claude Code extension."
        case .editorIntegrationMissing:
            return "Reinstall or reset settings."
        case .appNotFound, .shellFailed:
            return nil
        }
    }

    /// A System Settings pane that fixes this failure, surfaced as an actionable
    /// menu button — so the remedy doesn't depend on the user reading (and the menu
    /// not clipping) a long instruction string. nil when there's no one-click pane.
    public var settingsURL: URL? {
        switch self {
        case .terminalAutomationFailed(let k, _):
            let pane = k.needsAccessibility ? "Privacy_Accessibility" : "Privacy_Automation"
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        default:
            return nil
        }
    }

    /// Label for the `settingsURL` button.
    public var settingsActionLabel: String? {
        switch self {
        case .terminalAutomationFailed(let k, _):
            return k.needsAccessibility
                ? "Open Accessibility Settings\u{2026}"
                : "Open Automation Settings\u{2026}"
        default:
            return settingsURL == nil ? nil : "Open Automation Settings\u{2026}"
        }
    }

    /// The compact line the notch island shows during the failure beat.
    public var islandMessage: String {
        switch self {
        case .terminalNotInstalled(let k):   return "\(k.rawValue) isn’t installed"
        case .terminalAutomationFailed(let k, _): return "Couldn’t control \(k.rawValue)"
        case .editorDeepLinkRejected(let e): return "Couldn’t open \(e.rawValue)"
        case .editorIntegrationMissing(let e):    return "\(e.rawValue) not set up"
        case .appNotFound:                   return "Command unsupported"
        case .shellFailed:                   return "Command failed"
        }
    }
}
