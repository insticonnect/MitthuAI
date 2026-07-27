import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin thread-safe wrapper over the system SQLite. All access is funneled
/// through one serial queue; public methods must never call each other
/// from inside a queue block (they don't — each is a single prepare/step).
final class SQLiteDB {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.mitthuai.db")

    init(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("MitthuAI DB: failed to open \(path)")
        }
        execInternal("PRAGMA journal_mode=WAL;")
        execInternal("PRAGMA foreign_keys=ON;")
    }

    deinit { sqlite3_close(db) }

    private func execInternal(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("MitthuAI DB exec error: \(String(cString: e)) in: \(sql.prefix(120))")
        }
    }

    func exec(_ sql: String) {
        queue.sync { execInternal(sql) }
    }

    @discardableResult
    func run(_ sql: String, _ params: [Any?] = []) -> Int64 {
        return queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("MitthuAI DB prepare error: \(String(cString: sqlite3_errmsg(db))) in: \(sql.prefix(120))")
                return -1
            }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, params)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE && rc != SQLITE_ROW {
                print("MitthuAI DB step error: \(String(cString: sqlite3_errmsg(db))) in: \(sql.prefix(120))")
            }
            return sqlite3_last_insert_rowid(db)
        }
    }

    func query(_ sql: String, _ params: [Any?] = []) -> [[String: Any]] {
        return queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("MitthuAI DB prepare error: \(String(cString: sqlite3_errmsg(db))) in: \(sql.prefix(120))")
                return []
            }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, params)
            var rows: [[String: Any]] = []
            let colCount = sqlite3_column_count(stmt)
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                for i in 0..<colCount {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_INTEGER:
                        row[name] = sqlite3_column_int64(stmt, i)
                    case SQLITE_FLOAT:
                        row[name] = sqlite3_column_double(stmt, i)
                    case SQLITE_TEXT:
                        if let c = sqlite3_column_text(stmt, i) { row[name] = String(cString: c) }
                    case SQLITE_BLOB:
                        if let bytes = sqlite3_column_blob(stmt, i) {
                            row[name] = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, i)))
                        }
                    default:
                        break
                    }
                }
                rows.append(row)
            }
            return rows
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ params: [Any?]) {
        for (idx, p) in params.enumerated() {
            let i = Int32(idx + 1)
            switch p {
            case nil:
                sqlite3_bind_null(stmt, i)
            case let v as Int:
                sqlite3_bind_int64(stmt, i, Int64(v))
            case let v as Int64:
                sqlite3_bind_int64(stmt, i, v)
            case let v as Double:
                sqlite3_bind_double(stmt, i, v)
            case let v as Bool:
                sqlite3_bind_int64(stmt, i, v ? 1 : 0)
            case let v as String:
                sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)
            case let v as Data:
                _ = v.withUnsafeBytes { raw in
                    sqlite3_bind_blob(stmt, i, raw.baseAddress, Int32(v.count), SQLITE_TRANSIENT)
                }
            default:
                sqlite3_bind_null(stmt, i)
            }
        }
    }
}

// Convenience accessors for JSONSerialization-style rows.
extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int { (self[key] as? Int64).map { Int($0) } ?? (self[key] as? Int) ?? 0 }
    func double(_ key: String) -> Double {
        if let d = self[key] as? Double { return d }
        if let i = self[key] as? Int64 { return Double(i) }
        return 0
    }
    func str(_ key: String) -> String { self[key] as? String ?? "" }
}
