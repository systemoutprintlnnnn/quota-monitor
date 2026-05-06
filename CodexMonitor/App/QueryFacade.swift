import Foundation

// Pure pass-throughs to Aggregator. Lives here so the AppEnvironment file
// stays focused on shared mutable state + lifecycle, not query plumbing.

extension AppEnvironment {

    // MARK: - Sessions queries (used by Sessions tab)

    func fetchSessionsList(
        sort: SessionSort,
        search: String
    ) async throws -> [SessionRow] {
        let (db, _) = try ensureServices()
        let filter = providerFilter
        return try await db.pool.read { conn in
            try Aggregator.fetchSessions(
                db: conn, sort: sort, search: search, provider: filter)
        }
    }

    func fetchSessionDetail(sessionId: String) async throws -> SessionDetail? {
        let (db, _) = try ensureServices()
        return try await db.pool.read { conn in
            try Aggregator.fetchSessionDetail(db: conn, sessionId: sessionId)
        }
    }

    // MARK: - History queries (used by History tab)

    func fetchDaysList(limit: Int = 365) async throws -> [DaySummary] {
        let (db, _) = try ensureServices()
        let filter = providerFilter
        return try await db.pool.read { conn in
            try Aggregator.fetchDays(db: conn, limit: limit, provider: filter)
        }
    }

    func fetchDayDetail(day: String) async throws -> DayDetail? {
        let (db, _) = try ensureServices()
        let filter = providerFilter
        return try await db.pool.read { conn in
            try Aggregator.fetchDayDetail(db: conn, day: day, provider: filter)
        }
    }

    func fetchSessionEventsOnDay(sessionId: String, day: String) async throws -> [SessionDetail.Event] {
        let (db, _) = try ensureServices()
        return try await db.pool.read { conn in
            try Aggregator.fetchEventsForSessionOnDay(db: conn, sessionId: sessionId, day: day)
        }
    }
}
