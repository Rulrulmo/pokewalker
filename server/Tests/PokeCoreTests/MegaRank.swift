import Foundation
import Testing
@testable import PokeCore

// 10-16 (the user via 회사: "메가진화 포켓몬 순위좀 메겨볼수 있나?"): the Megas and the primals ranked by the engine, one against one. Off unless
// MEGA_RANK is set (CONTENT5 is implied). The 48 of the Mega raid and 메가레쿠쟈 (화룡점정: 5.2's 레쿠쟈 원정), each as a player can make it now:
// Lv.50, 31 in every IV, no EVs, a nature moving no stat, its first ability before it changes, holding its stone (orb), the four moves the
// tower would pick (towerMoves' rule) from everything it learns by level up to 100 — with the Mega's types (its own-type attacks are the Mega's).
// MEGA_RANK_TM=<json {dex: [move ids]}>: ORAS's TMs too (5.2, plan 19 §2; only moves this engine supports). Every pair MEGA_RANK_N fights a
// side (default 20), each as either side; both Mega Evolve at once (the primals revert coming out), both pick the hardest hit on paper:
// towerScore × type × attack ÷ defence (status moves only when nothing hits), the same rule for both. A draw (200 turns) is half.

private struct RankRNG: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }

private struct Entry { let name: String; let mon: Mon }

/// towerMoves' rule (Mon.swift) over a pool: two of its own type's hardest hits, the hardest of another type, one status move (a heal, an
/// ailment on the foe, a boost on itself), then the hardest left. `types`: the Mega's.
private func pick4(_ m: Mon, pool: [Int], types: [String]) -> [Int] {
    let skip: Set<Int> = [120, 153, 264, 138, 173, 387, 248, 353, 252, 255, 256, 364]
    let all = Set(pool).compactMap { moveTable[$0] }.filter { !skip.contains($0.id) && Moves.supported($0.id) }.sorted { $0.id < $1.id }
    let attacks = all.filter { !$0.isStatus }.sorted { m.towerScore($0) > m.towerScore($1) || m.towerScore($0) == m.towerScore($1) && $0.id < $1.id }, status = all.filter(\.isStatus)
    let ailments: Set<String> = ["sleep", "paralysis", "burn", "poison", "confusion", "yawn", "leech-seed"]
    var out = attacks.filter { types.contains($0.type) }.prefix(2).map(\.id)
    if let c = attacks.first(where: { !types.contains($0.type) }) { out.append(c.id) }
    if let s = status.first(where: { $0.cat == 3 }) ?? status.first(where: { $0.cat == 1 && ailments.contains($0.ailment) && $0.onFoe }) ?? status.first(where: { $0.cat == 2 && $0.onSelf }) { out.append(s.id) }
    for x in attacks + status where out.count < 4 && !out.contains(x.id) { out.append(x.id) }
    return Array(out.prefix(4))
}

private func entries(tm: [Int: [Int]]?) -> [Entry] {
    let neutral = natures.indices.first { natures[$0].up == natures[$0].down }!
    var list: [(MegaBoss, String)] = MegaRaid.bosses.map { b in (b, Forms.of(b.dex, b.form)?.name ?? monNames[b.dex]) }
    list.append((MegaBoss(dex: 384, form: 1, stone: ""), "메가레쿠쟈"))
    return list.map { b, name in
        var m = Mon(dex: b.dex, level: 100, female: false)
        m.ivs = Array(repeating: 31, count: 6); m.evs = nil; m.nature = neutral; m.ability = 0
        var mega = m; mega.form = b.form                                                          // its own type, its side: the Mega's
        var pool = m.relearnable + (tm?[b.dex] ?? [])
        if b.dex == 384 { pool.append(620) }                                                      // 화룡점정 (레쿠쟈 원정)
        var known = pick4(mega, pool: pool, types: mega.typing)
        if b.dex == 384, !known.contains(620) { known[known.count - 1] = 620 }                    // it must know it to Mega Evolve
        m.known = known; m.level = 50; m.exp = nil
        m.item = b.stone.isEmpty ? nil : b.stone
        return Entry(name: name, mon: m)
    }
}

