import Foundation
// docs/plans/11 §3: what each action does — what Flow.swift and the walker's tick did on the app until 3.0, now in one place for the server
// (and the app's self-test fake). Pure: the dice, the clock and new Pokémon's uids come in; nothing here reads Date() or rolls on its own.

enum Engine {
    static let radarFee = 10, radarWait = 1.5, radarSlack = 3.0          // the find shows after 1.5 s; a pick counts until 1.5 + window + 3 s (the network)
    static func radarWindow(_ chain: Int) -> Double { max(0.8, 2.0 - 0.25 * Double(chain)) }
    static let bpShells: [(name: String, bp: Int)] = [("배틀 골드", 40)]   // the device colours the BP 교환소 sells (Core's shells with a bp)
    static let raidPowerCost = 1000, raidTurns = 6, raidBars = 3        // 12 §4.2: a fight is 1칸 of power, 6 turns at most, 3 of the boss's bars at most

    /// A new trainer's first save (the server makes it): the starter with its issued uid, today, the 1.x one-time jobs marked done.
    static func fresh(now: Date, starter uid: Int) -> Walk {
        var w = Walk(); w.companion.uid = uid; w.lastUID = uid; w.audited = 2; w.ballsRefunded = true
        w.rollover(now); w.dex(); return w
    }

    /// One action: `steps` (already capped) walk first, then the act. A `cannot` leaves the act undone (its steps stay walked).
    static func apply<R: RandomNumberGenerator>(_ act: Act, steps: Int, walk: inout Walk, play: inout Play, rng: inout R, now: Date, ids: inout Issued) -> Outcome {
        var e = EngineRun(w: walk, p: play, r: rng, now: now, ids: ids)
        e.run(act, steps: steps)
        (walk, play, rng, ids) = (e.w, e.p, e.r, e.ids)
        return e.out
    }
}

struct EngineRun<R: RandomNumberGenerator> {
    var w: Walk, p: Play, r: R
    let now: Date
    var ids: Issued
    var out = Outcome()
    let start: Walk                                                       // as it was: levels, the season, unlocks, the dex, what changed
    var startLevels: [Int: Int] = [:]                                     // uid → level before
    var monNews: [Int: [News]] = [:], events: [News] = []                 // evolve / learn by uid; the rest in order
    var evolved: Set<Int> = []                                            // once an act each
    var oldLearn = 0                                                      // walk.learning's pairs before this act (the newer ones get news)

    init(w: Walk, p: Play, r: R, now: Date, ids: Issued) {
        self.w = w; self.p = p; self.r = r; self.now = now; self.ids = ids; start = w
        for m in [w.companion] + w.caught + w.box { if let u = m.uid { startLevels[u] = m.level } }
        oldLearn = (w.learning ?? []).count / 2
    }

    mutating func run(_ act: Act, steps: Int) {
        w.rollover(now)
        if steps > 0 { if p.battle != nil { p.held += steps } else { walkNow(steps) } }   // during a fight they wait for its end (the app's heldSteps)
        let (w0, p0, ids0, mn0, ev0, evd0) = (w, p, ids, monNews, events, evolved)
        if let why = act1(act) {                                         // not now: as if it never came (the steps stay)
            (w, p, ids, monNews, events, evolved) = (w0, p0, ids0, mn0, ev0, evd0)
            out = .no(why)
        }
        finish()
    }

