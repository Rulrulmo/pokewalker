import Foundation

// Gen IV single battles, as close to HGSS as this app can run them: stats from base stats / IVs / EVs / nature, 4 known moves with PP,
// the type chart, status conditions, stat stages, weather, screens and hazards, abilities, and most move effects (data from PokeAPI's
// move meta, the rest by hand below). Not here: double battles, held items (the walker has none), forms.

// MARK: - data
struct MoveInfo {
    let id: Int; let name, type: String
    let power, accuracy, kind, priority, pp, cat, target: Int         // kind 0 physical, 1 special, 2 status; accuracy 0 = never misses
    let ailment: String; let ailmentChance, flinch: Int
    let stats: [Int]; let statChance, minHits, maxHits, minTurns, maxTurns, drain, healing, crit, flags: Int
    var physical: Bool { kind == 0 }; var special: Bool { kind == 1 }; var isStatus: Bool { kind == 2 }
    var contact: Bool { flags & 1 != 0 }; var punch: Bool { flags & 2 != 0 }; var sound: Bool { flags & 4 != 0 }
    var protectable: Bool { flags & 8 != 0 }; var reflectable: Bool { flags & 16 != 0 }
    var recharge: Bool { flags & 64 != 0 }; var charges: Bool { flags & 128 != 0 }; var defrosts: Bool { flags & 512 != 0 }
    var onSelf: Bool { [4, 5, 7, 13, 15].contains(target) }           // the user / its side
    var onFoe: Bool { [2, 6, 8, 9, 10, 11, 14].contains(target) }
}
enum Status: String, Codable, Equatable {
    case poison, toxic, burn, paralysis, sleep, freeze
    var badge: String { ["poison": "독", "toxic": "맹독", "burn": "화상", "paralysis": "마비", "sleep": "잠듦", "freeze": "얼음"][rawValue]! }
}
enum Sky: String, Codable, Equatable { case clear, sun, rain, sand, hail, fog }
let statNames = ["HP", "공격", "방어", "특수공격", "특수방어", "스피드", "명중률", "회피율"]

enum Moves {
    /// Moves this engine can't run faithfully: doubles-only, held-item ones, Colosseum's shadow moves. They're left out of movesets.
    static let unsupported: Set<Int> = [166, 266, 270, 274, 278, 271, 415, 374, 363, 286, 289, 382]
    static func supported(_ id: Int) -> Bool { id < 10000 && moveTable[id] != nil && !unsupported.contains(id) }
    static let semiInvulnerable: Set<Int> = [19, 91, 291, 340, 467]  // 공중날기 구멍파기 다이빙 뛰어오르다 섀도다이브
    static let fixedDamage: Set<Int> = [12, 32, 49, 68, 69, 82, 90, 101, 117, 149, 162, 243, 283, 329, 368]   // only an immunity changes what they do
    static let fixedOrVariable: Set<Int> = [12, 32, 49, 67, 68, 69, 82, 90, 101, 117, 149, 162, 175, 179, 216, 217, 218, 222, 243, 255, 283, 329, 360, 368, 376, 378, 447, 462]
}

func effectiveness(_ type: String, on d: Int) -> Double { monTypes[d].reduce(1) { $0 * (typeChart[type]?[$1] ?? 1) } }

// MARK: - fighters and the field
enum Side: String, Codable, Equatable { case me, it }
struct Fighter: Equatable, Codable {
    var mon: Mon; var hp: Int
    var status: Status? = nil; var sleep = 0, toxic = 0
    var moves: [Int]; var pp: [Int]
    var stage = [Int](repeating: 0, count: 8)                          // 1 atk 2 def 3 spa 4 spd 5 spe 6 accuracy 7 evasion
    var confused = 0, flinch = false, seeded = false, sub = 0, focus = false, charge = 0, cursed = false, nightmare = false
    var ingrain = false, aquaRing = false, destinyBond = false, perish = 0, yawn = 0, taunt = 0, encore = 0, encoreMove = 0
    var disable = 0, disabledMove = 0, torment = false, lastMove = 0, lock = 0, lockMove = 0, rollout = 0, furyCutter = 0
    var charging = 0, semi = 0, recharge = false, protectChain = 0, protected = false, endure = false, bide = 0, bideDmg = 0
    var bound = 0, boundBy = 0, stockpile = 0, lastHitDmg = 0, lastHitSpecial = false, hitThisTurn = false, movedThisTurn = false
    var types: [String]? = nil, abilityOver: Int? = nil, flashFire = false, truantSkip = false, slowStart = 0
    var healBlock = 0, magnetRise = 0, roosted = false, lockOn = 0, minimized = false, curled = false, rage = false, identified = false, miracleEye = false
    var magicCoat = false, grudge = false, attracted = false, trapped = false, embargo = 0, form: Mon? = nil, turnsOut = 0, uproar = 0
    var down = false                                                   // its KO has been handled
    var ownMoves: [Int]? = nil, ownPP: [Int]? = nil                    // its own moves and PP before 변신 / 흉내내기 changed them (back on switching out)

