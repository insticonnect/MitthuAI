import Foundation
import SQLite3

class Database {
    private var db: OpaquePointer?
    
    init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let mitthuURL = appSupportURL.appendingPathComponent("Mitthu")
        
        // Ensure Directory exists
        try? fileManager.createDirectory(at: mitthuURL, withIntermediateDirectories: true, attributes: nil)
        let dbURL = mitthuURL.appendingPathComponent("mitthu.db")
        
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("Mitthu Database: Error opening database.")
        } else {
            print("Mitthu Database: Opened successfully at \(dbURL.path)")
        }
        
        createTables()
        upgradeSchemaIfNeeded()
        insertDefaultRules()
        migrateOlderDataIfNeeded()
    }
    
    private func migrateOlderDataIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "DidMigrateFromActivityWatchV2") {
            return
        }
        
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let oldDbPath = homeDir.appendingPathComponent("Library/Application Support/activitywatch/aw-server/peewee-sqlite.v2.db").path
        
        guard fileManager.fileExists(atPath: oldDbPath) else {
            print("Mitthu Database Migration: Older ActivityWatch database not found at \(oldDbPath). Skipping migration.")
            defaults.set(true, forKey: "DidMigrateFromActivityWatchV2")
            return
        }
        
        print("Mitthu Database Migration: Found older database at \(oldDbPath). Starting migration...")
        
        var oldDb: OpaquePointer?
        if sqlite3_open_v2(oldDbPath, &oldDb, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("Mitthu Database Migration: Failed to open older database.")
            return
        }
        defer {
            sqlite3_close(oldDb)
        }
        
        var windowBucketKey: Int64? = nil
        var afkBucketKey: Int64? = nil
        
        let bucketQuery = "SELECT key, type FROM bucketmodel;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(oldDb, bucketQuery, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = sqlite3_column_int64(stmt, 0)
                if let typeCol = sqlite3_column_text(stmt, 1) {
                    let typeStr = String(cString: typeCol)
                    if typeStr == "currentwindow" {
                        windowBucketKey = key
                    } else if typeStr == "afk" || typeStr == "afkstatus" {
                        afkBucketKey = key
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        
        guard windowBucketKey != nil || afkBucketKey != nil else {
            print("Mitthu Database Migration: No valid buckets found. Skipping.")
            defaults.set(true, forKey: "DidMigrateFromActivityWatchV2")
            return
        }
        
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        
        var migratedCount = 0
        let dateParser = DateFormatter()
        dateParser.timeZone = TimeZone(secondsFromGMT: 0)
        
        let parseDate: (String) -> Date? = { dateStr in
            dateParser.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ"
            if let date = dateParser.date(from: dateStr) {
                return date
            }
            dateParser.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"
            if let date = dateParser.date(from: dateStr) {
                return date
            }
            dateParser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
            if let date = dateParser.date(from: dateStr) {
                return date
            }
            return nil
        }
        
        if let winKey = windowBucketKey {
            let eventsQuery = "SELECT timestamp, duration, datastr FROM eventmodel WHERE bucket_id = ?;"
            var eventStmt: OpaquePointer?
            if sqlite3_prepare_v2(oldDb, eventsQuery, -1, &eventStmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(eventStmt, 1, winKey)
                
                while sqlite3_step(eventStmt) == SQLITE_ROW {
                    guard let tsCol = sqlite3_column_text(eventStmt, 0) else { continue }
                    let tsStr = String(cString: tsCol)
                    let duration = sqlite3_column_double(eventStmt, 1)
                    guard let dataCol = sqlite3_column_text(eventStmt, 2) else { continue }
                    let dataStr = String(cString: dataCol)
                    
                    guard let startTime = parseDate(tsStr) else { continue }
                    let endTime = startTime.addingTimeInterval(duration)
                    
                    var appName = "Unknown"
                    var windowTitle = ""
                    
                    if let jsonData = dataStr.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                        appName = json["app"] as? String ?? json["appName"] as? String ?? "Unknown"
                        windowTitle = json["title"] as? String ?? json["windowTitle"] as? String ?? ""
                    }
                    
                    let category = getCategoryFor(appName: appName, windowTitle: windowTitle)
                    
                    let insertSql = "INSERT INTO events (app_name, window_title, start_time, end_time, duration, is_idle, category, device) VALUES (?, ?, ?, ?, ?, 0, ?, 'Mac');"
                    var insertStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(insertStmt, 1, (appName as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(insertStmt, 2, (windowTitle as NSString).utf8String, -1, nil)
                        sqlite3_bind_double(insertStmt, 3, startTime.timeIntervalSince1970)
                        sqlite3_bind_double(insertStmt, 4, endTime.timeIntervalSince1970)
                        sqlite3_bind_double(insertStmt, 5, duration)
                        sqlite3_bind_text(insertStmt, 6, (category as NSString).utf8String, -1, nil)
                        sqlite3_step(insertStmt)
                    }
                    sqlite3_finalize(insertStmt)
                    migratedCount += 1
                }
            }
            sqlite3_finalize(eventStmt)
        }
        
        if let afkKey = afkBucketKey {
            let eventsQuery = "SELECT timestamp, duration, datastr FROM eventmodel WHERE bucket_id = ?;"
            var eventStmt: OpaquePointer?
            if sqlite3_prepare_v2(oldDb, eventsQuery, -1, &eventStmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(eventStmt, 1, afkKey)
                
                while sqlite3_step(eventStmt) == SQLITE_ROW {
                    guard let tsCol = sqlite3_column_text(eventStmt, 0) else { continue }
                    let tsStr = String(cString: tsCol)
                    let duration = sqlite3_column_double(eventStmt, 1)
                    guard let dataCol = sqlite3_column_text(eventStmt, 2) else { continue }
                    let dataStr = String(cString: dataCol)
                    
                    guard let startTime = parseDate(tsStr) else { continue }
                    let endTime = startTime.addingTimeInterval(duration)
                    
                    var isAfk = false
                    if let jsonData = dataStr.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                        let status = json["status"] as? String ?? ""
                        if status == "afk" {
                            isAfk = true
                        }
                    }
                    
                    if isAfk {
                        let insertSql = "INSERT INTO events (app_name, window_title, start_time, end_time, duration, is_idle, category, device) VALUES ('Idle', 'Away', ?, ?, ?, 1, 'Idle', 'Mac');"
                        var insertStmt: OpaquePointer?
                        if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                            sqlite3_bind_double(insertStmt, 1, startTime.timeIntervalSince1970)
                            sqlite3_bind_double(insertStmt, 2, endTime.timeIntervalSince1970)
                            sqlite3_bind_double(insertStmt, 3, duration)
                            sqlite3_step(insertStmt)
                        }
                        sqlite3_finalize(insertStmt)
                        migratedCount += 1
                    }
                }
            }
            sqlite3_finalize(eventStmt)
        }
        
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        print("Mitthu Database Migration: Completed. Migrated \(migratedCount) events from older database.")
        
        defaults.set(true, forKey: "DidMigrateFromActivityWatchV2")
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    func getDbPointer() -> OpaquePointer? {
        return db
    }
    
    private func createTables() {
        // Create events table with category and device columns
        let createEventsTable = """
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_name TEXT,
            window_title TEXT,
            start_time REAL,
            end_time REAL,
            duration REAL,
            is_idle INTEGER,
            category TEXT DEFAULT 'Uncategorized',
            device TEXT DEFAULT 'Mac'
        );
        """
        
        // Create rules table
        let createRulesTable = """
        CREATE TABLE IF NOT EXISTS rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_name TEXT,
            title_pattern TEXT,
            category TEXT
        );
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, createEventsTable, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Mitthu Database: Events table creation failed.")
            }
        }
        sqlite3_finalize(statement)
        
        if sqlite3_prepare_v2(db, createRulesTable, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Mitthu Database: Rules table creation failed.")
            }
        }
        sqlite3_finalize(statement)
    }
    
    private func upgradeSchemaIfNeeded() {
        // Safely add category column if it was created in a previous version without it
        let alterTableCategory = "ALTER TABLE events ADD COLUMN category TEXT DEFAULT 'Uncategorized';"
        sqlite3_exec(db, alterTableCategory, nil, nil, nil)
        
        // Safely add device column if it was created in a previous version without it
        let alterTableDevice = "ALTER TABLE events ADD COLUMN device TEXT DEFAULT 'Mac';"
        sqlite3_exec(db, alterTableDevice, nil, nil, nil)
    }
    
    private func insertDefaultRules() {
        let checkQuery = "SELECT COUNT(*) FROM rules;"
        var statement: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, checkQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        if count == 0 {
            print("Mitthu Database: Inserting default categorization rules...")
            let defaultRules = [
                ("Xcode", "", "Study"),
                ("VS Code", "", "Study"),
                ("Visual Studio Code", "", "Study"),
                ("Terminal", "", "Study"),
                ("Safari", "YouTube", "Entertainment"),
                ("Google Chrome", "YouTube", "Entertainment"),
                ("Safari", "Netflix", "Entertainment"),
                ("Google Chrome", "Netflix", "Entertainment"),
                ("Spotify", "", "Entertainment"),
                ("Slack", "", "Work"),
                ("Microsoft Teams", "", "Work")
            ]
            
            for rule in defaultRules {
                insertRule(appName: rule.0, titlePattern: rule.1, category: rule.2)
            }
        }
    }
    
    func insertRule(appName: String, titlePattern: String, category: String) {
        let insertString = "INSERT INTO rules (app_name, title_pattern, category) VALUES (?, ?, ?);"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertString, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (appName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (titlePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (category as NSString).utf8String, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    func addRule(appName: String, titlePattern: String, category: String) {
        insertRule(appName: appName, titlePattern: titlePattern, category: category)
        
        // Retrospectively update past events' categories matching this rule
        let updateQuery: String
        if !appName.isEmpty && !titlePattern.isEmpty {
            updateQuery = "UPDATE events SET category = ? WHERE app_name = ? AND window_title LIKE '%' || ? || '%';"
        } else if !appName.isEmpty {
            updateQuery = "UPDATE events SET category = ? WHERE app_name = ?;"
        } else {
            updateQuery = "UPDATE events SET category = ? WHERE window_title LIKE '%' || ? || '%';"
        }
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (category as NSString).utf8String, -1, nil)
            if !appName.isEmpty && !titlePattern.isEmpty {
                sqlite3_bind_text(statement, 2, (appName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (titlePattern as NSString).utf8String, -1, nil)
            } else if !appName.isEmpty {
                sqlite3_bind_text(statement, 2, (appName as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_text(statement, 2, (titlePattern as NSString).utf8String, -1, nil)
            }
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    func getCategoryFor(appName: String, windowTitle: String) -> String {
        // Query matching rule: Check specific app & title matches first, then app-only, then title-only
        let query = """
        SELECT category FROM rules 
        WHERE (app_name = ? AND title_pattern != '' AND ? LIKE '%' || title_pattern || '%')
           OR (app_name = ? AND title_pattern = '')
           OR (app_name = '' AND title_pattern != '' AND ? LIKE '%' || title_pattern || '%')
        ORDER BY app_name DESC, title_pattern DESC LIMIT 1;
        """
        
        var statement: OpaquePointer?
        var category = "Uncategorized"
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (appName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (windowTitle as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (appName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (windowTitle as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                if let catCol = sqlite3_column_text(statement, 0) {
                    category = String(cString: catCol)
                }
            }
        }
        sqlite3_finalize(statement)
        return category
    }
    
    func getLastEvent(device: String = "Mac") -> ActivityEvent? {
        let query = """
        SELECT id, app_name, window_title, start_time, end_time, duration, is_idle, category, device 
        FROM events 
        WHERE device = ? 
        ORDER BY id DESC 
        LIMIT 1;
        """
        
        var queryStatement: OpaquePointer?
        var event: ActivityEvent? = nil
        
        if sqlite3_prepare_v2(db, query, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(queryStatement, 1, (device as NSString).utf8String, -1, nil)
            if sqlite3_step(queryStatement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(queryStatement, 0))
                var appName = "Unknown"
                if let nameCol = sqlite3_column_text(queryStatement, 1) {
                    appName = String(cString: nameCol)
                }
                var windowTitle = ""
                if let titleCol = sqlite3_column_text(queryStatement, 2) {
                    windowTitle = String(cString: titleCol)
                }
                let startTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 3))
                let endTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 4))
                let duration = sqlite3_column_double(queryStatement, 5)
                let isIdle = sqlite3_column_int(queryStatement, 6) == 1
                var category = "Uncategorized"
                if let catCol = sqlite3_column_text(queryStatement, 7) {
                    category = String(cString: catCol)
                }
                var devName = "Mac"
                if let devCol = sqlite3_column_text(queryStatement, 8) {
                    devName = String(cString: devCol)
                }
                
                event = ActivityEvent(
                    id: id,
                    appName: appName,
                    windowTitle: windowTitle,
                    startTime: startTime,
                    endTime: endTime,
                    duration: duration,
                    isIdle: isIdle,
                    category: category,
                    device: devName
                )
            }
        }
        sqlite3_finalize(queryStatement)
        return event
    }
    
    func getSecondLastEvent(device: String = "Mac") -> ActivityEvent? {
        let query = """
        SELECT id, app_name, window_title, start_time, end_time, duration, is_idle, category, device 
        FROM events 
        WHERE device = ? 
        ORDER BY id DESC 
        LIMIT 1 OFFSET 1;
        """
        
        var queryStatement: OpaquePointer?
        var event: ActivityEvent? = nil
        
        if sqlite3_prepare_v2(db, query, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(queryStatement, 1, (device as NSString).utf8String, -1, nil)
            if sqlite3_step(queryStatement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(queryStatement, 0))
                var appName = "Unknown"
                if let nameCol = sqlite3_column_text(queryStatement, 1) {
                    appName = String(cString: nameCol)
                }
                var windowTitle = ""
                if let titleCol = sqlite3_column_text(queryStatement, 2) {
                    windowTitle = String(cString: titleCol)
                }
                let startTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 3))
                let endTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 4))
                let duration = sqlite3_column_double(queryStatement, 5)
                let isIdle = sqlite3_column_int(queryStatement, 6) == 1
                var category = "Uncategorized"
                if let catCol = sqlite3_column_text(queryStatement, 7) {
                    category = String(cString: catCol)
                }
                var devName = "Mac"
                if let devCol = sqlite3_column_text(queryStatement, 8) {
                    devName = String(cString: devCol)
                }
                
                event = ActivityEvent(
                    id: id,
                    appName: appName,
                    windowTitle: windowTitle,
                    startTime: startTime,
                    endTime: endTime,
                    duration: duration,
                    isIdle: isIdle,
                    category: category,
                    device: devName
                )
            }
        }
        sqlite3_finalize(queryStatement)
        return event
    }
    
    func updateEvent(id: Int, endTime: Date, duration: TimeInterval) {
        let updateQuery = "UPDATE events SET end_time = ?, duration = ? WHERE id = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, endTime.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, duration)
            sqlite3_bind_int(statement, 3, Int32(id))
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    func deleteEvent(id: Int) {
        let deleteQuery = "DELETE FROM events WHERE id = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(id))
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    func insertEvent(appName: String, windowTitle: String, startTime: Date, endTime: Date, duration: TimeInterval, isIdle: Bool, device: String = "Mac") {
        let category = isIdle ? "Idle" : getCategoryFor(appName: appName, windowTitle: windowTitle)
        
        let insertStatementString = "INSERT INTO events (app_name, window_title, start_time, end_time, duration, is_idle, category, device) VALUES (?, ?, ?, ?, ?, ?, ?, ?);"
        var insertStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertStatementString, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStatement, 1, (appName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (windowTitle as NSString).utf8String, -1, nil)
            sqlite3_bind_double(insertStatement, 3, startTime.timeIntervalSince1970)
            sqlite3_bind_double(insertStatement, 4, endTime.timeIntervalSince1970)
            sqlite3_bind_double(insertStatement, 5, duration)
            sqlite3_bind_int(insertStatement, 6, isIdle ? 1 : 0)
            sqlite3_bind_text(insertStatement, 7, (category as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 8, (device as NSString).utf8String, -1, nil)
            
            if sqlite3_step(insertStatement) != SQLITE_DONE {
                print("Mitthu Database: Could not insert row.")
            }
        }
        sqlite3_finalize(insertStatement)
    }
    
    func updateEventCategory(eventId: Int, category: String) {
        let updateQuery = "UPDATE events SET category = ? WHERE id = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (category as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(eventId))
            let result = sqlite3_step(statement)
            if result != SQLITE_DONE {
                print("Mitthu Database Error: updateEventCategory failed for eventId \(eventId) to \(category), code: \(result)")
            } else {
                print("Mitthu Database: Successfully updated eventId \(eventId) to category \(category)")
            }
        } else {
            print("Mitthu Database Error: Could not prepare updateEventCategory statement.")
        }
        sqlite3_finalize(statement)
    }
    
    private func getTimestampsForDate(_ dateStr: String) -> (start: Double, end: Double) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        
        let date = dateFormatter.date(from: dateStr) ?? Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = startOfDay.addingTimeInterval(86400)
        
        return (startOfDay.timeIntervalSince1970, endOfDay.timeIntervalSince1970)
    }
    
    func getTodayStats() -> (totalActive: TimeInterval, totalIdle: TimeInterval) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return getStatsForDate(dateStr: dateFormatter.string(from: Date()))
    }
    
    func getStatsForDate(dateStr: String, device: String = "Mac") -> (totalActive: TimeInterval, totalIdle: TimeInterval) {
        let bounds = getTimestampsForDate(dateStr)
        
        let queryString = "SELECT SUM(duration), is_idle FROM events WHERE start_time >= ? AND start_time < ? AND device = ? GROUP BY is_idle;"
        var queryStatement: OpaquePointer?
        
        var totalActive: TimeInterval = 0
        var totalIdle: TimeInterval = 0
        
        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(queryStatement, 1, bounds.start)
            sqlite3_bind_double(queryStatement, 2, bounds.end)
            sqlite3_bind_text(queryStatement, 3, (device as NSString).utf8String, -1, nil)
            
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let duration = sqlite3_column_double(queryStatement, 0)
                let isIdle = sqlite3_column_int(queryStatement, 1) == 1
                if isIdle {
                    totalIdle = duration
                } else {
                    totalActive += duration
                }
            }
        }
        sqlite3_finalize(queryStatement)
        return (totalActive, totalIdle)
    }
    
    func getTodayAppStats() -> [AppStat] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return getAppStatsForDate(dateStr: dateFormatter.string(from: Date()))
    }
    
    func getAppStatsForDate(dateStr: String, device: String = "Mac") -> [AppStat] {
        let bounds = getTimestampsForDate(dateStr)
        
        let queryString = """
        SELECT app_name, SUM(duration) as total_duration 
        FROM events 
        WHERE start_time >= ? AND start_time < ? AND is_idle = 0 AND app_name != 'Idle' AND device = ?
        GROUP BY app_name 
        ORDER BY total_duration DESC;
        """
        
        var queryStatement: OpaquePointer?
        var stats: [AppStat] = []
        var totalDuration: TimeInterval = 0
        
        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(queryStatement, 1, bounds.start)
            sqlite3_bind_double(queryStatement, 2, bounds.end)
            sqlite3_bind_text(queryStatement, 3, (device as NSString).utf8String, -1, nil)
            
            var tempStats: [(name: String, duration: TimeInterval)] = []
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                if let nameCol = sqlite3_column_text(queryStatement, 0) {
                    let name = String(cString: nameCol)
                    let duration = sqlite3_column_double(queryStatement, 1)
                    tempStats.append((name, duration))
                    totalDuration += duration
                }
            }
            
            for stat in tempStats {
                let percentage = totalDuration > 0 ? (stat.duration / totalDuration) : 0
                stats.append(AppStat(appName: stat.name, duration: stat.duration, percentage: percentage))
            }
        }
        sqlite3_finalize(queryStatement)
        return stats
    }
    
    func getRecentEvents(limit: Int = 10, device: String = "Mac") -> [ActivityEvent] {
        let query = """
        SELECT id, app_name, window_title, start_time, end_time, duration, is_idle, category, device 
        FROM events 
        WHERE device = ? 
        ORDER BY id DESC 
        LIMIT ?;
        """
        
        var queryStatement: OpaquePointer?
        var events: [ActivityEvent] = []
        
        if sqlite3_prepare_v2(db, query, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(queryStatement, 1, (device as NSString).utf8String, -1, nil)
            sqlite3_bind_int(queryStatement, 2, Int32(limit))
            
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(queryStatement, 0))
                var appName = "Unknown"
                if let nameCol = sqlite3_column_text(queryStatement, 1) {
                    appName = String(cString: nameCol)
                }
                var windowTitle = ""
                if let titleCol = sqlite3_column_text(queryStatement, 2) {
                    windowTitle = String(cString: titleCol)
                }
                let startTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 3))
                let endTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 4))
                let duration = sqlite3_column_double(queryStatement, 5)
                let isIdle = sqlite3_column_int(queryStatement, 6) == 1
                var category = "Uncategorized"
                if let catCol = sqlite3_column_text(queryStatement, 7) {
                    category = String(cString: catCol)
                }
                var devName = "Mac"
                if let devCol = sqlite3_column_text(queryStatement, 8) {
                    devName = String(cString: devCol)
                }
                
                events.append(ActivityEvent(
                    id: id,
                    appName: appName,
                    windowTitle: windowTitle,
                    startTime: startTime,
                    endTime: endTime,
                    duration: duration,
                    isIdle: isIdle,
                    category: category,
                    device: devName
                ))
            }
        }
        sqlite3_finalize(queryStatement)
        return events
    }
    
    func getEventsForDate(dateStr: String, device: String = "Mac") -> [ActivityEvent] {
        let bounds = getTimestampsForDate(dateStr)
        
        let query = """
        SELECT id, app_name, window_title, start_time, end_time, duration, is_idle, category, device 
        FROM events 
        WHERE start_time >= ? AND start_time < ? AND device = ?
        ORDER BY start_time ASC;
        """
        
        var queryStatement: OpaquePointer?
        var events: [ActivityEvent] = []
        
        if sqlite3_prepare_v2(db, query, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(queryStatement, 1, bounds.start)
            sqlite3_bind_double(queryStatement, 2, bounds.end)
            sqlite3_bind_text(queryStatement, 3, (device as NSString).utf8String, -1, nil)
            
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(queryStatement, 0))
                var appName = "Unknown"
                if let nameCol = sqlite3_column_text(queryStatement, 1) {
                    appName = String(cString: nameCol)
                }
                var windowTitle = ""
                if let titleCol = sqlite3_column_text(queryStatement, 2) {
                    windowTitle = String(cString: titleCol)
                }
                let startTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 3))
                let endTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 4))
                let duration = sqlite3_column_double(queryStatement, 5)
                let isIdle = sqlite3_column_int(queryStatement, 6) == 1
                var category = "Uncategorized"
                if let catCol = sqlite3_column_text(queryStatement, 7) {
                    category = String(cString: catCol)
                }
                var devName = "Mac"
                if let devCol = sqlite3_column_text(queryStatement, 8) {
                    devName = String(cString: devCol)
                }
                
                events.append(ActivityEvent(
                    id: id,
                    appName: appName,
                    windowTitle: windowTitle,
                    startTime: startTime,
                    endTime: endTime,
                    duration: duration,
                    isIdle: isIdle,
                    category: category,
                    device: devName
                ))
            }
        }
        sqlite3_finalize(queryStatement)
        return events
    }
    
    func getAllEvents(device: String = "Mac") -> [ActivityEvent] {
        let query = """
        SELECT id, app_name, window_title, start_time, end_time, duration, is_idle, category, device 
        FROM events 
        WHERE device = ? 
        ORDER BY start_time ASC;
        """
        
        var queryStatement: OpaquePointer?
        var events: [ActivityEvent] = []
        
        if sqlite3_prepare_v2(db, query, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(queryStatement, 1, (device as NSString).utf8String, -1, nil)
            
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(queryStatement, 0))
                var appName = "Unknown"
                if let nameCol = sqlite3_column_text(queryStatement, 1) {
                    appName = String(cString: nameCol)
                }
                var windowTitle = ""
                if let titleCol = sqlite3_column_text(queryStatement, 2) {
                    windowTitle = String(cString: titleCol)
                }
                let startTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 3))
                let endTime = Date(timeIntervalSince1970: sqlite3_column_double(queryStatement, 4))
                let duration = sqlite3_column_double(queryStatement, 5)
                let isIdle = sqlite3_column_int(queryStatement, 6) == 1
                var category = "Uncategorized"
                if let catCol = sqlite3_column_text(queryStatement, 7) {
                    category = String(cString: catCol)
                }
                var devName = "Mac"
                if let devCol = sqlite3_column_text(queryStatement, 8) {
                    devName = String(cString: devCol)
                }
                
                events.append(ActivityEvent(
                    id: id,
                    appName: appName,
                    windowTitle: windowTitle,
                    startTime: startTime,
                    endTime: endTime,
                    duration: duration,
                    isIdle: isIdle,
                    category: category,
                    device: devName
                ))
            }
        }
        sqlite3_finalize(queryStatement)
        return events
    }
    
    func getCategoryStatsForDate(dateStr: String, device: String = "Mac") -> [String: Double] {
        let bounds = getTimestampsForDate(dateStr)
        
        let queryString = """
        SELECT category, SUM(duration) as total_duration 
        FROM events 
        WHERE start_time >= ? AND start_time < ? AND is_idle = 0 AND app_name != 'Idle' AND device = ?
        GROUP BY category;
        """
        
        var queryStatement: OpaquePointer?
        var stats: [String: Double] = [:]
        
        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(queryStatement, 1, bounds.start)
            sqlite3_bind_double(queryStatement, 2, bounds.end)
            sqlite3_bind_text(queryStatement, 3, (device as NSString).utf8String, -1, nil)
            
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                if let catCol = sqlite3_column_text(queryStatement, 0) {
                    let cat = String(cString: catCol)
                    let duration = sqlite3_column_double(queryStatement, 1)
                    stats[cat] = duration
                }
            }
        }
        sqlite3_finalize(queryStatement)
        return stats
    }
    
    func getAllRules() -> [[String: Any]] {
        let query = "SELECT id, app_name, title_pattern, category FROM rules ORDER BY id ASC;"
        var statement: OpaquePointer?
        var rulesList: [[String: Any]] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                var appName = ""
                if let nameCol = sqlite3_column_text(statement, 1) {
                    appName = String(cString: nameCol)
                }
                var titlePattern = ""
                if let titleCol = sqlite3_column_text(statement, 2) {
                    titlePattern = String(cString: titleCol)
                }
                var category = ""
                if let catCol = sqlite3_column_text(statement, 3) {
                    category = String(cString: catCol)
                }
                
                let ruleDict: [String: Any] = [
                    "id": id,
                    "appName": appName,
                    "titlePattern": titlePattern,
                    "category": category
                ]
                rulesList.append(ruleDict)
            }
        }
        sqlite3_finalize(statement)
        return rulesList
    }
    
    func deleteRule(id: Int) {
        let deleteQuery = "DELETE FROM rules WHERE id = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(id))
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        // Recalculate categories of events to reflect the deletion
        // Fetch matching rows to memory first to avoid SQLite write locks during select statement execution
        var eventsToUpdate: [(id: Int, appName: String, windowTitle: String)] = []
        let selectQuery = "SELECT id, app_name, window_title FROM events WHERE is_idle = 0;"
        var selectStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, selectQuery, -1, &selectStmt, nil) == SQLITE_OK {
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                let eventId = Int(sqlite3_column_int(selectStmt, 0))
                var appName = ""
                if let nameCol = sqlite3_column_text(selectStmt, 1) {
                    appName = String(cString: nameCol)
                }
                var windowTitle = ""
                if let titleCol = sqlite3_column_text(selectStmt, 2) {
                    windowTitle = String(cString: titleCol)
                }
                eventsToUpdate.append((eventId, appName, windowTitle))
            }
        }
        sqlite3_finalize(selectStmt)
        
        for event in eventsToUpdate {
            let newCategory = getCategoryFor(appName: event.appName, windowTitle: event.windowTitle)
            updateEventCategory(eventId: event.id, category: newCategory)
        }
    }
    
    func getFocusStatsForDate(dateStr: String, device: String = "Mac") -> (focused: TimeInterval, multitasking: TimeInterval) {
        let events = getEventsForDate(dateStr: dateStr, device: device)
        
        var focusedDuration: TimeInterval = 0.0
        var multitaskingDuration: TimeInterval = 0.0
        
        for event in events {
            if event.isIdle || event.appName == "Idle" { continue }
            
            let cat = event.category
            let isFocusCategory = cat != "Uncategorized" && cat != "Entertainment" && cat != "Social" && cat != "Idle"
            
            if isFocusCategory {
                focusedDuration += event.duration
            } else {
                multitaskingDuration += event.duration
            }
        }
        
        return (focusedDuration, multitaskingDuration)
    }
    
    private func getPastDates(from dateStr: String, count: Int) -> [String] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        
        guard let date = dateFormatter.date(from: dateStr) else { return [] }
        var dates: [String] = []
        
        let calendar = Calendar.current
        for i in (0..<count).reversed() {
            if let d = calendar.date(byAdding: .day, value: -i, to: date) {
                dates.append(dateFormatter.string(from: d))
            }
        }
        return dates
    }
    
    func getWeeklyReport(relativeTo dateStr: String, device: String = "Mac") -> [String: Any] {
        let thisWeekDates = getPastDates(from: dateStr, count: 7)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        
        var priorWeekDateStr = dateStr
        if let baseDate = dateFormatter.date(from: dateStr),
           let priorDate = Calendar.current.date(byAdding: .day, value: -7, to: baseDate) {
            priorWeekDateStr = dateFormatter.string(from: priorDate)
        }
        let priorWeekDates = getPastDates(from: priorWeekDateStr, count: 7)
        
        var dailyStats: [[String: Any]] = []
        var thisWeekActive: TimeInterval = 0
        var thisWeekIdle: TimeInterval = 0
        var thisWeekFocused: TimeInterval = 0
        var thisWeekMultitasking: TimeInterval = 0
        var categoryTotals: [String: Double] = [:]
        
        for d in thisWeekDates {
            let stats = getStatsForDate(dateStr: d, device: device)
            let focus = getFocusStatsForDate(dateStr: d, device: device)
            
            thisWeekActive += stats.totalActive
            thisWeekIdle += stats.totalIdle
            thisWeekFocused += focus.focused
            thisWeekMultitasking += focus.multitasking
            
            let daily: [String: Any] = [
                "date": d,
                "active": stats.totalActive,
                "idle": stats.totalIdle,
                "focused": focus.focused,
                "multitasking": focus.multitasking
            ]
            dailyStats.append(daily)
            
            let catStats = getCategoryStatsForDate(dateStr: d, device: device)
            for (cat, dur) in catStats {
                categoryTotals[cat, default: 0.0] += dur
            }
        }
        
        var priorWeekActive: TimeInterval = 0

        var priorWeekIdle: TimeInterval = 0
        var priorWeekFocused: TimeInterval = 0
        var priorWeekMultitasking: TimeInterval = 0
        
        for d in priorWeekDates {
            let stats = getStatsForDate(dateStr: d, device: device)
            let focus = getFocusStatsForDate(dateStr: d, device: device)
            
            priorWeekActive += stats.totalActive
            priorWeekIdle += stats.totalIdle
            priorWeekFocused += focus.focused
            priorWeekMultitasking += focus.multitasking
        }
        
        let report: [String: Any] = [

            "dailyStats": dailyStats,
            "categoryStats": categoryTotals,
            "thisWeek": [
                "active": thisWeekActive,
                "idle": thisWeekIdle,
                "focused": thisWeekFocused,
                "multitasking": thisWeekMultitasking
            ],
            "priorWeek": [
                "active": priorWeekActive,
                "idle": priorWeekIdle,
                "focused": priorWeekFocused,
                "multitasking": priorWeekMultitasking
            ]
        ]
        return report
    }
    
    func getDevices() -> [String] {
        let query = "SELECT DISTINCT device FROM events;"
        var statement: OpaquePointer?
        var devices: [String] = ["Mac"] // Always have Mac
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let devCol = sqlite3_column_text(statement, 0) {
                    let dev = String(cString: devCol)
                    if !devices.contains(dev) && !dev.isEmpty {
                        devices.append(dev)
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        return devices
    }
}


