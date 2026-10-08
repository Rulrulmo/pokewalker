import Foundation

// docs/plans/15 (3.9): the 우편함. Everything the server gives a trainer outside its own act comes as mail: a trade's Pokémon, one back from the
// board or from 맡겨 키우기 (3.8's 받기 함, folded in), the Battle Tower's first-time streak rewards, an operator's gift or notice. Gifts go into
// the save only when claimed, from a 3.9 app (the user: no automatic delivery to older ones — they update to claim). Mail with gifts stays until
// claimed; claimed mail and read notices go after 30 days, unread notices after 90.

let mailSchema = """
    CREATE TABLE IF NOT EXISTS mail (id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT NOT NULL, kind TEXT NOT NULL, from_name TEXT NOT NULL, title TEXT NOT NULL,
      body TEXT, gifts TEXT NOT NULL, at INTEGER NOT NULL, read_at INTEGER, claimed_at INTEGER);
    CREATE INDEX IF NOT EXISTS mail_key ON mail (key, claimed_at);
    CREATE TABLE IF NOT EXISTS tower_rewards (key TEXT NOT NULL, wins INTEGER NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (key, wins));
    """
let mailApp = "3.9", mailKeptRead = 30 * 86400, mailKeptUnread = 90 * 86400

struct MailRow { let id: Int, key: String, kind: String, from: String, title: String, body: String?, gifts: [Gift], at: Int, read: Bool, claimed: Bool
    var mail: Mail { Mail(id: id, kind: kind, from: from, title: title, body: body, gifts: gifts, at: at, read: read, claimed: claimed) }
}

extension SaveDB {
    func mailRows(_ sql: String, _ args: [String: SQLValue] = [:]) throws -> [MailRow] {
        try db.rows("SELECT id, key, kind, from_name, title, body, gifts, at, read_at, claimed_at FROM mail WHERE " + sql, args).compactMap { r in
            guard let id = r.int("id"), let k = r.text("key"), let g = r.text("gifts").flatMap({ try? JSONDecoder().decode([Gift].self, from: Data($0.utf8)) }) else { return nil }
            return MailRow(id: id, key: k, kind: r.text("kind") ?? "notice", from: r.text("from_name") ?? "", title: r.text("title") ?? "", body: r.text("body"),
                           gifts: g, at: r.int("at") ?? 0, read: r.int("read_at") != nil, claimed: r.int("claimed_at") != nil)
        }
    }
    /// A mail into `key`'s 우편함 (news mailNew to a 3.9 app). Returns its id.
    @discardableResult func sendMail(_ key: String, kind: String, from: String, fromKey: String? = nil, title: String, body: String? = nil, gifts: [Gift] = [], now: Int) throws -> Int {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        try db.rows("INSERT INTO mail (key, kind, from_name, title, body, gifts, at) VALUES (:k, :kind, :f, :t, :b, :g, :now)",
                    ["k": .text(key), "kind": .text(kind), "f": .text(from), "t": .text(title), "b": body.map(SQLValue.text) ?? .null,
                     "g": .text(String(decoding: try e.encode(gifts), as: UTF8.self)), "now": .int(now)])
        let id = try db.rows("SELECT last_insert_rowid() AS id").first?.int("id") ?? 0
        try post(.mailNew(id: id, title: title), to: key, from: fromKey ?? key, fromName: from, app: mailApp, now: now)
        return id
    }

