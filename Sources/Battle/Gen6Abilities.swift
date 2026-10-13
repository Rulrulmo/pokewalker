import Foundation
// docs/plans/18 §2.3 (5.0, content5): the Gen V–VI abilities (124–191), each where its kind already happens (damage, contact, stat changes,
// switching, the end of a turn). Only Gen VI species (and hidden abilities, Mon.ability 2) carry them, so a Gen IV fight never meets one.
// Not here: 일루전 (a look only), 달마모드 · 배틀스위치 and the primal weathers (stage 5, with the forms); 치유의마음 · 프렌드가드 · 텔레파시 ·
// 공생 do nothing in singles.

extension Battle {
    /// 틀깨기 and its Gen V twins (터보블레이즈 · 테라볼티지).
    func breaksMold(_ s: Side) -> Bool { let x = f(s); return x.has(104) || x.has(163) || x.has(164) }
    /// 프리즈스킨 · 페어리스킨 · 스카이스킨: the type its Normal moves become.
    func skinType(_ s: Side) -> String? { [174: "ice", 182: "fairy", 184: "flying"][f(s).ability] }
    /// A move with an extra effect 우격다짐 takes away (for ×1.3): an ailment or flinch chance, a stat drop on the target, a boost of its own.
    func hasSecondary(_ m: MoveInfo) -> Bool {
        if [161, 290].contains(m.id) || m.flinch > 0 { return true }
        if m.cat == 4, m.ailmentChance > 0 { return true }
        if m.cat == 6, !m.stats.isEmpty { return true }
        if m.cat == 7, !m.stats.isEmpty, stride(from: 1, to: m.stats.count, by: 2).allSatisfy({ m.stats[$0] > 0 }) { return true }
        return false
    }
    func sheerForce(_ s: Side, _ m: MoveInfo) -> Bool { f(s).has(125) && hasSecondary(m) }
    /// The priority a move goes at for s: 짓궂은마음 (status +1), 질풍날개 (Flying +1).
    func priority(_ s: Side, _ id: Int) -> Int {
        let m = moveTable[id]!; var p = m.priority
        if f(s).has(158), m.isStatus { p += 1 }
        if f(s).has(177), moveType(s, m).type == "flying" { p += 1 }
        return p
    }

    // MARK: damage
    /// The abilities on a move's power (after the Gen IV ones): 우격다짐, 애널라이즈, 모래의힘, 옹골찬턱, 메가런처, 단단한발톱, the skins, 독폭주 · 열폭주, the auras.
    func gen6PowerMods(_ s: Side, _ t: Side, _ m: MoveInfo, type: String, physical phys: Bool) -> Double {
        let a = f(s); var p = 1.0
        if sheerForce(s, m) { p *= 1.3 }
        if a.has(148), f(t).movedThisTurn { p *= 1.3 }
        if a.has(159), weatherOn == .sand, ["rock", "ground", "steel"].contains(type) { p *= 1.3 }
        if a.has(173), m.flags & 8192 != 0 { p *= 1.5 }
        if a.has(178), m.flags & 16384 != 0 { p *= 1.5 }
        if a.has(181), m.contact { p *= 1.3 }
        if let sk = skinType(s), type == sk, m.type == "normal", ![165, 237, 311, 363, 449, 546].contains(m.id) { p *= 1.3 }
        if a.has(137), phys, [.poison, .toxic].contains(a.status) { p *= 1.5 }
        if a.has(138), !phys, a.status == .burn { p *= 1.5 }
        let field = [mine[me], theirs[it]].filter(\.alive), broken = field.contains { $0.has(188) }
        if type == "dark", field.contains(where: { $0.has(186) }) { p *= broken ? 0.75 : 4.0 / 3 }
        if type == "fairy", field.contains(where: { $0.has(187) }) { p *= broken ? 0.75 : 4.0 / 3 }
        return p
    }
    /// The abilities on the attacking and defending stats: 무기력 (its own at half HP), 퍼코트, 풀모피.
    func gen6StatMods(_ s: Side, _ t: Side, physical phys: Bool) -> (attack: Double, defense: Double) {
        var a = 1.0, d = 1.0
        if f(s).has(129), f(s).hp * 2 <= f(s).maxHP { a *= 0.5 }
        if phys, dAb(t, 169, by: s) { d *= 2 }
        if phys, dAb(t, 179, by: s), terrainUnder(t) == .grassy { d *= 1.5 }
        return (a, d)
    }

