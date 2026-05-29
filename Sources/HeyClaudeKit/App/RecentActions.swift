import Foundation

/// A capped, newest-first log of executed actions for the menu's "Recent"
/// section. Stores action TYPE + directory + timestamp — never the transcript.
public final class RecentActions {
    public struct Entry: Equatable, Sendable {
        public let label: String        // "Launched Claude" / "Opened Claude Desktop"
        public let directory: String?
        public let at: Double            // reference timestamp
    }

    private let capacity: Int
    public private(set) var entries: [Entry] = []

    public init(capacity: Int = 8) { self.capacity = capacity }

    public func record(_ action: Action, directory: String?, at: Double) {
        let label: String
        switch action {
        case .launchCLI:     label = "Launched Claude"
        case .openDesktopApp: label = "Opened Claude Desktop"
        case .custom(let id): label = "Ran “\(id)”"
        }
        entries.insert(Entry(label: label, directory: directory, at: at), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }
}
