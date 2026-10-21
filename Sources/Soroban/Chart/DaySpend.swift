import Foundation

/// One day of spend, as shown in the chart.
struct DaySpend {
    let date: Date
    let spend: Double
    let requests: Int
    var byModel: [String: Double] = [:]
}