    // MARK: claiming
    /// `mailClaim`: every gift of one mail into `w` (pick: which of a 고르기). Returns why not; `got` = a Pokémon it brought, as it came in.
    func claimMail(_ id: Int, pick: Int?, key: String, walk w: inout Walk, news: inout [News], got: inout Mon?, now: Int) throws -> String? {
        guard let m = try mailRows("id = :i AND key = :k", ["i": .int(id), "k": .text(key)]).first else { return "받을 수 없는\n우편이에요" }
        guard !m.claimed else { return "이미 받았어요" }
        guard !m.gifts.isEmpty else { return "받을 것이 없는\n우편이에요" }
        for g in m.gifts {                                                                         // a pick out of range: nothing is given
            switch g {
            case .pickItem(let items): guard let p = pick, items.indices.contains(p) else { return "하나를 골라 주세요" }
            case .pickLegend(let dex, _, _): guard let p = pick, dex.indices.contains(p) else { return "하나를 골라 주세요" }
            default: break
            }
        }
        let learn = (w.learning ?? []).count / 2
        for g in m.gifts {
            switch g {
            case .mon(let mon, let steps):
                switch m.kind {
                case "trade":                                                                       // a new one of ours: a uid here, its 어버이, a trade evolution
                    let (a, more) = try adopt(mon, from: m.from, into: &w, key: key, now: now); news += more; got = a
                case "returned", "visit":                                                           // our own, back: same uid (a visit's EXP first)
                    var x = mon; let from = x.level
                    if let s = steps, s > 0 { _ = x.gainBattleExp(s) }
                    _ = w.keep(x)
                    if let ref = w.ref(uid: x.uid ?? -1) {
                        w.queueMoves(ref, from: from)
                        if x.level > from, let e = w.levelEvolution(Date(timeIntervalSince1970: TimeInterval(now)), ref: ref) {
                            w.evolve(e, ref: ref, shed: false); news.append(.evolve(uid: x.uid!, from: x.dex, to: e.to, shed: nil))
                        }
                        if x.level > from { news.append(.level(uid: x.uid!, level: x.level)) }
                    }
                    got = w.ref(uid: x.uid ?? -1).flatMap(w.mon)
                default:                                                                            // a gift: minted here
                    var x = mon; x.uid = try nextUID(key, w); try record(key, x, kind: "mail", now: now); _ = w.keep(x); got = x
                }
            case .pickItem(let items): w.bag.append(items[pick!])
            case .pickLegend(let dex, let level, let shiny):
                var r = SystemRandomNumberGenerator()
                var x = Mon.wild(dex[pick!], level: level, shiny: shiny ? true : nil, perfect: 4, &r)
                x.uid = try nextUID(key, w); try record(key, x, kind: "tower", now: now); _ = w.keep(x); got = x
            default: w.receive(g)
            }
        }
        news += w.settleLearning(announceFrom: learn).map(\.news)
        try db.rows("UPDATE mail SET claimed_at = :now, read_at = coalesce(read_at, :now) WHERE id = :i", ["now": .int(now), "i": .int(id)])
        return nil
    }
    /// `mailClaimAll`: every mail with gifts and no 고르기. Returns how many.
    @discardableResult func claimAllMail(key: String, walk w: inout Walk, news: inout [News], now: Int) throws -> Int {
        var n = 0
        for m in try mailRows("key = :k AND claimed_at IS NULL ORDER BY id", ["k": .text(key)]) where !m.gifts.isEmpty && !m.mail.picks {
            var got: Mon? = nil
            if try claimMail(m.id, pick: nil, key: key, walk: &w, news: &news, got: &got, now: now) == nil { n += 1 }
        }
        return n
    }

