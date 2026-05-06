# Project survey — 2026-04-30

After many rounds of incremental changes (Dashboard redesign, i18n, Claude poller hardening, menu bar UI churn), the project is functional but accumulating drag. Here's the lay of the land and the cuts I'd recommend.

## The shape of things

```
CodexMonitor/CodexMonitor/
├── App/         CodexMonitorApp.swift, AppEnvironment.swift  (god-object, 522 LOC)
├── Core/
│   ├── Analytics/   Aggregator.swift (1187 LOC), BillingBlocks.swift
│   ├── AppServer/   Codex CLI bridge
│   ├── Claude/      Client + Poller + Snapshot + Hydrator (new)
│   ├── Importer/    Codex + Claude JSONL ingestion
│   ├── Localization/ L10n.swift (607 LOC, ~30% dead)
│   ├── Models/      RateLimitSnapshot, QuotaPaceLabel
│   ├── Pricing/     LiteLLM + catalog
│   ├── RateLimits/  Codex poller, notifier
│   ├── Settings/    SettingsStore (8 keys)
│   └── Storage/     GRDB
├── Features/
│   ├── Dashboard/   DashboardView + Sections/{Forecast, Trends, Composition}
│   ├── History/     HistoryView (357 LOC)
│   ├── MainWindow/  Tab switcher + provider filter
│   ├── MenuBar/     MenuBarContentView (650 LOC, internal subviews)
│   ├── Onboarding/  Language picker
│   ├── Sessions/    List + detail
│   └── Settings/    SettingsView (483 LOC, three tabs in one file)
└── Resources/
```

## What's actually broken / vestigial

**Dead L10n entries (zero references)** — about 30 `static var` / `static func` accumulated as we removed UI:
- `helpCodexPlanBadge`, `idleLimits(_:)`, `compositionBanner(model:percent:)` — recently-deleted UI fragments
- `kpiTotalSpend / kpiSpendToday / kpiSpend7d / kpiSpend30d / kpiSpentSoFar / kpiProjectedEob / kpiRemaining / kpiWindowEnds` — old KPI grid
- `codexQuotaTitle / fiveHourWindow / weeklyWindow / active5hBlock / noClaudeUsageYet` — pre-redesign headers
- `percentUsed / sampleSource / hits100InPace / percentPerHour / burnIdle` — old quota-card sublabels
- `justNow / minutesAgo / hoursAgo / daysAgo` — replaced everywhere by `RelativeDateTimeFormatter`
- `last14Days / last12Months / chartAxisMonth / chartAxisTime / chartAxisUsedPct / chartAxisSeries` — chart-range labels and axes from the deleted dual-chart layout
- `peakValue / sessionsCount / samplesCount / rateLimit24h / noSamplesYet` — rate-limit-history scatter
- `runsOutIn / onPace / inDeficit / inReserve / measured5hBlock / forecastModelsTooltip / blockDurationEvents / startedAt / tokPerMinAndCostHr / costPerHourShort / burnRate / recentBlocks`

**Settings keys with no live consumer**: `settings.codexMonthlyUSD`, `settings.claudeMonthlyUSD` — feeders for the deleted "payoff" KPI. Either delete the keys + UI rows, or wire them somewhere.

## What scares me

**Test coverage is essentially one file**: `Tests/CodexMonitorTests/ClaudeUsageDecoderTests.swift`. Zero tests for:
- `Aggregator.swift` (1187 LOC of SQL — your `$XXX.XX` flow, monthly bucketing, burn-rate regression all untested)
- `RolloutParser.swift` (Codex JSONL parsing for both <0.40 and ≥0.40 shapes — and we just changed it to derive titles from `cwd`)
- `BillingBlocks.swift` (290 LOC of session-block math — drives the menu-bar 5h widget)
- `ClaudeUsagePoller.swift` (back-off / `minimumGap` / `nextDelayOverride` — stateful and a known footgun)
- `ClaudeUsageHydrator.swift` (just added; obvious round-trip test against `Poller.persist`)

**`AppEnvironment.swift` (522 LOC) is a god-object**. 17 `@Observable` properties, 6 lazy services, methods for: poller wiring, manual refresh, scan kickoff, pricing fetching, CSV export, window-policy, and sessions/history query proxies. Realistic split: extract `PricingController`, `ScanController`, `QueryFacade`; leave `AppEnvironment` as live-snapshot store + poller wiring.

