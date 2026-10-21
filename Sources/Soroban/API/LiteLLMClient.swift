import Foundation

enum LiteLLMError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(let status): return "HTTP \(status)"
        }
    }
}

/// Talks to the LiteLLM proxy. Completion handlers are called on the main queue.
struct LiteLLMClient {
    let config: Config

    func fetchKeyInfo(completion: @escaping (Result<KeyInfo.Info, Error>) -> Void) {
        let request = makeRequest(path: "key/info", timeout: 15)
        send(request, as: KeyInfo.self) { completion($0.map(\.info)) }
    }

    func fetchModels(completion: @escaping (Result<[ModelGroupInfo.Model], Error>) -> Void) {
        let request = makeRequest(path: "model_group/info", timeout: 20)
        send(request, as: ModelGroupInfo.self) { completion($0.map(\.data)) }
    }

    /// Spend per day for the last `days` days (UTC, ending today), including days with no usage.
    func fetchDailySpend(days count: Int, completion: @escaping (Result<[DaySpend], Error>) -> Void) {
        fetchDailyActivity(days: count) { result in
            completion(result.map { days in
                days.map { day, result in
                    let m = result?.metrics
                    let byModel = (result?.breakdown?.model_groups ?? [:]).mapValues { $0.metrics.spend ?? 0 }
                    return DaySpend(date: day, spend: m?.spend ?? 0, requests: m?.api_requests ?? 0, byModel: byModel)
                }
            })
        }
    }

    /// Usage totals (spend, requests, tokens, latency) for the last `days` days, overall and per model.
    func fetchUsageStats(days count: Int, completion: @escaping (Result<UsageStats, Error>) -> Void) {
        fetchDailyActivity(days: count) { completion($0.map(UsageStats.init)) }
    }

    /// Every day in the last `days` days (UTC, ending today), with its activity, or nil if there was none.
    private func fetchDailyActivity(
        days count: Int, completion: @escaping (Result<[(Date, DailyActivity.Day?)], Error>) -> Void
    ) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let today = utc.startOfDay(for: Date())
        let days = (0..<count).reversed().compactMap { utc.date(byAdding: .day, value: -$0, to: today) }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = utc.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")

        let request = makeRequest(
            path: "user/daily/activity/aggregated",
            query: [
                "start_date": fmt.string(from: days.first ?? today),
                "end_date": fmt.string(from: today),
            ],
            timeout: 20)

        send(request, as: DailyActivity.self) { result in
            completion(result.map { activity in
                // Days with no usage are omitted by the API; fill them in as zero.
                let byDate = Dictionary(activity.results.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
                return days.map { ($0, byDate[fmt.string(from: $0)]) }
            })
        }
    }

    private func makeRequest(path: String, query: [String: String] = [:], timeout: TimeInterval) -> URLRequest {
        var components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type, completion: @escaping (Result<T, Error>) -> Void) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<T, Error>
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error {
                result = .failure(error)
            } else if status != 200 || data == nil {
                result = .failure(LiteLLMError.http(status))
            } else {
                result = Result { try JSONDecoder().decode(T.self, from: data!) }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

extension KeyInfo.Info {
    var budgetResetDate: Date? {
        guard let budget_reset_at else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: budget_reset_at) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: budget_reset_at)
    }
}
