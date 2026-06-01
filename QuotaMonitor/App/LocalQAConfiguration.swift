import Foundation

/// Launch-time configuration for the local QA harness.
///
/// The harness is intentionally opt-in through environment variables so
/// release builds and normal user launches never run automation code.
struct LocalQAConfiguration: Equatable {
    let outputDirectory: URL
    let steps: [LocalQAStep]

    init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard environment["QUOTAMONITOR_QA_MODE"] == "1" else { return nil }

        if let rawSteps = environment["QUOTAMONITOR_QA_STEPS"],
           !rawSteps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var parsed: [LocalQAStep] = []
            for token in rawSteps.split(separator: ",") {
                let name = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let step = LocalQAStep(rawValue: name) else { return nil }
                parsed.append(step)
            }
            self.steps = parsed
        } else {
            self.steps = [
                .openDashboard,
                .openSettings,
                .openMenuBarHelp,
                .showPopover,
                .refreshAll,
                .snapshot
            ]
        }

        let output = environment["QUOTAMONITOR_QA_OUTPUT_DIR"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("QuotaMonitorQA", isDirectory: true)
        self.outputDirectory = output
    }
}

enum LocalQAStep: String, Equatable {
    case openDashboard = "open-dashboard"
    case openSettings = "open-settings"
    case openMenuBarHelp = "open-menubar-help"
    case showPopover = "show-popover"
    case refreshAll = "refresh-all"
    case wait
    case snapshot
    case quit
}
