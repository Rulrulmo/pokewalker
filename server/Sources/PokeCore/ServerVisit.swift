import Foundation

// docs/plans/14 §3 (3.8): 맡겨 키우기 (놀러가기). A trainer sends one of its walker's or box Pokémon to a friend walking now; for 5 hours every step
// the friend walks is 1 EXP for it. Then (or when either ends it early) it goes home through the owner's 받기 함 with those steps, and the friend
// gets 1 BP a 2,000 steps raised (5 at most) on its next act. One away per owner and friend (3.8.5, the user; one in all before), two guests per host (3.8.1).

let visitSchema = """
    CREATE TABLE IF NOT EXISTS visits (id INTEGER PRIMARY KEY AUTOINCREMENT, owner TEXT NOT NULL, owner_name TEXT NOT NULL, host TEXT NOT NULL, host_name TEXT NOT NULL,
      uid INTEGER NOT NULL, mon TEXT NOT NULL, steps INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL, at INTEGER NOT NULL, ends INTEGER NOT NULL, ended_at INTEGER,
      bp INTEGER NOT NULL DEFAULT 0, paid INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS visits_owner ON visits (owner, state);
    CREATE INDEX IF NOT EXISTS visits_host ON visits (host, state);
    """
let visitLife = 5 * 3600, visitGuests = 2, visitStepsPerBP = 2000, visitBPMax = 5, visitApp = "3.8"

struct VisitRow { let id: Int, owner: String, ownerName: String, host: String, hostName: String, uid: Int, mon: Mon, steps: Int, state: String, ends: Int, bp: Int, paid: Bool }

extension SaveDB {
    func visitRows(_ sql: String, _ args: [String: SQLValue] = [:]) throws -> [VisitRow] {
        try db.rows("SELECT id, owner, owner_name, host, host_name, uid, mon, steps, state, ends, bp, paid FROM visits WHERE " + sql, args).compactMap { r in
            guard let id = r.int("id"), let o = r.text("owner"), let h = r.text("host"), let m = r.text("mon").flatMap({ try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }) else { return nil }
            return VisitRow(id: id, owner: o, ownerName: r.text("owner_name") ?? o, host: h, hostName: r.text("host_name") ?? h, uid: r.int("uid") ?? 0, mon: m,
                            steps: r.int("steps") ?? 0, state: r.text("state") ?? "", ends: r.int("ends") ?? 0, bp: r.int("bp") ?? 0, paid: r.int("paid") == 1)
        }
    }
    /// Seconds since this trainer's last act (under 60: walking now — the app sends steps every 15 s).
    func idle(_ key: String, now: Int) throws -> Int {
        let r = try db.rows("SELECT t.updated_at, p.bank_at FROM trainers t LEFT JOIN play p ON p.key = t.key WHERE t.key = :k", ["k": .text(key)]).first
        return max(0, now - Int(max(Double(r?.int("updated_at") ?? 0), r?.real("bank_at") ?? 0)))
    }
    /// The app this trainer last acted with (14 §8).
    func appSeen(_ key: String) throws -> String? { try db.rows("SELECT app_seen FROM trainers WHERE key = :k", ["k": .text(key)]).first?.text("app_seen") }

