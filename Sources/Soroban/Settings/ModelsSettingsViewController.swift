import AppKit

/// Lists the models available to the API key, with prices and limits.
final class ModelsSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Column: String, CaseIterable {
        case model, input, output, context, maxOutput, features

        var title: String {
            switch self {
            case .model: return "Model"
            case .input: return "Input / 1M"
            case .output: return "Output / 1M"
            case .context: return "Context"
            case .maxOutput: return "Max output"
            case .features: return "Features"
            }
        }

        var width: CGFloat {
            switch self {
            case .model: return 150
            case .input, .output: return 80
            case .context: return 64
            case .maxOutput: return 76
            case .features: return ModelsSettingsViewController.featuresColumnWidth
            }
        }

        var isNumeric: Bool { self != .model && self != .features }
    }

    private var models: [ModelGroupInfo.Model] = []
    private let tableView = NSTableView()
    private let statusField = SettingsUI.note("", width: 480)

    override func loadView() {
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
        tableView.rowHeight = 22
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(load))

        let size = NSSize(width: 830, height: 340)
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        for subview in [scrollView, statusField, refreshButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: refreshButton.topAnchor, constant: -12),
            refreshButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            refreshButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            statusField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusField.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            statusField.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -12),
        ])
        self.view = view
        preferredContentSize = size
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        load()
    }

    @objc private func load() {
        SettingsUI.setStatus(statusField, "Loading…")
        DispatchQueue.global().async {
            let config = Config.load()
            DispatchQueue.main.async {
                guard let config else {
                    SettingsUI.setStatus(self.statusField, "Not connected. Set a server URL and API key in the Connection tab.", isError: true)
                    return
                }
                LiteLLMClient(config: config).fetchModels { result in
                    switch result {
                    case .success(let models):
                        self.models = models
                        self.tableView.reloadData()
                        SettingsUI.setStatus(self.statusField,
                            "\(models.count) models available to your key. Prices are USD per 1M tokens.")
                    case .failure(let error):
                        SettingsUI.setStatus(self.statusField,
                            "Couldn't load models: \(error.localizedDescription)", isError: true)
                    }
                }
            }
        }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        models.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, let column = Column(rawValue: id.rawValue) else { return nil }
        let model = models[row]

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
                string: "● ", attributes: [.foregroundColor: SpendChartView.color(for: model.model_group)])
            text.append(NSAttributedString(
                string: model.model_group, attributes: [.foregroundColor: NSColor.labelColor, .font: field.font!]))
            field.attributedStringValue = text
            field.toolTip = model.providers.map { "Provider: " + $0.joined(separator: ", ") }
        case .input:
            field.stringValue = Self.price(model.input_cost_per_token)
        case .output:
            field.stringValue = Self.price(model.output_cost_per_token)
        case .context:
            field.stringValue = Self.tokens(model.max_input_tokens)
        case .maxOutput:
            field.stringValue = Self.tokens(model.max_output_tokens)
        case .features:
            return Self.featuresCell(supported: [
                model.supports_vision == true,
                model.supports_function_calling == true,
                model.supports_reasoning == true,
            ])
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

    private static let features: [(name: String, symbol: String)] = [
        ("Vision", "eye"),
        ("Tools", "wrench.and.screwdriver"),
        ("Reasoning", "brain"),
    ]
    private static let featureFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let iconBox: CGFloat = 16
    private static let iconGap: CGFloat = 4
    private static let featureGap: CGFloat = 14

    /// Every feature has its own fixed slot, so icons line up in columns across rows.
    /// A missing feature leaves its slot empty instead of shifting the others left.
    private static let featureSlots: [(x: CGFloat, width: CGFloat)] = {
        var x: CGFloat = 4
        return features.map { feature in
            let labelWidth = ceil((feature.name as NSString).size(withAttributes: [.font: featureFont]).width)
            let width = iconBox + iconGap + labelWidth
            defer { x += width + featureGap }
            return (x, width)
        }
    }()

    static var featuresColumnWidth: CGFloat {
        (featureSlots.last.map { $0.x + $0.width } ?? 0) + 8
    }

    private static func featuresCell(supported: [Bool]) -> NSView {
        let color = NSColor.secondaryLabelColor
        let cell = NSTableCellView()
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: featureFont.pointSize - 1, weight: .regular)

        if !supported.contains(true) {
            let dash = NSTextField(labelWithString: "—")
            dash.textColor = color
            dash.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(dash)
            NSLayoutConstraint.activate([
                dash.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                dash.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        for (i, feature) in features.enumerated() where supported.indices.contains(i) && supported[i] {
            let slot = featureSlots[i]

            // Fixed-size box: symbols have different natural widths, so centre each one in the same space.
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: feature.symbol, accessibilityDescription: feature.name)?
                .withSymbolConfiguration(symbolConfig)
            icon.imageScaling = .scaleProportionallyDown
            icon.imageAlignment = .alignCenter
            icon.contentTintColor = color

            let label = NSTextField(labelWithString: feature.name)
            label.font = featureFont
            label.textColor = color
            label.lineBreakMode = .byClipping

            for view in [icon, label] {
                view.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(view)
            }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: slot.x),
                icon.widthAnchor.constraint(equalToConstant: iconBox),
                icon.heightAnchor.constraint(equalToConstant: iconBox),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: iconGap),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    private static func price(_ perToken: Double?) -> String {
        guard let perToken else { return "—" }
        return String(format: "$%.2f", perToken * 1_000_000)
    }

    private static func tokens(_ count: Double?) -> String {
        guard let count, count > 0 else { return "—" }
        let format: (Double, String) -> String = { value, suffix in
            let s = String(format: "%.2f", value)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
            return s + suffix
        }
        if count >= 1_000_000 { return format(count / 1_000_000, "M") }
        if count >= 1_000 { return String(format: "%.0fK", count / 1_000) }
        return String(Int(count))
    }
}
