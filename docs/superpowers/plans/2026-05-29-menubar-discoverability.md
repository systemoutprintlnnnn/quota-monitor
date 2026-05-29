# Menu-bar Icon Discoverability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user's menu bar is full (notch-clipped / packed / hidden by a menu-bar manager) and QuotaMonitor's status item is invisible, the user can still find and use the app — via an auto-opened popover when the icon is visible, or a permanent Dock icon + main window when it is clipped.

**Architecture:** Replace the SwiftUI `MenuBarExtra` scene with an AppKit `NSStatusItem` owned by an `NSApplicationDelegateAdaptor`-attached `AppDelegate`. The existing SwiftUI label and popover views are reused via `NSHostingView` / `NSHostingController`. On launch (after onboarding), a clip-detection check decides between auto-opening the popover (icon visible) and a permanent Dock-icon fallback + one-time window open (icon clipped). All AppKit→SwiftUI window opens go through a single `WindowRouter` seam whose mechanism (SwiftUI `openWindow` vs. custom URL scheme) is decided by an early spike.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit interop (`NSStatusItem`, `NSPopover`, `NSHostingView`/`NSHostingController`, `NSApplicationDelegateAdaptor`), Swift Testing (`import Testing`), GRDB (unaffected).

**Spec:** `docs/superpowers/specs/2026-05-29-menubar-discoverability-design.md`

**Run tests:** `swift test --filter <SuiteName>`
**Build & run app:** `./build.sh && open .build/QuotaMonitor.app`
**Inspect logs while running:** `log stream --predicate 'subsystem == "dev.tjzhou.QuotaMonitor"' --level info`

---

## File Structure

**New files:**
- `QuotaMonitor/App/MenuBarVisibility.swift` — pure `StatusItemVisibility` enum + `MenuBarVisibilityEvaluator` geometry (unit-tested).
- `QuotaMonitor/App/MenuBarPresentation.swift` — pure `MenuBarPresentation` decision enum (unit-tested).
- `QuotaMonitor/App/WindowRouter.swift` — single seam for programmatic window opens from AppKit contexts.
- `QuotaMonitor/App/StatusItemController.swift` — `NSStatusItem` + `NSPopover` host, hosting the existing label/popover SwiftUI views; visibility query; screen-change observer.
- `QuotaMonitor/App/AppDelegate.swift` — app lifecycle, launch fan-out, discoverability orchestration.
- `Tests/QuotaMonitorTests/FirstRunFlagsTests.swift`
- `Tests/QuotaMonitorTests/MenuBarVisibilityTests.swift`
- `Tests/QuotaMonitorTests/MenuBarPresentationTests.swift`
- `Tests/QuotaMonitorTests/DemoteToAccessoryPredicateTests.swift`
- `Tests/QuotaMonitorTests/OnboardingCompletionNotificationTests.swift`

**Modified files:**
- `QuotaMonitor/Core/Settings/SettingsStore.swift` — two new flags + a notification post.
- `QuotaMonitor/App/AppEnvironment.swift` — `.shared` singleton; `menuBarUnreachable`; demote predicate + integration.
- `QuotaMonitor/App/QuotaMonitorApp.swift` — remove `MenuBarExtra`; add `@NSApplicationDelegateAdaptor`; use `.shared`; mount the `WindowRouter` driver.
- `QuotaMonitor/Features/MenuBar/MenuBarContentView.swift` — drop the `.onAppear` refresh (the controller now owns "popover opened").
- `QuotaMonitor/Features/MenuBar/MenuBarLabelView.swift` — drop the launch onboarding-open `.task` (AppDelegate owns launch).
- `QuotaMonitor/Features/Dashboard/DashboardView.swift` — one-time "icon may be hidden" hint banner.
- `QuotaMonitor/Core/Localization/L10n.swift` — hint banner strings.

---

## Task 1: SettingsStore — first-run flags

**Files:**
- Modify: `QuotaMonitor/Core/Settings/SettingsStore.swift`
- Test: `Tests/QuotaMonitorTests/FirstRunFlagsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/QuotaMonitorTests/FirstRunFlagsTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotaMonitor

/// Locks down the two discoverability flags added for the menu-bar
/// clip-fallback feature. Both default OFF on a fresh install and
/// persist as plain Bools.
@MainActor
@Suite("First-run discoverability flags")
struct FirstRunFlagsTests {

    private static func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "test.\(name).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test
    func firstRunPresentationDefaultsFalse() {
        let store = SettingsStore(defaults: Self.freshDefaults())
        #expect(store.hasShownFirstRunPresentation == false)
    }

    @Test
    func firstRunPresentationPersists() {
        let d = Self.freshDefaults()
        let store = SettingsStore(defaults: d)
        store.hasShownFirstRunPresentation = true
        #expect(d.bool(forKey: "discoverability.firstRunPresentationShown") == true)
        #expect(SettingsStore(defaults: d).hasShownFirstRunPresentation == true)
    }

    @Test
    func hintDismissedDefaultsFalse() {
        let store = SettingsStore(defaults: Self.freshDefaults())
        #expect(store.firstRunHintDismissed == false)
    }

    @Test
    func hintDismissedPersists() {
        let d = Self.freshDefaults()
        let store = SettingsStore(defaults: d)
        store.firstRunHintDismissed = true
        #expect(d.bool(forKey: "discoverability.firstRunHintDismissed") == true)
        #expect(SettingsStore(defaults: d).firstRunHintDismissed == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FirstRunFlagsTests`
Expected: FAIL — `value of type 'SettingsStore' has no member 'hasShownFirstRunPresentation'`.

- [ ] **Step 3: Add the two stored properties**

In `SettingsStore.swift`, after the `developerModeEnabled` property (around line 124), add:

