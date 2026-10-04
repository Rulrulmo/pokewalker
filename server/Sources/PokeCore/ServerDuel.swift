import Foundation

// docs/plans/12 §5 (3.6): 실시간 대전. A friend asks, the other says yes within a minute; both parties come in as the tower's (Lv.50 copies). One Battle,
// kept from the challenger's side (mine = the challenger's, theirs = the other's, pvp on); each turn waits for both picks (30 s each: one not made
// in time is made for it, two in a row and that side gives up), then the engine plays it. The other player sees it mirrored (Battle/Duel.swift).
// The winner gets 3 BP; both records move. No items, no running: fight, switch, give up.

let duelSchema = """
    CREATE TABLE IF NOT EXISTS duels (id INTEGER PRIMARY KEY AUTOINCREMENT, a TEXT NOT NULL, b TEXT NOT NULL, a_name TEXT NOT NULL, b_name TEXT NOT NULL,
      state TEXT NOT NULL, battle TEXT, turns TEXT NOT NULL DEFAULT '[]', plan_a TEXT, plan_b TEXT, need_a TEXT, need_b TEXT, idle_a INTEGER NOT NULL DEFAULT 0,
      idle_b INTEGER NOT NULL DEFAULT 0, deadline INTEGER NOT NULL, version INTEGER NOT NULL DEFAULT 0, winner TEXT, why TEXT, at INTEGER NOT NULL, ended_at INTEGER);
    CREATE INDEX IF NOT EXISTS duels_a ON duels (a, state);
    CREATE INDEX IF NOT EXISTS duels_b ON duels (b, state);
    """
let duelInviteLife = 60, duelTurnLife = 30, duelIdleMax = 2, duelBP = 3, duelApp = "3.6"

struct DuelRow {
    var id: Int, a: String, b: String, aName: String, bName: String, state: String
    var battle: Battle?, turns: [[Beat]], planA: BattleCmd?, planB: BattleCmd?, needA: String?, needB: String?, idleA: Int, idleB: Int
    var deadline: Int, version: Int, winner: String?, why: String?
    func side(_ key: String) -> Int? { key == a ? 0 : key == b ? 1 : nil }
}

extension SaveDB {
    func duelRows(_ sql: String, _ args: [String: SQLValue] = [:]) throws -> [DuelRow] {
        let dec = JSONDecoder()
        return try db.rows("SELECT id, a, b, a_name, b_name, state, battle, turns, plan_a, plan_b, need_a, need_b, idle_a, idle_b, deadline, version, winner, why FROM duels WHERE " + sql, args).compactMap { r in
            guard let id = r.int("id"), let a = r.text("a"), let b = r.text("b") else { return nil }
            func j<T: Decodable>(_ c: String, _ t: T.Type) -> T? { r.text(c).flatMap { try? dec.decode(T.self, from: Data($0.utf8)) } }
            return DuelRow(id: id, a: a, b: b, aName: r.text("a_name") ?? a, bName: r.text("b_name") ?? b, state: r.text("state") ?? "", battle: j("battle", Battle.self),
                           turns: j("turns", [[Beat]].self) ?? [], planA: j("plan_a", BattleCmd.self), planB: j("plan_b", BattleCmd.self), needA: r.text("need_a"), needB: r.text("need_b"),
                           idleA: r.int("idle_a") ?? 0, idleB: r.int("idle_b") ?? 0, deadline: r.int("deadline") ?? 0, version: r.int("version") ?? 0, winner: r.text("winner"), why: r.text("why"))
        }
    }
    func saveDuel(_ d: DuelRow, endedAt: Int? = nil) throws {
        let e = JSONEncoder()
        func t<T: Encodable>(_ v: T?) throws -> SQLValue { try v.map { .text(String(decoding: try e.encode($0), as: UTF8.self)) } ?? .null }
        try db.rows("""
            UPDATE duels SET state = :s, battle = :bt, turns = :tu, plan_a = :pa, plan_b = :pb, need_a = :na, need_b = :nb, idle_a = :ia, idle_b = :ib,
              deadline = :dl, version = :v, winner = :w, why = :why, ended_at = coalesce(ended_at, :end) WHERE id = :id
            """, ["s": .text(d.state), "bt": try t(d.battle), "tu": try t(d.turns), "pa": try t(d.planA), "pb": try t(d.planB), "na": d.needA.map(SQLValue.text) ?? .null,
                  "nb": d.needB.map(SQLValue.text) ?? .null, "ia": .int(d.idleA), "ib": .int(d.idleB), "dl": .int(d.deadline), "v": .int(d.version),
                  "w": d.winner.map(SQLValue.text) ?? .null, "why": d.why.map(SQLValue.text) ?? .null, "end": endedAt.map(SQLValue.int) ?? .null, "id": .int(d.id)])
    }
    /// This trainer's live battle: an open one (invited or on), else the last one (for its result).
    func duelOf(_ key: String) throws -> DuelRow? {
        try duelRows("(a = :k OR b = :k) AND state IN ('invited', 'active') ORDER BY id DESC LIMIT 1", ["k": .text(key)]).first
            ?? duelRows("(a = :k OR b = :k) ORDER BY id DESC LIMIT 1", ["k": .text(key)]).first
    }

