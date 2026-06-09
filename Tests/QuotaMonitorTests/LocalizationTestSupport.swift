import Foundation
@testable import QuotaMonitor

enum LocalizationTestSupport {
    private static let languageMutationLock = LocalizationLanguageMutationLock()

    static func withLanguage<T>(
        _ language: LocalizationStore.Language,
        _ body: () throws -> T
    ) rethrows -> T {
        try languageMutationLock.withLock {
            let previous = LocalizationStore.activeLanguage
            LocalizationStore.activeLanguageBytes.withLock { $0 = language }
            defer { LocalizationStore.activeLanguageBytes.withLock { $0 = previous } }
            return try body()
        }
    }
}

private final class LocalizationLanguageMutationLock: @unchecked Sendable {
    private let lock = NSLock()

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
