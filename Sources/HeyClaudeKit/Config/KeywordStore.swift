import Foundation

/// Reads/writes the per-user wake-word keyword file produced by enrollment.
/// Lives next to `settings.json` in Application Support; injectable `fileURL`
/// for tests. When this file is absent, the app falls back to the bundled
/// `Models/keywords.txt`. One keyword phrase per line (sherpa tokenised form,
/// e.g. `▁HE Y ▁C LO U D`).
public final class KeywordStore {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public convenience init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HeyClaude", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(fileURL: dir.appendingPathComponent("keywords.txt"))
    }

    /// Whether a per-user keyword file exists (so the engine should prefer it).
    public var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// The per-user keyword URL if present, else nil (caller falls back to bundle).
    public var urlIfPresent: URL? { exists ? fileURL : nil }

    /// Persist keyword lines (one phrase per line). Trailing newline included.
    public func save(lines: [String]) throws {
        let body = lines.joined(separator: "\n") + "\n"
        try body.data(using: .utf8)!.write(to: fileURL, options: .atomic)
    }

    /// The stored keyword lines, or nil if no file / unreadable.
    public func load() -> [String]? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return lines.isEmpty ? nil : lines
    }
}