    init(_ m: Mon) { mon = m; hp = m.stats[0]; moves = m.moves; pp = m.moves.map { moveTable[$0]?.pp ?? 5 } }
    var maxHP: Int { mon.stats[0] }
    var alive: Bool { hp > 0 }
    var typeList: [String] { (types ?? monTypes[(form ?? mon).dex]).filter { !(roosted && $0 == "flying") } }
    var ability: Int { abilityOver ?? (form ?? mon).abilityID }
    func has(_ a: Int) -> Bool { ability == a }
    /// Back to the start: what switching out clears (Baton Pass keeps some of it, see there).
    mutating func clearVolatile() {
        let (m, h, st, sl, mv, p, d, om, op, transformed) = (mon, hp, status, sleep, moves, pp, down, ownMoves, ownPP, form != nil)
        self = Fighter(m); hp = h; status = st; toxic = st == .toxic ? 1 : 0; sleep = sl; down = d    // 맹독's count starts over
        guard let om, let op else { moves = mv; pp = p; return }                                   // PP stays spent
        moves = om; pp = om.indices.map { k in !transformed && k < mv.count && mv[k] == om[k] ? p[k] : op[k] }   // 변신 / 흉내내기 wear off: its own moves back (after 흉내내기, the PP the others spent since)
    }
}
struct SideState: Equatable, Codable { var reflect = 0, light = 0, safeguard = 0, mist = 0, tailwind = 0, luckyChant = 0, spikes = 0, toxicSpikes = 0, stealthRock = false, wish = 0, wishHP = 0, future = 0, futureDmg = 0, healingWish = false, lunarDance = false }

enum Move: Equatable, Codable { case fight(Int), capture, item(ItemUse), swap(Int), run }
/// A bag item used in battle (the UI picks it and takes it out of the bag).
enum ItemUse: Equatable, Codable {
    case heal(Int)                                   // HP (999 = all)
    case cure([Status], confusion: Bool)             // the statuses it fixes
    case restore                                     // 회복약: all HP and any status
    case pp(Int, all: Bool)                          // +n PP (99 = full) to the lowest move / every move
    case x(Int, Int)                                 // stat index, stages (Gen IV X items: +1)
    case guardSpec, direHit
    case revive(Int)                                 // 기력의조각 · 부활초: a fainted one of ours back up (by hand, on the bench), HP %
}
enum Beat: Equatable, Codable {
    case appear                                      // a wild one slides in
    case sendOut(Side, Int)                          // that side's fighter #i comes in
    case use(Side, move: Int)                        // "X의 Y!" (the user dashes)
    case hit(Side, move: Int, damage: Int, effect: Double, crit: Bool)   // Side = the one hit
    case hurt(Side, damage: Int, text: String)       // indirect: poison, recoil, weather, confusion, hazards
    case heal(Side, amount: Int, text: String)
    case status(Side, Status?, text: String)         // set or cured
    case note(Side, text: String)                    // anything else to read; Side = whose sprite shows
    case retype(Side, [String])                      // its types changed (변색, 텍스처, 변신, 포캐스트): no time on screen, it keeps the replayed type badges right
    case fainted(Side)
    case thrown(shakes: Int), broke, caught          // the ball rocks `shakes` times, then breaks open or clicks
    case gained(exp: Int, level: Int?, foe: Int, to: Int)   // after a KO, for each of ours that faced it (mine[to]); level if it went up; foe = the EV yield's species
    case fled, ran, won, lost
    var ends: Bool { [.caught, .fled, .ran, .won, .lost].contains(self) }
    var length: Double {                             // seconds on screen
        switch self {
        case .sendOut(.it, 0): 3.0                    // a trainer's first: it comes in, says so, throws (a later switch back to #0 just stands longer)
        case .appear, .sendOut: 1.4
        case .use: 0.9
        case .hit(_, _, _, let e, let c): e != 1 || c ? 1.6 : 1.0
        case .thrown(let s): 1.8 + 0.75 * Double(s)   // thrown, swallowing, dropping; then each rock and pause
        case .caught: 1.8
        case .fainted, .won, .lost: 1.4
        case .gained(_, let l, _, _): l == nil ? 1.2 : 1.8
        case .retype: 0
        default: 1.3
        }
    }
}
