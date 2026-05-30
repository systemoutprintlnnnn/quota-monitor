import Foundation

// Localized strings for the Dashboard's ActivitySection (the CodeX-style
// usage profile: lifetime tokens, peak day, longest task, streaks, and the
// contribution heatmap). Kept in its own file so the feature is
// self-contained; the catalog stays type-checked Swift either way.
//
// `L10n.s(_:_:)` is private to L10n.swift, so this extension uses its own
// tiny `sa(_:_:)` mirror reading the same `LocalizationStore` language.
extension L10n {

    private static func sa(_ en: String, _ zh: String) -> String {
        switch LocalizationStore.shared.language {
        case .english: return en
        case .simplifiedChinese: return zh
        }
    }

    // MARK: - section + stat strip

    static var activitySectionTitle: String { sa("Activity", "使用画像") }
    static var activityLifetimeTokens: String { sa("Lifetime tokens", "累计 tokens") }
    static var activityPeakTokens: String { sa("Peak tokens", "单日峰值") }
    static var activityLongestTask: String { sa("Longest task", "最长任务") }
    static var activityCurrentStreak: String { sa("Current streak", "当前连续") }
    static var activityLongestStreak: String { sa("Longest streak", "最长连续") }
    static var activityNoData: String {
        sa("No activity recorded yet", "暂无活跃记录")
    }

    // MARK: - heatmap

    static var activityTokenActivity: String { sa("Token activity", "Token 活跃度") }
    static var activityModeDaily: String { sa("Daily", "每日") }
    static var activityModeWeekly: String { sa("Weekly", "每周") }
    static var activityModeCumulative: String { sa("Cumulative", "累计") }
    static var activityHeatmapLess: String { sa("Less", "少") }
    static var activityHeatmapMore: String { sa("More", "多") }

    // MARK: - formatted values

    /// Streak / day-count label, e.g. "38 days" / "38 天".
    static func activityStreakDays(_ count: Int) -> String {
        sa("\(count) days", "\(count) 天")
    }

    /// Duration for the "Longest task" stat. Hours+minutes at hour scale
    /// (matches CodeX's "14h 47m"), minutes+seconds below an hour.
    static func activityDuration(hours: Int, minutes: Int, seconds: Int) -> String {
        if hours > 0 { return sa("\(hours)h \(minutes)m", "\(hours) 时 \(minutes) 分") }
        if minutes > 0 { return sa("\(minutes)m \(seconds)s", "\(minutes) 分 \(seconds) 秒") }
        return sa("\(seconds)s", "\(seconds) 秒")
    }

    /// Heatmap cell tooltip, e.g. "May 12 · 1.2M tokens".
    static func activityHeatmapCell(date: String, tokens: String) -> String {
        sa("\(date) · \(tokens) tokens", "\(date) · \(tokens) tokens")
    }
}