```swift
    /// Whether the one-time first-run discoverability presentation has
    /// run (auto-open the popover when the icon is visible, or open the
    /// main window when it is clipped). Set true after the first launch
    /// past onboarding so we never auto-pop on subsequent launches.
    var hasShownFirstRunPresentation: Bool {
        didSet { defaults.set(hasShownFirstRunPresentation,
                              forKey: Keys.firstRunPresentationShown) }
    }
    /// Whether the user dismissed the Dashboard "menu-bar icon may be
    /// hidden" hint banner shown when the status item is clipped.
    var firstRunHintDismissed: Bool {
        didSet { defaults.set(firstRunHintDismissed,
                              forKey: Keys.firstRunHintDismissed) }
    }
```

- [ ] **Step 4: Initialize them in `init`**

In `SettingsStore.init`, after the `self.developerModeEnabled = …` line (around line 311), add:

```swift
        self.hasShownFirstRunPresentation =
            defaults.bool(forKey: Keys.firstRunPresentationShown)
        self.firstRunHintDismissed =
            defaults.bool(forKey: Keys.firstRunHintDismissed)
```

- [ ] **Step 5: Add the keys**

In the `private enum Keys` block, after `static let developerModeEnabled = …`, add:

```swift
        static let firstRunPresentationShown = "discoverability.firstRunPresentationShown"
        static let firstRunHintDismissed = "discoverability.firstRunHintDismissed"
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter FirstRunFlagsTests`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add QuotaMonitor/Core/Settings/SettingsStore.swift Tests/QuotaMonitorTests/FirstRunFlagsTests.swift
git commit -m "feat: add first-run discoverability flags to SettingsStore"
```

---

## Task 2: Pure menu-bar visibility evaluator

**Files:**
- Create: `QuotaMonitor/App/MenuBarVisibility.swift`
- Test: `Tests/QuotaMonitorTests/MenuBarVisibilityTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/QuotaMonitorTests/MenuBarVisibilityTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotaMonitor

/// Pure geometry for "is the status item actually on screen". Fails OPEN:
/// only strong signals (no frame, no screen, zero width, entirely
/// off-screen horizontally) count as clipped, so a partially-overlapping
/// item is treated as visible rather than falsely forcing the Dock
/// fallback.
@Suite("Menu-bar visibility evaluator")
struct MenuBarVisibilityTests {

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test
    func visibleWhenInsideScreen() {
        let button = CGRect(x: 1200, y: 876, width: 60, height: 24)
        #expect(MenuBarVisibilityEvaluator.evaluate(
            buttonWindowFrame: button, hostScreenFrame: screen) == .visible)
    }

    @Test
    func clippedWhenNoFrame() {
        #expect(MenuBarVisibilityEvaluator.evaluate(
            buttonWindowFrame: nil, hostScreenFrame: screen) == .clipped)
    }

    @Test
    func clippedWhenNoScreen() {
        let button = CGRect(x: 1200, y: 876, width: 60, height: 24)
        #expect(MenuBarVisibilityEvaluator.evaluate(
            buttonWindowFrame: button, hostScreenFrame: nil) == .clipped)
    }

    @Test
    func clippedWhenZeroWidth() {
        let button = CGRect(x: 1200, y: 876, width: 0, height: 24)
        #expect(MenuBarVisibilityEvaluator.evaluate(
            buttonWindowFrame: button, hostScreenFrame: screen) == .clipped)
    }

    @Test
    func clippedWhenEntirelyLeftOfScreen() {
        // AppKit parks an overflowed item off the left edge.
        let button = CGRect(x: -120, y: 876, width: 60, height: 24)
        #expect(MenuBarVisibilityEvaluator.evaluate(
            buttonWindowFrame: button, hostScreenFrame: screen) == .clipped)
    }

    @Test
    func clippedWhenEntirelyRightOfScreen() {
        let button = CGRect(x: 1500, y: 876, width: 60, height: 24)
        #expect(MenuBarVisibilityEvaluator.evaluate(
            buttonWindowFrame: button, hostScreenFrame: screen) == .clipped)
    }

    @Test
    func visibleWhenPartiallyOverlapping() {
        // Fail open: partial overlap is treated as visible.
        let button = CGRect(x: -30, y: 876, width: 60, height: 24)
        #expect(MenuBarVisibilityEvaluator.evaluate(
            buttonWindowFrame: button, hostScreenFrame: screen) == .visible)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuBarVisibilityTests`
Expected: FAIL — `cannot find 'MenuBarVisibilityEvaluator' in scope`.

- [ ] **Step 3: Create the implementation**

Create `QuotaMonitor/App/MenuBarVisibility.swift`:

```swift
import Foundation
import CoreGraphics

/// Whether the menu-bar status item is actually on screen, or clipped
/// away (notch-left overflow / packed bar / hidden by a menu-bar
/// manager). Pure value type so it can drive unit tests without AppKit.
enum StatusItemVisibility: Equatable {
    case visible
    case clipped
}

