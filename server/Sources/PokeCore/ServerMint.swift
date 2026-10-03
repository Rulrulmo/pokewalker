import Foundation

// docs/plans/10 §4: the server makes every new Pokémon (from app 2.1 on) with the game's own rolls (Game/Model/Mint.swift) and its own random
// numbers, and records it in `mons`; a 2.1 save may hold only Pokémon issued here, their traits unchanged. What else it hands out (a chain's W
// and reward items, what a legend cost) goes to `grants`, so the save check counts exactly what came in. Rerolls cost what the game charges:
// a radar is 10 W unless a chain goes on (a new radar with one still open ends the chain), an egg hatches once per egg's worth of steps.

let firstUID = 1_000_000                                                   // the starter's; issued ones count up from here (Walk.id's own stay below)

struct RadarReq: Codable, Sendable { let id, session, walk: String }
struct ResultReq: Codable, Sendable { let id, session: String; let uid: Int; let result: String }
struct HatchReq: Codable, Sendable { let id, session, walk: String }
struct BuyReq: Codable, Sendable { let id, session, walk: String; let index: Int }
struct EvolveReq: Codable, Sendable { let id, session: String; let uid, to, level: Int }

let mintSchema = """
    CREATE TABLE IF NOT EXISTS mons (key TEXT NOT NULL, uid INTEGER NOT NULL, dex INTEGER NOT NULL, level INTEGER NOT NULL, traits TEXT NOT NULL,
      kind TEXT NOT NULL, state TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (key, uid));
    CREATE TABLE IF NOT EXISTS chains (key TEXT PRIMARY KEY, chain INTEGER NOT NULL, pending INTEGER, free INTEGER NOT NULL, course INTEGER NOT NULL,
      hatched INTEGER NOT NULL DEFAULT -1, at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS grants (key TEXT NOT NULL, at INTEGER NOT NULL, watts INTEGER NOT NULL, bp INTEGER NOT NULL, item TEXT, why TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS grants_key ON grants (key, at);
    """

func monText(_ m: Mon) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return String(decoding: (try? e.encode(m)) ?? Data(), as: UTF8.self) }
func traitsText(_ m: Mon) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return String(decoding: (try? e.encode(MonTraits(m))) ?? Data(), as: UTF8.self) }
func decodeWalk(_ text: String) -> Walk? { (try? JSONDecoder().decode(Walk.self, from: Data(text.utf8))).flatMap { $0.version == 1 ? $0 : nil } }

/// A trainer's chain state: the open radar (pending uid), whether the next radar is free (the chain went on), the course it's on, the total at
/// the last hatch.
struct ChainRow { var chain = 0, pending: Int? = nil, free = false, course = 0, hatched = -1 }

extension SaveDB {
    func minting(_ key: String) throws -> Bool { try !db.rows("SELECT 1 AS n FROM mons WHERE key = :k LIMIT 1", ["k": .text(key)]).isEmpty }
    func nextUID(_ key: String) throws -> Int { max(firstUID + 1, (try db.rows("SELECT max(uid) AS n FROM mons WHERE key = :k", ["k": .text(key)]).first?.int("n") ?? 0) + 1) }
    func record(_ key: String, _ m: Mon, kind: String, state: String = "kept", now: Int) throws {
        try db.rows("INSERT OR REPLACE INTO mons (key, uid, dex, level, traits, kind, state, at) VALUES (:k, :u, :d, :l, :t, :kind, :s, :now)",
                    ["k": .text(key), "u": .int(m.uid ?? 0), "d": .int(m.dex), "l": .int(m.level), "t": .text(traitsText(m)), "kind": .text(kind), "s": .text(state), "now": .int(now)])
    }
    func grant(_ key: String, watts: Int = 0, bp: Int = 0, item: String? = nil, why: String, now: Int) throws {
        try db.rows("INSERT INTO grants (key, at, watts, bp, item, why) VALUES (:k, :now, :w, :b, :i, :why)",
                    ["k": .text(key), "now": .int(now), "w": .int(watts), "b": .int(bp), "i": item.map(SQLValue.text) ?? .null, "why": .text(why)])
    }
    func chainRow(_ key: String) throws -> ChainRow {
        guard let r = try db.rows("SELECT chain, pending, free, course, hatched FROM chains WHERE key = :k", ["k": .text(key)]).first else { return ChainRow() }
        return ChainRow(chain: r.int("chain") ?? 0, pending: r.int("pending"), free: r.int("free") == 1, course: r.int("course") ?? 0, hatched: r.int("hatched") ?? -1)
    }
    func setChain(_ key: String, _ c: ChainRow, now: Int) throws {
        try db.rows("INSERT OR REPLACE INTO chains (key, chain, pending, free, course, hatched, at) VALUES (:k, :c, :p, :f, :course, :h, :now)",
                    ["k": .text(key), "c": .int(c.chain), "p": c.pending.map(SQLValue.int) ?? .null, "f": .int(c.free ? 1 : 0), "course": .int(c.course), "h": .int(c.hatched), "now": .int(now)])
    }
    /// What was handed out since `since` (the last save taken): W (a chain's, or less: a radar fee, a legend), BP (less: 뮤츠), reward items.
    func granted(_ key: String, since: Int) throws -> (watts: Int, bp: Int, items: [String]) {
        let rows = try db.rows("SELECT watts, bp, item FROM grants WHERE key = :k AND at >= :since", ["k": .text(key), "since": .int(since)])
        return (rows.reduce(0) { $0 + ($1.int("watts") ?? 0) }, rows.reduce(0) { $0 + ($1.int("bp") ?? 0) }, rows.compactMap { $0.text("item") })
    }

