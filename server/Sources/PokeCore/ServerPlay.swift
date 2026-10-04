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
    var endedRun = false                                                   // a new session found a tower fight on: that run is over (towerEnd on the save)
    var sentRev = -1                                                       // the rev this session's app last got with a walk: another one (an admin's set, a trade) is sent
}

func actName(_ a: Act) -> String {
    switch a {
    case .steps: "steps"; case .radar: "radar"; case .radarPick(let b): "pick \(b)"; case .tower: "tower"; case .towerPick, .towerReset: "tower pick"
    case .battle(let c): "battle \(c)"; case .buy(let bp, let i, let l, let s, let q): "buy \(i ?? l.map { "legend \($0)" } ?? s ?? "?") ×\(q)\(bp ? " (BP)" : "")"
    case .use(let i, _, let on): "use \(i)" + (on.map { " on \($0)" } ?? ""); case .sellAll: "sell all"; case .mon(let op): "mon \(op)"; case .course(let c): "course \(c)"; case .greet(let to): "greet \(to)"
    case .tradeOffer(let to, let g, let wnt): "trade offer → \(to) \(g)\(wnt.map { " for \($0)" } ?? "")"; case .tradeAccept(let i, let g): "trade accept #\(i)\(g.map { " with \($0)" } ?? "")"
    case .tradeDecline(let i): "trade decline #\(i)"; case .tradeCancel(let i): "trade cancel #\(i)"; case .raid(let p): "raid" + (p.map { " with \($0)" } ?? ""); case .raidBall: "raid ball"
    case .friendRequest(let to): "friend request → \(to)"; case .friendAccept(let f): "friend accept \(f)"; case .friendDecline(let f): "friend decline \(f)"
    case .friendRemove(let n): "friend remove \(n)"; case .marketList(let g, let w, _): "market list \(g) wish \(w)"; case .marketUnlist(let i): "market unlist #\(i)"
    case .marketBid(let l, let g): "market bid #\(l) with \(g)"; case .marketWithdraw(let b): "market withdraw bid #\(b)"; case .marketAccept(let b): "market accept bid #\(b)"
    case .duelChallenge(let to): "duel challenge → \(to)"; case .duelAccept(let i): "duel accept #\(i)"; case .duelDecline(let i): "duel decline #\(i)"
    case .duelCancel(let i): "duel cancel #\(i)"; case .duelMove(let i, let c): "duel #\(i) \(c)"
    case .claim(let i): "claim #\(i)"; case .visitSend(let to, let u): "visit send \(u) → \(to)"; case .visitEnd(let i): "visit end #\(i)"
    case .duelParty(let u): "duel party \(u)"; case .duelQueue: "duel queue"; case .duelQueueCancel: "duel queue cancel"; case .duelPick(let i, let sl): "duel #\(i) pick \(sl)"
    }
}
/// News kinds an app before 3.8 can't read are kept from it (the inbox's min_app does the same for teammates' mail).
func appKnows(_ app: String?, _ n: News) -> Bool {
    switch n { case .claimReady, .visitCame, .visitDone: knows(app, claimApp); default: true }
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
                let loaded = w
                if row.endedRun { w.towerEnd() }                                                    // the old session's run, cut off mid-fight

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
                if case .raid = r.act { row.play.raidBoss = try raidBoss(id.key, now: now) }        // 12 §4: the engine fights the server's boss
                let fightWeek = row.play.raid
                var out = Engine.apply(r.act, steps: taken, walk: &w, play: &row.play, rng: &g, now: now, ids: &ids)
                row.play.raidBoss = nil
                if let week = fightWeek, let dealt = out.end?.dealt {                                   // a raid fight ended: its damage to the team's boss
                    let counted = try raidHit(week, key: id.key, name: t.name, lead: out.battle?.mine.first?.mon.dex ?? w.companion.dex, dealt: dealt, now: unix)
                    let bar = max(1, try db.rows("SELECT bar_hp FROM raids WHERE week = :w", ["w": .text(week)]).first?.int("bar_hp") ?? 1)
                    let earned = (counted + bar - 1) / bar, paid = out.end?.bp ?? 0                     // BP for the bars the counted damage covers (the last, partial one too)
                    if paid > earned { w.bp = max(0, (w.bp ?? 0) - (paid - earned)); out.end?.bp = earned }
                    out.end?.dealt = counted
                }
                if out.cannot == nil {
                    switch r.act {
                    case .greet(let to): out.cannot = try greet(from: id.key, name: t.name, to: to, companion: w.companion, now: unix)   // 12 §2.3: into their inbox
                    case .tradeOffer, .tradeAccept, .tradeDecline, .tradeCancel:                     // 12 §3: ServerTrade.swift (two saves at once)
                        let was = w; var more: [News] = []
                        if let why = try tradeAct(r.act, key: id.key, name: t.name, walk: &w, news: &more, now: unix) { out.cannot = why; w = was }
                        else { out.news += more; if w != was { out.changed = true } }
                    case .friendRequest, .friendAccept, .friendDecline, .friendRemove:                 // 12 §2.4: ServerTeam.swift
                        out.cannot = try friendAct(r.act, key: id.key, name: t.name, now: unix)
                    case .marketList, .marketUnlist, .marketBid, .marketWithdraw, .marketAccept:       // 12 §3.3: ServerMarket.swift (two saves at once)
                        let was = w; var more: [News] = []
                        if let why = try marketAct(r.act, key: id.key, name: t.name, walk: &w, news: &more, now: unix) { out.cannot = why; w = was }
                        else { out.news += more; if w != was { out.changed = true } }
                    case .duelChallenge, .duelAccept, .duelDecline, .duelCancel, .duelMove, .duelQueue, .duelQueueCancel, .duelPick:   // 12 §5, 14 §5: ServerDuel.swift
                        let was = w
                        if let why = try duelAct(r.act, key: id.key, name: t.name, app: r.app, walk: &w, out: &out, now: unix) { out.cannot = why; w = was } else if w != was { out.changed = true }
                    case .claim(let cid):                                                               // 14 §2.2: ServerClaims.swift
                        let was = w; var more: [News] = [], got: Mon? = nil
                        if let why = try claim(cid, key: id.key, walk: &w, news: &more, got: &got, now: unix) { out.cannot = why; w = was }
                        else { out.news += more; out.mon = got; out.changed = true }
                    case .visitSend, .visitEnd:                                                         // 14 §3: ServerVisit.swift
                        let was = w; var more: [News] = []
                        if let why = try visitAct(r.act, key: id.key, name: t.name, walk: &w, news: &more, now: unix) { out.cannot = why; w = was }
                        else { out.news += more; if w != was { out.changed = true } }
                    case .raidBall:                                                                     // 12 §4.3: ServerRaid.swift
                        let was = w
                        if let why = try raidBall(id.key, walk: &w, out: &out, now: now) { out.cannot = why; w = was } else if w != was { out.changed = true }
                    default: break
                    }
                }
                try visitTick(id.key, steps: taken, walk: &w, news: &out.news, now: unix)             // 14 §3: guests raised, visits over, a host's BP
                if !knows(r.app, claimApp) { try claimAll(id.key, walk: &w, news: &out.news, now: unix) }   // 14 §8: before 3.8, the 받기 함 empties itself
                let mail = try delivery(id.key, app: r.app, now: unix)                                 // what teammates sent (only what this app can read)
                out.news += mail.news
                out.news = out.news.filter { appKnows(r.app, $0) }
                if let a = r.app { try db.rows("UPDATE trainers SET app_seen = :a WHERE key = :k AND (app_seen IS NULL OR app_seen != :a)", ["a": .text(a), "k": .text(id.key)]) }
                for (m, kind) in ids.made { try record(id.key, m, kind: kind, state: kind == "radar" || kind == "legend" ? "pending" : "kept", now: unix) }
                try settleLedger(id.key, w, row.play, now: unix)

                var rev = t.rev
                let changed = out.changed || t.walk == nil || w != loaded
                let send = changed || mail.walk || t.rev != row.sentRev                              // the app's copy is older (an admin's set, a trade, a new session): send it
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
                if send { row.sentRev = rev }
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
        guard let r = try db.rows("SELECT session, seq, status, reply, bank, bank_at, state, sent_rev FROM play WHERE key = :k", ["k": .text(key)]).first else {
            let t = now.timeIntervalSince1970
            return PlayRow(session: session, bank: 0, bankAt: since > 0 ? min(since, t) : t - 600)   // from the last save (steps typed while away); a new one: 10 minutes
        }
        var row = PlayRow(session: r.text("session"), seq: r.int("seq") ?? 0, status: r.int("status") ?? 200, reply: r.text("reply"),
                          bank: r.real("bank") ?? 0, bankAt: r.real("bank_at") ?? now.timeIntervalSince1970)
        let old = (r.text("state").flatMap { try? JSONDecoder().decode(Play.self, from: Data($0.utf8)) }) ?? Play()
        if row.session == session { row.play = old; row.sentRev = r.int("sent_rev") ?? -1 }
        else {                                                                              // a new session: no radar, chain or fight carries over;
            (row.session, row.seq, row.reply, row.play) = (session, 0, nil, Play())         // a tower run between fights does (an update, a restart at home),
            row.play.tower = old.tower && old.battle == nil; row.endedRun = old.tower && old.battle != nil   // one mid-fight ends (no way out of a losing one)
        }
        return row
    }
    /// The login's "tower" (a run carries into the new session: one between fights, see playRow).
    func runCarries(_ key: String) throws -> Bool {
        guard let p = try db.rows("SELECT state FROM play WHERE key = :k", ["k": .text(key)]).first?.text("state").flatMap({ try? JSONDecoder().decode(Play.self, from: Data($0.utf8)) }) else { return false }
        return p.tower && p.battle == nil
    }
    func savePlay(_ key: String, _ session: String, _ row: PlayRow) throws {
        let state = String(decoding: try JSONEncoder().encode(row.play), as: UTF8.self)
        try db.rows("INSERT OR REPLACE INTO play (key, session, seq, status, reply, bank, bank_at, state, sent_rev) VALUES (:k, :s, :q, :st, :r, :b, :ba, :p, :sr)",
                    ["k": .text(key), "s": .text(session), "q": .int(row.seq), "st": .int(row.status), "r": row.reply.map(SQLValue.text) ?? .null,
                     "b": .real(row.bank), "ba": .real(row.bankAt), "p": .text(state), "sr": .int(row.sentRev)])
    }
    func stepsOn(_ key: String, _ day: String) throws -> Int {
        try db.rows("SELECT n FROM steps_day WHERE key = :k AND day = :d", ["k": .text(key), "d": .text(day)]).first?.int("n") ?? 0
    }
    /// The next uid: past every one issued and the save's own (never one used before).
    func nextUID(_ key: String, _ w: Walk) throws -> Int { max(try nextUID(key), (w.lastUID ?? 0) + 1) }
    /// The ledger follows the save: a radar's find comes into it (kept) or goes with the radar (gone); a kept one no longer there was released.
    func settleLedger(_ key: String, _ w: Walk, _ p: Play, now: Int) throws {
        let here = Set(SaveCheck.mons(w).compactMap(\.uid)).union(try awayUIDs(key))           // (3.8: on the board, raised elsewhere, waiting to be claimed)
        let live = Set([p.radar?.mon.uid, p.battle?.trainer == nil ? p.battle?.wild.uid : nil].compactMap { $0 })
        for r in try db.rows("SELECT uid, state FROM mons WHERE key = :k AND state IN ('pending', 'kept')", ["k": .text(key)]) {
            guard let u = r.int("uid") else { continue }
            let to: String? = r.text("state") == "pending" ? (here.contains(u) ? "kept" : live.contains(u) ? nil : "gone") : (here.contains(u) ? nil : "released")
            if let to { try db.rows("UPDATE mons SET state = :s WHERE key = :k AND uid = :u", ["s": .text(to), "k": .text(key), "u": .int(u)]) }
        }
    }
}
