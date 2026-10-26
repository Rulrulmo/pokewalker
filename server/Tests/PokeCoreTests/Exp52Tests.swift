import Foundation
import Testing
@testable import PokeCore

// docs/plans/19 §11 (5.2, content52): 배회 · 시련 · 레쿠쟈 원정, the boss and its ball stage, 기술머신.

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// One trainer's engine side, as ExpeditionTests' Desk (the clock a second an act; `day()` moves it a day on).
private struct Desk {
    var w: Walk, p = Play(), r = Seeded(s: 7), ids = Issued(next: firstUID + 1), clock = 0.0
    init(_ w: Walk = Engine.fresh(now: t0, starter: firstUID)) { self.w = w }
    @discardableResult mutating func act(_ a: Act, steps: Int = 0) -> Outcome {
        clock += 1
        return Engine.apply(a, steps: steps, walk: &w, play: &p, rng: &r, now: t0.addingTimeInterval(clock), ids: &ids)
    }
    mutating func day() { clock += 86_400 }
    func x(_ id: String) -> ExpProgress? { w.expeditions?[id] }
}
private func on52<T>(_ body: () throws -> T) rethrows -> T {
    try Content.$testing.withValue(true) { try Content.$testing51.withValue(true) { try Content.$testing52.withValue(true) { try body() } } }
}
private func course(_ f: (Course) -> Bool) -> Int { courses.firstIndex(where: f)! }
private var unova: Int { course { $0.region == 494...649 } }
private func strong(_ dex: Int, _ moves: [Int]) -> Mon { var m = Mon(dex: dex, level: 100, female: false); m.known = moves; m.uid = 9_000 + dex; return m }

@Test func roamerMeetings() throws {
    try on52 {
        var d = Desk(); d.w.course = unova
        #expect(d.act(.expStart(id: "토네로스")).cannot == nil)
        #expect(d.act(.expFight(id: "토네로스")).cannot == "만남이 없어요\n(5,000걸음마다)")
        var o = d.act(.steps, steps: 4_999)
        #expect(d.x("토네로스")?.meets == nil)
        o = d.act(.steps, steps: 1)
        #expect(d.x("토네로스")?.meets == 1 && o.news.contains(.expedition(id: "토네로스", n: 1, need: 2)))
        d.act(.steps, steps: 30_000)                                                                  // 2 banked at most, nothing carried past it
        #expect(d.x("토네로스")?.meets == 2 && d.x("토네로스")?.steps == 0)
        d.w.course = 0; d.w.expeditions?["토네로스"]?.meets = 0; d.act(.steps, steps: 30_000)       // not 하나: nothing
        #expect(d.x("토네로스")?.meets == 0)
        // a meeting: a wild fight with it as it left (HP, status); three of our turns and it runs off
        d.w.course = unova; d.w.expeditions?["토네로스"]?.meets = 1
        d.w.expeditions?["토네로스"]?.hp = 60; d.w.expeditions?["토네로스"]?.status = .paralysis
        d.w.companion = strong(242, [45])                                                             // 해피너스 Lv.100, 울음소리 only: no damage
        o = d.act(.expFight(id: "토네로스"))
        let b = try #require(o.battle)
        #expect(b.nm(.it) == "토네로스")                                                               // no 야생 (the user 10-23)
        #expect(o.cannot == nil && b.expedition == "토네로스" && b.raidTier == nil && b.theirs[0].hp == 60 && b.theirs[0].status == .paralysis && d.x("토네로스")?.meets == 0)
        var end: BattleEnd? = nil
        for _ in 0..<3 where end == nil { end = d.act(.battle(cmd: .fight(slot: 0))).end }
        #expect(end?.result == "fled" && d.p.battle == nil && d.p.exp == nil)
        let left = try #require(d.x("토네로스"))
        #expect(left.hp != nil && left.hp! <= 60 && left.on && left.done == 0)
    }
}

