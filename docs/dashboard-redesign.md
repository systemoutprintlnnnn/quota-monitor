# Dashboard Redesign — Persistent Progress Tracker

Started: 2026-04-29 · Owner: Enter agent

## Goal

The current Dashboard (`Features/Dashboard/DashboardView.swift`, 706 LOC) is a
random vertical pile of seven sections divided by `Divider()`. Information
hierarchy is inverted (lifetime KPIs at the top, urgent quota forecast
buried), color is decorative not semantic, the whole layout assumes a 700px
column even on 1800px windows, and ~60% of what's shown duplicates the menu
bar.

Redefine the Dashboard around three questions a user actually opens it for:

1. **Forecast** — Am I about to blow a quota? (Codex 5h/7d + Claude session)
2. **Trends** — Is my usage trending up/down vs prior periods?
3. **Composition** — Where is the spend going (which models, which provider)?

Anything that doesn't serve those three questions gets deleted (not toggled).

## Phases

Each phase is an independent commit point. After every phase: build, restart,
visually verify nothing exploded, mark done.

### Phase 1 — Replace lifetime KPI cards with a 30d statline
- [x] Started
- [x] Done

Delete the 4-card row at the top (`API-equivalent value` / `Total tokens` /
`Sessions` / `Events`). Replace with a single line:
`Last 30 days · $X · Yk tokens · Z sessions`. Use existing
`ProviderStats.last30dValueUSD` / `last30dTokens` / `last30dSessionCount`
already wired for the menu bar — no new aggregation needed.

Touched: `DashboardView.swift` (`kpiRow`, `OverviewStats` consumers).

### Phase 2 — Merge Codex quota + Active 5-hour block into one Forecast card
- [x] Started
- [x] Done

Two sections collapse into one because they describe the same thing at
different granularities. New layout:

```
Codex · <plan>
  5h    [bar]  32%   resets in 2h 59m
  7d    [bar]  16%   hits 100% in ~19h  (red when projected to bust)
  Pace  ~$90/hr · ~366k tok/min
Claude · <plan>
  (mirror, only when /usage data is fresh; show stub when stale)
```

Drops: sample-source caption, burn rate detail row, "Active 5-hour block"
section header, four colored KPI tiles, projected EoB tile (folded into pace
line), "started at HH:MM" line, model list (moved to tooltip).

Touched: `DashboardView.swift` (`codexQuotaSection`, `billingBlockSection`,
new `ForecastSection.swift` likely created).

### Phase 3 — Trends: Daily + Monthly side-by-side, kill rate-limit history
- [x] Started
- [x] Done

Daily chart (left) and Monthly chart (right) sit side-by-side at width
≥ 1100, stack when narrower. Add one statline below:
`Today $X · 7d $Y · 30d $Z (Δ vs prior 30d ±N%)`.

Delete: `rate_limit_samples` history scatter chart. Useful diagnostic, not
useful daily — move it into a hidden Settings → Data → Diagnostics panel
(or just delete; nobody asks for it).

Touched: `DashboardView.swift` (`dailyChartSection`, `monthlyChartSection`,
`rateLimitHistorySection`), new `TrendsSection.swift`.

### Phase 4 — Composition: horizontal bar of top models + provider donut + insight
- [x] Started
- [x] Done

Replace current Models section with two-column layout:
- Left: horizontal bar list, top 8 models by 30d spend, each row shows model
  name, % of total, absolute $.
- Right: provider donut (codex vs claude), and one auto-generated insight
  sentence ("Opus 4 = 67% of spend, +12pp vs prior 30d").

If a single model > 50% of spend, show a small banner above:
`<Model> drives <X>% of cost — consider downgrading suitable tasks`.

Touched: new `CompositionSection.swift`, replaces `Models` block in
`DashboardView`. Need a small aggregator extension if model-level 30d
breakdown isn't already exposed.

### Phase 5 — Split file + responsive layout
- [x] Started
- [x] Done

`DashboardView.swift` becomes a slim container (< 150 LOC) that composes
`ForecastSection` / `TrendsSection` / `CompositionSection`. Apply
`ViewThatFits` or `GeometryReader`-based modifier so two-column layouts
collapse cleanly when window narrows. Remove all dead helpers
(`paceAccent`, `progressTint`, `quotaTint` — keep only what survives).

## Out of scope (don't get distracted)

- Notification logic (`QuotaNotifier`) — driven by `MenuBarSnapshot`,
  unaffected.
- Menu bar UI — keep its own role: "now / next 5h" snapshot. Dashboard is
  "trends + context".
- Color theme — only allow green (healthy) and red (warning); strip
  blue/orange/purple decorative accents but don't introduce a new palette.
- New data sources — only re-arrange / re-aggregate existing snapshots.

## Done criteria

Visual: open Dashboard, see three logically named sections. Top section
answers "am I in trouble", middle answers "how's my trend", bottom answers
"where's the money going". No section duplicates menu bar content
verbatim. No KPI tile that requires multiplying months in your head to
understand. Window resizes; content reflows.

Code: `DashboardView.swift` < 150 LOC. Three section files each < 250 LOC.
No dead helpers. No `Divider()` between top-level sections (use card
backgrounds for separation instead).

## Progress log

### Phase 1 — what landed (2026-04-29)
Swapped the four lifetime KPI tiles for a single 30d statline that mirrors
the menu bar's headline numbers (`MenuBarSnapshot.codex/claude.last30d*`).
The statline reacts to `providerFilter`: sums both providers when `.all`,
restricts when narrowed. Deleted `kpiRow`, `currentPayoff`, and
`payoffAccent`. Retired the four lifetime KPI L10n keys
(`kpiApiEquivalentValue`, `kpiTotalTokens`, `kpiPayoff`) — `kpiSessions` /
`kpiEvents` survive because History/Sessions still consume them. Added two
new keys: `dashboardLast30dStatline(usd:tokens:sessions:)` and
`dashboardLast30dStatlineEmpty`. The `kpi(title:value:accent:)` helper is
parked with a TODO marker; Phase 2 deletes it once `billingBlockBody` is
gone. Files: `DashboardView.swift`, `Core/Localization/L10n.swift`.

