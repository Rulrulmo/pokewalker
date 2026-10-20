import Foundation
// 5.0's quality pass, the panel's ease (the user: "하단패널 내가 원한건 디자인 뿐만 아니라 편의성도 개선했으면 했던건데", then "전부다 포함해서
// 진행"): fewer clicks for what's done most. 홈's sheet with quick buttons (포켓 레이더 · 포켓몬
// · 도구 · 우편함, its red dot) and its rows opening their pages; the menu back on the tile last used, each tile's number key; the box's pick
// with its actions under the grid (함께 걷기 · 도구 주기 · 자세히) — no second click for its page; the shop's amount 최대; the 도감's
// 찾기 (a name or a number). Docs: lcd-mockups docs/mockups/ux-5.0.

extension Walker {
    /// 홈's quick buttons: a feature each, its red dot (something waits there).
    static let quick = ["포켓 레이더", "포켓몬", "도구", "우편함"]
    /// 홈's rows → the page each opens (the status sheet's 알 · 배틀 타워 · 도감 · 레이드 · 친구).
    static let homeLinks: [String: String] = ["전설 원정": "전설 원정", "알": "트레이너 카드", "배틀 타워": "배틀 타워", "도감": "도감", "레이드": "레이드", "친구": "친구"]
    /// 5.1.5 (the user via 회사 10-21: "홈화면에서 레이더 눌렀을때 메뉴 화면으로 이동했다가 넘어가는데 꼭 그렇게 넘어가야해?"): straight there — the
    /// radar waits for the server on the page it came from (not the menu on its tile), ↩ from 홈's goes home (up), the menu's last tile stays.
    func quickOpen(_ name: String) {
        guard !frozen, waiting == nil else { return }
        lastInput = Date(); host?.redraw(.all)
        let from = screen
        if case .home = from { homeOpened = name }
        switch name {
        case "도구": screen = .items(itemsAt)
        case "트레이너 카드": screen = .card(2)                                                       // (알: its page)
        case "포켓 레이더": openRadar(back: from, Date())
        default: if menuItems.contains(name) { open(name, tile: false) }
        }
    }
    /// Where ↩ from a feature's first page goes: home when 홈 opened it (5.1.5), else the menu on its tile.
    func up(_ name: String) -> Screen { homeOpened != nil ? .home : menuFor(name) }
    /// The shop's amount typed (1 … what can be bought).
    func shopAmount() {
        guard case .shop(let bp, let sel, .some) = screen, let w = wares(bp)[safe: sel], let h = host else { return }
        let most = max(1, state.canBuy(w, bp: bp))
        guard let raw = h.askText(title: "몇 개 살까요?", message: "1 ~ \(most)개"), let n = Int(raw.trimmingCharacters(in: .whitespaces)) else { return }
        screen = .shop(bp: bp, sel: sel, qty: max(1, min(most, n))); lastInput = Date(); host?.redraw(.all)
    }
    /// The 도감's 찾기: a name (its start, or in it) or a number → that one's entry (on 전국 · 전체, so it's in the list).
    func dexFind() {
        guard let h = host, let raw = h.askText(title: "도감 찾기", message: "포켓몬 이름이나 번호") else { return }
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        dexRegion = 0
        let all = dexList(0), found = Int(q).flatMap { n in all.contains(n) ? n : nil }
            ?? all.first { monNames[$0].hasPrefix(q) } ?? all.first { monNames[$0].contains(q) }
        guard let d = found else { screen = .say([josa("'\(q)'", "을", "를"), "찾지 못했어요"], next: screen, since: Date()); return }
        screen = .dex(d, filter: 0, detail: true)
    }

    /// 5.0: what's kept for next time (this PC; the app's walker only): the shop's ware last looked at, the bag's item.
    func remember(_ s: Screen) {
        guard persist else { return }
        switch s {
        case .shop(let bp, let sel, _): if settings.int("ui.shop.\(bp ? "BP" : "W")", -1) != sel { settings.set("ui.shop.\(bp ? "BP" : "W")", sel) }
        case .items(let sel): if settings.int("ui.items", -1) != sel { settings.set("ui.items", sel) }
        case .goals: if goalsSeen != (state.dexRewards ?? []).count { goalsSeen = (state.dexRewards ?? []).count; settings.set("ui.goalsSeen", goalsSeen) }
        default: break
        }
    }
    /// The bag where it was left (its row, clamped).
    var itemsAt: Int { min(max(0, settings.int("ui.items", 0)), max(0, state.inventory.count - 1)) }