    // MARK: the 우편함's list
    /// POST /v2/mail: the trainer's mail (gifts waiting first, then the newest); read = the ones just opened.
    func mailList(_ r: MailReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            let unix = Int(now.timeIntervalSince1970)
            for id in r.read ?? [] { try db.rows("UPDATE mail SET read_at = coalesce(read_at, :now) WHERE id = :i AND key = :k", ["now": .int(unix), "i": .int(id), "k": .text(key)]) }
            try pruneMail(key, now: unix)
            let rows = try mailRows("key = :k ORDER BY id DESC", ["k": .text(key)])
            let waiting = rows.filter { !$0.claimed && !$0.gifts.isEmpty }, rest = rows.filter { $0.claimed || $0.gifts.isEmpty }
            let unread = rows.filter { !$0.read || (!$0.claimed && !$0.gifts.isEmpty) }.count
            return try JSONEncoder().encode(MailReply(mails: (waiting + rest).map(\.mail), unread: unread))
        }
    }
    /// Old mail goes: claimed or gift-less and read, 30 days on; unread notices, 90. Gifts never go unclaimed.
    func pruneMail(_ key: String? = nil, now: Int) throws {
        let who = key.map { _ in "key = :k AND " } ?? "", k: [String: SQLValue] = key.map { ["k": .text($0)] } ?? [:]
        try db.rows("DELETE FROM mail WHERE \(who)claimed_at IS NOT NULL AND claimed_at < :t", k.merging(["t": .int(now - mailKeptRead)]) { $1 })
        try db.rows("DELETE FROM mail WHERE \(who)gifts = '[]' AND read_at IS NOT NULL AND read_at < :t", k.merging(["t": .int(now - mailKeptRead)]) { $1 })
        try db.rows("DELETE FROM mail WHERE \(who)gifts = '[]' AND read_at IS NULL AND at < :t", k.merging(["t": .int(now - mailKeptUnread)]) { $1 })
    }

    // MARK: the Battle Tower's first-time rewards (docs/plans/15 §3)
    /// Every act: each streak reached (towerBest) and not yet rewarded gets its mail, once (tower_rewards). The save remembers which (the lobby's strip).
    /// This is also the back-pay: a trainer past some of them gets theirs on its first act after 3.9's server.
    func towerRewards(_ key: String, walk w: inout Walk, now: Int) throws {
        let best = w.towerBest ?? 0
        guard best >= (Tower.rewards.first?.wins ?? .max) else { return }
        let paid = Set(try db.rows("SELECT wins FROM tower_rewards WHERE key = :k", ["k": .text(key)]).compactMap { $0.int("wins") })
        for r in Tower.rewards where r.wins <= best && !paid.contains(r.wins) {
            try db.rows("INSERT INTO tower_rewards (key, wins, at) VALUES (:k, :w, :now)", ["k": .text(key), "w": .int(r.wins), "now": .int(now)])
            try sendMail(key, kind: "tower", from: "배틀 타워", title: "\(r.wins)연승 달성 보상", body: "배틀 타워에서 처음으로 \(r.wins)연승에 닿았어요.", gifts: r.gifts, now: now)
        }
        let all = Set(try db.rows("SELECT wins FROM tower_rewards WHERE key = :k", ["k": .text(key)]).compactMap { $0.int("wins") })
        if Set(w.towerRewards ?? []) != all { w.towerRewards = all.sorted() }
    }

    // MARK: 3.8's 받기 함, folded in
    /// Startup: whatever still waits in the old 받기 함 becomes mail (once: they're marked claimed).
    static let claimsToMail = """
        INSERT INTO mail (key, kind, from_name, title, body, gifts, at)
          SELECT key, CASE kind WHEN 'traded' THEN 'trade' ELSE kind END, from_name,
                 CASE kind WHEN 'traded' THEN '교환으로 받은 포켓몬' WHEN 'visit' THEN '맡겼던 포켓몬이 돌아왔어요' ELSE '돌아온 포켓몬' END,
                 note, '[{"mon":{"mon":' || mon || ',"steps":' || steps || '}}]', at FROM claims WHERE claimed_at IS NULL;
        UPDATE claims SET claimed_at = strftime('%s', 'now'), note = ifnull(note, '') || ' (우편으로)' WHERE claimed_at IS NULL;
        """

    // MARK: operators
    /// `pw mail <id|--all> --title … [--body …] [--item 이름 n]… [--bp n] [--watts n] [--title-gift 칭호] [--deco silver|gold]`
    func adminMail(_ to: String, title: String, body: String?, gifts: [Gift], now: Int) throws -> String {
        let keys: [String]
        if to == "--all" { keys = try db.rows("SELECT key FROM trainers ORDER BY key").compactMap { $0.text("key") }.filter { !isTestID($0) } }
        else { keys = [try key(to)] }
        for k in keys { try sendMail(k, kind: gifts.isEmpty ? "notice" : "admin", from: "운영자", title: title, body: body, gifts: gifts, now: now) }
        return "mailed \(keys.count) trainer(s): \(title)" + (gifts.isEmpty ? "" : " · \(gifts.count) gift(s)")
    }
    /// `pw mail-log [n]`: the last mails sent, newest first.
    func mailLog(last n: Int) throws -> String {
        let rows = try mailRows("1 = 1 ORDER BY id DESC LIMIT :n", ["n": .int(n)])
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return (["id     at                to          kind      claimed  title"] + rows.map { m in
            "\(String(m.id).padding(toLength: 6, withPad: " ", startingAt: 0)) \(f.string(from: Date(timeIntervalSince1970: TimeInterval(m.at))))  \(m.key.padding(toLength: 11, withPad: " ", startingAt: 0)) \(m.kind.padding(toLength: 9, withPad: " ", startingAt: 0)) \(m.claimed ? "yes" : (m.gifts.isEmpty ? "-" : "no ").padding(toLength: 3, withPad: " ", startingAt: 0))      \(m.title)"
        }).joined(separator: "\n")
    }
}
