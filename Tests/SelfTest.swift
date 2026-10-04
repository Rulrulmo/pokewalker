import Foundation
#if os(macOS)
import AppKit                                                                                     // the Mac shell's own checks: its menu's colour, keys through the view, the window's geometry
#endif

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
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-selftest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
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
    var s1 = s0; s1.watts = 120; var s2 = s0; s2.watts = 340
    Store.save(s1, file: f, bak: b); Store.save(s2, file: f, bak: b)
    let signedOK = Store.loadChecked(file: f, bak: b, signedBefore: true)
    let edited = (try? String(contentsOf: f, encoding: .utf8))?.replacingOccurrences(of: "\"watts\":340", with: "\"watts\":9999") ?? ""; try? edited.write(to: f, atomically: true, encoding: .utf8)
    let caught = Store.loadChecked(file: f, bak: b, signedBefore: true)
    func aside(_ why: String) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []).filter { $0.hasPrefix("state.\(why)-") && $0.hasSuffix(".json") } }
    func keeps(_ why: String, _ text: String) -> Bool { aside(why).contains { (try? String(contentsOf: tmp.appendingPathComponent($0), encoding: .utf8))?.contains(text) == true } }
    let editedKept = keeps("rejected", "\"watts\":9999") && !FileManager.default.fileExists(atPath: f.path)
    try? edited.write(to: f, atomically: true, encoding: .utf8)                                    // the edited one again, without a .sig (it went aside with its file)
    let legacy = Store.loadChecked(file: f, bak: b, signedBefore: false), stripped = Store.loadChecked(file: f, bak: b, signedBefore: true)
    check(signedOK.walk == s2 && !signedOK.tampered && edited.contains("9999") && caught.walk == s1 && caught.tampered && legacy.walk.watts == 9999 && !legacy.tampered && stripped.walk == s1 && stripped.tampered,
          "a signed save loads; edited by hand (or its .sig deleted) the last save the app made comes back; unsigned is fine before this machine has signed")
    check(editedKept, "a save that isn't loaded is kept aside (state.rejected-…), out of the next saves' way")
    var s3 = s1; s3.watts = 777; Store.save(s3, file: f, bak: b)                                    // the first save after: no state.json to rotate
    check(Store.load(file: tmp.appendingPathComponent("none.json"), bak: b) == s1, "a save with state.json set aside leaves the good bak alone")
    Store.save(s3, file: f, bak: b)
    for u in [f, b] { try? ((try? String(contentsOf: u, encoding: .utf8)) ?? "").replacingOccurrences(of: "\"watts\":777", with: "\"watts\":8888").replacingOccurrences(of: "\"watts\":120", with: "\"watts\":8888").write(to: u, atomically: true, encoding: .utf8) }
    let rejectedBefore = aside("rejected").count, bothOff = Store.loadChecked(file: f, bak: b, signedBefore: true)
    Store.save(bothOff.walk, file: f, bak: b); Store.save(bothOff.walk, file: f, bak: b)            // launch saves twice: these used to write over both
    check(bothOff.walk == Walk() && bothOff.tampered && aside("rejected").count == rejectedBefore + 2 && aside("rejected").contains { $0.hasSuffix(".bak.json") } && keeps("rejected", "\"watts\":8888"),
          "save and bak both edited: a fresh walker, both kept aside (not saved over)", "\(aside("rejected"))")
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
    var ck = Walk(); ck.counter = 100; ck.boot = 7; ck.sync(counter: 5_000, boot: 7, at: at(10)); let ckFirst = ck.total; ck.sync(counter: 5_030, boot: 7, at: at(10))
    check(ckFirst == 0 && ck.total == 30 && ck.counterKind == Walk.counterNow, "a save from before 1.9 (clicks counted once): its first poll only re-baselines")
    w.sync(counter: 1250, boot: 7, at: at(10)); check(w.total == 250, "counter growth = steps")
    w.sync(counter: 40, boot: 7, at: at(10)); check(w.total == 250 && w.counter == 40, "counter went backwards => re-baseline")
    w.sync(counter: 900, boot: 8, at: at(10)); check(w.total == 250 && w.boot == 8, "new boot => re-baseline")
    w.syncedAt = at(10).timeIntervalSinceReferenceDate - 3600; w.sync(counter: 10_900, boot: 8, at: at(10), away: true)
    check(w.total == 250 + 3000 && w.counter == 10_900, "typed while quit: at most 3,000 an hour count (a macro left on all night counts little)", "\(w.total)")
    w.today = Walk.dayCap - 10; check(w.roomToday(500) == 10 && w.roomToday(5) == 5, "at most 100,000 steps a day count")
    func hoOh(_ shiny: Bool = false, lv: Int = 50) -> Mon { Mon(dex: 250, level: lv, female: false, shiny: shiny ? true : nil) }
    var au = Walk(); au.days = 2; au.earned = 31_000; au.watts = 4_000; au.box = [hoOh(), hoOh(true), Mon(dex: 16, level: 5, female: false), hoOh(lv: 51)]
    let auGone = au.audit()
    check(auGone?.gone == 2 && auGone?.macro == true && au.box.filter { $0.dex == 250 }.map { $0.shiny == true } == [true] && au.box.count == 2 && au.watts == 0 && au.corrected == true && au.audit() == nil,
          "1.7's check: 3 칠색조 bought in 2 days (31,000 W earned) → the 이로치 stays, 2 go, W 0; only once", "\(String(describing: auGone)) \(au.box.map(\.dex))")
    var fine = Walk(); fine.days = 40; fine.earned = 60_000; fine.watts = 900; fine.box = [hoOh()]
    check(fine.audit() == nil && fine.box.count == 1 && fine.watts == 900 && fine.corrected == nil, "… a save its days could pay for is left alone")
    var auc = Walk(); auc.days = 1; auc.earned = 20_000; auc.companion = hoOh(); auc.caught = [Mon(dex: 16, level: 5, female: false)]; auc.box = [hoOh()]
    check(auc.audit()?.gone == 2 && auc.companion.dex == 16 && auc.caught.isEmpty && auc.box.isEmpty, "… a 칠색조 companion hands over to the walker's one first")
    var ed1 = Walk(); ed1.days = 30; ed1.earned = 1_000; ed1.watts = 9_999; let ed1r = ed1.audit()
    var ed2 = Walk(); ed2.days = 30; ed2.earned = 5_000; ed2.box = [hoOh(), hoOh()]; let ed2r = ed2.audit()
    var ed3 = Walk(); ed3.audited = 1; ed3.box = [{ var m = Mon(dex: 16, level: 5, female: false); m.ivs = [99, 31, 31, 31, 31, 31]; return m }()]; let ed3r = ed3.audit()
    var ok1 = Walk(); ok1.audited = 1; ok1.days = 4; ok1.earned = 3_447; ok1.watts = 2_072
    check(ed1r?.macro == false && ed1.watts == 0 && ed2r?.gone == 2 && ed2.box.isEmpty && ed3r != nil && ed3.box[0].ivs?[0] == 31 && ed3.corrected == true && ok1.audit() == nil && ok1.watts == 2_072,
          "1.8's check: more W than ever earned, more 칠색조 than the W could buy, IVs over 31 → corrected; a plain save (checked by 1.7) is left alone")

    // 4b the server's copy (docs/plans/08 §4): shared goes up without this PC's fields; adopt takes the server's and walks this PC's steps it hasn't got on top
    func syMine(_ x: Walk, from pc: Walk) -> Walk { var x = x; (x.counter, x.boot, x.syncedAt, x.counterKind, x.cloudRev, x.cloudTotal, x.sentHash) = (pc.counter, pc.boot, pc.syncedAt, pc.counterKind, pc.cloudRev, pc.cloudTotal, pc.sentHash); return x }
    var syPC = Walk(); syPC.walk(1_300, at: at(12)); syPC.caught = [Mon(dex: 16, level: 5, female: false)]; syPC.bag = ["상처약"]
    (syPC.counter, syPC.boot, syPC.syncedAt, syPC.counterKind, syPC.cloudRev, syPC.cloudTotal, syPC.sentHash) = (4_321, 7, at(12).timeIntervalSinceReferenceDate, Walk.counterNow, 3, 1_000, "ab12")
    let syUp = syPC.shared, syEnc = JSONEncoder(); syEnc.outputFormatting = .sortedKeys
    let syText = (try? syEnc.encode(syUp)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    check(syUp.counter == 0 && syUp.boot == 0 && syUp.syncedAt == nil && syUp.counterKind == nil && syUp.cloudRev == nil && syUp.cloudTotal == nil && syUp.sentHash == nil
          && syMine(syUp, from: syPC) == syPC && (try? JSONDecoder().decode(Walk.self, from: Data(syText.utf8))) == syUp
          && !["syncedAt", "counterKind", "cloudRev", "cloudTotal", "sentHash"].contains { syText.contains("\"\($0)\"") },
          "shared: this PC's fields cleared, the rest as it was; through JSON unchanged", syText.count > 300 ? "" : syText)
    var syHead = Walk(); syHead.walk(1_210, at: at(12)); syHead.caught = [Mon(dex: 16, level: 5, female: false)]; syHead.box = [Mon(dex: 19, level: 3, female: true)]   // the server's: played elsewhere since
    var syAd = syPC, syWant = syHead; let syAdUp = syAd.adopt(syHead, rev: 5, at: at(12)), syWantUp = syWant.walk(300, at: at(12))   // 1,300 here, 1,000 up: 300 pending
    syWant = syMine(syWant, from: syPC); syWant.cloudRev = 5; syWant.cloudTotal = syHead.total
    check(syAd == syWant && syAdUp == syWantUp && syAd.total == syHead.total + 300 && syAd.today == syHead.today + 300 && syAd.watts > syHead.watts
          && syAd.companion.points > syHead.companion.points && syAd.caught[0].points > syHead.caught[0].points && syAd.box == syHead.box && syAd.counter == 4_321 && syAd.sentHash == "ab12",
          "adopt: the server's save with this PC's 300 pending steps walked on top (total, W, EXP rise); this PC's fields kept, the rev and the server's total noted")
    var syCapHead = syHead; syCapHead.today = Walk.dayCap - 100
    var syCap = syPC; syCap.adopt(syCapHead, rev: 6, at: at(12))
    var syLate = syHead; syLate.today = Walk.dayCap - 10
    var syNext = syPC; syNext.adopt(syLate, rev: 7, at: at(13, 9))
    check(syCap.today == Walk.dayCap && syCap.total == syCapHead.total + 100 && syNext.today == 300 && syNext.history.first == Walk.dayCap - 10 && syNext.total == syLate.total + 300,
          "adopt's re-walk keeps to the day's cap (room for 100 of 300: 100); a save from yesterday rolls over first, so yesterday's 99,990 doesn't cap today",
          "\(syCap.today) \(syNext.today) \(syNext.history)")
    var syStill = syPC; syStill.cloudTotal = syPC.total; syStill.adopt(syHead, rev: 8, at: at(12))
    var syNever = syPC; (syNever.cloudRev, syNever.cloudTotal) = (nil, nil); syNever.adopt(syHead, rev: 1, at: at(12))
    var syStillWant = syMine(syHead, from: syPC); syStillWant.cloudRev = 8; syStillWant.cloudTotal = syHead.total
    var syNeverWant = syStillWant; syNeverWant.cloudRev = 1
    check(syStill == syStillWant && syNever == syNeverWant, "adopt with nothing pending (or never saved up): the server's save as it is, with this PC's fields")
    let syOld: String = {                                                                         // a save from before these fields: the keys aren't there at all
        guard let d = try? syEnc.encode(syPC), var o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return "" }
        for k in ["cloudRev", "cloudTotal", "sentHash"] { o[k] = nil }
        return (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }()
    var syOldWant = syPC; (syOldWant.cloudRev, syOldWant.cloudTotal, syOldWant.sentHash) = (nil, nil, nil)
    check(syOld.contains("\"counter\"") && !syOld.contains("cloudRev") && (try? JSONDecoder().decode(Walk.self, from: Data(syOld.utf8))) == syOldWant,
          "a save without cloudRev / cloudTotal / sentHash still loads (they're nil)")

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
    w = Walk(); check((0..<50).allSatisfy { _ in w.courseItem(&r) == "상처약" }, "a find at 0 steps: only the common item")

    // 6 catches go to the box; the walker holds 3 the player sends (워커로); items: 3 on the walker, then the bag
    w = Walk(); for d in 1...4 { _ = w.keep(Mon(dex: d, level: 5, female: false)) }
    check(w.caught.isEmpty && w.box.map(\.dex) == [1, 2, 3, 4], "every catch goes to the box")
    for _ in 0..<4 { w.fetch(0) }; check(w.caught.map(\.dex) == [1, 2, 3] && w.box.map(\.dex) == [4], "워커로: the walker takes three")
    for _ in 0..<4 { _ = w.keep("상처약") }; check(w.items.count == 3 && w.bag.count == 1, "4th item goes to the bag")
    w.courseSteps = 900; w.setCourse(3, &r)
    check(w.course == 3 && w.courseSteps == 0, "new course: steps restart")
    w.courseSteps = 700; w.pair(0); check(w.companion.dex == 4 && w.box.last?.dex == 25 && w.box.count == 1 && w.caught.count == 3 && w.courseSteps == 700, "pair swaps with the box (the old one to its end), course progress kept")
    w.pair(0, onWalker: true)
    check(w.companion.dex == 1 && w.caught[0].dex == 4, "pair with a Pokémon on the walker")
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
    let baby = w.hatch(&r); check(baby.dex == 172 && baby.level == 1 && w.egg == nil && w.box.last?.dex == 172 && w.owned!.contains(172), "hatched Lv.1 피츄, in the box and the dex")
    w = Walk(); w.course = 34; var legends = 0
    for _ in 0..<5000 where w.legend(&r, chain: 0) != nil { legends += 1 }
    check((60...140).contains(legends), "legend course: ~2 % of radar finds", "\(legends)")
    w.owned = [249, 250, 493]; var again = 0; for _ in 0..<5000 where w.legend(&r, chain: 0) != nil { again += 1 }
    check((25...75).contains(again), "all of a course's legends caught: they still turn up, half as often (a shiny to hunt)", "\(again)")
    w = Walk(); check((0..<500).allSatisfy { _ in w.legend(&r, chain: 4) == nil }, "never on normal courses")
    w = Walk(); w.companion = Mon(dex: 290, level: 20, female: false); let nin = w.levelEvolution(at(10))!
    w.evolve(nin); check(w.companion.dex == 291 && w.box.map(\.dex) == [292], "토중몬 -> 아이스크 leaves 껍질몬 (in the box)")

    // 6f items
    check(ItemKind.of("상처약") == .heal(20) && ItemKind.of("풀회복약") == .heal(999) && ItemKind.of("기력의조각") == .revive(50) && ItemKind.of("하이퍼볼") == .sell(100)
          && ItemKind.of("힐볼") == .sell(40) && ItemKind.of("라즈열매") == .berry && ItemKind.of("천둥의돌") == .evolution && ItemKind.of("금구슬") == .sell(100)
          && ItemKind.of("기술머신68") == .sell(50), "item kinds")
    let allItems = Set(courses.flatMap { $0.items.map(\.item) })
    check(allItems.allSatisfy { if case .sell(let p) = ItemKind.of($0) { return p > 0 }; return true }, "every course item has a use or a price")
    w = Walk(); w.items = ["상처약"]; w.bag = ["고급상처약", "좋은상처약"]
    check(w.useHeal(missing: 40)! == ("좋은상처약", 40) && w.useHeal(missing: 300)! == ("고급상처약", 200) && w.useHeal(missing: 300)! == ("상처약", 20) && w.useHeal(missing: 1) == nil,
          "potions (Gen IV HP): smallest that fills the gap, else the biggest")
    w.bag = ["부활초", "기력의조각"]; check(w.useRevive()! == ("기력의조각", 50) && w.bag == ["부활초"], "revive: the cheaper one first (half HP)")
    var ballRng = Seeded(s: 77); var tally0: [String: Int] = [:], tally10: [String: Int] = [:]
    for _ in 0..<20_000 { tally0[Walk.rollBall(chain: 0, &ballRng).name, default: 0] += 1; tally10[Walk.rollBall(chain: 10, &ballRng).name, default: 0] += 1 }
    check((13_600...14_400).contains(tally0["몬스터볼"] ?? 0) && (60...150).contains(tally0["마스터볼"] ?? 0) && (7_600...8_400).contains(tally10["몬스터볼"] ?? 0) && (300...520).contains(tally10["마스터볼"] ?? 0),
          "a throw's ball by chance: 몬스터볼 70 % · 마스터볼 0.5 %; at chain 10: 40 % · 2 %", "\(tally0) \(tally10)")
    w.bag = ["슈퍼볼", "하이퍼볼", "힐볼", "상처약"]; w.watts = 0; let refund = w.refundBalls()
    check(refund?.count == 3 && refund?.watts == 180 && w.watts == 180 && w.bag == ["상처약"] && w.refundBalls() == nil && !Walk.shop.contains { $0.item.hasSuffix("볼") } && !Walk.bpShop.contains { $0.item.hasSuffix("볼") },
          "1.10: the balls one had go back as W, once; the shops sell no balls")
    var mb = Battle(wild: Mon(dex: 150, level: 70, female: false), companion: Mon(dex: 25, level: 50, female: false)); let mbBeats = mb.turn(.capture, &r, ball: 255)
    check(mbBeats.contains(.caught) && mb.over, "마스터볼: a sure catch, even a full-HP 뮤츠")
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
    let xe = Battle.wildExp(base: baseExp[16], foe: 10, mine: 5, share: 1)
    if xbeats.contains(.fainted(.it)) { check(xbeats.contains(.gained(exp: xe, level: nil, foe: 16, to: 0)) && xb.mine[0].mon.points == 125 + xe && xb.mine[0].mon.evs?[5] == evYield[16][5], "a wild KO pays the level-scaled EXP (1.14), and EVs") }
    func catches(_ m: Mon, hp: Int?, ball: Double, status: Status? = nil) -> Int { var n = 0; for _ in 0..<2000 { var b = Battle(wild: m, companion: pika50); if let hp { b.theirs[0].hp = hp }; b.theirs[0].status = status; if b.turn(.capture, &r, ball: ball).contains(.caught) { n += 1 } }; return n }
    let pFull = catches(Mon(dex: 16, level: 5, female: false), hp: nil, ball: 1), p1 = catches(Mon(dex: 16, level: 5, female: false), hp: 1, ball: 1)
    let mew = catches(Mon(dex: 150, level: 50, female: false), hp: 1, ball: 2), mewZ = catches(Mon(dex: 150, level: 50, female: false), hp: 1, ball: 2, status: .sleep)
    check((560...780).contains(pFull) && p1 > 1850 && (20...90).contains(mew) && mewZ > mew * 3 / 2, "Gen IV catch formula: 구구 full ~33 %, 1 HP ~97 %, 뮤츠 1 HP + 하이퍼볼 ~2.4 %, asleep x2", "\(pFull) \(p1) \(mew) \(mewZ)")
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
    // 흉내쟁이 and a foe's 따라하기 called each other forever (the app crashed): 따라하기 copies only a move aimed at its user
    var cm = Battle(wild: Mon(dex: 22, level: 40, female: false), companion: Mon(dex: 439, level: 40, female: false))   // 깨비드릴조 (faster) vs 흉내내
    cm.mine[0].moves = [383]; cm.mine[0].pp = [20]; cm.theirs[0].moves = [119]; cm.theirs[0].pp = [20]
    var cmDice = Seeded(s: 383)                                                                     // its own dice: the shared r's later draws stay as they were
    let cmBeats = cm.turn(.fight(383), &cmDice) + cm.turn(.fight(383), &cmDice)
    check(cmBeats.filter { $0 == .use(.it, move: 119) }.count == 2 && !cmBeats.contains(.use(.it, move: 383)), "흉내쟁이 then the foe's 따라하기: no endless calls, nothing copied", "\(cmBeats)")
    var gh = Battle(wild: Mon(dex: 94, level: 50, female: false), companion: lax50); gh.mine[0].moves = [89]; gh.mine[0].pp = [10]
    check(dealt(gh.turn(.fight(89), &r), .it, 89) == 0, "부유: 지진 can't touch 팬텀")
    var ib = Battle(wild: gyara50, companion: pika50); let ibeats = ib.begin(weather: .rain, &r)
    check(ibeats.first == .appear && ib.mine[0].stage[1] == -1 && ib.sky == .rain, "the opening: 위협 lowers 공격; the course's rain falls on the field")
    var rb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); check(rb.turn(.run, &r) == [.ran], "run ends a wild fight at once")
    var lb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: Mon(dex: 25, level: 5, female: false)); lb.mine[0].hp = 10
    let lmax = lb.mine[0].maxHP; lb.apply(.gained(exp: 5000, level: nil, foe: 16, to: 0))
    check(lb.mine[0].mon.level > 5 && lb.mine[0].hp == 10 + lb.mine[0].maxHP - lmax && lb.mine[0].mon.known != nil, "a level-up mid-fight raises current HP by the same amount (and freezes the moveset)")
    var fvRun = EngineRun(w: { var s = Walk(); s.bag = ["기력의조각"]; return s }(), p: Play(), r: Seeded(s: 11), now: Date(), ids: Issued(next: 1))   // (the server's after(): Model/EngineRules.swift)
    var fainted = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); fainted.mine[0].hp = 0; fainted.mine[0].down = true; fainted.over = true
    let fvBack = fvRun.ended(&fainted, .lost)                                                      // 3.6 (docs/plans/13): revives by hand only, on the bench
    check(fvBack.isEmpty && fvRun.out.end?.result == "lost" && fvRun.w.bag == ["기력의조각"], "no revive by itself: the last one down loses the fight, the 기력의조각 stays", "\(fvBack)")
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
        if k >= 400 || b.over && !(bs.last?.ends ?? false) { fuzzStall += 1 }   // over, but the last beat not its end: the screen would read on
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
    var split = Battle(wild: Mon(dex: 16, level: 10, female: false), party: [pika50, lax50])
    split.theirs[0].moves = [45]; split.theirs[0].pp = [40]; _ = split.turn(.swap(1), &r); split.theirs[0].hp = 1
    var sb: [Beat] = []; while !sb.contains(.fainted(.it)), !split.over { sb = split.turn(.fight(split.mine[1].moves.first { !moveTable[$0]!.isStatus }!), &r) }
    let half = Battle.wildExp(base: baseExp[16], foe: 10, mine: 50, share: 2)
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
    var d6 = duel(pika50, rat, [73]); d6.mine[0].hp = 50; d6.mine[0].lockOn = 2; let s6 = d6.turn(.fight(73), &r)   // sure to land
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
    check(sleeps == [2, 3, 4, 5], "sleep lasts 1-4 turns (Gen IV: the counter runs out on the turn it wakes and moves)", "\(sleeps)")
    var d11 = duel(pika50, rat, [156]); d11.mine[0].hp = 20; _ = d11.turn(.fight(156), &r)
    check(d11.mine[0].hp == d11.mine[0].maxHP && d11.mine[0].status == .sleep && d11.mine[0].sleep == 3, "잠자기: full HP, asleep 2 turns")
    var d12 = duel(pika50, Mon(dex: 19, level: 5, female: false), [164, 150], [33]); _ = d12.turn(.fight(164), &r); let afterSub = d12.mine[0].hp
    _ = d12.turn(.fight(150), &r)
    check(afterSub == d12.mine[0].maxHP - d12.mine[0].maxHP / 4 && d12.mine[0].hp == afterSub && d12.mine[0].sub < d12.mine[0].maxHP / 4, "대타출동: 1/4 HP, then it takes the hits")
    // the battle review (2026-10-01): one check a fix
    func notes(_ bs: [Beat]) -> [String] { bs.compactMap { if case .note(_, let t) = $0 { return t }; if case .hurt(_, _, let t) = $0 { return t }; return nil } }
    var rvLock = duel(pika50, Mon(dex: 94, level: 50, female: false), [37]); rvLock.mine[0].lock = 2; rvLock.mine[0].lockMove = 37; _ = rvLock.turn(.fight(37), &r)
    check(rvLock.mine[0].lock == 0 && rvLock.switchBlock == nil, "a rampage that can't land (into a ghost) ends there: no endless lock")
    var rvCharge = duel(pika50, rat, [268, 150]); _ = rvCharge.turn(.fight(268), &r); let rvOn = rvCharge.mine[0].charge > 0; _ = rvCharge.turn(.fight(150), &r)
    check(rvOn && rvCharge.mine[0].charge == 0, "충전 lasts its next turn only")
    var rvBond = duel(pika50, rat, [194, 150]); _ = rvBond.turn(.fight(194), &r); let rvSet = rvBond.mine[0].destinyBond; _ = rvBond.turn(.fight(150), &r)
    check(rvSet && !rvBond.mine[0].destinyBond, "길동무 wears off when it moves again")
    var rvStock = duel(pika50, rat, [254]); _ = rvStock.turn(.fight(254), &r)
    check(rvStock.mine[0].stockpile == 1 && rvStock.mine[0].stage[2] == 1 && rvStock.mine[0].stage[4] == 1, "비축하기 stocks one (+1 방어 / 특수방어)")
    var rvSub = duel(pika50, rat, [189]); rvSub.mine[0].lockOn = 2; rvSub.theirs[0].sub = 1; _ = rvSub.turn(.fight(189), &r)
    var rvWrap = duel(pika50, rat, [35]); rvWrap.mine[0].lockOn = 2; rvWrap.theirs[0].sub = 999; _ = rvWrap.turn(.fight(35), &r)
    check(rvSub.theirs[0].sub == 0 && rvSub.theirs[0].stage[6] == 0 && rvWrap.theirs[0].bound == 0, "a hit on a substitute (even the one that breaks it) has no side effects; no binding through it")
    var rvTomb = duel(pika50, rat, [328]); rvTomb.mine[0].lockOn = 2; let rvTombText = notes(rvTomb.turn(.fight(328), &r))
    check(rvTomb.theirs[0].boundBy == 328 && rvTombText.contains { $0.contains("모래지옥에 갇혔다") } && rvTombText.contains { $0.contains("모래지옥의 데미지") }, "binding moves say their own name (모래지옥, not 조임)", "\(rvTombText)")
    var rvLet = Battle(party: [pika50, rat], trainer: "x", foes: [rat, rat]); rvLet.mine[0].bound = 3; rvLet.mine[0].attracted = true; rvLet.switchIn(.it, 1)
    check(rvLet.mine[0].bound == 0 && !rvLet.mine[0].attracted, "the one that bound / charmed ours leaves: ours is let go")
    var rvNext = Battle(party: [pika50], trainer: "x", foes: [Mon(dex: 19, level: 2, female: false), rat]); rvNext.theirs[0].moves = [150]; rvNext.theirs[0].pp = [40]; rvNext.mine[0].moves = [33]; rvNext.mine[0].pp = [35]; rvNext.mine[0].lockOn = 2
    let rvNextBeats = rvNext.turn(.fight(33), &r), rvOut = rvNextBeats.lastIndex(of: .sendOut(.it, 1))
    check(rvOut != nil && !rvNextBeats[rvOut!...].contains { if case .hit(.it, _, _, _, _) = $0 { return true }; return false } && rvNext.theirs[1].turnsOut == 0, "a trainer's next one comes out at the end of the turn (nothing hits it on the way in)")
    var rvThaw = duel(pika50, rat, [52]); rvThaw.mine[0].lockOn = 2; rvThaw.theirs[0].status = .freeze; _ = rvThaw.turn(.fight(52), &r)
    check(rvThaw.theirs[0].status != .freeze, "a fire hit thaws the frozen")
    var rvTrace = duel(pika50, rat, [150]); rvTrace.mine[0].abilityOver = 36; rvTrace.theirs[0].abilityOver = 0; rvTrace.entry(.me)
    check(rvTrace.mine[0].abilityOver == 36, "트레이스 on one with no ability (위액): nothing to copy, no crash")
    var rvFuture = duel(Mon(dex: 65, level: 50, female: false), rat, [248]); let rvHP = rvFuture.theirs[0].hp; _ = rvFuture.turn(.fight(248), &r)
    check(rvFuture.theirs[0].hp == rvHP && rvFuture.sides[1].future > 0, "미래예지 lands later, not at once")
    var rvIce = duel(pika50, Mon(dex: 363, level: 50, female: false), [150]); rvIce.theirs[0].abilityOver = 115; rvIce.theirs[0].hp -= 20; rvIce.sky = .hail; let rvIceHP = rvIce.theirs[0].hp; _ = rvIce.turn(.fight(150), &r)
    check(rvIce.theirs[0].hp > rvIceHP, "아이스바디 heals in hail")
    var rvLost = Battle(party: [pika50], trainer: "x", foes: [Mon(dex: 19, level: 2, female: false), rat]); rvLost.mine[0].moves = [33]; rvLost.mine[0].pp = [35]; rvLost.mine[0].lockOn = 2
    rvLost.theirs[0].moves = [150]; rvLost.theirs[0].pp = [40]; rvLost.mine[0].hp = 1; rvLost.mine[0].status = .poison
    let rvLostBeats = rvLost.turn(.fight(33), &r)
    var rvRun = EngineRun(w: { var s = Walk(); s.items = ["기력의조각"]; return s }(), p: Play(tower: true), r: Seeded(s: 1), now: Date(), ids: Issued(next: 1))
    let rvBack = rvRun.ended(&rvLost, .lost)
    check(rvLostBeats.last == .lost && rvBack.isEmpty && rvRun.out.end?.result == "lost" && rvRun.w.items == ["기력의조각"], "ours KO'd in the turn it beat the trainer's one: no revive by itself (3.6), the run's over", "\(rvBack)")
    var rvAsleep = Battle(party: [Mon(dex: 19, level: 5, female: false)], trainer: "x", foes: [Mon(dex: 101, level: 100, female: false), rat]); rvAsleep.theirs[0].moves = [262]; rvAsleep.theirs[0].pp = [10]
    rvAsleep.mine[0].moves = [33]; rvAsleep.mine[0].pp = [35]; rvAsleep.mine[0].status = .sleep; rvAsleep.mine[0].sleep = 3; _ = rvAsleep.turn(.fight(33), &r)
    check(rvAsleep.mine[0].sleep == 2, "its target gone first (추억의선물), ours' sleep still counts down that turn")
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
    let lw0 = lw, lwSteps = expTable[growthRate[25]][next.0] - lw.companion.points
    lw.walk(lwSteps, at: Date())
    check(lw.companion.level == next.0 && lw.companion.uid != nil && Array((lw.learning ?? []).prefix(2)) == [lw.companion.uid!, next.1], "a level-up by walking queues the new move", "\(lw.learning ?? [])")
    let lv = online(lw0); lv.cloud!.addSteps(lwSteps); lv.cloud!.saveNow(); drain(lv)            // the server walks them: the level, the move waiting (4 known)
    var lvSaid: [String] = []; for _ in 0..<4 { if case .say(let l, _, _) = lv.screen { lvSaid += l; lv.press(1); drain(lv) } }
    if case .learn(4) = lv.screen, lvSaid.first == "레벨 업!" { lv.press(2); lv.press(1); drain(lv); check(lv.state.companion.known?[0] == next.1 && lv.state.companion.moves.count == 4 && served(lv)?.companion.known?[0] == next.1, "forget move 1 for the new one (the cursor starts on 배우지 않는다)") } else { check(false, "4 moves known: the level-up, then the forget-one screen, on 배우지 않는다", "\(lvSaid) \(lv.screen)") }
    let before4 = lv.state.companion.known, lvUID = lv.state.companion.uid!; serve(lv) { $0.learning = [lvUID, 85] }; lv.screen = .learn(sel: 4); lv.press(1); drain(lv)
    check(lv.state.companion.known == before4 && (lv.state.learning ?? []).isEmpty, "배우지 않는다 keeps the four")
    var lfRun = EngineRun(w: { var s = lw; s.companion.known = [84, 45]; return s }(), p: Play(), r: Seeded(s: 12), now: Date(), ids: Issued(next: 1_000_001)); lfRun.learnQueue(); lfRun.finish()
    check(lfRun.w.companion.known == [84, 45, next.1] && lfRun.out.news.contains(.learn(uid: lw.companion.uid!, move: next.1, learned: true)), "a free slot: learned straight away (news: learned)")
    lv.screen = .home; lv.news = [.learn(uid: lvUID, move: next.1, learned: true)]; lv.tick(Date())
    check({ if case .say(let l, _, _) = lv.screen { return l.last?.hasSuffix("배웠다!") == true }; return false }(), "… and home says so")
    var bw = Walk(); bw.box = [Mon(dex: 16, level: 5, female: false), Mon(dex: 25, level: next.0, female: false)]; bw.box[1].known = [84, 45]
    bw.queueMoves(1, from: next.0 - 1); bw.box.remove(at: 0)
    check(bw.nextToLearn()?.ref == 0 && bw.nextToLearn()?.move == next.1, "a queued move follows its Pokémon when the box shifts")
    // 7c 기술 바꾸기 (its page → a slot → a move): one passed on comes back, its own swap places, a free slot fills
    var rlw = Walk(); rlw.companion = Mon(dex: 25, level: 50, female: false); rlw.companion.known = [84, 45, 39, 86]
    let rl = online(rlw); let passed = rlw.companion.relearnable.first { !rlw.companion.moves.contains($0) }!
    func rls(_ r: Int, _ s: Int, _ a: Int?) -> Bool { var sc = rl.screen; if case .say(_, let n, _) = sc { sc = n }; if case .relearn(r, s, a) = sc { return true }; return false }
    rl.screen = .box(-1, act: nil, confirm: false, detail: true); rl.gridTap(4409); rl.pageTap(5501)
    let rlOpened = rls(-1, 1, 45); _ = rl.compose(Date()); rl.screen = .relearn(ref: -1, slot: 1, at: passed); _ = rl.compose(Date()); rl.press(1); drain(rl)
    check(rlOpened && rl.state.companion.moves == [84, passed, 39, 86] && rls(-1, 1, nil) && rlw.companion.relearnable.allSatisfy { rlw.companion.learnLevel($0).map { $0 <= 50 } ?? true },
          "기술 바꾸기: a move it passed on (배우지 않는다) goes in the slot picked", "\(rl.state.companion.moves)")
    rl.screen = .relearn(ref: -1, slot: 0, at: 86); rl.press(1); drain(rl)
    check(rl.state.companion.moves == [86, passed, 39, 84] && { if case .relearn(-1, 0, nil) = rl.screen { return true }; return false }(), "… one of its own: the two swap places, no message")
    serve(rl) { $0.companion.known = [84] }; rl.screen = .relearn(ref: -1, slot: 0, at: nil); rl.press(2); rl.press(2); let rlWrapped = rls(-1, 0, nil); rl.press(2); rl.press(1)
    let fill = rl.state.companion.relearnable.first { $0 != 84 }; rl.press(1); drain(rl)
    check(rlWrapped && rl.state.companion.moves == [84, fill!] && rl.paneContent(Date()).relearn?.slots.count == 2, "… a free slot: the slots go round it, and a move fills it", "\(rl.state.companion.moves)")
    rl.screen = .relearn(ref: -1, slot: 1, at: 84); rl.press(3); let up1 = rls(-1, 1, nil); rl.press(3)
    check(up1 && { if case .box(-1, nil, false, true) = rl.screen { return true }; return false }() && rl.homeKey() == false, "… ↩: the moves → the slots → its page")
    rl.screen = .relearn(ref: -1, slot: 0, at: rl.state.companion.relearnable[0]); rl.listRow(1000); rl.pageTap(5541)
    let rlPk = rl.paneContent(Date()).relearn?.pick; check(rlPk?.sel == 0 && rlPk?.first == 0 && rlPk?.rows.count == 5 && rlPk?.count == rl.state.companion.relearnable.count, "… the wheel stops at the end, ▶ goes round to the first page", "\(String(describing: rlPk))")
    bw.box.removeAll(); check(bw.nextToLearn() == nil && bw.learning == [], "released: its queued moves are dropped")
    let bv = online({ var s = Walk(); s.bag = ["마비치료제", "상처약"]; return s }(), rng: 13)
    var bb = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: pika50); bb.mine[0].status = .paralysis
    check(bv.battleItems(bb).map(\.name) == ["마비치료제"], "full HP: only the cure is offered")
    fightOn(bv, bb); bv.screen = .bagBattle(bb, sel: 0); bv.press(1); drain(bv)
    if case .beats(let after, let bs, _, _) = bv.screen { check(after.mine[0].status == nil && bv.state.bag == ["상처약"] && bs.first == .note(.me, text: "마비치료제를 사용했다!"), "using a cure in battle takes it from the bag") } else { check(false, "using a cure in battle") }
    let ov = Walker(state: { var s = Walk(); s.owned = [94]; return s }()); ov.persist = false; ov.rng = Seeded(s: 15)
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
    var w7 = w; w7.towerStreak = 7
    let tf = w7.towerFoes(&r); check(tf.foes.count == 3 && tf.foes.allSatisfy { f in f.level == Walk.towerLevel && !legendSet.contains(f.dex) && !evolutions.contains { $0.from == f.dex } }, "tower foes from 7 wins: 3 fully evolved non-legends at Lv.50 (1.14)", "\(tf.foes)")
    let wMean = w.party().map { baseStats[$0.mon.dex].reduce(0, +) }.reduce(0, +) / 3, tf0 = (0..<5).flatMap { _ in w.towerFoes(&r).foes }
    check(tf0.allSatisfy { f in f.level == Walk.towerLevel && !legendSet.contains(f.dex) && abs(baseStats[f.dex].reduce(0, +) - wMean) <= 60 && (f.known ?? []).allSatisfy { f.learnLevel($0).map { $0 <= 25 } ?? true } } && tf0.contains { f in evolutions.contains { $0.from == f.dex } },
          "3.1.2: the first 7 wins' foes are about as strong as our party (any stage, base stats within 60 of its mean) with Lv.25's moves, still Lv.50", "\(tf0.map { "\(monNames[$0.dex]) \(baseStats[$0.dex].reduce(0, +))" }) mean \(wMean)")
    var g: [Int] = []; for _ in 0..<8 { g.append(w.towerWin()) }
    check(g == [1, 1, 1, 1, 1, 1, 4, 2] && w.bp == 12 && w.towerBest == 8, "BP: 1 a win, +3 on the 7th, 2 a win after 7", "\(g)")
    w.towerEnd(); check(w.towerStreak == 0 && w.towerBest == 8, "a loss ends the streak, best kept")
    var up = w.box[1]; _ = up.gainBattleExp(50_000); w.writeBack([w.id(-1)!, w.id(1)!], [w.companion, up]); check(w.box[1].level > 30, "tower EXP goes back to the box")
    w.watts = 100; check(w.purchase(.init(kind: .item("슈퍼볼"), price: 40), 1, bp: false) != nil && w.watts == 60 && w.bag.last == "슈퍼볼" && w.purchase(.init(kind: .item("풀회복약"), price: 300), 1, bp: false) == nil, "W shop")
    check(w.purchase(.init(kind: .item("이상한사탕"), price: 8), 1, bp: true) != nil && w.bp == 4 && w.purchase(.init(kind: .item("이상한사탕"), price: 8), 1, bp: true) == nil, "BP exchange")
    w = Walk(); w.watts = 9998; check(w.buyLegend(0) == nil, "칠색조 needs the full 9,999 W")
    w.watts = 9999; check(w.buyLegend(0)?.dex == 250 && w.watts == 0 && w.box.last?.level == 50 && w.buyLegend(0) == nil, "칠색조: 9,999 W (not again without the watts)")
    w.watts = 9999; check(w.buyLegend(0)?.dex == 250 && w.box.filter { $0.dex == 250 }.count == 2, "… and again once they're back: as often as you can pay")
    w.bp = 299; check(w.buyLegend(1) == nil, "뮤츠 needs 300 BP"); w.bp = 300
    check(w.buyLegend(1)?.dex == 150 && w.bp == 0 && w.legendBought(150) && (w.owned ?? []).contains(150), "뮤츠: 300 BP, in the dex")
    check((w.caught + w.box).filter { [150, 250].contains($0.dex) }.allSatisfy { $0.perfectIVs >= 3 }, "shop legends come with 3 IVs at 31")
    var pr = Seeded(s: 9); check((0..<60).allSatisfy { _ in Mon.wild(144, level: 50, perfect: 3, &pr).perfectIVs >= 3 } && (0..<60).map { _ in Mon.wild(16, level: 5, &pr).perfectIVs }.max()! < 4, "perfect: n sure 31s")
    check((0...10).map(Walk.chainPerfectIVs) == [0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4], "radar chains: 3 → 1V, 5 → 2V, 7 → 3V, 9 → 4V")

    // 7a chain odds and rewards
    check(Walk.chainGoesOn(0) == 0.85 && abs(Walk.chainGoesOn(3) - 0.61) < 1e-9 && Walk.chainGoesOn(10) == 0.35, "chain goes on 85 %, -8 points a link, floor 35 %")
    w = Walk(); check(w.chainReward(1) == nil && w.watts == 2 && w.chainReward(4) == nil && w.watts == 10, "each link pays 2n W")
    check(w.chainReward(5) == courses[0].items[0].item && w.items == [courses[0].items[0].item] && w.bestChain == 5, "link 5: the course's rarest item, best chain kept")
    check(Walk.chainShinyOdds(0) == 64 && Walk.chainShinyOdds(3) == 25 && Walk.chainShinyOdds(5) == 18 && Walk.chainShinyOdds(10) == 10 && Walk.chainShinyOdds(30) == 10,
          "이로치 1/64 -> 1/25 at 3 -> 1/18 at 5 -> 1/10 from 10 on")

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
    func hex(_ s: String) -> Data { let c = Array(s); return Data(stride(from: 0, to: c.count, by: 2).map { UInt8(String(c[$0...$0 + 1]), radix: 16)! }) }
    var lcg = 1, ab: [UInt8] = []; for _ in 0..<256 { lcg = (lcg * 1103515245 + 12345) & 0x7fffffff; ab.append(lcg >> 16 & 1 == 0 ? 97 : 98) }   // a's and b's: zlib picks a dynamic block
    check(inflate(hex("010a00f5ff506f6b6557616c6b6572")) == Array("PokeWalker".utf8) && inflate(hex("cb48cdc9c957c840903a0ae58939d9a9458a00")) == Array("hello hello hello, walker!".utf8)
          && inflate(hex("000300fcff616263cb48cdc9c90700")) == Array("abchello".utf8)
          && inflate(hex("558e890d003008026785fd87a8b9421f6d0251844a9e923528f8801841987fb3fdb614ce96c2c891e6f0ed421d8e7776bd8bb76f46ec9d7f5ee9614dafbc04c54393dcc502")) == ab
          && inflate(hex("cb48cdc9c957c840")) == nil && inflate(hex("010a00f5fe506f6b6557616c6b6572")) == nil, "inflate: stored, fixed with copies, two blocks, dynamic; cut short or a bad LEN => nil")
    #if os(macOS)                                                                          // Apple's own zlib to compare with
    let raw = [ab, Array(String(repeating: "피카츄 이브이 리자몽 ", count: 40).utf8), (0..<5000).map { UInt8(truncatingIfNeeded: $0 * $0 / 7) }].map { Data($0) }
    check(raw.allSatisfy { p in (try? (p as NSData).compressed(using: .zlib)).map { inflate($0 as Data) == [UInt8](p) } == true }, "inflate: NSData's own DEFLATE round-trips")
    var blocks = 0, differ: [String] = []
    for (f, a) in [("anims", animData), ("walk", walkData)] { for d in 1...493 { if let b = block(a, d) {
        blocks += 1; let ns = (try? (b as NSData).decompressed(using: .zlib)).map { [UInt8]($0 as Data) }
        if ns == nil || inflate(b) != ns { differ.append("\(f) \(d)") }
    } } }
    check(blocks > 0 && differ.isEmpty, "inflate: every species' anims.bin and walk.bin block unpacks as NSData does", "\(blocks) blocks, differ \(differ)")
    #endif
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
    check(josa("피카츄", "을", "를") == "피카츄를" && josa("꼬렛", "을", "를") == "꼬렛을" && josa("zz100411", "이", "가") == "zz100411이" && josa("zz100412", "과", "와") == "zz100412와"
          && josa("zz7", "으로", "로") == "zz7로" && josa("zz3", "으로", "로") == "zz3으로" && josa("minsu", "이", "가") == "minsu가", "josa (a trailing digit as read: 일 · 이 …)")

    // 9 UI flows: the walker, driven through press() / touch() / tick()
    func on(_ v: Walker, _ p: (Screen) -> Bool) -> Bool { p(v.screen) }
    var s0w = Walk(); s0w.watts = 100
    let v = online(s0w, rng: 14)
    v.press(1); v.press(2); let homeStays = on(v) { if case .home = $0 { return true }; return false } && v.emote?.kind == 1
    v.press(4); let menuUp = on(v) { if case .menu(menuAt("포켓 레이더")) = $0 { return true }; return false } && v.compose(Date()).sprites.count == 1 && v.homeKey() == false; v.press(0)
    check(homeStays && menuUp && on(v) { if case .menu(menuItems.count - 1) = $0 { return true }; return false }, "home: ● pats (♥), ▶ does nothing; the 메뉴 key opens the menu on the pane (the LCD stays home); ◀ goes round")
    v.press(4); check(on(v) { if case .home = $0 { return true }; return false } && v.homeKey() == true, "… the same key again: home"); v.press(4)
    let sv = Walker(state: Walk()); sv.persist = false; sv.screen = .home
    sv.strollX = sv.strollRange.upperBound - 0.5; sv.strollRight = true; sv.lastStep = Date(); sv.strollAt = Date().addingTimeInterval(-0.2); sv.stroll(Date())
    let turned = sv.strollX == sv.strollRange.upperBound && !sv.strollRight, walkKey = sv.compose(Date()).pics.first { $0.key.hasPrefix("walk|") }?.key
    sv.lastStep = .distantPast; let x0 = sv.strollX; sv.strollAt = Date().addingTimeInterval(-0.2); sv.stroll(Date())
    let standKey = sv.compose(Date()).pics.first { $0.key.hasPrefix("walk|") }?.key
    check(walkSprite(25)?.size == 32 && turned && walkKey?.hasPrefix("walk|25|0|") == true && standKey?.hasPrefix("walk|25|2|") == true && sv.strollX == x0,
          "home: the HGSS walking sprite goes along the polaroid's photo while steps come in, turns at the end, faces us when they stop")
    v.press(1); drain(v); check(v.state.watts == 90 && on(v) { if case .radar = $0 { return true }; return false }, "radar costs 10W (the server's bush)")
    if case .radar(let b, _, _, let ch) = v.screen { v.screen = .radar(bush: b, cursor: (b + 2) % 4, since: Date().addingTimeInterval(-2), chain: ch) }
    v.press(2); v.press(2); v.press(1); drain(v)
    check(on(v) { if case .beats(_, let bs, _, _) = $0 { return bs.first == .appear }; return false } && v.state.seen?.isEmpty == false, "▶▶● on the shaking bush: a wild one appears (and is seen)")
    if case .beats(let b, _, _, _) = v.screen { v.screen = .battle(b, sel: 0) }
    if case .battle = v.screen { v.sidePick(3); drain(v) }                                            // the pane's 도망
    check(on(v) { if case .beats(_, let bs, _, _) = $0 { return bs == [.ran] || bs.first == .note(.me, text: "도망칠 수 없었다!") }; return false }, "tapping 도망 tries to run (Gen IV odds)")
    let caughtB = Battle(wild: Mon(dex: 16, level: 3, female: false), companion: v.state.companion, chain: 1)
    let (vs0, vk0) = server(v); vs0.rows[vk0]?.play = Play(chain: 2); v.news = [.chain(n: 2, bonus: 4, reward: nil)]
    v.fightEnd = BattleEnd(result: "caught", chain: 2); let goesOn = v.beatsDone(caughtB, .caught, Date()); let saysChain: Bool = { if case .say(let l, _, _) = goesOn { return l == ["연쇄 2!", "풀숲이 흔들린다"] }; return false }()
    drain(v); let chained = saysChain && { if case .radar(_, _, _, 2) = v.screen { return true }; return false }() && v.chainNote == "+4W" && v.news.isEmpty; calm(v)
    v.fightEnd = BattleEnd(result: "caught", chain: 0); let quiet = v.beatsDone(caughtB, .caught, Date())
    check(chained && { if case .say(let l, .home, _) = quiet { return l == ["풀숲이 조용해졌다", "연쇄 1에서 끝"] }; return false }(),
          "a catch, as the server ends it: the chain goes on — 연쇄 2! straight to its bush, no home in between (its +4W under it) — or quietly ends")
    var hpB = Battle(wild: Mon(dex: 143, level: 30, female: false), companion: Mon(dex: 25, level: 30, female: false))
    hpB.mine[0].moves = [85]; hpB.mine[0].pp = [15]; hpB.theirs[0].moves = [33]; hpB.theirs[0].pp = [35]   // damaging moves only (no 꼬리흔들기, no 잠자기)
    fightOn(v, hpB); v.screen = .moves(hpB, sel: 0); v.press(1); drain(v)
    if case .beats(let after, _, _, let before) = v.screen {
        check(after.theirs[0].hp < before.theirs[0].hp || after.mine[0].hp < before.mine[0].hp, "the battle kept after a turn is the one AFTER it (HP stays down next turn)")
        v.screen = .beats(after, [.appear], since: Date().addingTimeInterval(-30), from: after); v.tick(Date())
        if case .battle(let next, _) = v.screen { check(next.theirs[0].hp == after.theirs[0].hp && next.mine[0].hp == after.mine[0].hp, "next turn's menu shows the same HP") }
    } else { check(false, "the battle kept after a turn is the one AFTER it (HP stays down next turn)") }
    var mr = Battle(party: [Mon(dex: 25, level: 30, female: false), Mon(dex: 143, level: 30, female: false)], trainer: "x", foes: [Mon(dex: 16, level: 30, female: false)])
    mr.mine[0].hp = 0; mr.mine[0].down = true; mr.mustReplace = true; fightOn(v, mr, tower: true)
    v.screen = .beats(mr, [.fainted(.me)], since: Date().addingTimeInterval(-30), from: mr); v.tick(Date())
    let picking = on(v) { if case .party(_, 1) = $0 { return true }; return false }; v.press(3)
    let stuck = on(v) { if case .party = $0 { return true }; return false }; v.press(1); drain(v)
    check(picking && stuck && on(v) { if case .beats(let nb, let bs, _, _) = $0 { return bs.first == .sendOut(.me, 1) && nb.me == 1 }; return false }, "ours fainted: pick who's next (↩ can't skip it)")
    calm(v); v.news = []; v.screen = .menu(menuAt("포켓 레이더")); v.press(3); check(on(v) { if case .home = $0 { return true }; return false }, "↩ on a menu page: home")
    // ↩ 뒤로: one step up; where an answer is due only the cursor moves; nothing that can't be undone
    let bk = online({ var s = Walk(); s.watts = 500; s.bp = 40; return s }(), rng: 51)
    func back(_ sc: Screen) -> Screen { bk.screen = sc; bk.press(3); return bk.screen }
    let wild = Battle(wild: Mon(dex: 16, level: 5, female: false), companion: Mon(dex: 25, level: 20, female: false))
    let tw = Battle(party: [Mon(dex: 25, level: 20, female: false)], trainer: "x", foes: [Mon(dex: 16, level: 5, female: false)])
    func isBattle(_ s: Screen, _ opt: String) -> Bool { if case .battle(let b, let sel) = s { return bk.battleMenu(b)[sel] == opt }; return false }
    check(isBattle(back(.battle(wild, sel: 0)), "도망") && isBattle(back(.battle(tw, sel: 0)), "기권") && isBattle(back(.moves(wild, sel: 1)), "공격") && isBattle(back(.bagBattle(wild, sel: 0)), "도구"),
          "battle: ↩ puts the cursor on 도망 / 기권 (no instant escape or forfeit); from a sub-menu back onto its entry")
    check(isBattle(back(.say(["PP가 없다"], next: .moves(wild, sel: 0), since: Date())), "공격") == false && { if case .moves = bk.screen { return true }; return false }(),
          "a battle message: ↩ = ● (the fight doesn't vanish)")
    serve(bk) { $0.towerStreak = 5 }; fightOn(bk, tw, tower: true); bk.screen = .battle(tw, sel: 3); bk.press(1)
    let askedForfeit = { if case .forfeit(_, false) = bk.screen { return true }; return false }(); bk.press(1)
    check(askedForfeit && isBattle(bk.screen, "기권") && bk.state.towerStreak == 5 && bk.towerRun, "기권 asks first; ● on 아니오 goes back, the streak stays")
    bk.screen = .battle(tw, sel: 3); bk.press(1); bk.press(2); bk.press(1); drain(bk)
    check(bk.state.towerStreak == 0 && !bk.towerRun && server(bk).0.rows[server(bk).1]?.play.battle == nil, "… ▶ 예 ● gives up (the server's)")
    bk.towerRun = true; bk.state.towerStreak = 2
    check({ if case .menu(menuAt("배틀 타워")) = back(.tower(pick: nil)) { return true }; return false }() && bk.towerRun && bk.state.towerStreak == 2, "tower lobby: ↩ to the menu, the run stays on")
    let radar = Screen.radar(bush: 1, cursor: 0, since: Date(), chain: 4)
    check({ if case .radar(_, _, _, 4) = back(radar) { return true }; return false }(), "radar: ↩ does nothing (the 10W and the chain stay)")
    check({ if case .learn(4) = back(.learn(sel: 1)) { return true }; return false }(), "learn: ↩ onto 배우지 않는다")
    check({ if case .menu(menuAt("트레이너 카드")) = back(.card(1)) { return true }; return false }() && { if case .box(-1, nil, false, false) = back(.items(0)) { return true }; return false }()
          && { if case .menu(menuAt("도감")) = back(.dex(1, filter: 0, detail: false)) { return true }; return false }() && { if case .dex(1, 0, false) = back(.dex(1, filter: 0, detail: true)) { return true }; return false }()
          && { if case .menu(menuAt("BP 교환소")) = back(.shop(bp: true, sel: 0, qty: nil)) { return true }; return false }(), "card / dex / shop list: ↩ to their menu page; the 도구 page: back to 포켓몬")
    bk.state.box = [Mon(dex: 16, level: 5, female: false)]
    check({ if case .menu(menuAt("포켓몬")) = back(.box(0, act: nil, confirm: false)) { return true }; return false }() && { if case .box(0, nil, false, false) = back(.box(0, act: 1, confirm: true)) { return true }; return false }() && bk.state.box.count == 1
          && { if case .box(0, nil, false, true) = back(.box(0, act: 1, confirm: true, detail: true)) { return true }; return false }() && { if case .box(0, nil, false, false) = back(.box(0, act: nil, confirm: false, detail: true)) { return true }; return false }(),
          "box: ↩ from 놓아줄까? back (= 아니오), from a Pokémon's page to the grid, from the grid to the menu")
    bk.sideOn = true; bk.state.towerStreak = 5; bk.towerRun = true; bk.screen = .forfeit(tw, yes: false)
    check(!bk.touch(80, 56) && bk.state.towerStreak == 5, "with the side panel, an LCD tap in a fight answers nothing (it drags)")
    bk.sideOn = false; bk.screen = .forfeit(tw, yes: false); let lcdTap = bk.touch(55, 56); bk.sidePick(0)
    check(!lcdTap && bk.state.towerStreak == 5 && isBattle(bk.screen, "기권"), "the LCD answers nothing even without the pane; the pane's 아니오 is 아니오")
    bk.screen = .battle(wild, sel: 0)
    let rightClick = bk.menu()
    check(!rightClick.contains { m in ["코스", "함께 걷기", "가방", "진화의 돌"].contains { m.title.hasPrefix($0) } } && rightClick.contains { $0.title.hasPrefix("배틀 속도 · ") },
          "the right-click is options only (the game is on the pane), with 배틀 속도")
    let hider = Walker(state: Walk()); hider.persist = false; hider.screen = .say(["PP가 없다"], next: .moves(wild, sel: 0), since: Date())
    let midFight = hider.inBattle; hider.screen = .say(["샀다"], next: .shop(bp: false, sel: 0, qty: nil), since: Date())
    check(midFight && !hider.inBattle, "inBattle covers a fight's messages (so hiding to the menu bar keeps the fight), not a shop's")
    check({ if case .evolve = back(.evolve(from: Mon(dex: 1, level: 16, female: false), to: Mon(dex: 2, level: 16, female: false), since: Date())) { return true }; return false }(), "an evolution isn't cut short by ↩")
    calm(v); serve(v) { $0.box = [Mon(dex: 16, level: 20, female: false)] }; let wBefore = v.state.watts
    v.screen = .box(0, act: nil, confirm: false); v.press(1); v.press(1); v.press(2); v.press(2); v.press(1); v.press(2); v.press(1); drain(v)   // 함께 → 워커로 → 놓아주기, 예
    check(v.state.box.isEmpty && v.state.watts == wBefore + 10, "box: ● its page, ● 놓아주기 (after 워커로) 예 releases for level / 2 W")
    serve(v) { $0.box = [Mon(dex: 1, level: 7, female: false)] }; v.screen = .box(0, act: nil, confirm: false); v.press(1); v.press(1); v.press(1); drain(v)
    check(v.state.companion.dex == 1 && v.state.box.first?.dex == 25, "box: ● its page, ● 함께 swaps the companion")
    v.screen = .menu(menuAt("도감")); v.press(1); check(on(v) { if case .dex = $0 { return true }; return false }, "menu 도감 opens the dex")
    let dexTaps = [v.touch(80, 30), v.touch(10, 30), v.touch(48, 30)]; let still = on(v) { if case .dex(_, _, false) = $0 { return true }; return false }; v.press(1)
    check(dexTaps == [false, false, false] && still && on(v) { if case .dex(_, _, true) = $0 { return true }; return false }, "LCD clicks don't step (they drag); ● opens the entry page")
    v.screen = .say(["어라?"], next: .menu(menuAt("코스")), since: Date()); check(v.touch(10, 10) && on(v) { if case .menu(menuAt("코스")) = $0 { return true }; return false }, "… only a message goes on with a click on the LCD")

    // the 도감 / 상자 grids on the pane
    let gv = online({ var s = Walk(); s.owned = [1, 4, 25]; s.seen = [1, 4, 7, 25, 94]
        s.box = [Mon(dex: 16, level: 30, female: false), Mon(dex: 1, level: 5, female: false), Mon(dex: 16, level: 8, female: false, shiny: true)]; return s }(), rng: 71)
    func gs(_ p: (Screen) -> Bool) -> Bool { p(gv.screen) }
    let here = gv.state.here
    let onCourse: [Int] = here.slots.map(\.dex) + here.extra.map(\.dex) + here.guests + here.legends
    check(gv.dexList(0) == Array(1...493) && gv.dexList(1) == [1, 4, 25] && gv.dexList(2) == [7, 94] && Set(gv.dexList(3)) == Set(onCourse),
          "dex tabs: 전체 (all 493) / 잡음 / 못 잡음 (seen, not caught) / 이 코스")
    gv.screen = .menu(menuAt("도감")); gv.press(1)
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
    gv.gridTap(10002); let dexPicked = gs { if case .dex(25, 1, false) = $0 { return true }; return false } && gv.paneContent(Date()).grid?.sel == 2
    gv.gridTap(10002); check(dexPicked && gv.paneContent(Date()).dex?.num == 25, "a click on a cell picks it (the LCD shows it, the grid stays); a click on the pick opens its entry page")
    gv.press(2); check(gs { if case .dex(1, 1, true) = $0 { return true }; return false }, "▶ on the entry page: the next on the tab, wrapping")
    gv.press(3); let toGrid = gs { if case .dex(1, 1, false) = $0 { return true }; return false }; gv.press(3)
    check(toGrid && gs { if case .menu(menuAt("도감")) = $0 { return true }; return false }, "↩: the entry page → the grid → the menu")
    gv.state.owned = [1, 4, 7, 25, 94]; gv.screen = .dex(7, filter: 0, detail: false); gv.gridTap(4102)
    check(gv.paneContent(Date()).grid.map { $0.cells.isEmpty && $0.sel == nil && $0.empty == "모두 잡았다!" } == true && gv.compose(Date()).runs.contains { $0.s == "모두 잡았다!" }, "an empty tab says so, on the pane and the LCD")
    gv.press(1); check(gs { if case .dex(_, 2, false) = $0 { return true }; return false } && gv.paneContent(Date()).dex == nil, "● on an empty tab: no entry page for a pick that isn't on it")
    gv.screen = .menu(menuAt("포켓몬")); gv.press(1); let openedOn = gs { if case .box(-1, nil, false, false) = $0 { return true }; return false }; gv.gridStep(GridModel.columns)
    check(openedOn && gv.boxOrder == [1, 0, 2] && gs { if case .box(1, nil, false, false) = $0 { return true }; return false }, "포켓몬 opens on the companion; a row down goes into the box, 번호순 (then the higher level)")
    gv.gridTap(4101); check(gv.boxOrder == [0, 2, 1] && gs { if case .box(1, nil, false, false) = $0 { return true }; return false }, "레벨순 tab: the order changes, the pick stays")
    gv.press(2); let wrapHome = gs { if case .box(-1, nil, false, false) = $0 { return true }; return false }; gv.press(2)
    check(wrapHome && gs { if case .box(0, nil, false, false) = $0 { return true }; return false }, "▶ follows the grid's order, past the box's last round to the companion (then the walker's, then the box)")
    gv.boxSort = 3; check(gv.boxOrder == [2, 1, 0], "최근: the last to arrive first"); gv.boxSort = 1
    gv.boxSort = 2; gv.state.box[1].ivs = [31, 31, 31, 0, 0, 0]; check(gv.boxOrder.first == 1 && gv.paneContent(Date()).grid?.cells.first?.v3 == true, "V순: 3V first, marked"); gv.state.box[1].ivs = nil; gv.boxSort = 1
    let shinyCell = gv.paneContent(Date()).grid?.cells[1].shiny == true
    gv.gridTap(10001); let boxPicked = gs { if case .box(2, nil, false, false) = $0 { return true }; return false } && gv.paneContent(Date()).grid != nil
    gv.gridTap(10001)
    check(shinyCell && boxPicked && gs { if case .box(2, nil, false, true) = $0 { return true }; return false } && gv.paneContent(Date()).mon != nil,
          "포켓몬: a click on a cell picks it (★ = 이로치), a click on the pick opens its page")
    gv.state.box[2].nature = 3; gv.state.box[2].ivs = [31, 20, 31, 0, 12, 31]; gv.state.box[2].evs = [252, 0, 6, 0, 0, 252]; gv.state.box[2].hyper = [3]
    let mm = gv.paneContent(Date()).mon
    check(mm?.nature == natures[3].name && mm?.up == natures[3].up && mm?.down == natures[3].down && mm?.natureNote.contains("10% 높고") == true && mm?.ivs == [31, 20, 31, 31, 12, 31]
          && mm?.evTotal == 510 && mm?.v == 4 && mm?.abilityNote.isEmpty == false && mm?.ability == gv.state.box[2].abilityName,
          "a Pokémon's page: its nature (which stats, what it means), its ability and what it does, IVs as battles use them (특훈 = 31), EVs and their total")
    gv.state.box[2].nature = 0; check(gv.paneContent(Date()).mon.map { $0.up == nil && $0.natureNote.contains("영향을 주지 않는") } == true, "a neutral nature says it changes nothing")
    let noteW = natures.indices.map { i in gv.state.box[2].nature = i; return gv.paneContent(Date()).mon.map { width($0.natureNote, font(9)) } ?? .infinity }; gv.state.box[2].nature = 0
    check(noteW.allSatisfy { $0 <= 162 * K }, "every nature's note fits its line on the page", "widest \(noteW.max()!) of \(162 * K)")
    let od = [5, 12, 31, 57].map { abilityDescs[$0] ?? "" }
    check(od[0] == "일격필살 기술을 받지 않는다." && od[1] == "헤롱헤롱 상태가 되지 않는다." && od[2].contains("싱글 배틀에서는 효과가 없다") && od[3].contains("싱글"), "ability notes say what they do in Gen IV singles (not X/Y's later effects)")
    gv.gridTap(4401); let asking = gv.paneContent(Date()).mon.map { $0.confirm && $0.sel == 0 } == true; gv.gridTap(4402)
    check(asking && gs { if case .box(2, nil, false, true) = $0 { return true }; return false } && gv.paneContent(Date()).mon?.sel == nil,
          "its page's 놓아주기 asks first, 아니오 picked (red = what ● does); 아니오 stays")
    gv.screen = .box(0, act: 3, confirm: false, detail: true); gv.press(2); let wrapped = gs { if case .box(0, 0, false, true) = $0 { return true }; return false }   // 닫기 → round to 함께
    gv.press(2); gv.press(2); gv.press(1); gv.press(2); gv.press(1); drain(gv)                                       // 레벨순 [Lv.30, Lv.8, Lv.5]: the Lv.30 goes; next in the grid = the Lv.8 (box[1] now), not box[0]
    check(wrapped && gv.state.box.map(\.level) == [5, 8] && gs { if case .say(_, .box(1, nil, false, true), _) = $0 { return true }; return false } && gv.paneContent(Date()).mon != nil,
          "놓아주기 예 on its page: the next in the grid's page comes up, through the message too")
    gv.state.box = [Mon(dex: 131, level: 8, female: false), Mon(dex: 332, level: 10, female: false)]
    check(gv.state.box[0].points > gv.state.box[1].points && gv.boxOrder == [1, 0], "레벨순 is by level (a slow-growing Lv.8 has more EXP than a Lv.10)")
    gv.state.box = [Mon(dex: 16, level: 5, female: false), Mon(dex: 19, level: 5, female: false)]; gv.state.pair(0); gv.boxSort = 3
    check(gv.state.box.map(\.dex) == [19, 25] && gv.boxOrder.first == 1, "함께: the old companion goes to the box's end, first on 최근")

    v.state.box = (1...120).map { Mon(dex: $0 * 4 % 493 + 1, level: 5, female: false, shiny: $0 % 17 == 0 ? true : nil) }
    v.state.box += (0..<40).map { Mon(dex: 29, level: 1 + $0 % 25, female: $0 % 2 == 0) }

    // 7e 3V: radar chains, the menu's marks, 중복 놓아주기 by V
    let cv = Walker(state: Walk()); cv.persist = false; cv.rng = Seeded(s: 31); cv.state.watts = 100
    let lc = courses.firstIndex { !$0.legends.isEmpty }!, lw2: Walk = { var s = Walk(); s.course = lc; return s }()
    var legendV: [Int] = []
    for k in 0..<400 where legendV.count < 3 {                                                     // a legend at chain 0: 3V from being a legend, not from the chain (the server's roll: Model/Mint.swift)
        var g = Seeded(s: UInt64(k)); let f = lw2.radarMon(&g, chain: 0)
        if courses[lc].legends.contains(f.mon.dex) { legendV.append(f.mon.perfectIVs) }
    }
    check(legendV.count == 3 && legendV.allSatisfy { $0 >= 3 }, "a legend course's radar legend has 3 IVs at 31 (chain 0)", "\(legendV)")
    check((0..<20).allSatisfy { k in var g = Seeded(s: UInt64(31 + k)); return cv.state.radarMon(&g, chain: 7).mon.perfectIVs >= 3 }, "a chain-7 radar find has 3 IVs at 31")
    func withIVs(_ dex: Int, _ iv: [Int], level: Int = 20, shiny: Bool = false) -> Mon { var m = Mon(dex: dex, level: level, female: false, shiny: shiny ? true : nil); m.ivs = iv; return m }
    let v3 = withIVs(16, [31, 31, 31, 5, 5, 5]), v1 = withIVs(16, [31, 5, 5, 5, 5, 5], level: 40), v2 = withIVs(16, [31, 31, 0, 0, 0, 0], level: 10)
    var dw = Walk(); dw.box = [v1, v2, v3, withIVs(16, [0, 0, 0, 0, 0, 0], level: 60, shiny: true), withIVs(16, [3, 3, 3, 3, 3, 3], level: 90), withIVs(19, [0, 0, 0, 0, 0, 0])]
    check(dw.duplicates(of: 16) == [0, 1, 4], "중복 놓아주기: the 이로치, every 3V+ and the best stay; the rest go", "\(dw.duplicates(of: 16))")
    dw.box.remove(at: 2); check(dw.duplicates(of: 16) == [0, 3], "no 3V: the 2V is the one kept over higher levels", "\(dw.duplicates(of: 16))")
    var ow = Walk(); ow.box = [Mon(dex: 16, level: 60, female: false), withIVs(16, [30, 30, 30, 30, 30, 30], level: 5)]
    check(ow.duplicates(of: 16) == [1], "same V: the higher level stays (an old Lv.60 isn't traded for a fresh catch's IV total)")
    check(statLines({ var m = v1; m.hyper = [2]; return m }())[1].contains("방어 5→31") && statLines(v3)[1].hasPrefix("개체값 · 3V"), "the numbers stay; a 특훈 IV reads 5→31")
    // 7f the shops: in the walker's menu, several at once
    let mv0 = Walker(state: Walk()); mv0.persist = false
    check(!mv0.menu().contains { $0.title.hasPrefix("상점") || $0.title.hasPrefix("BP 교환소") || $0.title.hasPrefix("교환소") }, "the shops left the right-click menu")
    var sw = Walk(); sw.watts = 5000; sw.bp = 200; sw.companion = Mon(dex: 133, level: 20, female: false)             // 이브이: it has evolution items to sell
    let wW = sw.wares(bp: false, shells: []), wB = sw.wares(bp: true, shells: [(name: "배틀 골드", bp: 40)])
    check(wW.count == Walk.shop.count + Walk.mints.count + Walk.heldW.count + sw.evolutionItems().count + 1 && wW.last?.kind == .legend(0) && wW.contains { $0.kind == .item("불꽃의돌") && $0.price == Walk.evoItemPrice }
          && wB.count == Walk.bpShop.count + Walk.heldBP.count + 2 && wB.contains { $0.kind == .shell("배틀 골드") } && wB.last?.kind == .legend(1), "상점: goods + 민트 21 + the companion's evolution items + 칠색조; BP 교환소: goods + 배틀 골드 + 뮤츠")
    check(shells.filter { $0.bp > 0 }.map { "\($0.name) \($0.bp)" } == Engine.bpShells.map { "\($0.name) \($0.bp)" }, "BP 교환소's device colours: the 기기 menu's prices are the server's (Engine.bpShells)")
    let mochi = wW.first { $0.kind == .item("순백떡") }!, cap = wB.first { $0.kind == .item("금색병뚜껑") }!
    check(sw.canBuy(mochi, bp: false) == 25 && sw.canBuy(Walk.Ware(kind: .item("해독제"), price: 10), bp: false) == 99 && sw.canBuy(cap, bp: true) == 1 && sw.canBuy(wW.last!, bp: false) == 0,
          "how many: what the money covers, at most 99; 칠색조 needs 9,999W")
    check(sw.purchase(mochi, 3, bp: false) == .items("순백떡", 3) && sw.watts == 4400 && sw.count("순백떡") == 3 && sw.purchase(mochi, 23, bp: false) == nil && sw.watts == 4400,
          "3 순백떡 at once: -600W; more than the money covers: nothing happens")
    let shell = wB[Walk.bpShop.count + Walk.heldBP.count]                                                         // (3.7: after the 지닌 도구)
    check(sw.purchase(shell, 1, bp: true) == .shell("배틀 골드") && sw.bp == 160 && sw.canBuy(shell, bp: true) == 0 && sw.purchase(shell, 1, bp: true) == nil,
          "once-only (a device colour): bought once, then 보유")
    let shopV = online({ var s = Walk(); s.watts = 1000; s.bp = 30; return s }(), rng: 41)
    shopV.screen = .menu(menuAt("배틀 타워")); shopV.press(1); let tower = on(shopV) { if case .tower = $0 { return true }; return false }
    shopV.screen = .menu(menuAt("상점")); shopV.press(1)
    let opened = on(shopV) { if case .shop(false, 0, nil) = $0 { return true }; return false }
    shopV.press(2); shopV.press(1); shopV.press(2); shopV.press(2)                              // row 1 (좋은상처약 60W), how many: 3
    let three = on(shopV) { if case .shop(false, 1, 3?) = $0 { return true }; return false }
    shopV.press(1); drain(shopV)
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
    shopV.shopTap(2005); drain(shopV); check(shopV.state.count("은색병뚜껑") == 1 && shopV.state.bp == 5, "the panel's 구매 buys it")
    check(shopV.shopModel()?.hint.contains("받았다") == true && shopV.shopModel()?.qty == nil, "the panel stays up through the shop's message (shown in its box)")
    // a legend: how many, then 정말? (아니오 first), and never by a double-click or a held key
    let lg = online({ var s = Walk(); s.watts = 9999; return s }(), rng: 42)
    let hoOh = lg.wares(false).firstIndex { if case .legend(let k) = $0.kind { return Walk.legendShop[k].dex == 250 }; return false } ?? 0
    lg.screen = .shop(bp: false, sel: hoOh, qty: nil); lg.press(1); lg.press(1)                                             // 칠색조 (its tab, 전설), ● how many, ●
    let asked = on(lg) { if case .shopConfirm(false, _, false) = $0 { return true }; return false }
    lg.press(1); check(asked && lg.state.watts == 9999 && on(lg) { if case .shop(false, _, nil) = $0 { return true }; return false }, "칠색조: ● ● asks, and ● on 아니오 buys nothing")
    lg.press(1); lg.press(1); lg.press(2); lg.press(1); drain(lg)
    check(lg.state.watts == 0 && lg.state.legendBought(250) && (lg.state.box.last?.uid ?? 0) > 1_000_000, "… and ▶ 예 ● brings it (the server's 칠색조)")
    let dc = Walker(state: { var s = Walk(); s.watts = 1000; return s }()); dc.persist = false; dc.rng = Seeded(s: 43)
    dc.screen = .shop(bp: false, sel: 0, qty: nil); let shopLCD = dc.touch(48, 20); dc.shopTap(2100)
    let rowTap = on(dc) { if case .shop(false, 0, 1?) = $0 { return true }; return false }
    check(!shopLCD && rowTap && dc.state.watts == 1000, "a row on the pane opens how-many (the LCD never buys)")
    #if os(macOS)                                                                                 // the Mac: through its view's key map (36 = return)
    let heldReturn = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: true, keyCode: 36)!
    let dcv = WalkerView(walker: dc); dcv.keyDown(with: heldReturn)
    #else
    _ = dc.key(.enter, held: true)
    #endif
    check(dc.state.watts == 1000, "a held return doesn't buy")
    let hv = Walker(state: { var s = Walk(); s.companion = Mon(dex: 64, level: 20, female: false); return s }()); hv.persist = false   // 윤겔라: 통신 진화 needs nothing
    hv.screen = .menu(menuAt("포켓몬")); hv.press(1)                                                // the first press opens the grid
    for _ in 0..<4 { _ = hv.key(.enter, held: true) }                                             // it used to go on: the companion's page, then 통신 진화
    check(hv.state.companion.dex == 64 && on(hv) { if case .box(-1, nil, false, false) = $0 { return true }; return false }, "a held return opens 포켓몬 and stops there (no page, no evolution)", "\(hv.screen)")
    dc.shopStep(10); dc.listRow(1); check(on(dc) { if case .shop(false, 1, nil) = $0 { return true }; return false }, "scrolling the panel moves a row and leaves how-many (never the amount)")
    dc.screen = .shop(bp: false, sel: 0, qty: nil); check(dc.shopModel()?.hint.contains("●") == true, "the panel says what ● does")
    dc.screen = .shop(bp: false, sel: dc.wares(false).count - 1, qty: nil); check(dc.shopModel()?.hint == "W가 부족해요 · 9,999W 필요", "the panel says why a row can't be bought", "\(dc.shopModel()?.hint ?? "")")
    // 7g the Poké Ball card: the LCD 2 pt a dot at 보통, the keys on the band, the page under it growing down per screen
    let size0 = SIZE; SIZE = 2
    check(PX == 2 && K == 1 && devSize == CGSize(width: 216, height: 199) && lcdRect == CGRect(x: 12, y: 27, width: 192, height: 128),
          "보통: a 216 x 199 card, the LCD 192 x 128 (2 pt a dot: whole pixels on a 1x screen)", "\(devSize) \(lcdRect)")
    check(buttons.count == 5 && buttons.allSatisfy { $0.c.y == Layout.seam && $0.c.x - $0.r >= 0 && $0.c.x + $0.r <= Layout.w } && buttons[1].r > buttons[0].r && buttons.prefix(4).map(\.c.x) == buttons.prefix(4).map(\.c.x).sorted()
          && buttons[4].c.x + buttons[3].c.x == Layout.w * K, "메뉴 ◀ ● ▶ ↩ on the band, ● the ball's own bigger button, 메뉴 across from ↩")
    let gk = Walker(state: Walk()); gk.persist = false; gk.statusOpen = true                   // (not the user's own setting)
    #if os(macOS)
    let gw = WalkerView(walker: gk)                                                               // the Mac: its view, the host, follows the card
    #endif
    gk.refreshPane(Date(), force: true); let homeH = gk.cardH
    gk.screen = .menu(0); gk.refreshPane(Date(), force: true); let menuH = gk.cardH
    gk.screen = .dex(25, filter: 0, detail: false); gk.refreshPane(Date(), force: true); let gridH = gk.cardH
    gk.screen = .battle(wild, sel: 0); gk.refreshPane(Date(), force: true); let fightH = gk.cardH, hudUp = gk.hud == nil
    gk.statusOpen = false; gk.screen = .home; gk.refreshPane(Date(), force: true); let foldH = gk.cardH, foldChev = gk.chevron; gk.statusOpen = true
    gk.screen = .home; gk.refreshPane(Date(), force: true)
    #if os(macOS)
    let viewed = gw.frame.size == CGSize(width: 216, height: PaneContent.home) && gw.page.frame.minY == Layout.pane
    #else
    let viewed = true
    #endif
    check(homeH == 406 && menuH == 406 && gridH == 422 && fightH == 311 && gk.cardH == 406 && viewed && hudUp,
          "the card grows down to the page: 홈's status sheet 406 and the menu the same (the 메뉴 / 홈 key never resizes it), battle 311, a grid 422 (the page under the band)", "\(homeH) \(menuH) \(gridH) \(fightH) \(gk.cardH)")
    check(foldH == 199 && foldChev == false && gk.chevron == true, "⌄ folds home's status sheet: the idle card (199); open again: 406", "\(foldH)")
    SIZE = 3; check(PX == 3 && 422 * K < 850, "크게: 3 pt a dot, its tallest page still under a 13-inch screen's height"); SIZE = size0
    let pv = Walker(state: { var s = Walk(); s.box = [Mon(dex: 16, level: 5, female: false)]; return s }()); pv.persist = false; pv.statusOpen = true; pv.rng = Seeded(s: 61)
    func kind(_ sc: Screen) -> String {
        pv.screen = sc; let c = pv.paneContent(Date())
        return c.battle != nil ? "battle" : c.dex != nil ? "dex" : c.grid != nil ? "grid" : c.mon != nil ? "mon" : c.shop != nil ? "shop" : c.menu.map { "menu\($0.sel)" } ?? (c.status != nil ? "status" : "none")
    }
    check(kind(.home) == "status" && kind(.box(0, act: nil, confirm: false, detail: true)) == "mon" && kind(.menu(menuAt("트레이너 카드"))) == "menu\(menuAt("트레이너 카드"))" && kind(.battle(wild, sel: 0)) == "battle" && kind(.shop(bp: false, sel: 0, qty: nil)) == "shop" && kind(.dex(1, filter: 0, detail: true)) == "dex"
          && kind(.dex(1, filter: 0, detail: false)) == "grid" && kind(.box(0, act: nil, confirm: false)) == "grid",
          "the pane: the status sheet on 홈 (always: the card never shuts), 메뉴 tiles on the menu, the battle / 상점 pages, 도감 / 상자 grids, the dex entry, a box Pokémon's page")
    check(kind(.say(["기술의 남은", "PP가 없다!"], next: .moves(wild, sel: 0), since: Date())) == "battle" && kind(.say(["W가 부족하다"], next: .menu(menuAt("포켓 레이더")), since: Date())) == "menu0"
          && pv.paneContent(Date()).menu != nil, "a fight's / a menu page's message keeps its page up")
    pv.screen = .say(["기술의 남은", "PP가 없다!"], next: .moves(wild, sel: 0), since: Date()); check(pv.sideModel(Date())?.message == "기술의 남은 PP가 없다!", "… with the message in the battle page's box")
    #if os(macOS)                                                                                 // the Mac window's placement
    let grown = WalkerView.onScreen(NSRect(x: 2248, y: 24 + 288 - 376, width: 584, height: 376), in: NSRect(x: 0, y: 0, width: 2560, height: 1410))
    check(grown == NSRect(x: 1976, y: 0, width: 584, height: 376), "an old device at the bottom-right corner grows into the screen, not onto the next one", "\(grown)")
    #endif
    pv.screen = .menu(menuAt("포켓 레이더")); pv.menuTap(menuAt("포켓몬"))
    check({ if case .box = pv.screen { return true }; return false }(), "메뉴: a click on a tile opens it")
    // the walker's other pages: one click does what ● would
    let pt = online({ var s = Walk(); s.watts = 500; s.caught = [Mon(dex: 16, level: 5, female: false)]; s.items = ["상처약"]; return s }(), rng: 83)
    func pts(_ p: (Screen) -> Bool) -> Bool { p(pt.screen) }
    pt.screen = .menu(menuAt("포켓 레이더")); pt.press(1); drain(pt); var ptBush = -1
    if case .radar(let b, _, _, let ch) = pt.screen { ptBush = b; pt.screen = .radar(bush: b, cursor: 0, since: Date().addingTimeInterval(-2), chain: ch) }
    let rm = pt.paneContent(Date()).radar; pt.pageTap(5000 + max(0, ptBush)); drain(pt)
    check(ptBush >= 0 && rm?.live == ptBush && pts { if case .beats(_, let bs, _, _) = $0 { return bs.first == .appear }; return false }, "레이더: the rustling bush is marked on the pane, a click on it searches there")
    calm(pt)
    pt.screen = .card(0); pt.pageTap(5202); check(pts { if case .card(2) = $0 { return true }; return false } && pt.paneContent(Date()).card?.page == 2, "트레이너 카드: its pages are tabs")
    let ptW = pt.state.watts; pt.screen = .tower(pick: nil); let lobby = pt.paneContent(Date()).tower; pt.pageTap(5400); drain(pt)
    check(lobby?.party.count == 2 && lobby?.fee == Walk.towerFee && pt.state.watts == ptW - Walk.towerFee && pts { if case .beats = $0 { return true }; return false }, "배틀 타워: the party, and 도전 pays and starts")
    calm(pt)
    let tp = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 10, female: false); s.caught = [Mon(dex: 16, level: 20, female: false)]
        s.box = [Mon(dex: 1, level: 30, female: false), Mon(dex: 4, level: 5, female: false), Mon(dex: 7, level: 15, female: false)]; return s }())
    func tdex() -> [Int] { tp.state.party().map(\.mon.dex) }
    func tpick() -> TowerModel.Pick? { tp.paneContent(Date()).tower?.pick }
    tp.screen = .tower(pick: nil); let twRec = tdex(), twRecCustom = tp.paneContent(Date()).tower?.custom; tp.pageTap(5412); let twPk = tpick()
    check(twRec == [25, 1, 16] && twRecCustom == false && twPk?.slot == 2 && twPk?.count == 5 && twPk?.rows.map(\.name) == [1, 16, 7, 25, 4].map { monNames[$0] } && twPk?.rows.map(\.slot) == [1, 2, nil, 0, nil] && twPk?.sel == 1,
          "배틀 타워: the recommended party (the companion, then the strongest two); a party row opens everyone by level, on its own one, the party's marked")
    tp.pageTap(5432); drain(tp); let twPlaced = tdex(), twCustom = tp.paneContent(Date()).tower?.custom == true && tpick() == nil
    tp.pageTap(5410); tp.press(2); tp.press(1); drain(tp); let twByKeys = tdex()
    tp.pageTap(5411); tp.pageTap(5432); drain(tp); let twSwapped = tdex()
    check(twPlaced == [25, 1, 7] && twCustom && twByKeys == [4, 1, 7] && twSwapped == [4, 7, 1], "… a click on one puts it in the slot (추천으로 shows); ◀ ▶ ● do the same; picking one of the party swaps the two")
    let twSaved = (try? JSONDecoder().decode(Walk.self, from: JSONEncoder().encode(tp.state)))?.party().map(\.mon.dex)
    serve(tp) { $0.box.remove(at: 0) }; let twGone = tdex()
    tp.pageTap(5420); drain(tp); let twBack = tdex(), twPlain = tp.state.towerPick == nil && tp.paneContent(Date()).tower?.custom == false
    check(twSaved == [4, 7, 1] && twGone == [4, 7, 25] && twBack == [25, 16, 7] && twPlain, "… kept in the save, by who they are (one let go: the rest stay, topped up as recommended); 추천으로 goes back", "\(String(describing: twSaved)) \(twGone) \(twBack)")
    serve(tp) { $0.box += (10...14).map { Mon(dex: $0, level: 3, female: false) } }; tp.pageTap(5410); let twP1 = tpick(); tp.pageTap(5441); let twP2 = tpick(); _ = tp.key(.up); let twP3 = tpick()
    tp.pageTap(5440); let twWrapped = tpick(); tp.press(3); let twLobbyAgain = tpick() == nil && tp.paneContent(Date()).tower != nil; tp.press(3)
    check(twP1?.count == 9 && twP1?.rows.count == 5 && twP2?.first == 5 && twP2?.sel == 5 && twP2?.rows.count == 4 && twP3?.sel == 4 && twP3?.first == 0 && twWrapped?.first == 5 && twLobbyAgain
          && tp.paneContent(Date()).tower == nil && tp.state.party().map(\.mon.dex) == [25, 16, 7], "… five a page (▶ ◀ pages round, ↑ ↓ rows); ↩ leaves the picker, then the lobby")
    serve(tp) { $0.watts = 500 }; tp.screen = .tower(pick: nil); tp.pageTap(5411); _ = tp.key(.down); serve(tp) { $0.companion.level = 18 }; let twMoved = tpick()
    _ = tp.key(.enter, held: true); let twHeld = tpick() != nil; tp.press(1); drain(tp); let twAfter = tdex(); _ = tp.key(.enter, held: true); drain(tp)
    check(twMoved?.sel == 2 && twMoved?.rows[safe: 2]?.name == monNames[7] && twHeld && twAfter == [25, 7, 16] && tp.state.watts == 500 && tp.paneContent(Date()).tower != nil && tpick() == nil,
          "… the cursor stays on its Pokémon when a level-up reorders the list; a held ● neither picks again nor pays into a fight", "\(String(describing: twMoved)) \(twAfter)")
    // 1.3: the walker's team, the stickers, 코스, 배틀 속도, 특훈, 중복 놓아주기
    let nwSave: Walk = { var s = Walk(); s.watts = 500; s.earned = 100_000; s.caught = [Mon(dex: 16, level: 12, female: false)]; s.box = [Mon(dex: 19, level: 8, female: false)]; return s }()
    let nf = online(nwSave, rng: 41); nf.screen = .menu(menuAt("포켓 레이더")); nf.press(1); drain(nf)
    if case .radar(let b, _, _, let ch) = nf.screen { nf.screen = .radar(bush: b, cursor: b, since: Date().addingTimeInterval(-2), chain: ch) }
    nf.press(1); drain(nf)
    let nwFight: Battle? = { if case .beats(let b, _, _, _) = nf.screen { return b }; return nil }()
    check(nwFight?.mine.map(\.mon.dex) == [25, 16] && nwFight.map { nf.battleMenu($0) } == ["공격", "볼", "도구", "교체", "도망"] && server(nf).0.rows[server(nf).1]?.play.party?.count == 2 && nf.state.watts == 490,
          "a wild fight (the server's radar: 10 W) brings the walker's along: 공격 · 볼 · 도구 · 교체 · 도망")
    if var b = nwFight, var e = Optional(EngineRun(w: nf.state, p: Play(battle: b, party: [nf.state.companion.uid!, nf.state.caught[0].uid!]), r: Seeded(s: 1), now: Date(), ids: Issued(next: 2_000_000))) {
        var up = b.mine[1].mon; _ = up.gainBattleExp(5_000); b.mine[1].mon = up; _ = e.ended(&b, .won)
        check(e.w.caught[0].level > 12, "… and what the walker's one earned goes back to it (the server's after())")
    }
    let nw = online(nwSave, rng: 41)
    nw.screen = .home; let nwTap = nw.touch(9, 50); drain(nw)
    check(nwTap && nw.state.companion.dex == 16 && nw.state.caught[0].dex == 25 && nw.stickerRects.count == 1 && !nw.touch(60, 50), "a tap on the walker's sticker on home walks with it (the companion takes its place)")
    nw.screen = .menu(menuAt("코스")); nw.press(1); let cHere = nw.paneContent(Date()).course
    nw.pageTap(5801); let cPick = nw.paneContent(Date()).course; nw.pageTap(5820); drain(nw)
    check(cHere?.sel == 0 && cHere?.go == nil && cHere?.rows.first?.here == true && cPick?.sel == 1 && cPick?.go != nil && nw.state.course == 1 && nw.state.caught.count == 1,
          "코스 (the menu's): the list, a click picks one, 가기 walks it (the walker's team stays)")
    serve(nw) { $0.earned = 0 }; nw.screen = .course(2); let cLocked = nw.paneContent(Date()).course; nw.press(1); drain(nw)
    check(cLocked?.go == nil && cLocked?.rows[2].open == false && nw.state.course == 1, "… a locked one can't be walked")
    nw.screen = .beats(Battle(wild: rat, companion: pika50), [.appear], since: Date().addingTimeInterval(-Beat.appear.length / nw.battleSpeed - 0.01), from: Battle(wild: rat, companion: pika50))
    let fastEnd = nw.beatState(Date()) != nil; nw.tick(Date())
    check(nw.battleSpeed >= 1 && fastEnd && { if case .beats = nw.screen { return false }; return true }(), "배틀 속도 runs the beats' clock (x\(nw.battleSpeed))")
    serve(nw) { w in var m = Mon(dex: 25, level: 60, female: false, uid: w.companion.uid); m.ivs = [10, 31, 31, 31, 31, 31]; w.companion = m; w.bag = ["은색병뚜껑"] }
    nw.screen = .items(0); let capUse = nw.paneContent(Date()).items?.action; nw.press(1); nw.press(1); let trainPage = nw.paneContent(Date()).train   // (3.6: who, then which stat)
    nw.pageTap(5910); drain(nw)
    check(capUse?.contains("고르기") == true && trainPage?.sel == 0 && trainPage?.go != nil && nw.state.companion.effectiveIVs[0] == 31 && nw.state.count("은색병뚜껑") == 0, "은색병뚜껑: 도구 → who (the companion) → pick a stat → 특훈")
    serve(nw) { $0.box = [Mon(dex: 19, level: 8, female: false), Mon(dex: 19, level: 3, female: false), Mon(dex: 19, level: 5, female: false)] }
    nw.screen = .box(0, act: 0, confirm: true, detail: true); check(nw.paneContent(Date()).mon?.dupes == 2, "놓아줄까? also offers 중복 n마리 (that species' spares)")
    // 1.4: the walker's ones evolve too (after a fight they levelled in; at launch if they're already past it)
    var evW = Walk(); evW.caught = [Mon(dex: 16, level: 17, female: false), Mon(dex: 19, level: 15, female: false)]; let evU = [evW.id(-1)!, evW.id(-2)!, evW.id(-3)!]
    var evB = Battle(wild: rat, party: [evW.companion, evW.caught[0]]); var evUp = evB.mine[1].mon; _ = evUp.gainBattleExp(evUp.points); evB.mine[1].mon = evUp
    var evRun = EngineRun(w: evW, p: Play(battle: evB, party: [evU[0], evU[1]]), r: Seeded(s: 5), now: Date(), ids: Issued(next: 2_000_000)); _ = evRun.ended(&evB, .won); evRun.finish()
    check(evRun.w.caught[0].dex == 17 && evRun.w.companion.dex == 25 && evRun.out.news.contains(.evolve(uid: evU[1], from: 16, to: 17, shed: nil)),
          "a walker's 구구 that levels past 18 in a fight evolves at its end (the server's; the companion stays)", "\(evRun.out.news)")
    let ev = online({ var s = evW; s.caught[1].level = 25; return s }()); ev.cloud!.addSteps(1); ev.cloud!.saveNow(); drain(ev)
    let evShow: Bool = { if case .evolve(let f, let t, _) = ev.screen { return f.dex == 19 && t.dex == 20 }; return false }()
    check(evShow && ev.state.caught[1].dex == 20 && ev.state.caught[0].dex == 16, "a walker's 꼬렛 already past 20 evolves with the next steps, home shows it")
    // 1.14 (docs/plans/09): wild EXP = Gen V's scaled formula x 0.5; the tower gives no EXP / EVs, fights ours as Lv.50 copies, its trainers Lv.50 and better every 7 wins
    check([15, 30, 44, 70].map { Battle.wildExp(base: 150, foe: 30, mine: $0, share: 1) } == [822, 450, 285, 145] && Battle.wildExp(base: 150, foe: 30, mine: 30, share: 2) == 225,
          "1.14: wild EXP by level difference (Lv.30 foe, base 150: Lv.15 822 · 30 450 · 44 285 · 70 145), split among those that faced it")
    var b14r = Seeded(s: 21), b14 = Walk(); b14.companion = Mon.wild(150, level: 70, perfect: 3, &b14r); b14.caught = [Mon(dex: 129, level: 12, female: false)]
    b14.watts = 100; let b14v = online(b14, rng: 7); b14v.screen = .tower(pick: nil); b14v.press(1); drain(b14v)
    let b14B: Battle? = { if case .beats(let b, _, _, _) = b14v.screen { return b }; return nil }()
    let b14Capped = b14B.map { b in b.mine.map(\.mon.level) == [50, 50] && b.theirs.allSatisfy { $0.mon.level == 50 && ($0.mon.evs ?? []).allSatisfy { $0 == 0 } } && b.aiRandom == 5 } ?? false
    var b14Won = b14B!; b14Won.theirs[b14Won.it].hp = 0; b14Won.out = []; b14Won.faints()
    let b14NoExp = !b14Won.out.contains { if case .gained = $0 { return true }; return false }
    let b14Before = b14v.state.companion; var b14End = b14B!; b14End.mine[0].mon.level = 50; b14End.mine[0].mon.evs = [252, 0, 0, 0, 0, 252]
    var b14Run = EngineRun(w: b14v.state, p: Play(battle: b14End, tower: true), r: Seeded(s: 7), now: Date(), ids: Issued(next: 2_000_000)); _ = b14Run.ended(&b14End, .won)
    check(b14Capped && b14NoExp && b14Run.w.companion == b14Before && b14Run.w.towerStreak == 1 && b14v.state.watts == 50 && b14v.towerRun,
          "1.15: the tower fights a Lv.70 and a Lv.12 both as 50 (flat), its foes Lv.50, no EXP for a KO, and the Lv.70 is still 70 after it (nothing written back)")
    var b14Tiers: [Bool] = []
    for (streak, check) in [(0, { (m: Mon) in m.evs == nil && (m.known ?? []).allSatisfy { m.learnLevel($0).map { $0 <= 25 } ?? true } }), (7, { (m: Mon) in m.evs == nil && (m.ivs ?? []).allSatisfy { $0 >= 15 } }),
                            (14, { (m: Mon) in (m.evs ?? []).reduce(0, +) == 504 && (m.ivs ?? []).allSatisfy { $0 >= 15 } && m.known == nil }),
                            (21, { (m: Mon) in m.perfectIVs >= 3 && [3, 13, 15, 10].contains(m.nature ?? -1) && (1...4).contains(m.moves.count) && m.moves.allSatisfy { m.learnLevel($0).map { $0 <= 50 } ?? false } }),
                            (35, { (m: Mon) in m.perfectIVs == 6 && baseStats[m.dex].reduce(0, +) >= 450 })] as [(Int, (Mon) -> Bool)] {
        var b14s = b14; b14s.towerStreak = streak; var b14g = Seeded(s: UInt64(streak + 1))
        b14Tiers.append((0..<4).allSatisfy { _ in b14s.towerFoes(&b14g).foes.allSatisfy { $0.level == 50 && check($0) } })
    }
    check(b14Tiers == [true, true, true, true, true] && Walk.towerTier(6) == 0 && Walk.towerTier(7) == 1 && Walk.towerTier(99) == 5, "1.14: tower foes by 7 wins — as caught (3.1.2: Lv.25's moves) · IVs 15+ · EVs 252/252 · 3V, 고집/명랑/조심/겁쟁이, 좋은 4개 it learns · 5V · 6V with base stats 450+", "\(b14Tiers)")
    let b14Moves = Mon(dex: 149, level: 50, female: false).towerMoves()
    let wobb = Mon(dex: 202, level: 50, female: false).towerMoves(), arbok = Mon(dex: 24, level: 50, female: false).towerMoves(), blast = Mon(dex: 9, level: 50, female: false).towerMoves()
    check(wobb.contains { !moveTable[$0]!.isStatus } && !arbok.contains(256) && blast.filter { moveTable[$0]!.type == "water" && !moveTable[$0]!.isStatus }.count >= 2,
          "1.14: 좋은 4개 — 마자용 keeps 카운터 / 미러코트, 아보크 no 꿀꺽 without 비축하기, 거북왕 two water STAB", "\(wobb) \(arbok) \(blast)")
    let b14Mew = Mon.wild(150, level: 70, &b14r); let b14Mewv = online({ var s = Walk(); s.companion = b14Mew; s.watts = 50; return s }()); b14Mewv.screen = .tower(pick: nil); b14Mewv.press(1); drain(b14Mewv)
    check({ if case .beats(let b, _, _, _) = b14Mewv.screen { return b.mine[0].moves == b14Mew.moves && b.mine[0].mon.level == 50 }; return false }(), "1.14: a Lv.70 whose moves were never set fights as 50 with the moves it has at 70")
    check(b14Moves.count == 4 && Set(b14Moves.compactMap { moveTable[$0]?.type }).count >= 3 && b14Moves.allSatisfy { ![120, 153, 264].contains($0) }, "1.14: 좋은 4개 (망나뇽): four, three types or more, no 자폭 / 힘껏펀치", "\(b14Moves.compactMap { moveTable[$0]?.name })")
    // 1.14: wild levels banded by when a course opens (W, or the dex count), each course's order kept; chains +2 a link up to +20
    let bandsOK = courses.allSatisfy { c in
        guard let b = courseBands[c.name], let raw = rawCourses.first(where: { $0.name == c.name }) else { return false }
        let lv = c.all.map(\.level), rl = raw.all.map(\.level)
        let kept = zip(rl, lv).allSatisfy { a in zip(rl, lv).allSatisfy { b2 in a.0 < b2.0 ? a.1 <= b2.1 : true } }
        return lv.min() == b.lowerBound && lv.max() == b.upperBound && kept && zip(raw.all, c.all).allSatisfy { $0.dex == $1.dex && $0.steps == $1.steps }
    }
    let byWatts = courses.filter { $0.dex == 0 }.map { ($0.watts, courseBands[$0.name]!.upperBound) }.sorted { $0 < $1 }.map(\.1)
    check(courseBands.count == courses.count && bandsOK && byWatts == byWatts.sorted() && courses.last { $0.dex == 0 }.map { courseBands[$0.name] == 52...65 } == true,
          "1.14: every course (W and dex) banded — its lowest at the band's bottom, highest at the top, order and species kept, later courses higher",
          "\(courses.filter { c in courseBands[c.name].map { b in c.all.map(\.level).min() != b.lowerBound || c.all.map(\.level).max() != b.upperBound } ?? true }.map { "\($0.name) \($0.all.map(\.level))" }) \(byWatts)")
    check([0, 1, 3, 10, 15].map(Walk.chainLevel) == [0, 2, 6, 20, 20], "1.14: a radar chain's wild ones +2 levels a link, up to +20")
    var cb = Battle(wild: Mon(dex: 19, level: 30, female: false), companion: Mon(dex: 25, level: 30, female: false)); _ = cb.begin(weather: nil, &r)
    cb.out = []; _ = cb.throwBall(255); let ce = Battle.wildExp(base: baseExp[19], foe: 30, mine: 30, share: 1)
    check(cb.out.contains(.gained(exp: ce, level: nil, foe: 19, to: 0)) && cb.out.last == .caught && cb.mine[0].mon.points == expTable[growthRate[25]][30] + ce && (cb.mine[0].mon.evs?[5] ?? 0) == evYield[19][5],
          "1.14: a catch pays EXP and EVs as a KO would (before the end beat)", "\(cb.out)")
    // 1.13: the walker's get 1 EXP per 2 steps (single steps add up), no friendship; a level-up queues its evolution (home plays it)
    var wx = Walk(); wx.caught = [Mon(dex: 16, level: 17, female: false), Mon(dex: 19, level: 5, female: false)]
    let wx0 = wx.caught.map(\.points), cw0 = wx.companion.points
    wx.walk(1, at: Date()); wx.walk(1, at: Date()); wx.walk(1, at: Date()); wx.walk(5, at: Date()); wx.walk(2, at: Date())   // keys one by one, a click's 5 at once
    let wxHalf = wx.caught.map(\.points) == wx0.map { $0 + 5 } && wx.companion.points == cw0 + 10 && wx.caught.allSatisfy { ($0.walked ?? 0) == 0 }
    wx.walk(2 * (expTable[growthRate[16]][18] - wx.caught[0].points), at: Date())
    check(wxHalf && wx.caught[0].level == 18 && wx.evolving?.first == wx.caught[0].uid && wx.caught[1].level > 5, "1.13: the walker's get 1 EXP per 2 steps (10 steps = 5), no friendship; 구구 reaching 18 queues its evolution", "\(wx.caught.map(\.points)) \(wx0)")
    // 1.12 (3.0: the server's news): what a fight brought plays right after it, then where it was going — the tower's lobby, the chain's next bush (its clock from then)
    var grS = Walk(); grS.companion = Mon(dex: 148, level: 30, female: false); grS.companion.known = [35, 43]; let grU = grS.id(-1)!
    let grw = online(grS); grw.towerRun = true
    grw.news = [.level(uid: grU, level: 30), .evolve(uid: grU, from: 147, to: 148, shed: nil)]; grw.fightEnd = BattleEnd(result: "won", streak: 1, bp: 3)
    grw.screen = grw.endOfFight(Battle(party: [grw.state.companion], trainer: "트레이너", foes: [rat]), Date())
    let gSay: Bool = { if case .say(let l, .home, _) = grw.screen, l.first == "1연승!", case .tower(nil)? = grw.growthThen { return true }; return false }()
    grw.press(1); let gEvo: Bool = { if case .evolve(let f, let t, _) = grw.screen { return f.dex == 147 && t.dex == 148 }; return false }()
    grw.tick(Date() + 7)
    check(gSay && gEvo && { if case .tower(nil) = grw.screen { return true }; return false }() && grw.growthThen == nil,
          "a tower win: 미뇽 that reached 30 (the fight's held steps, the server's news) evolves right after the fight's line, then the lobby")
    var gpS = Walk(); gpS.companion = Mon(dex: 25, level: next.0, female: false); gpS.companion.known = [84, 45, 39, 86].filter { $0 != next.1 }.prefix(4).map { $0 }; let gpU = gpS.id(-1)!; gpS.learning = [gpU, next.1]
    let gp = online(gpS); gp.towerRun = true
    gp.news = [.learn(uid: gpU, move: next.1, learned: false)]; gp.fightEnd = BattleEnd(result: "won", streak: 1, bp: 3)
    gp.screen = gp.endOfFight(Battle(party: [gp.state.companion], trainer: "트레이너", foes: [rat]), Date()); gp.press(1); let gpLearn: Bool = { if case .learn = gp.screen { return true }; return false }()
    gp.press(3); gp.press(1); drain(gp); gp.press(1); drain(gp)
    check(gpLearn && gp.state.companion.moves.count == 4 && (gp.state.learning ?? []).isEmpty && { if case .tower(nil) = gp.screen { return true }; return false }(), "… a new move to learn: the forget-one screen comes first, then the lobby")
    let ghk = Walker(state: grS); ghk.persist = false; ghk.growthThen = .tower(pick: nil)
    ghk.screen = .say(["3연승!"], next: .home, since: Date()); ghk.press(4); let ghkHome: Bool = { if case .home = ghk.screen { return true }; return false }() && ghk.growthThen == nil
    ghk.growthThen = .tower(pick: nil); ghk.lastInput = .distantPast; ghk.screen = .home; ghk.tick(Date()); ghk.tick(Date() + 1)
    let ghkLobby: Bool = { if case .tower(nil) = ghk.screen { return true }; return false }()
    ghk.state.companion.known = [84, 45, 39, 86]; ghk.state.learning = [ghk.state.id(-1)!, rlw.companion.relearnable.first { ![84, 45, 39, 86].contains($0) }!]; ghk.screen = .learn(sel: 0)
    let ghkHeld = ghk.key(.enter, held: true) && { if case .learn(0) = ghk.screen { return true }; return false }()
    check(ghkHome && ghkLobby && ghkHeld, "… 메뉴/홈 on the fight's message stays home; the lobby it hands over to doesn't time out at once; a held ● can't pick on the forget-one screen")
    let gch = online(grS); let (gchSrv, gchKey) = server(gch); gchSrv.rows[gchKey]?.play.chain = 3
    gch.news = [.evolve(uid: grU, from: 147, to: 148, shed: nil)]; gch.chainNext = 3
    gch.screen = .home; gch.tick(Date()); let gEvo2: Bool = { if case .evolve = gch.screen { return true }; return false }()
    let gT = Date(); gch.tick(gT + 7); let gLine = { if case .say(let l, _, _) = gch.screen { return l == ["연쇄 3!", "풀숲이 흔들린다"] }; return false }(); drain(gch)
    check(gEvo2 && gLine && { if case .radar(_, 0, let since, 3) = gch.screen { return since >= gT }; return false }() && gchSrv.rows[gchKey]?.play.radar?.chain == 3 && gch.state.watts == grS.watts,
          "… a chain: its next bush is asked for after the evolution (free), its window starting then")
    pt.screen = .menu(menuAt("포켓몬")); pt.press(1); let g0 = pt.paneContent(Date()).grid
    check(pts { if case .box(-1, nil, false, false) = $0 { return true }; return false } && g0?.party.map(\.dex) == [25, 16] && g0?.partySel == 0 && g0?.items == 1
          && pt.paneContent(Date()).height == 472, "포켓몬: the companion (picked first) and the walker's in a row over the box, then the items' chip")
    pt.gridTap(4510); let itemsUp = pt.paneContent(Date()).items?.rows.map(\.name) == ["상처약"] && pts { if case .items = $0 { return true }; return false }; pt.press(3)
    pt.gridTap(4501); let walkerPicked = pt.paneContent(Date()).grid?.partySel == 1; pt.gridTap(4501); let walkerPage = walkerPicked && pt.paneContent(Date()).mon?.place == 1; pt.gridTap(4400); drain(pt)
    check(itemsUp && walkerPage && pt.state.companion.dex == 16 && pt.state.caught.first?.dex == 25, "… the items' chip opens the 도구 page; on one of the walker's, 함께 걷기 makes it the companion")
    pt.screen = .box(-1, act: nil, confirm: false, detail: true); pt.gridTap(4400); let idle = pt.state.companion.dex == 16 && pt.paneContent(Date()).mon?.place == 0
    pt.screen = .box(-2, act: nil, confirm: false, detail: true); pt.gridTap(4404); drain(pt)
    check(idle && pt.state.caught.isEmpty && pt.state.box.last?.dex == 25 && pts { if case .say(_, .box(0, nil, false, false), _) = $0 { return true }; return false },
          "… the companion's own page has nothing to do; 상자로 보내기 moves one of the walker's into the box, picked there")
    let pgv = online({ var s = Walk(); s.box = (1...31).map { Mon(dex: $0, level: 5, female: false) }; return s }())
    pgv.screen = .box(-1, act: nil, confirm: false); pgv.gridTap(4201); let pageOn = pgv.paneContent(Date()).grid?.page == 2
    pgv.screen = .box(-1, act: nil, confirm: false); pgv.gridTap(4200); let pageRound = pgv.paneContent(Date()).grid?.page == 2
    serve(pgv) { $0.box = [Mon(dex: 1, level: 5, female: false)] }; pgv.screen = .box(0, act: 1, confirm: true, detail: true); pgv.press(1); drain(pgv)
    check(pageOn && pageRound && pgv.state.box.isEmpty && { if case .say(_, .box(-1, nil, false, false), _) = pgv.screen { return true }; return false }(),
          "포켓몬: from the row above the pager still turns the box's pages (◀ round to the last); letting the last one go picks the companion")
    // 도구: the walker's and the bag's together, and what each does from there; 워커로; how a Pokémon evolves, and the companion's evolving now
    let iv = online({ var s = Walk(); s.items = ["상처약"]; s.bag = ["이상한사탕", "금구슬", "금속코트"]; s.companion = Mon(dex: 95, level: 20, female: false)
                                 s.box = [Mon(dex: 16, level: 5, female: false)]; return s }(), rng: 91)
    iv.screen = .items(0); let im = iv.paneContent(Date()).items
    iv.pageTap(5600 + (im?.rows.firstIndex { $0.name == "이상한사탕" } ?? 0)); let candyAct = iv.paneContent(Date()).items?.action; iv.pageTap(5700); iv.press(1); drain(iv)
    check(im?.rows.map(\.name).sorted() == ["금구슬", "금속코트", "상처약", "이상한사탕"] && im?.rows.first { $0.name == "상처약" }?.onWalker == 1 && im?.walker == 1 && im?.bag == 3
          && candyAct == "쓸 포켓몬 고르기" && iv.state.companion.level == 21 && iv.state.count("이상한사탕") == 0,
          "도구: the walker's and the bag's in one list (워커 marked); a row's button uses it (이상한사탕: +1 level)")
    iv.screen = .box(-1, act: nil, confirm: false, detail: true); let onix = iv.paneContent(Date()).mon
    check(onix?.evos.first?.contains("강철톤 · 교환") == true && onix?.evos.first?.contains("(있음)") == true && onix?.evos.contains { $0 == "교환하면 받는 쪽에서 진화해요" } == true && onix?.evoAction == nil,
          "a Pokémon's page: how it evolves (교환 · 금속코트 in the bag: 있음); no solo 통신 진화 button any more (12 §3: a real trade evolves it)", "\(String(describing: onix?.evos)) \(String(describing: onix?.evoAction))")
    let acts0 = server(iv).0.acts.count; iv.gridTap(4406); drain(iv); check(server(iv).0.acts.count == acts0 && iv.state.companion.dex == 95, "… and its spot does nothing (롱스톤 stays)")
    iv.screen = .box(0, act: nil, confirm: false, detail: true); let fetchable = iv.paneContent(Date()).mon?.fetch == true; iv.gridTap(4407); drain(iv)
    check(fetchable && iv.state.box.isEmpty && iv.state.caught.last?.dex == 16 && { if case .say(_, .box(-2, nil, false, false), _) = iv.screen { return true }; return false }(),
          "the box's: 워커로 brings it back onto the walker (picked there)")
    pt.screen = .say(["W가 부족하다"], next: .menu(menuAt("포켓 레이더")), since: Date()); pt.menuTap(menuAt("트레이너 카드"))
    check(pts { if case .card(0) = $0 { return true }; return false }, "a click on a page still up under its message ends the message and counts")
    #if os(macOS)                                                                                 // the Mac: through its view's key map (48 = tab)
    let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
    let ptv = WalkerView(walker: pt); func pressTab() { ptv.keyDown(with: tab) }
    #else
    func pressTab() { _ = pt.key(.tab) }
    #endif
    pt.screen = .dex(1, filter: 0, detail: false); pressTab(); let tabbed = pts { if case .dex(_, 1, false) = $0 { return true }; return false }
    pt.screen = .home; pt.statusOpen = true; pressTab(); let folded = !pt.statusOpen && pt.chevron == false; pressTab()
    check(tabbed && folded && pt.statusOpen, "Tab: a grid's next tab; on home, folds / unfolds the status sheet")
    let stm = pv.statusModel(); check(stm.level == "Lv.5" && stm.numbers.count == 3 && stm.rows.map(\.key) == ["알", "배틀 타워", "도감", "레이드", "친구"] && stm.exp >= 0 && stm.exp <= 1, "the status sheet: level, EXP to next, today / W / total, egg / tower / dex / 레이드 / 친구")
    #if os(macOS)
    let frameTimer = { (v: Walker) -> [(Bool, String)] in                                        // the frame timer is the Mac view's
        let mac = WalkerView(walker: v)
        v.screen = .dex(25, filter: 0, detail: true); mac.tick(nil); let fast = mac.fast != nil
        v.animOn = ("dex", 25, .distantPast); mac.tick(nil)
        return [(fast && mac.fast == nil, "an animation plays at 30 fps, then back to the tick's 10")]
    }
    #else
    let frameTimer = { (_: Walker) -> [(Bool, String)] in [] }                                    // P3: Windows' SetTimer shell
    #endif
    for (ok, name) in routeChecks() + ballChecks() + moveChecks() + walkChecks() + animChecks(timer: frameTimer) + notebookChecks() + stepGateChecks() + signChecks() + ed25519Checks() + cloudChecks() + actChecks() + tradeChecks() + raidChecks() + socialChecks() + itemChecks() + duelChecks() + updateFixtureChecks() + updateChecks() { check(ok, name) }   // the drawing files' own checks
    print(failed == 0 ? "PASS \(total) checks" : "FAIL \(failed)/\(total)")
    return failed == 0
}
