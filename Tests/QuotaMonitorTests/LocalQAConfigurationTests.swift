import Testing
@testable import QuotaMonitor

@Suite("Local QA launch configuration")
struct LocalQAConfigurationTests {
    @Test("Disabled when QA mode flag is absent")
    func disabledWithoutModeFlag() {
        #expect(LocalQAConfiguration(environment: [:]) == nil)
    }

    @Test("Parses explicit QA steps and output directory")
    func parsesStepsAndOutputDirectory() throws {
        let config = try #require(LocalQAConfiguration(environment: [
            "QUOTAMONITOR_QA_MODE": "1",
            "QUOTAMONITOR_QA_OUTPUT_DIR": "/tmp/qm-qa",
            "QUOTAMONITOR_QA_STEPS": "open-dashboard,open-settings,snapshot,quit"
        ]))

        #expect(config.outputDirectory.path == "/tmp/qm-qa")
        #expect(config.steps == [
            .openDashboard,
            .openSettings,
            .snapshot,
            .quit
        ])
    }

    @Test("Uses deterministic defaults when only QA mode is enabled")
    func defaultsForModeOnly() throws {
        let config = try #require(LocalQAConfiguration(environment: [
            "QUOTAMONITOR_QA_MODE": "1"
        ]))

        #expect(config.steps == [
            .openDashboard,
            .openSettings,
            .openMenuBarHelp,
            .showPopover,
            .refreshAll,
            .snapshot
        ])
        #expect(config.outputDirectory.path.hasSuffix("/QuotaMonitorQA"))
    }

    @Test("Rejects unknown QA steps instead of silently skipping them")
    func rejectsUnknownStep() {
        #expect(LocalQAConfiguration(environment: [
            "QUOTAMONITOR_QA_MODE": "1",
            "QUOTAMONITOR_QA_STEPS": "snapshot,typo"
        ]) == nil)
    }
}