    /// The checks every mint request shares: the trainer, its session, a PIN (2.1 makes them all), and the walk it sends (also checked as a
    /// save would be, against the last one taken). Returns the trainer and the walk, or the reply to send instead.
    private func mintGate(_ id: (name: String, key: String), session: String, walk text: String?, now: Int) throws -> (Trainer, Walk?, [String])? {
        guard let t = try trainer(id.key), session == t.session else { return nil }
        guard let text else { return (t, nil, []) }
        guard let w = decodeWalk(text) else { return nil }
        var reasons = SaveCheck.values(w)
        if let old = t.walk.flatMap(decodeWalk) {
            let g = try granted(id.key, since: t.updatedAt)
            reasons += SaveCheck.changes(from: old, to: w, seconds: now - t.updatedAt, granted: g)
        }
        if !reasons.isEmpty {
            try db.rows("INSERT INTO flags (key, rev, at, reasons) VALUES (:k, :r, :now, :why)",
                        ["k": .text(id.key), "r": .int(t.rev), "now": .int(now), "why": .text("(mint) " + reasons.joined(separator: "; "))])
        }
        return (t, w, reasons)
    }
    private func mintReply(_ id: String, session: String, walk: String?, now: Int, _ body: ((name: String, key: String), Trainer, Walk?) throws -> Reply) -> Reply {
        guard let key = trainerID(id) else { return .error(400, "bad_id") }
        if let walk, walk.utf8.count > walkLimit { return .error(413, "too_big") }
        do {
            return try db.transaction {
                guard try trainer(key.key) != nil else { return .error(404, "no_trainer") }
                guard try hasPIN(key.key) else { return .error(403, "pin_needed") }
                guard try minting(key.key) else { return .error(409, "relogin") }                 // its Pokémon aren't on record yet: a 2.1 login takes them first (10 §4.3)
                guard let (t, w, reasons) = try mintGate(key, session: session, walk: walk, now: now) else {
                    return try trainer(key.key)?.session == session ? .error(400, "bad_walk") : .error(409, "conflict", ["reason": .s("replaced")])
                }
                if reject, !reasons.isEmpty {                                                     // refused, the flag kept (a reply, not a throw: it commits)
                    return .error(422, "implausible", ["reasons": .s(reasons.joined(separator: "; ")), "rev": .i(t.rev), "walk": .str(t.walk)], note: "mint refused: \(reasons.joined(separator: "; "))")
                }
                return try body(key, t, w)
            }
        } catch { return .error(500, "internal", note: "\(error)") }
    }

