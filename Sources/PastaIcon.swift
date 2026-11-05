import AppKit
import SwiftUI

/// A hand-drawn, monochrome bowl of spaghetti with a twirling fork —
/// the Classic-style twin of the 🍝 emoji. Drawn as vectors, so it's crisp at any size,
/// and marked as a template so macOS tints it for light/dark menu bars.
enum PastaIcon {
    /// Variants used for the little menu bar reactions.
    enum Mood { case idle, sparkle, happy }

    static func image(pointSize: CGFloat = 18, mood: Mood = .idle) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            let scale = rect.width / 18
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.concat()
            draw(mood: mood)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pasta"
        return image
    }

    /// All drawing happens on an 18 × 18 grid (origin bottom-left).
    private static func draw(mood: Mood) {
        NSColor.black.setFill()
        NSColor.black.setStroke()

        // Bowl
        let bowl = NSBezierPath()
        bowl.move(to: NSPoint(x: 1.5, y: 8))
        bowl.line(to: NSPoint(x: 16.5, y: 8))
        bowl.curve(to: NSPoint(x: 9, y: 2.2),
                   controlPoint1: NSPoint(x: 16.5, y: 4.6),
                   controlPoint2: NSPoint(x: 13, y: 2.2))
        bowl.curve(to: NSPoint(x: 1.5, y: 8),
                   controlPoint1: NSPoint(x: 5, y: 2.2),
                   controlPoint2: NSPoint(x: 1.5, y: 4.6))
        bowl.close()
        bowl.fill()

        // Bowl foot
        NSBezierPath(roundedRect: NSRect(x: 6.2, y: 0.8, width: 5.6, height: 1.1),
                     xRadius: 0.5, yRadius: 0.5).fill()

        // Noodle mound: a bumpy outline…
        let mound = NSBezierPath()
        mound.lineWidth = 1.25
        mound.lineCapStyle = .round
        mound.lineJoinStyle = .round
        mound.move(to: NSPoint(x: 2.6, y: 8.7))
        mound.curve(to: NSPoint(x: 6, y: 10.7),
                    controlPoint1: NSPoint(x: 3, y: 10.4), controlPoint2: NSPoint(x: 4.6, y: 11.2))
        mound.curve(to: NSPoint(x: 9.2, y: 11.5),
                    controlPoint1: NSPoint(x: 7, y: 10.2), controlPoint2: NSPoint(x: 8.1, y: 12.3))
        mound.curve(to: NSPoint(x: 12.2, y: 10.8),
                    controlPoint1: NSPoint(x: 10.2, y: 10.8), controlPoint2: NSPoint(x: 11.2, y: 11.9))
        mound.curve(to: NSPoint(x: 15.4, y: 8.7),
                    controlPoint1: NSPoint(x: 13.5, y: 11.5), controlPoint2: NSPoint(x: 15.1, y: 10.3))
        mound.stroke()

        // …with a swirl of spaghetti inside it.
        let swirl = NSBezierPath()
        swirl.lineWidth = 1.0
        swirl.lineCapStyle = .round
        swirl.move(to: NSPoint(x: 4.6, y: 8.9))
        swirl.curve(to: NSPoint(x: 8.6, y: 9.4),
                    controlPoint1: NSPoint(x: 5.8, y: 10.3), controlPoint2: NSPoint(x: 7.4, y: 8.4))
        swirl.curve(to: NSPoint(x: 12.6, y: 9.1),
                    controlPoint1: NSPoint(x: 9.8, y: 10.6), controlPoint2: NSPoint(x: 11.4, y: 8.3))
        swirl.stroke()

        // Fork twirling in the noodles (pointing up and to the right).
        let dir = NSPoint(x: 0.587, y: 0.809)   // along the handle
        let perp = NSPoint(x: -0.809, y: 0.587) // across the tines
        let head = NSPoint(x: 14.9, y: 15.2)

        let fork = NSBezierPath()
        fork.lineWidth = 1.2
        fork.lineCapStyle = .round
        fork.move(to: NSPoint(x: 11.2, y: 10.1))
        fork.line(to: head)
        // Crossbar
        fork.move(to: NSPoint(x: head.x - perp.x * 1.25, y: head.y - perp.y * 1.25))
        fork.line(to: NSPoint(x: head.x + perp.x * 1.25, y: head.y + perp.y * 1.25))
        fork.stroke()

        let tines = NSBezierPath()
        tines.lineWidth = 0.85
        tines.lineCapStyle = .round
        for offset in [-1.1, 0.0, 1.1] {
            let base = NSPoint(x: head.x + perp.x * offset, y: head.y + perp.y * offset)
            tines.move(to: base)
            tines.line(to: NSPoint(x: base.x + dir.x * 1.9, y: base.y + dir.y * 1.9))
        }
        tines.stroke()

        // Little reactions for the menu bar.
        switch mood {
        case .idle:
            break
        case .sparkle:
            // Two sparkles on the left, like fresh pasta steam.
            sparkle(at: NSPoint(x: 3.6, y: 14.6), size: 2.4)
            sparkle(at: NSPoint(x: 7.4, y: 16.4), size: 1.5)
        case .happy:
            // A rising wisp of steam: "delizioso!"
            let steam = NSBezierPath()
            steam.lineWidth = 1.0
            steam.lineCapStyle = .round
            for x in [4.6, 7.8] {
                steam.move(to: NSPoint(x: x, y: 12.8))
                steam.curve(to: NSPoint(x: x, y: 16.8),
                            controlPoint1: NSPoint(x: x - 1.3, y: 14.1),
                            controlPoint2: NSPoint(x: x + 1.3, y: 15.5))
            }
            steam.stroke()
        }
    }

    /// A four-pointed sparkle.
    private static func sparkle(at c: NSPoint, size r: CGFloat) {
        let p = NSBezierPath()
        let k = r * 0.28
        p.move(to: NSPoint(x: c.x, y: c.y + r))
        p.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + k, y: c.y + k), controlPoint2: NSPoint(x: c.x + k, y: c.y + k))
        p.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + k, y: c.y - k), controlPoint2: NSPoint(x: c.x + k, y: c.y - k))
        p.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - k, y: c.y - k), controlPoint2: NSPoint(x: c.x - k, y: c.y - k))
        p.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - k, y: c.y + k), controlPoint2: NSPoint(x: c.x - k, y: c.y + k))
        p.close()
        p.fill()
    }
}

/// SwiftUI wrapper that tints the icon like text (primary color by default).
struct PastaGlyph: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: PastaIcon.image(pointSize: size))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
