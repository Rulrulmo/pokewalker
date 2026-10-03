import Foundation
import Testing
@testable import PokeCore

// docs/plans/11: the shared engine (Game/Model/Engine*.swift), action by action, with fixed dice.

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// One trainer's server side in miniature: the save, play, the dice, the uid counter.
private struct Desk {
    var w: Walk, p = Play(), r = Seeded(s: 42), ids = Issued(next: firstUID + 1), clock = 0.0
    init(_ w: Walk = Engine.fresh(now: t0, starter: firstUID)) { self.w = w }
    var now: Date { t0.addingTimeInterval(clock) }
    @discardableResult mutating func act(_ a: Act, steps: Int = 0, after s: Double = 1) -> Outcome {
        clock += s
        return Engine.apply(a, steps: steps, walk: &w, play: &p, rng: &r, now: now, ids: &ids)
    }
    /// Plays the fight on to its end: balls at a wild one, the first move at a trainer's, a replacement when one is due.
    mutating func fightOut(ball: Bool) -> Outcome? {
        for _ in 0..<300 {
            guard let b = p.battle else { return nil }
            let cmd: BattleCmd = b.mustReplace ? .replace(b.mine.indices.first { b.mine[$0].alive && $0 != b.me } ?? 0) : ball ? .ball : .fight(slot: 0)
            let o = act(.battle(cmd), after: 3)
            if o.end != nil { return o }
            if o.cannot != nil, case .fight = cmd { _ = act(.battle(.fight(slot: 1)), after: 3) }
        }
        return nil
    }
}

@Test func engineFreshAndSteps() {
    var d = Desk()
    #expect(d.w.companion.uid == firstUID && d.w.lastUID == firstUID && d.w.audited == 2 && !d.w.day.isEmpty)
    let o = d.act(.steps, steps: 400)
    #expect(o.changed && o.cannot == nil)
    #expect(d.w.total == 400 && d.w.watts == 20 && d.w.earned == 20)
    #expect(d.act(.steps).changed == false)                                                 // nothing walked, nothing new
}

@Test func engineRadarFeeAndMisses() {
    var d = Desk()
    let poor = d.act(.radar)
    #expect(poor.cannot == "W가 부족하다\n(10W 필요)" && d.p.radar == nil && d.ids.made.isEmpty)
    d.act(.steps, steps: 1000)                                                              // 50 W
    let w = d.w.watts, shown = d.act(.radar)
    #expect(shown.cannot == nil && d.w.watts == w - 10 && shown.radar != nil && d.p.radar != nil)
    #expect(d.ids.made.count == 1 && d.ids.made[0].mon.uid == firstUID + 1)
    let wrong = (shown.radar!.bush + 1) % 4
    #expect(d.act(.radarPick(bush: wrong)).missed == true && d.p.radar == nil && d.p.battle == nil)
    let again = d.act(.radar)
    #expect(d.act(.radarPick(bush: again.radar!.bush), after: 1.5 + again.radar!.window + 3.5).missed == true)   // too late
    d.act(.radar)
    #expect(d.act(.radarPick(bush: -1)).missed == true)                                     // given up
    #expect(d.act(.radarPick(bush: 0)).cannot == "레이더가 없어요")
}

