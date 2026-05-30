import SwiftUI
import HeyClaudeKit

/// Draws the MascotGrid as crisp pixel squares, scaled to fit the given size.
struct MascotView: View {
    var bodyColor: Color = Color(red: 0.847, green: 0.463, blue: 0.341)  // #D87757
    var eyeColor: Color = .black

    var body: some View {
        Canvas { ctx, size in
            let cw = size.width / CGFloat(MascotGrid.cols)
            let ch = size.height / CGFloat(MascotGrid.rows)
            for cell in MascotGrid.cells {
                let rect = CGRect(x: CGFloat(cell.col) * cw, y: CGFloat(cell.row) * ch,
                                  width: cw + 0.5, height: ch + 0.5)  // +0.5 avoids hairline seams
                ctx.fill(Path(rect), with: .color(cell.kind == .eye ? eyeColor : bodyColor))
            }
        }
        .aspectRatio(CGFloat(MascotGrid.cols) / CGFloat(MascotGrid.rows), contentMode: .fit)
        .accessibilityHidden(true)
    }
}
