import Foundation

// docs/plans/12 §3.3 (3.5): the 교환 게시판. A trainer puts up one of its box Pokémon (the species it wishes for shown), anyone offers one of theirs
// on it, the poster picks one: the two saves change as a trade does (ServerTrade.receive: new uids, 어버이, trade evolutions). Every other offer on
// it closes; a post lives three days. Test IDs' posts show to test IDs only.

let marketSchema = """
    CREATE TABLE IF NOT EXISTS listings (id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT NOT NULL, name TEXT NOT NULL, uid INTEGER NOT NULL, mon TEXT NOT NULL,
      wish TEXT NOT NULL, state TEXT NOT NULL, at INTEGER NOT NULL, closed_at INTEGER);
    CREATE INDEX IF NOT EXISTS listings_state ON listings (state, at);
    CREATE TABLE IF NOT EXISTS bids (id INTEGER PRIMARY KEY AUTOINCREMENT, listing INTEGER NOT NULL, key TEXT NOT NULL, name TEXT NOT NULL, uid INTEGER NOT NULL,
      mon TEXT NOT NULL, state TEXT NOT NULL, at INTEGER NOT NULL, closed_at INTEGER);
    CREATE INDEX IF NOT EXISTS bids_listing ON bids (listing, state);
    """
let listingsMax = 3, bidsMax = 5, listingLife = 3 * 86400, marketApp = "3.5"

struct ListingRow { let id: Int, key: String, name: String, uid: Int, mon: Mon, wish: [Int], state: String, at: Int }
struct BidRow { let id: Int, listing: Int, key: String, name: String, uid: Int, mon: Mon, state: String, at: Int }

extension SaveDB {
    func listings(_ sql: String, _ args: [String: SQLValue] = [:]) throws -> [ListingRow] {
        try db.rows("SELECT id, key, name, uid, mon, wish, state, at FROM listings WHERE " + sql, args).compactMap { r in
            guard let id = r.int("id"), let k = r.text("key"), let m = r.text("mon").flatMap({ try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }) else { return nil }
            return ListingRow(id: id, key: k, name: r.text("name") ?? k, uid: r.int("uid") ?? 0, mon: m,
                              wish: r.text("wish").flatMap { try? JSONDecoder().decode([Int].self, from: Data($0.utf8)) } ?? [], state: r.text("state") ?? "", at: r.int("at") ?? 0)
        }
    }
    func bids(_ sql: String, _ args: [String: SQLValue] = [:]) throws -> [BidRow] {
        try db.rows("SELECT id, listing, key, name, uid, mon, state, at FROM bids WHERE " + sql, args).compactMap { r in
            guard let id = r.int("id"), let l = r.int("listing"), let k = r.text("key"), let m = r.text("mon").flatMap({ try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }) else { return nil }
            return BidRow(id: id, listing: l, key: k, name: r.text("name") ?? k, uid: r.int("uid") ?? 0, mon: m, state: r.text("state") ?? "", at: r.int("at") ?? 0)
        }
    }
    /// A Pokémon of this trainer already up on the board, or offered: it can't be used again until that closes.
    func onMarket(_ key: String, _ uid: Int) throws -> Bool {
        try !listings("key = :k AND uid = :u AND state = 'open'", ["k": .text(key), "u": .int(uid)]).isEmpty
            || !bids("key = :k AND uid = :u AND state = 'open'", ["k": .text(key), "u": .int(uid)]).isEmpty
    }
    func closeListing(_ l: ListingRow, _ state: String, now: Int) throws {
        try db.rows("UPDATE listings SET state = :s, closed_at = :now WHERE id = :i", ["s": .text(state), "now": .int(now), "i": .int(l.id)])
    }
    func closeBid(_ b: BidRow, _ state: String, now: Int) throws {
        try db.rows("UPDATE bids SET state = :s, closed_at = :now WHERE id = :i", ["s": .text(state), "now": .int(now), "i": .int(b.id)])
    }
    /// A post's open offers closed (declined), each bidder told why.
    func declineBids(on l: ListingRow, except: Int? = nil, why: String, now: Int) throws {
        for b in try bids("listing = :l AND state = 'open'", ["l": .int(l.id)]) where b.id != except {
            try closeBid(b, "declined", now: now)
            try post(.tradeClosed(id: l.id, with: l.name, why: why), to: b.key, from: l.key, fromName: l.name, app: marketApp, now: now)
        }
    }
    /// Posts past three days: expired, the poster and its bidders told.
    func expireMarket(now: Int) throws {
        for l in try listings("state = 'open' AND at < :t", ["t": .int(now - listingLife)]) {
            try closeListing(l, "expired", now: now)
            try declineBids(on: l, why: "시간이 지났어요", now: now)
            try post(.tradeClosed(id: l.id, with: l.name, why: "시간이 지났어요"), to: l.key, from: l.key, fromName: l.name, app: marketApp, now: now)
        }
    }