/// Pure geometry behind `StatusItemController.currentVisibility()`.
///
/// **Fails open.** Only strong signals count as `.clipped`: a missing
/// frame, a missing host screen, zero width, or a frame lying entirely
/// outside the host screen on the horizontal axis (how AppKit parks an
/// item that doesn't fit left of the notch). A partially-overlapping
/// frame is `.visible` — we would rather occasionally skip the Dock
/// fallback than falsely strand a user who can in fact see their icon.
enum MenuBarVisibilityEvaluator {
    static func evaluate(buttonWindowFrame: CGRect?,
                         hostScreenFrame: CGRect?) -> StatusItemVisibility {
        guard let frame = buttonWindowFrame,
              let screen = hostScreenFrame else { return .clipped }
        if frame.width <= 0 { return .clipped }
        if frame.maxX <= screen.minX || frame.minX >= screen.maxX {
            return .clipped
        }
        return .visible
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MenuBarVisibilityTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add QuotaMonitor/App/MenuBarVisibility.swift Tests/QuotaMonitorTests/MenuBarVisibilityTests.swift
git commit -m "feat: add pure menu-bar visibility evaluator"
```

---

## Task 3: Pure first-run presentation decision

**Files:**
- Create: `QuotaMonitor/App/MenuBarPresentation.swift`
- Test: `Tests/QuotaMonitorTests/MenuBarPresentationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/QuotaMonitorTests/MenuBarPresentationTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotaMonitor

/// The one-time first-run presentation decision. The Dock-icon /
/// `menuBarUnreachable` side effect is NOT encoded here — it follows
/// directly from `visibility == .clipped` and is applied every launch by
/// the caller. This enum only governs the one-time popover/window action.
@Suite("Menu-bar first-run presentation decision")
struct MenuBarPresentationTests {

    @Test
    func visibleAndUnshownShowsPopover() {
        #expect(MenuBarPresentation.decide(
            visibility: .visible, hasShownFirstRun: false) == .showPopover)
    }

    @Test
    func clippedAndUnshownOpensFallbackWindow() {
        #expect(MenuBarPresentation.decide(
            visibility: .clipped, hasShownFirstRun: false) == .openFallbackWindow)
    }

    @Test
    func alreadyShownVisibleIsNone() {
        #expect(MenuBarPresentation.decide(
            visibility: .visible, hasShownFirstRun: true) == .none)
    }

    @Test
    func alreadyShownClippedIsNone() {
        // Already-shown means no *one-time* action; the per-launch Dock
        // fallback (driven by .clipped separately) still runs.
        #expect(MenuBarPresentation.decide(
            visibility: .clipped, hasShownFirstRun: true) == .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuBarPresentationTests`
Expected: FAIL — `cannot find 'MenuBarPresentation' in scope`.

- [ ] **Step 3: Create the implementation**

Create `QuotaMonitor/App/MenuBarPresentation.swift`:

```swift
import Foundation

/// The one-time, first-run-only presentation action. Pure + `Equatable`
/// so the decision table is unit-tested independently of AppKit.
///
/// The Dock-icon / `menuBarUnreachable` side effect is deliberately NOT
/// represented here: it is a *per-launch* consequence of
/// `visibility == .clipped`, applied by the caller on every launch,
/// whereas this decision is gated by `hasShownFirstRun` and fires once.
enum MenuBarPresentation: Equatable {
    /// Icon is visible and we have not presented before — open the
    /// popover so its anchor arrow points at the icon.
    case showPopover
    /// Icon is clipped and we have not presented before — open the
    /// Dashboard window (the per-launch Dock fallback also engages).
    case openFallbackWindow
    /// Nothing to do this launch (already presented once).
    case none

    static func decide(visibility: StatusItemVisibility,
                       hasShownFirstRun: Bool) -> MenuBarPresentation {
        guard !hasShownFirstRun else { return .none }
        switch visibility {
        case .visible: return .showPopover
        case .clipped: return .openFallbackWindow
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MenuBarPresentationTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add QuotaMonitor/App/MenuBarPresentation.swift Tests/QuotaMonitorTests/MenuBarPresentationTests.swift
git commit -m "feat: add pure first-run presentation decision"
```

---

## Task 4: AppEnvironment — shared singleton, menuBarUnreachable, demote predicate

**Files:**
- Modify: `QuotaMonitor/App/AppEnvironment.swift`
- Test: `Tests/QuotaMonitorTests/DemoteToAccessoryPredicateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/QuotaMonitorTests/DemoteToAccessoryPredicateTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotaMonitor

/// The pure predicate behind `AppEnvironment.demoteToAccessory()`. When
/// the menu-bar icon is unreachable we must NEVER demote back to
/// `.accessory` — that would drop the only visible entry (the Dock icon)
/// once the last window closes.
@Suite("Demote-to-accessory predicate")
struct DemoteToAccessoryPredicateTests {

    @Test
    func demotesWhenRegularAndReachable() {
        #expect(AppEnvironment.shouldDemoteToAccessory(
            currentlyRegular: true, menuBarUnreachable: false) == true)
    }

    @Test
    func doesNotDemoteWhenUnreachable() {
        #expect(AppEnvironment.shouldDemoteToAccessory(
            currentlyRegular: true, menuBarUnreachable: true) == false)
    }

    @Test
    func doesNotDemoteWhenAlreadyAccessory() {
        #expect(AppEnvironment.shouldDemoteToAccessory(
            currentlyRegular: false, menuBarUnreachable: false) == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DemoteToAccessoryPredicateTests`
Expected: FAIL — `type 'AppEnvironment' has no member 'shouldDemoteToAccessory'`.

- [ ] **Step 3: Add the shared singleton + `menuBarUnreachable` property**

In `AppEnvironment.swift`, inside the class, add a shared instance and the new state. Add the singleton right after the class opening / `let appServer` declaration (around line 18):

```swift
    /// Process-wide shared instance. The AppKit `AppDelegate` (which owns
    /// the status item) and the SwiftUI `Window` scenes must reference the
    /// same `@Observable` state. Matches the `SettingsStore.shared` /
    /// `LocalizationStore.shared` pattern. `UserDefaultsMigration` still
    /// runs first because `QuotaMonitorApp.init` triggers the first access
    /// only after calling it.
    static let shared = AppEnvironment()
```

And add the observable flag next to the other UI state (e.g. after `var lastError: String?` around line 65):

```swift
    /// True when the status item has been detected as clipped/hidden and
    /// we have promoted to a permanent Dock icon as the fallback entry.
    /// Consulted by `demoteToAccessory()` / `applyDockIconPolicy()` so
    /// closing the last window does NOT drop the Dock icon while the menu
    /// bar remains unreachable.
    var menuBarUnreachable = false
