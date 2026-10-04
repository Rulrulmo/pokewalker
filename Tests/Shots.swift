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
    take("grid_drag_to_walker", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (10002, CGPoint(x: 150 * K, y: 30 * K)) }
    take("grid_drag_to_box", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (4501, CGPoint(x: 100 * K, y: 120 * K)) }
    return n
}
#endif
