import Foundation

// docs/plans/19 §12.3 (5.3, content53): 협동 — two friends walk their dragons (레시라무 · 제크로무) together: 300,000 steps between them in 14
// days, 30,000 each at least. An ask (pairInvite, 3 days) takes no one's place; taking it (pairAccept) puts both on their dragons at once (the
// others stopped: one at a time, plan 19 §6.3) and starts the 14 days. The steps the server takes from each (an act's `taken`) count; once there,
// each one's dragon goes on to its boss at that one's next act (a_moved · b_moved). An ask taken back or said no to, a pair ended (pairCancel,
// or another expedition started), 14 days gone: closed, the pair's steps with it — the dragon stays on, to ask again or walk alone (the engine's
// ExpProgress.steps, 200,000, not while paired: Play.paired). Each side hears it as news (a 5.3 app's inbox).

let pairSchema = """
    CREATE TABLE IF NOT EXISTS exp_pairs (id INTEGER PRIMARY KEY AUTOINCREMENT, a TEXT NOT NULL, a_name TEXT NOT NULL, b TEXT NOT NULL, b_name TEXT NOT NULL,
      a_exp TEXT NOT NULL, b_exp TEXT, state TEXT NOT NULL, why TEXT, asked_at INTEGER NOT NULL, starts INTEGER, ends INTEGER NOT NULL,
      a_steps INTEGER NOT NULL DEFAULT 0, b_steps INTEGER NOT NULL DEFAULT 0, a_moved INTEGER NOT NULL DEFAULT 0, b_moved INTEGER NOT NULL DEFAULT 0, closed_at INTEGER);
    CREATE INDEX IF NOT EXISTS exp_pairs_a ON exp_pairs (a, state);
    CREATE INDEX IF NOT EXISTS exp_pairs_b ON exp_pairs (b, state);
    """
let content53App = "5.3"                                                   // plan 19 §12.5: the app that plays 5.3's rules (and can be asked to pair)

struct PairRow {
    let id: Int, a: String, aName: String, b: String, bName: String, aExp: String, bExp: String?, state: String, askedAt: Int, starts: Int?, ends: Int
    let aSteps: Int, bSteps: Int, aMoved: Bool, bMoved: Bool
    func other(_ k: String) -> (key: String, name: String) { k == a ? (b, bName) : (a, aName) }
    func exp(_ k: String) -> String? { k == a ? aExp : bExp }
    func steps(_ k: String) -> Int { k == a ? aSteps : bSteps }
    /// 300,000 between them, 30,000 each.
    var reached: Bool { aSteps + bSteps >= Expeditions.pairGoal && min(aSteps, bSteps) >= Expeditions.pairMin }
}

extension SaveDB {
    func pairRows(_ sql: String, _ args: [String: SQLValue] = [:]) throws -> [PairRow] {
        try db.rows("SELECT * FROM exp_pairs WHERE " + sql + " ORDER BY id", args).compactMap { r in
            guard let id = r.int("id"), let a = r.text("a"), let b = r.text("b"), let ae = r.text("a_exp"), let st = r.text("state") else { return nil }
            return PairRow(id: id, a: a, aName: r.text("a_name") ?? a, b: b, bName: r.text("b_name") ?? b, aExp: ae, bExp: r.text("b_exp"), state: st,
                           askedAt: r.int("asked_at") ?? 0, starts: r.int("starts"), ends: r.int("ends") ?? 0, aSteps: r.int("a_steps") ?? 0, bSteps: r.int("b_steps") ?? 0,
                           aMoved: r.int("a_moved") == 1, bMoved: r.int("b_moved") == 1)
        }
    }
    /// This trainer's pair walking now (one at most).
    func pairOn(_ key: String) throws -> PairRow? { try pairRows("state = 'on' AND (a = :k OR b = :k)", ["k": .text(key)]).first }
    func closePair(_ p: PairRow, _ why: String, now: Int) throws {
        try db.rows("UPDATE exp_pairs SET state = 'closed', why = :w, closed_at = :now WHERE id = :i", ["w": .text(why), "now": .int(now), "i": .int(p.id)])
    }

