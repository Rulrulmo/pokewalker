import Foundation
// docs/plans/13 (3.6): items on any of ours — the 도구 page's use picks who gets it (the companion, the walker's, the box's; those it would do
// nothing for dimmed), the server feeds / trains / evolves / mints that one (use(on: uid)); and in a fight an item on any of the party
// (the bench's HP · status · PP, a fainted one's revive: BattleCmd.item(on:)), picked on the party screen (itemFor).

/// Who gets an item: its name, the one picked (a ref: -1 the companion, -2-i the walker's, i the box's), the cursor in the list.
struct ItemOn: Equatable { var item: String; var pick: Int? = nil; var at = 0 }

extension Walker {
    /// Items the 도구 page gives to one of ours (picked): the rest are used as they are (sold) or only in a fight.
    static func targeted(_ kind: ItemKind) -> Bool {
        switch kind { case .candy, .vitamin, .evReset, .berry, .bottleCap, .evolution, .mint: true; default: false }
    }
    /// Ours in the picker's order: the companion, the walker's, then the box as the 포켓몬 grid has it.
    var itemRefs: [Int] { [-1] + state.caught.indices.map { -2 - $0 } + boxOrder }
    /// Why that item would do nothing for that one (nil: it would): the server's own rules (Walk.feedCandy …), told before asking it.
    func itemNot(_ item: String, _ ref: Int) -> String? {
        guard let m = state.mon(ref) else { return "없어요" }
        switch ItemKind.of(item) {
        case .candy: return m.level >= 100 ? "이미 Lv.100" : nil
        case .vitamin(let k, let d):
            let ev = m.evs ?? Array(repeating: 0, count: 6)
            return d > 0 ? (ev[k] >= 100 || ev.reduce(0, +) >= 510 ? "더 올릴 수 없어요" : nil) : (ev[k] == 0 ? "이미 0이에요" : nil)
        case .evReset: return (m.evs ?? []).reduce(0, +) == 0 ? "노력치가 이미 0" : nil
        case .berry: return nil
        case .bottleCap: return m.level < Walk.hyperLevel ? "Lv.\(Walk.hyperLevel)부터" : m.effectiveIVs.allSatisfy { $0 >= 31 } ? "이미 모두 최고" : nil
        case .evolution: return state.stoneEvolutions(Date(), ref: ref).contains { $0.item == item } ? nil : "이 도구로 진화하지 않아요"
        case .mint(let k): return (m.mint ?? m.nature ?? 0) == k ? "이미 그 성격 효과" : nil
        default: return "여기서는 쓸 수 없어요"
        }
    }
    /// The 도구 page's button for one of those: who gets it (the companion first, if it can).
    func pickFor(_ item: String) { screen = .itemOn(ItemOn(item: item, pick: itemNot(item, -1) == nil ? -1 : nil, at: 0)) }

