import Foundation

/// Headless rule check: `PokeWalker --selftest`. One line per check, then PASS/FAIL. `check` instead of assert: -O strips asserts.
struct Seeded: RandomNumberGenerator {                                   // SplitMix64: reproducible draws
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}
@MainActor func selftest() -> Bool {
    var failed = 0, total = 0
    func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        total += 1
        if !ok { failed += 1; print("FAIL \(name) \(detail())") } else { print("ok   \(name)") }
    }
    func at(_ day: Int, _ hour: Int = 12) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))! }
    var r = Seeded(s: 42)

    // 1 persistence
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-selftest-\(getpid())", isDirectory: true)
    let f = tmp.appendingPathComponent("state.json"), b = tmp.appendingPathComponent("state.json.bak")
    var s0 = Walk(); s0.walk(1234, at: at(10)); s0.caught = [Mon(dex: 16, level: 5, female: false)]; s0.bag = ["상처약"]
    Store.save(s0, file: f, bak: b)
    check(Store.load(file: f, bak: b) == s0, "store round-trip")
    Store.save(s0, file: f, bak: b)
    try? "garbage".write(to: f, atomically: true, encoding: .utf8)
    check(Store.load(file: f, bak: b) == s0, "corrupt state.json => .bak")
    check(((try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []).contains { $0.hasPrefix("state.corrupt-") }, "corrupt file kept aside")
    try? FileManager.default.removeItem(at: b); try? "garbage".write(to: f, atomically: true, encoding: .utf8)
    check(Store.load(file: f, bak: b) == Walk(), "both unreadable => fresh walker")
    try? FileManager.default.removeItem(at: tmp)

    // 2 steps -> watts
    var w = Walk(); w.walk(39, at: at(10))
    check(w.watts == 1 && w.remainder == 19, "20 steps per watt, remainder kept", "\(w.watts) \(w.remainder)")
    w.walk(1, at: at(10)); check(w.watts == 2 && w.earned == 2 && w.today == 40 && w.courseSteps == 40, "remainder completes the next watt")
    w.watts = 9999; w.walk(100, at: at(10)); check(w.watts == 9999 && w.earned == 7, "watts cap at 9999, lifetime keeps counting", "\(w.earned)")

    // 3 days
    w = Walk(); w.walk(500, at: at(10)); w.walk(300, at: at(11, 9))
    check(w.today == 300 && w.history == [500] && w.days == 2, "midnight moves today into history", "\(w.history)")
    w.walk(10, at: at(14)); check(w.history == [0, 0, 300, 500] && w.days == 5, "skipped days are zeros", "\(w.history)")
    w.walk(1, at: at(30)); check(w.history.count == 7 && w.history[0] == 0, "history keeps 7 days")
    w = Walk(); w.walk(5, at: at(10, 23)); w.walk(0, at: at(10, 1)); check(w.today == 5 && w.days == 1, "clock stepping back within the day changes nothing")

    // 4 input counter
    w = Walk(); w.sync(counter: 1000, boot: 7, at: at(10)); check(w.total == 0, "first sync only baselines")
    w.sync(counter: 1250, boot: 7, at: at(10)); check(w.total == 250, "counter growth = steps")
    w.sync(counter: 40, boot: 7, at: at(10)); check(w.total == 250 && w.counter == 40, "counter went backwards => re-baseline")
    w.sync(counter: 900, boot: 8, at: at(10)); check(w.total == 250 && w.boot == 8, "new boot => re-baseline")

    // 5 the draw reproduces Serebii's bands (상쾌한 들판, A = 두두 70 %, B 75 %)
    w = Walk(); w.companion = Mon(dex: 7, level: 5, female: false)            // squirtle: water, no bonus here
    w.picks = [0, 2, 4]
    func share(_ steps: Int) -> [Double] {
        w.courseSteps = steps; var n = [0, 0, 0]
        for _ in 0..<20000 { let s = w.encounter(&r); n[[0, 0, 1, 1, 2, 2][w.here.slots.firstIndex { $0.dex == s.dex && $0.steps == s.steps }!]] += 1 }
        return n.map { Double($0) / 200 }
    }
    check(share(0) == [0, 0, 100], "0 steps: only group C", "\(share(0))")
    let mid = share(500); check(abs(mid[1] - 75) < 1.5 && abs(mid[2] - 25) < 1.5, "500+: B 75 / C 25", "\(mid)")
    let top = share(2000); check(abs(top[0] - 70) < 1.5 && abs(top[1] - 22.5) < 1.5 && abs(top[2] - 7.5) < 1, "2000+: A 70 / B 22.5 / C 7.5", "\(top)")
    w.companion = Mon(dex: 4, level: 5, female: false); w.courseSteps = 1500    // charmander: fire is a course type
    check(w.bonus && w.effSteps == 2000, "type bonus: 25 % fewer steps")
    w = Walk(); check((0..<50).allSatisfy { _ in w.dowse(&r) == "상처약" }, "dowsing at 0 steps: only the common item")

    // 6 walker holds 3, overflow goes home
    w = Walk(); for d in 1...4 { _ = w.keep(Mon(dex: d, level: 5, female: false)) }
    check(w.caught.count == 3 && w.box.map(\.dex) == [4], "4th catch goes to the box")
    for _ in 0..<4 { _ = w.keep("상처약") }; check(w.items.count == 3 && w.bag.count == 1, "4th item goes to the bag")
    w.connect(); check(w.caught.isEmpty && w.items.isEmpty && w.box.count == 4 && w.bag.count == 4, "connect empties the walker")
    w.courseSteps = 900; w.setCourse(3, &r)
    check(w.course == 3 && w.courseSteps == 0 && [0, 1].contains(w.picks[0]) && [2, 3].contains(w.picks[1]) && [4, 5].contains(w.picks[2]), "new course: steps restart, one pick per group")
    w.courseSteps = 700; w.pair(0); check(w.companion.dex == 4 && w.box[0].dex == 25 && w.courseSteps == 700, "pair swaps with the box, course progress kept")
    _ = w.keep(Mon(dex: 16, level: 5, female: false)); w.pair(0, onWalker: true)
    check(w.companion.dex == 16 && w.caught[0].dex == 4, "pair with a Pokémon still on the walker")
    check(Walk().unlocked(1) && !Walk().unlocked(2), "courses unlock by lifetime watts")

    // 6b levels, evolution, dex
    var pk = Mon(dex: 25, level: 5, female: false)
    check(!pk.gain(90) && pk.gain(1) && pk.level == 6 && pk.points == 216, "1 step = 1 EXP: 피카츄 Lv.5 -> 6 after 91 steps (medium fast)", "\(pk)")
    w = Walk(); w.walk(500, at: at(10)); let e0 = w.companion.points
    w.box = [Mon(dex: 16, level: 5, female: false)]; w.pair(0); w.walk(50, at: at(10)); w.pair(0)
    check(w.companion.points == e0 && w.box[0].points == Mon(dex: 16, level: 5, female: false).points + 50, "each Pokémon keeps its own EXP across swaps")
    w = Walk(); w.companion = Mon(dex: 16, level: 17, female: false); check(w.levelEvolution(at(10)) == nil, "구구 Lv.17: not yet")
    w.companion.level = 18; check(w.levelEvolution(at(10))?.to == 17, "구구 Lv.18 -> 피죤")
    w.companion = Mon(dex: 133, level: 20, female: false, walked: friendSteps)
    w.total = 250; let noon = w.levelEvolution(at(10))?.to; w.total = 700; let late = w.levelEvolution(at(10))?.to
    check(noon == 196 && late == 197, "이브이: friendship at game noon 에브이, at game night 블래키 (steps, not the wall clock)", "\(String(describing: noon)) \(String(describing: late))")
    w.setCourse(1, &r); w.companion.walked = 0; check(w.levelEvolution(at(10))?.to == 470, "이브이 levelling in the forest -> 리피아")
    w = Walk(); check(w.stoneEvolutions(at(10)).isEmpty, "피카츄 without a stone: nothing")
    w.bag = ["천둥의돌"]; let st = w.stoneEvolutions(at(10))
    check(st.map(\.to) == [26], "피카츄 + 천둥의돌 -> 라이츄"); w.evolve(st[0]); check(w.companion.dex == 26 && w.bag.isEmpty && w.owned == [26], "evolving uses the stone and fills the dex")
    w = Walk(); w.companion = Mon(dex: 64, level: 20, female: false); check(w.tradeEvolution(at(10))?.to == 65, "윤겔라 + Connect -> 후딘")
    w.companion = Mon(dex: 281, level: 25, female: false); w.bag = ["각성의돌"]; check(w.stoneEvolutions(at(10)).map(\.to) == [475], "킬리아 ♂ + 각성의돌 -> 엘레이드")
    w.companion.female = true; check(w.stoneEvolutions(at(10)).isEmpty, "킬리아 ♀: no 엘레이드")
    w = Walk(); w.box = [Mon(dex: 16, level: 5, female: false)]; w.dex(); _ = w.keep(Mon(dex: 19, level: 5, female: false)); w.see(84)
    check(w.owned == [16, 19, 25] && w.seen == [16, 19, 25, 84], "dex: owned ⊂ seen, backfilled from what's here")
    _ = w.keep(Mon(dex: 130, level: 20, female: false, shiny: true)); check(w.shinyOwned == [130], "catching a 이로치 records it for the dex")
    check((try? JSONDecoder().decode(Walk.self, from: Data(String(decoding: try! JSONEncoder().encode(Walk()), as: UTF8.self).utf8))) != nil, "saves without dex fields decode")

    // 6c weather: rerolled every 1000 steps, boosts its types
    w = Walk(); check(!w.weatherDue, "no weather roll before 1000 steps")
    w.walk(999, at: at(10)); check(!w.weatherDue, "999 steps: still no roll"); w.walk(1, at: at(10)); check(w.weatherDue, "1000 steps: roll")
    _ = w.rollWeather(&r); check(!w.weatherDue && w.weatherAt == 1000, "rolled once per 1000")
    w = Walk(); w.setCourse(5, &r); var kinds = Set<Weather>(); for _ in 0..<300 { _ = w.rollWeather(&r); kinds.insert(w.weather!) }
    check(kinds == [.sunny, .fog], "caves only get fog", "\(kinds)")
    w = Walk(); w.picks = [0, 2, 4]; w.courseSteps = 500                                   // 상쾌한 들판 at 500+: B 니드런 75 %, C 구구 25 %
    func bShare() -> Double { var n = 0; for _ in 0..<20000 where w.encounter(&r).steps == w.here.slots[2].steps { n += 1 }; return Double(n) / 200 }
    let plain = bShare(); w.weather = .fog; let fog = bShare()
    check(abs(plain - 75) < 1.5 && abs(fog - 75) < 1.5, "fog boosts nothing here (니드런 is poison)", "\(plain) \(fog)")
    w.companion = Mon(dex: 1, level: 5, female: false)                                       // grass boost: none of these are grass either
    w.weather = .sunny; check(abs(bShare() - 75) < 1.5, "sunny: fire/grass only")
    w.course = 3; w.picks = [0, 2, 4]; w.courseSteps = 1500; w.weather = .rain           // 아름다운 해변 B 고라파덕 (water) 75 % -> 100 %
    check(abs(bShare() - 90) < 1.5, "rain: water B slot 87 % -> 90 % (capped)", "\(bShare())")

    // 6e game time on steps
    w = Walk(); check(w.hour == 6 && w.season == .spring && w.isDay, "step 0 = 6:00, spring")
    w.total = 584; check((20..<20.1).contains(w.hour) && !w.isDay, "584 steps later it's 20:00: night")
    w.total = 750; check(w.gameDay == 1 && w.hour == 0, "1000 steps = one day")
    w.total = seasonDays * dayLength; check(w.season == .summer, "7 days = next season")
    w.total = 3 * seasonDays * dayLength; check(w.season == .winter, "then autumn, winter")
    w = Walk(); w.total = 3 * seasonDays * dayLength; var snowy = 0; for _ in 0..<1000 { _ = w.rollWeather(&r); if w.weather == .snow { snowy += 1 } }
    check(snowy > 250, "winter fields snow a lot", "\(snowy)")

    // 6d eggs, legends, 껍질몬
    w = Walk(); _ = w.petEvent(&r)
    var eggs = 0; for _ in 0..<800 { w.total = w.nextEvent!; if case .egg = w.petEvent(&r) { eggs += 1; w.egg = nil } }
    check((60...150).contains(eggs), "about 1 event in 8 brings an egg", "\(eggs)")
    w = Walk(); w.egg = Egg(dex: 172, left: eggCycles[172] * 255)
    check(w.egg!.left == 2550 && eggPool.contains(172) && eggPool.contains(1) && !eggPool.contains(25) && !eggPool.contains(150), "피츄 egg 2550 steps; pool = unreachable bases, no legends")
    w.walk(2549, at: at(10)); check(!w.hatchDue, "not yet"); w.walk(1, at: at(10)); check(w.hatchDue, "hatches on the 2550th step")
    let baby = w.hatch(&r); check(baby.dex == 172 && baby.level == 1 && w.egg == nil && w.caught.first?.dex == 172 && w.owned!.contains(172), "hatched Lv.1 피츄, kept and in the dex")
    w = Walk(); w.course = 34; var legends = 0
    for _ in 0..<5000 where w.legend(&r, chain: 0) != nil { legends += 1 }
    check((60...140).contains(legends), "legend course: ~2 % of radar finds", "\(legends)")
    w.owned = [249, 250, 493]; check((0..<500).allSatisfy { _ in w.legend(&r, chain: 4) == nil }, "no legend once you have them all")
    w = Walk(); check((0..<500).allSatisfy { _ in w.legend(&r, chain: 4) == nil }, "never on normal courses")
    w = Walk(); w.companion = Mon(dex: 290, level: 20, female: false); let nin = w.levelEvolution(at(10))!
    w.evolve(nin); check(w.companion.dex == 291 && w.caught.map(\.dex) == [292], "토중몬 -> 아이스크 leaves 껍질몬")
    var hardHits = 0; for _ in 0..<2000 { var b = Battle(wild: Mon(dex: 150, level: 50, female: false), hard: true); b.wildHP = 1; if b.act(.capture, &r).contains(.caught) { hardHits += 1 } }
    check((700...900).contains(hardHits), "legends: 1 HP ball 40 %", "\(hardHits)")

    // 6f items
    check(ItemKind.of("상처약") == .heal(1) && ItemKind.of("풀회복약") == .heal(4) && ItemKind.of("기력의조각") == .revive(2) && ItemKind.of("하이퍼볼") == .ball(2)
          && ItemKind.of("네트볼") == .ball(1.5) && ItemKind.of("라즈열매") == .berry && ItemKind.of("천둥의돌") == .evolution && ItemKind.of("금구슬") == .sell(100)
          && ItemKind.of("마비치료제") == .sell(10) && ItemKind.of("기술머신68") == .sell(50), "item kinds")
    let allItems = Set(courses.flatMap { $0.items.map(\.item) })
    check(allItems.allSatisfy { if case .sell(let p) = ItemKind.of($0) { return p > 0 }; return true }, "every course item has a use or a price")
    w = Walk(); w.items = ["상처약"]; w.bag = ["고급상처약", "좋은상처약"]
    check(w.useHeal(missing: 2)! == ("좋은상처약", 2) && w.useHeal(missing: 4)! == ("고급상처약", 3) && w.useHeal(missing: 4)! == ("상처약", 1) && w.useHeal(missing: 1) == nil,
          "potions: smallest that fills the gap, else the biggest")
    w.bag = ["부활초", "기력의조각"]; check(w.useRevive()! == ("기력의조각", 2) && w.bag == ["부활초"], "revive: the cheaper one first")
    w.bag = ["슈퍼볼", "하이퍼볼"]; check(w.useBall()! == ("하이퍼볼", 2) && w.useBall()! == ("슈퍼볼", 1.5) && w.useBall() == nil, "best ball first")
    w = Walk(); w.bag = ["이상한사탕"]; check(w.feedCandy() && w.companion.level == 6 && w.companion.points == 216 && !w.feedCandy(), "이상한사탕: exactly one level")
    w.bag = ["라즈열매"]; check(w.feedBerry("라즈열매") && w.companion.walked == 500 && !w.feedBerry("상처약"), "berries feed friendship, potions don't")
    w.items = ["금구슬"]; w.bag = ["금구슬", "마비치료제", "천둥의돌"]
    check(w.sell("금구슬") == 200 && w.sell("천둥의돌") == 0 && w.watts == 200 && w.bag == ["마비치료제", "천둥의돌"], "selling: all of a kind; evolution items aren't for sale")
    var hb = Battle(wild: Mon(dex: 16, level: 5, female: false)); hb.myHP = 1
    let hbeats = hb.act(.item, &r, heal: 2); check(hbeats.first == .healed(2) && (hb.myHP == 3 || hb.myHP == 2), "battle item heals, then it may attack")
    var ballHits = 0; for _ in 0..<2000 { var b = Battle(wild: Mon(dex: 16, level: 5, female: false)); if b.act(.capture, &r, ball: 2).contains(.caught) { ballHits += 1 } }
    check((700...900).contains(ballHits), "하이퍼볼 doubles it: full HP 20 % -> 40 %", "\(ballHits)")

    // 7 battle
    var hits = 0, won = 0
    for _ in 0..<2000 { var bt = Battle(wild: Mon(dex: 16, level: 5, female: false)); bt.wildHP = 1; if bt.act(.capture, &r).contains(.caught) { hits += 1 } }
    check((1500...1700).contains(hits), "ball at 1 HP ~80 %", "\(hits)")
    hits = 0
    for _ in 0..<2000 { var bt = Battle(wild: Mon(dex: 16, level: 5, female: false)); if bt.act(.capture, &r).contains(.caught) { hits += 1 } }
    check((300...500).contains(hits), "ball at full HP ~20 %", "\(hits)")
    var odd: [Beat] = []
    for _ in 0..<500 {
        var bt = Battle(wild: Mon(dex: 16, level: 5, female: false)), beats: [Beat] = []
        while !(beats.last?.ends ?? false) { beats = bt.act(.attack, &r) }
        if beats.last == .won, bt.wildHP == 0 { won += 1 } else if !(beats.last == .lost && bt.myHP == 0) { odd = beats }
    }
    check(odd.isEmpty, "attack-only battles end won (wild 0 HP) or lost (ours 0 HP)", "\(odd)")
    check(won > 350, "attacking first wins most fights", "\(won)")
    var bt = Battle(wild: Mon(dex: 16, level: 5, female: false)); check(bt.act(.run, &r) == [.ran], "run ends at once")
    func winRate(_ edge: Int) -> Int {
        var n = 0
        for _ in 0..<1000 { var b = Battle(wild: Mon(dex: 16, level: 5, female: false)); b.edge = edge; var beats: [Beat] = []; while !(beats.last?.ends ?? false) { beats = b.act(.attack, &r) }; if beats.last == .won { n += 1 } }
        return n
    }
    let (low, even, high) = (winRate(-1), winRate(0), winRate(2))
    check(low < even && even < high && high > 950, "higher level: fewer misses, fewer hits taken", "\(low) \(even) \(high)")
    check(Battle.edge(50, 8) == 2 && Battle.edge(5, 30) == -1 && Battle.edge(12, 8) == 0, "level edge clamps to -1 ... 2")

    // 7a chain odds and rewards
    check(Walk.chainGoesOn(0) == 0.85 && abs(Walk.chainGoesOn(3) - 0.61) < 1e-9 && Walk.chainGoesOn(10) == 0.35, "chain goes on 85 %, -8 points a link, floor 35 %")
    w = Walk(); check(w.chainReward(1) == nil && w.watts == 2 && w.chainReward(4) == nil && w.watts == 10, "each link pays 2n W")
    check(w.chainReward(5) == courses[0].items[0].item && w.items == [courses[0].items[0].item] && w.bestChain == 5, "link 5: the course's rarest item, best chain kept")
    check(Walk.chainShinyOdds(0) == 128 && Walk.chainShinyOdds(5) == 11 && Walk.chainShinyOdds(10) == 6, "이로치 1/128 -> ~1/11 at 5 -> ~1/6 at 10")

    // 7b radar chain, companion events, box
    w = Walk(); w.picks = [0, 2, 4]; w.courseSteps = 2000
    func aShare(_ c: Int) -> Double { var n = 0; for _ in 0..<20000 where w.encounter(&r, chain: c).steps == 2000 { n += 1 }; return Double(n) / 200 }
    let a0 = aShare(0), a4 = aShare(4); check(abs(a0 - 70) < 1.5 && abs(a4 - 90) < 1.5, "chain 4: A slot 70 % -> 90 % (x1.8, capped)", "\(a0) \(a4)")
    w.courseSteps = 732; var seenB = Set<Int>(); for _ in 0..<2000 { seenB.insert(w.encounter(&r, chain: 6).dex) }
    check(seenB.count == 2, "6-chain before the A threshold still mixes B and C (was B only)", "\(seenB)")
    var grass = Set<[Int]>(); for _ in 0..<200 { w.newGrass(&r); grass.insert(w.picks) }
    check(grass.count == 8 && grass.allSatisfy { [0, 1].contains($0[0]) && [2, 3].contains($0[1]) && [4, 5].contains($0[2]) }, "new day: one of each group's two, all 8 mixes happen")
    w = Walk(); check(w.eventDue && w.petEvent(&r) == nil && !w.eventDue, "first event call only schedules")
    var found = 0; for _ in 0..<400 { w.total = w.nextEvent!; if w.petEvent(&r) != nil { found += 1 } }
    check((60...140).contains(found) && w.items.count == 3, "1 in 4 events brings an item back", "\(found)")
    w = Walk(); w.box = [Mon(dex: 16, level: 30, female: false), Mon(dex: 1, level: 5, female: false), Mon(dex: 16, level: 8, female: false)]
    w.sortBox(byLevel: false); check(w.box.map(\.dex) == [1, 16, 16] && w.box[1].level == 30, "sort by number (then level)")
    w.sortBox(byLevel: true); check(w.box.map(\.level) == [30, 8, 5], "sort by level")
    check(w.release(0) == 15 && w.watts == 15 && w.box.count == 2, "releasing gives level / 2 watts")

    // 8 data + art
    check(courses.count == 35 && courses.allSatisfy { $0.slots.count == 6 && $0.items.count == 10 }, "35 courses x 6 slots x 10 items")
    check(courses.prefix(20).map(\.watts) == courses.prefix(20).map(\.watts).sorted() && courses[20..<27].map(\.dex) == [10, 20, 30, 45, 60, 80, 100]
          && courses.suffix(8).map(\.dex) == [150, 170, 190, 210, 230, 260, 300, 350], "watts courses, then 7 event + 8 legend courses by Pokédex count")
    check(courses.flatMap(\.legends).count == 35 && Set(courses.flatMap(\.legends)).count == 35, "35 legends, each on exactly one course")
    w = Walk(); w.earned = 999_999; check(w.unlocked(19) && !w.unlocked(20), "event course needs the dex, not watts")
    w.owned = Array(1...10); check(w.unlocked(20) && courses[20].name == "노란 숲", "10 caught -> 노란 숲")
    check(monNames.count == 494 && monTypes.count == 494 && monNames[25] == "피카츄", "493 names + types")
    check(spriteData.count == 493 * 2 * 768, "sprites.bin in the bundle")
    check(colorData.count == 493 * 3162, "color.bin in the bundle")
    let body = (0..<48).flatMap { y in (0..<64).map { (x: $0, y: y) } }.first { spriteShade(6, 0, $0.x, $0.y) == 2 }!
    check(spriteColor(6, 0, body.x, body.y, shiny: false) != spriteColor(6, 0, body.x, body.y, shiny: true), "shiny 리자몽 has another palette")
    check(courses.flatMap { $0.slots.map(\.dex) }.allSatisfy { d in (0..<48).contains { y in (0..<64).contains { spriteColor(d, 0, $0, y, shiny: false) != 0 } } }, "every course Pokémon has colour art")
    let old = try? JSONDecoder().decode(Mon.self, from: Data(#"{"dex":25,"level":5,"female":false}"#.utf8))
    check(old == Mon(dex: 25, level: 5, female: false) && old?.shiny == nil, "pre-shiny saves still decode")
    let blank = Set(courses.flatMap { $0.slots.map(\.dex) } + [25]).filter { d in !(0..<48).contains { y in (0..<64).contains { spriteShade(d, 0, $0, y) > 0 } } }
    check(blank.isEmpty, "every course Pokémon has a sprite", "\(blank)")
    let td = textDots("포켓 레이더"); check(td.joined().contains(true) && td.count == 11, "Korean text renders to 11-row dots", td.map { String($0.map { $0 ? "#" : "." }) }.joined(separator: "\n"))
    check(josa("피카츄", "을", "를") == "피카츄를" && josa("꼬렛", "을", "를") == "꼬렛을", "josa")

    // 9 UI flows: the real view, driven through press() / touch() / tick()
    func on(_ v: WalkerView, _ p: (Screen) -> Bool) -> Bool { p(v.screen) }
    var s0w = Walk(); s0w.watts = 100
    let v = WalkerView(state: s0w); v.persist = false
    v.press(2); check(on(v) { if case .menu(0) = $0 { return true }; return false }, "home ▶ opens the menu")
    v.press(1); check(v.state.watts == 90 && on(v) { if case .radar = $0 { return true }; return false }, "radar costs 10W")
    v.screen = .radar(bush: 2, cursor: 0, since: Date().addingTimeInterval(-2), chain: 0)
    v.press(2); v.press(2); v.press(1)
    check(on(v) { if case .beats(_, [.appear], _, _) = $0 { return true }; return false } && v.state.seen?.isEmpty == false, "▶▶● on the shaking bush: a wild one appears (and is seen)")
    if case .beats(let b, _, _, _) = v.screen { v.screen = .battle(b, sel: 0) }
    _ = v.touch(v.moveRanges()[4].lowerBound + 1, 56)
    check(on(v) { if case .beats(_, [.ran], _, _) = $0 { return true }; return false }, "tapping 도망 runs")
    let caughtB = Battle(wild: Mon(dex: 16, level: 3, female: false), chain: 1)
    v.screen = .beats(caughtB, [.thrown, .caught], since: Date().addingTimeInterval(-30), from: caughtB); v.tick(nil)
    let chained = on(v) { if case .radar(_, _, _, 2) = $0 { return true }; return false }, ended = on(v) { if case .say = $0 { return true }; return false }
    check((chained || ended) && v.state.caught.last?.dex == 16, "a catch keeps it, then the chain goes on or quietly ends")
    v.press(3); check(on(v) { if case .home = $0 { return true }; return false }, "⌂ goes home")
    v.state.box = [Mon(dex: 16, level: 20, female: false)]; let wBefore = v.state.watts
    v.screen = .box(0, act: nil, confirm: false); v.press(1); v.press(2); v.press(1); v.press(2); v.press(1)
    check(v.state.box.isEmpty && v.state.watts == wBefore + 10, "box: ● 놓아주기 예 releases for level / 2 W")
    v.state.box = [Mon(dex: 1, level: 7, female: false)]; v.screen = .box(0, act: nil, confirm: false); v.press(1); v.press(1)
    check(v.state.companion.dex == 1 && v.state.box.first?.dex == 25, "box: ● 함께 swaps the companion")
    v.screen = .menu(6); v.press(1); check(on(v) { if case .dex = $0 { return true }; return false }, "menu 도감 opens the dex")
    _ = v.touch(80, 30); _ = v.touch(10, 30); _ = v.touch(48, 30); check(on(v) { if case .menu(6) = $0 { return true }; return false }, "dex taps: ▶ ◀ then ● back to the menu")

    print(failed == 0 ? "PASS \(total) checks" : "FAIL \(failed)/\(total)")
    return failed == 0
}
