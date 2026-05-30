import Foundation

/// The canonical Hey Claude mascot as pixel data — the single source of truth
/// ported from internal design notes. A 16×10
/// grid: flat top, two wide-set eyes (rows 2–3), full-width arm band (rows 4–5),
/// four legs (rows 8–9). Rendered by MascotView.
public enum MascotGrid {
    public enum CellKind: Equatable, Sendable { case body, eye }
    public struct Cell: Equatable, Sendable { public let col: Int; public let row: Int; public let kind: CellKind }

    public static let cols = 16
    public static let rows = 10

    /// '#' = body, 'O' = eye, '.' = empty
    private static let pattern = [
        "..############..",
        "..############..",
        "..##O######O##..",
        "..##O######O##..",
        "################",
        "################",
        "..############..",
        "..############..",
        "...#.#....#.#...",
        "...#.#....#.#...",
    ]

    public static let cells: [Cell] = {
        var out: [Cell] = []
        for (r, line) in pattern.enumerated() {
            for (c, ch) in line.enumerated() {
                switch ch {
                case "#": out.append(Cell(col: c, row: r, kind: .body))
                case "O": out.append(Cell(col: c, row: r, kind: .eye))
                default: break
                }
            }
        }
        return out
    }()
}
