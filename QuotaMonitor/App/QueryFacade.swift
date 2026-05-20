import Foundation

// Pure pass-throughs to Aggregator. Lives here so the AppEnvironment file
// stays focused on shared mutable state + lifecycle, not query plumbing.

extension AppEnvironment {

    // MARK: - Sessions queries (used by Sessions tab)

    func fetchSessionsList(
        sort: SessionSort,
        search: String
    ) async throws -> [SessionRow] {
        let filter = providerFilter
        let op = DeveloperLog.startOperation(
            "query.sessions.list",
            category: "query",
            trigger: "ui",
            fields: [
                "sort": .string(String(describing: sort)),
                "search_length": .int(search.count),
                "filter": .string(filter.rawValue)
            ])
        do {
            let (db, _) = try ensureServices()
            let rows = try await db.pool.read { conn in
                try Aggregator.fetchSessions(
                    db: conn, sort: sort, search: search, provider: filter)
            }
            DeveloperLog.finishOperation(op, fields: [
                "rows": .int(rows.count),
                "filter": .string(filter.rawValue)
            ])
            return rows
        } catch {
            DeveloperLog.failOperation(op, error: error, fields: ["filter": .string(filter.rawValue)])
            throw error
        }
    }

    func fetchSessionDetail(sessionId: String) async throws -> SessionDetail? {
        let op = DeveloperLog.startOperation(
            "query.session.detail",
            category: "query",
            trigger: "ui",
            fields: ["session_id": .string(sessionId)])
        do {
            let (db, _) = try ensureServices()
            let detail = try await db.pool.read { conn in
                try Aggregator.fetchSessionDetail(db: conn, sessionId: sessionId)
            }
            DeveloperLog.finishOperation(op, fields: [
                "session_id": .string(sessionId),
                "found": .bool(detail != nil)
            ])
            return detail
        } catch {
            DeveloperLog.failOperation(op, error: error, fields: ["session_id": .string(sessionId)])
            throw error
        }
    }

    // MARK: - History queries (used by History tab)

    func fetchDaysList(limit: Int = 365) async throws -> [DaySummary] {
        let filter = providerFilter
        let op = DeveloperLog.startOperation(
            "query.days.list",
            category: "query",
            trigger: "ui",
            fields: [
                "limit": .int(limit),
                "filter": .string(filter.rawValue)
            ])
        do {
            let (db, _) = try ensureServices()
            let rows = try await db.pool.read { conn in
                try Aggregator.fetchDays(db: conn, limit: limit, provider: filter)
            }
            DeveloperLog.finishOperation(op, fields: [
                "rows": .int(rows.count),
                "filter": .string(filter.rawValue)
            ])
            return rows
        } catch {
            DeveloperLog.failOperation(op, error: error, fields: ["filter": .string(filter.rawValue)])
            throw error
        }
    }

    func fetchDayDetail(day: String) async throws -> DayDetail? {
        let filter = providerFilter
        let op = DeveloperLog.startOperation(
            "query.day.detail",
            category: "query",
            trigger: "ui",
            fields: [
                "day": .string(day),
                "filter": .string(filter.rawValue)
            ])
        do {
            let (db, _) = try ensureServices()
            let detail = try await db.pool.read { conn in
                try Aggregator.fetchDayDetail(db: conn, day: day, provider: filter)
            }
            DeveloperLog.finishOperation(op, fields: [
                "day": .string(day),
                "found": .bool(detail != nil),
                "filter": .string(filter.rawValue)
            ])
            return detail
        } catch {
            DeveloperLog.failOperation(op, error: error, fields: [
                "day": .string(day),
                "filter": .string(filter.rawValue)
            ])
            throw error
        }
    }

    func fetchSessionEventsOnDay(sessionId: String, day: String) async throws -> [SessionDetail.Event] {
        let op = DeveloperLog.startOperation(
            "query.session_events_on_day",
            category: "query",
            trigger: "ui",
            fields: [
                "session_id": .string(sessionId),
                "day": .string(day)
            ])
        do {
            let (db, _) = try ensureServices()
            let rows = try await db.pool.read { conn in
                try Aggregator.fetchEventsForSessionOnDay(db: conn, sessionId: sessionId, day: day)
            }
            DeveloperLog.finishOperation(op, fields: [
                "rows": .int(rows.count),
                "session_id": .string(sessionId),
                "day": .string(day)
            ])
            return rows
        } catch {
            DeveloperLog.failOperation(op, error: error, fields: [
                "session_id": .string(sessionId),
                "day": .string(day)
            ])
            throw error
        }
    }
}
