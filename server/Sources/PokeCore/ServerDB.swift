import Foundation

// The save server's rules (docs/plans/08b-server-home.md §4–5): login / create / save / legacy over one SQLite file.
// The server is a store: it checks a save's form (it decodes as the app's Walk, version 1), never its contents.

let bodyLimit = 4 << 20                  // a request body: 4 MiB, more = 413
let walkLimit = 2_000_000                // a save's text in UTF-8 bytes (08's 2 MB), more = 413
let busySeconds = 300                    // another PC saved this long ago: login asks first (busy)
let conflictsKept = 10                   // history('conflict') rows per trainer
let legacyKept = 4                       // legacy rows per trainer (one per PC)

// MARK: - requests and replies

struct LoginReq: Codable, Sendable { let id, device, device_name: String; let app: String?; let force: Bool? }
struct CreateReq: Codable, Sendable { let id, device, device_name: String }
struct SaveReq: Codable, Sendable { let id, session, app: String; let base: Int; let walk: String }
struct LegacyReq: Codable, Sendable { let id, device, walk: String }

/// A reply's values: flat objects of strings, numbers, booleans and null (login's "walk": null before the first save).
enum JSON: Encodable, Sendable, Equatable {
    case s(String), i(Int), b(Bool), null
    static func str(_ v: String?) -> JSON { v.map(JSON.s) ?? .null }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .s(let v): try c.encode(v)
        case .i(let v): try c.encode(v)
        case .b(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

/// A status and its JSON body; `note` goes to the log with the trainer's key (replaced, stale, 426, new trainers, errors).
struct Reply: Sendable {
    let status: Int, body: Data, note: String?
    init(_ status: Int, _ value: [String: JSON], note: String? = nil) {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.status = status; self.body = (try? enc.encode(value)) ?? Data("{}".utf8); self.note = note
    }
    /// {"error": code, …more}
    static func error(_ status: Int, _ code: String, _ more: [String: JSON] = [:], note: String? = nil) -> Reply {
        Reply(status, more.merging(["error": .s(code)]) { _, e in e }, note: note)
    }
}

// versionParts / verCmp: Sources/Model/Version.swift (the app compares its updates with them too)

/// A save the app could load: the app's own Walk decodes it, version 1.
func walkDecodes(_ text: String) -> Bool { (try? JSONDecoder().decode(Walk.self, from: Data(text.utf8)))?.version == 1 }
func deviceOK(_ d: String) -> Bool { !d.isEmpty && d.count <= 64 }
func newSession() -> String { hex((0..<16).map { _ in UInt8.random(in: 0...255) }) }

/// The `trainers` row.
struct Trainer {
    let key, name: String, rev: Int
    let app, session, writer, device, lastDevice: String?
    let createdAt, updatedAt: Int
    let walk: String?
    init(_ r: Row) {
        key = r.text("key") ?? ""; name = r.text("name") ?? ""; rev = r.int("rev") ?? 0
        app = r.text("app"); session = r.text("session"); writer = r.text("writer"); device = r.text("device"); lastDevice = r.text("last_device")
        createdAt = r.int("created_at") ?? 0; updatedAt = r.int("updated_at") ?? 0; walk = r.text("walk")
    }
}

struct ServerError: Error, CustomStringConvertible { let description: String }

// MARK: - the database

let schema = """
    CREATE TABLE IF NOT EXISTS trainers (key TEXT PRIMARY KEY, name TEXT NOT NULL, rev INTEGER NOT NULL, app TEXT,
      session TEXT, writer TEXT, device TEXT, last_device TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, walk TEXT);
    CREATE TABLE IF NOT EXISTS history (key TEXT NOT NULL, rev INTEGER NOT NULL, reason TEXT NOT NULL, at INTEGER NOT NULL, walk TEXT NOT NULL,
      PRIMARY KEY (key, rev, reason));
    CREATE TABLE IF NOT EXISTS legacy (key TEXT NOT NULL, device TEXT NOT NULL, at INTEGER NOT NULL, walk TEXT NOT NULL, PRIMARY KEY (key, device));
    CREATE TABLE IF NOT EXISTS flags (key TEXT NOT NULL, rev INTEGER NOT NULL, at INTEGER NOT NULL, reasons TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS flags_key ON flags (key, at);
    """
// `walk` is every table's last column: SQLite follows a big TEXT's overflow pages to read the columns after it.

/// The one connection and the rules (08b 판정 7–13). One request = one method = one transaction; `now` comes in so tests can move the clock.
// ponytail: one connection, one writer; a reader pool if it ever matters
actor SaveDB {
    let db: SQLite
    let path: String
    let reject: Bool                                                       // CHECK_MODE=reject: an implausible save is refused (422), else only recorded

    /// create: only `pokeserver init` and the tests make the file; anything else on a missing file throws (a wrong DB_PATH must not start an empty server).
    init(path: String, create: Bool = false, reject: Bool = false) throws {
        guard create || FileManager.default.fileExists(atPath: path) else { throw ServerError(description: "\(path): no database (pokeserver init makes it)") }
        let c = try SQLite(path: path, create: create)
        try c.exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL; PRAGMA busy_timeout = 5000; PRAGMA max_page_count = 2621440;")   // 4 KiB × 2621440 = 10 GiB
        if create || FileManager.default.fileExists(atPath: path) { try c.exec(schema) }   // tables added since (flags) come in on any open: IF NOT EXISTS
        db = c; self.path = path; self.reject = reject
    }

    /// 판정 2–6, no database needed: the route runs it before awaiting the actor (a 2 MB decode doesn't hold the DB up).
    static func precheck(_ r: SaveReq) -> Reply? {
        if r.base < 0 { return .error(400, "bad_request") }
        if trainerID(r.id) == nil { return .error(400, "bad_id") }
        if r.walk.utf8.count > walkLimit { return .error(413, "too_big") }
        if !walkDecodes(r.walk) { return .error(400, "bad_walk") }
        if versionParts(r.app) == nil { return .error(400, "bad_app") }
        return nil
    }

    func trainer(_ key: String) throws -> Trainer? {
        try db.rows("SELECT key, name, rev, app, session, writer, device, last_device, created_at, updated_at, walk FROM trainers WHERE key = :k",
                    ["k": .text(key)]).first.map(Trainer.init)
    }

    /// A throw (an SQLite error, SQLITE_FULL at the page cap too) is a 500 with the error in the log.
    private func guarded(_ body: () throws -> Reply) -> Reply {
        do { return try body() } catch { return .error(500, "internal", note: "\(error)") }
    }

    func login(_ r: LoginReq, now: Int) -> Reply {
        guard let id = trainerID(r.id) else { return .error(400, "bad_id") }
        guard deviceOK(r.device) else { return .error(400, "bad_request") }
        if let a = r.app, versionParts(a) == nil { return .error(400, "bad_app") }
        return guarded {
            try db.transaction {
                guard let t = try trainer(id.key) else { return Reply(200, ["exists": .b(false)]) }
                if let a = r.app, let need = t.app, verCmp(a, need) ?? 0 < 0 {                          // before the session moves
                    return .error(426, "old_app", ["need": .s(need)], note: "login with app \(a) < \(need)")
                }
                if r.force != true, let d = t.device, d != r.device, now - t.updatedAt < busySeconds {  // another PC saved a moment ago: the app asks first
                    return Reply(200, ["exists": .b(true), "busy": .b(true), "name": .s(t.name), "last_device": .str(t.lastDevice), "updated_at": .i(t.updatedAt)])
                }
                let session = newSession()
                try db.rows("UPDATE trainers SET session = :s, device = :d, last_device = :n WHERE key = :k",
                            ["s": .text(session), "d": .text(r.device), "n": .text(String(r.device_name.prefix(64))), "k": .text(id.key)])
                return Reply(200, ["exists": .b(true), "name": .s(t.name), "rev": .i(t.rev), "walk": .str(t.walk), "session": .s(session),
                                   "last_device": .str(t.lastDevice), "updated_at": .i(t.updatedAt)],              // who had it, until when: before this login
                             note: t.device != nil && t.device != r.device ? "login from \(r.device_name.prefix(64)), took it from \(t.lastDevice ?? "?")" : nil)
            }
        }
    }

    func create(_ r: CreateReq, now: Int) -> Reply {
        guard let id = trainerID(r.id) else { return .error(400, "bad_id") }
        guard deviceOK(r.device) else { return .error(400, "bad_request") }
        return guarded {
            try db.transaction {
                if try trainer(id.key) != nil { return .error(409, "exists") }
                let session = newSession()
                try db.rows("INSERT INTO trainers (key, name, rev, session, device, last_device, created_at, updated_at) VALUES (:k, :n, 0, :s, :d, :dn, :now, :now)",
                            ["k": .text(id.key), "n": .text(id.name), "s": .text(session), "d": .text(r.device), "dn": .text(String(r.device_name.prefix(64))), "now": .int(now)])
                return Reply(200, ["rev": .i(0), "session": .s(session)], note: "new trainer \(id.name) from \(r.device_name.prefix(64))")
            }
        }
    }

    /// Call after `precheck`. 판정 7–13: the first row that matches decides.
    func save(_ r: SaveReq, now: Int) -> Reply {
        guard let id = trainerID(r.id) else { return .error(400, "bad_id") }
        var flagNote: String? = nil
        return guarded {
            try db.transaction {
                guard let t = try trainer(id.key) else { return .error(404, "no_trainer") }                                       // 7
                if let need = t.app, verCmp(r.app, need) ?? 0 < 0 { return .error(426, "old_app", ["need": .s(need)], note: "save with app \(r.app) < \(need)") }   // 8
                guard r.session == t.session else {                                                                                 // 9
                    try conflict(id.key, base: r.base, walk: r.walk, now: now)
                    return .error(409, "conflict", ["reason": .s("replaced")], note: "replaced (base \(r.base), rev \(t.rev))")
                }
                let rev: Int
                if r.base == t.rev { rev = t.rev + 1 }                                    // 10
                else if r.base > t.rev { rev = r.base + 1 }                               // 11: the server lost saves (a restored backup)
                else if t.writer == r.session { rev = t.rev + 1 }                         // 12: this session's resend after a lost reply
                else {                                                                    // 13: an admin's change, or an older session's rev
                    try conflict(id.key, base: r.base, walk: r.walk, now: now)
                    return .error(409, "conflict", ["reason": .s("stale"), "rev": .i(t.rev), "walk": .str(t.walk)], note: "stale (base \(r.base), rev \(t.rev), writer \(t.writer == "admin" ? "admin" : "an older session"))")
                }
                // 10 §2: the save's own values, and the change from the last one taken (the server's clock); recorded, refused in reject mode
                if let new = try? JSONDecoder().decode(Walk.self, from: Data(r.walk.utf8)) {
                    var reasons = SaveCheck.values(new)
                    if let old = t.walk.flatMap({ try? JSONDecoder().decode(Walk.self, from: Data($0.utf8)) }) { reasons += SaveCheck.changes(from: old, to: new, seconds: now - t.updatedAt) }
                    if !reasons.isEmpty {
                        try db.rows("INSERT INTO flags (key, rev, at, reasons) VALUES (:k, :r, :now, :why)",
                                    ["k": .text(id.key), "r": .int(rev), "now": .int(now), "why": .text(reasons.joined(separator: "; "))])
                        if reject { return .error(422, "implausible", ["reasons": .s(reasons.joined(separator: "; "))], note: "refused: \(reasons.joined(separator: "; "))") }
                        flagNote = "flagged: \(reasons.joined(separator: "; "))"
                    }
                }
                let app = t.app.map { verCmp($0, r.app) ?? 0 >= 0 ? $0 : r.app } ?? r.app   // the highest app that saved here (SQL max() compares text and nulls)
                try db.rows("UPDATE trainers SET walk = :w, rev = :r, app = :a, writer = :s, updated_at = :now WHERE key = :k",
                            ["w": .text(r.walk), "r": .int(rev), "a": .text(app), "s": .text(r.session), "now": .int(now), "k": .text(id.key)])
                try keep(id.key, rev: rev, walk: r.walk, now: now)
                return Reply(200, ["rev": .i(rev)], note: flagNote)
            }
        }
    }

    func legacy(_ r: LegacyReq, now: Int) -> Reply {
        guard let id = trainerID(r.id) else { return .error(400, "bad_id") }
        guard deviceOK(r.device) else { return .error(400, "bad_request") }
        if r.walk.utf8.count > walkLimit { return .error(413, "too_big") }
        guard (try? JSONSerialization.jsonObject(with: Data(r.walk.utf8))) is [String: Any] else { return .error(400, "bad_walk") }   // loose on purpose: an old save is kept as it is
        return guarded {
            try db.transaction {
                guard try trainer(id.key) != nil else { return .error(404, "no_trainer") }
                let have = try db.rows("SELECT device FROM legacy WHERE key = :k", ["k": .text(id.key)]).compactMap { $0.text("device") }
                if have.contains(r.device) || have.count >= legacyKept { return Reply(200, ["stored": .b(false)]) }       // never overwritten
                try db.rows("INSERT INTO legacy (key, device, at, walk) VALUES (:k, :d, :now, :w)",
                            ["k": .text(id.key), "d": .text(r.device), "now": .int(now), "w": .text(r.walk)])
                return Reply(200, ["stored": .b(true)], note: "legacy save from \(r.device)")
            }
        }
    }

    /// The hour's first rev and the day's (KST) first, kept as they come in: pruning is then three DELETEs.
    private func keep(_ key: String, rev: Int, walk: String, now: Int) throws {
        let a: [String: SQLValue] = ["k": .text(key), "r": .int(rev), "now": .int(now), "w": .text(walk)]
        try db.rows("""
            INSERT OR IGNORE INTO history (key, rev, reason, at, walk) SELECT :k, :r, 'hourly', :now, :w
              WHERE NOT EXISTS (SELECT 1 FROM history WHERE key = :k AND reason = 'hourly' AND at >= :now - :now % 3600)
            """, a)
        try db.rows("""
            INSERT OR IGNORE INTO history (key, rev, reason, at, walk) SELECT :k, :r, 'daily', :now, :w
              WHERE NOT EXISTS (SELECT 1 FROM history WHERE key = :k AND reason = 'daily' AND at >= :now - (:now + 32400) % 86400)
            """, a)
    }

    /// A save that lost (replaced / stale), kept for the admin: the newest `conflictsKept` per trainer (base comes from the client, so no endless 2 MB rows).
    private func conflict(_ key: String, base: Int, walk: String, now: Int) throws {
        try db.rows("""
            DELETE FROM history WHERE key = :k AND reason = 'conflict'
              AND rev NOT IN (SELECT rev FROM history WHERE key = :k AND reason = 'conflict' ORDER BY at DESC, rev DESC LIMIT :n)
            """, ["k": .text(key), "n": .int(conflictsKept - 1)])
        try db.rows("INSERT OR REPLACE INTO history (key, rev, reason, at, walk) VALUES (:k, :b, 'conflict', :now, :w)",
                    ["k": .text(key), "b": .int(base), "now": .int(now), "w": .text(walk)])
    }

    /// 48 hours of hourly copies, 90 days of daily ones, 30 days of conflicts; admin copies stay. Rows deleted.
    @discardableResult func prune(now: Int) throws -> Int {
        try db.transaction {
            var n = 0
            for (reason, age) in [("hourly", 48 * 3600), ("daily", 90 * 86400), ("conflict", 30 * 86400)] {
                try db.rows("DELETE FROM history WHERE reason = :r AND at < :t", ["r": .text(reason), "t": .int(now - age)])
                n += db.changes
            }
            return n
        }
    }
}
