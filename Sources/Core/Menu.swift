import Foundation
// The right-click / menu-bar menu as data over the walker's state; each row's action is a closure on the walker (Flow.swift, the look's setters below).
// The Mac shows it as its native menu (Mac/MenuBar.swift).

/// A row: its title, on or off (off = a dim note), ✓, a submenu, what it does; strong = the part shown bold in amber (3V and up), key = a shortcut
/// (종료: q), tip = a hover note. A separator is a line between groups.
struct MenuItem {
    var title: String, enabled: Bool, checked: Bool, key: String, tip: String?, strong: String? = nil, isSeparator = false
    var children: [MenuItem]?, action: (@MainActor () -> Void)?
    /// On unless `enabled` says: the rows that do something or open a submenu (the rest are notes).
    init(_ title: String, checked: Bool = false, enabled: Bool? = nil, key: String = "", tip: String? = nil, _ children: [MenuItem]? = nil, action: (@MainActor () -> Void)? = nil) {
        self.title = title; self.checked = checked; self.key = key; self.tip = tip; self.children = children; self.action = action
        self.enabled = enabled ?? (action != nil || children != nil)
    }
    static var separator: MenuItem { var m = MenuItem(""); m.isSeparator = true; return m }
    /// 3V and up in amber, bold, so the rare ones stand out in long lists (the title's last "nV"); 1V / 2V stay plain.
    func emphasized(_ n: Int) -> MenuItem { var m = self; if n >= 3, title.contains("\(n)V") { m.strong = "\(n)V" }; return m }
}

extension Walker {
    func menu() -> [MenuItem] {
        #if os(Windows)
        let hide = "알림 영역으로 숨기기", hotKey = "Ctrl+Alt+P"                                    // the tray, where the Mac has its menu bar
        #else
        let hide = "메뉴 막대로 숨기기", hotKey = "⌃⌥P"
        #endif
        var m = [MenuItem((host?.windowHidden == true ? "워커 보이기" : hide) + " · " + hotKey, action: { self.host?.toggleShown() })]   // the shortcut works from anywhere   // options only: the game is on the pane (코스, 포켓몬, 도구 …)
        func sub(_ title: String, _ items: [(String, Int)], _ current: Int, fits: ((Int) -> Bool)? = nil, _ set: @escaping @MainActor (Int) -> Void) -> MenuItem {
            MenuItem("\(title) · \(items.first { $0.1 == current }?.0 ?? "")", items.map { t, tag in MenuItem(t, checked: tag == current, enabled: fits.map { $0(tag) }, action: { set(tag) }) })
        }
        m.append(.separator)
        m.append(sub("크기", [("보통", 2), ("크게", 3), ("아주 크게", 4)], Int(SIZE), fits: { self.host?.fits(size: CGFloat($0)) ?? true }) { self.setSize($0) })   // a size whose tallest page won't fit this screen: off
        m.append(sub("기기", shells.enumerated().map { ($1.dex > dexCount ? "\($1.name) — 도감 \($1.dex)" : !shellOpen($1) ? "\($1.name) — \($1.bp)BP" : $1.name, $0) }, theme) { self.setTheme($0) })
        m.append(sub("화면", lcds.enumerated().map { ($1.name, $0) }, lcdStyle) { self.setLCD($0) })
        m.append(sub("수첩 배경", paperNames.enumerated().map { ($1, $0) }, paperStyle) { self.setPaper($0) })
        m.append(sub("화면 글씨", [("매끈하게", 1), ("도트", 0)], smoothText ? 1 : 0) { self.setTextStyle($0 == 1) })
        m.append(sub("배틀 속도", [("보통", 2), ("빠르게", 3), ("아주 빠르게", 4)], settings.int("battleSpeed", 3)) { self.setBattleSpeed($0) })   // x1 · x1.5 · x2
        m.append(.separator)
        m.append(MenuItem("알림", notifyKinds.enumerated().map { i, kn in MenuItem(kn.1, checked: notifyOn(kn.0), action: { self.toggleNotify(i) }) }
            + [.separator, MenuItem("테스트 알림 보내기", action: { self.testNotify() })]))
        if let c = cloud {                                                                        // the save server (on: Core/Cloud.swift)
            m.append(.separator)
            m.append(MenuItem(cloudMenuTitle, enabled: false))
            m.append(MenuItem("지금 저장", enabled: c.phase == .on, action: { self.cloud?.saveNow() }))
            m.append(MenuItem("ID 바꾸기…", enabled: !cloudAsking, action: { self.askID(change: true) }))
        }
        if let v = stagedUpdate {                                                                 // auto-update (Core/Update.swift): a newer one staged
            if cloud == nil { m.append(.separator) }
            let why = installBlocker
            var install: (@MainActor () -> Void)? = nil; if why == nil { install = { self.installUpdateNow() } }   // greyed: no action
            m.append(MenuItem(why.map { "업데이트 설치 · \(v) — \($0)" } ?? "업데이트 설치 (다시 시작) · \(v)", enabled: why == nil, action: install))
        }
        m.append(.separator)
        m.append(MenuItem("종료", key: "q", action: { self.host?.quit() }))
        return m
    }

