import AppKit

/// A titled block in the Stats tab with its own 7d / 14d / 1M picker.
final class StatsSection: NSObject {
    let view = NSView()
    private(set) var range: ChartRange
    var onRangeChange: ((ChartRange) -> Void)?
    private let control = NSSegmentedControl()

    init(title: String, content: NSView, range: ChartRange) {
        self.range = range
        super.init()

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        control.segmentCount = ChartRange.allCases.count
        for (i, option) in ChartRange.allCases.enumerated() {
            control.setLabel(option.shortTitle, forSegment: i)
            control.setWidth(40, forSegment: i)
        }
        control.trackingMode = .selectOne
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        control.selectedSegment = ChartRange.allCases.firstIndex(of: range) ?? 0
        control.target = self
        control.action = #selector(changeRange)

        view.translatesAutoresizingMaskIntoConstraints = false
        for subview in [titleLabel, control, content] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: view.topAnchor),
            control.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            content.topAnchor.constraint(equalTo: control.bottomAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func changeRange() {
        let all = ChartRange.allCases
        guard all.indices.contains(control.selectedSegment) else { return }
        let newRange = all[control.selectedSegment]
        guard newRange != range else { return }
        range = newRange
        onRangeChange?(newRange)
    }
}
