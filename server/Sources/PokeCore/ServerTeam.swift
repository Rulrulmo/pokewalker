import Foundation

// docs/plans/12 M1: the team — POST /v2/team (every 3.0 trainer's card, the server's own step counts, how long since each one acted) and
// 인사 (the greet act: into the other's inbox, at most once an hour per pair; delivered as `hello` news on its next act, app 3.2 on).

let teamSchema = """
    CREATE TABLE IF NOT EXISTS inbox (to_key TEXT NOT NULL, from_key TEXT NOT NULL, from_name TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL,
      at INTEGER NOT NULL, delivered INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS inbox_to ON inbox (to_key, delivered, at);
    """
let greetEvery = 3600, inboxKept = 86400                                   // one 인사 per pair an hour; undelivered ones go stale after a day

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
    func team(_ r: TeamReq, now: Date) -> Reply {
        guard let id = trainerID(r.id) else { return .error(400, "bad_id") }
        return guarded {
            guard let t = try trainer(id.key) else { return .error(404, "no_trainer") }
            guard r.session == t.session else { return .error(409, "conflict", ["reason": .s("replaced")]) }
            guard try hasPIN(id.key) else { return .error(403, "pin_needed") }
            let tester = isTestID(id.key)                                                         // test IDs (zz + 6 digits) see each other; players never see them
            if let c = teamCache[tester], now.timeIntervalSince1970 - c.at < 10 { return Reply(raw: 200, c.body) }   // 16+ teammates asking every few minutes: one build per 10 s
            let (week, days) = weekDays(now), today = Walk.key(now)
            var steps: [String: (today: Int, week: Int)] = [:]
            let inWeek = days.map { "'\($0)'" }.joined(separator: ",")
            for s in try db.rows("SELECT key, day, n FROM steps_day WHERE day IN (\(inWeek))") {
                guard let k = s.text("key"), let n = s.int("n") else { continue }
                steps[k, default: (0, 0)].week += n
                if s.text("day") == today { steps[k, default: (0, 0)].today += n }
            }
            let rows = try db.rows("""
                SELECT t.key, t.name, t.app, t.updated_at, p.bank_at, t.walk FROM trainers t LEFT JOIN play p ON p.key = t.key
                WHERE t.walk IS NOT NULL ORDER BY t.key
                """)
            var cards: [TeamCard] = []
            for row in rows where knows(row.text("app"), "3.0") {
                guard let k = row.text("key"), tester || !isTestID(k), let w = row.text("walk").flatMap(decodeWalk) else { continue }
                let last = max(Double(row.int("updated_at") ?? 0), row.real("bank_at") ?? 0)
                let s = steps[k] ?? (0, 0)
                cards.append(TeamCard(name: row.text("name") ?? k, walk: w, today: s.today, week: s.week, idle: max(0, Int(now.timeIntervalSince1970 - last))))
            }
            let e = JSONEncoder(); e.outputFormatting = .sortedKeys
            let body = try e.encode(TeamReply(week: week, cards: cards))
            teamCache[tester] = (now.timeIntervalSince1970, body)
            return Reply(raw: 200, body)
        }
    }

    /// The greet act's own part (the engine has done the steps): who to, once an hour; nil = sent.
    func greet(from key: String, name: String, to raw: String, companion: Mon, now: Int) throws -> String? {
        guard let to = trainerID(raw), to.key != key, let t = try trainer(to.key), knows(t.app, "3.0") else { return "인사할 수 없는\n트레이너예요" }
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
