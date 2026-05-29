import Foundation

/// A capped, newest-first log of executed commands for the menu's "Recent"
/// section. Stores a command LABEL + directory + timestamp — never the
/// transcript.
public final class RecentActions {
    public struct Entry: Equatable, Sendable {
        public let label: String        // "Claude Code" / "Claude desktop"
        public let directory: String?
        public let at: Double            // reference timestamp
    }

    private let capacity: Int
    public private(set) var entries: [Entry] = []

    public init(capacity: Int = 8) { self.capacity = capacity }

    public func record(label: String, directory: String?, at: Double) {
        entries.insert(Entry(label: label, directory: directory, at: at), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }
}
