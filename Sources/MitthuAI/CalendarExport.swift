import Foundation

/// Builds an iCalendar (.ics) feed of every upcoming revision and deadline so
/// the schedule can be imported into Google Calendar (Settings → Import &
/// export), Apple Calendar, or Outlook. Pure text output — no OAuth, no
/// network; the data never leaves the file the user downloads.
enum CalendarExport {

    static func ics(store: Store) -> String {
        let rows = store.db.query("""
            SELECT r.id AS reminder_id, r.fire_ts, r.interval_idx, f.kind, f.title, f.detail
            FROM reminders r JOIN facts f ON f.id = r.fact_id
            WHERE r.status = 'pending' AND f.status = 'open'
            ORDER BY r.fire_ts ASC LIMIT 500
            """)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let stamp = fmt.string(from: Date())

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//MitthuAI//Revision Schedule//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:MitthuAI — Revisions & Deadlines"
        ]

        for r in rows {
            let fire = Date(timeIntervalSince1970: r.double("fire_ts"))
            let idx = r.int("interval_idx")
            let title = String(r.str("title").prefix(120))
            let summary: String
            var detail: String
            if idx >= 0 {
                summary = "Revise (\(idx + 1)/5): \(title)"
                detail = "Spaced-repetition revision \(idx + 1) of 5, scheduled by MitthuAI."
            } else if r.str("kind") == "bill" {
                summary = "Bill: \(title)"
                detail = "Bill reminder scheduled by MitthuAI."
            } else {
                summary = "Deadline: \(title)"
                detail = "Deadline reminder scheduled by MitthuAI."
            }
            // If the source is a video, link it so the event opens the video.
            let link = r.str("detail")
            let hasLink = link.hasPrefix("http://") || link.hasPrefix("https://")
            if hasLink { detail += "\n" + link }
            lines += [
                "BEGIN:VEVENT",
                "UID:mitthuai-reminder-\(r.int("reminder_id"))@mitthuai.local",
                "DTSTAMP:\(stamp)",
                "DTSTART:\(fmt.string(from: fire))",
                "DTEND:\(fmt.string(from: fire.addingTimeInterval(1800)))",
                "SUMMARY:\(escape(summary))"]
            if hasLink { lines.append("URL:\(link)") }
            lines += [
                "DESCRIPTION:\(escape(detail))",
                "BEGIN:VALARM",
                "ACTION:DISPLAY",
                "DESCRIPTION:\(escape(summary))",
                "TRIGGER:-PT0M",
                "END:VALARM",
                "END:VEVENT"
            ]
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 5545 text escaping for SUMMARY/DESCRIPTION values.
    private static func escape(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
