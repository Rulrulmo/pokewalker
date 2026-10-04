import Foundation
// Held items in battle (docs/plans/13 ⑤), Gen IV's: what they do to stats, power, order, accuracy and crits; the berries and herbs;
// the end-of-turn ones; the item moves (트릭 바꿔치기 내던지기 자연의은혜 리사이클 탁쳐서떨구기 도둑질 탐내다 쪼아대기 벌레먹기).
// 서투름 and 금제 switch a holder's item off; 점착 keeps it from being taken; 곡예 doubles speed once it's gone; 통찰 tells the other's.
// What's used up is gone for good after a wild or raid fight (the Mon's own item, Fighter.spentOwn); what was taken or swapped comes back.

extension Battle {
    // MARK: who holds what
    /// The item s holds, if it does anything now (not under 서투름 / 금제).
    func held(_ s: Side) -> String? { let x = f(s); return x.has(103) || x.embargo > 0 ? nil : x.item }
    func holds(_ s: Side, _ i: String) -> Bool { held(s) == i }
    /// Its species' own item (전기구슬 on 피카츄 …; not once it has 변신ed).
    func holdsFor(_ s: Side, _ i: String) -> Bool { holds(s, i) && f(s).form == nil && Held.species[i]?.contains(f(s).mon.dex) == true }
    /// Its item can't be taken or swapped: 점착 (틀깨기 walks past it), 아르세우스's plate, 기라티나's 백금옥.
    func keeps(_ t: Side, by s: Side) -> Bool { dAb(t, 60, by: s) || fixedItem(t) }
    func fixedItem(_ s: Side) -> Bool { let x = f(s); return x.item.map { Held.plates[$0] != nil && x.mon.dex == 493 || $0 == "백금옥" && x.mon.dex == 487 } == true }
    /// s's item is used up (eaten, a herb, 기합의띠, thrown): 리사이클 remembers it; its own is gone after a wild fight.
    mutating func useUp(_ s: Side) {
        mod(s) { x in
            guard let i = x.item else { return }
            x.spent = i; x.spentOwn = i == x.mon.item ? true : nil
            if i == x.mon.item { x.mon.item = nil }
            x.item = nil; x.choice = nil
            if x.has(84) { x.unburden = true }
        }
    }
    /// s's item is taken off it (탁쳐서떨구기, 도둑질, 트릭, 벌레먹기): its own comes back after the fight.
    @discardableResult mutating func takeItem(_ s: Side) -> String? {
        let i = f(s).item
        mod(s) { x in x.item = nil; x.choice = nil; if i != nil, x.has(84) { x.unburden = true } }
        return i
    }
    mutating func giveItem(_ s: Side, _ i: String?) { mod(s) { $0.item = i; $0.choice = nil; if i != nil { $0.unburden = nil } } }

