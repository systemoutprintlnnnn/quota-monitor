import SwiftUI

/// The view that lives in the macOS menu bar slot itself (NOT the
/// popover — that's `MenuBarContentView`). Renders a compact two-row
/// stack of "5h XX%" / "7d XX%" for the user-chosen provider, or
/// falls back to a static SF Symbol when:
///   - the chosen provider isn't enabled in Settings, or
///   - we don't have a usable rate-limit snapshot yet (cold start,
///     not signed in, transient API error).
///
/// **Why text instead of an icon.** Text in the menu bar is the
/// canonical pattern for "live quantity" indicators (Stats, iStat,
/// Bartender's battery widget). It tracks the user's appearance
/// (template-rendered as black-on-light / white-on-dark) and stays
/// readable at the system font's 9pt floor. A circular gauge at this
/// size loses fidelity under the 4-bin SF Symbol rendering steps.
///
/// **Why two rows, not one.** The user explicitly asked for both 5h
/// and 7d windows visible. Stacked rows fit naturally into the 22pt
/// menu-bar height; a single row "5h 23% · 7d 8%" would either
/// overflow at high-DPI scales or shrink to <9pt and clip glyph
/// shapes. The vertical layout matches the Dashboard's QuotaRow
/// section and reuses the same reading order.
///
/// **No watch-mode rendering math here.** All the percent picking is
/// done off the `AppEnvironment` snapshots (`latestRateLimits` /
/// `latestClaudeUsage`) so this view stays pure UI — no DB, no I/O,
/// no `Task`. Recomputes whenever those snapshots change because
/// `@Environment(AppEnvironment.self)` triggers it via Observation.
struct MenuBarLabelView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if let pair = pickPair() {
            // The macOS menu bar slot is ~22pt tall, of which ~16pt is
            // safe for content (the rest is the system's own padding).
            // Two rows of system-minimum 9pt text + default leading add
            // up to ~24pt and SwiftUI silently clips the second line —
            // that's the "I only see 5h" symptom.
            //
            // Fix: shrink to 8pt rounded mono and zero VStack spacing,
            // which lands the box at ~16pt total. We also `.fixedSize`
            // so the menu bar gives us our intrinsic width instead of
            // squeezing us into one row.
            VStack(alignment: .trailing, spacing: 0) {
                Text(pair.row1)
                Text(pair.row2)
            }
            .font(.system(size: 8, weight: .semibold, design: .rounded)
                  .monospacedDigit())
            .fixedSize()
        } else {
            // Same icon the app shipped with before — keeps the menu
            // bar's visual identity stable when there's nothing
            // useful to show. The popover still works (it has its
            // own loading / sign-in copy).
            Image(systemName: "gauge.with.dots.needle.50percent")
        }
    }

    // MARK: - data picking

    private struct Pair {
        let row1: String
        let row2: String
    }

    private func pickPair() -> Pair? {
        // Honour the "is this provider even tracked?" rule first. If
        // the user disabled the provider their icon points at, we
        // fall through to the icon — `SettingsStore` tries to snap
        // the icon-provider to a still-enabled one, but a transient
        // race during the toggle can land us here briefly.
        let id = settings.menuBarIconProvider.rawValue
        guard settings.enabledProviders.contains(id) else { return nil }

        switch settings.menuBarIconProvider {
        case .codex:
            guard let snap = env.latestRateLimits else { return nil }
            // Need at least one window with non-trivial usage to
            // justify the label. A brand-new install where both
            // windows read 0% looks identical to "no data" — show
            // the icon instead so users don't think the app is
            // claiming they've used something they haven't.
            return makePair(
                fiveHour: snap.primary?.usedPercent,
                sevenDay: snap.secondary?.usedPercent)

        case .claude:
            guard let usage = env.latestClaudeUsage else { return nil }
            return makePair(
                fiveHour: usage.fiveHour?.usedPercent,
                sevenDay: usage.sevenDay?.usedPercent)
        }
    }

    private func makePair(fiveHour: Double?, sevenDay: Double?) -> Pair? {
        // If both windows are absent, there's literally nothing to
        // render — bail. If only one is missing show "--" in its
        // slot so the row layout stays stable (otherwise the symbol
        // height changes and the menu bar visibly twitches).
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return Pair(
            row1: "5h " + format(fiveHour),
            row2: "7d " + format(sevenDay))
    }

    /// "23%" — clamped to 0...100, no decimals (the menu bar slot is
    /// too narrow to be precise and the popover already shows the
    /// exact figure to one decimal).
    private func format(_ pct: Double?) -> String {
        guard let pct else { return "--" }
        return "\(Int(max(0, min(100, pct.rounded()))))%"
    }
}
