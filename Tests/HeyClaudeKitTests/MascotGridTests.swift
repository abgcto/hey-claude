import XCTest
@testable import HeyClaudeKit

final class MascotGridTests: XCTestCase {
    func test_dimensions16x10() {
        XCTAssertEqual(MascotGrid.cols, 16)
        XCTAssertEqual(MascotGrid.rows, 10)
    }
    func test_hasTwoEyes() {
        let eyes = MascotGrid.cells.filter { $0.kind == .eye }
        XCTAssertEqual(eyes.count, 4)   // 2 eyes × 2 cells tall
    }
    func test_armBandIsFullWidth() {
        // rows 4 & 5 are the full-width arm band
        let row4 = MascotGrid.cells.filter { $0.row == 4 && $0.kind == .body }
        XCTAssertEqual(row4.count, 16)
    }
    func test_fourLegs() {
        let row8 = MascotGrid.cells.filter { $0.row == 8 && $0.kind == .body }
        XCTAssertEqual(row8.count, 4)
    }
}
