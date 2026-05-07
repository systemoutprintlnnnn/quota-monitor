import Foundation
import Testing
@testable import QuotaMonitor

/// Coverage for `AppServerClient.salvageBodyFromErrorMessage` — the
/// brace-balance scanner that pulls the embedded JSON body out of the
/// `codex` CLI's error.message string.
///
/// Why this matters: when an account's `plan_type` is `"prolite"`, the
/// CLI's deserializer rejects the response with an error whose `message`
/// field still contains the intact body after a `body=` marker. Without
/// this salvage, the menu bar would show "no quota data" for an entire
/// class of paying users.
///
/// Pre-2026-04-30 this had zero tests despite being load-bearing for the
/// `prolite` salvage path.
@Suite("salvageBodyFromErrorMessage")
struct SalvageBodyFromErrorMessageTests {

    @Test("extracts a simple flat body")
    func flatBody() throws {
        let msg = #"deserialize error, body={"plan_type":"prolite","rate_limits":{"primary":{"used_percent":42.0}}}"#
        let data = try #require(AppServerClient.salvageBodyFromErrorMessage(msg))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["plan_type"] as? String == "prolite")
    }

    @Test("returns nil when no body= marker is present")
    func noMarker() {
        let msg = "completely unrelated error message with no marker"
        #expect(AppServerClient.salvageBodyFromErrorMessage(msg) == nil)
    }

    @Test("returns nil when body= is present but no opening brace follows")
    func markerButNoBrace() {
        let msg = "deserialize error, body=garbage with no json at all"
        #expect(AppServerClient.salvageBodyFromErrorMessage(msg) == nil)
    }

    @Test("nested braces are tracked with brace-balance, not the first '}' wins")
    func nestedBraces() throws {
        // The naive "first-closing-brace wins" approach would truncate after
        // `"primary": {…}`. Brace-balance must walk the whole structure.
        let inner = #"{"primary":{"used_percent":12.5,"resets_at":"2026-04-30T00:00:00Z"},"secondary":{"used_percent":99.9}}"#
        let msg = "deserialize error caused by foo, body=\(inner) trailing junk"
        let data = try #require(AppServerClient.salvageBodyFromErrorMessage(msg))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let secondary = try #require(json["secondary"] as? [String: Any])
        #expect((secondary["used_percent"] as? Double) == 99.9,
                "must capture all the way through the outer closing brace, not stop at the first inner '}'")
    }

    @Test("braces inside JSON strings do NOT affect the brace counter")
    func bracesInsideStrings() throws {
        // The salvage walker enters string mode on `"` and ignores braces
        // until the matching close-quote. If it misbehaves the early `}` in
        // the literal would terminate the parse early.
        let body = #"{"note":"value with } inside","ok":true}"#
        let msg  = "rejected, body=\(body)\n…stack trace…"
        let data = try #require(AppServerClient.salvageBodyFromErrorMessage(msg))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["note"] as? String == "value with } inside")
        #expect(json["ok"] as? Bool == true)
    }

    @Test("escaped quotes inside strings don't confuse string-mode tracking")
    func escapedQuotes() throws {
        // \" inside a JSON string must not flip the in-string flag off; if
        // the walker treats the escape as a real close-quote it'll start
        // counting braces inside what is logically still a string.
        let body = #"{"q":"he said \"}}\" then left","done":true}"#
        let msg  = "body=\(body) extra"
        let data = try #require(AppServerClient.salvageBodyFromErrorMessage(msg))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["done"] as? Bool == true)
    }

    @Test("multi-line body is captured across newlines")
    func multiLineBody() throws {
        // CLI sometimes pretty-prints the embedded body. Walker must not
        // stop at the first newline.
        let body = """
            {
              "plan_type": "prolite",
              "rate_limits": {
                "primary": { "used_percent": 7.0 }
              }
            }
            """
        let msg = "thread 'main' panicked, body=\(body)\n   at src/foo.rs:123"
        let data = try #require(AppServerClient.salvageBodyFromErrorMessage(msg))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["plan_type"] as? String == "prolite")
    }
}
