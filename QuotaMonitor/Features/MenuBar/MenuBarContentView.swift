import SwiftUI
import AppKit

// Top-level menu-bar popover. Only chrome + provider-block delegation here;
// the heavy view code lives in:
//   - ProviderBlock.swift   (codex / claude blocks + shared chrome)
//   - ScanStatusView.swift  (last-scan row + errors popover)
//   - QuotaRow.swift / Claude5hRow.swift / CopyButton.swift (atoms)

struct MenuBarContentView: View {
    @Environment(AppEnvironment.self) var env
    @Environment(SettingsStore.self) var settings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @State var showingErrors = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            // Two grouped provider blocks. Each block owns its own KPI line
            // + quota rows so the user can scan one column from top to
            // bottom without bouncing between Codex / Claude data spread
            // across 5 separate cards (the prior layout). Section colors
            // (blue / orange) match the Dashboard provider filter chips.
            if let snap = env.menuBarSnapshot {
                codexProviderBlock(stats: snap.codex)
                claudeProviderBlock(stats: snap.claude,
                                    blocks: snap.anthropicBlocks)
            } else {
                ProgressView(L10n.loading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }

            Divider()

            scanStatus

            HStack {
                // Single "Refresh" button: rescan local JSONL files AND
                // pull live Codex rate limits in one go. Two buttons used
                // to confuse users (Refresh = "API + KPI", Scan = "files +
                // KPI") because the difference was an implementation
                // leak, not a meaningful user choice. Claude /usage stays
                // out — it's edge-rate-limited and only the 2h background
                // poller may touch it.
                //
                // Both `isScanning` (file rescan) and `isRefreshingRateLimits`
                // (Codex /rateLimits/read) feed the spinner + disabled state
                // because runScan() and refreshRateLimits() flip independent
                // flags but visually they are one operation to the user.
                let busy = env.isScanning || env.isRefreshingRateLimits
                Button(busy ? L10n.refreshing : L10n.refresh) {
                    env.refreshRateLimits()
                    env.runScan() // tail of runScan() also calls refreshMenuBar()
                }
                .disabled(busy)
                .keyboardShortcut("r")
                Spacer()
                Button(L10n.quit) { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }

            Button {
                env.activateForWindow()
                openWindow(id: "dashboard")
                env.refreshDashboard()
            } label: {
                Label(L10n.openDashboard, systemImage: "chart.bar.xaxis")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut("d")

            // macOS 14+ official entry point. The previous
            // `NSApp.sendAction(Selector(("showSettingsWindow:")), …)`
            // hack silently no-op'd because the private selector was
            // retired in macOS 14, which is why this button "did
            // nothing" before. `openSettings` is the SwiftUI environment
            // action that replaces it. activateForWindow() runs first
            // so the Settings window comes forward over the menu popover.
            Button {
                env.activateForWindow()
                openSettings()
            } label: {
                Label(L10n.settingsMenuItem, systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .keyboardShortcut(",")
        }
        .padding(14)
        .frame(width: 360)
        // Allow click-and-drag to select any number / label in the popover.
        // Buttons stay clickable — `.textSelection` only affects standalone
        // Text views, not text inside Button labels. Lets the user copy
        // a USD figure or a token count without screenshotting.
        .textSelection(.enabled)
        // Refresh whenever the popover comes back into the foreground so the
        // user always sees current stats without clicking Refresh.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { env.refreshMenuBar() }
        }
    }

    private var header: some View {
        HStack {
            // Product name — intentionally not localized (see L10n proper-noun policy).
            Text("Quota Monitor")
                .font(.headline)
            Spacer()
            if env.isLoadingMenuBar {
                ProgressView().controlSize(.small)
            }
        }
    }
}
