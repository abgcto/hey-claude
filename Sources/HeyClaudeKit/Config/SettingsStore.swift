import Foundation

/// Loads/saves Settings as JSON. Defaults to Application Support; injectable
/// fileURL for tests. Missing/corrupt file -> Settings.default.
public final class SettingsStore {
    private let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public convenience init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HeyClaude", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(fileURL: dir.appendingPathComponent("settings.json"))
    }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .default }
        return s
    }

    public func save(_ settings: Settings) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(settings).write(to: fileURL, options: .atomic)
    }
}
