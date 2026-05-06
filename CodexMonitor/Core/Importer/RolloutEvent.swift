import Foundation

// Wire model for one line of a `rollout-*.jsonl` file.
//
// Each line is `{"timestamp": "...", "type": "...", "payload": {...}}`.
// We discriminate on `type` and lazily decode `payload` only for the cases we care about.
// Any unknown `type` yields `.other(type:)` — the parser logs and skips.

enum RolloutEvent {
    case sessionMeta(SessionMetaPayload, timestamp: String?)
    case turnContext(TurnContextPayload, timestamp: String?)
    case tokenCount(TokenCountPayload, timestamp: String?)
    case other(type: String, timestamp: String?)
}

struct RolloutLine: Decodable {
    let timestamp: String?
    let type: String
    let payload: JSONValue?
}

// MARK: - session_meta

struct SessionMetaPayload: Decodable {
    let id: String?
    let timestamp: String?
    let cwd: String?
    let originator: String?
    let cliVersion: String?
    let source: JSONValue?      // sometimes nested with subagent thread_spawn info
    let parentSessionId: String?
    let forkedFromId: String?
    let agentNickname: String?
    let agentRole: String?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, cwd, originator, source
        case cliVersion = "cli_version"
        case parentSessionId = "parent_session_id"
        case forkedFromId = "forked_from_id"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
    }

    /// Resolved parent id, preferring (in order):
    ///   1. `parent_session_id`
    ///   2. `forked_from_id`
    ///   3. nested `source.subagent.thread_spawn.parent_thread_id`
    /// Mirrors codex-pacer's `importer.rs` behavior.
    var resolvedParentSessionId: String? {
        if let p = parentSessionId, !p.isEmpty { return p }
        if let f = forkedFromId, !f.isEmpty { return f }
        return threadSpawn?["parent_thread_id"].flatMap(Self.string)
    }

    /// Effective nickname: top-level wins, else nested under thread_spawn.
    var resolvedAgentNickname: String? {
        if let n = agentNickname, !n.isEmpty { return n }
        return threadSpawn?["agent_nickname"].flatMap(Self.string)
    }

    /// Effective role: top-level wins, else nested under thread_spawn.
    var resolvedAgentRole: String? {
        if let r = agentRole, !r.isEmpty { return r }
        return threadSpawn?["agent_role"].flatMap(Self.string)
    }

    private var threadSpawn: [String: JSONValue]? {
        guard case .object(let obj) = source ?? .null,
              case .object(let sub) = obj["subagent"] ?? .null,
              case .object(let spawn) = sub["thread_spawn"] ?? .null
        else { return nil }
        return spawn
    }

    private static func string(_ v: JSONValue) -> String? {
        if case .string(let s) = v, !s.isEmpty { return s }
        return nil
    }
}

// MARK: - turn_context

struct TurnContextPayload: Decodable {
    let model: String?
}

// MARK: - event_msg / token_count

struct TokenCountPayload: Decodable {
    let info: TokenCountInfo?
    let rateLimits: EmbeddedRateLimits?
    /// Defensive: future Codex builds (or third-party recorders) may stamp the
    /// model id directly on the token_count payload. Today's CLI puts it on
    /// `turn_context` only.
    let model: String?
    let metadata: JSONValue?

    enum CodingKeys: String, CodingKey {
        case info, model, metadata
        case rateLimits = "rate_limits"
    }
}

struct TokenCountInfo: Decodable {
    let totalTokenUsage: TokenUsageWire?
    let lastTokenUsage: TokenUsageWire?
    let modelContextWindow: Int?
    /// Same defensive extraction as `TokenCountPayload`. ccusage scrapes these
    /// keys on every event; we do the same so we don't silently lose model
    /// attribution if Codex starts populating them.
    let model: String?
    let modelName: String?
    let metadata: JSONValue?

    enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
        case lastTokenUsage = "last_token_usage"
        case modelContextWindow = "model_context_window"
        case model
        case modelName = "model_name"
        case metadata
    }
}

struct TokenUsageWire: Decodable, Equatable {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    static let zero = TokenUsageWire(
        inputTokens: 0, cachedInputTokens: 0,
        outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0)
}

// Embedded in token_count events. Note this schema is DIFFERENT from the
// app-server's `account/rateLimits/read` shape — uses `window_minutes`
// and `resets_at` (epoch seconds) instead of `limit_window_seconds`.
struct EmbeddedRateLimits: Decodable {
    let primary: Window?
    let secondary: Window?
    let planType: String?
    let limitId: String?
    let limitName: String?

    struct Window: Decodable {
        let usedPercent: Double
        let windowMinutes: Int?
        let resetsAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case primary, secondary
        case planType = "plan_type"
        case limitId = "limit_id"
        case limitName = "limit_name"
    }
}

// MARK: - decoder dispatch

extension RolloutEvent {
    /// Decode one jsonl line. Returns nil if the line is empty or unparseable;
    /// returns `.other` for unknown discriminators.
    static func decode(line: Data) -> RolloutEvent? {
        guard !line.isEmpty else { return nil }
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(RolloutLine.self, from: line) else {
            return nil
        }

        let payloadData: Data? = envelope.payload.flatMap {
            try? JSONEncoder().encode($0)
        }

        switch envelope.type {
        case "session_meta":
            guard let data = payloadData,
                  let meta = try? decoder.decode(SessionMetaPayload.self, from: data)
            else { return .other(type: envelope.type, timestamp: envelope.timestamp) }
            return .sessionMeta(meta, timestamp: envelope.timestamp)

        case "turn_context":
            guard let data = payloadData,
                  let tc = try? decoder.decode(TurnContextPayload.self, from: data)
            else { return .other(type: envelope.type, timestamp: envelope.timestamp) }
            return .turnContext(tc, timestamp: envelope.timestamp)

        case "event_msg":
            // Nested discriminator — only token_count matters for usage.
            guard let payload = envelope.payload,
                  case .object(let dict) = payload,
                  case .string(let inner) = dict["type"] ?? .null,
                  inner == "token_count",
                  let data = payloadData,
                  let tc = try? decoder.decode(TokenCountPayload.self, from: data)
            else { return .other(type: envelope.type, timestamp: envelope.timestamp) }
            return .tokenCount(tc, timestamp: envelope.timestamp)

        default:
            return .other(type: envelope.type, timestamp: envelope.timestamp)
        }
    }
}
