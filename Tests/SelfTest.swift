import AppKit

/// Headless rule check: `PokeWalker --selftest`. One line per check, then PASS/FAIL. `check` instead of assert: -O strips asserts.
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
    w.courseSteps = 700; w.pair(0); check(w.companion.dex == 4 && w.box.last?.dex == 25 && w.box.count == 4 && w.courseSteps == 700, "pair swaps with the box (the old one to its end), course progress kept")
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
    check(ItemKind.of("순백떡") == .evReset && ItemKind.of("은색병뚜껑") == .bottleCap(false) && ItemKind.of("금색병뚜껑") == .bottleCap(true), "순백떡 / 병뚜껑 kinds")
    w.bag = ["순백떡"]; w.companion.evs = [0, 12, 0, 0, 0, 0]
    check(w.resetEVs() && w.companion.evs == [0, 0, 0, 0, 0, 0] && w.bag.isEmpty, "순백떡: every EV back to 0, used up")
    w.bag = ["순백떡"]; check(!w.resetEVs() && w.bag == ["순백떡"], "순백떡 with no EVs: kept")
    var hw = Walk(); var hr = Seeded(s: 21); hw.companion = Mon.wild(25, level: 49, &hr); hw.companion.ivs = [3, 12, 31, 7, 20, 31]; hw.bag = ["은색병뚜껑", "금색병뚜껑"]
    let hpBefore = Battle(wild: hw.companion, companion: hw.companion).hiddenPower(hw.companion), atkBefore = hw.companion.stats[1]
    check(!hw.hyperTrain(1) && hw.bag.count == 2, "대단한 특훈 waits for Lv.50"); hw.companion.level = 50
    check(hw.hyperTrain(1) && hw.companion.ivs?[1] == 12 && hw.companion.effectiveIVs[1] == 31 && hw.companion.stats[1] > atkBefore && hw.companion.perfectIVs == 3 && hw.bag == ["금색병뚜껑"],
          "은색병뚜껑: 공격 counts as 31 (its IV stays 12): 3V", "\(hw.companion.effectiveIVs)")
    hw.bag = ["은색병뚜껑", "금색병뚜껑"]; check(!hw.hyperTrain(2) && hw.bag == ["은색병뚜껑", "금색병뚜껑"], "은색병뚜껑 on a 31 (방어): nothing used"); hw.bag = ["금색병뚜껑"]
    check(hw.hyperTrain(nil) && hw.companion.perfectIVs == 6 && hw.bag.isEmpty && Battle(wild: hw.companion, companion: hw.companion).hiddenPower(hw.companion) == hpBefore,
          "금색병뚜껑: 6V, and 잠재파워 keeps its type (the IVs themselves stay)")
    hw.bag = ["금색병뚜껑"]; check(!hw.hyperTrain(nil) && hw.bag == ["금색병뚜껑"], "all 31 already: the cap is kept")
    w.bag = ["라즈열매"]; check(w.feedBerry("라즈열매") && w.companion.walked == 500 && !w.feedBerry("상처약"), "berries feed friendship, potions don't")
    w.items = ["금구슬"]; w.bag = ["금구슬", "마비치료제", "천둥의돌"]
    check(w.sell("금구슬") == 200 && w.sell("천둥의돌") == 0 && w.watts == 200 && w.bag == ["마비치료제", "천둥의돌"], "selling: all of a kind; evolution items aren't for sale")
    // 7 battle (Gen IV rules)
    let pika50 = Mon(dex: 25, level: 50, female: false), gyara50 = Mon(dex: 130, level: 50, female: false), lax50 = Mon(dex: 143, level: 50, female: false)
    check(pika50.stats == [102, 67, 42, 62, 52, 102], "stats: Gen IV base stats (방어 30, 특방 40) and formula, IV 15, no EV", "\(pika50.stats)")
    var adamant = pika50; adamant.nature = natures.firstIndex { $0.name == "고집" }!
    check(adamant.stats[1] == 67 * 11 / 10 && adamant.stats[3] == 62 * 9 / 10 && adamant.stats[5] == 102, "nature: 고집 +10 % 공격, -10 % 특수공격", "\(adamant.stats)")
    var wr = Seeded(s: 3), rolled = (0..<200).map { _ in Mon.wild(25, level: 10, &wr) }
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
    if xbeats.contains(.fainted(.it)) { check(xbeats.contains(.gained(exp: baseExp[16] * 10 / 7, level: nil, foe: 16, to: 0)) && xb.mine[0].mon.points == 125 + baseExp[16] * 10 / 7 && xb.mine[0].mon.evs?[5] == evYield[16][5], "a KO pays base EXP x level / 7, and EVs") }
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
    var pz = Battle(wild: Mon(dex: 16, level: 20, female: false), companion: pika50); pz.theirs[0].status = .poison; pz.theirs[0].moves = [150]; pz.theirs[0].pp = [40]   // (its 날려버리기 would end a wild fight)
    let pzb = pz.turn(.fight(45), &r); check(pzb.contains(.hurt(.it, damage: pz.theirs[0].maxHP / 8, text: "야생 구구는 독의 데미지를 입었다!")), "poison: 1/8 at the end of the turn", "\(pzb)")
    var gh = Battle(wild: Mon(dex: 94, level: 50, female: false), companion: lax50); gh.mine[0].moves = [89]; gh.mine[0].pp = [10]
    check(dealt(gh.turn(.fight(89), &r), .it, 89) == 0, "부유: 지진 can't touch 팬텀")
    var ib = Battle(wild: gyara50, companion: pika50); let ibeats = ib.begin(weather: .rain, &r)
    check(ibeats.first == .appear && ib.mine[0].stage[1] == -1 && ib.sky == .rain, "the opening: 위협 lowers 공격; the course's rain falls on the field")
    var rb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); check(rb.turn(.run, &r) == [.ran], "run ends a wild fight at once")
    var lb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: Mon(dex: 25, level: 5, female: false)); lb.mine[0].hp = 10
    let lmax = lb.mine[0].maxHP; lb.apply(.gained(exp: 5000, level: nil, foe: 16, to: 0))
    check(lb.mine[0].mon.level > 5 && lb.mine[0].hp == 10 + lb.mine[0].maxHP - lmax && lb.mine[0].mon.known != nil, "a level-up mid-fight raises current HP by the same amount (and freezes the moveset)")
    let fv = WalkerView(state: { var s = Walk(); s.bag = ["기력의조각"]; return s }()); fv.persist = false; fv.rng = Seeded(s: 11)
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
            var from = b; k += 1
            bs = b.mustReplace ? b.replace(b.mine.indices.first { b.mine[$0].alive }!) : b.turn(.fight(b.forced ?? (ok.isEmpty ? 165 : x.moves[ok.randomElement(using: &r)!])), &r)
            for bt in bs { from.apply(bt) }
            if from.me != b.me || from.it != b.it || from.mine.map(\.hp) != b.mine.map(\.hp) || from.theirs.map(\.hp) != b.theirs.map(\.hp)
                || from.mine.map(\.typeList) != b.mine.map(\.typeList) || from.theirs.map(\.typeList) != b.theirs.map(\.typeList) { fuzzBad += 1 }
        }
        if k >= 400 { fuzzStall += 1 }
    }
    check(fuzzBad == 0 && fuzzStall == 0, "300 random fights: all end, and the beats replay to the engine's HP and types", "\(fuzzBad) \(fuzzStall)")
    // 7a' rules the menus follow: trapping, 도발 / 트집, choosing who's next, EXP split, trainers switching
    check(abilitySlots[202] == [23], "마자용 has 그림자밟기")
    var trap = Battle(party: [pika50, lax50], trainer: "x", foes: [Mon(dex: 202, level: 30, female: false)])
    check(trap.switchBlock != nil && trap.trapped(.me), "그림자밟기: ours can't switch out")
    let wob = Battle(party: [Mon(dex: 202, level: 30, female: false), lax50], trainer: "x", foes: [Mon(dex: 202, level: 30, female: false)])
    check(wob.switchBlock == nil, "그림자밟기 doesn't hold another 그림자밟기 (Gen IV)")
    var wildWob = Battle(wild: Mon(dex: 202, level: 30, female: false), companion: pika50); check(!wildWob.canEscape(), "그림자밟기: no running either")
    trap.theirs[0] = Fighter(Mon(dex: 16, level: 5, female: false)); trap.mine[0].charging = 76; check(trap.locked && trap.switchBlock == "지금은 교체할 수 없다!", "charging 솔라빔: no switching")
    var tz = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); tz.mine[0].moves = [86, 85]; tz.mine[0].pp = [20, 15]; tz.mine[0].taunt = 2
    check(tz.usable(.me) == [85], "도발: status moves can't be picked")
    tz.mine[0].pp = [20, 0]; check(tz.usable(.me).isEmpty, "도발 + no PP on the rest: nothing to pick (→ 발버둥)")
    var rep = Battle(party: [Mon(dex: 129, level: 5, female: false), lax50], trainer: "x", foes: [Mon(dex: 68, level: 60, female: false)]), rn = 0, rbs: [Beat] = []
    while !rep.mustReplace, !rep.over, rn < 30 { rbs = rep.turn(.fight(rep.mine[0].moves[0]), &r); rn += 1 }
    check(rep.mustReplace && rep.me == 0 && !rep.over && !rbs.contains(.sendOut(.me, 1)), "ours fainted: the battle waits for the player's pick")
    let repB = rep.replace(1); check(repB.first == .sendOut(.me, 1) && rep.me == 1 && !rep.mustReplace, "the pick comes in")
    var split = Battle(party: [pika50, lax50], trainer: "x", foes: [Mon(dex: 16, level: 10, female: false), Mon(dex: 16, level: 10, female: false)])
    split.theirs[0].moves = [45]; split.theirs[0].pp = [40]; _ = split.turn(.swap(1), &r); split.theirs[0].hp = 1
    var sb: [Beat] = []; while !sb.contains(.fainted(.it)), !split.over { sb = split.turn(.fight(split.mine[1].moves.first { !moveTable[$0]!.isStatus }!), &r) }
    let half = baseExp[16] * 10 / 7 * 3 / 2 / 2
    check(sb.contains(.gained(exp: half, level: nil, foe: 16, to: 0)) && sb.contains(.gained(exp: half, level: nil, foe: 16, to: 1)), "EXP split between the two that faced it", "\(sb)")
    var swaps = 0, stays = 0
    for _ in 0..<40 {
        var sw = Battle(party: [Mon(dex: 9, level: 40, female: false)], trainer: "x", foes: [Mon(dex: 5, level: 40, female: false), Mon(dex: 1, level: 40, female: false)]); sw.mine[0].moves = [55]; sw.mine[0].pp = [25]
        if sw.turn(.fight(55), &r).contains(.sendOut(.it, 1)) { swaps += 1 }
        var st = Battle(party: [Mon(dex: 9, level: 40, female: false)], trainer: "x", foes: [Mon(dex: 1, level: 40, female: false), Mon(dex: 5, level: 40, female: false)]); st.mine[0].moves = [55]; st.mine[0].pp = [25]
        if st.turn(.fight(55), &r).contains(.sendOut(.it, 1)) { stays += 1 }
    }
    check(swaps > 10 && swaps < 40 && stays == 0, "a trainer's 리자드 facing 물대포 often pulls back for 이상해씨; 이상해씨 stays", "\(swaps) \(stays)")
    // 7d against the Gen IV formula: Bulbapedia's example (Lv.75 글레이시아 공격 123, 얼음엄니 → 한카리아스 방어 163 = 168-196), then each modifier by hand
    var gl = Mon(dex: 471, level: 75, female: true); gl.nature = 0; gl.ivs = [31, 31, 31, 31, 31, 31]; gl.evs = [0, 28, 0, 0, 0, 0]
    var gc = Mon(dex: 445, level: 75, female: false); gc.nature = 0; gc.ivs = [31, 31, 21, 31, 31, 31]
    check(gl.stats[1] == 123 && gc.stats[2] == 163 && moveTable[423]!.power == 65 && moveTable[423]!.physical, "reference setup: 공격 123, 방어 163, 얼음엄니 65 physical", "\(gl.stats) \(gc.stats)")
    func spread(_ setup: (inout Battle) -> Void, crit: Bool = false) -> ClosedRange<Int> {
        var b = Battle(wild: gc, companion: gl); setup(&b); var lo = 9999, hi = 0; let m = moveTable[423]!
        for _ in 0..<800 { let d = b.calc(.me, .it, m, power: 65, type: "ice", eff: 4, crit: crit); lo = min(lo, d); hi = max(hi, d) }
        return lo...hi
    }
    check(spread { _ in } == 168...196, "damage: 168-196 exactly (85-100 % roll, STAB, x4, rounding down each step)", "\(spread { _ in })")
    check(spread { $0.mine[0].status = .burn } == 84...100, "burn halves physical damage", "\(spread { $0.mine[0].status = .burn })")
    check(spread { $0.sides[1].reflect = 5 } == 84...100 && spread({ $0.sides[1].reflect = 5 }, crit: true) == 336...396, "리플렉터 halves it; a critical ignores it")
    check(spread({ _ in }, crit: true) == 336...396, "critical: x2 (Gen IV)")
    check(spread { $0.mine[0].stage[1] = -1 } == 108...132, "공격 -1: x2/3", "\(spread { $0.mine[0].stage[1] = -1 })")
    check(spread { $0.mine[0].abilityOver = 91 } == 224...264, "적응력: STAB x2")
    check(spread { $0.theirs[0].abilityOver = 111 } == 126...147, "필터: super effective x0.75")
    check(spread { $0.theirs[0].abilityOver = 47 } == 84...100, "두꺼운지방: ice / fire at half 공격")
    // behaviour, one move each (the other side 튀어오르기)
    func duel(_ a: Mon, _ b: Mon, _ am: [Int], _ bm: [Int] = [150]) -> Battle {
        var x = Battle(wild: b, companion: a); x.mine[0].moves = am; x.mine[0].pp = am.map { moveTable[$0]!.pp }; x.theirs[0].moves = bm; x.theirs[0].pp = bm.map { moveTable[$0]!.pp }; return x
    }
    let rat = Mon(dex: 19, level: 50, female: false)
    var d1 = duel(pika50, Mon(dex: 50, level: 30, female: false), [86]); _ = d1.turn(.fight(86), &r)
    var d2 = duel(pika50, rat, [86]); _ = d2.turn(.fight(86), &r)
    check(d1.theirs[0].status == nil && d2.theirs[0].status == .paralysis, "전기자석파: paralyses, not a ground type", "\(d1.theirs[0].status as Any) \(d2.theirs[0].status as Any) \(d2.theirs[0].mon.abilityName)")
    var d3 = duel(pika50, Mon(dex: 4, level: 30, female: false), [261]); for _ in 0..<6 { _ = d3.turn(.fight(261), &r) }
    var d4 = duel(pika50, rat, [261]); for _ in 0..<12 where d4.theirs[0].status == nil { _ = d4.turn(.fight(261), &r) }
    check(d3.theirs[0].status == nil && d4.theirs[0].status == .burn, "도깨비불: burns, not a fire type")
    var d5 = duel(pika50, rat, [92, 150]), poisonHits: [Int] = []
    for _ in 0..<12 where poisonHits.count < 2 {
        for bt in d5.turn(.fight(d5.theirs[0].status == nil ? 92 : 150), &r) { if case .hurt(.it, let d, let t) = bt, t.contains("독") { poisonHits.append(d) } }
    }
    let rmax = d5.theirs[0].maxHP; check(poisonHits == [rmax / 16, rmax * 2 / 16], "맹독: 1/16, then 2/16 …", "\(poisonHits) \(rmax)")
    var d6 = duel(pika50, rat, [73]); d6.mine[0].hp = 50; let s6 = d6.turn(.fight(73), &r)
    check(s6.contains(.hurt(.it, damage: d6.theirs[0].maxHP / 8, text: "씨뿌리기가 야생 꼬렛의 체력을 빼앗는다!")) && s6.contains { if case .heal(.me, d6.theirs[0].maxHP / 8, _) = $0 { return true }; return false }, "씨뿌리기: 1/8 a turn, to the user", "\(s6)")
    var d7 = duel(pika50, Mon(dex: 1, level: 30, female: false), [73]); _ = d7.turn(.fight(73), &r); check(!d7.theirs[0].seeded, "씨뿌리기 doesn't take on grass types")
    var d8 = duel(pika50, rat, [182], [33]); check(!d8.turn(.fight(182), &r).contains { if case .hit(.me, _, _, _, _) = $0 { return true }; return false }, "방어: the attack is blocked")
    var hz = Battle(party: [pika50], trainer: "x", foes: [Mon(dex: 16, level: 30, female: false), Mon(dex: 6, level: 30, female: false), rat])
    hz.sides[1].stealthRock = true; hz.out = []; hz.switchIn(.it, 1); let charMax = hz.theirs[1].maxHP
    check(hz.out.contains(.hurt(.it, damage: charMax / 2, text: "뾰족한 바위가 상대 리자몽을 파고들었다!")), "스텔스록: 1/8 x rock effectiveness (리자몽 1/2)", "\(hz.out)")
    hz.sides[1] = SideState(); hz.sides[1].spikes = 1; hz.out = []; hz.switchIn(.it, 2); let spikeRat = hz.out; hz.out = []; hz.switchIn(.it, 0)
    check(spikeRat.contains { if case .hurt(.it, hz.theirs[2].maxHP / 8, _) = $0 { return true }; return false } && !hz.out.contains { if case .hurt = $0 { return true }; return false }, "압정뿌리기: 1/8 on the ground, nothing on a flying type")
    var d9 = duel(pika50, rat, [446]); _ = d9.turn(.fight(446), &r); check(d9.sides[1].stealthRock, "스텔스록 lays the rocks")
    var d10 = duel(Mon(dex: 291, level: 30, female: false), rat, [150]); _ = d10.turn(.fight(150), &r); _ = d10.turn(.fight(150), &r)
    check(abilitySlots[291] == [3] && d10.mine[0].stage[5] >= 1, "가속: 스피드 up at the end of the turn")
    var sleeps = Set<Int>(); for _ in 0..<300 { var b = duel(pika50, rat, [150]); b.seed = r.next() | 1; b.inflict(.it, .sleep, from: .me, loud: false); sleeps.insert(b.theirs[0].sleep) }
    check(sleeps == [1, 2, 3, 4], "sleep lasts 1-4 turns (Gen IV)", "\(sleeps)")
    var d11 = duel(pika50, rat, [156]); d11.mine[0].hp = 20; _ = d11.turn(.fight(156), &r)
    check(d11.mine[0].hp == d11.mine[0].maxHP && d11.mine[0].status == .sleep && d11.mine[0].sleep == 2, "잠자기: full HP, asleep 2 turns")
    var d12 = duel(pika50, Mon(dex: 19, level: 5, female: false), [164, 150], [33]); _ = d12.turn(.fight(164), &r); let afterSub = d12.mine[0].hp
    _ = d12.turn(.fight(150), &r)
    check(afterSub == d12.mine[0].maxHP - d12.mine[0].maxHP / 4 && d12.mine[0].hp == afterSub && d12.mine[0].sub < d12.mine[0].maxHP / 4, "대타출동: 1/4 HP, then it takes the hits")
    var bp = Battle(party: [pika50, lax50], trainer: "x", foes: [Mon(dex: 19, level: 5, female: false)]); bp.mine[0].moves = [14, 226]; bp.mine[0].pp = [20, 40]; bp.theirs[0].moves = [150]; bp.theirs[0].pp = [40]
    _ = bp.turn(.fight(14), &r); _ = bp.turn(.fight(226), &r); check(bp.me == 1 && bp.mine[1].stage[1] == 2, "바톤터치 passes 칼춤's +2")
    var d13 = duel(pika50, rat, [389], [150]), d14 = duel(pika50, rat, [389], [33])
    let hitsIt: ([Beat]) -> Bool = { $0.contains { if case .hit(.it, 389, _, _, _) = $0 { return true }; return false } }
    check(!hitsIt(d13.turn(.fight(389), &r)) && hitsIt(d14.turn(.fight(389), &r)), "기습: only against an attack")
    var d15 = duel(pika50, Mon(dex: 292, level: 30, female: false), [55, 52])
    let wg1 = d15.turn(.fight(55), &r), wg2 = d15.turn(.fight(52), &r)
    check(abilitySlots[292] == [25] && !wg1.contains { if case .hit(.it, _, _, _, _) = $0 { return true }; return false } && wg2.contains(.fainted(.it)), "불가사의부적: only super-effective hits land")
    var kec = duel(pika50, Mon(dex: 352, level: 50, female: false), [85]); let kecFrom = kec, kecB = kec.turn(.fight(85), &r); var kecRe = kecFrom; for bt in kecB { kecRe.apply(bt) }
    check(abilitySlots[352] == [16] && kecB.contains(.retype(.it, ["electric"])) && kec.theirs[0].typeList == ["electric"] && kecRe.theirs[0].typeList == ["electric"], "변색: it turns electric, and the replay knows")
    var d16 = duel(pika50, Mon(dex: 58, level: 30, female: false), [52]); d16.theirs[0].abilityOver = 18; let ff = d16.turn(.fight(52), &r)
    check(!ff.contains { if case .hit(.it, _, _, _, _) = $0 { return true }; return false } && d16.theirs[0].flashFire, "타오르는불꽃: fire is absorbed")
    var d17 = duel(pika50, Mon(dex: 135, level: 50, female: false), [85]); d17.theirs[0].hp = d17.theirs[0].maxHP / 2; let va = d17.turn(.fight(85), &r)
    check(abilitySlots[135] == [10] && va.contains { if case .heal(.it, _, _) = $0 { return true }; return false } && d17.theirs[0].hp > d17.theirs[0].maxHP / 2, "축전: electric moves heal it")
    var ohko = 0, sturdyKO = 0
    for _ in 0..<40 {
        var a = duel(lax50, Mon(dex: 74, level: 30, female: false), [12]); a.theirs[0].abilityOver = 5; _ = a.turn(.fight(12), &r); if !a.theirs[0].alive { sturdyKO += 1 }
        var c = duel(lax50, Mon(dex: 74, level: 30, female: false), [12]); c.theirs[0].abilityOver = 69; _ = c.turn(.fight(12), &r); if !c.theirs[0].alive { ohko += 1 }
    }
    check(sturdyKO == 0 && ohko > 10, "옹골참 stops one-hit KO moves (Gen IV)", "\(sturdyKO) \(ohko)")
    var d18 = duel(Mon(dex: 287, level: 30, female: false), Mon(dex: 19, level: 60, female: false), [33]), uses = 0
    for _ in 0..<2 { uses += d18.turn(.fight(33), &r).filter { if case .use(.me, _) = $0 { return true }; return false }.count }
    check(abilitySlots[287] == [54] && uses == 1, "게으름: every other turn")
    var d19 = duel(pika50, Mon(dex: 118, level: 30, female: false), [150]); d19.theirs[0].abilityOver = 33; let dry = d19.speed(.it); d19.sky = .rain
    check(d19.speed(.it) == dry * 2, "쓱쓱: 스피드 x2 in rain")
    var stat = 0; for _ in 0..<300 { var b = duel(rat, pika50, [33]); _ = b.turn(.fight(33), &r); if b.mine[0].status == .paralysis { stat += 1 } }
    check(abilitySlots[25] == [9] && (55...125).contains(stat), "정전기: 30 % on contact", "\(stat)")
    var cr = duel(pika50, rat, [33]), crits = 0; for _ in 0..<3200 { if cr.critical(.me, .it, moveTable[33]!) { crits += 1 } }
    check((140...260).contains(crits), "critical rate 1/16", "\(crits)")
    var wet = duel(Mon(dex: 7, level: 50, female: false), rat, [55]); var hiDry = 0, hiWet = 0
    for _ in 0..<400 { hiDry = max(hiDry, wet.calc(.me, .it, moveTable[55]!, power: 40, type: "water", eff: 1, crit: false)) }; wet.sky = .rain
    for _ in 0..<400 { hiWet = max(hiWet, wet.calc(.me, .it, moveTable[55]!, power: 40, type: "water", eff: 1, crit: false)) }
    check(Double(hiWet) >= Double(hiDry) * 1.4, "rain: water x1.5", "\(hiDry) \(hiWet)")

    // 7b new moves: the forget-one choice
    let ls25 = learnsets[25], pairs25: [(Int, Int)] = stride(from: 0, to: ls25.count, by: 2).map { (ls25[$0], ls25[$0 + 1]) }, next = pairs25.first { $0.0 > 12 && Moves.supported($0.1) }!
    var lw = Walk(); lw.companion = Mon(dex: 25, level: next.0 - 1, female: false); lw.companion.known = [84, 45, 39, 86].filter { $0 != next.1 }.prefix(4).map { $0 }
    lw.walk(expTable[growthRate[25]][next.0] - lw.companion.points, at: Date())
    check(lw.companion.level == next.0 && lw.companion.uid != nil && Array((lw.learning ?? []).prefix(2)) == [lw.companion.uid!, next.1], "a level-up by walking queues the new move", "\(lw.learning ?? [])")
    let lv = WalkerView(state: lw); lv.persist = false; lv.rng = Seeded(s: 12); lv.nextLearn(Date())
    if case .learn = lv.screen { lv.press(1); check(lv.state.companion.known?[0] == next.1 && lv.state.companion.moves.count == 4, "forget move 1 for the new one") } else { check(false, "4 moves known: the forget-one screen") }
    let before4 = lv.state.companion.known; lv.state.learning = [lv.state.id(-1)!, 85]; lv.screen = .learn(sel: 4); lv.press(1)
    check(lv.state.companion.known == before4 && lv.state.learning == [], "배우지 않는다 keeps the four")
    lv.state.companion.known = [84, 45]; lv.state.learning = [lv.state.id(-1)!, next.1]; lv.screen = .home; lv.nextLearn(Date())
    check(lv.state.companion.known == [84, 45, next.1], "a free slot: learned straight away")
    var bw = Walk(); bw.box = [Mon(dex: 16, level: 5, female: false), Mon(dex: 25, level: next.0, female: false)]; bw.box[1].known = [84, 45]
    bw.queueMoves(1, from: next.0 - 1); bw.box.remove(at: 0)
    check(bw.nextToLearn()?.ref == 0 && bw.nextToLearn()?.move == next.1, "a queued move follows its Pokémon when the box shifts")
    bw.box.removeAll(); check(bw.nextToLearn() == nil && bw.learning == [], "released: its queued moves are dropped")
    let bv = WalkerView(state: { var s = Walk(); s.bag = ["마비치료제", "상처약"]; return s }()); bv.persist = false; bv.rng = Seeded(s: 13)
    var bb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); bb.mine[0].status = .paralysis
    check(bv.battleItems(bb).map(\.name) == ["마비치료제"], "full HP: only the cure is offered")
    bv.screen = .bagBattle(bb, sel: 0); bv.press(1)
    if case .beats(let after, let bs, _, _) = bv.screen { check(after.mine[0].status == nil && bv.state.bag == ["상처약"] && bs.first == .note(.me, text: "마비치료제를 사용했다!"), "using a cure in battle takes it from the bag") } else { check(false, "using a cure in battle") }
    let ov = WalkerView(state: { var s = Walk(); s.owned = [94]; return s }()); ov.persist = false; ov.rng = Seeded(s: 15)
    ov.screen = .battle(Battle(wild: Mon(dex: 94, level: 30, female: false), companion: pika50), sel: 0); let om = ov.sideModel(Date())
    ov.screen = .battle(Battle(party: [pika50], trainer: "x", foes: [Mon(dex: 6, level: 30, female: false)]), sel: 0); let tm = ov.sideModel(Date())
    check(om?.foe.types == ["ghost", "poison"] && om?.foe.owned == true && tm?.foe.types == ["fire", "flying"] && tm?.foe.owned == false && om?.mine.types == [],
          "the panel shows theirs' types and whether that species is caught (wild and tower)")
    var live = Battle(wild: Mon(dex: 19, level: 30, female: false), companion: pika50); live.mine[0].moves = [85, 237]; live.mine[0].pp = [15, 15]; live.theirs[0].types = ["water"]
    ov.screen = .moves(live, sel: 0)
    if case .moves(let btns, _)? = ov.sideModel(Date())?.mode {
        check(btns[0].effect == 2 && btns[1].type == "dark" && btns[1].power == 70 && ov.sideModel(Date())?.foe.types == ["water"], "move hints use the types it has now (a watered 꼬렛: 10만볼트 ▲) and 잠재파워's real type", "\(btns)")
    } else { check(false, "move hints use the types it has now") }

    // 7c Battle Tower + shops
    w = Walk(); w.companion = Mon(dex: 25, level: 20, female: false); w.box = [Mon(dex: 16, level: 5, female: false), Mon(dex: 143, level: 30, female: false), Mon(dex: 19, level: 12, female: false)]
    check(w.party().map(\.ref) == [-1, 1, 2] && w.party().map(\.mon.dex) == [25, 143, 19], "party: companion + the two strongest")
    let legendSet = Set(courses.flatMap(\.legends) + [150, 250])
    let tf = w.towerFoes(&r); check(tf.foes.count == 3 && tf.foes.allSatisfy { (20...23).contains($0.level) && !legendSet.contains($0.dex) }, "tower foes: 3 non-legends at the party's level", "\(tf.foes)")
    var g: [Int] = []; for _ in 0..<8 { g.append(w.towerWin()) }
    check(g == [1, 1, 1, 1, 1, 1, 4, 2] && w.bp == 12 && w.towerBest == 8, "BP: 1 a win, +3 on the 7th, 2 a win after 7", "\(g)")
    w.towerEnd(); check(w.towerStreak == 0 && w.towerBest == 8, "a loss ends the streak, best kept")
    var up = w.box[1]; _ = up.gainBattleExp(50_000); w.writeBack([w.id(-1)!, w.id(1)!], [w.companion, up]); check(w.box[1].level > 30, "tower EXP goes back to the box")
    w.watts = 100; check(w.purchase(.init(kind: .item("슈퍼볼"), price: 40), 1, bp: false) != nil && w.watts == 60 && w.bag.last == "슈퍼볼" && w.purchase(.init(kind: .item("풀회복약"), price: 300), 1, bp: false) == nil, "W shop")
    check(w.purchase(.init(kind: .item("이상한사탕"), price: 8), 1, bp: true) != nil && w.bp == 4 && w.purchase(.init(kind: .item("이상한사탕"), price: 8), 1, bp: true) == nil, "BP exchange")
    w = Walk(); w.watts = 9998; check(w.buyLegend(0) == nil, "칠색조 needs the full 9,999 W")
    w.watts = 9999; check(w.buyLegend(0)?.dex == 250 && w.watts == 0 && w.caught.last?.level == 50 && w.buyLegend(0) == nil, "칠색조: 9,999 W, once")
    w.bp = 299; check(w.buyLegend(1) == nil, "뮤츠 needs 300 BP"); w.bp = 300
    check(w.buyLegend(1)?.dex == 150 && w.bp == 0 && w.legendBought(150) && (w.owned ?? []).contains(150), "뮤츠: 300 BP, once, in the dex")
    check((w.caught + w.box).filter { [150, 250].contains($0.dex) }.allSatisfy { $0.perfectIVs >= 3 }, "shop legends come with 3 IVs at 31")
    var pr = Seeded(s: 9); check((0..<60).allSatisfy { _ in Mon.wild(144, level: 50, perfect: 3, &pr).perfectIVs >= 3 } && (0..<60).map { _ in Mon.wild(16, level: 5, &pr).perfectIVs }.max()! < 4, "perfect: n sure 31s")
    check((0...10).map(Walk.chainPerfectIVs) == [0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4], "radar chains: 3 → 1V, 5 → 2V, 7 → 3V, 9 → 4V")

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
    check(hgssData.count == 493 * 6490, "hgss.bin in the bundle")
    check(iconData.count == 493 * 557 && (1...493).allSatisfy { d in (0..<1024).filter { iconPixel(d, $0 % 32, $0 / 32) != 0 }.count >= 20 }, "icons.bin: a box icon for every species")
    func opaque(_ d: Int, back: Bool) -> [(x: Int, y: Int)] { (0..<80).flatMap { y in (0..<80).map { (x: $0, y: y) } }.filter { spritePixel(d, back: back, $0.x, $0.y, shiny: false) != 0 } }
    var off: [Int] = []                                                                    // every frame stands on row 79; every shiny differs on 5%+ of it (422/423: PokeAPI's copies)
    for d in 1...493 { for back in [false, true] {
        var n = 0, diff = 0, bottom = -1
        for y in 0..<80 { for x in 0..<80 { let c = spritePixel(d, back: back, x, y, shiny: false); if c != 0 { n += 1; bottom = y; if c != spritePixel(d, back: back, x, y, shiny: true) { diff += 1 } } } }
        if bottom != 79 || diff * 20 < n { off.append(d) }
    } }
    check(off.isEmpty, "every sprite stands on its bottom row and has its own shiny colours", "\(off)")
    check(!opaque(25, back: true).isEmpty, "피카츄 has a back sprite")
    let blank = Set(courses.flatMap { $0.slots.map(\.dex) } + [25]).filter { opaque($0, back: false).count < 50 || opaque($0, back: true).count < 50 }
    check(blank.isEmpty, "every course Pokémon has front and back sprites", "\(blank)")
    let old = try? JSONDecoder().decode(Mon.self, from: Data(#"{"dex":25,"level":5,"female":false}"#.utf8))
    check(old == Mon(dex: 25, level: 5, female: false) && old?.shiny == nil, "pre-shiny saves still decode")
    let td = textDots("포켓 레이더"); check(td.joined().contains(true) && td.count == 11, "Korean text renders to 11-row dots", td.map { String($0.map { $0 ? "#" : "." }) }.joined(separator: "\n"))
    check(josa("피카츄", "을", "를") == "피카츄를" && josa("꼬렛", "을", "를") == "꼬렛을", "josa")

    // 9 UI flows: the real view, driven through press() / touch() / tick()
    func on(_ v: WalkerView, _ p: (Screen) -> Bool) -> Bool { p(v.screen) }
    var s0w = Walk(); s0w.watts = 100
    let v = WalkerView(state: s0w); v.persist = false; v.rng = Seeded(s: 14)
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
    var mr = Battle(party: [Mon(dex: 25, level: 30, female: false), Mon(dex: 143, level: 30, female: false)], trainer: "x", foes: [Mon(dex: 16, level: 30, female: false)])
    mr.mine[0].hp = 0; mr.mine[0].down = true; mr.mustReplace = true
    v.screen = .beats(mr, [.fainted(.me)], since: Date().addingTimeInterval(-30), from: mr); v.tick(nil)
    let picking = on(v) { if case .party(_, 1) = $0 { return true }; return false }; v.press(3)
    let stuck = on(v) { if case .party = $0 { return true }; return false }; v.press(1)
    check(picking && stuck && on(v) { if case .beats(let nb, let bs, _, _) = $0 { return bs.first == .sendOut(.me, 1) && nb.me == 1 }; return false }, "ours fainted: pick who's next (↩ can't skip it)")
    v.screen = .menu(0); v.press(3); check(on(v) { if case .home = $0 { return true }; return false }, "↩ on a menu page: home")
    // ↩ 뒤로: one step up; where an answer is due only the cursor moves; nothing that can't be undone
    let bk = WalkerView(state: { var s = Walk(); s.watts = 500; s.bp = 40; return s }()); bk.persist = false; bk.rng = Seeded(s: 51)
    func back(_ sc: Screen) -> Screen { bk.screen = sc; bk.press(3); return bk.screen }
    let wild = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: Mon(dex: 25, level: 20, female: false))
    let tw = Battle(party: [Mon(dex: 25, level: 20, female: false)], trainer: "x", foes: [Mon(dex: 16, level: 5, female: false)])
    func isBattle(_ s: Screen, _ opt: String) -> Bool { if case .battle(let b, let sel) = s { return bk.battleMenu(b)[sel] == opt }; return false }
    check(isBattle(back(.battle(wild, sel: 0)), "도망") && isBattle(back(.battle(tw, sel: 0)), "기권") && isBattle(back(.moves(wild, sel: 1)), "공격") && isBattle(back(.bagBattle(wild, sel: 0)), "도구"),
          "battle: ↩ puts the cursor on 도망 / 기권 (no instant escape or forfeit); from a sub-menu back onto its entry")
    check(isBattle(back(.say(["PP가 없다"], next: .moves(wild, sel: 0), since: Date())), "공격") == false && { if case .moves = bk.screen { return true }; return false }(),
          "a battle message: ↩ = ● (the fight doesn't vanish)")
    bk.state.towerStreak = 5; bk.towerRun = true; bk.screen = .battle(tw, sel: 3); bk.press(1)
    let askedForfeit = { if case .forfeit(_, false) = bk.screen { return true }; return false }(); bk.press(1)
    check(askedForfeit && isBattle(bk.screen, "기권") && bk.state.towerStreak == 5 && bk.towerRun, "기권 asks first; ● on 아니오 goes back, the streak stays")
    bk.screen = .battle(tw, sel: 3); bk.press(1); bk.press(2); bk.press(1)
    check(bk.state.towerStreak == 0 && !bk.towerRun, "… ▶ 예 ● gives up")
    bk.towerRun = true; bk.state.towerStreak = 2
    check({ if case .menu(9) = back(.tower) { return true }; return false }() && bk.towerRun && bk.state.towerStreak == 2, "tower lobby: ↩ to the menu, the run stays on")
    let radar = Screen.radar(bush: 1, cursor: 0, since: Date(), chain: 4)
    check({ if case .radar(_, _, _, 4) = back(radar) { return true }; return false }(), "radar: ↩ does nothing (the 10W and the chain stay)")
    check({ if case .learn(4) = back(.learn(sel: 1)) { return true }; return false }(), "learn: ↩ onto 배우지 않는다")
    check({ if case .menu(3) = back(.card(1)) { return true }; return false }() && { if case .menu(4) = back(.bag(0)) { return true }; return false }()
          && { if case .menu(6) = back(.dex(1, filter: 0, detail: false)) { return true }; return false }() && { if case .dex(1, 0, false) = back(.dex(1, filter: 0, detail: true)) { return true }; return false }() && { if case .dowse = back(.dowse(cursor: 0, prize: 2, tries: 2, hint: nil)) { return true }; return false }()
          && { if case .menu(8) = back(.shop(bp: true, sel: 0, qty: nil)) { return true }; return false }(), "card / bag / dex / shop list: ↩ to their menu page; dowsing: ↩ does nothing (the 3W round stays)")
    bk.state.box = [Mon(dex: 16, level: 5, female: false)]
    check({ if case .menu(5) = back(.box(0, act: nil, confirm: false)) { return true }; return false }() && { if case .box(0, nil, false, false) = back(.box(0, act: 1, confirm: true)) { return true }; return false }() && bk.state.box.count == 1
          && { if case .box(0, nil, false, true) = back(.box(0, act: 1, confirm: true, detail: true)) { return true }; return false }() && { if case .box(0, nil, false, false) = back(.box(0, act: nil, confirm: false, detail: true)) { return true }; return false }(),
          "box: ↩ from 놓아줄까? back (= 아니오), from a Pokémon's page to the grid, from the grid to the menu")
    bk.sideOn = true; bk.state.towerStreak = 5; bk.towerRun = true; bk.screen = .forfeit(tw, yes: false)
    check(!bk.touch(80, 56) && bk.state.towerStreak == 5, "with the side panel, an LCD tap in a fight answers nothing (it drags)")
    bk.sideOn = false; bk.screen = .forfeit(tw, yes: false); bk.clickCount = 1; _ = bk.touch(55, 56)
    check(bk.state.towerStreak == 5 && isBattle(bk.screen, "기권"), "no panel: a tap on the drawn 아니오 is 아니오")
    bk.screen = .battle(wild, sel: 0)
    let battleMenuItems = bk.buildMenu().items
    check(battleMenuItems.contains { $0.title.hasPrefix("⚔ 배틀 중") } && battleMenuItems.first { $0.title.hasPrefix("코스") }?.submenu?.items.allSatisfy { $0.action == nil } == true,
          "mid-battle the menu's jump-away actions wait (no one-click escape)")
    let hider = WalkerView(state: Walk()); hider.persist = false; hider.screen = .say(["PP가 없다"], next: .moves(wild, sel: 0), since: Date())
    let midFight = hider.inBattle; hider.screen = .say(["샀다"], next: .shop(bp: false, sel: 0, qty: nil), since: Date())
    check(midFight && !hider.inBattle, "inBattle covers a fight's messages (so hiding to the menu bar keeps the fight), not a shop's")
    check({ if case .evolve = back(.evolve(from: Mon(dex: 1, level: 16, female: false), to: Mon(dex: 2, level: 16, female: false), since: Date())) { return true }; return false }(), "an evolution isn't cut short by ↩")
    v.state.box = [Mon(dex: 16, level: 20, female: false)]; let wBefore = v.state.watts
    v.screen = .box(0, act: nil, confirm: false); v.press(1); v.press(1); v.press(2); v.press(1); v.press(2); v.press(1)
    check(v.state.box.isEmpty && v.state.watts == wBefore + 10, "box: ● its page, ● 놓아주기 예 releases for level / 2 W")
    v.state.box = [Mon(dex: 1, level: 7, female: false)]; v.screen = .box(0, act: nil, confirm: false); v.press(1); v.press(1); v.press(1)
    check(v.state.companion.dex == 1 && v.state.box.first?.dex == 25, "box: ● its page, ● 함께 swaps the companion")
    v.screen = .menu(6); v.press(1); check(on(v) { if case .dex = $0 { return true }; return false }, "menu 도감 opens the dex")
    _ = v.touch(80, 30); _ = v.touch(10, 30); _ = v.touch(48, 30); check(on(v) { if case .dex(_, _, true) = $0 { return true }; return false }, "dex taps: ▶ ◀, then ● opens the entry page")

    // the 도감 / 상자 grids on the pane
    let gv = WalkerView(state: { var s = Walk(); s.owned = [1, 4, 25]; s.seen = [1, 4, 7, 25, 94]
        s.box = [Mon(dex: 16, level: 30, female: false), Mon(dex: 1, level: 5, female: false), Mon(dex: 16, level: 8, female: false, shiny: true)]; return s }())
    gv.persist = false; gv.rng = Seeded(s: 71)
    func gs(_ p: (Screen) -> Bool) -> Bool { p(gv.screen) }
    let here = gv.state.here
    let onCourse: [Int] = here.slots.map(\.dex) + here.extra.map(\.dex) + here.guests + here.legends
    check(gv.dexList(0) == Array(1...493) && gv.dexList(1) == [1, 4, 25] && gv.dexList(2) == [7, 94] && Set(gv.dexList(3)) == Set(onCourse),
          "dex tabs: 전체 (all 493) / 잡음 / 못 잡음 (seen, not caught) / 이 코스")
    gv.screen = .menu(6); gv.press(1)
    check(gs { if case .dex(let d, 0, false) = $0 { return d == gv.state.companion.dex }; return false } && gv.paneContent(Date()).grid?.sel != nil, "도감 opens on the grid, at the companion")
    gv.screen = .dex(25, filter: 0, detail: false); gv.press(2); gv.press(0); gv.press(0)
    check(gs { if case .dex(24, 0, false) = $0 { return true }; return false }, "◀ ▶ step one along the tab")
    gv.gridStep(30); let paged = gs { if case .dex(54, _, _) = $0 { return true }; return false }
    gv.screen = .dex(490, filter: 0, detail: false); gv.gridStep(30)
    check(paged && gs { if case .dex(493, _, _) = $0 { return true }; return false }, "a page = 30 on, stopping at the end")
    gv.gridTap(4201); let round = gs { if case .dex(1, _, _) = $0 { return true }; return false }; gv.gridTap(4200)
    check(round && gs { if case .dex(493, _, _) = $0 { return true }; return false }, "the last page's ▶ goes round to #1, the first page's ◀ to the last")
    gv.screen = .dex(493, filter: 0, detail: false)
    let pg = gv.paneContent(Date()).grid
    check(pg?.page == 17 && pg?.pages == 17 && pg?.cells.count == 13 && pg?.sel == 12 && pg?.cells.first?.dex == 481, "the last page: 481-493, the pick in its cell")
    gv.gridTap(4101); check(gs { if case .dex(1, 1, false) = $0 { return true }; return false }, "a tab: the pick moves onto it when it isn't on it")
    gv.gridTap(10002); check(gs { if case .dex(25, 1, false) = $0 { return true }; return false }, "a cell: picks it")
    gv.gridTap(10002); check(gv.paneContent(Date()).dex?.num == 25, "the picked one again: its entry page")
    gv.press(2); check(gs { if case .dex(1, 1, true) = $0 { return true }; return false }, "▶ on the entry page: the next on the tab, wrapping")
    gv.press(3); let toGrid = gs { if case .dex(1, 1, false) = $0 { return true }; return false }; gv.press(3)
    check(toGrid && gs { if case .menu(6) = $0 { return true }; return false }, "↩: the entry page → the grid → the menu")
    gv.state.owned = [1, 4, 7, 25, 94]; gv.screen = .dex(7, filter: 0, detail: false); gv.gridTap(4102)
    check(gv.paneContent(Date()).grid.map { $0.cells.isEmpty && $0.sel == nil && $0.empty == "모두 잡았다!" } == true && gv.compose(Date()).runs.contains { $0.s == "모두 잡았다!" }, "an empty tab says so, on the pane and the LCD")
    gv.press(1); check(gs { if case .dex(_, 2, false) = $0 { return true }; return false } && gv.paneContent(Date()).dex == nil, "● on an empty tab: no entry page for a pick that isn't on it")
    gv.screen = .menu(5); gv.press(1)
    check(gv.boxOrder == [1, 0, 2] && gs { if case .box(1, nil, false, false) = $0 { return true }; return false }, "상자 opens on the grid's first, 번호순 (then the higher level)")
    gv.gridTap(4101); check(gv.boxOrder == [0, 2, 1] && gs { if case .box(1, nil, false, false) = $0 { return true }; return false }, "레벨순 tab: the order changes, the pick stays")
    gv.press(2); check(gs { if case .box(0, nil, false, false) = $0 { return true }; return false }, "▶ follows the grid's order, wrapping")
    gv.boxSort = 3; check(gv.boxOrder == [2, 1, 0], "최근: the last to arrive first"); gv.boxSort = 1
    gv.boxSort = 2; gv.state.box[1].ivs = [31, 31, 31, 0, 0, 0]; check(gv.boxOrder.first == 1 && gv.paneContent(Date()).grid?.cells.first?.v3 == true, "V순: 3V first, marked"); gv.state.box[1].ivs = nil; gv.boxSort = 1
    let shinyCell = gv.paneContent(Date()).grid?.cells[1].shiny == true
    gv.gridTap(10001); let boxPicked = gs { if case .box(2, nil, false, false) = $0 { return true }; return false }; gv.gridTap(10001); gv.gridTap(10001)
    check(boxPicked && shinyCell && gs { if case .box(2, nil, false, true) = $0 { return true }; return false } && gv.paneContent(Date()).mon != nil,
          "a cell picks, the picked one again opens its page, and stays there (★ = 이로치)")
    gv.state.box[2].nature = 3; gv.state.box[2].ivs = [31, 20, 31, 0, 12, 31]; gv.state.box[2].evs = [252, 0, 6, 0, 0, 252]; gv.state.box[2].hyper = [3]
    let mm = gv.paneContent(Date()).mon
    check(mm?.nature == natures[3].name && mm?.up == natures[3].up && mm?.down == natures[3].down && mm?.natureNote.contains("10% 높고") == true && mm?.ivs == [31, 20, 31, 31, 12, 31]
          && mm?.evTotal == 510 && mm?.v == 4 && mm?.abilityNote.isEmpty == false && mm?.ability == gv.state.box[2].abilityName,
          "a Pokémon's page: its nature (which stats, what it means), its ability and what it does, IVs as battles use them (특훈 = 31), EVs and their total")
    gv.state.box[2].nature = 0; check(gv.paneContent(Date()).mon.map { $0.up == nil && $0.natureNote.contains("영향을 주지 않는") } == true, "a neutral nature says it changes nothing")
    let fitAll = natures.indices.allSatisfy { i in gv.state.box[2].nature = i; return gv.paneContent(Date()).mon.map { width($0.natureNote, font(9)) <= 162 * K } ?? false }; gv.state.box[2].nature = 0
    check(fitAll, "every nature's note fits its line on the page")
    let od = [5, 12, 31, 57].map { abilityDescs[$0] ?? "" }
    check(od[0] == "일격필살 기술을 받지 않는다." && od[1] == "헤롱헤롱 상태가 되지 않는다." && od[2].contains("싱글 배틀에서는 효과가 없다") && od[3].contains("싱글"), "ability notes say what they do in Gen IV singles (not X/Y's later effects)")
    gv.gridTap(4401); let asking = gv.paneContent(Date()).mon.map { $0.confirm && $0.sel == 0 } == true; gv.gridTap(4402)
    check(asking && gs { if case .box(2, nil, false, true) = $0 { return true }; return false } && gv.paneContent(Date()).mon?.sel == nil,
          "its page's 놓아주기 asks first, 아니오 picked (red = what ● does); 아니오 stays")
    gv.screen = .box(0, act: 2, confirm: false, detail: true); gv.press(2); let wrapped = gs { if case .box(0, 0, false, true) = $0 { return true }; return false }
    gv.press(2); gv.press(1); gv.press(2); gv.press(1)                                                  // 레벨순 [Lv.30, Lv.8, Lv.5]: the Lv.30 goes; next in the grid = the Lv.8 (box[1] now), not box[0]
    check(wrapped && gv.state.box.map(\.level) == [5, 8] && gs { if case .say(_, .box(1, nil, false, true), _) = $0 { return true }; return false } && gv.paneContent(Date()).mon != nil,
          "놓아주기 예 on its page: the next in the grid's page comes up, through the message too")
    gv.state.box = [Mon(dex: 131, level: 8, female: false), Mon(dex: 332, level: 10, female: false)]
    check(gv.state.box[0].points > gv.state.box[1].points && gv.boxOrder == [1, 0], "레벨순 is by level (a slow-growing Lv.8 has more EXP than a Lv.10)")
    gv.state.box = [Mon(dex: 16, level: 5, female: false), Mon(dex: 19, level: 5, female: false)]; gv.state.pair(0); gv.boxSort = 3
    check(gv.state.box.map(\.dex) == [19, 25] && gv.boxOrder.first == 1, "함께: the old companion goes to the box's end, first on 최근")

    v.state.box = (1...120).map { Mon(dex: $0 * 4 % 493 + 1, level: 5, female: false, shiny: $0 % 17 == 0 ? true : nil) }
    let walkMenu = v.buildMenu().items.first { $0.title.hasPrefix("함께 걷기") }?.submenu
    v.state.box += (0..<40).map { Mon(dex: 29, level: 1 + $0 % 25, female: $0 % 2 == 0) }
    let nido = v.buildMenu().items.first { $0.title.hasPrefix("함께 걷기") }?.submenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title.hasPrefix("니드런♀") }?.submenu
    check((nido?.items.count ?? 99) <= 12 && nido?.items.contains { $0.title.hasPrefix("그 밖") } == true && nido?.items.last?.title.hasPrefix("중복 놓아주기") == true,
          "40 니드런♀: ≤ 12 rows, the rest under 그 밖, and 중복 놓아주기", "\(nido?.items.count ?? -1)")
        check((walkMenu?.items.count ?? 99) <= 26 && walkMenu?.items.contains { $0.title.hasPrefix("★ 이로치") } == true, "big box: 함께 걷기 stays short (recent, shinies, dex ranges)", "\(walkMenu?.items.count ?? -1)")

    // 7e 3V: radar chains, the menu's marks, 중복 놓아주기 by V
    let cv = WalkerView(state: Walk()); cv.persist = false; cv.rng = Seeded(s: 31); cv.state.watts = 100
    let lc = courses.firstIndex { !$0.legends.isEmpty }!, lv2 = WalkerView(state: { var s = Walk(); s.course = lc; return s }()); lv2.persist = false
    var legendV: [Int] = []
    for k in 0..<400 where legendV.count < 3 {                                                     // a legend at chain 0: 3V from being a legend, not from the chain
        lv2.rng = Seeded(s: UInt64(k)); lv2.screen = .radar(bush: 0, cursor: 0, since: Date().addingTimeInterval(-2), chain: 0); lv2.press(1)
        if case .beats(let b, _, _, _) = lv2.screen, courses[lc].legends.contains(b.wild.dex) { legendV.append(b.wild.perfectIVs) }
    }
    check(legendV.count == 3 && legendV.allSatisfy { $0 >= 3 }, "a legend course's radar legend has 3 IVs at 31 (chain 0)", "\(legendV)")
    cv.screen = .radar(bush: 2, cursor: 2, since: Date().addingTimeInterval(-2), chain: 7); cv.press(1)
    check(on(cv) { if case .beats(let b, _, _, _) = $0 { return b.wild.perfectIVs >= 3 }; return false }, "a chain-7 radar find has 3 IVs at 31")
    func withIVs(_ dex: Int, _ iv: [Int], level: Int = 20, shiny: Bool = false) -> Mon { var m = Mon(dex: dex, level: level, female: false, shiny: shiny ? true : nil); m.ivs = iv; return m }
    let v3 = withIVs(16, [31, 31, 31, 5, 5, 5]), v1 = withIVs(16, [31, 5, 5, 5, 5, 5], level: 40), v2 = withIVs(16, [31, 31, 0, 0, 0, 0], level: 10)
    var dw = Walk(); dw.box = [v1, v2, v3, withIVs(16, [0, 0, 0, 0, 0, 0], level: 60, shiny: true), withIVs(16, [3, 3, 3, 3, 3, 3], level: 90), withIVs(19, [0, 0, 0, 0, 0, 0])]
    check(dw.duplicates(of: 16) == [0, 1, 4], "중복 놓아주기: the 이로치, every 3V+ and the best stay; the rest go", "\(dw.duplicates(of: 16))")
    dw.box.remove(at: 2); check(dw.duplicates(of: 16) == [0, 3], "no 3V: the 2V is the one kept over higher levels", "\(dw.duplicates(of: 16))")
    var ow = Walk(); ow.box = [Mon(dex: 16, level: 60, female: false), withIVs(16, [30, 30, 30, 30, 30, 30], level: 5)]
    check(ow.duplicates(of: 16) == [1], "same V: the higher level stays (an old Lv.60 isn't traded for a fresh catch's IV total)")
    let mv = WalkerView(state: { var s = Walk(); s.box = [v3, v1]; s.companion = withIVs(25, [31, 31, 31, 31, 0, 0]); return s }()); mv.persist = false
    let walkItems = mv.buildMenu().items.first { $0.title.hasPrefix("함께 걷기") }?.submenu?.items ?? []
    let pidgey = walkItems.first { $0.title.hasPrefix("구구") }, rowsIn = pidgey?.submenu?.items ?? []
    let r3 = rowsIn.first { $0.title.contains("3V") }, r1 = rowsIn.first { $0.title.contains("1V") }
    let gold = r3?.attributedTitle.map { $0.attribute(.foregroundColor, at: ($0.string as NSString).range(of: "3V").location, effectiveRange: nil) as? NSColor } ?? nil
    check(r3 != nil && gold == WalkerView.vColor && r1 != nil && r1?.attributedTitle == nil && pidgey?.title.contains("최고 3V") == true && walkItems.first?.title.hasSuffix("4V") == true,
          "menu: 1V / 2V plain, 3V+ in gold, the species row flags its best, the companion shows its V", "\(walkItems.first?.title ?? "") \(rowsIn.map(\.title))")
    check(mv.statLines({ var m = v1; m.hyper = [2]; return m }())[1].contains("방어 5→31") && mv.statLines(v3)[1].hasPrefix("개체값 · 3V"), "the numbers stay; a 특훈 IV reads 5→31")
    let bigV = WalkerView(state: { var s = Walk(); s.box = (1...14).map { Mon(dex: $0, level: 5, female: false) } + [withIVs(20, [31, 31, 31, 31, 0, 0])]; s.bag = []; return s }()); bigV.persist = false
    let bigItems = bigV.buildMenu().items.first { $0.title.hasPrefix("함께 걷기") }?.submenu?.items ?? []
    check(bigItems.contains { $0.title == "3V 이상 · 1" && $0.attributedTitle != nil } && bigItems.contains { $0.title.hasPrefix("No.001–050") && $0.title.hasSuffix("최고 4V") },
          "big box: a 3V 이상 list, and the dex range flags its best", "\(bigItems.map(\.title))")
    // 7f the shops: in the walker's menu, several at once
    check(!bigV.buildMenu().items.contains { $0.title.hasPrefix("상점") || $0.title.hasPrefix("BP 교환소") || $0.title.hasPrefix("교환소") }, "the shops left the right-click menu")
    var sw = Walk(); sw.watts = 5000; sw.bp = 200; sw.companion = Mon(dex: 133, level: 20, female: false)             // 이브이: it has evolution items to sell
    let wW = sw.wares(bp: false, shells: []), wB = sw.wares(bp: true, shells: [(name: "배틀 골드", bp: 40)])
    check(wW.count == Walk.shop.count + sw.evolutionItems().count + 1 && wW.last?.kind == .legend(0) && wW.contains { $0.kind == .item("불꽃의돌") && $0.price == Walk.evoItemPrice }
          && wB.count == Walk.bpShop.count + 2 && wB.contains { $0.kind == .shell("배틀 골드") } && wB.last?.kind == .legend(1), "상점: goods + the companion's evolution items + 칠색조; BP 교환소: goods + 배틀 골드 + 뮤츠")
    let mochi = wW.first { $0.kind == .item("순백떡") }!, cap = wB.first { $0.kind == .item("금색병뚜껑") }!
    check(sw.canBuy(mochi, bp: false) == 25 && sw.canBuy(Walk.Ware(kind: .item("해독제"), price: 10), bp: false) == 99 && sw.canBuy(cap, bp: true) == 1 && sw.canBuy(wW.last!, bp: false) == 0,
          "how many: what the money covers, at most 99; 칠색조 needs 9,999W")
    check(sw.purchase(mochi, 3, bp: false) == .items("순백떡", 3) && sw.watts == 4400 && sw.count("순백떡") == 3 && sw.purchase(mochi, 23, bp: false) == nil && sw.watts == 4400,
          "3 순백떡 at once: -600W; more than the money covers: nothing happens")
    check(sw.purchase(wB[Walk.bpShop.count], 1, bp: true) == .shell("배틀 골드") && sw.bp == 160 && sw.canBuy(wB[Walk.bpShop.count], bp: true) == 0 && sw.purchase(wB[Walk.bpShop.count], 1, bp: true) == nil,
          "once-only (a device colour): bought once, then 보유")
    let shopV = WalkerView(state: { var s = Walk(); s.watts = 1000; s.bp = 30; return s }()); shopV.persist = false; shopV.rng = Seeded(s: 41)
    shopV.screen = .menu(9); shopV.press(1); let tower = on(shopV) { if case .tower = $0 { return true }; return false }
    shopV.screen = .menu(7); shopV.press(1)
    let opened = on(shopV) { if case .shop(false, 0, nil) = $0 { return true }; return false }
    shopV.press(2); shopV.press(1); shopV.press(2); shopV.press(2)                              // row 1 (좋은상처약 60W), how many: 3
    let three = on(shopV) { if case .shop(false, 1, 3?) = $0 { return true }; return false }
    shopV.press(1)
    check(tower && opened && three && shopV.state.count("좋은상처약") == 3 && shopV.state.watts == 820 && on(shopV) { if case .say(_, .shop(false, 1, nil), _) = $0 { return true }; return false },
          "menu → 상점: ▶ a row, ● how many, ▶▶ 3, ● buys 3 at once and goes back to the list")
    shopV.screen = .shop(bp: false, sel: 0, qty: 1); shopV.shopStep(10); let ten = on(shopV) { if case .shop(_, _, 11?) = $0 { return true }; return false }
    shopV.shopStep(nil); let most = on(shopV) { if case .shop(_, _, 41?) = $0 { return true }; return false }     // 820W / 20W
    shopV.press(0); shopV.press(3); let back = on(shopV) { if case .shop(false, 0, nil) = $0 { return true }; return false }
    check(ten && most && back, "how many: +10 (↑), 최대, and ↩ back to the list")
    shopV.screen = .shop(bp: true, sel: 0, qty: nil); shopV.shopTap(2100 + Walk.bpShop.firstIndex { $0.item == "은색병뚜껑" }!)
    let sm = shopV.shopModel()
    check(sm?.title == "BP 교환소" && sm?.qty == 1 && sm?.most == 1 && sm?.total == "25BP" && sm?.rows[sm!.sel].note.contains("특훈") == true,
          "the shop panel: a row click picks it (how many 1), with what it does and the total", "\(String(describing: sm))")
    shopV.shopTap(2005); check(shopV.state.count("은색병뚜껑") == 1 && shopV.state.bp == 5, "the panel's 구매 buys it")
    check(shopV.shopModel()?.hint.contains("받았다") == true && shopV.shopModel()?.qty == nil, "the panel stays up through the shop's message (shown in its box)")
    // a legend: how many, then 정말? (아니오 first), and never by a double-click or a held key
    let lg = WalkerView(state: { var s = Walk(); s.watts = 9999; return s }()); lg.persist = false; lg.rng = Seeded(s: 42)
    lg.screen = .shop(bp: false, sel: 0, qty: nil); lg.press(0); lg.press(1); lg.press(1)                                  // ◀ wraps to 칠색조, ● how many, ●
    let asked = on(lg) { if case .shopConfirm(false, _, false) = $0 { return true }; return false }
    lg.press(1); check(asked && lg.state.watts == 9999 && on(lg) { if case .shop(false, _, nil) = $0 { return true }; return false }, "칠색조: ◀ ● ● asks, and ● on 아니오 buys nothing")
    lg.press(1); lg.press(1); lg.press(2); lg.press(1)
    check(lg.state.watts == 0 && lg.state.legendBought(250), "… and ▶ 예 ● brings it")
    let dc = WalkerView(state: { var s = Walk(); s.watts = 1000; return s }()); dc.persist = false; dc.rng = Seeded(s: 43)
    dc.screen = .shop(bp: false, sel: 0, qty: nil); dc.clickCount = 1; _ = dc.touch(48, 20); dc.clickCount = 2; _ = dc.touch(48, 20)   // double-click on the picked row
    let rowTap = on(dc) { if case .shop(false, 0, 1?) = $0 { return true }; return false }
    dc.clickCount = 2; _ = dc.touch(48, 30); check(rowTap && dc.state.watts == 1000, "LCD: a double-click opens how-many at most, its 2nd click never buys")
    let heldReturn = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: true, keyCode: 36)!
    dc.keyDown(with: heldReturn); check(dc.state.watts == 1000, "a held return doesn't buy")
    dc.clickCount = 1; dc.shopStep(10); dc.shopRow(1); check(on(dc) { if case .shop(false, 1, nil) = $0 { return true }; return false }, "scrolling the panel moves a row and leaves how-many (never the amount)")
    dc.screen = .shop(bp: false, sel: 0, qty: nil); check(!dc.touch(48, 63) && dc.shopModel()?.hint.contains("●") == true, "the LCD's bottom dot row isn't a hidden 6th row; the panel says what ● does")
    dc.screen = .shop(bp: false, sel: dc.wares(false).count - 1, qty: nil); check(dc.shopModel()?.hint == "W가 부족해요 · 9,999W 필요", "the panel says why a row can't be bought", "\(dc.shopModel()?.hint ?? "")")
    // 7g the Poké Ball card: the LCD 2 pt a dot at 보통, the keys on the band, the page under it growing down per screen
    let size0 = SIZE; SIZE = 2
    check(PX == 2 && K == 1 && devSize == NSSize(width: 216, height: 199) && lcdRect == NSRect(x: 12, y: 27, width: 192, height: 128),
          "보통: a 216 x 199 card, the LCD 192 x 128 (2 pt a dot: whole pixels on a 1x screen)", "\(devSize) \(lcdRect)")
    check(buttons.count == 4 && buttons.allSatisfy { $0.c.y == Layout.seam && $0.c.x - $0.r >= 0 && $0.c.x + $0.r <= Layout.w } && buttons[1].r > buttons[0].r && buttons.map(\.c.x) == buttons.map(\.c.x).sorted(),
          "◀ ● ▶ ↩ on the band, ● the ball's own bigger button")
    let gw = WalkerView(state: Walk()); gw.persist = false; gw.statusOpen = false
    gw.refreshPane(Date(), force: true); let idleH = gw.frame.height
    gw.screen = .dex(25, filter: 0, detail: false); gw.refreshPane(Date(), force: true); let gridH = gw.frame.height
    gw.screen = .battle(wild, sel: 0); gw.refreshPane(Date(), force: true); let fightH = gw.frame.height, hudUp = gw.hud == nil
    gw.screen = .home; gw.statusOpen = true; gw.refreshPane(Date(), force: true)
    check(idleH == 199 && gridH == 422 && fightH == 311 && gw.frame.height == 354 && gw.frame.width == 216 && gw.page.frame.minY == Layout.pane && hudUp,
          "the card grows down to the page: idle 199, battle 311, a grid 422, the status sheet 354 (the page under the band)", "\(idleH) \(gridH) \(fightH) \(gw.frame)")
    SIZE = 3; check(PX == 3 && 422 * K < 850, "크게: 3 pt a dot, its tallest page still under a 13-inch screen's height"); SIZE = size0
    let pv = WalkerView(state: { var s = Walk(); s.box = [Mon(dex: 16, level: 5, female: false)]; return s }()); pv.persist = false; pv.rng = Seeded(s: 61)
    func kind(_ sc: Screen) -> String {
        pv.screen = sc; let c = pv.paneContent(Date())
        return c.battle != nil ? "battle" : c.dex != nil ? "dex" : c.grid != nil ? "grid" : c.mon != nil ? "mon" : c.shop != nil ? "shop" : c.menu.map { "menu\($0.sel)" } ?? (c.status != nil ? "status" : "none")
    }
    pv.statusOpen = false; let shut = kind(.home); pv.statusOpen = true
    check(shut == "none" && kind(.home) == "status" && kind(.box(0, act: nil, confirm: false, detail: true)) == "mon" && kind(.menu(3)) == "menu3" && kind(.battle(wild, sel: 0)) == "battle" && kind(.shop(bp: false, sel: 0, qty: nil)) == "shop" && kind(.dex(1, filter: 0, detail: true)) == "dex"
          && kind(.dex(1, filter: 0, detail: false)) == "grid" && kind(.box(0, act: nil, confirm: false)) == "grid",
          "the pane: nothing on 홈 until ⌄ opens the status sheet, 메뉴 tiles on the menu, the battle / 상점 pages, 도감 / 상자 grids, the dex entry, a box Pokémon's page")
    check(kind(.say(["기술의 남은", "PP가 없다!"], next: .moves(wild, sel: 0), since: Date())) == "battle" && kind(.say(["W가 부족하다"], next: .menu(0), since: Date())) == "menu0"
          && pv.paneContent(Date()).menu != nil, "a fight's / a menu page's message keeps its page up")
    pv.screen = .say(["기술의 남은", "PP가 없다!"], next: .moves(wild, sel: 0), since: Date()); check(pv.sideModel(Date())?.message == "기술의 남은 PP가 없다!", "… with the message in the battle page's box")
    let grown = WalkerView.onScreen(NSRect(x: 2248, y: 24 + 288 - 376, width: 584, height: 376), in: NSRect(x: 0, y: 0, width: 2560, height: 1410))
    check(grown == NSRect(x: 1976, y: 0, width: 584, height: 376), "an old device at the bottom-right corner grows into the screen, not onto the next one", "\(grown)")
    pv.screen = .menu(0); pv.menuTap(5); let picked = { if case .menu(5) = pv.screen { return true }; return false }(); pv.menuTap(5)
    check(picked && { if case .box = pv.screen { return true }; return false }(), "메뉴 page: a click picks the page, a click on the picked one opens it")
    let stm = pv.statusModel(); check(stm.level == "Lv.5" && stm.numbers.count == 3 && stm.rows.count == 3 && stm.exp >= 0 && stm.exp <= 1, "the status sheet: level, EXP to next, today / W / total, egg / tower / dex")
    print(failed == 0 ? "PASS \(total) checks" : "FAIL \(failed)/\(total)")
    return failed == 0
}
