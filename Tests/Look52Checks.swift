import Foundation
// 5.2 (MegaLook.swift · Find52.swift): self-test checks (run by selftest()) — 메가 모습 (홈: the companion holding its stone shows its Mega, the
// 메가 pill turns it off and on; the page's 메가 모습 보기: its stats, the stone's three states, X → Y, back), 이로치 찾기 (★: 찾기 이로치), 교환 찾기
// (the board's filters, chips and tags; a pick's 찾기 and 안 잡은 종, the uncaught dotted), 홈's 레이드 row (its group, ↩ the group, ↩ home,
// the groups' last tiles kept; 루기아 · 메가 2종 · 파워 n칸).

@MainActor func look52Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) {
        var r = Seeded(s: 31)
        var saur = Mon.wild(3, level: 55, &r); saur.item = "이상해꽃나이트"
        var s = Walk(); s.companion = saur; s.caught = [Mon.wild(25, level: 30, &r)]
        s.box = [Mon.wild(6, level: 36, &r), Mon.wild(129, level: 10, &r), Mon.wild(133, level: 20, &r), Mon.wild(16, level: 8, &r)]
        s.box[1].shiny = true; s.box[3].shiny = true; s.bag = ["리자몽나이트Y"]; s.owned = [3, 6, 25, 129, 133, 16]; s.seen = Array(1...40)
        let w = online(s)
        // 메가 모습: 홈 and its pill
        let mega = w.homeLook.form == 1 && w.homeLook.art != w.state.companion.art
        w.screen = .home; w.paneTap(9340); let off = !w.megaHome && w.homeLook.form == nil; w.paneTap(9340)
        // the page: 메가 모습 보기 → its numbers; 리자몽 (the stone in the bag): X, ▶ Y; back
        w.screen = .box(-1, act: nil, confirm: false, detail: true)
        let link = w.paneContent(Date()).mon?.megaLink == true
        w.paneTap(4413); let mv = w.paneContent(Date()).mon?.mega
        let view = mv?.name == "메가이상해꽃" && mv?.stoneState == 2 && mv?.home == true && mv?.mega.reduce(0, +) == 625 && mv?.base.reduce(0, +) == 525
        w.press(1); let back = w.megaLookForm == nil && w.paneContent(Date()).mon?.mega == nil
        w.screen = .box(0, act: nil, confirm: false, detail: true); w.paneTap(4413)
        let x = w.paneContent(Date()).mon?.mega; w.press(2); let y = w.paneContent(Date()).mon?.mega
        let zard = x?.name == "메가리자몽X" && x?.stoneState == 0 && x?.next == "메가리자몽Y ▶" && x?.home == nil && y?.name == "메가리자몽Y" && y?.stoneState == 1
        _ = w.key(.back); let backKey: Bool = { if case .box(0, _, _, true) = w.screen { return w.megaLookForm == nil }; return false }()
        check(mega && off && link && view && back && zard && backKey,
              "5.2 메가 모습: 홈's companion holding its stone shows its Mega (the 메가 pill: off, on), the page's 메가 모습 보기 (525 → 625, 지니고 있어요, 홈 켜짐), ● back; 리자몽: X (메가 레이드에서), ▶ Y (가방에 있어요), ↩ its page",
              "\(mega) \(off) \(link) \(String(describing: mv)) \(back) \(String(describing: x?.name)) \(String(describing: y?.name)) \(backKey)")

        // 이로치: ★
        w.screen = .box(-1, act: nil, confirm: false); w.paneTap(4173)
        let shinyOnly = w.boxQuery == "이로치" && w.boxShown.count == 2 && w.boxShown.allSatisfy { w.state.box[$0].shiny == true }
        w.paneTap(4173); let cleared = w.boxQuery.isEmpty && w.boxShown.count == 4
        check(shinyOnly && cleared, "5.2 이로치 찾기: the 상자's ★ keeps the 이로치 (찾기 이로치), again: all", "\(shinyOnly) \(cleared) \(w.boxShown)")

        // 교환: the board's filters and tags, a pick's 찾기 and 안 잡은 종
        let (srv, _) = server(w), ts = Int(Date().timeIntervalSince1970)
        func post(_ from: String, _ dex: Int, _ wish: [Int], shiny: Bool = false) {
            var m = Mon.wild(dex, level: 20, &r); m.shiny = shiny
            srv.listings.append((Listing(id: srv.nextListing, from: from, mon: m, wish: wish, at: ts - 600, bids: 0, mine: false, note: nil), from, true)); srv.nextListing += 1
        }
        post("민수", 280, []); post("지은", 133, [129]); post("도윤", 447, [], shiny: true); post("서연", 25, [])
        w.cloud!.marketDue = true; drain(w); drain(w)
        w.screen = .market(.board(tab: 0, sel: 0))
        let board = w.paneContent(Date()).board
        let chips = board?.chips == ["찾기", "새 종 2", "내 것 원함 1", "★·3V 1"] && board?.rows.first { $0.line.contains("랄토스") }?.pill == "새 종" && board?.rows.first { $0.line.contains("이브이") }?.pill == "내 것 원함"
        w.pageTap(8041); let onlyNew = w.boardRows(0).count == 2 && w.boardRows(0).allSatisfy(w.boardNew)
        w.pageTap(8041); let allBack = w.boardRows(0).count == 4
        w.boardQuery = "이브"; let found = w.boardRows(0).map(\.mon.dex) == [133]; w.boardQuery = ""
        w.screen = .market(.pick(MarketPick(listing: nil, give: w.state.box[0].uid, wish: [], side: 1, at: 0)))
        let wishAll = w.marketPickList(MarketPick(side: 1)).count
        w.pageTap(8144); let wishNew = w.marketPickList(MarketPick(side: 1)).count, pick = w.paneContent(Date()).pick
        let dotted = pick?.colour == true && pick?.newOnly == true && pick?.dots.count == pick?.cells.count
        w.pageTap(8144); w.pickQuery = "피카"; let pika = w.marketPickList(MarketPick(side: 1)).map(\.dex) == [25]; w.pickQuery = ""
        check(chips && onlyNew && allBack && found && wishNew == wishAll - 6 && dotted && pika,
              "5.2 교환 찾기: the board's chips (찾기 · 새 종 n · 내 것 원함 n · ★·3V n) and tags, 새 종 only, 찾기 on its Pokémon; the wish grid: 안 잡은 종 (dotted, in colour), 찾기",
              "\(String(describing: board?.chips)) \(chips) \(onlyNew) \(allBack) \(found) \(wishAll) \(wishNew) \(dotted) \(pika)")
    } }
    // 홈's 레이드 row: its group (‹ 홈), the lobby ↩ the group ↩ home; the groups' last tiles kept; both raids on the row
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) { Content.$testingDaily.withValue(true) {
        let w = online({ var s = Walk(); s.raidPower = 4 * Engine.raidPowerCost + 10; s.day = Walk.key(Date()); return s }())
        w.cloud!.raidDue = true; w.cloud!.megaRaidDue = true; drain(w); drain(w)
        let g = menuTiles.firstIndex { $0.items.contains("레이드") } ?? 0
        w.menuSlot = [g: 1]
        let rowAt = w.statusModel().rows.firstIndex { $0.key == "레이드" } ?? 0, text = w.statusModel().rows[rowAt].value
        w.screen = .home; w.paneTap(9300 + rowAt)
        var group = false; if case .menu(g?, _) = w.screen { group = w.title().title == "홈" }
        w.press(1); drain(w); var lobby = false; if case .raid(.lobby) = w.screen { lobby = true }
        _ = w.key(.back); var backGroup = false; if case .menu(g?, _) = w.screen { backGroup = true }
        _ = w.key(.back); let home: Bool = { if case .home = w.screen { return true }; return false }()
        check(group && lobby && backGroup && home && w.menuSlot[g] == 1 && text.hasSuffix("파워 4칸") && text.contains(" · 메가 "),
              "5.2 홈's 레이드 row: 레이드 ▸ (‹ 홈) → the lobby → ↩ the group → ↩ 홈; the group's last tile kept; the row: 루기아 · 메가 2종 · 파워 4칸",
              "\(text) \(group) \(lobby) \(backGroup) \(home) \(w.menuSlot)")
    } } }
    return c
}
