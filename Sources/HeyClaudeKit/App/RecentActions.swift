import Foundation

/// A capped, newest-first log of executed commands for the menu's "Recent"
/// section. Stores a command LABEL + directory + timestamp — never the
/// transcript.
public final class RecentActions {
    /// Whether the recorded launch actually ran. Recent is an honest outcome log,
    /// not a success log — failures are kept and marked, never hidden.
    public enum Outcome: Equatable, Sendable { case launched, failed }

    public struct Entry: Equatable, Sendable {
        public let label: String        // "Claude Code" / "Claude desktop"
        public let directory: String?
        public let at: Double            // reference timestamp
        public let outcome: Outcome
    }

    private let capacity: Int
    public private(set) var entries: [Entry] = []

    public init(capacity: Int = 8) { self.capacity = capacity }

    public func record(label: String, directory: String?, at: Double,
                       outcome: Outcome = .launched) {
        entries.insert(Entry(label: label, directory: directory, at: at, outcome: outcome), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }
}
