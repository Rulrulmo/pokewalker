import Foundation

// docs/plans/14 §2.2 (3.8): the 받기 함. What another trainer's act sends my way — a Pokémon got in a trade, one of mine back from the board
// (an offer not chosen, a post closed), one home from 맡겨 키우기 — waits here instead of going straight into my save while I might be mid-chain or
// mid-fight. `claim` puts it in the box (a trade's new uid and trade evolution then; a visit's EXP and level evolution then). Apps before 3.8 don't
// know the 받기 함: their next act takes everything at once (as before, with news `traded`).

let claimSchema = """
    CREATE TABLE IF NOT EXISTS claims (id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT NOT NULL, kind TEXT NOT NULL, from_name TEXT NOT NULL, mon TEXT NOT NULL,
      steps INTEGER NOT NULL DEFAULT 0, note TEXT, gave TEXT, at INTEGER NOT NULL, claimed_at INTEGER);
    CREATE INDEX IF NOT EXISTS claims_key ON claims (key, claimed_at);
    """
let claimApp = "3.8"

struct ClaimRow { let id: Int, key: String, kind: String, from: String, mon: Mon, steps: Int, note: String?, gave: Mon?, at: Int }   // gave: a trade's other half (old apps' news)

extension SaveDB {
    func claimRows(_ sql: String, _ args: [String: SQLValue] = [:]) throws -> [ClaimRow] {
        try db.rows("SELECT id, key, kind, from_name, mon, steps, note, gave, at FROM claims WHERE " + sql, args).compactMap { r in
            func mon(_ c: String) -> Mon? { r.text(c).flatMap { try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) } }
            guard let id = r.int("id"), let k = r.text("key"), let m = mon("mon") else { return nil }
            return ClaimRow(id: id, key: k, kind: r.text("kind") ?? "returned", from: r.text("from_name") ?? "", mon: m, steps: r.int("steps") ?? 0, note: r.text("note"),
                            gave: mon("gave"), at: r.int("at") ?? 0)
        }
    }
    /// Something for `key` to pick up: kind traded (a new Pokémon from `fromName`) · returned (its own, back) · visit (its own, home with `steps` raised).
    func addClaim(_ key: String, kind: String, from fromName: String, fromKey: String, mon: Mon, steps: Int = 0, note: String? = nil, gave: Mon? = nil, now: Int) throws {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        func t(_ m: Mon) throws -> String { String(decoding: try e.encode(m), as: UTF8.self) }
        try db.rows("INSERT INTO claims (key, kind, from_name, mon, steps, note, gave, at) VALUES (:k, :kind, :f, :m, :s, :n, :g, :now)",
                    ["k": .text(key), "kind": .text(kind), "f": .text(fromName), "m": .text(try t(mon)), "s": .int(steps),
                     "n": note.map(SQLValue.text) ?? .null, "g": try gave.map { .text(try t($0)) } ?? .null, "now": .int(now)])
        let id = try db.rows("SELECT last_insert_rowid() AS id").first?.int("id") ?? 0
        try post(.claimReady(id: id, kind: kind), to: key, from: fromKey, fromName: fromName, app: claimApp, now: now)
    }
    func openClaims(_ key: String) throws -> [ClaimRow] { try claimRows("key = :k AND claimed_at IS NULL ORDER BY id", ["k": .text(key)]) }

    /// `claim`: one waiting Pokémon into `w`'s box. Returns why not, or nil with the news it brought (an evolution, moves); `got` = it, as it came in.
    func claim(_ id: Int, key: String, walk w: inout Walk, news: inout [News], got: inout Mon?, now: Int) throws -> String? {
        guard let c = try claimRows("id = :i AND key = :k", ["i": .int(id), "k": .text(key)]).first else { return "받을 포켓몬이\n없어요" }
        guard try db.rows("SELECT claimed_at FROM claims WHERE id = :i", ["i": .int(id)]).first?.int("claimed_at") == nil else { return "이미 받았어요" }
        let learn = (w.learning ?? []).count / 2
        switch c.kind {
        case "traded":
            let (m, more) = try adopt(c.mon, from: c.from, into: &w, key: key, now: now)
            news += more; got = m
        default:                                                                                    // its own: same uid, back in the box (a visit's EXP first)
            var m = c.mon; let from = m.level
            if c.kind == "visit", c.steps > 0 { _ = m.gainBattleExp(c.steps) }
            _ = w.keep(m)
            if let ref = w.ref(uid: m.uid ?? -1) {
                w.queueMoves(ref, from: from)
                if m.level > from, let e = w.levelEvolution(Date(timeIntervalSince1970: TimeInterval(now)), ref: ref) {
                    w.evolve(e, ref: ref, shed: false); news.append(.evolve(uid: m.uid!, from: m.dex, to: e.to, shed: nil))
                }
                if m.level > from { news.append(.level(uid: m.uid!, level: m.level)) }
            }
            got = w.ref(uid: m.uid ?? -1).flatMap(w.mon)
        }
        news += w.settleLearning(announceFrom: learn).map(\.news)
        try db.rows("UPDATE claims SET claimed_at = :now WHERE id = :i", ["now": .int(now), "i": .int(id)])
        return nil
    }
    /// A Pokémon from another trainer into `w`: a uid of this ledger (kind trade), its 어버이, a trade evolution by what it holds (3.8: the board's
    /// trades go by held items; the bag's way stays for the old 1:1 offers, ServerTrade.receive).
    func adopt(_ m0: Mon, from giverName: String, into w: inout Walk, key: String, now: Int) throws -> (Mon, [News]) {
        var m = m0
        m.uid = try nextUID(key, w); m.ot = m.ot ?? giverName
        try record(key, m, kind: "trade", now: now)
        _ = w.keep(m)
        guard let e = Walk.tradeEvolution(of: m, giverBag: []), let ref = w.ref(uid: m.uid!) else { return (m, []) }
        w.evolve(Evo(from: e.from, to: e.to, way: e.way, level: e.level, item: nil, female: e.female, time: e.time, place: e.place, party: e.party), ref: ref, shed: false)
        if e.item != nil, var a = w.mon(ref) { a.item = nil; w.setMon(ref, a) }                      // its held item was used up
        let after = w.mon(ref) ?? m
        return (after, [.evolve(uid: m.uid!, from: m.dex, to: after.dex, shed: nil)])
    }
    /// An app before 3.8 acting: everything waiting goes in now (a trade as news `traded`, as it always came).
    func claimAll(_ key: String, walk w: inout Walk, news: inout [News], now: Int) throws {
        for c in try openClaims(key) {
            var more: [News] = [], got: Mon? = nil
            guard try claim(c.id, key: key, walk: &w, news: &more, got: &got, now: now) == nil else { continue }
            if c.kind == "traded", let got { news.append(.traded(id: 0, with: c.from, gave: c.gave ?? got, got: got)) }
            news += more
        }
    }
    /// The uids of this trainer's that are away (on the board, offered, out raising, back and waiting): the ledger's "here", not let go.
    func awayUIDs(_ key: String) throws -> Set<Int> {
        var out = Set<Int>()
        for l in try listings("key = :k AND state = 'open'", ["k": .text(key)]) { out.insert(l.uid) }
        for b in try bids("key = :k AND state = 'open'", ["k": .text(key)]) { out.insert(b.uid) }
        for c in try claimRows("key = :k AND claimed_at IS NULL AND kind != 'traded'", ["k": .text(key)]) { if let u = c.mon.uid { out.insert(u) } }
        for v in try visitRows("owner = :k AND state = 'on'", ["k": .text(key)]) { if let u = v.mon.uid { out.insert(u) } }
        return out
    }
}
