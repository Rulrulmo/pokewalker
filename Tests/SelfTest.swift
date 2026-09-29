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
    func share(_ steps: Int) -> [Double] {
        w.courseSteps = steps; var n = [0, 0, 0]
        for _ in 0..<20000 { n[w.here.group(of: w.encounter(&r, guests: false))!] += 1 }
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
    check(w.course == 3 && w.courseSteps == 0, "new course: steps restart")
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
    w = Walk(); w.courseSteps = 500                                                         // 상쾌한 들판 at 500+: group B 75 %, C 25 %
    func bShare() -> Double { var n = 0; for _ in 0..<20000 where w.encounter(&r, guests: false).steps == w.here.slots[2].steps { n += 1 }; return Double(n) / 200 }
    let plain = bShare(); w.weather = .fog; let fog = bShare()
    check(abs(plain - 75) < 1.5 && abs(fog - 75) < 1.5, "fog boosts nothing here (니드런 is poison)", "\(plain) \(fog)")
    w.companion = Mon(dex: 1, level: 5, female: false)                                       // grass boost: none of these are grass either
    w.weather = .sunny; check(abs(bShare() - 75) < 1.5, "sunny: fire/grass only")
    w.course = 3; w.courseSteps = 0                                                          // 아름다운 해변 C: 해너츠 (grass) + three water types
    func sunkern() -> Double { var n = 0; for _ in 0..<20000 where w.encounter(&r, guests: false).dex == 191 { n += 1 }; return Double(n) / 200 }
    w.weather = .fog; let fogK = sunkern(); w.weather = .sunny; let sunK = sunkern()
    check(abs(fogK - 25) < 1.5 && abs(sunK - 33.3) < 1.5, "sunny: the grass one of four 25 % -> 33 % (x1.5 weight)", "\(fogK) \(sunK)")

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

    // 6f items
    check(ItemKind.of("상처약") == .heal(20) && ItemKind.of("풀회복약") == .heal(999) && ItemKind.of("기력의조각") == .revive(50) && ItemKind.of("하이퍼볼") == .ball(2)
          && ItemKind.of("네트볼") == .ball(1.5) && ItemKind.of("라즈열매") == .berry && ItemKind.of("천둥의돌") == .evolution && ItemKind.of("금구슬") == .sell(100)
          && ItemKind.of("기술머신68") == .sell(50), "item kinds")
    let allItems = Set(courses.flatMap { $0.items.map(\.item) })
    check(allItems.allSatisfy { if case .sell(let p) = ItemKind.of($0) { return p > 0 }; return true }, "every course item has a use or a price")
    w = Walk(); w.items = ["상처약"]; w.bag = ["고급상처약", "좋은상처약"]
    check(w.useHeal(missing: 40)! == ("좋은상처약", 40) && w.useHeal(missing: 300)! == ("고급상처약", 200) && w.useHeal(missing: 300)! == ("상처약", 20) && w.useHeal(missing: 1) == nil,
          "potions (Gen IV HP): smallest that fills the gap, else the biggest")
    w.bag = ["부활초", "기력의조각"]; check(w.useRevive()! == ("기력의조각", 50) && w.bag == ["부활초"], "revive: the cheaper one first (half HP)")
    w.bag = ["슈퍼볼", "하이퍼볼"]; check(w.useBall()! == ("하이퍼볼", 2) && w.useBall()! == ("슈퍼볼", 1.5) && w.useBall() == nil, "best ball first")
    w = Walk(); w.bag = ["이상한사탕"]; check(w.feedCandy() && w.companion.level == 6 && w.companion.points == 216 && !w.feedCandy(), "이상한사탕: exactly one level")
    w.bag = ["타우린", "타우린", "유석열매"]; w.companion.evs = [0, 95, 0, 0, 0, 0]
    check(w.feedVitamin("타우린") == 100 && w.feedVitamin("타우린") == nil && w.count("타우린") == 1 && w.feedVitamin("유석열매") == nil, "타우린: +10 up to 100, then no effect (kept); 유석열매 is HP")
    w.companion.evs = [150, 0, 0, 0, 0, 0]; w.bag = ["유석열매", "유석열매"]; check(w.feedVitamin("유석열매") == 100 && w.feedVitamin("유석열매") == 90, "EV berry: down to 100, then -10")
    w.bag = ["라즈열매"]; check(w.feedBerry("라즈열매") && w.companion.walked == 500 && !w.feedBerry("상처약"), "berries feed friendship, potions don't")
    w.items = ["금구슬"]; w.bag = ["금구슬", "마비치료제", "천둥의돌"]
    check(w.sell("금구슬") == 200 && w.sell("천둥의돌") == 0 && w.watts == 200 && w.bag == ["마비치료제", "천둥의돌"], "selling: all of a kind; evolution items aren't for sale")
    // 7 battle (Gen IV rules)
    let pika50 = Mon(dex: 25, level: 50, female: false), gyara50 = Mon(dex: 130, level: 50, female: false), lax50 = Mon(dex: 143, level: 50, female: false)
    check(pika50.stats == [102, 67, 42, 62, 52, 102], "stats: Gen IV base stats (방어 30, 특방 40) and formula, IV 15, no EV", "\(pika50.stats)")
    var adamant = pika50; adamant.nature = natures.firstIndex { $0.name == "고집" }!
    check(adamant.stats[1] == 67 * 11 / 10 && adamant.stats[3] == 62 * 9 / 10 && adamant.stats[5] == 102, "nature: 고집 +10 % 공격, -10 % 특수공격", "\(adamant.stats)")
    var wr = SystemRandomNumberGenerator(), rolled = (0..<200).map { _ in Mon.wild(25, level: 10, &wr) }
    check(rolled.allSatisfy { $0.ivs!.allSatisfy { (0...31).contains($0) } && abilitySlots[25].contains($0.abilityID) } && Set(rolled.map(\.nature)).count > 15 && rolled.contains(where: \.female) && rolled.contains { !$0.female },
          "wild ones roll IVs, a nature, an ability slot and a sex by ratio")
    check(abilitySlots[94] == [26] && Mon(dex: 94, level: 50, female: false).abilityName == "부유", "팬텀 has 부유 (Gen IV)")
    check(pika50.moves.count <= 4 && pika50.moves.allSatisfy(Moves.supported) && Mon(dex: 129, level: 5, female: false).moves == [150], "the last 4 level-up moves (status moves too): 잉어킹 Lv.5 튀어오르기", "\(Mon(dex: 129, level: 5, female: false).moves)")
    check(moveTable.count >= 460 && Moves.supported(252) && !Moves.supported(266), "every Gen I-IV move but the doubles / held-item ones", "\(moveTable.count)")
    check(effectiveness("electric", on: 130) == 4 && effectiveness("ground", on: 16) == 0 && effectiveness("ghost", on: 208) == 0.5, "type chart (Gen IV: Steel resists Ghost)")
    check(moveTable[85]!.power == 95 && moveTable[98]!.priority == 1 && moveTable[85]!.kind == 1 && moveTable[89]!.kind == 0, "HGSS move data: 10만볼트 95 special, 전광석화 +1, 지진 physical")
    func dealt(_ bs: [Beat], _ s: Side, _ id: Int) -> Int { bs.reduce(0) { if case .hit(s, id, let d, _, _) = $1 { return $0 + d }; return $0 } }
    var dG = 0, dS = 0
    for _ in 0..<60 { var a = Battle(wild: gyara50, companion: pika50), c = Battle(wild: lax50, companion: pika50); dG += dealt(a.turn(.fight(85), &r), .it, 85); dS += dealt(c.turn(.fight(85), &r), .it, 85) }
    check(dG > 3 * dS, "10만볼트: 4x on 갸라도스 vs 1x on 잠만보", "\(dG) \(dS)")
    var ob = Battle(wild: lax50, companion: pika50); check(ob.turn(.fight(85), &r).first == .use(.me, move: 85), "the faster one moves first")
    var pb = Battle(wild: Mon(dex: 135, level: 50, female: false), companion: lax50); pb.theirs[0].moves = [33]; pb.theirs[0].pp = [35]
    check(pb.turn(.fight(98), &r).first == .use(.me, move: 98), "전광석화 goes first even from a slow 잠만보")
    var sp = Battle(wild: lax50, companion: pika50); sp.mine[0].status = .paralysis; check(sp.speed(.me) < sp.speed(.it), "paralysis quarters speed")
    var ends = Set<String>(), bad: [Beat] = []
    for _ in 0..<200 {
        var b = Battle(wild: Mon(dex: 16, level: 6, female: false), companion: Mon(dex: 25, level: 8, female: false)), beats: [Beat] = [], n = 0
        while !(beats.last?.ends ?? false), n < 300 { let x = b.mine[0]; beats = b.turn(.fight(x.pp.firstIndex { $0 > 0 }.map { x.moves[$0] } ?? 165), &r); n += 1 }
        if beats.last == .won, b.theirs[0].hp == 0 { ends.insert("won") } else if beats.last == .lost, b.mine[0].hp == 0 { ends.insert("lost") } else if n < 300 { bad = beats }
    }
    check(bad.isEmpty && ends.contains("won"), "fights end won (it at 0 HP) or lost (ours at 0)", "\(bad)")
    var xb = Battle(wild: Mon(dex: 16, level: 10, female: false), companion: Mon(dex: 25, level: 5, female: false)); xb.theirs[0].hp = 1
    let xbeats = xb.turn(.fight(84), &r)
    if xbeats.contains(.fainted(.it)) { check(xbeats.contains(.gained(exp: baseExp[16] * 10 / 7, level: nil, foe: 16)) && xb.mine[0].mon.points == 125 + baseExp[16] * 10 / 7 && xb.mine[0].mon.evs?[5] == evYield[16][5], "a KO pays base EXP x level / 7, and EVs") }
    func catches(_ m: Mon, hp: Int?, ball: Double, status: Status? = nil) -> Int { var n = 0; for _ in 0..<2000 { var b = Battle(wild: m, companion: pika50); if let hp { b.theirs[0].hp = hp }; b.theirs[0].status = status; if b.turn(.capture, &r, ball: ball).contains(.caught) { n += 1 } }; return n }
    let pFull = catches(Mon(dex: 16, level: 5, female: false), hp: nil, ball: 1), p1 = catches(Mon(dex: 16, level: 5, female: false), hp: 1, ball: 1)
    let mew = catches(Mon(dex: 150, level: 50, female: false), hp: 1, ball: 2), mewZ = catches(Mon(dex: 150, level: 50, female: false), hp: 1, ball: 2, status: .sleep)
    check((780...980).contains(pFull) && p1 > 1900 && (60...240).contains(mew) && mewZ > mew * 3 / 2, "Gen IV catch formula: 구구 full ~44 %, 1 HP ~100 %, 뮤츠 1 HP + 하이퍼볼 ~6 %, asleep x2", "\(pFull) \(p1) \(mew) \(mewZ)")
    var hb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); hb.mine[0].hp = 10
    let hbeats = hb.turn(.item(.heal(50)), &r)
    check({ if case .heal(.me, 50, _)? = hbeats.first { return true }; return false }() && hb.mine[0].hp <= 60 && hb.mine[0].hp > 10, "potion first, then it may attack")
    hb.mine[0].status = .paralysis
    check(hb.usable(.cure([.paralysis], confusion: false)) && !hb.usable(.cure([.burn], confusion: false)), "the bag only offers what helps")
    let cbeats = hb.turn(.item(.cure([.paralysis], confusion: false)), &r); check(cbeats.contains { if case .status(.me, nil, _) = $0 { return true }; return false } && hb.mine[0].status == nil, "마비치료제 cures paralysis")
    hb.mine[0].pp[0] = 0; _ = hb.turn(.item(.pp(10, all: false)), &r); check(hb.mine[0].pp[0] == min(10, moveTable[hb.mine[0].moves[0]]!.pp), "PP에이드: +10 to the emptiest move")
    _ = hb.turn(.item(.x(1, 1)), &r); check(hb.mine[0].stage[1] == 1, "플러스파워: 공격 +1")
    check(ItemKind.of("마비치료제") == .battle(.cure([.paralysis], confusion: false)) && ItemKind.of("회복약") == .battle(.restore) && ItemKind.of("리샘열매") == .battle(.cure([.poison, .burn, .paralysis, .sleep, .freeze], confusion: true)),
          "cures, 회복약 and cure berries are battle items")
    var pz = Battle(wild: Mon(dex: 16, level: 20, female: false), companion: pika50); pz.theirs[0].status = .poison
    let pzb = pz.turn(.fight(45), &r); check(pzb.contains(.hurt(.it, damage: pz.theirs[0].maxHP / 8, text: "야생 구구는 독의 데미지를 입었다!")), "poison: 1/8 at the end of the turn")
    var gh = Battle(wild: Mon(dex: 94, level: 50, female: false), companion: lax50); gh.mine[0].moves = [89]; gh.mine[0].pp = [10]
    check(dealt(gh.turn(.fight(89), &r), .it, 89) == 0, "부유: 지진 can't touch 팬텀")
    var ib = Battle(wild: gyara50, companion: pika50); let ibeats = ib.begin(weather: .rain, &r)
    check(ibeats.first == .appear && ib.mine[0].stage[1] == -1 && ib.sky == .rain, "the opening: 위협 lowers 공격; the course's rain falls on the field")
    var rb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); check(rb.turn(.run, &r) == [.ran], "run ends a wild fight at once")
    var lb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: Mon(dex: 25, level: 5, female: false)); lb.mine[0].hp = 10
    let lmax = lb.mine[0].maxHP; lb.apply(.gained(exp: 5000, level: nil, foe: 16))
    check(lb.mine[0].mon.level > 5 && lb.mine[0].hp == 10 + lb.mine[0].maxHP - lmax && lb.mine[0].mon.known != nil, "a level-up mid-fight raises current HP by the same amount (and freezes the moveset)")
    let fv = WalkerView(state: { var s = Walk(); s.bag = ["기력의조각"]; return s }()); fv.persist = false
    var fainted = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); fainted.mine[0].hp = 0; fainted.mine[0].down = true; fainted.over = true
    if case .beats(let nb, let rbeats, _, let from) = fv.after(fainted, .lost, Date()), case .heal(.me, let h, _)? = rbeats.first {
        check(nb.mine[0].hp == h && h == pika50.stats[0] / 2 && from.mine[0].hp == 0 && !nb.over && !nb.mine[0].down, "a revive leaves the fight at the revived HP (not 0)")
    } else { check(false, "a revive leaves the fight at the revived HP (not 0)") }
    var tb = Battle(party: [pika50, lax50], trainer: "베테랑 민수", foes: [Mon(dex: 16, level: 3, female: false), Mon(dex: 19, level: 3, female: false)])
    check(tb.turn(.swap(1), &r).first == .sendOut(.me, 1) && tb.me == 1, "switching sends the other one in")
    tb.theirs[0].hp = 1; var tbeats: [Beat] = [], tn = 0
    while !tbeats.contains(.fainted(.it)), tn < 50 { let x = tb.mine[tb.me]; tbeats = tb.turn(.fight(x.moves.first { !moveTable[$0]!.isStatus } ?? x.moves[0]), &r); tn += 1 }
    check(tbeats.contains(.sendOut(.it, 1)) && tb.it == 1 && !tbeats.contains(.won), "a trainer sends the next one out")
    var fuzzBad = 0, fuzzStall = 0                                                             // random species / levels / moves: every fight ends, and replaying the beats gives the engine's HP
    for n in 0..<300 {
        func mon() -> Mon { Mon.wild(Int.random(in: 1...493, using: &r), level: Int.random(in: 1...100, using: &r), &r) }
        var b = n % 2 == 0 ? Battle(wild: mon(), companion: mon()) : Battle(party: [mon(), mon()], trainer: "x", foes: [mon(), mon()])
        var bs = b.begin(weather: [Weather.rain, .snow, nil].randomElement(using: &r)!, &r), k = 0
        while !(bs.last?.ends ?? false), k < 400 {
            let x = b.mine[b.me], ok = x.moves.indices.filter { x.pp[$0] > 0 }
            var from = b; bs = b.turn(.fight(b.forced ?? (ok.isEmpty ? 165 : x.moves[ok.randomElement(using: &r)!])), &r); k += 1
            for bt in bs { from.apply(bt) }
            if from.me != b.me || from.it != b.it || from.mine.map(\.hp) != b.mine.map(\.hp) || from.theirs.map(\.hp) != b.theirs.map(\.hp) { fuzzBad += 1 }
        }
        if k >= 400 { fuzzStall += 1 }
    }
    check(fuzzBad == 0 && fuzzStall == 0, "300 random fights: all end, and the beats replay to the engine's HP", "\(fuzzBad) \(fuzzStall)")
    // 7b new moves: the forget-one choice
    let ls25 = learnsets[25], next = stride(from: 0, to: ls25.count, by: 2).map { (ls25[$0], ls25[$0 + 1]) }.first { $0.0 > 12 && Moves.supported($0.1) }!
    var lw = Walk(); lw.companion = Mon(dex: 25, level: next.0 - 1, female: false); lw.companion.known = [84, 45, 39, 86].filter { $0 != next.1 }.prefix(4).map { $0 }
    lw.walk(expTable[growthRate[25]][next.0] - lw.companion.points, at: Date())
    check(lw.companion.level == next.0 && Array((lw.learn ?? []).prefix(2)) == [-1, next.1], "a level-up by walking queues the new move", "\(lw.learn ?? [])")
    let lv = WalkerView(state: lw); lv.persist = false; lv.nextLearn(Date())
    if case .learn = lv.screen { lv.press(1); check(lv.state.companion.known?[0] == next.1 && lv.state.companion.moves.count == 4, "forget move 1 for the new one") } else { check(false, "4 moves known: the forget-one screen") }
    let before4 = lv.state.companion.known; lv.state.learn = [-1, 85]; lv.screen = .learn(sel: 4); lv.press(1)
    check(lv.state.companion.known == before4 && lv.state.learn == [], "배우지 않는다 keeps the four")
    lv.state.companion.known = [84, 45]; lv.state.learn = [-1, next.1]; lv.screen = .home; lv.nextLearn(Date())
    check(lv.state.companion.known == [84, 45, next.1], "a free slot: learned straight away")
    let bv = WalkerView(state: { var s = Walk(); s.bag = ["마비치료제", "상처약"]; return s }()); bv.persist = false
    var bb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); bb.mine[0].status = .paralysis
    check(bv.battleItems(bb).map(\.name) == ["마비치료제"], "full HP: only the cure is offered")
    bv.screen = .bagBattle(bb, sel: 0); bv.press(1)
    if case .beats(let after, let bs, _, _) = bv.screen { check(after.mine[0].status == nil && bv.state.bag == ["상처약"] && bs.first == .note(.me, text: "마비치료제를 사용했다!"), "using a cure in battle takes it from the bag") } else { check(false, "using a cure in battle") }

    // 7c Battle Tower + shops
    w = Walk(); w.companion = Mon(dex: 25, level: 20, female: false); w.box = [Mon(dex: 16, level: 5, female: false), Mon(dex: 143, level: 30, female: false), Mon(dex: 19, level: 12, female: false)]
    check(w.party().map(\.ref) == [-1, 1, 2] && w.party().map(\.mon.dex) == [25, 143, 19], "party: companion + the two strongest")
    let legendSet = Set(courses.flatMap(\.legends) + [150, 250])
    let tf = w.towerFoes(&r); check(tf.foes.count == 3 && tf.foes.allSatisfy { (20...23).contains($0.level) && !legendSet.contains($0.dex) }, "tower foes: 3 non-legends at the party's level", "\(tf.foes)")
    var g: [Int] = []; for _ in 0..<8 { g.append(w.towerWin()) }
    check(g == [1, 1, 1, 1, 1, 1, 4, 2] && w.bp == 12 && w.towerBest == 8, "BP: 1 a win, +3 on the 7th, 2 a win after 7", "\(g)")
    w.towerEnd(); check(w.towerStreak == 0 && w.towerBest == 8, "a loss ends the streak, best kept")
    var up = w.box[1]; _ = up.gainBattleExp(50_000); w.writeBack([-1, 1], [w.companion, up]); check(w.box[1].level > 30, "tower EXP goes back to the box")
    w.watts = 100; check(w.buy("슈퍼볼", watts: 40) && w.watts == 60 && w.bag.last == "슈퍼볼" && !w.buy("풀회복약", watts: 300), "W shop")
    check(w.buy("이상한사탕", bp: 8) && w.bp == 4 && !w.buy("이상한사탕", bp: 8), "BP exchange")
    w = Walk(); w.watts = 9998; check(w.buyLegend(0) == nil, "칠색조 needs the full 9,999 W")
    w.watts = 9999; check(w.buyLegend(0)?.dex == 250 && w.watts == 0 && w.caught.last?.level == 50 && w.buyLegend(0) == nil, "칠색조: 9,999 W, once")
    w.bp = 299; check(w.buyLegend(1) == nil, "뮤츠 needs 300 BP"); w.bp = 300
    check(w.buyLegend(1)?.dex == 150 && w.bp == 0 && w.legendBought(150) && (w.owned ?? []).contains(150), "뮤츠: 300 BP, once, in the dex")

    // 7a chain odds and rewards
    check(Walk.chainGoesOn(0) == 0.85 && abs(Walk.chainGoesOn(3) - 0.61) < 1e-9 && Walk.chainGoesOn(10) == 0.35, "chain goes on 85 %, -8 points a link, floor 35 %")
    w = Walk(); check(w.chainReward(1) == nil && w.watts == 2 && w.chainReward(4) == nil && w.watts == 10, "each link pays 2n W")
    check(w.chainReward(5) == courses[0].items[0].item && w.items == [courses[0].items[0].item] && w.bestChain == 5, "link 5: the course's rarest item, best chain kept")
    check(Walk.chainShinyOdds(0) == 128 && Walk.chainShinyOdds(3) == 51 && Walk.chainShinyOdds(5) == 36 && Walk.chainShinyOdds(10) == 21 && Walk.chainShinyOdds(30) == 21,
          "이로치 1/128 -> 1/51 at 3 -> 1/36 at 5 -> 1/21 from 10 on")

    // 7b radar chain, companion events, box
    w = Walk(); w.courseSteps = 2000
    func aShare(_ c: Int) -> Double { var n = 0; for _ in 0..<20000 where w.encounter(&r, chain: c, guests: false).steps == 2000 { n += 1 }; return Double(n) / 200 }
    let a0 = aShare(0), a4 = aShare(4); check(abs(a0 - 70) < 1.5 && abs(a4 - 90) < 1.5, "chain 4: A slot 70 % -> 90 % (x1.8, capped)", "\(a0) \(a4)")
    w.courseSteps = 732; var seenG = Set<Int>(), seenD = Set<Int>()
    for _ in 0..<4000 { let s = w.encounter(&r, chain: 6, guests: false); seenG.insert(w.here.group(of: s)!); seenD.insert(s.dex) }
    check(seenG == [1, 2] && seenD.count == 8, "6-chain at 732 steps: groups B and C, all 8 of their candidates show up", "\(seenG) \(seenD.count)")
    w.courseSteps = 5000; var every = Set<Int>(); for _ in 0..<20000 { every.insert(w.encounter(&r).dex) }
    check(every == Set(w.here.all.map(\.dex) + w.here.guests), "past every threshold, all 12 candidates + 5 guests appear", "\(every.count)")
    check(courses.allSatisfy { c in c.extra.count == 6 && Set(c.extra.map(\.dex)).count == 6 && Set(c.extra.map(\.dex)).isDisjoint(with: c.slots.map(\.dex))
                                    && c.guests.count == 5 && Set(c.guests).isDisjoint(with: c.all.map(\.dex)) },
          "every course: 6 new extras + 5 other guests (노란 숲's 6 originals are all 피카츄)")
    check(courses.allSatisfy { c in c.extra.enumerated().allSatisfy { $0.element.steps == c.slots[$0.offset / 2 * 2].steps } }, "extras need their group's steps")
    w = Walk(); var guestsSeen = 0; for _ in 0..<5000 where w.here.guests.contains(w.encounter(&r).dex) { guestsSeen += 1 }
    check((380...620).contains(guestsSeen), "guests: ~10 % of finds", "\(guestsSeen)")
    w = Walk(); check(w.eventDue && w.petEvent(&r) == nil && !w.eventDue, "first event call only schedules")
    var found = 0; for _ in 0..<400 { w.total = w.nextEvent!; if w.petEvent(&r) != nil { found += 1 } }
    check((60...140).contains(found) && w.items.count == 3, "1 in 4 events brings an item back", "\(found)")
    w = Walk(); w.box = [Mon(dex: 16, level: 30, female: false), Mon(dex: 1, level: 5, female: false), Mon(dex: 16, level: 8, female: false)]
    w.sortBox(byLevel: false); check(w.box.map(\.dex) == [1, 16, 16] && w.box[1].level == 30, "sort by number (then level)")
    w.sortBox(byLevel: true); check(w.box.map(\.level) == [30, 8, 5], "sort by level")
    check(w.release(0) == 15 && w.watts == 15 && w.box.count == 2, "releasing gives level / 2 watts")
    w = Walk(); w.box = [Mon(dex: 29, level: 5, female: true), Mon(dex: 29, level: 12, female: true), Mon(dex: 16, level: 5, female: false), Mon(dex: 29, level: 5, female: true, shiny: true), Mon(dex: 29, level: 8, female: false)]
    let dup = w.releaseDuplicates(of: 29)
    check(dup.count == 2 && dup.watts == 6 && w.box.map(\.level) == [12, 5, 5] && w.box.filter { $0.dex == 29 }.count == 2 && w.box.contains { $0.shiny == true },
          "duplicates: keeps the 이로치 and the best, releases the rest", "\(dup) \(w.box)")

    // 8 data + art
    check(courses.count == 35 && courses.allSatisfy { $0.slots.count == 6 && $0.items.count == 10 }, "35 courses x 6 slots x 10 items")
    check(courses.prefix(20).map(\.watts) == courses.prefix(20).map(\.watts).sorted() && courses[20..<27].map(\.dex) == [10, 20, 30, 45, 60, 80, 100]
          && courses.suffix(8).map(\.dex) == [150, 170, 190, 210, 230, 260, 300, 350], "watts courses, then 7 event + 8 legend courses by Pokédex count")
    check(courses.flatMap(\.legends).count == 33 && Set(courses.flatMap(\.legends)).count == 33 && !courses.contains { $0.legends.contains(250) || $0.legends.contains(150) },
          "33 legends on courses, each once; 칠색조 / 뮤츠 are shop-only")
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
    check(on(v) { if case .beats(_, let bs, _, _) = $0 { return bs.first == .appear }; return false } && v.state.seen?.isEmpty == false, "▶▶● on the shaking bush: a wild one appears (and is seen)")
    if case .beats(let b, _, _, _) = v.screen { v.screen = .battle(b, sel: 0) }
    if case .battle(let bb, _) = v.screen { _ = v.touch(v.menuRanges(v.battleMenu(bb))[3].lowerBound + 1, 56) }
    check(on(v) { if case .beats(_, let bs, _, _) = $0 { return bs == [.ran] || bs.first == .note(.me, text: "도망칠 수 없었다!") }; return false }, "tapping 도망 tries to run (Gen IV odds)")
    let caughtB = Battle(wild: Mon(dex: 16, level: 3, female: false), companion: v.state.companion, chain: 1)
    v.screen = .beats(caughtB, [.thrown(shakes: 3), .caught], since: Date().addingTimeInterval(-30), from: caughtB); v.tick(nil)
    let chained = on(v) { if case .radar(_, _, _, 2) = $0 { return true }; return false }, ended = on(v) { if case .say = $0 { return true }; return false }
    check((chained || ended) && v.state.caught.last?.dex == 16, "a catch keeps it, then the chain goes on or quietly ends")
    var hpB = Battle(wild: Mon(dex: 143, level: 30, female: false), companion: Mon(dex: 25, level: 30, female: false))
    hpB.mine[0].moves = [85]; hpB.mine[0].pp = [15]; hpB.theirs[0].moves = [33]; hpB.theirs[0].pp = [35]   // damaging moves only (no 꼬리흔들기, no 잠자기)
    v.screen = .moves(hpB, sel: 0); v.press(1)
    if case .beats(let after, _, _, let before) = v.screen {
        check(after.theirs[0].hp < before.theirs[0].hp || after.mine[0].hp < before.mine[0].hp, "the battle kept after a turn is the one AFTER it (HP stays down next turn)")
        v.screen = .beats(after, [.appear], since: Date().addingTimeInterval(-30), from: after); v.tick(nil)
        if case .battle(let next, _) = v.screen { check(next.theirs[0].hp == after.theirs[0].hp && next.mine[0].hp == after.mine[0].hp, "next turn's menu shows the same HP") }
    } else { check(false, "the battle kept after a turn is the one AFTER it (HP stays down next turn)") }
    v.screen = .menu(0); v.press(3); check(on(v) { if case .home = $0 { return true }; return false }, "⌂ goes home")
    v.state.box = [Mon(dex: 16, level: 20, female: false)]; let wBefore = v.state.watts
    v.screen = .box(0, act: nil, confirm: false); v.press(1); v.press(2); v.press(1); v.press(2); v.press(1)
    check(v.state.box.isEmpty && v.state.watts == wBefore + 10, "box: ● 놓아주기 예 releases for level / 2 W")
    v.state.box = [Mon(dex: 1, level: 7, female: false)]; v.screen = .box(0, act: nil, confirm: false); v.press(1); v.press(1)
    check(v.state.companion.dex == 1 && v.state.box.first?.dex == 25, "box: ● 함께 swaps the companion")
    v.screen = .menu(6); v.press(1); check(on(v) { if case .dex = $0 { return true }; return false }, "menu 도감 opens the dex")
    _ = v.touch(80, 30); _ = v.touch(10, 30); _ = v.touch(48, 30); check(on(v) { if case .menu(6) = $0 { return true }; return false }, "dex taps: ▶ ◀ then ● back to the menu")

    v.state.box = (1...120).map { Mon(dex: $0 * 4 % 493 + 1, level: 5, female: false, shiny: $0 % 17 == 0 ? true : nil) }
    let walkMenu = v.buildMenu().items.first { $0.title.hasPrefix("함께 걷기") }?.submenu
    v.state.box += (0..<40).map { Mon(dex: 29, level: 1 + $0 % 25, female: $0 % 2 == 0) }
    let nido = v.buildMenu().items.first { $0.title.hasPrefix("함께 걷기") }?.submenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title.hasPrefix("니드런♀") }?.submenu
    check((nido?.items.count ?? 99) <= 12 && nido?.items.contains { $0.title.hasPrefix("그 밖") } == true && nido?.items.last?.title.hasPrefix("중복 놓아주기") == true,
          "40 니드런♀: ≤ 12 rows, the rest under 그 밖, and 중복 놓아주기", "\(nido?.items.count ?? -1)")
        check((walkMenu?.items.count ?? 99) <= 26 && walkMenu?.items.contains { $0.title.hasPrefix("★ 이로치") } == true, "big box: 함께 걷기 stays short (recent, shinies, dex ranges)", "\(walkMenu?.items.count ?? -1)")

    print(failed == 0 ? "PASS \(total) checks" : "FAIL \(failed)/\(total)")
    return failed == 0
}
