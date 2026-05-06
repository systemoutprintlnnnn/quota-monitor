# Codex CLI v0.115 — Probe Findings

Captured against `codex app-server` on macOS 15.5 / arm64, CLI version `0.115.0`,
user plan type `prolite` (upstream) / `plus` (per `account/read`).

## Methods that work

### `initialize`
Request:
```json
{"jsonrpc":"2.0","id":"init","method":"initialize",
 "params":{"clientInfo":{"name":"probe","version":"0"},
           "protocolVersion":"0.1.0","capabilities":{}}}
```
Response:
```json
{"id":"init","result":{
  "userAgent":"probe/0.115.0 (Mac OS 15.5.0; arm64) iTerm.app/3.6.10 (probe; 0)",
  "platformFamily":"unix","platformOs":"macos"}}
```
Required before any other call.

### `account/read`
Returns:
```json
{"id":"acc","result":{"account":{"type":"chatgpt","email":"...","planType":"plus"},
                       "requiresOpenaiAuth":true}}
```

## Method with a known bug on this CLI

### `account/rateLimits/read`
Upstream call to `https://chatgpt.com/backend-api/wham/usage` SUCCEEDS, but the CLI's
strict deserializer rejects `plan_type: "prolite"`. The complete usage JSON appears
in the error message (after `body=`).

Real response body extracted from the error:
```json
{
  "user_id": "...",
  "account_id": "...",
  "email": "...",
  "plan_type": "prolite",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {
      "used_percent": 7,
      "limit_window_seconds": 18000,
      "reset_after_seconds": 331,
      "reset_at": 1777284167
    },
    "secondary_window": {
      "used_percent": 75,
      "limit_window_seconds": 604800,
      "reset_after_seconds": 155153,
      "reset_at": 1777438990
    }
  },
  "code_review_rate_limit": null,
  "additional_rate_limits": [
    {
      "limit_name": "GPT-5.3-Codex-Spark",
      "metered_feature": "codex_bengalfox",
      "rate_limit": { "allowed": true, "limit_reached": false,
                      "primary_window": {...}, "secondary_window": {...} }
    }
  ],
  "credits": { "has_credits": false, "unlimited": false,
               "overage_limit_reached": false, "balance": "0",
               "approx_local_messages": [0,0], "approx_cloud_messages": [0,0] },
  "spend_control": { "reached": false },
  "rate_limit_reached_type": null,
  "promo": null,
  "referral_beacon": null
}
```

**Implications for our client:**
1. Treat `plan_type` as a free-form `String`, never enumerate.
2. When `account/rateLimits/read` returns `error`, attempt to extract the `body=`
   suffix from `error.message` and decode it as the same shape we'd accept from
   `result`.
3. Two windows we care about: `primary_window` (5h, 18000s) and
   `secondary_window` (7d, 604800s).

## Difference from original codex-pacer

The original Rust code in `src-tauri/src/rate_limits.rs` calls `rateLimits/read`.
That method **does not exist** in CLI 0.115. The current method is
`account/rateLimits/read`. The original also expected a different response shape
(camelCase `usedPercent`, `windowDurationMins`); the live shape is snake_case.

## Rollout JSONL shape

Each line is independently parseable JSON:
```json
{"timestamp": "<ISO8601>", "type": "<discriminator>", "payload": { ... }}
```

Confirmed `type` values so far:
- `session_meta` — `payload` includes `id`, `timestamp`, `cwd`, `originator`,
  `cli_version`, `instructions`, `source`, `model_provider`, `git`.
- `response_item` — `payload.type` is one of `message`, `function_call`,
  `function_call_output`, etc., with role/content arrays.

Token-usage events arrive as their own discriminator: `event_msg` outer
records whose inner `payload.type` is `token_count`. The parser at
`Core/Importer/RolloutEvent.swift:210` extracts the cumulative usage block
from `payload.info.total_token_usage` and lets `Importer` reconcile it into
deltas (with reset detection when totals decrease).

## Other available app-server methods (from rejection error list)

Worth investigating later:
- `thread/list`, `thread/read`, `thread/loaded/list` — server-side session index
- `model/list` — official model catalog
- `getAuthStatus`, `getConversationSummary`
- `config/read` — possibly replaces our `~/.codex/config.toml` parsing

## Risk register (next-likely-to-break code paths)

A short list of places where a silent regression would be hardest to
notice — kept here so the next agent / future me knows where to look
first when "the menu bar number is wrong."

