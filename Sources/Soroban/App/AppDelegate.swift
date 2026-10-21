import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let spendItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
    private let remainingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let chartView = SpendChartView(frame: NSRect(x: 0, y: 0, width: 220, height: 110))
    private let chartItem = NSMenuItem()
    private let chartSeparator = NSMenuItem.separator()
    private let rangeItem = NSMenuItem()
    private let rangeControl = NSSegmentedControl()
    private var range = ChartRange.saved
    private var client: LiteLLMClient?
    private var timer: Timer?
    private lazy var settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        MainMenu.install()
        statusItem.button?.title = "LLM …"
        buildMenu()
        if Settings.notificationsEnabled {
            BudgetNotifier.requestPermission()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange), name: Settings.didChange, object: nil)
        reloadConfig()
    }

    /// Reads the connection settings (off the main thread, as it may start a login shell),
    /// then refreshes and restarts the timer.
    private func reloadConfig() {
        DispatchQueue.global().async {
            let config = Config.load()
            DispatchQueue.main.async {
                self.client = config.map(LiteLLMClient.init)
                self.refresh()
                self.restartTimer()
            }
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Settings.refreshInterval, repeats: true) { _ in
            self.refresh()
        }
    }

    @objc private func settingsDidChange() {
        reloadConfig()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if Settings.refreshOnOpen { refresh() }
    }

    // MARK: - Menu

    private func buildMenu() {
        for item in [spendItem, remainingItem, resetItem, updatedItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        chartItem.view = chartView
        chartView.title = range.title
        rangeItem.view = makeRangeView()
        setChartHidden(true)

        menu.addItem(chartSeparator)
        menu.addItem(rangeItem)
        menu.addItem(chartItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
    }

    /// A control inside a view-based menu item doesn't close the menu when clicked,
    /// unlike a regular menu item, so switching ranges keeps the menu open.
    private func makeRangeView() -> NSView {
        rangeControl.segmentCount = ChartRange.allCases.count
        for (i, option) in ChartRange.allCases.enumerated() {
            rangeControl.setLabel(option.shortTitle, forSegment: i)
            rangeControl.setWidth(40, forSegment: i)
        }
        rangeControl.trackingMode = .selectOne
        rangeControl.controlSize = .small
        rangeControl.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        rangeControl.target = self
        rangeControl.action = #selector(selectRange(_:))
        rangeControl.sizeToFit()
        rangeControl.selectedSegment = ChartRange.allCases.firstIndex(of: range) ?? 0

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: rangeControl.frame.height + 8))
        view.autoresizingMask = [.width]
        rangeControl.frame.origin = NSPoint(x: 14, y: 4)
        view.addSubview(rangeControl)
        return view
    }

    private func setChartHidden(_ hidden: Bool) {
        chartItem.isHidden = hidden
        chartSeparator.isHidden = hidden
        rangeItem.isHidden = hidden
    }

    // MARK: - Actions

    @objc func selectRange(_ sender: NSSegmentedControl) {
        let all = ChartRange.allCases
        guard all.indices.contains(sender.selectedSegment) else { return }
        let newRange = all[sender.selectedSegment]
        guard newRange != range else { return }
        range = newRange
        ChartRange.saved = newRange
        chartView.title = newRange.title
        refreshChart()
    }

    @objc func openSettings() {
        settingsWindow.show()
    }

    @objc func refresh() {
        guard let client else {
            showError("Not set up. Add a server URL and API key in Settings → Connection.")
            return
        }
        client.fetchKeyInfo { result in
            switch result {
            case .success(let info):
                self.show(info)
                BudgetNotifier.check(info)
            case .failure(let error): self.showError(error.localizedDescription)
            }
        }
        refreshChart()
    }

    private func refreshChart() {
        guard let client else { return }
        let requestedRange = range
        client.fetchDailySpend(days: requestedRange.rawValue) { result in
            // Ignore a late response if the range was changed while it was in flight.
            guard requestedRange == self.range else { return }
            switch result {
            case .success(let days):
                self.chartView.days = days
                self.setChartHidden(false)
            case .failure:
                self.setChartHidden(true)
            }
        }
    }

    // MARK: - Display

    private func show(_ info: KeyInfo.Info) {
        let spend = info.spend ?? 0
        let money: (Double) -> String = { String(format: "$%.2f", $0) }

        statusItem.button?.toolTip = "LiteLLM spend"

        if let budget = info.max_budget, budget > 0 {
            let pct = spend / budget * 100
            spendItem.title = "Spent: \(money(spend)) of \(money(budget)) (\(String(format: "%.1f", pct))%)"
            remainingItem.title = "Remaining: \(money(budget - spend))"
            remainingItem.isHidden = false
            statusItem.button?.title = ""
            statusItem.button?.image = PillImage.make(fraction: spend / budget, label: money(spend))
            statusItem.button?.imagePosition = .imageOnly
        } else {
            spendItem.title = "Spent: \(money(spend))"
            remainingItem.isHidden = true
            statusItem.button?.image = nil
            statusItem.button?.title = money(spend)
        }

        if let date = info.budgetResetDate {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            let rel = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
            resetItem.title = "Resets: \(f.string(from: date)) (\(rel))"
            resetItem.isHidden = false
        } else {
            resetItem.isHidden = true
        }

        updatedItem.title = "Updated: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
    }

    private func showError(_ message: String) {
        statusItem.button?.image = nil
        statusItem.button?.title = "LLM ⚠︎"
        setChartHidden(true)
        spendItem.title = "Error: \(message)"
        remainingItem.isHidden = true
        resetItem.isHidden = true
        updatedItem.title = "Tried: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
    }
}
