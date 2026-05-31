import XCTest
@testable import HeyClaudeKit

/// `IdeLockfileReader` reads the active editor names from Claude Code's
/// `~/.claude/ide/*.lock` files. `DefaultTargetResolver` uses it to pick the
/// first-run launch target (the actively-used editor). A parsing bug here means
/// the wrong default target — or a fallback to terminal when an editor is live.
/// All tests run against an injected temp directory; the real home dir is never
/// touched.
final class IdeLockfileReaderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("heyclaude-ide-\(ProcessInfo.processInfo.globallyUniqueString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeLock(_ name: String, _ json: String) throws {
        try Data(json.utf8).write(to: dir.appendingPathComponent(name))
    }

    func test_missingDirectory_returnsEmpty() {
        let reader = IdeLockfileReader(dir: dir.appendingPathComponent("does-not-exist"))
        XCTAssertEqual(reader.activeIdeNames(), [])
    }

    func test_emptyDirectory_returnsEmpty() {
        let reader = IdeLockfileReader(dir: dir)
        XCTAssertEqual(reader.activeIdeNames(), [])
    }

    func test_readsIdeNameFromLock() throws {
        try writeLock("1234.lock", #"{"ideName":"Cursor","pid":1234}"#)
        let reader = IdeLockfileReader(dir: dir)
        XCTAssertEqual(reader.activeIdeNames(), ["Cursor"])
    }

    func test_ignoresNonLockFiles() throws {
        try writeLock("1234.lock", #"{"ideName":"Cursor"}"#)
        try writeLock("notes.txt", #"{"ideName":"VSCode"}"#)   // wrong extension
        try writeLock("config.json", #"{"ideName":"Antigravity"}"#)
        let reader = IdeLockfileReader(dir: dir)
        XCTAssertEqual(reader.activeIdeNames(), ["Cursor"])
    }

    func test_skipsMalformedJSON() throws {
        try writeLock("good.lock", #"{"ideName":"Cursor"}"#)
        try writeLock("broken.lock", "{ this is not json")
        let reader = IdeLockfileReader(dir: dir)
        XCTAssertEqual(reader.activeIdeNames(), ["Cursor"])
    }

    func test_skipsLockMissingIdeName() throws {
        try writeLock("named.lock", #"{"ideName":"VSCode"}"#)
        try writeLock("anon.lock", #"{"pid":42}"#)             // decodes, ideName == nil
        let reader = IdeLockfileReader(dir: dir)
        XCTAssertEqual(reader.activeIdeNames(), ["VSCode"])
    }

    func test_emptyIdeName_isReturnedVerbatim() throws {
        // Pins current behaviour: an empty `ideName` decodes to "" (non-nil) and
        // is returned. It is harmless downstream — "" matches no `EditorKind`, so
        // `DefaultTargetResolver` drops it — but the reader does not filter it.
        try writeLock("blank.lock", #"{"ideName":""}"#)
        try writeLock("real.lock", #"{"ideName":"Cursor"}"#)
        let reader = IdeLockfileReader(dir: dir)
        XCTAssertEqual(reader.activeIdeNames().sorted(), ["", "Cursor"])
    }

    func test_preservesDuplicates() throws {
        // Two windows of the same editor produce two locks; the reader returns
        // both and lets the caller de-dupe onto EditorKind.
        try writeLock("a.lock", #"{"ideName":"Cursor"}"#)
        try writeLock("b.lock", #"{"ideName":"Cursor"}"#)
        let reader = IdeLockfileReader(dir: dir)
        XCTAssertEqual(reader.activeIdeNames().sorted(), ["Cursor", "Cursor"])
    }
}
