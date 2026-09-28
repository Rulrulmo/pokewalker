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
    w.pair(0, &r); check(w.companion.dex == 4 && w.box[0].dex == 25, "pair swaps the companion with the box")
    check(Walk().unlocked(1) && !Walk().unlocked(2), "courses unlock by lifetime watts")

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

    // 8 data + art
    check(courses.count == 20 && courses.allSatisfy { $0.slots.count == 6 && $0.items.count == 10 }, "20 courses x 6 slots x 10 items")
    check(courses.map(\.watts) == courses.map(\.watts).sorted(), "courses unlock in order")
    check(monNames.count == 494 && monTypes.count == 494 && monNames[25] == "피카츄", "493 names + types")
    check(spriteData.count == 493 * 2 * 768, "sprites.bin in the bundle")
    let blank = Set(courses.flatMap { $0.slots.map(\.dex) } + [25]).filter { d in !(0..<48).contains { y in (0..<64).contains { spriteShade(d, 0, $0, y) > 0 } } }
    check(blank.isEmpty, "every course Pokémon has a sprite", "\(blank)")
    let td = textDots("포켓 레이더"); check(td.joined().contains(true) && td.count == 11, "Korean text renders to 11-row dots", td.map { String($0.map { $0 ? "#" : "." }) }.joined(separator: "\n"))
    check(josa("피카츄", "을", "를") == "피카츄를" && josa("꼬렛", "을", "를") == "꼬렛을", "josa")

    print(failed == 0 ? "PASS \(total) checks" : "FAIL \(failed)/\(total)")
    return failed == 0
}
