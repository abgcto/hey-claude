import AppKit
import HeyClaudeKit

/// Builds the menu-bar `NSImage` for a given `AppState`.
///
/// The glyph echoes the app icon's "Crown Meter": the pixel Claude mascot wearing
/// a small 3-bar level-meter crown (a center-aligned waveform). It's a RESTING
/// brand mark — it deliberately does not animate or recolor per state (live state
/// lives in the notch island). Only two persistent states alter it: `off` dims the
/// whole glyph, and `muted` knocks a diagonal slash through it.
///
/// Monochrome TEMPLATE: macOS tints the alpha shape to match light/dark/tinted
/// menu bars, so everything is drawn in a single opaque ink and dimming is done by
/// lowering the fill's alpha (which the template tint then carries through).
enum MenuBarIcon {
    static func image(for state: AppState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            // `off` (no models / mic denied) reads as a dimmed glyph; everything
            // else is the full-strength brand mark.
            NSColor(white: 0, alpha: state == .off ? 0.4 : 1).set()
            drawMascot(in: rect)
            if state == .muted { knockOutSlash(in: rect) }
            return true
        }
        img.isTemplate = true
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

    /// The mascot (rounded body + two eye knockouts) crowned by a 3-bar meter.
    /// Coordinates are points in an 18×18 canvas, origin bottom-left.
    private static func drawMascot(in rect: NSRect) {
        // Body with eye holes: append the body then the eyes and fill even-odd so
        // the inner eye rects punch through as transparent knockouts.
        let body = NSBezierPath()
        body.appendRoundedRect(NSRect(x: 3.5, y: 2.8, width: 11, height: 6.8),
                               xRadius: 1.8, yRadius: 1.8)
        for eyeX in [6.15, 10.15] as [CGFloat] {
            body.appendRoundedRect(NSRect(x: eyeX, y: 6.6, width: 1.7, height: 2.2),
                                   xRadius: 0.6, yRadius: 0.6)
        }
        body.windingRule = .evenOdd
        body.fill()

        // Crown: 3 capsule bars, center-aligned on a shared midline (a small
        // waveform, not a bottom-aligned mountain) — matching the app icon's meter.
        let midline: CGFloat = 13.2
        let barW: CGFloat = 2
        let bars: [(x: CGFloat, h: CGFloat)] = [(5.6, 4.4), (8.0, 6.4), (10.4, 3.2)]
        for bar in bars {
            let r = NSRect(x: bar.x, y: midline - bar.h / 2, width: barW, height: bar.h)
            NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).fill()
        }
    }

    /// Muted: clear a diagonal gutter (top-left → bottom-right) through the glyph so
    /// it reads as "crossed out / off", consistent with the island's slashed mic.
    private static func knockOutSlash(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: rect.minX + 3, y: rect.maxY - 3))
        slash.line(to: NSPoint(x: rect.maxX - 3, y: rect.minY + 3))
        slash.lineWidth = 2.4
        slash.lineCapStyle = .round
        slash.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
