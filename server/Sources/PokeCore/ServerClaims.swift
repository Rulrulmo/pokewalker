import Foundation

// 3.8's 받기 함 (docs/plans/14 §2.2), folded into the 우편함 in 3.9 (docs/plans/15, ServerMail.swift): its table stays for what was claimed
// (and is emptied into mail at startup: SaveDB.claimsToMail). What's left here: a traded Pokémon's adoption, and which of ours are away.

let claimSchema = """
    CREATE TABLE IF NOT EXISTS claims (id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT NOT NULL, kind TEXT NOT NULL, from_name TEXT NOT NULL, mon TEXT NOT NULL,
      steps INTEGER NOT NULL DEFAULT 0, note TEXT, gave TEXT, at INTEGER NOT NULL, claimed_at INTEGER);
    CREATE INDEX IF NOT EXISTS claims_key ON claims (key, claimed_at);
    """

let claimApp = "3.8"                                                                        // the apps that knew the 받기 함 (news claimReady · visitCame · visitDone)

extension SaveDB {
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
    /// The uids of this trainer's that are away (on the board, offered, out raising, back and waiting): the ledger's "here", not let go.
    func awayUIDs(_ key: String) throws -> Set<Int> {
        var out = Set<Int>()
        for l in try listings("key = :k AND state = 'open'", ["k": .text(key)]) { out.insert(l.uid) }
        for b in try bids("key = :k AND state = 'open'", ["k": .text(key)]) { out.insert(b.uid) }
        for m in try mailRows("key = :k AND claimed_at IS NULL AND kind IN ('returned', 'visit')", ["k": .text(key)]) {   // ours, waiting in the 우편함
            for g in m.gifts { if case .mon(let x, _) = g, let u = x.uid { out.insert(u) } }
        }
        for v in try visitRows("owner = :k AND state = 'on'", ["k": .text(key)]) { if let u = v.mon.uid { out.insert(u) } }
        return out
    }
}
