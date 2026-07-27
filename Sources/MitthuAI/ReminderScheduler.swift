import Foundation
import UserNotifications

/// Fires due reminders as macOS notifications (spaced-repetition revisions,
/// bill/deadline nudges). Checks the queue once a minute.
final class ReminderScheduler {
    private let store: Store
    private var timer: Timer?
    private var notificationsAllowed = false

    init(store: Store) {
        self.store = store
    }

    func start() {
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
                self?.notificationsAllowed = granted
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.check()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let now = Date().timeIntervalSince1970
        for r in store.pendingReminders(before: now) {
            let reminderId = Int64(r.int("reminder_id"))
            let kind = r.str("kind")
            let title = r.str("title")
            let idx = r.int("interval_idx")

            let (header, body): (String, String)
            switch kind {
            case "watched":
                let stage = idx >= 0 ? " (revision \(idx + 1))" : ""
                (header, body) = ("Time to revise\(stage)", title)
            case "bill":
                (header, body) = ("Bill due", title)
            case "deadline":
                (header, body) = ("Deadline approaching", title)
            default:
                (header, body) = ("Reminder", title)
            }

            deliver(header: header, body: body, note: r.str("note"),
                    id: "mitthuai-reminder-\(reminderId)")
            store.markReminderFired(id: reminderId)
        }
    }

    private func deliver(header: String, body: String, note: String, id: String) {
        guard notificationsAllowed, Bundle.main.bundleIdentifier != nil else {
            print("MitthuAI Reminder (notifications off): \(header) — \(body)\(note.isEmpty ? "" : " — \(note)")")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = header
        // The note you wrote in Brain — the nudge says *which* lecture it means.
        if !note.isEmpty { content.subtitle = note }
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let e = error { print("MitthuAI Reminder delivery error: \(e)") }
        }
    }
}
