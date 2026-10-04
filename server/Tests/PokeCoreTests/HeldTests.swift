import Foundation
import Testing
@testable import PokeCore

// docs/plans/13 ⑤ (3.7): held items — giving and taking, what they do in a fight, what's left after it, and the shops.

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func mon(_ dex: Int, _ level: Int, item: String? = nil, moves: [Int]? = nil) -> Mon {
    var m = Mon(dex: dex, level: level, female: false); m.item = item; m.known = moves; m.nature = 0; m.ivs = Array(repeating: 31, count: 6); return m
}
/// One of ours (first) against a wild one; dice fixed.
private func fight(_ a: Mon, _ b: Mon, seed: UInt64 = 7) -> Battle { var x = Battle(wild: b, party: [a]); x.seed = seed; return x }
private func said(_ b: Battle, _ s: String) -> Bool {
    b.out.contains { switch $0 { case .note(_, let t), .status(_, _, let t), .heal(_, _, let t), .hurt(_, _, let t): t.contains(s); default: false } }
}

@Test func holdAndTakeBack() {
    var w = Engine.fresh(now: t0, starter: firstUID); w.bag = ["구애머리띠", "먹다남은음식", "상처약"]
    let a = w.hold("구애머리띠", -1); #expect(a && w.companion.item == "구애머리띠" && w.count("구애머리띠") == 0)
    let b = w.hold("먹다남은음식", -1); #expect(b && w.companion.item == "먹다남은음식" && w.count("구애머리띠") == 1)   // what it held: back in the bag
    let c = w.hold("먹다남은음식", -1), d = w.hold("상처약", -1); #expect(!c && !d)                    // not again; not a held item
    let e = w.hold(nil, -1); #expect(e && w.companion.item == nil && w.count("먹다남은음식") == 1)
    let f = w.hold(nil, -1); #expect(!f)
    var boxed = mon(16, 10, item: "기합의띠"); boxed.uid = firstUID + 5; w.box = [boxed]
    _ = w.release(0)
    #expect(w.count("기합의띠") == 1)                                                                    // let go: its item stays with us
    #expect(ItemKind.of("구애머리띠") == .held("구애머리띠") && ItemKind.of("자뭉열매") == .heal(30) && ItemKind.of("왕의징표석") == .evolution)
    #expect(Held.holdable("자뭉열매") && Held.holdable("왕의징표석") && !Held.holdable("상처약") && !Held.holdable("불꽃의돌"))
}

@Test func holdAct() {
    var w = Engine.fresh(now: t0, starter: firstUID); w.bag = ["생명의구슬"]
    var p = Play(), r = Seeded(s: 1), ids = Issued(next: firstUID + 1)
    let o = Engine.apply(.mon(op: .hold(uid: firstUID, item: "생명의구슬")), steps: 0, walk: &w, play: &p, rng: &r, now: t0, ids: &ids)
    #expect(o.cannot == nil && o.changed && w.companion.item == "생명의구슬")
    #expect(Engine.apply(.mon(op: .hold(uid: firstUID, item: "생명의구슬")), steps: 0, walk: &w, play: &p, rng: &r, now: t0, ids: &ids).cannot != nil)
    #expect(Engine.apply(.mon(op: .hold(uid: firstUID, item: "상처약")), steps: 0, walk: &w, play: &p, rng: &r, now: t0, ids: &ids).cannot == "지니게 할 수 없는\n도구예요")
    #expect(Engine.apply(.mon(op: .hold(uid: firstUID, item: nil)), steps: 0, walk: &w, play: &p, rng: &r, now: t0, ids: &ids).cannot == nil && w.count("생명의구슬") == 1)
}

@Test func heldDamageModifiers() {
    func dmg(_ item: String?, move: Int = 33, foe: Int = 19) -> Int {
        var b = fight(mon(128, 50, item: item), mon(foe, 50)); b.seed = 99
        let m = moveTable[move]!, (type, power) = b.moveType(.me, m)
        return b.calc(.me, .it, m, power: power, type: type, eff: b.typeEff(type, .it, by: .me), crit: false)
    }
    let plain = dmg(nil)
    #expect(abs(Double(dmg("구애머리띠")) / Double(plain) - 1.5) < 0.08)
    #expect(abs(Double(dmg("생명의구슬")) / Double(plain) - 1.3) < 0.08)
    #expect(abs(Double(dmg("실크스카프")) / Double(plain) - 1.2) < 0.08)                              // 몸통박치기: Normal
    #expect(dmg("목탄") == plain && dmg("구애안경") == plain)                                            // the wrong type; the wrong side
    let fighting = dmg(nil, move: 2), belt = dmg("달인의띠", move: 2)                                   // 태권당수 on 꼬렛 (Normal): super effective
    #expect(Double(belt) / Double(fighting) > 1.1)
    #expect(dmg("달인의띠") == plain)
}

