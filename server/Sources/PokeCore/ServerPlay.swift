import Foundation

// docs/plans/11 (3.0): POST /v2/act — the server's side of the shared engine (Game/Model/EngineRules.swift). Here: who may act (the session,
// a PIN), in what order (seq: a resend gets the stored reply, a gap 409 seq), how many steps count (an allowance filling at 15 a second up to
// a day's, and the day's cap on the server's own count), the engine with the server's dice, new Pokémon in the ledger (mons), rev and history.
// The engine does the rest; the app never sends a save.

let actionsKept = 14 * 86400                                               // the actions log (what each act was, steps cut, refusals)

let playSchema = """
    CREATE TABLE IF NOT EXISTS play (key TEXT PRIMARY KEY, session TEXT, seq INTEGER NOT NULL, status INTEGER NOT NULL, reply TEXT,
      bank REAL NOT NULL, bank_at REAL NOT NULL, state TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS steps_day (key TEXT NOT NULL, day TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (key, day));
    CREATE TABLE IF NOT EXISTS actions (key TEXT NOT NULL, session TEXT NOT NULL, seq INTEGER NOT NULL, at INTEGER NOT NULL, act TEXT NOT NULL,
      asked INTEGER NOT NULL, taken INTEGER NOT NULL, note TEXT);
    CREATE INDEX IF NOT EXISTS actions_key ON actions (key, at);
    """

/// A trainer's `play` row: the session it's for, that session's last seq and its reply (sent again on a resend), the steps allowance
/// (unix seconds; it outlives sessions), and the engine's Play (a new session starts it over: plan 11 §0).
struct PlayRow {
    var session: String? = nil, seq = 0, status = 200, reply: String? = nil
    var bank = 0.0, bankAt = 0.0
    var play = Play()
}

func actName(_ a: Act) -> String {
    switch a {
    case .steps: "steps"; case .radar: "radar"; case .radarPick(let b): "pick \(b)"; case .tower: "tower"; case .towerPick, .towerReset: "tower pick"
    case .battle(let c): "battle \(c)"; case .buy(let bp, let i, let l, let s, let q): "buy \(i ?? l.map { "legend \($0)" } ?? s ?? "?") ×\(q)\(bp ? " (BP)" : "")"
    case .use(let i, _): "use \(i)"; case .sellAll: "sell all"; case .mon(let op): "mon \(op)"; case .course(let c): "course \(c)"; case .greet(let to): "greet \(to)"
    case .tradeOffer(let to, let g, let wnt): "trade offer → \(to) \(g)\(wnt.map { " for \($0)" } ?? "")"; case .tradeAccept(let i, let g): "trade accept #\(i)\(g.map { " with \($0)" } ?? "")"
    case .tradeDecline(let i): "trade decline #\(i)"; case .tradeCancel(let i): "trade cancel #\(i)"
    }
}
func savedText(_ w: Walk) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return String(decoding: (try? e.encode(w.shared)) ?? Data(), as: UTF8.self) }

extension SaveDB {
    static let stepsPerSecond = 15.0

