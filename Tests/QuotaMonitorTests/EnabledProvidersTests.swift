import Foundation
import Testing
@testable import QuotaMonitor

/// Locks down the per-provider toggle's persistence + invariants:
///   - default = the full `knownProviders` set (so users upgrading
///     from a build without the toggle keep tracking everything),
///   - "at least one" rule: disabling the last enabled provider is a
///     no-op and `setProviderEnabled` returns `false`,
///   - sanitisation: an unknown token in stored UserDefaults is dropped
///     on read, and an empty stored array is treated as "never set"
///     (i.e. fall back to the default rather than honouring the empty),
///   - onboarding inference: a fresh UserDefaults gets
///     `needsProviderOnboarding == true`, but a UserDefaults that
///     already holds *any* prior settings (e.g. a language pick from
///     v0.2.x) infers the user has been here before and skips the
///     new step,
///   - Snapshot carries the field so the non-MainActor poller code can
///     read it without hopping back to the actor.
///
/// `SettingsStore` is `@MainActor`, so the suite is too. We isolate
/// each test by handing the store its own `UserDefaults(suiteName:)`,
/// then `removePersistentDomain` in the teardown helper to leave the
/// host's defaults untouched.
@MainActor
@Suite("Provider enabled toggle")
struct EnabledProvidersTests {

    private static func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "test.\(name).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test
    func defaultsIncludeBothProviders() {
        let d = Self.freshDefaults()
        let store = SettingsStore(defaults: d)
        #expect(store.enabledProviders == ["codex", "claude"])
    }

    @Test
    func snapshotCarriesEnabledProviders() {
        let d = Self.freshDefaults()
        d.set(["codex"], forKey: "settings.enabledProviders")
        // Exercise the nonisolated path that the poller actually uses.
        // `snapshot()` reads `UserDefaults.standard`, so write into
        // standard for this case and clean up.
        let key = "settings.enabledProviders"
        let priorStandard = UserDefaults.standard.array(forKey: key)
        UserDefaults.standard.set(["codex"], forKey: key)
        defer {
            if let priorStandard {
                UserDefaults.standard.set(priorStandard, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let snap = SettingsStore.snapshot()
        #expect(snap.enabledProviders == ["codex"])
    }

    @Test
    func cannotDisableLastProvider() {
        let d = Self.freshDefaults()
        let store = SettingsStore(defaults: d)
        // Disable claude — succeeds, set goes down to {codex}.
        #expect(store.setProviderEnabled("claude", enabled: false))
        #expect(store.enabledProviders == ["codex"])
        // Now try to disable the only remaining one — must refuse and
        // keep the set unchanged so the UI's binding can stay ON.
        #expect(store.setProviderEnabled("codex", enabled: false) == false)
        #expect(store.enabledProviders == ["codex"])
    }

    @Test
    func unknownStoredProvidersAreDropped() {
        let d = Self.freshDefaults()
        d.set(["codex", "gemini" /* not yet supported */], forKey: "settings.enabledProviders")
        let store = SettingsStore(defaults: d)
        #expect(store.enabledProviders == ["codex"])
    }

    @Test
    func emptyStoredFallsBackToDefaultSet() {
        let d = Self.freshDefaults()
        d.set([] as [String], forKey: "settings.enabledProviders")
        let store = SettingsStore(defaults: d)
        // Empty is treated as "garbled / never set", not as "user
        // wants nothing" — that would violate the at-least-one rule
        // before any UI ever runs.
        #expect(store.enabledProviders == ["codex", "claude"])
    }

    @Test
    func freshInstallNeedsProviderOnboarding() {
        let d = Self.freshDefaults()
        let store = SettingsStore(defaults: d)
        #expect(store.needsProviderOnboarding)
    }

    @Test
    func upgradingUserSkipsProviderOnboarding() {
        let d = Self.freshDefaults()
        // Simulate a user who already had v0.2.x: language was picked,
        // poll interval was customised, but the new providers key
        // doesn't exist yet.
        d.set("en", forKey: "app.language")
        d.set(180, forKey: "settings.pollIntervalSeconds")
        let store = SettingsStore(defaults: d)
        #expect(store.needsProviderOnboarding == false)
        #expect(store.enabledProviders == ["codex", "claude"])
    }

    @Test
    func markProviderOnboardingDoneIsIdempotent() {
        let d = Self.freshDefaults()
        let store = SettingsStore(defaults: d)
        store.markProviderOnboardingDone()
        #expect(store.needsProviderOnboarding == false)
        // Calling again is a no-op (no-throws, no didSet thrash).
        store.markProviderOnboardingDone()
        #expect(store.needsProviderOnboarding == false)
    }

    @Test
    func replaceEnabledProvidersRejectsEmpty() {
        let d = Self.freshDefaults()
        let store = SettingsStore(defaults: d)
        #expect(store.replaceEnabledProviders([]) == false)
        #expect(store.enabledProviders == ["codex", "claude"])
        // An all-unknown set is also empty after sanitisation → reject.
        #expect(store.replaceEnabledProviders(["gemini"]) == false)
        #expect(store.enabledProviders == ["codex", "claude"])
    }
}
