import Foundation
import GRDB
import Testing
@testable import QuotaMonitor

/// `ClaudeRolloutParser` got an incremental `fromOffset` parameter in v5
/// so menu-bar scans don't have to re-parse multi-MB rollouts every 5
/// minutes. These tests pin the byte-offset bookkeeping that makes that
/// safe — specifically:
///
///   1. A full read returns `endOffset == file.size` only when the file
///      ends with a newline; a mid-write tail leaves `endOffset` BEFORE
///      the un-terminated last line (so the next scan re-reads it once
///      the writer has finished).
///   2. A second pass starting at the prior `endOffset` parses ONLY the
///      newly appended events, not the whole file.
///   3. The same `(sessionId, message.id)` appearing in both passes
///      surfaces as a `messageId` we can dedup on; the SQL layer's
///      partial unique index handles cross-pass collisions.
@Suite("ClaudeRolloutParser incremental")
struct ClaudeRolloutParserIncrementalTests {

    private func writeRollout(_ jsonl: String) throws -> URL {
        let dir = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent("qm-claude-incr-\(UUID().uuidString)",
                                 isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).jsonl")
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func append(_ url: URL, _ text: String) throws {
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
    }

    private func assistantLine(
        sid: String, msgId: String,
        ts: String = "2026-05-13T10:00:00.000Z",
        model: String = "claude-opus-4-7",
        input: Int = 100, output: Int = 50
    ) -> String {
        """
        {"type":"assistant","sessionId":"\(sid)","timestamp":"\(ts)","message":\
        {"id":"\(msgId)","model":"\(model)","usage":\
        {"input_tokens":\(input),"cache_creation_input_tokens":0,\
        "cache_read_input_tokens":0,"output_tokens":\(output)}}}
        """
    }

    private func makeDatabase() throws -> DatabaseManager {
        let dir = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent("qm-claude-import-\(UUID().uuidString)",
                                 isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return try DatabaseManager(
            url: dir.appendingPathComponent("quotamonitor.sqlite"))
    }

    // MARK: - 1. mid-write tail leaves endOffset behind the partial line

    @Test("mid-write tail: endOffset stops at last complete newline")
    func midWriteTail() throws {
        let url = try writeRollout(
            assistantLine(sid: "S1", msgId: "m1") + "\n"
            + assistantLine(sid: "S1", msgId: "m2") + "\n"
            // No trailing newline — simulates mid-write.
            + #"{"type":"assistant","sessionId":"S1","timestamp"#
        )
        let fileSize = try FileManager.default.attributesOfItem(
            atPath: url.path)[.size] as! Int64
        let out = try ClaudeRolloutParser.parse(fileURL: url)
        #expect(out.session != nil)
        #expect(out.session!.events.count == 2)
        #expect(out.endOffset < fileSize,
                "endOffset must skip the un-terminated tail")
    }

    // MARK: - 2. resume from prior offset only sees the appended slice

    @Test("incremental: second pass parses only the appended events")
    func incrementalAppend() throws {
        let url = try writeRollout(
            assistantLine(sid: "S1", msgId: "m1") + "\n"
            + assistantLine(sid: "S1", msgId: "m2") + "\n"
        )
        let pass1 = try ClaudeRolloutParser.parse(fileURL: url, fromOffset: 0)
        #expect(pass1.session?.events.count == 2)

        try append(url,
            assistantLine(sid: "S1", msgId: "m3") + "\n"
            + assistantLine(sid: "S1", msgId: "m4") + "\n")

        let pass2 = try ClaudeRolloutParser.parse(
            fileURL: url, fromOffset: pass1.endOffset)
        // Only the two NEW events — incremental mustn't re-emit m1/m2.
        #expect(pass2.session?.events.count == 2)
        #expect(pass2.session?.events.map { $0.messageId } == ["m3", "m4"])
    }

    // MARK: - 3. message ids surface so SQL dedup can do cross-pass dedup

    @Test("messageId is propagated for SQL-side dedup")
    func messageIdPropagation() throws {
        let url = try writeRollout(
            assistantLine(sid: "S1", msgId: "abc-123") + "\n")
        let out = try ClaudeRolloutParser.parse(fileURL: url)
        #expect(out.session?.events.first?.messageId == "abc-123")
    }

    @Test("cache creation duration split is parsed from usage.cache_creation")
    func cacheCreationDurationSplit() throws {
        let url = try writeRollout(
            """
            {"type":"assistant","sessionId":"S1","timestamp":"2026-05-13T10:00:00.000Z","message":\
            {"id":"cache-split","model":"claude-opus-4-7","usage":\
            {"input_tokens":1,"cache_creation_input_tokens":30,\
            "cache_read_input_tokens":4,"output_tokens":5,\
            "cache_creation":{"ephemeral_1h_input_tokens":20,"ephemeral_5m_input_tokens":10}}}}
            """ + "\n")
        let out = try ClaudeRolloutParser.parse(fileURL: url)
        let event = try #require(out.session?.events.first)

        #expect(event.cacheCreationTokens == 30)
        #expect(event.cacheCreation1hTokens == 20)
        #expect(event.cacheCreation5mTokens == 10)
    }

    // MARK: - 4. resuming past end-of-file is a clean no-op

    @Test("offset >= filesize parses nothing and returns the same offset")
    func offsetPastEnd() throws {
        let url = try writeRollout(assistantLine(sid: "S1", msgId: "m1") + "\n")
        let size = try FileManager.default.attributesOfItem(
            atPath: url.path)[.size] as! Int64
        let out = try ClaudeRolloutParser.parse(fileURL: url, fromOffset: size)
        #expect(out.session == nil)
        #expect(out.endOffset == size)
    }

    @Test("Claude import preserves existing events when a shared-session subagent file is added")
    func sharedSessionSubagentFileDoesNotReplaceMainFileEvents() async throws {
        let db = try makeDatabase()
        let root = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent("qm-claude-root-\(UUID().uuidString)",
                                 isDirectory: true)
        let project = root.appendingPathComponent("-repo", isDirectory: true)
        try FileManager.default.createDirectory(
            at: project, withIntermediateDirectories: true)

        let sid = "shared-session"
        let main = project.appendingPathComponent("\(sid).jsonl")
        try (assistantLine(
            sid: sid, msgId: "main-1",
            model: "claude-opus-4-8",
            input: 10, output: 1
        ) + "\n").write(to: main, atomically: true, encoding: .utf8)

        let engine = ClaudeImportEngine(database: db, claudeRoots: [root])
        _ = try await engine.performScan()

        let subagentDir = project
            .appendingPathComponent(sid, isDirectory: true)
            .appendingPathComponent("subagents/workflows/wf-1",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: subagentDir, withIntermediateDirectories: true)
        let subagent = subagentDir.appendingPathComponent("agent-a.jsonl")
        try (assistantLine(
            sid: sid, msgId: "agent-1",
            model: "claude-haiku-4-5-20251001",
            input: 20, output: 2
        ) + "\n").write(to: subagent, atomically: true, encoding: .utf8)

        _ = try await engine.performScan()

        let rows = try await db.pool.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT model_id, COUNT(*) AS events
                FROM usage_events
                WHERE provider = 'claude'
                GROUP BY model_id
                ORDER BY model_id
                """)
        }
        let counts = Dictionary(uniqueKeysWithValues: rows.map {
            ($0["model_id"] as String, $0["events"] as Int)
        })
        #expect(counts == [
            "claude-haiku-4-5-20251001": 1,
            "claude-opus-4-8": 1,
        ])
    }
}
