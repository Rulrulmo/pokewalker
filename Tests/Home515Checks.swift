import Foundation
// 5.1.5 (the user via 회사 10-21: "지금 홈화면에서 레이더 눌렀을때 메뉴 화면으로 이동했다가 넘어가는데 꼭 그렇게 넘어가야해?"): self-test checks (run by
// selftest()). 홈's quick buttons (레이더 · 포켓몬 · 도구 · 우편함) and rows (알 · 배틀 타워 · 도감 · 레이드 · 친구 · 전설 원정), clicked and by their keys
// (R · B · I · / · 1 · 3): never a frame of the menu on the way (the panel, the title row) — the radar waits for the server over 홈, offline's
// 연결되면 goes back home; ↩ (Esc) from there goes home; the menu's last tile and its groups' stay. From the menu: as before.

@MainActor func home515Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func add(_ t: (Bool, String, String)) { c.append((t.0, t.1)); if !t.0 { print("home515: \(t.1.prefix(32))… — \(t.2)") } }

    Content.$testing.withValue(true) { Content.$testing51.withValue(true) {
        let v = online({ var s = Walk(); s.watts = 5000; s.egg = Egg(dex: 175, left: 900); return s }())
        let (srv, _) = server(v)
        var bad: [String] = []
        /// What the card shows now (the panel, the title row): the menu's anywhere is a frame of it.
        @MainActor func frame(_ how: String) { v.refreshPane(Date(), force: true); if v.homeOpened != Walker.raidGroupHome, v.pane.menu != nil || v.title().title == "메뉴" { bad.append("\(how): \(v.screen)") } }   // (5.2: 홈's 레이드 row opens its group: 레이드 · 메가 레이드)
        /// The server's answer in, a frame after every tick (as the card draws between them).
        @MainActor func settle(_ how: String) { var n = 0; while n < 40, v.waiting != nil || v.cloud?.inFlight != nil || v.cloud?.queued != nil { v.tick(Date()); frame(how); n += 1 } }
        @MainActor func row(_ key: String) -> Int { v.screen = .home; v.refreshPane(Date(), force: true); return v.pane.status?.rows.firstIndex { $0.key == key } ?? -1 }
        @MainActor func at(_ s: Screen, _ want: String) -> Bool {
            switch (s, want) {
            case (.radar, "레이더"), (.box(-1, nil, _, false), "포켓몬"), (.items, "도구"), (.mail(.list), "우편함"), (.card(2), "알"), (.tower(nil), "배틀 타워"), (.dex(_, _, false), "도감"),
                 (.team(_, _, false), "친구"), (.expedition, "전설 원정"): true
            case (.menu(let g?, _), "레이드"): { let o = v.homeOpened, t = v.title().title; return menuTiles[g].items.contains("레이드") && o == Walker.raidGroupHome && t == "홈" }()   // 5.2 (the user: "레이드/메가레이드 선택화면으로")
            default: false
            }
        }
        let rows = ["알", "배틀 타워", "도감", "레이드", "친구", "전설 원정"]
        var ways: [(how: String, want: String, tap: Int?, key: Walker.Key?)] = Walker.quick.enumerated().map { k, n in ("click " + n, n == "포켓 레이더" ? "레이더" : n, 9320 + k, nil) }
        ways += rows.map { n in ("row " + n, n, 9300 + row(n), nil) }
        ways += [("R", "레이더", nil, .letter("r")), ("B", "포켓몬", nil, .letter("b")), ("I", "도구", nil, .letter("i")), ("/", "도감", nil, .letter("/")), ("1", "레이더", nil, .digit(1)), ("3", "포켓몬", nil, .digit(3))]
        v.lastTile = 5; v.menuSlot = [1: 1, 3: 2, 6: 3]
        var reached: [String] = [], waited: [String] = [], backHome: [String] = []
        for w in ways {
            v.screen = .home; frame("home")
            if let t = w.tap { v.paneTap(t) } else if let k = w.key { _ = v.key(k) }
            frame(w.how)
            if w.want == "레이더", case .say(["포켓 레이더", "준비 중..."], .home, _) = v.screen, v.waiting != nil, v.pane.status != nil { waited.append(w.how) }   // the wait: over 홈's sheet
            settle(w.how)
            if at(v.screen, w.want) { reached.append(w.how) }
            if case .radar(let b, _, _, let ch) = v.screen {                                    // the radar can't be backed out of: a wrong bush ends it (home)
                v.screen = .radar(bush: b, cursor: (b + 1) % 4, since: .distantPast, chain: ch); v.press(1); frame(w.how + " ✕"); v.press(1); frame(w.how + " ✕ ●"); drain(v)
            } else { _ = v.key(.back); frame(w.how + " ↩") }
            if case .home = v.screen { backHome.append(w.how) }
        }
        let kept = v.lastTile == 5 && v.menuSlot == [1: 1, 3: 2, 6: 3]
        add((bad.isEmpty && reached.count == ways.count && waited == ["click 포켓 레이더", "R", "1"] && backHome.count == ways.count && kept,
             "5.1.5 홈: its buttons (레이더 · 포켓몬 · 도구 · 우편함) and rows (알 · 배틀 타워 · 도감 · 레이드 · 친구 · 전설 원정), clicked or by R · B · I · / · 1 · 3, open straight (not a frame of the menu: the radar waits over 홈); ↩ goes home; the menu's last tile and groups' stay",
             "\(bad.prefix(6)) reached \(reached.count)/\(ways.count) \(Set(ways.map(\.how)).subtracting(reached)) waited \(waited) home \(Set(ways.map(\.how)).subtracting(backHome)) \(v.lastTile) \(v.menuSlot)"))

        // inside what 홈 opened, ↩ one step at a time and home at the end; 메뉴 then the menu's way: as before (back to the menu, its tile)
        v.screen = .home; v.paneTap(9321); v.paneTap(4510); let toItems: Bool = { if case .items = v.screen { return true }; return false }()
        _ = v.key(.back); let grid: Bool = { if case .box(-1, nil, _, false) = v.screen { return true }; return false }()
        _ = v.key(.back); let deep = toItems && grid && { if case .home = v.screen { return true }; return false }()
        v.screen = .home; v.paneTap(9300 + row("친구")); _ = v.key(.back)
        v.press(4); let menuKey: Bool = { if case .menu(nil, 5) = v.screen { return true }; return false }()       // (the 메뉴 key: on the tile it kept)
        v.press(4); v.openFeature("도감"); _ = v.key(.back); let viaMenu = onMenu(v.screen, "도감") && v.lastTile == menuTiles.firstIndex { $0.items.contains("도감") }
        v.screen = .home; v.paneTap(9300 + row("도감")); v.press(4); v.openFeature("도감"); _ = v.key(.back)
        let cleared = onMenu(v.screen, "도감")                                                            // (홈 again, then the menu: its ↩ the menu's)
        v.screen = .home; v.openFeature("포켓 레이더"); let menuWait: Bool = { if case .say(_, .menu, _) = v.screen { return v.waiting != nil }; return false }()
        settle("menu radar"); bad = []; if case .radar = v.screen { v.giveUpRadar(); v.screen = .home; drain(v) }
        add((deep && menuKey && viaMenu && cleared && menuWait,
             "5.1.5 홈's 포켓몬 → its 도구 tab → ↩ the grid → ↩ home; the 메뉴 key on the tile it kept; opened from the menu: ↩ to the menu, its tile (the radar waits on the menu, as before)",
             "\(toItems) \(grid) \(deep) \(menuKey) \(viaMenu) \(cleared) \(menuWait) \(v.screen)"))

        // offline: 연결되면 할 수 있어요 over 홈, ● home again
        srv.down = true; v.cloud!.addSteps(3); v.cloud!.saveNow(); v.tick(Date()); v.tick(Date())
        var offline: [String] = []
        for (how, code) in [("레이더", 9320), ("우편함", 9323), ("레이드", 9300 + row("레이드")), ("친구", 9300 + row("친구"))] {
            v.screen = .home; v.paneTap(code); frame("offline " + how)
            if case .say(Walker.offlineLines, .home, _) = v.screen { v.press(1); frame("offline " + how + " ●"); if case .home = v.screen { offline.append(how) } }
        }
        let wasOff = v.cloud?.online == false
        srv.down = false; v.tick(Date() + 121); drain(v)
        add((wasOff && bad.isEmpty && offline == ["레이더", "우편함", "레이드", "친구"],
             "5.1.5 홈 offline: 레이더 · 우편함 · 레이드 · 친구 say 연결되면 할 수 있어요 over 홈 (no menu under it), ● home again", "\(wasOff) \(offline) \(bad.prefix(4))"))
    } }
    return c
}
