import AppKit
import UserNotifications
// What the buttons and taps do on each screen, and how a fight ends.

extension WalkerView {
    /// End of a fight. Wild: EXP goes to the companion; caught or beaten => maybe the grass rustles again (a chain). Tower: BP and the next trainer.
    func after(_ b: Battle, _ end: Beat, _ now: Date) -> Screen {
        if end == .lost, let r = state.useRevive() {                                              // a revive in the bag: back up, the fight goes on
            var nb = b; let hp = max(1, nb.mine[nb.me].maxHP * r.pct / 100); usedItem = r.item
            nb.mine[nb.me].status = nil; nb.mine[nb.me].down = false; nb.over = false
            let from = nb, beat = Beat.heal(.me, amount: hp, text: josa(r.item, "으로", "로") + " 되살아났다!")
            nb.apply(beat)                                                                         // the fight goes on from the revived HP
            return .beats(nb, [beat], since: now, from: from)
        }
        let before = state.companion.level
        state.writeBack(b.trainer != nil ? towerRefs : [state.id(-1)!], b.mine.map(\.mon))
        if state.companion.level > before { levelled = true }                                     // the home screen then checks evolutions
        if b.trainer != nil {
            if end == .won { let g = state.towerWin(); return .say(["\(state.towerStreak ?? 0)연승!", "+\(g) BP"], next: .tower, since: now) }
            let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false
            return .say(["\(s)연승에서 끝났다", "BP \(state.bp ?? 0)"], next: .home, since: now)
        }
        switch end {
        case .caught, .won:
            if end == .caught { _ = state.keep(b.wild) }
            guard Double.random(in: 0..<1, using: &rng) < Walk.chainGoesOn(b.chain) else {
                return .say(b.chain > 0 ? ["풀숲이 조용해졌다", "연쇄 \(b.chain)에서 끝"] : ["풀숲이", "조용해졌다"], next: .home, since: now)
            }
            let n = b.chain + 1, item = state.chainReward(n)
            chainNote = "+\(2 * n)W" + (item.map { " · " + $0 } ?? "")
            return .radar(bush: Int.random(in: 0..<4, using: &rng), cursor: 0, since: now, chain: n)
        default: return .home
        }
    }
    func startTower(_ now: Date) {
        towerRefs = state.party().map { state.id($0.ref)! }; let p = state.party()                  // uids first, so the fighters carry them
        let f = state.towerFoes(&rng); var b = Battle(party: p.map(\.mon), trainer: f.trainer, foes: f.foes)
        let from = b, beats = b.begin(weather: nil, &rng)
        towerRun = true; screen = .beats(b, beats, since: now, from: from)
    }
    func radarWindow(_ chain: Int) -> Double { max(0.8, 2.0 - 0.25 * Double(chain)) }
    func notify(_ kind: String, _ title: String, _ body: String) {
        guard persist, notifyOn(kind) else { return }
        if useOsascript {                                                                        // shows as "스크립트 편집기" in Notification Center
            func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "display notification \(q(body)) with title \(q("PokeWalker")) subtitle \(q(title))"]
            try? p.run(); return
        }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    @objc func save(_ sender: Any?) { guard persist else { return }; Store.save(state); lastSave = Date() }
    /// The next move waiting in state.learning: straight in with a free slot, else the forget-one screen.
    func nextLearn(_ now: Date) {
        while let (ref, id) = state.nextToLearn() {
            let ls = learnsets[state.mon(ref)?.dex ?? 0]
            guard var m = state.mon(ref), !m.moves.contains(id), stride(from: 1, to: ls.count, by: 2).contains(where: { ls[$0] == id }) else { state.learned(); continue }
            if m.moves.count < 4 {
                m.known = m.moves + [id]; state.setMon(ref, m); state.learned()
                screen = .say([josa(monNames[m.dex], "은", "는") + " 새로", josa(moveTable[id]!.name, "을", "를") + " 배웠다!"], next: .home, since: now); return
            }
            screen = .learn(sel: 0); return
        }
    }
    /// The 상점's (bp false) or BP 교환소's rows.
    func wares(_ bp: Bool) -> [Walk.Ware] { state.wares(bp: bp, shells: shells.filter { $0.bp > 0 }.map { (name: $0.name, bp: $0.bp) }) }
    /// Buys q of the row; a line to say, then back to the list.
    func buyWare(_ w: Walk.Ware, _ q: Int, bp: Bool, sel: Int, _ now: Date) {
        let back = Screen.shop(bp: bp, sel: sel, qty: nil), cost = "(-\(w.price * q)\(bp ? "BP" : "W"))"
        switch state.purchase(w, q, bp: bp) {
        case .items(let i, let n)?: screen = .say([josa(i, "을", "를") + (n > 1 ? " \(n)개" : ""), (bp ? "받았다! " : "샀다! ") + cost], next: back, since: now)
        case .legend(let m)?:
            screen = .say(["전설의 " + monNames[m.dex] + "!", "Lv.\(m.level) · 워커에 왔다"], next: back, since: now)
            notify("unlock", "전설의 \(monNames[m.dex])", "Lv.\(m.level)이 워커에 왔어요")
        case .shell(let s)?:
            if let t = shells.firstIndex(where: { $0.name == s }) { theme = t; if persist { UserDefaults.standard.set(t, forKey: "shell") } }   // wear it straight away
            screen = .say(["기기 색", s + " 획득!"], next: back, since: now)
        case nil: screen = .say([bp ? "BP가 부족하다" : "W가 부족하다"], next: back, since: now); return
        }
        save(nil)
    }
    /// ↑ ↓ keys and the panel's buttons: in the list a row up / down, in how-many ±n (clamped, not wrapping); `nil` = as many as can be bought.
    func shopStep(_ d: Int?) {
        guard case .shop(let bp, let sel, let qty) = screen else { return }
        lastInput = Date(); shown = nil; needsDisplay = true
        let ws = wares(bp); guard let w = ws[safe: sel] else { return }
        let most = state.canBuy(w, bp: bp)
        if let q = qty { screen = .shop(bp: bp, sel: sel, qty: d.map { max(1, min(max(1, most), q + $0)) } ?? max(1, most)) }
        else if let d { screen = .shop(bp: bp, sel: max(0, min(ws.count - 1, sel + d.signum())), qty: nil) }
    }
    /// The scroll wheel / trackpad on the shop panel: a row up or down, leaving how-many (the amount only changes on purpose).
    func shopRow(_ d: Int) {
        let bp: Bool, sel: Int
        switch screen { case .shop(let b, let s, _), .shopConfirm(let b, let s, _): bp = b; sel = s; default: return }
        lastInput = Date(); shown = nil; needsDisplay = true
        screen = .shop(bp: bp, sel: max(0, min(wares(bp).count - 1, sel + d)), qty: nil)
    }
    /// A click on the shop panel: 2100 + k = row k (and how-many, if it can be bought), 2000-2004 = −10 −1 +1 +10 max, 2005 = buy, 2006 / 2007 = 예 / 아니오.
    func shopTap(_ code: Int) {
        throughSay()
        if case .shopConfirm(let bp, let sel, _) = screen {
            if code == 2006 { screen = .shopConfirm(bp: bp, sel: sel, yes: true); press(1) }
            else if code == 2007 { screen = .shop(bp: bp, sel: sel, qty: nil) }
            else if code >= 2100 { screen = .shop(bp: bp, sel: sel, qty: nil); shopTap(code) }
            return
        }
        guard case .shop(let bp, _, let qty) = screen else { return }
        lastInput = Date(); shown = nil; needsDisplay = true
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
    func battleItems(_ b: Battle) -> [(name: String, use: ItemUse)] {
        state.inventory.compactMap { i in
            let u: ItemUse? = switch ItemKind.of(i) { case .heal(let n): .heal(n); case .battle(let u): u; default: nil }
            return u.flatMap { b.usable($0) ? (i, $0) : nil }
        }
    }
    func startEvolving(_ e: Evo, _ now: Date) { let from = state.companion; state.evolve(e); screen = .evolve(from: from, to: state.companion, since: now); save(nil) }
    var seenList: [Int] { Array(Set((state.seen ?? []) + (state.owned ?? []))).sorted() }
    /// The 도감 grid's list for a tab: 전체 (1-493) / 잡음 / 못 잡음 (seen, not caught) / 이 코스 (what walks here, legends too).
    func dexList(_ f: Int) -> [Int] {
        let owned = Set(state.owned ?? []), c = state.here
        switch f {
        case 1: return owned.sorted()
        case 2: return seenList.filter { !owned.contains($0) }
        case 3: return Set(c.slots.map(\.dex) + c.extra.map(\.dex) + c.guests + c.legends).sorted()
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
            let next = wrap ? all[to(all.firstIndex(of: i) ?? 0, all.count)] : at == nil ? (d > 0 ? o.first : nil) : d < 0 && d > -GridModel.perPage && at! + d < 0 ? -1 : o[to(at!, o.count)]
            if let next { screen = .box(next, act: nil, confirm: false, detail: detail) }            // up from the box's top row: the companion
        default: return
        }
        lastInput = Date(); shown = nil; needsDisplay = true
    }

    /// The 메뉴 / 홈 key: true = it opens the menu (home), false = it goes home, nil = not now (a fight, a show, an answer due).
    func homeKey() -> Bool? {
        switch screen {
        case .home: true
        case .menu, .card, .items, .box, .dex, .shop, .shopConfirm, .tower: false
        case .say(_, let next, _): switch next { case .home, .menu, .card, .items, .box, .dex, .shop, .shopConfirm, .tower: false; default: nil }
        default: nil
        }
    }
    func press(_ k: Int) {                                    // 0 left, 1 enter, 2 right, 3 back (↩), 4 메뉴 / 홈
        let now = Date(); lastInput = now; defer { save(nil); shown = nil; needsDisplay = true }
        if k == 4 {                                           // one key both ways: home opens the menu (on the pane; the LCD stays home), anywhere else it goes home
            if let open = homeKey() { screen = open ? .menu(0) : .home }
            return
        }
        if k == 3 {                                           // ↩ 뒤로 (HGSS's B): one step up; where an answer is due only the cursor moves to the way out — nothing that can't be undone happens
            switch screen {
            case .home, .beats, .radar, .evolve, .hatch: return                                    // a turn plays out; the radar ends by itself (the W paid and the chain stay); shows aren't cancellable
            case .party(let b, _) where b.mustReplace: return                                       // someone has to come in
            case .say(_, let next, _): screen = next                                               // like ●
            case .menu: screen = .home
            case .card: screen = .menu(menuAt("트레이너 카드"))
            case .items: screen = .box(-1, act: nil, confirm: false)                                  // back to 포켓몬
            case .box(let i, let act, _, let detail): screen = act != nil ? .box(i, act: nil, confirm: false, detail: detail) : detail ? .box(i, act: nil, confirm: false) : .menu(menuAt("포켓몬"))   // 메뉴 / 놓아줄까? (= 아니오) → its page → the grid → the menu
            case .dex(let n, let f, let detail): screen = detail ? .dex(n, filter: f, detail: false) : .menu(menuAt("도감"))   // the entry page → the grid → the menu
            case .shop(let bp, let sel, .some), .shopConfirm(let bp, let sel, _): screen = .shop(bp: bp, sel: sel, qty: nil)
            case .shop(let bp, _, nil): screen = .menu(menuAt(bp ? "BP 교환소" : "상점"))
            case .tower: screen = .menu(menuAt("배틀 타워"))                                                          // a run stays on: ● in the lobby goes on
            case .learn: screen = .learn(sel: 4)                                                    // onto 배우지 않는다; ● decides
            case .moves(let b, _): screen = .battle(b, sel: battleMenu(b).firstIndex(of: "공격") ?? 0)   // back to where it came from
            case .party(let b, _): screen = .battle(b, sel: battleMenu(b).firstIndex(of: "교체") ?? 0)
            case .bagBattle(let b, _): screen = .battle(b, sel: battleMenu(b).firstIndex(of: "도구") ?? 0)
            case .battle(let b, _): screen = .battle(b, sel: battleMenu(b).firstIndex(of: b.trainer == nil ? "도망" : "기권") ?? 0)   // onto 도망 / 기권; ● decides (도망 by the Gen IV odds)
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
            let u = now.timeIntervalSince(since)
            if c == b, u >= 1.5 {
                let s = state.encounter(&rng, chain: chain), l = state.legend(&rng, chain: chain)
                var m = Mon.wild(l ?? s.dex, level: l == nil ? s.level : l == 493 ? 80 : 50, shiny: Int.random(in: 0..<Walk.chainShinyOdds(chain), using: &rng) == 0 ? true : nil,
                                 perfect: max(l == nil ? 0 : 3, Walk.chainPerfectIVs(chain)), &rng)   // chains raise 이로치 odds and sure 31s; legends have 3
                if l == nil { m.female = s.female }                                                // the walker's slots fix the sex
                var b = Battle(wild: m, companion: state.companion, chain: chain); state.see(m.dex)
                let from = b, beats = b.begin(weather: state.weather, &rng); screen = .beats(b, beats, since: now, from: from)
            } else { screen = .say(chain > 0 ? ["빗나갔다...", "연쇄 끝 (\(chain))"] : ["아무것도", "없었다..."], next: .home, since: now) }
        case .battle(var b, let sel):
            let opts = battleMenu(b), n = opts.count
            if k == 0 { screen = .battle(b, sel: (sel + n - 1) % n); return }
            if k == 2 { screen = .battle(b, sel: (sel + 1) % n); return }
            let from = b
            if b.locked, !["공격", "기권"].contains(opts[sel]) { screen = .say([josa(b.nm(.me), "은", "는"), "기술을 쓰는 중이다!"], next: .battle(b, sel: 0), since: now); return }
            switch opts[sel] {
            case "공격":
                let stuck = b.forced ?? (b.usable(.me).isEmpty ? 165 : nil)                           // nothing it may pick: 발버둥
                if let id = stuck { let beats = b.turn(.fight(id), &rng); screen = .beats(b, beats, since: now, from: from) } else { screen = .moves(b, sel: 0) }
            case "교체": screen = b.switchBlock.map { .say([$0], next: .battle(b, sel: sel), since: now) } ?? .party(b, sel: b.me)
            case "기권": screen = .forfeit(b, yes: false)                                            // 정말? — 아니오 first
            case "도구": screen = battleItems(b).isEmpty ? .say(["지금 쓸 수 있는", "도구가 없다"], next: .battle(b, sel: sel), since: now) : .bagBattle(b, sel: 0)
            case "볼":
                var boost = 1.0; usedItem = "몬스터볼"
                if let x = state.useBall() { boost = x.boost; usedItem = x.item }
                let beats = b.turn(.capture, &rng, ball: boost); screen = .beats(b, beats, since: now, from: from)
            default: let beats = b.turn(.run, &rng); screen = .beats(b, beats, since: now, from: from)
            }
        case .moves(var b, let sel):
            let x = b.mine[b.me], ms = x.moves, i = min(sel, ms.count - 1)
            if k == 0 { screen = .moves(b, sel: (sel + ms.count - 1) % ms.count) }
            else if k == 2 { screen = .moves(b, sel: (sel + 1) % ms.count) }
            else if x.pp[i] == 0 { screen = .say(["기술의 남은", "PP가 없다!"], next: .moves(b, sel: sel), since: now) }
            else if x.disable > 0, x.disabledMove == ms[i] { screen = .say(["사용할 수 없게", "되어 있다!"], next: .moves(b, sel: sel), since: now) }
            else if x.taunt > 0, moveTable[ms[i]]!.isStatus { screen = .say(["도발당해서", "쓸 수 없다!"], next: .moves(b, sel: sel), since: now) }
            else if x.torment, ms[i] == x.lastMove { screen = .say(["트집 때문에 같은", "기술은 못 쓴다!"], next: .moves(b, sel: sel), since: now) }
            else { let from = b; let beats = b.turn(.fight(ms[i]), &rng); screen = .beats(b, beats, since: now, from: from) }
        case .bagBattle(var b, let sel):
            let list = battleItems(b), n = max(1, list.count)
            if k == 0 { screen = .bagBattle(b, sel: (sel + n - 1) % n) }
            else if k == 2 { screen = .bagBattle(b, sel: (sel + 1) % n) }
            else if let it = list[safe: sel], state.take(it.name) {
                usedItem = it.name
                let from = b; let beats = b.turn(.item(it.use), &rng)
                screen = .beats(b, [.note(.me, text: josa(it.name, "을", "를") + " 사용했다!")] + beats, since: now, from: from)
            } else { screen = .battle(b, sel: 0) }
        case .shop(let bp, let sel, let qty):
            let ws = wares(bp), n = max(1, ws.count)
            guard let w = ws[safe: sel] else { screen = .shop(bp: bp, sel: 0, qty: nil); return }
            if let q = qty {                                                                       // how many: ◀ ▶ one at a time (wrapping, like the games), ● buys
                let most = max(1, state.canBuy(w, bp: bp))
                if k == 0 { screen = .shop(bp: bp, sel: sel, qty: q > 1 ? q - 1 : most) }
                else if k == 2 { screen = .shop(bp: bp, sel: sel, qty: q < most ? q + 1 : 1) }
                else if w.once { screen = .shopConfirm(bp: bp, sel: sel, yes: false) }                 // 전설 · 기기 색: one more step, 아니오 first
                else { buyWare(w, q, bp: bp, sel: sel, now) }
            } else if k == 0 { screen = .shop(bp: bp, sel: (sel + n - 1) % n, qty: nil) }
            else if k == 2 { screen = .shop(bp: bp, sel: (sel + 1) % n, qty: nil) }
            else if state.canBuy(w, bp: bp) > 0 { screen = .shop(bp: bp, sel: sel, qty: 1) }
            else { screen = .say(w.once && state.owned(w) > 0 ? ["이미 가지고 있다"] : [bp ? "BP가 부족하다" : "W가 부족하다"], next: .shop(bp: bp, sel: sel, qty: nil), since: now) }
        case .forfeit(let b, let yes):
            if k != 1 { screen = .forfeit(b, yes: !yes); return }
            if yes { let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false; screen = .say(["기권했다", "\(s)연승에서 끝"], next: .home, since: now) }
            else { screen = .battle(b, sel: battleMenu(b).firstIndex(of: "기권") ?? 0) }
        case .shopConfirm(let bp, let sel, let yes):
            if k != 1 { screen = .shopConfirm(bp: bp, sel: sel, yes: !yes); return }
            if yes, let w = wares(bp)[safe: sel] { buyWare(w, 1, bp: bp, sel: sel, now) } else { screen = .shop(bp: bp, sel: sel, qty: nil) }
        case .learn(let sel):
            guard let (ref, id) = state.nextToLearn(), var m = state.mon(ref) else { screen = .home; return }
            if k != 1 { screen = .learn(sel: (sel + (k == 0 ? 4 : 1)) % 5); return }
            let name = monNames[m.dex], new = moveTable[id]!.name
            state.learned()
            if sel == 4 { screen = .say([josa(name, "은", "는") + " " + josa(new, "을", "를"), "배우지 않았다!"], next: .home, since: now) }
            else {
                var ms = m.moves; let old = moveTable[ms[sel]]!.name; ms[sel] = id; m.known = ms; state.setMon(ref, m)
                screen = .say(["1, 2, 짠!", josa(old, "을", "를") + " 잊고", josa(new, "을", "를") + " 배웠다!"], next: .home, since: now)
            }
        case .party(var b, let sel):
            let n = b.mine.count
            if k == 0 { screen = .party(b, sel: (sel + n - 1) % n) }
            else if k == 2 { screen = .party(b, sel: (sel + 1) % n) }
            else if sel == b.me { screen = .say(["이미 싸우고 있다"], next: .party(b, sel: sel), since: now) }
            else if !b.mine[sel].alive { screen = .say(["기절해서", "싸울 수 없다"], next: .party(b, sel: sel), since: now) }
            else { let from = b; let beats = b.mustReplace ? b.replace(sel) : b.turn(.swap(sel), &rng); screen = .beats(b, beats, since: now, from: from) }
        case .tower:
            guard k == 1 else { return }
            if towerRun { startTower(now) }
            else if state.spend(Walk.towerFee) { state.towerStreak = 0; startTower(now) }
            else { screen = .say(["W가 부족하다", "(\(Walk.towerFee)W 필요)"], next: .tower, since: now) }
        case .card(let p): screen = k == 1 ? .menu(menuAt("트레이너 카드")) : .card((p + (k == 0 ? 2 : 1)) % 3)
        case .say(_, let next, _): screen = next
        case .dex(let n, let f, let detail):                                                     // ● = the entry page and back (not on an empty tab)
            if k == 1 { if dexList(f).contains(n) { screen = .dex(n, filter: f, detail: !detail) } } else { gridStep(k == 0 ? -1 : 1, wrap: true) }
        case .items: break
        case .box(let i, let act, let confirm, let detail):                                     // i: -1 the companion, -2-j the walker's j-th, else box[i]
            if state.mon(i) == nil { screen = .box(-1, act: nil, confirm: false) }                // gone meanwhile: back to the companion
            else if confirm {                                                                     // "놓아줄까?" 아니오 / 예
                if k != 1 { screen = .box(i, act: (act ?? 0) == 0 ? 1 : 0, confirm: true, detail: detail) }
                else if act == 1 {
                    let p = boxOrder.firstIndex(of: i) ?? 0, name = monNames[state.box[i].dex], w = state.release(i), o = boxOrder   // then the one after it in the grid
                    screen = .say([josa(name, "은", "는") + " 풀숲으로", "돌아갔다 (+\(w)W)"], next: .box(o.isEmpty ? 0 : o[min(p, o.count - 1)], act: nil, confirm: false, detail: detail && !o.isEmpty), since: now)
                }
                else { screen = .box(i, act: nil, confirm: false, detail: detail) }
            } else if let a = act {                                                              // 함께 걷기 / 놓아주기 / 닫기 (the order: the grid's tabs)
                if k != 1 { screen = .box(i, act: (a + (k == 0 ? 2 : 1)) % 3, confirm: false, detail: detail); return }
                switch a {
                case 0 where i != -1: if i < -1 { state.pair(-2 - i, onWalker: true) } else { state.pair(i) }; screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: .home, since: now)
                case 1 where i < -1: let name = monNames[state.caught[-2 - i].dex]; state.store(-2 - i)   // the walker's: into the box, picked there
                    screen = .say([josa(name, "을", "를"), "상자로 보냈다"], next: .box(state.box.count - 1, act: nil, confirm: false), since: now)
                case 1: screen = .box(i, act: 0, confirm: true, detail: detail)
                default: screen = .box(i, act: nil, confirm: false, detail: detail)
                }
            } else if k == 1, detail, i == -1 { screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷고 있다"], next: screen, since: now) }
            else if k == 1 { screen = .box(i, act: detail ? 0 : nil, confirm: false, detail: true) }   // ● on the grid: its page; on its page: 함께 / 상자로 or 놓아주기 / 닫기
            else { gridStep(k == 0 ? -1 : 1, wrap: true) }
        case .beats, .evolve, .hatch: break
        }
    }
    func open(_ i: Int, _ now: Date) {
        switch menuItems[i] {
        case "포켓 레이더": screen = state.spend(10) ? .radar(bush: Int.random(in: 0..<4, using: &rng), cursor: 0, since: now, chain: 0) : .say(["W가 부족하다", "(10W 필요)"], next: .menu(i), since: now)
        case "커넥트":
            let n = state.caught.count + state.items.count
            state.connect()
            if let e = state.tradeEvolution(now) { startEvolving(e, now); return }                 // Connect is the walker's link cable
            screen = .say(n == 0 ? ["보낼 것이", "없다"] : ["상자로", "\(n)개 보냈다"], next: .menu(i), since: now)
        case "트레이너 카드": screen = .card(0)
        case "포켓몬": screen = .box(-1, act: nil, confirm: false)                                  // the companion first
        case "상점", "BP 교환소": screen = .shop(bp: menuItems[i] == "BP 교환소", sel: 0, qty: nil)
        case "배틀 타워": screen = .tower
        default: screen = .dex(state.companion.dex, filter: 0, detail: false)
        }
    }

    /// A click on the LCD: it's the screen to look at — the pane's page and the keys are what you press. Only a message goes on (as ● would).
    /// Returns false where the click drags the device instead.
    func touch(_ x: Int, _ y: Int) -> Bool { if case .say = screen { press(1); return true }; return false }
}
