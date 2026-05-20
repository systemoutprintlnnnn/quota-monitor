import Foundation

// Pure pass-throughs to Aggregator. Lives here so the AppEnvironment file
// stays focused on shared mutable state + lifecycle, not query plumbing.

extension AppEnvironment {

    // MARK: - Sessions queries (used by Sessions tab)

    func fetchSessionsList(
        sort: SessionSort,
        search: String
    ) async throws -> [SessionRow] {
        DeveloperLog.info(
            "fetchSessionsList started sort=\(sort) searchLength=\(search.count) filter=\(providerFilter.rawValue)",
            category: "query")
        let (db, _) = try ensureServices()
        let filter = providerFilter
        let rows = try await db.pool.read { conn in
            try Aggregator.fetchSessions(
                db: conn, sort: sort, search: search, provider: filter)
        }
        DeveloperLog.info("fetchSessionsList succeeded rows=\(rows.count) filter=\(filter.rawValue)", category: "query")
        return rows
    }

    func fetchSessionDetail(sessionId: String) async throws -> SessionDetail? {
        DeveloperLog.info("fetchSessionDetail started sessionId=\(sessionId)", category: "query")
        let (db, _) = try ensureServices()
        let detail = try await db.pool.read { conn in
            try Aggregator.fetchSessionDetail(db: conn, sessionId: sessionId)
        }
        DeveloperLog.info("fetchSessionDetail succeeded sessionId=\(sessionId) found=\(detail != nil)", category: "query")
        return detail
    }

    // MARK: - History queries (used by History tab)

    func fetchDaysList(limit: Int = 365) async throws -> [DaySummary] {
        DeveloperLog.info(
            "fetchDaysList started limit=\(limit) filter=\(providerFilter.rawValue)",
            category: "query")
        let (db, _) = try ensureServices()
        let filter = providerFilter
        let rows = try await db.pool.read { conn in
            try Aggregator.fetchDays(db: conn, limit: limit, provider: filter)
        }
        DeveloperLog.info("fetchDaysList succeeded rows=\(rows.count) filter=\(filter.rawValue)", category: "query")
        return rows
    }

    func fetchDayDetail(day: String) async throws -> DayDetail? {
        DeveloperLog.info("fetchDayDetail started day=\(day) filter=\(providerFilter.rawValue)", category: "query")
        let (db, _) = try ensureServices()
        let filter = providerFilter
        let detail = try await db.pool.read { conn in
            try Aggregator.fetchDayDetail(db: conn, day: day, provider: filter)
        }
        DeveloperLog.info("fetchDayDetail succeeded day=\(day) found=\(detail != nil) filter=\(filter.rawValue)", category: "query")
        return detail
    }

    func fetchSessionEventsOnDay(sessionId: String, day: String) async throws -> [SessionDetail.Event] {
        DeveloperLog.info("fetchSessionEventsOnDay started sessionId=\(sessionId) day=\(day)", category: "query")
        let (db, _) = try ensureServices()
        let rows = try await db.pool.read { conn in
            try Aggregator.fetchEventsForSessionOnDay(db: conn, sessionId: sessionId, day: day)
        }
        DeveloperLog.info("fetchSessionEventsOnDay succeeded rows=\(rows.count) sessionId=\(sessionId) day=\(day)", category: "query")
        return rows
    }
}
