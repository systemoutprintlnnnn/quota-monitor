import SwiftUI

/// Which metric the contribution heatmap colors each cell by. The grid
/// itself never changes — one cell per local-calendar day — only the value
/// that drives the color does:
///   - `.daily`      each day's own tokens (the classic contribution graph)
///   - `.weekly`     each day colored by its whole week's total (columns read
///                   as uniform bands)
///   - `.cumulative` running total to date (the map darkens left → right)
enum HeatmapMode: String, CaseIterable, Identifiable, Hashable {
    case daily
    case weekly
    case cumulative

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily:      return L10n.activityModeDaily
        case .weekly:     return L10n.activityModeWeekly
        case .cumulative: return L10n.activityModeCumulative
        }
    }
}

/// Five-step green scale, shared by the grid and the legend so they can't
/// drift. Level 0 is the empty / no-activity tint; 1…4 deepen with volume.
/// Green matches the app's two-color (green/red) menu-bar discipline rather
/// than inventing a new accent.
enum HeatmapPalette {
    static func color(level: Int) -> Color {
        switch level {
        case ..<1:  return Color.secondary.opacity(0.12)
        case 1:     return Color.green.opacity(0.30)
        case 2:     return Color.green.opacity(0.50)
        case 3:     return Color.green.opacity(0.72)
        default:    return Color.green
        }
    }
}