### Phase 2 — what landed (2026-04-29)
Created `Features/Dashboard/Sections/ForecastSection.swift` (~225 LOC). It
collapses the old `codexQuotaSection` + `billingBlockSection` into one
"Forecast" block with a per-provider card (`Codex` / `Claude`). Each card
uses a shared `QuotaProgressRow` (also defined in the file) which only
applies green/red semantics — orange tints stripped — and a single pace
line below. Dropped: sample-source caption, "Active 5-hour block" header,
the four KPI tiles (`kpiSpentSoFar`/`Tokens`/`ProjectedEob`/`Remaining`)
inside the billing-block body, the "started at HH:MM" line, and the
recent-blocks list (the Sessions tab covers that ground). The model list
collapsed into a `.help(...)` tooltip on the Claude card header. Two-card
layout uses `ViewThatFits` so it stacks on narrow windows. Wiring in
`DashboardView` swapped the two old `Divider() + section(...)` blocks for
one `ForecastSection(snapshot:blocks:providerFilter:)` call. Deleted
`codexQuotaSection`, `quotaCard`, `quotaTint`, `formatRemainingDuration`,
`relativeTime`, `billingBlockSection`, `billingBlockBody`,
`recentHistory`, `recentBlocksList`, `recentBlockRow`, `paceAccent`,
`progressTint`, `formatMinutes`, and the `kpi(...)` helper from
`DashboardView.swift`. Added `forecast*` L10n keys; dropped no keys
(removed-from-Dashboard ones still consumed by Sessions/History). Files:
new `Features/Dashboard/Sections/ForecastSection.swift`,
`Features/Dashboard/DashboardView.swift`,
`Core/Localization/L10n.swift`.

### Phase 3 — what landed (2026-04-29)
Created `Features/Dashboard/Sections/TrendsSection.swift` (~210 LOC). It
wraps the daily + monthly bar charts in a `ViewThatFits` so they sit
side-by-side at wide widths and stack when the window narrows. Beneath the
charts is a single statline:
`Today $X · 7d $Y · 30d $Z (Δ vs prior 30d ±N%)`. To compute the prior-30d
delta I needed a 60-day daily series — added a new `dailyExtended:
[DailyPoint]` field to `DashboardSnapshot` and a second
`fetchDaily(db:days:60)` call inside `Aggregator.loadDashboard`. Charts
swap the previous decorative `accentColor` highlight for plain green per
the redesign palette. The orange/green month-over-month delta badge is
gone — the statline carries the same info now. Deleted from `DashboardView`:
`dailySection`, `tooltip(for:)`, `monthlySection`, `monthOverMonthDelta`,
`rateLimitHistory`, plus the `selectedDay` state. The
`recentRateLimits` data is still aggregated and persisted; just no longer
displayed (per spec). Files: new
`Features/Dashboard/Sections/TrendsSection.swift`,
`Features/Dashboard/DashboardView.swift`,
`Core/Analytics/Aggregator.swift`,
`Core/Localization/L10n.swift`.

### Phase 4 — what landed (2026-04-29)
Created `Features/Dashboard/Sections/CompositionSection.swift` (~225 LOC).
Layout: optional banner ("X drives Y% of spend — consider downgrading…")
on top of a two-column `ViewThatFits`. Left column is a horizontal bar
list of the top 8 models from the last 30 days; right column is a Swift
Charts SectorMark donut (Codex vs Claude) with a legend and an
auto-insight sentence ("Opus 4 = 67% of spend, +12pp vs prior 30d"). The
30d window data did not exist on the snapshot, so I extended
`DashboardSnapshot` with three new fields — `modelShares30d`,
`modelSharesPrior30d`, and `providerShares30d` — and added two new
aggregator queries: `fetchModelShares(db:provider:sinceDays:untilDaysAgo:)`
(half-open time-window variant) and `fetchProviderShares30d(db:)`. Also
added a small `ProviderShare` struct since `ProviderStats` carries too
much menu-bar-specific cruft for the donut. Two-color discipline holds:
banner uses red, dominant model bar flips to red at >50%, donut paints
codex green / claude grey-secondary. Deleted `modelSection` and
`modelRow` from `DashboardView`. Files: new
`Features/Dashboard/Sections/CompositionSection.swift`,
`Features/Dashboard/DashboardView.swift`,
`Core/Analytics/Aggregator.swift`,
`Core/Localization/L10n.swift`.

### Phase 5 — what landed (2026-04-29)
`DashboardView.swift` is now 107 LOC. It owns nothing but the statline, an
empty state, and a `VStack { Forecast / Trends / Composition }` body.
Removed `import Charts` (no chart calls left in this file). All three
sections wrap themselves in
`RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06))`,
which means there are zero `Divider()` instances between top-level
sections — the cards do the visual separation. Inside ForecastSection,
the per-provider sub-cards switched to a `controlBackgroundColor` fill +
hairline border so they remain visible against the parent card. The
provider filter picker stays in `MainWindowView` (it sits above all three
tabs, not just Dashboard) — unchanged. No new dead helpers introduced.
Final LOCs: DashboardView 107, ForecastSection 240, TrendsSection 218,
CompositionSection 222 — all under the 250 / 150 targets. Files:
`Features/Dashboard/DashboardView.swift`,
`Features/Dashboard/Sections/ForecastSection.swift`.