    // MARK: the acts
    func pairAct(_ act: Act, key: String, name: String, walk w: inout Walk, news: inout [News], now: Int) throws -> String? {
        guard Content.v53 else { return "5.3부터예요" }
        try pairExpire(now: now)
        switch act {
        case .pairInvite(let raw, let id):
            if let why = w.pairCan(id) { return why }
            guard let to = trainerID(raw), to.key != key, let them = try trainer(to.key), isTestID(to.key) == isTestID(key) else { return "청할 수 없는\n트레이너예요" }
            guard try areFriends(key, to.key) else { return "친구에게만\n청할 수 있어요" }
            guard knows(try appSeen(to.key), content53App) || isTestID(to.key) else { return "상대가 5.3으로\n업데이트해야 해요" }
            if try pairOn(key) != nil { return "이미 짝이 있어요" }
            if try pairOn(to.key) != nil { return josa(them.name, "은", "는") + " 이미\n짝이 있어요" }
            for p in try pairRows("state = 'asked' AND a = :k", ["k": .text(key)]) {                 // one ask out at a time: the last one taken back
                try closePair(p, "취소", now: now)
                try post(.pairClosed(pair: p.id, with: name, why: "취소"), to: p.b, from: key, fromName: name, app: content53App, now: now)
            }
            try db.rows("""
                INSERT INTO exp_pairs (a, a_name, b, b_name, a_exp, state, asked_at, ends) VALUES (:a, :an, :b, :bn, :e, 'asked', :now, :end)
                """, ["a": .text(key), "an": .text(name), "b": .text(to.key), "bn": .text(them.name), "e": .text(id), "now": .int(now),
                      "end": .int(now + Expeditions.inviteDays * 86400)])
            let pid = try db.rows("SELECT last_insert_rowid() AS id").first?.int("id") ?? 0
            try post(.pairAsked(pair: pid, from: name, id: id), to: to.key, from: key, fromName: name, app: content53App, now: now)
            return nil
        case .pairAccept(let pid, let id):
            guard let p = try pairRows("id = :i AND state = 'asked' AND b = :k", ["i": .int(pid), "k": .text(key)]).first else { return "없는 청하기예요" }
            if let why = w.pairCan(id) { return why }
            if try pairOn(key) != nil { return "이미 짝이 있어요" }
            if try pairOn(p.a) != nil { try closePair(p, "취소", now: now); return "상대가 이미\n짝이 있어요" }
            if try playing(p.a) { return "상대가 배틀 중이에요\n잠시 뒤에 받아 주세요" }
            guard let them = try trainer(p.a), var theirs = them.walk.flatMap(decodeWalk) else { try closePair(p, "취소", now: now); return "없는 청하기예요" }
            var g = SystemRandomNumberGenerator()
            if let why = theirs.pairTake(p.aExp, &g) {                                                // their dragon went on to its boss meanwhile
                try closePair(p, "취소", now: now)
                try post(.pairClosed(pair: p.id, with: name, why: "취소"), to: p.a, from: key, fromName: name, app: content53App, now: now)
                _ = why; return "상대의 원정이\n이미 보스전이에요"
            }
            if let why = w.pairTake(id, &g) { return why }
            let text = savedText(theirs)
            try db.rows("UPDATE trainers SET walk = :w, rev = rev + 1, writer = 'pair' WHERE key = :k", ["w": .text(text), "k": .text(p.a)])
            if let rev = try trainer(p.a)?.rev { try keep(p.a, rev: rev, walk: text, now: now) }
            try db.rows("UPDATE exp_pairs SET state = 'on', b_exp = :e, starts = :now, ends = :end WHERE id = :i",
                        ["e": .text(id), "now": .int(now), "end": .int(now + Expeditions.pairDays * 86400), "i": .int(p.id)])
            for o in try pairRows("state = 'asked' AND id != :i AND (a IN (:a, :b) OR b IN (:a, :b))", ["i": .int(p.id), "a": .text(p.a), "b": .text(key)]) {
                try closePair(o, "취소", now: now)                                                     // the two's other asks: gone (one pair each)
                for k in [o.a, o.b] where k != p.a && k != key {
                    try post(.pairClosed(pair: o.id, with: o.other(k).name, why: "취소"), to: k, from: o.other(k).key, fromName: o.other(k).name, app: content53App, now: now)
                }
            }
            try post(.pairOn(pair: p.id, with: name, id: id), to: p.a, from: key, fromName: name, app: content53App, walk: true, now: now)
            return nil
        case .pairCancel(let pid):
            guard let p = try pairRows("id = :i AND state IN ('asked', 'on') AND (a = :k OR b = :k)", ["i": .int(pid), "k": .text(key)]).first else { return "없는 짝이에요" }
            let why = p.state == "on" ? "풀림" : p.a == key ? "취소" : "거절"
            try closePair(p, why, now: now)
            let o = p.other(key)
            try post(.pairClosed(pair: p.id, with: name, why: why), to: o.key, from: key, fromName: name, app: content53App, now: now)
            return nil
        default: return nil
        }
    }
    /// Whether this trainer has a fight on (the server's play row): a pair taken then would move its expedition under it.
    func playing(_ key: String) throws -> Bool {
        guard let s = try db.rows("SELECT state FROM play WHERE key = :k", ["k": .text(key)]).first?.text("state"),
              let p = try? JSONDecoder().decode(Play.self, from: Data(s.utf8)) else { return false }
        return p.battle != nil
    }

