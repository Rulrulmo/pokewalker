import Foundation

// pokeserver <command>: the server (serve) and the admin tools (08b §7), one binary over the same SQLite file.
// Run them as the pokewalker user (sudo -u pokewalker): a root-owned -wal / -shm would lock the server out.

let usage = """
    usage: pokeserver <command> [--db <path>]
      serve                              the API on 127.0.0.1:$PORT (env APP_KEY, PORT=8787, DB_PATH), and with DOWNLOAD_PASSWORD
                                         the team's download page at / (RELEASE_DIR=/var/lib/pokewalker/release, server/publish.sh fills it)
      init                               make the database file and its tables (the only command that creates it)
      list                               every trainer, today's steps first
      show <id>                          one trainer: the row, its history and legacy copies
      walk <id> [<rev> <reason>]         the save's JSON (or a history copy's) on stdout
      rollback <id> <rev> <reason>       put a history copy back as a new rev
      set <id> <json-path> <json-value>  change one value: set 민 '$.watts' 0
      rename <id> <new id>               a new name (a new key logs the old PCs out)
      delete <id> --yes                  remove a trainer (the save is kept as a file next to the database)
      legacy [<id>]                      pre-server saves
      suspects [<days>]                  trainers whose saves the checks flagged (docs/plans/10 §2), and the busiest walkers (default 7 days)
      flags <id> [<n>]                   one trainer's flagged saves, newest first (default 30)
      pin-reset <id>                     forget the trainer's PIN and every PC's trust: the next login sets a new one
      mons <id>                          the Pokémon the server issued to a trainer (uid, species, kind, state, 이로치, IV total) and its grants
      actions <id> [<n>]                 3.0: a trainer's acts (steps cut, refusals), what's on now, today's steps (default 30)
      prune                              drop old history now (the server does it hourly)
      sample                             a new save's JSON (Walk(), the one-time checks marked done)
      verify-release <dir>               a release folder: manifest.sig checks with the release key, each zip's size and SHA-256 (publish.sh)
    --db: else $DB_PATH, else /var/lib/pokewalker/pokewalker.db
    """

func fail(_ message: String) -> Int32 {
    FileHandle.standardError.write(Data("pokeserver: \(message)\n".utf8))
    return 1
}

/// Columns padded to the terminal width of their text (Hangul and other wide letters count 2).
func table(_ header: [String], _ rows: [[String]]) -> String {
    func width(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { n, u in
            let v = u.value
            let wide = (0x1100...0x115F).contains(v) || (0x2E80...0xA4CF).contains(v) || (0xAC00...0xD7A3).contains(v)
                || (0xF900...0xFAFF).contains(v) || (0xFE30...0xFE4F).contains(v) || (0xFF00...0xFF60).contains(v) || (0xFFE0...0xFFE6).contains(v)
            return n + (wide ? 2 : 1)
        }
    }
    let all = [header] + rows
    let widths = header.indices.map { c in all.map { width($0[c]) }.max() ?? 0 }
    return all.map { r in
        r.indices.map { c in r[c] + String(repeating: " ", count: widths[c] - width(r[c])) }.joined(separator: "  ").replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }.joined(separator: "\n")
}

/// A new trainer's save (08 §5): the app's Walk(), the one-time checks (1.7 audit, 1.10 ball refund) already done, the starter's issued uid;
/// the device's fields empty.
func sampleWalk() throws -> String {
    var w = Walk()
    w.audited = 2; w.ballsRefunded = true
    w.companion.uid = firstUID; w.lastUID = firstUID                                             // the starter as 2.1's create issues it (10 §4.1)
    let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
    return String(decoding: try enc.encode(w), as: UTF8.self)
}

extension SaveDB {
    func key(_ id: String) throws -> String {
        guard let t = trainerID(id) else { throw ServerError(description: "\(id): not a trainer ID (2–12 of 가-힣 A-Z a-z 0-9 _)") }
        guard try trainer(t.key) != nil else { throw ServerError(description: "\(id): no such trainer") }
        return t.key
    }

