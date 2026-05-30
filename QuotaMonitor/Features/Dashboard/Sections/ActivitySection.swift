import SwiftUI

/// Activity card: the lifetime / engagement profile a CodeX-style usage
/// screen shows. A five-up stat strip (lifetime tokens, peak day, longest
/// task, current + longest streak) over a contribution-style heatmap with
/// a Daily / Weekly / Cumulative toggle.
///
/// Reads `DashboardSnapshot.activity`, which `loadDashboard` already scopes
/// to the active provider filter — so every number here follows the
/// All / Codex / Claude picker in the toolbar.
struct ActivitySection: View {
    @Environment(SettingsStore.self) private var settings
    let activity: ActivitySnapshot

    @State private var mode: HeatmapMode = .daily

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.activitySectionTitle)
                    .font(.headline)
                Spacer()
            }

            statStrip

            if activity.hasData {
                heatmapCard
            } else {
                Text(L10n.activityNoData)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - stat strip

    private var statStrip: some View {
        let locale = settings.tokenFormatLocale
        return HStack(spacing: 0) {
            statCell(
                value: compactTokens(activity.lifetimeTokens, locale: locale),
                label: L10n.activityLifetimeTokens)
            cellDivider
            statCell(
                value: compactTokens(activity.peakDayTokens, locale: locale),
                label: L10n.activityPeakTokens,
                help: activity.peakDay.map {
                    $0.formatted(.dateTime.year().month().day())
                })
            cellDivider
            statCell(
                value: durationText(activity.longestTaskSeconds),
                label: L10n.activityLongestTask)
            cellDivider
            statCell(
                value: L10n.activityStreakDays(activity.currentStreakDays),
                label: L10n.activityCurrentStreak)
            cellDivider
            statCell(
                value: L10n.activityStreakDays(activity.longestStreakDays),
                label: L10n.activityLongestStreak)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: 34)
    }

    private func statCell(value: String, label: String, help: String? = nil) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .help(help ?? "")
    }

    // MARK: - heatmap

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.activityTokenActivity)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(HeatmapMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ActivityHeatmap(
                daily: activity.daily,
                mode: mode,
                tokenLocale: settings.tokenFormatLocale)
        }
    }

    // MARK: - formatting

    private func compactTokens(_ tokens: Int64, locale: Locale) -> String {
        guard tokens > 0 else { return "0" }
        return tokens.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
                .locale(locale))
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return L10n.activityDuration(hours: hours, minutes: minutes, seconds: secs)
    }
}