    /// The act itself; a reason when it can't be done.
    mutating func act1(_ act: Act) -> String? {
        if p.battle != nil { switch act { case .battle, .steps: break; default: return "배틀 중이에요" } }
        let keepsChain: Bool = { switch act { case .steps, .radar, .radarPick, .mon(.learn): true; default: act.social } }()
        let keepsRadar: Bool = { switch act { case .steps, .radarPick: true; default: act.social } }()
        if !keepsChain { p.chain = nil }                                  // a held chain lets only these through (the server's acts with others don't touch play)
        if p.radar != nil, !keepsRadar { p.radar = nil; p.chain = nil }   // the radar shown: anything else gives it up
        switch act {
        case .steps: return nil
        case .radar: return radar()
        case .radarPick(let bush): return pick(bush)
        case .battle(let c): return battle(c)
        case .tower: return tower()
        case .towerPick(let slot, let uid):
            guard let ref = w.ref(uid: uid), (0..<3).contains(slot) else { return "고를 수 없어요" }
            w.towerSet(slot, ref); return nil
        case .towerReset: w.towerPick = nil; return nil
        case .buy(let bp, let item, let legend, let shell, let qty): return buy(bp, item, legend, shell, qty)
        case .use(let item, let stat): return use(item, stat)
        case .sellAll:
            var sum = 0
            for i in w.inventory { if case .sell = ItemKind.of(i) { sum += w.sell(i) } }
            guard sum > 0 else { return "팔 도구가 없어요" }
            out.watts = sum; return nil
        case .mon(let op): return mon(op)
        case .course(let i):
            guard courses.indices.contains(i), w.unlocked(i), i != w.course else { return "갈 수 없는 코스예요" }
            w.setCourse(i, &r); return nil
        case .greet, .tradeOffer, .tradeAccept, .tradeDecline, .tradeCancel, .raidBall, .friendRequest, .friendAccept, .friendDecline, .friendRemove,
             .marketList, .marketUnlist, .marketBid, .marketWithdraw, .marketAccept: return nil   // the server's: other trainers' saves, the inbox, the raid, friends, the board
        case .raid: return raid()
        }
    }

    // MARK: steps and what they bring (the walker's tick)
    /// n steps walked: W, EXP, the egg, levels; then the weather, the season, the companion's find, a hatch, evolutions and moves.
    mutating func walkNow(_ n: Int) {
        guard n > 0 else { return }
        let season = w.season
        _ = w.walk(n, at: now)
        if w.weatherDue, w.rollWeather(&r) { events.append(.weather(to: w.weather ?? .sunny)) }
        if w.season != season { events.append(.season(to: w.season.rawValue)) }
        if w.eventDue {
            switch w.petEvent(&r) {
            case .item(let i)?: events.append(.find(item: i))
            case .egg(let d)?: events.append(.egg(dex: d, left: w.egg?.left ?? 0))
            case nil: break
            }
        }
        if w.hatchDue, var m = w.eggMon(&r) { issue(&m, "egg"); w.hatched(m); events.append(.hatch(mon: m)) }
        growth()
    }
    /// Evolutions (docs/plans/11 §3.1): the companion's when its level went up in this act; the walker's three whenever it fits now (a night
    /// one at night, a place one on its course). Then the moves that came: into a free slot at once, else waiting in walk.learning.
    mutating func growth() {
        if let u = w.companion.uid, w.companion.level > (startLevels[u] ?? w.companion.level), let e = w.levelEvolution(now) { evolve(-1, e) }
        for i in w.caught.indices { if let e = w.levelEvolution(now, ref: -2 - i) { evolve(-2 - i, e) } }
        w.evolving = nil                                                  // (the app's queue: the news drives the shows now)
        learnQueue()
    }
    mutating func evolve(_ ref: Int, _ e: Evo) {
        guard let m = w.mon(ref), let u = m.uid ?? w.id(ref), !evolved.contains(u) else { return }
        evolved.insert(u)
        w.evolve(e, ref: ref, shed: false)
        var shed: Mon? = nil
        if e.to == 291, let now = w.mon(ref) { var s = Walk.shedinja(from: now, &r); issue(&s, "shedinja"); _ = w.keep(s); shed = s }   // 토중몬 → 아이스크 leaves a 껍질몬
        monNews[u, default: []].append(.evolve(uid: u, from: m.dex, to: e.to, shed: shed))
    }
    /// walk.learning, in order (Walk.settleLearning); news for the ones that came in this act.
    mutating func learnQueue() {
        for (u, n) in w.settleLearning(announceFrom: oldLearn) { monNews[u, default: []].append(n) }
        oldLearn = (w.learning ?? []).count / 2
    }
    mutating func issue(_ m: inout Mon, _ kind: String) { m.uid = ids.next; ids.next += 1; ids.made.append((m, kind)) }