    func list() throws -> String {
        let rows = try db.rows("""
            SELECT name, key, rev, json_extract(walk, '$.day') AS day,
              CASE WHEN json_extract(walk, '$.day') = date('now', 'localtime') THEN json_extract(walk, '$.today') ELSE 0 END AS today,
              json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts,
              datetime(updated_at, 'unixepoch', 'localtime') AS saved, last_device
            FROM trainers ORDER BY today DESC, total DESC, key
            """)
        let cols = ["name", "key", "rev", "day", "today", "total", "watts", "saved", "last_device"]
        return table(cols, rows.map { r in cols.map(r.show) }) + "\n\(rows.count) trainer(s)"
    }

    func show(_ id: String) throws -> String {
        let k = try key(id)
        let t = try db.rows("""
            SELECT name, key, rev, app, writer, device, last_device, json_extract(walk, '$.day') AS day, json_extract(walk, '$.today') AS today,
              json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts, json_extract(walk, '$.bp') AS bp,
              json_array_length(walk, '$.box') AS box, length(walk) AS bytes,
              datetime(created_at, 'unixepoch', 'localtime') AS created, datetime(updated_at, 'unixepoch', 'localtime') AS saved
            FROM trainers WHERE key = :k
            """, ["k": .text(k)])[0]
        func dash(_ c: String) -> String { let v = t.show(c); return v.isEmpty ? "-" : v }
        let writer = t.text("writer").map { $0 == "admin" ? "admin" : String($0.prefix(8)) + "…" } ?? "-"
        var out = """
            \(t.show("name")) (key \(t.show("key"))) · rev \(t.show("rev")) · app \(t.text("app") ?? "-") · writer \(writer)
            PC \(t.text("last_device") ?? "-") (\(t.text("device") ?? "no session")) · saved \(t.show("saved")) · created \(t.show("created"))
            day \(dash("day")) · today \(dash("today")) · total \(dash("total")) · watts \(dash("watts")) · bp \(dash("bp")) · box \(dash("box")) · \(dash("bytes")) bytes
            """
        let h = try db.rows("""
            SELECT rev, reason, datetime(at, 'unixepoch', 'localtime') AS at, json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts
            FROM history WHERE key = :k ORDER BY at DESC, rev DESC
            """, ["k": .text(k)])
        out += "\n\nhistory (\(h.count))\n" + table(["rev", "reason", "at", "total", "watts"], h.map { r in ["rev", "reason", "at", "total", "watts"].map(r.show) })
        let l = try db.rows("""
            SELECT device, datetime(at, 'unixepoch', 'localtime') AS at, json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts
            FROM legacy WHERE key = :k ORDER BY at
            """, ["k": .text(k)])
        if !l.isEmpty { out += "\n\nlegacy (\(l.count))\n" + table(["device", "at", "total", "watts"], l.map { r in ["device", "at", "total", "watts"].map(r.show) }) }
        return out
    }

    /// The save (or a history copy) as stored.
    func walkText(_ id: String, rev: Int? = nil, reason: String? = nil) throws -> String {
        let k = try key(id)
        if let rev, let reason {
            guard let w = try db.rows("SELECT walk FROM history WHERE key = :k AND rev = :r AND reason = :why", ["k": .text(k), "r": .int(rev), "why": .text(reason)]).first?.text("walk")
            else { throw ServerError(description: "\(id): no history copy (\(rev), \(reason)) — see pokeserver show \(id)") }
            return w
        }
        guard let w = try trainer(k)?.walk else { throw ServerError(description: "\(id): no save yet (rev 0)") }
        return w
    }