    // MARK: stats, power, order, accuracy, crits
    /// Speed: 구애스카프 ×1.5, 스피드파우더 ×2 (메타몽), 곡예 ×2 once its item's gone; 검은철구, 교정깁스 and the 파워 items halve it (even under 서투름).
    func itemSpeed(_ s: Side) -> Double {
        let x = f(s); var v = 1.0
        if let i = x.item, i == "검은철구" || i == "교정깁스" || Held.power[i] != nil { v *= 0.5 }
        if holds(s, "구애스카프") { v *= 1.5 }
        if holdsFor(s, "스피드파우더") { v *= 2 }
        if x.unburden == true, x.item == nil, x.has(84) { v *= 2 }
        return v
    }
    /// The attacker's stat: 구애머리띠 / 구애안경 ×1.5, 전기구슬 ×2 (피카츄), 굵은뼈 ×2 (탕구리 · 텅구리), 심해의이빨 ×2 (진주몽), 마음의물방울 ×1.5 (라티아스 · 라티오스).
    func itemAttack(_ s: Side, physical: Bool) -> Double {
        if physical { return holds(s, "구애머리띠") ? 1.5 : holdsFor(s, "전기구슬") || holdsFor(s, "굵은뼈") ? 2 : 1 }
        return holds(s, "구애안경") ? 1.5 : holdsFor(s, "전기구슬") || holdsFor(s, "심해의이빨") ? 2 : holdsFor(s, "마음의물방울") ? 1.5 : 1
    }
    /// The defender's: 금속파우더 ×2 방어 (메타몽), 심해의비늘 ×2 특수방어 (진주몽), 마음의물방울 ×1.5 특수방어.
    func itemDefense(_ t: Side, physical: Bool) -> Double {
        if physical { return holdsFor(t, "금속파우더") ? 2 : 1 }
        return holdsFor(t, "심해의비늘") ? 2 : holdsFor(t, "마음의물방울") ? 1.5 : 1
    }
    /// Base power: its type's item ×1.2, 힘의머리띠 / 박식안경 ×1.1, the three orbs ×1.2 to their own pair of types.
    func itemPower(_ s: Side, physical: Bool, type: String) -> Double {
        guard let i = held(s), !type.isEmpty else { return 1 }
        if Held.typeBoost[i] == type { return 1.2 }
        if i == "힘의머리띠" { return physical ? 1.1 : 1 }; if i == "박식안경" { return physical ? 1 : 1.1 }
        let orb = ["금강옥": ["dragon", "steel"], "백옥": ["dragon", "water"], "백금옥": ["dragon", "ghost"]][i]
        return orb?.contains(type) == true && holdsFor(s, i) ? 1.2 : 1
    }
    /// Damage after the crit (Gen IV's Mod2): 생명의구슬 ×1.3, 메트로놈 +10 % a use in a row (up to ×2).
    func itemDamage(_ s: Side) -> Double {
        if holds(s, "생명의구슬") { return 1.3 }
        if holds(s, "메트로놈") { return 1 + 0.1 * Double(min(10, f(s).metronome ?? 0)) }
        return 1
    }
    /// Who moves first within a priority: +1 선제공격손톱 (20 %) / 애슈열매 (at 1/4 HP, eaten), −1 느림보꼬리 / 만복향로.
    mutating func quick(_ s: Side) -> Int {
        let n = nm(s)
        if holds(s, "느림보꼬리") || holds(s, "만복향로") { return -1 }
        if holds(s, "애슈열매"), f(s).hp * (f(s).has(82) ? 2 : 4) <= f(s).maxHP { useUp(s); say(s, josa(n, "은", "는") + " 애슈열매로 행동이 빨라졌다!"); return 1 }
        if holds(s, "선제공격손톱"), pct(20) { say(s, josa(n, "은", "는") + " 선제공격손톱으로 행동이 빨라졌다!"); return 1 }
        return 0
    }
    /// Accuracy: 광각렌즈 ×1.1, 포커스렌즈 ×1.2 moving after the target, 미클열매 ×1.2 once; 반짝가루 / 무사태평향로 on the target ×0.9.
    mutating func itemAccuracy(_ s: Side, _ t: Side) -> Double {
        var a = 1.0
        if holds(s, "광각렌즈") { a *= 1.1 }
        if holds(s, "포커스렌즈"), f(t).movedThisTurn { a *= 1.2 }
        if f(s).micle == true { a *= 1.2; mod(s) { $0.micle = nil } }
        if holds(t, "반짝가루") || holds(t, "무사태평향로") { a *= 0.9 }
        return a
    }
    /// Crit stages: 초점렌즈 / 예리한손톱 +1, 대파 (파오리) / 럭키펀치 (럭키) +2.
    func itemCrit(_ s: Side) -> Int { (holds(s, "초점렌즈") || holds(s, "예리한손톱") ? 1 : 0) + (holdsFor(s, "대파") || holdsFor(s, "럭키펀치") ? 2 : 0) }
    /// 구애 items: the move it's locked into (nil = free).
    func choiceLock(_ s: Side) -> Int? { let x = f(s); guard let c = x.choice, x.item?.hasPrefix("구애") == true, x.moves.contains(c) else { return nil }; return c }