    // MARK: the radar
    mutating func radar() -> String? {
        let chain: Int
        if let c = p.chain { chain = c } else { guard w.spend(Engine.radarFee) else { return "W가 부족하다\n(10W 필요)" }; chain = 0 }
        p.chain = nil                                                     // used: a miss ends it, a catch or a KO may hold it again
        let (m0, legend) = w.radarMon(&r, chain: chain)
        var m = m0; issue(&m, legend ? "legend" : "radar")
        let bush = Int.random(in: 0..<4, using: &r), win = Engine.radarWindow(chain)
        p.radar = Play.Radar(bush: bush, window: win, chain: chain, at: now.timeIntervalSinceReferenceDate, mon: m)
        out.radar = RadarShown(bush: bush, window: win, chain: chain)
        return nil
    }
    mutating func pick(_ bush: Int) -> String? {
        guard let rd = p.radar else { return "레이더가 없어요" }
        p.radar = nil
        let t = now.timeIntervalSinceReferenceDate - rd.at
        guard bush == rd.bush, t <= Engine.radarWait + rd.window + Engine.radarSlack else { out.missed = true; p.chain = nil; return nil }
        let refs = [-1] + w.caught.indices.map { -2 - $0 }
        p.party = refs.map { w.id($0)! }                                  // the companion, then the walker's: they can switch in
        var b = Battle(wild: rd.mon, party: [w.companion] + w.caught, chain: rd.chain); b.seed = r.next()
        w.see(rd.mon.dex)
        out.beats = b.begin(weather: w.weather, &r); p.battle = b; out.battle = b
        return nil
    }

