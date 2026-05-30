import XCTest
@testable import HeyClaudeKit

final class MascotCatalogTests: XCTestCase {
    private let allowed: Set<Character> = ["#", "O", "H", "."]

    func test_everyPatternIsWellFormed() {
        for mascot in MascotCatalog.all {
            XCTAssertFalse(mascot.pattern.isEmpty, "\(mascot.id): pattern is empty")
            let width = mascot.pattern.first?.count ?? 0
            XCTAssertGreaterThan(width, 0, "\(mascot.id): zero-width rows")
            for (r, row) in mascot.pattern.enumerated() {
                XCTAssertEqual(row.count, width, "\(mascot.id): row \(r) width \(row.count) != \(width)")
                for ch in row {
                    XCTAssertTrue(allowed.contains(ch),
                                  "\(mascot.id): illegal char '\(ch)' in row \(r)")
                }
            }
        }
    }

    func test_byID_returnsClassic_andFallsBack() {
        XCTAssertEqual(MascotCatalog.byID("classic").id, "classic")
        XCTAssertEqual(MascotCatalog.byID("classic").displayName, "Classic")
        // Unknown id falls back to Classic (all[0]).
        XCTAssertEqual(MascotCatalog.byID("nonexistent").id, "classic")
    }

    func test_catalogHasSevenMascots() {
        XCTAssertEqual(MascotCatalog.all.count, 7)
        XCTAssertEqual(MascotCatalog.all.map(\.id),
                       ["classic", "sleepy", "wink", "wideEyed", "happy", "stompy", "birthday"])
    }

    /// Classic must be byte-identical to the shipped `MascotGrid`. Its `pattern`
    /// is `private`, so reconstruct an equivalent `[String]` from the public
    /// `cells` (every non-'.' char lives in `cells`; dims are fixed) and compare.
    func test_classicMatchesMascotGrid() {
        var grid = Array(repeating: Array(repeating: Character("."),
                                          count: MascotGrid.cols),
                         count: MascotGrid.rows)
        for cell in MascotGrid.cells {
            grid[cell.row][cell.col] = (cell.kind == .eye) ? "O" : "#"
        }
        let reconstructed = grid.map { String($0) }
        XCTAssertEqual(MascotCatalog.byID("classic").pattern, reconstructed,
                       "Classic pattern diverged from MascotGrid — FLAG: renderer truth split")
    }

    func test_decorationTags() {
        XCTAssertEqual(MascotCatalog.byID("happy").decoration, .chevronEyes)
        XCTAssertEqual(MascotCatalog.byID("birthday").decoration, .candle)
        XCTAssertEqual(MascotCatalog.byID("classic").decoration, .none)
    }
}
