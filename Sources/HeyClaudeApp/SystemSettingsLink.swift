import AppKit

/// Named deep links into System Settings panes, so the URL strings live in one
/// place instead of being duplicated at each call site.
enum SystemSettingsLink {
    /// Privacy & Security ▸ Microphone — where the user grants/restores mic access.
    case microphone

    var url: URL {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        }
    }

    func open() { NSWorkspace.shared.open(url) }
}