    /// An admin's change, in one transaction: the current save kept as history('admin'), the new one at rev + 1 by writer 'admin'
    /// (the PC's next save then gets 409 stale and takes this one). A text the app couldn't decode rolls it all back.
    private func adminWrite(_ k: String, _ make: () throws -> String, now: Int) throws -> (from: Int, to: Int) {
        try db.transaction {
            guard let t = try trainer(k) else { throw ServerError(description: "\(k): no such trainer") }
            let walk = try make()
            guard walkDecodes(walk) else { throw ServerError(description: "the result isn't a save the app can load (Walk, version 1) — nothing changed") }
            if let old = t.walk {
                try db.rows("INSERT OR REPLACE INTO history (key, rev, reason, at, walk) VALUES (:k, :r, 'admin', :now, :w)",
                            ["k": .text(k), "r": .int(t.rev), "now": .int(now), "w": .text(old)])
            }
            try db.rows("UPDATE trainers SET walk = :w, rev = :r, writer = 'admin' WHERE key = :k", ["w": .text(walk), "r": .int(t.rev + 1), "k": .text(k)])
            return (t.rev, t.rev + 1)
        }
    }

    func rollback(_ id: String, rev: Int, reason: String, now: Int) throws -> String {
        let k = try key(id), copy = try walkText(id, rev: rev, reason: reason)
        let r = try adminWrite(k, { copy }, now: now)
        return "\(k): history (\(rev), \(reason)) is rev \(r.to) now (rev \(r.from) kept as admin)"
    }

    func set(_ id: String, path: String, value: String, now: Int) throws -> String {
        let k = try key(id)
        let r = try adminWrite(k, {
            guard let w = try db.rows("SELECT json_set(coalesce(walk, '{}'), :p, json(:v)) AS w FROM trainers WHERE key = :k",
                                      ["p": .text(path), "v": .text(value), "k": .text(k)]).first?.text("w")
            else { throw ServerError(description: "json_set gave nothing") }
            return w
        }, now: now)
        return "\(k): \(path) = \(value) → rev \(r.to) (rev \(r.from) kept as admin)"
    }

    /// A new name; a new key moves the trainer, its history and legacy rows (a legacy row whose (key, device) is taken stays put) and ends the session.
    func rename(_ id: String, to newID: String) throws -> String {
        let k = try key(id)
        guard let n = trainerID(newID) else { throw ServerError(description: "\(newID): not a trainer ID (2–12 of 가-힣 A-Z a-z 0-9 _)") }
        return try db.transaction {
            if n.key == k {
                try db.rows("UPDATE trainers SET name = :n WHERE key = :k", ["n": .text(n.name), "k": .text(k)])
                return "\(k): name is \(n.name) now (same key, the session stays)"
            }
            guard try trainer(n.key) == nil else { throw ServerError(description: "\(newID): already a trainer") }
            let a: [String: SQLValue] = ["k": .text(k), "nk": .text(n.key)]
            try db.rows("UPDATE trainers SET key = :nk, name = :n, session = NULL, device = NULL WHERE key = :k", a.merging(["n": .text(n.name)]) { $1 })
            try db.rows("UPDATE history SET key = :nk WHERE key = :k", a)
            try db.rows("UPDATE OR IGNORE legacy SET key = :nk WHERE key = :k", a)
            for t in ["pins", "flags", "mons", "chains", "grants", "steps_day", "actions"] { try db.rows("UPDATE \(t) SET key = :nk WHERE key = :k", a) }
            for t in ["trust", "pin_fails", "play"] { try db.rows("DELETE FROM \(t) WHERE key = :k", ["k": .text(k)]) }   // play: the session ends anyway
            try db.rows("UPDATE inbox SET to_key = :nk WHERE to_key = :k", a); try db.rows("UPDATE inbox SET from_key = :nk WHERE from_key = :k", a)
            return "\(k) → \(n.key) (\(n.name)); its PC gets no_trainer on its next save and asks for an ID"
        }
    }