    // MARK: the acts (after the engine walked the steps; `w` is the acting trainer's save, which act() writes back)
    func duelAct(_ act: Act, key: String, name: String, walk w: inout Walk, out: inout Outcome, now: Int) throws -> String? {
        if var d = try duelOf(key) { try tick(&d, actor: key, walk: &w, now: now) }
        switch act {
        case .duelChallenge(let raw):
            guard let to = trainerID(raw), to.key != key, let them = try trainer(to.key), knows(them.app, "3.0") else { return "대전할 수 없는\n트레이너예요" }
            guard try areFriends(key, to.key) else { return "친구와만\n대전할 수 있어요" }
            for k in [key, to.key] where try !duelRows("(a = :k OR b = :k) AND state IN ('invited', 'active')", ["k": .text(k)]).isEmpty {
                return k == key ? "이미 대전 중이에요" : "상대가 대전 중이에요"
            }
            try db.rows("INSERT INTO duels (a, b, a_name, b_name, state, deadline, at) VALUES (:a, :b, :an, :bn, 'invited', :dl, :now)",
                        ["a": .text(key), "b": .text(to.key), "an": .text(name), "bn": .text(them.name), "dl": .int(now + duelInviteLife), "now": .int(now)])
            let id = try db.rows("SELECT last_insert_rowid() AS id").first?.int("id") ?? 0
            try post(.duelInvite(id: id, from: name), to: to.key, from: key, fromName: name, app: duelApp, now: now)
            out.duel = try view(id, for: key, since: 0)
            return nil
        case .duelAccept(let id), .duelDecline(let id), .duelCancel(let id):
            guard var d = try duelRows("id = :i", ["i": .int(id)]).first, d.state == "invited" else { return "그 대전은 이제\n없어요" }
            switch act {
            case .duelCancel: guard d.a == key else { return "그 대전은 이제\n없어요" }; d.state = "cancelled"
            case .duelDecline: guard d.b == key else { return "그 대전은 이제\n없어요" }; d.state = "declined"
            default:
                guard d.b == key else { return "그 대전은 이제\n없어요" }
                guard let them = try trainer(d.a), let theirs = them.walk.flatMap(decodeWalk) else { return "그 대전은 이제\n없어요" }
                func party(_ x: Walk) -> [Mon] { x.party().map { p -> Mon in var m = p.mon; if m.known == nil { m.known = m.moves }; m.level = Walk.towerLevel; return m } }
                var b = Battle(party: party(theirs), trainer: name, foes: party(w)); b.pvp = true
                var g = SystemRandomNumberGenerator(); b.seed = g.next()
                d.turns = [b.begin(weather: nil, &g)]; d.battle = b
                d.state = "active"; (d.needA, d.needB) = ("move", "move"); d.deadline = now + duelTurnLife
            }
            d.version += 1; try saveDuel(d, endedAt: d.state == "active" ? nil : now)
            out.duel = try view(d.id, for: key, since: 0)
            return nil
        case .duelMove(let id, let cmd):
            guard var d = try duelRows("id = :i", ["i": .int(id)]).first, d.state == "active", let side = d.side(key), var b = d.battle else { return "그 대전은 이제\n없어요" }
            guard let need = side == 0 ? d.needA : d.needB else { return "상대를 기다리는 중이에요" }
            let s: Side = side == 0 ? .me : .it
            switch (need, cmd) {
            case ("move", .forfeit): break
            case ("move", .fight(let slot)):
                if b.forcedMove(s) == nil {
                    let x = b.f(s)
                    guard x.moves.indices.contains(slot) else { return "그 기술은 없어요" }
                    let mv = x.moves[slot]
                    if x.pp[slot] == 0 { return "기술의 남은\nPP가 없다!" }
                    if !b.usable(s).contains(mv), !b.usable(s).isEmpty { return "지금은 쓸 수 없는\n기술이다!" }
                }
            case ("move", .swap(let i)):
                let mine = side == 0 ? b.mine : b.theirs, cur = side == 0 ? b.me : b.it
                guard mine.indices.contains(i), mine[i].alive, i != cur else { return "교체할 수 없어요" }
                if let why = b.switchBlock(s) { return why }
            case ("replace", .replace(let i)):
                let mine = side == 0 ? b.mine : b.theirs, cur = side == 0 ? b.me : b.it
                guard mine.indices.contains(i), mine[i].alive, i != cur else { return "교체할 수 없어요" }
            default: return need == "replace" ? "다음 포켓몬을\n골라 주세요" : "대전에서는 쓸 수 없어요"
            }
            if side == 0 { d.planA = cmd; d.needA = nil; d.idleA = 0 } else { d.planB = cmd; d.needB = nil; d.idleB = 0 }
            d.version += 1
            _ = b
            try resolve(&d, actor: key, walk: &w, now: now)
            out.duel = try view(d.id, for: key, since: d.turns.count - 1)
            return nil
        default: return nil
        }
    }

