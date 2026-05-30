import SwiftUI

/// The notch outline: concave TOP corners that flare out to the screen edge so
/// the shape fuses seamlessly with the physical notch (a plain rounded rect
/// reads as a separate bar beside/below the notch), plus convex ROUNDED BOTTOM
/// corners. Technique mirrors the macOS notch-app genre (boring.notch /
/// vibe-notch). Animate the radii between the resting and expanded states.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 13

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = topCornerRadius
        let br = bottomCornerRadius

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // top-left concave flare (curves inward+down to the body's left edge)
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX + tr, y: rect.minY))
        // left edge down
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        // bottom-left convex corner
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        // bottom edge
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        // bottom-right convex corner
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        // right edge up
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        // top-right concave flare
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
