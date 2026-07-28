import Foundation

/// JSON REST API behind the dashboard.
final class Api {
    private let store: Store

    init(store: Store) {
        self.store = store
    }

    static func json(_ obj: Any) -> Data {
        return (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? Data("{}".utf8)
    }

    private func parseBody(_ req: HttpRequest) -> [String: Any] {
        return (try? JSONSerialization.jsonObject(with: req.body, options: [])) as? [String: Any] ?? [:]
    }

    private func today() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    func handle(_ req: HttpRequest) -> (String, String, Data, [String: String]) {
        let ct = "application/json; charset=utf-8"

        switch (req.method, req.path) {

        case ("GET", "/api/status"):
            let counts = store.counts()
            let obj: [String: Any] = [
                "paused": Config.shared.paused,
                "capture_text": Config.shared.captureText,
                "capture_urls": Config.shared.captureURLs,
                "auto_revise": Config.shared.autoRevise,
                "embeddings": Embeddings.shared.available,
                "embeddings_model": Embeddings.shared.describe,
                "turbo_embeddings": Config.shared.turboEmbeddings,
                "openai_key_set": (Keychain.get("openai_api_key")?.isEmpty == false),
                "excluded_apps": Config.shared.excludedApps.sorted(),
                "video_sources": Config.shared.videoSources,
                "detection_log": Extractors.detectionLog,
                "date_order": Config.shared.dateOrder.rawValue,
                "model_assist": Config.shared.modelAssist,
                "model_status": ModelAssist.status,
                "account_paired": AccountPairing.shared.isPaired,
                "relay_enabled": Config.shared.relayEnabled,
                "launch_at_login": LoginItem.isEnabled,
                "port": Int(Config.shared.port),
                "token": store.apiToken,
                "counts": counts,
                "version": "1.0"
            ]
            return ("200 OK", ct, Api.json(obj), [:])

        case ("GET", "/api/overview"):
            let date = req.query["date"] ?? today()
            let stats = store.statsForDate(date)
            let focus = store.focusStatsForDate(date)
            let obj: [String: Any] = [
                "date": date,
                "active_secs": stats.active,
                "idle_secs": stats.idle,
                "focus_secs": focus.focus,
                "multitask_secs": focus.multitask,
                "event_count": store.eventCountForDate(date),
                "sessions": store.sessionsForDate(date),
                "top_apps": store.appStatsForDate(date),
                "categories": store.categoryStatsForDate(date)
            ]
            return ("200 OK", ct, Api.json(obj), [:])

        case ("GET", "/api/rules"):
            return ("200 OK", ct, Api.json(["rules": store.allRules(),
                                            "categories": Store.categories]), [:])

        case ("POST", "/api/rules"):
            let body = parseBody(req)
            let category = (body["category"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let app = (body["app"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let pattern = (body["title_pattern"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !category.isEmpty, !(app.isEmpty && pattern.isEmpty) else {
                return ("400 Bad Request", ct, Api.json(["error": "need category and app or title_pattern"]), [:])
            }
            // Forward-only unless the user ticked "also apply to past activity";
            // `retagged` is how many recorded events that opt-in actually moved.
            let backfill = body["backfill"] as? Bool ?? false
            let retagged = store.addRule(app: app, titlePattern: pattern,
                                         category: category, backfill: backfill)
            return ("200 OK", ct, Api.json(["ok": true, "retagged": retagged,
                                            "rules": store.allRules()]), [:])

        case ("POST", "/api/rules/delete"):
            let body = parseBody(req)
            guard let id = body["id"] as? Int else {
                return ("400 Bad Request", ct, Api.json(["error": "missing id"]), [:])
            }
            store.deleteRule(id: id)
            return ("200 OK", ct, Api.json(["ok": true, "rules": store.allRules()]), [:])

        case ("POST", "/api/categorize"):
            let body = parseBody(req)
            let title = (body["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let category = (body["category"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let app = (body["app"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, !category.isEmpty else {
                return ("400 Bad Request", ct, Api.json(["error": "need title and category"]), [:])
            }
            // The dashboard sends the row's own span along with the title. A
            // timeline row is a merged session — every tab visited in that app,
            // plus the stretches macOS reports with no title at all — and
            // tapping its chip is a statement about all of it, not just about
            // whichever tab happened to hold the screen longest.
            // The dashboard always sends the span; without one there is nothing
            // on screen being pointed at, so the tap only teaches the title
            // going forward and no recorded minutes move.
            let from = (body["from"] as? Double) ?? (body["from"] as? Int).map { Double($0) }
            let to = (body["to"] as? Double) ?? (body["to"] as? Int).map { Double($0) }
            if let f = from, let t = to, t > f {
                store.categorizeSession(app: app, title: title, category: category, from: f, to: t)
            } else {
                store.categorizeTitle(app: app, title: title, category: category)
            }
            return ("200 OK", ct, Api.json(["ok": true]), [:])

        case ("GET", "/api/report"):
            let days = min(max(req.query["days"].flatMap(Int.init) ?? 7, 1), 366)
            return ("200 OK", ct, Api.json(store.report(days: days)), [:])

        case ("GET", "/api/search"):
            let q = req.query["q"] ?? ""
            guard !q.isEmpty else {
                return ("400 Bad Request", ct, Api.json(["error": "missing q"]), [:])
            }
            let from = req.query["from"].flatMap(Double.init)
            let to = req.query["to"].flatMap(Double.init)
            let limit = req.query["limit"].flatMap(Int.init) ?? 20
            let results = store.search(query: q, from: from, to: to, limit: min(limit, 50))
            return ("200 OK", ct, Api.json(["query": q, "results": results]), [:])

        case ("GET", "/api/history"):
            // Calendar/history feed: watch events, revision outcomes, deadlines.
            let now = Date().timeIntervalSince1970
            let from = req.query["from"].flatMap(Double.init) ?? (now - 90 * 86400)
            let to = req.query["to"].flatMap(Double.init) ?? (now + 60 * 86400)
            guard to > from, to - from <= 400 * 86400 else {
                return ("400 Bad Request", ct, Api.json(["error": "bad range"]), [:])
            }
            return ("200 OK", ct, Api.json(["from": from, "to": to,
                                            "items": store.history(from: from, to: to)]), [:])

        case ("GET", "/api/calendar.ics"):
            // iCalendar feed of the upcoming schedule, for Google/Apple/Outlook.
            let ics = CalendarExport.ics(store: store)
            return ("200 OK", "text/calendar; charset=utf-8", Data(ics.utf8),
                    ["Content-Disposition": "attachment; filename=\"mitthuai-revisions.ics\""])

        case ("GET", "/api/brain"):
            let obj: [String: Any] = [
                "facts": store.openFacts(),
                "reminders": store.upcomingReminders(),
                "important": store.importantToday()
            ]
            return ("200 OK", ct, Api.json(obj), [:])

        case ("GET", "/api/digest"):
            let date = req.query["date"] ?? today()
            return ("200 OK", ct, Api.json(["date": date, "text": Digest.forDate(date, store: store)]), [:])

        case ("POST", "/api/fact"):
            let body = parseBody(req)
            let action = body["action"] as? String ?? ""
            switch action {
            case "create":
                let title = body["title"] as? String ?? ""
                guard !title.isEmpty else {
                    return ("400 Bad Request", ct, Api.json(["error": "missing title"]), [:])
                }
                let due = (body["due_ts"] as? Double) ?? (body["due_ts"] as? Int).map { Double($0) }
                let kind = body["kind"] as? String ?? "note"
                let id = store.addFact(kind: kind, title: title,
                                       detail: body["detail"] as? String ?? "",
                                       dueTs: due, source: "dashboard",
                                       note: body["note"] as? String ?? "")
                return ("200 OK", ct, Api.json(["ok": true, "id": id ?? -1]), [:])
            case "complete", "dismiss":
                guard let id = body["id"] as? Int else {
                    return ("400 Bad Request", ct, Api.json(["error": "missing id"]), [:])
                }
                store.setFactStatus(id: Int64(id), status: action == "complete" ? "done" : "dismissed")
                return ("200 OK", ct, Api.json(["ok": true]), [:])
            case "revise":
                guard let id = body["id"] as? Int else {
                    return ("400 Bad Request", ct, Api.json(["error": "missing id"]), [:])
                }
                store.addRevisionLadder(factId: Int64(id))
                return ("200 OK", ct, Api.json(["ok": true]), [:])
            case "model_fix":
                // Hand this one item to the on-device model to re-read.
                guard let id = body["id"] as? Int else {
                    return ("400 Bad Request", ct, Api.json(["error": "missing id"]), [:])
                }
                guard Config.shared.modelAssist, ModelAssist.isAvailable else {
                    return ("200 OK", ct, Api.json(["ok": false, "error": "on-device model is off or unavailable: \(ModelAssist.status)"]), [:])
                }
                guard let line = store.factDetail(id: Int64(id)), !line.isEmpty else {
                    return ("200 OK", ct, Api.json(["ok": false, "error": "no source text stored for this item"]), [:])
                }
                ModelAssist.refine(factId: Int64(id), line: line, store: store)
                return ("200 OK", ct, Api.json(["ok": true, "queued": true]), [:])
            case "due":
                // Correcting a date the extractor got wrong; null clears it.
                guard let id = body["id"] as? Int else {
                    return ("400 Bad Request", ct, Api.json(["error": "missing id"]), [:])
                }
                let due = (body["due_ts"] as? Double) ?? (body["due_ts"] as? Int).map { Double($0) }
                store.setFactDue(id: Int64(id), dueTs: due)
                return ("200 OK", ct, Api.json(["ok": true]), [:])
            case "note":
                // Your own subtitle for the item — "" clears it.
                guard let id = body["id"] as? Int else {
                    return ("400 Bad Request", ct, Api.json(["error": "missing id"]), [:])
                }
                store.setFactNote(id: Int64(id), note: body["note"] as? String ?? "")
                return ("200 OK", ct, Api.json(["ok": true]), [:])
            case "reminder_done":
                // Mark one revision step as actually completed (History tab).
                guard let id = body["id"] as? Int else {
                    return ("400 Bad Request", ct, Api.json(["error": "missing id"]), [:])
                }
                store.markReminderDone(id: Int64(id))
                return ("200 OK", ct, Api.json(["ok": true]), [:])
            default:
                return ("400 Bad Request", ct, Api.json(["error": "unknown action"]), [:])
            }

        case ("POST", "/api/settings"):
            let body = parseBody(req)
            if let v = body["paused"] as? Bool { Config.shared.paused = v }
            if let v = body["capture_text"] as? Bool { Config.shared.captureText = v }
            if let v = body["capture_urls"] as? Bool { Config.shared.captureURLs = v }
            if let v = body["auto_revise"] as? Bool { Config.shared.autoRevise = v }
            if let v = body["turbo_embeddings"] as? Bool { Config.shared.turboEmbeddings = v }
            // Registration can be refused, so store what macOS actually did.
            if let v = body["launch_at_login"] as? Bool {
                Config.shared.launchAtLogin = LoginItem.setEnabled(v)
            }
            if let v = body["excluded_apps"] as? [String] {
                Config.shared.excludedApps = Set(v.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            }
            if let v = body["video_sources"] as? [String] {
                Config.shared.videoSources = v.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            if let v = body["date_order"] as? String, let o = DateParse.Order(rawValue: v) {
                Config.shared.dateOrder = o
            }
            if let v = body["model_assist"] as? Bool { Config.shared.modelAssist = v }
            // OpenAI key is sensitive → Keychain, never the DB. "" clears it.
            if let k = body["openai_api_key"] as? String {
                Keychain.set("openai_api_key", k.trimmingCharacters(in: .whitespaces))
            }
            Config.shared.save()
            return ("200 OK", ct, Api.json(["ok": true]), [:])

        case ("POST", "/api/account/connect"):
            // Opens the browser to mitthuai.com sign-in and polls for the token.
            AccountPairing.shared.begin()
            return ("200 OK", ct, Api.json(["ok": true, "pairing_url": Config.shared.pairingURL]), [:])

        case ("POST", "/api/account/disconnect"):
            AccountPairing.shared.signOut()
            return ("200 OK", ct, Api.json(["ok": true]), [:])

        case ("POST", "/api/purge"):
            let body = parseBody(req)
            guard let from = body["from"] as? Double, let to = body["to"] as? Double else {
                return ("400 Bad Request", ct, Api.json(["error": "need from/to unix seconds"]), [:])
            }
            let n = store.purge(from: from, to: to)
            return ("200 OK", ct, Api.json(["ok": true, "chunks_deleted": n]), [:])

        default:
            return ("404 Not Found", ct, Api.json(["error": "not found"]), [:])
        }
    }
}
