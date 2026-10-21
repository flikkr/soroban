import Foundation

/// User preferences, stored in UserDefaults (the API key override lives in the Keychain instead).
enum Settings {
    enum Keys {
        static let refreshMinutes = "refreshMinutes"
        static let refreshOnOpen = "refreshOnMenuOpen"
        static let baseURLOverride = "baseURLOverride"
        static let notificationsEnabled = "budgetNotificationsEnabled"
        static let notifyThresholds = "budgetNotifyThresholds"
        static let notifiedThresholds = "budgetNotifiedThresholds"
    }

    /// Posted when a setting that affects fetching (interval, connection) changes.
    static let didChange = Notification.Name("SettingsDidChange")

    static let refreshOptions = [1, 5, 15, 30]
    static let thresholdOptions = [50, 80, 90, 100]

    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            Keys.refreshMinutes: 5,
            Keys.refreshOnOpen: false,
            Keys.notificationsEnabled: true,
            Keys.notifyThresholds: "50,80,100",
        ])
    }

    static var refreshInterval: TimeInterval {
        TimeInterval(max(defaults.integer(forKey: Keys.refreshMinutes), 1) * 60)
    }

    static var refreshOnOpen: Bool { defaults.bool(forKey: Keys.refreshOnOpen) }

    static var baseURLOverride: String? {
        let value = Config.stripV1(defaults.string(forKey: Keys.baseURLOverride) ?? "")
        return value.isEmpty ? nil : value
    }

    static var notificationsEnabled: Bool { defaults.bool(forKey: Keys.notificationsEnabled) }

    static func parseThresholds(_ value: String) -> Set<Int> {
        Set(value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    static func formatThresholds(_ value: Set<Int>) -> String {
        value.sorted().map(String.init).joined(separator: ",")
    }

    static var notifyThresholds: Set<Int> {
        parseThresholds(defaults.string(forKey: Keys.notifyThresholds) ?? "")
    }

    /// Thresholds already notified in a budget period, so each one fires only once per period.
    static func notifiedThresholds(period: String) -> Set<Int> {
        let all = defaults.dictionary(forKey: Keys.notifiedThresholds) as? [String: [Int]] ?? [:]
        return Set(all[period] ?? [])
    }

    static func setNotifiedThresholds(_ value: Set<Int>, period: String) {
        // Only the current period matters; drop older ones.
        defaults.set([period: value.sorted()], forKey: Keys.notifiedThresholds)
    }
}
