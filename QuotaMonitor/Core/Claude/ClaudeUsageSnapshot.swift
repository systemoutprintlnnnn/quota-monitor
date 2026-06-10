import Foundation

/// Domain-level view of Anthropic's `/api/oauth/usage` response. Decoupled
/// from the wire shape so a future API tweak only changes the mapping.
///
/// Source: [CodexBar `docs/claude.md`] documents the same endpoint and
/// fields. Anthropic doesn't publicly advertise this — it backs the
/// official `claude` CLI's quota indicator — so the shape may evolve. We
/// decode defensively (every nested field optional).
struct ClaudeUsageSnapshot: Equatable, Sendable {
    let capturedAt: Date
    /// "pro" | "max5x" | "max20x" | "team" | "enterprise" | "free" — used
    /// for the badge next to the Claude block. Nil = the API didn't say.
    let tier: String?
    let fiveHour: Window?
    /// Last known 5-hour window after Anthropic has stopped returning
    /// `five_hour` because that window reset and no new current window has
    /// started. UI can render this through the stale-row treatment without
    /// confusing it with the active `fiveHour` slot.
    let staleFiveHour: Window?
    let sevenDay: Window?
    /// Per-model 7-day windows. Pro / Max users see Opus + Sonnet
    /// separately because Opus has a tighter sub-limit; Free / lower tiers
    /// may omit one or both.
    let sevenDayOpus: Window?
    let sevenDaySonnet: Window?

    init(
        capturedAt: Date,
        tier: String?,
        fiveHour: Window?,
        staleFiveHour: Window? = nil,
        sevenDay: Window?,
        sevenDayOpus: Window?,
        sevenDaySonnet: Window?
    ) {
        self.capturedAt = capturedAt
        self.tier = tier
        self.fiveHour = fiveHour
        self.staleFiveHour = staleFiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
    }

    func preservingStaleFiveHour(from previous: ClaudeUsageSnapshot?) -> ClaudeUsageSnapshot {
        guard fiveHour == nil,
              staleFiveHour == nil,
              hasCurrentQuotaWindow,
              let previousWindow = previous?.fiveHour ?? previous?.staleFiveHour,
              previousWindow.resetAt <= capturedAt else {
            return self
        }
        return ClaudeUsageSnapshot(
            capturedAt: capturedAt,
            tier: tier,
            fiveHour: fiveHour,
            staleFiveHour: previousWindow,
            sevenDay: sevenDay,
            sevenDayOpus: sevenDayOpus,
            sevenDaySonnet: sevenDaySonnet)
    }

    private var hasCurrentQuotaWindow: Bool {
        sevenDay != nil || sevenDayOpus != nil || sevenDaySonnet != nil
    }

    struct Window: Equatable, Sendable {
        let usedPercent: Double
        let resetAt: Date
        /// Window duration in seconds, derived from labels in the API
        /// response (`five_hour` → 18000, `seven_day` → 604800).
        let windowDuration: TimeInterval

        var remainingPercent: Double { max(0, 100 - usedPercent) }
        var timeUntilReset: TimeInterval { resetAt.timeIntervalSinceNow }

        /// Same definition as `RateLimitSnapshot.Window.paceRatio`. Lets us
        /// reuse the QuotaRow UI without forking it for Anthropic.
        func paceRatio(now: Date = Date()) -> Double? {
            let elapsed = windowDuration - resetAt.timeIntervalSince(now)
            guard elapsed > 0, windowDuration > 0 else { return nil }
            let elapsedFraction = elapsed / windowDuration
            guard elapsedFraction > 0 else { return nil }
            return (usedPercent / 100.0) / elapsedFraction
        }

        /// Human-readable verdict, identical formatting to Codex.
        func paceLabel(now: Date = Date()) -> QuotaPaceLabel.Result? {
            QuotaPaceLabel.make(
                usedPercent: usedPercent,
                paceRatio: paceRatio(now: now),
                timeUntilReset: max(0, resetAt.timeIntervalSince(now)))
        }
    }
}
