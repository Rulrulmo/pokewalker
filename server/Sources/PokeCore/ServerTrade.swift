import Foundation

// docs/plans/12 M2: 교환. An offer is a row in `trades`; accepting it changes both saves in one transaction (the acceptor's through /v2/act's
// own walk, the offerer's here, rev + 1), each Pokémon taking a new uid in its new trainer's ledger and, where its species evolves by trade, evolving
// there (an item it needs leaves the giver's bag). The other side hears through the inbox (news, app 3.3 on; its next reply carries its save).

let tradeSchema = """
    CREATE TABLE IF NOT EXISTS trades (id INTEGER PRIMARY KEY AUTOINCREMENT, from_key TEXT NOT NULL, to_key TEXT NOT NULL, from_name TEXT NOT NULL,
      to_name TEXT NOT NULL, give_uid INTEGER NOT NULL, want_uid INTEGER, give_mon TEXT NOT NULL, want_mon TEXT, state TEXT NOT NULL,
      at INTEGER NOT NULL, closed_at INTEGER);
    CREATE INDEX IF NOT EXISTS trades_to ON trades (to_key, state);
    CREATE INDEX IF NOT EXISTS trades_from ON trades (from_key, state);
    """
let tradesOpenMax = 5, tradeLife = 86400, tradeApp = "3.3"

struct TradeRow {
    let id: Int, from, to, fromName, toName: String, give: Int, want: Int?, giveMon: Mon, wantMon: Mon?, state: String, at: Int
    init?(_ r: Row) {
        guard let id = r.int("id"), let f = r.text("from_key"), let t = r.text("to_key"), let g = r.int("give_uid"),
              let gm = r.text("give_mon").flatMap({ try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }) else { return nil }
        self.id = id; from = f; to = t; fromName = r.text("from_name") ?? f; toName = r.text("to_name") ?? t; give = g; want = r.int("want_uid")
        giveMon = gm; wantMon = r.text("want_mon").flatMap { try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }; state = r.text("state") ?? "open"; at = r.int("at") ?? 0
    }
    var offer: TradeOffer { TradeOffer(id: id, from: fromName, to: toName, mon: giveMon, want: wantMon, at: at, state: state) }
}

extension SaveDB {
    /// A news for someone else, delivered on their next act (an app from `app` on); walk: their save changed meanwhile (the reply carries it).
    func post(_ news: News, to key: String, from: String, fromName: String, app: String, walk: Bool = false, now: Int) throws {
        let payload = String(decoding: try JSONEncoder().encode(news), as: UTF8.self)
        try db.rows("INSERT INTO inbox (to_key, from_key, from_name, kind, payload, at, min_app, walk) VALUES (:t, :f, :n, 'news', :p, :now, :a, :w)",
                    ["t": .text(key), "f": .text(from), "n": .text(fromName), "p": .text(payload), "now": .int(now), "a": .text(app), "w": .int(walk ? 1 : 0)])
    }
    func tradeRows(_ sql: String, _ args: [String: SQLValue]) throws -> [TradeRow] {
        try db.rows("SELECT id, from_key, to_key, from_name, to_name, give_uid, want_uid, give_mon, want_mon, state, at FROM trades WHERE " + sql, args).compactMap(TradeRow.init)
    }
    /// Offers past their day: expired, the offerer told.
    func expireTrades(now: Int) throws {
        for t in try tradeRows("state = 'open' AND at < :t", ["t": .int(now - tradeLife)]) {
            try close(t, "expired", now: now)
            try post(.tradeClosed(id: t.id, with: t.toName, why: "시간이 지났어요"), to: t.from, from: t.to, fromName: t.toName, app: tradeApp, now: now)
        }
    }
    func close(_ t: TradeRow, _ state: String, now: Int) throws {
        try db.rows("UPDATE trades SET state = :s, closed_at = :now WHERE id = :i", ["s": .text(state), "now": .int(now), "i": .int(t.id)])
    }

