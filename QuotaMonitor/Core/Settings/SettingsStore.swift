import Foundation
import Observation

// Cross-feature settings backed by UserDefaults.
//
// Convention:
//   - Empty string means "not set" / use auto-discovery.
//   - Hot-reloadable settings (poll interval, threshold) are applied via
//     AppEnvironment.applySettings() right after the user edits them.
//   - Path-changing settings (codex binary, codex home, claude home) currently
//     take effect on next launch — we surface that in the UI so users aren't
//     surprised.

@Observable
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    var codexBinaryOverride: String {
        didSet { defaults.set(codexBinaryOverride, forKey: Keys.codexBinary) }
    }
    var codexHomeOverride: String {
        didSet { defaults.set(codexHomeOverride, forKey: Keys.codexHome) }
    }
    var claudeHomeOverride: String {
        didSet { defaults.set(claudeHomeOverride, forKey: Keys.claudeHome) }
    }
    var pollIntervalSeconds: Int {
        didSet { defaults.set(pollIntervalSeconds, forKey: Keys.pollInterval) }
    }
    var notifyThreshold: Double {
        didSet { defaults.set(notifyThreshold, forKey: Keys.notifyThreshold) }
    }
    /// Controls whether `ClaudeUsageClient` is allowed to read the
    /// `Claude Code-credentials` keychain entry. First read may prompt
    /// the user; subsequent reads are silent unless the user clicked
    /// "Deny" (which sticks for the app's bundle ID). The file source
    /// (`~/.claude/.credentials.json`) is always tried first, so most
    /// users won't notice this knob.
    var keychainPolicy: KeychainPolicy {
        didSet { defaults.set(keychainPolicy.rawValue, forKey: Keys.keychainPolicy) }
    }
    /// **OFF by default — security policy.** When ON, after a successful
    /// Keychain read of the Claude OAuth credentials we mirror the same
    /// JSON blob to `~/.claude/.credentials.json`. This stops the
    /// recurring "QuotaMonitor wants to use…" Keychain prompt that
    /// appears after every ad-hoc rebuild (the macOS ACL is bound to
    /// the binary's signature, which changes with each `./build.sh`).
    ///
    /// **Why opt-in.** Moving credentials from a more-protected store
    /// (Keychain, per-app ACL'd) to a less-protected one (a plain
    /// 0600 file readable by any process running as your user) is a
    /// security downgrade. We will not flip this for the user
    /// silently — they have to enable it in Settings → Advanced.
    /// Help text on the toggle spells out the trade-off.
    ///
    /// File written 0600 + atomic replace so we never expose the
    /// token mid-write or leave a half-written file behind.
    var mirrorClaudeKeychainToFile: Bool {
        didSet { defaults.set(mirrorClaudeKeychainToFile,
                              forKey: Keys.mirrorClaudeKeychainToFile) }
    }
    /// Which rolling window the menu bar uses for the headline
    /// `$X.XX · Yk tokens` line and the session-count chip. Default
    /// 7 days because most users want a "what did I do this week"
    /// signal — 30 days drowns out short-term spikes. The picker lives in
    /// Settings → General → Menu bar.
    var menuBarHeadlineWindow: HeadlineWindow {
        didSet { defaults.set(menuBarHeadlineWindow.rawValue,
                              forKey: Keys.menuBarHeadlineWindow) }
    }
    /// Which provider's quota fills the menu-bar icon (one row per
    /// window: 5h + 7d, "X% used"). Only one provider at a time —
    /// the menu-bar slot is too narrow to fit both, and the popover
    /// already shows everything in detail. Hidden when the chosen
    /// provider isn't currently tracked (`enabledProviders` doesn't
    /// contain it) or when no usage data is available yet — the
    /// label falls back to a static SF Symbol in those cases.
    ///
    /// Default: `.codex`. Snap behaviour: when the user disables the
    /// currently-selected provider, `setProviderEnabled` flips this
    /// to whatever's still enabled so we never persistently point at
    /// nothing.
    var menuBarIconProvider: MenuBarIconProvider {
        didSet { defaults.set(menuBarIconProvider.rawValue,
                              forKey: Keys.menuBarIconProvider) }
    }
    /// Which providers QuotaMonitor actively tracks. Persisted as a
    /// string array under `Keys.enabledProviders`. Disabling a provider
    /// stops its background poller, hides its menu-bar block, drops it
    /// from the Dashboard's Forecast / Composition / statline, and
    /// removes it from the toolbar provider filter.
    ///
    /// Constraint: must contain at least one entry. Mutating directly is
    /// allowed (set logic clamps to the previous value if the input is
    /// empty), but UI should prefer `setProviderEnabled(_:enabled:)`
    /// which returns false when the constraint blocked the change so
    /// the caller can keep the toggle in its current visual state.
    private(set) var enabledProviders: Set<String> {
        didSet {
            defaults.set(Array(enabledProviders).sorted(),
                         forKey: Keys.enabledProviders)
        }
    }
    /// Set once the user has completed the provider step of onboarding.
    /// Existing-installation upgrades infer `true` in `init` so they
    /// never see the new step.
    private(set) var hasCompletedProviderOnboarding: Bool {
        didSet { defaults.set(hasCompletedProviderOnboarding,
                              forKey: Keys.providerOnboardingDone) }
    }
    var needsProviderOnboarding: Bool { !hasCompletedProviderOnboarding }

    enum KeychainPolicy: String, CaseIterable, Sendable, Identifiable {
        /// Try keychain only when the on-disk credentials file is missing
        /// or stale. Default — covers Claude CLI users without prompts.
        case fallback
        /// Skip the keychain entirely. Use this if the user has rejected
        /// the prompt and doesn't want to be asked again.
        case never
        var id: String { rawValue }
        var label: String {
            switch self {
            case .fallback: return L10n.keychainPolicyFallback
            case .never:    return L10n.keychainPolicyNever
            }
        }
    }

    /// Provider whose quota fills the menu-bar icon. Raw values match
    /// the `provider` strings in `enabledProviders` and the SQLite
    /// `provider` column so we can cross-check membership without a
    /// translation table.
    enum MenuBarIconProvider: String, CaseIterable, Sendable, Identifiable {
        case codex
        case claude
        var id: String { rawValue }
        var label: String {
            switch self {
            case .codex:  return L10n.codex
            case .claude: return L10n.claudeCode
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.codexBinaryOverride = defaults.string(forKey: Keys.codexBinary) ?? ""
        self.codexHomeOverride   = defaults.string(forKey: Keys.codexHome) ?? ""
        self.claudeHomeOverride  = defaults.string(forKey: Keys.claudeHome) ?? ""
        let storedInterval = defaults.integer(forKey: Keys.pollInterval)
        self.pollIntervalSeconds = storedInterval > 0 ? storedInterval : 300
        let storedThreshold = defaults.double(forKey: Keys.notifyThreshold)
        self.notifyThreshold = storedThreshold > 0 ? storedThreshold : 85
        self.keychainPolicy = (defaults.string(forKey: Keys.keychainPolicy)
            .flatMap(KeychainPolicy.init(rawValue:))) ?? .fallback
        // Default false. We never default-on a security downgrade —
        // see `mirrorClaudeKeychainToFile` doc comment.
        self.mirrorClaudeKeychainToFile =
            defaults.bool(forKey: Keys.mirrorClaudeKeychainToFile)
        self.menuBarHeadlineWindow = (defaults.string(forKey: Keys.menuBarHeadlineWindow)
            .flatMap(HeadlineWindow.init(rawValue:))) ?? .last7d
        self.menuBarIconProvider = (defaults.string(forKey: Keys.menuBarIconProvider)
            .flatMap(MenuBarIconProvider.init(rawValue:))) ?? .codex
        // Enabled providers — defaults to the full set so an old build
        // upgrading to this binary keeps tracking both. We sanitise to
        // drop unknown tokens (future renames / deletions) and refuse
        // an empty stored value (treat as "never set" → full default).
        let storedProviders = defaults.array(forKey: Keys.enabledProviders) as? [String]
        let sanitised: Set<String> = storedProviders.map {
            Set($0).intersection(Self.knownProviders)
        } ?? []
        self.enabledProviders = sanitised.isEmpty
            ? Self.knownProviders
            : sanitised
        // Onboarding-done flag. If it's missing AND the user already has
        // some prior settings written (e.g. they picked a language on a
        // previous launch), assume they're an existing user and don't
        // re-prompt them. Only fully-fresh installs get the new step.
        let storedDone = defaults.object(forKey: Keys.providerOnboardingDone) as? Bool
        if let done = storedDone {
            self.hasCompletedProviderOnboarding = done
        } else {
            let looksLikeExistingUser =
                defaults.string(forKey: "app.language") != nil
                || storedProviders != nil
                || storedInterval > 0
                || storedThreshold > 0
            self.hasCompletedProviderOnboarding = looksLikeExistingUser
            // Persist the inference so we don't redo it on every launch.
            defaults.set(looksLikeExistingUser, forKey: Keys.providerOnboardingDone)
        }
    }

    /// Update one provider's enabled state, honouring the "at least one
    /// must stay enabled" constraint. Returns `false` (and leaves the
    /// store untouched) when the change would empty the set so the UI
    /// can keep the toggle visibly ON without going through a no-op
    /// write that would still fire the didSet.
    @discardableResult
    func setProviderEnabled(_ provider: String, enabled: Bool) -> Bool {
        var next = enabledProviders
        if enabled {
            guard Self.knownProviders.contains(provider) else { return false }
            next.insert(provider)
        } else {
            next.remove(provider)
        }
        guard !next.isEmpty else { return false }
        guard next != enabledProviders else { return true }
        enabledProviders = next
        snapMenuBarIconProviderIfNeeded()
        return true
    }

    /// Mark the provider step of onboarding as done. Idempotent.
    func markProviderOnboardingDone() {
        guard !hasCompletedProviderOnboarding else { return }
        hasCompletedProviderOnboarding = true
    }

    /// Replace the enabled set wholesale (e.g. from the onboarding
    /// sheet). Empty input is rejected (returns false).
    @discardableResult
    func replaceEnabledProviders(_ providers: Set<String>) -> Bool {
        let cleaned = providers.intersection(Self.knownProviders)
        guard !cleaned.isEmpty else { return false }
        enabledProviders = cleaned
        snapMenuBarIconProviderIfNeeded()
        return true
    }

    /// If the user just disabled the provider currently powering the
    /// menu-bar icon, switch the icon to whichever provider is still
    /// enabled. The render path also has a fallback (SF Symbol when the
    /// chosen provider has no usable data), but the icon should track
    /// the user's current setup, not stay "stuck" pointed at something
    /// they've turned off.
    private func snapMenuBarIconProviderIfNeeded() {
        guard !enabledProviders.contains(menuBarIconProvider.rawValue) else { return }
        if let fallback = MenuBarIconProvider.allCases.first(where: {
            enabledProviders.contains($0.rawValue)
        }) {
            menuBarIconProvider = fallback
        }
    }

    /// Provider IDs the app currently knows about. Match the `provider`
    /// column values in SQLite + `ProviderFilter.rawValue`.
    /// `nonisolated` so `Snapshot` (called off the main actor by the
    /// pollers) can read it without hopping back.
    nonisolated static let knownProviders: Set<String> = ["codex", "claude"]

    /// Read-only snapshot for non-MainActor callers (poller actor, etc.).
    nonisolated static func snapshot() -> Snapshot {
        let d = UserDefaults.standard
        let storedProviders = d.array(forKey: Keys.enabledProviders) as? [String]
        let sanitised: Set<String> = storedProviders.map {
            Set($0).intersection(knownProviders)
        } ?? []
        let providers = sanitised.isEmpty ? knownProviders : sanitised
        return Snapshot(
            codexBinaryOverride: d.string(forKey: Keys.codexBinary) ?? "",
            codexHomeOverride: d.string(forKey: Keys.codexHome) ?? "",
            claudeHomeOverride: d.string(forKey: Keys.claudeHome) ?? "",
            pollIntervalSeconds: max(60, d.integer(forKey: Keys.pollInterval) > 0
                ? d.integer(forKey: Keys.pollInterval) : 300),
            notifyThreshold: {
                let t = d.double(forKey: Keys.notifyThreshold)
                return t > 0 ? t : 85
            }(),
            keychainPolicy: (d.string(forKey: Keys.keychainPolicy)
                .flatMap(KeychainPolicy.init(rawValue:))) ?? .fallback,
            mirrorClaudeKeychainToFile: d.bool(forKey: Keys.mirrorClaudeKeychainToFile),
            enabledProviders: providers
        )
    }

    struct Snapshot: Sendable {
        let codexBinaryOverride: String
        let codexHomeOverride: String
        let claudeHomeOverride: String
        let pollIntervalSeconds: Int
        let notifyThreshold: Double
        let keychainPolicy: KeychainPolicy
        let mirrorClaudeKeychainToFile: Bool
        let enabledProviders: Set<String>
    }

    private enum Keys {
        static let codexBinary    = "settings.codexBinary"
        static let codexHome      = "settings.codexHome"
        static let claudeHome     = "settings.claudeHome"
        static let pollInterval   = "settings.pollIntervalSeconds"
        static let notifyThreshold = "settings.notifyThreshold"
        static let keychainPolicy = "settings.keychainPolicy"
        static let mirrorClaudeKeychainToFile = "settings.mirrorClaudeKeychainToFile"
        static let menuBarHeadlineWindow = "settings.menuBarHeadlineWindow"
        static let menuBarIconProvider = "settings.menuBarIconProvider"
        static let enabledProviders = "settings.enabledProviders"
        static let providerOnboardingDone = "onboarding.providersDone"
    }
}
