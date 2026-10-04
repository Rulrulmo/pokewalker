import Foundation
// What the buttons and taps do on each screen, and the menu's actions. 3.0 (docs/plans/11): what changes the save is an act the server runs
// (Core/Act.swift); here are the screens around it.

extension Walker {
    /// A fight begins: its foes play their entry animations afresh, and the last fight's per-species effect masks are let go (they're rebuilt on demand).
    func freshFight() {
        animOn = nil
        dropPics("fx|mask|")
    }
    func radarWindow(_ chain: Int) -> Double { Engine.radarWindow(chain) }
    func notify(_ kind: String, _ title: String, _ body: String) {
        guard persist, notifyOn(kind) else { return }
        host?.notify(title, body)
    }
    /// The save on this PC is the server's, as last shown (a cache to open with), and the steps not up yet (cloud.json).
    func save() { guard persist else { return }; Store.save(state); cloud?.keepSteps(); lastSave = Date(); if !savedSigned { savedSigned = true; settings.set("saveSigned", true) } }
    /// Quitting: the last steps counted, up to the server (2 s at most), saved.
    func quitSave() {
        if let h = host, !frozen { let n = state.roomToday(gate.pass(state.take(counter: h.counter(), boot: h.boot(), at: Date()), Date().timeIntervalSinceReferenceDate)); cloud?.addSteps(n); if !inBattle { _ = state.walk(n, at: Date()) } }
        cloud?.flush()
        save()
        if persist || relaunchAfterQuit, !shuttingDown { _ = installUpdate(relaunchAfterQuit) }   // a staged update goes in once the app is gone, started again only from 업데이트 설치 (else the user quit); not mid-shutdown: half a swap
    }
    /// The 상점's (bp false) or BP 교환소's rows (the BP device colours at the server's prices).
    func wares(_ bp: Bool) -> [Walk.Ware] { state.wares(bp: bp, shells: Engine.bpShells) }
    /// The shop's tabs that have something (docs/plans/13), the one a row is on, and a tab's rows (their places in wares).
    func shopTabs(_ bp: Bool) -> [String] { let ws = wares(bp); return Walk.shopTabs(bp: bp).filter { t in ws.contains { Walk.shopTab($0, bp: bp) == t } } }
    func shopTab(_ bp: Bool, _ sel: Int) -> Int { let ts = shopTabs(bp); return wares(bp)[safe: sel].flatMap { ts.firstIndex(of: Walk.shopTab($0, bp: bp)) } ?? 0 }
    func shopRows(_ bp: Bool, _ tab: Int) -> [Int] { let ws = wares(bp), t = shopTabs(bp)[safe: tab]; return ws.indices.filter { Walk.shopTab(ws[$0], bp: bp) == t } }
    /// A shell the 기기 menu offers: the dex reached, and a BP one bought.
    func shellOpen(_ s: Shell) -> Bool { s.dex <= dexCount && (s.bp == 0 || (state.bought ?? []).contains(s.name)) }
    /// Buys q of the row (the server's): a line to say, then back to the list.
    func buyWare(_ w: Walk.Ware, _ q: Int, bp: Bool, sel: Int, _ now: Date) {
        let back = Screen.shop(bp: bp, sel: sel, qty: nil), cost = "(-\(w.price * q)\(bp ? "BP" : "W"))"
        guard state.canBuy(w, bp: bp) >= q else { screen = .say([bp ? "BP가 부족하다" : "W가 부족하다"], next: back, since: now); return }
        switch w.kind {
        case .item(let i):
            act(.buy(bp: bp, item: i, legend: nil, shell: nil, qty: q), back: back, now) { _, now in .say([josa(i, "을", "를") + (q > 1 ? " \(q)개" : ""), (bp ? "받았다! " : "샀다! ") + cost], next: back, since: now) }
        case .legend(let k):
            act(.buy(bp: bp, item: nil, legend: k, shell: nil, qty: 1), back: back, now, lines: ["전설의 포켓몬", "부르는 중..."]) { [weak self] o, now in
                guard let m = o.mon else { return back }
                self?.notify("unlock", "전설의 \(monNames[m.dex])", "Lv.\(m.level)이 상자에 왔어요")
                return .say(["전설의 " + monNames[m.dex] + "!", "Lv.\(m.level) · 상자에 왔다"], next: back, since: now)
            }
        case .shell(let s):
            act(.buy(bp: bp, item: nil, legend: nil, shell: s, qty: 1), back: back, now) { [weak self] _, now in
                if let self, let t = shells.firstIndex(where: { $0.name == s }) { theme = t; if persist { settings.set("shell", t) } }   // wear it straight away
                return .say(["기기 색", s + " 획득!"], next: back, since: now)
            }
        }
    }
    /// ↑ ↓ keys and the panel's buttons: in the list a row up / down, in how-many ±n (clamped, not wrapping); `nil` = as many as can be bought.
    func shopStep(_ d: Int?) {
        guard case .shop(let bp, let sel, let qty) = screen else { return }
        lastInput = Date(); host?.redraw(.all)
        let ws = wares(bp); guard let w = ws[safe: sel] else { return }
        let most = state.canBuy(w, bp: bp)
        if let q = qty { screen = .shop(bp: bp, sel: sel, qty: d.map { max(1, min(max(1, most), q + $0)) } ?? max(1, most)) }
        else if let d { let ids = shopRows(bp, shopTab(bp, sel)), i = ids.firstIndex(of: sel) ?? 0; screen = .shop(bp: bp, sel: ids[max(0, min(ids.count - 1, i + d.signum()))], qty: nil) }   // within its tab
    }
    /// The scroll wheel / trackpad on a list: a row up or down — the shop's (leaving how-many: the amount only changes on purpose) or the tower's picker.
    func listRow(_ d: Int) {
        guard !frozen, waiting == nil else { return }
        if case .tower(_?) = screen { towerStep(d); return }
        if case .course(let i) = screen { lastInput = Date(); host?.redraw(.all); screen = .course(max(0, min(courses.count - 1, i + d))); return }
        if case .items(let s) = screen { lastInput = Date(); host?.redraw(.all); screen = .items(max(0, min(state.inventory.count - 1, s + d))); return }   // 도구: a row (the wheel, ↑ ↓)
        if case .train(let k) = screen { lastInput = Date(); host?.redraw(.all); screen = .train(max(0, min(5, k + d))); return }
        if case .relearn(let r, let s, let at) = screen, let m = state.mon(r) {                 // 기술 바꾸기: its slots, or the moves for one
            lastInput = Date(); host?.redraw(.all)
            if let at { let all = m.relearnable, i = all.firstIndex(of: at) ?? 0; screen = .relearn(ref: r, slot: s, at: all[max(0, min(all.count - 1, i + d))]) }
            else { screen = .relearn(ref: r, slot: max(0, min(min(3, m.moves.count), s + d)), at: nil) }
            return
        }
        let bp: Bool, sel: Int
        switch screen { case .shop(let b, let s, _), .shopConfirm(let b, let s, _): bp = b; sel = s; default: return }
        lastInput = Date(); host?.redraw(.all)
        screen = .shop(bp: bp, sel: max(0, min(wares(bp).count - 1, sel + d)), qty: nil)
    }
    /// The tower's picker: d rows on (↑ ↓, page up / down, the wheel), stopping at the ends.
    func towerStep(_ d: Int) {
        guard case .tower(let p?) = screen else { return }
        lastInput = Date(); host?.redraw(.all)
        let all = state.towerCandidates, sel = all.firstIndex(of: p.at) ?? 0
        screen = .tower(pick: (p.slot, all[max(0, min(all.count - 1, sel + d))]))
    }
    /// A click on the shop panel: 2100 + k = row k (and how-many, if it can be bought), 2000-2004 = −10 −1 +1 +10 max, 2005 = buy, 2006 / 2007 = 예 / 아니오,
    /// 2900 + t = tab t (3.6).
    func shopTap(_ code: Int) {
        guard !frozen, waiting == nil else { return }
        throughSay()
        if case .shopConfirm(let bp, let sel, _) = screen {
            if code == 2006 { screen = .shopConfirm(bp: bp, sel: sel, yes: true); press(1) }
            else if code == 2007 { screen = .shop(bp: bp, sel: sel, qty: nil) }
            else if code >= 2100 { screen = .shop(bp: bp, sel: sel, qty: nil); shopTap(code) }
            return
        }
        guard case .shop(let bp, _, let qty) = screen else { return }
        lastInput = Date(); host?.redraw(.all)
        if (2900..<2920).contains(code) { if let first = shopRows(bp, code - 2900).first { screen = .shop(bp: bp, sel: first, qty: nil) }; return }   // a tab: its first row
        if code >= 2100 {
            let k = code - 2100; guard let w = wares(bp)[safe: k] else { return }
            screen = .shop(bp: bp, sel: k, qty: state.canBuy(w, bp: bp) > 0 ? 1 : nil); return
        }
        guard qty != nil else { return }                                                           // a stale click on buttons that are gone
        switch code {
        case 2000: shopStep(-10); case 2001: shopStep(-1); case 2002: shopStep(1); case 2003: shopStep(10); case 2004: shopStep(nil)
        default: if case .shop(_, _, .some) = screen { press(1) }
        }
    }
    /// Bag items that would do something for ours right now.
    /// The bag in a fight: what would do something for any of ours (the one out, the bench, a fainted one's revive: 3.6).
    func battleItems(_ b: Battle) -> [(name: String, use: ItemUse)] {
        state.inventory.compactMap { i in Walker.battleUse(i).flatMap { u in itemTargets(b, u).isEmpty ? nil : (i, u) } }
    }
    /// The companion's 진화의 돌, now: the server evolves it; home shows it. (A trade evolution happens at a real trade now: 12 §3.)
    /// 3.7 (docs/plans/13 ⑤): a Pokémon that holds an item takes it along in a trade — said first, the player's yes.
    func holdsAlong(_ m: Mon?, _ verb: String) -> Bool {
        guard let m, let it = m.item else { return true }
        return host?.confirm(josa(monNames[m.dex], "은", "는") + " " + josa(it, "을", "를") + " 지니고 있어요", "교환되면 " + josa(it, "도", "도") + " 함께 가요.", ok: verb) ?? true
    }
    func evolveNow(_ e: Evo, back: Screen, _ now: Date = Date()) {
        act(.use(item: e.item ?? "", stat: nil), back: back, now) { _, _ in .home }
    }
    var seenList: [Int] { Array(Set((state.seen ?? []) + (state.owned ?? []))).sorted() }
    /// What walks on course k (the radar's, its guests, its legends): the 도감's 이 코스 tab, and 코스's 잡음 n/m.
    func courseSpecies(_ k: Int) -> [Int] { let c = courses[k]; return Set(c.slots.map(\.dex) + c.extra.map(\.dex) + c.guests + c.legends).sorted() }
    /// The 도감 grid's list for a tab: 전체 (1-493) / 잡음 / 못 잡음 (seen, not caught) / 이 코스 (what walks here, legends too).
    func dexList(_ f: Int) -> [Int] {
        let owned = Set(state.owned ?? []), c = state.here
        switch f {
        case 1: return owned.sorted()
        case 2: return seenList.filter { !owned.contains($0) }
        case 3: return courseSpecies(state.course)
        default: return Array(1...493)
        }
    }
    /// The box as the 상자 grid shows it (indices into state.box): 번호순 / 레벨순 / V순 / 최근 (the last to arrive first). Keys once per call
    /// (V counts aren't free), ties by level, then EXP (growth rates differ: EXP alone puts a slow Lv.8 over a fast Lv.10).
    var boxOrder: [Int] {
        let b = state.box
        if boxSort == 3 { return Array(b.indices.reversed()) }
        let k = b.map { m -> (Int, Int, Int, Int) in
            switch boxSort { case 1: (-m.level, -m.points, m.dex, 0); case 2: (-m.perfectIVs, -m.level, -m.points, m.dex); default: (m.dex, -m.level, -m.points, 0) }
        }
        return b.indices.sorted { k[$0] != k[$1] ? k[$0] < k[$1] : $0 < $1 }
    }
    /// The grids' pick moves d along its list: ◀ ▶ wrap around; rows (↑ ↓) and the wheel stop at the ends; a page step (the page buttons, page up / down,
    /// `ends`) past the last page goes to #1, before the first to the last one. The box's ● menu closes.
    func gridStep(_ d: Int, wrap: Bool = false, ends: Bool = false) {
        guard !frozen, waiting == nil else { return }
        func to(_ i: Int, _ n: Int) -> Int {
            let j = i + d, per = GridModel.perPage
            if wrap { return (j % n + n) % n }
            if ends, j >= n, i / per == (n - 1) / per { return 0 }
            if ends, j < 0, i / per == 0 { return n - 1 }
            return max(0, min(n - 1, j))
        }
        switch screen {
        case .dex(let n, let f, let detail):
            let l = dexList(f); guard !l.isEmpty else { return }
            screen = .dex(l[to(l.firstIndex(of: n) ?? 0, l.count)], filter: f, detail: detail)
        case .box(let i, _, _, let detail):                                                       // ◀ ▶: the companion, the walker's, then the box, round; rows and pages in the box
            let o = boxOrder, all = [-1] + state.caught.indices.map { -2 - $0 } + o, at = o.firstIndex(of: i)
            let next = wrap ? all[to(all.firstIndex(of: i) ?? 0, all.count)] : at == nil ? (o.isEmpty || d < 0 && !ends ? nil : abs(d) < GridModel.perPage ? o.first : o[to(0, o.count)]) : d < 0 && d > -GridModel.perPage && at! + d < 0 ? -1 : o[to(at!, o.count)]
            if let next { screen = .box(next, act: nil, confirm: false, detail: detail) }            // up from the box's top row: the companion
        default: return
        }
        lastInput = Date(); host?.redraw(.all)
    }