/// GitHub-style contribution heatmap: weeks as columns, weekday as rows,
/// month labels along the top. Cells are bucketed into five intensity levels.
/// Horizontally scrollable so a full year never clips inside the dashboard.
struct ActivityHeatmap: View {
    /// Trailing daily series, oldest first, zero-filled (one entry per day).
    let daily: [DailyPoint]
    let mode: HeatmapMode
    let tokenLocale: Locale

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        let model = HeatmapModel(daily: daily, mode: mode, calendar: .current)
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    monthLabels(model)
                    grid(model)
                }
            }
            legend
        }
    }

    // MARK: - grid

    private func grid(_ model: HeatmapModel) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(model.weeks.indices, id: \.self) { col in
                VStack(spacing: gap) {
                    ForEach(model.weeks[col].indices, id: \.self) { row in
                        cellView(model.weeks[col][row])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell entry: HeatmapModel.Cell) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(HeatmapPalette.color(level: entry.level))
            .frame(width: cell, height: cell)
            .help(tooltip(entry))
    }

    private func tooltip(_ entry: HeatmapModel.Cell) -> String {
        guard let point = entry.point else { return "" }
        let date = point.date.formatted(.dateTime.year().month(.abbreviated).day())
        let tokens = point.tokens.formatted(
            .number.notation(.compactName).locale(tokenLocale))
        return L10n.activityHeatmapCell(date: date, tokens: tokens)
    }

    // MARK: - month labels

    private func monthLabels(_ model: HeatmapModel) -> some View {
        let width = CGFloat(model.weeks.count) * (cell + gap)
        return ZStack(alignment: .topLeading) {
            ForEach(model.monthMarkers, id: \.column) { marker in
                Text(marker.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(x: CGFloat(marker.column) * (cell + gap))
            }
        }
        .frame(width: max(width, 1), height: 12, alignment: .topLeading)
    }

    // MARK: - legend

    private var legend: some View {
        HStack(spacing: 4) {
            Text(L10n.activityHeatmapLess)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(HeatmapPalette.color(level: level))
                    .frame(width: cell, height: cell)
            }
            Text(L10n.activityHeatmapMore)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Pure layout model for the heatmap: turns the flat daily series into
/// calendar-aligned week columns, assigns each day an intensity level for
/// the active `mode`, and works out where month labels go. No SwiftUI here
/// so the bucketing stays easy to reason about.
struct HeatmapModel {
    struct Cell {
        let point: DailyPoint?   // nil = calendar padding outside the range
        let level: Int           // 0…4
    }

    /// Each inner array is one week (7 entries, top → bottom by weekday).
    let weeks: [[Cell]]
    /// `(column index, abbreviated month label)` for the first column of
    /// each month present in the range.
    let monthMarkers: [(column: Int, label: String)]

    init(daily: [DailyPoint], mode: HeatmapMode, calendar: Calendar) {
        // 1. Per-day display value for the chosen mode.
        let values = HeatmapModel.values(daily: daily, mode: mode, calendar: calendar)
        let thresholds = HeatmapModel.thresholds(values: values, mode: mode)
        func level(_ v: Double) -> Int {
            guard v > 0 else { return 0 }
            var lvl = 1
            for t in thresholds where v > t { lvl += 1 }
            return min(lvl, 4)
        }

        // 2. Pad the leading days so column 0 starts on the calendar's
        //    first weekday, then chunk into 7-day columns.
        guard let first = daily.first?.date else {
            weeks = []
            monthMarkers = []
            return
        }
        let weekdayOfFirst = calendar.component(.weekday, from: first)
        let lead = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var cells: [Cell] = []
        cells.reserveCapacity(daily.count + lead + 7)
        for _ in 0..<lead { cells.append(Cell(point: nil, level: 0)) }
        for (i, point) in daily.enumerated() {
            cells.append(Cell(point: point, level: level(values[i])))
        }
        while cells.count % 7 != 0 { cells.append(Cell(point: nil, level: 0)) }

        var builtWeeks: [[Cell]] = []
        var c = 0
        while c < cells.count {
            builtWeeks.append(Array(cells[c..<min(c + 7, cells.count)]))
            c += 7
        }
        weeks = builtWeeks

        // 3. Month markers: first column whose representative day starts a
        //    new month.
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = LocalizationStore.shared.language == .simplifiedChinese
            ? Locale(identifier: "zh_Hans")
            : Locale(identifier: "en_US")
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")

        var markers: [(column: Int, label: String)] = []
        var lastMonth = -1
        for (col, week) in builtWeeks.enumerated() {
            guard let date = week.compactMap({ $0.point?.date }).first else { continue }
            let month = calendar.component(.month, from: date)
            if month != lastMonth {
                markers.append((col, monthFormatter.string(from: date)))
                lastMonth = month
            }
        }
        monthMarkers = markers
    }

    /// Per-day value the color is bucketed from, in `daily` order.
    static func values(
        daily: [DailyPoint], mode: HeatmapMode, calendar: Calendar
    ) -> [Double] {
        switch mode {
        case .daily:
            return daily.map { Double($0.tokens) }
        case .weekly:
            var weekTotal: [Date: Double] = [:]
            for point in daily {
                let start = calendar.dateInterval(of: .weekOfYear, for: point.date)?.start
                    ?? calendar.startOfDay(for: point.date)
                weekTotal[start, default: 0] += Double(point.tokens)
            }
            return daily.map { point in
                let start = calendar.dateInterval(of: .weekOfYear, for: point.date)?.start
                    ?? calendar.startOfDay(for: point.date)
                return weekTotal[start] ?? 0
            }
        case .cumulative:
            var running = 0.0
            return daily.map { running += Double($0.tokens); return running }
        }
    }

    /// Three cut points splitting levels 1/2, 2/3, 3/4. Quartiles of the
    /// non-zero values for daily/weekly (so one runaway day doesn't wash
    /// everything else pale); even quarters of the max for cumulative
    /// (which grows monotonically, so quartiles would bunch at the end).
    static func thresholds(values: [Double], mode: HeatmapMode) -> [Double] {
        if mode == .cumulative {
            let maxValue = values.max() ?? 0
            return [maxValue * 0.25, maxValue * 0.5, maxValue * 0.75]
        }
        let nonzero = values.filter { $0 > 0 }.sorted()
        guard !nonzero.isEmpty else { return [0, 0, 0] }
        func percentile(_ p: Double) -> Double {
            let idx = Int((Double(nonzero.count - 1) * p).rounded())
            return nonzero[min(max(idx, 0), nonzero.count - 1)]
        }
        return [percentile(0.25), percentile(0.5), percentile(0.75)]
    }
}