@Test func focusSashAndBerries() {
    var b = fight(mon(129, 5, item: "기합의띠"), mon(150, 100))
    b.execute(.it, 94, called: false)                                                            // 사이코키네시스 from a Lv.100 뮤츠
    #expect(b.mine[0].hp == 1 && b.mine[0].item == nil && b.mine[0].mon.item == nil && said(b, "기합의띠로 버텼다"))   // used up: its own, gone for good
    b.out = []; b.execute(.it, 94, called: false)
    #expect(!b.mine[0].alive)                                                                    // once only

    var c = fight(mon(25, 30, item: "자뭉열매"), mon(19, 5))
    let full = c.mine[0].maxHP; c.hurt(.me, full * 6 / 10, "")
    #expect(c.mine[0].hp == full - full * 6 / 10 + full / 4 && c.mine[0].item == nil && c.mine[0].spent == "자뭉열매")
    c.out = []; c.execute(.me, 278, called: false)                                               // 리사이클
    #expect(c.mine[0].item == "자뭉열매" && c.mine[0].mon.item == "자뭉열매")

    var d = fight(mon(25, 30, item: "버치열매"), mon(25, 30))
    d.act(.it, 86, d.it)                                                                         // 전기자석파 → 버치열매 at once
    #expect(d.mine[0].status == nil && d.mine[0].item == nil && said(d, "버치열매로 마비 상태가 나았다"))
}

@Test func choiceLockSpeedAndOrder() {
    var b = fight(mon(25, 30, item: "구애스카프", moves: [84, 98]), mon(19, 30))
    let fast = b.speed(.me); b.mine[0].item = nil; #expect(abs(fast / b.speed(.me) - 1.5) < 0.01); b.mine[0].item = "구애스카프"
    var g = Seeded(s: 3)
    _ = b.turn(.fight(98), &g)
    #expect(b.usable(.me) == [98])                                                               // locked into 전광석화
    b.switchIn(.me, 0); #expect(b.usable(.me).count == 2)                                        // a switch frees it
    var c = fight(mon(25, 30, item: "검은철구"), mon(19, 30))
    #expect(c.grounded(.me) && c.speed(.me) < Double(c.base(.me, 5)))
    var slow = fight(mon(25, 30, item: "느림보꼬리"), mon(129, 5))
    let first = slow.moveFirst(33, 33); #expect(!first)                                                             // 느림보꼬리: last, even faster
}

@Test func itemMoves() {
    var b = fight(mon(65, 40, item: "구애스카프"), mon(19, 30))
    b.execute(.me, 271, called: false)                                                           // 트릭
    #expect(b.mine[0].item == nil && b.theirs[0].item == "구애스카프" && b.mine[0].mon.item == "구애스카프")   // swapped; ours comes back after
    var c = fight(mon(215, 40), mon(19, 30)); c.theirs[0].item = "먹다남은음식"
    c.execute(.me, 168, called: false)                                                           // 도둑질
    #expect(c.mine[0].item == "먹다남은음식" && c.theirs[0].item == nil && c.mine[0].mon.item == nil)
    var k = fight(mon(215, 40), mon(19, 30)); k.theirs[0].item = "먹다남은음식"; k.theirs[0].abilityOver = 60
    k.execute(.me, 282, called: false)                                                           // 점착: 탁쳐서떨구기 can't take it
    #expect(k.theirs[0].item == "먹다남은음식")
    var f = fight(mon(215, 40, item: "화염구슬"), mon(19, 30))
    f.execute(.me, 374, called: false)                                                           // 내던지기
    #expect(f.mine[0].item == nil && f.mine[0].mon.item == nil && f.theirs[0].status == .burn && said(f, "화염구슬을 내던졌다"))
    var n = fight(mon(215, 40, item: "오카열매"), mon(19, 30))
    n.execute(.me, 363, called: false)                                                           // 자연의은혜: 불꽃 60
    #expect(n.mine[0].item == nil && n.out.contains { if case .hit(.it, 363, let d, _, _) = $0 { return d > 0 }; return false })
    var e = fight(mon(215, 40), mon(19, 30)); e.execute(.me, 363, called: false)
    #expect(said(e, "그러나 실패했다"))
}

