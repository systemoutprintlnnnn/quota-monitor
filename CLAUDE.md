# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

QuotaMonitor — a macOS-only (14+) Swift 6 menu-bar app tracking Codex and
Claude Code usage: live quota meters, spend analytics, session drilldown.
Pure SwiftPM (no Xcode project); the `.app` bundle is assembled by `build.sh`.
Strict concurrency is enabled on all targets.

## Commands

```bash
./qa/run-static.sh            # full non-GUI gate: shell/Python helper tests,
                              # release-note format, git diff --check, swift test.
                              # Same thing CI runs. run-all.sh is an alias.

swift test --disable-keychain                      # Swift tests only
swift test --disable-keychain --filter SomeTests   # single test class

./build.sh                    # debug build → .build/QuotaMonitor.app (ad-hoc signed)
CONFIG=release ./build.sh     # release build
./script/build_and_run.sh     # kill running app, rebuild, relaunch
```

Toolchain caveat (this machine): the default CommandLineTools `/usr/bin/swift`
fails to compile `Package.swift` ("Undefined symbols ... PackageDescription").
Use the swift.org toolchain: `TOOLCHAINS=org.swift.632202512021a swift build`
(bundle identifier, not name — `TOOLCHAINS=swift-6.3.2-RELEASE` does NOT work),
or put `~/Library/Developer/Toolchains/swift-6.3.2-RELEASE.xctoolchain/usr/bin`
first on PATH. The `build.sh` / `qa/*.sh` scripts handle this themselves by
sourcing `~/.swiftly/env.sh` when present.

Test gotcha: `MainWindowLayoutTests` walks up from `#filePath` looking for a
directory named exactly `quota-monitor` — it fails in any checkout/worktree
named otherwise. Temp worktrees must be named `…/quota-monitor`.

### UI / visible-behavior QA

The static gate must never launch a GUI app instance. For changes affecting
visible behavior, prepare an isolated QA build for a Computer Use walkthrough:

```bash
./qa/prepare-computer-use-fixture.sh     # fixture data; prints artifact dir,
                                         # computer-use-qa.md brief, exact .app target
./qa/prepare-computer-use-real-data.sh   # real-data shadow variant
./qa/check-artifacts.sh .build/qa-artifacts/<timestamp>   # replay checks, no relaunch
```

Always target the exact `.app` path from the brief (a real
`/Applications/QuotaMonitor.app` may also be running). Run the printed
`cleanup-computer-use.sh` afterwards. Details: `docs/local-qa.md`,
`docs/computer-qa.md`, and `.codex/skills/quota-monitor-computer-qa/SKILL.md`.

### Changelog requirement (CI-enforced)

Every PR must add user-facing entries to the `## [Unreleased]` section of
**both** `CHANGELOG.md` and `CHANGELOG.zh-Hans.md`
(`tools/validate-pr-changelog.py` runs in CI). Allowed `###` headings are
fixed (Added/Changed/Fixed/Removed/Known limitations and their zh-Hans
equivalents — see `tools/validate-release-notes.py`). Release PRs instead bump
`Resources/VERSION` and move entries into a versioned section.

## Architecture

Data flow: two providers (Codex, Claude), each with a **live quota** path and
a **local history** path, converging in SQLite (GRDB) and read back through
the Aggregator:

- Live Codex: `Core/AppServer/` spawns `codex app-server` and speaks JSON-RPC
  (`account/rateLimits/read`); polled by `Core/RateLimits/RateLimitPoller`.
- Live Claude: `Core/Claude/` calls Anthropic's OAuth `/api/oauth/usage` with
  Claude Code credentials (`~/.claude/.credentials.json`, then Keychain).
  Hard 2-hour cadence + 429 back-off; tokens are never refreshed by us — a
  stale token triggers spawning `claude --version` to let the official CLI
  rotate it.
- Local history: `Core/Importer/` scans jsonl rollouts (`~/.codex/sessions`,
  `~/.claude/projects`) and persists via `Core/Storage/` (GRDB schema in
  `Migrations.swift`; auto-migrates the legacy CodexMonitor DB).
- `Core/Analytics/Aggregator*.swift` is the query layer feeding all UI
  (dashboard, sessions, history, menu bar). `BillingBlocks.swift` holds the
  5-hour billing-block algorithm ported from ccusage.
- `Core/Pricing/` maps tokens → spend (seed catalog + LiteLLM sync).

UI / app layer:

- `App/QuotaMonitorApp.swift` is `@main` with SwiftUI `Window`/`Settings`
  scenes, but the menu-bar presence is an **AppKit `NSStatusItem`** owned by
  `AppDelegate` / `StatusItemController` (not `MenuBarExtra` — it can't open
  programmatically or expose geometry, needed for clip detection / Dock-icon
  fallback). `App/WindowRouter.swift` bridges AppKit → SwiftUI windows via
  `quotamonitor://` URLs and `.handlesExternalEvents`.
- Shared state is `@MainActor @Observable` singletons referenced by both
  worlds: `AppEnvironment.shared` (services + live UI state; big methods live
  in extensions: `PricingController`, `ScanController`, `QueryFacade`),
  `SettingsStore.shared`, `LocalizationStore.shared`. In `QuotaMonitorApp.init`
  the `@State` wrappers are assigned in the init body, *after*
  `UserDefaultsMigration.runIfNeeded()` — don't move them to inline defaults.
- `Features/` is the per-surface SwiftUI (Dashboard, Sessions, History,
  MainWindow, MenuBar, Settings, Onboarding); `Core/` must stay UI-free.
- i18n: English + 简体中文, hot-swappable at runtime through
  `Core/Localization/L10n.swift` — user-facing strings go through `L10n`,
  not string literals.
- Local QA mode: `App/LocalQA*.swift` lets the app launch against an isolated
  profile/fixture config (`--quotamonitor-qa-config-base64`); the `qa/`
  scripts drive it and verify the artifact/isolation boundary.

Build pipeline quirks (all in `build.sh`): version comes solely from
`Resources/VERSION` and is injected into the copied Info.plist at build time
(the source plist deliberately says 0.0.0); Sparkle.framework must be
hand-copied into `Contents/Frameworks/` and an rpath added — SwiftPM won't do
either, and the app crashes without them. Sparkle compares `CFBundleVersion`
against the appcast, so both version keys get the same dotted semver.

`docs/findings.md` records reverse-engineered Codex CLI / Anthropic API
behavior (RPC names, error-body salvage, rate-limit quirks) — check it before
touching the decoders or pollers.
