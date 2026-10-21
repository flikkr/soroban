import AppKit
import UserNotifications

final class NotificationsSettingsViewController: NSViewController {
    private let enabledBox = NSButton(checkboxWithTitle: "Notify me when my spend passes:", target: nil, action: nil)
    private var thresholdBoxes: [NSButton] = []
    private let statusField = SettingsUI.note("")

    override func loadView() {
        enabledBox.state = Settings.notificationsEnabled ? .on : .off
        enabledBox.target = self
        enabledBox.action = #selector(toggleEnabled)

        let selected = Settings.notifyThresholds
        thresholdBoxes = Settings.thresholdOptions.map { percent in
            let title = percent >= 100 ? "100% of budget (used up)" : "\(percent)% of budget"
            let box = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggleThreshold))
            box.tag = percent
            box.state = selected.contains(percent) ? .on : .off
            return box
        }
        let thresholds = SettingsUI.vstack(thresholdBoxes, spacing: 6)
        thresholds.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)

        let testButton = NSButton(title: "Send Test Notification", target: self, action: #selector(sendTest))
        SettingsUI.setStatus(statusField, "")

        let stack = SettingsUI.vstack([
            enabledBox,
            thresholds,
            SettingsUI.note("Each alert is sent once per budget period, the first time your spend passes it."),
            testButton,
            statusField,
        ], spacing: 10)
        let size = NSSize(width: 480, height: 270)
        view = SettingsUI.container(stack, size: size)
        preferredContentSize = size
        updateEnabledState()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        guard BudgetNotifier.isAvailable else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .denied {
                    self.showDeniedMessage()
                }
            }
        }
    }

    private func updateEnabledState() {
        thresholdBoxes.forEach { $0.isEnabled = enabledBox.state == .on }
    }

    private func showDeniedMessage() {
        SettingsUI.setStatus(statusField,
            "Notifications are turned off for Soroban. Turn them on in System Settings → Notifications.",
            isError: true)
    }

    @objc private func toggleEnabled() {
        let enabled = enabledBox.state == .on
        UserDefaults.standard.set(enabled, forKey: Settings.Keys.notificationsEnabled)
        updateEnabledState()
        if enabled {
            BudgetNotifier.requestPermission { granted in
                if !granted { self.showDeniedMessage() }
            }
        }
    }

    @objc private func toggleThreshold() {
        let selected = Set(thresholdBoxes.filter { $0.state == .on }.map(\.tag))
        UserDefaults.standard.set(Settings.formatThresholds(selected), forKey: Settings.Keys.notifyThresholds)
    }

    @objc private func sendTest() {
        BudgetNotifier.requestPermission { granted in
            if granted {
                BudgetNotifier.sendTest()
                SettingsUI.setStatus(self.statusField, "Test notification sent.")
            } else {
                self.showDeniedMessage()
            }
        }
    }
}
