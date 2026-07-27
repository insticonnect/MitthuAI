import Foundation

/// MCP (Model Context Protocol) endpoint — streamable HTTP transport.
/// Lets Claude Code / Claude Desktop / any MCP client query your memory:
///   claude mcp add --transport http mitthuai http://localhost:4789/mcp \
///     --header "Authorization: Bearer <token>"
final class McpServer {
    private let store: Store

    init(store: Store) {
        self.store = store
    }

    private static let protocolVersion = "2025-03-26"

    /// Retrieval playbook advertised to the client so it fetches comprehensively.
    private static let playbook = """
    MitthuAI is this user's on-device memory of everything they've seen and done \
    on their Mac (window text, titles, URLs, timeline, and extracted tasks). It \
    is the ONLY source of truth for the user's own recent activity — do not guess \
    or say you lack access; query it.

    Fetch more, not less:
    • When the user references past activity ("what did I", "that video/article/\
      doc", "where did I leave off", "the bill", "what was I working on"), call \
      search_memory FIRST, before answering.
    • Use MULTIPLE angles per question: pass several strings in `queries` (exact \
      terms, synonyms, people, the topic) rather than one narrow query. If results \
      look thin, broaden and try again.
    • Use get_timeline for "what did I do today/on <date>"; get_important for \
      "what's due / important now"; get_daily_digest for a day summary.
    • Respect time hints ("yesterday", "last week") via from/to.
    Synthesize across results; cite app/title/time; note if memory seems incomplete.
    """

