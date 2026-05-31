import XCTest
@testable import HeyClaudeKit

/// `KeywordStore` is the per-user wake-word file (`keywords.txt`) produced by
/// enrollment. It is load-bearing: when present it overrides the bundled
/// keyword model, so a broken round-trip silently reverts every user to the
/// generic "hey claude" keyword. These tests lock the persistence contract and
/// the present/absent signalling the engine uses to choose the file.
final class KeywordStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("heyclaude-kw-\(ProcessInfo.processInfo.globallyUniqueString).txt")
    }

    // MARK: present / absent signalling (drives the bundle-fallback decision)

    func test_missingFile_existsIsFalse_loadIsNil() {
        let store = KeywordStore(fileURL: tempURL())
        XCTAssertFalse(store.exists)
        XCTAssertNil(store.urlIfPresent)
        XCTAssertNil(store.load())            // caller falls back to bundled keywords.txt
    }

    func test_afterSave_existsIsTrue_urlIfPresentReturnsFile() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = KeywordStore(fileURL: url)
        try store.save(lines: ["▁HE Y ▁C LO U D"])
        XCTAssertTrue(store.exists)
        XCTAssertEqual(store.urlIfPresent, url)
    }

    // MARK: round-trip

    func test_saveThenLoad_roundTripsSingleLine() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = KeywordStore(fileURL: url)
        try store.save(lines: ["▁HE Y ▁C LO U D"])
        XCTAssertEqual(store.load(), ["▁HE Y ▁C LO U D"])
    }

    func test_saveThenLoad_roundTripsMultipleVariants() throws {
        // keywords.txt may hold multiple pronunciation variants; the spotter
        // fires on any. All lines must survive a round-trip.
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = KeywordStore(fileURL: url)
        let lines = ["▁HE Y ▁C LO U D", "▁HE Y ▁C LA U DE", "▁HE Y ▁C LAW D"]
        try store.save(lines: lines)
        XCTAssertEqual(store.load(), lines)
    }

    func test_save_writesTrailingNewline_loadDoesNotYieldEmptyEntry() throws {
        // The sherpa keyword loader expects newline-terminated lines; the
        // trailing "\n" must not round-trip back as a phantom empty keyword
        // (an empty keyword line would arm the spotter on silence).
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = KeywordStore(fileURL: url)
        try store.save(lines: ["▁HE Y ▁C LO U D"])
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.hasSuffix("\n"))
        XCTAssertEqual(store.load(), ["▁HE Y ▁C LO U D"])   // no "" entry
    }

    // MARK: degenerate stored content

    func test_load_emptyFile_returnsNil() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("".utf8).write(to: url)
        let store = KeywordStore(fileURL: url)
        XCTAssertNil(store.load())            // empty → nil → bundle fallback
    }

    func test_load_blankLinesOnly_returnsNil() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("\n\n\n".utf8).write(to: url)
        let store = KeywordStore(fileURL: url)
        XCTAssertNil(store.load())            // no real keyword lines
    }

    func test_saveEmptyArray_marksFilePresentButLoadIsNil() throws {
        // Documents a sharp edge: if enrollment ever derived zero keyword lines
        // and saved them, `exists` is true (engine prefers the per-user file)
        // yet `load()` is nil. Callers must treat nil-load as "fall back to
        // bundle" even when the file exists, not assume present ⇒ usable.
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = KeywordStore(fileURL: url)
        try store.save(lines: [])
        XCTAssertTrue(store.exists)
        XCTAssertNil(store.load())
    }

    func test_save_overwritesPreviousContent() throws {
        // Re-enrollment must fully replace the prior keyword set, not append.
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = KeywordStore(fileURL: url)
        try store.save(lines: ["▁HE Y ▁C LA U DE", "▁OLD ▁VARIANT"])
        try store.save(lines: ["▁HE Y ▁C LO U D"])
        XCTAssertEqual(store.load(), ["▁HE Y ▁C LO U D"])
    }
}
