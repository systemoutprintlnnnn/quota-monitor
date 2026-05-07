import Foundation
import Testing
@testable import QuotaMonitor

/// State-machine tests for `ClaudeUsagePoller`. We exercise the actor by
/// driving `pollOnce()` directly with a scripted mock fetcher and asserting
/// on the actor-internal state via the `_*ForTest` accessors.
///
/// What this test pins down (each was a real production behaviour that
/// either shipped broken or was easy to break):
///
///   1. **Single-flight throttle** — two `pollOnce()` calls inside one
///      `minimumGap` window must collapse to one network call. Pre-fix,
///      a UI bug that wired pollOnce to a click handler hit the endpoint
///      every click and earned 429s within seconds.
///   2. **429 ladder** — first 429 → 5-minute backoff (often a transient
///      collision), subsequent 429s → 30-minute backoff. Success resets.
///   3. **Retry-After honoured** — server hint wins as long as it's >= 60s.
///   4. **Auth-class errors surface** — `noCredentials` / `unauthorized` /
///      `insufficientScope` MUST call `onSnapshot(.failure)` so the menu
///      bar can show a hint. 429 must NOT surface (it's transient).
///   5. **Successful fetch resets counters** — both rate-limit and auth.
@Suite("ClaudeUsagePoller state machine")
struct ClaudeUsagePollerTests {

    // MARK: - mock fetcher

    /// Scripted responder. Each call to `fetch()` consumes the next entry
    /// from `script`. If the script is exhausted, returns the last entry
    /// (so a "always succeed" test only needs one entry).
    actor MockFetcher: ClaudeUsageFetching {
        enum Step: Sendable {
            case success(ClaudeUsageSnapshot)
            case failure(any Error)
        }
        private var script: [Step]
        private var calls = 0
        init(script: [Step]) { self.script = script }

        func fetch() async throws -> ClaudeUsageSnapshot {
            calls += 1
            let step = script.count > 1 ? script.removeFirst() : (script.first ?? .failure(ClaudeUsageClient.FetchError.malformed("empty script")))
            switch step {
            case .success(let snap): return snap
            case .failure(let err):  throw err
            }
        }
        var callCount: Int { calls }
    }

    // MARK: - shared helpers

