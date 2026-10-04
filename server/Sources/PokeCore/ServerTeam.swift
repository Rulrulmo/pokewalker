import Foundation

// docs/plans/12 M1: the team — POST /v2/team (every 3.0 trainer's card, the server's own step counts, how long since each one acted) and
// 인사 (the greet act: into the other's inbox, at most once an hour per pair; delivered as `hello` news on its next act, app 3.2 on).

let teamSchema = """
    CREATE TABLE IF NOT EXISTS inbox (to_key TEXT NOT NULL, from_key TEXT NOT NULL, from_name TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL,
      at INTEGER NOT NULL, delivered INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS inbox_to ON inbox (to_key, delivered, at);
    """
let greetEvery = 3600, inboxKept = 86400                                   // one 인사 per pair an hour; undelivered ones go stale after a day
let friendsSchema = """
    CREATE TABLE IF NOT EXISTS friends (a TEXT NOT NULL, b TEXT NOT NULL, state TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (a, b));
    CREATE INDEX IF NOT EXISTS friends_b ON friends (b);
    """
let friendsMax = 100, friendAsksMax = 20, friendApp = "3.5"

/// The app knows news kinds from `v` on (12 §1: an older app can't decode them).
func knows(_ app: String?, _ v: String) -> Bool { app.flatMap { verCmp($0, v) }.map { $0 >= 0 } ?? false }
/// This week's days (Monday first, the server's time zone: KST) up to today, as steps_day keys; and its "2026-W40".
func weekDays(_ now: Date) -> (key: String, days: [String]) {
    var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
    let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    let n = (cal.dateComponents([.day], from: start, to: now).day ?? 0) + 1
    let days = (0..<max(1, n)).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.map(Walk.key)
    return (String(format: "%04d-W%02d", cal.component(.yearForWeekOfYear, from: now), cal.component(.weekOfYear, from: now)), days)
}

