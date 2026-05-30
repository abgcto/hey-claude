import Foundation

/// The curated set of mascots a user can pick from. Pattern strings are the
/// canonical source of truth, ported byte-for-byte from the `MASCOTS` object in
/// internal design notes. Classic stays identical to
/// `MascotGrid` (today's shipped mascot).
public enum MascotCatalog {
    public static let all: [Mascot] = [
        Mascot(
            id: "classic",
            displayName: "Classic",
            pattern: [
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
        ),
        Mascot(
            id: "sleepy",
            displayName: "Sleepy",
            pattern: [
                "..############..",
                "..############..",
                "..############..",
                "..##OO####OO##..",
                "################",
                "################",
                "..############..",
                "..############..",
                "...#.#....#.#...",
                "...#.#....#.#...",
            ]
        ),
        Mascot(
            id: "wink",
            displayName: "Wink",
            pattern: [
                "..############..",
                "..############..",
                "..##O#########..",
                "..##O#####OO##..",
                "################",
                "################",
                "..############..",
                "..############..",
                "...#.#....#.#...",
                "...#.#....#.#...",
            ]
        ),
        Mascot(
            id: "wideEyed",
            displayName: "Wide-eyed",
            pattern: [
                "..############..",
                "..############..",
                "..##OO####OO##..",
                "..##OO####OO##..",
                "################",
                "################",
                "..############..",
                "..############..",
                "...#.#....#.#...",
                "...#.#....#.#...",
            ]
        ),
        Mascot(
            id: "happy",
            displayName: "Happy ><",
            pattern: [
                "..############..",
                "..############..",
                "..############..",
                "..############..",
                "################",
                "################",
                "..############..",
                "..############..",
                "...#.#....#.#...",
                "...#.#....#.#...",
            ],
            decoration: .chevronEyes
        ),
        Mascot(
            id: "stompy",
            displayName: "Stompy",
            pattern: [
                "..############..",
                "..############..",
                "..##O######O##..",
                "..##O######O##..",
                "################",
                "################",
                "..############..",
                "..############..",
                "..##..####..##..",
                "..##..####..##..",
            ]
        ),
        Mascot(
            id: "birthday",
            displayName: "Birthday",
            pattern: [
                "................",
                "................",
                "................",
                ".....HHHHHH.....",
                ".....HHHHHH.....",
                "....HHHHHHHH....",
                "....HHHHHHHH....",
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
            ],
            decoration: .candle
        ),
    ]

    /// The mascot for `id`, or Classic (`all[0]`) as a fallback.
    public static func byID(_ id: String) -> Mascot {
        all.first { $0.id == id } ?? all[0]
    }
}
