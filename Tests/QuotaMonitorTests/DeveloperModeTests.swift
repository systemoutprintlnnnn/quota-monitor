import Foundation
import Testing
@testable import QuotaMonitor

@MainActor
@Suite("Developer mode")
struct DeveloperModeTests {

    private static func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "test.\(name).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private static func tempLogURL(_ name: String = #function) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaMonitorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(name).log", isDirectory: false)
    }

    @Test
    func defaultsToFalseOnFreshInstall() {
        let d = Self.freshDefaults()
        let store = SettingsStore(defaults: d)
        #expect(store.developerModeEnabled == false)
    }

    @Test
    func mutatingWritesToUserDefaults() {
        let d = Self.freshDefaults()
        let store = SettingsStore(defaults: d)
        store.developerModeEnabled = true
        #expect(d.bool(forKey: "settings.developerModeEnabled") == true)
    }

    @Test
    func storedTrueIsReadOnInit() {
        let d = Self.freshDefaults()
        d.set(true, forKey: "settings.developerModeEnabled")
        let store = SettingsStore(defaults: d)
        #expect(store.developerModeEnabled == true)
    }

    @Test
    func snapshotCarriesDeveloperMode() {
        let d = Self.freshDefaults()
        d.set(true, forKey: "settings.developerModeEnabled")
        let snap = SettingsStore.snapshot(defaults: d)
        #expect(snap.developerModeEnabled == true)
    }

    @Test
    func fileLoggerDoesNotCreateFileWhenDisabled() async throws {
        let url = try Self.tempLogURL()
        let logger = DeveloperFileLogger(fileURL: url, isEnabled: { false })

        let wrote = await logger.record(
            level: .info,
            category: "test",
            message: "should not write")

        #expect(wrote == false)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test
    func fileLoggerCreatesParentAndAppendsLineWhenEnabled() async throws {
        let url = try Self.tempLogURL()
            .deletingLastPathComponent()
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("developer.log", isDirectory: false)
        let logger = DeveloperFileLogger(fileURL: url, isEnabled: { true })

        let wrote = await logger.record(
            level: .info,
            category: "test",
            message: "hello world")

        #expect(wrote == true)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("INFO"))
        #expect(text.contains("[test]"))
        #expect(text.contains("hello world"))
        #expect(text.hasSuffix("\n"))
    }

    @Test
    func fileLoggerEscapesMultilineMessages() async throws {
        let url = try Self.tempLogURL()
        let logger = DeveloperFileLogger(fileURL: url, isEnabled: { true })

        _ = await logger.record(
            level: .error,
            category: "scan",
            message: "line one\nline two")

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("ERROR"))
        #expect(text.contains("line one\\nline two"))
    }

    @Test
    func fileLoggerDeletesExistingLogWhenDeveloperModeTurnsOff() async throws {
        let url = try Self.tempLogURL()
        let logger = DeveloperFileLogger(fileURL: url, isEnabled: { true })

        _ = await logger.record(level: .info, category: "test", message: "old log")
        #expect(FileManager.default.fileExists(atPath: url.path))

        await logger.deleteLogFile()

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }
}