```

- [ ] **Step 4: Add the pure predicate**

In `AppEnvironment.swift`, near the other `nonisolated static` helpers (e.g. just above `withTimeout`), add:

```swift
    /// Pure decision for `demoteToAccessory()`. Only demote when we are
    /// currently `.regular` AND the menu-bar icon is reachable.
    nonisolated static func shouldDemoteToAccessory(
        currentlyRegular: Bool, menuBarUnreachable: Bool) -> Bool {
        currentlyRegular && !menuBarUnreachable
    }
```

- [ ] **Step 5: Route `demoteToAccessory()` through the predicate**

In `AppEnvironment.swift`, replace the guard in `demoteToAccessory()`:

```swift
    func demoteToAccessory() {
        guard NSApp.activationPolicy() == .regular else { return }
```

with:

```swift
    func demoteToAccessory() {
        guard Self.shouldDemoteToAccessory(
            currentlyRegular: NSApp.activationPolicy() == .regular,
            menuBarUnreachable: menuBarUnreachable) else { return }
```

- [ ] **Step 6: Guard `applyDockIconPolicy()`'s demote branch**

In `applyDockIconPolicy()`, the `else` branch currently calls `NSApp.setActivationPolicy(.accessory)` unconditionally. Replace that `else` branch body:

```swift
        } else {
            // Toggle OFF with a window still open: drop the Dock icon
            // right now. The Settings window stays put because it's a
            // `Window(id:)` scene, not the auto-closing `Settings { }`
            // scene the old code had to dance around.
            NSApp.setActivationPolicy(.accessory)
        }
```

with:

```swift
        } else if !menuBarUnreachable {
            // Toggle OFF with a window still open: drop the Dock icon
            // right now. The Settings window stays put because it's a
            // `Window(id:)` scene, not the auto-closing `Settings { }`
            // scene the old code had to dance around.
            //
            // EXCEPT when the menu-bar icon is unreachable — then the
            // Dock icon is the user's only visible entry and we keep it.
            NSApp.setActivationPolicy(.accessory)
        }
```

- [ ] **Step 7: Run test to verify it passes**

Run: `swift test --filter DemoteToAccessoryPredicateTests`
Expected: PASS (3 tests).

- [ ] **Step 8: Commit**

```bash
git add QuotaMonitor/App/AppEnvironment.swift Tests/QuotaMonitorTests/DemoteToAccessoryPredicateTests.swift
git commit -m "feat: add AppEnvironment.shared + menuBarUnreachable demote guard"
```

---

## Task 5: Post a notification when onboarding completes

**Files:**
- Modify: `QuotaMonitor/Core/Settings/SettingsStore.swift`
- Test: `Tests/QuotaMonitorTests/OnboardingCompletionNotificationTests.swift`

**Why:** `AppDelegate` (AppKit, not a SwiftUI view) needs to run the discoverability check *after* a brand-new user finishes onboarding. A notification posted from the single completion path (`markProviderOnboardingDone`) is the explicit hook.

- [ ] **Step 1: Write the failing test**

Create `Tests/QuotaMonitorTests/OnboardingCompletionNotificationTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotaMonitor

@MainActor
@Suite("Onboarding completion notification")
struct OnboardingCompletionNotificationTests {