    // MARK: berries and herbs
    /// Whatever a held berry or herb is waiting for, now: a status or confusion (상태 berries), HP low enough, a stat lowered (하양허브),
    /// 헤롱헤롱 (멘탈허브), a move out of PP (과사열매). After every action, hit and hurt.
    mutating func heldCheck(_ s: Side) {
        guard f(s).alive, let i = held(s) else { return }
        let x = f(s), n = nm(s)
        if i.hasSuffix("열매") { if eat(s, i, forced: false) { useUp(s) }; return }
        if i == "멘탈허브", x.attracted { useUp(s); mod(s) { $0.attracted = false }; say(s, josa(n, "은", "는") + " 멘탈허브로 헤롱헤롱 상태가 풀렸다!") }
        if i == "하양허브", x.stage[1...7].contains(where: { $0 < 0 }) {
            useUp(s); mod(s) { for k in 1...7 where $0.stage[k] < 0 { $0.stage[k] = 0 } }; say(s, josa(n, "은", "는") + " 하양허브로 떨어진 능력을 원래대로 되돌렸다!")
        }
    }
    /// A berry's effect on s: held, when its moment has come; forced = thrown at it or 벌레먹기 / 쪼아대기 (whatever the HP). Whether it did anything.
    @discardableResult mutating func eat(_ s: Side, _ i: String, forced: Bool) -> Bool {
        let x = f(s), n = nm(s), half = forced || x.hp * 2 <= x.maxHP, pinch = forced || x.hp * (x.has(82) ? 2 : 4) <= x.maxHP   // 먹보: at 1/2
        let by = josa(n, "은", "는") + " " + josa(i, "으로", "로") + " "
        if let c = Held.cures[i] {
            let st = x.status.map { c.sts.contains($0) } ?? false, conf = c.confusion && x.confused > 0
            guard st || conf else { return false }
            if st, let was = x.status { setStatus(s, nil, by + was.badge + " 상태가 나았다!") }
            if conf { mod(s) { $0.confused = 0 }; say(s, by + "혼란이 풀렸다!") }
            return true
        }
        if let k = Held.pinch[i] { guard pinch, x.stage[k] < 6 else { return false }; say(s, josa(n, "은", "는") + " " + josa(i, "을", "를") + " 먹었다!"); boost(s, k, 1, from: s); return true }
        if let k = Held.flavor[i] {
            guard half, x.hp < x.maxHP, x.healBlock == 0 else { return false }
            restore(s, max(1, x.maxHP / 8), by + "체력을 회복했다!")
            let nat = natures[x.mon.nature ?? 0]
            if nat.up != nat.down, nat.down == k { say(s, "싫어하는 맛이었다!"); confuse(s, from: nil, loud: false) }
            return true
        }
        switch i {
        case "오랭열매", "자뭉열매":
            guard half, x.hp < x.maxHP, x.healBlock == 0 else { return false }
            restore(s, i == "오랭열매" ? 10 : max(1, x.maxHP / 4), by + "체력을 회복했다!"); return true
        case "과사열매":
            let open = x.moves.indices.filter { x.pp[$0] < (moveTable[x.moves[$0]]?.pp ?? 5) }
            guard let k = open.min(by: { x.pp[$0] < x.pp[$1] }), forced || x.pp[k] == 0 else { return false }
            mod(s) { $0.pp[k] = min(moveTable[$0.moves[k]]?.pp ?? 5, $0.pp[k] + 10) }; say(s, by + josa(moveTable[x.moves[k]]?.name ?? "", "의", "의") + " PP를 회복했다!"); return true
        case "랑사열매": guard pinch, !x.focus else { return false }; mod(s) { $0.focus = true }; say(s, josa(n, "은", "는") + " 랑사열매를 먹고 의욕이 넘치고 있다!"); return true
        case "스타열매":
            let ks = (1...5).filter { x.stage[$0] < 6 }
            guard pinch, !ks.isEmpty else { return false }
            say(s, josa(n, "은", "는") + " 스타열매를 먹었다!"); boost(s, ks[roll(ks.count)], 2, from: s); return true
        case "미클열매": guard pinch, x.micle != true else { return false }; mod(s) { $0.micle = true }; say(s, by + "다음 기술이 잘 맞게 되었다!"); return true
        default: return false                                                                       // 애슈 (moveFirst), the resist berries (a hit), 의문 · 자보 · 애터 (being hit): elsewhere
        }
    }
    /// A super-effective hit on t (카리열매: any Normal one) is halved once by its berry. Returns the damage.
    mutating func resistBerry(_ t: Side, type: String, eff: Double, _ d: Int) -> Int {
        guard f(t).sub == 0, let i = held(t), let r = Held.resist[i], r == type, eff > 1 || r == "normal" else { return d }
        useUp(t); say(t, josa(i, "이", "가") + " " + (r == "normal" ? "" : "효과가 굉장한 ") + "기술의 위력을 약하게 했다!")
        return max(1, d / 2)
    }
    /// 기합의띠 (full HP, once) / 기합의머리띠 (10 %): a KO left at 1 HP. Returns the item's line when it held on.
    mutating func hangOn(_ t: Side, _ d: Int) -> String? {
        let x = f(t)
        guard d >= x.hp else { return nil }
        if holds(t, "기합의띠"), x.hp == x.maxHP { useUp(t); return josa(nm(t), "은", "는") + " 기합의띠로 버텼다!" }
        if holds(t, "기합의머리띠"), pct(10) { return josa(nm(t), "은", "는") + " 기합의머리띠로 버텼다!" }
        return nil
    }

