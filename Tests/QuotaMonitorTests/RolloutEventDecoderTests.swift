import Foundation
import Testing
@testable import QuotaMonitor

@Suite("RolloutEvent decoder")
struct RolloutEventDecoderTests {

    @Test("irrelevant top-level events do not decode payload")
    func irrelevantTopLevelPayloadIsSkipped() throws {
        let line = Data(#"""
        {"timestamp":"2026-05-20T00:00:00.000Z","type":"response_item","payload":{"text":"ignored","bad_number":1e999}}
        """#.utf8)

        let event = try #require(RolloutEvent.decode(line: line))
        guard case .other(let type, let timestamp) = event else {
            Issue.record("expected .other, got \(event)")
            return
        }
        #expect(type == "response_item")
        #expect(timestamp == "2026-05-20T00:00:00.000Z")
    }

    @Test("non-token event_msg payloads do not decode beyond the inner type")
    func nonTokenEventPayloadIsSkipped() throws {
        let line = Data(#"""
        {"timestamp":"2026-05-20T00:00:01.000Z","type":"event_msg","payload":{"type":"task_started","bad_number":1e999}}
        """#.utf8)

        let event = try #require(RolloutEvent.decode(line: line))
        guard case .other(let type, let timestamp) = event else {
            Issue.record("expected .other, got \(event)")
            return
        }
        #expect(type == "event_msg")
        #expect(timestamp == "2026-05-20T00:00:01.000Z")
    }
}
