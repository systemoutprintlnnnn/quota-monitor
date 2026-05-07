import Foundation

// Fetches the LiteLLM static price catalog
// (https://github.com/BerriAI/litellm). The JSON is a dict-of-dicts:
//
//   {
//     "sample_spec": { ... docs example, skip ... },
//     "gpt-4o":      { "input_cost_per_token": 2.5e-6, ... },
//     "claude-3-5-sonnet-20240620": { ... cache_creation_input_token_cost ... },
//     ...
//   }
//
// LiteLLM stores prices in per-token units (USD). We convert to per-million
// at apply time so the existing schema doesn't need rescaling.

struct LiteLLMEntry: Sendable, Equatable {
    let modelId: String
    let provider: String?
    let inputCostPerToken: Double?
    let outputCostPerToken: Double?
    let cacheReadInputTokenCost: Double?
    let cacheCreationInputTokenCost: Double?
    let inputCostAbove200kTokens: Double?
    let outputCostAbove200kTokens: Double?
    let maxInputTokens: Int?
    let maxOutputTokens: Int?

    var perMillionInput: Double? { inputCostPerToken.map { $0 * 1_000_000 } }
    var perMillionOutput: Double? { outputCostPerToken.map { $0 * 1_000_000 } }
    var perMillionCacheRead: Double? { cacheReadInputTokenCost.map { $0 * 1_000_000 } }
    var perMillionCacheCreation: Double? { cacheCreationInputTokenCost.map { $0 * 1_000_000 } }
    var perMillionAbove200kInput: Double? { inputCostAbove200kTokens.map { $0 * 1_000_000 } }
    var perMillionAbove200kOutput: Double? { outputCostAbove200kTokens.map { $0 * 1_000_000 } }
}

enum LiteLLMError: Error, LocalizedError {
    case invalidResponse(Int)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let code):
            return "LiteLLM fetch failed with HTTP \(code)."
        case .decodeFailed(let detail):
            return "LiteLLM decode failed: \(detail)"
        }
    }
}

actor LiteLLMPricingSource {
    static let defaultURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    )!

    private let url: URL
    private let session: URLSession

    init(url: URL = LiteLLMPricingSource.defaultURL,
         session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    /// Download and decode the full catalog. Returns one entry per model; the
    /// `sample_spec` placeholder is filtered out.
    func fetch() async throws -> [LiteLLMEntry] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiteLLMError.invalidResponse(http.statusCode)
        }

        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LiteLLMError.decodeFailed("root is not an object")
        }

        var entries: [LiteLLMEntry] = []
        entries.reserveCapacity(raw.count)

        for (key, value) in raw {
            if key == "sample_spec" { continue }
            guard let dict = value as? [String: Any] else { continue }
            entries.append(LiteLLMEntry(
                modelId: key,
                provider: dict["litellm_provider"] as? String,
                inputCostPerToken: Self.double(dict["input_cost_per_token"]),
                outputCostPerToken: Self.double(dict["output_cost_per_token"]),
                cacheReadInputTokenCost: Self.double(dict["cache_read_input_token_cost"]),
                cacheCreationInputTokenCost: Self.double(dict["cache_creation_input_token_cost"]),
                inputCostAbove200kTokens: Self.double(dict["input_cost_per_token_above_200k_tokens"]),
                outputCostAbove200kTokens: Self.double(dict["output_cost_per_token_above_200k_tokens"]),
                maxInputTokens: Self.int(dict["max_input_tokens"]),
                maxOutputTokens: Self.int(dict["max_output_tokens"])
            ))
        }
        return entries
    }

    private static func double(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }
}
