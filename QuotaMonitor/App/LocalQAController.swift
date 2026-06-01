import AppKit
import Foundation

@MainActor
final class LocalQAController {
    private let configuration: LocalQAConfiguration
    private let environment: AppEnvironment
    private let statusItemController: StatusItemController

    init(configuration: LocalQAConfiguration,
         environment: AppEnvironment,
         statusItemController: StatusItemController) {
        self.configuration = configuration
        self.environment = environment
        self.statusItemController = statusItemController
    }

    func start() {
        Task { @MainActor in
            await run()
        }
    }

    private func run() async {
        try? FileManager.default.createDirectory(
            at: configuration.outputDirectory,
            withIntermediateDirectories: true)

        await pause(seconds: 0.8)
        for step in configuration.steps {
            switch step {
            case .openDashboard:
                environment.activateForWindow()
                WindowRouter.shared.request("dashboard")
                await pause(seconds: 0.8)
            case .openSettings:
                environment.activateForWindow()
                WindowRouter.shared.request("settings")
                await pause(seconds: 0.8)
            case .openMenuBarHelp:
                environment.activateForWindow()
                WindowRouter.shared.request("menubar-help")
                await pause(seconds: 0.8)
            case .showPopover:
                statusItemController.showPopover()
                await pause(seconds: 0.6)
            case .refreshAll:
                environment.refreshAll(throttle: false, trigger: "qa")
                await pause(seconds: 2.0)
            case .wait:
                await pause(seconds: 1.0)
            case .snapshot:
                writeSnapshot()
            case .quit:
                writeSnapshot()
                await pause(seconds: 0.2)
                NSApp.terminate(nil)
            }
        }
    }

    private func pause(seconds: Double) async {
        let nanos = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }

    private func writeSnapshot() {
        let visibility = statusItemController.currentVisibility()
        let report = LocalQAReport(
            generatedAt: ISO8601.fractional.string(from: Date()),
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            qaSteps: configuration.steps.map(\.rawValue),
            databasePath: DatabaseManager.defaultURL().path,
            developerLogPath: DeveloperLog.logFileURL.path,
            statusItemVisibility: String(describing: visibility),
            lastError: environment.lastError,
            windows: NSApp.windows.map {
                LocalQAWindowReport(
                    title: $0.title,
                    identifier: $0.identifier?.rawValue,
                    isVisible: $0.isVisible,
                    isKeyWindow: $0.isKeyWindow)
            },
            menuBar: environment.menuBarSnapshot.map {
                LocalQAMenuBarReport(
                    codexEvents: $0.codex.eventCount,
                    codexSessions: $0.codex.sessionCount,
                    codexTokens: $0.codex.totalTokens,
                    claudeEvents: $0.claude.eventCount,
                    claudeSessions: $0.claude.sessionCount,
                    claudeTokens: $0.claude.totalTokens)
            })

        do {
            try report.write(to: configuration.outputDirectory)
            DeveloperLog.eventRecord(
                "qa.snapshot.write",
                category: "app",
                trigger: "qa",
                result: "success",
                fields: [
                    "path": .string(configuration.outputDirectory
                        .appendingPathComponent("app-state.json").path)
                ])
        } catch {
            DeveloperLog.eventRecord(
                "qa.snapshot.write",
                level: .error,
                category: "app",
                trigger: "qa",
                result: "failure",
                message: error.localizedDescription)
        }
    }
}
