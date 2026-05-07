import SwiftUI

// Top-level Settings window. Tab content lives in:
//   - GeneralSettingsTab.swift   (Language, menu bar window, polling, notify)
//   - PricingSettingsTab.swift   (LiteLLM sync + read-only catalog)
//   - AdvancedSettingsTab.swift  (paths, keychain, database, CSV export)
//
// **Why three tabs not two:** General stays short on purpose so first-
// time users don't bounce off a wall of knobs. Pricing has its own tab
// because the catalog table needs the full window width. Advanced
// collects every "I know what I'm doing" toggle in one place.

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(LocalizationStore.self) private var loc
    @State private var settings = SettingsStore.shared

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environment(settings)
                .environment(loc)
                .tabItem { Label(L10n.settingsTabGeneral, systemImage: "gearshape") }
            PricingSettingsTab()
                .environment(env)
                .tabItem { Label(L10n.settingsTabPricing, systemImage: "dollarsign.circle") }
            AdvancedSettingsTab()
                .environment(settings)
                .environment(env)
                .tabItem { Label(L10n.settingsTabAdvanced, systemImage: "wrench.and.screwdriver") }
        }
        // Use min + ideal instead of a fixed size. The previous
        // `.frame(width:height:)` pinned the content to a single
        // dimension, which made the Settings window non-resizable —
        // dragging the corners had no effect because the inner view
        // refused to grow. min keeps tabs from collapsing into illegible
        // widths; ideal is what the window opens at.
        .frame(minWidth: 480, idealWidth: 620, minHeight: 380, idealHeight: 520)
        // Make every Text in Settings copyable. textSelection is an
        // environment value that propagates to descendant Text views, so
        // setting it once at the TabView root covers all three tabs and
        // any future ones — easier than auditing every individual label.
        // Form controls (Toggle / Picker / Stepper labels) are unaffected
        // because they render as control text, not Text.
        .textSelection(.enabled)
    }
}
