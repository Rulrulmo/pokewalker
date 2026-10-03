import Foundation
// The battle state and its plumbing: HP / status changes that emit beats, stat stages, speed.

struct Battle: Equatable, Codable {                                 // Codable: the server holds a fight and sends it (docs/plans/11 §3.3)
    var mine: [Fighter], theirs: [Fighter]
    var me = 0, it = 0
    var trainer: String? = nil
    var chain = 0                                    // radar chain this fight belongs to
    var aiRandom = 5                                 // a trainer picks at random 1 time in aiRandom (0 = never): the tower's higher tiers lower it
    var sides = [SideState(), SideState()]           // 0 ours, 1 theirs
    var sky = Sky.clear, skyTurns = 0                // skyTurns 0 with a sky = lasts (the course's weather, or an ability's)
    var trickRoom = 0, gravity = 0, mudSport = false, waterSport = false, lastUsed = 0, escapes = 0, turnNo = 0
    var out: [Beat] = [], over = false, seed: UInt64 = 1, planned = [0, 0]      // planned = each side's chosen move this turn (기습 needs it)
    var faced: Set<Int> = [0]                        // ours that have been out against their current one (they share its EXP)
    var mustReplace = false                          // ours fainted with others left: the player picks who's next (replace(_:))
    var foeSwapTurn = -9                             // when the trainer last pulled one back
    var inTurn = false, foeNext: Int? = nil          // a trainer's KO'd one is replaced once the turn is over, not mid-turn
    var subTook = false                              // the hit being resolved went into a substitute (no secondary or contact effects)
    var wild: Mon { theirs[it].mon }

    init(wild: Mon, companion: Mon, chain: Int = 0) { self.init(wild: wild, party: [companion], chain: chain) }
    init(wild: Mon, party: [Mon], chain: Int = 0) { mine = party.map(Fighter.init); theirs = [Fighter(wild)]; self.chain = chain }   // the companion first, then the walker's
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
        case .sendOut(.me, let i): mine[me].types = nil; mine[me].form = nil; me = i         // the one going back loses its 변신 / new types
        case .sendOut(.it, let i): theirs[it].types = nil; theirs[it].form = nil; it = i
        case .retype(let s, let t): mod(s) { $0.types = t }
        case .hit(let s, _, let d, _, _), .hurt(let s, let d, _): mod(s) { $0.hp = max(0, $0.hp - d) }
        case .heal(let s, let n, _): mod(s) { $0.hp = min($0.maxHP, $0.hp + n) }
        case .status(let s, let st, _): mod(s) { $0.status = st; if st != .sleep { $0.nightmare = false } }   // any wake ends 악몽
        case .gained(let e, _, let foe, let k):
            let old = mine[k].maxHP
            if mine[k].mon.gainBattleExp(e) { mine[k].hp += mine[k].maxHP - old }                    // a level-up raises current HP too
            mine[k].mon.gainEVs(from: foe)
        default: break
        }
    }
    /// HP changes go through these, so the beats replay to exactly the same state.
    mutating func hurt(_ s: Side, _ n: Int, _ text: String) { let d = min(f(s).hp, max(1, n)); out.append(.hurt(s, damage: d, text: text)); apply(out.last!) }
    mutating func restore(_ s: Side, _ n: Int, _ text: String) {
        guard f(s).healBlock == 0 else { say(s, josa(nm(s), "은", "는") + " 회복할 수 없다!"); return }
        let h = min(f(s).maxHP - f(s).hp, max(1, n)); guard h > 0 else { return }                // full: nothing to say (a heal move checks first)
        out.append(.heal(s, amount: h, text: text)); apply(out.last!)
    }
    /// After the engine changed a fighter's types: a beat, so the replay (and the panel's type badges) follow.
    mutating func retyped(_ s: Side) { let x = f(s); out.append(.retype(s, x.types ?? monTypes[(x.form ?? x.mon).dex])) }
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
    func grounded(_ s: Side) -> Bool { let x = f(s); return gravity > 0 || x.ingrain || !(x.typeList.contains("flying") || x.has(26) || x.magnetRise > 0) }

    // MARK: status and stat changes
    /// Tries to give `st` to s. Returns false (quietly, unless `loud`) when it can't stick. A substitute is the move's business (the callers check);
    /// sync = 싱크로 may pass it back (not for 독압정, which no one used).
    @discardableResult mutating func inflict(_ s: Side, _ st: Status, from: Side?, loud: Bool, sync: Bool = true) -> Bool {
        let x = f(s), n = nm(s)
        func no(_ why: String) -> Bool { if loud { say(s, why) }; return false }
        guard x.alive else { return false }
        if x.status != nil { return no(x.status == st || (st == .poison && x.status == .toxic) ? josa(n, "은", "는") + " 이미 " + st.badge + " 상태다!" : "그러나 실패했다!") }
        if from != nil, from != s, sides[si(s)].safeguard > 0 { return no(josa(n, "은", "는") + " 신비의 베일에 보호받고 있다!") }
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
        if st == .sleep { let turns = 2 + roll(4); mod(s) { $0.sleep = turns } }                       // 1-4 turns asleep (the counter runs out on the turn it wakes and moves)
        if st == .toxic { mod(s) { $0.toxic = 1 } }
        let line = ["poison": "독에 걸렸다!", "toxic": "맹독을 입었다!", "burn": "화상을 입었다!", "paralysis": "마비되어 기술이 나오기 어려워졌다!", "sleep": "잠들어 버렸다!", "freeze": "얼어붙었다!"][st.rawValue]!
        setStatus(s, st, josa(n, "은", "는") + " " + line)
        if sync, let src = from, src != s, f(s).has(28), [.poison, .toxic, .burn, .paralysis].contains(st) { inflict(src, st == .toxic ? .poison : st, from: s, loud: false) }   // 싱크로
        return true
    }
    mutating func confuse(_ s: Side, from: Side?, loud: Bool) {
        let x = f(s)
        guard x.alive else { return }
        if x.confused > 0 { if loud { say(s, josa(nm(s), "은", "는") + " 이미 혼란 상태다!") }; return }
        if x.has(20) { if loud { say(s, josa(nm(s), "은", "는") + " 마이페이스라 혼란하지 않는다!") }; return }
        if from != nil, from != s, sides[si(s)].safeguard > 0 { if loud { say(s, josa(nm(s), "은", "는") + " 신비의 베일에 보호받고 있다!") }; return }
        let n = 2 + roll(4); mod(s) { $0.confused = n }                                            // 1-4 moves confused (the last one snaps out and acts)
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