@Test func roamerCaughtAndOdds() throws {
    try on52 {
        var g = Seeded(s: 1)
        var full = Fighter(Mon.wild(641, level: 50, perfect: 3, &g)); let mx = full.maxHP
        #expect(abs(EngineRun<Seeded>.roamOdds(full) - 0.10) < 1e-9)
        full.hp = mx / 2
        #expect(abs(EngineRun<Seeded>.roamOdds(full) - (0.10 + 0.60 * Double(mx - mx / 2) / Double(mx))) < 1e-9)
        // HP 1: about 70 % a ball — caught within a few meetings, the legend rolled at the start into the box
        var d = Desk(); d.w.course = unova; d.w.companion = strong(242, [45])
        d.act(.expStart(id: "볼트로스"))
        let rolled = try #require(d.x("볼트로스")?.mon)
        var caught: Outcome? = nil
        for _ in 0..<10 where caught == nil {
            d.w.expeditions?["볼트로스"]?.meets = 1; d.w.expeditions?["볼트로스"]?.hp = 1
            d.act(.expFight(id: "볼트로스"))
            for _ in 0..<3 where d.p.battle != nil { let o = d.act(.battle(cmd: .ball)); if o.end?.result == "caught" { caught = o } }
        }
        let o = try #require(caught)
        #expect(o.mon?.dex == 642 && o.mon?.ivs == rolled.ivs && o.mon?.uid != nil && d.w.box.contains { $0.uid == o.mon?.uid })
        #expect(d.x("볼트로스") == ExpProgress(done: 1) && o.news.contains(.expeditionDone(id: "볼트로스", dex: 642, gift: nil)))
        #expect(!d.w.box.contains { $0.dex == 642 && $0.uid != o.mon?.uid })                          // the battle's copy isn't kept too
    }
}

@Test func roamerOnTheRadar() throws {                                                           // its course today: 1/30 a find, before the guests
    try on52 {
        var d = Desk(); d.w.watts = 9_999
        d.act(.expStart(id: "토네로스"))
        d.w.course = try #require(Expeditions.roamCourse("토네로스", day: d.w.day, open: { d.w.unlocked($0) }))
        var found = 0
        for _ in 0..<600 {
            d.act(.radar); if d.p.radar?.exp == "토네로스" { found += 1 }
            d.act(.radarPick(bush: -1)); d.w.watts = 9_999
        }
        #expect((8...35).contains(found))
        // the pick: the roamer's fight (no uid; a chain as it was)
        for _ in 0..<200 where d.p.radar?.exp == nil { d.act(.radarPick(bush: -1)); d.w.watts = 9_999; d.act(.radar) }
        let rd = try #require(d.p.radar)
        let o = d.act(.radarPick(bush: rd.bush))
        #expect(o.battle?.expedition == "토네로스" && o.battle?.wild.uid == nil && d.p.exp == "토네로스")
    }
}

