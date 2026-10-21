import AppKit

final class SpendChartView: NSView {
    var days: [DaySpend] = [] {
        didSet {
            updateModels()
            needsDisplay = true
        }
    }
    var title = ChartRange.week.title { didSet { needsDisplay = true } }

    private let labelFont = NSFont.systemFont(ofSize: 10)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    /// Height of the bars area (title, bars and day labels), excluding the legend below it.
    var barAreaHeight: CGFloat = 110 { didSet { updateModels() } }
    private static let legendRowHeight: CGFloat = 15
    private static let palette: [NSColor] = [
        .systemBlue, .systemPurple, .systemOrange, .systemTeal, .systemPink, .systemYellow, .systemIndigo, .systemBrown,
    ]

    private static let knownColors: [String: NSColor] = [
        "claude-opus-5-5": .systemPurple,
        "claude-sonnet-5-5": .systemBlue,
        "claude-haiku-5-5": .systemTeal,
        "gpt-6.1-sol": .systemGreen,
        "gpt-6-luna": .systemMint,
        "grok-4.7": .systemOrange,
        "glm-5.3": .systemPink,
    ]

    /// Same model always gets the same colour, whatever range is shown.
    static func color(for model: String) -> NSColor {
        if let known = knownColors[model] { return known }
        // Stable hash (Swift's hashValue changes between launches).
        let hash = model.utf8.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ UInt32($1) }
        return palette[Int(hash % UInt32(palette.count))]
    }

    /// Models in the visible range, most expensive first, with their total spend and colour.
    private(set) var models: [(name: String, spend: Double, color: NSColor)] = []

    /// Model under the mouse (in a bar or the legend); other models are dimmed while set.
    private var highlightedModel: String? {
        didSet { if highlightedModel != oldValue { needsDisplay = true } }
    }
    // Hit areas recorded while drawing, used for hover hit-testing.
    private var segmentRects: [(rect: NSRect, model: String)] = []
    private var legendRects: [(rect: NSRect, model: String)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        // NSMenu stretches views with a flexible width to the menu's full width.
        autoresizingMask = [.width]
        // .activeAlways is needed because the app is never the active app while its menu is open.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        highlightedModel = (segmentRects + legendRects).first { $0.rect.contains(point) }?.model
    }

    override func mouseExited(with event: NSEvent) {
        highlightedModel = nil
    }

    private func displayColor(for model: (name: String, spend: Double, color: NSColor)) -> NSColor {
        guard let highlightedModel, highlightedModel != model.name else { return model.color }
        return model.color.withAlphaComponent(0.2)
    }

    private func updateModels() {
        var totals: [String: Double] = [:]
        for day in days {
            for (model, spend) in day.byModel { totals[model, default: 0] += spend }
        }
        let sorted = totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        models = sorted.map { ($0.key, $0.value, Self.color(for: $0.key)) }
        invalidateIntrinsicContentSize()
        // The menu sizes the item from the view's frame, so grow it to fit one legend row per model.
        // (In an Auto Layout window, intrinsicContentSize does this instead.)
        if translatesAutoresizingMaskIntoConstraints && frame.height != contentHeight {
            setFrameSize(NSSize(width: frame.width, height: contentHeight))
        }
        needsDisplay = true
    }

    private var contentHeight: CGFloat {
        let legendHeight = models.isEmpty ? 0 : CGFloat(models.count) * Self.legendRowHeight + 6
        return barAreaHeight + legendHeight
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        segmentRects = []
        legendRects = []
        guard !days.isEmpty else { return }
        let total = days.reduce(0) { $0 + $1.spend }
        let maxSpend = max(days.map(\.spend).max() ?? 0, 0.01)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor]
        (title as NSString).draw(at: NSPoint(x: 14, y: bounds.height - 18), withAttributes: titleAttrs)
        let totalStr = String(format: "$%.2f total", total) as NSString
        let totalSize = totalStr.size(withAttributes: titleAttrs)
        totalStr.draw(at: NSPoint(x: bounds.width - 14 - totalSize.width, y: bounds.height - 18), withAttributes: titleAttrs)

        // The legend sits below the chart; everything in the chart is offset up by its height.
        let base = bounds.height - barAreaHeight
        let chartLeft: CGFloat = 14
        let chartWidth = bounds.width - 28
        let labelHeight: CGFloat = 14
        let valueHeight: CGFloat = 12
        let barBottom: CGFloat = base + 6 + labelHeight
        let barMaxHeight = bounds.height - 24 - barBottom - valueHeight
        let slot = chartWidth / CGFloat(days.count)
        let barWidth = min(slot * 0.6, 22)

        let dayFormatter = DateFormatter()
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        if days.count <= 7 {
            dayFormatter.dateFormat = "EEE"
        } else {
            dayFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        }

        // With many days, only label every Nth day (counting back from today) so labels don't overlap.
        let widestLabel = days.map {
            (dayFormatter.string(from: $0.date) as NSString).size(withAttributes: [.font: labelFont]).width
        }.max() ?? 0
        let labelStride = max(1, Int(ceil((widestLabel + 6) / slot)))
        // Only show per-bar amounts when there's room for them.
        let showValues = slot >= 26

        for (i, day) in days.enumerated() {
            let centerX = chartLeft + slot * (CGFloat(i) + 0.5)
            let isToday = i == days.count - 1
            let showLabel = (days.count - 1 - i) % labelStride == 0
            let height = max(CGFloat(day.spend / maxSpend) * barMaxHeight, day.spend > 0 ? 2 : 1)
            let bar = NSRect(x: centerX - barWidth / 2, y: barBottom, width: barWidth, height: height)

            if day.spend > 0 {
                // Stack one segment per model, most expensive model at the bottom.
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).addClip()
                var y = bar.minY
                let modelTotal = day.byModel.values.reduce(0, +)
                for model in models {
                    guard let spend = day.byModel[model.name], spend > 0, modelTotal > 0 else { continue }
                    let h = bar.height * CGFloat(spend / modelTotal)
                    let segment = NSRect(x: bar.minX, y: y, width: bar.width, height: h)
                    displayColor(for: model).setFill()
                    segment.fill()
                    // Pad thin segments so they're still easy to hover.
                    segmentRects.append((segment.insetBy(dx: -2, dy: h < 4 ? -(4 - h) / 2 : 0), model.name))
                    y += h
                }
                if modelTotal <= 0 {
                    NSColor.systemGray.setFill()
                    bar.fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor.tertiaryLabelColor.setFill()
                NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
            }

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: isToday ? NSFont.systemFont(ofSize: 10, weight: .semibold) : labelFont,
                .foregroundColor: isToday ? NSColor.labelColor : NSColor.secondaryLabelColor]
            if showLabel {
                let label = dayFormatter.string(from: day.date) as NSString
                let labelSize = label.size(withAttributes: labelAttrs)
                let x = min(max(centerX - labelSize.width / 2, 2), bounds.width - 2 - labelSize.width)
                label.draw(at: NSPoint(x: x, y: base + 4), withAttributes: labelAttrs)
            }

            // While a model is highlighted, show that model's amount for the day instead of the day total.
            let shownSpend = highlightedModel.map { day.byModel[$0] ?? 0 } ?? day.spend
            if showValues && shownSpend > 0 {
                let valueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.labelColor]
                let value = (shownSpend < 0.05 ? "<$0.1"
                    : shownSpend >= 10 ? String(format: "$%.0f", shownSpend)
                    : String(format: "$%.1f", shownSpend)) as NSString
                let valueSize = value.size(withAttributes: valueAttrs)
                value.draw(at: NSPoint(x: centerX - valueSize.width / 2, y: bar.maxY + 1), withAttributes: valueAttrs)
            }
        }

        drawLegend(below: base)
    }

    private func drawLegend(below top: CGFloat) {
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.labelColor]
        let amountAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor]

        for (i, model) in models.enumerated() {
            let rowTop = top - 4 - CGFloat(i) * Self.legendRowHeight
            let midY = rowTop - Self.legendRowHeight / 2
            let row = NSRect(x: 8, y: rowTop - Self.legendRowHeight, width: bounds.width - 16, height: Self.legendRowHeight)
            legendRects.append((row, model.name))

            let isDimmed = highlightedModel != nil && highlightedModel != model.name
            if highlightedModel == model.name {
                NSColor.labelColor.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: row, xRadius: 4, yRadius: 4).fill()
            }
            var nameAttrs = nameAttrs
            var amountAttrs = amountAttrs
            if isDimmed {
                nameAttrs[.foregroundColor] = NSColor.tertiaryLabelColor
                amountAttrs[.foregroundColor] = NSColor.tertiaryLabelColor
            }

            displayColor(for: model).setFill()
            NSBezierPath(roundedRect: NSRect(x: 14, y: midY - 4, width: 8, height: 8), xRadius: 2, yRadius: 2).fill()

            let amount = String(format: model.spend < 0.01 ? "<$0.01" : "$%.2f", model.spend) as NSString
            let amountSize = amount.size(withAttributes: amountAttrs)
            let amountX = bounds.width - 14 - amountSize.width
            amount.draw(at: NSPoint(x: amountX, y: midY - amountSize.height / 2), withAttributes: amountAttrs)

            let name = model.name as NSString
            let nameSize = name.size(withAttributes: nameAttrs)
            let nameRect = NSRect(x: 28, y: midY - nameSize.height / 2, width: amountX - 6 - 28, height: nameSize.height)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            var attrs = nameAttrs
            attrs[.paragraphStyle] = style
            name.draw(in: nameRect, withAttributes: attrs)
        }
    }
}