    // MARK: fights (what Flow's battle screens and after() did)
    mutating func battle(_ c: BattleCmd) -> String? {
        guard var b = p.battle else { return "배틀 중이 아니에요" }
        let x = b.mine[b.me], locked = josa(b.nm(.me), "은", "는") + "\n기술을 쓰는 중이다!"
        var beats: [Beat]
        switch c {
        case .fight(let slot):
            if let id = b.forced ?? (b.usable(.me).isEmpty ? 165 : nil) { beats = b.turn(.fight(id), &r) }   // nothing it may pick: 발버둥
            else {
                guard x.moves.indices.contains(slot) else { return "그 기술은 없어요" }
                let id = x.moves[slot]
                if x.pp[slot] == 0 { return "기술의 남은\nPP가 없다!" }
                if x.disable > 0, x.disabledMove == id { return "사용할 수 없게\n되어 있다!" }
                if x.taunt > 0, moveTable[id]?.isStatus == true { return "도발당해서\n쓸 수 없다!" }
                if x.torment, id == x.lastMove { return "트집 때문에 같은\n기술은 못 쓴다!" }
                beats = b.turn(.fight(id), &r)
            }
        case .ball:
            guard b.trainer == nil else { return "트레이너의 포켓몬은\n잡을 수 없다" }
            guard p.raid == nil else { return "레이드 보스는\n볼로 잡을 수 없다" }
            if b.locked { return locked }
            let roll = Walk.rollBall(chain: b.chain, &r); out.ball = roll.name   // free: which ball it turns out to be is luck (and the chain)
            beats = b.turn(.capture, &r, ball: roll.boost)
        case .item(let name):
            if b.locked { return locked }
            let u: ItemUse? = switch ItemKind.of(name) { case .heal(let n): .heal(n); case .battle(let u): u; default: nil }
            guard let u, b.usable(u), w.take(name) else { return "지금 쓸 수 있는\n도구가 아니다" }
            beats = [.note(.me, text: josa(name, "을", "를") + " 사용했다!")] + b.turn(.item(u), &r)
        case .swap(let i), .replace(let i):
            guard b.mine.indices.contains(i) else { return "교체할 수 없어요" }
            if !b.mine[i].alive { return "기절해서\n싸울 수 없다" }
            if i == b.me { return "이미 싸우고 있다" }
            if b.mustReplace { beats = b.replace(i) }
            else {
                if b.locked { return locked }
                if let why = b.switchBlock { return why }
                beats = b.turn(.swap(i), &r)
            }
        case .run:
            guard b.trainer == nil else { return "트레이너와의 승부에서\n도망칠 수 없다" }
            if b.locked { return locked }
            beats = b.turn(.run, &r)
        case .forfeit:
            guard b.trainer != nil else { return "기권할 수 없어요" }
            let s = w.towerStreak ?? 0; w.towerEnd(); p.tower = false; p.battle = nil; p.party = nil
            out.end = BattleEnd(result: "forfeit", streak: s)
            let h = p.held; p.held = 0; walkNow(h)                          // the fight's held steps
            return nil
        }
        if p.raid != nil, !(beats.last?.ends ?? false), b.turnNo >= Engine.raidTurns {          // a raid fight's 6 turns are up
            beats += [.note(.it, text: josa(monNames[b.wild.dex], "의", "의") + " 기세에 밀려났다!"), .fled]; b.over = true
        }
        if let last = beats.last, last.ends { beats += ended(&b, last) }
        out.battle = b; out.beats = beats
        if out.end == nil { p.battle = b }
        return nil
    }
    /// A fight's last beat (Flow's after()): a revive goes on with it (more beats, no end); else EXP back, held steps, the catch, the chain, the tower.
    mutating func ended(_ b: inout Battle, _ last: Beat) -> [Beat] {
        if last == .lost, let rv = w.useRevive() {                                                  // a revive in the bag: back up, the fight goes on
            let hp = max(1, b.mine[b.me].maxHP * rv.pct / 100)
            b.mine[b.me].clearVolatile(); b.mine[b.me].status = nil; b.mine[b.me].down = false; b.over = false
            let beat = Beat.heal(.me, amount: hp, text: josa(rv.item, "으로", "로") + " 되살아났다!")
            b.apply(beat)
            var bs = [beat]
            if let n = b.foeNext { b.foeNext = nil; b.out = []; b.switchIn(.it, n); bs += b.out }   // a trainer's one KO'd that same turn: its next comes out now
            return bs
        }
        let result = switch last { case .caught: "caught"; case .won: "won"; case .lost: "lost"; case .fled: "fled"; default: "ran" }
        p.battle = nil
        var end = BattleEnd(result: result)
        if p.raid != nil {                                                                          // 12 §4.2: the damage (the server counts it), a BP a bar, EXP as a wild fight's
            let bars = b.theirs.filter { !$0.alive }.count
            end.dealt = b.theirs.reduce(0) { $0 + ($1.maxHP - $1.hp) }; end.bp = bars
            w.writeBack(p.party ?? [], b.mine.map(\.mon)); p.party = nil; p.raid = nil
            let h = p.held; p.held = 0; walkNow(h)
            if bars > 0 { w.bp = (w.bp ?? 0) + bars }
            growth(); out.end = end
            return []
        }
        if b.trainer == nil {
            w.writeBack(p.party ?? [], b.mine.map(\.mon)); p.party = nil                         // EXP, EVs, levels (moves queued)
            let h = p.held; p.held = 0; walkNow(h)
            if last == .caught { _ = w.keep(b.wild) }
            if last == .caught || last == .won, Walk.chainContinues(b.chain, &r) {
                let n = b.chain + 1, item = w.chainReward(n)
                events.append(.chain(n: n, bonus: 2 * n, reward: item)); p.chain = n; end.chain = n
            } else { p.chain = nil; end.chain = 0 }
        } else {                                                                                    // the tower: Lv.50 copies, no EXP to write back
            let h = p.held; p.held = 0; walkNow(h)
            if last == .won { end.bp = w.towerWin(); end.streak = w.towerStreak }
            else { end.streak = w.towerStreak ?? 0; w.towerEnd(); p.tower = false }
            p.party = nil
        }
        growth()
        out.end = end
        return []
    }
    /// 12 §4.2: this week's boss (the server's), 1칸 of power; our party (the tower's three) at its own levels, against 3 of its bars.
    mutating func raid() -> String? {
        guard let rb = p.raidBoss else { return "이번 주 레이드가\n없어요" }
        guard rb.left > 0 else { return "이번 주 보스는\n이미 쓰러졌어요" }
        guard (w.raidPower ?? 0) >= Engine.raidPowerCost else { return "파워가 부족하다\n(1,000걸음마다 1칸)" }
        w.raidPower = (w.raidPower ?? 0) - Engine.raidPowerCost
        let refs = w.party().map(\.ref)
        p.party = refs.map { w.id($0)! }                                                            // uids first: the fighters carry them, EXP goes back by them
        var b = Battle(wild: rb.boss, party: refs.compactMap { w.mon($0) }); b.seed = r.next()
        b.theirs += Array(repeating: Fighter(rb.boss), count: Engine.raidBars - 1)                  // a bar down: it stands up again
        w.see(rb.boss.dex)
        out.beats = b.begin(weather: nil, &r); p.battle = b; p.raid = rb.week; out.battle = b
        return nil
    }
    mutating func tower() -> String? {
        if !p.tower { guard w.spend(Walk.towerFee) else { return "W가 부족하다\n(\(Walk.towerFee)W 필요)" }; w.towerStreak = 0; p.tower = true }
        p.party = w.party().map { w.id($0.ref)! }                                                   // uids first, so the fighters carry them
        let ours = w.party().map { x -> Mon in var m = x.mon; if m.known == nil { m.known = m.moves }; m.level = Walk.towerLevel; return m }   // all as Lv.50 copies
        let f = w.towerFoes(&r)
        var b = Battle(party: ours, trainer: f.trainer, foes: f.foes); b.seed = r.next()
        b.aiRandom = Walk.towerAIRandom[Walk.towerTier(w.towerStreak ?? 0)]
        out.beats = b.begin(weather: nil, &r); p.battle = b; out.battle = b
        return nil
    }

