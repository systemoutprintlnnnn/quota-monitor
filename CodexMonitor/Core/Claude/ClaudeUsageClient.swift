import Foundation

/// Fetches live quota usage from Anthropic's OAuth-protected
/// `/api/oauth/usage` endpoint. The endpoint is undocumented but powers
/// the official `claude` CLI's quota meter and is the only source of
/// truth for Pro / Max plan usage (header-based `anthropic-ratelimit-*`
/// fields require routing every API call through us, which we don't).
///
/// Credential lookup order (matches CodexBar):
///   1. `~/.claude/.credentials.json` (file written by Claude Code CLI on
///      every login). No keychain prompt — strongly preferred.
///   2. macOS Keychain `Claude Code-credentials` service. May prompt the
///      user the first time (or every time, depending on
///      `SettingsStore.keychainPolicy`). Skipped entirely when policy is
///      `.never`.
///
/// Token requirement: scope must include `user:profile`. CLI-only tokens
/// scoped to `user:inference` get a 403 from this endpoint — we surface
/// that as `.insufficientScope` so the UI can tell the user to re-login.
actor ClaudeUsageClient: ClaudeUsageFetching {

    enum FetchError: Error, CustomStringConvertible {
        case noCredentials
        case insufficientScope
        case unauthorized
        /// 429 Too Many Requests. `retryAfter` is the server-suggested
        /// cool-off in seconds (parsed from `Retry-After` header), or nil
        /// if the header was absent / unparseable.
        case rateLimited(retryAfter: TimeInterval?)
        case http(Int, String)
        case malformed(String)
        case transport(any Error)

        var description: String {
            switch self {
            case .noCredentials:
                return "No Claude Code credentials found (run `claude login`)"
            case .insufficientScope:
                return "Claude token lacks the `user:profile` scope — re-run `claude login`"
            case .unauthorized:
                return "Claude token rejected (expired or revoked)"
            case .rateLimited(let retry):
                if let retry {
                    return "Anthropic /usage rate-limited (HTTP 429); retry in ~\(Int(retry))s"
                }
                return "Anthropic /usage rate-limited (HTTP 429)"
            case .http(let code, let body):
                return "Anthropic /usage HTTP \(code): \(body.prefix(120))"
            case .malformed(let s):
                return "malformed /usage response: \(s)"
            case .transport(let e):
                return "Anthropic /usage transport error: \(e)"
            }
        }
    }

    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// In-process token cache. Set on the first successful keychain or
    /// file read; reused for the rest of the process lifetime so we don't
    /// reopen the Keychain ACL prompt every 5-minute poll. Cleared only
    /// when the server reports the token is bad (`unauthorized`), at
    /// which point we re-read on the next poll.
    ///
    /// Caching is safe because (a) the access token doesn't change
    /// mid-session — Claude Code CLI rotates it, and we re-read from disk
    /// every poll anyway; (b) on `unauthorized` we explicitly invalidate.
    private var cachedToken: String?
    /// Set to true when the user clicks "Deny" / cancels the prompt OR
    /// the keychain query returns auth-class errors. Stops us from asking
    /// again in this process; combined with `.never` policy persistence
    /// below, also stops asking on next launch.
    private var keychainBlocked = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// One-shot fetch. Caller decides retry / scheduling.
    func fetch() async throws -> ClaudeUsageSnapshot {
        guard let token = try await loadAccessToken() else {
            throw FetchError.noCredentials
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Required header per Anthropic's beta gating. Matches CodexBar.
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("CodexMonitor/0.1", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw FetchError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FetchError.malformed("non-HTTP response")
        }

        switch http.statusCode {
        case 200:
            return try Self.decode(data: data, capturedAt: Date())
        case 401:
            // Server says the token is bad — drop the cache so the next
            // poll re-reads (in case the user just re-ran `claude login`).
            cachedToken = nil
            throw FetchError.unauthorized
        case 403:
            // Anthropic returns 403 when token's scope doesn't include
            // `user:profile`. Distinguish from generic auth so we can
            // tell the user *why*.
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.lowercased().contains("scope") {
                throw FetchError.insufficientScope
            }
            throw FetchError.http(403, body)
        case 429:
            // Server-side rate limit. Honour `Retry-After` if present so
            // the poller can back off (default 30 min in the poller's
            // currentInterval). Otherwise the 5-min poll cadence will
            // self-amplify and keep getting 429'd.
            let retry = (http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init))
            throw FetchError.rateLimited(retryAfter: retry)
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FetchError.http(http.statusCode, body)
        }
    }

    // MARK: - Decoding

    /// Parse the `/usage` response. The shape we observe:
    /// ```
    /// { "rate_limit_tier": "max5x",
    ///   "five_hour":  {"utilization": 60.0, "resets_at": "2026-..."},
    ///   "seven_day":  {"utilization": 12.0, "resets_at": "..."},
    ///   "seven_day_opus": {...}, "seven_day_sonnet": {...}
    /// }
    /// ```
    /// All keys are optional — Free plans in particular omit most.
    /// `extra_usage` (pay-as-you-go overflow) is intentionally NOT
    /// decoded: the product team decided we don't surface dollar-billed
    /// overflow in CodexMonitor. If Anthropic ever wires it back into
    /// Claude Code's pricing UX and we want it back, the field comes
    /// through as a JSON object so adding a `Wire.extra_usage` line
    /// later is trivial.
    static func decode(data: Data, capturedAt: Date) throws -> ClaudeUsageSnapshot {
        struct Wire: Decodable {
            let rate_limit_tier: String?
            let five_hour: WindowWire?
            let seven_day: WindowWire?
            let seven_day_opus: WindowWire?
            let seven_day_sonnet: WindowWire?
        }
        struct WindowWire: Decodable {
            let utilization: Double?
            let used_percent: Double?
            let resets_at: String?
            let reset_at: String?
        }

        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw FetchError.malformed("\(error)")
        }

        let isoMillis = ISO8601DateFormatter()
        isoMillis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        func parseDate(_ s: String?) -> Date? {
            guard let s, !s.isEmpty else { return nil }
            return isoMillis.date(from: s) ?? isoPlain.date(from: s)
        }

        // Anthropic's current `/api/oauth/usage` returns `utilization`
        // already in percent (e.g. 60.0 means 60%). Older CodexBar
        // captures showed `used_percent` as 0..100 too. Some very early
        // beta captures used 0..1 ratios — we keep that compat by
        // heuristic: a value <= 1.5 is treated as a 0..1 ratio (so 0.42
        // → 42%), anything larger is already a percent. This matches
        // what every real response on the dev account returns today.
        // Tests in `ClaudeUsageDecoderTests` lock this with real fixtures.
        func mkWindow(_ w: WindowWire?, duration: TimeInterval) -> ClaudeUsageSnapshot.Window? {
            guard let w else { return nil }
            let resetStr = w.resets_at ?? w.reset_at
            guard let reset = parseDate(resetStr) else { return nil }
            let raw: Double
            if let u = w.utilization {
                raw = u
            } else if let p = w.used_percent {
                raw = p
            } else {
                return nil
            }
            let pct = raw <= 1.5 ? raw * 100 : raw
            return .init(usedPercent: pct, resetAt: reset, windowDuration: duration)
        }

        return .init(
            capturedAt: capturedAt,
            tier: wire.rate_limit_tier,
            fiveHour:    mkWindow(wire.five_hour,        duration: 5 * 3600),
            sevenDay:    mkWindow(wire.seven_day,        duration: 7 * 86400),
            sevenDayOpus:   mkWindow(wire.seven_day_opus,   duration: 7 * 86400),
            sevenDaySonnet: mkWindow(wire.seven_day_sonnet, duration: 7 * 86400))
    }

    // MARK: - Credential loading

    /// File-first, keychain-fallback. Returns nil only when neither source
    /// yielded a token (caller turns it into `.noCredentials`).
    ///
    /// **Prompt-suppression policy** (the whole reason this method is on
    /// the actor instead of a static helper):
    ///   1. If `cachedToken` is set, return it. Skips the Keychain ACL
    ///      check entirely — that's what was triggering the password
    ///      prompt every poll. ad-hoc-signed builds re-derive a new
    ///      cdhash on every `swift build`, so the user's "Always Allow"
    ///      click never sticks across rebuilds.
    ///   2. Always try the on-disk credentials file first (no prompt).
    ///   3. Try Keychain only if (a) policy permits and (b) we haven't
    ///      already been blocked once this process. A single denial /
    ///      timeout flips `keychainBlocked` to true so the next 287 polls
    ///      go quiet.
    ///   4. We deliberately don't auto-persist `.never` on a single
    ///      denial — the user might have been busy / mistyped. They get
    ///      no more prompts this run; if they want permanent silence,
    ///      Settings → Live quotas → "Never read Keychain".
    private func loadAccessToken() async throws -> String? {
        if let cached = cachedToken {
            return cached
        }
        if let token = try Self.readCredentialsFile() {
            cachedToken = token
            return token
        }
        let policy = SettingsStore.snapshot().keychainPolicy
        guard policy != .never, !keychainBlocked else { return nil }

        let outcome = Self.readKeychainTokenOutcome()
        switch outcome {
        case .ok(let token, let raw):
            cachedToken = token
            // Mirror the credential to disk so the next process launch
            // can read it without prompting. No-op if a file already
            // exists (e.g. the CLI is the source of truth).
            Self.mirrorTokenToFile(rawKeychainData: raw, fallbackToken: token)
            return token
        case .denied, .interactionNotAllowed, .notFound:
            // All three mean "don't keep asking". `notFound` in particular
            // would otherwise re-query the keychain every 5 min for an
            // item that doesn't exist — pointless I/O and on some
            // systems still pops the unlock prompt.
            keychainBlocked = true
            return nil
        case .otherError:
            // Unknown status — try once more on the next poll.
            return nil
        }
    }

    /// Read `~/.claude/.credentials.json`. The Claude Code CLI **used to**
    /// rewrite this on every login + token refresh, so it was the freshest
    /// source. Format observed:
    /// ```
    /// { "claudeAiOauth": { "accessToken": "...", "refreshToken": "...",
    ///                      "expiresAt": 1735000000000, "scopes": [...] } }
    /// ```
    /// **Drift caught 2026-05-06:** newer CLI versions (≥ 2.1.x) only
    /// rotate the access token inside the Keychain, leaving the on-disk
    /// file frozen at its last `claude login` value. If we accept the file
    /// blindly we get stuck on an expired token forever — file always
    /// "wins" over the up-to-date Keychain copy. So: parse `expiresAt`
    /// (with a 60-second clock-skew margin) and treat anything past its
    /// expiry as "no usable file token", so `loadAccessToken` falls
    /// through to the Keychain.
    /// We still don't refresh tokens ourselves — that's the CLI's job.
    static func readCredentialsFile() throws -> String? {
        let override = SettingsStore.snapshot().claudeHomeOverride
        let home = !override.isEmpty
            ? override
            : (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        let path = (home as NSString).appendingPathComponent(".credentials.json")
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        struct Wrapper: Decodable {
            struct Inner: Decodable {
                let accessToken: String?
                /// Unix epoch in **milliseconds** (CLI-side convention).
                /// Optional because very old CLI captures didn't include it.
                let expiresAt: Double?
            }
            let claudeAiOauth: Inner?
        }
        let inner = try JSONDecoder().decode(Wrapper.self, from: data).claudeAiOauth
        guard let token = inner?.accessToken else { return nil }
        if let expMs = inner?.expiresAt {
            // 60s margin so we don't hand the network a token that will
            // expire mid-request. expMs is in ms since epoch (CLI convention).
            let expSeconds = expMs / 1000.0 - 60
            if Date().timeIntervalSince1970 >= expSeconds {
                Log.poller.info("claude .credentials.json token expired (\(expMs, privacy: .public)ms), falling through to Keychain")
                return nil
            }
        }
        return token
    }

    /// Outcome of a keychain read. Distinguishing between "denied" and
    /// "no such item" lets the caller decide whether to escalate to
    /// auto-disabling the policy.
    ///
    /// The `.ok` payload carries both the parsed access token AND the
    /// original raw bytes that were stored in the Keychain. We need the
    /// raw bytes so we can mirror them verbatim to
    /// `~/.claude/.credentials.json` (see `mirrorTokenToFile`) — that
    /// file is the silent fallback that prevents the Keychain prompt
    /// from re-firing after every app restart.
    enum KeychainOutcome {
        case ok(token: String, raw: Data)
        case notFound
        case denied               // user clicked Deny, or item ACL refused us
        case interactionNotAllowed // we asked for non-interactive read and it'd need UI
        case otherError
    }

    /// Pull `Claude Code-credentials` (service name) generic password from
    /// the login keychain. Wraps `SecItemCopyMatching` and classifies the
    /// status code so the actor can react sensibly to denials.
    static func readKeychainTokenOutcome() -> KeychainOutcome {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .otherError }
            // Keychain may contain either the bare token or the same JSON
            // wrapper as the on-disk file. Try JSON first, fall back to raw.
            if let token = try? JSONDecoder()
                .decode([String: [String: String]].self, from: data)["claudeAiOauth"]?["accessToken"] {
                return .ok(token: token, raw: data)
            }
            if let s = String(data: data, encoding: .utf8) {
                return .ok(token: s.trimmingCharacters(in: .whitespacesAndNewlines), raw: data)
            }
            return .otherError
        case errSecItemNotFound:
            return .notFound
        case errSecUserCanceled, errSecAuthFailed:
            return .denied
        case errSecInteractionNotAllowed:
            return .interactionNotAllowed
        default:
            return .otherError
        }
    }

    /// Mirror a successful Keychain read into `~/.claude/.credentials.json`
    /// so future app launches can skip the Keychain prompt entirely.
    ///
    /// **Why this exists.** Keychain ACLs are tied to the cdhash of the
    /// requesting binary. CodexMonitor is ad-hoc signed, so every
    /// `swift build` produces a new cdhash and the user's "Always Allow"
    /// click never sticks across rebuilds — they get the password prompt
    /// on every launch. The file source has no such restriction (just
    /// POSIX perms), so a one-time mirror permanently silences the prompt.
    ///
    /// **Safety.**
    ///   - 0600 perms (owner read/write only) — same protection level as
    ///     the file the Claude Code CLI writes itself.
    ///   - Atomic write via tmp + rename so a crash mid-write can't leave
    ///     a half-written file.
    ///   - We refuse to overwrite a file whose token is **fresh** (the
    ///     CLI's own write that we want to read on next launch). A file
    ///     whose `expiresAt` is in the past is treated as stale — newer
    ///     CLI versions only rotate the access token in the Keychain and
    ///     leave the on-disk file frozen, so that's the *common* case
    ///     and the only practical way our process keeps working without
    ///     the keychain prompt firing every poll.
    ///   - If the Keychain blob isn't already a JSON wrapper, we wrap
    ///     the bare token in the minimal `claudeAiOauth.accessToken`
    ///     shape so the CLI / our own reader can parse it.
    ///
    /// Returns true if a file was written (for logging / tests).
    @discardableResult
    static func mirrorTokenToFile(rawKeychainData: Data, fallbackToken: String) -> Bool {
        let override = SettingsStore.snapshot().claudeHomeOverride
        let home = !override.isEmpty
            ? override
            : (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        let path = (home as NSString).appendingPathComponent(".credentials.json")
        let fm = FileManager.default

        // Don't clobber an existing file *unless* it's already past its
        // own expiresAt. The "newer CLI only updates Keychain" drift
        // means a stale file would otherwise lock us into a perma-401
        // loop on the next launch (file still wins over keychain in
        // `loadAccessToken`'s order).
        if fm.fileExists(atPath: path) {
            if !Self.fileTokenIsExpired(at: path) {
                return false
            }
        }

        // Ensure ~/.claude exists (it usually does, but be defensive on
        // fresh installs).
        if !fm.fileExists(atPath: home) {
            try? fm.createDirectory(atPath: home, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }

        // Decide what to write. If the Keychain blob already parses as
        // the canonical JSON wrapper, mirror it verbatim — preserves
        // refreshToken, expiresAt, scopes, etc. that the CLI may need
        // later. Otherwise build a minimal wrapper around the bare token.
        let payload: Data
        if (try? JSONSerialization.jsonObject(with: rawKeychainData)) != nil {
            payload = rawKeychainData
        } else {
            let wrapper: [String: Any] = [
                "claudeAiOauth": ["accessToken": fallbackToken]
            ]
            guard let encoded = try? JSONSerialization.data(
                withJSONObject: wrapper, options: [.prettyPrinted]) else {
                return false
            }
            payload = encoded
        }

        // Atomic write: temp file in same directory, then rename.
        let tmp = path + ".tmp"
        guard fm.createFile(atPath: tmp, contents: payload,
                            attributes: [.posixPermissions: 0o600]) else {
            return false
        }
        do {
            // `replaceItem` handles the rename atomically on APFS.
            _ = try fm.replaceItemAt(URL(fileURLWithPath: path),
                                     withItemAt: URL(fileURLWithPath: tmp))
            return true
        } catch {
            // Fall back to a plain rename. If even that fails, clean up
            // the tmp file so we don't leave litter.
            do {
                try fm.moveItem(atPath: tmp, toPath: path)
                return true
            } catch {
                try? fm.removeItem(atPath: tmp)
                return false
            }
        }
    }

    /// Returns true if the on-disk `~/.claude/.credentials.json` token
    /// has already expired (or is within 60s of expiring). Used to gate
    /// `mirrorTokenToFile`'s no-clobber rule — see that method's doc
    /// comment for the "newer CLI only updates Keychain" drift this
    /// guards against.
    private static func fileTokenIsExpired(at path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            // If we can't read it, treat as expired so the caller will
            // try to overwrite — the alternative is permanent breakage.
            return true
        }
        struct Wrapper: Decodable {
            struct Inner: Decodable { let expiresAt: Double? }
            let claudeAiOauth: Inner?
        }
        guard let expMs = (try? JSONDecoder().decode(Wrapper.self, from: data))?
                .claudeAiOauth?.expiresAt
        else {
            // No expiry → can't prove freshness. Be conservative: keep
            // the existing file (false). User can `claude login` to fix.
            return false
        }
        return Date().timeIntervalSince1970 >= (expMs / 1000.0 - 60)
    }

    /// Persist `keychainPolicy = .never` on the main actor. Currently
    /// only invoked by the "Disable now" button surfaced in the menu bar
    /// after we detect a denial — keeps the auto-flip out of the silent
    /// poll path while still giving the user a one-click escape hatch.
    static func persistKeychainDisabled() async {
        await MainActor.run {
            SettingsStore.shared.keychainPolicy = .never
        }
    }

}