    // MARK: steps, time, the saves
    /// An act's steps: this trainer's side of its pair (walking now, before its end); 300,000 · 30,000 reached: done.
    func pairSteps(_ key: String, _ n: Int, now: Int) throws {
        guard n > 0, let p = try pairOn(key), now < p.ends else { return }
        try db.rows("UPDATE exp_pairs SET \(key == p.a ? "a_steps" : "b_steps") = \(key == p.a ? "a_steps" : "b_steps") + :n WHERE id = :i", ["n": .int(n), "i": .int(p.id)])
        if let q = try pairRows("id = :i", ["i": .int(p.id)]).first, q.reached { try db.rows("UPDATE exp_pairs SET state = 'done' WHERE id = :i", ["i": .int(p.id)]) }
    }
    /// Asks past 3 days and pairs past 14 days (not reached): closed, both told.
    func pairExpire(now: Int) throws {
        for p in try pairRows("state IN ('asked', 'on') AND ends <= :now", ["now": .int(now)]) {
            try closePair(p, "기한", now: now)
            try post(.pairClosed(pair: p.id, with: p.bName, why: "기한"), to: p.a, from: p.b, fromName: p.bName, app: content53App, now: now)
            if p.state == "on" { try post(.pairClosed(pair: p.id, with: p.aName, why: "기한"), to: p.b, from: p.a, fromName: p.aName, app: content53App, now: now) }
        }
    }
    /// After each act: a pair done moves this one's dragon on to its boss (once); a pair whose dragon this one no longer walks (another
    /// expedition started, here or on an older app) ends, the other told. Its own news into `news`.
    func pairTick(_ key: String, name: String, walk w: inout Walk, news: inout [News], now: Int) throws {
        try pairExpire(now: now)
        for p in try pairRows("state = 'done' AND ((a = :k AND a_moved = 0) OR (b = :k AND b_moved = 0))", ["k": .text(key)]) {
            if let id = p.exp(key), let n = w.pairDone(id) { news.append(n) }
            try db.rows("UPDATE exp_pairs SET \(key == p.a ? "a_moved" : "b_moved") = 1 WHERE id = :i", ["i": .int(p.id)])
        }
        if let p = try pairOn(key), let id = p.exp(key), !w.pairWalking(id) {
            try closePair(p, "풀림", now: now)
            let o = p.other(key)
            try post(.pairClosed(pair: p.id, with: name, why: "풀림"), to: o.key, from: key, fromName: name, app: content53App, now: now)
            news.append(.pairClosed(pair: p.id, with: o.name, why: "풀림"))
        }
    }
    /// /v2/expedition's pairs: my ask out, the asks to me, my pair — as I see them.
    func pairViews(_ key: String, now: Int) throws -> [PairView] {
        try pairExpire(now: now)
        return try pairRows("state IN ('asked', 'on') AND (a = :k OR b = :k)", ["k": .text(key)]).map { p in
            let o = p.other(key)
            let state = p.state == "on" ? "on" : p.a == key ? "sent" : "got"
            return PairView(id: p.id, with: o.name, state: state, mine: p.exp(key), theirs: p.exp(o.key) ?? p.aExp, steps: p.steps(key), theirSteps: p.steps(o.key),
                            goal: Expeditions.pairGoal, min: Expeditions.pairMin, ends: p.ends)
        }
    }

    // MARK: operators
    /// `pokeserver pairs`: every ask and pair not closed, and the last closed ones (read only).
    func pairsReport(now: Int) throws -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; f.timeZone = TimeZone(identifier: "Asia/Seoul")
        func when(_ t: Int?) -> String { t.map { f.string(from: Date(timeIntervalSince1970: TimeInterval($0))) } ?? "-" }
        let rows = try (pairRows("state != 'closed'") + pairRows("state = 'closed' AND closed_at > :t", ["t": .int(now - 7 * 86400)])).map { p -> [String] in
            [String(p.id), "\(p.aName) (\(p.aExp)) · \(p.bName) (\(p.bExp ?? "?"))", p.state + (p.state == "closed" ? "" : ""), when(p.starts ?? p.askedAt) + " ~ " + when(p.ends),
             "\(p.aSteps.formatted()) + \(p.bSteps.formatted()) / \(Expeditions.pairGoal.formatted())"]
        }
        return table(["id", "pair", "state", "from ~ ends (KST)", "steps"], rows) + "\ncontent53 " + ((try content53()) ? "on" : "off")
    }
}
