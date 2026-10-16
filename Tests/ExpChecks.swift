import Foundation
// 5.1 (docs/plans/19 §1 · §9, content51): 전설 원정 — self-test checks (run by selftest()): the menu's 모험 ▸, 홈's sixth row, the page (the team
// event from /v2/expedition, 지가르데, what opens later), starting one, a cell's card, 50 put together (the show, its line, the box, 특성패치),
// and the LCD's words inside at any font.

@MainActor func expChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) {
        let menuOK = menuTiles[1].name == "모험" && menuTiles[1].items == ["코스", "전설 원정"] && PaneContent.home == 468
            && { if case .menu(1?, 1) = menuFor("전설 원정") { return true }; return false }()
        let w = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 30, female: false); return s }())
        let (srv, _) = server(w), now = Int(Date().timeIntervalSince1970)
        srv.expEvents = [TeamEventView(id: 1, legend: 494, starts: now - 2 * 86_400, ends: now + 3 * 86_400, goal: 1_500_000, min: 20_000, team: 931_200, mine: 12_400, got: false)]
        let homeBefore = w.statusModel().rows.last
        w.open("전설 원정"); drain(w)
        let rows = w.expPane(0).exp?.rows ?? [], homeEvent = w.statusModel().rows.last
        let listOK = rows.count == 6 && rows[0].name == "비크티니" && rows[0].mine != nil && rows[1].name == "지가르데" && rows[1].note == "시작 전" && rows[2].off && rows[5].off
        w.screen = .expedition(1); w.press(1); drain(w)                                             // 시작하기
        let started = served(w)?.expeditions?["지가르데"]?.on == true && w.state.expeditions?["지가르데"]?.mon != nil
            && { if case .say(let l, .expedition(1), _) = w.screen { return l == ["지가르데 원정을", "시작했다!"] }; return false }()
        w.show(.expedition(id: "지가르데", n: 24, need: 50), Date())                               // a cell came: 홈's card, the cell big
        let card = { if case .say(let l, .home, _) = w.screen { return l == ["지가르데 셀을", "모았다!", "24/50"] }; return false }() && w.sayStone?.stone == "지가르데셀"
        serve(w) { $0.expeditions?["지가르데"]?.n = 50 }
        w.sayStone = nil; w.screen = .expedition(1)
        let ready = w.expPane(1).exp?.go == "조립하기" && w.expDot
        w.press(1); drain(w)                                                                        // 조립하기: the show, then its line, then the page
        var shown = false; if case .assemble(let m, _) = w.screen { shown = m.dex == 718 }
        w.tick(Date() + 6)
        let after = { if case .say(let l, .expedition(1), _) = w.screen { return l.first == "지가르데를" && l.contains("특성패치를 받았다!") }; return false }()
        let boxed = w.state.box.contains { $0.dex == 718 } && w.state.bag.contains("특성패치") && w.state.expeditions?["지가르데"]?.done == 1
        var bad: [String] = []
        for k in [1.0, 1.15] {                                                                       // (and as if a font 15 % wider: another OS's)
            textWidthScale = k; defer { textWidthScale = 1 }
            for s in 0..<rows.count { w.screen = .expedition(s); let fb = w.compose(Date()); bad += lcdOverlaps(fb) + fb.runs.filter { $0.x < 0 || $0.x + $0.w > 96 }.map { "×\(k) \(s): \($0.s)" } + runClashes(fb.runs) }
        }
        c.append((menuOK && homeBefore?.key == "전설 원정" && homeEvent?.value.hasPrefix("비크티니 62%") == true && listOK && started && card && ready && shown && after && boxed && bad.isEmpty,
                  "5.1 전설 원정: 모험 ▸ 코스 · 전설 원정, 홈's sixth row (the card 468), the page (비크티니's team event, 지가르데 시작 전, four dimmed), 시작하기 → .expStart, a cell's card, 50 → 조립하기 → the show → its line (특성패치) → the box; the LCD inside at any font"
                  + (bad.isEmpty ? "" : " — \(bad.prefix(4))")))
        if !(menuOK && listOK && started && card && ready && shown && after && boxed) { print("exp: \(menuOK) \(String(describing: homeBefore)) \(String(describing: homeEvent)) \(rows.map(\.name)) \(listOK) \(started) \(card) \(ready) \(shown) \(after) \(boxed)") }
    } }
    return c
}