    // MARK: the requests (10 §4.1)
    func radar(_ r: RadarReq, now: Int) -> Reply {
        mintReply(r.id, session: r.session, walk: r.walk, now: now) { id, _, w in
            guard let w else { return .error(400, "bad_walk") }
            var c = try chainRow(id.key)
            if let p = c.pending { try db.rows("UPDATE mons SET state = 'gone' WHERE key = :k AND uid = :u AND state = 'pending'", ["k": .text(id.key), "u": .int(p)]); c = ChainRow(hatched: c.hatched) }   // one left open: that chain is over
            let free = c.free && c.chain > 0
            if !free {
                guard w.watts >= 10 else { return .error(402, "watts") }
                try grant(id.key, watts: -10, why: "radar", now: now); c.chain = 0
            }
            var g = SystemRandomNumberGenerator()
            var (m, legend) = w.radarMon(&g, chain: c.chain)
            m.uid = try nextUID(id.key)
            try record(id.key, m, kind: legend ? "legend" : "radar", state: "pending", now: now)
            c.pending = m.uid; c.free = false; c.course = w.course
            try setChain(id.key, c, now: now)
            return Reply(200, ["mon": .s(monText(m)), "legend": .b(legend), "chain": .i(c.chain), "free": .b(free)])
        }
    }
    func radarResult(_ r: ResultReq, now: Int) -> Reply {
        guard ["caught", "defeated", "fled", "lost", "missed"].contains(r.result) else { return .error(400, "bad_request") }
        return mintReply(r.id, session: r.session, walk: nil, now: now) { id, _, _ in
            var c = try chainRow(id.key)
            guard c.pending == r.uid else { return .error(409, "no_radar") }
            try db.rows("UPDATE mons SET state = :s WHERE key = :k AND uid = :u", ["s": .text(r.result == "caught" ? "kept" : "gone"), "k": .text(id.key), "u": .int(r.uid)])
            c.pending = nil
            var g = SystemRandomNumberGenerator()
            guard r.result == "caught" || r.result == "defeated", Walk.chainContinues(c.chain, &g) else {
                c.chain = 0; c.free = false; try setChain(id.key, c, now: now)
                return Reply(200, ["chain": .i(0), "bonus": .i(0), "reward": .null])
            }
            c.chain += 1; c.free = true
            let n = c.chain, reward: String? = n % 5 == 0 ? courses[min(max(c.course, 0), courses.count - 1)].items[0].item : nil   // Walk.chainReward's
            try grant(id.key, watts: 2 * n, item: reward, why: "chain \(n)", now: now)
            try setChain(id.key, c, now: now)
            return Reply(200, ["chain": .i(n), "bonus": .i(2 * n), "reward": .str(reward)])
        }
    }
    func hatch(_ r: HatchReq, now: Int) -> Reply {
        mintReply(r.id, session: r.session, walk: r.walk, now: now) { id, _, w in
            guard let w, let e = w.egg, w.hatchDue, eggPool.contains(e.dex) else { return .error(409, "no_egg") }
            var c = try chainRow(id.key)
            guard c.hatched < 0 || w.total - c.hatched >= eggCycles[e.dex] * 255 else { return .error(409, "hatched") }   // one hatch per egg's worth of steps
            var g = SystemRandomNumberGenerator()
            guard var m = w.eggMon(&g) else { return .error(409, "no_egg") }
            m.uid = try nextUID(id.key)
            try record(id.key, m, kind: "egg", now: now)
            c.hatched = w.total; try setChain(id.key, c, now: now)
            return Reply(200, ["mon": .s(monText(m))])
        }
    }
    func buy(_ r: BuyReq, now: Int) -> Reply {
        guard Walk.legendShop.indices.contains(r.index) else { return .error(400, "bad_request") }
        return mintReply(r.id, session: r.session, walk: r.walk, now: now) { id, _, w in
            let l = Walk.legendShop[r.index]
            guard let w, w.watts >= l.watts, (w.bp ?? 0) >= l.bp else { return .error(402, "price") }
            var g = SystemRandomNumberGenerator(), m = Walk.legendMon(r.index, &g)
            m.uid = try nextUID(id.key)
            try record(id.key, m, kind: "shop", now: now)
            try grant(id.key, watts: -l.watts, bp: -l.bp, why: "legend #\(l.dex)", now: now)
            return Reply(200, ["mon": .s(monText(m))])
        }
    }
    func evolve(_ r: EvolveReq, now: Int) -> Reply {
        guard (1...100).contains(r.level) else { return .error(400, "bad_request") }
        return mintReply(r.id, session: r.session, walk: nil, now: now) { id, _, _ in
            guard let row = try db.rows("SELECT dex, traits FROM mons WHERE key = :k AND uid = :u AND state = 'kept'", ["k": .text(id.key), "u": .int(r.uid)]).first,
                  let dex = row.int("dex") else { return .error(404, "no_mon") }
            guard evolutions.contains(where: { $0.from == dex && $0.to == r.to }) else { return .error(409, "no_evolution") }
            try db.rows("UPDATE mons SET dex = :d WHERE key = :k AND uid = :u", ["d": .int(r.to), "k": .text(id.key), "u": .int(r.uid)])
            guard r.to == 291 else { return Reply(200, ["shedinja": .null]) }
            var g = SystemRandomNumberGenerator()
            let traits = try JSONDecoder().decode(MonTraits.self, from: Data((row.text("traits") ?? "{}").utf8))
            var s = Walk.shedinja(from: Mon(dex: 291, level: r.level, female: traits.female, shiny: traits.shiny ? true : nil), &g)
            s.uid = try nextUID(id.key)
            try record(id.key, s, kind: "shedinja", now: now)
            return Reply(200, ["shedinja": .s(monText(s))])
        }
    }

