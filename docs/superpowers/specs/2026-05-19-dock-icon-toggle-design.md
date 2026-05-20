# Dock Icon Toggle

**Date:** 2026-05-19
**Status:** Approved (design)
**Execution status:** Implemented in v0.2.13.

## Goal

Add a Settings → General toggle that controls whether QuotaMonitor's
Dock icon appears while a window (Dashboard, Settings, Onboarding) is
open. **Default: OFF** — the app stays in `.accessory` activation mode
permanently, so no Dock icon ever appears.

## Why

`Info.plist` already sets `LSUIElement=true`, so the app launches
without a Dock icon. However, `AppEnvironment.activateForWindow()`
(`QuotaMonitor/App/AppEnvironment.swift:401`) calls
`NSApp.setActivationPolicy(.regular)` whenever the user opens the
Dashboard, Settings, or Onboarding window — which makes the Dock icon
appear for the lifetime of that window. The original motivation was to
give the window proper key-focus and Cmd+Tab visibility (see
`docs/progress.md` Day-3 notes).

The user reports this behavior is unwanted: they expect a menu-bar app
to *never* show in the Dock. They also asked for a toggle so the old
behavior remains reachable, with the new no-Dock-icon behavior as the
default — including for existing installs upgrading to this release.

Trade-off accepted with the user: when the toggle is OFF, windows do
not appear in Cmd+Tab. That is the inherent behavior of macOS
`.accessory` activation policy and cannot be split from "no Dock icon"
without unsupported hacks. Window key-focus itself still works fine in
`.accessory` mode — Cmd+Tab visibility is the only thing lost.

## Non-goals

- **No change to `Info.plist`.** `LSUIElement=true` stays. Launch
  behavior is already correct; only the in-session promotion to
  `.regular` is being gated.
- **No new entry in Advanced.** The toggle lives in General per user
  preference — it's a UX choice in the same category as "language" and
  "menu bar headline window", not power-user territory.
- **No migration for the old `notifyThreshold` style cleanup.** A fresh
  default-OFF behaves identically to a missing key, so existing
  `UserDefaults` need no special handling.
- **No effect on the Onboarding window's first-launch auto-open.** That
  flow already works in `.accessory` mode (the window appears without
  the user needing the app in Cmd+Tab).
- **No mock / no test of `NSApp.setActivationPolicy` itself.** It's an
  AppKit side-effect; we trust the platform. We only unit-test the
  `SettingsStore` round-trip.

## Affected files

### Modified

- **`QuotaMonitor/Core/Settings/SettingsStore.swift`** — new
  `showDockIconForWindows: Bool` property (default `false`); new
  `Keys.showDockIconForWindows = "settings.showDockIconForWindows"`;
  `init` reads via `defaults.object(forKey:) as? Bool` (so a missing
  key resolves to `false` via the property's default — distinct from
  `defaults.bool(forKey:)` which also returns `false` but is
  indistinguishable from an explicit stored `false`; either is fine
  here since the resolved default is `false` anyway). No change to
  `Snapshot` (the value is only read on `MainActor`).

- **`QuotaMonitor/App/AppEnvironment.swift`** —
  - `activateForWindow()` reads `settings.showDockIconForWindows`. When
    `true` keep the current `NSApp.setActivationPolicy(.regular)` +
    `NSApp.activate(ignoringOtherApps: true)` flow. When `false`, call
    `NSApp.activate(ignoringOtherApps: true)` only — no policy change.
  - `demoteToAccessory()` becomes a no-op when
    `showDockIconForWindows` is `false` (we never promoted, so
    demoting would be a redundant `.accessory → .accessory` write,
    harmless but pointless).
  - New `applyDockIconPolicy()` method: called from the Settings
    toggle's binding when the user flips the setting. Inspects
    `NSApp.windows` to decide whether *any* tracked window is
    currently on-screen; if so and the setting just turned ON, promote
    now; if so and it just turned OFF, demote now. If no tracked
    window is open, do nothing (next `activateForWindow()` call will
    pick up the new value).

- **`QuotaMonitor/Features/Settings/GeneralSettingsTab.swift`** — new
  `Section(L10n.sectionAppearance)` at the top of the form (above
  Language), containing a single `Toggle` bound to
  `$settings.showDockIconForWindows`, with caption text from
  `L10n.showDockIconHelp`. After the toggle's value changes, call
  `env.applyDockIconPolicy()` so the change takes effect immediately
  even with a window already open.

- **`QuotaMonitor/Core/Localization/L10n.swift`** — three new keys:
  - `sectionAppearance` — "Appearance" / "外观"
  - `showDockIconLabel` — "Show Dock icon when windows are open" /
    "窗口打开时显示程序坞图标"
  - `showDockIconHelp` — "When off, QuotaMonitor stays in the menu bar
    only. The Dashboard and Settings windows will not appear in
    Cmd+Tab." / "关闭后 QuotaMonitor 完全只占菜单栏，但 Cmd+Tab 将切换不到
    Dashboard 与设置窗口。"

### Added

- **`Tests/QuotaMonitorTests/DockIconSettingTests.swift`** — three
  cases:
  1. Fresh `SettingsStore` (empty UserDefaults) → `showDockIconForWindows`
     is `false`.
  2. Setting `showDockIconForWindows = true` writes to UserDefaults
     under `"settings.showDockIconForWindows"`.
  3. Constructing a new `SettingsStore` from a UserDefaults containing
     `true` resolves to `true`. Same for `false`.

  Uses the same in-memory `UserDefaults(suiteName:)` pattern as
  `EnabledProvidersTests.swift`.

## Implementation notes

### `activateForWindow()` change

```swift
func activateForWindow() {
    if settings.showDockIconForWindows {
        NSApp.setActivationPolicy(.regular)
    }
    NSApp.activate(ignoringOtherApps: true)
}
```

`activate(ignoringOtherApps:)` works fine in `.accessory` mode and is
sufficient to bring the just-opened window forward over the menu-bar
popover (this is what was missing before the original `activateForWindow`
landed — but the popover is a transient panel, not an active app, so a
plain `activate` is enough; the `.regular` policy switch was only
needed for Dock-icon and Cmd+Tab visibility).

### `applyDockIconPolicy()` (live toggle)

The window-tracking heuristic: iterate `NSApp.windows`, skip the
`NSStatusBarWindow`-class menu-bar host and any window that is not
`isVisible`. If any visible app window remains, treat as "a window is
open" and apply the new policy immediately. Otherwise leave the policy
alone — the next `activateForWindow()` will handle it.

This avoids piping every window's open/close back through
`AppEnvironment`. We're piggy-backing on AppKit's existing window
tracking instead of introducing our own counter.

### Why the default is `false` for existing users

User explicitly asked for default-OFF, and the behavior change is
small and reversible (one toggle in Settings). No staged rollout or
"keep old behavior on upgrade" carve-out is needed.

## Manual test plan

After implementing:

1. Fresh `./build.sh && open .build/QuotaMonitor.app`.
   - Open Dashboard from menu bar → **no Dock icon should appear**.
   - Cmd+Tab → QuotaMonitor should *not* show. (Confirms `.accessory`
     stayed.)
   - Close Dashboard, reopen Settings → no Dock icon, same.
2. In Settings → General → Appearance, toggle **ON** while Settings is
   open.
   - **Dock icon should appear immediately** (no need to reopen the
     window).
   - Cmd+Tab → QuotaMonitor now appears.
3. Toggle back **OFF**.
   - Dock icon disappears immediately.
4. Quit and relaunch — toggle state persists across launches.
