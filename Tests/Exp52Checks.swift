import Foundation
// 5.2 (docs/plans/19 §11, content52; Core/Exp52.swift): 전설 원정 with the eight — self-test checks (run by selftest()): the page's kind tabs and
// rows, starting 토네로스, a meeting (its HP carried in, the turns left, gone after 3: "토네로스는 도망쳤다..." with no 야생, the HP said after),
// 랜드로스 waiting for both, the boss of 테라키온 (its party, 3 bars, 후퇴: the day's one fight gone) and its ball stage (나중에 던지기 keeps the
// balls; a throw at a time till it's caught or they're gone), 케르디오's companion, 레쿠쟈's three steps, 홈's row (the one going on first),
// and the LCD's words inside at any font on every tab.

@MainActor func exp52Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    /// The fight played to its end: the first move each turn (or 후퇴 / 도망 at once), the beats run out.
    func fightOut(_ w: Walker, leave: Bool = false) {
        var n = 0
        while n < 200, w.inBattle || { if case .beats = w.screen { return true }; return false }() {
            n += 1
            switch w.screen {
            case .beats: playOut(w)
            case .battle(let b, _): w.screen = .battle(b, sel: leave ? w.battleMenu(b).count - 1 : 0); w.press(1); drain(w)
            case .moves(let b, _): w.screen = .moves(b, sel: 0); w.press(1); drain(w)
            case .party(let b, _): w.screen = .party(b, sel: b.mine.indices.first { b.mine[$0].alive } ?? 0); w.press(1); drain(w)
            case .say: w.press(1)
            default: n = 999
            }
        }
    }
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) { Content.$testing52.withValue(true) {
        // a sturdy companion with a move that does nothing to a roamer: three turns, and it runs off
        var s = Walk(); s.companion = Mon(dex: 242, level: 100, female: true); s.companion.known = [45]
        s.caught = [Mon(dex: 150, level: 100, female: false)]; s.caught[0].known = [94, 85, 58, 247]
        let w = online(s), (srv, _) = server(w), now = Int(Date().timeIntervalSince1970)
        srv.expEvents = [TeamEventView(id: 1, legend: 648, starts: now - 2 * 86_400, ends: now + 3 * 86_400, goal: 1_500_000, min: 20_000, team: 931_200, mine: 12_400, got: false)]
        w.open("전설 원정"); drain(w)
        w.exp52Tab(1)
        let roamRows = w.exp52Pane(0).exp?.rows ?? []
        check(w.exp52Pane(0).exp?.tabs == Walker.expTabs && roamRows.map(\.name) == ["토네로스", "볼트로스", "랜드로스"] && roamRows[0].note == "시작 전" && roamRows[2].locked
              && roamRows[2].note == "토네로스 · 볼트로스를 먼저" && w.exp52Pane(2).exp?.go == nil,
              "5.2 전설 원정: the kinds' tabs (지금 · 배회 · 시련 · 수집 · 팀 · 예정); 배회's three, 랜드로스 waiting for both (no button)", "\(roamRows)")
        w.screen = .expedition(0); w.press(1); drain(w)                                                 // 시작하기
        let started = served(w)?.expeditions?["토네로스"]?.on == true && says(w) == ["토네로스 원정을", "시작했다!"]
        serve(w) { $0.expeditions?["토네로스"]?.meets = 1; $0.expeditions?["토네로스"]?.hp = 40; $0.expeditions?["토네로스"]?.status = .paralysis }
        w.screen = .expedition(0)
        let page = w.exp52Pane(0).exp, roamer = Expeditions.of("토네로스")!
        let hpLine = page?.hpNote == "\(w.pct(w.roamHP(roamer, w.expProgress(roamer))))% · 마비" && page?.place.hasPrefix("오늘 토네로스: 하나") == true && page?.go == "만나기 · 만남 1번"
        w.press(1); drain(w)                                                                            // 만나기: a meeting, its HP and status carried in
        var meet: Battle? = w.fight
        if meet == nil, case .beats(let b, _, _, _) = w.screen { meet = b }
        let carried = meet?.theirs[0].hp == 40 && meet?.theirs[0].status == .paralysis && meet?.expedition == "토네로스" && meet?.raidTier == nil
        playOut(w)
        let turns = w.paneContent(Date()).battle?.turnsLeft == 3 && w.title().title == "배회 전설"
        fightOut(w)
        let fled = served(w)?.expeditions?["토네로스"]?.hp == 40 && served(w)?.expeditions?["토네로스"]?.meets == 0
            && says(w).first == "남은 HP \(w.pct(40.0 / Double(roamer.steps.isEmpty ? 1 : max(1, w.expProgress(roamer).mon!.stats[0]))))%는"
        let noWild = meet.map { w.beatLine(.fled, 0, $0) } == "토네로스는 도망쳤다..."
        check(started && hpLine && carried && turns && fled && noWild,
              "5.2 배회: 시작하기 → .expStart; 오늘 위치 · 남은 HP · 마비 · 만나기 (a meeting banked) → its fight with the HP and status it left with (3 turns: 남은 턴), gone after the third (\"토네로스는 도망쳤다...\", no 야생), the HP said and kept",
              "\(started) \(hpLine) \(String(describing: page?.hpNote)) \(String(describing: page?.place)) \(String(describing: page?.go)) \(carried) \(turns) \(fled) \(says(w)) \(noWild)")

        // 시련: 테라키온's walk done → the boss (its party, 3 bars, 후퇴 ends the day), then a win's ball stage (kept when left, thrown one by one)
        var x = ExpProgress(on: true, mon: Expeditions.legend(639, &srv.rng), stage: 1)
        serve(w) { $0.expeditions?["토네로스"]?.on = false; $0.expeditions?["테라키온"] = x }
        w.exp52Tab(2); w.screen = .expedition(1)
        let bossPage = w.exp52Pane(1).exp
        let strip = bossPage?.steps.map(\.state) == [2, 1, 0] && bossPage?.go == "보스전 · 오늘 1번"
        w.press(1)
        var squadOK = false; if case .squad(let q) = w.screen, case .exp("테라키온") = q.kind { squadOK = true }
        if case .squad(let q) = w.screen { w.squadGo(Squad(kind: q.kind, picked: [w.state.caught[0].uid!], at: 1), Date()); drain(w) }
        playOut(w)
        let boss = w.fight, bossUI = boss.map { w.battleMenu($0).last == "후퇴" && $0.theirs.count == 3 && w.paneContent(Date()).battle?.bars?.total == 3 } == true
        fightOut(w, leave: true)                                                                        // 후퇴: the day's one fight is gone
        let retreated = says(w) == ["결전에서 물러났다", "오늘은 끝 · 내일 다시"] && served(w)?.expeditions?["테라키온"]?.fought == Walk.key(Date())
        w.screen = .expedition(1)
        let tomorrow = w.exp52Pane(1).exp?.go == nil && w.exp52Pane(1).exp?.rows[1].note == "오늘은 싸웠어요"
        x = served(w)!.expeditions!["테라키온"]!; x.balls = 5; x.fought = Walk.key(Date())
        serve(w) { $0.expeditions?["테라키온"] = x }
        let ballsGo = w.exp52Pane(1).exp?.go == "볼 던지기 · 남은 5개" && w.expDot
        w.press(1)
        let stageOK = w.paneContent(Date()).raidBalls.map { $0.exp && $0.balls == 5 && $0.of == 5 } == true
        w.pageTap(7041)                                                                                 // 나중에 던지기: the balls stay
        let kept = { if case .expedition = w.screen { return true }; return false }() && served(w)?.expeditions?["테라키온"]?.balls == 5
        w.press(1); var tries = 0
        while tries < 6, case .raid(.expBalls) = w.screen { w.calmAt = .distantPast; w.press(1); drain(w); playOut(w); tries += 1; while case .say = w.screen { w.press(1) } }
        let after = served(w)?.expeditions?["테라키온"]
        let thrown = (after?.done == 1 && after?.mon == nil && w.state.box.contains { $0.dex == 639 }) || (after?.balls == nil && after?.done == 0 && after?.mon != nil)
        check(strip && squadOK && bossUI && retreated && tomorrow && ballsGo && stageOK && kept && thrown && tries >= 1,
              "5.2 시련: 테라키온's steps (산 코스 ✓ → 보스전 → 볼), 보스전 · 오늘 1번 → its party (1–3) → the boss's fight (3 bars, 후퇴), 후퇴 ends the day (오늘은 싸웠어요); a win's 5 balls: 나중에 던지기 keeps them, thrown till caught or gone",
              "\(strip) \(String(describing: bossPage?.steps)) \(String(describing: bossPage?.go)) \(squadOK) \(bossUI) \(retreated) \(says(w)) \(tomorrow) \(ballsGo) \(stageOK) \(kept) \(thrown) \(tries) \(String(describing: after))")

        // 케르디오 (after the three): its companion's steps; 레쿠쟈's three steps; 홈's row: the one going on, before the team event
        serve(w) { for id in ["코바르온", "테라키온", "비리디온"] { $0.expeditions?[id] = ExpProgress(done: 1) }; $0.expeditions?["케르디오"] = ExpProgress(on: true, steps: 4_200, mon: Mon(dex: 647, level: 50, female: false)) }
        let kel = Expeditions.of("케르디오")!
        w.screen = .expedition(3)
        let kRow = w.exp52Words(kel)
        let keldeo = !w.expLocked(kel) && kRow.note == "동행 4,200/1만" && w.exp52Detail(.exp(kel)).act == .companion
        serve(w) { $0.expeditions?["케르디오"]?.on = false; $0.expeditions?["레쿠쟈"] = ExpProgress(on: true, n: 7, mon: Mon(dex: 384, level: 50, female: false)) }
        let ray = Expeditions.of("레쿠쟈")!, rs = w.expStrip(ray)
        let rayquaza = rs.map(\.title) == ["운석 조각", "산 코스", "결전"] && rs.map(\.state) == [1, 0, 0] && rs[0].sub == "7/20" && w.exp52Words(ray).note == "1단계 · 조각 7/20"
        let home = w.statusModel().rows.last
        check(keldeo && rayquaza && home?.value.hasPrefix("레쿠쟈 · 1단계") == true,
              "5.2 케르디오 (its companion's steps, 동행 바꾸기), 레쿠쟈's three steps (운석 조각 → 산 코스 → 결전), 홈's row: the one going on before the team event",
              "\(keldeo) \(kRow) \(rayquaza) \(rs) \(String(describing: home))")

        // every tab's rows on the LCD inside, at any font
        var bad: [String] = []
        for k in [1.0, 1.15] {
            textWidthScale = k; defer { textWidthScale = 1 }
            for t in Walker.expTabs.indices {
                w.exp52Tab(t)
                for r in 0..<max(1, w.expRows(t).count) { w.screen = .expedition(r); let fb = w.compose(Date()); bad += lcdOverlaps(fb) + fb.runs.filter { $0.x < 0 || $0.x + $0.w > 96 }.map { "×\(k) \(t)/\(r): \($0.s)" } + runClashes(fb.runs) }
            }
        }
        check(bad.isEmpty, "5.2 전설 원정's LCD: every tab's every row inside at any font", "\(bad.prefix(6))")
        w.exp52Tab(0)
    } } }
    return c
}
