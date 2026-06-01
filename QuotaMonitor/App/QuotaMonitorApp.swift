import SwiftUI

@main
struct QuotaMonitorApp: App {
    // The AppDelegate owns the AppKit NSStatusItem (which replaced the
    // SwiftUI MenuBarExtra) and the launch-time discoverability
    // orchestration. It references the same `.shared` singletons the
    // scenes below use.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment
    // Single source of truth for language selection. Wired into the
    // SwiftUI environment so any view can switch language at runtime
    // via `@Environment(LocalizationStore.self)`. We pass the same
    // instance into all three Scenes so the menu bar, dashboard, and
    // Settings windows stay in sync — switching language in Settings
    // updates the menu bar popover instantly.
    @State private var localization: LocalizationStore
    // SettingsStore drives non-language preferences (menu bar headline
    // window, poll cadence, paths, keychain policy). Same lifetime as
    // localization — exposed in every Scene so any view can flip a
    // setting and have it reflected app-wide on the next render.
    @State private var settings: SettingsStore

    init() {
        // Migrate UserDefaults from the legacy `dev.tjzhou.CodexMonitor`
        // bundle id BEFORE the @Observable singletons below read their
        // persisted values. The State wrappers below are assigned in
        // this init body (NOT via `=` defaults at declaration), so we
        // can guarantee the migration runs first. If you switch back
        // to inline defaults like `@State private var foo = X.shared`,
        // those default expressions run before this init body and you
        // lose the migration on the first launch under the new id.
        UserDefaultsMigration.runIfNeeded()
        _environment = State(wrappedValue: AppEnvironment.shared)
        _localization = State(wrappedValue: LocalizationStore.shared)
        _settings = State(wrappedValue: SettingsStore.shared)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let snap = SettingsStore.snapshot()
        if snap.developerModeEnabled {
            DeveloperLog.eventRecord(
                "app.start",
                category: "app",
                trigger: "launch",
                fields: [
                    "version": .string(version),
                    "bundle_id": .string(bundleID),
                    "pid": .int(Int(ProcessInfo.processInfo.processIdentifier)),
                    "log_path": .string(DeveloperLog.logFileURL.path),
                    "database_path": .string(DatabaseManager.defaultURL().path),
                    "enabled_providers": .string(snap.enabledProviders.sorted().joined(separator: ",")),
                    "poll_interval_seconds": .int(snap.pollIntervalSeconds),
                    "onboarding_done": .bool(snap.hasCompletedProviderOnboarding),
                    "codex_fast_mode_billing": .bool(snap.codexFastModeBilling)
                ])
        }
    }

    var body: some Scene {
        // The whole shell is AppKit-owned: the menu-bar presence is an
        // `NSStatusItem` (`StatusItemController`), and the four real app
        // windows — onboarding / dashboard / settings / menubar-help — are
        // `NSWindowController`s managed by `WindowManager`, hosting these same
        // SwiftUI views via `NSHostingController`. AppKit code and SwiftUI
        // views all open windows through `WindowManager.show(_:)`; there is no
        // longer a `quotamonitor://` URL scheme or `openWindow` split.
        //
        // A SwiftUI `App` must still declare at least one `Scene`. This inert,
        // hidden placeholder satisfies that requirement and nothing else;
        // macOS auto-opens it at launch and `AppDelegate.closeStrayWindows()`
        // immediately closes it.
        Window("", id: "__inert__") {
            EmptyView().frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)
    }
}
