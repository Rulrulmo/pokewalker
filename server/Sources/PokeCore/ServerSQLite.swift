import CSQLite
import Foundation

// SQLite's C API, as thin as the server's dozen queries need: open, exec, rows (named :parameters), a transaction.
// One connection, used by one owner at a time (SaveDB is an actor; the admin CLI is one process of its own).

struct SQLError: Error, CustomStringConvertible {
    let code: Int32, message: String
    var description: String { "sqlite \(code): \(message)" }
}

enum SQLValue: Sendable, Equatable { case int(Int), real(Double), text(String), null }

struct Row {
    let values: [String: SQLValue]
    func int(_ c: String) -> Int? { if case .int(let n)? = values[c] { n } else { nil } }
    func text(_ c: String) -> String? { if case .text(let s)? = values[c] { s } else { nil } }
    func real(_ c: String) -> Double? { switch values[c] { case .real(let x)?: x; case .int(let n)?: Double(n); default: nil } }
    /// For printing: a number, a text or "" (NULL).
    func show(_ c: String) -> String {
        switch values[c] {
        case .int(let n)?: String(n)
        case .real(let d)?: String(d)
        case .text(let s)?: s
        default: ""
        }
    }
}

/// SQLITE_TRANSIENT (a macro Swift doesn't import): sqlite copies the bound bytes before the call returns.
private var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

final class SQLite {
    private let handle: OpaquePointer

    /// create: false opens an existing file only (a wrong path must not leave an empty database behind).
    init(path: String, create: Bool) throws {
        var h: OpaquePointer?
        let rc = sqlite3_open_v2(path, &h, SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0), nil)
        guard rc == SQLITE_OK, let h else {
            let message = h.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close(h)
            throw SQLError(code: rc, message: "\(path): \(message)")
        }
        handle = h
    }
    deinit { sqlite3_close_v2(handle) }

    private func failure(_ rc: Int32) -> SQLError { SQLError(code: rc, message: String(cString: sqlite3_errmsg(handle))) }

    /// Statements without parameters or rows (pragmas, the schema, BEGIN / COMMIT).
    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        guard rc == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? ""
            sqlite3_free(err)
            throw SQLError(code: rc, message: message)
        }
    }

    /// One statement, `:name` parameters bound from `args` (keys without the colon); every row, columns by name.
    @discardableResult func rows(_ sql: String, _ args: [String: SQLValue] = [:]) throws -> [Row] {
        var st: OpaquePointer?
        var rc = sqlite3_prepare_v2(handle, sql, -1, &st, nil)
        guard rc == SQLITE_OK, let st else { throw failure(rc) }
        defer { sqlite3_finalize(st) }
        for (name, value) in args {
            let i = sqlite3_bind_parameter_index(st, ":" + name)
            guard i > 0 else { throw SQLError(code: SQLITE_RANGE, message: "no parameter :\(name) in \(sql)") }
            switch value {
            case .int(let n): rc = sqlite3_bind_int64(st, i, Int64(n))
            case .real(let d): rc = sqlite3_bind_double(st, i, d)
            case .text(let s): rc = s.utf8CString.withUnsafeBufferPointer { sqlite3_bind_text(st, i, $0.baseAddress, Int32(s.utf8.count), transient) }
            case .null: rc = sqlite3_bind_null(st, i)
            }
            guard rc == SQLITE_OK else { throw failure(rc) }
        }
        var out: [Row] = []
        while true {
            rc = sqlite3_step(st)
            if rc == SQLITE_DONE { return out }
            guard rc == SQLITE_ROW else { throw failure(rc) }
            var row: [String: SQLValue] = [:]
            for c in 0..<sqlite3_column_count(st) {
                let name = String(cString: sqlite3_column_name(st, c))
                switch sqlite3_column_type(st, c) {
                case SQLITE_INTEGER: row[name] = .int(Int(sqlite3_column_int64(st, c)))
                case SQLITE_FLOAT: row[name] = .real(sqlite3_column_double(st, c))
                case SQLITE_NULL: row[name] = .null
                default:                                                                                   // text (and blobs, read as UTF-8)
                    let p = sqlite3_column_text(st, c), n = Int(sqlite3_column_bytes(st, c))
                    row[name] = .text(p.map { String(decoding: UnsafeBufferPointer(start: $0, count: n), as: UTF8.self) } ?? "")
                }
            }
            out.append(Row(values: row))
        }
    }

    /// Rows changed by the last statement.
    var changes: Int { Int(sqlite3_changes(handle)) }

    /// BEGIN IMMEDIATE … COMMIT around `body`; ROLLBACK when it throws. The write lock comes first, so a reader can't turn into a writer that loses.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }
}
