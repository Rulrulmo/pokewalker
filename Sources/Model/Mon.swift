import Foundation
// One Pokémon: level / EXP / friendship, and for battles its ability, nature, IVs, EVs and known moves.

struct Mon: Codable, Equatable {
    var dex: Int; var level: Int; var female: Bool
    var shiny: Bool? = nil               // Optionals: saves from before these fields still decode
    var exp: Int? = nil                  // nil = the minimum for `level`
    var walked: Int? = nil               // steps as the companion (friendship)
    var known: [Int]? = nil              // its 4 moves once chosen (nil = the last 4 it learned by level)
    var ability: Int? = nil              // ability slot (0 / 1); nature 0-24; IVs / EVs HP Atk Def SpA SpD Spe — nil = never rolled (IV 15, no EV)
    var nature: Int? = nil, ivs: [Int]? = nil, evs: [Int]? = nil
    var uid: Int? = nil                  // given the first time something has to find this one again (Walk.id(_:))
    var hyper: [Int]? = nil              // stats (0-5) raised by 대단한 특훈 (병뚜껑): they count as 31 in battle; the IVs themselves stay

    var points: Int { exp ?? expTable[growthRate[dex]][level] }
    static func level(dex: Int, exp: Int) -> Int { let t = expTable[growthRate[dex]]; return (1...100).last { t[$0] <= exp } ?? 1 }
    /// 1 step = 1 EXP, like HGSS. Returns true on a level-up.
    mutating func gain(_ n: Int) -> Bool {
        let e = points + n, before = level
        if known == nil { known = moves }
        exp = e; walked = (walked ?? 0) + n; level = max(level, Mon.level(dex: dex, exp: e))
        return level > before
    }
}
/// 이로치 odds. Gen IV is 1/8192, which at a few radar fights a day would never show up.
let shinyOdds = 128


// MARK: - the individual: ability slot, nature, IVs, EVs, known moves
extension Mon {
    /// A newly met Pokémon: gender by its species ratio, a random ability slot, nature and IVs.
    /// perfect = how many IVs (picked at random) are sure to be 31: 3 for legends (Gen VI on), more for long radar chains.
    static func wild<R: RandomNumberGenerator>(_ dex: Int, level: Int, shiny: Bool? = nil, perfect: Int = 0, _ r: inout R) -> Mon {
        let g = genderRate[dex]
        var m = Mon(dex: dex, level: level, female: g < 0 ? false : Int.random(in: 0..<8, using: &r) < g, shiny: shiny)
        m.ability = Int.random(in: 0..<abilitySlots[dex].count, using: &r); m.nature = Int.random(in: 0..<25, using: &r)
        m.ivs = (0..<6).map { _ in Int.random(in: 0...31, using: &r) }
        if perfect > 0 { for k in Array(0..<6).shuffled(using: &r).prefix(perfect) { m.ivs![k] = 31 } }
        return m
    }
    var abilityID: Int { let s = abilitySlots[dex]; return s[min(ability ?? 0, s.count - 1)] }   // the slot survives evolution, like the games
    var abilityName: String { abilityNames[abilityID] ?? "" }
    var natureName: String { natures[nature ?? 0].name }
    /// The IVs battles use: its own (15 if never rolled), with the 특훈 ones at 31.
    var effectiveIVs: [Int] { let iv = ivs ?? Array(repeating: 15, count: 6); return iv.indices.map { hyper?.contains($0) == true ? 31 : iv[$0] } }
    /// "3V": how many of them are 31 (특훈 included).
    var perfectIVs: Int { effectiveIVs.filter { $0 == 31 }.count }
    /// HP Atk Def SpA SpD Spe: the Gen IV formula with those IVs, its EVs and nature.
    var stats: [Int] {
        let b = baseStats[dex], l = level, iv = effectiveIVs, ev = evs ?? Array(repeating: 0, count: 6), n = natures[nature ?? 0]
        return (0..<6).map { k in
            let core = (2 * b[k] + iv[k] + ev[k] / 4) * l / 100
            if k == 0 { return dex == 292 ? 1 : core + l + 10 }                                    // 껍질몬: always 1
            let x = core + 5
            return n.up == n.down ? x : k == n.up ? x * 11 / 10 : k == n.down ? x * 9 / 10 : x
        }
    }
    /// The moves it knows: chosen ones, or (never chosen yet) the last four it learned by now.
    var moves: [Int] { known.map { $0.filter(Moves.supported) }.flatMap { $0.isEmpty ? nil : $0 } ?? Mon.defaultMoves(dex, level) }
    static func defaultMoves(_ dex: Int, _ level: Int) -> [Int] {
        var out: [Int] = []
        let ls = learnsets[dex]
        for k in stride(from: 0, to: ls.count, by: 2) where ls[k] <= level && Moves.supported(ls[k + 1]) { out.removeAll { $0 == ls[k + 1] }; out.append(ls[k + 1]) }
        return out.isEmpty ? [33] : Array(out.suffix(4))
    }
    /// Moves it learns on reaching levels (from, to], that it doesn't know yet.
    func newMoves(from a: Int, to b: Int) -> [Int] {
        let ls = learnsets[dex]; var out: [Int] = []
        for k in stride(from: 0, to: ls.count, by: 2) where ls[k] > a && ls[k] <= b && Moves.supported(ls[k + 1]) && !moves.contains(ls[k + 1]) && !out.contains(ls[k + 1]) { out.append(ls[k + 1]) }
        return out
    }
    /// Battle EXP only (walking EXP also counts friendship steps). Returns true on a level-up.
    mutating func gainBattleExp(_ n: Int) -> Bool {
        let before = level, e = points + n
        if known == nil { known = moves }                                                           // freeze the moveset before new moves arrive
        exp = e; level = max(level, Mon.level(dex: dex, exp: e)); return level > before
    }
    /// EVs from beating `foe`: its yield, 255 a stat, 510 in all.
    mutating func gainEVs(from foe: Int) {
        var e = evs ?? Array(repeating: 0, count: 6)
        for k in 0..<6 { let room = 510 - e.reduce(0, +); e[k] = min(255, e[k] + min(room, evYield[foe][k])) }
        evs = e
    }
}