    // MARK: the acts (after the engine walked the steps; `w` is the acting trainer's save)
    func marketAct(_ act: Act, key: String, name: String, walk w: inout Walk, news: inout [News], now: Int) throws -> String? {
        try expireMarket(now: now)
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        func text<T: Encodable>(_ v: T) throws -> String { String(decoding: try e.encode(v), as: UTF8.self) }
        switch act {
        case .marketList(let give, let wish):
            guard let r = w.ref(uid: give), r >= 0, let mon = w.mon(r) else { return "상자의 포켓몬만\n올릴 수 있어요" }
            guard try !onMarket(key, give) else { return "이미 올리거나\n제안한 포켓몬이에요" }
            guard try listings("key = :k AND state = 'open'", ["k": .text(key)]).count < listingsMax else { return "올린 글이\n너무 많아요 (\(listingsMax)개)" }
            let wished = Array(wish.filter { (1...493).contains($0) }.prefix(3))
            try db.rows("INSERT INTO listings (key, name, uid, mon, wish, state, at) VALUES (:k, :n, :u, :m, :w, 'open', :now)",
                        ["k": .text(key), "n": .text(name), "u": .int(give), "m": .text(try text(mon)), "w": .text(try text(wished)), "now": .int(now)])
            return nil
        case .marketUnlist(let id):
            guard let l = try listings("id = :i AND state = 'open'", ["i": .int(id)]).first, l.key == key else { return "그 글은 이제\n없어요" }
            try closeListing(l, "cancelled", now: now)
            try declineBids(on: l, why: "상대가 글을 내렸어요", now: now)
            return nil
        case .marketBid(let id, let give):
            guard let l = try listings("id = :i AND state = 'open'", ["i": .int(id)]).first else { return "그 글은 이제\n없어요" }
            guard l.key != key else { return "내 글에는\n제안할 수 없어요" }
            guard isTestID(l.key) == isTestID(key) else { return "그 글은 이제\n없어요" }
            guard let r = w.ref(uid: give), r >= 0, let mon = w.mon(r) else { return "상자의 포켓몬만\n제안할 수 있어요" }
            guard try !onMarket(key, give) else { return "이미 올리거나\n제안한 포켓몬이에요" }
            guard try bids("listing = :l AND key = :k AND state = 'open'", ["l": .int(id), "k": .text(key)]).isEmpty else { return "이 글에는 이미\n제안했어요" }
            guard try bids("key = :k AND state = 'open'", ["k": .text(key)]).count < bidsMax else { return "걸어 둔 제안이\n너무 많아요 (\(bidsMax)개)" }
            try db.rows("INSERT INTO bids (listing, key, name, uid, mon, state, at) VALUES (:l, :k, :n, :u, :m, 'open', :now)",
                        ["l": .int(id), "k": .text(key), "n": .text(name), "u": .int(give), "m": .text(try text(mon)), "now": .int(now)])
            try post(.marketBid(listing: id, from: name, mon: mon), to: l.key, from: key, fromName: name, app: marketApp, now: now)
            return nil
        case .marketWithdraw(let id):
            guard let b = try bids("id = :i AND state = 'open'", ["i": .int(id)]).first, b.key == key else { return "그 제안은 이제\n없어요" }
            try closeBid(b, "withdrawn", now: now)
            if let l = try listings("id = :i", ["i": .int(b.listing)]).first {
                try post(.tradeClosed(id: l.id, with: name, why: "제안을 거뒀어요"), to: l.key, from: key, fromName: name, app: marketApp, now: now)
            }
            return nil
        case .marketAccept(let id):
            guard let b = try bids("id = :i AND state = 'open'", ["i": .int(id)]).first,
                  let l = try listings("id = :i AND state = 'open'", ["i": .int(b.listing)]).first, l.key == key else { return "그 제안은 이제\n없어요" }
            guard let r = w.ref(uid: l.uid), r >= 0 else {                                          // ours left the box: the post can't go on
                try closeListing(l, "failed", now: now); try declineBids(on: l, why: "포켓몬이 상자에 없어요", now: now)
                return "올린 포켓몬이\n상자에 없어요"
            }
            guard let them = try trainer(b.key), var theirs = them.walk.flatMap(decodeWalk), let r2 = theirs.ref(uid: b.uid), r2 >= 0 else {
                try closeBid(b, "failed", now: now)
                try post(.tradeClosed(id: l.id, with: name, why: "포켓몬이 상자에 없어요"), to: b.key, from: key, fromName: name, app: marketApp, now: now)
                return "상대 포켓몬이\n상자에 없어요"
            }
            let mineOut = w.box.remove(at: r), theirsOut = theirs.box.remove(at: r2)
            let learnW = (w.learning ?? []).count / 2, learnT = (theirs.learning ?? []).count / 2
            let (got, gotNews) = try receive(theirsOut, giver: &theirs, giverName: b.name, into: &w, key: key, now: now)
            let (sent, sentNews) = try receive(mineOut, giver: &w, giverName: name, into: &theirs, key: b.key, now: now)
            let wLearn = w.settleLearning(announceFrom: learnW).map(\.news), tLearn = theirs.settleLearning(announceFrom: learnT).map(\.news)
            try db.rows("UPDATE mons SET state = 'traded' WHERE key = :k AND uid = :u", ["k": .text(key), "u": .int(l.uid)])
            try db.rows("UPDATE mons SET state = 'traded' WHERE key = :k AND uid = :u", ["k": .text(b.key), "u": .int(b.uid)])
            let saved = savedText(theirs)
            try db.rows("UPDATE trainers SET walk = :w, rev = rev + 1, writer = 'trade' WHERE key = :k", ["w": .text(saved), "k": .text(b.key)])
            if let rev = try trainer(b.key)?.rev { try keep(b.key, rev: rev, walk: saved, now: now) }
            try closeListing(l, "done", now: now); try closeBid(b, "accepted", now: now)
            try declineBids(on: l, except: b.id, why: "다른 제안이 선택됐어요", now: now)
            for (k, u) in [(key, l.uid), (b.key, b.uid)] {                                          // the two that moved: out of any other post or offer
                for o in try listings("key = :k AND uid = :u AND state = 'open'", ["k": .text(k), "u": .int(u)]) {
                    try closeListing(o, "failed", now: now); try declineBids(on: o, why: "포켓몬이 교환됐어요", now: now)
                }
                for o in try bids("key = :k AND uid = :u AND state = 'open'", ["k": .text(k), "u": .int(u)]) {
                    try closeBid(o, "failed", now: now)
                    if let ol = try listings("id = :i", ["i": .int(o.listing)]).first {
                        try post(.tradeClosed(id: ol.id, with: o.name, why: "포켓몬이 교환됐어요"), to: ol.key, from: k, fromName: o.name, app: marketApp, now: now)
                    }
                }
            }
            news += [.traded(id: l.id, with: b.name, gave: mineOut, got: got)] + gotNews + wLearn
            try post(.traded(id: l.id, with: name, gave: theirsOut, got: sent), to: b.key, from: key, fromName: name, app: marketApp, walk: true, now: now)
            for n in sentNews + tLearn { try post(n, to: b.key, from: key, fromName: name, app: marketApp, walk: true, now: now) }
            return nil
        default: return nil
        }
    }

