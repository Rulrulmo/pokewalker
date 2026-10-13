// Not generated. docs/plans/18 (5.0): the content5 switch — Gen V·VI species (494-721), Fairy and the Gen VI rules, hidden abilities, Mega.
// Off, everything reads 4.1's Gen IV tables and rules exactly; on, the tables below with tools/gen.py's Gen VI changes applied. Engine code that
// differs by generation asks `Content.gen6`. The tables a Gen IV game never reads past 493 (names, growth, EV yields ...) are one table to 721.

enum Content {
    /// The server's setting (pokeserver content5); the app takes it from the login reply. Set once a session, before any battle.
    nonisolated(unsafe) static var on = false
    /// A test's own switch (`Content.$testing.withValue(true) { ... }`): tests run side by side, so they never flip `on`.
    @TaskLocal static var testing: Bool? = nil
    static var gen6: Bool { testing ?? on }
}

private func patched<T>(_ base: [T], _ changes: [Int: T]) -> [T] { var a = base; for (k, v) in changes { a[k] = v }; return a }

let monTypesGen6 = patched(monTypesGen4, monTypesGen6Changes)             // the Fairy retcon (20)
let baseStatsGen6 = patched(baseStatsGen4, baseStatsGen6Changes)          // Gen VI's raises (피카츄 방어 40 ...)
let learnsetsGen6 = patched(learnsetsGen4, learnsetsGen6Changes)          // HGSS + the retyped's new Fairy moves
let abilitySlotsGen6 = patched(abilitySlotsGen4, abilitySlotsGen6Changes)
let moveTableGen6 = moveTableGen4.merging(moveTableGen6Changes) { $1 }    // ORAS values; 468-621
let abilityDescsGen6 = abilityDescsGen4.merging(abilityDescsGen6Changes) { $1 }
let evolutionsGen6 = evolutionsGen4 + evolutionsGen6Added

var monTypes: [[String]] { Content.gen6 ? monTypesGen6 : monTypesGen4 }
var baseStats: [[Int]] { Content.gen6 ? baseStatsGen6 : baseStatsGen4 }
var learnsets: [[Int]] { Content.gen6 ? learnsetsGen6 : learnsetsGen4 }
var abilitySlots: [[Int]] { Content.gen6 ? abilitySlotsGen6 : abilitySlotsGen4 }
var moveTable: [Int: MoveInfo] { Content.gen6 ? moveTableGen6 : moveTableGen4 }
var typeChart: [String: [String: Double]] { Content.gen6 ? typeChartGen6 : typeChartGen4 }
var abilityDescs: [Int: String] { Content.gen6 ? abilityDescsGen6 : abilityDescsGen4 }
var evolutions: [Evo] { Content.gen6 ? evolutionsGen6 : evolutionsGen4 }
/// The highest species number in play: 493, or 721 with content5.
var dexMax: Int { Content.gen6 ? 721 : 493 }
