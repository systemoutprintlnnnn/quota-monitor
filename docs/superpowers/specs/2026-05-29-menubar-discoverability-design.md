# Menu-bar icon discoverability — design

**Date:** 2026-05-29
**Status:** Approved (brainstorming) → ready for implementation plan

## Problem

QuotaMonitor is a menu-bar-only app (`LSUIElement`, no Dock icon). On a Mac
with a crowded menu bar — especially notched MacBooks where items that don't
fit to the left of the notch are simply **clipped and never rendered**, or
when a menu-bar manager (Bartender / Ice / Hidden Bar) folds items away — the
freshly-installed status item is invisible. First-time users can't find it,
can't open the popover, and conclude the app "does nothing." The menu bar is
currently the **only** entry point, so an invisible icon means no entry at all.

### Hard constraint (verified)

macOS owns menu-bar layout. There is **no supported API** for an app to force
its status item to show when the bar overflows, to reposition itself ahead of
others, or to override a menu-bar manager's hiding. We do **not** attempt to
"win the position fight." Instead we make the icon present itself when it is
visible, and provide a durable alternative entry when it is not.

Both desired mechanisms require dropping SwiftUI `MenuBarExtra`:

- **Auto-open the popover** — `MenuBarExtra` has no `isPresented`-style API to
  open its window programmatically.
- **Clip detection** — needs `statusItem.button.window` screen geometry, which
  `MenuBarExtra` does not expose.

So this is an **architecture migration** (`MenuBarExtra` → AppKit
`NSStatusItem`), not a patch.

## Goals

1. On first launch (after onboarding), if the icon is visible, auto-open the
   popover so its anchor arrow points the user straight at the icon.
2. If the icon is clipped/hidden, detect it and provide a durable fallback:
   a permanent Dock icon plus a one-time main-window open with an explanatory
   hint.

## Non-goals

- Forcing the status item to be visible past OS overflow / notch clipping
  (impossible — see constraint above).
- Reordering relative to other menu-bar items beyond an `autosaveName` nudge
  (out of scope; not relied upon).
- Decoding Claude Desktop's separate Electron safeStorage auth (unrelated).

## Architecture

Replace the `MenuBarExtra` scene with an AppKit `NSStatusItem` owned by an
`NSApplicationDelegateAdaptor`. SwiftUI content is reused via hosting. The
three `Window` scenes (onboarding / dashboard / settings) are unchanged.

```
QuotaMonitorApp (@main)
├── @NSApplicationDelegateAdaptor → AppDelegate
│     └── StatusItemController                 // new, AppKit, @MainActor
│           ├── NSStatusItem(.variableLength)
│           │     └── button: NSHostingView(MenuBarLabelView + env)
│           ├── NSPopover(.transient)
│           │     └── NSHostingController(MenuBarContentView + env)
│           ├── togglePopover()  (button action)
│           ├── showPopover()    (for first-run auto-open)
│           └── statusItemVisibility() -> .visible | .clipped
└── Window scenes: onboarding / dashboard / settings (unchanged)
```

### Shared state

Convert `AppEnvironment` to a `.shared` singleton, matching the existing
`SettingsStore.shared` / `LocalizationStore.shared` pattern, so the AppDelegate
and the SwiftUI Window scenes share one instance. The migration and
init-ordering logic currently in `App.init` (UserDefaults migration before
singletons read their values) is preserved — run it before first access to
`AppEnvironment.shared`.

## Behavior

### Flow A — first-run presentation (one-time, flag-gated)

Triggered when onboarding completes (user clicks Continue):

1. Wait ~0.6s for the status item to finish laying out.
2. If `statusItemVisibility() == .visible` → `controller.showPopover()`. The
   popover's anchor arrow points at the icon.
