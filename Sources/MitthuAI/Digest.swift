import Foundation

/// Rule-based daily review: what you did, watched, and what's pending.
enum Digest {

    static func formatDuration(_ secs: Double) -> String {
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func forDate(_ dateStr: String, store: Store) -> String {
        let stats = store.statsForDate(dateStr)
        let apps = store.appStatsForDate(dateStr)
        let cats = store.categoryStatsForDate(dateStr)
        let sessions = store.sessionsForDate(dateStr)

        var lines: [String] = []
        lines.append("Daily review — \(dateStr)")
        lines.append("")
        lines.append("Screen time: \(formatDuration(stats.active)) active, \(formatDuration(stats.idle)) idle.")

        if !cats.isEmpty {
            let catLine = cats.prefix(5)
                .map { "\($0.str("category")) \(formatDuration($0.double("total")))" }
                .joined(separator: " · ")
            lines.append("By category: \(catLine)")
        }

        if !apps.isEmpty {
            lines.append("")
            lines.append("Top apps:")
            for a in apps.prefix(6) {
                lines.append("  • \(a.str("app")) — \(formatDuration(a.double("total")))")
            }
        }

        let watched = sessions.filter {
            Extractors.knownVideoSource(($0.str("title") + " " + $0.str("app") + " " + $0.str("url")).lowercased())
        }
        if !watched.isEmpty {
            lines.append("")
            lines.append("Watched:")
            for w in watched.prefix(6) {
                lines.append("  • \(w.str("title")) (\(formatDuration(w.double("duration"))))")
            }
        }

        let important = store.importantToday()
        let dueSoon = important["due_soon"] as? [[String: Any]] ?? []
        let revisions = important["revisions_today"] as? [[String: Any]] ?? []
        if !dueSoon.isEmpty || !revisions.isEmpty {
            lines.append("")
            lines.append("Needs attention:")
            for f in dueSoon.prefix(5) {
                lines.append("  ! \(f.str("kind")): \(f.str("title"))")
            }
            for r in revisions.prefix(5) {
                lines.append("  ↻ revise: \(r.str("title"))")
            }
        }

        lines.append("")
        lines.append("\(sessions.count) activity sessions logged.")
        return lines.joined(separator: "\n")
    }
}
