import Foundation
import UserNotifications

/// Sends a notification the first time spend crosses each chosen % of the budget in a period.
enum BudgetNotifier {
    /// UNUserNotificationCenter crashes outside an .app bundle (e.g. under `swift run`).
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestPermission(completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else {
            completion?(false)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    static func check(_ info: KeyInfo.Info) {
        guard Settings.notificationsEnabled,
              let budget = info.max_budget, budget > 0,
              let spend = info.spend else { return }

        // Identify the budget period by its reset date, so thresholds re-arm after each reset.
        let period = info.budget_reset_at ?? "none"
        let percent = spend / budget * 100
        let alreadyNotified = Settings.notifiedThresholds(period: period)
        let crossed = Settings.notifyThresholds.filter { percent >= Double($0) }
        let new = crossed.subtracting(alreadyNotified)
        guard let highest = new.max() else { return }

        // Mark every crossed threshold as done, but only notify once, for the highest.
        Settings.setNotifiedThresholds(alreadyNotified.union(crossed), period: period)

        let money: (Double) -> String = { String(format: "$%.2f", $0) }
        let title = highest >= 100 ? "LiteLLM budget used up" : "LiteLLM spend passed \(highest)%"
        var body = "You've spent \(money(spend)) of \(money(budget)) (\(String(format: "%.0f", percent))%)."
        if let reset = info.budgetResetDate {
            let rel = RelativeDateTimeFormatter().localizedString(for: reset, relativeTo: Date())
            body += " Budget resets \(rel)."
        }
        send(title: title, body: body)
    }

    static func sendTest() {
        send(title: "LiteLLM spend", body: "Notifications are working.")
    }

    private static func send(title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