    /// The save goes to deleted-<key>-<unix>.json next to the database first; legacy rows stay.
    func delete(_ id: String, now: Int) throws -> String {
        let k = try key(id)
        return try db.transaction {
            var kept = "no save to keep (rev 0)"
            if let w = try trainer(k)?.walk {
                let file = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("deleted-\(k)-\(now).json")
                try Data(w.utf8).write(to: file, options: .atomic)
                kept = "save kept as \(file.path)"
            }
            for t in ["history", "trainers", "pins", "trust", "pin_fails", "mons", "chains", "grants", "play", "steps_day", "actions"] { try db.rows("DELETE FROM \(t) WHERE key = :k", ["k": .text(k)]) }
            try db.rows("DELETE FROM inbox WHERE to_key = :k OR from_key = :k", ["k": .text(k)])
            return "\(k): deleted, \(kept)"
        }
    }

    /// 10 §2.3: who the checks flagged in the last `days` (how often, the latest reasons), then today's walkers by steps.
    func suspects(days: Int, now: Int) throws -> String {
        let since = now - days * 86_400
        let f = try db.rows("""
            SELECT t.name, f.key, count(*) AS saves, datetime(max(f.at), 'unixepoch', 'localtime') AS last,
              (SELECT reasons FROM flags g WHERE g.key = f.key ORDER BY g.at DESC LIMIT 1) AS latest
            FROM flags f LEFT JOIN trainers t ON t.key = f.key WHERE f.at >= :since GROUP BY f.key ORDER BY saves DESC
            """, ["since": .int(since)])
        var out = "flagged in \(days) day(s): \(f.count)\n" + table(["name", "key", "saves", "last", "latest"], f.map { r in
            ["name", "key", "saves", "last"].map(r.show) + [String(r.show("latest").prefix(90))] })
        let w = try db.rows("""
            SELECT name, key, json_extract(walk, '$.today') AS today, json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts,
              json_extract(walk, '$.bp') AS bp, json_array_length(walk, '$.box') AS box
            FROM trainers WHERE json_extract(walk, '$.day') = date('now', 'localtime') ORDER BY today DESC LIMIT 10
            """)
        out += "\n\ntoday's walkers (a day's cap is \(SaveCheck.daySteps))\n" + table(["name", "key", "today", "total", "watts", "bp", "box"], w.map { r in ["name", "key", "today", "total", "watts", "bp", "box"].map(r.show) })
        return out
    }
    func monsList(_ id: String) throws -> String {
        let k = try key(id)
        let rows = try db.rows("""
            SELECT uid, dex, level, kind, state, json_extract(traits, '$.shiny') AS shiny,
              (SELECT sum(value) FROM json_each(json_extract(traits, '$.ivs'))) AS ivs, datetime(at, 'unixepoch', 'localtime') AS at
            FROM mons WHERE key = :k ORDER BY uid
            """, ["k": .text(k)])
        let g = try db.rows("SELECT datetime(at, 'unixepoch', 'localtime') AS at, watts, bp, item, why FROM grants WHERE key = :k ORDER BY at DESC LIMIT 20", ["k": .text(k)])
        return table(["uid", "dex", "level", "kind", "state", "shiny", "ivs", "at"], rows.map { r in ["uid", "dex", "level", "kind", "state", "shiny", "ivs", "at"].map(r.show) })
            + "\n\(rows.count) issued\n\ngrants (latest 20)\n" + table(["at", "watts", "bp", "item", "why"], g.map { r in ["at", "watts", "bp", "item", "why"].map(r.show) })
    }
    /// Plan 11: a 3.0 trainer's acts (newest first: steps cut, refusals), what's on now (radar, fight, tower run, held steps) and today's steps.
    func actionsList(_ id: String, last n: Int) throws -> String {
        let k = try key(id)
        let rows = try db.rows("SELECT datetime(at, 'unixepoch', 'localtime') AS at, seq, act, asked, taken, note FROM actions WHERE key = :k ORDER BY at DESC, seq DESC LIMIT :n",
                               ["k": .text(k), "n": .int(n)])
        var out = table(["at", "seq", "act", "asked", "taken", "note"], rows.map { r in ["at", "seq", "act", "asked", "taken", "note"].map(r.show) })
        if let p = try db.rows("SELECT seq, bank, state FROM play WHERE key = :k", ["k": .text(k)]).first,
           let play = p.text("state").flatMap({ try? JSONDecoder().decode(Play.self, from: Data($0.utf8)) }) {
            var on: [String] = []
            if let r = play.radar { on.append("radar (bush \(r.bush), chain \(r.chain), #\(r.mon.dex))") }
            if let c = play.chain { on.append("a chain held at \(c)") }
            if let b = play.battle { on.append(b.trainer.map { "a tower fight vs \($0)" } ?? "a wild fight vs #\(b.wild.dex)") }
            if play.tower { on.append("a tower run") }
            if play.held > 0 { on.append("\(play.held) steps held") }
            out += "\n\nnow: " + (on.isEmpty ? "nothing" : on.joined(separator: " · ")) + " · last seq \(p.show("seq")) · step allowance \(Int(p.real("bank") ?? 0))"
        }
        let today = try db.rows("SELECT n FROM steps_day WHERE key = :k AND day = :d", ["k": .text(k), "d": .text(Walk.key(Date()))]).first?.int("n") ?? 0
        return out + "\ntoday's steps (the server's count): \(today) of \(Walk.dayCap)"
    }
    func pinReset(_ id: String) throws -> String {
        let k = try key(id)
        return try db.transaction {
            for t in ["pins", "trust", "pin_fails"] { try db.rows("DELETE FROM \(t) WHERE key = :k", ["k": .text(k)]) }
            return "\(k): PIN and trusted PCs forgotten; the next login (app 2.1 on) sets a new PIN"
        }
    }
    func flags(_ id: String, last n: Int) throws -> String {
        let k = try key(id)
        let rows = try db.rows("SELECT rev, datetime(at, 'unixepoch', 'localtime') AS at, reasons FROM flags WHERE key = :k ORDER BY at DESC, rev DESC LIMIT :n",
                               ["k": .text(k), "n": .int(n)])
        return rows.isEmpty ? "\(k): no flagged saves" : rows.map { "rev \($0.show("rev")) · \($0.show("at")) · \($0.show("reasons"))" }.joined(separator: "\n")
    }