**`Aggregator.swift` (1187 LOC) is one enum with everything**. Natural cuts: `AggregatorReports` (dashboard + monthly + daily + provider stats), `AggregatorSessions`, `AggregatorHistory`, `AggregatorRateLimits`.

**Refresh fan-out**: a single user click can trigger `refreshMenuBar` 2-3 times. Cheap (DB-only), but auditing this prevents future cycles. Specifically: `providerFilter` change → `refreshDashboard` → `refreshMenuBar`; Codex `refreshRateLimits` and `runScan` also both call `refreshMenuBar`.

## Files exceeding 300 LOC (split candidates)

| File | LOC | Notes |
|---|---|---|
| `Core/Analytics/Aggregator.swift` | 1187 | Split by query group |
| `Features/MenuBar/MenuBarContentView.swift` | 650 | `Claude5hRow`, `QuotaRow`, `CopyButton`, `claudeOAuthInner`, `claudeFallbackInner` are subviews waiting to be extracted |
| `Core/Localization/L10n.swift` | 607 | Will drop ~30% after dead-code purge |
| `App/AppEnvironment.swift` | 522 | God-object split |
| `Features/Settings/SettingsView.swift` | 483 | Three tabs in one file |
| `Core/Claude/ClaudeUsageClient.swift` | 445 | |
| `Features/History/HistoryView.swift` | 357 | |
| `Core/Importer/ClaudeImportEngine.swift` | 349 | |
| `Core/Importer/RolloutParser.swift` | 339 | |
| `Core/Pricing/PricingService.swift` | 323 | |
| `Core/AppServer/AppServerClient.swift` | 302 | |

## Polling cadence map

| Site | Cadence | Op | UI surface |
|---|---|---|---|
| `RateLimitPoller` | 300s (settings-driven) | Codex `account/rateLimits/read` | yes |
| `ClaudeUsagePoller` | 7200s hard-coded; 60s minGap; 1800s/300s back-off | POST `/api/oauth/usage` | 429 NOT surfaced; auth errors do |
| `ClaudeUsageHydrator` | once at boot | DB read | warms `latestClaudeUsage` |
| `LiteLLM pricing fetch` | once at boot if >24h stale + manual | HTTP | yes |
| `MenuBarExtra .task` | first popover open | `refresh*` ×3 + `startBackgroundPolling` | yes |
| `MenuBar onChange(scenePhase==.active)` | every foreground | `refreshMenuBar` (DB only) | yes |
| `DashboardView .task` | view appear | `refreshDashboard` | yes |
| `MenuBar Refresh button` | click | `refreshRateLimits` + `runScan` (NOT Claude) | yes |

## Recommendations, in priority order

### P0 — Bug-hunting safety nets (Do these first)
1. **Aggregator burn-rate + 30d window regression test**. The `$XXX.XX` headline went wrong twice in three days. A single fixture test pinning `fetchPerProviderStats` against a seeded DB would catch the next drift.
2. **`RolloutParser` snapshot test** — three real rollout JSONLs (Codex 0.39, 0.40, current). The `cwd → title` change we just made has zero coverage.
3. **`ClaudeUsagePoller` state-machine test** — `minimumGap`, `consecutiveRateLimits` ladder, `nextDelayOverride` honoring `Retry-After`. This logic has been touched in 4 separate sessions; it deserves a test before the next change.

### P1 — Dead-code purge (mechanical, half a day)
4. Delete the ~30 dead L10n entries listed above.
5. Decide `codexMonthlyUSD` / `claudeMonthlyUSD` settings keys: keep + wire, or delete with UI.
6. Audit settings UI for orphan rows (the SettingsView Pricing tab still has a "monthly bills" section iirc).

### P2 — Structural splits (can be done piecemeal)
7. `AppEnvironment` → extract `PricingController`, `ScanController`, `QueryFacade`. Leaves ~200 LOC of poller wiring + live snapshots.
8. `Aggregator` → split into 4 files by query domain.
9. `MenuBarContentView` → extract `Claude5hRow`, `QuotaRow`, `ClaudeProviderBlock` to own files (already named subviews, just move them).
10. `SettingsView` → one file per tab.