@Test func landorusBossAndBalls() throws {
    try on52 {
        var d = Desk(); d.w.course = unova
        #expect(d.act(.expStart(id: "랜드로스")).cannot == "토네로스와 볼트로스를\n먼저 잡아 주세요")
        d.w.expeditions = ["토네로스": ExpProgress(done: 1)]
        #expect(d.act(.expStart(id: "랜드로스")).cannot == "볼트로스를\n먼저 잡아 주세요")
        d.w.expeditions?["볼트로스"] = ExpProgress(done: 1)
        #expect(d.act(.expStart(id: "랜드로스")).cannot == nil)
        #expect(d.act(.expFight(id: "랜드로스")).cannot == "아직 걸음이\n모자라요")
        d.w.course = 0; d.act(.steps, steps: 30_000)
        #expect(d.x("랜드로스")?.steps == 0)
        d.w.course = unova; d.act(.steps, steps: 19_999)
        var o = d.act(.steps, steps: 5)
        #expect(d.x("랜드로스")?.stage == 1 && d.x("랜드로스")?.steps == 0 && o.news.contains(.expeditionStage(id: "랜드로스", stage: 1)))
        // the boss: Lv.60 · 4V, 3 bars, once a day; a retreat ends it
        let me = strong(150, [94, 247, 58, 85]); d.w.box = [me]
        o = d.act(.expFight(id: "랜드로스", party: [me.uid!]))
        let b = try #require(o.battle)
        #expect(b.nm(.it) == "랜드로스" && Battle(wild: b.wild, party: [me]).nm(.it) == "야생 랜드로스")
        #expect(b.expedition == "랜드로스" && b.raidTier == 3 && b.theirs.count == 3 && b.wild.level == 60 && b.wild.perfectIVs >= 4 && b.megaUsed == [false, true])
        #expect(d.x("랜드로스")?.fought == d.w.day)
        #expect(d.act(.battle(cmd: .ball)).cannot == "보스는 볼로\n잡을 수 없다")
        o = d.act(.battle(cmd: .run))
        #expect(o.end?.result == "ran" && d.p.battle == nil)
        #expect(d.act(.expFight(id: "랜드로스")).cannot == "오늘은 이미\n싸웠어요")
        // a win (each bar at 1 HP): the ball stage, 5 balls of 30 %; the last missed → the boss again tomorrow
        var got: Outcome? = nil
        for _ in 0..<12 where got == nil {
            d.day()
            o = d.act(.expFight(id: "랜드로스", party: [me.uid!]))
            #expect(o.cannot == nil)
            for i in d.p.battle!.theirs.indices { d.p.battle!.theirs[i].hp = 1 }
            var end: BattleEnd? = nil
            for _ in 0..<12 where end == nil { end = d.act(.battle(cmd: .fight(slot: 0))).end; if d.p.battle?.mustReplace == true { _ = d.act(.battle(cmd: .replace(to: 0))) } }
            #expect(end?.result == "won" && end?.bars == 3 && end?.balls == 5 && d.x("랜드로스")?.balls == 5)
            #expect(d.act(.expFight(id: "랜드로스")).cannot == "볼을 먼저\n던져 주세요")
            for _ in 0..<5 where got == nil {
                let t = d.act(.expBall(id: "랜드로스"))
                #expect(t.raidThrow != nil)
                if t.raidThrow?.caught == true { got = t }
            }
            if got == nil { #expect(d.x("랜드로스")?.balls == nil && d.x("랜드로스")?.stage == 1) }
        }
        let g = try #require(got)
        #expect(g.mon?.dex == 645 && g.mon?.level == 50 && d.x("랜드로스") == ExpProgress(done: 1))
        #expect(d.w.bag.contains("비추는거울") && d.w.bag.contains("특성패치") && g.news.contains(.expeditionGift(id: "랜드로스", item: "비추는거울")))
        #expect(d.act(.expBall(id: "랜드로스")).cannot == "던질 볼이 없어요")
    }
}

@Test func swordsAndKeldeo() throws {
    try on52 {
        var d = Desk()
        let field = course { $0.art == .field }, cave = course { $0.art == .cave }
        d.act(.expStart(id: "코바르온"))
        d.w.course = field; d.act(.steps, steps: 40_000)
        #expect(d.x("코바르온")?.steps == 0)
        d.w.course = cave; d.act(.steps, steps: 40_000)
        #expect(d.x("코바르온")?.stage == 1)
        // one at a time: another stops it where it is
        #expect(d.act(.expStart(id: "테라키온")).cannot == nil)
        #expect(d.x("코바르온")?.on == false && d.x("코바르온")?.stage == 1)
        #expect(d.act(.expFight(id: "코바르온")).cannot == "하고 있는 원정이\n아니에요")
        // 케르디오: after the three; steps only with a sword as the companion
        #expect(d.act(.expStart(id: "케르디오")).cannot == "세 검사를\n먼저 잡아 주세요")
        for s in ["코바르온", "테라키온", "비리디온"] { d.w.expeditions?[s] = ExpProgress(done: 1) }
        #expect(d.act(.expStart(id: "케르디오")).cannot == nil)
        d.act(.steps, steps: 20_000)
        #expect(d.x("케르디오")?.steps == 0)
        d.w.companion = Mon(dex: 640, level: 50, female: false); d.w.companion.uid = 77
        var o = d.act(.steps, steps: 10_000)
        #expect(d.x("케르디오")?.steps == 10_000 && o.news.contains(.expeditionStage(id: "케르디오", stage: 1)))
        o = d.act(.expClaim(id: "케르디오"))
        #expect(o.mon?.dex == 647 && o.mon?.moves.contains(548) == true && d.w.bag.contains("특성패치") && d.x("케르디오") == ExpProgress(done: 1))
    }
}

@Test func rayquazaExpedition() throws {
    try on52 {
        var d = Desk()
        let mountain = course { $0.art == .mountain }, field = course { $0.art == .field }
        d.act(.expStart(id: "레쿠쟈"))
        d.w.course = field; d.act(.steps, steps: 30_000)
        #expect(d.x("레쿠쟈")?.n == 0)
        d.w.course = mountain; d.act(.steps, steps: 59_999)
        #expect(d.x("레쿠쟈")?.n == 19 && d.x("레쿠쟈")?.stage == nil)
        var o = d.act(.steps, steps: 1)
        #expect(d.x("레쿠쟈")?.stage == 1 && o.news.contains(.expeditionStage(id: "레쿠쟈", stage: 1)))
        d.act(.steps, steps: 30_000)
        #expect(d.x("레쿠쟈")?.stage == 2)
        let me = strong(150, [94, 247, 58, 85]); d.w.box = [me]
        o = d.act(.expFight(id: "레쿠쟈", party: [me.uid!]))
        #expect(o.battle?.wild.level == 70 && o.battle?.wild.moves.contains(620) == true && o.battle?.megaUsed == [false, true])
        for i in d.p.battle!.theirs.indices { d.p.battle!.theirs[i].hp = 1 }
        var end: BattleEnd? = nil
        for _ in 0..<12 where end == nil { let x = d.act(.battle(cmd: .fight(slot: 0))); end = x.end; if end != nil { o = x }; if d.p.battle?.mustReplace == true { _ = d.act(.battle(cmd: .replace(to: 0))) } }
        #expect(end?.result == "won" && end?.balls == nil)                                           // no ball stage: it comes (R2)
        let ray = try #require(o.mon)
        #expect(ray.dex == 384 && ray.level == 50 && ray.moves.contains(620) && d.x("레쿠쟈") == ExpProgress(done: 1) && !d.w.bag.contains("특성패치"))
        // every 레쿠쟈 of this trainer's may pick 화룡점정 now (기술 바꾸기)
        var other = Mon(dex: 384, level: 60, female: false); other.uid = 4_242; d.w.box.append(other)
        #expect(d.w.relearnable(other).contains(620) && !other.relearnable.contains(620))
        #expect(d.act(.mon(op: .move(uid: 4_242, slot: 0, move: 620))).cannot == nil)
    }
}

@Test func machines() throws {
    #expect(Machines.move(26) == 89 && Machines.name(26) == "기술머신26" && Machines.name(103) == "비전머신03" && Machines.number("비전머신03") == 103)
    #expect(Machines.learns(25, 24) && !Machines.learns(129, 24) && (1...107).allSatisfy { !Machines.learns(129, $0) })   // 피카츄 10만볼트, 잉어킹 none
    try on52 {
        #expect(Machines.price(26) == 3000 && Machines.price(4) == 2000 && Machines.price(1) == 1000 && Machines.price(10) == 2000 && Machines.price(98) == 1000)
        var d = Desk(); d.w.watts = 9_999
        let rows = d.w.wares(bp: false, shells: []).filter { if case .item(let i) = $0.kind { return Machines.number(i) != nil }; return false }
        #expect(rows.count == Machines.sold.count && Machines.sold.count == 106 && !Machines.sold.contains(60))   // (with 프리폴, §11.5)
        #expect(Dictionary(grouping: Machines.sold, by: Machines.price).mapValues(\.count) == [1000: 41, 2000: 43, 3000: 22])
        #expect(rows.allSatisfy { Walk.shopTab($0) == "기술머신" && $0.once })
        #expect(d.act(.buy(bp: false, item: "기술머신26", legend: nil, shell: nil, qty: 1)).cannot == nil)
        #expect(d.w.tms == [26] && d.w.watts == 6_999 && !d.w.bag.contains("기술머신26"))
        #expect(d.act(.buy(bp: false, item: "기술머신26", legend: nil, shell: nil, qty: 1)).cannot == "이미 가지고 있다")
        var gar = Mon(dex: 445, level: 50, female: false); gar.uid = 555; d.w.box = [gar]
        #expect(d.w.relearnable(gar).contains(89) && d.w.machineMoves(gar) == [89])
        #expect(d.act(.mon(op: .move(uid: 555, slot: 0, move: 89))).cannot == nil)
        // a course's copies (from before, or found): one of each number kept for good, the rest stay to sell
        d.w.bag += ["기술머신07", "기술머신07", "기술머신07", "기술머신26"]
        d.act(.steps)
        #expect(d.w.tms == [7, 26] && d.w.bag.filter { $0 == "기술머신07" }.count == 2 && d.w.bag.filter { $0 == "기술머신26" }.count == 1)
    }
    // off (or a 5.1.x app's request): no rows, no list, the bag as it was
    try Content.$testing.withValue(true) { try Content.$testing51.withValue(true) {
        var d = Desk(); d.w.bag = ["기술머신07"]; d.w.tms = [26]
        #expect(!d.w.wares(bp: false, shells: []).contains { $0.kind == .item("기술머신26") })
        var gar = Mon(dex: 445, level: 50, female: false); gar.uid = 555; d.w.box = [gar]
        #expect(!d.w.relearnable(gar).contains(89) || gar.relearnable.contains(89))
        d.act(.steps)
        #expect(d.w.bag == ["기술머신07"] && d.w.tms == [26])
        try Content.$testing52.withValue(true) { try Content.$app52.withValue(false) {
            #expect(!Content.v52)
            #expect(d.act(.expStart(id: "토네로스")).cannot == "없는 원정이에요")
        } }
    } }
}

@Test func machinesNotFound() throws {                                                             // 5.2.1 (the user via 회사 10-26): no 기술머신 from a course
    var with: [Int] { courses.indices.filter { courses[$0].items.contains { Machines.number($0.item) != nil } } }
    on52 { #expect(with.count == 11 && with.allSatisfy { Machines.number(courses[$0].items.last!.item) == nil }) }   // (none ends on one: the fallback stays)
    func finds(_ i: Int) -> [String] {
        var w = Walk(); w.course = i; w.courseSteps = 20_000; var r = Seeded(s: UInt64(i + 1))
        return (0..<2_000).map { _ in w.courseItem(&r) }
    }
    try on52 {
        for i in with {
            let got = finds(i)
            #expect(got.allSatisfy { Machines.number($0) == nil }, "\(courses[i].name)")
            #expect(Set(got).isSubset(of: Set(courses[i].items.map(\.item))))                    // nothing new: the others take its share
        }
    }
    var first: [Int] { courses.indices.filter { Machines.number(courses[$0].items[0].item) != nil } }   // the radar chain's every-5th reward: the rarest
    on52 { #expect(first.count == 11) }                                                            // (with 5.0's courses: 하나 동굴, 칼로스 산)
    func reward(_ i: Int) -> String? { var w = Walk(); w.course = i; return w.chainReward(5) }
    try on52 {
        for i in first { #expect(reward(i) == courses[i].items.first { Machines.number($0.item) == nil }?.item && reward(i) != nil, "\(courses[i].name)") }
        #expect(reward(course { $0.name == "어둑어둑 동굴" }) == "은빛가루" && reward(course { $0.name == "하얀 호수" }) == "으름열매")
    }
    try Content.$testing.withValue(true) { try Content.$testing51.withValue(true) {               // off (or a 5.1.x app): as before
        #expect(with.contains { i in finds(i).contains { Machines.number($0) != nil } })
        #expect(first.allSatisfy { reward($0) == courses[$0].items[0].item })
    } }
}

@Test func machineCleanupWalk() {                                                                  // 5.2.1's pokeserver tm-cleanup, on one save
    var w = Walk(); w.tms = [68]
    w.bag = ["기술머신68", "상처약", "기술머신68", "기술머신07", "기술머신07", "기술머신60"]; w.items = ["기술머신68", "기술머신10", "오랭열매"]
    let c = w.machineCleanup()
    #expect(c.adopted == [7, 10] && c.extra == 4)                                                  // 68 ×3 (had already) and 07's second
    #expect(w.tms == [7, 10, 68] && w.bag == ["상처약", "기술머신60"] && w.items == ["오랭열매"])     // (TM60 never had: it stays to sell)
    let again = w.machineCleanup()
    #expect(again.adopted.isEmpty && again.extra == 0)
    guard case .sell(let p) = ItemKind.of("기술머신68") else { Issue.record("not a sell item"); return }
    #expect(p == Walk.machineSale)
}

@Test func illusion() throws {                                                                    // plan 19 §11.5: 일루전 — the last one standing, broken by a hit
    func fight(_ foes: [Mon], pvp: Bool? = nil, illusion: Bool? = nil) -> Battle {
        var b = Battle(party: [strong(150, [94, 58])], trainer: "엘리트트레이너", foes: foes); b.pvp = pvp; b.illusion = illusion
        var g = Seeded(s: 3); _ = b.begin(weather: nil, &g); return b
    }
    let zoroark = Mon(dex: 571, level: 50, female: false), lucario = Mon(dex: 448, level: 50, female: false), garchomp = Mon(dex: 445, level: 50, female: false)
    try on52 {
        var b = fight([zoroark, lucario, garchomp])
        #expect(b.theirs[0].disguise?.dex == 445 && b.nm(.it) == "상대 한카리아스" && b.looks(.it).dex == 445)
        #expect(b.hint(94, "psychic") == 1)                                                          // 사이코키네시스 on 한카리아스' types, not 조로아크's 0
        var g = Seeded(s: 5)
        let beats = b.turn(.fight(58), &g)                                                            // our 뮤츠's 냉동빔: it shows
        #expect(beats.contains(.reform(.it, form: 0, text: "일루전이 풀렸다!")) && b.theirs[0].disguise == nil)
        // the last fainted: the one before it; alone or last itself: no disguise
        var c = Battle(party: [strong(150, [94])], trainer: "x", foes: [zoroark, lucario, garchomp]); c.theirs[2].hp = 0
        var g2 = Seeded(s: 3); _ = c.begin(weather: nil, &g2)
        #expect(c.theirs[0].disguise?.dex == 448)
        #expect(fight([zoroark]).theirs[0].disguise == nil)
        // a live battle: only when the server says both apps know it
        #expect(fight([zoroark, lucario], pvp: true).theirs[0].disguise == nil && fight([zoroark, lucario], pvp: true, illusion: true).theirs[0].disguise?.dex == 448)
    }
    try Content.$testing.withValue(true) { try Content.$testing51.withValue(true) {                 // off: as before
        #expect(fight([zoroark, lucario]).theirs[0].disguise == nil)
    } }
}

@Test func freeFall() throws {                                                                    // plan 19 §11.5: 프리폴 — up with the target, then the hit
    try on52 {
        #expect(Moves.supported(507) && Machines.sold.count == 106)
        var g = Seeded(s: 11)
        func wild(_ dex: Int) -> Battle { var b = Battle(wild: Mon(dex: dex, level: 30, female: false), party: [strong(149, [507, 58])]); _ = b.begin(weather: nil, &g); return b }
        var b = wild(448)                                                                            // 루카리오 54 kg
        var beats = b.turn(.fight(507), &g)
        #expect(b.mine[0].charging == 507 && b.mine[0].semi == 507 && b.theirs[0].lifted == true && b.theirs[0].semi == 507)
        #expect(beats.contains(.note(.me, text: "망나뇽은 야생 루카리오를 하늘로 데리고 올라갔다!")))
        #expect(!beats.contains { if case .use(.it, _) = $0 { return true }; return false })         // it can't move up there
        let hp = b.theirs[0].hp
        beats = b.turn(.fight(507), &g)                                                               // turn 2: the hit, both down
        #expect(b.theirs[0].hp < hp && b.theirs[0].lifted == nil && b.theirs[0].semi == 0 && b.mine[0].charging == 0)
        b = wild(143)                                                                                 // 잠만보 460 kg: it fails
        beats = b.turn(.fight(507), &g)
        #expect(beats.contains(.note(.me, text: "그러나 실패했다!")) && b.theirs[0].lifted == nil && b.mine[0].charging == 0)
        b = wild(18)                                                                                  // 피죤투: up, then nothing (Flying)
        _ = b.turn(.fight(507), &g); let hp2 = b.theirs[0].hp
        beats = b.turn(.fight(507), &g)
        #expect(b.theirs[0].hp == hp2 && beats.contains(.note(.it, text: "야생 피죤투에게는 효과가 없는 것 같다...")))
        // held up ourselves: 공격 only (it won't move), no switch, no ball
        var c = wild(448); c.mine[0].lifted = true; c.mine[0].semi = 507
        #expect(c.forced == 165 && c.locked && c.switchBlock != nil)
    }
    Content.$testing.withValue(true) { #expect(!Moves.supported(507)) }                             // off: as 5.0 left it
}

@Test func fuzz52() {                                                                             // 3 vs 3 with 5.2 on: the new moves often, 조로아크 often — always ends, HP in range
    on52 {
        let pool = moveTable.keys.filter(Moves.supported).sorted(), new = Array(Moves.since52)
        var r = Seeded(s: 2026_10_23), ended = 0
        for round in 0..<300 {
            func one() -> Mon {
                var m = Mon.wild(Int.random(in: 0..<4, using: &r) == 0 ? 571 : Int.random(in: 1...721, using: &r), level: Int.random(in: 30...80, using: &r), &r)
                m.known = (0..<4).map { k in k < 2 && Int.random(in: 0..<2, using: &r) == 0 ? new.randomElement(using: &r)! : pool.randomElement(using: &r)! }
                return m
            }
            var b = Battle(party: [one(), one(), one()], trainer: "퍼저", foes: [one(), one(), one()])
            _ = b.begin(weather: [nil, .rain, .snow, .fog].randomElement(using: &r)!, &r)
            for _ in 0..<400 where !b.over {
                if b.mustReplace, let i = b.mine.indices.first(where: { b.mine[$0].alive && $0 != b.me }) { _ = b.replace(i); continue }
                _ = b.turn(.fight(b.forced ?? b.usable(.me).randomElement(using: &r) ?? 165), &r)
                for x in b.mine + b.theirs { #expect(x.hp >= 0 && x.hp <= x.maxHP, "round \(round)") }
                #expect(!(b.mine + b.theirs).contains { $0.lifted == true && !$0.alive }, "round \(round)")
            }
            if b.over { ended += 1 }
        }
        #expect(ended >= 285)
    }
}
