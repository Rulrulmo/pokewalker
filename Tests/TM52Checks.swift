import Foundation
// 5.2 (docs/plans/19 §11.4, content52; Core/TMView.swift): 기술머신 — self-test checks (run by selftest()): the W 상점's 기술머신 tab (the 106, its
// three sorts, 우리 팀만, a row's TM26 지진 · type · n마리 · the team), buying one (정말 살까? → Walk.tms, 보유), the bag's 기술머신 tab (no count),
// 가르칠 포켓몬 고르기 → that one's 기술 바꾸기 on the move (its slot first) → learnt, the list's TM26 mark, the disc's picture; the LCD inside.

@MainActor func tm52Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) { Content.$testing52.withValue(true) {
        var s = Walk(); s.companion = Mon(dex: 3, level: 55, female: false); s.companion.known = [76, 188, 79, 202]
        s.caught = [Mon(dex: 25, level: 40, female: false), Mon(dex: 133, level: 30, female: true)]; s.box = [Mon(dex: 6, level: 36, female: false)]; s.watts = 9_999
        let w = online(s)
        let tabs = w.shopTabs(false), t = tabs.firstIndex(of: "기술머신") ?? -1, ws = w.wares(false)
        func no(_ k: Int) -> Int { if case .item(let i) = ws[k].kind { return Walk.machine(i) ?? 0 }; return 0 }
        let byNo = w.shopRows(false, t)
        w.tmSort = 1; let byType = w.shopRows(false, t).map { Walker.typeOrder.firstIndex(of: w.tmMove(no($0))?.type ?? "") ?? 99 }
        w.tmSort = 2; let byPrice = w.shopRows(false, t).map { ws[$0].price }
        w.tmSort = 0; w.tmTeamOnly = true; let team = w.shopRows(false, t); w.tmTeamOnly = false
        let sorted = byNo.count == Machines.sold.count && byNo.map(no) == byNo.map(no).sorted() && byType == byType.sorted() && byPrice == byPrice.sorted()
        let teamOK = !team.isEmpty && team.count < byNo.count && team.allSatisfy { k in w.tmTeam.contains { Machines.learns($0.dex, no(k)) } }
        let k26 = ws.firstIndex { if case .item("기술머신26") = $0.kind { return true }; return false } ?? 0
        w.screen = .shop(bp: false, sel: k26, qty: nil)
        let shop = w.paneContent(Date()).shop, row = shop?.rows.first { $0.name.hasPrefix("TM26") }
        let rowOK = shop?.tmSort == 0 && row?.name == "TM26 지진" && row?.type == "ground" && row?.team.count == 3 && row?.note.hasSuffix("마리") == true && shop?.hint.contains("배워요") == true
        check(t >= 0 && sorted && teamOK && rowOK, "5.2 기술머신: the W 상점's tab (the \(Machines.sold.count): 번호순 · 타입순 · 값순, 우리 팀만), a row TM26 지진 · 땅 · 물리 · 위력 100 · n마리 · the team's three, who learns it under the list",
              "\(tabs) \(byNo.count) \(sorted) \(team.count) \(teamOK) \(String(describing: row)) \(String(describing: shop?.hint))")

        w.press(1); w.press(1)                                                                             // ● → ×1 → ● 정말 살까? → 예 (a once-only row, as a legend's)
        var asked = false; if case .shopConfirm = w.screen { asked = true; w.screen = .shopConfirm(bp: false, sel: k26, yes: true); w.press(1); drain(w) }
        let bought = asked && served(w)?.tms == [26] && w.state.watts == 9_999 - Machines.price(26) && w.paneContent(Date()).shop?.rows.first { $0.name.hasPrefix("TM26") }?.price == "보유"
        while case .say = w.screen { w.press(1) }
        w.screen = .items(Walker.tmRow0)
        let bag = w.paneContent(Date()).items, bagOK = w.itemTabs.contains("기술머신") && bag?.rows.first?.tm?.label == "TM26" && bag?.action == "가르칠 포켓몬 고르기"
        w.press(1)                                                                                         // 가르칠 포켓몬 고르기 → the companion (it learns it)
        var picked = false; if case .itemOn(let p) = w.screen { picked = p.item == "기술머신26" && p.pick == -1; w.press(1) }
        var slots = false; if case .relearn(-1, 3, nil) = w.screen { slots = w.paneContent(Date()).relearn?.hint == "지진을 넣을 칸을 골라요" }
        w.press(1)
        var onIt = false; if case .relearn(-1, 3, 89?) = w.screen { onIt = w.paneContent(Date()).relearn?.pick?.rows.first { $0.move.name == "지진" }?.tag == "TM26" }
        w.press(1); drain(w)
        let learnt = served(w)?.companion.known?[3] == 89 && w.state.relearnable(w.state.companion).contains(89)
        let disc = itemPic("기술머신26").px.contains { $0 != 0 }
        var bad: [String] = []
        for scr in [Screen.shop(bp: false, sel: k26, qty: nil), .items(Walker.tmRow0), .relearn(ref: -1, slot: 3, at: 89)] { w.screen = scr; let fb = w.compose(Date()); bad += fb.runs.filter { $0.x < 0 || $0.x + $0.w > 96 }.map { $0.s } + runClashes(fb.runs) }
        check(bought && bagOK && picked && slots && onIt && learnt && disc && bad.isEmpty,
              "5.2 기술머신: bought once (정말 살까? → Walk.tms, 보유), the bag's 기술머신 tab (TM26, no count), 가르칠 포켓몬 고르기 → 기술 바꾸기 (지진을 넣을 칸을 골라요 → on 지진, TM26) → learnt; the disc; the LCD inside",
              "\(bought) \(String(describing: served(w)?.tms)) \(bagOK) \(picked) \(slots) \(onIt) \(learnt) \(disc) \(bad)")
    } } }
    return c
}