    /// POST /v2/market: every open post (test IDs' to test IDs only), the offers on mine, mine on others'.
    func market(_ r: TeamReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            try expireMarket(now: Int(now.timeIntervalSince1970))
            let tester = isTestID(key)
            let open = try listings("state = 'open' ORDER BY at DESC").filter { isTestID($0.key) == tester }
            var counts: [Int: Int] = [:]
            for row in try db.rows("SELECT listing, count(*) AS n FROM bids WHERE state = 'open' GROUP BY listing") { if let l = row.int("listing") { counts[l] = row.int("n") ?? 0 } }
            let mine = Set(open.filter { $0.key == key }.map(\.id))
            func bid(_ b: BidRow) -> Bid { Bid(id: b.id, listing: b.listing, from: b.name, mon: b.mon, at: b.at, state: b.state) }
            let offers = try bids("state = 'open' ORDER BY at").filter { mine.contains($0.listing) }.map(bid)
            let myBids = try bids("key = :k AND state = 'open' ORDER BY at", ["k": .text(key)]).map(bid)
            let ls = open.map { Listing(id: $0.id, from: $0.name, mon: $0.mon, wish: $0.wish, at: $0.at, bids: counts[$0.id] ?? 0, mine: $0.key == key) }
            return try JSONEncoder().encode(MarketReply(listings: ls, offers: offers, myBids: myBids))
        }
    }
}