    func act(_ r: ActReq, now: Date) -> Reply {
        guard let id = trainerID(r.id) else { return .error(400, "bad_id") }
        guard r.seq >= 1, (r.steps ?? 0) >= 0 else { return .error(400, "bad_request") }
        let unix = Int(now.timeIntervalSince1970)
        return guarded {
            try db.transaction {
                guard let t = try trainer(id.key) else { return .error(404, "no_trainer") }
                guard r.session == t.session else { return .error(409, "conflict", ["reason": .s("replaced")], note: "act replaced (seq \(r.seq))") }
                guard try hasPIN(id.key) else { return .error(403, "pin_needed") }
                var row = try playRow(id.key, session: r.session, since: Double(t.updatedAt), now: now)
                if r.seq == row.seq, let body = row.reply { return Reply(raw: row.status, Data(body.utf8), note: "seq \(r.seq) again: its reply") }   // the reply was lost
                guard r.seq == row.seq + 1 else { return .error(409, "seq", ["last": .i(row.seq)], note: "seq \(r.seq) after \(row.seq)") }

                var w: Walk
                if let text = t.walk {
                    guard let d = decodeWalk(text) else { return .error(500, "internal", note: "the save doesn't decode") }
                    w = d
                } else {                                                                            // a new 3.0 trainer: the server makes its first save
                    w = Engine.fresh(now: now, starter: firstUID)
                    if try !minting(id.key) { try record(id.key, w.companion, kind: "starter", now: unix) }
                }

                // steps: the allowance (15 a second since the last act, a day's at most) and the day's cap, both on the server's own counts
                let asked = r.steps ?? 0, day = Walk.key(now), done = try stepsOn(id.key, day)
                row.bank = min(Double(Walk.dayCap), row.bank + max(0, now.timeIntervalSince1970 - row.bankAt) * SaveDB.stepsPerSecond); row.bankAt = now.timeIntervalSince1970
                let taken = max(0, min(asked, Int(row.bank), Walk.dayCap - done))
                row.bank -= Double(taken)
                if taken > 0 {
                    try db.rows("INSERT INTO steps_day (key, day, n) VALUES (:k, :d, :n) ON CONFLICT (key, day) DO UPDATE SET n = n + :n",
                                ["k": .text(id.key), "d": .text(day), "n": .int(taken)])
                }

                var ids = Issued(next: try nextUID(id.key, w)), g = SystemRandomNumberGenerator()
                var out = Engine.apply(r.act, steps: taken, walk: &w, play: &row.play, rng: &g, now: now, ids: &ids)
                if out.cannot == nil {
                    switch r.act {
                    case .greet(let to): out.cannot = try greet(from: id.key, name: t.name, to: to, companion: w.companion, now: unix)   // 12 §2.3: into their inbox
                    case .tradeOffer, .tradeAccept, .tradeDecline, .tradeCancel:                     // 12 §3: ServerTrade.swift (two saves at once)
                        let was = w; var more: [News] = []
                        if let why = try tradeAct(r.act, key: id.key, name: t.name, walk: &w, news: &more, now: unix) { out.cannot = why; w = was }
                        else { out.news += more; if w != was { out.changed = true } }
                    default: break
                    }
                }
                let mail = try delivery(id.key, app: r.app, now: unix)                                 // what teammates sent (only what this app can read)
                out.news += mail.news
                for (m, kind) in ids.made { try record(id.key, m, kind: kind, state: kind == "radar" || kind == "legend" ? "pending" : "kept", now: unix) }
                try settleLedger(id.key, w, row.play, now: unix)

                var rev = t.rev
                let changed = out.changed || t.walk == nil, send = changed || mail.walk          // (a trade changed it meanwhile: send it, no new rev)
                if changed {
                    rev += 1
                    let text = savedText(w)
                    try db.rows("UPDATE trainers SET walk = :w, rev = :r, writer = :s, updated_at = :now WHERE key = :k",
                                ["w": .text(text), "r": .int(rev), "s": .text(r.session), "now": .int(unix), "k": .text(id.key)])
                    try keep(id.key, rev: rev, walk: text, now: unix)
                }
                if verCmp(t.app ?? "0", "3.0") ?? 0 < 0 { try db.rows("UPDATE trainers SET app = '3.0' WHERE key = :k", ["k": .text(id.key)]) }   // acting here: 2.x may not save over it

                let e = JSONEncoder(); e.outputFormatting = .sortedKeys
                let body = try e.encode(ActReply(rev: rev, walk: send ? w.shared : nil, taken: r.steps == nil ? nil : taken, out: out))
                (row.seq, row.status, row.reply) = (r.seq, 200, String(decoding: body, as: UTF8.self))
                try savePlay(id.key, r.session, row)
                let note: String? = out.cannot.map { "\(actName(r.act)): cannot (\($0.replacingOccurrences(of: "\n", with: " ")))" }
                    ?? (taken < asked ? "steps \(asked) → \(taken)" : nil)
                if r.act != .steps || note != nil {
                    try db.rows("INSERT INTO actions (key, session, seq, at, act, asked, taken, note) VALUES (:k, :s, :q, :now, :a, :asked, :t, :n)",
                                ["k": .text(id.key), "s": .text(r.session), "q": .int(r.seq), "now": .int(unix), "a": .text(actName(r.act)),
                                 "asked": .int(asked), "t": .int(taken), "n": note.map(SQLValue.text) ?? .null])
                }
                return Reply(raw: 200, body, note: note)
            }
        }
    }

