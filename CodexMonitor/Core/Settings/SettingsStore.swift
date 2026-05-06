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
    /// Which rolling window the menu bar uses for the headline
    /// `$X.XX · Yk tokens` line and the session-count chip. Default
    /// 7 days because most users want a "what did I do this week"
    /// signal — 30 days drowns out short-term spikes. The picker lives in
    /// Settings → General → Menu bar.
    var menuBarHeadlineWindow: HeadlineWindow {
        didSet { defaults.set(menuBarHeadlineWindow.rawValue,
                              forKey: Keys.menuBarHeadlineWindow) }
    }

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
        self.menuBarHeadlineWindow = (defaults.string(forKey: Keys.menuBarHeadlineWindow)
            .flatMap(HeadlineWindow.init(rawValue:))) ?? .last7d
    }

    /// Read-only snapshot for non-MainActor callers (poller actor, etc.).
    nonisolated static func snapshot() -> Snapshot {
        let d = UserDefaults.standard
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
                .flatMap(KeychainPolicy.init(rawValue:))) ?? .fallback
        )
    }

    struct Snapshot: Sendable {
        let codexBinaryOverride: String
        let codexHomeOverride: String
        let claudeHomeOverride: String
        let pollIntervalSeconds: Int
        let notifyThreshold: Double
        let keychainPolicy: KeychainPolicy
    }

    private enum Keys {
        static let codexBinary    = "settings.codexBinary"
        static let codexHome      = "settings.codexHome"
        static let claudeHome     = "settings.claudeHome"
        static let pollInterval   = "settings.pollIntervalSeconds"
        static let notifyThreshold = "settings.notifyThreshold"
        static let keychainPolicy = "settings.keychainPolicy"
        static let menuBarHeadlineWindow = "settings.menuBarHeadlineWindow"
    }
}