### P3 — Polish
11. Audit refresh fan-out so `refreshMenuBar` fires once per user action, not 2-3 times. Cheap to do; clarity win.
12. `ClaudeUsageHydrator` round-trip test (after #3 above is in place — same test scaffolding).
13. `Tests/` directory currently has only `ClaudeUsageDecoderTests.swift`; everything else is fixtures. Set a baseline expectation that new Core code ships with at least one fixture test.

## What I'd do next session, concretely

If you want me to start chipping away, the highest-leverage single sitting is **P0 #1 (Aggregator burn-rate test)** — it locks down the number that's most visible and most prone to silent drift. Second-highest is **P1 #4 (L10n purge)** — pure deletion, drops the largest file by ~150 LOC, no behavior change.

Want me to proceed with either or both?

---

## Update — 2026-04-30 evening

User said "do it all", so this entire audit was executed in one sitting:

**P0 (test safety net) — DONE**
- `Tests/CodexMonitorTests/RolloutParserTests.swift` (6 tests) — pins title-from-cwd fallback, subagent metadata, cumulative→delta conversion, embedded rate-limit extraction, legacy gpt-5 fallback. Fixtures live under `Tests/CodexMonitorTests/Fixtures/Rollout/`.
- `Tests/CodexMonitorTests/AggregatorTests.swift` (6 tests) — pins `fetchPerProviderStats` zero-fill, the 30d-window exclusive trailing edge, DISTINCT session_id counting, `fetchDaily` zero-fill ordering, `fetchProviderShares30d` always-emits-both, ProviderFilter clause restriction.
- `Tests/CodexMonitorTests/ClaudeUsagePollerTests.swift` (9 tests) — pins minimumGap throttle, the 5min→30min 429 ladder, Retry-After honoured (clamped to 60s floor), auth-class errors surface to UI, 429 does NOT surface, success resets counters. Required adding `protocol ClaudeUsageFetching` + a few `_*ForTest` accessors on the actor.
- `Tests/CodexMonitorTests/ClaudeUsageHydratorTests.swift` (5 tests) — round-trips all 4 windows, newest-sample-wins, opus/sonnet without plain secondary row, empty DB → nil, codex source_kind ignored.

Total test count went from **11 → 37**, all green.

**P1 (deletion) — DONE**
- L10n purge: ~50 dead entries removed (`L10n.swift` shrunk by ~150 LOC). Verified each via `grep` before deletion.
- `settings.codexMonthlyUSD` / `settings.claudeMonthlyUSD` UserDefaults keys removed; matching SettingsStore properties + Pricing tab UI rows + L10n strings (`payoffHint`, `sectionSubscriptionCost`, `codexChatgptPlan`, `claudeCodePlan`) all gone.

**P2 (structural splits) — DONE**
- `Aggregator.swift` (1187 LOC) → `Aggregator.swift` (types) + `AggregatorReports.swift` + `AggregatorSessions.swift` + `AggregatorHistory.swift` + `AggregatorRateLimits.swift`. Public surface unchanged (`enum Aggregator { ... }` extended in each file).
- `AppEnvironment.swift` (522 LOC) → `AppEnvironment.swift` (~250 LOC, lifecycle + shared state) + `PricingController.swift` + `ScanController.swift` + `QueryFacade.swift`. Same `@Observable` storage; methods moved to extensions.
- `MenuBarContentView.swift` (650 LOC) → main view (~120 LOC) + `ProviderBlock.swift` + `ScanStatusView.swift` + `QuotaRow.swift` + `Claude5hRow.swift` + `CopyButton.swift`.
- `SettingsView.swift` (483 LOC) → main view (~30 LOC) + `GeneralSettingsTab.swift` + `PricingSettingsTab.swift` + `DataSettingsTab.swift`.

**P3 (cleanup) — DONE**
- Refresh fan-out de-duplication: `runScan()` was calling `refreshDashboard()` AND `refreshMenuBar()`, but `refreshDashboard()` already chains to `refreshMenuBar()` at its tail. Removed the duplicate call — second-redundant DB read gone, occasional KPI flicker gone.
- `ClaudeUsageHydrator` round-trip test (in P0 above).

**Build & runtime**
- `./build.sh debug` clean.
- `swift test` → 37/37 green.
- App restarted, PID 52827 confirmed running. Menu bar headline still renders, Dashboard tabs still load.

What's NOT done from the original survey: the deeper refactors in Section 4.5 (Notifier strategy, Pricing fetch retry/backoff) and the open product question about whether the Composition donut still earns its space — those are judgment calls, not mechanical wins, and warrant a separate conversation.