    // MARK: the shops, the bag, the Pokémon
    mutating func buy(_ bp: Bool, _ item: String?, _ legend: Int?, _ shell: String?, _ qty: Int) -> String? {
        let ware = w.wares(bp: bp, shells: Engine.bpShells).first { x in
            switch x.kind { case .item(let i): i == item && legend == nil && shell == nil; case .legend(let k): k == legend; case .shell(let s): s == shell }
        }
        guard let ware else { return "팔지 않는 물건이에요" }
        guard qty >= 1, w.canBuy(ware, bp: bp) >= qty else { return ware.once && w.owned(ware) > 0 ? "이미 가지고 있다" : bp ? "BP가 부족하다" : "W가 부족하다" }
        if case .legend(let k) = ware.kind {                                                        // the legend: issued here (3 sure 31s, 이로치 1/64)
            guard w.payLegend(k) else { return bp ? "BP가 부족하다" : "W가 부족하다" }
            var m = Walk.legendMon(k, &r); issue(&m, "shop"); _ = w.keep(m); out.mon = m
            return nil
        }
        return w.purchase(ware, qty, bp: bp) == nil ? (bp ? "BP가 부족하다" : "W가 부족하다") : nil
    }
    mutating func use(_ item: String, _ stat: Int?) -> String? {
        guard w.count(item) > 0 else { return "가지고 있지 않아요" }
        switch ItemKind.of(item) {
        case .candy: guard w.feedCandy() else { return "이미 Lv.100이다" }
        case .vitamin: guard w.feedVitamin(item) != nil else { return "먹어도 효과가\n없을 것 같다" }
        case .evReset: guard w.resetEVs() else { return "노력치가 이미\n0이다" }
        case .berry: guard w.feedBerry(item) else { return "먹을 수 없어요" }
        case .sell: out.watts = w.sell(item)
        case .evolution:
            guard let e = w.stoneEvolutions(now).first(where: { $0.item == item }) else { return "지금은\n쓸 수 없다" }
            evolve(-1, e)
        case .bottleCap(let gold):
            guard gold || stat.map({ (0..<6).contains($0) }) == true, w.hyperTrain(gold ? nil : stat) else { return "특훈할 수 없다" }
        default: return "여기서는\n쓸 수 없다"
        }
        growth()
        return nil
    }
    mutating func mon(_ op: MonOp) -> String? {
        switch op {
        case .pair(let u):
            guard let ref = w.ref(uid: u), ref != -1 else { return "함께 걸을 수 없어요" }
            if ref <= -2 { w.pair(-2 - ref, onWalker: true) } else { w.pair(ref) }
        case .store(let u):
            guard let ref = w.ref(uid: u), ref <= -2 else { return "상자로 보낼 수 없어요" }
            w.store(-2 - ref)
        case .fetch(let u):
            guard let ref = w.ref(uid: u), ref >= 0, w.caught.count < 3 else { return "워커가 꽉 찼어요" }
            w.fetch(ref)
        case .release(let u):
            guard let ref = w.ref(uid: u), ref >= 0 else { return "놓아줄 수 없어요" }
            out.watts = w.release(ref)
        case .releaseDupes(let dex):
            let x = w.releaseDuplicates(of: dex)
            guard x.count > 0 else { return "놓아줄 포켓몬이\n없어요" }
            out.watts = x.watts
        case .move(let u, let slot, let mv):
            guard let ref = w.ref(uid: u), var m = w.mon(ref), m.relearnable.contains(mv), (0..<min(4, m.moves.count + 1)).contains(slot) else { return "배울 수 없는 기술이에요" }
            m.setMove(mv, at: slot); w.setMon(ref, m)
        case .learn(let slot):
            guard let (ref, mv) = w.nextToLearn(), var m = w.mon(ref) else { return "배울 기술이 없어요" }
            if let s = slot { guard m.moves.indices.contains(s) else { return "그 칸은 없어요" }; var ms = m.moves; ms[s] = mv; m.known = ms; w.setMon(ref, m) }
            w.learned(); oldLearn = max(0, oldLearn - 1)
            learnQueue()
        case .trade:
            guard let e = w.tradeEvolution(now) else { return "통신 진화할 수\n없어요" }
            evolve(-1, e); learnQueue()
        }
        return nil
    }

