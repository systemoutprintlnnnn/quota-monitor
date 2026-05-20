import Foundation

enum DeveloperLogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

actor DeveloperFileLogger {
    private let fileURL: URL
    private let isEnabled: @Sendable () -> Bool
    private let clock: @Sendable () -> Date

    init(fileURL: URL = DeveloperFileLogger.defaultLogURL(),
         isEnabled: @escaping @Sendable () -> Bool = {
             SettingsStore.developerModeEnabledNonisolated
         },
         clock: @escaping @Sendable () -> Date = Date.init) {
        self.fileURL = fileURL
        self.isEnabled = isEnabled
        self.clock = clock
    }

    nonisolated static func defaultLogDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("QuotaMonitor", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    nonisolated static func defaultLogURL() -> URL {
        defaultLogDirectory()
            .appendingPathComponent("quotamonitor-dev.log", isDirectory: false)
    }

    @discardableResult
    func record(level: DeveloperLogLevel,
                category: String,
                message: String,
                force: Bool = false) -> Bool {
        guard force || isEnabled() else { return false }

        let line = Self.formatLine(
            date: clock(),
            level: level,
            category: category,
            message: message)
        guard let data = (line + "\n").data(using: .utf8) else { return false }

        do {
            let parent = fileURL.deletingLastPathComponent()
            let fm = FileManager.default
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: fileURL.path) {
                fm.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    func deleteLogFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private nonisolated static func formatLine(date: Date,
                                               level: DeveloperLogLevel,
                                               category: String,
                                               message: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: date)
        let cleanCategory = sanitize(category)
        let cleanMessage = sanitize(message)
        return "\(timestamp) \(level.rawValue) [\(cleanCategory)] \(cleanMessage)"
    }

    private nonisolated static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

enum DeveloperLog {
    private static let logger = DeveloperFileLogger()

    nonisolated static var logFileURL: URL {
        DeveloperFileLogger.defaultLogURL()
    }

    nonisolated static func debug(_ message: @autoclosure () -> String,
                                  category: String) {
        record(level: .debug, category: category, message: message)
    }

    nonisolated static func info(_ message: @autoclosure () -> String,
                                 category: String) {
        record(level: .info, category: category, message: message)
    }

    nonisolated static func warning(_ message: @autoclosure () -> String,
                                    category: String) {
        record(level: .warning, category: category, message: message)
    }

    nonisolated static func error(_ message: @autoclosure () -> String,
                                  category: String) {
        record(level: .error, category: category, message: message)
    }

    nonisolated static func modeChanged(enabled: Bool) {
        Task.detached(priority: .utility) {
            if enabled {
                await logger.record(
                    level: .info,
                    category: "settings",
                    message: "developer mode enabled",
                    force: true)
            } else {
                await logger.deleteLogFile()
            }
        }
    }

    private nonisolated static func record(
        level: DeveloperLogLevel,
        category: String,
        message: () -> String
    ) {
        guard SettingsStore.developerModeEnabledNonisolated else { return }
        let resolved = message()
        Task.detached(priority: .utility) {
            await logger.record(level: level, category: category, message: resolved)
        }
    }
}
