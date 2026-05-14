import SwiftUI

@main
struct QuotaMonitorApp: App {
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
        _environment = State(wrappedValue: AppEnvironment())
        _localization = State(wrappedValue: LocalizationStore.shared)
        _settings = State(wrappedValue: SettingsStore.shared)
    }

    var body: some Scene {
        // Label-content MenuBarExtra so we can render a custom view in
        // the menu bar slot itself — `MenuBarLabelView` shows live
        // 5h/7d usage % for the user-chosen provider, falling back to
        // the same gauge SF Symbol the app shipped with when there's
        // no usable data.
        MenuBarExtra {
            MenuBarContentView()
                .environment(environment)
                .environment(localization)
                .environment(settings)
                .environment(\.locale, localization.locale)
                // Re-evaluate body whenever language flips. `L10n.foo` is
                // a static read SwiftUI can't track on its own, so we
                // explicitly read `tickForceRedraw` to register a
                // dependency.
                .id(localization.tickForceRedraw)
                .sheet(isPresented: .constant(
                    localization.needsOnboarding || settings.needsProviderOnboarding
                )) {
                    OnboardingView()
                        .environment(localization)
                        .environment(settings)
                        .environment(environment)
                }
                .task {
                    environment.refreshRateLimits()
                    environment.refreshDashboard()
                    environment.refreshMenuBar()
                    environment.startBackgroundPolling()
                }
        } label: {
            MenuBarLabelView()
                .environment(environment)
                .environment(settings)
        }
        .menuBarExtraStyle(.window)

        Window("Quota Monitor", id: "dashboard") {
            MainWindowView()
                .environment(environment)
                .environment(localization)
                .environment(settings)
                .environment(\.locale, localization.locale)
                .id(localization.tickForceRedraw)
        }
        .defaultSize(width: 980, height: 680)

        Settings {
            SettingsView()
                .environment(environment)
                .environment(localization)
                .environment(settings)
                .environment(\.locale, localization.locale)
                .id(localization.tickForceRedraw)
        }
        // Let the Settings window grow/shrink to whatever the inner
        // view's min/ideal frame allows. Without this the scene defaults
        // can clamp the window to its first measurement and ignore drag.
        .windowResizability(.contentMinSize)
    }
}
