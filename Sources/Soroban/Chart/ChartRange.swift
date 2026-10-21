import Foundation

enum ChartRange: Int, CaseIterable {
    case week = 7
    case twoWeeks = 14
    case month = 30

    var title: String {
        switch self {
        case .week: return "Last 7 days"
        case .twoWeeks: return "Last 14 days"
        case .month: return "Last month"
        }
    }

    var shortTitle: String {
        switch self {
        case .week: return "7d"
        case .twoWeeks: return "14d"
        case .month: return "1M"
        }
    }

    private static let defaultsKey = "chartRangeDays"

    static var saved: ChartRange {
        get { ChartRange(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .week }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