    // MARK: after a hit, at the end of a turn
    /// After s's damaging move on t: what t's item does back (의문 자보 애터 열매, 끈적끈적바늘 moving over), what s's does (왕의징표석 / 예리한이빨,
    /// 조개껍질방울, 생명의구슬), and the item moves' own part (탁쳐서떨구기, 도둑질 / 탐내다, 쪼아대기 / 벌레먹기, 자연의은혜's berry).
    mutating func itemsAfterHit(_ s: Side, _ t: Side, _ m: MoveInfo, dealt: Int) {
        let id = m.id, n = nm(s), tn = nm(t)
        if dealt > 0, !subTook {
            if f(t).alive, holds(t, "의문열매"), typeEff(moveType(s, m).type, t, by: s) > 1, f(t).hp < f(t).maxHP, f(t).healBlock == 0 {
                useUp(t); restore(t, max(1, f(t).maxHP / 4), josa(tn, "은", "는") + " 의문열매로 체력을 회복했다!")
            }
            if let i = held(t), (i == "자보열매" && m.physical) || (i == "애터열매" && m.special) {
                useUp(t); if f(s).alive, !f(s).has(98) { hurt(s, max(1, f(s).maxHP / 8), josa(n, "은", "는") + " " + josa(tn + "의 " + i, "으로", "로") + " 데미지를 입었다!") }
            }
            if m.contact, f(s).alive, f(s).item == nil, holds(t, "끈적끈적바늘") { giveItem(s, takeItem(t)); say(s, "끈적끈적바늘이 " + josa(n, "에게", "에게") + " 달라붙었다!") }
            if f(t).alive, m.flinch == 0, holds(s, "왕의징표석") || holds(s, "예리한이빨"), !f(t).movedThisTurn, !dAb(t, 39, by: s), pct(10) { mod(t) { $0.flinch = true } }
            if id == 282, f(t).item != nil, !keeps(t, by: s), let i = takeItem(t) { say(s, josa(n, "은", "는") + " " + josa(tn + "의 " + i, "을", "를") + " 탁쳐서 떨어뜨렸다!") }
            if [168, 343].contains(id), f(s).alive, f(s).item == nil, f(t).item != nil, !keeps(t, by: s), let i = takeItem(t) {
                giveItem(s, i); say(s, josa(n, "은", "는") + " " + josa(tn, "에게서", "에게서") + " " + josa(i, "을", "를") + " 빼앗았다!")
            }
            if [365, 450].contains(id), f(s).alive, let i = f(t).item, i.hasSuffix("열매"), !keeps(t, by: s) {
                takeItem(t); say(s, josa(n, "은", "는") + " " + josa(tn + "의 " + i, "을", "를") + " 빼앗아 먹었다!"); eat(s, i, forced: true)
            }
        }
        if id == 363, f(s).item.flatMap({ Held.gift[$0] }) != nil { useUp(s) }                       // 자연의은혜: the berry's gone
        if dealt > 0, f(s).alive, holds(s, "조개껍질방울") { restore(s, max(1, dealt / 8), josa(n, "은", "는") + " 조개껍질방울로 체력을 조금 회복했다!") }
        if dealt > 0, f(s).alive, holds(s, "생명의구슬"), !f(s).has(98) { hurt(s, max(1, f(s).maxHP / 10), josa(n, "은", "는") + " 생명이 조금 깎였다!") }
    }
    /// 내던지기: what the thrown item does to t once it lands (a berry it eats; the orbs, 전기구슬, 독바늘, 왕의징표석 / 예리한이빨, the herbs).
    mutating func flung(_ i: String, at t: Side, from s: Side) {
        guard f(t).alive, !subTook else { return }
        if i.hasSuffix("열매") { eat(t, i, forced: true); return }
        switch i {
        case "화염구슬": inflict(t, .burn, from: s, loud: false)
        case "맹독구슬": inflict(t, .toxic, from: s, loud: false)
        case "전기구슬": inflict(t, .paralysis, from: s, loud: false)
        case "독바늘": inflict(t, .poison, from: s, loud: false)
        case "왕의징표석", "예리한이빨": if !f(t).movedThisTurn, !dAb(t, 39, by: s) { mod(t) { $0.flinch = true } }
        case "하양허브": if f(t).stage[1...7].contains(where: { $0 < 0 }) { mod(t) { for k in 1...7 where $0.stage[k] < 0 { $0.stage[k] = 0 } }; say(t, josa(nm(t), "의", "의") + " 떨어진 능력이 원래대로 돌아왔다!") }
        case "멘탈허브": if f(t).attracted { mod(t) { $0.attracted = false }; say(t, josa(nm(t), "의", "의") + " 헤롱헤롱 상태가 풀렸다!") }
        default: break
        }
    }
    /// End of turn: 먹다남은음식, 검은오물 (독 타입 heals, others hurt), 끈적끈적바늘.
    mutating func itemResidual(_ s: Side) {
        guard f(s).alive, let i = held(s) else { return }
        let x = f(s), n = nm(s)
        switch i {
        case "먹다남은음식": if x.hp < x.maxHP, x.healBlock == 0 { restore(s, max(1, x.maxHP / 16), josa(n, "은", "는") + " 먹다남은음식으로 조금 회복했다!") }
        case "검은오물":
            if x.typeList.contains("poison") { if x.hp < x.maxHP, x.healBlock == 0 { restore(s, max(1, x.maxHP / 16), josa(n, "은", "는") + " 검은오물로 조금 회복했다!") } }
            else if !x.has(98) { hurt(s, max(1, x.maxHP / 8), josa(n, "은", "는") + " 검은오물로 데미지를 입었다!") }
        case "끈적끈적바늘": if !x.has(98) { hurt(s, max(1, x.maxHP / 8), josa(n, "은", "는") + " 끈적끈적바늘로 데미지를 입었다!") }
        default: break
        }
    }
    /// The turn's very end: 맹독구슬 / 화염구슬.
    mutating func orbs(_ s: Side) {
        guard f(s).alive, f(s).status == nil else { return }
        if holds(s, "맹독구슬") { inflict(s, .toxic, from: nil, loud: false) } else if holds(s, "화염구슬") { inflict(s, .burn, from: nil, loud: false) }
    }

