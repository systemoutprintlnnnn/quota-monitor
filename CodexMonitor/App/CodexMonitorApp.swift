import SwiftUI

@main
struct CodexMonitorApp: App {
    @State private var environment = AppEnvironment()
    // Single source of truth for language selection. Wired into the
    // SwiftUI environment so any view can switch language at runtime
    // via `@Environment(LocalizationStore.self)`. We pass the same
    // instance into all three Scenes so the menu bar, dashboard, and
    // Settings windows stay in sync — switching language in Settings
    // updates the menu bar popover instantly.
    @State private var localization = LocalizationStore.shared
    // SettingsStore drives non-language preferences (menu bar headline
    // window, poll cadence, paths, keychain policy). Same lifetime as
    // localization — exposed in every Scene so any view can flip a
    // setting and have it reflected app-wide on the next render.
    @State private var settings = SettingsStore.shared

    var body: some Scene {
        MenuBarExtra("Codex Monitor", systemImage: "gauge.with.dots.needle.50percent") {
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
                .sheet(isPresented: .constant(localization.needsOnboarding)) {
                    LanguageOnboardingView()
                        .environment(localization)
                }
                .task {
                    environment.refreshRateLimits()
                    environment.refreshDashboard()
                    environment.refreshMenuBar()
                    environment.startBackgroundPolling()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Codex Monitor", id: "dashboard") {
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
