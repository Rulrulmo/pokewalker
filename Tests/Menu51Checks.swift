import Foundation
// 5.1 (the user via 회사 10-16, the mockups' third round "ㅇㅇ"): self-test checks (run by selftest()) — the first page's eight with 레이드 ▸ on its
// own and 우편함 in 친구 ▸ (its red dot and line on 친구's tile), 5.0's remembered tile let go; 친구's tabs 친구 · 신청 · 맡기기 · 전체; 친구 ▸ 랭킹 (this
// week's 레이드 the legend raid alone, 메가 레이드 the Mega raid's wins and stones, 친구 / 전체, ● a card); 우편 지우기 (one; a gift left: not; every
// one taken, asked first) — the list, its dot and its line at once.

@MainActor func menu51Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) {
        // the menu
        let names = menuTiles.map(\.name), groups = Dictionary(uniqueKeysWithValues: menuTiles.map { ($0.name, $0.items) })
        let menuOK = names == ["포켓 레이더", "모험", "포켓몬", "기록", "배틀", "레이드", "친구", "상점"] && groups["배틀"] == ["배틀 타워", "대전"] && groups["레이드"] == ["레이드", "메가 레이드"]
            && groups["친구"] == ["친구", "교환", "랭킹", "우편함"] && { if case .menu(6?, 3) = menuFor("우편함") { return true }; return false }()
        let k0 = settings.int("ui.menuLayout", 0), t0 = settings.int("ui.lastTile", 0)                  // 5.0's remembered tile (7 = its 우편함): let go once
        settings.set("ui.menuLayout", 0); settings.set("ui.lastTile", 7)
        let fresh = Walker(state: Walk()), reset = fresh.lastTile == 0 && settings.int("ui.menuLayout", 0) == 51
        settings.set("ui.menuLayout", k0); settings.set("ui.lastTile", t0)
        // three trainers: a, b friends; z everyone's (전체)
        let sv = FakeCloud()
        let a = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 30, female: false); s.bag = Array(Forms.stones.prefix(3)); return s }(), server: sv)
        let b = online({ var s = Walk(); s.companion = Mon(dex: 6, level: 50, female: false); s.bag = Array(Forms.stones.prefix(9)); return s }(), server: sv)
        let z = online({ var s = Walk(); s.companion = Mon(dex: 150, level: 70, female: false); return s }(), server: sv)
        let (ak, bk, zk) = (a.myName.lowercased(), b.myName.lowercased(), z.myName.lowercased()), day = Walk.key(Date()), t = Int(Date().timeIntervalSince1970)
        sv.befriend(ak, bk); sv.viewAll.insert(ak)
        func run(_ won: Bool, mega: Bool) -> FakeCloud.RaidRun { .init(tier: 3, boss: Mon(dex: 249, level: 70, female: false), day: day, at: t - 600, bars: won ? 10 : 4, won: won, ended: true, mega: mega) }
        sv.raidRuns[ak] = [run(true, mega: false), run(true, mega: false), run(true, mega: true)]           // a: 2 legend wins, 1 Mega
        sv.raidRuns[bk] = [run(true, mega: false), run(true, mega: true), run(true, mega: true), run(true, mega: true)]   // b: 1 legend, 3 Mega
        sv.raidRuns[zk] = [run(true, mega: true), run(true, mega: true), run(true, mega: true), run(true, mega: true), run(true, mega: true)]
        a.cloud!.teamDue = true; drain(a); drain(a)
        // 친구's tabs
        let tabs = a.teamTabLabels; a.screen = .team(sel: 0, tab: TeamTab.friends, card: false); a.pageTap(6001)
        let toReq = { if case .team(_, TeamTab.requests, false) = a.screen { return true }; return false }()
        let tabsOK = tabs == ["친구", "신청", "맡기기", "전체"] && toReq
        // 랭킹
        a.openFeature("랭킹"); drain(a)
        let raidRows = a.rankRows(3, false).map { $0.card.name.lowercased() }, megaRows = a.rankRows(4, false).map { $0.card.name.lowercased() }
        a.screen = .rank(tab: 4, sel: 0, all: false); let megaPane = a.paneContent(Date()).team
        a.pageTap(6091); let allRows = a.rankRows(4, true).map { $0.card.name.lowercased() }, onAll = { if case .rank(4, 0, true) = a.screen { return true }; return false }()
        a.screen = .rank(tab: 3, sel: 0, all: false); a.press(1); let card = { if case .team(_, TeamTab.friends, true) = a.screen { return true }; return false }()
        let rankOK = raidRows == [ak, bk] && megaRows == [bk, ak] && megaPane?.rows.first?.value == "3승 · 스톤 9/\(MegaRaid.stones.count)" && megaPane?.scope == 0
            && onAll && allRows.first == zk && card && a.rankNote.hasPrefix("이번 주 걸음 ")
        // 우편 지우기
        sv.giveMail(ak, "notice", from: "운영자", title: "안내", body: "읽기만 해요", [])
        sv.giveMail(ak, "admin", from: "운영자", title: "선물", [.bp(amount: 5)])
        a.cloud!.mailDue = true; drain(a)
        let notice = a.mails.first { $0.gifts.isEmpty }!, gift = a.mails.first { !$0.gifts.isEmpty }!
        a.screen = .mail(.open(id: gift.id)); let giftOpen = a.paneContent(Date()).mailOpen; a.pageTap(8841); drain(a)
        let keptGift = giftOpen?.del == false && giftOpen?.delWhy != nil && !sv.acts.contains(.mailDelete(id: gift.id))
        a.screen = .mail(.open(id: notice.id)); a.pageTap(8841); drain(a)
        let gone = sv.acts.contains(.mailDelete(id: notice.id)) && !a.mails.contains { $0.id == notice.id } && { if case .say(["우편을 지웠다"], .mail(.list(0)), _) = a.screen { return true }; return false }()
        a.screen = .mail(.list(sel: 0)); a.pageTap(8830); drain(a)                                      // 모두 받기: the gift taken — then it can go too
        a.screen = .mail(.list(sel: 0)); let list = a.paneContent(Date()).mailList
        (a.host as? TestHost)?.answer = true; a.pageTap(8831); drain(a)
        let all = list?.delAll == "받은 1통 지우기" && sv.acts.contains(.mailDeleteAll) && a.mails.isEmpty && !a.mailDot
        c.append((menuOK && reset && tabsOK && rankOK && keptGift && gone && all,
                  "5.1 메뉴 · 친구 · 랭킹 · 우편 지우기: the eight (레이드 ▸ its own, 우편함 in 친구 ▸), 5.0's tile let go; 친구 · 신청 · 맡기기 · 전체; 랭킹's 레이드 (the legend raid alone) · 메가 레이드 (wins · stones), 전체, ● a card; a mail out (a gift left: not), every one taken out, asked first"))
        if !(menuOK && reset && tabsOK && rankOK && keptGift && gone && all) {
            print("menu51: \(menuOK) \(reset) \(tabs) \(toReq) \(raidRows) \(megaRows) \(String(describing: megaPane?.rows.first?.value)) \(onAll) \(allRows) \(card) \(a.rankNote) \(keptGift) \(gone) \(String(describing: list?.delAll)) \(all)")
        }
    } }
    return c
}
