import SwiftUI
import HeyClaudeKit

/// Draws a `Mascot` as crisp pixel squares plus an optional vector decoration,
/// scaled to fit the given frame.
///
/// The pixel grid is driven by `mascot.pattern` / `cols` / `rows` (any size).
/// Decorations are filled `Path`s expressed in the mascot's grid-unit coordinate
/// space (matching the canonical mockup's SVG `viewBox 0 0 cols rows`): one grid
/// unit maps to `size.width / cols`, which equals `size.height / rows` because the
/// aspect-fit keeps grid units square.
struct MascotView: View {
    var mascot: Mascot
    var bodyColor: Color = Color(red: 0.847, green: 0.463, blue: 0.341)  // #D87757 clay
    /// Blink: when true, `"O"` eyes render as a thin closed-lid dash instead of the
    /// open dot. Mascots without `"O"` eyes are unaffected (they don't blink).
    var eyesClosed: Bool = false

    /// Near-black eye / chevron ink (`#0a0a0a`).
    private static let eyeColor = Color(red: 0.04, green: 0.04, blue: 0.04)
    /// Hat purple (`#9e8cc9`).
    private static let hatColor = Color(red: 0.62, green: 0.55, blue: 0.79)
    /// Candle stem (`#edeae3`).
    private static let candleColor = Color(red: 0xed / 255.0, green: 0xea / 255.0, blue: 0xe3 / 255.0)
    /// Candle flame (`#ffd479`).
    private static let flameColor = Color(red: 0xff / 255.0, green: 0xd4 / 255.0, blue: 0x79 / 255.0)

    var body: some View {
        Canvas { ctx, size in
            let cols = mascot.cols
            let rows = mascot.rows
            guard cols > 0, rows > 0 else { return }
            // Aspect-fit keeps grid units square: width/cols == height/rows.
            let unit = size.width / CGFloat(cols)

            // Pixel grid. +0.5 oversize avoids hairline seams between cells.
            for (r, row) in mascot.pattern.enumerated() {
                for (c, ch) in row.enumerated() {
                    // Blink: an eye cell becomes a thin horizontal lid dash.
                    if ch == "O", eyesClosed {
                        let h = unit * 0.28
                        let lid = CGRect(x: CGFloat(c) * unit,
                                         y: CGFloat(r) * unit + (unit - h) / 2,
                                         width: unit + 0.5, height: h)
                        ctx.fill(Path(lid), with: .color(Self.eyeColor))
                        continue
                    }
                    let color: Color
                    switch ch {
                    case "#": color = bodyColor
                    case "O": color = Self.eyeColor
                    case "H": color = Self.hatColor
                    default: continue  // "." (or anything else) → clear
                    }
                    let rect = CGRect(x: CGFloat(c) * unit, y: CGFloat(r) * unit,
                                      width: unit + 0.5, height: unit + 0.5)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }

            // Vector decoration, drawn in the same grid-unit space.
            switch mascot.decoration {
            case .none:
                break
            case .chevronEyes:
                // Left ">" and right "<", filled with the eye ink.
                let left = Self.path([(3.9, 1.6), (5.6, 2.7), (3.9, 3.8),
                                      (3.9, 3.1), (4.6, 2.7), (3.9, 2.3)], unit: unit)
                let right = Self.path([(12.1, 1.6), (10.4, 2.7), (12.1, 3.8),
                                       (12.1, 3.1), (11.4, 2.7), (12.1, 2.3)], unit: unit)
                ctx.fill(left, with: .color(Self.eyeColor))
                ctx.fill(right, with: .color(Self.eyeColor))
            case .candle:
                // Stem rect (x 7.78, y 1.4, w 0.44, h 1.7) then flame polygon.
                let stem = CGRect(x: 7.78 * unit, y: 1.4 * unit,
                                  width: 0.44 * unit, height: 1.7 * unit)
                ctx.fill(Path(stem), with: .color(Self.candleColor))
                let flame = Self.path([(8, 0.25), (8.5, 0.9), (8, 1.55), (7.5, 0.9)], unit: unit)
                ctx.fill(flame, with: .color(Self.flameColor))
            }
        }
        .aspectRatio(CGFloat(mascot.cols) / CGFloat(mascot.rows), contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Builds a closed `Path` from grid-unit points scaled into canvas points.
    private static func path(_ points: [(CGFloat, CGFloat)], unit: CGFloat) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.0 * unit, y: first.1 * unit))
        for pt in points.dropFirst() {
            p.addLine(to: CGPoint(x: pt.0 * unit, y: pt.1 * unit))
        }
        p.closeSubpath()
        return p
    }
}
