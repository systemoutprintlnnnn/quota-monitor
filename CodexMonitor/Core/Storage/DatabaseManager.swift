import Foundation
import GRDB

// Thin wrapper around a GRDB DatabasePool. We don't add an actor on top because
// GRDB already serializes writes and allows concurrent reads via `read`/`write`.

final class DatabaseManager: Sendable {
    let pool: DatabasePool

    init(url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA busy_timeout = 10000")
        }
        self.pool = try DatabasePool(path: url.path, configuration: config)

        var migrator = DatabaseMigrator()
        Migrations.register(in: &migrator)
        try migrator.migrate(pool)
    }

    /// Default DB location: ~/Library/Application Support/CodexMonitor/codexmonitor.sqlite
    static func defaultURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("CodexMonitor", isDirectory: true)
            .appendingPathComponent("codexmonitor.sqlite", isDirectory: false)
    }
}