### 1. `ClaudeUsageDecoder` — Anthropic /api/oauth/usage shape drift
- **Why risky**: Anthropic ships A/B-test keys (`iguana_necktie`,
  `omelette_promotional`, …) and silently flipped utilization from
  0..1 ratio to 0..100 percent once already (Day 25 → Day 26 6000% bug).
- **Coverage today**: 9 tests in `ClaudeUsageDecoderTests` pinned
  against real captured fixtures (`Tests/.../Fixtures/ClaudeUsage/*.json`).
- **What to do if it drifts again**: capture the new response into
  `Fixtures/ClaudeUsage/`, add a fixture-driven test, **do not** widen
  the `<=1.5 → ratio*100, else → as-is` heuristic blindly.

### 2. `ClaudeUsagePoller` — 2-hour cadence + 429 backoff ladder
- **Why risky**: Anthropic edge rate-limits the `/usage` endpoint
  aggressively. Wiring `pollOnce()` to a click handler or NSWindow
  appearance will silently be throttled by `minimumGap = 30 min`, or
  earn HTTP 429s that compound the back-off.
- **Coverage today**: 6 state-machine tests in `ClaudeUsagePollerTests`.
- **Don't**: don't shorten `minimumGap`, don't share the Codex poll
  interval setting, don't add extra trigger sites.

### 3. `BillingBlocks` — 5-hour billing-block math (ported from ccusage)
- **Why risky**: full of edge cases (gap > 5h splits, hour-flooring of
  block start in UTC, active-vs-closed determination at "now"). A bug
  here directly mislabels "Pace ~$X.XX/hr" + "Active 5h block."
- **Coverage today**: 6 DB-driven tests in `BillingBlocksTests`
  (added 2026-04-30; was 0 prior).
- **Watch**: any change to `identifyBlocks` or `floorToHour`.

### 4. `AppServerClient.salvageBodyFromErrorMessage` — `prolite` plan-type salvage
- **Why risky**: when `plan_type: "prolite"`, the CLI's deserializer
  rejects the response but embeds the intact JSON body after `body=`
  in the error. Without the brace-balance walker, prolite users see
  "no quota data" forever.
- **Coverage today**: 6 tests in `SalvageBodyFromErrorMessageTests`
  (added 2026-04-30).
- **Watch**: changes to the CLI error format. If the marker shifts
  from `body=` to something else, the tests + this code both die
  silently — regression must be caught by an end-to-end integration
  test someday, not just the unit tests.

### 5. `PricingService.backfillAllValues` — single SQL UPDATE that prices everything
- **Why risky**: a typo in the JOIN, a wrong column name, or an `OR`
  that misses a row would silently corrupt every dollar amount in the
  menu bar.
- **Coverage today**: 5 tests in `PricingValueBackfillTests` (added
  2026-04-30) pin: codex formula subtracts cached from input, claude
  formula is additive across input/cached/cache_creation, unknown
  model_id leaves rows alone, idempotent on re-run, price edit
  reprices only matching rows.
- **Watch**: any new token category (e.g. a future `vision_tokens`
  column) needs to be added to the SQL **and** a test.

### 6. `RolloutParser` token reconciliation
- **Why risky**: the cumulative→delta logic with reset detection is
  load-bearing for every Codex import. If we miss a reset we double-
  count tokens; if we false-positive a reset we lose them.
- **Coverage today**: handful of tests in `RolloutParserTests` plus
  `Aggregator` integration.
- **Watch**: changes to Codex CLI's `total_token_usage` schema —
  CLI 0.40 already truncated headers in older rollouts (see
  `scanErrorsExplain` in L10n.swift).

### 7. `LocalizationStore` runtime locale switch + `RelativeDateTimeFormatter`
- **Why risky**: `RelativeDateTimeFormatter()` defaults to the process's
  initial locale, NOT the runtime-switched one. Every site that
  creates one must do `f.locale = LocalizationStore.activeLanguage.locale`.
  3 such sites today (MenuBar QuotaRow, Sessions, Settings Pricing).
- **Coverage today**: none — these are UI-side and hard to unit-test.
- **Watch**: any new "X minutes ago" / "Y days from now" display.

### 8. Build pipeline version drift
- **Why risky**: `Resources/VERSION` is the single source of truth.
  `Info.plist` ships placeholder `0.0.0` so an un-injected build is
  obviously wrong, and `release.sh` cross-checks the injected version
  against `VERSION` post-build. But anything that bypasses `build.sh`
  (e.g. running `swift build` directly + opening
  `.build/.../CodexMonitor`) will produce an unversioned bundle.
- **Coverage today**: `release.sh` step 4 fails loud if the version
  inside the built `.app` doesn't match `VERSION`.
- **Watch**: any new build entry point that skips `build.sh`.

