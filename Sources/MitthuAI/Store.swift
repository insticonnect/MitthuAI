import Foundation
import Security

/// All persistence for MitthuAI: activity events, captured text chunks
/// (with FTS5 + vector index), extracted facts, and reminders.
final class Store {
    let db: SQLiteDB
    let dataDir: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDir = appSupport.appendingPathComponent("MitthuAI")
        try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true, attributes: nil)
        db = SQLiteDB(path: dataDir.appendingPathComponent("mitthuai.db").path)
        migrate()
        ensureToken()
    }

    private func migrate() {
        db.exec("""
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts_start REAL, ts_end REAL, duration REAL,
            app TEXT, title TEXT, url TEXT,
            is_idle INTEGER DEFAULT 0,
            category TEXT DEFAULT 'Uncategorized'
        );
        CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts_start);

        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL, app TEXT, title TEXT, url TEXT,
            text TEXT, hash TEXT UNIQUE
        );
        CREATE INDEX IF NOT EXISTS idx_chunks_ts ON chunks(ts);

        CREATE TABLE IF NOT EXISTS embeddings (
            chunk_id INTEGER PRIMARY KEY REFERENCES chunks(id) ON DELETE CASCADE,
            dim INTEGER, vec BLOB, model TEXT DEFAULT ''
        );

        CREATE TABLE IF NOT EXISTS facts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT, title TEXT, detail TEXT,
            due_ts REAL, created_ts REAL,
            source TEXT, status TEXT DEFAULT 'open',
            done_ts REAL,                       -- when it was marked done
            note TEXT DEFAULT '',               -- your own subtitle for it
            watch_secs REAL DEFAULT 0,          -- time actually spent watching
            needs_review INTEGER DEFAULT 0      -- a date we weren't sure of
        );

        CREATE TABLE IF NOT EXISTS reminders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fact_id INTEGER REFERENCES facts(id) ON DELETE CASCADE,
            fire_ts REAL, interval_idx INTEGER DEFAULT 0,
            status TEXT DEFAULT 'pending',
            done_ts REAL                        -- when the revision was done
        );
        CREATE INDEX IF NOT EXISTS idx_reminders_fire ON reminders(fire_ts);

        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);

        CREATE TABLE IF NOT EXISTS rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app TEXT DEFAULT '',
            title_pattern TEXT DEFAULT '',
            category TEXT
        );
        """)

        // Hand-tagged events. Tapping a category chip on a timeline row is a
        // statement about that stretch of the day, not a guess — so it is
        // marked, and rule churn afterwards leaves it alone.
        if !columnExists(table: "events", column: "manual_category") {
            db.exec("ALTER TABLE events ADD COLUMN manual_category INTEGER DEFAULT 0;")
        }

        db.exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(text, content='chunks', content_rowid='id');
        """)
        db.exec("""
        CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
            INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text);
        END;
        """)
        db.exec("""
        CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
            INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES ('delete', old.id, old.text);
        END;
        """)

        seedDefaultRules()
    }

    private func columnExists(table: String, column: String) -> Bool {
        return db.query("PRAGMA table_info(\(table))").contains { $0.str("name") == column }
    }

    // MARK: - Categorization rules (user-defined)

    /// The canonical category set the dashboard organizes around. Users can
    /// type any category on a rule, but these are the suggested buckets.
    static let categories = ["Study", "Entertainment", "Work", "Other"]
    static let focusCategories: Set<String> = ["Study", "Work", "Coding", "Writing"]

    private func seedDefaultRules() {
        let count = db.query("SELECT COUNT(*) AS n FROM rules").first?.int("n") ?? 0
        guard count == 0, setting("rules_seeded") == nil else { return }
        let defaults: [(String, String, String)] = [
            ("Xcode", "", "Study"),
            ("Visual Studio Code", "", "Study"),
            ("Code", "", "Study"),
            ("Terminal", "", "Study"),
            ("Safari", "YouTube", "Entertainment"),
            ("Google Chrome", "YouTube", "Entertainment"),
            ("Safari", "Netflix", "Entertainment"),
            ("Google Chrome", "Netflix", "Entertainment"),
            ("Spotify", "", "Entertainment"),
            ("Slack", "", "Work"),
            ("Microsoft Teams", "", "Work"),
            ("Zoom", "", "Work")
        ]
        for r in defaults {
            db.run("INSERT INTO rules (app, title_pattern, category) VALUES (?, ?, ?)", [r.0, r.1, r.2])
        }
        setSetting("rules_seeded", "1")
    }

    func allRules() -> [[String: Any]] {
        return db.query("SELECT id, app, title_pattern, category FROM rules ORDER BY id ASC")
    }

    /// Category for an app/title: user rules win, choosing the most specific
    /// (app-matched, then longest title pattern) and, on a tie, the newest rule.
    /// Falls back to the built-in heuristic.
    func categoryFor(app: String, title: String, url: String? = nil) -> String {
        let rows = db.query("""
            SELECT category FROM rules
            WHERE (app = ? AND title_pattern != '' AND ? LIKE '%' || title_pattern || '%')
               OR (app = ? AND title_pattern = '')
               OR (app = '' AND title_pattern != '' AND ? LIKE '%' || title_pattern || '%')
            ORDER BY (app != '') DESC, (title_pattern != '') DESC, LENGTH(title_pattern) DESC, id DESC
            LIMIT 1
            """, [app, title, app, title])
        if let cat = rows.first?.str("category"), !cat.isEmpty { return cat }
        return Extractors.heuristicCategory(app: app, title: title, url: url)
    }

    /// Add a rule, then retroactively re-tag matching past events. Also pulls
    /// in same-title activity within ±10 minutes of any match (so a video you
    /// flicked away from and back to lands in one category). Stretches the user
    /// tagged by hand are left alone — a rule is a general statement, a chip tap
    /// is a specific one, and the specific one wins.
    func addRule(app: String, titlePattern: String, category: String) {
        db.run("INSERT INTO rules (app, title_pattern, category) VALUES (?, ?, ?)",
               [app, titlePattern, category])

        var conds: [String] = []
        var params: [Any?] = [category]
        if !app.isEmpty { conds.append("app = ?"); params.append(app) }
        if !titlePattern.isEmpty { conds.append("title LIKE '%' || ? || '%'"); params.append(titlePattern) }
        guard !conds.isEmpty else { return }
        let whereClause = conds.joined(separator: " AND ")

        db.run("UPDATE events SET category = ? WHERE is_idle = 0 AND manual_category = 0 AND \(whereClause)", params)

        // ±10-minute same-title expansion.
        let matched = db.query("SELECT DISTINCT title, ts_start, ts_end FROM events WHERE is_idle = 0 AND \(whereClause)",
                               Array(params.dropFirst()))
        for m in matched {
            let title = m.str("title")
            guard !title.isEmpty else { continue }
            db.run("""
                UPDATE events SET category = ?
                WHERE is_idle = 0 AND manual_category = 0 AND title = ?
                  AND ts_start >= ? AND ts_start <= ?
                """, [category, title, m.double("ts_start") - 600, m.double("ts_end") + 600])
        }
    }

    /// Tag a single observed title directly ("this video is Study"): REPLACES any
    /// existing rule for that exact app+title (so re-tapping a different category
    /// actually switches it, instead of stacking a conflicting rule), then
    /// re-tags matching history. The title's own events are marked hand-tagged,
    /// so a broader rule — including the built-in "Safari + YouTube →
    /// Entertainment" — can never take this title back off you.
    func categorizeTitle(app: String, title: String, category: String) {
        // Drop any prior exact-title rule for this app so only one wins.
        db.run("DELETE FROM rules WHERE app = ? AND title_pattern = ?", [app, title])
        addRule(app: app, titlePattern: title, category: category)
        // Directly re-tag this exact title too (covers app-agnostic matches and
        // ensures an immediate switch even if the LIKE expansion missed edges).
        if app.isEmpty {
            db.run("UPDATE events SET category = ?, manual_category = 1 WHERE is_idle = 0 AND title = ?",
                   [category, title])
        } else {
            db.run("UPDATE events SET category = ?, manual_category = 1 WHERE is_idle = 0 AND app = ? AND title = ?",
                   [category, app, title])
        }
    }

    /// What tapping a chip on a timeline row actually means: *this stretch of my
    /// day was Study*. A row is a merged session, not one title — it holds every
    /// tab visited in that app, plus the stretches macOS reports with no title at
    /// all (which is what a video playing fullscreen looks like). Tagging only the
    /// headline title moved a fraction of the row's minutes and left the rest
    /// counted as whatever they were, so a row could read "Study" while the donut
    /// and the focus score still called it Other. Everything inside the row's own
    /// span moves together, and the headline title still becomes a rule so the
    /// same page is categorized on sight next time.
    func categorizeSession(app: String, title: String, category: String,
                           from: Double, to: Double) {
        categorizeTitle(app: app, title: title, category: category)
        guard to > from else { return }
        var sql = """
            UPDATE events SET category = ?, manual_category = 1
            WHERE is_idle = 0 AND ts_start >= ? AND ts_start <= ?
            """
        var params: [Any?] = [category, from, to]
        if !app.isEmpty { sql += " AND app = ?"; params.append(app) }
        db.run(sql, params)
    }

    func deleteRule(id: Int) {
        // Deleting the very rule a chip tap created is the user taking that tap
        // back, so those events give up their hand-tagged protection and fall
        // back to whatever the remaining rules say.
        if let r = db.query("SELECT app, title_pattern FROM rules WHERE id = ?", [id]).first {
            let app = r.str("app"), pattern = r.str("title_pattern")
            if !pattern.isEmpty && app.isEmpty {
                db.run("UPDATE events SET manual_category = 0 WHERE title = ?", [pattern])
            } else if !pattern.isEmpty {
                db.run("UPDATE events SET manual_category = 0 WHERE app = ? AND title = ?", [app, pattern])
            }
        }
        db.run("DELETE FROM rules WHERE id = ?", [id])
        recategorizeAll()
    }

    /// Recompute every non-idle event's category from the current rule set,
    /// leaving hand-tagged stretches as the user set them.
    private func recategorizeAll() {
        let events = db.query("SELECT id, app, title, url FROM events WHERE is_idle = 0 AND manual_category = 0")
        for e in events {
            let cat = categoryFor(app: e.str("app"), title: e.str("title"), url: e.str("url"))
            db.run("UPDATE events SET category = ? WHERE id = ?", [cat, e.int("id")])
        }
    }

    func focusStatsForDate(_ dateStr: String) -> (focus: Double, multitask: Double) {
        let (s, e) = dayBounds(dateStr)
        var focus = 0.0, multi = 0.0
        for row in db.query("""
            SELECT category, SUM(duration) AS total FROM events
            WHERE ts_start >= ? AND ts_start < ? AND is_idle = 0
            GROUP BY category
            """, [s, e]) {
            if Store.focusCategories.contains(row.str("category")) { focus += row.double("total") }
            else { multi += row.double("total") }
        }
        return (focus, multi)
    }

    func eventCountForDate(_ dateStr: String) -> Int {
        let (s, e) = dayBounds(dateStr)
        return db.query("SELECT COUNT(*) AS n FROM events WHERE ts_start >= ? AND ts_start < ?", [s, e]).first?.int("n") ?? 0
    }

    /// Multi-day report for the Trends view: per-day active/idle/focus/multitask,
    /// period totals, the preceding-period totals (for the "vs last period"
    /// deltas), and category totals across the whole range.
    func report(days: Int) -> [String: Any] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current

        var daily: [[String: Any]] = []
        var tActive = 0.0, tIdle = 0.0, tFocus = 0.0, tMulti = 0.0
        var catTotals: [String: Double] = [:]

        for i in stride(from: days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let ds = fmt.string(from: d)
            let s = statsForDate(ds)
            let f = focusStatsForDate(ds)
            daily.append(["date": ds, "active": s.active, "idle": s.idle,
                          "focus": f.focus, "multitask": f.multitask])
            tActive += s.active; tIdle += s.idle; tFocus += f.focus; tMulti += f.multitask
            for row in categoryStatsForDate(ds) {
                catTotals[row.str("category"), default: 0] += row.double("total")
            }
        }

        // Preceding period of the same length, for comparison.
        var pActive = 0.0, pIdle = 0.0, pFocus = 0.0, pMulti = 0.0
        for i in 0..<days {
            guard let d = cal.date(byAdding: .day, value: -(days + i), to: today) else { continue }
            let ds = fmt.string(from: d)
            let s = statsForDate(ds)
            let f = focusStatsForDate(ds)
            pActive += s.active; pIdle += s.idle; pFocus += f.focus; pMulti += f.multitask
        }

        let categories = catTotals
            .map { ["category": $0.key, "total": $0.value] as [String: Any] }
            .sorted { ($0["total"] as? Double ?? 0) > ($1["total"] as? Double ?? 0) }

        return [
            "days": days,
            "daily": daily,
            "totals": ["active": tActive, "idle": tIdle, "focus": tFocus, "multitask": tMulti],
            "prior": ["active": pActive, "idle": pIdle, "focus": pFocus, "multitask": pMulti],
            "categories": categories
        ]
    }

    // MARK: - Settings / token

    func setting(_ key: String) -> String? {
        return db.query("SELECT value FROM settings WHERE key = ?", [key]).first?.str("value")
    }

    func setSetting(_ key: String, _ value: String) {
        db.run("INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [key, value])
    }

    private func ensureToken() {
        if setting("api_token") == nil {
            var bytes = [UInt8](repeating: 0, count: 24)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let token = bytes.map { String(format: "%02x", $0) }.joined()
            setSetting("api_token", token)
        }
    }

    var apiToken: String { setting("api_token") ?? "" }

    // MARK: - Events

    func insertEvent(app: String, title: String, url: String?, start: Date, end: Date, isIdle: Bool) {
        let duration = end.timeIntervalSince(start)
        guard duration > 0.5 else { return }
        let category = isIdle ? "Idle" : categoryFor(app: app, title: title, url: url)
        db.run("""
            INSERT INTO events (ts_start, ts_end, duration, app, title, url, is_idle, category)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, [start.timeIntervalSince1970, end.timeIntervalSince1970, duration,
                  app, title, url, isIdle, category])
    }

    private func dayBounds(_ dateStr: String) -> (Double, Double) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        let date = fmt.date(from: dateStr) ?? Date()
        let start = Calendar.current.startOfDay(for: date)
        return (start.timeIntervalSince1970, start.timeIntervalSince1970 + 86400)
    }

    func statsForDate(_ dateStr: String) -> (active: Double, idle: Double) {
        let (s, e) = dayBounds(dateStr)
        var active = 0.0, idle = 0.0
        for row in db.query("SELECT is_idle, SUM(duration) AS total FROM events WHERE ts_start >= ? AND ts_start < ? GROUP BY is_idle", [s, e]) {
            if row.int("is_idle") == 1 { idle = row.double("total") } else { active += row.double("total") }
        }
        return (active, idle)
    }

    func appStatsForDate(_ dateStr: String) -> [[String: Any]] {
        let (s, e) = dayBounds(dateStr)
        return db.query("""
            SELECT app, SUM(duration) AS total FROM events
            WHERE ts_start >= ? AND ts_start < ? AND is_idle = 0
            GROUP BY app ORDER BY total DESC LIMIT 12
            """, [s, e])
    }

    func categoryStatsForDate(_ dateStr: String) -> [[String: Any]] {
        let (s, e) = dayBounds(dateStr)
        return db.query("""
            SELECT category, SUM(duration) AS total FROM events
            WHERE ts_start >= ? AND ts_start < ? AND is_idle = 0
            GROUP BY category ORDER BY total DESC
            """, [s, e])
    }

    /// Merge raw events into human-level sessions: consecutive events in the
    /// same app (gap < 3 min) collapse into one block.
    func sessionsForDate(_ dateStr: String) -> [[String: Any]] {
        let (s, e) = dayBounds(dateStr)
        let events = db.query("""
            SELECT ts_start, ts_end, duration, app, title, url, is_idle, category FROM events
            WHERE ts_start >= ? AND ts_start < ? ORDER BY ts_start ASC
            """, [s, e])

        // One merged same-app session. Seconds are tallied per tab title so the
        // finished session is fronted by the title that actually dominated it,
        // not whichever tab happened to come last. App switches never merge —
        // only tabs get this mercy.
        struct Session {
            var app = "", isIdle = false
            var tsStart = 0.0, tsEnd = 0.0, duration = 0.0
            var titles: [String] = []                                       // first-appearance order
            var perTitle: [String: (secs: Double, category: String, url: String)] = [:]
            var perCategory: [String: Double] = [:]                         // seconds by category, EVERY event
            var fallbackCategory = "", fallbackURL = ""                     // for title-less sessions (Idle, bare windows)

            mutating func absorb(_ ev: [String: Any]) {
                tsEnd = ev.double("ts_end")
                duration += ev.double("duration")
                // Tallied for every event, titled or not. A video playing
                // fullscreen reports no window title, and those minutes used to
                // fall out of the row's category altogether — which is how a row
                // could show "Study" while most of its time was still being
                // counted as something else.
                let category = ev.str("category")
                if !category.isEmpty { perCategory[category, default: 0] += ev.double("duration") }
                let title = ev.str("title")
                guard !title.isEmpty else { return }
                if !titles.contains(title) && titles.count < 8 { titles.append(title) }
                var t = perTitle[title] ?? (0, ev.str("category"), ev.str("url"))
                t.secs += ev.double("duration")
                t.category = ev.str("category")
                if !ev.str("url").isEmpty { t.url = ev.str("url") }
                perTitle[title] = t
            }

            // Title and url follow the dominant tab, so the row reads as the
            // thing that actually held the screen (ties go to the earlier-seen
            // title). The *category* follows the seconds instead — whichever
            // bucket owns most of the row — so the chip on show and the donut
            // beside it can never tell two different stories. A tie goes to the
            // headline title's own category.
            var asDict: [String: Any] {
                let top = perTitle.max { a, b in
                    a.value.secs != b.value.secs
                        ? a.value.secs < b.value.secs
                        : (titles.firstIndex(of: a.key) ?? 0) > (titles.firstIndex(of: b.key) ?? 0)
                }
                var category = top?.value.category ?? fallbackCategory
                var best = perCategory[category] ?? 0
                for (name, secs) in perCategory.sorted(by: { $0.key < $1.key }) where secs > best {
                    category = name
                    best = secs
                }
                return [
                    "app": app,
                    "title": top?.key ?? "",
                    "titles": titles,
                    "ts_start": tsStart,
                    "ts_end": tsEnd,
                    "duration": duration,
                    "category": category,
                    "category_secs": perCategory,
                    "url": top?.value.url ?? fallbackURL,
                    "is_idle": isIdle
                ]
            }
        }

        var sessions: [[String: Any]] = []
        var cur: Session? = nil
        for ev in events {
            let isIdle = ev.int("is_idle") == 1
            let app = isIdle ? "Idle" : ev.str("app")
            if var c = cur, c.app == app, ev.double("ts_start") - c.tsEnd < 180 {
                c.absorb(ev)
                cur = c
            } else {
                if let c = cur { sessions.append(c.asDict) }
                var next = Session()
                next.app = app
                next.isIdle = isIdle
                next.tsStart = ev.double("ts_start")
                next.fallbackCategory = ev.str("category")
                next.fallbackURL = ev.str("url")
                next.absorb(ev)
                cur = next
            }
        }
        if let c = cur { sessions.append(c.asDict) }
        // Drop micro-sessions under 15 seconds to keep the timeline readable.
        return sessions.filter { $0.double("duration") >= 15 }
    }

    // MARK: - Chunks (captured text) + hybrid search

    /// Insert a captured text chunk, returns new chunk id or nil when deduped.
    func insertChunk(ts: Double, app: String, title: String, url: String?, text: String, hash: String) -> Int64? {
        let existing = db.query("SELECT id FROM chunks WHERE hash = ?", [hash])
        if !existing.isEmpty { return nil }
        let id = db.run("""
            INSERT OR IGNORE INTO chunks (ts, app, title, url, text, hash) VALUES (?, ?, ?, ?, ?, ?)
            """, [ts, app, title, url, text, hash])
        return id > 0 ? id : nil
    }

    func insertEmbedding(chunkId: Int64, vec: [Float], model: String) {
        db.run("INSERT OR REPLACE INTO embeddings (chunk_id, dim, vec, model) VALUES (?, ?, ?, ?)",
               [chunkId, vec.count, Embeddings.data(from: vec), model])
    }

    /// Convenience single-query entry point.
    func search(query: String, from: Double?, to: Double?, limit: Int = 20) -> [[String: Any]] {
        return search(queries: [query], from: from, to: to, limit: limit)
    }

    /// Hybrid retrieval over one or more query angles (multi-query expansion):
    /// FTS5 (BM25) + vector cosine fused with reciprocal-rank fusion, then a
    /// rerank pass adding lexical-overlap and recency signals. The semantic leg
    /// only compares vectors embedded by the *same* model as the live query, so
    /// mixed-dimension histories stay correct after a backend switch.
    func search(queries: [String], from: Double?, to: Double?, limit: Int = 20) -> [[String: Any]] {
        let qs = queries.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !qs.isEmpty else { return [] }

        var ranks: [Int64: Double] = [:]

        // Keyword leg (union across all query angles).
        for q in qs {
            let terms = q.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map { "\"\($0)\"" }
            guard !terms.isEmpty else { continue }
            var sql = """
                SELECT c.id AS id, bm25(chunks_fts) AS rank FROM chunks_fts
                JOIN chunks c ON c.id = chunks_fts.rowid
                WHERE chunks_fts MATCH ?
                """
            var params: [Any?] = [terms.joined(separator: " OR ")]
            if let f = from { sql += " AND c.ts >= ?"; params.append(f) }
            if let t = to { sql += " AND c.ts <= ?"; params.append(t) }
            sql += " ORDER BY rank LIMIT 60"
            for (i, row) in db.query(sql, params).enumerated() {
                ranks[Int64(row.int("id")), default: 0] += 1.0 / Double(60 + i + 1)
            }
        }

        // Semantic leg — load candidate vectors once, score against each query.
        let activeModel = Embeddings.shared.modelId
        let qvecs = qs.compactMap { Embeddings.shared.embed($0) }
        if !qvecs.isEmpty {
            var sql = """
                SELECT e.chunk_id AS id, e.vec AS vec FROM embeddings e
                JOIN chunks c ON c.id = e.chunk_id
                WHERE e.model = ?
                """
            var params: [Any?] = [activeModel]
            if let f = from { sql += " AND c.ts >= ?"; params.append(f) }
            if let t = to { sql += " AND c.ts <= ?"; params.append(t) }
            let rows = db.query(sql, params)
            for q in qvecs {
                var scored: [(Int64, Float)] = []
                for row in rows {
                    guard let blob = row["vec"] as? Data else { continue }
                    let v = Embeddings.floats(from: blob)
                    guard v.count == q.count else { continue }
                    scored.append((Int64(row.int("id")), Embeddings.cosine(q, v)))
                }
                scored.sort { $0.1 > $1.1 }
                for (i, item) in scored.prefix(60).enumerated() {
                    ranks[item.0, default: 0] += 1.0 / Double(60 + i + 1)
                }
            }
        }

        // Take a wider candidate pool, then rerank with lexical + recency.
        let poolIds = ranks.sorted { $0.value > $1.value }.prefix(max(limit * 3, 40)).map { $0.key }
        guard !poolIds.isEmpty else { return [] }

        let placeholders = poolIds.map { _ in "?" }.joined(separator: ",")
        let rows = db.query("SELECT id, ts, app, title, url, text FROM chunks WHERE id IN (\(placeholders))",
                            poolIds.map { $0 as Any? })
        var byId: [Int64: [String: Any]] = [:]
        for r in rows { byId[Int64(r.int("id"))] = r }

        // Query term set for lexical overlap.
        let queryTerms = Set(qs.joined(separator: " ").lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { $0.count > 2 })
        let now = Date().timeIntervalSince1970

        var reranked: [(id: Int64, score: Double)] = []
        for id in poolIds {
            guard let r = byId[id] else { continue }
            let fused = ranks[id] ?? 0
            let text = (r.str("title") + " " + r.str("text")).lowercased()
            let hits = queryTerms.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            let lexical = queryTerms.isEmpty ? 0 : Double(hits) / Double(queryTerms.count)
            // Recency: mild boost, half-life ~14 days.
            let ageDays = max(0, (now - r.double("ts")) / 86400)
            let recency = pow(0.5, ageDays / 14.0)
            let score = fused + 0.15 * lexical + 0.05 * recency
            reranked.append((id, score))
        }
        reranked.sort { $0.score > $1.score }

        return reranked.prefix(limit).compactMap { item -> [String: Any]? in
            guard var r = byId[item.id] else { return nil }
            let text = r.str("text")
            r["snippet"] = String(text.prefix(400))
            r.removeValue(forKey: "text")
            r["score"] = item.score
            return r
        }
    }

    // MARK: - Facts & reminders (the "brain")

    @discardableResult
    func addFact(kind: String, title: String, detail: String, dueTs: Double?, source: String,
                 note: String = "") -> Int64? {
        let existing = db.query("SELECT id FROM facts WHERE kind = ? AND title = ?", [kind, title])
        if !existing.isEmpty { return nil }
        let id = db.run("""
            INSERT OR IGNORE INTO facts (kind, title, detail, due_ts, created_ts, source, status, note)
            VALUES (?, ?, ?, ?, ?, ?, 'open', ?)
            """, [kind, title, detail, dueTs, Date().timeIntervalSince1970, source, Store.cleanNote(note)])
        guard id > 0 else { return nil }
        if let due = dueTs {
            let dayBefore = due - 86400
            let now = Date().timeIntervalSince1970
            if dayBefore > now { addReminder(factId: id, fireTs: dayBefore, intervalIdx: -1) }
            if due > now { addReminder(factId: id, fireTs: due, intervalIdx: -1) }
        }
        return id
    }

    /// Record (or extend) a watched video. One Brain entry per video per 24h:
    /// matched by URL when we have one — SPA portals keep a single title
    /// across every lecture, so the URL is the video's identity — falling back
    /// to the title for browsers that expose no URL. A match inside the window
    /// accumulates watch seconds; outside it, a re-watch is a fresh entry.
    ///
    /// The URL arrives canonical (see `Extractors.canonicalURL`): players and
    /// portals decorate the same address differently on every visit —
    /// `&themeRefresh=1`, `&t=42`, `&embeds_referring_euri=…` — and comparing
    /// those raw made one lecture look like several videos, each with a slice
    /// of the time actually spent on it.
    func recordWatch(title: String, url: String?, source: String, secs: Double,
                     ts: Double) -> (id: Int64, isNew: Bool)? {
        let windowStart = Date().timeIntervalSince1970 - 86400
        let existing: [[String: Any]]
        if let u = url, !u.isEmpty {
            existing = db.query("""
                SELECT id, title FROM facts WHERE kind = 'watched' AND detail = ? AND created_ts >= ?
                ORDER BY created_ts DESC LIMIT 1
                """, [u, windowStart])
        } else {
            existing = db.query("""
                SELECT id, title FROM facts WHERE kind = 'watched' AND title = ? AND created_ts >= ?
                ORDER BY created_ts DESC LIMIT 1
                """, [title, windowStart])
        }
        if let row = existing.first {
            let id = Int64(row.int("id"))
            db.run("UPDATE facts SET watch_secs = watch_secs + ? WHERE id = ?", [max(0, secs), id])
            // The stretch that opened the entry may have had no title to give
            // (fullscreen); once macOS names the video, the entry takes the name.
            if row.str("title").isEmpty && !title.isEmpty { setFactTitle(id: id, title: title) }
            return (id, false)
        }
        let id = db.run("""
            INSERT INTO facts (kind, title, detail, due_ts, created_ts, source, status, watch_secs)
            VALUES ('watched', ?, ?, NULL, ?, ?, 'open', ?)
            """, [title, url ?? "", ts, source, max(0, secs)])
        guard id > 0 else { return nil }
        return (id, true)
    }

    func addReminder(factId: Int64, fireTs: Double, intervalIdx: Int) {
        db.run("INSERT INTO reminders (fact_id, fire_ts, interval_idx, status) VALUES (?, ?, ?, 'pending')",
               [factId, fireTs, intervalIdx])
    }

    /// Your own subtitle for an item — what the page title didn't tell you.
    func setFactNote(id: Int64, note: String) {
        db.run("UPDATE facts SET note = ? WHERE id = ?", [Store.cleanNote(note), id])
    }

    /// An open item of the same kind, due the same day, that is really the same
    /// thing said differently. One mail reaches the screen as a tab title, a
    /// subject line and a heading; without this each becomes its own task.
    func similarOpenFact(kind: String, title: String, dueTs: Double) -> String? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date(timeIntervalSince1970: dueTs)).timeIntervalSince1970
        let candidates = db.query("""
            SELECT title FROM facts
            WHERE status = 'open' AND kind = ? AND due_ts >= ? AND due_ts < ?
            """, [kind, dayStart, dayStart + 86400])
        for row in candidates where Extractors.sameThing(title, row.str("title"), threshold: 0.7) {
            return row.str("title")
        }
        return nil
    }

    func setFactTitle(id: Int64, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        db.run("UPDATE facts SET title = ? WHERE id = ?", [String(t.prefix(140)), id])
    }

    /// The source line an extracted item came from, for re-reading it later.
    func factDetail(id: Int64) -> String? {
        return db.query("SELECT detail FROM facts WHERE id = ?", [id]).first?.str("detail")
    }

    func setNeedsReview(id: Int64, _ flag: Bool) {
        db.run("UPDATE facts SET needs_review = ? WHERE id = ?", [flag ? 1 : 0, id])
    }

    /// Correct an item's due date. Its one-off nudges (interval_idx -1) are
    /// rebuilt around the new date, and the item stops asking to be checked —
    /// the user just told us what the date is.
    func setFactDue(id: Int64, dueTs: Double?) {
        db.run("UPDATE facts SET due_ts = ?, needs_review = 0 WHERE id = ?", [dueTs, id])
        db.run("UPDATE reminders SET status = 'cancelled' WHERE fact_id = ? AND status = 'pending' AND interval_idx = -1", [id])
        guard let due = dueTs else { return }
        let now = Date().timeIntervalSince1970
        let dayBefore = due - 86400
        if dayBefore > now { addReminder(factId: id, fireTs: dayBefore, intervalIdx: -1) }
        if due > now { addReminder(factId: id, fireTs: due, intervalIdx: -1) }
    }

    /// One-time repair after the date parser was fixed. Extracted deadlines
    /// keep their original sentence in `detail`, so the corrected parser can
    /// re-read them: a different date is written back, and a line that no
    /// longer yields a believable date (a stale mail whose year had been
    /// rolled forward) has its nudges cancelled. Nothing is deleted — the item

    /// Clear out items the old, looser extractor created: marketing urgency
    /// ("Shop now before it's too late"), clipped fragments, and anything whose
    /// source line turns out to hold no date at all. Dismissed rather than

    private static func cleanNote(_ note: String) -> String {
        return String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
    }

    /// Spaced-repetition ladder for a fact (e.g. a watched lecture). Idempotent:
    /// clears any existing pending revision reminders for the fact first, so
    /// re-enrolling (or auto-enroll + a manual "revise" tap) never stacks.
    func addRevisionLadder(factId: Int64, baseTs: Double? = nil) {
        db.run("""
            UPDATE reminders SET status = 'cancelled'
            WHERE fact_id = ? AND status = 'pending' AND interval_idx >= 0
            """, [factId])
        let base = baseTs ?? Date().timeIntervalSince1970
        let days: [Double] = [1, 3, 7, 14, 30]
        for (i, d) in days.enumerated() {
            addReminder(factId: factId, fireTs: base + d * 86400, intervalIdx: i)
        }
    }

    func openFacts() -> [[String: Any]] {
        return db.query("SELECT * FROM facts WHERE status = 'open' ORDER BY COALESCE(due_ts, 9e12) ASC, created_ts DESC LIMIT 100")
    }

    func importantToday() -> [String: Any] {
        let now = Date().timeIntervalSince1970
        let endOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 + 86400
        let dueSoon = db.query("""
            SELECT * FROM facts WHERE status = 'open' AND due_ts IS NOT NULL AND due_ts < ?
            ORDER BY due_ts ASC LIMIT 30
            """, [endOfDay + 2 * 86400])
        let firingToday = db.query("""
            SELECT r.id AS reminder_id, r.fire_ts, r.interval_idx, f.id AS fact_id, f.kind, f.title, f.detail, f.note
            FROM reminders r JOIN facts f ON f.id = r.fact_id
            WHERE r.status = 'pending' AND r.fire_ts < ? AND f.status = 'open'
            ORDER BY r.fire_ts ASC LIMIT 30
            """, [endOfDay])
        let overdue = dueSoon.filter { $0.double("due_ts") < now }
        return ["due_soon": dueSoon, "revisions_today": firingToday, "overdue_count": overdue.count]
    }

    func setFactStatus(id: Int64, status: String) {
        if status == "done" {
            db.run("UPDATE facts SET status = ?, done_ts = ? WHERE id = ?",
                   [status, Date().timeIntervalSince1970, id])
        } else {
            db.run("UPDATE facts SET status = ? WHERE id = ?", [status, id])
        }
        if status != "open" {
            db.run("UPDATE reminders SET status = 'cancelled' WHERE fact_id = ? AND status = 'pending'", [id])
        }
    }

    func pendingReminders(before ts: Double) -> [[String: Any]] {
        return db.query("""
            SELECT r.id AS reminder_id, r.fire_ts, r.interval_idx, f.id AS fact_id, f.kind, f.title, f.note
            FROM reminders r JOIN facts f ON f.id = r.fact_id
            WHERE r.status = 'pending' AND r.fire_ts <= ? AND f.status = 'open'
            ORDER BY r.fire_ts ASC LIMIT 20
            """, [ts])
    }

    func markReminderFired(id: Int64) {
        db.run("UPDATE reminders SET status = 'fired' WHERE id = ?", [id])
    }

    /// The user actually did this revision (vs. just receiving the nudge).
    func markReminderDone(id: Int64) {
        db.run("UPDATE reminders SET status = 'done', done_ts = ? WHERE id = ? AND status != 'cancelled'",
               [Date().timeIntervalSince1970, id])
    }

    /// Everything the History calendar needs for a window: watch events, each
    /// revision-ladder step with its outcome, and deadline/bill due dates.
    /// Outcomes: done (revised), missed (day passed, never marked done),
    /// due (scheduled today, still actionable), upcoming (in the future),
    /// closed (the parent item was completed/dismissed before this step).
    func history(from: Double, to: Double) -> [[String: Any]] {
        var items: [[String: Any]] = []
        let now = Date().timeIntervalSince1970
        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

        // Attach a clickable link when the fact's detail is a URL (watched
        // facts store the video URL there), and carry the user's own note so
        // the calendar says which lecture an entry actually was.
        func withLink(_ item: [String: Any], _ f: [String: Any]) -> [String: Any] {
            var item = item
            let detail = f.str("detail")
            if detail.hasPrefix("http://") || detail.hasPrefix("https://") { item["url"] = detail }
            item["note"] = f.str("note")
            return item
        }

        // Watch events — the day the video/lecture was first seen.
        for f in db.query("""
            SELECT id, title, detail, note, created_ts, watch_secs FROM facts
            WHERE kind = 'watched' AND created_ts >= ? AND created_ts < ?
            ORDER BY created_ts ASC
            """, [from, to]) {
            items.append(withLink(["type": "watched", "fact_id": f.int("id"), "title": f.str("title"),
                                   "ts": f.double("created_ts"), "status": "watched",
                                   "watch_secs": f.double("watch_secs")], f))
        }

        // Revision-ladder steps (interval_idx >= 0; idx -1 is a deadline nudge,
        // which the deadline item below already represents).
        for r in db.query("""
            SELECT r.id AS reminder_id, r.fire_ts, r.interval_idx, r.status AS rstatus,
                   f.id AS fact_id, f.title, f.detail, f.note, f.status AS fstatus
            FROM reminders r JOIN facts f ON f.id = r.fact_id
            WHERE r.interval_idx >= 0 AND r.status != 'cancelled'
              AND r.fire_ts >= ? AND r.fire_ts < ?
            ORDER BY r.fire_ts ASC
            """, [from, to]) {
            let fireTs = r.double("fire_ts")
            let status: String
            if r.str("rstatus") == "done" { status = "done" }
            else if r.str("fstatus") != "open" { status = "closed" }
            else if fireTs < todayStart { status = "missed" }
            else if fireTs <= now { status = "due" }
            else { status = "upcoming" }
            items.append(withLink(["type": "revision", "reminder_id": r.int("reminder_id"),
                                   "fact_id": r.int("fact_id"), "title": r.str("title"),
                                   "ts": fireTs, "interval_idx": r.int("interval_idx"),
                                   "status": status], r))
        }

        // Every non-watched item with a due date — bills, deadlines, and
        // items you add in the Brain tab — placed on its due date. Marking
        // one done in Brain shows up here as done.
        for f in db.query("""
            SELECT id, kind, title, detail, note, due_ts, status FROM facts
            WHERE kind != 'watched' AND due_ts IS NOT NULL
              AND due_ts >= ? AND due_ts < ?
            ORDER BY due_ts ASC
            """, [from, to]) {
            let status: String
            switch f.str("status") {
            case "done": status = "done"
            case "dismissed": status = "closed"
            default: status = f.double("due_ts") < now ? "missed" : "upcoming"
            }
            items.append(withLink(["type": "deadline", "fact_id": f.int("id"), "kind": f.str("kind"),
                                   "title": f.str("title"), "ts": f.double("due_ts"), "status": status], f))
        }

        // Completed items with NO due date — placed on the day they were
        // marked done, so Brain completions always reflect in the calendar.
        for f in db.query("""
            SELECT id, kind, title, detail, note, done_ts FROM facts
            WHERE kind != 'watched' AND due_ts IS NULL AND status = 'done'
              AND done_ts IS NOT NULL AND done_ts >= ? AND done_ts < ?
            ORDER BY done_ts ASC
            """, [from, to]) {
            items.append(withLink(["type": "deadline", "fact_id": f.int("id"), "kind": f.str("kind"),
                                   "title": f.str("title"), "ts": f.double("done_ts"), "status": "done"], f))
        }

        return items
    }

    /// One row per fact — the NEXT pending reminder plus how many remain — so a
    /// 5-step revision ladder shows as a single item, not five duplicates.
    func upcomingReminders() -> [[String: Any]] {
        return db.query("""
            SELECT f.id AS fact_id, f.kind, f.title, f.note,
                   MIN(r.fire_ts) AS fire_ts,
                   COUNT(*) AS remaining
            FROM reminders r JOIN facts f ON f.id = r.fact_id
            WHERE r.status = 'pending' AND f.status = 'open'
            GROUP BY r.fact_id
            ORDER BY fire_ts ASC LIMIT 50
            """)
    }

    // MARK: - Privacy

    func purge(from: Double, to: Double) -> Int {
        let n = db.query("SELECT COUNT(*) AS n FROM chunks WHERE ts >= ? AND ts <= ?", [from, to]).first?.int("n") ?? 0
        db.run("DELETE FROM chunks WHERE ts >= ? AND ts <= ?", [from, to])
        db.run("DELETE FROM events WHERE ts_start >= ? AND ts_start <= ?", [from, to])
        db.run("DELETE FROM embeddings WHERE chunk_id NOT IN (SELECT id FROM chunks)")
        return n
    }

    func dbSizeBytes() -> Int64 {
        let path = dataDir.appendingPathComponent("mitthuai.db").path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    func counts() -> [String: Any] {
        let events = db.query("SELECT COUNT(*) AS n FROM events").first?.int("n") ?? 0
        let chunks = db.query("SELECT COUNT(*) AS n FROM chunks").first?.int("n") ?? 0
        let embedded = db.query("SELECT COUNT(*) AS n FROM embeddings").first?.int("n") ?? 0
        let facts = db.query("SELECT COUNT(*) AS n FROM facts").first?.int("n") ?? 0
        return ["events": events, "chunks": chunks, "embedded": embedded, "facts": facts,
                "db_bytes": dbSizeBytes()]
    }
}