    // MARK: the news, in home's order
    mutating func finish() {
        for i in courses.indices where !start.unlocked(i) && w.unlocked(i) { events.append(.unlock(course: i)) }
        if (w.owned ?? []).count > (start.owned ?? []).count { events.append(.dex(count: (w.owned ?? []).count)) }
        var order: [Int] = []
        for m in [w.companion] + w.caught + w.box { if let u = m.uid, !order.contains(u) { order.append(u) } }
        for u in monNews.keys.sorted() where !order.contains(u) { order.append(u) }
        var news: [News] = []
        for u in order {
            if let r = w.ref(uid: u), let m = w.mon(r), let was = startLevels[u], m.level > was { news.append(.level(uid: u, level: m.level)) }
            news += monNews[u] ?? []
        }
        out.news = news + events
        out.changed = w != start
    }
}

extension Walk {
    /// walk.learning, in order: gone ones and known moves dropped, a free slot learns it now, a full one waits. News (by uid) for those learned,
    /// and for the waiting ones from pair `announceFrom` on (the ones that came since: the older ones were announced when they came).
    mutating func settleLearning(announceFrom old: Int) -> [(uid: Int, news: News)] {
        let q = learning ?? []
        var keep: [Int] = [], out: [(Int, News)] = [], k = 0
        while k + 1 < q.count {
            let (u, mv) = (q[k], q[k + 1]), new = k / 2 >= old; k += 2
            guard let r = ref(uid: u), var m = mon(r), !m.moves.contains(mv) else { continue }
            if m.moves.count < 4 { m.known = m.moves + [mv]; setMon(r, m); out.append((u, .learn(uid: u, move: mv, learned: true))) }
            else { keep += [u, mv]; if new { out.append((u, .learn(uid: u, move: mv, learned: false))) } }
        }
        learning = keep.isEmpty ? nil : keep
        return out
    }
    /// What a Pokémon traded becomes at its new trainer (12 §3.2): its species' trade evolution, if it needs no item or the giver's bag has it.
    static func tradeEvolution(of m: Mon, giverBag: [String]) -> Evo? {
        evolutions.first { $0.from == m.dex && $0.way == .trade && ($0.item.map { giverBag.contains($0) } ?? true) }
    }
}

extension Act {
    /// The server's own acts with other trainers (friends, 인사, trades, the board, the raid's ball): they leave play alone (a chain holds, a radar stays).
    var social: Bool {
        switch self {
        case .greet, .tradeOffer, .tradeAccept, .tradeDecline, .tradeCancel, .raidBall, .friendRequest, .friendAccept, .friendDecline, .friendRemove,
             .marketList, .marketUnlist, .marketBid, .marketWithdraw, .marketAccept: true
        default: false
        }
    }
}
