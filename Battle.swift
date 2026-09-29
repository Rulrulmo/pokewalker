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
enum Sky: Equatable { case clear, sun, rain, sand, hail, fog }
let statNames = ["HP", "공격", "방어", "특수공격", "특수방어", "스피드", "명중률", "회피율"]

enum Moves {
    /// Moves this engine can't run faithfully: doubles-only, held-item ones, Colosseum's shadow moves. They're left out of movesets.
    static let unsupported: Set<Int> = [166, 266, 270, 274, 278, 271, 415, 374, 363, 286, 289, 382]
    static func supported(_ id: Int) -> Bool { id < 10000 && moveTable[id] != nil && !unsupported.contains(id) }
    static let semiInvulnerable: Set<Int> = [19, 91, 291, 340, 467]  // 공중날기 구멍파기 다이빙 뛰어오르다 섀도다이브
    static let fixedOrVariable: Set<Int> = [12, 32, 49, 67, 68, 69, 82, 90, 101, 117, 149, 162, 175, 179, 216, 217, 218, 222, 243, 255, 283, 329, 360, 368, 376, 378, 447, 462]
}

// MARK: - the individual: ability slot, nature, IVs, EVs, known moves
extension Mon {
    /// A newly met Pokémon: gender by its species ratio, a random ability slot, nature and IVs.
    static func wild<R: RandomNumberGenerator>(_ dex: Int, level: Int, shiny: Bool? = nil, _ r: inout R) -> Mon {
        let g = genderRate[dex]
        var m = Mon(dex: dex, level: level, female: g < 0 ? false : Int.random(in: 0..<8, using: &r) < g, shiny: shiny)
        m.ability = Int.random(in: 0..<abilitySlots[dex].count, using: &r); m.nature = Int.random(in: 0..<25, using: &r)
        m.ivs = (0..<6).map { _ in Int.random(in: 0...31, using: &r) }
        return m
    }
    var abilityID: Int { let s = abilitySlots[dex]; return s[min(ability ?? 0, s.count - 1)] }   // the slot survives evolution, like the games
    var abilityName: String { abilityNames[abilityID] ?? "" }
    var natureName: String { natures[nature ?? 0].name }
    /// HP Atk Def SpA SpD Spe: the Gen IV formula with this one's IVs (15 if never rolled), EVs and nature.
    var stats: [Int] {
        let b = baseStats[dex], l = level, iv = ivs ?? Array(repeating: 15, count: 6), ev = evs ?? Array(repeating: 0, count: 6), n = natures[nature ?? 0]
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
func effectiveness(_ type: String, on d: Int) -> Double { monTypes[d].reduce(1) { $0 * (typeChart[type]?[$1] ?? 1) } }

// MARK: - fighters and the field
enum Side: Equatable { case me, it }
struct Fighter: Equatable {
    var mon: Mon; var hp: Int
    var status: Status? = nil; var sleep = 0, toxic = 0
    var moves: [Int]; var pp: [Int]
    var stage = [Int](repeating: 0, count: 8)                          // 1 atk 2 def 3 spa 4 spd 5 spe 6 accuracy 7 evasion
    var confused = 0, flinch = false, seeded = false, sub = 0, focus = false, charged = false, cursed = false, nightmare = false
    var ingrain = false, aquaRing = false, destinyBond = false, perish = 0, yawn = 0, taunt = 0, encore = 0, encoreMove = 0
    var disable = 0, disabledMove = 0, torment = false, lastMove = 0, lock = 0, lockMove = 0, rollout = 0, furyCutter = 0
    var charging = 0, semi = 0, recharge = false, protectChain = 0, protected = false, endure = false, bide = 0, bideDmg = 0
    var bound = 0, stockpile = 0, lastHitDmg = 0, lastHitSpecial = false, hitThisTurn = false, movedThisTurn = false
    var types: [String]? = nil, abilityOver: Int? = nil, flashFire = false, truantSkip = false, slowStart = 0
    var healBlock = 0, magnetRise = 0, roosted = false, lockOn = 0, minimized = false, curled = false, rage = false, identified = false
    var magicCoat = false, grudge = false, attracted = false, trapped = false, embargo = 0, form: Mon? = nil, turnsOut = 0, uproar = 0
    var down = false                                                   // its KO has been handled

    init(_ m: Mon) { mon = m; hp = m.stats[0]; moves = m.moves; pp = m.moves.map { moveTable[$0]?.pp ?? 5 } }
    var maxHP: Int { mon.stats[0] }
    var alive: Bool { hp > 0 }
    var typeList: [String] { (types ?? monTypes[(form ?? mon).dex]).filter { !(roosted && $0 == "flying") } }
    var ability: Int { abilityOver ?? (form ?? mon).abilityID }
    func has(_ a: Int) -> Bool { ability == a }
    /// Back to the start: what switching out clears (Baton Pass keeps some of it, see there).
    mutating func clearVolatile() {
        let (m, h, st, sl, mv, p, d, transformed) = (mon, hp, status, sleep, moves, pp, down, form != nil)
        self = Fighter(m); hp = h; status = st; sleep = sl; down = d
        if !transformed { moves = mv; pp = p }                                                     // 변신 / 흉내내기 wear off; PP stays spent
    }
}
struct SideState: Equatable { var reflect = 0, light = 0, safeguard = 0, mist = 0, tailwind = 0, luckyChant = 0, spikes = 0, toxicSpikes = 0, stealthRock = false, wish = 0, wishHP = 0, future = 0, futureDmg = 0, healingWish = false }

enum Move: Equatable { case fight(Int), capture, item(ItemUse), swap(Int), run }
/// A bag item used in battle (the UI picks it and takes it out of the bag).
enum ItemUse: Equatable {
    case heal(Int)                                   // HP (999 = all)
    case cure([Status], confusion: Bool)             // the statuses it fixes
    case restore                                     // 회복약: all HP and any status
    case pp(Int, all: Bool)                          // +n PP (99 = full) to the lowest move / every move
    case x(Int, Int)                                 // stat index, stages (Gen IV X items: +1)
    case guardSpec, direHit
}
enum Beat: Equatable {
    case appear                                      // a wild one slides in
    case sendOut(Side, Int)                          // that side's fighter #i comes in
    case use(Side, move: Int)                        // "X의 Y!" (the user dashes)
    case hit(Side, move: Int, damage: Int, effect: Double, crit: Bool)   // Side = the one hit
    case hurt(Side, damage: Int, text: String)       // indirect: poison, recoil, weather, confusion, hazards
    case heal(Side, amount: Int, text: String)
    case status(Side, Status?, text: String)         // set or cured
    case note(Side, text: String)                    // anything else to read; Side = whose sprite shows
    case fainted(Side)
    case thrown(shakes: Int), broke, caught          // the ball rocks `shakes` times, then breaks open or clicks
    case gained(exp: Int, level: Int?, foe: Int)     // after a KO; level if it went up; foe = the EV yield's species
    case fled, ran, won, lost
    var ends: Bool { [.caught, .fled, .ran, .won, .lost].contains(self) }
    var length: Double {                             // seconds on screen
        switch self {
        case .appear, .sendOut: 1.4
        case .use: 0.9
        case .hit(_, _, _, let e, let c): e != 1 || c ? 1.6 : 1.0
        case .thrown(let s): 1.25 + 0.6 * Double(s)
        case .caught: 1.8
        case .fainted, .won, .lost: 1.4
        case .gained(_, let l, _): l == nil ? 1.2 : 1.8
        default: 1.3
        }
    }
}

struct Battle: Equatable {
    var mine: [Fighter], theirs: [Fighter]
    var me = 0, it = 0
    var trainer: String? = nil
    var chain = 0                                    // radar chain this fight belongs to
    var sides = [SideState(), SideState()]           // 0 ours, 1 theirs
    var sky = Sky.clear, skyTurns = 0                // skyTurns 0 with a sky = lasts (the course's weather, or an ability's)
    var trickRoom = 0, gravity = 0, mudSport = false, waterSport = false, lastUsed = 0, escapes = 0, turnNo = 0
    var out: [Beat] = [], over = false, seed: UInt64 = 1, planned = [0, 0]      // planned = each side's chosen move this turn (기습 needs it)
    var wild: Mon { theirs[it].mon }

    init(wild: Mon, companion: Mon, chain: Int = 0) { mine = [Fighter(companion)]; theirs = [Fighter(wild)]; self.chain = chain }
    init(party: [Mon], trainer: String, foes: [Mon]) { mine = party.map(Fighter.init); theirs = foes.map(Fighter.init); self.trainer = trainer }

    // MARK: plumbing
    func f(_ s: Side) -> Fighter { s == .me ? mine[me] : theirs[it] }
    mutating func mod(_ s: Side, _ body: (inout Fighter) -> Void) { if s == .me { body(&mine[me]) } else { body(&theirs[it]) } }
    func other(_ s: Side) -> Side { s == .me ? .it : .me }
    func si(_ s: Side) -> Int { s == .me ? 0 : 1 }
    func nm(_ s: Side) -> String { (s == .me ? "" : trainer == nil ? "야생 " : "상대 ") + monNames[f(s).mon.dex] }
    func stat(_ i: Int) -> String { statNames[i] }
    mutating func rnd() -> UInt64 { seed &+= 0x9E3779B97F4A7C15; var z = seed; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    mutating func roll(_ n: Int) -> Int { Int(rnd() % UInt64(max(1, n))) }
    mutating func pct(_ p: Double) -> Bool { Double(roll(10000)) < p * 100 }
    mutating func say(_ s: Side, _ text: String) { out.append(.note(s, text: text)) }
    var weatherOn: Sky { [mine[me], theirs[it]].contains { $0.alive && ($0.has(13) || $0.has(76)) } ? .clear : sky }   // 날씨부정 / 에어록

    /// Replays one beat onto HP / status / who's out (the UI shows it happening mid-turn).
    mutating func apply(_ b: Beat) {
        switch b {
        case .sendOut(.me, let i): me = i
        case .sendOut(.it, let i): it = i
        case .hit(let s, _, let d, _, _), .hurt(let s, let d, _): mod(s) { $0.hp = max(0, $0.hp - d) }
        case .heal(let s, let n, _): mod(s) { $0.hp = min($0.maxHP, $0.hp + n) }
        case .status(let s, let st, _): mod(s) { $0.status = st }
        case .gained(let e, _, let foe):
            let old = mine[me].maxHP
            if mine[me].mon.gainBattleExp(e) { mine[me].hp += mine[me].maxHP - old }                 // a level-up raises current HP too
            mine[me].mon.gainEVs(from: foe)
        default: break
        }
    }
    /// HP changes go through these, so the beats replay to exactly the same state.
    mutating func hurt(_ s: Side, _ n: Int, _ text: String) { let d = min(f(s).hp, max(1, n)); out.append(.hurt(s, damage: d, text: text)); apply(out.last!) }
    mutating func restore(_ s: Side, _ n: Int, _ text: String) {
        guard f(s).healBlock == 0 else { say(s, josa(nm(s), "은", "는") + " 회복할 수 없다!"); return }
        let h = min(f(s).maxHP - f(s).hp, max(1, n)); guard h > 0 else { say(s, josa(nm(s), "의", "의") + " HP는 가득하다!"); return }
        out.append(.heal(s, amount: h, text: text)); apply(out.last!)
    }
    mutating func setStatus(_ s: Side, _ st: Status?, _ text: String) { out.append(.status(s, st, text: text)); apply(out.last!) }

    // MARK: stats, speed, accuracy
    func mult(_ n: Int) -> Double { n >= 0 ? Double(2 + n) / 2 : 2 / Double(2 - n) }
    func accMult(_ n: Int) -> Double { let n = max(-6, min(6, n)); return n >= 0 ? Double(3 + n) / 3 : 3 / Double(3 - n) }
    func base(_ s: Side, _ k: Int) -> Int { let x = f(s); return k == 0 ? x.maxHP : ((x.form ?? x.mon).stats)[k] }
    func speed(_ s: Side) -> Double {
        let x = f(s); var v = Double(base(s, 5)) * mult(x.stage[5])
        if x.status == .paralysis { v *= x.has(95) ? 1 : 0.25 }
        if x.status != nil, x.has(95) { v *= 1.5 }                                               // 속보
        if weatherOn == .rain, x.has(33) { v *= 2 }; if weatherOn == .sun, x.has(34) { v *= 2 }  // 쓱쓱 / 엽록소
        if x.slowStart > 0 { v *= 0.5 }
        if sides[si(s)].tailwind > 0 { v *= 2 }
        return v
    }
    func grounded(_ s: Side) -> Bool { let x = f(s); return gravity > 0 || !(x.typeList.contains("flying") || x.has(26) || x.magnetRise > 0) }

    // MARK: status and stat changes
    /// Tries to give `st` to s. Returns false (quietly, unless `loud`) when it can't stick.
    @discardableResult mutating func inflict(_ s: Side, _ st: Status, from: Side?, loud: Bool) -> Bool {
        let x = f(s), n = nm(s)
        func no(_ why: String) -> Bool { if loud { say(s, why) }; return false }
        guard x.alive else { return false }
        if x.status != nil { return no(x.status == st || (st == .poison && x.status == .toxic) ? josa(n, "은", "는") + " 이미 " + st.badge + " 상태다!" : "그러나 실패했다!") }
        if from != nil, from != s, sides[si(s)].safeguard > 0 { return no(josa(n, "은", "는") + " 신비의 베일에 보호받고 있다!") }
        if from != nil, from != s, x.sub > 0 { return no("그러나 실패했다!") }
        let t = x.typeList
        switch st {
        case .poison, .toxic: if t.contains("poison") || t.contains("steel") || x.has(17) { return no(josa(n, "에게는", "에게는") + " 효과가 없는 것 같다...") }
        case .burn: if t.contains("fire") || x.has(41) { return no(josa(n, "에게는", "에게는") + " 효과가 없는 것 같다...") }
        case .freeze: if t.contains("ice") || x.has(40) || weatherOn == .sun { return false }
        case .paralysis: if x.has(7) { return no(josa(n, "은", "는") + " 유연 때문에 마비되지 않는다!") }
        case .sleep:
            if x.has(15) || x.has(72) { return no(josa(n, "은", "는") + " 잠들지 않는다!") }
            if [mine[me], theirs[it]].contains(where: { $0.uproar > 0 }) { return no("소란 때문에 잠들 수 없다!") }
        }
        if weatherOn == .sun, x.has(102) { return no(josa(n, "은", "는") + " 리프가드로 보호받고 있다!") }
        if st == .sleep { let turns = 1 + roll(4); mod(s) { $0.sleep = turns } }                       // 1-4 turns asleep
        if st == .toxic { mod(s) { $0.toxic = 1 } }
        let line = ["poison": "독에 걸렸다!", "toxic": "맹독을 입었다!", "burn": "화상을 입었다!", "paralysis": "마비되어 기술이 나오기 어려워졌다!", "sleep": "잠들어 버렸다!", "freeze": "얼어붙었다!"][st.rawValue]!
        setStatus(s, st, josa(n, "은", "는") + " " + line)
        if let src = from, src != s, f(s).has(28), [.poison, .toxic, .burn, .paralysis].contains(st) { inflict(src, st == .toxic ? .poison : st, from: s, loud: false) }   // 싱크로
        return true
    }
    mutating func confuse(_ s: Side, from: Side?, loud: Bool) {
        let x = f(s)
        guard x.alive else { return }
        if x.confused > 0 { if loud { say(s, josa(nm(s), "은", "는") + " 이미 혼란 상태다!") }; return }
        if x.has(20) { if loud { say(s, josa(nm(s), "은", "는") + " 마이페이스라 혼란하지 않는다!") }; return }
        if from != nil, from != s, sides[si(s)].safeguard > 0 { if loud { say(s, josa(nm(s), "은", "는") + " 신비의 베일에 보호받고 있다!") }; return }
        let n = 1 + roll(4); mod(s) { $0.confused = n }
        say(s, josa(nm(s), "은", "는") + " 혼란에 빠졌다!")
    }
    /// Stage change on s (by `from`'s move). Simple doubles, Clear Body & co. block drops, Mist too.
    mutating func boost(_ s: Side, _ k: Int, _ n0: Int, from: Side, loud: Bool = true) {
        let x = f(s); guard x.alive else { return }
        var n = x.has(86) ? n0 * 2 : n0
        if n < 0, from != s {
            if sides[si(s)].mist > 0 { if loud { say(s, josa(nm(s), "은", "는") + " 흰안개에 둘러싸여 있다!") }; return }
            if x.has(29) || x.has(73) || (k == 1 && x.has(52)) || (k == 6 && x.has(51)) { if loud { say(s, josa(nm(s), "의", "의") + " " + abilityNames[x.ability]! + " 때문에 " + josa(stat(k), "이", "가") + " 떨어지지 않는다!") }; return }
            if x.sub > 0 { if loud { say(s, "그러나 실패했다!") }; return }
        }
        let cur = x.stage[k]
        if (n > 0 && cur >= 6) || (n < 0 && cur <= -6) { if loud { say(s, josa(nm(s), "의", "의") + " " + josa(stat(k), "은", "는") + " 더 " + (n > 0 ? "올라가지" : "떨어지지") + " 않는다!") }; return }
        n = max(-6 - cur, min(6 - cur, n))
        mod(s) { $0.stage[k] += n }
        let how = abs(n) >= 3 ? (n > 0 ? "매우 크게 올라갔다!" : "매우 크게 떨어졌다!") : abs(n) == 2 ? (n > 0 ? "크게 올라갔다!" : "크게 떨어졌다!") : (n > 0 ? "올라갔다!" : "떨어졌다!")
        say(s, josa(nm(s), "의", "의") + " " + josa(stat(k), "이", "가") + " " + how)
    }
}

// MARK: - a turn
extension Battle {
    /// The opening: the wild one appears (or the trainer sends one out); the course's weather settles over the field; switch-in abilities fire.
    mutating func begin<R: RandomNumberGenerator>(weather: Weather?, _ r: inout R) -> [Beat] {
        seed = r.next() | 1; out = []
        switch weather { case .rain?: sky = .rain; case .snow?: sky = .hail; case .fog?: sky = .fog; default: break }
        out.append(trainer == nil ? .appear : .sendOut(.it, 0))
        switch sky { case .rain: say(.it, "비가 계속 내리고 있다"); case .hail: say(.it, "싸라기눈이 계속 내리고 있다"); case .fog: say(.it, "안개가 깊다..."); default: break }
        entry(.me); entry(.it)
        return out
    }
    /// Switch-in: hazards, then abilities (위협, weather, 다운로드, 트레이스, 프레셔 …).
    mutating func entry(_ s: Side) {
        let t = other(s), n = nm(s), side = sides[si(s)]
        if grounded(s), !f(s).has(98) {
            if side.spikes > 0 { hurt(s, f(s).maxHP * [0, 1, 2, 3][side.spikes] / [1, 8, 12, 16][side.spikes], josa(n, "은", "는") + " 압정뿌리기의 데미지를 입었다!") }
            if side.toxicSpikes > 0 { if f(s).typeList.contains("poison") { sides[si(s)].toxicSpikes = 0; say(s, "독압정이 사라졌다!") } else { inflict(s, side.toxicSpikes >= 2 ? .toxic : .poison, from: t, loud: false) } }
        }
        if side.stealthRock, !f(s).has(98) { hurt(s, max(1, Int(Double(f(s).maxHP) * typeEff("rock", s, by: t) / 8)), "뾰족한 바위가 " + josa(n, "을", "를") + " 파고들었다!") }
        if side.healingWish { sides[si(s)].healingWish = false; restore(s, f(s).maxHP, "치유의 소원이 이루어졌다!"); if f(s).status != nil { setStatus(s, nil, "") } }
        faints()
        guard f(s).alive, !over else { return }
        switch f(s).ability {
        case 22: say(s, josa(n, "의", "의") + " 위협!"); boost(t, 1, -1, from: s)
        case 2: sky = .rain; skyTurns = 0; say(s, josa(n, "의", "의") + " 잔비로 비가 내리기 시작했다!")
        case 70: sky = .sun; skyTurns = 0; say(s, josa(n, "의", "의") + " 가뭄으로 햇살이 강해졌다!")
        case 45: sky = .sand; skyTurns = 0; say(s, josa(n, "의", "의") + " 모래날림으로 모래바람이 불기 시작했다!")
        case 117: sky = .hail; skyTurns = 0; say(s, josa(n, "의", "의") + " 눈퍼뜨리기로 싸라기눈이 내리기 시작했다!")
        case 88: boost(s, base(t, 2) < base(t, 4) ? 1 : 3, 1, from: s)
        case 36: let a = f(t).ability; if ![36, 121].contains(a) { mod(s) { $0.abilityOver = a }; say(s, josa(n, "은", "는") + " " + monNames[f(t).mon.dex] + "의 " + josa(abilityNames[a]!, "을", "를") + " 트레이스했다!") }
        case 46: say(s, josa(n, "은", "는") + " 프레셔를 발휘하고 있다!")
        case 104: say(s, josa(n, "은", "는") + " 틀을 깼다!")
        case 112: mod(s) { $0.slowStart = 5 }; say(s, josa(n, "은", "는") + " 좀처럼 힘을 낼 수 없다!")
        case 107: if f(t).moves.contains(where: { let m = moveTable[$0]!; return !m.isStatus && typeEff(m.type, s, by: t) > 1 }) { say(s, josa(n, "은", "는") + " 몸서리를 쳤다!") }
        case 108: if let best = f(t).moves.max(by: { (moveTable[$0]?.power ?? 0) < (moveTable[$1]?.power ?? 0) }) { say(s, josa(monNames[f(t).mon.dex] + "의 " + moveTable[best]!.name, "을", "를") + " 꿰뚫어 보았다!") }
        default: break
        }
        forecast()
    }
    mutating func forecast() { for s in [Side.me, .it] where f(s).mon.dex == 351 && f(s).has(59) { let ty = ["sun": "fire", "rain": "water", "hail": "ice"]["\(weatherOn)"] ?? "normal"; mod(s) { $0.types = [ty] } } }
    /// s sends out #i (baton = keep stages, substitute, confusion, seeds...).
    mutating func switchIn(_ s: Side, _ i: Int, baton: Bool = false) {
        let keep = f(s)
        if f(s).has(30), f(s).status != nil, f(s).alive { mod(s) { $0.status = nil } }             // 자연회복 (quietly, as it leaves)
        mod(s) { $0.clearVolatile() }
        out.append(.sendOut(s, i)); apply(out.last!)
        if baton { mod(s) { $0.stage = keep.stage; $0.sub = keep.sub; $0.confused = keep.confused; $0.seeded = keep.seeded; $0.focus = keep.focus; $0.cursed = keep.cursed; $0.ingrain = keep.ingrain; $0.aquaRing = keep.aquaRing; $0.perish = keep.perish; $0.magnetRise = keep.magnetRise } }
        entry(s)
    }

    /// One turn. The last beat `ends` the battle when it's over. ball = the thrown ball's catch multiplier.
    mutating func turn<R: RandomNumberGenerator>(_ m: Move, _ r: inout R, ball: Double = 1) -> [Beat] {
        seed = r.next() | 1; out = []; turnNo += 1
        for s in [Side.me, .it] { mod(s) { $0.protected = false; $0.endure = false; $0.flinch = false; $0.hitThisTurn = false; $0.movedThisTurn = false; $0.magicCoat = false } }
        let foe = foeChoice(), (mi, ti) = (me, it)
        planned = [0, foe]
        switch m {
        case .run:
            if trainer != nil { say(.me, "승부 중에는 도망칠 수 없다!"); return out }
            if canEscape() { out.append(.ran); over = true; return out }
            say(.me, "도망칠 수 없었다!")
        case .capture: if throwBall(ball) { return out }
        case .item(let u): useItem(u)
        case .swap(let i): switchIn(.me, i)
        case .fight(let id):
            planned[0] = id
            if moveFirst(id, foe) { act(.me, id, mi); act(.it, foe, ti) } else { act(.it, foe, ti); act(.me, id, mi) }
            if !over { endOfTurn() }
            return out
        }
        act(.it, foe, ti)
        if !over { endOfTurn() }
        return out
    }
    /// Priority, then speed (Trick Room flips it; 늑장 goes last); ties at random.
    mutating func moveFirst(_ a: Int, _ b: Int) -> Bool {
        let pa = moveTable[a]!.priority, pb = moveTable[b]!.priority
        if pa != pb { return pa > pb }
        if f(.me).has(100) != f(.it).has(100) { return f(.it).has(100) }
        let sa = speed(.me), sb = speed(.it)
        if sa == sb { return roll(2) == 0 }
        return trickRoom > 0 ? sa < sb : sa > sb
    }

    /// Everything that can stop a move before it starts; then the move.
    mutating func act(_ s: Side, _ id0: Int, _ index: Int) {
        guard !over, f(s).alive, (s == .me ? me : it) == index else { return }                     // a replacement doesn't move the turn it comes in
        mod(s) { $0.movedThisTurn = true }
        let n = nm(s)
        var id = id0
        if f(s).recharge { mod(s) { $0.recharge = false }; say(s, josa(n, "은", "는") + " 공격의 반동으로 움직일 수 없다!"); return }
        if f(s).charging != 0 { id = f(s).charging } else if f(s).lock > 0 { id = f(s).lockMove } else if f(s).bide > 0 { id = 117 } else if f(s).encore > 0 { id = f(s).encoreMove }
        if f(s).status == .sleep {
            mod(s) { $0.sleep -= $0.has(48) ? 2 : 1 }
            if f(s).sleep <= 0 { setStatus(s, nil, josa(n, "은", "는") + " 눈을 떴다!"); mod(s) { $0.nightmare = false } }
            else if id != 173 && id != 214 { say(s, josa(n, "은", "는") + " 쿨쿨 잠들어 있다"); return }
        }
        if f(s).status == .freeze {
            if moveTable[id]!.defrosts || pct(20) { setStatus(s, nil, josa(n, "의", "의") + " 얼음이 녹았다!") }
            else { say(s, josa(n, "은", "는") + " 얼어버려서 움직일 수 없다!"); return }
        }
        if f(s).has(54) { if f(s).truantSkip { mod(s) { $0.truantSkip = false }; say(s, josa(n, "은", "는") + " 게으름을 피우고 있다"); return }; mod(s) { $0.truantSkip = true } }
        if f(s).flinch { say(s, josa(n, "은", "는") + " 풀이 죽어 기술을 쓸 수 없다!"); if f(s).has(80) { boost(s, 5, 1, from: s) }; return }
        if f(s).disable > 0, f(s).disabledMove == id { say(s, josa(n, "의", "의") + " " + josa(moveTable[id]!.name, "은", "는") + " 사용할 수 없다!"); return }
        if f(s).taunt > 0, moveTable[id]!.isStatus { say(s, josa(n, "은", "는") + " 도발당해서 " + josa(moveTable[id]!.name, "을", "를") + " 쓸 수 없다!"); return }
        if f(s).torment, id == f(s).lastMove, id != 165 { say(s, josa(n, "은", "는") + " 트집 때문에 같은 기술을 쓸 수 없다!"); return }
        if f(s).confused > 0 {
            mod(s) { $0.confused -= 1 }
            if f(s).confused == 0 { say(s, josa(n, "의", "의") + " 혼란이 풀렸다!") }
            else {
                say(s, josa(n, "은", "는") + " 혼란스러워 하고 있다!")
                if pct(50) { hurt(s, confusionHit(s), "영문도 모른 채 자신을 공격했다!"); faints(); return }
            }
        }
        if f(s).attracted { say(s, josa(n, "은", "는") + " 사랑에 빠져 있다!"); if pct(50) { say(s, josa(n, "은", "는") + " 헤롱헤롱해서 기술을 쓸 수 없었다!"); return } }
        if f(s).status == .paralysis, pct(25) { say(s, josa(n, "은", "는") + " 몸이 저려서 움직일 수 없다!"); return }
        execute(s, id, called: false)
        faints()
    }
    mutating func confusionHit(_ s: Side) -> Int {
        let a = f(s), A = Double(base(s, 1)) * mult(a.stage[1]), D = Double(base(s, 2)) * mult(a.stage[2])
        return max(1, Int((floor(floor(Double(2 * a.mon.level / 5 + 2) * 40 * A / D) / 50) + 2) * Double(217 + roll(39)) / 255))
    }
    mutating func deductPP(_ s: Side, _ id: Int) {
        let cost = f(other(s)).has(46) ? 2 : 1
        mod(s) { if let k = $0.moves.firstIndex(of: id) { $0.pp[k] = max(0, $0.pp[k] - cost) } }
    }

    /// The move itself: charging, callers, protection, accuracy, then damage or its effect.
    mutating func execute(_ s: Side, _ id: Int, called: Bool) {
        let m = moveTable[id]!, t = other(s), n = nm(s)
        if m.charges, f(s).charging != id, !(id == 76 && weatherOn == .sun) {                  // turn 1 of a two-turn move
            if !called { deductPP(s, id) }
            mod(s) { $0.charging = id; if Moves.semiInvulnerable.contains(id) { $0.semi = id } }
            let line = [76: "빛을 흡수했다!", 19: "하늘 높이 날아올랐다!", 91: "땅으로 파고들었다!", 291: "물속으로 잠수했다!", 340: "높이 뛰어올랐다!", 467: "모습을 감췄다!",
                        13: "회오리를 일으켰다!", 130: "목을 움츠렸다!", 143: "강렬한 빛에 휩싸였다!"][id] ?? "힘을 모으고 있다!"
            out.append(.use(s, move: id)); say(s, josa(n, "은", "는") + " " + line)
            if id == 130 { boost(s, 2, 1, from: s) }
            return
        }
        let second = f(s).charging == id
        mod(s) { $0.charging = 0; $0.semi = 0 }
        if !called && !second && f(s).lock == 0 { deductPP(s, id) }
        out.append(.use(s, move: id))
        mod(s) { $0.lastMove = id }
        let before = lastUsed; lastUsed = id
        switch id {                                                                                  // moves that pick another move
        case 118:
            let pool = moveTable.keys.filter { Moves.supported($0) && ![118, 165, 102, 144, 214, 119, 383, 267, 264, 182, 197, 203, 68, 243, 194].contains($0) }.sorted()
            let pick = pool[roll(pool.count)]; say(s, "손가락흔들기로 " + josa(moveTable[pick]!.name, "이", "가") + " 나왔다!"); execute(s, pick, called: true); return
        case 214:
            let ok = f(s).moves.filter { ![214, 117, 118, 264, 253, 13, 19, 76, 91, 130, 143, 291, 340, 467].contains($0) }
            guard f(s).status == .sleep, !ok.isEmpty else { say(s, "그러나 실패했다!"); return }
            execute(s, ok[roll(ok.count)], called: true); return
        case 119: guard f(t).lastMove != 0, Moves.supported(f(t).lastMove), f(t).lastMove != 119 else { say(s, "그러나 실패했다!"); return }; execute(s, f(t).lastMove, called: true); return
        case 383: guard before != 0, before != 383 else { say(s, "그러나 실패했다!"); return }; execute(s, before, called: true); return
        case 267: say(s, "자연의힘은 트라이어택이 되었다!"); execute(s, 161, called: true); return
        default: break
        }
        if m.onFoe && m.protectable && f(t).protected && id != 364 { say(t, josa(nm(t), "은", "는") + " 공격으로부터 몸을 지켰다!"); crash(s, t, m); return }
        if m.onFoe && m.reflectable && f(t).magicCoat { say(t, josa(nm(t), "은", "는") + " 매직코트로 " + josa(m.name, "을", "를") + " 튕겨냈다!"); statusMove(t, s, m); return }
        if m.onFoe, f(t).semi != 0, !canHitSemi(id, f(t).semi), !(f(s).has(99) || f(t).has(99)), f(s).lockOn == 0 { say(t, josa(nm(t), "에게는", "에게는") + " 맞지 않았다!"); crash(s, t, m); return }
        if (m.onFoe || m.accuracy > 0) && !m.onSelf, !hits(s, t, m) { say(t, josa(n, "의", "의") + " 공격은 빗나갔다!"); crash(s, t, m); mod(s) { $0.rollout = 0; $0.furyCutter = 0 }; return }
        if m.onFoe, m.sound, dAb(t, 43, by: s) { say(t, josa(nm(t), "은", "는") + " 방음으로 소리를 막았다!"); return }
        if m.power > 0 || Moves.fixedOrVariable.contains(id) { damageMove(s, t, m) } else { statusMove(s, t, m) }
    }
    /// A defender's ability, unless the attacker's 틀깨기 walks past it.
    func dAb(_ t: Side, _ a: Int, by s: Side) -> Bool { f(t).has(a) && !f(s).has(104) }
    func canHitSemi(_ id: Int, _ semi: Int) -> Bool {
        switch semi {
        case 19, 340: return [87, 16, 239, 327].contains(id)                                         // 번개 바람일으키기 회오리 스카이업퍼
        case 91: return [89, 222, 90].contains(id)                                                    // 지진 매그니튜드 땅가르기
        case 291: return [57, 250].contains(id)                                                       // 파도타기 바다회오리
        default: return false
        }
    }
    mutating func crash(_ s: Side, _ t: Side, _ m: MoveInfo) {
        if [26, 136].contains(m.id), !f(s).has(98) { hurt(s, min(f(t).maxHP / 2, max(1, f(s).maxHP / 8)), josa(nm(s), "은", "는") + " 기세 좋게 넘어졌다!") }
        if [120, 153].contains(m.id) { hurt(s, f(s).hp, "") }
    }
    mutating func hits(_ s: Side, _ t: Side, _ m: MoveInfo) -> Bool {
        if m.accuracy == 0 || f(s).has(99) || f(t).has(99) || f(s).lockOn > 0 { return true }
        if [12, 32, 90, 329].contains(m.id) {                                                      // one-hit KOs
            guard f(t).mon.level <= f(s).mon.level, !dAb(t, 5, by: s) else { return false }
            return roll(100) < 30 + f(s).mon.level - f(t).mon.level
        }
        var acc = Double(m.accuracy)
        if m.id == 87 { if weatherOn == .rain { return true }; if weatherOn == .sun { acc = 50 } }
        if m.id == 59, weatherOn == .hail { return true }
        let evas = f(s).has(109) || f(t).identified ? 0 : f(t).stage[7], accu = f(t).has(109) ? 0 : f(s).stage[6]
        acc *= accMult(accu - evas)
        if f(s).has(14) { acc *= 1.3 }; if f(s).has(55), m.physical { acc *= 0.8 }
        if weatherOn == .sand, dAb(t, 8, by: s) { acc *= 0.8 }; if weatherOn == .hail, dAb(t, 81, by: s) { acc *= 0.8 }
        if dAb(t, 77, by: s), f(t).confused > 0 { acc *= 0.5 }
        if gravity > 0 { acc *= 5.0 / 3 }; if weatherOn == .fog { acc *= 0.6 }
        return Double(roll(100)) < acc
    }
    func typeEff(_ type: String, _ t: Side, by s: Side) -> Double {
        guard !type.isEmpty else { return 1 }
        var e = 1.0
        for dt in f(t).typeList {
            var x = typeChart[type]?[dt] ?? 1
            if x == 0, dt == "ghost", type == "normal" || type == "fighting", f(s).has(113) || f(t).identified { x = 1 }
            if x == 0, dt == "dark", type == "psychic", f(t).identified { x = 1 }
            if x == 0, dt == "flying", type == "ground", gravity > 0 { x = 1 }
            e *= x
        }
        if type == "ground", !grounded(t), !(f(s).has(104) && f(t).has(26) && f(t).magnetRise == 0 && !f(t).typeList.contains("flying")) { e = 0 }
        return e
    }
    mutating func critical(_ s: Side, _ t: Side, _ m: MoveInfo) -> Bool {
        if dAb(t, 4, by: s) || dAb(t, 75, by: s) || sides[si(t)].luckyChant > 0 { return false }
        let st = min(4, m.crit + (f(s).focus ? 2 : 0) + (f(s).has(105) ? 1 : 0))
        return roll([16, 8, 4, 3, 2][st]) == 0
    }
    /// Gen IV damage: base, then burn, screens, weather, +2, crit, random, STAB, type, 필터/색안경.
    mutating func calc(_ s: Side, _ t: Side, _ m: MoveInfo, power: Int, type: String, eff: Double, crit: Bool) -> Int {
        let a = f(s), d = f(t), phys = m.physical || m.id == 165
        var A = Double(base(s, phys ? 1 : 3)), D = Double(base(t, phys ? 2 : 4))
        var aS = a.stage[phys ? 1 : 3], dS = d.stage[phys ? 2 : 4]
        if crit { aS = max(0, aS); dS = min(0, dS) }
        if d.has(109) { aS = 0 }; if a.has(109) { dS = 0 }
        A *= mult(aS); D *= mult(dS)
        if phys {
            if a.has(37) || a.has(74) { A *= 2 }; if a.has(55) { A *= 1.5 }; if a.has(62), a.status != nil { A *= 1.5 }
            if a.slowStart > 0 { A *= 0.5 }; if weatherOn == .sun, a.has(122) { A *= 1.5 }
            if dAb(t, 63, by: s), d.status != nil { D *= 1.5 }
        } else {
            if weatherOn == .sun, a.has(94) { A *= 1.5 }
            if weatherOn == .sand, d.typeList.contains("rock") { D *= 1.5 }; if weatherOn == .sun, d.has(122) { D *= 1.5 }
        }
        if [120, 153].contains(m.id) { D *= 0.5 }
        if dAb(t, 47, by: s), type == "fire" || type == "ice" { A *= 0.5 }
        if a.flashFire, type == "fire" { A *= 1.5 }
        var P = Double(power)
        if a.has(101), power <= 60 { P *= 1.5 }; if a.has(89), m.punch { P *= 1.2 }; if a.has(120), m.drain < 0 || [26, 136].contains(m.id) { P *= 1.2 }
        if a.hp * 3 <= a.maxHP, (type == "grass" && a.has(65)) || (type == "fire" && a.has(66)) || (type == "water" && a.has(67)) || (type == "bug" && a.has(68)) { P *= 1.5 }
        if a.has(79), genderRate[a.mon.dex] >= 0, genderRate[d.mon.dex] >= 0 { P *= a.mon.female == d.mon.female ? 1.25 : 0.75 }
        if dAb(t, 85, by: s), type == "fire" { P *= 0.5 }; if dAb(t, 87, by: s), type == "fire" { P *= 1.25 }
        if a.charged, type == "electric" { P *= 2 }; if mudSport, type == "electric" { P *= 0.5 }; if waterSport, type == "fire" { P *= 0.5 }
        var x = floor(floor(Double(2 * a.mon.level / 5 + 2) * P * A / max(1, D)) / 50)
        if a.status == .burn, phys, !a.has(62) { x = floor(x / 2) }
        if !crit, (phys && sides[si(t)].reflect > 0) || (!phys && sides[si(t)].light > 0) { x = floor(x / 2) }
        if weatherOn == .rain { if type == "water" { x *= 1.5 }; if type == "fire" { x *= 0.5 } }
        if weatherOn == .sun { if type == "fire" { x *= 1.5 }; if type == "water" { x *= 0.5 } }
        x += 2
        if crit { x *= a.has(97) ? 3 : 2 }
        x = floor(x * Double(217 + roll(39)) / 255)
        if !type.isEmpty, a.typeList.contains(type) { x *= a.has(91) ? 2 : 1.5 }
        x *= eff
        if eff > 1, dAb(t, 111, by: s) || dAb(t, 116, by: s) { x *= 0.75 }
        if eff < 1, a.has(110) { x *= 2 }
        return max(1, Int(x))
    }
    /// 잠재파워 with IVs: type and power the Gen IV way (IVs 15 everywhere = 악 70).
    func hiddenPower(_ m: Mon) -> (String, Int) {
        let iv = m.ivs ?? Array(repeating: 15, count: 6), order = [0, 1, 2, 5, 3, 4]
        let t = order.enumerated().reduce(0) { $0 + (iv[$1.element] & 1) << $1.offset } * 15 / 63
        let p = order.enumerated().reduce(0) { $0 + ((iv[$1.element] >> 1) & 1) << $1.offset } * 40 / 63 + 30
        return (["fighting", "flying", "poison", "ground", "rock", "bug", "ghost", "steel", "fire", "water", "grass", "electric", "psychic", "ice", "dragon", "dark"][t], p)
    }

    // MARK: damaging moves
    mutating func damageMove(_ s: Side, _ t: Side, _ m: MoveInfo) {
        let id = m.id, n = nm(s), tn = nm(t)
        var type = f(s).has(96) && id != 165 ? "normal" : m.type, power = m.power
        if id == 165 { type = "" }
        if id == 237 { (type, power) = hiddenPower(f(s).mon) }
        if id == 311 { switch weatherOn { case .sun: type = "fire"; power = 100; case .rain: type = "water"; power = 100; case .sand: type = "rock"; power = 100; case .hail: type = "ice"; power = 100; default: break } }
        if id == 449 { type = monTypes[f(s).mon.dex][0] }
        // immunity abilities first
        if !type.isEmpty {
            if (type == "water" && (dAb(t, 11, by: s) || dAb(t, 87, by: s))) || (type == "electric" && dAb(t, 10, by: s)) {
                say(t, josa(tn, "은", "는") + " " + abilityNames[f(t).ability]! + "로 회복했다!"); restore(t, f(t).maxHP / 4, ""); return }
            if type == "electric", dAb(t, 78, by: s) { say(t, josa(tn, "은", "는") + " 전기엔진이 작동했다!"); boost(t, 5, 1, from: t); return }
            if type == "fire", dAb(t, 18, by: s) { mod(t) { $0.flashFire = true }; say(t, josa(tn, "은", "는") + " 타오르는불꽃으로 불꽃 기술의 위력이 올라갔다!"); return }
        }
        let eff = typeEff(type, t, by: s)
        if eff == 0 { say(t, tn + "에게는 효과가 없는 것 같다..."); crash(s, t, m); return }
        if dAb(t, 25, by: s), eff <= 1, !type.isEmpty { say(t, josa(tn, "은", "는") + " 불가사의부적으로 공격을 받지 않는다!"); return }
        if id == 138, f(t).status != .sleep { say(t, josa(tn, "은", "는") + " 잠들어 있지 않다!"); return }
        if id == 173, f(s).status != .sleep { say(s, "그러나 실패했다!"); return }
        if id == 252, f(s).turnsOut > 0 { say(s, "그러나 실패했다!"); return }
        if id == 264, f(s).hitThisTurn { say(s, josa(n, "은", "는") + " 집중이 흐트러져서 기술을 쓸 수 없다!"); return }
        if id == 389, f(t).movedThisTurn || (moveTable[planned[si(t)]]?.isStatus ?? true) { say(s, "그러나 실패했다!"); return }
        if id == 364, !f(t).protected { say(s, "그러나 실패했다!"); return }
        if [120, 153].contains(id), [mine[me], theirs[it]].contains(where: { $0.has(6) }) { say(s, "습기 때문에 " + josa(m.name, "을", "를") + " 쓸 수 없다!"); return }
        if id == 255 && f(s).stockpile == 0 { say(s, "그러나 비축하지 못했다!"); return }
        // fixed damage
        let fixed: Int? = switch id {
        case 49: 20
        case 82: 40
        case 69, 101: f(s).mon.level
        case 149: max(1, f(s).mon.level * (50 + roll(101)) / 100)
        case 162: max(1, f(t).hp / 2)
        case 283: f(t).hp > f(s).hp ? f(t).hp - f(s).hp : 0
        case 12, 32, 90, 329: f(t).hp
        case 68: f(s).hitThisTurn && !f(s).lastHitSpecial ? f(s).lastHitDmg * 2 : 0
        case 243: f(s).hitThisTurn && f(s).lastHitSpecial ? f(s).lastHitDmg * 2 : 0
        case 368: f(s).hitThisTurn ? f(s).lastHitDmg * 3 / 2 : 0
        default: nil
        }
        if let d = fixed {
            if d == 0 { say(s, "그러나 실패했다!"); return }
            land(s, t, m, d, eff: 1, crit: false)
            if [12, 32, 90, 329].contains(id), !f(t).alive { say(t, "일격필살!") }
            post(s, t, m, dealt: d); return
        }
        if id == 117 {                                                                               // 참기
            if f(s).bide == 0 { mod(s) { $0.bide = 2; $0.bideDmg = 0 }; say(s, josa(n, "은", "는") + " 참기 시작했다!"); return }
            mod(s) { $0.bide -= 1 }
            if f(s).bide > 0 { say(s, josa(n, "은", "는") + " 참고 있다!"); return }
            guard f(s).bideDmg > 0 else { say(s, "그러나 실패했다!"); return }
            say(s, josa(n, "의", "의") + " 참았던 힘이 풀렸다!"); land(s, t, m, f(s).bideDmg * 2, eff: 1, crit: false); return
        }
        // variable power
        let tw = weightKg[f(t).mon.dex], ratio = Double(f(s).hp) / Double(f(s).maxHP)
        switch id {
        case 67, 447: power = tw < 10 ? 20 : tw < 25 ? 40 : tw < 50 ? 60 : tw < 100 ? 80 : tw < 200 ? 100 : 120
        case 175, 179: let p = 48 * f(s).hp / f(s).maxHP; power = p <= 1 ? 200 : p <= 4 ? 150 : p <= 9 ? 100 : p <= 16 ? 80 : p <= 32 ? 40 : 20
        case 284, 323: power = max(1, Int(150 * ratio))
        case 378, 462: power = 1 + 120 * f(t).hp / f(t).maxHP
        case 216, 218: let fr = min(255, 70 + (f(s).mon.walked ?? 0) / 100); power = max(1, (id == 216 ? fr : 255 - fr) * 10 / 25)
        case 222: let k = roll(100); let i = [5, 15, 35, 65, 85, 95, 100].firstIndex { k < $0 }!; power = [10, 30, 50, 70, 90, 110, 150][i]; say(s, "매그니튜드 \(i + 4)!"); if f(t).semi == 91 { power *= 2 }
        case 360: power = min(150, 1 + Int(25 * speed(t) / max(1, speed(s))))
        case 386: power = min(200, 60 + 20 * f(t).stage[1...7].filter { $0 > 0 }.reduce(0, +))
        case 376: let left = f(s).moves.firstIndex(of: id).map { f(s).pp[$0] } ?? 0; power = [200, 80, 60, 50][min(3, left)] ; if left > 3 { power = 40 }
        case 255: power = 100 * f(s).stockpile
        case 217: let k = roll(10); if k < 2 { restore(t, 80, josa(tn, "의", "의") + " 체력이 회복되었다!"); return }; power = k < 6 ? 40 : k < 9 ? 80 : 120
        case 263: if f(s).status != nil { power *= 2 }
        case 362: if f(t).hp * 2 <= f(t).maxHP { power *= 2 }
        case 371: if f(t).movedThisTurn { power *= 2 }
        case 279, 419: if f(s).hitThisTurn { power *= 2 }
        case 372: if f(t).hitThisTurn { power *= 2 }
        case 358: if f(t).status == .sleep { power *= 2 }
        case 265: if f(t).status == .paralysis { power *= 2 }
        case 23: if f(t).minimized { power *= 2 }
        case 205, 301:
            if f(s).lock == 0 { mod(s) { $0.lock = 5; $0.lockMove = id; $0.rollout = 0 } }
            power = power << f(s).rollout; if f(s).curled { power *= 2 }; mod(s) { $0.rollout += 1 }
        case 210: power = min(160, power << min(4, f(s).furyCutter)); mod(s) { $0.furyCutter += 1 }
        case 89: if f(t).semi == 91 { power *= 2 }
        case 57, 250: if f(t).semi == 291 { power *= 2 }
        case 16, 239: if [19, 340].contains(f(t).semi) { power *= 2 }
        case 76: if [.rain, .sand, .hail].contains(weatherOn) { power /= 2 }
        default: break
        }
        if id != 210 { mod(s) { $0.furyCutter = 0 } }
        if id != 205 && id != 301 { mod(s) { $0.rollout = 0 } }
        // hits
        var count = 1
        if m.maxHits > 1 {
            if f(s).has(92) { count = m.maxHits }
            else if m.minHits == 2 && m.maxHits == 5 { let k = roll(8); count = k < 3 ? 2 : k < 6 ? 3 : k < 7 ? 4 : 5 }
            else { count = m.minHits + roll(m.maxHits - m.minHits + 1) }
        }
        if id == 251 { count = (s == .me ? mine : theirs).filter { $0.alive && $0.status == nil }.count; type = "dark" }
        var total = 0, landed = 0
        for k in 0..<count {
            guard f(t).alive, f(s).alive else { break }
            if id == 167 && k > 0 && !hits(s, t, m) { break }                                    // 트리플킥 checks every kick
            let crit = critical(s, t, m), p = id == 167 ? 10 * (k + 1) : id == 251 ? 10 : power
            let d = calc(s, t, m, power: p, type: type, eff: eff, crit: crit)
            land(s, t, m, d, eff: eff, crit: crit); total += d; landed += 1
            if crit, f(t).alive, dAb(t, 83, by: s) { mod(t) { $0.stage[1] = 6 }; say(t, josa(tn, "은", "는") + " 분노의 경혈로 공격이 최대가 되었다!") }
        }
        if landed > 1 { say(t, "\(landed)번 맞았다!") }
        post(s, t, m, dealt: total)
    }
    /// One hit landing: substitute first; 버티기 / 칼등치기 leave 1 HP.
    mutating func land(_ s: Side, _ t: Side, _ m: MoveInfo, _ d0: Int, eff: Double, crit: Bool) {
        if f(t).sub > 0, s != t {
            let d = min(f(t).sub, d0); mod(t) { $0.sub -= d }
            say(t, "대타가 " + josa(nm(t), "을", "를") + " 대신하여 공격을 받았다!")
            if f(t).sub <= 0 { say(t, josa(nm(t), "의", "의") + " 대타는 사라져 버렸다...") }
            return
        }
        var d = min(d0, f(t).hp), endured = false
        if d >= f(t).hp, f(t).endure || m.id == 206 { d = f(t).hp - 1; endured = f(t).endure }
        out.append(.hit(t, move: m.id, damage: d, effect: eff, crit: crit)); apply(out.last!)
        if endured { say(t, josa(nm(t), "은", "는") + " 공격을 버텼다!") }
        mod(t) { $0.hitThisTurn = true; $0.lastHitDmg = d; $0.lastHitSpecial = m.special; if $0.bide > 0 { $0.bideDmg += d } }
        if f(t).rage, f(t).alive { boost(t, 1, 1, from: t) }
        if f(t).alive, dAb(t, 16, by: s), !m.type.isEmpty, !f(t).typeList.elementsEqual([m.type]) { mod(t) { $0.types = [m.type] }; say(t, josa(nm(t), "은", "는") + " " + (typeKo[m.type] ?? m.type) + " 타입이 되었다!") }
        if !f(t).alive, f(t).destinyBond { say(t, josa(nm(t), "은", "는") + " 상대를 길동무로 삼았다!"); hurt(s, f(s).hp, "") }
    }
    /// After the hits: drain / recoil, contact abilities, secondary effects, and each move's own aftermath.
    mutating func post(_ s: Side, _ t: Side, _ m: MoveInfo, dealt: Int) {
        let id = m.id, n = nm(s), tn = nm(t)
        if m.drain > 0, dealt > 0 {
            let h = max(1, dealt * m.drain / 100)
            if f(t).has(64) { hurt(s, h, josa(n, "은", "는") + " 해감액을 흡수했다!") } else { restore(s, h, josa(tn, "의", "의") + " 체력을 흡수했다!") }
        }
        if m.drain < 0, dealt > 0, !f(s).has(69), !f(s).has(98) { hurt(s, max(1, dealt * -m.drain / 100), josa(n, "은", "는") + " 반동으로 데미지를 입었다!") }
        if id == 165 { hurt(s, max(1, f(s).maxHP / 4), josa(n, "은", "는") + " 반동으로 데미지를 입었다!") }
        if [120, 153].contains(id) { hurt(s, f(s).hp, "") }
        if m.contact, dealt > 0, f(s).alive {                                                    // the defender's body abilities
            let a = f(t).ability, roll30 = pct(30)
            switch a {
            case 9 where roll30: inflict(s, .paralysis, from: t, loud: false)
            case 49 where roll30: inflict(s, .burn, from: t, loud: false)
            case 38 where roll30: inflict(s, .poison, from: t, loud: false)
            case 27 where roll30: inflict(s, [.poison, .paralysis, .sleep][roll(3)], from: t, loud: false)
            case 24: if !f(s).has(98) { hurt(s, max(1, f(s).maxHP / 8), josa(tn, "의", "의") + " 까칠한피부에 " + josa(n, "은", "는") + " 상처를 입었다!") }
            case 56 where roll30: attract(s, from: t, loud: false)
            case 106 where !f(t).alive: if !f(s).has(98) && ![mine[me], theirs[it]].contains(where: { $0.has(6) }) { hurt(s, max(1, f(s).maxHP / 4), josa(n, "은", "는") + " 유폭의 데미지를 입었다!") }
            default: break
            }
        }
        if m.recharge, f(s).alive { mod(s) { $0.recharge = true } }
        // secondary effects (not through a substitute; 인분 blocks them; 하늘의은총 doubles the odds)
        let grace = f(s).has(32) ? 2.0 : 1.0
        func odds(_ p: Int) -> Double { Double(p == 0 ? 100 : p) * grace }
        if f(t).alive, dealt > 0, f(t).sub == 0, !f(t).has(19) {
            if m.ailment != "none", m.cat == 4 || m.cat == 6 || m.cat == 0, m.ailmentChance > 0, pct(odds(m.ailmentChance)) { ailment(t, m.ailment, from: s, loud: false, move: m) }
            if id == 161, pct(odds(20)) { inflict(t, [.burn, .paralysis, .freeze][roll(3)], from: s, loud: false) }
            if id == 290, pct(odds(30)) { inflict(t, .paralysis, from: s, loud: false) }
            if m.flinch > 0, !f(t).movedThisTurn, !f(t).has(39), pct(odds(m.flinch)) { mod(t) { $0.flinch = true } }
            if m.cat == 6, !m.stats.isEmpty, m.statChance == 0 || pct(odds(m.statChance)) { for k in stride(from: 0, to: m.stats.count, by: 2) { boost(t, m.stats[k] - 1, m.stats[k + 1], from: s) } }
        }
        if m.cat == 7, f(s).alive, !m.stats.isEmpty, m.statChance == 0 || pct(odds(m.statChance)) { for k in stride(from: 0, to: m.stats.count, by: 2) { boost(s, m.stats[k] - 1, m.stats[k + 1], from: s) } }
        if f(t).alive, id == 358, f(t).status == .sleep { setStatus(t, nil, josa(tn, "은", "는") + " 눈을 떴다!") }
        if f(t).alive, id == 265, f(t).status == .paralysis { setStatus(t, nil, josa(tn, "의", "의") + " 마비가 풀렸다!") }
        if id == 229 {                                                                               // 고속스핀 clears the user's side
            sides[si(s)].spikes = 0; sides[si(s)].stealthRock = false; sides[si(s)].toxicSpikes = 0; mod(s) { $0.seeded = false; $0.bound = 0 }
        }
        if m.ailment == "trap", f(t).alive, f(t).bound == 0 { let k = 2 + roll(4); mod(t) { $0.bound = k }; say(t, josa(tn, "은", "는") + " 조임을 당했다!") }
        if [200, 37, 80].contains(id) {                                                              // 역린 난동부리기 꽃잎댄스
            if f(s).lock == 0 { let k = 2 + roll(2); mod(s) { $0.lock = k; $0.lockMove = id } }
            mod(s) { $0.lock -= 1 }
            if f(s).lock == 0 { say(s, josa(n, "은", "는") + " 지쳐서 혼란에 빠졌다!"); mod(s) { $0.confused = 0 }; confuse(s, from: nil, loud: false) }
        } else if [205, 301].contains(id) { mod(s) { $0.lock -= 1 }; if f(s).lock == 0 { mod(s) { $0.rollout = 0 } } }
        if id == 253 { if f(s).lock == 0 { let k = 2 + roll(4); mod(s) { $0.lock = k; $0.lockMove = id; $0.uproar = k }; say(s, josa(n, "은", "는") + " 소란을 피우기 시작했다!") }; mod(s) { $0.lock -= 1 } }
        if id == 255 { mod(s) { $0.stage[2] -= $0.stockpile; $0.stage[4] -= $0.stockpile; $0.stockpile = 0 } }
        if id == 99 { mod(s) { $0.rage = true } }
        if id == 369, f(s).alive, let i = nextAlive(s) { say(s, josa(n, "은", "는") + " 돌아왔다!"); switchIn(s, i) }
    }

    // MARK: status and field moves
    mutating func ailment(_ t: Side, _ a: String, from s: Side, loud: Bool, move m: MoveInfo) {
        switch a {
        case "paralysis": inflict(t, .paralysis, from: s, loud: loud)
        case "sleep": inflict(t, .sleep, from: s, loud: loud)
        case "freeze": inflict(t, .freeze, from: s, loud: loud)
        case "burn": inflict(t, .burn, from: s, loud: loud)
        case "poison": inflict(t, [92, 305].contains(m.id) ? .toxic : .poison, from: s, loud: loud)          // 맹독, 독엄니: bad poison
        case "confusion": confuse(t, from: s, loud: loud)
        case "infatuation": attract(t, from: s, loud: loud)
        case "leech-seed":
            if f(t).typeList.contains("grass") || f(t).seeded { if loud { say(t, "그러나 실패했다!") }; return }
            mod(t) { $0.seeded = true }; say(t, josa(nm(t), "에게", "에게") + " 씨앗을 심었다!")
        case "yawn": if f(t).status == nil, f(t).yawn == 0 { mod(t) { $0.yawn = 2 }; say(t, josa(nm(t), "의", "의") + " 졸음을 유도했다!") } else if loud { say(t, "그러나 실패했다!") }
        case "nightmare": if f(t).status == .sleep, !f(t).nightmare { mod(t) { $0.nightmare = true }; say(t, josa(nm(t), "은", "는") + " 악몽을 꾸기 시작했다!") } else if loud { say(t, "그러나 실패했다!") }
        case "torment": mod(t) { $0.torment = true }; say(t, josa(nm(t), "은", "는") + " 트집을 잡혔다!")
        case "disable":
            guard f(t).lastMove != 0, f(t).disable == 0 else { if loud { say(t, "그러나 실패했다!") }; return }
            let k = 4 + roll(4); mod(t) { $0.disable = k; $0.disabledMove = $0.lastMove }; say(t, josa(nm(t), "의", "의") + " " + josa(moveTable[f(t).lastMove]!.name, "을", "를") + " 사슬묶기했다!")
        case "heal-block": mod(t) { $0.healBlock = 5 }; say(t, josa(nm(t), "은", "는") + " 회복봉인 당했다!")
        case "no-type-immunity": mod(t) { $0.identified = true; $0.stage[7] = min(0, $0.stage[7]) }; say(t, josa(nm(t), "의", "의") + " 정체를 꿰뚫어 보았다!")
        case "embargo": mod(t) { $0.embargo = 5 }; say(t, josa(nm(t), "은", "는") + " 도구를 쓸 수 없게 되었다!")
        case "perish-song":
            say(t, "멸망의 노래를 들은 포켓몬은 3턴 후에 쓰러진다!")
            for x in [Side.me, .it] where f(x).perish == 0 && !f(x).has(43) { mod(x) { $0.perish = 4 } }
        case "ingrain": mod(s) { $0.ingrain = true; $0.trapped = true }; say(s, josa(nm(s), "은", "는") + " 뿌리를 내렸다!")
        case "trap": if m.isStatus { mod(t) { $0.trapped = true }; say(t, josa(nm(t), "은", "는") + " 이제 도망칠 수 없다!") }
        default: if loud { say(t, "그러나 아무 일도 일어나지 않았다!") }
        }
    }
    mutating func attract(_ t: Side, from s: Side, loud: Bool) {
        let a = f(s).mon, b = f(t).mon
        guard genderRate[a.dex] >= 0, genderRate[b.dex] >= 0, a.female != b.female, !f(t).attracted, !f(t).has(12) else { if loud { say(t, "그러나 실패했다!") }; return }
        mod(t) { $0.attracted = true }; say(t, josa(nm(t), "은", "는") + " 헤롱헤롱해졌다!")
    }
    mutating func statusMove(_ s: Side, _ t: Side, _ m: MoveInfo) {
        let id = m.id, n = nm(s), tn = nm(t)
        func fail() { say(s, "그러나 실패했다!") }
        switch m.cat {
        case 1: if f(t).sub > 0 && m.onFoe && m.ailment != "perish-song" { fail() } else { ailment(m.onSelf ? s : t, m.ailment, from: s, loud: true, move: m) }; return
        case 2:
            let who = m.onSelf ? s : t
            if id == 445, genderRate[f(s).mon.dex] < 0 || genderRate[f(t).mon.dex] < 0 || f(s).mon.female == f(t).mon.female { fail(); return }
            for k in stride(from: 0, to: m.stats.count, by: 2) { boost(who, m.stats[k] - 1, m.stats[k + 1], from: s) }
            if id == 107 { mod(s) { $0.minimized = true } }; if id == 111 { mod(s) { $0.curled = true } }
            if id == 268 { mod(s) { $0.charged = true }; say(s, josa(n, "은", "는") + " 충전했다!") }
            if id == 254 { if f(s).stockpile >= 3 { fail() } else { mod(s) { $0.stockpile += 1 }; say(s, josa(n, "은", "는") + " \(f(s).stockpile)개 비축했다!") } }
            return
        case 3:
            var p = m.healing
            if [234, 235, 236].contains(id) { p = weatherOn == .sun ? 67 : weatherOn == .clear || weatherOn == .fog ? 50 : 25 }
            if id == 256 { guard f(s).stockpile > 0 else { fail(); return }; p = [0, 25, 50, 100][f(s).stockpile]; mod(s) { $0.stage[2] -= $0.stockpile; $0.stage[4] -= $0.stockpile; $0.stockpile = 0 } }
            if id == 355 { mod(s) { $0.roosted = true } }
            if f(s).hp == f(s).maxHP { say(s, josa(n, "의", "의") + " HP는 가득하다!"); return }
            restore(s, f(s).maxHP * p / 100, josa(n, "은", "는") + " 체력을 회복했다!"); return
        case 5:
            if f(t).sub > 0 { fail(); return }
            for k in stride(from: 0, to: m.stats.count, by: 2) { boost(t, m.stats[k] - 1, m.stats[k + 1], from: s) }
            confuse(t, from: s, loud: true); return
        default: break
        }
        switch id {                                                                                  // everything with its own rule
        case 150: say(s, "그러나 아무 일도 일어나지 않았다!")
        case 182, 197, 203:
            let ok = (f(s).protectChain == 0 || roll(1 << min(8, f(s).protectChain)) == 0) && !f(other(s)).movedThisTurn   // fails when used last, and gets less likely in a row
            guard ok else { mod(s) { $0.protectChain = 0 }; fail(); return }
            mod(s) { $0.protectChain += 1; if id == 203 { $0.endure = true } else { $0.protected = true } }
            say(s, josa(n, "은", "는") + (id == 203 ? " 버티기 태세에 들어갔다!" : " 방어 태세에 들어갔다!")); return
        case 113, 115, 219, 54, 381, 366:
            let k = si(s), turns = id == 366 ? 3 : 5
            switch id {
            case 113: guard sides[k].light == 0 else { fail(); return }; sides[k].light = turns; say(s, "빛의장막으로 특수공격에 강해졌다!")
            case 115: guard sides[k].reflect == 0 else { fail(); return }; sides[k].reflect = turns; say(s, "리플렉터로 물리공격에 강해졌다!")
            case 219: guard sides[k].safeguard == 0 else { fail(); return }; sides[k].safeguard = turns; say(s, "신비의 베일에 둘러싸였다!")
            case 54: guard sides[k].mist == 0 else { fail(); return }; sides[k].mist = turns; say(s, "흰안개에 둘러싸였다!")
            case 381: guard sides[k].luckyChant == 0 else { fail(); return }; sides[k].luckyChant = turns; say(s, "행운의 주문으로 급소를 맞지 않게 되었다!")
            default: guard sides[k].tailwind == 0 else { fail(); return }; sides[k].tailwind = turns; say(s, "순풍이 불기 시작했다!")
            }
        case 114: for x in [Side.me, .it] { mod(x) { $0.stage = Array(repeating: 0, count: 8) } }; say(s, "모든 능력 변화가 원래대로 돌아왔다!")
        case 156:
            guard f(s).hp < f(s).maxHP, f(s).status != .sleep, !f(s).has(15), !f(s).has(72) else { fail(); return }
            setStatus(s, .sleep, josa(n, "은", "는") + " 잠들어 체력을 회복했다!"); mod(s) { $0.sleep = 2 }; restore(s, f(s).maxHP, "")
        case 116: guard !f(s).focus else { fail(); return }; mod(s) { $0.focus = true }; say(s, josa(n, "은", "는") + " 의욕이 넘치고 있다!")
        case 164:
            guard f(s).sub == 0, f(s).hp > f(s).maxHP / 4 else { fail(); return }
            let c = f(s).maxHP / 4; hurt(s, c, josa(n, "의", "의") + " 대타가 나타났다!"); mod(s) { $0.sub = c }
        case 18, 46:
            if dAb(t, 21, by: s) || f(t).ingrain { say(t, josa(tn, "은", "는") + " 꿈쩍도 하지 않는다!"); return }
            if trainer == nil { say(t, josa(tn, "은", "는") + " 멀리 날아갔다!"); out.append(s == .me ? .fled : .ran); over = true; return }
            let others = (t == .me ? mine : theirs).indices.filter { $0 != (t == .me ? me : it) && (t == .me ? mine : theirs)[$0].alive }
            guard !others.isEmpty else { fail(); return }
            say(t, josa(tn, "은", "는") + " 멀리 날아갔다!"); switchIn(t, others[roll(others.count)])
        case 100:
            guard trainer == nil, !f(s).trapped else { fail(); return }
            say(s, josa(n, "은", "는") + " 순간이동했다!"); out.append(s == .me ? .ran : .fled); over = true
        case 144:
            guard f(t).form == nil else { fail(); return }
            let src = f(t)
            mod(s) { $0.form = src.form ?? src.mon; $0.types = src.typeList; $0.stage = src.stage; $0.moves = src.moves; $0.pp = src.moves.map { _ in 5 }; $0.abilityOver = src.ability }
            say(s, josa(n, "은", "는") + " " + josa(monNames[src.mon.dex], "으로", "로") + " 변신했다!")
        case 102:
            guard f(t).lastMove != 0, !f(s).moves.contains(f(t).lastMove), let k = f(s).moves.firstIndex(of: 102) else { fail(); return }
            let lm = f(t).lastMove; mod(s) { $0.moves[k] = lm; $0.pp[k] = 5 }; say(s, josa(n, "은", "는") + " " + josa(moveTable[lm]!.name, "을", "를") + " 흉내 냈다!")
        case 160:
            let ts = f(s).moves.compactMap { moveTable[$0]?.type }.filter { !f(s).typeList.contains($0) && $0 != "" }
            guard let ty = ts.first else { fail(); return }; mod(s) { $0.types = [ty] }; say(s, josa(n, "은", "는") + " " + (typeKo[ty] ?? ty) + " 타입이 되었다!")
        case 176:
            guard let lt = moveTable[f(t).lastMove]?.type else { fail(); return }
            let resist = typeKo.keys.filter { (typeChart[lt]?[$0] ?? 1) < 1 }.sorted()
            guard !resist.isEmpty else { fail(); return }; let ty = resist[roll(resist.count)]; mod(s) { $0.types = [ty] }; say(s, josa(n, "은", "는") + " " + (typeKo[ty] ?? ty) + " 타입이 되었다!")
        case 293: mod(s) { $0.types = ["normal"] }; say(s, josa(n, "은", "는") + " 노말 타입이 되었다!")
        case 169, 212, 335: guard !f(t).trapped else { fail(); return }; mod(t) { $0.trapped = true }; say(t, josa(tn, "은", "는") + " 이제 도망칠 수 없다!")
        case 170, 199: mod(s) { $0.lockOn = 2 }; say(s, josa(n, "은", "는") + " " + josa(tn, "을", "를") + " 노리고 있다!")
        case 174:
            if f(s).typeList.contains("ghost") {
                guard !f(t).cursed else { fail(); return }
                hurt(s, max(1, f(s).maxHP / 2), josa(n, "은", "는") + " 자신의 체력을 깎아 " + josa(tn, "에게", "에게") + " 저주를 걸었다!"); mod(t) { $0.cursed = true }
            } else { boost(s, 5, -1, from: s); boost(s, 1, 1, from: s); boost(s, 2, 1, from: s) }
        case 180:
            guard let k = f(t).moves.firstIndex(of: f(t).lastMove), f(t).pp[k] > 0 else { fail(); return }
            let c = min(f(t).pp[k], 2 + roll(4)); mod(t) { $0.pp[k] -= c }; say(t, josa(tn + "의 " + moveTable[f(t).lastMove]!.name, "의", "의") + " PP가 \(c) 줄었다!")
        case 187:
            guard f(s).hp > f(s).maxHP / 2, f(s).stage[1] < 6 else { fail(); return }
            hurt(s, f(s).maxHP / 2, josa(n, "은", "는") + " 체력을 깎아서 공격을 최대로 올렸다!"); mod(s) { $0.stage[1] = 6 }
        case 191: guard sides[si(t)].spikes < 3 else { fail(); return }; sides[si(t)].spikes += 1; say(t, "상대 주위에 압정이 뿌려졌다!")
        case 390: guard sides[si(t)].toxicSpikes < 2 else { fail(); return }; sides[si(t)].toxicSpikes += 1; say(t, "상대 주위에 독압정이 뿌려졌다!")
        case 446: guard !sides[si(t)].stealthRock else { fail(); return }; sides[si(t)].stealthRock = true; say(t, "상대 주위에 뾰족한 바위가 떠다니기 시작했다!")
        case 194: mod(s) { $0.destinyBond = true }; say(s, josa(n, "은", "는") + " 상대를 길동무로 삼으려 하고 있다!")
        case 201, 240, 241, 258:
            let sk: Sky = [201: .sand, 240: .rain, 241: .sun, 258: .hail][id]!
            guard sky != sk else { fail(); return }
            sky = sk; skyTurns = 5; forecast()
            say(s, [201: "모래바람이 불기 시작했다!", 240: "비가 내리기 시작했다!", 241: "햇살이 강해졌다!", 258: "싸라기눈이 내리기 시작했다!"][id]!)
        case 215, 312:
            for i in (s == .me ? mine : theirs).indices { if s == .me { mine[i].status = nil } else { theirs[i].status = nil } }
            setStatus(s, nil, "동료의 상태이상이 모두 나았다!")
        case 220:
            let avg = (f(s).hp + f(t).hp) / 2, ds = f(s).hp - avg, dt = f(t).hp - avg
            if ds > 0 { hurt(s, ds, "") } else if ds < 0 { restore(s, -ds, "") }
            if dt > 0 { hurt(t, dt, "") } else if dt < 0 { restore(t, -dt, "") }
            say(s, "서로의 체력을 나누었다!")
        case 226:
            guard let i = nextAlive(s) else { fail(); return }
            say(s, josa(n, "은", "는") + " 바통을 넘겼다!"); switchIn(s, i, baton: true)
        case 227:
            guard f(t).lastMove != 0, f(t).encore == 0, ![227, 102, 165, 118].contains(f(t).lastMove) else { fail(); return }
            let k = 4 + roll(5); mod(t) { $0.encore = k; $0.encoreMove = $0.lastMove }; say(t, josa(tn, "은", "는") + " 앙코르를 받았다!")
        case 244: let st = f(t).stage; mod(s) { $0.stage = st }; say(s, josa(n, "은", "는") + " " + josa(tn, "의", "의") + " 능력 변화를 복사했다!")
        case 248, 353:
            guard sides[si(t)].future == 0 else { fail(); return }
            let m2 = moveTable[id]!, d = calc(s, t, m2, power: id == 248 ? 80 : 120, type: id == 248 ? "" : "steel", eff: id == 248 ? 1 : typeEff("steel", t, by: s), crit: false)
            sides[si(t)].future = 3; sides[si(t)].futureDmg = d; say(s, josa(n, "은", "는") + (id == 248 ? " 미래를 예지했다!" : " 파멸의 소원을 빌었다!"))
        case 262:
            hurt(s, f(s).hp, ""); boost(t, 1, -2, from: s); boost(t, 3, -2, from: s)
        case 269: guard f(t).taunt == 0 else { fail(); return }; let k = 3 + roll(3); mod(t) { $0.taunt = k }; say(t, josa(tn, "은", "는") + " 도발에 넘어갔다!")
        case 272: let a = f(t).ability; guard ![25, 36].contains(a) else { fail(); return }; mod(s) { $0.abilityOver = a }; say(s, josa(n, "은", "는") + " " + josa(abilityNames[a]!, "을", "를") + " 복사했다!")
        case 273: guard sides[si(s)].wish == 0 else { fail(); return }; sides[si(s)].wish = 2; sides[si(s)].wishHP = f(s).maxHP / 2; say(s, josa(n, "은", "는") + " 희망사항을 빌었다!")
        case 277: mod(s) { $0.magicCoat = true }; say(s, josa(n, "은", "는") + " 매직코트로 몸을 감쌌다!")
        case 285:
            let a = f(s).ability, b = f(t).ability; guard ![25, 121].contains(a), ![25, 121].contains(b) else { fail(); return }
            mod(s) { $0.abilityOver = b }; mod(t) { $0.abilityOver = a }; say(s, "서로의 특성을 바꿨다!")
        case 287: guard [.poison, .toxic, .burn, .paralysis].contains(f(s).status) else { fail(); return }; setStatus(s, nil, josa(n, "은", "는") + " 몸의 상태가 좋아졌다!")
        case 288: mod(s) { $0.grudge = true }; say(s, josa(n, "은", "는") + " 원념을 품었다!")
        case 300: mudSport = true; say(s, "전기의 위력이 약해졌다!")
        case 346: waterSport = true; say(s, "불꽃의 위력이 약해졌다!")
        case 356: guard gravity == 0 else { fail(); return }; gravity = 5; mod(.me) { $0.magnetRise = 0 }; mod(.it) { $0.magnetRise = 0 }; say(s, "중력이 강해졌다!")
        case 361, 461: guard nextAlive(s) != nil else { fail(); return }; sides[si(s)].healingWish = true; hurt(s, f(s).hp, "")
        case 367:
            let ks = (1...7).filter { f(s).stage[$0] < 6 }; guard !ks.isEmpty else { fail(); return }; boost(s, ks[roll(ks.count)], 2, from: s)
        case 375:
            guard let st = f(s).status, f(t).status == nil else { fail(); return }
            if inflict(t, st, from: s, loud: true) { setStatus(s, nil, josa(n, "의", "의") + " 상태이상이 옮겨졌다!") }
        case 380: mod(t) { $0.abilityOver = 0 }; say(t, josa(tn, "의", "의") + " 특성이 사라졌다!")
        case 388: guard !f(t).has(54), !f(t).has(121) else { fail(); return }; mod(t) { $0.abilityOver = 15 }; say(t, josa(tn, "은", "는") + " 불면 특성이 되었다!")
        case 384, 385, 391:
            let ks = id == 384 ? [1, 3] : id == 385 ? [2, 4] : Array(1...7)
            var a = f(s).stage, b = f(t).stage; for k in ks { swap(&a[k], &b[k]) }
            mod(s) { $0.stage = a }; mod(t) { $0.stage = b }; say(s, "서로의 능력 변화를 바꿨다!")
        case 379: say(s, "그러나 실패했다!")
        case 392: guard !f(s).aquaRing else { fail(); return }; mod(s) { $0.aquaRing = true }; say(s, josa(n, "은", "는") + " 물의 베일을 둘렀다!")
        case 393: guard f(s).magnetRise == 0, gravity == 0 else { fail(); return }; mod(s) { $0.magnetRise = 5 }; say(s, josa(n, "은", "는") + " 전자력으로 떠올랐다!")
        case 432:
            boost(t, 7, -1, from: s)
            let k = si(t); sides[k].reflect = 0; sides[k].light = 0; sides[k].safeguard = 0; sides[k].mist = 0; sides[k].spikes = 0; sides[k].toxicSpikes = 0; sides[k].stealthRock = false
            if sky == .fog { sky = .clear; say(s, "안개가 걷혔다!") }
        case 433: trickRoom = trickRoom > 0 ? 0 : 5; say(s, trickRoom > 0 ? "시공이 뒤틀렸다!" : "뒤틀린 시공이 원래대로 돌아왔다!")
        default: say(s, "그러나 아무 일도 일어나지 않았다!")
        }
    }
    func nextAlive(_ s: Side) -> Int? { let fs = s == .me ? mine : theirs, cur = s == .me ? me : it; return fs.indices.first { $0 != cur && fs[$0].alive } }

    // MARK: end of turn
    mutating func endOfTurn() {
        if sky != .clear, skyTurns > 0 {
            skyTurns -= 1
            if skyTurns == 0 { say(.it, ["sun": "햇살이 약해졌다!", "rain": "비가 그쳤다!", "sand": "모래바람이 가라앉았다!", "hail": "싸라기눈이 그쳤다!"]["\(sky)"] ?? ""); sky = .clear; forecast() }
        }
        for s in [Side.me, .it] where f(s).alive && !over {
            let x = f(s), n = nm(s), guardian = x.has(98)
            switch weatherOn {
            case .sand where !x.typeList.contains(where: { ["rock", "ground", "steel"].contains($0) }) && !x.has(8) && !guardian && x.semi == 0: hurt(s, max(1, x.maxHP / 16), "모래바람이 " + josa(n, "을", "를") + " 덮쳤다!")
            case .hail where !x.typeList.contains("ice"):
                if x.has(115) { restore(s, max(1, x.maxHP / 16), "") } else if !x.has(81) && !guardian && x.semi == 0 { hurt(s, max(1, x.maxHP / 16), "싸라기눈이 " + josa(n, "을", "를") + " 덮쳤다!") }
            case .rain:
                if x.has(44) { restore(s, max(1, x.maxHP / 16), "") }; if x.has(87) { restore(s, max(1, x.maxHP / 8), "") }
                if x.has(93), x.status != nil { setStatus(s, nil, josa(n, "은", "는") + " 촉촉바디로 나았다!") }
            case .sun: if (x.has(87) || x.has(94)) && !guardian { hurt(s, max(1, x.maxHP / 8), "") }
            default: break
            }
            faints()
        }
        for s in [Side.me, .it] {
            let k = si(s)
            if sides[k].future > 0 { sides[k].future -= 1; if sides[k].future == 0, f(s).alive { hurt(s, sides[k].futureDmg, josa(nm(s), "은", "는") + " 미래의 공격을 받았다!") } }
            if sides[k].wish > 0 { sides[k].wish -= 1; if sides[k].wish == 0, f(s).alive { restore(s, sides[k].wishHP, "희망사항이 이루어졌다!") } }
        }
        faints()
        for s in [Side.me, .it] where f(s).alive && !over {
            let x = f(s), n = nm(s), t = other(s), guardian = x.has(98)
            if x.ingrain { restore(s, max(1, x.maxHP / 16), josa(n, "은", "는") + " 뿌리로 양분을 흡수했다!") }
            if x.aquaRing { restore(s, max(1, x.maxHP / 16), josa(n, "은", "는") + " 물의 베일로 체력을 회복했다!") }
            if x.seeded, f(t).alive, !guardian {
                let d = min(x.hp, max(1, x.maxHP / 8)); hurt(s, d, "씨뿌리기가 " + josa(n, "의", "의") + " 체력을 빼앗는다!")
                if x.has(64) { hurt(t, d, "") } else { restore(t, d, "") }
            }
            if f(s).alive, !guardian {
                switch x.status {
                case .poison?: if x.has(90) { restore(s, max(1, x.maxHP / 8), "") } else { hurt(s, max(1, x.maxHP / 8), josa(n, "은", "는") + " 독의 데미지를 입었다!") }
                case .toxic?: if x.has(90) { restore(s, max(1, x.maxHP / 8), "") } else { hurt(s, max(1, x.maxHP * x.toxic / 16), josa(n, "은", "는") + " 독의 데미지를 입었다!"); mod(s) { $0.toxic = min(15, $0.toxic + 1) } }
                case .burn?: hurt(s, max(1, x.maxHP / 8), josa(n, "은", "는") + " 화상 데미지를 입었다!")
                default: break
                }
            }
            if f(s).alive, x.nightmare, x.status == .sleep, !guardian { hurt(s, max(1, x.maxHP / 4), josa(n, "은", "는") + " 악몽에 시달리고 있다!") }
            if f(s).alive, x.cursed, !guardian { hurt(s, max(1, x.maxHP / 4), josa(n, "은", "는") + " 저주를 받고 있다!") }
            if f(s).alive, x.bound > 0 { mod(s) { $0.bound -= 1 }; if f(s).bound == 0 { say(s, josa(n, "은", "는") + " 조임에서 풀려났다!") } else if !guardian { hurt(s, max(1, x.maxHP / 16), josa(n, "은", "는") + " 조임의 데미지를 입었다!") } }
            if f(s).alive, x.has(3), x.turnsOut > 0 { boost(s, 5, 1, from: s) }
            if f(s).alive, x.has(61), f(s).status != nil, pct(30) { setStatus(s, nil, josa(n, "은", "는") + " 탈피로 나았다!") }
            if f(s).alive, x.status == .sleep, f(t).alive, f(t).has(123), !guardian { hurt(s, max(1, x.maxHP / 8), josa(n, "은", "는") + " 나이트메어에 시달리고 있다!") }
            if f(s).alive, x.yawn > 0 { mod(s) { $0.yawn -= 1 }; if f(s).yawn == 0 { inflict(s, .sleep, from: t, loud: false) } }
            if f(s).alive, x.perish > 0 { mod(s) { $0.perish -= 1 }; say(s, josa(n, "의", "의") + " 멸망 카운트가 \(f(s).perish)이(가) 되었다!"); if f(s).perish == 0 { hurt(s, f(s).hp, "") } }
            mod(s) {
                if $0.taunt > 0 { $0.taunt -= 1 }; if $0.encore > 0 { $0.encore -= 1 }; if $0.disable > 0 { $0.disable -= 1 }
                if $0.healBlock > 0 { $0.healBlock -= 1 }; if $0.magnetRise > 0 { $0.magnetRise -= 1 }; if $0.embargo > 0 { $0.embargo -= 1 }
                if $0.lockOn > 0 { $0.lockOn -= 1 }; if $0.slowStart > 0 { $0.slowStart -= 1 }; if $0.uproar > 0 { $0.uproar -= 1 }
                $0.turnsOut += 1; $0.roosted = false; $0.rage = $0.lastMove == 99 && $0.rage
                if $0.lastMove != 182 && $0.lastMove != 197 && $0.lastMove != 203 { $0.protectChain = 0 }
            }
            faints()
        }
        for k in 0..<2 {
            let s: Side = k == 0 ? .me : .it
            for (path, text) in [(\SideState.reflect, "리플렉터"), (\SideState.light, "빛의장막"), (\SideState.safeguard, "신비의부적"), (\SideState.mist, "흰안개"), (\SideState.tailwind, "순풍"), (\SideState.luckyChant, "행운의주문")] where sides[k][keyPath: path] > 0 {
                sides[k][keyPath: path] -= 1; if sides[k][keyPath: path] == 0 { say(s, josa(text, "의", "의") + " 효과가 사라졌다!") }
            }
        }
        if trickRoom > 0 { trickRoom -= 1; if trickRoom == 0 { say(.it, "뒤틀린 시공이 원래대로 돌아왔다!") } }
        if gravity > 0 { gravity -= 1; if gravity == 0 { say(.it, "중력이 원래대로 돌아왔다!") } }
        faints()
    }

    /// KOs: EXP (and EVs) for ours, the next one out, or the end of the battle.
    mutating func faints() {
        guard !over else { return }
        if !f(.it).alive, !f(.it).down {
            mod(.it) { $0.down = true }; out.append(.fainted(.it))
            if f(.me).alive {
                let foe = f(.it).mon, e = baseExp[foe.dex] * foe.level / 7 * (trainer == nil ? 2 : 3) / 2
                var probe = f(.me).mon; let up = probe.gainBattleExp(e)
                out.append(.gained(exp: e, level: up ? probe.level : nil, foe: foe.dex)); apply(out.last!)
            }
            if let n = theirs.indices.first(where: { theirs[$0].alive }) { switchIn(.it, n) } else { out.append(.won); over = true; return }
        }
        if !f(.me).alive, !f(.me).down {
            mod(.me) { $0.down = true }; out.append(.fainted(.me))
            if let n = mine.indices.first(where: { mine[$0].alive }) { switchIn(.me, n) } else { out.append(.lost); over = true }
        }
    }

    // MARK: ball, escape, items, the other side's choice
    mutating func throwBall(_ ball: Double) -> Bool {
        let t = f(.it), bonus: Double = [.sleep, .freeze].contains(t.status) ? 2 : t.status != nil ? 1.5 : 1
        let a = Double((3 * t.maxHP - 2 * t.hp) * catchRate[t.mon.dex]) * ball * bonus / Double(3 * t.maxHP)
        let b = a >= 255 ? 65536 : 65536 / pow(255 / max(a, 0.1), 0.1875)
        var shakes = 0
        while shakes < 4, Double(roll(65536)) < b { shakes += 1 }
        out.append(.thrown(shakes: min(shakes, 3)))
        if shakes == 4 { out.append(.caught); over = true; return true }
        out.append(.broke); return false
    }
    /// Gen IV: sure if we're faster, else by the speed ratio and how many tries; trapping moves and abilities stop it.
    mutating func canEscape() -> Bool {
        let x = f(.me), y = f(.it)
        if x.has(50) { return true }
        if x.trapped || x.bound > 0 || x.ingrain || y.has(23) || (y.has(71) && grounded(.me)) || (y.has(42) && x.typeList.contains("steel")) { return false }
        let a = speed(.me), b = max(1, speed(.it)); escapes += 1
        if a >= b { return true }
        return roll(256) < (Int(a * 128 / b) + 30 * escapes) % 256
    }
    mutating func useItem(_ u: ItemUse) {
        let n = nm(.me)
        switch u {
        case .heal(let h): restore(.me, h, josa(n, "의", "의") + " 체력이 회복되었다!")
        case .restore:
            if f(.me).hp < f(.me).maxHP { restore(.me, f(.me).maxHP, josa(n, "의", "의") + " 체력이 회복되었다!") }
            if f(.me).status != nil { setStatus(.me, nil, josa(n, "은", "는") + " 건강해졌다!") }
            mod(.me) { $0.confused = 0 }
        case .cure(let sts, let conf):
            if let st = f(.me).status, sts.contains(st) || (st == .toxic && sts.contains(.poison)) { setStatus(.me, nil, josa(n, "의", "의") + " " + st.badge + " 상태가 나았다!") }
            if conf, f(.me).confused > 0 { mod(.me) { $0.confused = 0 }; say(.me, josa(n, "의", "의") + " 혼란이 풀렸다!") }
        case .pp(let k, let all):
            mod(.me) { x in
                let idx = all ? Array(x.moves.indices) : [x.moves.indices.min { x.pp[$0] < x.pp[$1] } ?? 0]
                for i in idx { x.pp[i] = min(moveTable[x.moves[i]]?.pp ?? 5, x.pp[i] + k) }
            }
            say(.me, josa(n, "의", "의") + " PP가 회복되었다!")
        case .x(let k, let by): boost(.me, k, by, from: .me)
        case .guardSpec: sides[0].mist = 5; say(.me, "흰안개에 둘러싸였다!")
        case .direHit: mod(.me) { $0.focus = true }; say(.me, josa(n, "은", "는") + " 의욕이 넘치고 있다!")
        }
    }
    /// The other side's pick. Wild ones pick at random, as in the games; a trainer mostly takes what hits hardest on paper
    /// (and sets up or heals when it makes sense), sometimes anything.
    mutating func foeChoice() -> Int {
        let x = f(.it)
        if x.charging != 0 { return x.charging }; if x.lock > 0 { return x.lockMove }; if x.bide > 0 { return 117 }
        let ok = x.moves.indices.filter { i in
            let id = x.moves[i], m = moveTable[id]!
            return x.pp[i] > 0 && !(x.disable > 0 && x.disabledMove == id) && !(x.taunt > 0 && m.isStatus) && !(x.torment && id == x.lastMove) && !(x.encore > 0 && id != x.encoreMove)
        }.map { x.moves[$0] }
        guard !ok.isEmpty else { return 165 }
        if trainer == nil || roll(5) == 0 { return ok[roll(ok.count)] }
        let d = f(.me)
        func score(_ id: Int) -> Double {
            let m = moveTable[id]!
            if m.isStatus {
                if m.cat == 1 { return d.status == nil && m.ailment != "none" ? 45 : 0 }
                if m.cat == 3 { return x.hp * 2 < x.maxHP ? 90 : 0 }
                if m.cat == 2 { return m.onSelf ? (x.stage[1] < 2 ? 35 : 0) : 20 }
                return 15
            }
            let p = m.power > 0 ? Double(m.power) : 60
            return p * (x.typeList.contains(m.type) ? 1.5 : 1) * typeEff(m.type, .me, by: .it) * Double(m.accuracy == 0 ? 100 : m.accuracy) / 100
        }
        return ok.max { score($0) < score($1) }!
    }
}

// MARK: - what the menus need
extension Battle {
    /// Ours can't pick this turn (charging, rampaging, recharging, biding, encored): the move it's stuck with.
    var forced: Int? {
        let x = mine[me]
        if x.charging != 0 { return x.charging }; if x.lock > 0 { return x.lockMove }; if x.bide > 0 { return 117 }
        if x.recharge { return x.lastMove }; if x.encore > 0 { return x.encoreMove }
        return nil
    }
    /// Whether this item would do anything for ours right now (the bag hides the rest).
    func usable(_ u: ItemUse) -> Bool {
        let x = mine[me]
        switch u {
        case .heal: return x.hp < x.maxHP
        case .restore: return x.hp < x.maxHP || x.status != nil || x.confused > 0
        case .cure(let sts, let conf): return x.status.map { sts.contains($0) || ($0 == .toxic && sts.contains(.poison)) } ?? false || (conf && x.confused > 0)
        case .pp: return x.moves.indices.contains { x.pp[$0] < (moveTable[x.moves[$0]]?.pp ?? 5) }
        case .x(let k, _): return x.stage[k] < 6
        case .guardSpec: return sides[0].mist == 0
        case .direHit: return !x.focus
        }
    }
}
