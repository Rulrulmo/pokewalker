import Foundation
// What the buttons and taps do on each screen, how a fight ends, and the menu's actions.

extension Walker {
    /// End of a fight. Wild: EXP goes to the companion; caught or beaten => maybe the grass rustles again (a chain). Tower: BP and the next trainer.
    /// What the fight brought (an evolution, a move to learn) plays first, from home (settle), then the lobby or the next bush (growthThen).
    func after(_ b: Battle, _ end: Beat, _ now: Date) -> Screen {
        if end == .lost, let r = state.useRevive() {                                              // a revive in the bag: back up, the fight goes on
            var nb = b; let hp = max(1, nb.mine[nb.me].maxHP * r.pct / 100); usedItem = r.item
            nb.mine[nb.me].clearVolatile(); nb.mine[nb.me].status = nil; nb.mine[nb.me].down = false; nb.over = false   // back up fresh: what felled it (저주, 씨뿌리기, 조이기 …) is gone
            let from = nb, beat = Beat.heal(.me, amount: hp, text: josa(r.item, "으로", "로") + " 되살아났다!")
            nb.apply(beat)                                                                         // the fight goes on from the revived HP
            var bs = [beat]
            if let n = nb.foeNext { nb.foeNext = nil; nb.out = []; nb.switchIn(.it, n); bs += nb.out }   // a trainer's one KO'd that same turn: its next comes out now
            return .beats(nb, bs, since: now, from: from)
        }
        if b.trainer == nil { writeBackFight(b) }                                                  // the tower's fight as Lv.50 copies, no EXP: nothing to write back (it would cut a Lv.70 to 50)
        if heldSteps > 0 { if state.walk(heldSteps, at: now) { levelled = true }; heldSteps = 0 }   // the fight's held-back steps count now: a level they bring evolves before the next one too
        let grows = growthDue(now)
        if b.trainer != nil {
            if end == .won {
                let g = state.towerWin(); if grows { growthThen = .tower(pick: nil) }
                return .say(["\(state.towerStreak ?? 0)연승!", "+\(g) BP"], next: grows ? .home : .tower(pick: nil), since: now)
            }
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
            let next = Screen.radar(bush: Int.random(in: 0..<4, using: &rng), cursor: 0, since: now, chain: n)
            if grows { growthThen = next; return .home }                                          // its bush rustles once they're done (settle restarts its clock)
            return next
        default: return .home
        }
    }
    func startTower(_ now: Date) {
        partyRefs = state.party().map { state.id($0.ref)! }; let p = state.party()                  // uids first, so the fighters carry them
        let ours = p.map { var m = $0.mon; if m.known == nil { m.known = m.moves }; m.level = Walk.towerLevel; return m }   // everyone fights as Lv.50 (1.15, flat) with the moves it has (copies — after() writes nothing back)
        let f = state.towerFoes(&rng); var b = Battle(party: ours, trainer: f.trainer, foes: f.foes)
        b.aiRandom = Walk.towerAIRandom[Walk.towerTier(state.towerStreak ?? 0)]
        freshFight(); let from = b, beats = b.begin(weather: nil, &rng)
        towerRun = true; screen = .beats(b, beats, since: now, from: from)
    }
    /// A fight begins: its foes play their entry animations afresh, and the last fight's per-species effect masks are let go (they're rebuilt on demand).
    func freshFight() {
        animOn = nil
        dropPics("fx|mask|")
    }
    func radarWindow(_ chain: Int) -> Double { max(0.8, 2.0 - 0.25 * Double(chain)) }
    func notify(_ kind: String, _ title: String, _ body: String) {
        guard persist, notifyOn(kind) else { return }
        host?.notify(title, body)
    }
    func save() { guard persist else { return }; Store.save(state); lastSave = Date(); if !savedSigned { savedSigned = true; settings.set("saveSigned", true) } }   // from now on an unsigned save here is an edited one
    /// Quitting: count the steps a fight held back (its copy is dropped on quit), then save.
    func quitSave() {
        if let h = host, !frozen { let n = gate.pass(state.take(counter: h.counter(), boot: h.boot(), at: Date()), Date().timeIntervalSinceReferenceDate); state.walk(state.roomToday(n + heldSteps), at: Date()); heldSteps = 0 }
        save()
        if let c = cloud { c.flush(&state); save() }                                              // up before it goes (2 s at most); its rev / hash on disk
    }
    /// A fight brought something to play before what comes next: one of ours that levelled can evolve, or a move waits to be learned.
    func growthDue(_ now: Date) -> Bool {
        var s = state
        return s.nextToLearn() != nil || levelled && state.levelEvolution(now) != nil || (state.evolving ?? []).contains { u in state.ref(uid: u).flatMap { state.levelEvolution(now, ref: $0) } != nil }
    }
    /// Home: the companion's level-up from walking (or its evolution), ours that levelled in a fight evolving one at a time, new moves;
    /// once nothing is left, where the fight was going on to (growthThen: the lobby, the chain's bush, its clock restarted).
    func settle(_ now: Date) {
        guard case .home = screen else { return }
        if levelled {
            levelled = false
            let name = monNames[state.companion.dex]
            if let e = state.levelEvolution(now) { startEvolving(e, now); notify("grow", "어라...? " + josa(name, "의", "의") + " 모습이...!", josa(name, "이", "가") + " " + josa(monNames[e.to], "으로", "로") + " 진화했어요!") }
            else {
                screen = .say(["레벨 업!", name + " Lv.\(state.companion.level)"], next: .home, since: now)
                if state.companion.level % 5 == 0 { notify("grow", "레벨 업!", name + " Lv.\(state.companion.level)") }
            }
        }
        while case .home = screen, var q = state.evolving, !q.isEmpty {                            // one at a time: the next when its show is over
            let u = q.removeFirst(); state.evolving = q.isEmpty ? nil : q
            if let r = state.ref(uid: u), let e = state.levelEvolution(now, ref: r) {
                let name = monNames[state.mon(r)!.dex]
                startEvolving(e, now, ref: r); notify("grow", "어라...? " + josa(name, "의", "의") + " 모습이...!", josa(name, "이", "가") + " " + josa(monNames[e.to], "으로", "로") + " 진화했어요!")
            }
        }
        if case .home = screen, (state.learning ?? []).count >= 2 { nextLearn(now) }
        if case .home = screen, let t = growthThen {
            growthThen = nil; lastInput = now                                                    // the lobby's idle time starts now, not at the fight's last press
            if case .radar(let b, let c, _, let n) = t { screen = .radar(bush: b, cursor: c, since: now, chain: n) } else { screen = t }
        }
    }
    /// The next move waiting in state.learning: straight in with a free slot, else the forget-one screen.
    func nextLearn(_ now: Date) {
        while let (ref, id) = state.nextToLearn() {
            let ls = learnsets[state.mon(ref)?.dex ?? 0]
            guard var m = state.mon(ref), !m.moves.contains(id), stride(from: 1, to: ls.count, by: 2).contains(where: { ls[$0] == id }) else { state.learned(); continue }
            if m.moves.count < 4 {
                m.known = m.moves + [id]; state.setMon(ref, m); state.learned()
                screen = .say([josa(monNames[m.dex], "은", "는") + " 새로", josa(moveTable[id]!.name, "을", "를") + " 배웠다!"], next: .home, since: now); return
            }
            screen = .learn(sel: 4); return                                                       // on 배우지 않는다: a reflex ● (skipping the fight's message) forgets nothing — it stays in 기술 바꾸기
        }
    }
    /// The 상점's (bp false) or BP 교환소's rows.
    func wares(_ bp: Bool) -> [Walk.Ware] { state.wares(bp: bp, shells: shells.filter { $0.bp > 0 }.map { (name: $0.name, bp: $0.bp) }) }
    /// A shell the 기기 menu offers: the dex reached, and a BP one bought.
    func shellOpen(_ s: Shell) -> Bool { s.dex <= dexCount && (s.bp == 0 || (state.bought ?? []).contains(s.name)) }
    /// Buys q of the row; a line to say, then back to the list.
    func buyWare(_ w: Walk.Ware, _ q: Int, bp: Bool, sel: Int, _ now: Date) {
        let back = Screen.shop(bp: bp, sel: sel, qty: nil), cost = "(-\(w.price * q)\(bp ? "BP" : "W"))"
        switch state.purchase(w, q, bp: bp) {
        case .items(let i, let n)?: screen = .say([josa(i, "을", "를") + (n > 1 ? " \(n)개" : ""), (bp ? "받았다! " : "샀다! ") + cost], next: back, since: now)
        case .legend(let m)?:
            screen = .say(["전설의 " + monNames[m.dex] + "!", "Lv.\(m.level) · 상자에 왔다"], next: back, since: now)
            notify("unlock", "전설의 \(monNames[m.dex])", "Lv.\(m.level)이 상자에 왔어요")
        case .shell(let s)?:
            if let t = shells.firstIndex(where: { $0.name == s }) { theme = t; if persist { settings.set("shell", t) } }   // wear it straight away
            screen = .say(["기기 색", s + " 획득!"], next: back, since: now)
        case nil: screen = .say([bp ? "BP가 부족하다" : "W가 부족하다"], next: back, since: now); return
        }
        save()
    }
    /// ↑ ↓ keys and the panel's buttons: in the list a row up / down, in how-many ±n (clamped, not wrapping); `nil` = as many as can be bought.
    func shopStep(_ d: Int?) {
        guard case .shop(let bp, let sel, let qty) = screen else { return }
        lastInput = Date(); host?.redraw(.all)
        let ws = wares(bp); guard let w = ws[safe: sel] else { return }
        let most = state.canBuy(w, bp: bp)
        if let q = qty { screen = .shop(bp: bp, sel: sel, qty: d.map { max(1, min(max(1, most), q + $0)) } ?? max(1, most)) }
        else if let d { screen = .shop(bp: bp, sel: max(0, min(ws.count - 1, sel + d.signum())), qty: nil) }
    }
    /// The scroll wheel / trackpad on a list: a row up or down — the shop's (leaving how-many: the amount only changes on purpose) or the tower's picker.
    func listRow(_ d: Int) {
        guard !frozen else { return }
        if case .tower(_?) = screen { towerStep(d); return }
        if case .course(let i) = screen { lastInput = Date(); host?.redraw(.all); screen = .course(max(0, min(courses.count - 1, i + d))); return }
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
    /// A click on the shop panel: 2100 + k = row k (and how-many, if it can be bought), 2000-2004 = −10 −1 +1 +10 max, 2005 = buy, 2006 / 2007 = 예 / 아니오.
    func shopTap(_ code: Int) {
        guard !frozen else { return }
        throughSay()
        if case .shopConfirm(let bp, let sel, _) = screen {
            if code == 2006 { screen = .shopConfirm(bp: bp, sel: sel, yes: true); press(1) }
            else if code == 2007 { screen = .shop(bp: bp, sel: sel, qty: nil) }
            else if code >= 2100 { screen = .shop(bp: bp, sel: sel, qty: nil); shopTap(code) }
            return
        }
        guard case .shop(let bp, _, let qty) = screen else { return }
        lastInput = Date(); host?.redraw(.all)
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
    func startEvolving(_ e: Evo, _ now: Date, ref: Int = -1) {
        guard let from = state.mon(ref) else { return }
        state.evolve(e, ref: ref); screen = .evolve(from: from, to: state.mon(ref) ?? from, since: now); save()
    }
    /// A fight's EXP, EVs and levels back to ours. Those that levelled (the companion too: the fight showed its Lv.) queue to evolve right after it (settle).
    func writeBackFight(_ b: Battle) {
        let before = partyRefs.map { u in state.ref(uid: u).flatMap { state.mon($0)?.level } }
        state.writeBack(partyRefs, b.mine.map(\.mon))
        for (u, l) in zip(partyRefs, before) {
            guard let l, let r = state.ref(uid: u), let m = state.mon(r), m.level > l else { continue }
            state.evolving = (state.evolving ?? []).filter { $0 != u } + [u]
        }
    }
    /// At launch: a save changed outside the app came back as the last one the app made (tampered), and the once-only check (Walk.audit)
    /// corrected a macro's or an edited file's gains; a message for each (they stay up a while).
    func auditAtLaunch(tampered: Bool = false) {
        var msgs: [[String]] = []
        if tampered { msgs.append(["세이브 파일이 바뀌어 있어", "마지막 정상 기록으로 되돌렸어요"]); notify("unlock", "세이브를 되돌렸어요", "세이브 파일이 앱 밖에서 바뀌어 있어서 마지막 정상 기록으로 되돌렸어요.") }
        if let r = state.refundBalls() { msgs.append(["볼은 이제 무료예요!", "가진 볼 \(r.count)개 → +\(r.watts)W"]) }   // (1.10, once)
        if let r = state.audit() {
            msgs.append([r.macro ? "자동 입력으로 쌓인 기록을" : "세이브에서 맞지 않는 기록을", "보정했어요 · W 0" + (r.gone > 0 ? " · 칠색조 \(r.gone)마리" : "")])
            notify("unlock", "기록을 보정했어요", (r.macro ? "자동 입력(매크로)으로 쌓인 W를 0으로" : "세이브 파일에서 맞지 않는 기록을 고치고 W를 0으로") + (r.gone > 0 ? ", 칠색조 \(r.gone)마리를 놓아줬어요." : "했어요."))
        }
        guard !msgs.isEmpty else { return }
        screen = msgs.reversed().reduce(Screen.home) { next, m in .say(m, next: next, since: Date().addingTimeInterval(30)) }; save()
    }
    /// At launch: the walker's ones already past their evolution (they levelled before the others could evolve) wait to evolve at home.
    func queueReadyEvolutions() {
        for i in state.caught.indices where state.levelEvolution(Date(), ref: -2 - i) != nil {
            if let u = state.id(-2 - i), !(state.evolving ?? []).contains(u) { state.evolving = (state.evolving ?? []) + [u] }
        }
    }
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
        guard !frozen else { return }
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
        case .menu, .card, .items, .box, .dex, .shop, .shopConfirm, .tower, .course, .train, .relearn: false
        case .say(_, let next, _): switch next { case .home, .menu, .card, .items, .box, .dex, .shop, .shopConfirm, .tower, .course, .train, .relearn: false; default: nil }
        default: nil
        }
    }
    func press(_ k: Int) {                                    // 0 left, 1 enter, 2 right, 3 back (↩), 4 메뉴 / 홈
        if frozen { if k == 1 { lockPress() }; return }          // locked by the server (no ID, another PC has it, too old): ● is the lock's button, nothing else
        let now = Date(); lastInput = now; defer { settle(now); save(); host?.redraw(.all) }        // back home: what a fight brought goes on at once
        if k == 4 {                                           // one key both ways: home opens the menu (on the pane; the LCD stays home), anywhere else it goes home
            if let open = homeKey() { if !open { growthThen = nil }; screen = open ? .menu(0) : .home }   // home means home: what a fight brought still plays there, then it stays
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
            case .course: screen = .menu(menuAt("코스"))
            case .train: screen = .items(state.inventory.firstIndex(of: "은색병뚜껑") ?? 0)
            case .tower(let p): screen = p != nil ? .tower(pick: nil) : .menu(menuAt("배틀 타워"))                    // the picker → the lobby → the menu; a run stays on: ● in the lobby goes on
            case .learn: screen = .learn(sel: 4)                                                    // onto 배우지 않는다; ● decides
            case .relearn(let r, let s, let at): screen = at != nil ? .relearn(ref: r, slot: s, at: nil) : .box(r, act: nil, confirm: false, detail: true)   // the moves → the slots → its page
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
                let top = state.here.all.map(\.level).max() ?? 45                                      // legends: over the course's own (1.14 bands), 50 at least; 아르세우스 80
                var m = Mon.wild(l ?? s.dex, level: l == nil ? min(100, s.level + Walk.chainLevel(chain)) : l == 493 ? 80 : max(50, top + 5), shiny: Int.random(in: 0..<Walk.chainShinyOdds(chain), using: &rng) == 0 ? true : nil,
                                 perfect: max(l == nil ? 0 : 3, Walk.chainPerfectIVs(chain)), &rng)   // chains raise 이로치 odds and sure 31s; legends have 3
                if l == nil { m.female = s.female }                                                // the walker's slots fix the sex
                partyRefs = ([-1] + state.caught.indices.map { -2 - $0 }).map { state.id($0)! }        // the companion, then the walker's: they can switch in
                var b = Battle(wild: m, party: [state.companion] + state.caught, chain: chain); state.see(m.dex)
                freshFight(); let from = b, beats = b.begin(weather: state.weather, &rng); screen = .beats(b, beats, since: now, from: from)
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
                let roll = Walk.rollBall(chain: b.chain, &rng); usedItem = roll.name                // free: which ball it turns out to be is luck (and the chain)
                let beats = b.turn(.capture, &rng, ball: roll.boost); screen = .beats(b, beats, since: now, from: from)
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
            if yes {
                let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false; screen = .say(["기권했다", "\(s)연승에서 끝"], next: .home, since: now)
            }
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
            else if !b.mine[sel].alive { screen = .say(["기절해서", "싸울 수 없다"], next: .party(b, sel: sel), since: now) }
            else if sel == b.me { screen = .say(["이미 싸우고 있다"], next: .party(b, sel: sel), since: now) }
            else { let from = b; let beats = b.mustReplace ? b.replace(sel) : b.turn(.swap(sel), &rng); screen = .beats(b, beats, since: now, from: from) }
        case .course(let i):                                                                      // ◀ ▶ a course (round), ● walk it
            if k == 1 { goCourse(i) } else { screen = .course((i + (k == 0 ? courses.count - 1 : 1)) % courses.count) }
        case .train(let st):                                                                      // ◀ ▶ a stat (round), ● trains it
            if k == 1 { useCap(st, back: .train(st)) } else { screen = .train((st + (k == 0 ? 5 : 1)) % 6) }
        case .tower(let p?):                                                                      // the picker: ◀ ▶ a row (round), ● puts it in the slot
            let all = state.towerCandidates, sel = all.firstIndex(of: p.at) ?? 0
            if k == 1 { state.towerSet(p.slot, all[sel]); screen = .tower(pick: nil) } else { screen = .tower(pick: (p.slot, all[(sel + (k == 0 ? all.count - 1 : 1)) % all.count])) }
        case .tower:
            guard k == 1 else { return }
            if towerRun { startTower(now) }
            else if state.spend(Walk.towerFee) { state.towerStreak = 0; startTower(now) }
            else { screen = .say(["W가 부족하다", "(\(Walk.towerFee)W 필요)"], next: .tower(pick: nil), since: now) }
        case .card(let p): screen = k == 1 ? .menu(menuAt("트레이너 카드")) : .card((p + (k == 0 ? 2 : 1)) % 3)
        case .say(_, let next, _): screen = next
        case .dex(let n, let f, let detail):                                                     // ● = the entry page and back (not on an empty tab)
            if k == 1 { if dexList(f).contains(n) { screen = .dex(n, filter: f, detail: !detail) } } else { gridStep(k == 0 ? -1 : 1, wrap: true) }
        case .items(let sel):                                                                     // ◀ ▶ a row, ● its use
            let n = state.inventory.count
            guard n > 0 else { return }
            if k != 1 { screen = .items((min(sel, n - 1) + (k == 0 ? n - 1 : 1)) % n); return }
            let name = state.inventory[min(sel, n - 1)], me = monNames[state.companion.dex], back = { (s: Int) in Screen.items(min(s, max(0, self.state.inventory.count - 1))) }
            switch ItemKind.of(name) {
            case .candy: if state.feedCandy() { levelled = true; screen = .say([me + " Lv.\(state.companion.level)!"], next: back(sel), since: now) }   // an evolution shows back home
            case .vitamin: screen = state.feedVitamin(name).map { .say([josa(me, "은", "는") + " " + josa(name, "을", "를"), "먹었다! 노력치 \($0)"], next: back(sel), since: now) } ?? .say([josa(name, "을", "를") + " 먹어도", "효과가 없을 것 같다"], next: back(sel), since: now)
            case .evReset: screen = .say(state.resetEVs() ? [josa(me, "은", "는") + " 순백떡을 먹었다!", "노력치가 0이 되었다"] : ["노력치가 이미", "0이다"], next: back(sel), since: now)
            case .berry: if state.feedBerry(name) { screen = .say([josa(me, "이", "가") + " " + josa(name, "을", "를"), "맛있게 먹었다!"], next: back(sel), since: now) }
            case .sell: let w = state.sell(name); screen = .say([name + " 판매", "+\(w)W"], next: back(sel), since: now)
            case .evolution: if let e = state.stoneEvolutions(now).first(where: { $0.item == name }) { startEvolving(e, now) }
            case .bottleCap(let gold): if itemUse(name).0 != nil { if gold { useCap(nil, back: back(sel)) } else { screen = .train(state.companion.effectiveIVs.firstIndex { $0 < 31 } ?? 0) } }   // 은색: pick the stat first
            default: break
            }
        case .box(let i, let act, let confirm, let detail):                                     // i: -1 the companion, -2-j the walker's j-th, else box[i]
            if state.mon(i) == nil { screen = .box(-1, act: nil, confirm: false) }                // gone meanwhile: back to the companion
            else if confirm {                                                                     // "놓아줄까?" 아니오 / 예
                if k != 1 { screen = .box(i, act: (act ?? 0) == 0 ? 1 : 0, confirm: true, detail: detail) }
                else if act == 1 {
                    let p = boxOrder.firstIndex(of: i) ?? 0, name = monNames[state.box[i].dex], w = state.release(i), o = boxOrder   // then the one after it in the grid
                    screen = .say([josa(name, "은", "는") + " 풀숲으로", "돌아갔다 (+\(w)W)"], next: .box(o.isEmpty ? -1 : o[min(p, o.count - 1)], act: nil, confirm: false, detail: detail && !o.isEmpty), since: now)
                }
                else { screen = .box(i, act: nil, confirm: false, detail: detail) }
            } else if let a = act {                                                              // the ● menu: boxActs (함께 / 상자로 or 워커로 · 놓아주기 / 닫기)
                let acts = boxActs(i)
                if k != 1 { screen = .box(i, act: (a + (k == 0 ? acts.count - 1 : 1)) % max(1, acts.count), confirm: false, detail: detail); return }
                switch acts[safe: a] {
                case "함께"?: if i < -1 { state.pair(-2 - i, onWalker: true) } else { state.pair(i) }; screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: .home, since: now)
                case "상자로"?: let name = monNames[state.caught[-2 - i].dex]; state.store(-2 - i)   // the walker's: into the box, picked there
                    screen = .say([josa(name, "을", "를"), "상자로 보냈다"], next: .box(state.box.count - 1, act: nil, confirm: false), since: now)
                case "워커로"?: let name = monNames[state.box[i].dex]; state.fetch(i)                  // the box's: onto the walker, picked there
                    screen = .say([josa(name, "을", "를"), "워커로 데려왔다"], next: .box(-1 - state.caught.count, act: nil, confirm: false), since: now)
                case "놓아주기"?: screen = .box(i, act: 0, confirm: true, detail: detail)
                default: screen = .box(i, act: nil, confirm: false, detail: detail)
                }
            } else if k == 1, detail, i == -1 { if let e = companionEvolution() { startEvolving(e, now) } else { screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷고 있다"], next: screen, since: now) } }
            else if k == 1 { screen = .box(i, act: detail ? 0 : nil, confirm: false, detail: true) }   // ● on the grid: its page; on its page: 함께 / 상자로 or 놓아주기 / 닫기
            else { gridStep(k == 0 ? -1 : 1, wrap: true) }
        case .relearn(let r, let s, let at):                                                     // the slots: ◀ ▶ one (round), ● what goes there; then ◀ ▶ a move, ● puts it in
            guard var m = state.mon(r) else { screen = .box(-1, act: nil, confirm: false); return }
            let all = m.relearnable
            guard let at else {
                let n = min(4, m.moves.count + 1)
                if k != 1 { screen = .relearn(ref: r, slot: (s + (k == 0 ? n - 1 : 1)) % n, at: nil); return }
                screen = .relearn(ref: r, slot: s, at: m.moves[safe: s] ?? all.first { !m.moves.contains($0) } ?? all[0]); return
            }
            let i = all.firstIndex(of: at) ?? 0
            if k != 1 { screen = .relearn(ref: r, slot: s, at: all[(i + (k == 0 ? all.count - 1 : 1)) % all.count]); return }
            let id = all[i], old = m.moves[safe: s], knew = m.moves.contains(id), back = Screen.relearn(ref: r, slot: s, at: nil), new = moveTable[id]!.name
            m.setMove(id, at: s); state.setMon(r, m)
            screen = knew ? back                                                                  // one of its own: two swapped places (or nothing changed)
                : old.map { .say(["1, 2, 짠!", josa(moveTable[$0]!.name, "을", "를") + " 잊고", josa(new, "을", "를") + " 배웠다!"], next: back, since: now) }
                ?? .say([josa(monNames[m.dex], "은", "는") + " 새로", josa(new, "을", "를") + " 배웠다!"], next: back, since: now)
        case .beats, .evolve, .hatch: break
        }
    }
    func open(_ i: Int, _ now: Date) {
        switch menuItems[i] {
        case "포켓 레이더": screen = state.spend(10) ? .radar(bush: Int.random(in: 0..<4, using: &rng), cursor: 0, since: now, chain: 0) : .say(["W가 부족하다", "(10W 필요)"], next: .menu(i), since: now)
        case "코스": screen = .course(state.course)
        case "트레이너 카드": screen = .card(0)
        case "포켓몬": screen = .box(-1, act: nil, confirm: false)                                  // the companion first
        case "상점", "BP 교환소": screen = .shop(bp: menuItems[i] == "BP 교환소", sel: 0, qty: nil)
        case "배틀 타워": screen = .tower(pick: nil)
        default: screen = .dex(state.companion.dex, filter: 0, detail: false)
        }
    }

    /// A click on the LCD: it's the screen to look at — the pane's page and the keys are what you press. Only a message goes on (as ● would).
    /// Returns false where the click drags the device instead.
    func touch(_ x: Int, _ y: Int) -> Bool {
        if frozen { return true }
        if case .say = screen { press(1); return true }
        guard let k = stickerAt(x, y) else { return false }                                        // the LCD is to look at, but for the walker's stickers on home:
        lastInput = Date(); state.pair(k, onWalker: true); emote = (1, Date().addingTimeInterval(2)); animOn = ("home", state.companion.dex, Date())   // a tap = walk with that one
        save(); host?.redraw(.all); return true
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

    // MARK: the menu's actions (the menu: Core/Menu.swift)
    /// 코스: walk course i (if it's open and not the one already walked): its progress starts over.
    func goCourse(_ i: Int) {
        guard state.unlocked(i), i != state.course else { host?.beep(); return }
        state.setCourse(i, &rng); screen = .say([josa(state.here.name, "으로", "로"), "출발!"], next: .home, since: Date()); save()
    }
    func useCandy() {
        guard state.feedCandy() else { return }
        levelled = true; screen = .home; save()                                                 // the home screen shows the level-up (or an evolution)
    }
    func useVitamin(_ v: String) {
        let name = monNames[state.companion.dex]
        if let e = state.feedVitamin(v) { screen = .say([josa(name, "은", "는") + " " + josa(v, "을", "를"), "먹었다!", "노력치 \(e)"], next: .home, since: Date()); save() }
        else { screen = .say([josa(v, "을", "를") + " 먹어도", "효과가 없을 것 같다"], next: .home, since: Date()) }
    }
    func useReset() {
        let name = monNames[state.companion.dex]
        if state.resetEVs() { screen = .say([josa(name, "은", "는") + " 순백떡을", "먹었다!", "노력치가 0이 되었다"], next: .home, since: Date()); save() }
        else { screen = .say(["노력치가 이미", "0이다"], next: .home, since: Date()) }
    }
    /// 대단한 특훈: one stat (은색병뚜껑), nil = all (금색병뚜껑).
    func useCap(_ stat: Int?, back: Screen = .home) {
        let name = monNames[state.companion.dex]
        guard state.hyperTrain(stat) else { screen = .say(["특훈할 수 없다"], next: back, since: Date()); return }
        let what = stat.map { ["HP", "공격", "방어", "특공", "특방", "스피드"][$0] } ?? "모든 능력"
        let left = state.inventory.firstIndex(of: "은색병뚜껑")                                    // back to the list where the caps are (or were)
        screen = .say(["대단한 특훈!", josa(name, "의", "의") + " " + what, "최고가 되었다! (\(state.companion.perfectIVs)V)"], next: stat == nil ? back : .items(left ?? 0), since: Date()); save()
    }
    func useBerry(_ b: String) {
        guard state.feedBerry(b) else { return }
        screen = .say([josa(monNames[state.companion.dex], "이", "가") + " " + josa(b, "을", "를"), "맛있게 먹었다!"], next: .home, since: Date()); save()
    }
    func sellOne(_ n: String) { let w = state.sell(n); screen = .say([n + " 판매", "+\(w)W"], next: .home, since: Date()); save() }
    func sellAll() {
        let w = state.inventory.reduce(0) { $0 + state.sell($1) }
        screen = .say(["전부 팔았다", "+\(w)W"], next: .home, since: Date()); save()
    }
    func useStone(_ i: Int) { let s = state.stoneEvolutions(Date()); guard s.indices.contains(i) else { return }; startEvolving(s[i], Date()) }
    /// 중복 놓아주기, once the platform has asked: the box's spare ones of that species go.
    func releaseDupes(_ dex: Int) { let r = state.releaseDuplicates(of: dex); screen = .say(["\(r.count)마리를 놓아줬다", "+\(r.watts)W"], next: .box(-1, act: nil, confirm: false), since: Date()); save() }   // back to the grid
}
