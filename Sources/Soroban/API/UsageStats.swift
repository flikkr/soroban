import Foundation

/// Usage totals over a range of days, shown in Settings → Stats.
struct UsageStats {
    struct Totals {
        var spend: Double = 0
        var requests = 0
        var successful = 0
        var failed = 0
        var promptTokens = 0
        var completionTokens = 0
        var cachedTokens = 0
        var cacheWriteTokens = 0
        var cacheSavings: Double = 0
        var responseTimeMs = 0
        var timedRequests = 0

        var totalTokens: Int { promptTokens + completionTokens }
        var averageLatencyMs: Double? { timedRequests > 0 ? Double(responseTimeMs) / Double(timedRequests) : nil }
        var costPerRequest: Double? { requests > 0 ? spend / Double(requests) : nil }

        /// Share of input tokens served from the prompt cache, or nil if there was no input.
        /// LiteLLM's prompt_tokens already includes cached reads and writes.
        var cacheHitRate: Double? {
            promptTokens > 0 ? Double(cachedTokens) / Double(promptTokens) : nil
        }

        /// Success rate as a fraction, or nil if the server doesn't report successes and failures.
        var successRate: Double? {
            let known = successful + failed
            return known > 0 ? Double(successful) / Double(known) : nil
        }

        mutating func add(_ m: DailyActivity.Day.Metrics) {
            spend += m.spend ?? 0
            requests += m.api_requests ?? 0
            successful += m.successful_requests ?? 0
            failed += m.failed_requests ?? 0
            promptTokens += m.prompt_tokens ?? 0
            completionTokens += m.completion_tokens ?? 0
            cachedTokens += m.cache_read_input_tokens ?? 0
            cacheWriteTokens += m.cache_creation_input_tokens ?? 0
            cacheSavings += m.prompt_caching_savings_spend ?? 0
            responseTimeMs += m.total_response_time_ms ?? 0
            timedRequests += m.timed_requests ?? 0
        }
    }

    let dayCount: Int
    let activeDays: Int
    let total: Totals
    /// Most expensive first.
    let models: [(name: String, totals: Totals)]
    let busiestDay: (date: Date, spend: Double)?

    var averageSpendPerDay: Double { dayCount > 0 ? total.spend / Double(dayCount) : 0 }

    init(days: [(Date, DailyActivity.Day?)]) {
        var total = Totals()
        var byModel: [String: Totals] = [:]
        var busiest: (date: Date, spend: Double)?
        var active = 0

        for (date, day) in days {
            guard let day else { continue }
            total.add(day.metrics)
            for (model, entry) in day.breakdown?.model_groups ?? [:] {
                byModel[model, default: Totals()].add(entry.metrics)
            }
            let spend = day.metrics.spend ?? 0
            if (day.metrics.api_requests ?? 0) > 0 || spend > 0 { active += 1 }
            if spend > (busiest?.spend ?? 0) { busiest = (date, spend) }
        }

        dayCount = days.count
        activeDays = active
        self.total = total
        models = byModel
            .filter { $0.value.requests > 0 || $0.value.spend > 0 }
            .sorted { $0.value.spend != $1.value.spend ? $0.value.spend > $1.value.spend : $0.key < $1.key }
            .map { ($0.key, $0.value) }
        busiestDay = busiest
    }
}
