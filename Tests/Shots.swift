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
    take("menu_team", tme) { v in v.screen = .menu(menuAt("친구")) }
    for t in 0..<4 { take("team_tab\(t)", tme) { v in v.screen = .team(sel: 0, tab: t, card: false) } }
    take("team_page2", tme) { v in v.screen = .team(sel: 7, tab: 0, card: false) }
    take("team_card", tme) { v in v.screen = .team(sel: 1, tab: 0, card: true) }
    take("team_card_me", tme) { v in let i = v.teamRows(0).firstIndex { v.isMe($0.card) } ?? 0; v.screen = .team(sel: i, tab: 0, card: true) }
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
    take("menu_team_trades", tme) { v in v.screen = .menu(menuAt("친구")) }
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
    let rme = online({ var s = base(); s.raidPower = Engine.raidPowerCost * 234 / 100; s.caught = [Mon(dex: 149, level: 61, female: false), Mon(dex: 6, level: 55, female: false)]; return s }(), server: rsrv)
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
    take("raid_no_power", rme) { v in v.state.raidPower = Engine.raidPowerCost * 64 / 100; v.screen = .raid(tab: 0) }
    take("raid_full_power", rme) { v in v.state.raidPower = Engine.raidPowerMax; v.screen = .raid(tab: 0) }
    var rr = Seeded(s: 5); let rb = { () -> Battle in var b = Battle(wild: rsrv.raidBoss, party: [rme.state.companion] + rme.state.caught); b.theirs += [Fighter(rsrv.raidBoss), Fighter(rsrv.raidBoss)]; return b }()
    let rbeats = { () -> (Battle, [Beat]) in var b = rb; let bs = b.begin(weather: nil, &rr); return (b, bs) }()
    take("raid_appear", rme) { v in v.raidOn = true; v.screen = .beats(rbeats.0, rbeats.1, since: Date().addingTimeInterval(-1.2), from: rb) }
    take("raid_menu", rme) { v in v.raidOn = true; var b = rbeats.0; b.theirs[0].hp = 0; b.it = 1; b.theirs[1].hp = b.theirs[1].maxHP / 3; v.fight = b; v.screen = .battle(b, sel: 3) }
    take("raid_standup", rme) { v in v.raidOn = true; var b = rbeats.0; b.theirs[0].hp = 0; v.screen = .beats(b, [.sendOut(.it, 1)], since: Date().addingTimeInterval(-0.8), from: b) }
    take("raid_done", rme) { v in v.raidOn = false; v.screen = .say(["38,214 데미지! +1BP", "보스를 쓰러뜨렸다!", "볼을 던질 수 있다"], next: .raid(tab: 0), since: Date()) }
    take("raid_throw", rme) { v in v.raidOn = false; v.usedItem = "몬스터볼"; let b = Battle(wild: rsrv.raidBoss, companion: v.state.companion); v.raidThen = .home; v.screen = .beats(b, [.thrown(shakes: 2), .broke], since: Date().addingTimeInterval(-2.4), from: b) }
    rsrv.raidLeft = 0; rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("raid_cleared", rme) { v in v.raidThen = nil; v.state.raidPower = Engine.raidPowerCost * 234 / 100; v.screen = .raid(tab: 0) }
    take("menu_raid_cleared", rme) { v in v.screen = .menu(menuAt("레이드")) }
    rsrv.raidBalls[rme.myName.lowercased()] = 2; rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("raid_balls_left", rme) { v in v.screen = .raid(tab: 0) }
    rsrv.raidCaught.insert(rme.myName.lowercased()); rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("raid_caught", rme) { v in v.screen = .raid(tab: 0) }
    // 3.5 (12 §2.4 · 3.3): 친구, the 교환 게시판
    let fsrv = FakeCloud(), fme = online({ var s = base(); s.seen = Array(1...151); s.owned = Array(1...60)
        var r = Seeded(s: 61); s.box = (0..<20).map { k in Mon.wild([19, 41, 133, 147, 4, 1, 95, 129, 16, 25][k % 10], level: 5 + k, shiny: k == 3 ? true : nil, &r) }; return s }(), server: fsrv)
    take("friends_empty", fme) { v in v.cloud!.teamDue = true; drain(v); v.screen = .team(sel: 0, tab: 0, card: false) }
    for (k, m) in mates.prefix(6).enumerated() {
        var w = Walk(), r = Seeded(s: UInt64(k + 30)); w.companion = Mon.wild(m.1, level: m.2, &r); w.today = m.3; w.owned = Array(1...m.4)
        w.box = [Mon.wild([94, 6, 149, 130, 65, 68][k], level: 30 + k, shiny: k == 1 ? true : nil, &r)]; w.box[0].uid = 900 + k
        fsrv.add(m.0, w); fsrv.lastAct[m.0] = m.6 ? Date() : Date().addingTimeInterval(-3600)
        if k < 4 { fsrv.befriend(fme.myName, m.0) }
    }
    fsrv.friendAsks[fme.myName.lowercased()] = ["현우", "유나"]; fsrv.friendAsks["트레이너긴이름"] = [fme.myName.lowercased()]
    fsrv.add("트레이너긴이름", Walk())
    fme.cloud!.teamDue = true; drain(fme); drain(fme)
    take("menu_friends", fme) { v in v.screen = .menu(menuAt("친구")) }
    take("menu_market", fme) { v in v.screen = .menu(menuAt("교환")) }
    take("friends_list", fme) { v in v.screen = .team(sel: 0, tab: 0, card: false) }
    take("friends_requests", fme) { v in v.screen = .team(sel: 0, tab: 4, card: false) }
    take("friends_card", fme) { v in let i = v.teamRows(0).firstIndex { !v.isMe($0.card) } ?? 0; v.screen = .team(sel: i, tab: 0, card: true) }
    let tsF = Int(Date().timeIntervalSince1970), meK = fme.myName.lowercased()
    func lst(_ id: Int, _ who: String, _ m: Mon, _ wish: [Int], _ ago: Int) -> (l: Listing, key: String, open: Bool) { (Listing(id: id, from: who, mon: m, wish: wish, at: tsF - ago, bids: 0, mine: false), who.lowercased(), true) }
    fsrv.listings = [lst(1, "민수", fsrv.walk("민수")!.box[0], [25, 133, 6], 50_000), lst(2, "지은", fsrv.walk("지은")!.box[0], [], 9000),
                     lst(3, fme.myName, fme.state.box[2], [94, 149], 7200), lst(4, "도윤", fsrv.walk("도윤")!.box[0], [1], 600), lst(5, fme.myName, fme.state.box[5], [], 300)]
    fsrv.listings[2].key = meK; fsrv.listings[4].key = meK
    fsrv.bids = [(Bid(id: 1, listing: 3, from: "민수", mon: fsrv.walk("민수")!.box[0], at: tsF - 3000, state: "open"), "민수", meK),
                 (Bid(id: 2, listing: 3, from: "서연", mon: fsrv.walk("서연")!.box[0], at: tsF - 900, state: "open"), "서연", meK),
                 (Bid(id: 3, listing: 1, from: fme.myName, mon: fme.state.box[7], at: tsF - 600, state: "open"), meK, "민수")]
    fme.cloud!.marketDue = true; drain(fme); drain(fme)
    take("market_all", fme) { v in v.screen = .market(.board(tab: 0, sel: 0)) }
    take("market_mine", fme) { v in v.screen = .market(.board(tab: 1, sel: 0)) }
    take("market_bids", fme) { v in v.screen = .market(.board(tab: 2, sel: 0)) }
    take("market_post_other", fme) { v in v.screen = .market(.post(id: 4, sel: nil)) }
    take("market_post_bid", fme) { v in v.screen = .market(.post(id: 1, sel: nil)) }
    take("market_post_mine", fme) { v in v.screen = .market(.post(id: 3, sel: nil)) }
    take("market_post_mine_pick", fme) { v in v.screen = .market(.post(id: 3, sel: 1)) }
    take("market_post_mine_none", fme) { v in v.screen = .market(.post(id: 5, sel: nil)) }
    take("market_pick_post", fme) { v in v.screen = .market(.pick(MarketPick(give: v.myTradeBox[4].uid, side: 0, at: 4))) }
    take("market_pick_wish", fme) { v in v.screen = .market(.pick(MarketPick(give: v.myTradeBox[4].uid, wish: [25, 133, 6], side: 1, at: 5))) }
    take("market_pick_bid", fme) { v in v.screen = .market(.pick(MarketPick(listing: 4, give: v.myTradeBox[3].uid, side: 0, at: 3))) }
    // 3.6 (12 §5, docs/plans/13): shop tabs, items on anyone, battle items on the bench, live battles
    let shop36 = online({ var s = base(); s.watts = 9999; s.bp = 400; return s }())
    take("shop_tab_heal", shop36) { v in v.screen = .shop(bp: false, sel: 0, qty: nil) }
    take("shop_tab_mint", shop36) { v in v.screen = .shop(bp: false, sel: v.shopRows(false, v.shopTabs(false).firstIndex(of: "민트") ?? 0).first ?? 0, qty: nil) }
    take("shop_bp_tabs", shop36) { v in v.screen = .shop(bp: true, sel: 0, qty: nil) }
    let it36 = online({ var s = base(); var r = Seeded(s: 71); s.box = (0..<14).map { k in Mon.wild([19, 133, 25, 1, 4, 7, 16, 41, 129, 92, 66, 74, 95, 63][k], level: 5 + 6 * k, &r) }
        s.bag = ["이상한사탕", "고집민트", "불꽃의돌", "타우린", "은색병뚜껑"]; return s }())
    take("item_pick_candy", it36) { v in v.screen = .itemOn(ItemOn(item: "이상한사탕", pick: -1, at: 0)) }
    take("item_pick_stone", it36) { v in v.screen = .itemOn(ItemOn(item: "불꽃의돌", pick: v.itemRefs.firstIndex { v.state.mon($0)?.dex == 133 }.map { v.itemRefs[$0] }, at: v.itemRefs.firstIndex { v.state.mon($0)?.dex == 133 } ?? 0)) }
    take("item_pick_cap_none", it36) { v in v.screen = .itemOn(ItemOn(item: "은색병뚜껑", pick: nil, at: 3)) }
    take("items_candy_button", it36) { v in v.screen = .items(v.state.inventory.firstIndex(of: "이상한사탕") ?? 0) }
    take("mon_mint", it36) { v in v.state.box[3].mint = natures.firstIndex { $0.name == "고집" }; v.screen = .box(3, act: nil, confirm: false, detail: true) }
    var bb = Battle(wild: Mon(dex: 129, level: 5, female: false), party: [it36.state.companion] + it36.state.caught); bb.mine[1].hp = 0; bb.mine[1].down = true
    take("battle_item_target", it36) { v in v.itemFor = "기력의조각"; v.fight = bb; v.screen = .party(bb, sel: 1) }
    take("duel_card", fme) { v in let i = v.teamRows(0).firstIndex { !v.isMe($0.card) && Walker.walkingNow($0.card) } ?? 0; v.screen = .team(sel: i, tab: 0, card: true) }
    take("duel_card_idle", fme) { v in let i = v.teamRows(0).firstIndex { !v.isMe($0.card) && !Walker.walkingNow($0.card) } ?? 0; v.screen = .team(sel: i, tab: 0, card: true) }
    take("duel_invite", tme) { v in v.duelOn = true; v.duel = DuelView(id: 1, state: "invited", opponent: "민수", challenger: false, deadline: Int(Date().timeIntervalSince1970) + 47); v.screen = .duel(.invite(id: 1, from: "민수")) }
    take("duel_wait_accept", tme) { v in v.duelOn = true; v.duel = DuelView(id: 1, state: "invited", opponent: "지은", challenger: true, deadline: Int(Date().timeIntervalSince1970) + 52); v.screen = .duel(.waitAccept(id: 1, to: "지은")) }
    var db36 = Battle(party: [Mon(dex: 25, level: 50, female: false), Mon(dex: 6, level: 50, female: false)], trainer: "민수", foes: [Mon(dex: 448, level: 50, female: false), Mon(dex: 130, level: 50, female: false)]); db36.pvp = true
    take("duel_menu", tme) { v in v.duelOn = true; v.duelWait = false; v.duel = DuelView(id: 1, state: "active", opponent: "민수", challenger: true, battle: db36, turn: 1, need: "move", deadline: Int(Date().timeIntervalSince1970) + 24); v.fight = db36; v.screen = .battle(db36, sel: 0) }
    take("duel_waiting", tme) { v in v.duelOn = true; v.duelWait = true; v.duel = DuelView(id: 1, state: "active", opponent: "민수", challenger: true, battle: db36, turn: 1, need: nil, deadline: Int(Date().timeIntervalSince1970) + 19); v.fight = db36; v.screen = .battle(db36, sel: 0) }
    take("duel_won", tme) { v in v.duelOn = false; v.duelWait = false; v.screen = .say(["이겼다!", "+3 BP"], next: .home, since: Date()) }
    // 3.7 (docs/plans/13 ⑤): 지닌 도구
    let h37 = online({ var s = base(); s.watts = 9999; s.bp = 400; s.companion.item = "생명의구슬"; s.caught[0].item = "먹다남은음식"
        var r = Seeded(s: 81); s.box = (0..<10).map { k in var m = Mon.wild([19, 133, 25, 1, 4, 7, 16, 41, 129, 92][k], level: 10 + 5 * k, &r); if k % 3 == 0 { m.item = "오랭열매" }; return m }
        s.bag = ["구애머리띠", "구애스카프", "기합의띠", "자뭉열매", "오랭열매", "금속코트", "목탄"]; return s }())
    take("mon_held", h37) { v in v.screen = .box(-1, act: nil, confirm: false, detail: true) }
    take("mon_held_none", h37) { v in v.screen = .box(1, act: nil, confirm: false, detail: true) }
    take("hold_pick", h37) { v in v.screen = .hold(ref: -1, sel: 2) }
    take("hold_pick_none", h37) { v in v.screen = .hold(ref: 1, sel: 0) }
    take("items_held_only", h37) { v in v.screen = .items(v.state.inventory.firstIndex(of: "구애머리띠") ?? 0) }
    take("box_held_dots", h37) { v in v.screen = .box(-1, act: nil, confirm: false) }
    take("shop_held_w", h37) { v in v.screen = .shop(bp: false, sel: v.shopRows(false, v.shopTabs(false).firstIndex(of: "지닌 도구") ?? 0).first ?? 0, qty: nil) }
    take("shop_berries", h37) { v in v.screen = .shop(bp: false, sel: v.shopRows(false, v.shopTabs(false).firstIndex(of: "열매") ?? 0).first ?? 0, qty: nil) }
    take("shop_held_bp", h37) { v in v.screen = .shop(bp: true, sel: v.shopRows(true, v.shopTabs(true).firstIndex(of: "지닌 도구") ?? 0).first ?? 0, qty: nil) }
    var hb = Battle(wild: Mon(dex: 130, level: 30, female: false), party: [h37.state.companion] + h37.state.caught); hb.mine[0].item = "생명의구슬"
    take("battle_held_hud", h37) { v in v.sideOn = true; v.fight = hb; v.screen = .battle(hb, sel: 0) }
    take("battle_held_party", h37) { v in v.sideOn = true; v.fight = hb; v.screen = .party(hb, sel: 1) }
    // 3.8 (docs/plans/14): 받기 · a post's 한마디 · the 교환 tile's dot, 맡겨 키우기, the 대전 menu, picks in order, 12 tiles
    fsrv.listings[0].l.note = "이브이랑 바꿔요!"; fsrv.listings[2].l.note = "레벨 높은 걸로 부탁해요"
    var r38 = Seeded(s: 91)
    fsrv.claimBox[meK] = [Claim(id: 1, kind: "traded", from: "민수", mon: Mon.wild(94, level: 31, &r38), at: tsF - 400),
                          Claim(id: 2, kind: "returned", from: "서연", mon: fme.state.box[9], at: tsF - 4000), Claim(id: 3, kind: "visit", from: "현우", mon: Mon.wild(4, level: 22, &r38), at: tsF - 90_000)]
    fme.cloud!.marketDue = true; drain(fme); drain(fme)
    take("market_claims", fme) { v in v.screen = .market(.board(tab: 3, sel: 0)) }
    take("market_claim_lcd", fme) { v in v.screen = .market(.board(tab: 3, sel: 1)) }
    take("menu_market_dot", fme) { v in v.screen = .menu(menuAt("교환")) }
    take("market_post_note", fme) { v in v.screen = .market(.post(id: 1, sel: nil)) }
    take("market_post_mine_note", fme) { v in v.screen = .market(.post(id: 3, sel: nil)) }
    let ends = tsF + 3 * 3600 + 1200
    fsrv.visitList = [FakeCloud.FakeVisit(id: 1, owner: meK, ownerName: fme.myName, host: "민수", hostName: "민수", mon: fme.state.box[11], steps: 3120, ends: ends),
                      FakeCloud.FakeVisit(id: 2, owner: "지은", ownerName: "지은", host: meK, hostName: fme.myName, mon: Mon.wild(282, level: 34, shiny: true, &r38), steps: 4380, ends: ends + 3000),
                      FakeCloud.FakeVisit(id: 3, owner: "현우", ownerName: "현우", host: meK, hostName: fme.myName, mon: Mon.wild(149, level: 55, &r38), steps: 870, ends: ends - 9000)]
    fme.cloud!.teamDue = true; drain(fme); drain(fme)
    take("friends_visits", fme) { v in v.screen = .team(sel: 0, tab: 5, card: false) }
    take("visit_pick", fme) { v in v.screen = .visitPick(ItemOn(item: "민수", pick: v.visitRefs[safe: 2], at: 2)) }
    take("home_guests", fme) { v in v.screen = .home }
    take("friends_card_visit", fme) { v in let i = v.teamRows(0).firstIndex { !v.isMe($0.card) && Walker.walkingNow($0.card) } ?? 0; v.screen = .team(sel: i, tab: 0, card: true) }
    take("menu_twelve", fme) { v in v.screen = .menu(menuAt("대전")) }
    take("duel_hub_noparty", fme) { v in v.screen = .duel(.hub(tab: 0, sel: 0)) }
    let uids = fme.state.box.compactMap(\.uid)
    fme.state.duelParty = [fme.state.companion.uid].compactMap { $0 } + Array(uids.prefix(4))
    take("duel_hub", fme) { v in v.screen = .duel(.hub(tab: 0, sel: 0)) }
    take("duel_hub_friend", fme) { v in v.screen = .duel(.hub(tab: 0, sel: 1)) }
    fme.cloud!.duelRecord = DuelRecords(wins: 3, losses: 2, recent: [
        DuelRecord(id: 5, opponent: "민수", won: true, why: "faint", at: tsF - 600, mine: [25, 133, 6], theirs: [94, 65, 68]),
        DuelRecord(id: 4, opponent: "지은", won: false, why: "forfeit", at: tsF - 7200, mine: [25, 19, 41], theirs: [282, 448, 445]),
        DuelRecord(id: 3, opponent: "트레이너긴이름", won: true, why: "timeout", at: tsF - 90_000, mine: [133, 6, 4], theirs: [149, 130, 6]),
        DuelRecord(id: 2, opponent: "도윤", won: true, why: "faint", at: tsF - 200_000, mine: [25, 133, 6], theirs: [1, 4, 7]),
        DuelRecord(id: 1, opponent: "서연", won: false, why: "faint", at: tsF - 300_000, mine: [25, 133, 6], theirs: [65, 94, 248]),
        DuelRecord(id: 0, opponent: "현우", won: true, why: "faint", at: tsF - 400_000, mine: [25, 133, 6], theirs: [149, 130, 6])])
    take("duel_records", fme) { v in v.screen = .duel(.hub(tab: 1, sel: 0)) }
    take("duel_queued", fme) { v in v.duelOn = true; v.duel = DuelView(id: 9, state: "queued", opponent: "", challenger: true, deadline: tsF + 41); v.screen = .duel(.queued) }
    take("squad_party", fme) { v in v.duelOn = false; v.screen = .squad(Squad(kind: .duelParty, picked: Array(v.state.duelParty!.prefix(4)), at: 6)) }
    take("squad_party_full", fme) { v in v.screen = .squad(Squad(kind: .duelParty, picked: [v.state.companion.uid!] + Array(uids.prefix(5)), at: v.squadKeys(Squad(kind: .duelParty, picked: [], at: 0)).count)) }
    take("squad_raid", fme) { v in v.screen = .squad(Squad(kind: .raid, picked: [uids[3], uids[0]], at: 3)) }
    let six = Array(fme.state.box.prefix(6)).map { m -> Mon in var m = m; m.level = 50; return m }
    let theirs = [DuelMon(dex: 94, female: false, shiny: false), DuelMon(dex: 448, female: true, shiny: false), DuelMon(dex: 130, female: false, shiny: true),
                  DuelMon(dex: 65, female: false, shiny: false), DuelMon(dex: 6, female: false, shiny: false), DuelMon(dex: 149, female: false, shiny: false)]
    take("squad_pick", fme) { v in v.duelOn = true; v.duel = DuelView(id: 9, state: "picking", opponent: "민수", challenger: false, deadline: tsF + 38, parties: DuelParties(mine: six, theirs: theirs, picked: nil, theyPicked: true))
        v.screen = .squad(Squad(kind: .duelPick(id: 9), picked: [4, 1], at: 2)) }
    take("squad_pick_sent", fme) { v in v.duelOn = true; v.duel = DuelView(id: 9, state: "picking", opponent: "민수", challenger: false, deadline: tsF + 21, parties: DuelParties(mine: six, theirs: theirs, picked: [4, 1, 0], theyPicked: false))
        v.screen = .squad(Squad(kind: .duelPick(id: 9), picked: [4, 1, 0], at: 6)) }
    // 3.8.1: the two guests above a tall companion, the bottom row full
    take("home_guests_tall", fme) { v in v.duelOn = false; v.state.companion = Mon(dex: 384, level: 70, female: false); v.state.caught = [Mon(dex: 16, level: 8, female: false), Mon(dex: 19, level: 9, female: false), Mon(dex: 41, level: 7, female: false)]
        v.state.egg = Egg(dex: 175, left: 300); v.screen = .home }
    // 3.8.2: what a move does — the battle's four, 기술 배우기, 기술 바꾸기 (its slots, what could go there)
    let mv382 = online({ var s = base(); s.companion = Mon(dex: 25, level: 30, female: false); s.companion.known = [85, 98, 86, 194]; return s }())
    let fb382 = Battle(wild: Mon(dex: 6, level: 30, female: false), party: [mv382.state.companion])
    take("battle_moves_text", mv382) { v in v.fight = fb382; v.screen = .moves(fb382, sel: 3) }
    take("learn_text", mv382) { v in v.state.learning = [v.state.id(-1)!, 87]; v.screen = .learn(sel: 1) }
    take("learn_text_keep", mv382) { v in v.state.learning = [v.state.id(-1)!, 87]; v.screen = .learn(sel: 4) }
    take("relearn_slots", mv382) { v in v.state.learning = nil; v.screen = .relearn(ref: -1, slot: 3, at: nil) }
    take("relearn_pick", mv382) { v in v.screen = .relearn(ref: -1, slot: 0, at: v.state.companion.relearnable.dropFirst(2).first) }
    take("grid_drag_to_walker", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (10002, CGPoint(x: 150 * K, y: 30 * K)) }
    take("grid_drag_to_box", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (4501, CGPoint(x: 100 * K, y: 120 * K)) }
    return n
}
#endif
