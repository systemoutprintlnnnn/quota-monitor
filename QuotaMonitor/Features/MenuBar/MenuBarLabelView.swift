import SwiftUI

/// The view that lives in the macOS menu bar slot itself (NOT the
/// popover — that's `MenuBarContentView`). Renders a single
/// horizontal row showing the user's selected provider(s):
///   single-pick → "5h 23% · 7d 8%"
///   both        → "CX 5h 23% · 7d 8% | CC 5h 50% · 7d 12%"
/// Falls back to a static SF Symbol when no selected provider has
/// usable data yet (cold start, not signed in, transient API error).
///
/// **Why text instead of an icon.** Text in the menu bar is the
/// canonical pattern for "live quantity" indicators (Stats, iStat,
/// Bartender's battery widget). It tracks the user's appearance
/// (template-rendered as black-on-light / white-on-dark) and stays
/// readable at the system font's 9pt floor. A circular gauge at this
/// size loses fidelity under the 4-bin SF Symbol rendering steps.
///
/// **Always one line.** macOS reserves vertical padding inside the
/// menu-bar slot we can't reclaim, so any 2-row stack ends up
/// clipped — even at 8pt with zero VStack spacing the system still
/// eats the second row. We always render one row at 11pt and join
/// multi-provider output with " | ". The line gets wider but never
/// taller, which is the only dimension the slot will give us.
///
/// **Provider tag in multi mode.** "CX" / "CC" prefix tells the user
/// which CLI each percent belongs to. We omit the prefix in
/// single-provider mode since there's nothing to disambiguate.
///
/// **No watch-mode rendering math here.** All percent picking is
/// done off the `AppEnvironment` snapshots (`latestRateLimits` /
/// `latestClaudeUsage`) so this view stays pure UI — no DB, no I/O,
/// no `Task`. Recomputes whenever those snapshots change because
/// `@Environment(AppEnvironment.self)` triggers it via Observation.
struct MenuBarLabelView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(LocalizationStore.self) private var loc
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let rows = pickRows()
        Group {
            if rows.isEmpty {
                // Same icon the app shipped with before — keeps the menu
                // bar's visual identity stable when there's nothing
                // useful to show. The popover still works (it has its
                // own loading / sign-in copy).
                Image(systemName: "gauge.with.dots.needle.50percent")
            } else {
                // Always one horizontal row — multi-row stacks get
                // clipped by the menu-bar slot's reserved padding even
                // at 8pt. With both providers selected we join them
                // with a " | " separator so they read as two distinct
                // chunks without forcing a second line. `.fixedSize`
                // stops the system from squeezing the intrinsic width
                // when other items crowd the bar.
                Text(rows.map(\.line).joined(separator: " | "))
                    .font(.system(size: 11, weight: .semibold, design: .rounded)
                          .monospacedDigit())
                    .fixedSize()
            }
        }
        // First-launch onboarding lives in a standalone Window scene,
        // not a sheet on the popover (the popover is too narrow to
        // host the picker without it looking cramped). We use the
        // label's `.task` because it runs on app launch even when the
        // user hasn't clicked the menu-bar icon yet — the popover's
        // own task fires only on first open, which would mean the
        // window stays hidden until the user pokes the icon.
        .task {
            if loc.needsOnboarding || settings.needsProviderOnboarding {
                openWindow(id: "onboarding")
            }
        }
    }

    // MARK: - data picking

    private struct Row {
        /// Two-letter provider tag ("CX" / "CC"). Used both as the
        /// visible prefix when multiple providers are shown and as
        /// the ForEach id.
        let tag: String
        /// "5h 23% · 7d 8%". Stable layout so the bar doesn't
        /// twitch when one window is missing — `format` returns
        /// "--" when a percent is unknown.
        let body: String
        /// Final string emitted into the menu bar — single-provider
        /// mode skips the tag (the user picked exactly one), multi
        /// keeps the prefix so they can tell rows apart.
        let line: String
    }

    private func pickRows() -> [Row] {
        // Order matters for the visible row — keep it stable across
        // renders (`Set` iteration is not stable) by hard-coding the
        // canonical "codex first, claude second" sequence.
        var out: [(tag: String, body: String)] = []
        for id in ["codex", "claude"] {
            guard settings.menuBarIconProviders.contains(id),
                  settings.enabledProviders.contains(id),
                  let row = makeRow(for: id) else { continue }
            out.append(row)
        }
        // Tag prefix only matters when there's more than one row to
        // disambiguate. Single-provider mode keeps the line clean.
        let multi = out.count > 1
        return out.map { Row(
            tag: $0.tag,
            body: $0.body,
            line: multi ? "\($0.tag) \($0.body)" : $0.body)
        }
    }

    private func makeRow(for id: String) -> (tag: String, body: String)? {
        switch id {
        case "codex":
            guard let snap = env.latestRateLimits else { return nil }
            return composeRow(tag: "CX",
                              fiveHour: snap.primary?.usedPercent,
                              sevenDay: snap.secondary?.usedPercent)
        case "claude":
            guard let usage = env.latestClaudeUsage else { return nil }
            return composeRow(tag: "CC",
                              fiveHour: usage.fiveHour?.usedPercent,
                              sevenDay: usage.sevenDay?.usedPercent)
        default:
            return nil
        }
    }

    private func composeRow(tag: String,
                            fiveHour: Double?,
                            sevenDay: Double?) -> (tag: String, body: String)? {
        // If both windows are absent, there's literally nothing to
        // render for this provider — drop it so we don't waste space
        // on "CC 5h -- · 7d --".
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return (tag, "5h \(format(fiveHour)) · 7d \(format(sevenDay))")
    }

    /// "23%" — clamped to 0...100, no decimals (the menu bar slot is
    /// too narrow to be precise and the popover already shows the
    /// exact figure to one decimal).
    private func format(_ pct: Double?) -> String {
        guard let pct else { return "--" }
        return "\(Int(max(0, min(100, pct.rounded()))))%"
    }
}
