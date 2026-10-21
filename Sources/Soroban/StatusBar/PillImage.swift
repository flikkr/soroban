import AppKit

/// The menu bar pill: an outline that fills with the share of budget spent, with the amount inside.
enum PillImage {
    static func make(fraction: Double, label: String) -> NSImage {
        let clamped = CGFloat(min(max(fraction, 0), 1))
        let fillColor: NSColor = clamped >= 0.9 ? .systemRed : clamped >= 0.5 ? .systemOrange : .systemGreen
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        let textSize = (label as NSString).size(withAttributes: [.font: font])
        let height: CGFloat = 16
        let width = ceil(textSize.width) + 16

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            // Resolved at draw time, so it follows the menu bar's light/dark appearance.
            let color = NSColor.labelColor
            color.set()

            let outer = rect.insetBy(dx: 0.5, dy: 0.5)
            let outline = NSBezierPath(roundedRect: outer, xRadius: outer.height / 2, yRadius: outer.height / 2)
            outline.lineWidth = 1
            outline.stroke()

            let inner = rect.insetBy(dx: 2, dy: 2)
            let track = NSBezierPath(roundedRect: inner, xRadius: inner.height / 2, yRadius: inner.height / 2)
            var filled = inner
            filled.size.width = inner.width * clamped
            var empty = inner
            empty.origin.x = filled.maxX
            empty.size.width = inner.width - filled.width

            NSGraphicsContext.saveGraphicsState()
            track.addClip()
            fillColor.setFill()
            filled.fill()
            NSGraphicsContext.restoreGraphicsState()

            let textRect = NSRect(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width, height: textSize.height)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

            // Over the empty part, draw the text normally.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: empty).addClip()
            (label as NSString).draw(in: textRect, withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()

            // Over the filled part, draw it in white so it stays readable on the color.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: filled).addClip()
            (label as NSString).draw(in: textRect, withAttributes: [.font: font, .foregroundColor: NSColor.white])
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        return image
    }
}
