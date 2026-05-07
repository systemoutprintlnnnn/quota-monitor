import SwiftUI

// Provider-block rendering helpers (Codex + Claude). Extracted from
// MenuBarContentView so the file's header is just top-level layout.

extension MenuBarContentView {

    /// Codex block: KPI header + plan badge + 5h / 7d / additional quota
    /// rows from the live rate-limit API. The block always renders even
    /// when there's no quota data (keeps the menu bar layout stable).
    @ViewBuilder
    func codexProviderBlock(stats: ProviderStats) -> some View {
        providerBlock(
            label: L10n.codex,
            accent: .blue,
            stats: stats,
            tail: AnyView(codexQuotaInner(stats: stats))
        )
    }

    @ViewBuilder
    func codexQuotaInner(stats: ProviderStats) -> some View {
        if let snapshot = env.latestRateLimits {
            // Compact quota rows nested inside the Codex block. Pre-Day-23
            // these lived in their own card with a separate "Codex CLI
            // quotas" header — folded into the provider block now.
            let activeAdditional = snapshot.additional.filter {
                ($0.primary?.usedPercent ?? 0) > 0.5
            }

            VStack(alignment: .leading, spacing: 6) {
                if let primary = snapshot.primary {
                    QuotaRow(title: L10n.quotaCardTitle5h, window: primary, accent: .blue)
                }
                if let secondary = snapshot.secondary {
                    QuotaRow(title: L10n.quotaCardTitle7d, window: secondary, accent: .blue)
                }
                ForEach(activeAdditional, id: \.limitName) { extra in
                    if let win = extra.primary {
                        QuotaRow(title: extra.limitName, window: win, accent: .blue)
                    }
                }
            }
        } else if env.isRefreshingRateLimits {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // No live data + not loading = either signed-out or first run.
            // Show a one-liner so the empty space isn't mysterious.
            Text(L10n.codexSignInPrompt)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Claude block: KPI header + (preferred) live OAuth `/usage` quota
    /// rows that mirror Codex, falling back to the measured 5h billing
    /// block + last-7d spend when no Claude Code credentials are
    /// available. The fallback path was the *only* path before Day-24,
    /// when we discovered Anthropic does expose a quota endpoint after
    /// all (`POST /api/oauth/usage`, used by the official `claude` CLI).
    @ViewBuilder
    func claudeProviderBlock(
        stats: ProviderStats, blocks: BillingBlocks.Snapshot
    ) -> some View {
        providerBlock(
            label: L10n.claude,
            accent: .orange,
            stats: stats,
            tail: AnyView(claudeQuotaInner(stats: stats, blocks: blocks))
        )
    }

    @ViewBuilder
    func claudeQuotaInner(
        stats: ProviderStats, blocks: BillingBlocks.Snapshot
    ) -> some View {
        if let usage = env.latestClaudeUsage,
           usage.fiveHour != nil || usage.sevenDay != nil {
            claudeOAuthInner(usage: usage)
        } else {
            claudeFallbackInner(stats: stats, blocks: blocks)
        }
    }

    /// Preferred path: render OAuth `/usage` like the Codex block — plan
    /// tier badge + 5h / 7d / per-model quota rows. Mirroring the Codex
    /// layout is the whole point of Day-23/24: one column, two providers,
    /// same shape.
    @ViewBuilder
    func claudeOAuthInner(usage: ClaudeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let w = usage.fiveHour {
                QuotaRow(title: L10n.quotaCardTitle5h, window: w, accent: .orange)
            }
            if let w = usage.sevenDay {
                QuotaRow(title: L10n.quotaCardTitle7d, window: w, accent: .orange)
            }
            // Model-specific 7d quotas (Pro/Max only). Render only when
            // present and non-trivial so Free / lower-tier users don't
            // see empty rows.
            if let w = usage.sevenDayOpus, w.usedPercent > 0.5 {
                QuotaRow(title: L10n.quotaCardTitle7dOpus, window: w, accent: .orange)
            }
            if let w = usage.sevenDaySonnet, w.usedPercent > 0.5 {
                QuotaRow(title: L10n.quotaCardTitle7dSonnet, window: w, accent: .orange)
            }
        }
    }

    /// Fallback when OAuth credentials are unavailable. Same shape as the
    /// pre-Day-24 layout (5h billing block + measured 7d spend), plus a
    /// caption explaining how to upgrade to live quotas.
    @ViewBuilder
    func claudeFallbackInner(
        stats: ProviderStats, blocks: BillingBlocks.Snapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let block = blocks.currentBlock {
                Claude5hRow(block: block,
                            burn: blocks.burnRate,
                            projection: blocks.projection)
            } else if stats.hasData {
                Text(L10n.no5hBlockActive)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if stats.hasData {
                HStack(spacing: 4) {
                    Text(L10n.last7Days)
                        .font(.caption2.weight(.medium))
                    Spacer()
                    Text(stats.last7dValueUSD.formatted(.currency(code: "USD")))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.green)
                    Text("· \(stats.last7dTokens.formatted(.number.notation(.compactName)))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.claudeStartTracking)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let err = env.lastClaudeUsageError, env.latestClaudeUsage == nil {
                // Only nag the user when we have NO usable snapshot at all.
                // A stale `lastClaudeUsageError` left over from a transient
                // 429 / network blip would otherwise sit forever next to a
                // perfectly fine 5h+7d block, contradicting itself.
                Text(claudeErrorHint(err))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .help(err)
            }
        }
    }

    /// Map the verbose `String(describing:)` form of `ClaudeUsageClient.FetchError`
    /// to a one-liner the user can act on.
    func claudeErrorHint(_ raw: String) -> String {
        if raw.contains("noCredentials") || raw.contains("No Claude Code credentials") {
            return L10n.errClaudeNoCreds
        }
        if raw.contains("insufficientScope") || raw.contains("user:profile") {
            return L10n.errClaudeMissingScope
        }
        if raw.contains("unauthorized") {
            return L10n.errClaudeUnauthorized
        }
        if raw.contains("rateLimited") || raw.contains("HTTP 429") || raw.contains("rate-limited") {
            return L10n.errClaudeRateLimited
        }
        return L10n.errClaudeUnavailable
    }

    /// Shared chrome for both provider blocks. `tail` is the provider-
    /// specific quota content rendered below the KPI header.
    func providerBlock(
        label: String, accent: Color, stats: ProviderStats, tail: AnyView
    ) -> some View {
        // Window picker is shared across both provider blocks so the user
        // sees a coherent "everything is the same period" header. Pulled
        // off SettingsStore here (not threaded through every call site)
        // because the only readers are these blocks + the Dashboard
        // statline — both already touch SettingsStore.
        let window = settings.menuBarHeadlineWindow
        let headlineUSD: Double
        let headlineTokens: Int64
        let headlineSessions: Int
        switch window {
        case .last7d:
            headlineUSD      = stats.last7dValueUSD
            headlineTokens   = stats.last7dTokens
            headlineSessions = stats.last7dSessionCount
        case .last30d:
            headlineUSD      = stats.last30dValueUSD
            headlineTokens   = stats.last30dTokens
            headlineSessions = stats.last30dSessionCount
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                if stats.hasData {
                    Text(L10n.providerSessionCount(headlineSessions))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help(L10n.headlineApiEquivalentHelp)
                } else {
                    Text(L10n.noDataLower)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.headlineApiEquivalent(window))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help(L10n.headlineApiEquivalentHelp)
                    // Headline: dollar figure + token count on the same
                    // line. Token count was relegated to a tiny right-
                    // corner chip pre-2026-05-06; merging here gives it
                    // the same visual weight as the dollar value, which
                    // matters because the API-equivalent USD is a
                    // *hypothetical* — actual subscription cost is fixed
                    // — while the token count is what you actually used.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(headlineUSD.formatted(.currency(code: "USD")))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(stats.hasData ? Color.primary : Color.secondary)
                            .help(L10n.headlineApiEquivalentHelp)
                        if stats.hasData {
                            Text(L10n.headlineTokensSuffix(
                                headlineTokens.formatted(.number.notation(.compactName))))
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(Color.primary)
                                .help(L10n.headlineApiEquivalentHelp)
                        }
                    }
                }
                Spacer()
            }
            tail
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.08))
        )
    }
}
