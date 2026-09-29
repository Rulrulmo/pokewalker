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
    /// Bag items that would do something for ours right now.
    func battleItems(_ b: Battle) -> [(name: String, use: ItemUse)] {
        state.inventory.compactMap { i in
            let u: ItemUse? = switch ItemKind.of(i) { case .heal(let n): .heal(n); case .battle(let u): u; default: nil }
            return u.flatMap { b.usable($0) ? (i, $0) : nil }
        }
    }
    func startEvolving(_ e: Evo, _ now: Date) { let from = state.companion; state.evolve(e); screen = .evolve(from: from, to: state.companion, since: now); save(nil) }
    var seenList: [Int] { Array(Set((state.seen ?? []) + (state.owned ?? []))).sorted() }

    func press(_ k: Int) {                                    // 0 left, 1 enter, 2 right, 3 home
        let now = Date(); lastInput = now; defer { save(nil); shown = nil; needsDisplay = true }
        if k == 3 {                                           // home from anywhere; mid-battle it counts as running away (or giving up a tower fight)
            switch screen {
            case .beats: return
            case .party(let b, _) where b.mustReplace: return                                       // someone has to come in
            case .moves(let b, _), .party(let b, _), .bagBattle(let b, _): screen = .battle(b, sel: 0)   // back out of the sub-menu
            case .battle(let b, _) where b.trainer != nil: let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false; screen = .say(["기권했다", "\(s)연승에서 끝"], next: .home, since: now)
            case .battle: screen = .say(["무사히", "도망쳤다!"], next: .home, since: now)
            case .tower where towerRun: let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false; screen = .say(["타워를 나왔다", "\(s)연승 기록"], next: .home, since: now)
            default: screen = .home
            }
            return
        }
        let n = menuItems.count
        switch screen {
        case .home: screen = .menu(k == 0 ? n - 1 : 0)
        case .menu(let i):
            if k == 0 { screen = i == 0 ? .home : .menu(i - 1) }
            else if k == 2 { screen = i == n - 1 ? .home : .menu(i + 1) }
            else { open(i, now) }
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
            case "기권": let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false; screen = .say(["기권했다", "\(s)연승에서 끝"], next: .home, since: now)
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
        case .dowse(let c, let prize, let tries, _):
            if k != 1 { screen = .dowse(cursor: (c + (k == 0 ? 5 : 1)) % 6, prize: prize, tries: tries, hint: nil); return }
            if c == prize {
                let item = state.dowse(&rng)
                screen = .say(state.keep(item) ? [josa(item, "을", "를"), "찾았다!"] : [josa(item, "을", "를") + " 찾았다!", "가방으로 보냈다"], next: .home, since: now)
            } else if tries == 1 { screen = .say(["아무것도", "없었다..."], next: .home, since: now) }
            else { screen = .dowse(cursor: c, prize: prize, tries: 1, hint: abs(c - prize) == 1 ? "가깝다!" : "멀다...") }
        case .card(let p): screen = k == 1 ? .menu(3) : .card((p + (k == 0 ? 2 : 1)) % 3)
        case .bag(let p):
            let n = bagPages
            if k != 1 { screen = .bag((p + (k == 0 ? n - 1 : 1)) % n) }
            else if state.caught.indices.contains(p), p < n - 1 {                           // ● on a Pokémon: walk with it
                state.pair(p, onWalker: true)
                screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: .home, since: now)
            } else { screen = .menu(4) }
        case .say(_, let next, _): screen = next
        case .dex(let i): let n = max(1, seenList.count); screen = k == 1 ? .menu(6) : .dex((i + (k == 0 ? n - 1 : 1)) % n)
        case .box(let i, let act, let confirm):
            let n = max(1, state.box.count)
            if state.box.isEmpty { screen = .menu(5) }
            else if confirm {                                                                     // "놓아줄까?" 아니오 / 예
                if k != 1 { screen = .box(i, act: (act ?? 0) == 0 ? 1 : 0, confirm: true) }
                else if act == 1 { let name = monNames[state.box[i].dex], w = state.release(i); screen = .say([josa(name, "은", "는") + " 풀숲으로", "돌아갔다 (+\(w)W)"], next: .box(min(i, max(0, state.box.count - 1)), act: nil, confirm: false), since: now) }
                else { screen = .box(i, act: nil, confirm: false) }
            } else if let a = act {                                                              // 함께 걷기 / 놓아주기 / 정렬 / 취소
                if k != 1 { screen = .box(i, act: (a + (k == 0 ? 3 : 1)) % 4, confirm: false); return }
                switch a {
                case 0: state.pair(i); screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: .home, since: now)
                case 1: screen = .box(i, act: 0, confirm: true)
                case 2: boxByLevel.toggle(); state.sortBox(byLevel: boxByLevel); screen = .say([boxByLevel ? "레벨순으로" : "번호순으로", "정렬했다"], next: .box(0, act: nil, confirm: false), since: now)
                default: screen = .box(i, act: nil, confirm: false)
                }
            } else if k == 1 { screen = .box(i, act: 0, confirm: false) }
            else { screen = .box((i + (k == 0 ? n - 1 : 1)) % n, act: nil, confirm: false) }
        case .beats, .evolve, .hatch: break
        }
    }
    func open(_ i: Int, _ now: Date) {
        switch i {
        case 0: screen = state.spend(10) ? .radar(bush: Int.random(in: 0..<4, using: &rng), cursor: 0, since: now, chain: 0) : .say(["W가 부족하다", "(10W 필요)"], next: .menu(0), since: now)
        case 1: screen = state.spend(3) ? .dowse(cursor: 0, prize: Int.random(in: 0..<6, using: &rng), tries: 2, hint: nil) : .say(["W가 부족하다", "(3W 필요)"], next: .menu(1), since: now)
        case 2:
            let n = state.caught.count + state.items.count
            state.connect()
            if let e = state.tradeEvolution(now) { startEvolving(e, now); return }                 // Connect is the walker's link cable
            screen = .say(n == 0 ? ["보낼 것이", "없다"] : ["상자로", "\(n)개 보냈다"], next: .menu(2), since: now)
        case 3: screen = .card(0)
        case 4: screen = .bag(0)
        case 5: screen = .box(0, act: nil, confirm: false)
        case 7: screen = .tower
        default: screen = .dex(max(0, seenList.firstIndex(of: state.companion.dex) ?? 0))
        }
    }

    /// Tap on the screen (dot coords 96x64). Returns false where the click should drag the device instead.
    func touch(_ x: Int, _ y: Int) -> Bool {
        func pick(_ select: () -> Void) { select(); press(1) }
        switch screen {
        case .home, .say: press(1)
        case .menu, .card, .bag, .dex: press(x < 32 ? 0 : x >= 64 ? 2 : 1)
        case .box(_, let act, _):
            if act != nil, y >= 50 { press(1) } else { press(x < 32 ? 0 : x >= 64 ? 2 : 1) }                             // left third ◀, middle ●, right third ▶
        case .radar(let b, _, let since, let chain): pick { screen = .radar(bush: b, cursor: (x < 48 ? 0 : 1) + (y < 32 ? 0 : 2), since: since, chain: chain) }
        case .battle(let b, _):
            guard y >= 50, let k = menuRanges(battleMenu(b)).firstIndex(where: { $0.contains(x) }) else { return false }
            pick { screen = .battle(b, sel: k) }
        case .moves(let b, _):
            guard y >= 37 else { press(3); return true }                                           // tap the stage = back
            let k = (x < 48 ? 0 : 1) + (y < 50 ? 0 : 2)
            guard k < b.mine[b.me].moves.count else { return false }
            pick { screen = .moves(b, sel: k) }
        case .bagBattle(let b, let sel):
            let n = battleItems(b).count, top = max(0, min(sel - 2, n - 5)), k = top + (y - 14) / 10
            guard y >= 14, k < n else { press(3); return true }
            pick { screen = .bagBattle(b, sel: k) }
        case .learn:
            let k = (y - 12) / 10
            guard y >= 12, k < 5 else { return false }
            pick { screen = .learn(sel: k) }
        case .party(let b, _):
            let k = (y - 15) / 15
            guard y >= 15, k < b.mine.count else { press(3); return true }
            pick { screen = .party(b, sel: k) }
        case .tower: press(1)
        case .dowse(_, let prize, let tries, _):
            guard (20..<48).contains(y) else { return false }
            pick { screen = .dowse(cursor: min(5, max(0, (x - 2) / 16)), prize: prize, tries: tries, hint: nil) }
        case .beats, .evolve, .hatch: return false
        }
        return true
    }
}