    // MARK: the acts
    func visitAct(_ act: Act, key: String, name: String, walk w: inout Walk, news: inout [News], now: Int) throws -> String? {
        switch act {
        case .visitSend(let raw, let uid):
            guard let to = trainerID(raw), to.key != key, let host = try trainer(to.key), isTestID(to.key) == isTestID(key) else { return "보낼 수 없는\n트레이너예요" }
            guard try areFriends(key, to.key) else { return "친구에게만\n보낼 수 있어요" }
            guard try idle(to.key, now: now) < 60 else { return "지금 걷고 있는 친구에게만\n보낼 수 있어요" }
            guard knows(try appSeen(to.key), visitApp) else { return "상대가 3.8로\n업데이트해야 해요" }
            guard try visitRows("owner = :k AND host = :h AND state = 'on'", ["k": .text(key), "h": .text(to.key)]).isEmpty else { return josa(host.name, "에게", "에게") + " 이미\n맡긴 포켓몬이 있어요" }
            guard let ref = w.ref(uid: uid) else { return "그 포켓몬은\n없어요" }
            guard ref != -1 else { return "동료는 보낼 수 없어요" }
            guard try visitRows("host = :k AND state = 'on'", ["k": .text(to.key)]).count < visitGuests else { return josa(host.name, "은", "는") + " 이미\n\(visitGuests)마리를 맡고 있어요" }
            guard let m = w.mon(ref) else { return "그 포켓몬은\n없어요" }
            if ref <= -2 { w.caught.remove(at: -2 - ref) } else { w.box.remove(at: ref) }
            w.duelParty = w.duelParty?.filter { $0 != uid }
            let e = JSONEncoder(); e.outputFormatting = .sortedKeys
            try db.rows("""
                INSERT INTO visits (owner, owner_name, host, host_name, uid, mon, state, at, ends) VALUES (:o, :on, :h, :hn, :u, :m, 'on', :now, :end)
                """, ["o": .text(key), "on": .text(name), "h": .text(to.key), "hn": .text(host.name), "u": .int(uid), "m": .text(String(decoding: try e.encode(m), as: UTF8.self)),
                      "now": .int(now), "end": .int(now + visitLife)])
            let id = try db.rows("SELECT last_insert_rowid() AS id").first?.int("id") ?? 0
            try post(.visitCame(id: id, owner: name, dex: m.dex, shiny: m.shiny == true), to: to.key, from: key, fromName: name, app: visitApp, now: now)
            return nil
        case .visitEnd(let id):
            guard let v = try visitRows("id = :i AND state = 'on'", ["i": .int(id)]).first, v.owner == key || v.host == key else { return "그 포켓몬은 이제\n여기 없어요" }
            try endVisit(v, now: now)
            try payVisits(key, walk: &w, news: &news)
            return nil
        default: return nil
        }
    }
    /// A visit over (its 5 hours, or ended early): the owner's 받기 함 gets the Pokémon with the steps raised; the host's BP waits for its next act.
    func endVisit(_ v: VisitRow, now: Int) throws {
        let bp = min(visitBPMax, v.steps / visitStepsPerBP)
        try db.rows("UPDATE visits SET state = 'done', ended_at = :now, bp = :bp WHERE id = :i", ["now": .int(now), "bp": .int(bp), "i": .int(v.id)])
        try sendMail(v.owner, kind: "visit", from: v.hostName, fromKey: v.host, title: "맡겼던 포켓몬이 돌아왔어요",
                     body: josa(v.hostName, "이", "가") + " \(v.steps.formatted())걸음 키워 줬어요", gifts: [.mon(mon: v.mon, steps: v.steps)], now: now)
    }
    /// Every act: the host's steps (taken now) to its guests; visits past their 5 hours end; a host's BP for the ones done comes in.
    func visitTick(_ key: String, steps: Int, walk w: inout Walk, news: inout [News], now: Int) throws {
        if steps > 0 { try db.rows("UPDATE visits SET steps = steps + :n WHERE host = :k AND state = 'on' AND ends >= :now", ["n": .int(steps), "k": .text(key), "now": .int(now)]) }
        for v in try visitRows("(host = :k OR owner = :k) AND state = 'on' AND ends < :now", ["k": .text(key), "now": .int(now)]) { try endVisit(v, now: now) }
        try payVisits(key, walk: &w, news: &news)
    }
    func payVisits(_ key: String, walk w: inout Walk, news: inout [News]) throws {
        for v in try visitRows("host = :k AND state = 'done' AND paid = 0", ["k": .text(key)]) {
            if v.bp > 0 { w.bp = (w.bp ?? 0) + v.bp }
            news.append(.visitDone(owner: v.ownerName, dex: v.mon.dex, steps: v.steps, bp: v.bp))
            try db.rows("UPDATE visits SET paid = 1 WHERE id = :i", ["i": .int(v.id)])
        }
    }
    /// /v2/team's part: mine away, the ones I'm raising.
    func visits(_ key: String) throws -> Visits {
        func view(_ v: VisitRow) -> Visit { Visit(id: v.id, owner: v.ownerName, host: v.hostName, mon: v.mon, steps: v.steps, ends: v.ends) }
        let mine = try visitRows("owner = :k AND state = 'on' ORDER BY id", ["k": .text(key)]).map(view)
        return Visits(away: mine.last, guests: try visitRows("host = :k AND state = 'on' ORDER BY id", ["k": .text(key)]).map(view), out: mine)
    }
}