    private func makeDatabase() throws -> DatabaseManager {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexmonitor-tests", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(
            "poller-\(UUID().uuidString).sqlite")
        return try DatabaseManager(url: url)
    }

    private func emptySnapshot() -> ClaudeUsageSnapshot {
        // Empty windows are easier than a full fixture and exercise the
        // persist path without putting anything interesting in the DB.
        ClaudeUsageSnapshot(
            capturedAt: Date(),
            tier: nil,
            fiveHour: nil,
            sevenDay: nil,
            sevenDayOpus: nil,
            sevenDaySonnet: nil)
    }

    /// Box for capturing the result of `onSnapshot` callbacks across
    /// async boundaries. Sendable + locked so concurrent calls don't race.
    final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var inner: [Result<ClaudeUsageSnapshot, any Error>] = []
        func append(_ r: Result<ClaudeUsageSnapshot, any Error>) {
            lock.lock(); defer { lock.unlock() }
            inner.append(r)
        }
        var all: [Result<ClaudeUsageSnapshot, any Error>] {
            lock.lock(); defer { lock.unlock() }
            return inner
        }
    }

    private func makePoller(
        fetcher: any ClaudeUsageFetching,
        db: DatabaseManager,
        results: ResultBox
    ) -> ClaudeUsagePoller {
        ClaudeUsagePoller(
            client: fetcher,
            database: db,
            interval: .seconds(7200),
            onSnapshot: { result in
                results.append(result)
            })
    }

    // MARK: - 1. minimum-gap throttle

    @Test("two pollOnce() calls within minimumGap collapse to one fetch")
    func minimumGap_collapsesRapidCalls() async throws {
        let mock = MockFetcher(script: [.success(emptySnapshot())])
        let db = try makeDatabase()
        let results = ResultBox()
        let poller = makePoller(fetcher: mock, db: db, results: results)

        await poller.pollOnce()
        await poller.pollOnce()  // < 60s after the first → must be skipped

        let calls = await mock.callCount
        #expect(calls == 1, "second pollOnce inside minimumGap must NOT hit the network")
        #expect(results.all.count == 1)
    }

    // MARK: - 2. 429 ladder

    @Test("first 429: short 5-min backoff, no UI failure surface")
    func firstRateLimit_shortBackoff_noUIError() async throws {
        let mock = MockFetcher(script: [
            .failure(ClaudeUsageClient.FetchError.rateLimited(retryAfter: nil))
        ])
        let db = try makeDatabase()
        let results = ResultBox()
        let poller = makePoller(fetcher: mock, db: db, results: results)

        await poller.pollOnce()

        let count = await poller._consecutiveRateLimitsForTest
        let next = await poller._nextDelayOverrideSecondsForTest
        #expect(count == 1)
        #expect(next == 300, "1st 429 with no Retry-After → exactly 5-min override")
        #expect(results.all.isEmpty,
                "429 must NOT call onSnapshot — UI would lie about a transient signal")
    }

    @Test("second consecutive 429: long 30-min backoff")
    func secondRateLimit_longBackoff() async throws {
        let mock = MockFetcher(script: [
            .failure(ClaudeUsageClient.FetchError.rateLimited(retryAfter: nil)),
            .failure(ClaudeUsageClient.FetchError.rateLimited(retryAfter: nil))
        ])
        let db = try makeDatabase()
        let results = ResultBox()
        let poller = makePoller(fetcher: mock, db: db, results: results)

        await poller.pollOnce()
        // Reset minimumGap clock so the second pollOnce doesn't get
        // throttled out by the throttle test above.
        await poller._resetThrottleForTest()
        await poller.pollOnce()

        let count = await poller._consecutiveRateLimitsForTest
        let next = await poller._nextDelayOverrideSecondsForTest
        #expect(count == 2)
        #expect(next == 1800, "2nd consecutive 429 → 30-min override")
    }

    @Test("Retry-After header honoured (clamped to >= 60s)")
    func retryAfter_honoured() async throws {
        let mock = MockFetcher(script: [
            .failure(ClaudeUsageClient.FetchError.rateLimited(retryAfter: 900))
        ])
        let db = try makeDatabase()
        let results = ResultBox()
        let poller = makePoller(fetcher: mock, db: db, results: results)

        await poller.pollOnce()
        let next = await poller._nextDelayOverrideSecondsForTest
        #expect(next == 900, "Retry-After:900 must win over the 5-min default")
    }

    @Test("Retry-After below floor clamps to 60s")
    func retryAfter_belowFloor_clampsTo60() async throws {
        let mock = MockFetcher(script: [
            .failure(ClaudeUsageClient.FetchError.rateLimited(retryAfter: 5))
        ])
        let db = try makeDatabase()
        let results = ResultBox()
        let poller = makePoller(fetcher: mock, db: db, results: results)

        await poller.pollOnce()
        let next = await poller._nextDelayOverrideSecondsForTest
        #expect(next == 60, "must clamp to 60s floor — sub-minute polling earns more 429s")
    }

    // MARK: - 3. auth-class errors

    @Test("noCredentials surfaces to UI")
    func noCredentials_surfacesToUI() async throws {
        let mock = MockFetcher(script: [
            .failure(ClaudeUsageClient.FetchError.noCredentials)
        ])
        let db = try makeDatabase()
        let results = ResultBox()
        let poller = makePoller(fetcher: mock, db: db, results: results)

        await poller.pollOnce()

        let auth = await poller._consecutiveAuthFailuresForTest
        #expect(auth == 1)
        #expect(results.all.count == 1, "noCredentials MUST hit onSnapshot so the menu bar can prompt")
        if case .failure(let err) = results.all.first {
            #expect(err is ClaudeUsageClient.FetchError)
            if let fe = err as? ClaudeUsageClient.FetchError,
               case .noCredentials = fe {
                // good
            } else {
                Issue.record("expected noCredentials error, got \(err)")
            }
        } else {
            Issue.record("expected onSnapshot(.failure(noCredentials))")
        }
    }

    @Test("unauthorized surfaces to UI and bumps auth counter")
    func unauthorized_surfacesAndCounts() async throws {
        let mock = MockFetcher(script: [
            .failure(ClaudeUsageClient.FetchError.unauthorized)
        ])
        let db = try makeDatabase()
        let results = ResultBox()
        let poller = makePoller(fetcher: mock, db: db, results: results)

        await poller.pollOnce()

        let auth = await poller._consecutiveAuthFailuresForTest
        #expect(auth == 1)
        #expect(results.all.count == 1)
    }

    // MARK: - 4. success resets both counters

    @Test("success after 429 resets the rate-limit counter")
    func success_resetsRateLimitCounter() async throws {
        let mock = MockFetcher(script: [
            .failure(ClaudeUsageClient.FetchError.rateLimited(retryAfter: nil)),
            .success(emptySnapshot())
        ])
        let db = try makeDatabase()
        let results = ResultBox()
        let poller = makePoller(fetcher: mock, db: db, results: results)

        await poller.pollOnce()
        await poller._resetThrottleForTest()
        await poller.pollOnce()

        let rl = await poller._consecutiveRateLimitsForTest
        let auth = await poller._consecutiveAuthFailuresForTest
        #expect(rl == 0, "successful fetch must reset rate-limit counter")
        #expect(auth == 0)
        #expect(results.all.count == 1, "only the success surfaces; the 429 was suppressed")
        if case .success = results.all.first {} else {
            Issue.record("expected the surfaced result to be the success")
        }
    }

    @Test("success after auth failure resets the auth counter")
    func success_resetsAuthCounter() async throws {
        let mock = MockFetcher(script: [
            .failure(ClaudeUsageClient.FetchError.unauthorized),
            .success(emptySnapshot())
        ])
        let db = try makeDatabase()
        let results = ResultBox()
        let poller = makePoller(fetcher: mock, db: db, results: results)

        await poller.pollOnce()
        await poller._resetThrottleForTest()
        await poller.pollOnce()

        let auth = await poller._consecutiveAuthFailuresForTest
        #expect(auth == 0)
    }
}
