import Foundation
import Testing
@testable import QuotaMonitor

@Suite("Local QA isolation")
struct LocalQAIsolationTests {
    @Test("QA home redirects application support into the harness profile")
    func qaHomeRedirectsApplicationSupport() throws {
        let dir = LocalQAEnvironment.applicationSupportDirectory(environment: [
            "QUOTAMONITOR_QA_HOME": "/tmp/qm-qa-home"
        ])

        #expect(dir.path == "/tmp/qm-qa-home/Library/Application Support")
    }

    @Test("QA defaults suite uses a separate preferences domain")
    func qaDefaultsSuiteUsesSeparateDomain() throws {
        let suiteName = "dev.tjzhou.QuotaMonitor.QATest.\(UUID().uuidString)"
        let defaults = try #require(LocalQAEnvironment.userDefaults(environment: [
            "QUOTAMONITOR_QA_DEFAULTS_SUITE": suiteName
        ]))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("qa", forKey: "marker")

        #expect(UserDefaults.standard.string(forKey: "marker") == nil)
        #expect(UserDefaults(suiteName: suiteName)?.string(forKey: "marker") == "qa")
    }
}