    /// Picks not made in time are made (the first usable move, the first one that can come in); two in a row and that side gives up. An invitation
    /// past its minute goes. Then whatever is due is played.
    func tick(_ d: inout DuelRow, actor: String?, walk w: inout Walk, now: Int) throws {
        guard now > d.deadline else { return }
        if d.state == "invited" { d.state = "expired"; d.version += 1; try saveDuel(d, endedAt: now); return }
        guard d.state == "active", let b = d.battle else { return }
        for side in [0, 1] {
            guard let need = side == 0 ? d.needA : d.needB else { continue }
            let s: Side = side == 0 ? .me : .it, mine = side == 0 ? b.mine : b.theirs, cur = side == 0 ? b.me : b.it
            let idle = (side == 0 ? d.idleA : d.idleB) + 1
            var pick: BattleCmd
            if idle >= duelIdleMax { pick = .forfeit }
            else if need == "replace" { pick = .replace(to: mine.indices.first { mine[$0].alive && $0 != cur } ?? cur) }
            else { pick = .fight(slot: b.f(s).moves.indices.first { b.usable(s).contains(b.f(s).moves[$0]) } ?? 0) }
            if side == 0 { d.planA = pick; d.needA = nil; d.idleA = idle } else { d.planB = pick; d.needB = nil; d.idleB = idle }
        }
        d.version += 1
        try resolve(&d, actor: actor, walk: &w, now: now, timedOut: true)
    }

    /// Both picks in (or none owed): the turn (or the replacements), the next needs, or the end.
    func resolve(_ d: inout DuelRow, actor: String?, walk w: inout Walk, now: Int, timedOut: Bool = false) throws {
        guard d.state == "active", d.needA == nil, d.needB == nil, var b = d.battle else { try saveDuel(d); return }
        if d.planA == .forfeit || d.planB == .forfeit {
            let aQuit = d.planA == .forfeit
            try finish(&d, winner: aQuit ? d.b : d.a, why: timedOut && ((aQuit ? d.idleA : d.idleB) >= duelIdleMax) ? "timeout" : "forfeit", actor: actor, walk: &w, now: now)
            return
        }
        var beats: [Beat] = []
        var g = SystemRandomNumberGenerator()
        if b.mustReplace || b.foeMustReplace == true {                                             // the replacements a KO asked for
            if case .replace(let i)? = d.planA, b.mustReplace { beats += b.replace(i) }
            if case .replace(let i)? = d.planB, b.foeMustReplace == true { beats += b.replaceFoe(i) }
        } else {
            var mine: Move = .fight(165)
            switch d.planA { case .fight(let slot)?: mine = .fight(b.forcedMove(.me) ?? b.f(.me).moves[safe: slot] ?? 165); case .swap(let i)?: mine = .swap(i); default: break }
            switch d.planB { case .fight(let slot)?: b.foePlan = .fight(b.forcedMove(.it) ?? b.f(.it).moves[safe: slot] ?? 165); case .swap(let i)?: b.foePlan = .swap(i); default: b.foePlan = .fight(165) }
            if case .fight(let id) = mine, b.usable(.me).isEmpty, b.forcedMove(.me) == nil, id != 165 { mine = .fight(165) }   // nothing it may use: 발버둥
            beats = b.turn(mine, &g)
            b.foePlan = nil
        }
        d.turns.append(beats); d.battle = b; (d.planA, d.planB) = (nil, nil); d.version += 1
        if b.over {
            let aWon = beats.last == .won
            try finish(&d, winner: aWon ? d.a : d.b, why: "faint", actor: actor, walk: &w, now: now)
            return
        }
        switch (b.mustReplace, b.foeMustReplace == true) {
        case (false, false): (d.needA, d.needB) = ("move", "move")
        case (let a, let bb): (d.needA, d.needB) = (a ? "replace" : nil, bb ? "replace" : nil)
        }
        d.deadline = now + duelTurnLife
        try saveDuel(d)
    }

