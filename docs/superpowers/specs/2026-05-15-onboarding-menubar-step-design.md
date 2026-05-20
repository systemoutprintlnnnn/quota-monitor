# Onboarding · Menu-Bar Display Step

**Date:** 2026-05-15
**Status:** Approved (design)
**Execution status:** Implemented in v0.2.8; kept here as the design record.

## Goal

Add a third onboarding step that asks **which provider's usage to show in
the menu-bar icon**, but only when the user selected both Codex and Claude
Code on the existing provider step. Single-provider pickers continue to
flow straight to "Continue" — the question is degenerate for them.

## Why

Today the menu-bar icon defaults to "show everything the user tracks." A
user who tracks both tools but only cares about one of them at a glance
has to discover the picker buried in Settings → General. Surfacing it as
an onboarding step puts the choice in front of users who actually have
the choice (both providers picked), without adding friction for users
who don't.

## Non-goals

- No change to `SettingsStore.menuBarIconProviders` storage shape,
  defaults, or reconciliation. The new step is a UI layer that calls the
  existing `setMenuBarIconProviderEnabled` API.
- No new persistence flag (no `needsMenuBarOnboarding`). The third step's
  visibility is session-scoped: derived from the user's in-memory provider
  choice on step 2.
- No back button. Consistent with the existing step 1 → step 2 flow
  (which also has no back).
- No change to the upgrade path (`SettingsStore.onboardingResetMinVersion`).
  Upgraded users dragged through provider re-onboarding will see step 3
  if they pick both providers — same logic as fresh installs.

## Affected files

- `QuotaMonitor/Features/Onboarding/LanguageOnboardingView.swift` —
  extend the `Step` enum, add `menuBarStep` ViewBuilder, refactor commit
  path into a shared `finishOnboarding` closure.
- No new files. No L10n additions (existing
  `menuBarIconProviderLabel` and `menuBarIconProviderHelp` are reused).

## Design

### View structure

`OnboardingView` keeps its single-window-three-step shape. Extend the
`Step` enum:

```swift
private enum Step { case language, providers, menuBar }
```

The step is derived from a mix of persisted state and a new local
`@State`:

```swift
@State private var providersCommitted = false

private var step: Step {
    if loc.needsOnboarding { return .language }
    if !providersCommitted   { return .providers }
    return .menuBar
}
```

`providersCommitted` flips to `true` only when the user clicks Continue
on step 2 having picked **both** providers. Single-provider pickers
never set it; they take the immediate-commit path described below.

### Commit flow (single-write principle)

Extract a shared closure that performs every settings write atomically:

```swift
private func finishOnboarding(providers: Set<String>,
                              iconProviders: Set<String>) {
    settings.replaceEnabledProviders(providers)
    // Explicitly sync the menu-bar subset. Without this we'd inherit the
    // SettingsStore default (a copy of enabledProviders), which would
    // over-show on a "user picked both providers but only wants Codex in
    // the menu bar" flow.
    for id in SettingsStore.knownIconProviders {
        _ = settings.setMenuBarIconProviderEnabled(
            id, enabled: iconProviders.contains(id))
    }
    settings.markProviderOnboardingDone()
    env.applyEnabledProviders()
    dismissWindow(id: "onboarding")
}
```

Call sites:

| Step 2 picks | Action on Continue |
|---|---|
| One provider (Codex or Claude only) | `finishOnboarding(providers: {one}, iconProviders: {one})`. Step 3 is skipped — the question is degenerate. |
| Both providers | Set `providersCommitted = true`. **No settings writes yet.** |
| Step 3 Continue | `finishOnboarding(providers: {codex, claude}, iconProviders: pickedIconSet)`. |

Step 2's existing "at least one provider must be picked" gate
(`.disabled(!pickedCodex && !pickedClaude)`) stays exactly as it is —
the new logic only changes what happens *after* the user successfully
clicks Continue, not whether Continue is enabled.

The crucial property: no partial commits. Either the full set of
settings is written and the window dismisses, or nothing changes.

### Step 3 UI

