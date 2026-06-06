import ApplicationServices
import HeyClaudeKit

/// Manages the Accessibility (assistive access) permission needed by terminal
/// targets that require AppleScript UI automation (e.g. Cursor Terminal, Ghostty).
enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Whether `target` needs Accessibility and it hasn't been granted yet.
    static func targetNeedsPermission(for target: LaunchTarget) -> Bool {
        guard case .terminal(let kind) = target else { return false }
        return kind.needsAccessibility && !isGranted
    }

    /// Trigger the system Accessibility prompt (no-op if already granted).
    static func request() {
        guard !isGranted else { return }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Convenience: request only when the target actually needs it.
    static func requestIfNeeded(for target: LaunchTarget) {
        guard targetNeedsPermission(for: target) else { return }
        request()
    }
}