    // MARK: the item moves that aren't attacks
    /// 트릭 / 바꿔치기: the two swap what they hold.
    mutating func trick(_ s: Side, _ t: Side) {
        let a = f(s).item, b = f(t).item
        guard a != nil || b != nil, f(t).sub == 0, !keeps(t, by: s), !fixedItem(s) else { say(s, "그러나 실패했다!"); return }
        takeItem(s); takeItem(t); giveItem(s, b); giveItem(t, a)
        say(s, josa(nm(s), "은", "는") + " 서로의 도구를 바꿨다!")
        if let b { say(s, josa(nm(s), "은", "는") + " " + josa(b, "을", "를") + " 받았다!") }
        if let a { say(t, josa(nm(t), "은", "는") + " " + josa(a, "을", "를") + " 받았다!") }
    }
    /// 리사이클: the last item it used up, back in its hands.
    mutating func recycle(_ s: Side) {
        let x = f(s)
        guard x.item == nil, let i = x.spent else { say(s, "그러나 실패했다!"); return }
        mod(s) { $0.item = i; if $0.spentOwn == true { $0.mon.item = i }; $0.spent = nil; $0.spentOwn = nil; $0.unburden = nil }
        say(s, josa(nm(s), "은", "는") + " " + josa(i, "을", "를") + " 주웠다!")
    }
}