    func legacyList(_ id: String?) throws -> String {
        let k = try id.map(key)
        let rows = try db.rows("""
            SELECT key, device, datetime(at, 'unixepoch', 'localtime') AS at, json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts
            FROM legacy \(k == nil ? "" : "WHERE key = :k") ORDER BY key, at
            """, k.map { ["k": .text($0)] } ?? [:])
        let cols = ["key", "device", "at", "total", "watts"]
        return table(cols, rows.map { r in cols.map(r.show) }) + "\n\(rows.count) legacy save(s)"
    }
}

/// The command line. The DB: --db, else DB_PATH, else /var/lib/pokewalker/pokewalker.db (sudo -u clears the environment: point elsewhere with --db).
public func run(_ arguments: [String]) async -> Int32 {
    var args = Array(arguments.dropFirst()), dbPath: String?
    if let i = args.firstIndex(of: "--db") {
        guard i + 1 < args.count else { return fail("--db needs a path") }
        dbPath = args[i + 1]; args.removeSubrange(i...i + 1)
    }
    let yes = args.contains("--yes"); args.removeAll { $0 == "--yes" }
    let env = ProcessInfo.processInfo.environment
    let path = dbPath ?? env["DB_PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/var/lib/pokewalker/pokewalker.db"
    guard let command = args.first else { print(usage); return 2 }
    let rest = Array(args.dropFirst())

    do {
        switch command {
        case "sample":
            print(try sampleWalk())
            return 0
        case "init":
            let existed = FileManager.default.fileExists(atPath: path)
            _ = try SaveDB(path: path, create: true)
            print(existed ? "\(path): there already; tables checked" : "\(path): made")
            return 0
        case "serve":
            guard let appKey = env["APP_KEY"], !appKey.isEmpty else { return fail("APP_KEY is empty (/etc/pokewalker/server.env)") }
            let port = env["PORT"].flatMap { Int($0) } ?? 8787
            let db = try SaveDB(path: path, reject: env["CHECK_MODE"] == "reject", rejectTests: env["CHECK_REJECT_TESTS"] == "1",
                                minApp: env["MIN_APP"].flatMap { $0.isEmpty || versionParts($0) == nil ? nil : $0 })
            let release = URL(fileURLWithPath: env["RELEASE_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "/var/lib/pokewalker/release", isDirectory: true)
            let site = env["DOWNLOAD_PASSWORD"].flatMap { $0.isEmpty ? nil : DownloadSite(dir: release, password: $0) }
            try await serve(db: db, appKey: appKey, port: port, site: site, release: release)
            return 0
        case "verify-release":                                                            // publish.sh: before anything goes up
            guard rest.count == 1 else { return fail("verify-release <dir>") }
            let m = try ReleaseFiles.verify(URL(fileURLWithPath: rest[0], isDirectory: true))
            print("release \(m.version) (build \(m.build), \(m.commit.prefix(7))): signed by the release key; " + [("mac", m.mac), ("windows", m.windows)].compactMap { k, e in e.map { "\(k) \($0.size) bytes ok" } }.joined(separator: ", "))
            return 0
        case "-h", "--help", "help":
            print(usage)
            return 0
        default: break
        }

        let db = try SaveDB(path: path)
        let out: String
        switch (command, rest.count) {
        case ("list", 0): out = try await db.list()
        case ("show", 1): out = try await db.show(rest[0])
        case ("walk", 1): out = try await db.walkText(rest[0])
        case ("walk", 3):
            guard let rev = Int(rest[1]) else { return fail("walk: <rev> is a number") }
            out = try await db.walkText(rest[0], rev: rev, reason: rest[2])
        case ("rollback", 3):
            guard let rev = Int(rest[1]) else { return fail("rollback: <rev> is a number") }
            out = try await db.rollback(rest[0], rev: rev, reason: rest[2], now: unixNow())
        case ("set", 3): out = try await db.set(rest[0], path: rest[1], value: rest[2], now: unixNow())
        case ("rename", 2): out = try await db.rename(rest[0], to: rest[1])
        case ("delete", 1):
            guard yes else { return fail("delete \(rest[0]): add --yes (the save is kept as a file, its history goes)") }
            out = try await db.delete(rest[0], now: unixNow())
        case ("legacy", 0), ("legacy", 1): out = try await db.legacyList(rest.first)
        case ("prune", 0): out = "\(try await db.prune(now: unixNow())) history row(s) dropped"
        case ("suspects", 0), ("suspects", 1):
            guard let days = rest.first.map({ Int($0) }) ?? 7 else { return fail("suspects: <days> is a number") }
            out = try await db.suspects(days: days, now: unixNow())
        case ("pin-reset", 1): out = try await db.pinReset(rest[0])
        case ("mons", 1): out = try await db.monsList(rest[0])
        case ("actions", 1), ("actions", 2):
            guard let n = rest.count > 1 ? Int(rest[1]) : 30 else { return fail("actions: <n> is a number") }
            out = try await db.actionsList(rest[0], last: n)
        case ("flags", 1), ("flags", 2):
            guard let n = rest.count > 1 ? Int(rest[1]) : 30 else { return fail("flags: <n> is a number") }
            out = try await db.flags(rest[0], last: n)
        default:
            return fail("\(([command] + rest).joined(separator: " ")): not a command (or not its arguments)\n\(usage)")
        }
        print(out)
        return 0
    } catch {
        return fail("\(error)")
    }
}
