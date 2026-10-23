import Foundation
// 5.2 (the user via 회사 10-23: "교환 화면에서 포켓몬 찾기가 좀 힘들고 포켓몬 화면에서 이로치 찾기가 쉽지 않네", "6. 뒤에 숫자는 없어도 될것같은데 별만 7. ㅇㅇ";
// lcd-mockups docs/mockups/v5.2 trade-* · shiny-*): finding. The 교환 게시판's 전체: 찾기 (its Pokémon: a name, a number, a type …, as the 상자's)
// and three filters — 새 종 (not in my 도감), 내 것 원함 (wishing a species my box has), ★·3V — each with how many; the rows say 새 종 · 내 것
// 원함 without a filter too. A pick's grid (글 올리기 · 제안 · 1:1 교환): 찾기; the species wished for (and a friend's box) 안 잡은 종, every species
// seen in colour, the uncaught dotted green. The 상자: ★ (one click: 찾기 "이로치"), 이로치 ringed gold.

extension Walker {
    // MARK: the board
    func boardNew(_ l: Listing) -> Bool { !l.mine && !(state.owned ?? []).contains(l.mon.dex) }
    func boardWantsMine(_ l: Listing) -> Bool { !l.mine && !Set(l.wish).isDisjoint(with: Set(myTradeBox.map(\.dex))) }
    func boardRare(_ l: Listing) -> Bool { !l.mine && (l.mon.shiny == true || l.mon.perfectIVs >= 3) }
    /// 전체 as filtered: 찾기's words on its Pokémon, then the filter picked (0 새 종 · 1 내 것 원함 · 2 ★·3V).
    func boardKeeps(_ l: Listing) -> Bool {
        let f: Bool = switch boardFilter { case 0?: boardNew(l); case 1?: boardWantsMine(l); case 2?: boardRare(l); default: true }
        return f && (boardQuery.isEmpty || boardMatch(l))
    }
    func boardMatch(_ l: Listing) -> Bool { boxMatch(l.mon, boardQuery) || l.wish.contains { boxMatch(Mon(dex: $0, level: 1, female: false), boardQuery) } }
    /// A page of the board: 전체 keeps a row for its chips.
    func boardPer(_ tab: Int) -> Int { tab == 0 ? MarketBoardModel.perPage - 1 : MarketBoardModel.perPage }
    /// A row's tag when nothing else is said: 새 종 (green), 내 것 원함 (blue).
    func boardTag(_ l: Listing) -> (String, Int)? { boardNew(l) ? ("새 종", 1) : boardWantsMine(l) ? ("내 것 원함", 2) : nil }
    func boardChips() -> [String] {
        let all = (market?.listings ?? []).filter { !$0.mine }
        return [boardQuery.isEmpty ? "찾기" : "✕ " + boardQuery, "새 종 \(all.filter(boardNew).count)", "내 것 원함 \(all.filter(boardWantsMine).count)", "★·3V \(all.filter(boardRare).count)"]
    }
    /// 8040 찾기 (or its words cleared), 8041 … 8043 a filter (again: off).
    func boardChip(_ code: Int) {
        if code == 8040 {
            if boardQuery.isEmpty { guard let h = host, let raw = h.askText(title: "게시판 찾기", message: "이름 · 번호 · 타입(불꽃) · 이로치 · 3V\n올린 포켓몬이나 원하는 포켓몬") else { return }; boardQuery = raw.trimmingCharacters(in: .whitespaces) }
            else { boardQuery = "" }
        } else { let f = code - 8041; boardFilter = boardFilter == f ? nil : f }
        screen = .market(.board(tab: 0, sel: 0)); lastInput = Date(); host?.redraw(.all)
    }

    // MARK: a pick's grid
    /// What a pick's grid keeps: 찾기's words; 안 잡은 종 on the species wished for (or a friend's box).
    func pickKeeps(_ list: [Mon], newOnly: Bool) -> [Mon] {
        guard !pickQuery.isEmpty || newOnly && pickNew else { return list }
        let owned = Set(state.owned ?? [])
        return list.filter { m in (!newOnly || !pickNew || !owned.contains(m.dex)) && (pickQuery.isEmpty || boxMatch(m, pickQuery)) }
    }
    /// b + 43 찾기 (or its words cleared), b + 44 안 잡은 종 (b: 교환's 6100, the 게시판's 8100).
    func pickChip(_ code: Int, base b: Int) {
        if code == b + 43 {
            if pickQuery.isEmpty { guard let h = host, let raw = h.askText(title: "찾기", message: "이름 · 번호 · 타입(불꽃) · 이로치 · 3V\n띄어 쓰면 모두 맞는 것만") else { return }; pickQuery = raw.trimmingCharacters(in: .whitespaces) }
            else { pickQuery = "" }
        } else { pickNew.toggle() }
        switch screen {
        case .market(.pick(var p)): p.at = 0; screen = .market(.pick(p))
        case .trade(.pick(var p)): p.at = 0; screen = .trade(.pick(p))
        default: break
        }
        lastInput = Date(); host?.redraw(.all)
    }

    // MARK: the 상자
    /// ★: 찾기 "이로치" in one click (again: cleared).
    func boxShinyChip() {
        boxQuery = boxQuery == "이로치" ? "" : "이로치"
        screen = .box(boxShown.first ?? -1, act: nil, confirm: false); lastInput = Date(); host?.redraw(.all)
    }
}