3. If `.clipped` → run the clipped fallback (Flow B's one-time parts).
4. Set `hasShownFirstRunPresentation = true`. The auto-open **never repeats**.

### Flow B — per-launch clip → Dock fallback (NOT flag-gated)

On **every** launch, after the status item lays out, check visibility:

- If clipped:
  - `NSApp.setActivationPolicy(.regular)` → **permanent Dock icon** so a
    permanently-overflowing bar still leaves a visible entry every launch.
  - Set `AppEnvironment.menuBarUnreachable = true`.
  - If `hasShownFirstRunPresentation` is being set this run (i.e. first run),
    also `openWindow("dashboard")` once and show a one-time hint banner.
- If visible: leave activation policy to the existing Dock-icon-for-windows
  logic.

The one-time *window open* is gated; the *Dock-icon enforcement* is per-launch,
so durable entry always exists while the icon is unreachable.

### Integration with existing Dock policy

`menuBarUnreachable` becomes a new reason to stay `.regular`. Both
`demoteToAccessory()` and `applyDockIconPolicy()` must consult it: when
`menuBarUnreachable == true`, never demote to `.accessory` (otherwise closing
the last window would drop the only visible entry). This is the sole coupling
point with the existing Dock-icon code (`AppEnvironment.activateForWindow` /
`demoteToAccessory` / `applyDockIconPolicy`).

## Clip detection

```
func statusItemVisibility() -> Visibility {
    guard statusItem.isVisible,
          let button = statusItem.button,
          let win = button.window,
          let screen = win.screen
    else { return .clipped }
    let frameInScreen = win.frame   // button window frame, screen coords
    // clipped if zero-width, or does not intersect the menu-bar strip of the
    // screen that hosts the menu bar (covers notch-left overflow where AppKit
    // places the window off-screen / on no screen).
    if frameInScreen.width == 0 { return .clipped }
    if !intersectsMenuBarStrip(frameInScreen, on: screen) { return .clipped }
    return .visible
}
```

- **Timing:** check after launch (post-layout delay) and re-check on
  `NSApplication.didChangeScreenParametersNotification` (external display /
  resolution / notch changes).
- **Threshold calibration:** exact strip geometry, especially notch-left
  overflow, is tuned during implementation against a real test matrix
  (packed bar / notched MacBook / external display / Bartender active).

## New persisted state (SettingsStore)

- `hasShownFirstRunPresentation: Bool` — gates the one-time popover/window
  presentation in Flow A.
- `firstRunHintDismissed: Bool` — whether the Dashboard "icon may be hidden"
  banner has been dismissed.

## Files touched

| File | Change |
| --- | --- |
| `App/QuotaMonitorApp.swift` | Remove `MenuBarExtra` scene; add `@NSApplicationDelegateAdaptor`; use `AppEnvironment.shared` |
| `App/AppDelegate.swift` (new) | Lifecycle; launch fan-out (moved from the old `MenuBarExtra` `.task`); first-run presentation + per-launch clip check |
| `App/StatusItemController.swift` (new) | `NSStatusItem` + `NSPopover` hosting; `showPopover()`; `statusItemVisibility()`; screen-change observer |
| `App/AppEnvironment.swift` | `.shared` singleton; add `menuBarUnreachable`; integrate into `demoteToAccessory` / `applyDockIconPolicy` |
| `Core/Settings/SettingsStore.swift` | Two new flags (+ snapshot fields) |
| `Features/MenuBar/MenuBarLabelView.swift` | Adapt as hosted root; preserve `.fixedSize()` width; preserve `.id(loc.tickForceRedraw)`; route launch window-open via bridge |
| `Features/MenuBar/MenuBarContentView.swift` | Adapt as hosted popover root; keep `openWindow` usage working |
| `Features/Dashboard/DashboardView.swift` | One-time "icon may be hidden" hint banner |
| `Core/Localization/L10n.swift` + store | Hint + banner strings (EN + 简体中文) |

## Risks & mitigations

1. **`openWindow` from a manually-created `NSHostingView`.** The current code
   opens the onboarding window via `@Environment(\.openWindow)` from inside the
   `MenuBarExtra`-hosted `MenuBarLabelView`. Once detached from `MenuBarExtra`,
   the scene-environment connection may not survive.
   **Mitigation:** the implementation plan starts with a spike to confirm
   `openWindow` works from the status button's hosting view and the popover's
   hosting controller. If it does not, fall back to a URL-scheme bridge
   (`quotamonitor://dashboard` / `://onboarding` + `.handlesExternalEvents`)
   or host the windows via AppKit `NSWindowController`.
2. **Clip-detection accuracy on notched displays.** Validate against the test
   matrix above; treat "uncertain" as visible (fail open — never strand the
   user with neither popover nor Dock icon by a false "visible").
3. **`NSHostingView` auto-sizing inside the status button.** Use
   `.variableLength` + autolayout; verify the label keeps its current width
   behavior (intrinsic width, no squeeze) that `.fixedSize()` provides today.
4. **i18n live re-render.** Keep `.id(loc.tickForceRedraw)` on both hosted root
   views so language switches still redraw the label and popover.

## Open questions resolved during brainstorming

- Fallback strategy when clipped → **permanent Dock icon** (re-evaluated every
  launch) + one-time window open with hint. (Not "open window every launch",
  not "open once then nothing".)
