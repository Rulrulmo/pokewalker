import Foundation
// The Pokémon a moment makes (docs/plans/10 §4) — the radar's find, a chain going on, an egg's, the legend shop's, 껍질몬 — one function each,
// with the random numbers passed in. The app rolls with them on its own until 2.1; from 2.1 the server rolls with them (its own random
// numbers) and records what it made, and a save may hold only Pokémon the server issued. Same code both sides: the rules can't drift apart.

extension Walk {
    /// The radar's find at chain length `chain`: the walker's slot (its sex fixed) or a legend; a chain's levels, 이로치 odds and sure 31s;
    /// legends at least Lv.50 over the course's own (아르세우스 80) with 3 sure 31s. (What Flow's radar did inline; the same draws in the same order.)
    func radarMon<R: RandomNumberGenerator>(_ r: inout R, chain: Int) -> (mon: Mon, legend: Bool) {
        let s = encounter(&r, chain: chain), l = legend(&r, chain: chain)
        let top = here.all.map(\.level).max() ?? 45
        let level = l == nil ? min(100, s.level + Walk.chainLevel(chain)) : l == 493 ? 80 : max(50, top + 5)
        let shiny: Bool? = Int.random(in: 0..<Walk.chainShinyOdds(chain), using: &r) == 0 ? true : nil
        var m = Mon.wild(l ?? s.dex, level: level, shiny: shiny, perfect: max(l == nil ? 0 : 3, Walk.chainPerfectIVs(chain)), &r)
        if l == nil { m.female = s.female }
        return (m, l != nil)
    }
    /// After a catch or a KO at chain length `chain`: does the grass rustle again?
    static func chainContinues<R: RandomNumberGenerator>(_ chain: Int, _ r: inout R) -> Bool { Double.random(in: 0..<1, using: &r) < chainGoesOn(chain) }
    /// What the walker's egg hatches into (Lv.1, 이로치 1/64); nil = no egg. The egg itself stays (hatch() takes it).
    func eggMon<R: RandomNumberGenerator>(_ r: inout R) -> Mon? {
        guard let e = egg else { return nil }
        let shiny: Bool? = Int.random(in: 0..<shinyOdds, using: &r) == 0 ? true : nil
        return Mon.wild(e.dex, level: 1, shiny: shiny, &r)
    }
    /// The legend shop's i-th (칠색조 Lv.50, 뮤츠 Lv.70): 3 sure 31s, 이로치 1/64.
    static func legendMon<R: RandomNumberGenerator>(_ i: Int, _ r: inout R) -> Mon {
        let l = legendShop[i], shiny: Bool? = Int.random(in: 0..<shinyOdds, using: &r) == 0 ? true : nil
        return Mon.wild(l.dex, level: l.level, shiny: shiny, perfect: 3, &r)
    }
    /// The 껍질몬 a 토중몬 leaves when it becomes 아이스크: the evolver's level, 이로치 and moves, its own roll otherwise.
    static func shedinja<R: RandomNumberGenerator>(from m: Mon, _ r: inout R) -> Mon {
        var s = Mon.wild(292, level: m.level, shiny: m.shiny, &r); s.known = m.known
        return s
    }
    /// The first companion of a new trainer: 피카츄 Lv.5, never rolled (IVs 15, nature 0, ability slot 0).
    static var starter: Mon { Walk().companion }
}

/// The traits that never change once a Pokémon exists: what the server checks a saved one against what it issued (10 §4).
struct MonTraits: Codable, Equatable {
    var female: Bool, shiny: Bool, ability: Int, nature: Int, ivs: [Int]
    init(_ m: Mon) { female = m.female; shiny = m.shiny == true; ability = m.ability ?? 0; nature = m.nature ?? 0; ivs = m.ivs ?? Array(repeating: 15, count: 6) }
}
/// Can `from` become `to` by evolving (any number of steps, forward only)?
func evolves(_ from: Int, into to: Int) -> Bool {
    if from == to { return true }
    var seen: Set<Int> = [from], todo = [from]
    while let d = todo.popLast() {
        for e in evolutions where e.from == d && !seen.contains(e.to) {
            if e.to == to { return true }
            seen.insert(e.to); todo.append(e.to)
        }
    }
    return false
}
