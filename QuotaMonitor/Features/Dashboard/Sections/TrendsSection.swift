import SwiftUI
import Charts

/// Trends card: a single 30-day daily bar chart plus a statline beneath
/// summarizing today / 7d / 30d totals and the month-over-month delta.
/// Answers "is my usage trending up or down?".
///
/// The old Dashboard had three separate sections for these numbers
/// (`dailySection`, `monthlySection`, `rateLimitHistory`). The 12-month
/// chart was dropped per a later product call — at the menu-bar app's
/// cadence the 30-day window is the only horizon that drives action; the
/// 12-month view was decorative. The rate-limit scatter chart is no
/// longer rendered either, but its underlying samples continue to be
/// collected for future diagnostics.
struct TrendsSection: View {
    /// 60-day extension. We render the trailing N entries (selected via the
    /// `range` picker) as the chart and use the full 60 to compute the
    /// prior-period delta in `statline`.
    let dailyExtended: [DailyPoint]

    enum Range: Hashable, CaseIterable {
        case last7d
        case last30d

        var days: Int {
            switch self {
            case .last7d: return 7
            case .last30d: return 30
            }
        }

        var label: String {
            switch self {
            case .last7d: return L10n.last7Days
            case .last30d: return L10n.last30Days
            }
        }
    }

    @State private var range: Range = .last30d
    @State private var selectedDay: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.trendsSectionTitle)
                    .font(.headline)
                Spacer()
                Picker("", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            dailyChartCard

            statline
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Daily (selectable window)

    private var windowed: [DailyPoint] {
        Array(dailyExtended.suffix(range.days))
    }

    private var dailyChartCard: some View {
        let cal = Calendar.current
        let series = windowed
        let selectedPoint: DailyPoint? = {
            guard let selectedDay else { return nil }
            return series.first { cal.isDate($0.date, inSameDayAs: selectedDay) }
        }()
        // 7-day stride is too sparse for a 7-day window; pick a stride that
        // keeps ~6 ticks visible regardless of range.
        let stride = max(1, range.days / 6)
        return VStack(alignment: .leading, spacing: 6) {
            Text(range.label)
                .font(.subheadline.weight(.semibold))
            Chart(series) { point in
                BarMark(
                    x: .value(L10n.chartAxisDay, point.date, unit: .day),
                    y: .value(L10n.chartAxisApiValue, point.valueUSD)
                )
                // Two-color discipline: green is the only decorative tint.
                .foregroundStyle(
                    selectedPoint.map { cal.isDate($0.date, inSameDayAs: point.date) } ?? false
                    ? Color.green
                    : Color.green.opacity(0.55)
                )
                .cornerRadius(3)

                if let selectedPoint, cal.isDate(selectedPoint.date, inSameDayAs: point.date) {
                    RuleMark(x: .value(L10n.chartAxisDay, selectedPoint.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .annotation(
                            position: .top,
                            alignment: .center,
                            spacing: 4,
                            overflowResolution: .init(x: .fit, y: .disabled)
                        ) { tooltip(for: selectedPoint) }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: stride)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(),
                                    centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDay)
            .frame(height: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tooltip(for point: DailyPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(point.valueUSD.formatted(.currency(code: "USD")))
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.green)
            Text(L10n.tokensCount(point.tokens.formatted(.number.notation(.compactName))))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 1)
        )
    }

    // MARK: - Statline

    private var statline: some View {
        let today = todayUSD
        let last7d = lastNDaysUSD(7)
        let last30d = lastNDaysUSD(30)
        let prior30d = priorNDaysUSD(30, offsetDays: 30)

        var parts: [String] = [
            L10n.trendsTodayShort(today.formatted(.currency(code: "USD"))),
            L10n.trends7dShort(last7d.formatted(.currency(code: "USD"))),
            L10n.trends30dShort(last30d.formatted(.currency(code: "USD"))),
        ]
        if prior30d > 0.01 {
            let pct = (last30d - prior30d) / prior30d * 100
            parts.append(L10n.trendsDeltaPriorMonth(percent: pct))
        }
        return HStack {
            Text(parts.joined(separator: " · "))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// Sum of last `n` days from `dailyExtended` (oldest first). Always
    /// inclusive of today as the last entry.
    private func lastNDaysUSD(_ n: Int) -> Double {
        let slice = dailyExtended.suffix(n)
        return slice.reduce(0) { $0 + $1.valueUSD }
    }

    /// Sum of the `n` days that ended `offsetDays` ago. For `n = 30,
    /// offsetDays = 30` this is "the 30 days before the most recent 30".
    private func priorNDaysUSD(_ n: Int, offsetDays: Int) -> Double {
        let total = dailyExtended.count
        let endIndex = total - offsetDays
        let startIndex = max(0, endIndex - n)
        guard startIndex < endIndex, endIndex <= total else { return 0 }
        return dailyExtended[startIndex..<endIndex].reduce(0) { $0 + $1.valueUSD }
    }

    private var todayUSD: Double {
        dailyExtended.last?.valueUSD ?? 0
    }
}
