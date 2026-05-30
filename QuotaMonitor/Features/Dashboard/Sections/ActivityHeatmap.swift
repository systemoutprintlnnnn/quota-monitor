import SwiftUI

/// Which metric the contribution heatmap colors each cell by. The grid
/// itself never changes — one cell per local-calendar day — only the value
/// that drives the color does:
///   - `.daily`      each day's own tokens (the classic contribution graph)
///   - `.weekly`     daily tokens for fill, week total encoded as border
///   - `.cumulative` running total to date (logarithmic thresholds)
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

    @State private var hoveredCell: (col: Int, row: Int, cell: HeatmapModel.Cell)?

    private let cell: CGFloat = 13
    private let gap: CGFloat = 3

    var body: some View {
        let model = HeatmapModel(daily: daily, mode: mode, calendar: .current)
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        monthLabels(model)
                        grid(model)
                    }
                    // Custom tooltip overlay — inside ScrollView so it
                    // scrolls with the grid instead of floating at a
                    // fixed viewport position.
                    if let (col, row, cell) = hoveredCell, let point = cell.point {
                        tooltipOverlay(for: point, col: col, row: row)
                    }
                }
            }
            legend
        }
    }

    // MARK: - tooltip overlay

    private func tooltipOverlay(for point: DailyPoint, col: Int, row: Int) -> some View {
        let date = point.date.formatted(.dateTime.year().month(.abbreviated).day())
        let tokens = point.tokens.formatted(
            .number.notation(.compactName).locale(tokenLocale))

        // Position tooltip above the cell
        let xOffset = CGFloat(col) * (cell + gap) + cell / 2
        let yOffset = 16 + CGFloat(row) * (cell + gap) - cell / 2 - 8

        return VStack(alignment: .leading, spacing: 2) {
            Text(date)
                .font(.caption.weight(.medium))
            Text(tokens + " tokens")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
        )
        .position(x: xOffset, y: yOffset)
    }

    // MARK: - grid

    private func grid(_ model: HeatmapModel) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(model.weeks.indices, id: \.self) { col in
                VStack(spacing: gap) {
                    ForEach(model.weeks[col].indices, id: \.self) { row in
                        cellView(model.weeks[col][row], col: col, row: row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ entry: HeatmapModel.Cell, col: Int, row: Int) -> some View {
        let border = entry.weekLevel.flatMap { $0 > 0 ? HeatmapPalette.color(level: $0) : nil }
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(HeatmapPalette.color(level: entry.level))
            .stroke(border ?? .clear, lineWidth: border != nil ? 1.5 : 0)
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering && entry.point != nil {
                    hoveredCell = (col, row, entry)
                } else if !hovering {
                    if hoveredCell?.col == col && hoveredCell?.row == row {
                        hoveredCell = nil
                    }
                }
            }
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
        /// In `.weekly` mode, the intensity level for the whole week's total.
        /// Used as a border/stroke color so the fill still shows daily variation.
        let weekLevel: Int?      // nil in non-weekly modes or for padding
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

        // 1b. In weekly mode, fill color shows daily tokens (not weekly total),
        //     and week total is encoded as a border via `weekLevel`.
        let dailyValues: [Double]
        let weekLevels: [Double?]
        let dailyThresholds: [Double]
        if mode == .weekly {
            dailyValues = daily.map { Double($0.tokens) }
            let weeklyAgg = HeatmapModel.values(daily: daily, mode: .weekly, calendar: calendar)
            weekLevels = weeklyAgg
            dailyThresholds = HeatmapModel.thresholds(values: dailyValues, mode: .daily)
        } else {
            dailyValues = []
            weekLevels = []
            dailyThresholds = []
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

        func cellLevel(_ v: Double, thresholds: [Double]) -> Int {
            guard v > 0 else { return 0 }
            var lvl = 1
            for t in thresholds where v > t { lvl += 1 }
            return min(lvl, 4)
        }

        var cells: [Cell] = []
        cells.reserveCapacity(daily.count + lead + 7)
        for _ in 0..<lead { cells.append(Cell(point: nil, level: 0, weekLevel: nil)) }
        for (i, point) in daily.enumerated() {
            let fillLevel: Int
            let wl: Int?
            if mode == .weekly {
                fillLevel = cellLevel(dailyValues[i], thresholds: dailyThresholds)
                wl = weekLevels[i].map { cellLevel($0, thresholds: thresholds) }
            } else {
                fillLevel = level(values[i])
                wl = nil
            }
            cells.append(Cell(point: point, level: fillLevel, weekLevel: wl))
        }
        while cells.count % 7 != 0 { cells.append(Cell(point: nil, level: 0, weekLevel: nil)) }

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
        monthFormatter.locale = LocalizationStore.activeLanguage == .simplifiedChinese
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
    /// everything else pale); logarithmic scale for cumulative (which
    /// grows monotonically, so linear thresholds would bunch at the end).
    static func thresholds(values: [Double], mode: HeatmapMode) -> [Double] {
        if mode == .cumulative {
            // Logarithmic thresholds so early low-cumulative days aren't
            // all washed to the same pale level. Map through log, pick
            // even fractions on the log scale, then exp back.
            let logValues = values.map { log($0 + 1) }
            let logMax = logValues.max() ?? 0
            guard logMax > 0 else { return [0, 0, 0] }
            return [exp(logMax * 0.25) - 1, exp(logMax * 0.5) - 1, exp(logMax * 0.75) - 1]
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
