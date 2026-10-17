import Foundation
// 5.1.3 (docs/plans/23, the user via 회사 10-17: "A로가자"): self-test checks (run by selftest()) — 배루키's pick at Lv.20. Off: as before (its
// steps pick, at once; no cards, no dot, no link). On (the login's evoChoice): the companion levelled to 20 waits — "어라...? 배루키의 모습이...!",
// the three cards (시라소몬 · 홍수몬 · 카포에라, a type and an ability each), ◀ ▶, ● 진화할까? 아니오 (nothing sent) / 예 → MonOp.evolve → the show;
// the walker's (ready already: its dot, the ● menu's 진화, no notification) and the box's (one come in: told once, its cell's dot, its page's 진화
// 고르기); 변함없는돌 (none) and taken off (ready, told); offline (연결되면); the launch with a 하나 · 칼로스 course (35–43) and the switches off.

@MainActor func evo513Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func add(_ t: (Bool, String, String)) { c.append((t.0, t.1)); if !t.0 { print("evo513: \(t.1.prefix(32))… — \(t.2)") } }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func picking(_ w: Walker) -> (uid: Int, at: Int, ask: Bool?)? { if case .evoPick(let u, let a, let k) = w.screen { return (u, a, k) }; return nil }
    func evolved(_ w: Walker) -> (Int, Int)? { if case .evolve(let f, let t, _) = w.screen { return (f.dex, t.dex) }; return nil }
    func candied(_ lv: Int, _ setup: (inout Walk) -> Void = { _ in }, server: FakeCloud) -> Walker {
        var m = Mon(dex: 236, level: lv, female: false); m.exp = expTable[growthRate[236]][lv]
        let v = online({ var s = Walk(); s.companion = m; s.bag = ["이상한사탕"]; setup(&s); return s }(), server: server)
        v.screen = .items(v.state.inventory.firstIndex(of: "이상한사탕") ?? 0); v.press(1); v.press(1); drain(v)
        return v
    }
    /// Home until something shows (the news, then the companion's "어라...?").
    func home(_ v: Walker) { for _ in 0..<6 { if case .say(_, .evoPick, _) = v.screen { return }; if evolved(v) != nil { return }; v.screen = .home; v.tick(Date()) } }
    func steps(_ v: Walker) { v.cloud!.addSteps(5); v.cloud!.saveNow(); drain(v) }
    let was = (Content.onChoice, settings.int("evoChoice", 0))
    defer { Content.onChoice = was.0; settings.set("evoChoice", was.1) }

    // off: as before — its steps pick, at once
    Content.$testingChoice.withValue(false) {
        let v = candied(19, server: FakeCloud()); home(v)
        let shown = evolved(v), now = v.state.companion.dex
        v.screen = .box(-1, act: nil, confirm: false, detail: true)
        let page = v.monModel()
        add((shown?.0 == 236 && [106, 107, 237].contains(now) && shown?.1 == now && v.evoNew.isEmpty && page?.evoPick == nil && !v.openEvoPick(-1)
                    && page?.evos.first?.contains("직접") == false,
                  "5.1.3 배루키 off: Lv.20 evolves at once by its steps (the show), no cards, no link, nothing told", "\(String(describing: shown)) \(now) \(v.evoNew) \(String(describing: page?.evos))"))
    }

    Content.$testingChoice.withValue(true) { Content.$testing.withValue(true) {
        // the login's switch, kept for the next launch
        Content.onChoice = false; settings.set("evoChoice", false)
        let sv = FakeCloud(); sv.evoChoice = true
        let v = candied(19, server: sv)
        let heard = Content.onChoice && settings.bool("evoChoice", false)
        // the companion: waits, "어라...?", the cards
        let waits = v.state.companion.dex == 236 && v.state.companion.level == 20, uid = v.state.companion.uid ?? -1
        let told = v.evoNew == [uid]
        home(v)
        let prompt = says(v) == ["어라...?", "배루키의 모습이...!"] && { if case .say(_, .evoPick(uid, 0, nil), _) = v.screen { return true }; return false }()
        v.press(1)
        let pane = v.paneContent(Date()).evoPick, cards = pane?.cards ?? []
        let cardsOK = picking(v)?.uid == uid && cards.map(\.dex) == [106, 107, 237] && cards.allSatisfy { $0.types == ["fighting"] && !$0.ability.isEmpty }
            && cards.map(\.atk) == [baseStats[106][1], baseStats[107][1], baseStats[237][1]] && pane?.stats == baseStats[106] && pane?.ask == nil
        _ = v.compose(Date())
        // ◀ ▶, ● 아니오 (nothing sent), ● 예
        v.press(2); let second = picking(v)?.at == 1
        v.press(1); let asked = picking(v)?.ask == false && v.paneContent(Date()).evoPick?.ask == false; _ = v.compose(Date())
        let sent0 = sv.acts.count; v.press(1)
        let no = picking(v).map { $0.at == 1 && $0.ask == nil } == true && sv.acts.count == sent0 && v.state.companion.dex == 236
        v.press(1); v.press(0); let yesUp = picking(v)?.ask == true
        v.press(1); drain(v); home(v)
        let sent = sv.acts.contains(.mon(op: .evolve(uid: uid, to: 107))), show = evolved(v)
        let done = v.state.companion.dex == 107 && v.state.companion.uid == uid && v.state.companion.level == 20 && served(v)?.companion.dex == 107 && (v.state.owned ?? []).contains(107)
        add((heard && waits && told && prompt && cardsOK && second && asked && no && yesUp && sent && show?.0 == 236 && show?.1 == 107 && done,
                  "5.1.3 배루키 on (the login's evoChoice, kept): the companion at Lv.20 waits, told once; at home 어라...? 배루키의 모습이...! → the cards (시라소몬 · 홍수몬 · 카포에라, 격투, an ability, 공 · 방), ◀ ▶, ● 진화할까? 아니오 sends nothing, 예 → MonOp.evolve → the show → 홍수몬 (its uid, level, 도감)",
                  "\(heard) \(waits) \(told) \(prompt) \(says(v)) \(cardsOK) \(cards.map(\.dex)) \(second) \(asked) \(no) \(yesUp) \(sent) \(String(describing: show)) \(done)"))

        // the walker's (ready already: no notification, its dot and ● menu) and the box's (come in: told, its cell, its page)
        let walkerTyro: Mon = { var m = Mon(dex: 236, level: 30, female: false); m.ability = 1; return m }()
        let w = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 30, female: false); s.caught = [walkerTyro]; s.bag = ["변함없는돌"]; return s }(), server: sv)
        let first = w.evoNew.isEmpty && w.evolveDot && w.boxActs(-2).contains("진화")
        w.screen = .box(-1, act: nil, confirm: false); let partyDot = w.gridModel(Date())?.party[safe: 1]?.evo == true && w.gridModel(Date())?.party[safe: 0]?.evo == false
        serve(w) { $0.box = [Mon(dex: 16, level: 5, female: false), Mon(dex: 236, level: 25, female: false)] }; steps(w)
        let boxUID = w.state.box[safe: 1]?.uid ?? -1, boxTold = w.evoNew == [boxUID] && w.evoPrompt == nil
        w.screen = .box(1, act: nil, confirm: false); let cell = w.gridModel(Date())?.cells.map(\.evo) == [false, true]
        w.screen = .box(1, act: nil, confirm: false, detail: true); let link = w.monModel()?.evoPick == "진화 고르기" && w.monModel()?.evos.first == "→ 시라소몬 · 홍수몬 · 카포에라"
        w.paneTap(4412); let opened = picking(w)?.uid == boxUID
        w.paneTap(5962); w.paneTap(5962); let tapAsk = picking(w).map { $0.at == 2 && $0.ask == false } == true
        w.paneTap(5971); let tapNo = picking(w)?.ask == nil
        w.paneTap(5970); w.paneTap(5972); drain(w); home(w)
        let boxDone = w.state.box[safe: 1]?.dex == 237 && evolved(w)?.1 == 237 && sv.acts.contains(.mon(op: .evolve(uid: boxUID, to: 237)))
        // the walker's by its ● menu: 진화 → the cards, its ability by its slot
        w.screen = .box(-2, act: w.boxActs(-2).firstIndex(of: "진화"), confirm: false, detail: true); w.press(1)
        let menuOpened = picking(w)?.uid == w.state.caught[0].uid
        let slotOK = w.paneContent(Date()).evoPick?.cards.map(\.ability) == [106, 107, 237].map { d -> String in var x = walkerTyro; x.dex = d; return x.abilityName }
        w.press(3)                                                                                // ↩ (the cards → its page)
        let backOK = { if case .box(-2, nil, false, true) = w.screen { return true }; return false }()
        add((first && partyDot && boxTold && cell && link && opened && tapAsk && tapNo && boxDone && menuOpened && slotOK && backOK,
                  "5.1.3 배루키 the walker's and the box's: one ready at the login (Lv.30 on the walker) — its dot, the ● menu's 진화, no notification; one come into the box (Lv.25) told once (no 어라...?), its cell's dot, its page's 진화 고르기 → the cards by click (again: 진화할까요?, 아니오, 예) → 카포에라; the walker's by its ● menu, the abilities by its slot; ↩ to its page",
                  "\(first) \(partyDot) \(boxTold) \(w.evoNew) \(cell) \(link) \(opened) \(tapAsk) \(tapNo) \(boxDone) \(menuOpened) \(slotOK) \(backOK)"))

        // 변함없는돌: never ready while held; taken off → ready, told
        let s = online({ var s = Walk(); var m = Mon(dex: 236, level: 25, female: false); m.item = "변함없는돌"; s.box = [m]; return s }(), server: sv)
        s.screen = .box(0, act: nil, confirm: false, detail: true)
        let held = s.state.evoReady(Date()).isEmpty && s.monModel()?.evoPick == nil && !s.boxActs(0).contains("진화") && !s.evolveDot && !s.openEvoPick(0)
        let su = s.state.box[0].uid ?? -1
        s.act(.mon(op: .hold(uid: su, item: nil)), back: .home); drain(s)
        let off = s.state.box[0].item == nil && s.evoNew == [su] && s.evolveDot && s.openEvoPick(0)
        add((held && off, "5.1.3 배루키 holding 변함없는돌: never ready (no link, no 진화, no dot); taken off: ready at once, told", "\(held) \(off) \(s.evoNew)"))

        // offline: 예 says 연결되면, nothing changes
        let o = online({ var s = Walk(); s.companion = Mon(dex: 236, level: 22, female: false); return s }(), server: FakeCloud())
        let (osv, _) = server(o); osv.evoChoice = true
        osv.down = true; o.cloud!.addSteps(10); o.cloud!.saveNow(); o.tick(Date()); o.tick(Date())
        o.screen = .box(-1, act: nil, confirm: false, detail: true); o.press(1); o.press(1); o.press(2); o.press(1)
        let offline = says(o) == Walker.offlineLines && o.state.companion.dex == 236 && !osv.acts.contains { if case .mon(op: .evolve) = $0 { return true }; return false }
        add((offline, "5.1.3 배루키 offline: the cards open, 예 says 연결되면 할 수 있어요, nothing sent or changed", "\(says(o)) \(o.state.companion.dex)"))

        // every button on the cards does something (as the Mac's and Windows')
        @MainActor func make(_ ask: Bool?) -> () -> Walker {
            { let x = Walker(state: { var s = Walk(); var m = Mon(dex: 236, level: 20, female: false); m.uid = 7; s.companion = m; return s }()); x.persist = false; x.screen = .evoPick(uid: 7, at: 0, ask: ask); return x }
        }
        let dead = deadHits(make(nil), skip: [5960]) + deadHits(make(false), skip: [5960, 5971])   // (the card picked; 아니오 picked)
        add((dead.isEmpty, "5.1.3 배루키's cards: every button does something (the cards, 진화, 아니오 · 예)", "dead: \(dead)"))
    } }

    // the launch (5.1.1's lesson): a 하나 · 칼로스 course save (35–43), the switches off and not heard, opened and drawn; with evo-choice heard, a
    // 배루키 at Lv.20 there too
    var launched: [Int] = []
    let keys = ["content5", "content51", "raidDaily", "evoChoice"], kept = keys.map { settings.int($0, 0) }, on = (Content.on, Content.on51, Content.onDaily, Content.onChoice)
    for k in 35...43 {
        for heard in [false, true] {
            for key in keys { settings.set(key, heard) }
            var s = Walk(); s.course = k; s.courseSteps = 5000; s.companion = Mon(dex: 236, level: 20, female: false); s.box = [Mon(dex: 700, level: 30, female: false)]
            Content.on = false; Content.on51 = false; Content.onDaily = false; Content.onChoice = false
            Content.atLaunch(s)
            let v = Walker(state: s); v.persist = false; v.host = TestHost()
            for sc in [Screen.home, .course(k), .box(-1, act: nil, confirm: false), .box(-1, act: nil, confirm: false, detail: true), .evoPick(uid: 1, at: 0, ask: nil), menuFor("포켓몬")] {
                v.screen = sc; _ = v.compose(Date()); _ = v.paneContent(Date()); _ = v.title()
            }
            if v.state.course == k, Content.gen6, Content.onChoice == heard { launched.append(k) }
        }
    }
    (Content.on, Content.on51, Content.onDaily, Content.onChoice) = on; for (k, v) in zip(keys, kept) { settings.set(k, v) }
    add((launched == (35...43).flatMap { [$0, $0] }, "5.1.3 launch: a save on each 하나 · 칼로스 course (35–43) with 배루키 Lv.20, the switches not heard and heard — opened, home · 코스 · 포켓몬 · its page · the cards drawn, its course kept", "\(launched)"))
    return c
}
