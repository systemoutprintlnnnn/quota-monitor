import Foundation

enum LocalQAEnvironment {
    static let homeKey = "QUOTAMONITOR_QA_HOME"
    static let defaultsSuiteKey = "QUOTAMONITOR_QA_DEFAULTS_SUITE"

    static func isActive(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["QUOTAMONITOR_QA_MODE"] == "1"
    }

    static func homeDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let raw = environment[homeKey], !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func applicationSupportDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let raw = environment[homeKey], !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        }
        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    static func userDefaults(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UserDefaults? {
        guard let suite = environment[defaultsSuiteKey], !suite.isEmpty else {
            return .standard
        }
        return UserDefaults(suiteName: suite)
    }
}