    // MARK: the menu's own actions (the walker's: Flow.swift)
    /// 중복 놓아주기: asks first (who stays, that it can't be undone), then lets them go.
    func askReleaseDupes(_ dex: Int) {
        let gone = state.duplicates(of: dex), n = gone.count
        let stay = state.box.indices.filter { state.box[$0].dex == dex && !gone.contains($0) }.map { state.box[$0] }
        let who = stay.prefix(4).map { "\($0.shiny == true ? "★" : "")Lv.\($0.level)\(sexMark($0))\(vMark($0))" }.joined(separator: ", ") + (stay.count > 4 ? " 외 \(stay.count - 4)마리" : "")
        guard n > 0, host?.confirm("\(monNames[dex]) \(n)마리를 놓아줄까요?",
            "상자에서 이로치와 3V 이상은 모두 남고, 그 밖엔 가장 좋은 1마리(V 수 → 경험치 순)만 남아요 — 3V 이상이 있으면 그 1마리 몫도 그쪽이에요.\n남는 포켓몬: \(who)\n되돌릴 수 없어요.", ok: "놓아주기") == true else { return }
        releaseDupes(dex)
    }
    func testNotify() { notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 인사해요", "알림이 이렇게 와요 · 지금 \(state.watts)W") }
    func toggleNotify(_ i: Int) { let k = notifyKinds[i].0; settings.set("notify.\(k)", !notifyOn(k)) }
    /// 크기: the card grows down from its top-left (the host keeps it on the screen).
    func setSize(_ size: Int) {
        guard host?.fits(size: CGFloat(size)) ?? true else { host?.beep(); return }
        SIZE = CGFloat(size); settings.set("px", size)
        host?.resized(); host?.redraw(.all)
    }
    func setTheme(_ t: Int) { guard shellOpen(shells[t]) else { return }; theme = t; settings.set("shell", theme); host?.redraw(.all) }
    func setTextStyle(_ smooth: Bool) { smoothText = smooth; settings.set("smoothText", smoothText); host?.redraw(.all) }
    func setLCD(_ i: Int) { lcdStyle = i; settings.set("lcd", lcdStyle); host?.redraw(.all) }
    /// 배틀 속도: a turn playing now goes on from where it is (its clock is rebased).
    func setBattleSpeed(_ tag: Int) {
        let old = battleSpeed; settings.set("battleSpeed", tag)
        if case .beats(let b, let bs, let s, let f) = screen { let now = Date(); screen = .beats(b, bs, since: now.addingTimeInterval(-now.timeIntervalSince(s) * old / battleSpeed), from: f) }
    }
    func setPaper(_ i: Int) { paperStyle = i; settings.set("paper", paperStyle); host?.redraw(.all) }
}
