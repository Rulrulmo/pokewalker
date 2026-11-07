import Foundation
// 5.3 (docs/plans/19 §12, content53; Core/Exp53.swift; the mockups lcd-mockups docs/mockups/v5.3): 협동 · 스토리 — self-test checks (run by
// selftest()): the seven tabs and their rows; 짝 청하기 from the 협동 tab (the friends, one in a pair dimmed) and from a friend's card (my dragon
// first), the ask on the other side (its news, the row, my dragon's two cards) → a pair walking together (the panel, both saves on their
// dragons), 짝 풀기 and switching away (asked first: the pair ends, the other told), the walk done → the boss; the story's scenes once each
// (the start, the trainer's, the win's after it), a 플레어단 fight (its title, its picture, no turns), the 칼로스 도감 gate passing by itself,
// the pick (expPick) and its scene, the final fight's win and its scene, 5장 with the other one; and every scene of the mockups — the worst
// cases too (a 12-letter ID, 29만/30만, the longest lines) — readable at 크기 2 · 3 · 4 with the LCD inside, as drawn and 15 % wider.

@MainActor func exp53Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func act(_ w: Walker, _ n: Int = 1) { w.news = []; w.screen = .home; w.cloud!.addSteps(n); w.cloud!.saveNow(); drain(w); drain(w) }
    func team(_ w: Walker) { w.cloud!.teamDue = true; w.cloud!.expeditionDue = true; w.cloud!.tick(Date()); drain(w); drain(w) }
    func tab(_ w: Walker, _ name: String, _ row: String? = nil) {
        w.expTab = Walker.expTabs.firstIndex(of: name) ?? 0
        let rows = w.expRows(w.expTab)
        w.screen = .expedition(row.flatMap { n in rows.firstIndex { if case .exp(let e) = $0 { return e.id == n }; if case .ask(let a) = $0 { return "ask:" + a.with == n }; return false } } ?? 0)
    }
    func fightOut(_ w: Walker) {
        var n = 0
        while n < 300, w.inBattle || { if case .beats = w.screen { return true }; return false }() {
            n += 1
            switch w.screen {
            case .beats: playOut(w)
            case .battle(let b, _): w.screen = .battle(b, sel: 0); w.press(1); drain(w)
            case .moves(let b, _): w.screen = .moves(b, sel: 0); w.press(1); drain(w)
            case .party(let b, _): w.screen = .party(b, sel: b.mine.indices.first { b.mine[$0].alive } ?? 0); w.press(1); drain(w)
            case .say: w.press(1)
            default: n = 999
            }
        }
    }
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) { Content.$testing52.withValue(true) { Content.$testing53.withValue(true) {
        let srv = FakeCloud(), ha = TestHost(), hb = TestHost()
        func strong() -> Walk {
            var s = Walk(); s.companion = Mon(dex: 150, level: 100, female: false); s.companion.known = [85, 58, 94, 247]   // (10만볼트 first: 델빌 is dark)
            s.caught = [Mon(dex: 94, level: 100, female: false)]; s.caught[0].known = [188, 247, 94, 85]; return s
        }
        let a = online(strong(), server: srv, host: ha), b = online(strong(), server: srv, host: hb), d = online(Walk(), server: srv), o = online(Walk(), server: srv)
        srv.befriend(a.myName, b.myName); srv.befriend(a.myName, d.myName); srv.befriend(a.myName, o.myName); srv.oldApps53 = [o.myName.lowercased()]   // o: before 5.3 (no app53)
        act(b); act(d); act(o); team(a); team(b)
        let ka = a.myName.lowercased(), kb = b.myName.lowercased()

        // the tabs and rows
        a.open("전설 원정"); drain(a)
        let tabs = a.exp52Pane(0).exp?.tabs == ["지금", "배회", "시련", "수집", "협동", "스토리", "팀"]
        tab(a, "협동"); let coop = a.exp52Pane(0).exp?.rows ?? []
        tab(a, "스토리"); let story = a.exp52Pane(0).exp?.rows ?? []
        check(tabs && coop.map(\.name) == ["레시라무", "제크로무", "큐레무"] && coop[2].locked && coop[2].note == "레시라무 · 제크로무를 먼저"
              && story.map(\.name) == ["칼로스 이야기", "칼로스 이야기 5장"] && story[1].locked && story[1].note == "칼로스 이야기를 먼저",
              "5.3 전설 원정: seven tabs (지금 · 배회 · 시련 · 수집 · 협동 · 스토리 · 팀); 협동's 레시라무 · 제크로무 · 큐레무 (waiting for both), 스토리's 칼로스 이야기 · 5장 (waiting for it)",
              "\(tabs) \(coop.map { ($0.name, $0.note) }) \(story.map { ($0.name, $0.note) })")

        // 짝 청하기 from the 협동 tab: the friends (one in a pair dimmed: d's pair is a fake one), the ask
        srv.pairList.append(FakeCloud.FakePair(id: 99, a: d.myName.lowercased(), aName: d.myName, b: "zzother", bName: "zzother", aExp: "제크로무", bExp: "레시라무", state: "on", ends: srv.clockNow + 86_400))
        team(a)
        tab(a, "협동", "레시라무")
        let firstPage = a.exp52Pane(0).exp
        a.press(1)
        var picked = false; if case .pairPick(643, _) = a.screen { picked = true }
        let friends = a.paneContent(Date()).pairPick, rowB = friends?.rows.firstIndex { $0.name == b.myName }, rowD = friends?.rows.first { $0.name == d.myName }
        let rowO = friends?.rows.first { $0.name == o.myName }, cardO = a.teamRows(0).first { $0.card.name == o.myName }.map { a.pairCardButton($0.card) }
        a.screen = .pairPick(dex: 643, sel: rowB ?? 0); a.press(1); drain(a)
        let asked = ha.asked.last == b.myName + "에게 짝을 청할까요?" && srv.acts.contains(.pairInvite(to: b.myName, id: "레시라무")) && says(a).last == "3일 안에 받으면 짝이 돼요"
        team(a); tab(a, "협동", "레시라무")
        let sentRow = a.exp52Pane(0).exp?.rows.first, sentGo = a.exp52Pane(0).exp?.go
        check(firstPage?.go == "짝 청하기" && firstPage?.go2 == "혼자 시작" && firstPage?.steps.map(\.title) == ["함께 걷기", "보스전", "볼 5개"] && picked
              && rowD?.off == true && rowD?.pill == "짝 있음" && rowO?.off == true && rowO?.pill == "5.3 아님" && cardO == "5.3 아님" && friends?.rows[rowB ?? 0].off == false && asked && sentRow?.chip == "협동 · 청함" && sentGo == "청하기 거두기",
              "5.3 짝 청하기: 협동 탭 (짝 청하기 · 혼자 시작; 함께 걷기 → 보스전 → 볼 5개) → the friends (one in a pair dimmed: 짝 있음; one before 5.3 — no app53 — 5.3 아님, on its card too) → asked → .pairInvite; the row: 협동 · 청함, 청하기 거두기",
              "\(String(describing: firstPage?.go)) \(String(describing: firstPage?.go2)) \(picked) \(String(describing: rowD)) \(String(describing: rowO)) \(String(describing: cardO)) \(asked) \(ha.asked) \(says(a)) \(String(describing: sentRow)) \(String(describing: sentGo))")

        // the other side: the news, 홈's row, the ask's row → my dragon (two cards) → 짝 짓기; both on their dragons, the pair on
        act(b)
        let news = says(b) == [b.myName.count > 6 ? a.myName : josa(a.myName, "이", "가") + " 짝을 청했다!"] + (a.myName.count > 6 ? ["짝을 청했다!"] : []) + ["레시라무와 함께 · 30만 걸음"]
        team(b)
        let homeRow = b.statusModel().rows.last?.value.hasSuffix("짝을 청했어요 · 레시라무") == true
        b.open("전설 원정"); drain(b); tab(b, "지금", "ask:" + a.myName)
        let askRow = b.exp52Pane(0).exp?.rows.first { $0.chip == "협동 · 받음" }, askGo = b.exp52Pane(0).exp?.go
        b.press(1)
        var cards = false; if case .twoPick(0, 0) = b.screen { cards = b.paneContent(Date()).twoPick?.cards.first?.mark != nil }
        b.screen = .twoPick(kind: 0, sel: 1); b.press(1); drain(b)
        let accepted = hb.asked.last == "제크로무로 짝을 지을까요?" && srv.acts.contains { if case .pairAccept(_, "제크로무") = $0 { return true }; return false }
        act(a); team(a); team(b)
        let both = served(a)?.expeditions?["레시라무"]?.on == true && served(b)?.expeditions?["제크로무"]?.on == true && a.pairOn("레시라무")?.theirs == "제크로무" && b.pairOn("제크로무")?.with == a.myName
        check(news && homeRow && askRow != nil && askGo == "받기 · 내 용 고르기" && cards && accepted && both,
              "5.3 받은 청하기: the news (…이 짝을 청했다!), 홈's row, the ask's row (받기 · 내 용 고르기) → two cards (the friend's marked) → 제크로무로 짝 짓기 (asked) → .pairAccept; both on their dragons, the pair seen both ways",
              "\(news) \(says(b)) \(homeRow) \(String(describing: askRow)) \(String(describing: askGo)) \(cards) \(accepted) \(hb.asked) \(both)")

        // walking together: steps to the pair (not alone), the panel, the row; then 짝 풀기 (asked) → the other told
        act(a, 300); team(a); team(b)
        tab(a, "협동", "레시라무")
        let panel = a.exp52Pane(0).exp?.pair, pRow = a.exp52Pane(0).exp?.rows.first
        let together = (panel?.mine ?? 0) >= 300 && panel?.with == b.myName && panel?.least == Expeditions.pairMin && pRow?.note.hasPrefix("둘이 ") == true && served(a)?.expeditions?["레시라무"]?.steps == 0
            && b.pairOn("제크로무")?.theirSteps == panel?.mine && a.exp52Pane(0).exp?.go2 == "짝 풀기" && a.statusModel().rows.last?.value.hasPrefix("레시라무 · ") == true
        a.pageTap(9231); drain(a)
        let unpaired = ha.asked.last?.hasSuffix("의 짝을 풀까요?") == true && srv.acts.contains { if case .pairCancel = $0 { return true }; return false }
        act(b)
        let told = says(b).joined(separator: " ").contains("짝이 풀렸다")
        team(a); act(a, 50); team(a)
        let alone = a.pairOn("레시라무") == nil && (served(a)?.expeditions?["레시라무"]?.steps ?? 0) > 0
        check(together && unpaired && told && alone,
              "5.3 짝 걷기: the steps go to the pair (not alone), the panel (mine · theirs · 3만 each · days), the row (둘이 …), 홈's row; 짝 풀기 (asked) → .pairCancel, the friend told (…짝이 풀렸다), alone again",
              "\(together) \(String(describing: panel)) \(String(describing: pRow)) \(String(describing: served(a)?.expeditions?["레시라무"])) \(unpaired) \(told) \(says(b)) \(alone)")

        // a friend's card: 짝 청하기 (my dragon first) → asked; then paired, switching away is asked (짝이 풀려요) and ends it
        a.screen = .team(sel: a.teamRows(0).firstIndex { $0.card.name == b.myName } ?? 0, tab: 0, card: true)
        let card = a.paneContent(Date()).teamCard
        a.pageTap(6035)
        var mine = false; if case .twoPick(2, _) = a.screen { mine = a.paneContent(Date()).twoPick?.go == "레시라무로 청하기" }
        a.press(1); drain(a)
        let fromCard = srv.acts.last == .pairInvite(to: b.myName, id: "레시라무")
        act(b); team(b); b.pairAsk = b.pairAsks.first; b.screen = .twoPick(kind: 0, sel: 1); b.press(1); drain(b); act(a); team(a); team(b)
        let paired2 = a.pairOn("레시라무") != nil
        tab(a, "배회", "토네로스")
        let warn = a.exp52Pane(0).exp?.go == "바꾸기 · 짝이 풀려요"
        a.press(1); drain(a)
        let switched = ha.asked.last == "토네로스 원정으로 바꿀까요?" && ha.bodies.last?.contains("짝이 풀려요") == true && served(a)?.expeditions?["토네로스"]?.on == true
        act(b); let told2 = says(b).joined(separator: " ").contains("짝이 풀렸다"); team(a)
        check(card?.pair == "짝 청하기" && card?.twoRows == true && mine && fromCard && paired2 && warn && switched && told2 && a.pairOn("레시라무") == nil,
              "5.3 친구 카드: 짝 청하기 (the card's fourth button, two rows) → my dragon (레시라무로 청하기) → .pairInvite; paired, another expedition says 바꾸기 · 짝이 풀려요, asked (바꾸고 짝 풀기) → the pair ends, the friend told",
              "\(String(describing: card?.pair)) \(String(describing: card?.twoRows)) \(mine) \(fromCard) \(paired2) \(warn) \(switched) \(ha.bodies.last ?? "") \(told2)")

        // the walk done → each one's boss (its news); 300,000 · 30,000 each
        serve(a) { $0.expeditions?["토네로스"]?.on = false; $0.expeditions?["레시라무"]?.on = true }
        act(a); team(a)
        b.screen = .home; act(b); team(b)
        a.screen = .team(sel: a.teamRows(0).firstIndex { $0.card.name == b.myName } ?? 0, tab: 0, card: true); a.pageTap(6035); a.press(1); drain(a)
        act(b); team(b); b.pairAsk = b.pairAsks.first; b.screen = .twoPick(kind: 0, sel: 1); b.press(1); drain(b); act(a); team(a)
        if let i = srv.pairList.firstIndex(where: { $0.state == "on" && $0.a == ka }) { srv.pairList[i].aSteps = 269_000; srv.pairList[i].bSteps = 30_000 }
        act(a, 1_000)
        let reached = served(a)?.expeditions?["레시라무"]?.stage == 1 && srv.pairList.contains { $0.a == ka && $0.b == kb && $0.state == "done" }
        act(b); let bBoss = served(b)?.expeditions?["제크로무"]?.stage == 1
        tab(a, "협동", "레시라무")
        check(reached && bBoss && a.exp52Pane(0).exp?.go == "보스전 · 오늘 1번",
              "5.3 짝 걷기 끝: 300,000 between them (30,000 each) → each one's dragon on to its boss (its next act), 5.2's 보스전 · 오늘 1번",
              "\(reached) \(String(describing: served(a)?.expeditions?["레시라무"])) \(bBoss) \(String(describing: a.exp52Pane(0).exp?.go))")

        // 스토리: 시작하기 → its first scene (once), walked → the trainer's scene → the party; the fight (its title and picture, no turns), won →
        // the win's scene and the next one's
        serve(a) { $0.expeditions?["레시라무"]?.on = false; $0.owned = Array(1...30) + [650, 653, 656] }
        tab(a, "스토리", Expeditions.story); a.press(1); drain(a)
        var scene0 = false; if case .talk(0) = a.screen { scene0 = a.storyScene?.stage == 0 && a.storyScene?.pages.count == 5 && a.paneContent(Date()).talk?.chapter == "1장 · 수상한 무리" }
        for _ in 0..<5 { a.press(1) }
        var backOnPage = false; if case .expedition = a.screen { backOnPage = true }
        serve(a) { $0.expeditions?[Expeditions.story]?.on = false }; a.press(1); drain(a)          // (이어 하기: no scene again)
        var noAgain = true; if case .talk = a.screen { noAgain = false }
        serve(a) { $0.expeditions?[Expeditions.story]?.steps = 19_990; $0.course = courses.firstIndex { $0.region == Expeditions.kalos }! }
        act(a, 20)                                                                                      // (its news: the trainer's scene)
        var trainerScene = false; if case .talk = a.screen { trainerScene = a.storyScene?.stage == 1 && a.storyThen.map { if case .squad = $0 { return true }; return false } == true }
        while case .talk = a.screen { a.press(1) }
        var party = false; if case .squad(let q) = a.screen, case .exp(Expeditions.story) = q.kind { party = a.title().meta == "출전할 1~3마리 · 몇 번이든" }
        if case .squad(let q) = a.screen { a.squadGo(Squad(kind: q.kind, picked: [a.state.companion.uid!], at: 0), Date()); drain(a) }
        playOut(a)
        let fight = a.fight, fightLook = fight.map { $0.trainer == "플레어단 조무래기" && $0.expedition == Expeditions.story && trainerFrame($0.trainer!) == "flaregrunt" } == true
            && a.title().title == "플레어단 조무래기" && a.title().meta.hasPrefix("1장 · 남은") && a.paneContent(Date()).battle?.turnsLeft == nil
        fightOut(a)
        var wonScenes = false
        if case .talk = a.screen { wonScenes = a.storyScene?.at == "won" && a.storyScene?.stage == 1 && a.storyQueue.first?.stage == 2 }
        else if says(a).first == "플레어단 조무래기를 이겼다!" { a.press(1); if case .talk = a.screen { wonScenes = a.storyScene?.at == "won" && a.storyScene?.stage == 1 && a.storyQueue.first?.stage == 2 } }
        while case .talk = a.screen { a.press(1) }
        check(scene0 && backOnPage && noAgain && trainerScene && party && fightLook && wonScenes && served(a)?.expeditions?[Expeditions.story]?.stage == 2,
              "5.3 칼로스 이야기: 시작하기 → 1장's scene (5 pages, 1장 · 수상한 무리; once: 이어 하기 shows none); walked → the trainer's scene → its party (몇 번이든); 플레어단 조무래기's fight (its title, flaregrunt, no turns) → won: its scene after, then 2장's",
              "\(scene0) \(backOnPage) \(noAgain) \(trainerScene) \(party) \(fightLook) \(wonScenes) \(String(describing: served(a)?.expeditions?[Expeditions.story])) \(a.screen) \(says(a))")

        // the 칼로스 도감 gate (passes by itself), the pick (expPick) and its scene, the final fight's win and its scene, 5장 with the other one
        serve(a) { $0.expeditions?[Expeditions.story]?.stage = 4; $0.expeditions?[Expeditions.story]?.steps = 0 }
        tab(a, "스토리", Expeditions.story)
        let gate = a.exp52Pane(0).exp?.rows.first?.note == "3장 · 칼로스 도감 3/5종" && a.exp52Pane(0).exp?.go == "칼로스 도감 보기"
        serve(a) { $0.owned = ($0.owned ?? []) + [659, 661] }; act(a)
        let passed = served(a)?.expeditions?[Expeditions.story]?.stage == 5
        while case .talk = a.screen { a.press(1) }
        serve(a) { $0.expeditions?[Expeditions.story]?.stage = 9 }
        tab(a, "스토리", Expeditions.story); a.press(1)
        var cardsOK = false; if case .twoPick(1, 0) = a.screen { cardsOK = a.paneContent(Date()).twoPick?.cards.map(\.name) == ["제르네아스", "이벨타르"] }
        a.press(1); drain(a)
        let pickedX = served(a)?.expeditions?[Expeditions.story]?.pick == 716 && served(a)?.expeditions?[Expeditions.story]?.stage == 10 && ha.asked.last == "제르네아스와 결전할까요?"
        var pickScene = false; if case .talk = a.screen { pickScene = a.storyScene?.stage == 10 }
        while case .talk = a.screen { a.press(1) }
        var bb = Battle(wild: Mon(dex: 716, level: 70, female: false), companion: a.state.companion); bb.expedition = Expeditions.story; bb.raidTier = 0
        serve(a) { $0.expeditions?[Expeditions.story] = ExpProgress(done: 1, pick: 716) }
        a.news = [.expeditionDone(id: Expeditions.story, dex: 716, gift: "특성패치")]
        a.screen = a.expFightEnded(Expeditions.story, bb, BattleEnd(result: "won", balls: 0), Date())
        let finalLines = says(a).prefix(2) == ["제르네아스를 잡았다!", "상자로 보냈다"] && says(a).contains("특성패치를 받았다!")
        a.press(1); var finalScene = false; if case .talk = a.screen { finalScene = a.storyScene?.stage == 10 && a.storyScene?.at == "won" }
        while case .talk = a.screen { a.press(1) }
        tab(a, "스토리", Expeditions.story5)
        let five = a.story5Legend == 717 && a.exp52Pane(1).exp?.rows[1].locked == false && a.expStrip(Expeditions.of(Expeditions.story5)!).last?.sub == "이벨타르"
        check(gate && passed && cardsOK && pickedX && pickScene && finalLines && finalScene && five,
              "5.3 칼로스 이야기: 3장's 칼로스 도감 3/5종 (passes by itself at 5), the pick (two cards → asked → .expPick: 제르네아스, its scene), the final win (잡았다! · 특성패치, the scene after), 5장 for 이벨타르",
              "\(gate) \(passed) \(cardsOK) \(pickedX) \(pickScene) \(finalLines) \(says(a)) \(finalScene) \(five)")

        // every scene of the mockups — and the worst cases — readable: the page at 크기 2 · 3 · 4, the LCD inside and clear, as drawn and 15 % wider
        var bad: [String] = [], n = 0
        let size = SIZE
        exp53Scenes(worst: true) { name, v, set in
            set(v); n += 1
            for px in [2, 3, 4] as [CGFloat] { SIZE = px; bad += paneOverflow(v).map { "\(name) ×\(Int(px)) \($0)" } }
            SIZE = size
            for k in [1.0, 1.15] {
                textWidthScale = k
                let fb = v.compose(Date())
                bad += fb.runs.filter { $0.x < 0 || $0.x + $0.w > 96 }.map { "\(name) LCD \(k): past the screen: \($0.s)" } + runClashes(fb.runs).map { "\(name) LCD \(k): \($0)" }
            }
            textWidthScale = 1
        }
        SIZE = size
        let lines = Story.scenes.flatMap { $0.pages.flatMap(\.lines) }, wide = { (k: Double) -> [String] in textWidthScale = k; defer { textWidthScale = 1 }; return lines.filter { textWidth($0, small: true) > 90 } }
        let over = wide(1) + wide(1.15)
        check(bad.isEmpty && n > 60 && over.isEmpty && frameNames.suffix(5) == ["flaregrunt", "mable", "xerosic", "lysandre", "sycamore"] && frameData.count == frameNames.count * 3245,
              "5.3 the mockups' scenes (\(n), the worst cases too: a 12-letter ID, 29만/30만, 1일, 3.9만/4만): no words over words, past the page, cut or across a box (크기 2 · 3 · 4), the LCD inside and clear (15 % wider too); every scene line in the LCD's box (90 dots); 플레어단's frames",
              "\(n) \(Array(Set(bad)).sorted().prefix(12)) \(over)")
    } } } }
    return c
}

