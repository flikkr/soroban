import AppKit

/// Small layout helpers shared by the settings tabs.
enum SettingsUI {
    static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    static func note(_ text: String, width: CGFloat = 320) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = width
        return field
    }

    static func vstack(_ views: [NSView], spacing: CGFloat = 4) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    /// Two-column form: right-aligned labels on the left, controls on the right.
    static func form(_ rows: [(String?, NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { row in
            [row.0.map { label($0) } ?? NSGridCell.emptyContentView, row.1]
        })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 8
        grid.rowSpacing = 14
        return grid
    }

    /// A fixed-size tab view with the content pinned to the top-left.
    static func container(_ content: NSView, size: NSSize) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
        ])
        return view
    }

    static func setStatus(_ field: NSTextField, _ text: String, isError: Bool = false) {
        field.stringValue = text
        field.textColor = isError ? .systemRed : .secondaryLabelColor
        field.isHidden = text.isEmpty
    }
}
