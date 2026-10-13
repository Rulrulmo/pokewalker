import Foundation
// docs/plans/18 §2.4 (5.0, content5): the Gen V–VI held items in a fight. The shops sell them only with content5 (Shop.swift), so a
// Gen IV fight never meets one. Mega stones and orbs (Gen6Forms.swift) stay put on the species they're for.

extension Battle {
    /// 돌격조끼 (특수방어 ×1.5), 진화의휘석 (방어 · 특수방어 ×1.5 on one that can still evolve).
    func gen6ItemDefense(_ t: Side, physical: Bool) -> Double {
        var d = 1.0
        if !physical, holds(t, "돌격조끼") { d *= 1.5 }
        if holds(t, "진화의휘석"), evolutions.contains(where: { $0.from == f(t).mon.dex }) { d *= 1.5 }
        return d
    }
    /// A 주얼 of the move's own type: used up, ×1.3 for this move.
    mutating func gem(_ s: Side, _ m: MoveInfo, type: String) -> Bool {
        guard let g = held(s), Held.gems[g] == type, !type.isEmpty else { return false }
        useUp(s); say(s, josa(g, "이", "가") + " " + josa(m.name, "의", "의") + " 위력을 올렸다!"); return true
    }
    /// The other side's 긴장감: no berries.
    func nervous(_ s: Side) -> Bool { f(other(s)).alive && f(other(s)).has(127) }
    /// After s's damaging hit on t: t's 약점보험, 구근 · 충전지 · 빛이끼 · 눈덩이, 악키 · 타라프열매, 풍선 (popped), 울퉁불퉁멧, 레드카드, 탈출버튼.
    mutating func gen6ItemsAfterHit(_ s: Side, _ t: Side, _ m: MoveInfo, dealt: Int) {
        guard dealt > 0, !subTook else { return }
        let n = nm(s), tn = nm(t), type = moveType(s, m).type
        if f(t).alive, let i = held(t) {
            func eat() { useUp(t); say(t, josa(tn, "은", "는") + " " + josa(i, "을", "를") + " 먹었다!") }
            switch i {
            case "약점보험" where typeEff(type, t, by: s) > 1: useUp(t); say(t, josa(tn, "은", "는") + " 약점보험이 발동했다!"); boost(t, 1, 2, from: t); boost(t, 3, 2, from: t)
            case "구근" where type == "water": useUp(t); boost(t, 3, 1, from: t)
            case "충전지" where type == "electric": useUp(t); boost(t, 1, 1, from: t)
            case "빛이끼" where type == "water": useUp(t); boost(t, 4, 1, from: t)
            case "눈덩이" where type == "ice": useUp(t); boost(t, 1, 1, from: t)
            case "악키열매" where m.physical && !nervous(t): eat(); boost(t, 2, 1, from: t)
            case "타라프열매" where m.special && !nervous(t): eat(); boost(t, 4, 1, from: t)
            case "풍선": takeItem(t); say(t, josa(tn + "의 풍선", "이", "가") + " 터졌다!")
            default: break
            }
        }
        if m.contact, f(s).alive, holds(t, "울퉁불퉁멧"), !f(s).has(98) { hurt(s, max(1, f(s).maxHP / 6), josa(n, "은", "는") + " 울퉁불퉁멧에 데미지를 입었다!") }
        if f(t).alive, f(s).alive, holds(t, "레드카드") { useUp(t); say(t, josa(tn, "은", "는") + " " + josa(n, "에게", "에게") + " 레드카드를 들이댔다!"); blowAway(t, s, loud: false) }
        else if f(t).alive, !over, holds(t, "탈출버튼"), let i = nextAlive(t) { useUp(t); say(t, josa(tn, "은", "는") + " 탈출버튼으로 돌아왔다!"); switchIn(t, i) }
    }
}
