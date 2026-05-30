import AppKit
import HeyClaudeKit

/// Builds the menu-bar `NSImage` for a given `AppState`. Monochrome TEMPLATE at
/// rest (so it auto-adapts to light/dark/tinted menu bars); a brief NON-template
/// coral accent only during `.hot`/`.working` so the active moment reads.
enum MenuBarIcon {
    /// Direction A "The Seam" coral accent, used only for the active states.
    static let accent = NSColor(red: 1.0, green: 0.54, blue: 0.42, alpha: 1.0)

    static func image(for state: AppState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            drawBars(in: rect, state: state)
            return true
        }
        // Template for the calm states (system tints them); the accent states
        // draw their own coral and must opt out of template rendering.
        img.isTemplate = (state == .armed || state == .muted || state == .paused || state == .off)
        // .failed draws its own coral accent → must opt out of template tinting (below).
        img.accessibilityDescription = description(for: state)
        return img
    }

    private static func description(for state: AppState) -> String {
        switch state {
        case .off:     return "Hey Claude — off"
        case .armed:   return "Hey Claude — listening"
        case .hot:     return "Hey Claude — heard you"
        case .working: return "Hey Claude — launching"
        case .failed:  return "Hey Claude — launch failed"
        case .muted:   return "Hey Claude — muted"
        case .paused:  return "Hey Claude — paused"
        }
    }

    /// Three vertical bars (reads as a level meter and a stylized "C").
    private static func drawBars(in rect: NSRect, state: AppState) {
        let color: NSColor
        switch state {
        case .hot, .working, .failed: color = accent   // .failed: brief attention tint
        case .off:           color = NSColor.labelColor.withAlphaComponent(0.4)
        case .paused:        color = NSColor.labelColor.withAlphaComponent(0.45)
        default:             color = NSColor.labelColor
        }
        color.set()

        let n = 3
        let barW: CGFloat = 2.4
        let gap: CGFloat = 2.2
        let totalW = CGFloat(n) * barW + CGFloat(n - 1) * gap
        var x = rect.midX - totalW / 2
        let base: [CGFloat] = [0.45, 0.85, 0.6]
        for i in 0..<n {
            let h = rect.height * base[i]
            let barRect = NSRect(x: x, y: rect.midY - h / 2, width: barW, height: h)
            let path = NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1)
            path.lineWidth = 1.4
            if state == .armed {
                path.stroke()   // resting reads as a hollow, calm glyph
            } else {
                path.fill()
            }
            x += barW + gap
        }
        if state == .muted { drawSlash(in: rect) }
    }

    private static func drawSlash(in rect: NSRect) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + 2))
        p.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 2))
        p.lineWidth = 1.6
        NSColor.labelColor.set()
        p.stroke()
    }
}
