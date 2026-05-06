import Foundation
import OSLog

// Single source for OSLog categories. Use `Log.<area>.info("...")` etc.
//
// Inspect from Console.app or:
//   log stream --predicate 'subsystem == "dev.tjzhou.CodexMonitor"' --level info

enum Log {
    static let subsystem = "dev.tjzhou.CodexMonitor"

    static let appServer  = Logger(subsystem: subsystem, category: "appserver")
    static let importer   = Logger(subsystem: subsystem, category: "importer")
    static let poller     = Logger(subsystem: subsystem, category: "poller")
    static let pricing    = Logger(subsystem: subsystem, category: "pricing")
    static let ui         = Logger(subsystem: subsystem, category: "ui")
}