    // MARK: the shortcuts (5.0): 1–8 the menu's tiles (a group's page: its rows), R 포켓 레이더, B 포켓몬, I 도구, / 찾기 (도감, 상자)
    func shortcut(_ k: Key) -> Bool {
        let calmPage: Bool = { switch screen { case .home, .menu, .dex(_, _, false), .box(_, .none, _, false), .items, .card, .goals, .course, .expedition, .rank: true; default: false } }()
        guard calmPage else { return false }
        switch k {
        case .digit(let n) where (1...8).contains(n):
            if case .menu(let g?, _) = screen { guard menuTiles[g].items.indices.contains(n - 1) else { return false }; menuTap(n - 1); return true }
            if case .home = screen, menuTiles[n - 1].items.isEmpty { quickOpen(menuTiles[n - 1].name); return true }   // 5.1.5: 홈's 1 · 3 (레이더 · 포켓몬) as its buttons
            screen = .menu(group: nil, sel: n - 1); press(1); return true
        case .letter(let c):
            switch c {
            case "r": quickOpen("포켓 레이더")
            case "b": quickOpen("포켓몬")
            case "i": quickOpen("도구")
            case "/":
                if case .dex = screen { dexFind() } else if case .box = screen { boxFind() } else { quickOpen("도감"); dexFind() }
            default: return false
            }
            return true
        default: return false
        }
    }

    // MARK: the 상자's 찾기 (5.0): words, all of them to match — a name (or part of it), a number, a type (불꽃), 이로치 (★), 3V … 6V, 도구 (지닌)
    func boxMatch(_ m: Mon, _ q: String) -> Bool {
        let types = Dictionary(typeKo.map { ($1, $0) }) { a, _ in a }
        return q.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).allSatisfy { w in
            let t = String(w)
            if t == "이로치" || t == "★" { return m.shiny == true }
            if t.count == 2, t.hasSuffix("v"), let n = Int(t.prefix(1)) { return m.perfectIVs >= n }
            if ["도구", "지닌", "지님", "지닌도구"].contains(t) { return m.item != nil }
            if let ty = types[t] { return m.typing.contains(ty) }
            if let n = Int(t) { return m.dex == n }
            return monNames[m.dex].contains(t) || (Forms.of(m.dex, m.form)?.name.contains(t) ?? false)
        }
    }
    /// The box as the grid shows it: its order (boxSort), what 찾기 keeps.
    var boxShown: [Int] { boxQuery.isEmpty ? boxOrder : boxOrder.filter { boxMatch(state.box[$0], boxQuery) } }
    func boxFind() {
        guard let h = host, let raw = h.askText(title: "상자 찾기", message: "이름 · 번호 · 타입(불꽃) · 이로치 · 3V · 도구\n띄어 쓰면 모두 맞는 것만") else { return }
        boxQuery = raw.trimmingCharacters(in: .whitespaces)
        screen = .box(boxShown.first ?? -1, act: nil, confirm: false); lastInput = Date(); host?.redraw(.all)
    }

    // MARK: the red dots (5.0): the power full with runs left today, one of ours ready to evolve by an item in the bag, a 도감 업적 not looked at
    func powerDot(mega: Bool) -> Bool {
        if raidDaily {                                                                              // 5.1 (plan 20): power that midnight would take (3 hours before it)
            guard raidPower >= Engine.raidPowerCost, cloud?.online == true, let e = mega ? megaLobby?.ends : raidLobby?.ends else { return false }
            return hoursLeft(e) <= 3 && (mega ? Content.gen6 && (megaLeftToday ?? 1) > 0 : (raidLeftToday ?? 1) > 0)
        }
        guard raidPower >= Engine.raidPowerMax, cloud?.online == true else { return false }
        if mega { return Content.gen6 && (megaLeftToday ?? 1) > 0 }
        return (raidLeftToday ?? 1) > 0
    }
    var evolveDot: Bool { ([-1] + state.caught.indices.map { -2 - $0 }).contains { !state.stoneEvolutions(Date(), ref: $0).isEmpty } || !state.evoReady(Date()).isEmpty }   // (5.1.3: a 배루키 to pick, the box's too)
    var goalsDot: Bool { Content.gen6 && (state.dexRewards ?? []).count > goalsSeen }
}