    /// The trainer's play row; another session's (or none) starts over, its allowance kept (a first one: what the time since the last save allows).
    func playRow(_ key: String, session: String, since: Double, now: Date) throws -> PlayRow {
        guard let r = try db.rows("SELECT session, seq, status, reply, bank, bank_at, state FROM play WHERE key = :k", ["k": .text(key)]).first else {
            let t = now.timeIntervalSince1970
            return PlayRow(session: session, bank: 0, bankAt: since > 0 ? min(since, t) : t - 600)   // from the last save (steps typed while away); a new one: 10 minutes
        }
        var row = PlayRow(session: r.text("session"), seq: r.int("seq") ?? 0, status: r.int("status") ?? 200, reply: r.text("reply"),
                          bank: r.real("bank") ?? 0, bankAt: r.real("bank_at") ?? now.timeIntervalSince1970)
        if row.session == session { row.play = (r.text("state").flatMap { try? JSONDecoder().decode(Play.self, from: Data($0.utf8)) }) ?? Play() }
        else { (row.session, row.seq, row.reply, row.play) = (session, 0, nil, Play()) }      // a new session: no radar, fight or tower run carries over
        return row
    }
    func savePlay(_ key: String, _ session: String, _ row: PlayRow) throws {
        let state = String(decoding: try JSONEncoder().encode(row.play), as: UTF8.self)
        try db.rows("INSERT OR REPLACE INTO play (key, session, seq, status, reply, bank, bank_at, state) VALUES (:k, :s, :q, :st, :r, :b, :ba, :p)",
                    ["k": .text(key), "s": .text(session), "q": .int(row.seq), "st": .int(row.status), "r": row.reply.map(SQLValue.text) ?? .null,
                     "b": .real(row.bank), "ba": .real(row.bankAt), "p": .text(state)])
    }
    func stepsOn(_ key: String, _ day: String) throws -> Int {
        try db.rows("SELECT n FROM steps_day WHERE key = :k AND day = :d", ["k": .text(key), "d": .text(day)]).first?.int("n") ?? 0
    }
    /// The next uid: past every one issued and the save's own (never one used before).
    func nextUID(_ key: String, _ w: Walk) throws -> Int { max(try nextUID(key), (w.lastUID ?? 0) + 1) }
    /// The ledger follows the save: a radar's find comes into it (kept) or goes with the radar (gone); a kept one no longer there was released.
    func settleLedger(_ key: String, _ w: Walk, _ p: Play, now: Int) throws {
        let here = Set(SaveCheck.mons(w).compactMap(\.uid))
        let live = Set([p.radar?.mon.uid, p.battle?.trainer == nil ? p.battle?.wild.uid : nil].compactMap { $0 })
        for r in try db.rows("SELECT uid, state FROM mons WHERE key = :k AND state IN ('pending', 'kept')", ["k": .text(key)]) {
            guard let u = r.int("uid") else { continue }
            let to: String? = r.text("state") == "pending" ? (here.contains(u) ? "kept" : live.contains(u) ? nil : "gone") : (here.contains(u) ? nil : "released")
            if let to { try db.rows("UPDATE mons SET state = :s WHERE key = :k AND uid = :u", ["s": .text(to), "k": .text(key), "u": .int(u)]) }
        }
    }
}
