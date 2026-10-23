import Foundation
// docs/plans/19 §1 (5.1, content51): the personal 전설 원정's acts and what the walk and the radar bring them (Expedition.swift's data).
// In the order of Expeditions.personal, so the server's dice go the same way every time.
// 5.2 (§11, content52): expeditions in steps (ExpStage) — walks on a picture's or a region's courses, pieces, the roamer's meetings, a boss
// once a day with a ball stage after a win, walking with a companion; one finished first (after). One at a time as in 5.1: a stopped one keeps
// everything and gathers nothing; a fight is only the one going on's.

extension EngineRun {
    /// expStart: the one going on (one at a time: plan 19 §6.3, the user 10-16 — the team events aside). Another going on stops where it is
    /// (kept: `on` false, its legend still rolled); one stopped goes on from there; one not begun (or done) begins, its legend rolled now.
    mutating func expStart(_ id: String) -> String? {
        guard Content.v51, let e = Expeditions.of(id) else { return "없는 원정이에요" }
        var x = w.expeditions?[id] ?? ExpProgress()
        guard !x.on else { return "이미 하고 있는\n원정이에요" }
        if let why = expAfter(e) { return why }
        for k in (w.expeditions ?? [:]).keys.sorted() where w.expeditions?[k]?.on == true { w.expeditions?[k]?.on = false }   // stopped, kept
        if x.mon == nil { x = ExpProgress(mon: Expeditions.legend(e.legend, &r), done: x.done) }
        x.on = true
        w.expeditions = (w.expeditions ?? [:]).merging([id: x]) { $1 }
        return nil
    }
    /// The ones to finish first (5.2: 랜드로스 after 토네로스 · 볼트로스, 케르디오 after the three).
    func expAfter(_ e: Expedition) -> String? {
        let left = e.after.filter { (w.expeditions?[$0]?.done ?? 0) == 0 }
        guard !left.isEmpty else { return nil }
        return e.after.count == 3 ? "세 검사를\n먼저 잡아 주세요" : left.count == 1 ? josa(left[0], "을", "를") + "\n먼저 잡아 주세요" : josa(left.joined(separator: "와 "), "을", "를") + "\n먼저 잡아 주세요"
    }
    /// expClaim: its last step done — 지가르데's 50 cells (조립), 케르디오's walk with a sword — its legend into the box (Outcome.mon), the
    /// progress back to the start (done + 1); a kind's first finish: its gift. One begun counts, going on or stopped.
    mutating func expClaim(_ id: String) -> String? {
        guard Content.v51, let e = Expeditions.of(id), var x = w.expeditions?[id], x.mon != nil else { return "하고 있는 원정이\n아니에요" }
        let st = e.steps, k = x.stage ?? 0
        guard k == st.count - 1, [.collect, .companion, .walk].contains(st[k].kind) else { return "받을 수 있는\n원정이 아니에요" }
        if st[k].kind == .collect { guard x.n >= st[k].need else { return "아직 모자라요\n(\(x.n)/\(st[k].need))" } }
        else { guard x.steps >= st[k].need else { return "아직 모자라요\n(\(x.steps.formatted())/\(st[k].need.formatted())걸음)" } }
        expFinish(e, &x, x.mon ?? Expeditions.legend(e.legend, &r))
        return nil
    }
    /// The legend comes (into the box: Outcome.mon) and the expedition is back at its start (done + 1); its first finish gives its gift (특성패치)
    /// and its item (비추는거울), into the bag.
    mutating func expFinish(_ e: Expedition, _ x: inout ExpProgress, _ legend: Mon) {
        var m = legend
        issue(&m, "expedition"); _ = w.keep(m); out.mon = m
        x = ExpProgress(done: x.done + 1)
        let first = x.done == 1, gift = first ? e.gift : nil
        if let g = gift { w.bag.append(g) }
        w.expeditions?[e.id] = x
        events.append(.expeditionDone(id: e.id, dex: m.dex, gift: gift))
        if first, let i = e.item { w.bag.append(i); events.append(.expeditionGift(id: e.id, item: i)) }
    }
    /// The step done: the next one is on (its counts from 0).
    mutating func expNext(_ e: Expedition, _ x: inout ExpProgress) {
        x.stage = (x.stage ?? 0) + 1; x.n = 0; x.steps = 0
        events.append(.expeditionStage(id: e.id, stage: x.stage ?? 0))
    }
    /// n steps walked on this course: the one going on's step — pieces a `stepsPer` (the rest carried; none past `need`), a walk's steps,
    /// a meeting a `stepsPer` (2 banked at most), steps with the companion one of them. A step done moves on (the last waits for expClaim).
    mutating func expSteps(_ n: Int) {
        guard Content.v51, n > 0, w.expeditions != nil else { return }
        for e in Expeditions.personal {
            guard var x = w.expeditions?[e.id], x.on, x.mon != nil else { continue }
            let st = e.steps, k = x.stage ?? 0
            guard st.indices.contains(k) else { continue }
            let s = st[k], last = k == st.count - 1
            switch s.kind {
            case .collect:
                guard s.counts(w.here), x.n < s.need else { continue }
                x.steps += n
                let got = min(s.need - x.n, x.steps / s.stepsPer)
                x.n += got; x.steps = x.n >= s.need ? 0 : x.steps - got * s.stepsPer
                if got > 0 { events.append(.expedition(id: e.id, n: x.n, need: s.need)) }
                if x.n >= s.need, !last { expNext(e, &x) }
            case .walk, .companion:
                guard x.steps < s.need, s.kind == .walk ? s.counts(w.here) : s.with.contains(w.companion.dex) else { continue }
                x.steps = min(s.need, x.steps + n)
                if x.steps >= s.need { if last { events.append(.expeditionStage(id: e.id, stage: st.count)) } else { expNext(e, &x) } }
            case .meet:
                guard s.counts(w.here), (x.meets ?? 0) < Expeditions.meetsMax else { continue }
                x.steps += n
                let got = min(Expeditions.meetsMax - (x.meets ?? 0), x.steps / s.stepsPer)
                if got > 0 { x.meets = (x.meets ?? 0) + got }
                x.steps = (x.meets ?? 0) >= Expeditions.meetsMax ? 0 : x.steps - got * s.stepsPer
                if got > 0 { events.append(.expedition(id: e.id, n: x.meets ?? 0, need: Expeditions.meetsMax)) }
            case .fight: continue
            }
            w.expeditions?[e.id] = x
        }
    }
    /// A radar find on this course: the one going on's pieces, one more at its odds.
    mutating func expRadar() {
        guard Content.v51, w.expeditions != nil else { return }
        for e in Expeditions.personal {
            guard var x = w.expeditions?[e.id], x.on, x.mon != nil, e.steps.indices.contains(x.stage ?? 0) else { continue }
            let s = e.steps[x.stage ?? 0], last = (x.stage ?? 0) == e.steps.count - 1
            guard s.kind == .collect, s.radarOdds > 0, s.counts(w.here), x.n < s.need, Double.random(in: 0..<1, using: &r) < s.radarOdds else { continue }
            x.n += 1; if x.n >= s.need { x.steps = 0 }
            events.append(.expedition(id: e.id, n: x.n, need: s.need))
            if x.n >= s.need, !last { expNext(e, &x) }
            w.expeditions?[e.id] = x
        }
    }