/// The hardest hit on paper for side s: towerScore (the body's) × type × its attack ÷ the foe's defence.
private func rankPick(_ b: Battle, _ s: Side) -> Int {
    if let id = b.forcedMove(s) { return id }
    let ok = b.usable(s); guard !ok.isEmpty else { return 165 }
    let t: Side = s == .me ? .it : .me, me = b.f(s).body, foe = b.f(t).body
    func score(_ id: Int) -> Double {
        let m = moveTable[id]!
        if m.isStatus { return 0.001 }
        let a = Double(m.physical ? me.stats[1] : me.stats[3]), d = Double(m.physical ? foe.stats[2] : foe.stats[4])
        return me.towerScore(m) * b.typeEff(m.type, t, by: s) * a / max(1, d)
    }
    return ok.max { score($0) < score($1) || score($0) == score($1) && $0 > $1 }!
}

/// One fight: 1 = me won, 0 = it won, 0.5 = a draw.
private func fight(_ a: Mon, _ c: Mon, _ r: inout RankRNG) -> Double {
    var b = Battle(party: [a], trainer: "상대", foes: [c]); b.pvp = true; b.seed = r.next()
    _ = b.begin(weather: nil, &r)
    while !b.over, b.turnNo < 200 {
        let mine = rankPick(b, .me), theirs = rankPick(b, .it)
        b.foePlan = b.canMega(.it) ? .megaFight(theirs) : .fight(theirs)
        _ = b.turn(b.canMega(.me) ? .megaFight(mine) : .fight(mine), &r)
        b.foePlan = nil
    }
    if !b.over { return 0.5 }
    return b.mine[0].alive ? 1 : b.theirs[0].alive ? 0 : 0.5
}

@Test func megaRank() throws {
    guard ProcessInfo.processInfo.environment["MEGA_RANK"] != nil else { return }
    try Content.$testing.withValue(true) {
        let env = ProcessInfo.processInfo.environment, n = Int(env["MEGA_RANK_N"] ?? "") ?? 20
        let tm = try env["MEGA_RANK_TM"].map { p in
            try JSONDecoder().decode([String: [Int]].self, from: Data(contentsOf: URL(fileURLWithPath: p))).reduce(into: [Int: [Int]]()) { $0[Int($1.key)!] = $1.value }
        }
        let all = entries(tm: tm)
        for e in all { print("MEGARANK MOVES \(e.name): " + e.mon.moves.map { moveTable[$0]?.name ?? "?" }.joined(separator: " · ")) }
        var r = RankRNG(s: 2026_10_16)
        var score = Array(repeating: Array(repeating: 0.0, count: all.count), count: all.count)   // score[i][j]: i's share against j
        for i in all.indices { for j in all.indices where j > i {
            var w = 0.0
            for _ in 0..<n { w += fight(all[i].mon, all[j].mon, &r); w += 1 - fight(all[j].mon, all[i].mon, &r) }
            score[i][j] = w / Double(2 * n); score[j][i] = 1 - score[i][j]
        } }
        let rate = all.indices.map { i in all.indices.filter { $0 != i }.map { score[i][$0] }.reduce(0, +) / Double(all.count - 1) }
        for (k, i) in all.indices.sorted(by: { rate[$0] > rate[$1] }).enumerated() {
            let beats = all.indices.filter { $0 != i && score[i][$0] >= 0.5 }.count
            let worst = all.indices.filter { $0 != i }.min { score[i][$0] < score[i][$1] }!
            print("MEGARANK \(k + 1) \(all[i].name) " + String(format: "%.1f", 100 * rate[i]) + "% beats \(beats)/\(all.count - 1), worst: \(all[worst].name) " + String(format: "%.0f", 100 * score[i][worst]) + "%")
        }
    }
}
