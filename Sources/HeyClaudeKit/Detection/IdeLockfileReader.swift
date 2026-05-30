import Foundation

/// Reads the *active editor names* from Claude Code's IDE lockfiles
/// (`~/.claude/ide/*.lock`). Each lockfile means an editor is running with
/// Claude Code connected.
///
/// We read **only** `ideName`. We deliberately do not touch `workspaceFolders`
/// — folder/window targeting is out of scope (the deep link uses the editor's
/// focused window). See internal design notes §3, §5.7.
public struct IdeLockfileReader: Sendable {
    private let dir: URL

    public init(dir: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/ide", isDirectory: true)) {
        self.dir = dir
    }

    private struct Lock: Decodable { let ideName: String? }

    /// The `ideName` of every present lockfile. Duplicates are fine — callers
    /// map them onto `EditorKind` and de-dupe there.
    public func activeIdeNames() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "lock" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? JSONDecoder().decode(Lock.self, from: $0).ideName }
    }
}