    /// A fight is on (its screens, a turn playing, or a message on the way back to one).
    var inBattle: Bool {
        func fight(_ s: Screen) -> Bool { switch s { case .battle, .moves, .party, .bagBattle, .forfeit, .beats: true; case .say(_, let n, _): fight(n); default: false } }
        return fight(screen)
    }
    /// The 메뉴 / 홈 key: true = it opens the menu (home), false = it goes home, nil = not now (a fight, a show, an answer due).
    func homeKey() -> Bool? {
        switch screen {
        case .home: true
        case .menu, .card, .items, .box, .dex, .shop, .shopConfirm, .tower, .course, .train, .relearn, .team, .trade, .raid, .market, .itemOn, .duel, .hold, .visitPick: false
        case .say(_, let next, _): switch next { case .home, .menu, .card, .items, .box, .dex, .shop, .shopConfirm, .tower, .course, .train, .relearn, .team, .trade, .raid, .market, .itemOn, .duel, .hold, .visitPick: false; default: nil }
        default: nil
        }
    }
    func press(_ k: Int) {                                    // 0 left, 1 enter, 2 right, 3 back (↩), 4 메뉴 / 홈
        if frozen { if k == 1 { lockPress() }; return }          // locked by the server (no ID, another PC has it, too old): ● is the lock's button, nothing else
        if waiting != nil { return }                             // an act's answer on the way: keys wait
        let now = Date(); lastInput = now; defer { settle(now); host?.redraw(.all) }               // back home: the news go on at once
        if k == 4 {                                           // one key both ways: home opens the menu (on the pane; the LCD stays home), anywhere else it goes home
            if let open = homeKey() { if !open { growthThen = nil }; screen = open ? .menu(0) : .home }   // home means home: the news still play there, then it stays
            return
        }
        if k == 3 {                                           // ↩ 뒤로 (HGSS's B): one step up; where an answer is due only the cursor moves to the way out — nothing that can't be undone happens
            switch screen {
            case .home, .beats, .radar, .evolve, .hatch, .traded: return                           // a turn plays out; the radar ends by itself (the W paid and the chain stay); shows aren't cancellable
            case .party(let b, _) where b.mustReplace: return                                       // someone has to come in
            case .say(_, let next, _): screen = next                                               // like ●
            case .menu: screen = .home
            case .card: screen = .menu(menuAt("트레이너 카드"))
            case .team(let s, let t, let card): screen = card ? .team(sel: s, tab: t, card: false) : .menu(menuAt("친구"))   // the card → the list → the menu
            case .trade(let s): screen = tradeBack(s)
            case .raid: screen = .menu(menuAt("레이드"))
            case .market(let s): screen = marketBack(s)
            case .itemOn(let p): screen = .items(state.inventory.firstIndex(of: p.item) ?? 0)
            case .duel: screen = .home                                                             // (the invitation stays open: its minute)
            case .hold(let r, _): screen = .box(r, act: nil, confirm: false, detail: true)
            case .visitPick(let p): screen = teamRows(0).firstIndex { trainerID($0.card.name)?.key == trainerID(p.item)?.key }.map { .team(sel: $0, tab: 0, card: true) } ?? .team(sel: 0, tab: 0, card: false)
            case .items: screen = .box(-1, act: nil, confirm: false)                                  // back to 포켓몬
            case .box(let i, let act, _, let detail): screen = act != nil ? .box(i, act: nil, confirm: false, detail: detail) : detail ? .box(i, act: nil, confirm: false) : .menu(menuAt("포켓몬"))   // 메뉴 / 놓아줄까? (= 아니오) → its page → the grid → the menu
            case .dex(let n, let f, let detail): screen = detail ? .dex(n, filter: f, detail: false) : .menu(menuAt("도감"))   // the entry page → the grid → the menu
            case .shop(let bp, let sel, .some), .shopConfirm(let bp, let sel, _): screen = .shop(bp: bp, sel: sel, qty: nil)
            case .shop(let bp, _, nil): screen = .menu(menuAt(bp ? "BP 교환소" : "상점"))
            case .course: screen = .menu(menuAt("코스"))
            case .train: screen = .items(state.inventory.firstIndex(of: "은색병뚜껑") ?? 0); trainRef = -1
            case .tower(let p): screen = p != nil ? .tower(pick: nil) : .menu(menuAt("배틀 타워"))                    // the picker → the lobby → the menu; a run stays on: ● in the lobby goes on
            case .learn: screen = .learn(sel: 4)                                                    // onto 배우지 않는다; ● decides
            case .relearn(let r, let s, let at): screen = at != nil ? .relearn(ref: r, slot: s, at: nil) : .box(r, act: nil, confirm: false, detail: true)   // the moves → the slots → its page
            case .moves(let b, _): screen = .battle(b, sel: battleMenu(b).firstIndex(of: "공격") ?? 0)   // back to where it came from
            case .party(let b, _) where itemFor != nil: screen = .bagBattle(b, sel: battleItems(b).firstIndex { $0.name == itemFor } ?? 0); itemFor = nil
            case .party(let b, _): screen = .battle(b, sel: battleMenu(b).firstIndex(of: "교체") ?? 0)
            case .bagBattle(let b, _): screen = .battle(b, sel: battleMenu(b).firstIndex(of: "도구") ?? 0)
            case .battle(let b, _): screen = .battle(b, sel: battleMenu(b).count - 1)                // onto 도망 / 기권 / 후퇴 (the last); ● decides (도망 by the Gen IV odds)
            case .forfeit(let b, _): screen = .battle(b, sel: battleMenu(b).firstIndex(of: "기권") ?? 0)
            }
            return
        }
        let n = menuItems.count
        switch screen {
        case .home: if k == 1 { emote = (1, now.addingTimeInterval(2)); animOn = ("home", state.companion.dex, now) }   // ● pats the companion (♥, its animation); the menu is the 메뉴 key's
        case .menu(let i):
            if k == 1 { open(i, now) } else { screen = .menu((i + (k == 0 ? n - 1 : 1)) % n) }       // ◀ ▶ go round the tiles
        case .radar(let b, let c, let since, let chain):
            if k != 1 { screen = .radar(bush: b, cursor: (c + (k == 0 ? 3 : 1)) % 4, since: since, chain: chain); return }
            pickBush(b, cursor: c, since: since, chain: chain, now)
        case .battle(let b, let sel):
            if duelWait { return }                                                                 // 12 §5: our pick is in — the other's is waited for
            let opts = battleMenu(b), n = opts.count
            if k == 0 { screen = .battle(b, sel: (sel + n - 1) % n); return }
            if k == 2 { screen = .battle(b, sel: (sel + 1) % n); return }
            if b.locked, !["공격", "기권"].contains(opts[sel]) { screen = .say([josa(b.nm(.me), "은", "는"), "기술을 쓰는 중이다!"], next: .battle(b, sel: 0), since: now); return }
            let back = Screen.battle(b, sel: sel)
            switch opts[sel] {
            case "공격":
                if b.forced != nil || b.usable(.me).isEmpty { turn(.fight(slot: 0), from: b, back: back, now) }   // nothing it may pick (발버둥) or locked into one: the server knows which
                else { screen = .moves(b, sel: 0) }
            case "교체": screen = b.switchBlock.map { .say([$0], next: .battle(b, sel: sel), since: now) } ?? .party(b, sel: b.me)
            case "기권": screen = .forfeit(b, yes: false)                                            // 정말? — 아니오 first
            case "도구": screen = battleItems(b).isEmpty ? .say(["지금 쓸 수 있는", "도구가 없다"], next: .battle(b, sel: sel), since: now) : .bagBattle(b, sel: 0)
            case "볼": turn(.ball, from: b, back: back, now)                                        // free: which ball it turns out to be is luck (and the chain): the server's
            default: turn(.run, from: b, back: back, now)
            }
        case .moves(let b, let sel):
            let x = b.mine[b.me], ms = x.moves, i = min(sel, ms.count - 1)
            if k == 0 { screen = .moves(b, sel: (sel + ms.count - 1) % ms.count) }
            else if k == 2 { screen = .moves(b, sel: (sel + 1) % ms.count) }
            else if x.pp[i] == 0 { screen = .say(["기술의 남은", "PP가 없다!"], next: .moves(b, sel: sel), since: now) }
            else if x.disable > 0, x.disabledMove == ms[i] { screen = .say(["사용할 수 없게", "되어 있다!"], next: .moves(b, sel: sel), since: now) }
            else if x.taunt > 0, moveTable[ms[i]]!.isStatus { screen = .say(["도발당해서", "쓸 수 없다!"], next: .moves(b, sel: sel), since: now) }
            else if x.torment, ms[i] == x.lastMove { screen = .say(["트집 때문에 같은", "기술은 못 쓴다!"], next: .moves(b, sel: sel), since: now) }
            else { turn(.fight(slot: i), from: b, back: .moves(b, sel: sel), now) }
        case .bagBattle(let b, let sel):
            let list = battleItems(b), n = max(1, list.count)
            if k == 0 { screen = .bagBattle(b, sel: (sel + n - 1) % n) }
            else if k == 2 { screen = .bagBattle(b, sel: (sel + 1) % n) }
            else if let it = list[safe: sel] {
                let to = itemTargets(b, it.use)
                if to == [b.me] { usedItem = it.name; turn(.item(name: it.name), from: b, back: .bagBattle(b, sel: sel), now) }   // only the one out: straight on
                else { itemFor = it.name; screen = .party(b, sel: to.first ?? b.me) }                  // the bench or a fainted one too: who? (3.6)
            }
            else { screen = .battle(b, sel: 0) }
        case .shop(let bp, let sel, let qty):
            let ws = wares(bp), n = max(1, ws.count)
            guard let w = ws[safe: sel] else { screen = .shop(bp: bp, sel: 0, qty: nil); return }
            if let q = qty {                                                                       // how many: ◀ ▶ one at a time (wrapping, like the games), ● buys
                let most = max(1, state.canBuy(w, bp: bp))
                if k == 0 { screen = .shop(bp: bp, sel: sel, qty: q > 1 ? q - 1 : most) }
                else if k == 2 { screen = .shop(bp: bp, sel: sel, qty: q < most ? q + 1 : 1) }
                else if w.once { screen = .shopConfirm(bp: bp, sel: sel, yes: false) }                 // 전설 · 기기 색: one more step, 아니오 first
                else { buyWare(w, q, bp: bp, sel: sel, now) }
            } else if k != 1 { let ids = shopRows(bp, shopTab(bp, sel)), m = max(1, ids.count), i = ids.firstIndex(of: sel) ?? 0; _ = n; screen = .shop(bp: bp, sel: ids[safe: (i + (k == 0 ? m - 1 : 1)) % m] ?? sel, qty: nil) }   // ◀ ▶ round its tab
            else if state.canBuy(w, bp: bp) > 0 { screen = .shop(bp: bp, sel: sel, qty: 1) }
            else { screen = .say(w.once && state.owned(w) > 0 ? ["이미 가지고 있다"] : [bp ? "BP가 부족하다" : "W가 부족하다"], next: .shop(bp: bp, sel: sel, qty: nil), since: now) }
        case .forfeit(let b, let yes):
            if k != 1 { screen = .forfeit(b, yes: !yes); return }
            guard yes else { screen = .battle(b, sel: battleMenu(b).firstIndex(of: "기권") ?? 0); return }
            if duelOn { duelPick(.forfeit, b, back: .battle(b, sel: 0), now); return }              // a live battle: giving up is this turn's pick
            act(.battle(cmd: .forfeit), back: .battle(b, sel: 0), now) { [weak self] o, now in
                self?.towerRun = false; self?.fight = nil
                return .say(["기권했다", "\(o.end?.streak ?? 0)연승에서 끝"], next: .home, since: now)
            }
        case .shopConfirm(let bp, let sel, let yes):
            if k != 1 { screen = .shopConfirm(bp: bp, sel: sel, yes: !yes); return }
            if yes, let w = wares(bp)[safe: sel] { buyWare(w, 1, bp: bp, sel: sel, now) } else { screen = .shop(bp: bp, sel: sel, qty: nil) }
        case .learn(let sel):
            guard let (ref, id) = state.nextToLearn(), let m = state.mon(ref) else { screen = .home; return }
            if k != 1 { screen = .learn(sel: (sel + (k == 0 ? 4 : 1)) % 5); return }
            let name = monNames[m.dex], new = moveTable[id]!.name, old = sel < 4 ? m.moves[safe: sel].map { moveTable[$0]!.name } : nil
            act(.mon(op: .learn(slot: sel == 4 ? nil : sel)), back: .learn(sel: sel), now) { _, now in
                old.map { .say(["1, 2, 짠!", josa($0, "을", "를") + " 잊고", josa(new, "을", "를") + " 배웠다!"], next: .home, since: now) }
                    ?? .say([josa(name, "은", "는") + " " + josa(new, "을", "를"), "배우지 않았다!"], next: .home, since: now)
            }
        case .party(let b, let sel):
            let n = b.mine.count
            if k == 0 { screen = .party(b, sel: (sel + n - 1) % n) }
            else if k == 2 { screen = .party(b, sel: (sel + 1) % n) }
            else if let it = itemFor {                                                               // whom the item goes to
                guard let u = Walker.battleUse(it), b.usable(u, on: sel) else { screen = .say(["이 포켓몬에게는", "쓸 수 없다"], next: .party(b, sel: sel), since: now); return }
                itemFor = nil; usedItem = it
                turn(.item(name: it, on: sel == b.me ? nil : sel), from: b, back: .bagBattle(b, sel: battleItems(b).firstIndex { $0.name == it } ?? 0), now)
            }
            else if !b.mine[sel].alive { screen = .say(["기절해서", "싸울 수 없다"], next: .party(b, sel: sel), since: now) }
            else if sel == b.me { screen = .say(["이미 싸우고 있다"], next: .party(b, sel: sel), since: now) }
            else { turn(b.mustReplace ? .replace(to: sel) : .swap(to: sel), from: b, back: .party(b, sel: sel), now) }
        case .course(let i):                                                                      // ◀ ▶ a course (round), ● walk it
            if k == 1 { goCourse(i) } else { screen = .course((i + (k == 0 ? courses.count - 1 : 1)) % courses.count) }
        case .train(let st):                                                                      // ◀ ▶ a stat (round), ● trains it
            if k == 1 { useCap(st, back: .train(st)) } else { screen = .train((st + (k == 0 ? 5 : 1)) % 6) }
        case .tower(let p?):                                                                      // the picker: ◀ ▶ a row (round), ● puts it in the slot
            let all = state.towerCandidates, sel = all.firstIndex(of: p.at) ?? 0
            if k == 1, let u = state.id(all[sel]) { act(.towerPick(slot: p.slot, uid: u), back: .tower(pick: nil), now) { _, _ in .tower(pick: nil) } }
            else if k != 1 { screen = .tower(pick: (p.slot, all[(sel + (k == 0 ? all.count - 1 : 1)) % all.count])) }
        case .tower:
            guard k == 1 else { return }
            towerNext(now)
        case .card(let p): screen = k == 1 ? .menu(menuAt("트레이너 카드")) : .card((p + (k == 0 ? 2 : 1)) % 3)
        case .team(let s, let t, let card):                                                      // ◀ ▶ a teammate (on a card: the next one's card), ● its card / 인사
            if k != 1 { teamStep(k == 0 ? -1 : 1); return }
            if t == 4, !card { if let r = friendReqRows[safe: s], !r.mine { friendReq(r, accept: true, now) } else if friendReqRows.isEmpty { askFriend(now) }; return }   // 신청: ● accepts (none: ID로 신청)
            if t == 5, !card { visitEnd(s, now); return }                                            // 맡기기: ● ends the pick's (데려오기 / 돌려보내기)
            guard let c = teamRows(t)[safe: s]?.card else { return }
            if !card { screen = .team(sel: s, tab: t, card: true) } else if !isMe(c), !visitorGreeted(c.name) { greet(c.name, back: screen) }
        case .trade(let s): tradePress(k, s, now)
        case .raid(let t): raidPress(k, t, now)
        case .market(let s): marketPress(k, s, now)
        case .itemOn(let p): itemOnPress(k, p, now)
        case .duel(let s): duelPress(k, s, now)
        case .hold(let r, let s): holdPress(k, r, s, now)
        case .visitPick(let p): visitPickPress(k, p, now)
        case .say(_, let next, _): screen = next
        case .dex(let n, let f, let detail):                                                     // ● = the entry page and back (not on an empty tab)
            if k == 1 { if dexList(f).contains(n) { screen = .dex(n, filter: f, detail: !detail) } } else { gridStep(k == 0 ? -1 : 1, wrap: true) }
        case .items(let sel):                                                                     // ◀ ▶ a row, ● its use
            let n = state.inventory.count
            guard n > 0 else { return }
            if k != 1 { screen = .items((min(sel, n - 1) + (k == 0 ? n - 1 : 1)) % n); return }
            let name = state.inventory[min(sel, n - 1)], back = { [weak self] (s: Int) in Screen.items(min(s, max(0, (self?.state.inventory.count ?? 1) - 1))) }
            let kind = ItemKind.of(name)
            if Walker.targeted(kind) { if itemUse(name).0 != nil { pickFor(name) } }                    // 3.6: who gets it first (docs/plans/13)
            else if case .sell = kind { useItem(name, back: back(sel), then: { back(sel) }, now) }
        case .box(let i, let act, let confirm, let detail):                                     // i: -1 the companion, -2-j the walker's j-th, else box[i]
            if state.mon(i) == nil { screen = .box(-1, act: nil, confirm: false) }                // gone meanwhile: back to the companion
            else if confirm {                                                                     // "놓아줄까?" 아니오 / 예
                if k != 1 { screen = .box(i, act: (act ?? 0) == 0 ? 1 : 0, confirm: true, detail: detail) }
                else if act == 1, let u = state.id(i) {
                    let p = boxOrder.firstIndex(of: i) ?? 0, name = monNames[state.box[i].dex]       // then the one after it in the grid
                    self.act(.mon(op: .release(uid: u)), back: .box(i, act: nil, confirm: false, detail: detail), now) { [weak self] o, now in
                        let ord = self?.boxOrder ?? []
                        return .say([josa(name, "은", "는") + " 풀숲으로", "돌아갔다 (+\(o.watts ?? 0)W)"], next: .box(ord.isEmpty ? -1 : ord[min(p, ord.count - 1)], act: nil, confirm: false, detail: detail && !ord.isEmpty), since: now)
                    }
                }
                else { screen = .box(i, act: nil, confirm: false, detail: detail) }
            } else if let a = act {                                                              // the ● menu: boxActs (함께 / 상자로 or 워커로 · 놓아주기 / 닫기)
                let acts = boxActs(i)
                if k != 1 { screen = .box(i, act: (a + (k == 0 ? acts.count - 1 : 1)) % max(1, acts.count), confirm: false, detail: detail); return }
                let here = Screen.box(i, act: nil, confirm: false, detail: detail)
                switch acts[safe: a] {
                case "함께"?: if let u = state.id(i) { pairWith(u, back: here, now) }
                case "상자로"?:                                                                    // the walker's: into the box, picked there
                    if let u = state.id(i) { let name = monNames[state.caught[-2 - i].dex]
                        self.act(.mon(op: .store(uid: u)), back: here, now) { [weak self] _, now in .say([josa(name, "을", "를"), "상자로 보냈다"], next: .box((self?.state.box.count ?? 1) - 1, act: nil, confirm: false), since: now) } }
                case "워커로"?:                                                                    // the box's: onto the walker, picked there
                    if let u = state.id(i) { let name = monNames[state.box[i].dex]
                        self.act(.mon(op: .fetch(uid: u)), back: here, now) { [weak self] _, now in .say([josa(name, "을", "를"), "워커로 데려왔다"], next: .box(-1 - (self?.state.caught.count ?? 1), act: nil, confirm: false), since: now) } }
                case "놓아주기"?: screen = .box(i, act: 0, confirm: true, detail: detail)
                default: screen = here
                }
            } else if k == 1, detail, i == -1 { if let e = companionEvolution() { evolveNow(e, back: screen, now) } else { screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷고 있다"], next: screen, since: now) } }
            else if k == 1 { screen = .box(i, act: detail ? 0 : nil, confirm: false, detail: true) }   // ● on the grid: its page; on its page: 함께 / 상자로 or 놓아주기 / 닫기
            else { gridStep(k == 0 ? -1 : 1, wrap: true) }
        case .relearn(let r, let s, let at):                                                     // the slots: ◀ ▶ one (round), ● what goes there; then ◀ ▶ a move, ● puts it in
            guard let m = state.mon(r) else { screen = .box(-1, act: nil, confirm: false); return }
            let all = m.relearnable
            guard let at else {
                let n = min(4, m.moves.count + 1)
                if k != 1 { screen = .relearn(ref: r, slot: (s + (k == 0 ? n - 1 : 1)) % n, at: nil); return }
                screen = .relearn(ref: r, slot: s, at: m.moves[safe: s] ?? all.first { !m.moves.contains($0) } ?? all[0]); return
            }
            let i = all.firstIndex(of: at) ?? 0
            if k != 1 { screen = .relearn(ref: r, slot: s, at: all[(i + (k == 0 ? all.count - 1 : 1)) % all.count]); return }
            let id = all[i], old = m.moves[safe: s], knew = m.moves.contains(id), back = Screen.relearn(ref: r, slot: s, at: nil), new = moveTable[id]!.name
            guard let u = state.id(r) else { return }
            act(.mon(op: .move(uid: u, slot: s, move: id)), back: back, now) { _, now in
                knew ? back                                                                       // one of its own: two swapped places (or nothing changed)
                    : old.map { .say(["1, 2, 짠!", josa(moveTable[$0]!.name, "을", "를") + " 잊고", josa(new, "을", "를") + " 배웠다!"], next: back, since: now) }
                    ?? .say([josa(monNames[m.dex], "은", "는") + " 새로", josa(new, "을", "를") + " 배웠다!"], next: back, since: now)
            }
        case .beats, .evolve, .hatch, .traded: break
        }
    }
    func open(_ i: Int, _ now: Date) {
        switch menuItems[i] {
        case "포켓 레이더": openRadar(back: .menu(i), now)                                            // the server's find (docs/plans/11 §3.2)
        case "코스": screen = .course(state.course)
        case "트레이너 카드": screen = .card(0)
        case "포켓몬": screen = .box(-1, act: nil, confirm: false)                                  // the companion first
        case "상점", "BP 교환소": screen = .shop(bp: menuItems[i] == "BP 교환소", sel: 0, qty: nil)
        case "배틀 타워": screen = .tower(pick: nil)
        case "친구":
            guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: .menu(i), since: now); return }
            c.wantTeam(now); screen = .team(sel: 0, tab: 0, card: false)
        case "교환":
            guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: .menu(i), since: now); return }
            c.marketDue = true; screen = .market(.board(tab: 0, sel: 0))
        case "레이드":
            guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: .menu(i), since: now); return }
            c.raidDue = true; screen = .raid(tab: 0)
        default: screen = .dex(state.companion.dex, filter: 0, detail: false)
        }
    }

    /// A click on the LCD: it's the screen to look at — the pane's page and the keys are what you press. Only a message goes on (as ● would).
    /// Returns false where the click drags the device instead.
    func touch(_ x: Int, _ y: Int) -> Bool {
        if frozen || waiting != nil { return true }
        if case .say = screen { press(1); return true }
        if case .home = screen, visitorTouched(x, y) || guestTouched(x, y) { return true }       // a friend's companion dropped by, or one I'm raising: 인사
        guard let k = stickerAt(x, y) else { return false }                                        // the LCD is to look at, but for the walker's stickers on home:
        lastInput = Date()
        if let u = state.id(-2 - k) { pairWith(u, back: screen, Date(), quietly: true) }          // a tap = walk with that one
        host?.redraw(.all); return true
    }
    /// 함께: that one walks with us (the server swaps it in); a line on the LCD, or (a sticker's tap) just its ♥.
    func pairWith(_ uid: Int, back: Screen, _ now: Date, quietly: Bool = false, next: Screen = .home) {
        act(.mon(op: .pair(uid: uid)), back: back, now) { [weak self] _, now in
            guard let self else { return nil }
            if quietly { emote = (1, now.addingTimeInterval(2)); animOn = ("home", state.companion.dex, now); return back }
            return .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: next, since: now)
        }
    }
    // MARK: 포켓몬's grid: a Pokémon dragged between the walker's row and the box (the platform's mouse: press, move, release)
    /// A press on `code` can drag: one of the walker's or the box's on the grid (the companion stays: it moves by 함께).
    func dragsFrom(_ code: Int) -> Bool {
        guard case .box(_, nil, false, false) = screen, waiting == nil, !frozen else { return false }
        if (4501...4503).contains(code) { return state.mon(-1 - (code - 4500)) != nil }
        return code >= 10000 && boxOrder.indices.contains(code - 10000)
    }
    /// The one a press on `code` picks: its ref.
    func dragRef(_ code: Int) -> Int? { code >= 10000 ? boxOrder[safe: code - 10000] : (4500...4503).contains(code) ? -1 - (code - 4500) : nil }
    /// Whether a drag from `from` does something dropped on `to`: the companion takes the walker's or the box's; the walker's row takes the box's;
    /// the box takes the walker's.
    func canDrop(_ from: Int, _ to: Int) -> Bool {
        guard let r = dragRef(from) else { return false }
        switch to { case 4500: return r != -1; case 4501...4503: return r >= 0 && state.caught.count < 3; case 4520: return r <= -2; default: return false }   // (the walker holds 3)
    }
    /// Dropped on `to` (a page's drop; nil = nowhere): on the companion = 함께; a box one on the walker's row = 워커로; a walker's one on
    /// the box = 상자로 — the same acts as the buttons, their lines; anything else: back where it was.
    func gridDrop(_ from: Int, _ to: Int?) {
        drag = nil; host?.redraw(.all)
        guard let to, canDrop(from, to), let r = dragRef(from), let m = state.mon(r), let u = state.id(r) else { return }
        let now = Date(), grid = screen, name = monNames[m.dex]
        if to == 4500 { pairWith(u, back: grid, now, next: .box(-1, act: nil, confirm: false)); return }   // (the grid again, the new companion picked)
        if (4501...4503).contains(to) {
            act(.mon(op: .fetch(uid: u)), back: grid, now) { [weak self] _, now in .say([josa(name, "을", "를"), "워커로 데려왔다"], next: .box(-1 - (self?.state.caught.count ?? 1), act: nil, confirm: false), since: now) }
        } else {
            act(.mon(op: .store(uid: u)), back: grid, now) { [weak self] _, now in .say([josa(name, "을", "를"), "상자로 보냈다"], next: .box((self?.state.box.count ?? 1) - 1, act: nil, confirm: false), since: now) }
        }
    }
    /// The walker's stickers on home, in card points: where the hand shows over the LCD.
    var stickerRects: [CGRect] {
        switch screen { case .home, .menu: break; default: return [] }
        return (0..<min(3, state.caught.count)).map { k in CGRect(x: lcdRect.minX + CGFloat(2 + 15 * k) * PX, y: lcdRect.minY + 43 * PX, width: 17 * PX, height: 21 * PX) }
    }
    /// Which of the walker's stickers home shows at LCD dot (x, y) (the menu keeps home on the LCD too), nil = none.
    func stickerAt(_ x: Int, _ y: Int) -> Int? {
        switch screen { case .home, .menu: break; default: return nil }
        guard y >= 43 else { return nil }
        return (0..<min(3, state.caught.count)).first { (2 + 15 * $0)..<(19 + 15 * $0) ~= x }    // as Notebook draws them: 30 half-dots apart, 34 wide, along the bottom
    }

    // MARK: the menu's actions (the menu: Core/Menu.swift) and the bag's
    /// 코스: walk course i (if it's open and not the one already walked): its progress starts over.
    func goCourse(_ i: Int) {
        guard state.unlocked(i), i != state.course else { host?.beep(); return }
        act(.course(index: i), back: .course(i)) { [weak self] _, now in .say([josa(self?.state.here.name ?? "", "으로", "로"), "출발!"], next: .home, since: now) }
    }
    /// A bag item's use (the server's): a line for what it did, then `then` (the bag where it was, or home); an evolution plays at home.
    func useItem(_ name: String, on ref: Int = -1, back: Screen, then: @escaping @MainActor () -> Screen = { .home }, _ now: Date = Date()) {
        let target = state.mon(ref) ?? state.companion, me = monNames[target.dex], kind = ItemKind.of(name), uid = ref == -1 ? nil : target.uid
        let quiet: Bool = { if case .candy = kind { return true }; return false }()
        act(.use(item: name, stat: nil, on: uid), back: back, now, quiet: quiet) { [weak self] o, now in
            guard let self else { return nil }
            let after = (uid.flatMap { u in self.state.ref(uid: u) }.flatMap { self.state.mon($0) }) ?? (ref == -1 ? self.state.companion : target)
            switch kind {
            case .candy: return .say([me + " Lv.\(after.level)!"], next: then(), since: now)              // an evolution shows back home (its news)
            case .mint(let k): return .say([josa(me, "은", "는") + " " + josa(name, "을", "를"), "먹었다!", "능력치가 " + natures[k].name + " 성격처럼"], next: then(), since: now)
            case .vitamin(let k, _): return .say([josa(me, "은", "는") + " " + josa(name, "을", "를"), "먹었다!", "노력치 \((after.evs ?? [])[safe: k] ?? 0)"], next: then(), since: now)
            case .evReset: return .say([josa(me, "은", "는") + " 순백떡을", "먹었다!", "노력치가 0이 되었다"], next: then(), since: now)
            case .berry: return .say([josa(me, "이", "가") + " " + josa(name, "을", "를"), "맛있게 먹었다!"], next: then(), since: now)
            case .sell: return .say([name + " 판매", "+\(o.watts ?? 0)W"], next: then(), since: now)
            default: return .home                                                                   // 진화의 돌: home shows it
            }
        }
    }
    func useCandy() { useItem("이상한사탕", back: .home) }
    func useVitamin(_ v: String) { useItem(v, back: .home) }
    func useReset() { useItem("순백떡", back: .home) }
    func useBerry(_ b: String) { useItem(b, back: .home) }
    func sellOne(_ n: String) { useItem(n, back: .home) }
    /// 대단한 특훈: one stat (은색병뚜껑), nil = all (금색병뚜껑).
    func useCap(_ stat: Int?, back: Screen = .home) {
        let target = state.mon(trainRef) ?? state.companion, uid = trainRef == -1 ? nil : target.uid
        let name = monNames[target.dex], what = stat.map { ["HP", "공격", "방어", "특공", "특방", "스피드"][$0] } ?? "모든 능력"
        act(.use(item: stat == nil ? "금색병뚜껑" : "은색병뚜껑", stat: stat, on: uid), back: back) { [weak self] _, now in
            guard let self else { return nil }
            let left = state.inventory.firstIndex(of: "은색병뚜껑"), after = uid.flatMap { u in self.state.ref(uid: u) }.flatMap { self.state.mon($0) } ?? self.state.companion
            return .say(["대단한 특훈!", josa(name, "의", "의") + " " + what, "최고가 되었다! (\(after.perfectIVs)V)"], next: stat == nil ? back : .items(left ?? 0), since: now)
        }
    }
    func sellAll(back: Screen = .home) { act(.sellAll, back: back) { o, now in .say(["전부 팔았다", "+\(o.watts ?? 0)W"], next: back, since: now) } }
    func useStone(_ i: Int) { let s = state.stoneEvolutions(Date()); guard s.indices.contains(i) else { return }; evolveNow(s[i], back: .home) }
    /// 중복 놓아주기, once the platform has asked: the box's spare ones of that species go.
    func releaseDupes(_ dex: Int) {
        let n = state.duplicates(of: dex).count
        act(.mon(op: .releaseDupes(dex: dex)), back: .box(-1, act: nil, confirm: false)) { o, now in .say(["\(n)마리를 놓아줬다", "+\(o.watts ?? 0)W"], next: .box(-1, act: nil, confirm: false), since: now) }   // back to the grid
    }
}
