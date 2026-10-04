#if os(macOS)
import AppKit
// `PokeWalker --shots <dir>` (a dev build only: main.swift): a few screens drawn offscreen by the Mac's own view, as PNGs to look at — no window,
// never the save; the walkers are the self-test's (a fake server where one is needed).

@MainActor func shots(_ dir: String) -> Int {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var n = 0
    func base() -> Walk { var s = Walk(), r = Seeded(s: 3); s.companion = Mon.wild(25, level: 30, &r); s.caught = [Mon.wild(16, level: 8, &r)]; s.watts = 1234; s.bp = 40; return s }
    func take(_ name: String, _ v: Walker, _ set: (Walker) -> Void) {
        let view = WalkerView(walker: v); set(v)
        v.refreshPane(Date(), force: true); view.fitWindow(); view.shown = v.compose(Date()); view.page.needsDisplay = true
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if (try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))) != nil { n += 1 }
    }
    let off = online(base()), (srv, _) = server(off)
    srv.down = true; off.cloud!.addSteps(120); off.cloud!.saveNow(); off.tick(Date()); off.tick(Date())   // no answer: offline, 120 steps waiting
    take("menu_offline", off) { v in v.screen = .menu(0) }
    let on = online(base())
    take("menu_online", on) { v in v.screen = .menu(0) }
    take("wait_dots", on) { v in
        v.waiting = Walker.Waiting(act: .radar, back: .home, since: Date().addingTimeInterval(-0.7), quiet: false, then: { _, _ in nil })
        v.screen = .say(["포켓 레이더", "준비 중..."], next: .home, since: .distantFuture)
    }
    take("say_offline", off) { v in v.waiting = nil; v.screen = .say(Walker.offlineLines, next: .home, since: Date()) }
    let bag = online({ var s = base(); s.items = ["상처약", "기력의조각", "금구슬"]; s.bag = ["이상한사탕", "금구슬", "타우린", "하이퍼볼", "천둥의돌", "라즈열매", "은색병뚜껑", "좋은상처약", "큰진주", "진주", "별의모래"] + Array(repeating: "금구슬", count: 40); return s }())
    take("items_sell", bag) { v in v.screen = .items(0) }
    take("items_scrolled", bag) { v in v.screen = .items(9) }
    let few = online({ var s = base(); s.bag = ["진주"]; return s }())
    take("items_one", few) { v in v.screen = .items(0) }
    let walked = online({ var s = base(); s.earned = 10_000_000; s.owned = Array(1...160); s.dex(); return s }())
    for p in 0..<((courses.count + CourseModel.perPage - 1) / CourseModel.perPage) { take("course_p\(p + 1)", walked) { v in v.screen = .course(p * CourseModel.perPage) } }
    let locked = online(base())
    take("course_locked", locked) { v in v.screen = .course(0) }
    let grid = online({ var s = base(); s.box = (0..<12).map { Mon(dex: [19, 41, 133, 147, 4, 1, 95, 129, 16, 25, 74, 92][$0], level: 5 + $0, female: false) }; return s }())
    take("box_one_click", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.gridTap(10003) }
    take("box_two_clicks", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.gridTap(10003); v.gridTap(10003) }
    let dexed = online({ var s = base(); s.owned = [1, 4, 7, 25, 133]; s.seen = [16, 19]; s.dex(); return s }())
    take("dex_one_click", dexed) { v in v.screen = .dex(25, filter: 0, detail: false); v.gridTap(10003) }
    take("dex_two_clicks", dexed) { v in v.screen = .dex(25, filter: 0, detail: false); v.gridTap(10003); v.gridTap(10003) }
    // 3.2 (12 M1): the team
    let tsrv = FakeCloud(), tme = online({ var s = base(); s.today = 4321; s.towerBest = 6; s.owned = Array(1...48); return s }(), server: tsrv)
    let mates: [(String, Int, Int, Int, Int, Int, Bool)] = [("민수", 6, 52, 12_345, 160, 21, true), ("지은", 282, 47, 9_876, 210, 35, true), ("도윤", 448, 61, 15_002, 188, 14, false),
        ("서연", 133, 30, 3_210, 95, 3, false), ("하은", 25, 18, 1_234, 40, 0, true), ("현우", 149, 70, 22_222, 260, 49, false), ("유나", 393, 25, 5_555, 120, 8, false),
        ("준호", 445, 55, 8_100, 175, 27, false), ("보라", 359, 44, 7_000, 140, 12, false), ("태양", 248, 58, 11_000, 199, 30, false), ("트레이너긴이름", 4, 12, 600, 22, 1, false)]
    for (k, m) in mates.enumerated() {
        var w = Walk(), r = Seeded(s: UInt64(k + 5)); w.companion = Mon.wild(m.1, level: m.2, shiny: k == 1 ? true : nil, &r); w.caught = [Mon.wild(16, level: 20 + k, &r), Mon.wild(41, level: 15 + k, &r)]
        w.today = m.3; w.owned = Array(1...m.4); w.towerBest = m.5; w.total = m.3 * 20; w.bestChain = k + 3; w.bp = 10 * k; w.course = k % 5
        tsrv.add(m.0, w); tsrv.lastAct[m.0] = m.6 ? Date() : Date().addingTimeInterval(Double(-600 * (k + 1)))
    }
    tme.cloud!.teamDue = true; drain(tme)
    take("menu_team", tme) { v in v.screen = .menu(menuAt("팀")) }
    for t in 0..<4 { take("team_tab\(t)", tme) { v in v.screen = .team(sel: 0, tab: t, card: false) } }
    take("team_page2", tme) { v in v.screen = .team(sel: 7, tab: 0, card: false) }
    take("team_card", tme) { v in v.screen = .team(sel: 1, tab: 0, card: true) }
    take("team_card_me", tme) { v in let i = v.teamRows(0).firstIndex { v.isMe($0.card) } ?? 0; v.screen = .team(sel: i, tab: 0, card: true) }
    take("home_visitor", tme) { v in v.screen = .home; v.visitor = Visitor(name: "민수", dex: 6, shiny: false, until: Date().addingTimeInterval(60), hello: false) }
    take("home_hello", tme) { v in v.screen = .home; v.visitor = Visitor(name: "지은", dex: 282, shiny: true, until: Date().addingTimeInterval(60), hello: true) }
    take("home_visitor_tall", tme) { v in v.screen = .home; v.state.companion = Mon(dex: 384, level: 70, female: false); v.visitor = Visitor(name: "현우", dex: 149, shiny: false, until: Date().addingTimeInterval(60), hello: false) }
    // 3.3 (12 M2): 교환
    serve(tme) { w in var r = Seeded(s: 41); w.box = (0..<40).map { k in Mon.wild([19, 41, 133, 147, 4, 1, 95, 129, 16, 25, 74, 92, 66, 63, 61, 64][k % 16], level: 5 + k, shiny: k == 7 ? true : nil, &r) } }
    if var minsu = tsrv.walk("민수") {
        var r = Seeded(s: 42); minsu.box = (0..<30).map { k in var m = Mon.wild([94, 6, 149, 130, 131, 143, 65, 68, 76, 59][k % 10], level: 20 + k, shiny: k == 4 ? true : nil, &r); m.uid = 500 + k; return m }
        tsrv.set("민수", minsu)
    }
    let me = tme.myName.lowercased(), at = Int(Date().timeIntervalSince1970)
    func mon(_ d: Int, _ l: Int, _ u: Int, shiny: Bool? = nil) -> Mon { var r = Seeded(s: UInt64(u)); var m = Mon.wild(d, level: l, shiny: shiny, &r); m.uid = u; return m }
    tsrv.offers = [(TradeOffer(id: 1, from: "민수", to: tme.myName, mon: mon(94, 41, 520), want: tme.state.box[3], at: at - 3 * 3600, state: "open"), "민수", me),
                   (TradeOffer(id: 2, from: "지은", to: tme.myName, mon: mon(282, 36, 521, shiny: true), want: nil, at: at - 20 * 3600, state: "open"), "지은", me),
                   (TradeOffer(id: 3, from: tme.myName, to: "도윤", mon: tme.state.box[0], want: mon(448, 50, 522), at: at - 600, state: "open"), me, "도윤")]
    tme.cloud!.tradesDue = true; drain(tme)
    take("menu_team_trades", tme) { v in v.screen = .menu(menuAt("팀")) }
    take("team_card_trade", tme) { v in v.screen = .team(sel: 0, tab: 0, card: true) }
    take("trade_list", tme) { v in v.screen = .trade(.list(0)) }
    take("trade_offer_in", tme) { v in v.screen = .trade(.offer(id: 1, act: nil)) }
    take("trade_offer_any", tme) { v in v.screen = .trade(.offer(id: 2, act: 1)) }
    take("trade_offer_out", tme) { v in v.screen = .trade(.offer(id: 3, act: nil)) }
    take("trade_pick_loading", tme) { v in v.cloud!.wantBox("현우"); v.screen = .trade(.pick(TradePick(to: "현우"))) }
    tme.cloud!.wantBox("민수"); drain(tme)
    take("trade_pick_theirs", tme) { v in v.screen = .trade(.pick(TradePick(to: "민수"))) }
    take("trade_pick_theirs_p2", tme) { v in v.screen = .trade(.pick(TradePick(to: "민수", at: 26))) }
    take("trade_pick_mine", tme) { v in v.screen = .trade(.pick(TradePick(to: "민수", want: 504, side: 0, at: 2))) }
    take("trade_pick_ready", tme) { v in v.screen = .trade(.pick(TradePick(to: "민수", give: v.myTradeBox[5].uid, want: 504, side: 0, at: 5))) }
    take("trade_pick_any_ready", tme) { v in v.screen = .trade(.pick(TradePick(to: "민수", give: v.myTradeBox[7].uid, want: nil, side: 1, at: 0))) }
    take("trade_pick_answer", tme) { v in v.screen = .trade(.pick(TradePick(to: "지은", offer: 2, give: v.myTradeBox[1].uid, side: 0, at: 1))) }
    for u in [0.5, 1.7, 2.3, 3.0, 3.3, 3.8, 5.0] {
        take("traded_\(Int(u * 10))", tme) { v in v.screen = .traded(gave: v.myTradeBox[2], got: mon(64, 30, 600), with: "민수", since: Date().addingTimeInterval(-u)) }
    }
    take("box_ot", tme) { v in v.state.box[4].ot = "민수"; v.screen = .box(4, act: nil, confirm: false, detail: true) }
    let fresh = online(base())
    fresh.cloud!.tradesDue = true; drain(fresh)
    take("trade_list_empty", fresh) { v in v.screen = .trade(.list(0)) }
    take("trade_pick_mine_empty", fresh) { v in v.screen = .trade(.pick(TradePick(to: "민수", side: 0))) }
    let onix = online({ var s = base(); s.companion = Mon(dex: 95, level: 30, female: false); s.bag = ["금속코트"]; return s }())
    take("mon_trade_evo", onix) { v in v.screen = .box(-1, act: nil, confirm: false, detail: true) }
    // 3.4 (12 M3): 레이드
    let rsrv = FakeCloud(); rsrv.raidOpen(4_200_000); rsrv.raidLeft = 2_730_000
    let rme = online({ var s = base(); s.raidPower = 2340; s.caught = [Mon(dex: 149, level: 61, female: false), Mon(dex: 6, level: 55, female: false)]; return s }(), server: rsrv)
    for (k, m) in mates.prefix(7).enumerated() { rsrv.add(m.0, Walk()); rsrv.raidDealt[m.0.lowercased()] = [412_000, 388_000, 201_500, 150_000, 99_000, 61_000, 12_000][k]; rsrv.raidFights[m.0.lowercased()] = 9 - k }
    rsrv.raidDealt[rme.myName.lowercased()] = 46_500; rsrv.raidFights[rme.myName.lowercased()] = 3
    let ts = Int(Date().timeIntervalSince1970)
    rsrv.raidRecent = [RaidHit(name: "민수", dex: 6, dealt: 21_340, at: ts - 120), RaidHit(name: rme.myName, dex: 25, dealt: 18_002, at: ts - 900), RaidHit(name: "지은", dex: 282, dealt: 30_115, at: ts - 4000),
                       RaidHit(name: "트레이너긴이름", dex: 4, dealt: 2_100, at: ts - 9000), RaidHit(name: "도윤", dex: 448, dealt: 25_000, at: ts - 20000), RaidHit(name: "서연", dex: 133, dealt: 9_990, at: ts - 30000)]
    take("raid_loading", rme) { v in v.screen = .raid(tab: 0) }
    rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("menu_raid", rme) { v in v.screen = .menu(menuAt("레이드")) }
    take("raid_lobby", rme) { v in v.screen = .raid(tab: 0) }
    take("raid_recent", rme) { v in v.screen = .raid(tab: 1) }
    take("raid_no_power", rme) { v in v.state.raidPower = 640; v.screen = .raid(tab: 0) }
    take("raid_full_power", rme) { v in v.state.raidPower = 3000; v.screen = .raid(tab: 0) }
    var rr = Seeded(s: 5); let rb = { () -> Battle in var b = Battle(wild: rsrv.raidBoss, party: [rme.state.companion] + rme.state.caught); b.theirs += [Fighter(rsrv.raidBoss), Fighter(rsrv.raidBoss)]; return b }()
    let rbeats = { () -> (Battle, [Beat]) in var b = rb; let bs = b.begin(weather: nil, &rr); return (b, bs) }()
    take("raid_appear", rme) { v in v.raidOn = true; v.screen = .beats(rbeats.0, rbeats.1, since: Date().addingTimeInterval(-1.2), from: rb) }
    take("raid_menu", rme) { v in v.raidOn = true; var b = rbeats.0; b.theirs[0].hp = 0; b.it = 1; b.theirs[1].hp = b.theirs[1].maxHP / 3; v.fight = b; v.screen = .battle(b, sel: 3) }
    take("raid_standup", rme) { v in v.raidOn = true; var b = rbeats.0; b.theirs[0].hp = 0; v.screen = .beats(b, [.sendOut(.it, 1)], since: Date().addingTimeInterval(-0.8), from: b) }
    take("raid_done", rme) { v in v.raidOn = false; v.screen = .say(["38,214 데미지! +1BP", "보스를 쓰러뜨렸다!", "볼을 던질 수 있다"], next: .raid(tab: 0), since: Date()) }
    take("raid_throw", rme) { v in v.raidOn = false; v.usedItem = "몬스터볼"; let b = Battle(wild: rsrv.raidBoss, companion: v.state.companion); v.raidThen = .home; v.screen = .beats(b, [.thrown(shakes: 2), .broke], since: Date().addingTimeInterval(-2.4), from: b) }
    rsrv.raidLeft = 0; rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("raid_cleared", rme) { v in v.raidThen = nil; v.state.raidPower = 2340; v.screen = .raid(tab: 0) }
    take("menu_raid_cleared", rme) { v in v.screen = .menu(menuAt("레이드")) }
    rsrv.raidBalls[rme.myName.lowercased()] = 2; rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("raid_balls_left", rme) { v in v.screen = .raid(tab: 0) }
    rsrv.raidCaught.insert(rme.myName.lowercased()); rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("raid_caught", rme) { v in v.screen = .raid(tab: 0) }
    take("grid_drag_to_walker", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (10002, CGPoint(x: 150 * K, y: 30 * K)) }
    take("grid_drag_to_box", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (4501, CGPoint(x: 100 * K, y: 120 * K)) }
    return n
}
#endif
