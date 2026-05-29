import Foundation

/// What to run in a terminal: `claude` (optionally with a prompt) in a dir.
public struct LaunchSpec: Equatable, Sendable {
    public var directory: String
    public var executable: String        // e.g. "claude"
    public var prompt: String?

    public init(directory: String, executable: String, prompt: String?) {
        self.directory = directory
        self.executable = executable
        self.prompt = prompt
    }

    /// The shell command run inside the terminal. Single-quoted, shell-escaped.
    public func shellCommand() -> String {
        let dir = LaunchSpec.singleQuote(directory)
        var cmd = "cd \(dir) && \(executable)"
        if let p = prompt, !p.isEmpty {
            cmd += " \(LaunchSpec.singleQuote(p))"
        }
        return cmd
    }

    /// POSIX single-quote escaping: ' -> '\''
    static func singleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public protocol TerminalLauncher: Sendable {
    /// Whether this terminal app is installed (bundle id present).
    func isAvailable() -> Bool
    /// Open the terminal and run the spec. Throws on automation failure.
    func launch(_ spec: LaunchSpec) throws
}

public enum TerminalLaunchError: Swift.Error, Equatable {
    case notInstalled
    case automationFailed(String)
}
