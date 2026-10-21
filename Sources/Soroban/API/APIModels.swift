import Foundation

// Response types for the LiteLLM proxy API.

struct KeyInfo: Decodable {
    struct Info: Decodable {
        let key_alias: String?
        let key_name: String?
        let spend: Double?
        let max_budget: Double?
        let budget_reset_at: String?
        let budget_duration: String?
    }
    let info: Info
}

struct ModelGroupInfo: Decodable {
    struct Model: Decodable {
        let model_group: String
        let providers: [String]?
        let mode: String?
        let max_input_tokens: Double?
        let max_output_tokens: Double?
        let input_cost_per_token: Double?
        let output_cost_per_token: Double?
        let supports_vision: Bool?
        let supports_function_calling: Bool?
        let supports_reasoning: Bool?
    }
    let data: [Model]
}

struct DailyActivity: Decodable {
    struct Day: Decodable {
        struct Metrics: Decodable {
            let spend: Double?
            let api_requests: Int?
            let successful_requests: Int?
            let failed_requests: Int?
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let cache_read_input_tokens: Int?
            let cache_creation_input_tokens: Int?
            let prompt_caching_savings_spend: Double?
            let total_response_time_ms: Int?
            let timed_requests: Int?
        }
        struct Breakdown: Decodable {
            struct Entry: Decodable {
                let metrics: Metrics
            }
            let model_groups: [String: Entry]?
        }
        let date: String
        let metrics: Metrics
        let breakdown: Breakdown?
    }
    let results: [Day]
}
