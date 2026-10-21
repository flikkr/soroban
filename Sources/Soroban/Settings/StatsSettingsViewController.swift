import AppKit

/// Usage stats for the API key in three sections (summary numbers, daily chart, per-model table),
/// each with its own 7d / 14d / 1M range.
final class StatsSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Column: String, CaseIterable {
        case model, spend, share, requests, input, cacheHit, output, latency

        var title: String {
            switch self {
            case .model: return "Model"
            case .spend: return "Spend"
            case .share: return "Share"
            case .requests: return "Requests"
            case .input: return "Input tokens"
            case .cacheHit: return "Cache hit"
            case .output: return "Output tokens"
            case .latency: return "Avg latency"
            }
        }

        var width: CGFloat {
            switch self {
            case .model: return 140
            case .share: return 52
            case .cacheHit: return 72
            case .requests: return 70
            case .spend: return 78
            default: return 88
            }
        }

        var isNumeric: Bool { self != .model }
    }

    private enum Tile: CaseIterable {
        case spend, requests, tokens, perDay, successRate, latency, perRequest, busiestDay, cacheHitRate, cacheSavings

        var title: String {
            switch self {
            case .cacheHitRate: return "Cache hit rate"
            case .cacheSavings: return "Cache savings"
            case .spend: return "Total spend"
            case .requests: return "Requests"
            case .tokens: return "Tokens"
            case .perDay: return "Avg spend / day"
            case .successRate: return "Success rate"
            case .latency: return "Avg latency"
            case .perRequest: return "Avg cost / request"
            case .busiestDay: return "Busiest day"
            }
        }
    }

    private enum Section: Int, CaseIterable {
        case summary, chart, table

        var tabTitle: String {
            switch self {
            case .summary: return "Summary"
            case .chart: return "Chart"
            case .table: return "By model"
            }
        }
    }

    private static let tileHeight: CGFloat = 72
    private static let tableRowHeight: CGFloat = 22

    private var tileValues: [Tile: NSTextField] = [:]
    private var tileDetails: [Tile: NSTextField] = [:]
    private var sections: [Section: StatsSection] = [:]
    private var tableStats: UsageStats?
    private let chartView = SpendChartView(frame: NSRect(x: 0, y: 0, width: 600, height: 160))
    private let tableView = NSTableView()
    private let sectionPicker = NSSegmentedControl()
    private let statusField = SettingsUI.note("", width: 480)

    /// Bumped per section on every load, so a late response for an old range is ignored.
    private var generation: [Section: Int] = [:]

    override func loadView() {
        let initial = ChartRange.saved
        sections[.summary] = StatsSection(title: "Summary", content: makeTiles(), range: initial)
        sections[.chart] = StatsSection(title: "Daily spend", content: makeChart(), range: initial)
        sections[.table] = StatsSection(title: "By model", content: makeTable(), range: initial)
        for section in Section.allCases {
            sections[section]?.onRangeChange = { [weak self] _ in self?.load(section) }
        }

        // Summary | Chart | By model: shows one section at a time.
        sectionPicker.segmentCount = Section.allCases.count
        for section in Section.allCases {
            sectionPicker.setLabel(section.tabTitle, forSegment: section.rawValue)
            sectionPicker.setWidth(100, forSegment: section.rawValue)
        }
        sectionPicker.trackingMode = .selectOne
        sectionPicker.selectedSegment = Section.summary.rawValue
        sectionPicker.target = self
        sectionPicker.action = #selector(selectSection)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(loadAll))
        let separator = NSBox()
        separator.boxType = .separator

        let size = NSSize(width: 830, height: 520)
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        for subview in [sectionPicker, separator, statusField, refreshButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        for section in Section.allCases {
            guard let sectionView = sections[section]?.view else { continue }
            view.addSubview(sectionView)
            var constraints = [
                sectionView.topAnchor.constraint(equalTo: sectionPicker.bottomAnchor, constant: 20),
                sectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                sectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            ]
            // The table fills the space (and scrolls itself); the others keep their natural height.
            constraints.append(section == .table
                ? sectionView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -16)
                : sectionView.bottomAnchor.constraint(lessThanOrEqualTo: separator.topAnchor, constant: -16))
            NSLayoutConstraint.activate(constraints)
        }

        NSLayoutConstraint.activate([
            sectionPicker.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            sectionPicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            separator.bottomAnchor.constraint(equalTo: refreshButton.topAnchor, constant: -12),
            refreshButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            refreshButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            statusField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusField.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            statusField.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -12),
        ])
        self.view = view
        preferredContentSize = size
        showSummary(nil)
        showSection(.summary)
    }

    @objc private func selectSection() {
        guard let section = Section(rawValue: sectionPicker.selectedSegment) else { return }
        showSection(section)
    }

    private func showSection(_ selected: Section) {
        for section in Section.allCases {
            sections[section]?.view.isHidden = section != selected
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        loadAll()
    }

    // MARK: - Building

    /// Rows of four equal-width tiles, each with a caption, a large value and a small detail line.
    private func makeTiles() -> NSView {
        let all = Tile.allCases
        let rows = stride(from: 0, to: all.count, by: 4).map { start -> NSStackView in
            var views = all[start..<min(start + 4, all.count)].map(makeTile)
            // Pad a short last row with empty space so its tiles stay the same width as the others.
            while views.count < 4 { views.append(NSView()) }
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 10
            return row
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        return stack
    }

    private func makeTile(_ tile: Tile) -> NSView {
        let caption = NSTextField(labelWithString: tile.title)
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        caption.textColor = .secondaryLabelColor

        let value = NSTextField(labelWithString: "—")
        value.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        value.lineBreakMode = .byTruncatingTail

        let detail = NSTextField(labelWithString: " ")
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .tertiaryLabelColor
        detail.lineBreakMode = .byTruncatingTail

        tileValues[tile] = value
        tileDetails[tile] = detail

        let stack = SettingsUI.vstack([caption, value, detail], spacing: 2)
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0
        box.cornerRadius = 8
        box.fillColor = .quaternaryLabelColor.withAlphaComponent(0.08)
        box.contentViewMargins = NSSize(width: 12, height: 10)
        box.contentView = stack
        // Without a fixed height the boxes stretch to fill the space.
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: Self.tileHeight).isActive = true
        return box
    }

    private func makeChart() -> NSView {
        chartView.barAreaHeight = 170
        // The chart sizes itself (bars + one legend row per model) via its intrinsic height.
        // An NSBox wouldn't follow that, so use a plain background view with constraints.
        let background = RoundedBackgroundView()
        chartView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(chartView)
        NSLayoutConstraint.activate([
            chartView.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            chartView.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8),
            chartView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 4),
            chartView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -4),
        ])
        return background
    }

    private func makeTable() -> NSView {
        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column.width
            if column.isNumeric { tableColumn.headerCell.alignment = .right }
            tableView.addTableColumn(tableColumn)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .fullWidth
        tableView.rowHeight = Self.tableRowHeight
        tableView.selectionHighlightStyle = .none
        // Share any spare width across all columns, so the table always fits without scrolling sideways.
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 8, height: tableView.intercellSpacing.height)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        return scrollView
    }

    // MARK: - Loading

    @objc private func loadAll() {
        Section.allCases.forEach(load)
    }

    private func load(_ section: Section) {
        guard let range = sections[section]?.range else { return }
        let token = (generation[section] ?? 0) + 1
        generation[section] = token
        SettingsUI.setStatus(statusField, "Loading…")

        DispatchQueue.global().async {
            let config = Config.load()
            DispatchQueue.main.async {
                guard let config else {
                    SettingsUI.setStatus(self.statusField,
                        "Not connected. Set a server URL and API key in the Connection tab.", isError: true)
                    return
                }
                let client = LiteLLMClient(config: config)
                let isCurrent = { self.generation[section] == token }

                switch section {
                case .chart:
                    client.fetchDailySpend(days: range.rawValue) { result in
                        guard isCurrent() else { return }
                        switch result {
                        case .success(let days):
                            self.chartView.title = range.title
                            self.chartView.days = days
                            self.loaded()
                        case .failure(let error):
                            self.failed(error)
                        }
                    }
                case .summary, .table:
                    client.fetchUsageStats(days: range.rawValue) { result in
                        guard isCurrent() else { return }
                        switch result {
                        case .success(let stats):
                            if section == .summary { self.showSummary(stats) } else { self.showTable(stats) }
                            self.loaded()
                        case .failure(let error):
                            self.failed(error)
                        }
                    }
                }
            }
        }
    }

    private func loaded() {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        SettingsUI.setStatus(statusField, "Days are in UTC. Updated \(time).")
    }

    private func failed(_ error: Error) {
        SettingsUI.setStatus(statusField, "Couldn't load stats: \(error.localizedDescription)", isError: true)
    }

    // MARK: - Display

    private func showSummary(_ stats: UsageStats?) {
        func set(_ tile: Tile, _ value: String, _ detail: String = " ") {
            tileValues[tile]?.stringValue = value
            tileDetails[tile]?.stringValue = detail
        }
        guard let stats else {
            for tile in Tile.allCases { set(tile, "—") }
            return
        }
        let t = stats.total

        set(.spend, Self.money(t.spend), "\(stats.models.count) model\(stats.models.count == 1 ? "" : "s") used")
        set(.requests, Self.count(t.requests),
            t.failed > 0 ? "\(Self.count(t.failed)) failed" : "No failures")
        set(.tokens, Self.count(t.totalTokens),
            "\(Self.count(t.promptTokens)) in · \(Self.count(t.completionTokens)) out")
        set(.perDay, Self.money(stats.averageSpendPerDay), "Active on \(stats.activeDays) of \(stats.dayCount) days")
        set(.successRate, t.successRate.map { String(format: "%.1f%%", $0 * 100) } ?? "—",
            "\(Self.count(t.successful)) succeeded")
        set(.latency, Self.latency(t.averageLatencyMs),
            t.timedRequests > 0 ? "Over \(Self.count(t.timedRequests)) timed requests" : " ")
        set(.perRequest, t.costPerRequest.map(Self.money) ?? "—",
            t.requests > 0 ? "Over \(Self.count(t.requests)) requests" : " ")
        set(.cacheHitRate, Self.percent(t.cacheHitRate),
            t.promptTokens > 0 ? "\(Self.count(t.cachedTokens)) of \(Self.count(t.promptTokens)) input tokens" : " ")
        set(.cacheSavings, Self.money(t.cacheSavings),
            t.cacheSavings > 0 ? "vs. \(Self.money(t.spend)) spent" : "No cached reads")
        if let busiest = stats.busiestDay {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("EEE d MMM")
            f.timeZone = TimeZone(identifier: "UTC")
            set(.busiestDay, f.string(from: busiest.date), "\(Self.money(busiest.spend)) spent")
        } else {
            set(.busiestDay, "—", "No usage yet")
        }
    }

    private func showTable(_ stats: UsageStats) {
        tableStats = stats
        tableView.reloadData()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableStats?.models.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, let column = Column(rawValue: id.rawValue),
              let stats = tableStats, stats.models.indices.contains(row) else { return nil }
        let (name, m) = stats.models[row]

        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.font = column.isNumeric
            ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : .systemFont(ofSize: NSFont.systemFontSize)
        field.alignment = column.isNumeric ? .right : .left

        switch column {
        case .model:
            // Same colour as this model's bars in the chart.
            let text = NSMutableAttributedString(
                string: "● ", attributes: [.foregroundColor: SpendChartView.color(for: name)])
            text.append(NSAttributedString(
                string: name, attributes: [.foregroundColor: NSColor.labelColor, .font: field.font!]))
            field.attributedStringValue = text
        case .spend:
            field.stringValue = Self.money(m.spend)
        case .share:
            if stats.total.spend > 0 {
                let share = m.spend / stats.total.spend * 100
                field.stringValue = share > 0 && share < 1 ? "<1%" : String(format: "%.0f%%", share)
            } else {
                field.stringValue = "—"
            }
        case .requests:
            field.stringValue = Self.count(m.requests)
        case .input:
            field.stringValue = Self.count(m.promptTokens)
        case .cacheHit:
            field.stringValue = Self.percent(m.cacheHitRate)
        case .output:
            field.stringValue = Self.count(m.completionTokens)
        case .latency:
            field.stringValue = Self.latency(m.averageLatencyMs)
        }

        let cell = NSTableCellView()
        cell.textField = field
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: - Formatting

    private static func money(_ value: Double) -> String {
        value > 0 && value < 0.01 ? String(format: "$%.4f", value) : String(format: "$%.2f", value)
    }

    /// e.g. 950, 12.3K, 4.56M
    private static func count(_ value: Int) -> String {
        let v = Double(value)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 10_000 { return String(format: "%.1fK", v / 1_000) }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return String(format: "%.1f%%", fraction * 100)
    }

    private static func latency(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return ms >= 1000 ? String(format: "%.1f s", ms / 1000) : String(format: "%.0f ms", ms)
    }
}

/// Same look as the summary tiles, but sized by Auto Layout from its subviews.
private final class RoundedBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}
