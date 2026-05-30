import Foundation

/// Non-pixel parts of a mascot that can't be expressed as grid cells — the
/// renderer overlays these as vector paths in the grid's proportional space.
public enum MascotDecoration: String, Codable, Sendable {
    case none
    case chevronEyes
    case candle
}

/// One mascot: its pixel grid plus an optional vector decoration.
///
/// Valid pattern chars:
/// - `#` body
/// - `O` eye
/// - `H` hat (the renderer colors these distinctly)
/// - `.` empty
public struct Mascot: Identifiable, Equatable, Sendable {
    public let id: String           // stable key persisted in settings
    public let displayName: String
    public let pattern: [String]    // rows of '#' / 'O' / 'H' / '.'
    public let decoration: MascotDecoration

    /// Grid width (columns), derived from the first row.
    public var cols: Int { pattern.first?.count ?? 0 }
    /// Grid height (rows).
    public var rows: Int { pattern.count }

    public init(id: String,
                displayName: String,
                pattern: [String],
                decoration: MascotDecoration = .none) {
        self.id = id
        self.displayName = displayName
        self.pattern = pattern
        self.decoration = decoration
    }
}
