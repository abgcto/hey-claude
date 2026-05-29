import AppKit
import Foundation

/// Executes a resolved Action. `openDesktopApp` is injected so it's testable
/// and so the default (NSWorkspace) lives in one place.
public struct ActionExecutor {
    private let settings: Settings
    private let launcher: TerminalLauncher
    private let openDesktopApp: () -> Void

    public init(settings: Settings,
                launcher: TerminalLauncher,
                openDesktopApp: @escaping () -> Void = ActionExecutor.defaultOpenDesktopApp) {
        self.settings = settings
        self.launcher = launcher
        self.openDesktopApp = openDesktopApp
    }

    public func execute(_ action: Action) throws {
        switch action {
        case .launchCLI(let prompt):
            try launcher.launch(LaunchSpec(
                directory: settings.projectDirectory,
                executable: settings.claudeExecutable,
                prompt: prompt))
        case .openDesktopApp:
            openDesktopApp()
        case .custom:
            break   // reserved for Phase 3 phrase-mapped actions
        }
    }

    public static func defaultOpenDesktopApp() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
        }
    }
}
