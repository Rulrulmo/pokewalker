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
    take("grid_drag_to_walker", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (10002, CGPoint(x: 150 * K, y: 30 * K)) }
    take("grid_drag_to_box", grid) { v in v.screen = .box(-1, act: nil, confirm: false); v.refreshPane(Date(), force: true); v.drag = (4501, CGPoint(x: 100 * K, y: 120 * K)) }
    return n
}
#endif