    // MARK: 5.2: the roamer and the boss (plan 19 §11.3)
    /// The roamer going on whose course today this is (the radar's 1/30 there): its id and itself as it is now (HP and status apart).
    func roamerHere() -> (id: String, stage: ExpStage)? {
        guard Content.v52 else { return nil }
        for e in Expeditions.personal {
            guard let x = w.expeditions?[e.id], x.on, x.mon != nil, e.steps.indices.contains(x.stage ?? 0) else { continue }
            let s = e.steps[x.stage ?? 0]
            if s.kind == .meet, Expeditions.roamCourse(e.id, day: w.day, open: { w.unlocked($0) }) == w.course { return (e.id, s) }
        }
        return nil
    }
    /// expFight: the one going on's fight — a meeting with the roamer (one banked), or its boss once a day (1–3 of ours; nil: the tower's three).
    mutating func expFight(_ id: String, _ party: [Int]?) -> String? {
        guard Content.v52, let e = Expeditions.of(id), var x = w.expeditions?[id], x.on, x.mon != nil, e.steps.indices.contains(x.stage ?? 0) else { return "하고 있는 원정이\n아니에요" }
        let s = e.steps[x.stage ?? 0]
        switch s.kind {
        case .meet:
            guard (x.meets ?? 0) > 0 else { return "만남이 없어요\n(\(s.stepsPer.formatted())걸음마다)" }
            x.meets = (x.meets ?? 0) - 1; w.expeditions?[id] = x
            roamFight(id, x, chain: 0)
            return nil
        case .fight:
            guard x.balls == nil else { return "볼을 먼저\n던져 주세요" }
            guard x.fought != w.day else { return "오늘은 이미\n싸웠어요" }
            if let u = party {                                                                       // as the raid's: the player's 1–3, else the tower's three
                guard (1...3).contains(u.count), Set(u).count == u.count else { return "1~3마리를\n골라 주세요" }
                guard u.allSatisfy({ w.ref(uid: $0) != nil }) else { return "그 포켓몬은\n없어요" }
            }
            x.fought = w.day; w.expeditions?[id] = x
            let refs = party.map { $0.compactMap { w.ref(uid: $0) } } ?? w.party(anyLegends: true).map(\.ref)
            p.party = refs.map { w.id($0)! }
            var boss = Mon.wild(e.legend, level: s.level, shiny: x.mon?.shiny, perfect: s.perfect, &r)
            boss.known = boss.withSignature(boss.moves)
            if e.legend == 384 { boss.known = boss.with(620, boss.moves) }                           // 레쿠쟈: 화룡점정 (no Mega: its side's is used)
            var b = Battle(wild: boss, party: refs.compactMap { w.mon($0) }); b.seed = r.next()
            b.theirs += Array(repeating: Fighter(boss), count: max(1, s.bars) - 1)                   // a bar down: it stands up again
            b.raidTier = 3; b.megaUsed = [false, true]; b.expedition = id                             // bars' EXP as a run's; the app's raid screen
            w.see(e.legend)
            out.beats = b.begin(weather: nil, &r); p.battle = b; p.exp = id; out.battle = b
            return nil
        default:
            return "아직 걸음이\n모자라요"
        }
    }
    /// A wild fight with the roamer (a meeting, or the radar's find there): its HP and status as it left them.
    mutating func roamFight(_ id: String, _ x: ExpProgress, chain: Int) {
        guard let m = x.mon else { return }
        let refs = [-1] + w.caught.indices.map { -2 - $0 }
        p.party = refs.map { w.id($0)! }
        var b = Battle(wild: m, party: [w.companion] + w.caught, chain: chain); b.seed = r.next()
        if let hp = x.hp { b.theirs[0].hp = max(1, min(b.theirs[0].maxHP, hp)) }
        b.theirs[0].status = x.status
        b.expedition = id
        w.see(m.dex)
        out.beats = b.begin(weather: w.weather, &r); p.battle = b; p.exp = id; out.battle = b
    }
    /// 배회's ball: 10 % + 60 % of the HP it lost (plan 19 §1.4-1).
    static func roamOdds(_ f: Fighter) -> Double { 0.10 + 0.60 * Double(f.maxHP - f.hp) / Double(max(1, f.maxHP)) }
    /// An expedition fight's end (ended()): the roamer keeps its HP and status (caught: the expedition is done; KO'd: full again next time);
    /// the boss — a win opens the ball stage (레쿠쟈: it comes now), a loss waits for tomorrow.
    mutating func expEnded(_ b: Battle, _ last: Beat, _ end: inout BattleEnd) {
        guard let id = p.exp, let e = Expeditions.of(id), var x = w.expeditions?[id], e.steps.indices.contains(x.stage ?? 0) else { p.exp = nil; return }
        p.exp = nil
        let s = e.steps[x.stage ?? 0]
        if s.kind == .meet {
            let f = b.theirs[0]
            if last == .caught, let m = x.mon { expFinish(e, &x, m); return }
            if f.alive { x.hp = f.hp < f.maxHP ? f.hp : nil; x.status = f.status } else { x.hp = nil; x.status = nil }
        } else if s.kind == .fight {
            end.bars = b.theirs.filter { !$0.alive }.count
            if last == .won {
                if s.balls > 0 { x.balls = s.balls; end.balls = s.balls }
                else if var m = x.mon { m.known = m.with(620, m.moves); expFinish(e, &x, m); return }   // 레쿠쟈 (R2): it comes, knowing 화룡점정
            }
        }
        w.expeditions?[id] = x
    }
    /// expBall: one of the ball stage's (30 %, the raid's for a new species); the last missed: the boss again tomorrow (the legend as it was).
    mutating func expBall(_ id: String) -> String? {
        guard Content.v52, let e = Expeditions.of(id), var x = w.expeditions?[id], x.on, let balls = x.balls, balls > 0, let m = x.mon else { return "던질 볼이 없어요" }
        let caught = Double.random(in: 0..<1, using: &r) < RaidRules.newOdds, shakes = caught ? 3 : Int.random(in: 0...2, using: &r)
        if caught {
            expFinish(e, &x, m)
            out.raidThrow = RaidThrow(caught: true, shakes: 3, balls: balls - 1, mon: out.mon)
            return nil
        }
        x.balls = balls > 1 ? balls - 1 : nil
        w.expeditions?[id] = x
        out.raidThrow = RaidThrow(caught: false, shakes: shakes, balls: balls - 1)
        return nil
    }
}
