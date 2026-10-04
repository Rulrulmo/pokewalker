import Foundation
// Accuracy, type effectiveness, criticals, the Gen IV damage formula, and what damaging moves do.

extension Battle {
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
        if [26, 136].contains(m.id), !f(s).has(98) {                                              // half of what it would have done (on an immune one: as if it hit for its full HP), at most half the target's max HP
            let e = typeEff(m.type, t, by: s), d = e == 0 ? f(t).maxHP : calc(s, t, m, power: m.power, type: m.type, eff: e, crit: false)
            hurt(s, min(max(1, d / 2), max(1, f(t).maxHP / 2)), josa(nm(s), "은", "는") + " 기세 좋게 넘어졌다!")
        }
        if [120, 153].contains(m.id) { hurt(s, f(s).hp, "") }
    }
    mutating func hits(_ s: Side, _ t: Side, _ m: MoveInfo) -> Bool {
        if [12, 32, 90, 329].contains(m.id) {                                                      // one-hit KOs: never on a higher level or 옹골참; then 노가드 / 록온 make sure
            guard f(t).mon.level <= f(s).mon.level, !dAb(t, 5, by: s) else { return false }
            if f(s).has(99) || f(t).has(99) || f(s).lockOn > 0 { return true }
            return roll(100) < 30 + f(s).mon.level - f(t).mon.level
        }
        if m.accuracy == 0 || f(s).has(99) || f(t).has(99) || f(s).lockOn > 0 { return true }
        var acc = Double(m.accuracy)
        if m.id == 87 { if weatherOn == .rain { return true }; if weatherOn == .sun { acc = 50 } }
        if m.id == 59, weatherOn == .hail { return true }
        let evas = f(s).has(109) || f(t).identified || f(t).miracleEye ? 0 : f(t).stage[7], accu = dAb(t, 109, by: s) ? 0 : f(s).stage[6]
        acc *= accMult(accu - evas)
        if f(s).has(14) { acc *= 1.3 }; if f(s).has(55), m.physical { acc *= 0.8 }
        if weatherOn == .sand, dAb(t, 8, by: s) { acc *= 0.8 }; if weatherOn == .hail, dAb(t, 81, by: s) { acc *= 0.8 }
        if dAb(t, 77, by: s), f(t).confused > 0 { acc *= 0.5 }
        if gravity > 0 { acc *= 5.0 / 3 }; if weatherOn == .fog { acc *= 0.6 }
        acc *= itemAccuracy(s, t)
        return Double(roll(100)) < acc
    }
    func typeEff(_ type: String, _ t: Side, by s: Side) -> Double {
        guard !type.isEmpty else { return 1 }
        var e = 1.0
        for dt in f(t).typeList {
            var x = typeChart[type]?[dt] ?? 1
            if x == 0, dt == "ghost", type == "normal" || type == "fighting", f(s).has(113) || f(t).identified { x = 1 }
            if x == 0, dt == "dark", type == "psychic", f(t).miracleEye { x = 1 }
            if x == 0, dt == "flying", type == "ground", grounded(t) { x = 1 }                           // 중력, 뿌리박기
            e *= x
        }
        if type == "ground", !grounded(t), !(f(s).has(104) && f(t).has(26) && f(t).magnetRise == 0 && !f(t).typeList.contains("flying")) { e = 0 }
        return e
    }
    mutating func critical(_ s: Side, _ t: Side, _ m: MoveInfo) -> Bool {
        if dAb(t, 4, by: s) || dAb(t, 75, by: s) || sides[si(t)].luckyChant > 0 { return false }
        let st = min(4, m.crit + (f(s).focus ? 2 : 0) + (f(s).has(105) ? 1 : 0) + itemCrit(s))
        return roll([16, 8, 4, 3, 2][st]) == 0
    }
    /// Gen IV damage: base, then burn, screens, weather, +2, crit, random, STAB, type, 필터/색안경 — rounding down after each, as DPPt/HGSS do.
    mutating func calc(_ s: Side, _ t: Side, _ m: MoveInfo, power: Int, type: String, eff: Double, crit: Bool) -> Int {
        let a = f(s), d = f(t), phys = m.physical || m.id == 165
        var A = Double(base(s, phys ? 1 : 3)), D = Double(base(t, phys ? 2 : 4))
        var aS = a.stage[phys ? 1 : 3], dS = d.stage[phys ? 2 : 4]
        if crit { aS = max(0, aS); dS = min(0, dS) }
        if dAb(t, 109, by: s) { aS = 0 }; if a.has(109) { dS = 0 }
        A *= mult(aS) * itemAttack(s, physical: phys); D *= mult(dS) * itemDefense(t, physical: phys)
        if phys {
            if a.has(37) || a.has(74) { A *= 2 }; if a.has(55) { A *= 1.5 }; if a.has(62), a.status != nil { A *= 1.5 }
            if a.slowStart > 0 { A *= 0.5 }; if weatherOn == .sun, a.has(122) { A *= 1.5 }
            if dAb(t, 63, by: s), d.status != nil { D *= 1.5 }
        } else {
            if weatherOn == .sun, a.has(94) { A *= 1.5 }
            if weatherOn == .sand, d.typeList.contains("rock") { D *= 1.5 }; if weatherOn == .sun, dAb(t, 122, by: s) { D *= 1.5 }
        }
        if [120, 153].contains(m.id) { D *= 0.5 }
        if dAb(t, 47, by: s), type == "fire" || type == "ice" { A *= 0.5 }
        if a.flashFire, type == "fire" { A *= 1.5 }
        var P = Double(power)
        if a.has(101), power <= 60 { P *= 1.5 }; if a.has(89), m.punch { P *= 1.2 }; if a.has(120), m.drain < 0 || [26, 136].contains(m.id) { P *= 1.2 }
        if a.hp * 3 <= a.maxHP, (type == "grass" && a.has(65)) || (type == "fire" && a.has(66)) || (type == "water" && a.has(67)) || (type == "bug" && a.has(68)) { P *= 1.5 }
        if a.has(79), genderRate[a.mon.dex] >= 0, genderRate[d.mon.dex] >= 0 { P *= a.mon.female == d.mon.female ? 1.25 : 0.75 }
        if dAb(t, 85, by: s), type == "fire" { P *= 0.5 }; if dAb(t, 87, by: s), type == "fire" { P *= 1.25 }
        if a.charge > 0, type == "electric" { P *= 2 }; if mudSport, type == "electric" { P *= 0.5 }; if waterSport, type == "fire" { P *= 0.5 }
        P = floor(P * itemPower(s, physical: phys, type: type))
        var x = floor(floor(Double(2 * a.mon.level / 5 + 2) * P * A / max(1, D)) / 50)
        if a.status == .burn, phys, !a.has(62) { x = floor(x / 2) }
        if !crit, (phys && sides[si(t)].reflect > 0) || (!phys && sides[si(t)].light > 0) { x = floor(x / 2) }
        if weatherOn == .rain { if type == "water" { x *= 1.5 }; if type == "fire" { x *= 0.5 } }
        if weatherOn == .sun { if type == "fire" { x *= 1.5 }; if type == "water" { x *= 0.5 } }
        x += 2
        if crit { x *= a.has(97) ? 3 : 2 }
        x = floor(x * itemDamage(s))                                                                 // 생명의구슬 · 메트로놈
        x = floor(x * Double(85 + roll(16)) / 100)                                                  // Gen III-IV: 85-100 %
        if !type.isEmpty, a.typeList.contains(type) { x = floor(x * (a.has(91) ? 2 : 1.5)) }        // each step rounds down
        x = floor(x * eff)
        if eff > 1, dAb(t, 111, by: s) || dAb(t, 116, by: s) { x = floor(x * 0.75) }
        if eff < 1, a.has(110) { x *= 2 }
        if eff > 1, holds(s, "달인의띠") { x = floor(x * 1.2) }
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
    /// The type (and power) a move really has when s uses it: 노말스킨, 발버둥 (typeless), 잠재파워, 웨더볼, 심판의뭉치.
    func moveType(_ s: Side, _ m: MoveInfo) -> (type: String, power: Int) {
        let id = m.id
        var type = m.type, power = m.power
        if id == 165 { type = "" }
        if id == 237 { (type, power) = hiddenPower(f(s).mon) }
        if id == 311 { switch weatherOn { case .sun: type = "fire"; power = 100; case .rain: type = "water"; power = 100; case .sand: type = "rock"; power = 100; case .hail: type = "ice"; power = 100; case .fog: power = 100; default: break } }
        if id == 284 || id == 323 { power = max(1, 150 * f(s).hp / f(s).maxHP) }                   // 분화 / 해수스파우팅: by the HP left
        if id == 449, let p = held(s).flatMap({ Held.plates[$0] }) { type = p }                    // 심판의뭉치: its plate's type
        if id == 363, let g = held(s).flatMap({ Held.gift[$0] }) { (type, power) = g }             // 자연의은혜: its berry's
        if f(s).has(96), id != 165 { type = "normal" }                                             // 노말스킨 last: it turns even those Normal (심판의뭉치 without plates is Normal anyway)
        return (type, power)
    }
    mutating func damageMove(_ s: Side, _ t: Side, _ m: MoveInfo) {
        let id = m.id, n = nm(s), tn = nm(t)
        subTook = false
        var (type, power) = moveType(s, m)
        // immunity abilities first
        if !type.isEmpty {
            if (type == "water" && (dAb(t, 11, by: s) || dAb(t, 87, by: s))) || (type == "electric" && dAb(t, 10, by: s)) {
                let ab = abilityNames[f(t).ability]!
                if f(t).hp < f(t).maxHP { restore(t, f(t).maxHP / 4, josa(tn, "은", "는") + " " + josa(ab, "으로", "로") + " 회복했다!") } else { say(t, josa(tn, "에게는", "에게는") + " 효과가 없는 것 같다...") }
                return }
            if type == "electric", dAb(t, 78, by: s) { say(t, josa(tn, "은", "는") + " 전기엔진이 작동했다!"); boost(t, 5, 1, from: t); return }
            if type == "fire", dAb(t, 18, by: s) { mod(t) { $0.flashFire = true }; say(t, josa(tn, "은", "는") + " 타오르는불꽃으로 불꽃 기술의 위력이 올라갔다!"); return }
        }
        let eff = typeEff(type, t, by: s)
        if eff == 0 { say(t, tn + "에게는 효과가 없는 것 같다..."); crash(s, t, m); return }
        if dAb(t, 25, by: s), eff <= 1, !type.isEmpty { say(t, josa(tn, "은", "는") + " 불가사의부적으로 공격을 받지 않는다!"); return }
        if id == 138, f(t).status != .sleep { say(t, josa(tn, "은", "는") + " 잠들어 있지 않다!"); return }
        if id == 173, f(s).status != .sleep { say(s, "그러나 실패했다!"); return }
        if id == 252, f(s).turnsOut > 1 { say(s, "그러나 실패했다!"); return }                         // 속이기: its first turn out only
        if id == 264, f(s).hitThisTurn { say(s, josa(n, "은", "는") + " 집중이 흐트러져서 기술을 쓸 수 없다!"); return }
        if id == 389, f(t).movedThisTurn || (moveTable[planned[si(t)]]?.isStatus ?? true) { say(s, "그러나 실패했다!"); return }
        if id == 364, !f(t).protected { say(s, "그러나 실패했다!"); return }
        if [120, 153].contains(id), !f(s).has(104), [mine[me], theirs[it]].contains(where: { $0.has(6) }) { say(s, "습기 때문에 " + josa(m.name, "을", "를") + " 쓸 수 없다!"); return }
        if id == 255 && f(s).stockpile == 0 { say(s, "그러나 비축하지 못했다!"); return }
        if id == 363, held(s).flatMap({ Held.gift[$0] }) == nil { say(s, "그러나 실패했다!"); return }
        var thrown: String? = nil
        if id == 374 {                                                                               // 내던지기: what it holds, gone whatever happens next
            guard let i = held(s), let p = Held.fling(i), !fixedItem(s) else { say(s, "그러나 실패했다!"); return }
            thrown = i; power = p; useUp(s); say(s, josa(n, "은", "는") + " " + josa(i, "을", "를") + " 내던졌다!")
        }
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
        let tw = weightKg[f(t).mon.dex]
        switch id {
        case 67, 447: power = tw < 10 ? 20 : tw < 25 ? 40 : tw < 50 ? 60 : tw < 100 ? 80 : tw < 200 ? 100 : 120
        case 175, 179: let p = 48 * f(s).hp / f(s).maxHP; power = p <= 1 ? 200 : p <= 4 ? 150 : p <= 9 ? 100 : p <= 16 ? 80 : p <= 32 ? 40 : 20
        case 378, 462: power = 1 + 120 * f(t).hp / f(t).maxHP
        case 216, 218: let fr = min(255, 70 + (f(s).mon.walked ?? 0) / 100); power = max(1, (id == 216 ? fr : 255 - fr) * 10 / 25)
        case 222: let k = roll(100); let i = [5, 15, 35, 65, 85, 95, 100].firstIndex { k < $0 }!; power = [10, 30, 50, 70, 90, 110, 150][i]; say(s, "매그니튜드 \(i + 4)!"); if f(t).semi == 91 { power *= 2 }
        case 360: power = min(150, 1 + Int(25 * speed(t) / max(1, speed(s))))
        case 386: power = min(200, 60 + 20 * f(t).stage[1...7].filter { $0 > 0 }.reduce(0, +))
        case 376: let left = f(s).moves.firstIndex(of: id).map { f(s).pp[$0] } ?? 0; power = [200, 80, 60, 50][min(3, left)] ; if left > 3 { power = 40 }
        case 255: power = 100 * f(s).stockpile
        case 217: let k = roll(10); if k < 2 { restore(t, 80, josa(tn, "의", "의") + " 체력이 회복되었다!"); return }; power = k < 6 ? 40 : k < 9 ? 80 : 120
        case 263: if [.poison, .toxic, .burn, .paralysis].contains(f(s).status) { power *= 2 }   // not asleep / frozen
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
        if id != 205 && id != 301 { mod(s) { $0.rollout = 0 } }
        // hits
        var count = 1
        if m.maxHits > 1 {
            if f(s).has(92) { count = m.maxHits }
            else if m.minHits == 2 && m.maxHits == 5 { let k = roll(8); count = k < 3 ? 2 : k < 6 ? 3 : k < 7 ? 4 : 5 }
            else { count = m.minHits + roll(m.maxHits - m.minHits + 1) }
        }
        if id == 251 { count = (s == .me ? mine : theirs).filter { $0.alive && $0.status == nil }.count; type = "dark"; if count == 0 { say(s, "그러나 실패했다!"); return } }
        var total = 0, landed = 0
        for k in 0..<count {
            guard f(t).alive, f(s).alive else { break }
            if id == 167 && k > 0 && !hits(s, t, m) { break }                                    // 트리플킥 checks every kick
            let crit = critical(s, t, m), p = id == 167 ? 10 * (k + 1) : id == 251 ? 10 : power
            let d = resistBerry(t, type: type, eff: eff, calc(s, t, m, power: p, type: type, eff: eff, crit: crit))
            land(s, t, m, d, eff: eff, crit: crit); total += d; landed += 1
            if crit, f(t).alive, dAb(t, 83, by: s) { mod(t) { $0.stage[1] = 6 }; say(t, josa(tn, "은", "는") + " 분노의 경혈로 공격이 최대가 되었다!") }
        }
        if landed > 1 { say(t, "\(landed)번 맞았다!") }
        if let i = thrown { flung(i, at: t, from: s) }
        post(s, t, m, dealt: total)
    }
    /// One hit landing: substitute first; 버티기 / 칼등치기 leave 1 HP.
    mutating func land(_ s: Side, _ t: Side, _ m: MoveInfo, _ d0: Int, eff: Double, crit: Bool) {
        if f(t).sub > 0, s != t {
            let d = min(f(t).sub, d0); mod(t) { $0.sub -= d }; subTook = true
            say(t, "대타가 " + josa(nm(t), "을", "를") + " 대신하여 공격을 받았다!")
            if f(t).sub <= 0 { say(t, josa(nm(t), "의", "의") + " 대타는 사라져 버렸다...") }
            return
        }
        subTook = false                                                                              // this hit reached the Pokémon (a multi-hit's later ones after the sub broke)
        var d = min(d0, f(t).hp), endured = false, hung: String? = nil
        if d >= f(t).hp, f(t).endure || m.id == 206 { d = f(t).hp - 1; endured = f(t).endure }
        else if let line = hangOn(t, d) { d = f(t).hp - 1; hung = line }                           // 기합의띠 / 기합의머리띠
        out.append(.hit(t, move: m.id, damage: d, effect: eff, crit: crit)); apply(out.last!)
        if endured { say(t, josa(nm(t), "은", "는") + " 공격을 버텼다!") }
        if let hung { say(t, hung) }
        heldCheck(t)
        mod(t) { $0.hitThisTurn = true; $0.lastHitDmg = d; $0.lastHitSpecial = m.special; if $0.bide > 0 { $0.bideDmg += d } }
        if f(t).rage, f(t).alive { boost(t, 1, 1, from: t) }
        let ty = moveType(s, m).type                                                                 // 변색: the type it really had
        if f(t).alive, dAb(t, 16, by: s), !ty.isEmpty, !f(t).typeList.elementsEqual([ty]) { mod(t) { $0.types = [ty] }; retyped(t); say(t, josa(nm(t), "은", "는") + " " + (typeKo[ty] ?? ty) + " 타입이 되었다!") }
        if !f(t).alive, f(t).destinyBond { say(t, josa(nm(t), "은", "는") + " 상대를 길동무로 삼았다!"); hurt(s, f(s).hp, "") }
        if !f(t).alive, f(t).grudge, let k = f(s).moves.firstIndex(of: m.id) { mod(s) { $0.pp[k] = 0 }; say(s, josa(nm(s) + "의 " + m.name, "은", "는") + " 원념으로 PP가 0이 되었다!") }
    }
    /// After the hits: drain / recoil, contact abilities, secondary effects, and each move's own aftermath.
    mutating func post(_ s: Side, _ t: Side, _ m: MoveInfo, dealt: Int) {
        let id = m.id, n = nm(s), tn = nm(t)
        if m.drain > 0, dealt > 0 {
            let h = max(1, dealt * m.drain / 100 * (holds(s, "큰뿌리") ? 13 : 10) / 10)
            if f(t).has(64) { hurt(s, h, josa(n, "은", "는") + " 해감액을 흡수했다!") } else { restore(s, h, josa(tn, "의", "의") + " 체력을 흡수했다!") }
        }
        if m.drain < 0, dealt > 0, !f(s).has(69), !f(s).has(98) { hurt(s, max(1, dealt * -m.drain / 100), josa(n, "은", "는") + " 반동으로 데미지를 입었다!") }
        if id == 165 { hurt(s, max(1, f(s).maxHP / 4), josa(n, "은", "는") + " 반동으로 데미지를 입었다!") }
        if [120, 153].contains(id) { hurt(s, f(s).hp, "") }
        if m.contact, dealt > 0, !subTook, f(s).alive {                                                    // the defender's body abilities
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
        if f(t).alive, dealt > 0, !subTook, !dAb(t, 19, by: s) {
            for _ in 0..<(id == 41 ? 2 : 1) where m.ailment != "none" && (m.cat == 4 || m.cat == 6 || m.cat == 0) && m.ailmentChance > 0 { if pct(odds(m.ailmentChance)) { ailment(t, m.ailment, from: s, loud: false, move: m) } }   // 더블니들: a roll a needle
            if id == 161, pct(odds(20)) { inflict(t, [.burn, .paralysis, .freeze][roll(3)], from: s, loud: false) }
            if id == 290, pct(odds(30)) { inflict(t, .paralysis, from: s, loud: false) }
            if m.flinch > 0, !f(t).movedThisTurn, !dAb(t, 39, by: s), pct(odds(m.flinch)) { mod(t) { $0.flinch = true } }
            if m.cat == 6, !m.stats.isEmpty, m.statChance == 0 || pct(odds(m.statChance)) { for k in stride(from: 0, to: m.stats.count, by: 2) { boost(t, m.stats[k] - 1, m.stats[k + 1], from: s) } }
        }
        if m.cat == 7, f(s).alive, !m.stats.isEmpty, m.statChance == 0 || pct(odds(m.statChance)) { for k in stride(from: 0, to: m.stats.count, by: 2) { boost(s, m.stats[k] - 1, m.stats[k + 1], from: s) } }
        if f(t).alive, !subTook, f(t).status == .freeze, dealt > 0, moveType(s, m).type == "fire" { setStatus(t, nil, josa(tn, "의", "의") + " 얼음이 녹았다!") }   // a fire hit thaws it
        if f(t).alive, !subTook, id == 358, f(t).status == .sleep { setStatus(t, nil, josa(tn, "은", "는") + " 눈을 떴다!") }
        if f(t).alive, !subTook, id == 265, f(t).status == .paralysis { setStatus(t, nil, josa(tn, "의", "의") + " 마비가 풀렸다!") }
        if id == 229 {                                                                               // 고속스핀 clears the user's side
            sides[si(s)].spikes = 0; sides[si(s)].stealthRock = false; sides[si(s)].toxicSpikes = 0; mod(s) { $0.seeded = false; $0.bound = 0 }
        }
        if m.ailment == "trap", f(t).alive, !subTook, f(t).bound == 0 {                            // each binding move its own line (one "조임" for all read as 조이기 on a ghost)
            let k = holds(s, "끈기갈고리손톱") ? 6 : 3 + roll(4); mod(t) { $0.bound = k; $0.boundBy = id }   // 2-5 turns of damage (끈기갈고리손톱: 5)
            let caught = switch id {
            case 20: n + "에게 조이기를 당했다!"
            case 35: n + "에게 김밥말이를 당했다!"
            case 83: "불꽃의 소용돌이에 갇혔다!"
            case 128: josa(n, "의", "의") + " 껍질에 끼였다!"
            case 250: "소용돌이에 갇혔다!"
            case 328: "모래지옥에 갇혔다!"
            case 463: "마그마의 소용돌이에 갇혔다!"
            default: josa(m.name, "에", "에") + " 갇혔다!"
            }
            say(t, josa(tn, "은", "는") + " " + caught)
        }
        if [200, 37, 80].contains(id) {                                                              // 역린 난동부리기 꽃잎댄스
            if f(s).lock == 0 { let k = 2 + roll(2); mod(s) { $0.lock = k; $0.lockMove = id } }
            mod(s) { $0.lock -= 1 }
            if f(s).lock == 0, f(s).confused == 0, !f(s).has(20) { let c = 2 + roll(4); mod(s) { $0.confused = c }; say(s, josa(n, "은", "는") + " 지쳐서 혼란에 빠졌다!") }   // one line; 마이페이스 stays clear
        } else if [205, 301].contains(id) { mod(s) { $0.lock -= 1 }; if f(s).lock == 0 { mod(s) { $0.rollout = 0 } } }
        if id == 253 { if f(s).lock == 0 { let k = 2 + roll(4); mod(s) { $0.lock = k; $0.lockMove = id; $0.uproar = k }; say(s, josa(n, "은", "는") + " 소란을 피우기 시작했다!") }; mod(s) { $0.lock -= 1 } }
        if id == 255 { let k = f(s).stockpile; mod(s) { $0.stockpile = 0 }; boost(s, 2, -k, from: s); boost(s, 4, -k, from: s) }   // the stock's 방어 / 특수방어 back
        if id == 99 { mod(s) { $0.rage = true } }
        itemsAfterHit(s, t, m, dealt: dealt)
        if id == 369, f(s).alive, nextAlive(s) != nil { faints(); if !over, f(s).alive, let i = nextAlive(s) { say(s, josa(n, "은", "는") + " 돌아왔다!"); switchIn(s, i) } }   // a KO (and its EXP) before the switch
    }

}