@Test func engineWildFightCatchAndChain() {
    var d = Desk(); d.act(.steps, steps: 4000)
    var caught = 0, chains = 0
    for _ in 0..<12 {
        guard let shown = d.act(.radar).radar else { break }
        let start = d.act(.radarPick(bush: shown.bush), after: 2)
        #expect(start.battle != nil && start.beats?.isEmpty == false && d.p.party?.first == firstUID)
        let seen = d.w.seen ?? []
        #expect(seen.contains(start.battle!.wild.dex))
        d.act(.steps, steps: 50)                                                            // mid-fight: held, not walked
        #expect(d.p.held == 50)
        let total = d.w.total
        guard let end = d.fightOut(ball: true)?.end else { Issue.record("no end"); return }
        #expect(d.p.battle == nil && d.p.held == 0 && d.w.total == total + 50)
        if end.result == "caught" { caught += 1; #expect(d.w.box.contains { $0.uid == start.battle!.wild.uid }) }
        if let n = end.chain, n > 0 {
            chains += 1
            #expect(d.p.chain == n)
            let w = d.w.watts; #expect(d.act(.radar).cannot == nil && d.w.watts == w)            // a held chain's next bush is free
            d.act(.radarPick(bush: -1))
        }
    }
    #expect(caught > 0)
    print("engine: \(caught) caught, \(chains) chains")
}

@Test func engineHeldChainEndsOnOtherActs() {
    var d = Desk(); d.p.chain = 3
    d.act(.steps, steps: 10); #expect(d.p.chain == 3)
    d.act(.mon(.learn(slot: nil))); #expect(d.p.chain == 3)                                 // (nothing to learn: a cannot, the chain stays)
    d.act(.course(0)); #expect(d.p.chain == 3)                                              // a cannot (the course it's on): as if it never came
    d.act(.towerReset); #expect(d.p.chain == nil)                                           // anything else that happens: over
}

@Test func engineCannotLeavesTheActUndone() {
    var d = Desk(); d.act(.steps, steps: 100)
    let w = d.w
    let o = d.act(.buy(bp: false, item: "회복약", legend: nil, shell: nil, qty: 1), steps: 20)
    #expect(o.cannot == "W가 부족하다" && d.w.total == w.total + 20 && d.w.bag == w.bag)     // its steps walked, nothing bought
    #expect(d.act(.buy(bp: false, item: "칠색조", legend: nil, shell: nil, qty: 1)).cannot == "팔지 않는 물건이에요")
    #expect(d.act(.battle(.ball)).cannot == "배틀 중이 아니에요")
    #expect(d.act(.use(item: "이상한사탕", stat: nil)).cannot == "가지고 있지 않아요")
}

@Test func engineShopsAndBag() {
    var d = Desk(); d.w.watts = 9999; d.w.bp = 400
    #expect(d.act(.buy(bp: false, item: "상처약", legend: nil, shell: nil, qty: 3)).cannot == nil)
    #expect(d.w.watts == 9999 - 60 && d.w.count("상처약") == 3)
    #expect(d.act(.buy(bp: true, item: "이상한사탕", legend: nil, shell: nil, qty: 2)).cannot == nil && d.w.bp == 384)
    let legend = d.act(.buy(bp: true, item: nil, legend: 1, shell: nil, qty: 1))            // 뮤츠, 300 BP: issued
    #expect(legend.mon?.dex == 150 && legend.mon?.perfectIVs ?? 0 >= 3 && d.w.bp == 84 && d.ids.made.last?.kind == "shop")
    #expect(d.w.box.contains { $0.uid == legend.mon?.uid })
    #expect(d.act(.buy(bp: true, item: nil, legend: nil, shell: "배틀 골드", qty: 1)).cannot == nil && d.w.bought?.contains("배틀 골드") == true)
    #expect(d.act(.buy(bp: true, item: nil, legend: nil, shell: "배틀 골드", qty: 1)).cannot == "이미 가지고 있다")
    let lv = d.w.companion.level
    let candy = d.act(.use(item: "이상한사탕", stat: nil))
    #expect(candy.cannot == nil && d.w.companion.level == lv + 1 && candy.news.first == .level(uid: firstUID, level: lv + 1))
    d.w.bag += ["금구슬", "금구슬"]
    #expect(d.act(.sellAll).watts == 200)
}

@Test func engineEvolutionAndMovesInHomeOrder() {
    var c = Mon(dex: 4, level: 15, female: false); c.uid = firstUID; c.known = [10, 45, 52, 108]   // 파이리, four moves known
    var w = Engine.fresh(now: t0, starter: firstUID); w.companion = c; w.bag = ["이상한사탕"]
    var d = Desk(w)
    let o = d.act(.use(item: "이상한사탕", stat: nil))                                       // Lv.16: 리자드
    #expect(d.w.companion.dex == 5)
    guard case .level(firstUID, 16)? = o.news.first, case .evolve(firstUID, 4, 5, nil)? = o.news.dropFirst().first else { Issue.record("\(o.news)"); return }
    let waiting = o.news.compactMap { n -> Int? in if case .learn(_, let m, false) = n { return m }; return nil }
    if let mv = waiting.first {                                                             // a move it can't fit: forget one, or not
        #expect(d.w.learning?.prefix(2) == [firstUID, mv])
        let k = d.act(.mon(.learn(slot: 0)))
        #expect(k.cannot == nil && d.w.companion.moves[0] == mv)
    }
}

@Test func engineWalkerEvolvesWhenItFits() {
    var m = Mon(dex: 133, level: 30, female: false); m.uid = firstUID + 9                   // 이브이 on the walker, past nothing: no level evolution
    var g = Mon(dex: 74, level: 25, female: false); g.uid = firstUID + 10                   // 꼬마돌 Lv.25: 데구리 (level 25)
    var w = Engine.fresh(now: t0, starter: firstUID); w.caught = [m, g]
    var d = Desk(w)
    let o = d.act(.steps, steps: 2)
    #expect(d.w.caught[1].dex == 75 && d.w.caught[0].dex == 133)
    #expect(o.news.contains { if case .evolve(firstUID + 10, 74, 75, _) = $0 { return true }; return false })
}

@Test func engineMonOps() {
    var a = Mon(dex: 16, level: 10, female: false); a.uid = firstUID + 1
    var b = Mon(dex: 19, level: 12, female: false); b.uid = firstUID + 2
    var w = Engine.fresh(now: t0, starter: firstUID); w.box = [a, b]
    var d = Desk(w)
    #expect(d.act(.mon(.fetch(uid: firstUID + 1))).cannot == nil && d.w.caught.map(\.uid) == [firstUID + 1])
    #expect(d.act(.mon(.store(uid: firstUID + 1))).cannot == nil && d.w.caught.isEmpty)
    #expect(d.act(.mon(.pair(uid: firstUID + 2))).cannot == nil && d.w.companion.uid == firstUID + 2 && d.w.box.last?.uid == firstUID)
    #expect(d.act(.mon(.pair(uid: firstUID + 2))).cannot == "함께 걸을 수 없어요")
    let w0 = d.w.watts
    #expect(d.act(.mon(.release(uid: firstUID + 1))).watts == 5 && d.w.watts == w0 + 5 && d.w.ref(uid: firstUID + 1) == nil)
    #expect(d.act(.mon(.release(uid: firstUID + 2))).cannot == "놓아줄 수 없어요")         // the companion
    #expect(d.act(.course(courses.count - 1)).cannot == "갈 수 없는 코스예요")                // locked
}

@Test func engineTowerRun() {
    var d = Desk(); d.w.watts = 49
    #expect(d.act(.tower).cannot == "W가 부족하다\n(50W 필요)")
    d.w.watts = 500
    let t = d.act(.tower)
    #expect(t.cannot == nil && t.battle?.trainer != nil && d.w.watts == 450 && d.p.tower)
    #expect(d.act(.mon(.store(uid: firstUID))).cannot == "배틀 중이에요")
    #expect(d.act(.battle(.run)).cannot == "트레이너와의 승부에서\n도망칠 수 없다")
    let f = d.act(.battle(.forfeit))
    #expect(f.end?.result == "forfeit" && d.p.battle == nil && !d.p.tower && d.w.towerStreak == 0)
    d.act(.tower); let end = d.fightOut(ball: false)?.end
    #expect(end != nil && (end?.result == "won" ? d.p.tower && d.w.bp == end?.bp : !d.p.tower))
}

@Test func engineWireRoundTrip() throws {
    var d = Desk(); d.act(.steps, steps: 3000)
    let shown = d.act(.radar), start = d.act(.radarPick(bush: shown.radar!.bush))
    let req = ActReq(id: "민수", session: "s", seq: 3, steps: 12, act: .battle(.fight(slot: 2)))
    #expect(try JSONDecoder().decode(ActReq.self, from: JSONEncoder().encode(req)) == req)
    let reply = ActReply(rev: 4, walk: d.w, taken: 12, out: start)
    let back = try JSONDecoder().decode(ActReply.self, from: JSONEncoder().encode(reply))
    #expect(back.walk == d.w && back.out == start && back.rev == 4)
    for a: Act in [.steps, .radar, .radarPick(bush: -1), .tower, .towerPick(slot: 1, uid: 9), .towerReset, .buy(bp: true, item: nil, legend: 1, shell: nil, qty: 1),
                   .use(item: "은색병뚜껑", stat: 2), .sellAll, .mon(.learn(slot: nil)), .mon(.move(uid: 1, slot: 0, move: 33)), .course(3), .battle(.forfeit)] {
        #expect(try JSONDecoder().decode(Act.self, from: JSONEncoder().encode(a)) == a)
    }
    print("wire: " + String(decoding: try JSONEncoder().encode(ActReq(id: "민수", session: "s", seq: 1, steps: 5, act: .buy(bp: false, item: "상처약", legend: nil, shell: nil, qty: 2))), as: UTF8.self))
}
