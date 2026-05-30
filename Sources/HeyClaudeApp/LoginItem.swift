import ServiceManagement
import HeyClaudeKit

/// Launch-at-login, backed by `SMAppService.mainApp`. The system is the source of
/// truth (it tracks the registration), so there is no mirrored `Settings` field —
/// the menu toggle reads and writes `status` directly.
///
/// Caveat: registration only takes effect for the bundled, signed `.app`. Under
/// `swift run` the unsigned dev binary has no registerable main bundle, so
/// `register()` throws and `status` stays `.notFound` — the toggle simply snaps
/// back to off. That's expected in development, not a bug.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.launch.error("login item \(on ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
