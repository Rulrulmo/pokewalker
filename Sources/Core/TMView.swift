import Foundation
// 5.2 (docs/plans/19 §11.4, content52; the user via 회사 10-23: "4-1. 정렬 있었음 좋겠따 4-2. 넣기 4-3. 넣어줘"; lcd-mockups docs/mockups/v5.2 tm-*):
// 기술머신 on the app. The W 상점's 기술머신 tab: 번호순 · 타입순 · 값순 and 우리 팀만 (a chip row over it); a row is its number and move, type,
// price (or 보유), 물리 · 특수 and power, how many of ours learn it (the box too) and the team's four (who doesn't learn it faded). The bag's
// 기술머신 tab: the machines had (Walk.tms, numbers — never bag items: a course's second copy stays under 기타 to sell), the button 가르칠 포켓몬
// 고르기 → that one's 기술 바꾸기 with the move under the cursor once a slot is picked. 기술 바꾸기 marks a machine's move (TM26) and 레쿠쟈 원정's
// 화룡점정 (원정). A machine's picture: the disc in its move's type, drawn (every one alike, the eight course ones too).

extension Walker {
    static let tmSorts = ["번호순", "타입순", "값순"]
    /// The bag's machine rows: .items(tmRow0 + i), i in the sorted Walk.tms (the inventory's indices stay below).
    static let tmRow0 = 10_000
    static let typeOrder = ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground", "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]
    func tmLabel(_ no: Int) -> String { no > Machines.hm ? String(format: "HM%02d", no - Machines.hm) : String(format: "TM%02d", no) }
    func tmMove(_ no: Int) -> MoveInfo? { moveTable[Machines.move(no)] }
    /// "물리 · 위력 100", "특수 · 위력 90", "변화".
    func tmKind(_ no: Int) -> String {
        guard let m = tmMove(no) else { return "" }
        return m.isStatus ? "변화" : (m.physical ? "물리" : "특수") + " · 위력 " + (m.power > 1 ? "\(m.power)" : "-")
    }
    var tmTeam: [Mon] { [state.companion] + state.caught }
    /// Who of ours learns it: the team's (the companion and the walker's, in order) and how many in all (the box too).
    func tmLearners(_ no: Int) -> (team: [Bool], all: Int) {
        let team = tmTeam.map { Machines.learns($0.dex, no) }
        return (team, team.filter { $0 }.count + state.box.filter { Machines.learns($0.dex, no) }.count)
    }
    /// The shop's 기술머신 rows (ware indices) in the sort picked; 우리 팀만: one of the team learns it.
    func tmShopOrder(_ ids: [Int], _ ws: [Walk.Ware]) -> [Int] {
        func no(_ k: Int) -> Int { if case .item(let i) = ws[k].kind { return Walk.machine(i) ?? 0 }; return 0 }
        let kept = tmTeamOnly ? ids.filter { k in tmTeam.contains { Machines.learns($0.dex, no(k)) } } : ids
        func type(_ k: Int) -> Int { Walker.typeOrder.firstIndex(of: tmMove(no(k))?.type ?? "") ?? 99 }
        switch tmSort {
        case 1: return kept.sorted { (type($0), no($0)) < (type($1), no($1)) }
        case 2: return kept.sorted { (ws[$0].price, no($0)) < (ws[$1].price, no($1)) }
        default: return kept.sorted { no($0) < no($1) }
        }
    }
    /// The shop's 기술머신 line under the list: who of ours learns the pick.
    func tmShopHint(_ no: Int, owned: Bool) -> String {
        let l = tmLearners(no), names = zip(tmTeam, l.team).filter { $0.1 }.map { monNames[$0.0.dex] }
        if owned { return "가지고 있어요 · 기술 바꾸기에서 가르쳐요" }
        if l.all == 0 { return "배울 수 있는 포켓몬이 없어요 · 그래도 살 수 있어요" }
        let who = names.count > 2 ? names.prefix(2).joined(separator: " · ") + " 외" : names.joined(separator: " · ")
        let team = names.isEmpty ? "우리 팀은 못 배워요" : names.count == 1 && l.all == 1 ? who + "만 배워요" : josa(who, "이", "가") + " 배워요"
        return team + " · 모두 \(l.all)마리"
    }
    /// The 기술머신 tab: its sort or the filter picked (2950 + n; 2953 우리 팀만), back on its first row.
    func tmShopChip(_ code: Int, bp: Bool) {
        if code == 2953 { tmTeamOnly.toggle() } else { tmSort = code - 2950 }
        let t = shopTabs(bp).firstIndex(of: "기술머신") ?? 0
        screen = .shop(bp: bp, sel: shopRows(bp, t).first ?? wares(bp).firstIndex { Walk.shopTab($0, bp: bp) == "기술머신" } ?? 0, qty: nil)
    }

    // MARK: the bag
    var tmHad: [Int] { (state.tms ?? []).sorted() }
    /// The bag's tabs with 기술머신 (before 기타) once one is had.
    func bagTabsWithTM(_ tabs: [String]) -> [String] {
        guard Content.v52, !tmHad.isEmpty else { return tabs }
        var t = tabs; t.insert("기술머신", at: t.firstIndex(of: "기타") ?? t.count); return t
    }
    func tmRowName(_ sel: Int) -> String? { tmHad[safe: sel - Walker.tmRow0].map(Machines.name) }
    func tmItemsModel(_ sel: Int) -> ItemsModel {
        let had = tmHad, i = min(max(0, sel - Walker.tmRow0), max(0, had.count - 1)), arts = tmTeam.map(\.art)
        let rows = had.map { no -> ItemsModel.Row in
            var r = ItemsModel.Row(name: Machines.name(no), count: 1, onWalker: 0)
            r.tm = .init(label: tmLabel(no), move: tmMove(no)?.name ?? "", type: tmMove(no)?.type ?? "normal", team: arts, teamOK: tmLearners(no).team)
            return r
        }
        let no = had[safe: i] ?? 0, l = tmLearners(no)
        return ItemsModel(rows: rows, sel: i, walker: state.items.count, bag: state.bag.count, action: l.all > 0 ? "가르칠 포켓몬 고르기" : nil,
                          hint: tmKind(no) + " · 배우는 포켓몬 \(l.all)마리 · 가르쳐도 없어지지 않아요", sellAll: nil, tabs: itemTabs, tab: itemTabs.firstIndex(of: "기술머신") ?? 0)
    }
    func tmItemsLCD(_ fb: inout FB, _ sel: Int) {
        let had = tmHad, x = 44
        guard let no = had[safe: min(max(0, sel - Walker.tmRow0), had.count - 1)] else { return }
        let name = Machines.name(no)
        fb.focusPic("item|" + name) { itemPic(name) }
        fb.name(tmLabel(no) + " " + (tmMove(no)?.name ?? ""), x, 13, 94 - x)
        fb.line((tmMove(no).map { (typeKo[$0.type] ?? "") + ($0.power > 1 ? " \($0.power)" : "") } ?? ""), x, 25, 94 - x)
        fb.wrap("배우는 포켓몬 \(tmLearners(no).all)마리 · 써도 없어지지 않아요", x, 35, 94 - x, lines: 2)
        fb.text("\(min(max(0, sel - Walker.tmRow0), had.count - 1) + 1)/\(had.count)", 94, 53, 1, right: true, small: true)
    }

    // MARK: 기술 바꾸기
    /// Its mark: a machine's (TM26 · HM01) or 레쿠쟈 원정's 화룡점정 (원정) — a move it learns by level shows its level instead (nil).
    func relearnTag(_ m: Mon, _ id: Int) -> String? {
        guard Content.v52, m.learnLevel(id) == nil, !m.relearnable.contains(id) else { return nil }
        if m.dex == 384, id == 620 { return "원정" }
        return (state.tms ?? []).sorted().first { Machines.move($0) == id && Machines.learns(m.dex, $0) }.map(tmLabel)
    }
}

// MARK: - a machine's picture
/// HGSS's disc in the move's type: its rim, a lit arc, the hole (an item's picture: ItemArt.swift asks for it by name).
func machineDisc(_ type: String) -> Pic {
    let t = fxTones[type] ?? fxTones["normal"]!
    return Pic([".....ooooo.....", "...ooLLMMMoo...", "..oLLWLMMMMMo..", ".oLWLLMMMMMMDo.", ".oLLLMMMMMMMDo.", "oLLMMMoooMMMMDo", "oMMMMo...oMMMDo", "oMMMMo...oMMDDo",
               "oMMMMo...oMMDDo", "oMMMMMoooMMDDDo", ".oMMMMMMMMDDDo.", ".oMMMMMMMDDDDo.", "..oDMMMMDDDDo..", "...ooDDDDDoo...", ".....ooooo....."],
               ["o": t[0], "D": t[1], "M": t[2], "L": t[3], "W": t[4]])
}