```
┌──────────────────────────────────┐
│   menubar.dock.rectangle (36 pt) │
│                                  │
│   菜单栏显示                       │  L10n.menuBarIconProviderLabel
│                                  │
│   选择哪些工具的 5h/7d 使用率…     │  L10n.menuBarIconProviderHelp
│                                  │
│   ┌────────────────────────────┐ │
│   │ Codex                  [●] │ │  .switch style toggle
│   │ Claude Code            [○] │ │  .switch style toggle
│   └────────────────────────────┘ │
│                                  │
│   [          Continue          ] │  always enabled
└──────────────────────────────────┘
```

- Same outer padding / spacing / typography as step 2.
- Toggles use `.switch` style — matches step 2 (Settings uses `.checkbox`
  but onboarding stays consistent with itself).
- Initial state: `@State private var iconCodex = true`,
  `@State private var iconClaude = false` (per user requirement: Codex on
  by default, Claude off).
- Continue button is **always enabled**. Empty selection is a valid state
  meaning "fall back to the gauge SF Symbol," matching the existing
  `menuBarIconProviders` semantics.
- SF Symbol for the header is `menubar.dock.rectangle`. Available since
  SF Symbols 2 / macOS 11; safely within the project's macOS 14
  deployment target (`Package.swift`).

### Localization

Reuse without additions:

- Headline: `L10n.menuBarIconProviderLabel`
  - en: "Show in menu bar"
  - zh: "菜单栏显示"
- Subhead: `L10n.menuBarIconProviderHelp`
  - en: "Pick which tools' 5h and 7d usage to show on the menu-bar
    icon. Choose both for a combined line, one for a shorter readout,
    or none to keep the gauge icon."
  - zh: "选择哪些工具的 5 小时与 7 日使用率显示在菜单栏图标上。两个都选会
    并排显示在一行，只选一个会更短，都不选则显示原本的表盘图标。"
- Continue button: `L10n.onboardingContinue`

### Edge cases

| Scenario | Behavior |
|---|---|
| Step 2 picks one provider | Skips step 3. Single atomic commit with `iconProviders = {that provider}`. Matches today's SettingsStore default for a single-provider install. |
| Step 2 picks both | Transition to step 3. Zero settings writes until step 3 Continue. |
| Step 3 both toggles off, click Continue | Commits `menuBarIconProviders = []`. Menu bar falls back to the gauge SF Symbol. Legal and intentional. |
| Step 3 closed via titlebar red button | `onDisappear` sees `needsProviderOnboarding` is still true (we never wrote it) → re-opens window. `providersCommitted` is a new `@State` on the fresh view → back to step 2. Language is preserved (`loc.set(.xxx)` was committed on step 1). Provider picks must be re-entered. |
| Upgrade user with `onboardingResetMinVersion` trigger | Goes through the same provider step they always did. If they pick both, they see step 3 with the standard defaults (Codex on, Claude off). We deliberately do **not** seed step 3's toggles from the user's current `menuBarIconProviders` — re-onboarding is "re-introduce the choice," and consistency between fresh installs and re-onboarded users is more valuable than preserving a value the user may not remember setting. |
| Existing tests (`EnabledProvidersTests`) | Exercise the `SettingsStore` API directly and remain unaffected. The new UI changes only the call site. |

## Testing

- Unit tests are not required for the view itself. The behavioral
  invariants live in `SettingsStore`, which already has test coverage
  via `EnabledProvidersTests.swift`.
- Manual verification on first run:
  1. Fresh defaults: step 1 → step 2 (pick both) → step 3 (Codex on,
     Claude off by default) → Continue → menu bar shows Codex only.
  2. Pick one on step 2 → step 3 is skipped → window dismisses → menu
     bar shows the picked provider.
  3. Step 3 with both toggles off → Continue → menu bar shows gauge
     icon.
  4. Step 3 → red titlebar close → window re-opens at step 2 with
     language preserved.

## Open questions

None at design time. Confirmed:
1. Header SF Symbol is `menubar.dock.rectangle`. (Confirmed by user.)
2. Upgrade users get the same defaults as fresh installs on step 3, not
   a seed from their current `menuBarIconProviders`. (Confirmed by user.)
3. No back button on step 3. (Confirmed by user.)