@Test func endOfTurnItems() {
    var b = fight(mon(143, 50, item: "먹다남은음식"), mon(19, 5)); b.mine[0].hp = 10
    b.endOfTurn(); #expect(b.mine[0].hp == 10 + b.mine[0].maxHP / 16)
    var o = fight(mon(68, 50, item: "화염구슬"), mon(19, 5)); o.endOfTurn(); #expect(o.mine[0].status == .burn)
    var s = fight(mon(89, 50, item: "검은오물"), mon(19, 5)); s.mine[0].hp = 10; s.endOfTurn(); #expect(s.mine[0].hp > 10)   // 질뻐기: Poison
    var t = fight(mon(68, 50, item: "검은오물"), mon(19, 5)); t.endOfTurn(); #expect(t.mine[0].hp == t.mine[0].maxHP - t.mine[0].maxHP / 8)
}

@Test func afterTheFight() {
    // a wild fight: what was used up is gone; what was taken comes back
    var w = Engine.fresh(now: t0, starter: firstUID); w.companion.item = "자뭉열매"
    var p = Play(), r = Seeded(s: 4), ids = Issued(next: firstUID + 1)
    var b = Battle(wild: mon(19, 2), party: [w.companion]); b.seed = 5; b.mine[0].hp = b.mine[0].maxHP / 3
    p.battle = b; p.party = [firstUID]
    _ = Engine.apply(.battle(cmd: .fight(slot: 0)), steps: 0, walk: &w, play: &p, rng: &r, now: t0, ids: &ids)
    for _ in 0..<30 where p.battle != nil { _ = Engine.apply(.battle(cmd: .ball), steps: 0, walk: &w, play: &p, rng: &r, now: t0, ids: &ids) }
    #expect(p.battle == nil && w.companion.item == nil)
    // EXP: 행복의알 ×1.5; 학습장치 shares with one that never came out
    var x = fight(mon(25, 10, item: "행복의알"), mon(19, 10)); x.theirs[0].hp = 0; x.award()
    var y = fight(mon(25, 10), mon(19, 10)); y.theirs[0].hp = 0; y.award()
    func exp(_ b: Battle, _ k: Int) -> Int { b.out.compactMap { if case .gained(let e, _, _, k) = $0 { return e }; return nil }.first ?? 0 }
    #expect(exp(x, 0) == exp(y, 0) * 3 / 2)
    var z = Battle(wild: mon(19, 10), party: [mon(25, 10), mon(16, 10, item: "학습장치")]); z.theirs[0].hp = 0; z.award()
    #expect(exp(z, 1) > 0 && exp(z, 0) < exp(y, 0))
    // EVs: 교정깁스 doubles, a 파워 item adds 4
    var m = mon(25, 10, item: "파워앵클릿"); m.gainEVs(from: 19); let ev = m.evs?[5]; #expect(ev == evYield[19][5] + 4)
    var mb = mon(25, 10, item: "교정깁스"); mb.gainEVs(from: 19); #expect(mb.evs?[5] == evYield[19][5] * 2)
}

@Test func heldEvolutionAndEverstone() {
    #expect(Walk.tradeEvolution(of: mon(61, 30, item: "왕의징표석"), giverBag: [])?.to == 186)       // 슈륙챙이 holding 왕의징표석 → 왕구리
    #expect(Walk.tradeEvolution(of: mon(64, 30, item: "변함없는돌"), giverBag: []) == nil)             // 윤겔라: not with 변함없는돌
    var w = Engine.fresh(now: t0, starter: firstUID); w.companion = mon(4, 40, item: "변함없는돌")
    #expect(w.levelEvolution(t0) == nil)
    w.companion.item = nil; #expect(w.levelEvolution(t0)?.to == 5)
    var c = mon(25, 5, item: "평온의방울"); _ = c.gain(100); let walked = c.walked; #expect(walked == 150)
}