/// The mockups' scenes (lcd-mockups docs/mockups/v5.3), on the fake server's pairs and the server's scenes: the shots' (fav-style names:
/// coop… · story… · home… · w-… the worst cases), the checks', Windows' renders (WinRender). Each: its name, its walker, how its screen is set.
@MainActor func exp53Scenes(worst: Bool, _ each: (String, Walker, (Walker) -> Void) -> Void) {
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) { Content.$testing52.withValue(true) { Content.$testing53.withValue(true) {
    Content.$testingDaily.withValue(true) { Content.$testingSlots.withValue(true) { Content.$testingChoice.withValue(true) {
        var r = Seeded(s: 21)
        var saur = Mon(dex: 3, level: 55, female: false); saur.nature = 3; saur.ivs = [31, 14, 31, 24, 31, 19]; saur.known = [76, 188, 79, 202]; saur.item = "기적의씨"
        var tyrogue = Mon(dex: 236, level: 20, female: false); tyrogue.ability = 2
        let long = "김수한무거북이와두루미삼"                                                            // 12: the longest ID
        var save = Walk()
        save.companion = saur
        save.caught = [tyrogue, Mon.wild(25, level: 24, &r), Mon.wild(133, level: 18, &r)]
        save.box = [1, 4, 7, 16, 19, 41, 52, 63, 66, 74, 92, 129, 147, 158, 175, 246].map { Mon.wild($0, level: 8 + $0 % 23, &r) }
        save.watts = 12_480; save.earned = 640_000; save.bp = 120; save.weather = .sunny; save.today = 6_240; save.total = 412_300
        save.owned = Array(1...9) + [16, 19, 25, 41, 52, 63, 66, 74, 92, 129, 133, 147, 158, 175, 236, 246, 650, 653, 656]   // 칼로스 3
        save.seen = Array(10...40); save.day = Walk.key(Date()); save.dex()
        let srv = FakeCloud()
        let v = online(save, server: srv), me = v.myName.lowercased(), myName = v.myName
        let friends: [(String, Int, Int, Int)] = [("민수", 6, 52, 124_000), ("지은", 282, 47, 88_000), ("도윤", 448, 61, 61_000), ("서연", 133, 30, 23_000)] + (worst ? [(long, 445, 100, 699_993)] : [])
        for (k, f) in friends.enumerated() {
            var w = Walk(), fr = Seeded(s: UInt64(k + 40)); w.companion = Mon.wild(f.1, level: f.2, &fr); w.today = f.3; w.owned = Array(1...(60 + 20 * k))
            srv.add(f.0.lowercased(), w); srv.rows[f.0.lowercased()]?.name = f.0; srv.lastAct[f.0.lowercased()] = k < 2 ? Date() : Date().addingTimeInterval(-3600 * Double(k)); srv.befriend(me, f.0.lowercased())
        }
        let ts = srv.clockNow
        srv.expEvents = [TeamEventView(id: 3, legend: 649, starts: ts - 2 * 86_400, ends: ts + 5 * 86_400 - 600, goal: 1_500_000, min: 20_000, team: 642_000, mine: 12_400, got: false)]
        // 도윤 walks with someone already (짝 있음)
        srv.pairList = [FakeCloud.FakePair(id: 90, a: "도윤", aName: "도윤", b: "zzelse", bName: "zzelse", aExp: "제크로무", bExp: "레시라무", state: "on", ends: ts + 86_400)]
        v.cloud!.teamDue = true; v.cloud!.expeditionDue = true; v.cloud!.tick(Date()); drain(v); drain(v)
        func legend(_ d: Int) -> Mon { var lr = Seeded(s: UInt64(d)); return Expeditions.legend(d, &lr) }
        func prog(_ id: String, on: Bool = true, stage: Int = 0, steps: Int = 0, n: Int = 0, done: Int = 0, pick: Int? = nil, mon: Int? = nil) -> (String, ExpProgress) {
            (id, ExpProgress(on: on, n: n, steps: steps, mon: legend(mon ?? Expeditions.of(id)?.legend ?? 643), done: done, stage: stage, pick: pick))
        }
        func pair(_ id: Int, _ with: String, _ state: String, mine: String, theirs: String?, me m: Int = 0, them: Int = 0, days: Double = 9) -> FakeCloud.FakePair {
            let k = with.lowercased(), asked = state != "got"
            var p = FakeCloud.FakePair(id: id, a: asked ? me : k, aName: asked ? myName : with, b: asked ? k : me, bName: asked ? with : myName, aExp: asked ? mine : (theirs ?? "레시라무"),
                                      bExp: state == "on" ? theirs : nil, state: state == "on" ? "on" : "asked", ends: ts + Int(days * 86_400) - 3600)
            p.aSteps = asked ? m : them; p.bSteps = asked ? them : m
            return p
        }
        /// The save's expeditions and the fake server's pairs for a scene; the tab by name, the row by its id (ask:<name> a friend's ask).
        @MainActor func set(_ v: Walker, _ ps: [(String, ExpProgress)], pairs: [FakeCloud.FakePair] = [], tab: String, row: String? = nil) {
            serve(v) { $0.expeditions = Dictionary(uniqueKeysWithValues: ps) }
            srv.pairList = [srv.pairList[0]] + pairs; v.cloud!.expeditionDue = true; v.cloud!.teamDue = true; v.cloud!.tick(Date()); drain(v); drain(v)
            v.expTab = Walker.expTabs.firstIndex(of: tab) ?? 0
            let rows = v.expRows(v.expTab)
            v.screen = .expedition(row.flatMap { n in rows.firstIndex { r in
                switch r { case .exp(let e): return e.id == n; case .ask(let a): return "ask:" + a.with == n; default: return false }
            } } ?? 0)
        }
        let tornado = prog("토네로스", steps: 1_800), sb = Expeditions.story, s5 = Expeditions.story5
        @MainActor func talk(_ id: String, _ stage: Int, _ at: String, _ page: Int) -> @MainActor (Walker) -> Void {
            { v in v.storyScene = Story.scenes.first { $0.id == id && $0.stage == stage && $0.at == at }; v.storyQueue = []; v.storyThen = .expedition(0); v.screen = .talk(page) }
        }
        // 협동
        each("coop1-tab", v) { set($0, [tornado], tab: "협동", row: "레시라무") }
        each("coop1-pick", v) { $0.screen = .pairPick(dex: 643, sel: 0) }
        each("coop1-pick-paired", v) { v in v.screen = .pairPick(dex: 643, sel: v.pairFriends().firstIndex { $0.name == "도윤" } ?? 0) }
        each("coop1-sent", v) { set($0, [tornado], pairs: [pair(7, "민수", "sent", mine: "레시라무", theirs: nil, days: 3)], tab: "협동", row: "레시라무") }
        each("coop2-home", v) { set($0, [tornado], pairs: [pair(9, "민수", "got", mine: "", theirs: "레시라무", days: 2.5)], tab: "지금"); $0.screen = .home }
        each("coop2-news", v) { $0.showPair(.pairAsked(pair: 9, from: "민수", id: "레시라무"), Date()) }
        each("coop2-row", v) { set($0, [tornado], pairs: [pair(9, "민수", "got", mine: "", theirs: "레시라무", days: 2.5)], tab: "지금", row: "ask:민수") }
        each("coop2-dragon", v) { v in v.pairAsk = v.pairAsks.first; v.screen = .twoPick(kind: 0, sel: 1) }
        let rOn = prog("레시라무", steps: 12_000), on = pair(9, "민수", "on", mine: "레시라무", theirs: "제크로무", me: 96_000, them: 86_000)
        each("coop3-pair", v) { set($0, [rOn, prog("토네로스", on: false, steps: 1_800)], pairs: [on], tab: "협동", row: "레시라무") }
        each("coop3-short", v) { set($0, [rOn], pairs: [pair(9, "민수", "on", mine: "레시라무", theirs: "제크로무", me: 12_000, them: 251_000, days: 2)], tab: "협동", row: "레시라무") }
        each("coop3-now", v) { set($0, [rOn, prog("토네로스", on: false, steps: 1_800), prog("지가르데", on: false, n: 23), prog("코바르온", on: false, steps: 21_000)], pairs: [on], tab: "지금", row: "레시라무") }
        each("coop3-home", v) { set($0, [rOn], pairs: [on], tab: "지금"); $0.screen = .home }
        each("coop3-boss", v) { set($0, [prog("레시라무", stage: 1)], tab: "협동", row: "레시라무") }
        each("coop3-card", v) { v in set(v, [tornado], tab: "지금"); v.screen = .team(sel: v.teamRows(0).firstIndex { $0.card.name == "민수" } ?? 0, tab: 0, card: true) }
        each("coop3-card-pick", v) { v in v.pairTo = "민수"; v.screen = .twoPick(kind: 2, sel: 0) }
        each("coop4-solo", v) { set($0, [prog("레시라무", steps: 73_000)], tab: "협동", row: "레시라무") }
        each("coop4-kyurem-locked", v) { set($0, [("레시라무", ExpProgress(done: 1))], tab: "협동", row: "큐레무") }
        each("coop4-kyurem", v) { set($0, [("레시라무", ExpProgress(done: 1)), ("제크로무", ExpProgress(done: 1)), prog("큐레무", steps: 12_000)], tab: "협동", row: "큐레무") }
        each("coop4-switch", v) { set($0, [rOn, prog("토네로스", on: false, steps: 1_800)], pairs: [on], tab: "배회", row: "토네로스") }
        each("coop4-closed", v) { set($0, [prog("레시라무", steps: 12_000)], tab: "지금"); $0.showPair(.pairClosed(pair: 9, with: "민수", why: "풀림"), Date()) }
        each("coop4-expired", v) { $0.showPair(.pairClosed(pair: 9, with: "민수", why: "기한"), Date()) }
        // 스토리
        each("story1-start", v) { set($0, [tornado], tab: "스토리", row: sb) }
        each("story1-walk", v) { set($0, [prog(sb, steps: 12_000)], tab: "스토리", row: sb) }
        each("story1-trainer", v) { set($0, [prog(sb, stage: 3)], tab: "스토리", row: sb) }
        each("story1-dex", v) { set($0, [prog(sb, stage: 4)], tab: "스토리", row: sb) }
        each("story1-locked5", v) { set($0, [prog(sb, stage: 5, steps: 4_000)], tab: "스토리", row: s5) }
        each("story2-talk-1", v) { set($0, [prog(sb)], tab: "스토리"); talk(sb, 0, "start", 0)($0) }
        each("story2-talk-2", v, talk(sb, 0, "start", 1))
        each("story2-talk-sci", v) { set($0, [prog(sb, stage: 6)], tab: "스토리"); talk(sb, 6, "start", 1)($0) }
        each("story2-talk-ly", v) { set($0, [prog(sb, stage: 8)], tab: "스토리"); talk(sb, 8, "start", 3)($0) }
        each("story2-talk-won", v) { set($0, [prog(sb, stage: 2)], tab: "스토리"); talk(sb, 1, "won", 1)($0) }
        var grunt = Battle(party: v.state.party().map(\.mon), trainer: "플레어단 조무래기", foes: [Mon(dex: 228, level: 35, female: false), Mon(dex: 453, level: 35, female: true)]); grunt.expedition = sb
        var ly = Battle(party: v.state.party().map(\.mon), trainer: "플레어단 보스 플라드리", foes: [620, 430, 668, 130].map { Mon(dex: $0, level: 65, female: false) }); ly.expedition = sb
        each("story3-party", v) { set($0, [prog(sb, stage: 1)], tab: "스토리"); $0.screen = .squad(Squad(kind: .exp(id: sb), picked: [], at: 0)) }
        each("story3-intro", v) { v in v.fight = grunt; v.screen = .beats(grunt, [.sendOut(.it, 0)], since: Date().addingTimeInterval(-0.45), from: grunt) }
        each("story3-fight", v) { v in set(v, [prog(sb, stage: 8)], tab: "스토리"); v.fight = ly; v.screen = .battle(ly, sel: 0) }
        each("story3-won", v) { v in v.fight = nil; set(v, [prog(sb, stage: 7)], tab: "스토리"); v.screen = .say(["플레어단 과학자를 이겼다!"], next: .expedition(0), since: Date()) }
        each("story4-pick", v) { set($0, [prog(sb, stage: 9)], tab: "스토리", row: sb) }
        each("story4-scene", v, talk(sb, 9, "start", 3))
        each("story4-cards", v) { $0.screen = .twoPick(kind: 1, sel: 0) }
        each("story4-final", v) { set($0, [prog(sb, stage: 10, pick: 716, mon: 716)], tab: "스토리", row: sb) }
        each("story4-five", v) { set($0, [(sb, ExpProgress(done: 1, pick: 716)), prog(s5, mon: 717)], tab: "스토리", row: s5) }
        each("home-story", v) { set($0, [prog(sb, stage: 5, steps: 12_000)], tab: "지금"); $0.screen = .home }
        each("menu-adventure", v) { set($0, [rOn], pairs: [on], tab: "지금"); $0.screen = menuFor("전설 원정") }
        each("news-pair-on", v) { $0.showPair(.pairOn(pair: 9, with: "민수", id: "제크로무"), Date()) }
        each("news-boss", v) { set($0, [prog("레시라무", stage: 1)], tab: "협동"); $0.showExpStage("레시라무", 1, Date()) }
        if worst {
            let w1 = pair(9, long, "on", mine: "제크로무", theirs: "레시라무", me: 50_000, them: 249_999, days: 14)
            each("w-pair-long", v) { set($0, [prog("제크로무")], pairs: [w1], tab: "협동", row: "제크로무") }
            each("w-pair-short", v) { set($0, [prog("제크로무")], pairs: [pair(9, long, "on", mine: "제크로무", theirs: "제크로무", me: 1, them: 299_998, days: 1)], tab: "협동", row: "제크로무") }
            each("w-ask-long", v) { set($0, [prog("레쿠쟈", stage: 1, steps: 29_000)], pairs: [pair(9, long, "got", mine: "", theirs: "제크로무", days: 3)], tab: "지금", row: "ask:" + long) }
            each("w-sent-long", v) { set($0, [prog("레쿠쟈", stage: 1)], pairs: [pair(7, long, "sent", mine: "레시라무", theirs: nil, days: 3)], tab: "협동", row: "레시라무") }
            each("w-dragon-long", v) { v in v.pairAsk = v.pairAsks.first; v.screen = .twoPick(kind: 0, sel: 0) }
            each("w-friends", v) { v in v.screen = .pairPick(dex: 644, sel: v.pairFriends().firstIndex { $0.name == long } ?? 0) }
            each("w-card-long", v) { v in v.screen = .team(sel: v.teamRows(0).firstIndex { $0.card.name == long } ?? 0, tab: 0, card: true) }
            each("w-home-ask", v) { set($0, [], pairs: [pair(9, long, "got", mine: "", theirs: "제크로무", days: 3)], tab: "지금"); $0.screen = .home }
            each("w-home-pair", v) { set($0, [prog("제크로무")], pairs: [w1], tab: "지금"); $0.screen = .home }
            each("w-news", v) { $0.showPair(.pairClosed(pair: 9, with: long, why: "풀림"), Date()) }
            each("w-news-asked", v) { $0.showPair(.pairAsked(pair: 9, from: long, id: "제크로무"), Date()) }
            each("w-story-trainer", v) { set($0, [prog(sb, stage: 8)], tab: "스토리", row: sb) }
            each("w-story-walk", v) { set($0, [prog(sb, stage: 7, steps: 19_999)], tab: "스토리", row: sb) }
            each("w-story-five", v) { set($0, [(sb, ExpProgress(done: 3, pick: 717)), prog(s5, stage: 1, steps: 39_999, mon: 716)], tab: "스토리", row: s5) }
            each("w-fight-title", v) { v in set(v, [prog(sb, stage: 8)], tab: "스토리"); v.fight = ly; v.screen = .battle(ly, sel: 0) }
            for sc in Story.scenes { for p in sc.pages.indices { each("w-talk-\(sc.id == sb ? "s" : "f")\(sc.stage)\(sc.at)-\(p)", v) { v in serve(v) { $0.expeditions = [sc.id: prog(sc.id, stage: sc.stage).1] }; talk(sc.id, sc.stage, sc.at, p)(v) } } }
        }
    } } } } } } }
}