    // MARK: the acts (after the engine has walked the request's steps; `w` is the acting trainer's save, written back by act())
    func tradeAct(_ act: Act, key: String, name: String, walk w: inout Walk, news: inout [News], now: Int) throws -> String? {
        try expireTrades(now: now)
        switch act {
        case .tradeOffer(let raw, let give, let want):
            guard let to = trainerID(raw), to.key != key, let them = try trainer(to.key), knows(them.app, "3.0"), let theirs = them.walk.flatMap(decodeWalk) else { return "교환할 수 없는\n트레이너예요" }
            guard let r = w.ref(uid: give), r >= 0, let mon = w.mon(r) else { return "상자의 포켓몬만\n교환할 수 있어요" }
            var wanted: Mon? = nil
            if let want { guard let r2 = theirs.ref(uid: want), r2 >= 0 else { return "상대 상자에\n없는 포켓몬이에요" }; wanted = theirs.mon(r2) }
            let open = try tradeRows("from_key = :k AND state = 'open'", ["k": .text(key)])
            guard open.count < tradesOpenMax else { return "걸어 둔 교환이\n너무 많아요 (5개)" }
            guard !open.contains(where: { $0.give == give }) else { return "이미 교환에\n걸어 둔 포켓몬이에요" }
            let e = JSONEncoder(); e.outputFormatting = .sortedKeys
            try db.rows("""
                INSERT INTO trades (from_key, to_key, from_name, to_name, give_uid, want_uid, give_mon, want_mon, state, at)
                VALUES (:f, :t, :fn, :tn, :g, :w, :gm, :wm, 'open', :now)
                """, ["f": .text(key), "t": .text(to.key), "fn": .text(name), "tn": .text(them.name), "g": .int(give), "w": want.map(SQLValue.int) ?? .null,
                      "gm": .text(String(decoding: try e.encode(mon), as: UTF8.self)), "wm": try wanted.map { SQLValue.text(String(decoding: try e.encode($0), as: UTF8.self)) } ?? .null,
                      "now": .int(now)])
            let id = Int(try db.rows("SELECT last_insert_rowid() AS id").first?.int("id") ?? 0)
            try post(.tradeOffer(id: id, from: name, mon: mon, want: wanted), to: to.key, from: key, fromName: name, app: tradeApp, now: now)
            return nil
        case .tradeDecline(let id), .tradeCancel(let id):
            let mine: Bool = { if case .tradeCancel = act { return true }; return false }()
            guard let t = try tradeRows("id = :i AND state = 'open'", ["i": .int(id)]).first, (mine ? t.from : t.to) == key else { return "그 교환은 이제\n없어요" }
            try close(t, mine ? "cancelled" : "declined", now: now)
            try post(.tradeClosed(id: id, with: name, why: mine ? "상대가 거뒀어요" : "상대가 거절했어요"), to: mine ? t.to : t.from, from: key, fromName: name, app: tradeApp, now: now)
            return nil
        case .tradeAccept(let id, let giveRaw):
            guard let t = try tradeRows("id = :i AND state = 'open'", ["i": .int(id)]).first, t.to == key else { return "그 교환은 이제\n없어요" }
            guard let give = t.want ?? giveRaw, let r = w.ref(uid: give), r >= 0 else { return t.want == nil ? "줄 포켓몬을\n골라 주세요" : "그 포켓몬이\n상자에 없어요" }
            guard let them = try trainer(t.from), var theirs = them.walk.flatMap(decodeWalk), let r2 = theirs.ref(uid: t.give), r2 >= 0 else {
                try close(t, "failed", now: now)
                try post(.tradeClosed(id: id, with: name, why: "포켓몬이 상자에 없어요"), to: t.from, from: key, fromName: name, app: tradeApp, now: now)
                return "상대 포켓몬이\n상자에 없어요"
            }
            // the swap: each one out of its box, into the other's with a new uid (and 어버이), evolving there if it does by trade
            let mineOut = w.box.remove(at: r), theirsOut = theirs.box.remove(at: r2)
            let learnW = (w.learning ?? []).count / 2, learnT = (theirs.learning ?? []).count / 2
            let (got, gotNews) = try receive(theirsOut, giver: &theirs, giverName: t.fromName, into: &w, key: key, now: now)
            let (sent, sentNews) = try receive(mineOut, giver: &w, giverName: name, into: &theirs, key: t.from, now: now)
            let wLearn = w.settleLearning(announceFrom: learnW).map(\.news), tLearn = theirs.settleLearning(announceFrom: learnT).map(\.news)
            try db.rows("UPDATE mons SET state = 'traded' WHERE key = :k AND uid = :u", ["k": .text(key), "u": .int(give)])
            try db.rows("UPDATE mons SET state = 'traded' WHERE key = :k AND uid = :u", ["k": .text(t.from), "u": .int(t.give)])
            let text = savedText(theirs)
            try db.rows("UPDATE trainers SET walk = :w, rev = rev + 1, writer = 'trade' WHERE key = :k", ["w": .text(text), "k": .text(t.from)])
            if let rev = try trainer(t.from)?.rev { try keep(t.from, rev: rev, walk: text, now: now) }
            try close(t, "done", now: now)
            for o in try tradeRows("state = 'open' AND ((from_key = :a AND give_uid = :ga) OR (from_key = :b AND give_uid = :gb))",
                                   ["a": .text(key), "ga": .int(give), "b": .text(t.from), "gb": .int(t.give)]) {     // other offers of the two that moved: gone
                try close(o, "failed", now: now)
                try post(.tradeClosed(id: o.id, with: o.from == key ? o.toName : name, why: "포켓몬이 교환됐어요"), to: o.from == key ? o.to : o.from,
                         from: key, fromName: name, app: tradeApp, now: now)
            }
            news += [.traded(id: id, with: t.fromName, gave: mineOut, got: got)] + gotNews + wLearn
            try post(.traded(id: id, with: name, gave: theirsOut, got: sent), to: t.from, from: key, fromName: name, app: tradeApp, walk: true, now: now)
            for n in sentNews + tLearn { try post(n, to: t.from, from: key, fromName: name, app: tradeApp, walk: true, now: now) }
            return nil
        default: return nil
        }
    }
    /// One Pokémon into its new trainer's box: a new uid in that ledger (kind trade), its 어버이, a trade evolution (the item from the giver's bag).
    private func receive(_ m0: Mon, giver: inout Walk, giverName: String, into w: inout Walk, key: String, now: Int) throws -> (Mon, [News]) {
        var m = m0
        m.uid = try nextUID(key, w); m.ot = m.ot ?? giverName
        try record(key, m, kind: "trade", now: now)
        _ = w.keep(m)
        guard let e = Walk.tradeEvolution(of: m, giverBag: giver.items + giver.bag), let ref = w.ref(uid: m.uid!) else { return (m, []) }
        if let item = e.item { _ = giver.take(item) }                                              // it went along, held
        w.evolve(Evo(from: e.from, to: e.to, way: e.way, level: e.level, item: nil, female: e.female, time: e.time, place: e.place, party: e.party), ref: ref, shed: false)
        let after = w.mon(ref) ?? m
        return (after, [.evolve(uid: m.uid!, from: m.dex, to: after.dex, shed: nil)])
    }

