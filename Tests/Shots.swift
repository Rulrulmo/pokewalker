#if os(macOS)
import AppKit
// `PokeWalker --shots <dir>` (a dev build only: main.swift): a few screens drawn offscreen by the Mac's own view, as PNGs to look at — no window,
// never the save; the walkers are the self-test's (a fake server where one is needed).

@MainActor func shots(_ dir: String) -> Int {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var n = 0
    if let d = ProcessInfo.processInfo.environment["LCD_DECO"].flatMap(Int.init) { lcdDeco = d != 0 }   // 5.0: the LCD's pages plain (0), as before they were dressed (LCDDeco.swift)
    if let l = ProcessInfo.processInfo.environment["LCD_SCREEN"].flatMap(Int.init) { lcdStyle = min(max(l, 0), lcds.count - 1) }   // ... on another screen (1 원작, 2 백라이트)
    if ProcessInfo.processInfo.environment["LCD_FOCUS"] == "0" { lcdFocus = false }
    if ProcessInfo.processInfo.environment["FX_V2"] == "0" { fxV2 = false }                        // 5.0: the moves as before their second look (MoveFX2.swift)
    if ProcessInfo.processInfo.environment["HUD_AUDIT"] == "1" { for l in hudOverlaps() { print("hud " + l) } }   // 5.0: every picture against the fight's HP boxes
    func base() -> Walk { var s = Walk(), r = Seeded(s: 3); s.companion = Mon.wild(25, level: 30, &r); s.caught = [Mon.wild(16, level: 8, &r)]; s.watts = 1234; s.bp = 40; return s }
    func take(_ name: String, _ v: Walker, _ set: (Walker) -> Void) {
        let view = WalkerView(walker: v); set(v)
        if let only = ProcessInfo.processInfo.environment["SHOTS"], !only.split(separator: ",").contains(where: { name.hasPrefix($0) }) { return }   // SHOTS=raid,friends: just those (the rest still set up)
        cutTexts = []; drawnTexts = []
        v.refreshPane(Date(), force: true); view.fitWindow(); view.shown = v.compose(Date()); view.page.needsDisplay = true
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let cut = cutTexts, !cut.isEmpty { print("cut \(name): " + Array(Set(cut)).sorted().joined(separator: " | ")) }   // text cut short (…) or off the LCD
        if lcdDeco, v.pageGroup() != nil, let fb = view.shown, !lcdOverlaps(fb).isEmpty { print("overlap \(name): " + lcdOverlaps(fb).joined(separator: " | ")) }   // 5.0: a Pokémon over a word, the band or the panel
        cutTexts = nil
        let clash = textClashes(drawnTexts ?? [], width: view.bounds.width) + (view.shown.map { runClashes($0.runs) } ?? []).map { "LCD " + $0 }; drawnTexts = nil
        if !clash.isEmpty { print("clash \(name): " + Array(Set(clash)).sorted().joined(separator: " | ")) }   // 5.0: words over words, or off the window
        if (try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))) != nil { n += 1 }
    }
    let off = online(base()), (srv, _) = server(off)
    srv.down = true; off.cloud!.addSteps(120); off.cloud!.saveNow(); off.tick(Date()); off.tick(Date())   // no answer: offline, 120 steps waiting
    take("menu_offline", off) { v in v.screen = .menu(group: nil, sel: 0) }
    let on = online(base())
    take("menu_online", on) { v in v.screen = .menu(group: nil, sel: 0) }
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
    // 5.0 (docs/plans/18 §9.6, content5): the 도감's regions, 5.0's pictures (hg-engine: §9.1), the entry page's forms, a Fairy move
    Content.$testing.withValue(true) {
        let d5 = online({ var s = base(); s.owned = [1, 4, 6, 7, 25, 133, 479, 495, 501, 650, 666, 716]; s.seen = [16, 19, 494]; s.dex(); return s }())
        take("dex_regions", d5) { v in v.dexRegion = 0; v.screen = .dex(25, filter: 0, detail: false) }
        take("dex_regions_unova", d5) { v in v.dexRegion = 5; v.screen = .dex(495, filter: 0, detail: false) }
        take("dex_kalos_entry", d5) { v in v.dexRegion = 6; v.screen = .dex(650, filter: 0, detail: true) }
        take("dex_regions_kalos", d5) { v in v.dexRegion = 6; v.screen = .dex(650, filter: 0, detail: false) }
        take("menu_battle5", d5) { v in v.dexRegion = 0; v.screen = menuFor("대전") }                     // 4 with 메가 레이드
        take("shop_w5_key", d5) { v in v.state.watts = 5000; v.screen = .shop(bp: false, sel: v.wares(false).firstIndex { $0.kind == .item("로토무카탈로그") } ?? 0, qty: nil) }   // 9 tabs: 기타's 로토무카탈로그
        take("dex_form_rotom", d5) { v in v.dexRegion = 0; v.dexForm = (479, 1); v.screen = .dex(479, filter: 0, detail: true) }
        take("dex_form_mega", d5) { v in v.dexForm = (6, 2); v.screen = .dex(6, filter: 0, detail: true) }
        take("dex_form_vivillon", d5) { v in v.dexForm = (666, 4); v.screen = .dex(666, filter: 0, detail: true) }
        d5.dexForm = nil
        // 도감 업적 (§15): 전국, a region filled (✦), one half way, 해금; the regions' tabs with ✦
        let gw = online({ var s = base(); s.owned = Array(1...151) + Array(152...230) + [495, 650]; s.shinyOwned = [25, 6, 249]; s.dex()
                          s.dexRewards = ["전국:25", "전국:50", "전국:100", "전국:150", "전국:200", "관동:50", "관동:100", "성도:50"]; return s }())
        for k in [0, 1, 2, 7] { take("goals_\(k)", gw) { v in v.screen = .goals(k) } }
        take("dex_regions_done", gw) { v in v.dexRegion = 1; v.screen = .dex(25, filter: 0, detail: false) }
        var r5 = Seeded(s: 6), frog = Mon.wild(658, level: 40, &r5); frog.known = [57, 98, 400, 92]
        var vivi = Mon.wild(666, level: 20, &r5); vivi.form = 7; var wash = Mon.wild(479, level: 30, &r5); wash.form = 2
        let g6 = online({ var s = base(); s.companion = frog; s.caught = [Mon.wild(495, level: 10, &r5), wash]
                          s.box = [vivi] + [494, 497, 500, 503, 571, 609, 635, 643, 644, 646, 650, 653, 656, 700, 706, 716, 717, 718, 719, 720, 721].map { Mon.wild($0, level: 50, &r5) }; return s }())
        take("home_gen6", g6) { v in v.screen = .home }
        take("home_update_new", g6) { v in v.updateWaits = "5.0.1"; v.screen = .home }                // 5.0 (§9.8): an update waits: the NEW tag
        g6.updateWaits = nil
        take("box_gen6", g6) { v in v.screen = .box(0, act: nil, confirm: false) }
        take("mon_gen6_form", g6) { v in v.screen = .box(-3, act: nil, confirm: false, detail: true) }
        let xb = Battle(wild: Mon.wild(716, level: 50, &r5), companion: frog)
        take("battle_gen6", g6) { v in v.animOn = ("foe 0", 716, Date().addingTimeInterval(-60)); v.fight = xb; v.screen = .battle(xb, sel: 0) }
        var fr = Seeded(s: 5), pixie = Mon.wild(35, level: 30, &fr); pixie.known = [585, 1, 3, 45]
        let fairy = online({ var s = base(); s.companion = pixie; return s }()), fbt = Battle(wild: Mon(dex: 16, level: 30, female: false), companion: pixie)
        take("battle_moves_fairy", fairy) { v in v.fight = fbt; v.screen = .moves(fbt, sel: 0) }
        // 메가진화 (§9.6): the button after the moves (off / ticked), the LCD's, the light gathering and bursting, both sides Mega (the HP boxes' names, the LCD's marks)
        var zard = Mon.wild(6, level: 60, &fr); zard.known = [53, 19, 337, 89]; zard.item = "리자몽나이트X"
        var cross = Mon.wild(214, level: 60, &fr); cross.item = "헤라크로스나이트"
        let mg = online({ var s = base(); s.companion = zard; return s }()), mgb = Battle(wild: cross, companion: zard)
        let glowBeat = Beat.mega(.me, form: 1, text: "리자몽의 리자몽나이트X가 빛나기 시작했다!\n리자몽은 메가리자몽X로 메가진화했다!")
        take("battle_mega_toggle", mg) { v in v.megaOn = false; v.fight = mgb; v.screen = .moves(mgb, sel: 0) }
        take("battle_mega_toggle_on", mg) { v in v.megaOn = true; v.fight = mgb; v.screen = .moves(mgb, sel: 4) }
        take("battle_mega_tick_move", mg) { v in v.megaOn = true; v.fight = mgb; v.screen = .moves(mgb, sel: 0) }   // 5.1: ticked, on a move — the cards, the note, the HP box's tab
        take("battle_mega_tick_wait", mg) { v in                                                  // ... and while the turn's answer comes (the tick stays)
            v.megaOn = true; v.fight = mgb; v.screen = .moves(mgb, sel: 0)
            v.waiting = Walker.Waiting(act: .battle(cmd: .megaFight(slot: 0)), back: .moves(mgb, sel: 0), since: Date().addingTimeInterval(-0.5), quiet: true, then: { _, _ in nil })
        }
        mg.waiting = nil; mg.megaOn = false
        for (name, u) in [("battle_mega_fx1_stone", 0.3), ("battle_mega_fx2_streaks", 0.85), ("battle_mega_fx3_cocoon", 1.35), ("battle_mega_fx4_flash", 1.6),
                          ("battle_mega_fx5_symbol", 1.8), ("battle_mega_fx6_shards", 2.05), ("battle_mega_fx7_mega", 2.7)] {   // MegaFX's steps
            take(name, mg) { v in v.screen = .beats(mgb, [glowBeat], since: Date().addingTimeInterval(-u / v.battleSpeed), from: mgb) }
        }
        if ProcessInfo.processInfo.environment["MEGA_FRAMES"] != nil {                                   // MegaFX as frames (a GIF to look at): ours, a foe's, 원시그란돈
            var don = Mon.wild(383, level: 70, &fr); don.item = "주홍구슬"
            let pb = Battle(wild: don, companion: zard), cases: [(String, Battle, Beat)] = [
                ("me", mgb, glowBeat), ("foe", mgb, Beat.mega(.it, form: 1, text: "헤라크로스의 헤라크로스나이트가 빛나기 시작했다!\n헤라크로스는 메가헤라크로스로 메가진화했다!")),
                ("primal", pb, Beat.mega(.it, form: 1, text: "그란돈의 원시회귀!\n그란돈은 원시회귀하여 원래의 모습을 되찾았다!"))]
            for (tag, bt, beat) in cases {
                for k in 0..<44 { take(String(format: "megagif_%@_%02d", tag, k), mg) { v in v.screen = .beats(bt, [beat], since: Date().addingTimeInterval(-Double(k) / 15 / v.battleSpeed), from: bt) } }
            }
        }
        if let list = ProcessInfo.processInfo.environment["MOVE_FRAMES"] {                              // 5.0's quality pass: a move's flight and hit as frames (GIFs to compare): MOVE_FRAMES=53,56,…
            for id in list.split(separator: ",").compactMap({ Int($0) }) where moveTable[id] != nil {
                let beats: [Beat] = [.use(.me, move: id), .hit(.it, move: id, damage: 20, effect: 2, crit: false)], total = beats.map(\.length).reduce(0, +)
                for k in 0..<Int(total * 20) + 4 { take(String(format: "movegif_%03d_%03d", id, k), mg) { v in v.screen = .beats(mgb, beats, since: Date().addingTimeInterval(-Double(k) / 20 / v.battleSpeed), from: mgb) } }
            }
        }
        var both = mgb; both.mine[0].mega = 1; both.theirs[0].mega = 1; both.megaUsed = [true, true]
        take("battle_mega_after", mg) { v in v.fight = both; v.screen = .battle(both, sel: 0) }
        // A4 (§9.6): 로토무카탈로그's forms, 유전자쐐기's partners, a page with its form and hidden ability, the courses' 하나 page
        var heat = Mon.wild(479, level: 40, &fr); heat.form = 1; heat.ability = 2
        let fm = online({ var s = base(); s.companion = heat; s.bag = ["로토무카탈로그", "유전자쐐기"]
                          s.box = [Mon.wild(646, level: 60, &fr), Mon.wild(643, level: 60, &fr), Mon.wild(644, level: 55, &fr)]; return s }())
        take("form_rotom", fm) { v in v.screen = .formPick(ref: -1, item: "로토무카탈로그", sel: 2) }
        take("form_rotom_lcd", fm) { v in v.screen = .formPick(ref: -1, item: "로토무카탈로그", sel: 2) }
        take("form_kyurem", fm) { v in v.screen = .formPick(ref: 0, item: "유전자쐐기", sel: 1) }
        take("mon_form_hidden", fm) { v in v.screen = .box(-1, act: nil, confirm: false, detail: true) }
        let c5 = online({ var s = base(); s.earned = 10_000_000; s.owned = Array(1...160) + Array(494...540); s.dex(); return s }())
        take("course_unova", c5) { v in v.screen = .course(35) }
        // 메가 레이드 (§6.4 · §9.6): its lobby (the week's two), its tier, a boss near its 20 wins, the LCD's, a stone that came, a run's Mega boss
        let msrv = FakeCloud(); msrv.megaWeekNo = 0
        var mew = Mon.wild(150, level: 100, &fr); mew.known = [94, 105, 58, 247]
        let mrw = online({ var s = base(); s.companion = mew; s.raidPower = 25_000; return s }(), server: msrv), mkey = server(mrw).1
        msrv.raidRuns[mkey] = (0..<4).map { k in FakeCloud.RaidRun(tier: k % 3 + 1, boss: Mon(dex: MegaRaid.week(0)[0].dex, level: 20, female: false), day: "2026-10-1\(k)", at: msrv.clockNow - 3600 * (k + 1), bars: k == 2 ? 6 : 10, won: k != 2, ended: true, mega: true) }
        mrw.openFeature("메가 레이드"); drain(mrw); drain(mrw)
        take("mega_raid_lobby", mrw) { v in v.screen = .raid(.lobby(tab: 0)) }
        take("mega_raid_lobby_lcd", mrw) { v in v.screen = .raid(.lobby(tab: 1)) }
        take("mega_raid_tier", mrw) { v in v.raidMegaBoss = 0; v.screen = .raid(.tier(sel: 2)) }
        take("mega_raid_tier5", mrw) { v in v.raidMegaBoss = 0; v.screen = .raid(.tier(sel: RaidRules.tiers.count - 1)) }   // its first ★5 win's 금색병뚜껑 (the row's pill, the LCD's line)
        take("card_mega", mrw) { v in v.state.bag += Array(MegaRaid.stones.sorted().prefix(13)); v.state.titles = ["타워 타이쿤", MegaRaid.master]; v.state.deco = "gold"; v.screen = .card(0) }   // 메가스톤 13/48 by the 칭호
        take("card_title_pick", mrw) { v in v.titlePick = true; v.state.cardTitle = "타워 타이쿤"; v.screen = .card(0) }   // the 칭호 to show: 가장 최근, then each
        mrw.titlePick = false; mrw.state.cardTitle = nil
        msrv.megaWins[mkey] = [MegaRaid.week(0)[0].stone: 19, MegaRaid.week(0)[1].stone: 7]
        mrw.cloud!.megaRaidDue = true; drain(mrw); drain(mrw)
        take("mega_raid_near", mrw) { v in v.screen = .raid(.lobby(tab: 0)) }
        for (name, first) in [("mega_stone_twenty", "같은 보스 \(MegaRaid.bossWins)승!"), ("mega_stone_drop", "행운의 메가스톤!")] {
            let stone = MegaRaid.week(0)[name.hasSuffix("drop") ? 1 : 0].stone, got = [first, josa(stone, "을", "를"), "얻었다!", "우편함에서 받아요"]
            take(name, mrw) { v in v.sayStone = (got, stone); v.screen = .say(got, next: .raid(.lobby(tab: 0)), since: .distantFuture) }
        }
        if let b = msrv.megaRaidStart(mkey, 3, 0).boss {
            var mb = Battle(wild: b.boss, companion: mew); mb.theirs += Array(repeating: Fighter(b.boss), count: RaidRules.bars - 1); mb.raidTier = 3
            for i in mb.theirs.indices { mb.theirs[i].mega = b.mega }; mb.megaUsed = [false, true]
            take("mega_raid_fight", mrw) { v in v.raidOn = true; v.fight = mb; v.screen = .battle(mb, sel: 0) }
            mrw.raidOn = false
        }
        mrw.raidMega = false
    }
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
    take("menu_team", tme) { v in v.screen = menuFor("친구") }
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
    take("menu_team_trades", tme) { v in v.screen = menuFor("친구") }
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
    // 4.0 (docs/plans/16 §8): 레이드 — runs
    let rsrv = FakeCloud()
    let rme = online({ var s = base(); s.raidPower = Engine.raidPowerCost * 234 / 100; s.caught = [Mon(dex: 149, level: 61, female: false), Mon(dex: 6, level: 55, female: false)]; return s }(), server: rsrv)
    let ts = Int(Date().timeIntervalSince1970), today = Walk.key(Date()), lugia = Mon(dex: 249, level: RaidRules.tiers[2].level, female: false)
    var shinyLugia = lugia; shinyLugia.shiny = true
    func run(_ tier: Int, _ bars: Int, _ caught: Bool, shiny: Bool = false, ago: Int, day: String = today) -> FakeCloud.RaidRun {
        var b = lugia; b.level = RaidRules.tier(tier)?.level ?? 50; if shiny { b.shiny = true }
        return .init(tier: tier, boss: b, day: day, at: ts - ago, bars: bars, balls: 0, won: bars == RaidRules.bars, caught: caught, ended: true)
    }
    for (k, m) in mates.prefix(6).enumerated() {
        rsrv.add(m.0, { var w = Walk(); w.companion = Mon(dex: m.1, level: m.2, female: false); return w }()); rsrv.befriend(rme.myName, m.0)
        let weeks: [[FakeCloud.RaidRun]] = [[run(5, 10, true, ago: 3600), run(4, 10, true, ago: 9000), run(4, 10, false, ago: 20000), run(3, 6, false, ago: 40000)],
                                            [run(3, 10, true, shiny: true, ago: 5000), run(3, 10, false, ago: 7000)], [run(4, 10, true, ago: 600), run(5, 4, false, ago: 800)],
                                            [run(2, 10, false, ago: 9000)], [], [run(1, 3, false, ago: 100)]]
        rsrv.raidRuns[m.0.lowercased()] = weeks[k]
    }
    rsrv.raidRuns[rme.myName.lowercased()] = [run(3, 10, true, shiny: true, ago: 90000, day: "2026-10-11"), run(4, 7, false, ago: 86000, day: "2026-10-11"), run(3, 10, false, ago: 3000), run(3, 10, true, ago: 1200)]
    take("raid_loading", rme) { v in v.screen = .raid(.lobby(tab: 0)) }
    rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("menu_raid", rme) { v in v.screen = menuFor("레이드") }
    take("raid_lobby", rme) { v in v.screen = .raid(.lobby(tab: 0)) }
    take("raid_runs", rme) { v in v.screen = .raid(.lobby(tab: 1)) }
    take("raid_no_power", rme) { v in v.state.raidPower = Engine.raidPowerCost * 64 / 100; v.screen = .raid(.lobby(tab: 0)) }
    take("raid_full_power", rme) { v in v.state.raidPower = Engine.raidPowerMax; v.screen = .raid(.lobby(tab: 0)) }
    take("raid_tier", rme) { v in v.state.raidPower = Engine.raidPowerCost * 234 / 100; v.screen = .raid(.tier(sel: 2)) }
    take("raid_tier_top", rme) { v in v.screen = .raid(.tier(sel: RaidRules.tiers.count - 1)) }
    take("raid_squad", rme) { v in v.raidTier = 3; v.screen = .squad(Squad(kind: .raid, picked: [v.state.caught[0].uid ?? 0], at: 0)) }
    var rr = Seeded(s: 5); let rb = { () -> Battle in var b = Battle(wild: lugia, party: [rme.state.companion] + rme.state.caught); b.theirs += Array(repeating: Fighter(lugia), count: 9); return b }()   // 4.0: ten bars
    let rbeats = { () -> (Battle, [Beat]) in var b = rb; let bs = b.begin(weather: nil, &rr); return (b, bs) }()
    take("raid_appear", rme) { v in v.raidOn = true; v.screen = .beats(rbeats.0, rbeats.1, since: Date().addingTimeInterval(-1.2), from: rb) }
    take("raid_menu", rme) { v in v.raidOn = true; var b = rbeats.0; for k in 0..<3 { b.theirs[k].hp = 0 }; b.it = 3; b.theirs[3].hp = b.theirs[3].maxHP / 3; b.turnNo = 6; v.fight = b; v.screen = .battle(b, sel: 3) }
    take("raid_standup", rme) { v in v.raidOn = true; var b = rbeats.0; for k in 0..<3 { b.theirs[k].hp = 0 }; b.it = 2; v.screen = .beats(b, [.sendOut(.it, 3)], since: Date().addingTimeInterval(-0.2), from: b) }
    do {                                                                                            // 4.0 (16 §8-2): a shiny boss — ✦ 반짝, then its line with the burst and the gold frame
        let boss = { () -> Mon in var m = Mon(dex: 487, level: RaidRules.tiers.last!.level, female: false); m.shiny = true; return m }()
        var sb = Battle(wild: boss, party: [rme.state.companion] + rme.state.caught); sb.theirs += Array(repeating: Fighter(boss), count: 9)
        var r2 = Seeded(s: 7); let from = sb; let bs = Walker.raidShown(sb.begin(weather: nil, &r2), from: from)
        take("raid_shiny_spark", rme) { v in v.raidOn = true; v.screen = .beats(sb, bs, since: Date().addingTimeInterval(-0.75 / v.battleSpeed), from: from) }
        take("raid_shiny_reveal", rme) { v in v.raidOn = true; v.screen = .beats(sb, bs, since: Date().addingTimeInterval(-1.5 / v.battleSpeed), from: from) }
        take("raid_shiny_menu", rme) { v in v.raidOn = true; var b = sb; b.theirs[0].hp = b.theirs[0].maxHP * 2 / 3; v.fight = b; v.screen = .battle(b, sel: 0) }
        take("raid_shiny_hud", rme) { v in v.raidOn = true; var b = sb; for k in 0..<4 { b.theirs[k].hp = 0 }; b.it = 4; b.theirs[4].hp = b.theirs[4].maxHP / 2; v.fight = b; v.screen = .battle(b, sel: 0) }   // the app's own: the HP boxes
    }
    take("raid_won", rme) { v in v.raidOn = false; v.screen = .say(["10줄을 모두 깼다!", "2BP · 볼 5개!", "우편함에 이번 주 보상이 왔다"], next: .raid(.balls), since: Date()) }
    take("raid_balls", rme) { v in v.raidStage = RaidPending(boss: shinyLugia, tier: 3, bars: 10, won: true, balls: 5); v.screen = .raid(.balls) }
    take("raid_balls_lost", rme) { v in v.raidStage = RaidPending(boss: lugia, tier: 3, bars: 6, won: false, balls: 2); v.screen = .raid(.balls) }
    take("raid_balls_top", rme) { v in var m = lugia; m.level = RaidRules.tiers.last!.level; v.raidStage = RaidPending(boss: m, tier: RaidRules.tiers.last!.tier, bars: 3, won: false, balls: 3); v.screen = .raid(.balls) }
    take("raid_throw", rme) { v in v.usedItem = "몬스터볼"; let b = Battle(wild: lugia, companion: v.state.companion); v.raidThen = .raid(.balls); v.screen = .beats(b, [.thrown(shakes: 2), .broke], since: Date().addingTimeInterval(-2.4), from: b) }
    take("raid_resume", rme) { v in v.raidThen = nil; v.raidStage = nil; v.screen = .say(["잡을 기회가", "남았어요!"], next: .raid(.balls), since: Date()) }
    rsrv.raidRuns[rme.myName.lowercased()]!.append(.init(tier: 3, boss: shinyLugia, day: today, at: ts - 60, bars: 8, balls: 2, won: false, caught: false, ended: true))
    rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("menu_raid_waiting", rme) { v in v.screen = menuFor("레이드") }
    take("menu_battle_raid_waiting", rme) { v in v.screen = .menu(group: nil, sel: 2) }
    rsrv.raidRuns[rme.myName.lowercased()]!.removeLast(); rsrv.raidRuns[rme.myName.lowercased()]!.append(run(3, 2, false, ago: 30))
    rme.cloud!.raidDue = true; drain(rme); drain(rme)
    take("raid_done_today", rme) { v in v.raidStage = nil; v.screen = .raid(.lobby(tab: 1)) }
    rme.cloud!.teamDue = true; drain(rme); drain(rme)
    take("friends_raid", rme) { v in v.screen = .team(sel: 0, tab: TeamTab.raid, card: false) }
    take("friends_card_raid", rme) { v in v.screen = .team(sel: 0, tab: TeamTab.raid, card: true) }
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
    take("menu_friends", fme) { v in v.screen = menuFor("친구") }
    take("menu_market", fme) { v in v.screen = menuFor("교환") }
    take("friends_list", fme) { v in v.screen = .team(sel: 0, tab: 0, card: false) }
    take("friends_requests", fme) { v in v.screen = .team(sel: 0, tab: TeamTab.requests, card: false) }
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
    for (name, pick) in [("shop_bp_shell", { (k: Walk.Ware.Kind) -> Bool in if case .shell = k { true } else { false } }), ("shop_bp_legend", { if case .legend = $0 { true } else { false } })] {
        take(name, shop36) { v in v.screen = .shop(bp: true, sel: v.wares(true).firstIndex { pick($0.kind) } ?? 0, qty: nil) }   // (a device colour, a legend: the focus page's pictures)
    }
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
    take("battle_held_hud", h37) { v in v.fight = hb; v.screen = .battle(hb, sel: 0) }
    take("battle_held_party", h37) { v in v.fight = hb; v.screen = .party(hb, sel: 1) }
    // 3.8 (docs/plans/14): 받기 · a post's 한마디 · the 교환 tile's dot, 맡겨 키우기, the 대전 menu, picks in order, 12 tiles
    fsrv.listings[0].l.note = "이브이랑 바꿔요!"; fsrv.listings[2].l.note = "레벨 높은 걸로 부탁해요"
    var r38 = Seeded(s: 91)
    // 3.9 (15 §6 A · D): the 우편함 — a trade's, one back, a visit's, rewards, a notice; one open; the picks
    fsrv.giveMail(meK, "notice", from: "운영자", title: "3.9 업데이트 안내", body: "우편함이 생겼어요. 교환으로 받은 포켓몬, 돌아온 포켓몬, 배틀 타워 연승 보상이 여기로 와요.\n선물은 받을 때까지 사라지지 않아요.", [])
    fsrv.giveMail(meK, "visit", from: "현우", title: "맡겼던 포켓몬이 돌아왔어요", body: "현우가 2,160걸음 키워 줬어요", [.mon(mon: Mon.wild(4, level: 22, &r38), steps: 2160)])
    fsrv.giveMail(meK, "returned", from: "서연", title: "돌아온 포켓몬", body: "이브이가 돌아왔어요 · 다른 제안이 선택됐어요", [.mon(mon: fme.state.box[9])])
    fsrv.giveMail(meK, "trade", from: "민수", title: "교환으로 받은 포켓몬", body: "민수와 교환했어요 · 이브이 ↔ 고우스트", [.mon(mon: Mon.wild(94, level: 31, &r38))])
    for r in Tower.rewards.prefix(3) { fsrv.giveMail(meK, "tower", from: "배틀 타워", title: "\(r.wins)연승 달성 보상", body: "배틀 타워에서 처음으로 \(r.wins)연승에 닿았어요.", r.gifts) }
    fsrv.giveMail(meK, "tower", from: "배틀 타워", title: "100연승 달성 보상", body: "배틀 타워에서 처음으로 100연승에 닿았어요.", Tower.rewards.last!.gifts)
    fsrv.giveMail(meK, "dex", from: "도감", title: "50종 · 민트 고르기", body: "포켓몬을 50종 잡았어요.", [.pickItem(items: Walk.mints)])   // 5.0: a long pick (21 mints)
    if let i = fsrv.postBox[meK]?.indices { for k in i { fsrv.postBox[meK]![k].at = tsF - [86_400 * 3, 90_000, 4000, 400, 7200, 3600, 1800, 600][k % 8] } }
    fme.cloud!.mailDue = true; drain(fme); drain(fme)
    let mails38 = fme.mails, pick14 = mails38.first { $0.title == "14연승 달성 보상" }?.id ?? 0, pick100 = mails38.first { $0.title == "100연승 달성 보상" }?.id ?? 0
    take("mail_list", fme) { v in v.screen = .mail(.list(sel: 0)) }
    take("menu_mail_dot", fme) { v in v.screen = .menu(group: nil, sel: 7) }
    take("mail_open_trade", fme) { v in v.screen = .mail(.open(id: mails38.first { $0.kind == "trade" }?.id ?? 0)) }
    take("mail_open_tower", fme) { v in v.screen = .mail(.open(id: pick100)) }
    take("mail_open_notice", fme) { v in v.screen = .mail(.open(id: mails38.first { $0.kind == "notice" }?.id ?? 0)) }
    take("mail_pick_item", fme) { v in v.screen = .mail(.pick(id: pick14, at: 2, ask: nil)) }
    take("mail_pick_item_ask", fme) { v in v.screen = .mail(.pick(id: pick14, at: 2, ask: true)) }
    let mintPick = mails38.first { $0.title.hasSuffix("· 민트 고르기") }?.id ?? 0
    for at in [0, 8, 20] { take("mail_pick_mints_\(at)", fme) { v in v.screen = .mail(.pick(id: mintPick, at: at, ask: nil)) } }   // its pages: the pick in view, clear of the button
    take("mail_pick_legend", fme) { v in v.screen = .mail(.pick(id: pick100, at: 3, ask: nil)) }
    take("mail_pick_legend_p2", fme) { v in v.screen = .mail(.pick(id: pick100, at: 27, ask: false)) }
    // 5.0.1 (10-15, a Windows 우편함 quit on a title past the LCD's band): such a title a size smaller (메가메타그로스 ★5 첫 승리!, 91 dots), then … (an
    // operator's long one: its "cut" line here is meant)
    let metagross = MegaRaid.bosses.first { MegaRaid.name($0) == "메가메타그로스" } ?? MegaRaid.bosses[0]
    fsrv.giveMail(meK, "raid", from: "메가 레이드", title: MegaRaid.firstTitle(metagross, tier: 5), body: MegaRaid.firstBody(metagross, tier: 5), [.items(name: "금색병뚜껑", count: 1)])
    fsrv.giveMail(meK, "admin", from: "운영자", title: "운영자 선물: 전설 포켓몬 선택권과 금색병뚜껑 묶음", body: "5.0 출시를 기념해서 보내 드려요.", [.items(name: "금색병뚜껑", count: 2)])
    fme.cloud!.mailDue = true; drain(fme); drain(fme)
    for (k, m) in fme.mails.filter({ $0.kind == "raid" || $0.kind == "admin" }).enumerated() {
        take("mail_long_title_\(k)", fme) { v in v.screen = .mail(.list(sel: v.mails.firstIndex { $0.id == m.id } ?? 0)) }
        take("mail_long_title_open_\(k)", fme) { v in v.screen = .mail(.open(id: m.id)) }
    }
    take("market_board_39", fme) { v in v.screen = .market(.board(tab: 1, sel: 0)) }
    take("menu_market_dot", fme) { v in v.screen = menuFor("교환") }
    take("market_post_note", fme) { v in v.screen = .market(.post(id: 1, sel: nil)) }
    take("market_post_mine_note", fme) { v in v.screen = .market(.post(id: 3, sel: nil)) }
    let ends = tsF + 3 * 3600 + 1200
    fsrv.visitList = [FakeCloud.FakeVisit(id: 1, owner: meK, ownerName: fme.myName, host: "민수", hostName: "민수", mon: fme.state.box[11], steps: 3120, ends: ends),
                      FakeCloud.FakeVisit(id: 2, owner: "지은", ownerName: "지은", host: meK, hostName: fme.myName, mon: Mon.wild(282, level: 34, shiny: true, &r38), steps: 4380, ends: ends + 3000),
                      FakeCloud.FakeVisit(id: 3, owner: "현우", ownerName: "현우", host: meK, hostName: fme.myName, mon: Mon.wild(149, level: 55, &r38), steps: 870, ends: ends - 9000)]
    fme.cloud!.teamDue = true; drain(fme); drain(fme)
    take("friends_visits", fme) { v in v.screen = .team(sel: 0, tab: TeamTab.visits, card: false) }
    take("visit_pick", fme) { v in v.screen = .visitPick(ItemOn(item: "민수", pick: v.visitRefs[safe: 2], at: 2)) }
    take("home_guests", fme) { v in v.screen = .home }
    take("friends_card_visit", fme) { v in let i = v.teamRows(0).firstIndex { !v.isMe($0.card) && Walker.walkingNow($0.card) } ?? 0; v.screen = .team(sel: i, tab: 0, card: true) }
    take("menu_battle", fme) { v in v.screen = menuFor("대전") }
    take("menu_record", fme) { v in v.screen = menuFor("트레이너 카드") }                       // 3.9: a group's page
    take("menu_shop", fme) { v in v.screen = menuFor("상점") }
    take("menu_dot_top", fme) { v in v.screen = .menu(group: nil, sel: 5) }                     // the 친구 group's tile gathers 교환's dot
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
    take("squad_tower", fme) { v in v.duelOn = false; v.screen = .squad(Squad(kind: .tower, picked: v.state.party().compactMap { $0.mon.uid }, at: 4)) }
    take("squad_raid", fme) { v in v.screen = .squad(Squad(kind: .raid, picked: [uids[3], uids[0]], at: 3)) }
    // 4.1: the tower's one legend — 뮤츠 in, the other legends shadows; the cursor on 루기아 (the LCD says why)
    let lme = online({ var s = base(); var r = Seeded(s: 9); s.box = [150, 249, 382, 445, 6, 130, 384, 248].enumerated().map { var m = Mon.wild($1, level: 50, &r); m.uid = 900 + $0; return m }; return s }())
    let lUids = lme.state.box.compactMap(\.uid)
    take("squad_tower_legend", lme) { v in v.duelOn = false
        let keys = v.squadKeys(Squad(kind: .tower, picked: [], at: 0)), at = keys.firstIndex { v.squadMon(Squad(kind: .tower, picked: [], at: 0), $0)?.dex == 249 } ?? 0
        v.screen = .squad(Squad(kind: .tower, picked: [lUids[0], lUids[3]], at: at)) }
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
    // 3.8.5: the bag's tabs; 도구 주기 from a Pokémon's page
    let b385 = online({ var s = base(); s.items = ["상처약"]; s.bag = ["이상한사탕", "타우린", "고집민트", "불꽃의돌", "천둥의돌", "먹다남은음식", "구애머리띠", "오랭열매", "자뭉열매", "은색병뚜껑", "몬스터볼", "금구슬", "좋은상처약", "플러스파워"]
        s.box = [Mon(dex: 25, level: 30, female: false)]; return s }())
    take("items_tabs", b385) { v in v.screen = .items(v.state.inventory.firstIndex(of: "이상한사탕") ?? 0) }
    take("items_tabs_berries", b385) { v in v.screen = .items(v.state.inventory.firstIndex(of: "오랭열매") ?? 0) }
    take("give_page", b385) { v in v.screen = .hold(ref: 0, sel: 1) }
    take("give_page_dim", b385) { v in v.screen = .hold(ref: 0, sel: 0) }
    take("mon_give_link", b385) { v in v.screen = .box(0, act: nil, confirm: false, detail: true) }
    // a full page of the 교환 게시판 (six rows, a second page) and of 친구 신청 (five, more after): the pager and the button clear the last row
    let more = ["하은", "현우", "유나", "서연"].compactMap { n in fsrv.walk(n)?.box.first.map { (n, $0) } }
    fsrv.listings += more.enumerated().map { k, x in lst(20 + k, x.0, x.1, k % 2 == 0 ? [25] : [], 3000 + 500 * k) }
    fme.cloud!.marketDue = true; drain(fme); drain(fme)
    take("market_all_full", fme) { v in v.duelOn = false; v.screen = .market(.board(tab: 0, sel: 0)) }
    take("market_all_full_last", fme) { v in v.screen = .market(.board(tab: 0, sel: 5)) }
    for k in 1...5 { fsrv.add("신청자\(k)", Walk()) }
    fsrv.friendAsks[meK] = Set(["현우", "유나"] + (1...5).map { "신청자\($0)" })
    fme.cloud!.teamDue = true; drain(fme); drain(fme)
    take("friends_requests_full", fme) { v in v.screen = .team(sel: 0, tab: TeamTab.requests, card: false) }
    // the README's picture (tools/hero/): the download page's two — home and a wild battle — set up as WinRender's home and battle_menu
    func heroBase() -> Walk {
        var s = Walk(), r = Seeded(s: 3)
        s.companion = Mon.wild(25, level: 30, &r); s.caught = [Mon.wild(16, level: 8, &r), Mon.wild(41, level: 9, &r)]
        s.box = [Mon.wild(133, level: 20, &r), Mon.wild(147, level: 25, shiny: true, &r), Mon.wild(4, level: 12, perfect: 3, &r), Mon.wild(1, level: 5, &r), Mon.wild(95, level: 31, &r)]
        s.items = ["상처약", "기력의조각"]; s.bag = ["이상한사탕", "금구슬", "타우린", "하이퍼볼", "천둥의돌", "라즈열매", "은색병뚜껑", "좋은상처약"]
        s.watts = 1234; s.earned = 2500; s.bp = 40; s.weather = .sunny; s.egg = Egg(dex: 175, left: 300); s.towerBest = 5
        s.total = 5250; s.today = 1234; s.history = [3000, 0, 4521, 812, 2210]; s.seen = [19, 150, 243]; s.dex()
        return s
    }
    let heroW = Walker(state: heroBase()); heroW.persist = false; heroW.lastStep = .distantPast
    take("hero_home", heroW) { v in v.screen = .home }
    take("hero_battle", heroW) { v in
        var r = Seeded(s: 5), b = Battle(wild: Mon.wild(6, level: 30, &r), companion: v.state.companion, chain: 0); _ = b.begin(weather: nil, &r)
        v.animOn = ("foe 0", 6, Date().addingTimeInterval(-60)); v.fight = b; v.screen = .battle(b, sel: 1)
    }
    // 3.9 (15 §6 C · E): 장식 · 칭호 (my card, the friends' list, a friend's card), the tower's strip, the tycoon (its lobby, intro, fight in 은 and 금, the win)
    let dsrv = FakeCloud(), dme = online({ var s = base(); s.deco = "gold"; s.titles = ["타워 타이쿤"]; s.towerBest = 26; s.towerStreak = Tower.tycoonFights.min()! - 1; return s }(), server: dsrv)
    for (k, f) in [("민수", "gold", "타워 타이쿤"), ("지은", "silver", ""), ("도윤", "", "")].enumerated() {
        var w = Walk(), r = Seeded(s: UInt64(k + 70)); w.companion = Mon.wild([6, 282, 448][k], level: 50, &r); w.deco = f.1.isEmpty ? nil : f.1; w.titles = f.2.isEmpty ? nil : [f.2]
        w.towerBest = [100, 50, 12][k]; w.today = [8_200, 5_100, 900][k]
        dsrv.add(f.0, w); dsrv.lastAct[f.0] = Date(); dsrv.befriend(dme.myName, f.0)
    }
    dme.cloud!.teamDue = true; drain(dme); drain(dme)
    take("card_deco_gold", dme) { v in v.screen = .card(0) }
    take("friends_deco", dme) { v in v.screen = .team(sel: 0, tab: 0, card: false) }
    take("friends_card_title", dme) { v in let i = v.teamRows(0).firstIndex { $0.card.name == "민수" } ?? 0; v.screen = .team(sel: i, tab: 0, card: true) }
    take("tower_tycoon_lobby", dme) { v in v.state.towerRewards = [7, 14, 21]; v.towerRun = true; v.screen = .tower(pick: nil) }
    let sme = online({ var s = base(); s.deco = "silver"; s.towerBest = 8; return s }())
    take("card_deco_silver", sme) { v in v.screen = .card(0) }
    take("card_deco_long", Walker(state: { var s = base(); s.deco = "gold"; s.titles = ["타워 타이쿤"]; return s }())) { v in v.persist = false; v.screen = .card(0) }   // (no ID yet: 트레이너 카드, its medal and 칭호 — Windows' render)
    take("tower_strip", sme) { v in v.state.towerRewards = [7]; v.towerRun = false; v.screen = .tower(pick: nil) }
    // 4.1: after 100, every 50 (the strip's 9th cell: the next of them); the one-time reset (streak, best, rewards all 0 — my card, a friend's, the lobby)
    take("tower_strip_endless", sme) { v in v.state.towerBest = 163; v.state.towerStreak = 163; v.state.towerRewards = Tower.rewards.map(\.wins) + [150]; v.towerRun = true; v.screen = .tower(pick: nil) }
    let zsrv = FakeCloud(), zme = online({ var s = base(); s.deco = "gold"; s.titles = ["타워 타이쿤"]; s.towerBest = 0; s.towerStreak = 0; s.towerRewards = []; return s }(), server: zsrv)
    for (k, n) in ["민수", "지은"].enumerated() {
        var w = Walk(), r = Seeded(s: UInt64(k + 80)); w.companion = Mon.wild([6, 282][k], level: 50, &r); w.deco = k == 0 ? "gold" : nil; w.titles = k == 0 ? ["타워 타이쿤"] : nil
        w.towerBest = 0; w.today = [8_200, 5_100][k]; zsrv.add(n, w); zsrv.lastAct[n] = Date(); zsrv.befriend(zme.myName, n)
    }
    zme.cloud!.teamDue = true; drain(zme); drain(zme)
    take("reset_card", zme) { v in v.screen = .card(0) }
    take("reset_friends_tower", zme) { v in v.screen = .team(sel: 0, tab: TeamTab.tower, card: false) }
    take("reset_friend_card", zme) { v in let i = v.teamRows(0).firstIndex { $0.card.name == "민수" } ?? 0; v.screen = .team(sel: i, tab: 0, card: true) }
    take("reset_tower_lobby", zme) { v in v.towerRun = false; v.screen = .tower(pick: nil) }
    let tyb = Battle(party: dme.state.party().map(\.mon), trainer: Tower.tycoon, foes: Tower.tycoonTeams[Tower.tycoonFights.min()!]!.map { Mon(dex: $0.dex, level: 50, female: $0.dex == 350) })   // its team as it is
    take("tycoon_intro", dme) { v in v.towerRun = true; v.fight = tyb; v.screen = .beats(tyb, [.sendOut(.it, 0)], since: Date().addingTimeInterval(-0.45), from: tyb) }
    take("tycoon_fight", dme) { v in v.fight = tyb; v.screen = .battle(tyb, sel: 0) }
    take("tycoon_won", dme) { v in v.screen = .say(["타워 타이쿤을 이겼다!", "\(Tower.tycoonFights.min()!)연승! +20 BP", "우편함에 보상이 왔다"], next: .tower(pick: nil), since: Date()) }
    take("tycoon_fight_gold", dme) { v in v.state.towerStreak = Tower.tycoonFights.max()! - 1; v.fight = tyb; v.screen = .battle(tyb, sel: 0) }
    // 4.1: the tycoon's legend (its team as the Model has it, the legend out) and a trainer's from the 101st fight on (its last one a legend, as towerFoes makes it)
    for (name, wins) in [("tycoon_legend", Tower.tycoonFights.min()! - 1), ("tycoon_legend_gold", Tower.tycoonFights.max()! - 1), ("tower_legend_foe", Tower.legendFrom - 1)] {
        var w = dme.state; w.towerStreak = wins; var r = Seeded(s: 41); let f = w.towerFoes(&r)
        var b = Battle(party: dme.state.party().map(\.mon), trainer: f.trainer, foes: f.foes)
        if let i = f.foes.firstIndex(where: { Tower.isLegend($0.dex) }) { for k in 0..<i { b.theirs[k].hp = 0 }; b.it = i }
        take(name, dme) { v in v.state.towerStreak = wins; v.towerRun = true; v.fight = b; v.screen = .battle(b, sel: 0) }
    }
    take("grid_drag_to_walker", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (10002, CGPoint(x: 150 * K, y: 30 * K)) }
    take("grid_drag_to_box", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (4501, CGPoint(x: 100 * K, y: 120 * K)) }
    // 5.0's quality pass (회사: "글자 겹침같은 문제 없게 ui 제대로 확인"): the extremes — the longest names (Pokémon, moves, abilities, forms,
    // 칭호), 12-character IDs, the biggest numbers, every mark at once (이로치 · ♀ · an item · a hidden ability · a Mega), full and empty lists
    Content.$testing.withValue(true) {
        var r = Seeded(s: 404)
        let longMoves = moveTable.values.filter { $0.id <= 621 && $0.power > 0 }.sorted { ($0.name.count, $0.id) > ($1.name.count, $1.id) }.prefix(4).map(\.id)
        let longMons = (1...721).sorted { (monNames[$0].count, $0) > (monNames[$1].count, $1) }
        var big = Mon.wild(6, level: 100, &r); big.form = Forms.mega(6, holding: "리자몽나이트Y")?.n; big.shiny = true; big.female = true; big.item = "리자몽나이트Y"; big.ability = 2; big.known = Array(longMoves)
        let held = (Walk.heldBP.map(\.item) + Walk.heldWGen6.map(\.item)).sorted { ($0.count, $0) > ($1.count, $1) }
        let sx = online({ var s = Walk(); s.companion = big; s.watts = 9_999; s.bp = 9_999; s.towerBest = 9_999; s.towerStreak = 999; s.earned = 99_999_999; s.total = 99_999_999; s.today = 99_999
                          s.titles = ["타워 타이쿤", MegaRaid.master, DexGoals.doctor]; s.deco = "gold"; s.owned = Array(1...721); s.shinyOwned = Array(1...721); s.dex()
                          s.caught = longMons.prefix(3).map { var m = Mon.wild($0, level: 100, &r); m.shiny = true; m.item = held.first; return m }
                          s.box = longMons.prefix(40).map { Mon.wild($0, level: 100, &r) }; s.bag = Array(held.prefix(30)) + Walk.mints; s.items = Array(held.prefix(3)); return s }())
        sx.cloud?.seat.trainerID = "pokewalker12"
        take("stress_card", sx) { v in v.screen = .card(0) }
        take("stress_card_titles", sx) { v in v.titlePick = true; v.screen = .card(0) }
        take("stress_box", sx) { v in v.screen = .box(-1, act: nil, confirm: false, detail: true) }
        take("stress_box_walker", sx) { v in v.screen = .box(-2, act: nil, confirm: false, detail: true) }
        take("stress_box_grid", sx) { v in v.screen = .box(-1, act: nil, confirm: false) }
        take("stress_dex", sx) { v in v.screen = .dex(longMons[0], filter: 0, detail: true) }
        take("stress_dex_mega", sx) { v in v.dexForm = (6, Forms.mega(6, holding: "리자몽나이트Y")?.n ?? 1); v.screen = .dex(6, filter: 0, detail: true) }
        take("stress_shop", sx) { v in v.screen = .shop(bp: false, sel: 0, qty: nil) }
        take("stress_shop_qty", sx) { v in v.screen = .shop(bp: false, sel: 0, qty: 99) }
        // the ease (5.0): 상자 찾기's words, the shop's amount at its most, who holds a held item already, a mint's before / after, a page's ‹
        take("ux_box_query", sx) { v in v.boxQuery = "불꽃 이로치"; v.screen = .box(v.boxShown.first ?? -1, act: nil, confirm: false) }
        sx.boxQuery = ""
        take("ux_shop_most", sx) { v in v.state.watts = 300; v.screen = .shop(bp: false, sel: 2, qty: 1) }
        take("ux_shop_most_max", sx) { v in v.state.watts = 300; v.screen = .shop(bp: false, sel: 2, qty: 1); v.shopStep(nil) }
        take("ux_shop_held", sx) { v in v.state.companion.item = Walk.heldWGen6.first?.item; v.screen = .shop(bp: false, sel: v.wares(false).firstIndex { v.state.wareName($0) == Walk.heldWGen6.first?.item } ?? 0, qty: nil) }
        take("ux_mint", sx) { v in v.screen = .itemOn(ItemOn(item: "대담민트", pick: -1, at: 0)) }
        take("stress_bp", sx) { v in v.screen = .shop(bp: true, sel: v.wares(true).count - 1, qty: nil) }
        take("stress_items", sx) { v in v.screen = .items(0) }
        take("stress_hold", sx) { v in v.screen = .hold(ref: -1, sel: 3) }
        take("stress_tower", sx) { v in v.towerRun = true; v.screen = .tower(pick: nil) }
        take("stress_goals", sx) { v in v.screen = .goals(0) }
        take("stress_goals_region", sx) { v in v.screen = .goals(5) }
        take("stress_menu", sx) { v in v.screen = .menu(group: nil, sel: 0) }
        take("stress_relearn", sx) { v in v.screen = .relearn(ref: -1, slot: 0, at: nil) }
        var foe = Mon.wild(longMons[1], level: 100, &r); foe.shiny = true; foe.female = true; foe.item = held.first
        var sb = Battle(wild: foe, party: [big] + sx.state.caught); sb.mine[0].status = .burn; sb.theirs[0].status = .paralysis
        take("stress_battle", sx) { v in v.fight = sb; v.screen = .battle(sb, sel: 0) }
        take("stress_moves", sx) { v in v.fight = sb; v.screen = .moves(sb, sel: 3) }
        take("stress_party", sx) { v in v.fight = sb; v.screen = .party(sb, sel: 2) }
        let ex = online(Walk())                                                                   // nothing at all
        for (name, s) in [("stress_empty_items", Screen.items(0)), ("stress_empty_hold", .hold(ref: -1, sel: 0)), ("stress_empty_goals", .goals(0)), ("stress_empty_card", .card(0))] { take(name, ex) { v in v.screen = s } }
    }
    // 5.1 (docs/plans/19 §3 · §9, content51): 특성패치 — BP 교환소, who (before → after; one without a hidden ability dimmed), its line after, the page;
    // 그라시데아꽃 — the shop's 기타, 쉐이미's 모습, the forms page, 스카이폼
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) {
        var r7 = Seeded(s: 11), saur = Mon.wild(3, level: 52, &r7); saur.ability = 0; saur.nature = 3
        let pw = online({ var s = base(); s.companion = saur; s.caught = [Mon.wild(25, level: 40, &r7), Mon.wild(151, level: 50, &r7), Mon.wild(492, level: 50, &r7)]
                          s.bag = ["특성패치", "특성패치", "그라시데아꽃"]; s.bp = 260; s.watts = 6420; return s }())
        take("patch_bp_shop", pw) { v in v.screen = .shop(bp: true, sel: v.wares(true).firstIndex { $0.kind == .item("특성패치") } ?? 0, qty: nil) }
        take("patch_pick", pw) { v in v.screen = .itemOn(ItemOn(item: "특성패치", pick: -1, at: 0)) }
        take("patch_pick_back", pw) { v in v.state.caught[0].ability = 2; v.screen = .itemOn(ItemOn(item: "특성패치", pick: -2, at: 1)) }
        take("patch_pick_none", pw) { v in v.screen = .itemOn(ItemOn(item: "특성패치", pick: nil, at: 2)) }
        take("patch_done", pw) { v in v.state.companion.ability = 2; v.screen = .say(["이상해꽃의 특성이", "엽록소로 바뀌었다!", "숨겨진특성이에요"], next: .home, since: Date()) }
        take("patch_mon_page", pw) { v in v.screen = .box(-1, act: nil, confirm: false, detail: true) }
        take("flower_shop", pw) { v in v.state.bag.removeAll { $0 == "그라시데아꽃" }; v.screen = .shop(bp: false, sel: v.wares(false).firstIndex { $0.kind == .item("그라시데아꽃") } ?? 0, qty: nil) }
        take("flower_mon_page", pw) { v in v.state.bag.append("그라시데아꽃"); v.screen = .box(-4, act: 0, confirm: false, detail: true) }
        take("flower_pick", pw) { v in v.screen = .formPick(ref: -4, item: "그라시데아꽃", sel: 1) }
        take("flower_sky_page", pw) { v in v.state.caught[2].form = 1; v.screen = .box(-4, act: nil, confirm: false, detail: true) }
    } }
    // 5.1 (docs/plans/19 §1 · §9, content51): 전설 원정 — 모험 ▸, 홈's sixth row (a team event, the cells, 조립), the page (시작 전 · 지금 · 50), a cell's
    // card, the cells put together
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) {
        var r8 = Seeded(s: 12), saur = Mon.wild(3, level: 52, &r8); saur.ability = 0
        let ew = online({ var s = base(); s.companion = saur; s.caught = [Mon.wild(25, level: 40, &r8)]; s.watts = 6420; s.today = 12_400; s.total = 1_284_300; return s }())
        let (esrv, _) = server(ew), t0 = Int(Date().timeIntervalSince1970)
        esrv.expEvents = [TeamEventView(id: 1, legend: 494, starts: t0 - 4 * 86_400, ends: t0 + 3 * 86_400 - 600, goal: 1_500_000, min: 20_000, team: 931_200, mine: 12_400, got: false)]
        ew.cloud!.expeditionDue = true; drain(ew)
        take("exp_menu_first", ew) { v in v.screen = .menu(group: nil, sel: 1) }
        take("exp_menu_group", ew) { v in v.screen = menuFor("전설 원정") }
        take("exp_home_team", ew) { v in v.screen = .home }
        take("exp_list_team", ew) { v in v.screen = .expedition(0) }
        take("exp_list_start", ew) { v in v.screen = .expedition(1) }
        take("exp_list_later", ew) { v in v.screen = .expedition(2) }
        serve(ew) { $0.expeditions = ["지가르데": ExpProgress(on: true, n: 23, steps: 1_760, mon: Mon(dex: 718, level: 50, female: false))] }
        take("exp_list_cells", ew) { v in v.screen = .expedition(1) }
        esrv.expEvents = []; ew.cloud!.expeditionDue = true; drain(ew)
        take("exp_home_cells", ew) { v in v.screen = .home }
        let found = ["지가르데 셀을", "모았다!", "24/50"]
        take("exp_cell_found", ew) { v in v.sayStone = (found, "지가르데셀"); v.screen = .say(found, next: .home, since: Date()) }
        ew.sayStone = nil
        serve(ew) { $0.expeditions?["지가르데"]?.n = 50 }
        take("exp_list_ready", ew) { v in v.screen = .expedition(0) }
        take("exp_home_ready", ew) { v in v.screen = .home }
        take("exp_menu_ready", ew) { v in v.screen = .menu(group: nil, sel: 1) }
        for u in [0.9, 2.3, 3.3, 4.6] { take("exp_assemble_\(Int(u * 10))", ew) { v in v.screen = .assemble(Mon(dex: 718, level: 50, female: false), since: Date().addingTimeInterval(-u)) } }
        take("exp_assembled", ew) { v in v.screen = .say(["지가르데를", "상자에 보냈다!", "특성패치를 받았다!"], next: .expedition(0), since: Date()) }
    } }
    return n
}
#endif
