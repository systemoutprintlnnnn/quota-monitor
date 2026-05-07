import SwiftUI
import AppKit

struct MainWindowView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tab: Tab = .dashboard

    enum Tab: Hashable { case dashboard, history, sessions }

    var body: some View {
        @Bindable var env = env

        Group {
            switch tab {
            case .dashboard: DashboardView()
            case .history:   HistoryView()
            case .sessions:  SessionsView()
            }
        }
        .id(env.providerFilter)     // force inner views to reload state on switch
        .frame(minWidth: 820, minHeight: 560)
        .toolbar {
            // Provider filter — left side, compact menu.
            ToolbarItem(placement: .navigation) {
                Picker("", selection: $env.providerFilter) {
                    ForEach(ProviderFilter.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            // Inner section switch — center, segmented with icon + title.
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    Label(L10n.dashboardTitle, systemImage: "chart.bar.xaxis").tag(Tab.dashboard)
                    Label(L10n.historyTitle,   systemImage: "calendar").tag(Tab.history)
                    Label(L10n.sessionsTitle,  systemImage: "list.bullet.rectangle").tag(Tab.sessions)
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .labelsHidden()
                .fixedSize()
            }

            // Reload — right.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    env.refreshDashboard()
                } label: {
                    Label(L10n.reload, systemImage: "arrow.clockwise")
                }
                .disabled(env.isLoadingDashboard)
                .help(L10n.reload)
            }
        }
        .onDisappear {
            // When user closes the window, drop back to menu-bar-only mode so
            // the Dock icon doesn't linger.
            env.demoteToAccessory()
        }
    }
}