    func itemOnPane(_ p: ItemOn, _ now: Date) -> PaneContent {
        let refs = itemRefs, per = TradePickModel.perPage, at = min(p.at, max(0, refs.count - 1)), first = at / per * per
        let cells = refs[min(first, refs.count)..<min(refs.count, first + per)].compactMap { r -> GridModel.Cell? in
            guard let m = state.mon(r) else { return nil }
            return GridModel.Cell(dex: m.dex, look: itemNot(p.item, r) == nil ? 2 : 1, shiny: m.shiny == true, v3: m.perfectIVs >= 3, level: m.level)
        }
        let m = p.pick.flatMap { state.mon($0) }, why = p.pick.flatMap { itemNot(p.item, $0) }
        let mine = m.map { TradeSlot(label: p.pick == -1 ? "동료" : (p.pick ?? 0) < -1 ? "워커" : "상자", dex: $0.dex, level: $0.level, shiny: $0.shiny == true, name: monNames[$0.dex], v: $0.perfectIVs) }
            ?? TradeSlot(label: "받을 포켓몬", name: "골라 주세요")
        let verb: String = { switch ItemKind.of(p.item) { case .candy, .vitamin, .evReset, .berry: "먹이기"; case .bottleCap(let g): g ? "특훈" : "특훈할 능력 고르기"; default: "쓰기" } }()
        let go = m != nil && why == nil ? josa(monNames[m!.dex], "에게", "에게") + " " + verb : nil
        return PaneContent(pick: TradePickModel(title: "누구에게 쓸까요?", note: "\(p.item) ×\(state.count(p.item))", mine: mine, theirs: TradeSlot(label: "쓸 도구", name: p.item),
                                                side: 0, fixed: true, boxTitle: "동료 · 워커 · 상자 · \(refs.count.formatted())마리", cells: cells, sel: refs.isEmpty ? nil : at - first,
                                                picked: p.pick.flatMap { refs.firstIndex(of: $0) }.flatMap { (first..<first + per).contains($0) ? $0 - first : nil },
                                                first: first, count: refs.count, empty: "", any: nil, go: go, hint: why.map { "이 포켓몬에게는: " + $0 } ?? "쓸 포켓몬을 골라 주세요",
                                                bob: Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0, base: 8300))
    }
    func itemOnLCD(_ fb: inout FB, _ p: ItemOn, _ now: Date) {
        let refs = itemRefs, half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        guard let r = refs[safe: min(p.at, max(0, refs.count - 1))], let m = state.mon(r) else { return }
        fb.text((m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)", 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(m, half, 0, 2, anim: animT("itemon \(r)", m.dex, now))
        let line: String = {
            switch ItemKind.of(p.item) {
            case .vitamin(let k, _): return statNames[k] + " \((m.evs ?? [])[safe: k] ?? 0)"
            case .evReset: return "노력치 \((m.evs ?? []).reduce(0, +))"
            case .mint: return natures[m.mint ?? m.nature ?? 0].name
            case .bottleCap: return "\(m.perfectIVs)V"
            default: return r == -1 ? "동료" : r < -1 ? "워커" : "상자"
            }
        }()
        fb.text(line, 94, 15, 2, right: true, small: true)
        if let why = itemNot(p.item, r) { fb.text(why, 94, 52, 1, right: true, small: true) } else { fb.text(p.pick == r ? "● 쓰기" : "● 고르기", 94, 52, 2, right: true, small: true) }
    }
    /// ◀ ▶ the cursor, ● picks it (on the pick: uses it); a click picks, the button uses.
    func itemOnPress(_ k: Int, _ p0: ItemOn, _ now: Date) {
        var p = p0; let n = itemRefs.count; guard n > 0 else { return }
        if k != 1 { p.at = ((min(p.at, n - 1) + (k == 0 ? -1 : 1)) % n + n) % n; screen = .itemOn(p); return }
        itemOnCell(p, min(p.at, n - 1), now, press: true)
    }
    func itemOnCell(_ p0: ItemOn, _ k: Int, _ now: Date, press: Bool) {
        var p = p0; guard let r = itemRefs[safe: k] else { return }
        p.at = k
        if let why = itemNot(p.item, r) { screen = .say(["이 포켓몬에게는", why], next: .itemOn(p), since: now); return }
        if p.pick == r, press { giveItem(p, now); return }
        p.pick = r; screen = .itemOn(p)
    }
    func itemOnTap(_ code: Int, _ now: Date) {
        guard case .itemOn(var p) = screen else { return }
        let per = TradePickModel.perPage, n = itemRefs.count
        switch code {
        case 8350..<8380: itemOnCell(p, min(p.at, max(0, n - 1)) / per * per + code - 8350, now, press: false)
        case 8380...8381:
            let pages = max(1, (n + per - 1) / per)
            p.at = min(max(0, n - 1), ((min(p.at, max(0, n - 1)) / per + (code == 8380 ? pages - 1 : 1)) % pages) * per); screen = .itemOn(p)
        case 8390: giveItem(p, now)
        default: return
        }
    }
    /// The picked one gets it: a 은색병뚜껑 first asks which stat (the 특훈 page, on that one); the rest go to the server now.
    func giveItem(_ p: ItemOn, _ now: Date) {
        guard let r = p.pick, itemNot(p.item, r) == nil else { return }
        let back = Screen.items(state.inventory.firstIndex(of: p.item) ?? 0)
        if case .bottleCap(false) = ItemKind.of(p.item) { trainRef = r; screen = .train(state.mon(r)?.effectiveIVs.firstIndex { $0 < 31 } ?? 0); return }
        if case .bottleCap(true) = ItemKind.of(p.item) { trainRef = r; useCap(nil, back: back); return }
        useItem(p.item, on: r, back: .itemOn(p), then: { [weak self] in .items(self?.state.inventory.firstIndex(of: p.item) ?? 0) }, now)
    }

    // MARK: in a fight: an item on any of the party
    /// An item could go to more than the one out (the bench, a fainted one): the party screen asks who (itemFor set).
    func itemTargets(_ b: Battle, _ use: ItemUse) -> [Int] { b.mine.indices.filter { b.usable(use, on: $0) } }
    static func battleUse(_ name: String) -> ItemUse? {
        switch ItemKind.of(name) { case .heal(let n): .heal(n); case .battle(let u): u; case .revive(let p): .revive(p); default: nil }
    }
}
