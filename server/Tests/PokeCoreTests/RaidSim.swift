import Foundation
import Testing
@testable import PokeCore

// docs/plans/16: the raid's difficulty, simulated with the engine. Off unless RAID_SIM names a parties file ({"name": [Mon, …]}, the team's
// saves as exported — never committed). One fight: the party (as saved: levels, IVs, EVs, items, moves) against `bars` fresh copies of the
// boss (a wild one: random moves), our side greedy (the hardest hit on paper, as the tower's AI scores it), the next one alive when one falls,
// no items, no switching. Prints win rate, bars down and turns per party and boss level. RAID_SIM_N fights per cell (default 60).
// RAID_SIM_MOVES: the boss's four — raid (default: as the server makes it, RaidRules.boss), level (the last four it learned by now: before
// 10-12's own move), tower (towerMoves), level+sig / tower+sig (those with its own move at any level, withSignature). RAID_SIM_SPLIT: a line per species too. A level that is a tier's has that tier's V (else 4).

private struct SimRNG: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }

/// The hardest hit on paper among what ours may use (status moves last), or what it must use.
private func simPick(_ b: Battle) -> Int {
    if let id = b.forced { return id }
    let ok = b.usable(.me); guard !ok.isEmpty else { return 165 }
    let x = b.f(.me)
    func score(_ id: Int) -> Double {
        let m = moveTable[id]!
        if m.isStatus { return 1 }
        let p = m.power > 0 ? Double(m.power) : 60
        return p * (x.typeList.contains(m.type) ? 1.5 : 1) * b.typeEff(m.type, .it, by: .me) * Double(m.accuracy == 0 ? 100 : m.accuracy) / 100
    }
    return ok.max { score($0) < score($1) }!
}

/// One raid fight: (won, bars down, turns).
private func simFight(_ party: [Mon], boss: Mon, bars: Int, _ r: inout SimRNG) -> (Bool, Int, Int) {
    var b = Battle(wild: boss, party: party); b.seed = r.next(); b.raidTier = 1                  // a run's rules (날려버리기 can't end it)
    b.theirs += Array(repeating: Fighter(boss), count: bars - 1)
    _ = b.begin(weather: nil, &r)
    while !b.over, b.turnNo < 400 {
        if b.mustReplace, let n = b.mine.indices.first(where: { b.mine[$0].alive }) { _ = b.replace(n); continue }
        _ = b.turn(.fight(simPick(b)), &r)
    }
    let down = b.theirs.filter { !$0.alive }.count
    return (down == bars, down, b.turnNo)
}

@Test func raidSim() throws {
    guard let path = ProcessInfo.processInfo.environment["RAID_SIM"] else { return }
    let n = Int(ProcessInfo.processInfo.environment["RAID_SIM_N"] ?? "") ?? 60
    let parties = try JSONDecoder().decode([String: [Mon]].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    let only = ProcessInfo.processInfo.environment["RAID_SIM_DEX"].flatMap(Int.init)
    let species = only.map { [$0] } ?? raidRotation, bars = Int(ProcessInfo.processInfo.environment["RAID_SIM_BARS"] ?? "") ?? 10
    let levels = (ProcessInfo.processInfo.environment["RAID_SIM_LEVELS"] ?? RaidRules.tiers.map { String($0.level) }.joined(separator: ",")).split(separator: ",").compactMap { Int($0) }
    let rel = ProcessInfo.processInfo.environment["RAID_SIM_REL"]                  // "max" / "avg": levels are offsets from the party's top / mean level
    let moves = ProcessInfo.processInfo.environment["RAID_SIM_MOVES"] ?? "raid", split = ProcessInfo.processInfo.environment["RAID_SIM_SPLIT"] != nil
    var r = SimRNG(s: 2026_10_19)
    print("RAIDSIM bars \(bars) species \(species) n \(n)/species moves \(moves)")
    for name in parties.keys.sorted() {
        let party = parties[name]!
        var line = "RAIDSIM \(name.padding(toLength: 16, withPad: " ", startingAt: 0)) " + party.map { "\(monNames[$0.dex]) \($0.level)" }.joined(separator: " · ")
        let top = party.map(\.level).max() ?? 1, mean = party.map(\.level).reduce(0, +) / max(1, party.count)
        var per: [Int: String] = [:]
        for step in levels {
            let lv = rel == nil ? step : max(5, min(100, (rel == "avg" ? mean : top) + step))
            let tier = RaidRules.tiers.first { $0.level == lv } ?? RaidTier(tier: 0, level: lv, perfect: 4, bp: 0)
            var won = 0, down = 0, turns = 0
            for dex in species {
                var dw = 0
                for _ in 0..<n {
                    var boss = RaidRules.boss(dex, tier, shiny: false, &r)
                    switch moves {
                    case "level": boss.known = nil
                    case "tower": boss.known = boss.towerMoves()
                    case "level+sig": boss.known = nil; boss.known = boss.withSignature(boss.moves)
                    case "tower+sig": boss.known = boss.withSignature(boss.towerMoves())
                    default: break
                    }
                    let (w, d, t) = simFight(party, boss: boss, bars: bars, &r)
                    won += w ? 1 : 0; down += d; turns += t; dw += w ? 1 : 0
                }
                per[dex, default: ""] += String(format: " | L%d %3.0f%%", step, 100 * Double(dw) / Double(n))
            }
            let all = Double(n * species.count)
            line += " | " + (rel == nil ? "L" : "Δ") + String(format: "%d %3.0f%% %4.1f줄 %3.0f턴", step, 100 * Double(won) / all, Double(down) / all, Double(turns) / all)
        }
        print(line)
        if split { for dex in species { print("RAIDSIM   \(name.padding(toLength: 14, withPad: " ", startingAt: 0)) \(monNames[dex])" + per[dex]!) } }
    }
}
