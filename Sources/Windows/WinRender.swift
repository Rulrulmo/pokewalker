#if os(Windows) || SOFTCANVAS
import Foundation
// --render <dir>: representative screens drawn through the software canvas (Windows/SoftCanvas.swift) as PNGs, the CI's artifact to set beside the Mac's:
// the Mac's golden renders by name — a made-up walker at one fixed time, fixed seeds, the whole card at 2 px a point (the LCD alone at 3). Never the
// user's save; the caller keeps settings in memory.

@MainActor func renderShots(_ dir: String) -> Int {
    let T = Date(timeIntervalSinceReferenceDate: 800_000_000)                                   // every shot's "now": a past day (the app's own Date() reads land long after)
    settings.set("battleSpeed", 2)                                                             // x1: the timed battle shots land where their names say
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    /// Pikachu Lv.30 (a 천둥의돌 in the bag), two on the walker, five in the box, an egg; spring day 6, noon, sunny.
    func base() -> Walk {
        var s = Walk(), r = Seeded(s: 3)
        s.companion = Mon.wild(25, level: 30, &r); s.caught = [Mon.wild(16, level: 8, &r), Mon.wild(41, level: 9, &r)]
        s.box = [Mon.wild(133, level: 20, &r), Mon.wild(147, level: 25, shiny: true, &r), Mon.wild(4, level: 12, perfect: 3, &r), Mon.wild(1, level: 5, &r), Mon.wild(95, level: 31, &r)]
        s.items = ["상처약", "기력의조각"]; s.bag = ["이상한사탕", "금구슬", "타우린", "하이퍼볼", "천둥의돌", "라즈열매", "은색병뚜껑", "좋은상처약"]
        s.watts = 1234; s.earned = 2500; s.bp = 40; s.weather = .sunny; s.egg = Egg(dex: 175, left: 300); s.towerBest = 5
        s.total = 5250; s.today = 1234; s.history = [3000, 0, 4521, 812, 2210]; s.seen = [19, 150, 243]; s.dex()
        return s
    }
    func still(_ v: Walker, _ who: String, _ dex: Int) { v.animOn = (who, dex, T - 60) }                // its entry animation long done
    func into(_ bs: [Beat], _ i: Int, _ u: Double) -> Date { T - (bs[..<i].map(\.length).reduce(0, +) + u) }
    func wildFight(_ v: Walker) -> (b: Battle, from: Battle, beats: [Beat]) {
        var r = Seeded(s: 5), b = Battle(wild: Mon.wild(6, level: 30, &r), companion: v.state.companion, chain: 0); let from = b
        let beats = b.begin(weather: nil, &r); return (b, from, beats)
    }
    func towerFight(_ v: Walker) -> (b: Battle, from: Battle, beats: [Beat]) {
        var r = Seeded(s: 7)
        var b = Battle(party: v.state.party().map(\.mon), trainer: "엘리트 트레이너 지은", foes: [Mon.wild(130, level: 30, &r), Mon.wild(59, level: 30, &r), Mon.wild(212, level: 31, &r)]); let from = b
        let beats = b.begin(weather: nil, &r); v.towerRun = true; return (b, from, beats)
    }
    var n = 0
    /// One shot: the look reset (SIZE size, 몬스터볼, 컬러, smooth text), `set` puts the screen, then the pane and the frame at T, as the app orders them.
    func take(_ name: String, size: CGFloat = 2, lcd: Bool = false, on v0: Walker? = nil, _ set: (Walker) -> Void) {
        SIZE = size; theme = 0; lcdStyle = 0; paperStyle = 0; smoothText = true
        let v = v0 ?? Walker(state: base()); v.persist = false; v.sideOn = true; v.rng = Seeded(s: 1); v.lastStep = .distantPast
        set(v); v.refreshPane(T, force: true); let fb = v.compose(T)
        let k: CGFloat = lcd ? 3 : 2, page = Page(); page.walker = v
        let r = Raster(Int((Layout.w * K * k).rounded()), Int(((v.cardH * K).rounded() * k).rounded()))
        drawWhole(v, page, SoftCanvas(r, scale: 2, pixels: k), shown: fb, down: nil)
        let crop = lcd ? IRect(x0: Int(lcdRect.minX * k), y0: Int(lcdRect.minY * k), x1: Int(lcdRect.maxX * k), y1: Int(lcdRect.maxY * k)) : nil
        if (try? r.png(crop).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))) != nil { n += 1 }
    }
    take("home") { _ in }
    take("home_folded") { v in v.statusOpen = false }
    take("home_night_kraft") { v in paperStyle = 3; v.state.total = 5750 }                       // 0 h
    take("home_size3", size: 3) { _ in }
    take("home_grey_original", lcd: true) { _ in lcdStyle = 1 }
    take("menu") { v in v.screen = .menu(3) }
    take("box_grid_party") { v in v.screen = .box(-1, act: nil, confirm: false) }
    take("page_box") { v in still(v, "box 0", 133); v.screen = .box(0, act: nil, confirm: false, detail: true) }
    take("items") { v in v.screen = .items(2) }
    take("items_scrolled") { v in v.screen = .items(7) }                                         // 3.1: the header's 팔 것 모두 팔기, a row further down
    take("course_list") { v in v.state.earned = 100_000; v.state.owned = Array(1...120); v.screen = .course(5) }   // 3.1: 잡음 n/m on the open ones
    let tsrv = FakeCloud(), tme = online(base(), server: tsrv)                                     // 3.2: the team (the self-test's fake server, five teammates)
    for (k, n) in ["민수", "지은", "도윤", "서연", "하은"].enumerated() {
        var w = Walk(), tr = Seeded(s: UInt64(k + 9)); w.companion = Mon.wild([6, 282, 448, 133, 25][k], level: 30 + 5 * k, &tr); w.caught = [Mon.wild(16, level: 20, &tr)]
        w.today = 2000 * (5 - k); w.owned = Array(1...(40 + 30 * k)); w.towerBest = 3 * k; tsrv.add(n, w); tsrv.lastAct[n] = k < 2 ? Date() : Date().addingTimeInterval(-3600)
    }
    tme.cloud!.teamDue = true; drain(tme)
    take("team_list", on: tme) { v in v.screen = .team(sel: 0, tab: 0, card: false) }
    take("team_ranks", on: tme) { v in v.screen = .team(sel: 0, tab: 1, card: false) }
    take("team_card", on: tme) { v in v.screen = .team(sel: 1, tab: 0, card: true) }
    take("home_visitor") { v in v.visitor = Visitor(name: "민수", dex: 6, shiny: false, until: T.addingTimeInterval(60), hello: true) }
    serve(tme) { w in var tr = Seeded(s: 21); w.box = (0..<30).map { k in Mon.wild([19, 41, 133, 147, 4, 1, 95, 129, 16, 25][k % 10], level: 5 + k, &tr) } }   // 3.3: 교환
    if var m = tsrv.walk("민수") { var tr = Seeded(s: 22); m.box = (0..<12).map { k in var x = Mon.wild([94, 6, 149, 130, 65, 68][k % 6], level: 20 + k, &tr); x.uid = 500 + k; return x }; tsrv.set("민수", m) }
    let me = tme.myName.lowercased(), now = Int(T.timeIntervalSince1970)
    tsrv.offers = [(TradeOffer(id: 1, from: "민수", to: tme.myName, mon: tsrv.walk("민수")!.box[0], want: tme.state.box[3], at: now - 3 * 3600, state: "open"), "민수", me),
                   (TradeOffer(id: 2, from: tme.myName, to: "지은", mon: tme.state.box[0], want: nil, at: now - 600, state: "open"), me, "지은")]
    tme.cloud!.tradesDue = true; drain(tme); tme.cloud!.wantBox("민수"); drain(tme)
    take("trade_list", on: tme) { v in v.screen = .trade(.list(0)) }
    take("trade_offer", on: tme) { v in v.screen = .trade(.offer(id: 1, act: nil)) }
    take("trade_pick", on: tme) { v in v.screen = .trade(.pick(TradePick(to: "민수", give: v.myTradeBox[4].uid, want: 502, side: 0, at: 4))) }
    tsrv.raidOpen(4_200_000); tsrv.raidLeft = 2_730_000                                            // 3.4: 레이드
    for (k, n) in ["민수", "지은", "도윤"].enumerated() { tsrv.raidDealt[n] = [412_000, 388_000, 201_500][k]; tsrv.raidFights[n] = 9 - k }
    tsrv.raidRecent = [RaidHit(name: "민수", dex: 6, dealt: 21_340, at: now - 120), RaidHit(name: "지은", dex: 282, dealt: 30_115, at: now - 4000)]
    serve(tme) { w in w.raidPower = 2340 }
    tme.cloud!.raidDue = true; drain(tme); drain(tme)
    take("raid_lobby", on: tme) { v in v.screen = .raid(tab: 0) }
    take("raid_battle", on: tme) { v in
        v.raidOn = true; var b = Battle(wild: tsrv.raidBoss, party: v.state.party().map(\.mon)); b.theirs += [Fighter(tsrv.raidBoss), Fighter(tsrv.raidBoss)]
        b.theirs[0].hp = 0; b.it = 1; v.fight = b; v.screen = .battle(b, sel: 0)
    }
    for n in ["민수", "지은", "도윤"] { tsrv.befriend(tme.myName, n) }; tsrv.friendAsks[tme.myName.lowercased()] = ["서연"]   // 3.5: 친구, the 게시판
    tsrv.listings = [(Listing(id: 7, from: "민수", mon: tsrv.walk("민수")!.box[1], wish: [25, 133], at: now - 5000, bids: 0, mine: false), "민수", true),
                     (Listing(id: 8, from: tme.myName, mon: tme.state.box[2], wish: [149], at: now - 900, bids: 0, mine: false), tme.myName.lowercased(), true)]
    tsrv.bids = [(Bid(id: 4, listing: 8, from: "지은", mon: tsrv.walk("민수")!.box[2], at: now - 300, state: "open"), "지은", tme.myName.lowercased())]
    tme.cloud!.teamDue = true; tme.cloud!.marketDue = true; drain(tme); drain(tme)
    take("menu_11", on: tme) { v in v.screen = .menu(menuAt("교환")) }
    take("friends_requests", on: tme) { v in v.screen = .team(sel: 0, tab: 4, card: false) }
    take("market_board", on: tme) { v in v.screen = .market(.board(tab: 0, sel: 0)) }
    take("market_post_mine", on: tme) { v in v.screen = .market(.post(id: 8, sel: 0)) }
    take("market_pick_wish", on: tme) { v in v.screen = .market(.pick(MarketPick(give: v.myTradeBox[3].uid, wish: [25, 133], side: 1, at: 24))) }
    take("traded", on: tme) { v in v.screen = .traded(gave: v.state.box[2], got: tsrv.walk("민수")!.box[4], with: "민수", since: T - 5) }
    take("grid_drag") { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(T, force: true); v.drag = (10001, CGPoint(x: 150 * K, y: 30 * K)) }   // 3.1: one of the box carried onto the walker's row
    take("dex_grid") { v in v.screen = .dex(25, filter: 0, detail: false) }
    take("dex_entry") { v in still(v, "dex", 25); v.screen = .dex(25, filter: 0, detail: true) }
    take("shop_list") { v in v.screen = .shop(bp: false, sel: 3, qty: nil) }
    take("shop_qty") { v in v.screen = .shop(bp: false, sel: 1, qty: 5) }
    take("radar_live") { v in v.screen = .radar(bush: 1, cursor: 1, since: T - 1.75, chain: 3) }
    take("battle_menu") { v in let f = wildFight(v); still(v, "foe 0", 6); v.screen = .battle(f.b, sel: 1) }
    take("battle_moves") { v in let f = wildFight(v); still(v, "foe 0", 6); v.screen = .moves(f.b, sel: 2) }
    take("move_use") { v in                                                                     // the foe (faster) goes first: 용의분노, 0.55 s in
        var r = Seeded(s: 9), f = wildFight(v); let from = f.b
        let id = f.b.mine[f.b.me].moves.first { moveTable[$0]!.special && moveTable[$0]!.power > 0 } ?? f.b.mine[f.b.me].moves[0]
        let beats = f.b.turn(.fight(id), &r), uses = beats.indices.filter { if case .use = beats[$0] { true } else { false } }
        let bs = uses.count > 1 && uses.last! > uses[0] + 1 ? Array(beats[...uses.last!]) : beats
        still(v, "foe 0", 6); v.screen = .beats(f.b, bs, since: into(bs, uses[0], 0.55), from: from)
    }
    take("throw_rock") { v in let f = wildFight(v), bs: [Beat] = [.thrown(shakes: 3)]; v.usedItem = "하이퍼볼"; v.screen = .beats(f.b, bs, since: T - 2.4, from: f.b) }
    take("tower_intro_2.5") { v in let f = towerFight(v); v.screen = .beats(f.b, f.beats, since: T - 2.5, from: f.from) }
    take("learn") { v in v.state.learning = [v.state.id(-1)!, 87]; v.screen = .learn(sel: 1) }
    take("card_0") { v in v.screen = .card(0) }
    take("battle_size3", size: 3) { v in let f = wildFight(v); still(v, "foe 0", 6); v.screen = .battle(f.b, sel: 0) }
    return n
}
#endif