    // MARK: reads
    func trades(_ r: TeamReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            try expireTrades(now: Int(now.timeIntervalSince1970))
            let inc = try tradeRows("to_key = :k AND state = 'open' ORDER BY at", ["k": .text(key)]).map(\.offer)
            let out = try tradeRows("from_key = :k AND state = 'open' ORDER BY at", ["k": .text(key)]).map(\.offer)
            return try JSONEncoder().encode(TradesReply(incoming: inc, outgoing: out))
        }
    }
    func box(_ r: BoxReq, now: Date) -> Reply {
        readGate(r.id, r.session) { _ in
            guard let of = trainerID(r.of), let t = try trainer(of.key), knows(t.app, "3.0"), let w = t.walk.flatMap(decodeWalk) else { return nil }
            return try JSONEncoder().encode(BoxReply(name: t.name, box: w.box))
        }
    }
    /// A read: the trainer, its session and PIN; nil from the body = 404.
    func readGate(_ raw: String, _ session: String, _ body: (String) throws -> Data?) -> Reply {
        guard let id = trainerID(raw) else { return .error(400, "bad_id") }
        return guarded {
            guard let t = try trainer(id.key) else { return .error(404, "no_trainer") }
            guard session == t.session else { return .error(409, "conflict", ["reason": .s("replaced")]) }
            guard try hasPIN(id.key) else { return .error(403, "pin_needed") }
            guard let d = try body(id.key) else { return .error(404, "no_trainer") }
            return Reply(raw: 200, d)
        }
    }
}