    /// Over: the winner's BP and both records (the acting trainer's through `w`, the other's straight to its row: rev + 1, its app gets it).
    func finish(_ d: inout DuelRow, winner: String, why: String, actor: String?, walk w: inout Walk, now: Int) throws {
        d.state = "over"; d.winner = winner; d.why = why; (d.needA, d.needB) = (nil, nil); d.version += 1
        try saveDuel(d, endedAt: now)
        for k in [d.a, d.b] {
            let won = k == winner
            func change(_ x: inout Walk) { if won { x.bp = (x.bp ?? 0) + duelBP; x.duelWins = (x.duelWins ?? 0) + 1 } else { x.duelLosses = (x.duelLosses ?? 0) + 1 } }
            if k == actor { change(&w); continue }
            guard let t = try trainer(k), var x = t.walk.flatMap(decodeWalk) else { continue }
            change(&x)
            let text = savedText(x)
            try db.rows("UPDATE trainers SET walk = :w, rev = rev + 1, writer = 'duel' WHERE key = :k", ["w": .text(text), "k": .text(k)])
            if let rev = try trainer(k)?.rev { try keep(k, rev: rev, walk: text, now: now) }
        }
    }

    /// The battle as `key` sees it: the turns after `since`, its own side first, the lines worded for it.
    func view(_ id: Int, for key: String, since: Int) throws -> DuelView? {
        guard let d = try duelRows("id = :i", ["i": .int(id)]).first, let side = d.side(key) else { return nil }
        let first = side == 0
        var v = DuelView(id: d.id, state: d.state, opponent: first ? d.bName : d.aName, challenger: first, turn: d.turns.count,
                         need: first ? d.needA : d.needB, deadline: d.state == "active" || d.state == "invited" ? d.deadline : nil, version: d.version)
        let fresh = Array(d.turns.dropFirst(max(0, since)).joined())
        if let b = d.battle {
            if first { v.battle = b; v.beats = fresh }
            else {
                let words = duelWords(ours: b.mine.map(\.mon.dex), theirs: b.theirs.map(\.mon.dex))
                v.battle = b.mirrored(name: d.aName); v.beats = fresh.map { $0.flipped(words) }
            }
        }
        if d.state == "over", let wnr = d.winner { let won = wnr == key; v.result = DuelResult(won: won, why: d.why ?? "faint", bp: won ? duelBP : 0) }
        return v
    }
    func duelVersion(_ key: String) throws -> Int { try duelOf(key)?.version ?? -1 }

    /// POST /v2/duel: my live battle as I see it (its due picks made first).
    func duel(_ r: DuelReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            let unix = Int(now.timeIntervalSince1970)
            guard var d = try duelOf(key) else { return try JSONEncoder().encode(DuelReply(duel: nil)) }
            var none = Walk()                                                                      // (no act here: both saves go straight to their rows)
            try tick(&d, actor: nil, walk: &none, now: unix)
            return try JSONEncoder().encode(DuelReply(duel: try view(d.id, for: key, since: r.since ?? 0)))
        }
    }
}
