import Foundation
// 5.1.4 (the user via 회사 10-18: "친구대전에서도 메가진화 가능하도록 바꿔"): self-test checks (run by selftest()) — Mega Evolution in a live
// battle. The second player's view (Battle.mirrored) keeps each side's Mega used as its own, and its lines (duelWords) keep a stone's name whole
// (리자몽나이트X, never 상대 리자몽나이트X) for every stone, either side's.

@MainActor func duel514Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func add(_ t: (Bool, String, String)) { c.append((t.0, t.1)); if !t.0 { print("duel514: \(t.1.prefix(32))… — \(t.2)") } }
    func megaText(_ b: Battle) -> String? { for x in b.out { if case .mega(_, _, let t) = x { return t } }; return nil }

    Content.$testing.withValue(true) {
        // the mirror: A's 리자몽 Megas; in B's view it's the other side's (B's 루카리오 still may), and the other way round
        var za = Mon(dex: 6, level: 50, female: false); za.item = "리자몽나이트X"; za.known = [53, 19, 337, 89]
        var lu = Mon(dex: 448, level: 50, female: false); lu.item = "루카리오나이트"; lu.known = [396, 14, 98, 182]
        var b = Battle(party: [za], trainer: "민수", foes: [lu]); b.pvp = true
        b.megaEvolve(.me)
        let m = b.mirrored(name: "지훈")
        var b2 = Battle(party: [za], trainer: "민수", foes: [lu]); b2.pvp = true; b2.megaEvolve(.it)
        let m2 = b2.mirrored(name: "지훈")
        add((!b.canMega(.me) && b.canMega(.it) && m.canMega(.me) && !m.canMega(.it) && b2.canMega(.me) && !m2.canMega(.me) && m2.canMega(.it) && m.megaUsed == [false, true],
             "5.1.4 대전: the second player's view keeps each side's Mega used as its own (A's done: B's button stays; B's done: B's goes, A's stays)",
             "\(b.canMega(.me)) \(b.canMega(.it)) \(m.canMega(.me)) \(m.canMega(.it)) \(b2.canMega(.me)) \(m2.canMega(.me)) \(m2.canMega(.it)) \(String(describing: m.megaUsed))"))

        // the words: every stone, ours and theirs, seen from the other side — its name whole, "상대" before the species only
        var bad: [String] = []
        for dex in monForms.keys.sorted() { for (k, f) in monForms[dex]!.enumerated() where f.kind == .mega {
            guard let stone = f.item else { continue }
            var x = Mon(dex: dex, level: 50, female: false); x.item = stone
            var foe = Mon(dex: 448, level: 50, female: false); foe.item = nil
            if dex == 448 { foe = Mon(dex: 6, level: 50, female: false) }
            for side in [Side.me, .it] {
                var bt = side == .me ? Battle(party: [x], trainer: "민수", foes: [foe]) : Battle(party: [foe], trainer: "민수", foes: [x]); bt.pvp = true
                bt.megaEvolve(side)
                guard let raw = megaText(bt) else { bad.append("\(stone) \(side): none"); continue }
                let words = duelWords(ours: bt.mine.map(\.mon.dex), theirs: bt.theirs.map(\.mon.dex)), seen = Beat.mega(side, form: k + 1, text: raw).flipped(words)
                let name = monNames[dex], want = side == .me
                    ? "상대 " + josa(name + "의 " + stone, "이", "가") + " 빛나기 시작했다!\n" + "상대 " + josa(name, "은", "는") + " " + josa(f.name, "으로", "로") + " 메가진화했다!"
                    : josa(name + "의 " + stone, "이", "가") + " 빛나기 시작했다!\n" + josa(name, "은", "는") + " " + josa(f.name, "으로", "로") + " 메가진화했다!"
                if seen != .mega(side == .me ? .it : .me, form: k + 1, text: want) { bad.append("\(stone) \(side): \(seen)") }
            }
        } }
        add((bad.isEmpty, "5.1.4 대전: every Mega's lines from the other side — its stone's name whole (리자몽나이트X), 상대 before the species only, either side's",
             bad.prefix(4).joined(separator: " | ")))
    }

    // live (FakeCloud as the server's plan 24): two walkers, a duel each way the server may start it
    Content.$testing.withValue(true) { Content.$testingDuelMega.withValue(true) {
        let sv = FakeCloud(); sv.duelMega = true
        let da = online(Walk(), server: sv), db = online(Walk(), server: sv), ka = server(da).1, kb = server(db).1
        @MainActor func mon(_ dex: Int, _ item: String?, _ known: [Int]) -> Mon { var m = Mon(dex: dex, level: 50, female: false); m.item = item; m.known = known; return m }
        let zard = mon(6, "리자몽나이트X", [14, 53, 337, 89]), luca = mon(448, "루카리오나이트", [14, 396, 98, 182]), ray = mon(384, nil, [349, 620, 337, 245])   // (the first: 칼춤 · 용의춤 — no one down)
        let kyo = mon(382, "쪽빛구슬", [347, 57, 58, 104]), pika = mon(25, nil, [85, 98, 86, 21]), eevee = mon(133, nil, [33, 98, 39, 28])
        @MainActor func pump() { for _ in 0..<4 { for w in [da, db] { w.tick(Date()); drain(w) } } }
        @MainActor func shown(_ w: Walker) -> [Beat] { if case .beats(_, let bs, _, _) = w.screen { return bs }; return [] }
        @MainActor func megas(_ bs: [Beat]) -> [(Side, String)] { bs.compactMap { if case .mega(let s, _, let t) = $0 { return (s, t) }; return nil } }
        @MainActor func onMoves(_ w: Walker) -> Battle? {
            for _ in 0..<8 { if case .beats = w.screen { playOut(w) } else { break }; pump() }
            guard case .battle(let b, _) = w.screen, !w.duelWait else { return nil }
            w.screen = .battle(b, sel: 0); w.press(1); if case .moves(let x, _) = w.screen { return x }; return nil
        }
        @MainActor func button(_ w: Walker) -> Bool? { w.paneContent(Date()).battle?.mega }                     // (nil: none; false · true: there, ticked or not)
        @MainActor func pick(_ w: Walker, mega: Bool) { guard case .moves(let b, _) = w.screen else { return }; if mega { w.screen = .moves(b, sel: b.mine[b.me].moves.count); w.press(1) }; w.screen = .moves(b, sel: 0); w.press(1); drain(w) }
        /// A duel at its pick's end, both sides following it from its opening (the opening's beats: each side's as it saw them).
        @MainActor func start(_ a3: [Mon], _ b3: [Mon]) -> (i: Int, a: [Beat], b: [Beat]) {
            sv.duels.append(FakeCloud.FakeDuel(id: sv.nextDuel, a: ka, b: kb, aName: da.myName, bName: db.myName, state: "picking", deadline: sv.clockNow + 60, partyA: a3, partyB: b3, pickA: [0, 1, 2], pickB: [0, 1, 2]))
            sv.nextDuel += 1; let i = sv.duels.count - 1; sv.startDuel(i)
            sv.duels[i].version = 100 * sv.duels.count; sv.flushDuelWaiters(); pump()                // (the last duel's polls still held: let go)
            for (w, mine) in [(da, true), (db, false)] { w.screen = .home; w.duelStart(DuelView(id: sv.duels[i].id, state: "active", opponent: mine ? db.myName : da.myName, challenger: mine)) }
            var a: [Beat] = [], b: [Beat] = []
            for _ in 0..<6 { pump(); if a.isEmpty { a = shown(da) }; if b.isEmpty { b = shown(db) }; if !a.isEmpty && !b.isEmpty { break } }
            return (i, a, b)
        }
        @MainActor func end(_ i: Int) { sv.duels[i].state = "over"; sv.duels[i].winner = ka; sv.duels[i].version += 1; sv.flushDuelWaiters(); pump(); for w in [da, db] { w.duelStop(); w.screen = .home } }

        // ① both Mega in one turn: each its button, the tick kept while the other picks; the faster (리자몽) first; each side's own words
        let d1 = start([zard, pika, eevee], [luca, pika, eevee])
        let ma = onMoves(da), mb = onMoves(db), bothButtons = button(da) == false && button(db) == false && da.duel?.mega == true
        pick(da, mega: true); let ticked = da.duelWait && da.megaOn && da.sideModel(Date())?.megaTicked == true
        pick(db, mega: true); pump()
        let ta = megas(shown(da)), tb = megas(shown(db))
        let wantA = [(Side.me, "리자몽의 리자몽나이트X가 빛나기 시작했다!\n리자몽은 메가리자몽X로 메가진화했다!"), (.it, "상대 루카리오의 루카리오나이트가 빛나기 시작했다!\n상대 루카리오는 메가루카리오로 메가진화했다!")]
        let wantB = [(Side.it, "상대 리자몽의 리자몽나이트X가 빛나기 시작했다!\n상대 리자몽은 메가리자몽X로 메가진화했다!"), (.me, "루카리오의 루카리오나이트가 빛나기 시작했다!\n루카리오는 메가루카리오로 메가진화했다!")]
        let words = ta.map(\.0) == wantA.map(\.0) && ta.map(\.1) == wantA.map(\.1) && tb.map(\.0) == wantB.map(\.0) && tb.map(\.1) == wantB.map(\.1)
        let ma2 = onMoves(da), mb2 = onMoves(db), after = button(da) == nil && button(db) == nil && !da.megaOn && !db.megaOn && ma2?.megaUsed == [true, true] && mb2?.megaUsed == [true, true]
        add((ma != nil && mb != nil && bothButtons && ticked && words && after,
             "5.1.4 대전 메가: both sides' button (the duel's mega); ticked kept while the other picks; both in one turn — the faster first, each side's words its own (상대 before the other's, the stone whole); after: no button, the tick gone",
             "\(ma != nil) \(mb != nil) \(bothButtons) \(ticked) \(ta) \(tb) \(after) \(String(describing: ma2?.megaUsed)) \(String(describing: mb2?.megaUsed))"))
        end(d1.i)

        // ② 원시회귀 as it comes out (no button for it), 메가레쿠쟈 by 화룡점정 on one side only; a second asked: refused (the engine's words)
        let d2 = start([ray, pika, eevee], [kyo, luca, eevee])
        let primalA = megas(d2.a).map(\.1) == ["상대 가이오가의 원시회귀!\n고대의 모습을 되찾았다!"] && megas(d2.a).first?.0 == .it
        let primalB = megas(d2.b).map(\.1) == ["가이오가의 원시회귀!\n고대의 모습을 되찾았다!"] && megas(d2.b).first?.0 == .me
        _ = onMoves(da); let rayButton = button(da) == false; _ = onMoves(db); let kyoNone = button(db) == nil
        pick(da, mega: true); pick(db, mega: false); pump()
        let rayA = megas(shown(da)).map(\.1) == ["레쿠쟈는 화룡점정의 힘에 휩싸였다!\n레쿠쟈는 메가레쿠쟈로 메가진화했다!"], rayB = megas(shown(db)).map(\.1) == ["상대 레쿠쟈는 화룡점정의 힘에 휩싸였다!\n상대 레쿠쟈는 메가레쿠쟈로 메가진화했다!"]
        var again: [String] = []
        if let b = onMoves(da) { _ = onMoves(db); da.duelPick(.megaFight(slot: 0), b, back: .moves(b, sel: 0), Date()); drain(da); if case .say(let l, _, _) = da.screen { again = l } }
        add((primalA && primalB && rayButton && kyoNone && rayA && rayB && again == ["메가진화할 수", "없다!"],
             "5.1.4 대전 메가: 원시회귀 as 가이오가 comes out (its side, its words; no button for it); 메가레쿠쟈 by 화룡점정 on one side only; a second asked: 메가진화할 수 없다!",
             "\(megas(d2.a)) \(megas(d2.b)) \(rayButton) \(kyoNone) \(megas(shown(da))) \(again)"))
        end(d2.i)

        // ③ the other's app before 5.1.4: neither may (no mega; 이번엔 없음 on ours); the switch off mid-duel: gone at the next view, refused
        sv.oldDuelApps = [kb]
        let d3 = start([zard, pika, eevee], [luca, pika, eevee])
        let b3 = onMoves(da), oldA = da.duel?.mega == nil && button(da) == nil && da.paneContent(Date()).battle?.megaOff == true
        var refused: [String] = []
        if let b = b3 { da.duelPick(.megaFight(slot: 0), b, back: .moves(b, sel: 0), Date()); drain(da); if case .say(let l, _, _) = da.screen { refused = l } }
        end(d3.i); sv.oldDuelApps = []
        let d4 = start([zard, pika, eevee], [luca, pika, eevee])
        _ = onMoves(da); let on4 = button(da) == false
        sv.duelMega = false; sv.duels[d4.i].version += 1; sv.flushDuelWaiters(); pump()
        let off4 = da.duel?.mega == nil && button(da) == nil
        var refused4: [String] = []
        if case .moves(let b, _) = da.screen { da.duelPick(.megaFight(slot: 0), b, back: .moves(b, sel: 0), Date()); drain(da); if case .say(let l, _, _) = da.screen { refused4 = l } }
        end(d4.i); sv.duelMega = true
        let hub = { @MainActor () -> String? in da.screen = .duel(.hub(tab: 0, sel: 0)); return da.paneContent(Date()).duelHub?.note }()
        add((oldA && refused == ["이번 대전에서는", "메가진화를 쓸 수 없어요"] && on4 && off4 && refused4 == refused && hub?.hasSuffix("메가진화 OK") == true,
             "5.1.4 대전 메가: a duel with an app before 5.1.4 — no Mega (이번엔 없음 on ours, a Mega asked: refused); the switch off mid-duel: the button gone at the next view, refused; the 대전 menu says 메가진화 OK",
             "\(oldA) \(refused) \(on4) \(off4) \(refused4) \(String(describing: hub))"))
    } }
    // the switch off (5.1's way): no button in a duel, whatever its view says
    Content.$testing.withValue(true) { Content.$testingDuelMega.withValue(false) {
        let w = Walker(state: Walk()); w.persist = false
        var b = Battle(party: [{ var m = Mon(dex: 6, level: 50, female: false); m.item = "리자몽나이트X"; m.known = [53, 19, 337, 89]; return m }()], trainer: "민수", foes: [Mon(dex: 25, level: 50, female: false)]); b.pvp = true
        w.duelOn = true; w.duel = DuelView(id: 1, state: "active", opponent: "민수", challenger: true, battle: b); w.fight = b; w.screen = .moves(b, sel: 0)
        let p = w.paneContent(Date()).battle
        w.duelOn = false
        add((p?.mega == nil && p?.megaOff == false, "5.1.4 대전 메가: the switch off and a duel's view without mega — no button, no 이번엔 없음 (as 5.1)", "\(String(describing: p?.mega)) \(String(describing: p?.megaOff))"))
    } }
    return c
}
