import SwiftUI
import Charts

/// Composition card: where is the spend going? Two-column layout —
///
/// - Left: top 8 models from the last 30 days as horizontal bars
///   (model name, %, $).
/// - Right: provider donut (Codex vs Claude) + a one-liner auto-insight
///   ("Opus 4 = 67% of spend, +12pp vs prior 30d").
struct CompositionSection: View {
    let modelShares30d: [ModelShare]
    let modelSharesPrior30d: [ModelShare]
    let providerShares30d: [ProviderShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.compositionSectionTitle)
                    .font(.headline)
                Spacer()
            }

            if modelShares30d.isEmpty && providerShares30d.allSatisfy({ $0.valueUSD <= 0 }) {
                Text(L10n.compositionNoSpend)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        modelBarsColumn
                        providerDonutColumn
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        modelBarsColumn
                        providerDonutColumn
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Models column

    private var modelBarsColumn: some View {
        let total = total30d
        let top = Array(modelShares30d.prefix(8))
        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.compositionTopModels)
                .font(.subheadline.weight(.semibold))
            VStack(spacing: 4) {
                ForEach(top) { share in
                    modelBarRow(share, total: max(total, 0.0001))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modelBarRow(_ share: ModelShare, total: Double) -> some View {
        let pct = share.valueUSD / total
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(share.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(share.valueUSD.formatted(.currency(code: "USD")))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", pct * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            ProgressView(value: pct)
                // Two-color discipline: bar tint flips to red when one
                // model is dominant (>50%) — matches the banner trigger.
                .tint(pct > 0.5 ? Color.red : Color.green)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    // MARK: - Provider donut column

    private var providerDonutColumn: some View {
        let total = providerShares30d.reduce(0) { $0 + $1.valueUSD }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.compositionByProvider)
                .font(.subheadline.weight(.semibold))
            if total <= 0 {
                Text(L10n.compositionNoSpend)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                providerDonut(total: total)
                providerLegend(total: total)
            }
            if let insight = insightText {
                Text(insight)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerDonut(total: Double) -> some View {
        Chart(providerShares30d) { share in
            SectorMark(
                angle: .value("USD", share.valueUSD),
                innerRadius: .ratio(0.6),
                angularInset: 1.5
            )
            .cornerRadius(3)
            // Two-color palette: green for the dominant share, secondary
            // grey for the rest. Avoids inventing decorative provider
            // colors that would conflict with the menu bar's green/red
            // semantic discipline.
            .foregroundStyle(by: .value("Provider", share.provider))
        }
        .chartForegroundStyleScale([
            "codex":  Color.green.opacity(0.85),
            "claude": Color.secondary.opacity(0.55)
        ])
        .chartLegend(.hidden)
        .frame(height: 140)
    }

    private func providerLegend(total: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(providerShares30d) { share in
                HStack(spacing: 6) {
                    Circle()
                        .fill(share.provider == "codex"
                              ? Color.green.opacity(0.85)
                              : Color.secondary.opacity(0.55))
                        .frame(width: 7, height: 7)
                    Text(providerLabel(share.provider))
                        .font(.caption2)
                    Spacer()
                    Text(share.valueUSD.formatted(.currency(code: "USD")))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f%%",
                                total > 0 ? share.valueUSD / total * 100 : 0))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private func providerLabel(_ id: String) -> String {
        switch id {
        case "codex":  return L10n.codex
        case "claude": return L10n.claude
        default:       return id
        }
    }

    // MARK: - Insight

    /// Auto-insight sentence — uses the dominant model's pp-delta vs the
    /// prior 30 days when available, otherwise falls back to the static
    /// share-of-spend phrasing.
    private var insightText: String? {
        guard total30d > 0, let top = modelShares30d.first, top.valueUSD > 0
        else { return nil }
        let pct = top.valueUSD / total30d * 100
        let prior = modelSharesPrior30d.first { $0.modelId == top.modelId }
        let priorTotal = modelSharesPrior30d.reduce(0) { $0 + $1.valueUSD }
        if let prior, priorTotal > 0 {
            let priorPct = prior.valueUSD / priorTotal * 100
            let pp = pct - priorPct
            return L10n.compositionInsightWithDelta(
                model: top.displayName, percent: pct, pp: pp)
        }
        return L10n.compositionInsightFlat(model: top.displayName, percent: pct)
    }

    private var total30d: Double {
        modelShares30d.reduce(0) { $0 + $1.valueUSD }
    }
}
