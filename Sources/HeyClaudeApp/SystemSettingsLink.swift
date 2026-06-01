import AppKit

/// Named deep links into System Settings panes, so the URL strings live in one
/// place instead of being duplicated at each call site.
enum SystemSettingsLink {
    /// Privacy & Security ▸ Microphone — where the user grants/restores mic access.
    case microphone
    /// Privacy & Security ▸ Input Monitoring — where the user grants the
    /// push-to-talk global hotkey (CGEventTap) access.
    case inputMonitoring

    var url: URL {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }

    func open() { NSWorkspace.shared.open(url) }
}