extension SaveDB {
    /// 12 §2.4 (3.5): me and my friends' cards (2.1's shape), the requests to me and mine out.
    func team(_ r: TeamReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            let (week, days) = weekDays(now), today = Walk.key(now)
            let keys = [key] + (try friendKeys(key))
            let everyone = viewAll.contains(key) ? try db.rows("SELECT key FROM trainers ORDER BY updated_at DESC").compactMap { $0.text("key") }.filter { isTestID($0) == isTestID(key) } : []
            var steps: [String: (today: Int, week: Int)] = [:]
            let inWeek = days.map { "'\($0)'" }.joined(separator: ",")
            for s in try db.rows("SELECT key, day, n FROM steps_day WHERE day IN (\(inWeek))") {
                guard let k = s.text("key"), keys.contains(k) || everyone.contains(k), let n = s.int("n") else { continue }
                steps[k, default: (0, 0)].week += n
                if s.text("day") == today { steps[k, default: (0, 0)].today += n }
            }
            func card(_ k: String) throws -> TeamCard? {
                guard let row = try db.rows("SELECT t.name, t.updated_at, p.bank_at, t.walk FROM trainers t LEFT JOIN play p ON p.key = t.key WHERE t.key = :k",
                                            ["k": .text(k)]).first, let w = row.text("walk").flatMap(decodeWalk) else { return nil }
                let last = max(Double(row.int("updated_at") ?? 0), row.real("bank_at") ?? 0), s = steps[k] ?? (0, 0)
                return TeamCard(name: row.text("name") ?? k, walk: w, today: s.today, week: s.week, idle: max(0, Int(now.timeIntervalSince1970 - last)))
            }
            let cards = try keys.compactMap(card)
            let asks = try db.rows("SELECT t.name FROM friends f JOIN trainers t ON t.key = f.a WHERE f.b = :k AND f.state = 'pending' ORDER BY f.at", ["k": .text(key)]).compactMap { $0.text("name") }
            let sent = try db.rows("SELECT t.name FROM friends f JOIN trainers t ON t.key = f.b WHERE f.a = :k AND f.state = 'pending' ORDER BY f.at", ["k": .text(key)]).compactMap { $0.text("name") }
            let e = JSONEncoder(); e.outputFormatting = .sortedKeys
            return try e.encode(TeamReply(week: week, cards: cards, requests: asks, sent: sent, visits: try visits(key),
                                          all: everyone.isEmpty ? nil : try everyone.compactMap(card)))
        }
    }
    func friendKeys(_ key: String) throws -> [String] {
        try db.rows("SELECT CASE WHEN a = :k THEN b ELSE a END AS f FROM friends WHERE (a = :k OR b = :k) AND state = 'friends' ORDER BY at", ["k": .text(key)]).compactMap { $0.text("f") }
    }
    func areFriends(_ x: String, _ y: String) throws -> Bool {
        try !db.rows("SELECT 1 AS n FROM friends WHERE ((a = :x AND b = :y) OR (a = :y AND b = :x)) AND state = 'friends'", ["x": .text(x), "y": .text(y)]).isEmpty
    }
    /// 친구 (12 §2.4): ask (mutual at once if they asked first), accept, decline, remove (a request out too). nil = done.
    func friendAct(_ act: Act, key: String, name: String, now: Int) throws -> String? {
        func other(_ raw: String) throws -> (key: String, name: String)? {
            guard let id = trainerID(raw), id.key != key, let t = try trainer(id.key), knows(t.app, "3.0") else { return nil }
            return (id.key, t.name)
        }
        func pending(_ a: String, _ b: String) throws -> Bool {
            try !db.rows("SELECT 1 AS n FROM friends WHERE a = :a AND b = :b AND state = 'pending'", ["a": .text(a), "b": .text(b)]).isEmpty
        }
        switch act {
        case .friendRequest(let raw):
            guard let o = try other(raw) else { return "친구를 맺을 수 없는\n트레이너예요" }
            if try areFriends(key, o.key) { return "이미 친구예요" }
            if try pending(o.key, key) {                                                          // they asked first: friends now
                try db.rows("UPDATE friends SET state = 'friends', at = :now WHERE a = :a AND b = :b", ["now": .int(now), "a": .text(o.key), "b": .text(key)])
                try post(.friendAdded(name: name), to: o.key, from: key, fromName: name, app: friendApp, now: now)
                return nil
            }
            if try pending(key, o.key) { return "이미 신청했어요" }
            guard try friendKeys(key).count < friendsMax else { return "친구가 너무 많아요\n(\(friendsMax)명)" }
            let asked = try db.rows("SELECT count(*) AS n FROM friends WHERE a = :k AND state = 'pending'", ["k": .text(key)]).first?.int("n") ?? 0
            guard asked < friendAsksMax else { return "걸어 둔 신청이\n너무 많아요" }
            try db.rows("INSERT INTO friends (a, b, state, at) VALUES (:a, :b, 'pending', :now)", ["a": .text(key), "b": .text(o.key), "now": .int(now)])
            try post(.friendRequest(from: name), to: o.key, from: key, fromName: name, app: friendApp, now: now)
            return nil
        case .friendAccept(let raw), .friendDecline(let raw):
            guard let o = try other(raw), try pending(o.key, key) else { return "그 신청은 이제\n없어요" }
            if case .friendAccept = act {
                guard try friendKeys(key).count < friendsMax else { return "친구가 너무 많아요\n(\(friendsMax)명)" }
                try db.rows("UPDATE friends SET state = 'friends', at = :now WHERE a = :a AND b = :b", ["now": .int(now), "a": .text(o.key), "b": .text(key)])
                try post(.friendAdded(name: name), to: o.key, from: key, fromName: name, app: friendApp, now: now)
            } else { try db.rows("DELETE FROM friends WHERE a = :a AND b = :b", ["a": .text(o.key), "b": .text(key)]) }
            return nil
        case .friendRemove(let raw):
            guard let id = trainerID(raw) else { return "친구가 아니에요" }
            try db.rows("DELETE FROM friends WHERE (a = :k AND b = :o) OR (a = :o AND b = :k AND state = 'friends')", ["k": .text(key), "o": .text(id.key)])
            return db.changes > 0 ? nil : "친구가 아니에요"
        default: return nil
        }
    }

    /// The greet act's own part (the engine has done the steps): who to, once an hour; nil = sent.
    func greet(from key: String, name: String, to raw: String, companion: Mon, now: Int) throws -> String? {
        guard let to = trainerID(raw), to.key != key, let t = try trainer(to.key), knows(t.app, "3.0") else { return "인사할 수 없는\n트레이너예요" }
        guard try areFriends(key, to.key) else { return "친구에게만\n인사할 수 있어요" }   // 12 §2.4 (3.5)
        let last = try db.rows("SELECT max(at) AS at FROM inbox WHERE from_key = :f AND to_key = :t AND payload LIKE '{\"hello\"%'", ["f": .text(key), "t": .text(to.key)]).first?.int("at")
        if let last, now - last < greetEvery { return "조금 뒤에 다시\n인사할 수 있어요" }
        try post(.hello(from: name, dex: companion.dex, shiny: companion.shiny == true), to: to.key, from: key, fromName: name, app: "3.2", now: now)
        return nil
    }
    /// What waits for this trainer and its app can read (a day at most; trade news a week: an offer's answer is worth waiting for), as news,
    /// marked delivered (its reply is stored: a resend brings it again); walk: one came with a change to its save (a trade), the reply carries it.
    func delivery(_ key: String, app: String?, now: Int) throws -> (news: [News], walk: Bool) {
        let rows = try db.rows("SELECT rowid AS id, payload, min_app, walk, at FROM inbox WHERE to_key = :k AND delivered = 0 AND kind = 'news' ORDER BY at",
                               ["k": .text(key)])
        var out: [News] = [], walk = false, done: [Int] = []
        for r in rows {
            guard let id = r.int("id") else { continue }
            if r.int("walk") == 1 { walk = true; done.append(id) }                              // the save changed either way: send it (once)
            guard knows(app, r.text("min_app") ?? "3.2") else { continue }
            if r.int("walk") != 1 { done.append(id) }
            guard now - (r.int("at") ?? 0) <= (r.int("walk") == 1 ? 7 * 86400 : inboxKept),
                  let n = r.text("payload").flatMap({ try? JSONDecoder().decode(News.self, from: Data($0.utf8)) }) else { continue }
            out.append(n)
        }
        for id in done { try db.rows("UPDATE inbox SET delivered = 1 WHERE rowid = :i", ["i": .int(id)]) }
        return (out, walk)
    }
}