@Test func heldShops() {
    let w = Engine.fresh(now: t0, starter: firstUID)
    for bp in [true, false] {
        let tabs = Walk.shopTabs(bp: bp)
        for ware in w.wares(bp: bp, shells: []) { #expect(tabs.contains(Walk.shopTab(ware, bp: bp)), "\(w.wareName(ware)) → \(Walk.shopTab(ware, bp: bp))") }
    }
    #expect(Walk.shopTab(.init(kind: .item("구애머리띠"), price: 32), bp: true) == "지닌 도구")
    #expect(Walk.shopTab(.init(kind: .item("왕의징표석"), price: 24), bp: true) == "지닌 도구")
    #expect(Walk.shopTab(.init(kind: .item("오카열매"), price: 200)) == "열매" && Walk.shopTab(.init(kind: .item("목탄"), price: 500)) == "지닌 도구")
    for i in Walk.heldBP.map(\.item) + Walk.heldW.map(\.item) { #expect(Held.holdable(i), "\(i)") }
    #expect(Set(Walk.heldBP.map(\.item)).count == Walk.heldBP.count && Set(Walk.heldW.map(\.item)).count == Walk.heldW.count)
}

@Test func towerTrainersHoldItems() {
    var w = Engine.fresh(now: t0, starter: firstUID); w.towerStreak = 21
    var r = Seeded(s: 9)
    let f = w.towerFoes(&r)
    #expect(f.foes.allSatisfy { $0.item != nil } && Set(f.foes.compactMap(\.item)).count == 3)
    w.towerStreak = 13; #expect(w.towerFoes(&r).foes.allSatisfy { $0.item == nil })                // (3.8: none before 14 wins)
    w.towerStreak = 14; #expect(w.towerFoes(&r).foes.allSatisfy { $0.item != nil })
}

@Test func heldFuzz() {                                                                          // 3 vs 3, every held item at random, item moves in the sets: always ends, HP in range
    let items = Array(Set(Walk.heldBP.map(\.item) + Walk.heldW.map(\.item) + Array(Held.gift.keys))).sorted()
    var r = Seeded(s: 2026), ended = 0
    for round in 0..<150 {
        func one() -> Mon {
            var m = Mon.wild(Int.random(in: 1...493, using: &r), level: 50, &r)
            m.item = items.randomElement(using: &r)
            var ms = m.moves; if Bool.random(using: &r) { ms[0] = [271, 415, 374, 363, 278, 282, 168, 343, 365, 450].randomElement(using: &r)! }; m.known = Array(ms.prefix(4))
            return m
        }
        var b = Battle(party: [one(), one(), one()], trainer: "퍼저", foes: [one(), one(), one()])
        _ = b.begin(weather: nil, &r)
        for _ in 0..<400 where !b.over {
            if b.mustReplace, let i = b.mine.indices.first(where: { b.mine[$0].alive && $0 != b.me }) { _ = b.replace(i); continue }
            let ok = b.usable(.me)
            _ = b.turn(.fight(ok.randomElement(using: &r) ?? 165), &r)
            for x in b.mine + b.theirs { #expect(x.hp >= 0 && x.hp <= x.maxHP, "round \(round)") }
        }
        if b.over { ended += 1 }
    }
    #expect(ended >= 145)
}

@Test func choiceLockAct() {
    var w = Engine.fresh(now: t0, starter: firstUID); w.companion = mon(25, 30, item: "구애머리띠", moves: [84, 98]); w.companion.uid = firstUID
    var p = Play(), r = Seeded(s: 1), ids = Issued(next: firstUID + 1)
    var b = Battle(wild: mon(129, 60), party: [w.companion]); b.seed = 3; p.battle = b; p.party = [firstUID]
    _ = Engine.apply(.battle(cmd: .fight(slot: 1)), steps: 0, walk: &w, play: &p, rng: &r, now: t0, ids: &ids)
    let o = Engine.apply(.battle(cmd: .fight(slot: 0)), steps: 0, walk: &w, play: &p, rng: &r, now: t0, ids: &ids)
    #expect(o.cannot == "구애머리띠로\n전광석화만 쓸 수 있다!")
}
