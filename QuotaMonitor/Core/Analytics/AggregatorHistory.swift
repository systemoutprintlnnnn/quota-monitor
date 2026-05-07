import Foundation
import GRDB

// Day-bucketed history queries powering the History tab.

extension Aggregator {

    /// Returns days that had at least one usage_event, newest first.
    /// Buckets by local-calendar day (same offset trick as `fetchDaily`).
    static func fetchDays(
        db: Database, limit: Int = 365, provider: ProviderFilter = .all
    ) throws -> [DaySummary] {
        let offsetClause = String(format: "%+d seconds",
                                  TimeZone.current.secondsFromGMT())

        let rows = try Row.fetchAll(db, sql: """
            SELECT
              date(timestamp, ?) AS day,
              SUM(value_usd) AS value_usd,
              SUM(total_tokens) AS tokens,
              COUNT(*) AS events,
              COUNT(DISTINCT session_id) AS sessions
            FROM usage_events
            \(provider.whereClause(table: "usage_events"))
            GROUP BY day
            ORDER BY day DESC
            LIMIT \(limit)
            """, arguments: [offsetClause])

        let cal = Calendar(identifier: .gregorian)
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = cal
        dayFormatter.timeZone = TimeZone.current
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        return rows.compactMap { row -> DaySummary? in
            let day: String = row["day"] ?? ""
            guard let date = dayFormatter.date(from: day) else { return nil }
            return DaySummary(
                day: day,
                date: date,
                valueUSD: row["value_usd"] ?? 0,
                tokens: row["tokens"] ?? 0,
                eventCount: row["events"] ?? 0,
                sessionCount: row["sessions"] ?? 0)
        }
    }

    /// Drilldown for one local-calendar day: per-model breakdown + sessions
    /// active that day, with values restricted to events on that day only.
    static func fetchDayDetail(
        db: Database, day: String, provider: ProviderFilter = .all
    ) throws -> DayDetail? {
        let offsetClause = String(format: "%+d seconds",
                                  TimeZone.current.secondsFromGMT())

        let summaryRow = try Row.fetchOne(db, sql: """
            SELECT
              SUM(value_usd) AS value_usd,
              SUM(total_tokens) AS tokens,
              COUNT(*) AS events,
              COUNT(DISTINCT session_id) AS sessions
            FROM usage_events
            WHERE date(timestamp, ?) = ?
            \(provider.clause(table: "usage_events"))
            """, arguments: [offsetClause, day])
        guard let summaryRow, (summaryRow["events"] as Int? ?? 0) > 0 else { return nil }

        let cal = Calendar(identifier: .gregorian)
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = cal
        dayFormatter.timeZone = TimeZone.current
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let date = dayFormatter.date(from: day) ?? Date()

        let summary = DaySummary(
            day: day,
            date: date,
            valueUSD: summaryRow["value_usd"] ?? 0,
            tokens: summaryRow["tokens"] ?? 0,
            eventCount: summaryRow["events"] ?? 0,
            sessionCount: summaryRow["sessions"] ?? 0)

        let breakdown = try Row.fetchAll(db, sql: """
            SELECT
              ue.model_id,
              COALESCE(pc.display_name, ue.model_id) AS display_name,
              SUM(ue.value_usd)     AS value_usd,
              SUM(ue.total_tokens)  AS tokens,
              COUNT(*)              AS event_count
            FROM usage_events ue
            LEFT JOIN pricing_catalog pc ON pc.model_id = ue.model_id
            WHERE date(ue.timestamp, ?) = ?
            \(provider.clause(table: "ue"))
            GROUP BY ue.model_id
            ORDER BY value_usd DESC
            """, arguments: [offsetClause, day]).map { row in
            ModelShare(
                modelId: row["model_id"] ?? "unknown",
                displayName: row["display_name"] ?? "Unknown",
                valueUSD: row["value_usd"] ?? 0,
                tokens: row["tokens"] ?? 0,
                eventCount: row["event_count"] ?? 0)
        }

        let sessions = try Row.fetchAll(db, sql: """
            SELECT
              s.session_id,
              s.title,
              s.agent_nickname,
              s.last_model_id,
              s.started_at,
              s.updated_at,
              s.contains_subagents,
              MIN(ue.timestamp) AS day_started_at,
              MAX(ue.timestamp) AS day_updated_at,
              SUM(ue.value_usd)     AS total_value,
              SUM(ue.total_tokens)  AS total_tokens,
              COUNT(ue.id)          AS event_count,
              COALESCE(MAX(ue.model_inferred), 0) AS has_inferred_model
            FROM usage_events ue
            JOIN sessions s ON s.session_id = ue.session_id
            WHERE date(ue.timestamp, ?) = ?
            \(provider.clause(table: "ue"))
            GROUP BY s.session_id
            ORDER BY total_value DESC
            """, arguments: [offsetClause, day]).map { row in
            SessionRow(
                sessionId: row["session_id"] ?? "",
                title: row["title"],
                agentNickname: row["agent_nickname"],
                lastModelId: row["last_model_id"],
                startedAt: row["day_started_at"] ?? row["started_at"],
                updatedAt: row["day_updated_at"] ?? row["updated_at"],
                totalValueUSD: row["total_value"] ?? 0,
                totalTokens: row["total_tokens"] ?? 0,
                eventCount: row["event_count"] ?? 0,
                containsSubagents: row["contains_subagents"] ?? false,
                subagentCount: nil,
                hasInferredModel: row["has_inferred_model"] ?? false)
        }

        return DayDetail(summary: summary, modelBreakdown: breakdown, sessions: sessions)
    }

    /// Events for a given session restricted to a single local-calendar day.
    /// Powers the inline timeline shown when a user expands a session row in History.
    static func fetchEventsForSessionOnDay(
        db: Database, sessionId: String, day: String
    ) throws -> [SessionDetail.Event] {
        let offsetClause = String(format: "%+d seconds",
                                  TimeZone.current.secondsFromGMT())
        return try Row.fetchAll(db, sql: """
            SELECT id, timestamp, model_id,
                   input_tokens, cached_input_tokens,
                   output_tokens, reasoning_output_tokens,
                   total_tokens, value_usd, model_inferred
            FROM usage_events
            WHERE session_id = ? AND date(timestamp, ?) = ?
            ORDER BY timestamp ASC, id ASC
            """, arguments: [sessionId, offsetClause, day]).map { row in
            SessionDetail.Event(
                id: row["id"] ?? 0,
                timestamp: row["timestamp"] ?? "",
                modelId: row["model_id"] ?? "unknown",
                inputTokens: row["input_tokens"] ?? 0,
                cachedInputTokens: row["cached_input_tokens"] ?? 0,
                outputTokens: row["output_tokens"] ?? 0,
                reasoningOutputTokens: row["reasoning_output_tokens"] ?? 0,
                totalTokens: row["total_tokens"] ?? 0,
                valueUSD: row["value_usd"] ?? 0,
                modelInferred: row["model_inferred"] ?? false)
        }
    }
}
