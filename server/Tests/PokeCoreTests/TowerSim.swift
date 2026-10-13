import Foundation
import Testing
@testable import PokeCore

// docs/plans/17: the tower's hard fights, simulated with the engine. Off unless TOWER_SIM names a saves file ({"name": Walk}, the team's as
// exported — never committed); TOWER_SIM_WHO: whose (comma-separated; default all). Each one's tower party with one legend at most (its pick's
// first legend, topped up as party() does), Lv.50 copies; our side greedy (the hardest hit on paper), the next one in when one falls; the
// trainer's AI as the tower's at tier 5 (never at random). TOWER_SIM_N fights per cell (default 60). Prints:
//   plain — a 51st-to-99th fight;  은 / 금 — the tycoon's teams as they are, and with each legend in each slot (은: the slot's item and side);
//   101+ — a fight from the 101st, per legend (its last one).
// TOWER_SIM_TEAMS="50:464,350,249;100:149,350,376": only these tycoon teams (by fight; slot k keeps that team's item, its side by base stats).
// TOWER_SIM_QUICK: the tycoons as set, without each legend in each slot. CONTENT5=1: with the 5.0 switch on.

private struct SimRNG: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }

private func pick(_ b: Battle) -> Int {
    if let id = b.forced { return id }
    let ok = b.usable(.me); guard !ok.isEmpty else { return 165 }
    let x = b.f(.me)
    func score(_ id: Int) -> Double {
        let m = moveTable[id]!
        if m.isStatus { return 1 }
        return (m.power > 0 ? Double(m.power) : 60) * (x.typeList.contains(m.type) ? 1.5 : 1) * b.typeEff(m.type, .it, by: .me) * Double(m.accuracy == 0 ? 100 : m.accuracy) / 100
    }
    return ok.max { score($0) < score($1) }!
}

private func fight(_ ours: [Mon], _ trainer: String, _ foes: [Mon], _ r: inout SimRNG) -> Bool {
    var b = Battle(party: ours, trainer: trainer, foes: foes); b.seed = r.next(); b.aiRandom = 0
    _ = b.begin(weather: nil, &r)
    while !b.over, b.turnNo < 300 {
        if b.mustReplace, let n = b.mine.indices.first(where: { b.mine[$0].alive }) { _ = b.replace(n); continue }
        _ = b.turn(.fight(pick(b)), &r)
    }
    return b.theirs.allSatisfy { !$0.alive }
}

@Test func towerSim() throws {                                                                // CONTENT5=1: with the 5.0 switch on (docs/plans/18)
    guard let path = ProcessInfo.processInfo.environment["TOWER_SIM"] else { return }
    try Content.$testing.withValue(ProcessInfo.processInfo.environment["CONTENT5"] != nil) { try towerSim(path) }
}
private func towerSim(_ path: String) throws {
    let n = Int(ProcessInfo.processInfo.environment["TOWER_SIM_N"] ?? "") ?? 60
    var saves = try JSONDecoder().decode([String: Walk].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    if let who = ProcessInfo.processInfo.environment["TOWER_SIM_WHO"] { let k = Set(who.split(separator: ",").map(String.init)); saves = saves.filter { k.contains($0.key) } }
    var r = SimRNG(s: 2026_10_13)
    let names = saves.keys.sorted()
    var party: [String: [Mon]] = [:]
    for name in names {
        var w = saves[name]!
        if let p = w.towerPick {
            var seen = false; w.towerPick = p.filter { u in guard let m = w.ref(uid: u).flatMap(w.mon), Tower.isLegend(m.dex) else { return true }; defer { seen = true }; return !seen }
        }
        party[name] = w.party().map { x -> Mon in var m = x.mon; if m.known == nil { m.known = m.moves }; m.level = Walk.towerLevel; return m }
        print("TOWERSIM party \(name): " + party[name]!.map { monNames[$0.dex] }.joined(separator: " · "))
    }
    func rates(_ foes: () -> (String, [Mon])) -> [Double] {
        names.map { name in var won = 0; for _ in 0..<n { let f = foes(); won += fight(party[name]!, f.0, f.1, &r) ? 1 : 0 }; return 100 * Double(won) / Double(n) }
    }
    func show(_ label: String, _ x: [Double]) -> String { label + String(format: " avg %3.0f%%", x.reduce(0, +) / Double(x.count)) + " | " + zip(names, x).map { String(format: "%@ %.0f", $0.0, $0.1) }.joined(separator: " · ") }
    if let spec = ProcessInfo.processInfo.environment["TOWER_SIM_TEAMS"] {
        for part in spec.split(separator: ";") {
            let kv = part.split(separator: ":"), no = Int(kv[0])!, base = Tower.tycoonTeams[no]!
            let t = kv[1].split(separator: ",").enumerated().map { k, x -> (dex: Int, nature: Int, item: String, physical: Bool) in
                let d = Int(x)!, phys = baseStats[d][1] >= baseStats[d][3]; return (d, phys ? 3 : 15, base[k].item, phys)
            }
            print("TOWERSIM " + show("\(no): " + t.map { monNames[$0.dex] }.joined(separator: "·"), rates { (Tower.tycoon, t.map { Walk.tycoonMon($0, &r) }) }))
        }
        return
    }
    var w = Walk(); w.towerStreak = 60
    print("TOWERSIM " + show("plain (51–99th)", rates { let f = w.towerFoes(&r); return (f.trainer, f.foes) }))
    for (fightNo, label) in [(50, "은"), (100, "금")] {
        let team = Tower.tycoonTeams[fightNo]!
        print("TOWERSIM " + show("\(label) as set: " + team.map { monNames[$0.dex] }.joined(separator: "·"), rates { (Tower.tycoon, team.map { Walk.tycoonMon($0, &r) }) }))
        var rows: [(String, Double)] = []
        if ProcessInfo.processInfo.environment["TOWER_SIM_QUICK"] != nil { continue }               // the teams as set only
        for k in team.indices { for d in Tower.legends {
            var t = team; let phys = baseStats[d][1] >= baseStats[d][3]; t[k] = (d, phys ? 3 : 15, team[k].item, phys)
            let x = rates { (Tower.tycoon, t.map { Walk.tycoonMon($0, &r) }) }
            rows.append((show("\(label) \(monNames[team[k].dex])→\(monNames[d])", x), x.reduce(0, +) / Double(x.count)))
        } }
        for row in rows.sorted(by: { $0.1 > $1.1 }) { print("TOWERSIM   " + row.0) }
    }
    w.towerStreak = 120
    var rows: [(String, Double)] = []
    for d in Tower.legendFoes {                                                                    // (5.0: the 54)
        let x = rates { var f = w.towerFoes(&r); while f.foes[2].dex != d { f = w.towerFoes(&r) }; return (f.trainer, f.foes) }
        rows.append((show("101+ \(monNames[d])", x), x.reduce(0, +) / Double(x.count)))
    }
    for row in rows.sorted(by: { $0.1 > $1.1 }) { print("TOWERSIM   " + row.0) }
}