    private static func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "test.\(name).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test
    func markingDonePostsCompletionNotification() async {
        let store = SettingsStore(defaults: Self.freshDefaults())
        var received = false
        let token = NotificationCenter.default.addObserver(
            forName: .quotaMonitorOnboardingCompleted,
            object: nil, queue: nil) { _ in received = true }
        defer { NotificationCenter.default.removeObserver(token) }

        store.markProviderOnboardingDone()
        #expect(received == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OnboardingCompletionNotificationTests`
Expected: FAIL — `type 'NSNotification.Name' has no member 'quotaMonitorOnboardingCompleted'`.

- [ ] **Step 3: Declare the notification name + post it**

In `SettingsStore.swift`, at file scope (after the imports, before `final class SettingsStore`), add:

```swift
extension Notification.Name {
    /// Posted once the provider step of onboarding is marked done. The
    /// AppKit `AppDelegate` listens for this to run the menu-bar
    /// discoverability check after a fresh user finishes the wizard.
    static let quotaMonitorOnboardingCompleted =
        Notification.Name("dev.tjzhou.QuotaMonitor.onboardingCompleted")
}
```

In `markProviderOnboardingDone()`, after the `lastOnboardedVersion` stamp, add the post as the final statement:

```swift
    func markProviderOnboardingDone() {
        if !hasCompletedProviderOnboarding {
            hasCompletedProviderOnboarding = true
        }
        if let appVersion {
            defaults.set(appVersion, forKey: Keys.lastOnboardedVersion)
        }
        NotificationCenter.default.post(
            name: .quotaMonitorOnboardingCompleted, object: nil)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OnboardingCompletionNotificationTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add QuotaMonitor/Core/Settings/SettingsStore.swift Tests/QuotaMonitorTests/OnboardingCompletionNotificationTests.swift
git commit -m "feat: post notification when onboarding completes"
```

---

## Task 6: WindowRouter seam

**Files:**
- Create: `QuotaMonitor/App/WindowRouter.swift`

**Why:** AppKit code (`AppDelegate`) cannot call SwiftUI's `@Environment(\.openWindow)` directly. `WindowRouter` is the single seam: AppKit requests a window by id, and a long-lived SwiftUI driver (mounted in Task 9) performs the actual `openWindow`. The driver mechanism is validated by the spike in Task 8; if `openWindow` does not fire from a hosted view, Task 8 swaps the driver for a URL-scheme implementation **without changing this seam's call sites**.

- [ ] **Step 1: Create the router (no test — trivial observable holder verified via app run)**

Create `QuotaMonitor/App/WindowRouter.swift`:

```swift
import Observation

/// Single seam for opening SwiftUI `Window(id:)` scenes from AppKit
/// contexts (the `AppDelegate` / `StatusItemController`, which have no
/// access to SwiftUI's `openWindow` environment action).
///
/// Producers call `request(_:)`. A long-lived SwiftUI driver view
/// (mounted in `QuotaMonitorApp`) observes `pendingOpen`, performs the
/// real open, then clears it back to nil.
@Observable
@MainActor
final class WindowRouter {
    static let shared = WindowRouter()

    /// The window id requested to open ("onboarding" / "dashboard" /
    /// "settings"), or nil when there is nothing pending.
    var pendingOpen: String?

    func request(_ id: String) { pendingOpen = id }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds (the type is referenced by later tasks; nothing uses it yet, which is fine).

- [ ] **Step 3: Commit**

```bash
git add QuotaMonitor/App/WindowRouter.swift
git commit -m "feat: add WindowRouter seam for AppKit-initiated window opens"
```

---

## Task 7: StatusItemController

**Files:**
- Create: `QuotaMonitor/App/StatusItemController.swift`

**Note:** This is AppKit UI glue — verified by building and running the app (Task 9), not by a unit test. It is created now so Task 8 can spike against it.

- [ ] **Step 1: Create the controller**

Create `QuotaMonitor/App/StatusItemController.swift`:

```swift
import AppKit
import SwiftUI

/// Owns the AppKit `NSStatusItem` that replaced the SwiftUI
/// `MenuBarExtra`. AppKit is required for two things `MenuBarExtra`
/// cannot do: open the popover programmatically (first-run auto-open)
/// and read the status item's on-screen geometry (clip detection).
///
/// The existing SwiftUI views are reused verbatim:
///   - menu-bar label  → `NSHostingView(HostedLabel)`
///   - popover content → `NSHostingController(HostedContent)`
///
/// The two `Hosted*` wrappers read `loc.tickForceRedraw` in their body so
/// a language switch re-renders the hosted tree (a bare `NSHostingView`
/// captures its rootView once and would otherwise miss the static-`L10n`
/// refresh that `.id(tickForceRedraw)` drives).
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let env: AppEnvironment
    private let settings: SettingsStore

    /// Invoked when the display configuration changes (external monitor,
    /// resolution, notch) so the owner can re-run the clip check.
    var onScreenChange: (() -> Void)?

    init(env: AppEnvironment,
         localization: LocalizationStore,
         settings: SettingsStore) {
        self.env = env
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(
            length: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        statusItem.autosaveName = "QuotaMonitor"   // nudge placement only

        let host = NSHostingView(rootView: HostedLabel()
            .environment(env)
            .environment(localization)
            .environment(settings)
            .environment(\.locale, localization.locale))
        host.translatesAutoresizingMaskIntoConstraints = false
        if let button = statusItem.button {
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: HostedContent()
                .environment(env)
                .environment(localization)
                .environment(settings)
                .environment(\.locale, localization.locale))

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    /// Open the popover anchored to the status button. Used both by the
    /// button click and by the first-run auto-open.
    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds,
                     of: button,
                     preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// `NSPopoverDelegate` — the authoritative "popover opened" hook now
    /// that we own the popover. Mirrors the old
    /// `MenuBarContentView.onAppear` refresh-on-open (which depended on
    /// `MenuBarExtra` re-mounting its content each open).
    func popoverWillShow(_ notification: Notification) {
        guard !settings.needsProviderOnboarding else { return }
        env.refreshAll(throttle: true, trigger: "popover")
    }

    // MARK: - visibility

    /// Live clip check. Wraps the pure `MenuBarVisibilityEvaluator` with
    /// the AppKit geometry: the status button's window frame and the
    /// frame of the screen hosting it (falling back to the main screen).
    func currentVisibility() -> StatusItemVisibility {
        guard statusItem.isVisible,
              let win = statusItem.button?.window else { return .clipped }
        let screenFrame = (win.screen ?? NSScreen.main)?.frame
        return MenuBarVisibilityEvaluator.evaluate(
            buttonWindowFrame: win.frame, hostScreenFrame: screenFrame)
    }

    @objc private func screenParamsChanged() { onScreenChange?() }
}

// MARK: - hosted SwiftUI wrappers

/// Wraps `MenuBarLabelView` so reading `loc.tickForceRedraw` in the body
/// re-renders the `NSHostingView` on a language switch.
private struct HostedLabel: View {
    @Environment(LocalizationStore.self) private var loc
    var body: some View {
        MenuBarLabelView().id(loc.tickForceRedraw)
    }
}

private struct HostedContent: View {
    @Environment(LocalizationStore.self) private var loc
    var body: some View {
        MenuBarContentView().id(loc.tickForceRedraw)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds. (Not yet wired into the app — Task 9 does that.)

- [ ] **Step 3: Commit**

```bash
git add QuotaMonitor/App/StatusItemController.swift
git commit -m "feat: add StatusItemController (NSStatusItem + popover host)"
```

---

## Task 8: AppDelegate + discoverability orchestration

**Files:**
- Create: `QuotaMonitor/App/AppDelegate.swift`

**Note:** Verified by building/running in Task 9. The orchestration leans on the pure decisions (`MenuBarPresentation`, `MenuBarVisibilityEvaluator`) already unit-tested.

- [ ] **Step 1: Create the AppDelegate**

Create `QuotaMonitor/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

/// Owns the menu-bar status item and the launch-time discoverability
/// orchestration. Attached via `@NSApplicationDelegateAdaptor` in
/// `QuotaMonitorApp`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = AppEnvironment.shared
        let loc = LocalizationStore.shared
        let settings = SettingsStore.shared

        let controller = StatusItemController(
            env: env, localization: loc, settings: settings)
        controller.onScreenChange = { [weak self] in
            self?.enforceClipFallback()
        }
        self.statusItemController = controller

        // Launch fan-out previously carried by the MenuBarExtra `.task`.
        env.refreshAll(throttle: false, trigger: "launch")
        env.refreshDashboard()
        env.refreshMenuBar(trigger: "launch")
        env.startBackgroundPolling()

        // Onboarding window on launch (previously MenuBarLabelView.task).
        if loc.needsOnboarding || settings.needsProviderOnboarding {
            WindowRouter.shared.request("onboarding")
            // A brand-new user is mid-wizard; defer the discoverability
            // check until they finish (see notification observer below).
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onboardingCompleted),
                name: .quotaMonitorOnboardingCompleted,
                object: nil)
        } else {
            scheduleDiscoverabilityCheck()
        }
    }

    @objc private func onboardingCompleted() {
        NotificationCenter.default.removeObserver(
            self, name: .quotaMonitorOnboardingCompleted, object: nil)
        scheduleDiscoverabilityCheck()
    }

    /// Give the status item a beat to lay out before we read its frame.
    private func scheduleDiscoverabilityCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.runDiscoverabilityCheck()
        }
    }

    /// One-time first-run presentation + per-launch clip fallback.
    private func runDiscoverabilityCheck() {
        guard let controller = statusItemController else { return }
        let visibility = controller.currentVisibility()

        // Per-launch: clipped → permanent Dock icon + mark unreachable so
        // closing the last window can't drop the only visible entry.
        applyUnreachableState(clipped: visibility == .clipped)

        // One-time presentation.
        let action = MenuBarPresentation.decide(
            visibility: visibility,
            hasShownFirstRun: SettingsStore.shared.hasShownFirstRunPresentation)
        switch action {
        case .showPopover:
            controller.showPopover()
        case .openFallbackWindow:
            AppEnvironment.shared.activateForWindow()
            WindowRouter.shared.request("dashboard")
            AppEnvironment.shared.refreshDashboard()
        case .none:
            break
        }
        if action != .none {
            SettingsStore.shared.hasShownFirstRunPresentation = true
        }
    }

    /// Per-launch / on-screen-change enforcement of the Dock fallback,
    /// without the one-time presentation.
    private func enforceClipFallback() {
        guard let controller = statusItemController else { return }
        applyUnreachableState(clipped: controller.currentVisibility() == .clipped)
    }

    private func applyUnreachableState(clipped: Bool) {
        let env = AppEnvironment.shared
        env.menuBarUnreachable = clipped
        if clipped {
            NSApp.setActivationPolicy(.regular)
        }
        // When reachable we leave the activation policy to the existing
        // Dock-icon-for-windows logic; we never force `.accessory` here
        // (a window may legitimately be holding `.regular`).
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds.

- [ ] **Step 3: Commit**

```bash
git add QuotaMonitor/App/AppDelegate.swift
git commit -m "feat: add AppDelegate with discoverability orchestration"
```

---

## Task 9: Swap QuotaMonitorApp from MenuBarExtra to NSStatusItem (+ spike)

**Files:**
- Modify: `QuotaMonitor/App/QuotaMonitorApp.swift`
- Modify: `QuotaMonitor/Features/MenuBar/MenuBarContentView.swift`
- Modify: `QuotaMonitor/Features/MenuBar/MenuBarLabelView.swift`

**This task contains the central spike (Step 5): confirm `openWindow` fires from the hosted popover. The onboarding window open is mission-critical, so if the spike fails, Step 6 switches `WindowRouter` to a URL-scheme driver before proceeding.**

- [ ] **Step 1: Remove the `MenuBarExtra` scene and add the adaptor + router driver**

In `QuotaMonitorApp.swift`, change the `environment` State to the shared singleton. Replace:

```swift
        _environment = State(wrappedValue: AppEnvironment())
```

with:

```swift
        _environment = State(wrappedValue: AppEnvironment.shared)
```

Add the adaptor as the first stored property of the `App` struct (after `@main struct QuotaMonitorApp: App {`):

```swift
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```

Delete the entire `MenuBarExtra { … } label: { … } .menuBarExtraStyle(.window).windowResizability(.contentSize)` block (lines ~74–116). Replace it with a `WindowGroup`-free driver hosted in the onboarding scene's content via a background modifier. Concretely, add a `.background(WindowRouterDriver())` to the **first** `Window` scene's root view (the onboarding scene), so a long-lived SwiftUI view can service `WindowRouter`. On the onboarding `OnboardingView()` add:

```swift
            OnboardingView()
                .environment(localization)
                .environment(settings)
                .environment(environment)
                .environment(\.locale, localization.locale)
                .id(localization.tickForceRedraw)
                .background(WindowRouterDriver())
```

Then add the driver view at the bottom of `QuotaMonitorApp.swift` (outside the struct):

```swift
/// Long-lived SwiftUI view that services `WindowRouter` requests by
/// calling the real `openWindow` action. Mounted via `.background` on a
/// `Window` scene so it lives inside the scene environment that provides
/// `openWindow`.
private struct WindowRouterDriver: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppEnvironment.self) private var env
    private var router = WindowRouter.shared

    var body: some View {
        Color.clear
            .onChange(of: router.pendingOpen) { _, id in
                guard let id else { return }
                env.activateForWindow()
                openWindow(id: id)
                router.pendingOpen = nil
            }
    }
}
```

> Note: `router` is a `let`/computed reference to the `@Observable` singleton; `onChange(of:)` observes `router.pendingOpen` because reading it in the closure registers the dependency. If the linter requires `@State`, use `@State private var router = WindowRouter.shared`.

- [ ] **Step 2: Drop the redundant popover-open refresh**

In `MenuBarContentView.swift`, remove the `.onAppear { … env.refreshAll(throttle: true, trigger: "popover") }` modifier (lines ~54–61). The `StatusItemController.popoverWillShow` now owns refresh-on-open. Leave the rest of the view unchanged.

- [ ] **Step 3: Drop the launch onboarding-open task from the label**

In `MenuBarLabelView.swift`, remove the `.task { if loc.needsOnboarding || settings.needsProviderOnboarding { openWindow(id: "onboarding") } }` block (lines ~79–83) and the now-unused `@Environment(\.openWindow) private var openWindow` (line ~48). `AppDelegate` now opens onboarding on launch via `WindowRouter`.

- [ ] **Step 4: Build and launch**

Run: `./build.sh && open .build/QuotaMonitor.app`
Expected: the app launches; a `5h … · 7d …` (or gauge) item appears in the menu bar; clicking it toggles the popover open/closed.

- [ ] **Step 5: SPIKE — verify `openWindow` fires from the hosted popover**

With the popover open, click **Open Dashboard** (⌘D) inside it.
Expected (PASS): the Dashboard window opens and comes to the front.

If the Dashboard window opens → the hosted `openWindow` path works; `WindowRouterDriver` will also work. **Skip Step 6.**

If nothing happens (no window) → `openWindow` does not fire from manually-hosted views. **Do Step 6** before continuing.

- [ ] **Step 6: (ONLY IF SPIKE FAILED) Switch WindowRouter to a URL-scheme driver**

6a. Register a URL scheme. In `QuotaMonitor/Resources/Info.plist`, add inside the top-level `<dict>`:

```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>dev.tjzhou.QuotaMonitor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>quotamonitor</string>
			</array>
		</dict>
	</array>
```

6b. Make each `Window` scene respond to its URL. In `QuotaMonitorApp.swift`, add `.handlesExternalEvents(matching: ["onboarding"])` to the onboarding `Window`, `["dashboard"]` to the dashboard `Window`, and `["settings"]` to the settings `Window`. Add the app-level handler on the onboarding scene root:

```swift
                .onOpenURL { url in
                    guard let host = url.host else { return }
                    // host is the window id, e.g. quotamonitor://dashboard
                    // SwiftUI routes it to the scene whose
                    // handlesExternalEvents matches `host`.
                    _ = host
                }
```

6c. Change `WindowRouter.request` to open the URL instead of setting `pendingOpen`:

```swift
import AppKit

    func request(_ id: String) {
        guard let url = URL(string: "quotamonitor://\(id)") else { return }
        NSWorkspace.shared.open(url)
    }
```

6d. Remove the now-unused `WindowRouterDriver` `.background(...)` and the driver struct from Step 1 (the URL scheme replaces it). Rebuild: `./build.sh && open .build/QuotaMonitor.app`. Re-verify Open Dashboard works (this time via the in-popover button, still using SwiftUI `openWindow`, which works inside the popover content regardless — the URL path is only for AppKit-initiated opens in Task 8).

- [ ] **Step 7: Run the full test suite (no regressions)**

Run: `swift test`
Expected: all suites PASS.

- [ ] **Step 8: Commit**

```bash
git add QuotaMonitor/App/QuotaMonitorApp.swift QuotaMonitor/Features/MenuBar/MenuBarContentView.swift QuotaMonitor/Features/MenuBar/MenuBarLabelView.swift QuotaMonitor/Resources/Info.plist
git commit -m "feat: replace MenuBarExtra with NSStatusItem-backed menu bar"
```

---

## Task 10: Dashboard "icon may be hidden" hint banner

**Files:**
- Modify: `QuotaMonitor/Core/Localization/L10n.swift`
- Modify: `QuotaMonitor/Features/Dashboard/DashboardView.swift`

- [ ] **Step 1: Add the strings**

In `L10n.swift`, add to an appropriate `MARK` group (e.g. near the menu-bar group):

```swift
    // MARK: - menu-bar discoverability hint

    static var menuBarHiddenHintTitle: String {
        t(en: "Menu-bar icon may be hidden",
          zh: "菜单栏图标可能被隐藏")
    }
    static var menuBarHiddenHintBody: String {
        t(en: "QuotaMonitor's menu-bar icon doesn't fit on your menu bar — it may be behind the notch or hidden by a menu-bar manager (e.g. Bartender, Ice). A Dock icon is shown so you can always reach the app.",
          zh: "QuotaMonitor 的菜单栏图标在你的菜单栏放不下——可能被刘海挡住，或被菜单栏整理工具（如 Bartender、Ice）隐藏了。已为你显示 Dock 图标，便于随时打开应用。")
    }
    static var menuBarHiddenHintDismiss: String {
        t(en: "Got it", zh: "知道了")
    }
```

- [ ] **Step 2: Add the banner to the Dashboard**

In `DashboardView.swift`, read the env + settings and conditionally show a banner at the top of the dashboard's main content. Add these environment reads if not already present:

```swift
    @Environment(AppEnvironment.self) private var env
    @Environment(SettingsStore.self) private var settings
```

At the top of the dashboard's outermost `VStack`/`ScrollView` content (before the existing sections), insert:

```swift
            if env.menuBarUnreachable && !settings.firstRunHintDismissed {
                hiddenIconHint
            }
```

And add the banner builder as a private property in `DashboardView`:

```swift
    @ViewBuilder
    private var hiddenIconHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "menubar.rectangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.menuBarHiddenHintTitle)
                    .font(.headline)
                Text(L10n.menuBarHiddenHintBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(L10n.menuBarHiddenHintDismiss) {
                settings.firstRunHintDismissed = true
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 4)
    }
```

> If `DashboardView`'s body structure differs (e.g. it delegates to section subviews), place `hiddenIconHint` as the first child of whichever container renders the page body, keeping it above the Forecast section. Match the file's existing padding/spacing idiom.

- [ ] **Step 3: Build and verify the banner renders**

Run: `./build.sh && open .build/QuotaMonitor.app`
Manual: temporarily force the banner by setting `env.menuBarUnreachable = true` is not directly toggle-able from UI, so verify via the clipped-bar manual test in Task 11. For a quick standalone check, confirm the build compiles and the strings resolve:
Run: `swift build`
Expected: builds with no missing-symbol errors.

- [ ] **Step 4: Commit**

```bash
git add QuotaMonitor/Core/Localization/L10n.swift QuotaMonitor/Features/Dashboard/DashboardView.swift
git commit -m "feat: add Dashboard hint banner when menu-bar icon is hidden"
```

---

## Task 11: Manual verification matrix

**Files:** none (verification only)

Run: `./build.sh && open .build/QuotaMonitor.app` for each scenario. Use a clean state to exercise first-run paths:

```bash
defaults delete dev.tjzhou.QuotaMonitor 2>/dev/null || true
```

- [ ] **Scenario A — fresh install, roomy menu bar (icon visible):**
  1. Delete defaults (above), launch.
  2. Complete onboarding (pick a language + provider, click Continue).
  3. Expected: ~0.6s after finishing onboarding the popover auto-opens, its anchor arrow pointing at the icon. No Dock icon (default policy).
  4. Quit and relaunch → popover does NOT auto-open again (`hasShownFirstRunPresentation` is set).

- [ ] **Scenario B — fresh install, packed menu bar / notch (icon clipped):**
  1. Fill the menu bar so the new item is clipped (open many menu-bar apps on a notched MacBook, or use a non-notched display with a deliberately overcrowded bar; alternatively run a menu-bar manager that hides items).
  2. Delete defaults, launch, complete onboarding.
  3. Expected: no popover (icon unreachable); a **Dock icon appears** and the **Dashboard window opens** showing the orange "Menu-bar icon may be hidden" banner.
  4. Close the Dashboard window → Dock icon **remains** (because `menuBarUnreachable`).
  5. Quit and relaunch (still packed) → Dock icon appears again on launch (per-launch enforcement); Dashboard does NOT auto-open (one-time presentation already shown); banner not shown unless Dashboard opened.
  6. Click **Got it** on the banner → it stays dismissed across launches.

- [ ] **Scenario C — language switch reactivity:**
  1. Open Settings → switch language.
  2. Expected: the menu-bar label and the popover content re-render in the new language (validates `HostedLabel`/`HostedContent` `tickForceRedraw` wiring).

- [ ] **Scenario D — popover refresh-on-open:**
  1. With logs streaming (`log stream --predicate 'subsystem == "dev.tjzhou.QuotaMonitor"' --level info`), open the popover.
  2. Expected: a `refresh.all` operation with `trigger: "popover"` fires (validates `popoverWillShow`).

- [ ] **Scenario E — display change re-check:**
  1. With the icon clipped and Dock icon present, plug in / unplug an external display (or change resolution).
  2. Expected: the clip check re-runs; if the icon becomes reachable on the new layout the Dock icon is released on the next window-close cycle, and stays if still clipped.

- [ ] **Scenario F — existing user upgrade (onboarding already complete):**
  1. Set `defaults write dev.tjzhou.QuotaMonitor onboarding.providersDone -bool true` and `defaults write dev.tjzhou.QuotaMonitor onboarding.lastVersion -string "9.9.9"` (skip onboarding reset), launch.
  2. Expected: no onboarding window; discoverability check runs ~0.6s after launch directly; visible → popover auto-opens once, clipped → Dock + Dashboard once.

- [ ] **Commit (verification notes, if any fixes were needed):** commit any fixes discovered, referencing the scenario.

---

## Self-Review

**Spec coverage:**
- Migration `MenuBarExtra` → `NSStatusItem` → Tasks 7, 9. ✓
- Auto-open popover when visible → Task 8 (`.showPopover`) + Task 9 spike. ✓
- Clip detection → Task 2 (pure) + Task 7 (`currentVisibility`). ✓
- Permanent Dock fallback when clipped (per-launch) → Task 8 `applyUnreachableState`. ✓
- One-time window open + hint when clipped → Task 8 (`.openFallbackWindow`) + Task 10 banner. ✓
- `AppEnvironment.shared` + `menuBarUnreachable` integration into demote/policy → Task 4. ✓
- First-run flags → Task 1; hint-dismissed flag → Task 1 + Task 10. ✓
- Onboarding-gated timing → Task 5 (notification) + Task 8 (observer/defer). ✓
- i18n redraw of hosted views → Task 7 (`HostedLabel`/`HostedContent`). ✓
- Risk #1 (openWindow from hosting) → Task 6 seam + Task 9 spike + URL-scheme fallback. ✓
- Risk #2 (fail-open clip detection) → Task 2 tests + evaluator doc. ✓
- L10n EN + zh strings → Task 10. ✓

**Placeholder scan:** No TBD/TODO. Conditional Step 6 (URL-scheme) is fully written, not a placeholder; it is gated on the spike outcome. The DashboardView insertion note allows for structural variance but gives exact code.

**Type consistency:** `StatusItemVisibility` (Task 2) used by `MenuBarPresentation.decide` (Task 3), `StatusItemController.currentVisibility()` (Task 7), `AppDelegate` (Task 8). `MenuBarPresentation` cases `.showPopover` / `.openFallbackWindow` / `.none` consistent across Tasks 3 and 8. `WindowRouter.request(_:)` / `pendingOpen` consistent across Tasks 6, 8, 9. `menuBarUnreachable` / `shouldDemoteToAccessory` / `hasShownFirstRunPresentation` / `firstRunHintDismissed` / `.quotaMonitorOnboardingCompleted` names consistent across all referencing tasks.