    private static func tool(_ name: String, _ description: String,
                             properties: [String: [String: String]],
                             required: [String]) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema]
    }

    private static let toolDefs: [[String: Any]] = [
        tool("search_memory",
             "Semantic + keyword search over everything the user has seen on their Mac (window text, titles, URLs). Returns matching text with timestamps, app and window. Use for questions like 'when did I watch X', 'what was that article about Y'. Pass MULTIPLE angles in `queries` for best recall.",
             properties: [
                "query": ["type": "string", "description": "A single search string"],
                "queries": ["type": "array", "description": "Several search angles (exact terms, synonyms, people, topic) — preferred over a single query for recall"],
                "from": ["type": "string", "description": "Optional ISO date/datetime lower bound, e.g. 2026-07-20"],
                "to": ["type": "string", "description": "Optional ISO date/datetime upper bound"],
                "limit": ["type": "integer", "description": "Max results (default 10)"]
             ],
             required: []),
        tool("get_timeline",
             "The user's activity timeline for a day: sessions (app, window, start/end, duration), screen-time stats, top apps. Use for 'what did I do today/on <date>'.",
             properties: ["date": ["type": "string", "description": "Day as YYYY-MM-DD (default: today)"]],
             required: []),
        tool("get_important",
             "What needs the user's attention: open bills/deadlines due soon or overdue, and spaced-repetition revisions firing today. Use for 'what's important today', 'what do I need to do'.",
             properties: [:],
             required: []),
        tool("get_daily_digest",
             "A readable end-of-day review for a date: screen time, categories, top apps, watched videos, pending items.",
             properties: ["date": ["type": "string", "description": "Day as YYYY-MM-DD (default: today)"]],
             required: []),
        tool("create_reminder",
             "Create a reminder/task in the user's brain. Provide either an ISO due date or days_from_now.",
             properties: [
                "title": ["type": "string"],
                "detail": ["type": "string"],
                "note": ["type": "string", "description": "Short subtitle shown under the title in Brain, the calendar and the reminder notification"],
                "due": ["type": "string", "description": "ISO date e.g. 2026-07-26"],
                "days_from_now": ["type": "number"]
             ],
             required: ["title"]),
        tool("complete_item",
             "Mark a fact/task/reminder item done by its id.",
             properties: ["id": ["type": "integer"]],
             required: ["id"]),
        tool("add_revision",
             "Enroll a fact (e.g. a watched lecture) into the spaced-repetition ladder (reminders after 1, 3, 7, 14, 30 days).",
             properties: ["id": ["type": "integer"]],
             required: ["id"])
    ]

    /// HTTP transport entry point (used by the local server).
    func handle(_ req: HttpRequest) -> (String, String, Data, [String: String]) {
        let ct = "application/json; charset=utf-8"
        guard req.method == "POST" else {
            return ("405 Method Not Allowed", ct, Data(#"{"error":"POST only"}"#.utf8), [:])
        }
        guard let msg = (try? JSONSerialization.jsonObject(with: req.body, options: [])) as? [String: Any] else {
            return ("400 Bad Request", ct, rpcError(id: nil, code: -32700, message: "parse error"), [:])
        }
        guard let data = dispatch(msg) else {
            return ("202 Accepted", ct, Data(), [:])   // notification, no response body
        }
        return ("200 OK", ct, data, [:])
    }

    /// Relay transport entry point: takes a raw JSON-RPC message and returns the
    /// response bytes (nil for notifications). Shared dispatch with HTTP.
    func processRPC(_ data: Data) -> Data? {
        guard let msg = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return rpcError(id: nil, code: -32700, message: "parse error")
        }
        return dispatch(msg)
    }

    /// Single dispatch shared by both transports. Returns response bytes, or
    /// nil for notifications (which have no reply).
    private func dispatch(_ msg: [String: Any]) -> Data? {
        let id = msg["id"]
        let method = msg["method"] as? String ?? ""
        let params = msg["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? Self.protocolVersion
            let result: [String: Any] = [
                "protocolVersion": requested,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "mitthuai", "version": "1.0"],
                "instructions": Self.playbook
            ]
            return rpcResult(id: id, result: result)

        case "notifications/initialized", "notifications/cancelled":
            return nil

        case "ping":
            return rpcResult(id: id, result: [:] as [String: Any])

        case "tools/list":
            return rpcResult(id: id, result: ["tools": Self.toolDefs])

        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            let text = callTool(name: name, args: args)
            let result: [String: Any] = [
                "content": [["type": "text", "text": text]],
                "isError": false
            ]
            return rpcResult(id: id, result: result)

        default:
            return rpcError(id: id, code: -32601, message: "method not found: \(method)")
        }
    }

    // MARK: - Tool implementations

    private func callTool(name: String, args: [String: Any]) -> String {
        switch name {
        case "search_memory":
            var queries: [String] = []
            if let arr = args["queries"] as? [Any] {
                queries = arr.compactMap { $0 as? String }
            }
            if let q = args["query"] as? String, !q.isEmpty { queries.append(q) }
            queries = queries.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !queries.isEmpty else { return "Error: provide `query` or `queries`." }
            let from = (args["from"] as? String).flatMap(Self.parseISO)
            let to = (args["to"] as? String).flatMap(Self.parseISO)
            let limit = (args["limit"] as? Int) ?? 10
            let results = store.search(queries: queries, from: from, to: to, limit: min(limit, 30))
            let label = queries.joined(separator: " / ")
            if results.isEmpty { return "No matches in memory for \"\(label)\"." }
            var out = "Memory matches for \"\(label)\":\n"
            for r in results {
                out += "\n[\(Self.fmt(r.double("ts")))] \(r.str("app")) — \(r.str("title"))"
                let url = r.str("url")
                if !url.isEmpty { out += "\n  url: \(url)" }
                out += "\n  \(r.str("snippet").replacingOccurrences(of: "\n", with: " ").prefix(300))\n"
            }
            return out

        case "get_timeline":
            let date = (args["date"] as? String) ?? Self.todayStr()
            let stats = store.statsForDate(date)
            let sessions = store.sessionsForDate(date)
            var out = "Timeline for \(date) — active \(Digest.formatDuration(stats.active)), idle \(Digest.formatDuration(stats.idle)):\n"
            for s in sessions {
                let start = Self.fmtTime(s.double("ts_start"))
                let end = Self.fmtTime(s.double("ts_end"))
                let title = s.str("title")
                out += "\n\(start)–\(end)  \(s.str("app"))"
                if !title.isEmpty { out += ": \(title)" }
                out += " (\(Digest.formatDuration(s.double("duration"))))"
            }
            if sessions.isEmpty { out += "\n(no activity logged)" }
            return out

        case "get_important":
            let imp = store.importantToday()
            let dueSoon = imp["due_soon"] as? [[String: Any]] ?? []
            let revisions = imp["revisions_today"] as? [[String: Any]] ?? []
            if dueSoon.isEmpty && revisions.isEmpty {
                return "Nothing urgent: no bills/deadlines due soon and no revisions scheduled today."
            }
            var out = "Important now:\n"
            // The user's own note on an item says what the page title didn't.
            func note(_ row: [String: Any]) -> String {
                let n = row.str("note")
                return n.isEmpty ? "" : " — note: \(n)"
            }
            for f in dueSoon {
                let due = f.double("due_ts")
                let overdue = due < Date().timeIntervalSince1970 ? " (OVERDUE)" : ""
                out += "\n• [id \(f.int("id"))] \(f.str("kind")): \(f.str("title")) — due \(Self.fmt(due))\(overdue)\(note(f))"
            }
            for r in revisions {
                out += "\n• [id \(r.int("fact_id"))] revise: \(r.str("title"))\(note(r))"
            }
            return out

        case "get_daily_digest":
            let date = (args["date"] as? String) ?? Self.todayStr()
            return Digest.forDate(date, store: store)

        case "create_reminder":
            let title = args["title"] as? String ?? ""
            guard !title.isEmpty else { return "Error: title is required." }
            var due: Double? = nil
            if let d = args["due"] as? String { due = Self.parseISO(d) }
            if due == nil, let days = args["days_from_now"] as? Double {
                due = Date().timeIntervalSince1970 + days * 86400
            }
            if due == nil, let days = args["days_from_now"] as? Int {
                due = Date().timeIntervalSince1970 + Double(days) * 86400
            }
            let id = store.addFact(kind: "note", title: title,
                                   detail: args["detail"] as? String ?? "",
                                   dueTs: due, source: "mcp",
                                   note: args["note"] as? String ?? "")
            if let id = id {
                var out = "Created reminder [id \(id)]: \(title)"
                if let d = due { out += ", due \(Self.fmt(d))" }
                return out
            }
            return "A reminder with that title already exists."

        case "complete_item":
            guard let id = args["id"] as? Int else { return "Error: id is required." }
            store.setFactStatus(id: Int64(id), status: "done")
            return "Marked item \(id) as done."

        case "add_revision":
            guard let id = args["id"] as? Int else { return "Error: id is required." }
            store.addRevisionLadder(factId: Int64(id))
            return "Item \(id) enrolled in spaced repetition (reminders after 1, 3, 7, 14, 30 days)."

        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - Helpers

    private func rpcResult(id: Any?, result: [String: Any]) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "result": result]
        obj["id"] = id ?? NSNull()
        return Api.json(obj)
    }

    private func rpcError(id: Any?, code: Int, message: String) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        obj["id"] = id ?? NSNull()
        return Api.json(obj)
    }

    static func parseISO(_ s: String) -> Double? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d.timeIntervalSince1970 }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        if let d = fmt.date(from: s) { return d.timeIntervalSince1970 }
        return nil
    }

    static func todayStr() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    /// 12-hour clock with AM/PM. The POSIX locale keeps the format fixed even
    /// on Macs set to a 24-hour region, where `h:mm a` would otherwise be
    /// rewritten to a 24-hour pattern.
    private static func clockFormatter(_ pattern: String) -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = pattern
        return fmt
    }

    static func fmt(_ ts: Double) -> String {
        return clockFormatter("yyyy-MM-dd h:mm a").string(from: Date(timeIntervalSince1970: ts))
    }

    static func fmtTime(_ ts: Double) -> String {
        return clockFormatter("h:mm a").string(from: Date(timeIntervalSince1970: ts))
    }
}
