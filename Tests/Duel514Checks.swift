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
    return c
}
