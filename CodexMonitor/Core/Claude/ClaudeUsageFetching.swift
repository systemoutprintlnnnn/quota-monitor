import Foundation

/// Tiny seam over `ClaudeUsageClient` so `ClaudeUsagePoller` can be
/// exercised with a mock fetcher (success / each FetchError variant /
/// timing assertions). The real client conforms naturally — its `fetch`
/// has the same signature.
protocol ClaudeUsageFetching: Sendable, AnyObject {
    func fetch() async throws -> ClaudeUsageSnapshot
}
