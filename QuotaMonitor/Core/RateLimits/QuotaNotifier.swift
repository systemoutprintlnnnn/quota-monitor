import Foundation
import UserNotifications

// Posts a desktop notification the first time a window's used% crosses a
// configured threshold within a given reset cycle. Dedup key is
// (bucket, limitName, resetAt) so the same alert doesn't fire on every poll.
//
// Permission is requested lazily on first call; if the user denies, we silently
// stop trying. Threshold defaults to 85% — reasonable headroom before the
// hard 100% wall.

@MainActor
final class QuotaNotifier {
    static let shared = QuotaNotifier()

    private var permissionGranted: Bool?
    private var firedKeys: Set<String> = []

    private init() {}

    private var threshold: Double {
        SettingsStore.snapshot().notifyThreshold
    }

    private nonisolated var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    func evaluate(snapshot: RateLimitSnapshot) {
        var candidates: [(label: String, window: RateLimitSnapshot.Window, key: String)] = []
        if let p = snapshot.primary {
            candidates.append((
                label: "5-hour quota",
                window: p,
                key: dedupKey(bucket: "primary", name: nil, resetAt: p.resetAt)))
        }
        if let s = snapshot.secondary {
            candidates.append((
                label: "7-day quota",
                window: s,
                key: dedupKey(bucket: "secondary", name: nil, resetAt: s.resetAt)))
        }
        for extra in snapshot.additional {
            if let p = extra.primary {
                candidates.append((
                    label: "\(extra.limitName) (5h)",
                    window: p,
                    key: dedupKey(bucket: "primary", name: extra.limitName, resetAt: p.resetAt)))
            }
            if let s = extra.secondary {
                candidates.append((
                    label: "\(extra.limitName) (7d)",
                    window: s,
                    key: dedupKey(bucket: "secondary", name: extra.limitName, resetAt: s.resetAt)))
            }
        }

        for c in candidates where c.window.usedPercent >= threshold && !firedKeys.contains(c.key) {
            firedKeys.insert(c.key)
            Task { await fire(label: c.label, percent: c.window.usedPercent, resetAt: c.window.resetAt) }
        }
    }

    private func dedupKey(bucket: String, name: String?, resetAt: Date) -> String {
        "\(bucket)|\(name ?? "-")|\(Int(resetAt.timeIntervalSince1970))"
    }

    private func fire(label: String, percent: Double, resetAt: Date) async {
        if permissionGranted == nil {
            permissionGranted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard permissionGranted == true else { return }

        let content = UNMutableNotificationContent()
        content.title = "Codex usage \(Int(percent))%"
        let rf = RelativeDateTimeFormatter()
        rf.unitsStyle = .abbreviated
        let resetIn = rf.localizedString(for: resetAt, relativeTo: Date())
        content.body = "\(label) is at \(Int(percent))% — resets \(resetIn)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codexmonitor.quota.\(UUID().uuidString)",
            content: content,
            trigger: nil)
        try? await center.add(request)
    }
}