    // MARK: before a move
    /// The defender's abilities that stop a move before it lands (방탄, 초식) and 매직미러 (sends it back). True: handled.
    mutating func gen6Blocks(_ s: Side, _ t: Side, _ m: MoveInfo) -> Bool {
        guard m.onFoe, f(t).alive else { return false }
        if m.flags & 32768 != 0, dAb(t, 171, by: s) { say(t, josa(nm(t), "에게는", "에게는") + " 효과가 없는 것 같다..."); return true }   // 방탄
        if moveType(s, m).type == "grass", dAb(t, 157, by: s) {                                         // 초식: 공격 +1 instead
            say(t, josa(nm(t), "은", "는") + " 초식으로 기술을 받아들였다!"); boost(t, 1, 1, from: t); return true
        }
        return false
    }
    /// 변환자재: s becomes the type of the move it's about to use.
    mutating func protean(_ s: Side, _ m: MoveInfo) {
        guard f(s).has(168), m.id != 165 else { return }
        let ty = moveType(s, m).type
        guard !ty.isEmpty, f(s).typeList != [ty] else { return }
        mod(s) { $0.types = [ty]; $0.addedType = nil }; retyped(s); say(s, josa(nm(s), "은", "는") + " " + (typeKo[ty] ?? ty) + " 타입이 되었다!")
    }

    // MARK: after a hit
    /// After s's damaging move hit t: the defender's (저주받은바디, 깨어진갑옷, 정의의마음, 주눅, and on contact 나쁜손버릇 · 미라 · 철가시 · 미끈미끈)
    /// and the attacker's (독수, 자기과신, 매지션).
    mutating func gen6AbilitiesAfterHit(_ s: Side, _ t: Side, _ m: MoveInfo, dealt: Int) {
        guard dealt > 0, !subTook else { return }
        let n = nm(s), tn = nm(t), type = moveType(s, m).type
        if f(t).alive {
            if f(t).has(130), f(s).alive, f(s).disable == 0, f(s).moves.contains(m.id), pct(30) {      // 저주받은바디
                mod(s) { $0.disable = 4; $0.disabledMove = m.id }; say(s, josa(n + "의 " + m.name, "은", "는") + " 사용할 수 없게 되었다!")
            }
            if f(t).has(133), m.physical { boost(t, 2, -1, from: t); boost(t, 5, 1, from: t) }             // 깨어진갑옷
            if f(t).has(154), type == "dark" { boost(t, 1, 1, from: t) }                                   // 정의의마음
            if f(t).has(155), ["dark", "ghost", "bug"].contains(type) { boost(t, 5, 1, from: t) }           // 주눅
        }
        if m.contact, f(s).alive {
            switch f(t).ability {
            case 124 where f(t).alive && f(t).item == nil && f(s).item != nil && !keeps(s, by: t):        // 나쁜손버릇
                if let i = takeItem(s) { giveItem(t, i); say(t, josa(tn, "은", "는") + " " + josa(n + "의 " + i, "을", "를") + " 빼앗았다!") }
            case 152 where ![121, 152, 176].contains(f(s).ability):                                         // 미라
                mod(s) { $0.abilityOver = 152 }; say(s, josa(n, "의", "의") + " 특성이 미라가 되었다!")
            case 160 where !f(s).has(98): hurt(s, max(1, f(s).maxHP / 8), josa(tn, "의", "의") + " 철가시에 " + josa(n, "은", "는") + " 상처를 입었다!")   // 철가시
            case 183: boost(s, 5, -1, from: t)                                                              // 미끈미끈
            default: break
            }
            if f(s).has(143), f(t).alive, pct(30) { inflict(t, .poison, from: s, loud: false) }             // 독수
        }
        if f(s).alive, f(s).has(153), !f(t).alive { boost(s, 1, 1, from: s) }                              // 자기과신
        if f(s).alive, f(s).has(170), f(s).item == nil, f(t).item != nil, !keeps(t, by: s), let i = takeItem(t) {   // 매지션
            giveItem(s, i); say(s, josa(n, "은", "는") + " " + josa(tn, "에게서", "에게서") + " " + josa(i, "을", "를") + " 빼앗았다!")
        }
    }

    // MARK: switching, the end of a turn
    /// 재생력: a third of its HP back as it leaves.
    mutating func regenerate(_ s: Side) { if f(s).has(144), f(s).alive, f(s).hp < f(s).maxHP { restore(s, max(1, f(s).maxHP / 3), "") } }
    /// The end of a turn's Gen V–VI abilities: 변덕쟁이 (+2 one stat, -1 another), 수확 (its berry back, 50 % or in the sun always).
    mutating func gen6AbilitiesEndOfTurn(_ s: Side) {
        guard f(s).alive else { return }
        if f(s).has(141) {
            let up = (1...7).filter { f(s).stage[$0] < 6 }
            if let k = up.isEmpty ? nil : up[roll(up.count)] {
                boost(s, k, 2, from: s)
                let down = (1...7).filter { $0 != k && f(s).stage[$0] > -6 }
                if !down.isEmpty { boost(s, down[roll(down.count)], -1, from: s) }
            }
        }
        if f(s).has(139), f(s).item == nil, let b = f(s).spent, b.hasSuffix("열매"), weatherOn == .sun || pct(50) {
            mod(s) { $0.item = b; $0.spent = nil }; say(s, josa(nm(s), "은", "는") + " " + josa(b, "을", "를") + " 수확했다!")
        }
    }
}