    /// A 2.0 trainer's first 2.1 login: every Pokémon in its save is taken as issued (10 §4.3); the ones with no uid get one, so the save
    /// changes (rev + 1, writer admin) and the app takes it like a stale reply. nil = nothing to do.
    func grandfather(_ key: String, now: Int) throws -> (rev: Int, walk: String)? {
        guard try !minting(key), let t = try trainer(key), let text = t.walk, var w = decodeWalk(text) else { return nil }
        var uid = max(firstUID, w.lastUID ?? 0)
        func stamp(_ m: inout Mon) { if m.uid == nil { uid += 1; m.uid = uid } }
        stamp(&w.companion); for i in w.caught.indices { stamp(&w.caught[i]) }; for i in w.box.indices { stamp(&w.box[i]) }
        w.lastUID = max(w.lastUID ?? 0, uid)
        for m in SaveCheck.mons(w) { try record(key, m, kind: "grandfathered", now: now) }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        let out = String(decoding: try e.encode(w), as: UTF8.self)
        guard out != text else { return nil }
        try db.rows("INSERT OR REPLACE INTO history (key, rev, reason, at, walk) VALUES (:k, :r, 'admin', :now, :w)", ["k": .text(key), "r": .int(t.rev), "now": .int(now), "w": .text(text)])
        try db.rows("UPDATE trainers SET walk = :w, rev = :r, writer = 'admin' WHERE key = :k", ["w": .text(out), "r": .int(t.rev + 1), "k": .text(key)])
        return (t.rev + 1, out)
    }

    /// 10 §4.4: a 2.1 save's Pokémon against what was issued — each one issued here (pending counts: its result may still be on the way), its
    /// fixed traits the same, its species the issued one or an evolution of it, its level not under the issued one; a released one doesn't come
    /// back. Issued ones missing from the save are marked released.
    func mintProblems(_ key: String, _ w: Walk, now: Int) throws -> [String] {
        var out: [String] = []
        let rows = try db.rows("SELECT uid, dex, level, traits, state FROM mons WHERE key = :k", ["k": .text(key)])
        var issued: [Int: Row] = [:]; for r in rows { if let u = r.int("uid") { issued[u] = r } }
        var seen: Set<Int> = []
        for m in SaveCheck.mons(w) {
            guard let u = m.uid, let r = issued[u] else { out.append("#\(m.dex) Lv.\(m.level) wasn't issued"); continue }
            seen.insert(u)
            if r.text("state") == "released" || r.text("state") == "gone" { out.append("uid \(u) (\(r.text("state") ?? "")) is back") }
            if let t = r.text("traits"), let traits = try? JSONDecoder().decode(MonTraits.self, from: Data(t.utf8)), traits != MonTraits(m) { out.append("uid \(u)'s traits changed") }
            if let d = r.int("dex"), !evolves(d, into: m.dex) { out.append("uid \(u) is #\(m.dex), issued as #\(d)") }
            if let l = r.int("level"), m.level < l { out.append("uid \(u) Lv.\(m.level) under its issued Lv.\(l)") }
            if r.text("state") == "pending" { try db.rows("UPDATE mons SET state = 'kept' WHERE key = :k AND uid = :u", ["k": .text(key), "u": .int(u)]) }
        }
        for (u, r) in issued where r.text("state") == "kept" && !seen.contains(u) {
            try db.rows("UPDATE mons SET state = 'released' WHERE key = :k AND uid = :u", ["k": .text(key), "u": .int(u)])
        }
        return out
    }
}
