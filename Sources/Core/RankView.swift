import Foundation
// 5.1 (the user via 회사 10-16: "다 한번에 모을거면 친구 메뉴에 랭킹을 넣자", "친구창에 있는 걸음,도감,타워,레이드 이것도 랭킹 화면으로"; the mockups'
// third round, "ㅇㅇ"): 친구 ▸ 랭킹 — this week's ranks in one place: 걸음 · 도감 · 타워 · 레이드 (승 · 잡음 · 이로치) · 메가 레이드 (승 · 스톤 n/48), the
// friends or 전체 (every trainer: Cloud.team.all), the top 10 and me (ties share a rank). The cards are the server's (/v2/team): with content51 its
// TeamCard.raid counts the legend raid alone and megaWeek the Mega raid (8342e2f). ● on a row: that one's card.

extension Walker {
    static let rankTabs = ["걸음", "도감", "타워", "레이드", "메가 레이드"]
    /// A tab's rows: this week's ranks, the top 10 and me.
    func rankRows(_ tab: Int, _ all: Bool) -> [(rank: Int?, card: TeamCard)] {
        let cards = (all ? cloud?.team?.all : nil) ?? cloud?.team?.cards ?? []
        func key(_ c: TeamCard) -> Int {
            switch tab {
            case 0: return c.week
            case 1: return c.owned
            case 2: return c.towerBest
            case 3: let r = c.raid ?? RaidWeek(); return r.wins * 1_000_000 + r.caught * 1_000 + r.shiny        // 승 → 잡음 → 이로치 (each under 1,000 a week)
            default: return (c.megaWeek?.wins ?? 0) * 1_000 + (c.megaStones ?? 0)                                  // 승 → 스톤
            }
        }
        let sorted = cards.sorted { key($0) != key($1) ? key($0) > key($1) : $0.name < $1.name }
        var ranked: [(rank: Int?, card: TeamCard)] = [], rank = 0
        for (i, c) in sorted.enumerated() { if i == 0 || key(sorted[i - 1]) != key(c) { rank = i + 1 }; ranked.append((rank, c)) }
        return Array(ranked.prefix(10)) + ranked.dropFirst(10).filter { isMe($0.card) }
    }
    func rankValue(_ c: TeamCard, _ tab: Int) -> String {
        switch tab {
        case 0: return "\(c.week.formatted())걸음"
        case 1: return "도감 \(c.owned)"
        case 2: return "\(c.towerBest)연승"
        case 3: return raidLine(c.raid)
        default: return "\(c.megaWeek?.wins ?? 0)승 · 스톤 \(c.megaStones ?? 0)/\(MegaRaid.stones.count)"
        }
    }
    /// 전체 only when the server sends it.
    var rankAll: Bool { cloud?.team?.all != nil }
    /// The menu's line: my rank in this week's steps.
    var rankNote: String { cloud?.team == nil ? "이번 주 순위" : rankRows(0, false).first { isMe($0.card) }?.rank.map { "이번 주 걸음 \($0)위" } ?? "이번 주 순위" }
    func rankPane(_ tab: Int, _ sel: Int, _ all: Bool) -> PaneContent {
        let all = all && rankAll, rows = rankRows(tab, all), s = min(sel, max(0, rows.count - 1)), per = TeamModel.perPage, first = s / per * per
        let page = rows[first..<min(rows.count, first + per)].map { r in
            TeamModel.Row(rank: r.rank, name: r.card.name, dex: r.card.companion.dex, shiny: r.card.companion.shiny == true, value: rankValue(r.card, tab), walking: false, me: isMe(r.card), deco: r.card.deco, title: nil)
        }
        let n = (all ? cloud?.team?.all?.count : cloud?.team?.cards.count) ?? 0, mine = rows.first { isMe($0.card) }?.rank.map { " · 나 \($0)위" } ?? ""
        let note = cloud?.team == nil ? (cloud?.online == false ? "연결되면 볼 수 있어요" : "불러오는 중…") : (all ? "전체 \(n)명" : "친구 \(max(0, n - 1))명") + mine
        var m = TeamModel(tabs: Walker.rankTabs, tab: tab, rows: page, sel: s, first: first, count: rows.count, note: note, week: "")
        m.scope = rankAll ? (all ? 1 : 0) : nil
        return PaneContent(team: m)
    }
    func rankLCD(_ fb: inout FB, _ tab: Int, _ sel: Int, _ all: Bool, _ now: Date) {
        let rows = rankRows(tab, all && rankAll)
        guard let r = rows[safe: min(sel, max(0, rows.count - 1))] else { fb.text("랭킹", 2, 0); fb.fill(0, 12, 96, 1, 2); fb.text(cloud?.team == nil ? "불러오는 중..." : "아직 아무도 없다", 0, 30, 2, center: true); return }
        let c = r.card, half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        fb.text(c.name, 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(c.companion, half, 0, 2, anim: animT("rank", c.companion.art, now))
        fb.text(Walker.rankTabs[tab], 94, 16, 2, right: true, small: true)
        fb.text(r.rank.map { "\($0)위" } ?? "-", 94, 28, 3, right: true)
        fb.text(all && rankAll ? "전체" : "친구", 94, 52, 1, right: true, small: true)
    }
    /// ◀ ▶ a row; ● that one's card (a friend's on 친구, else 전체's).
    func rankPress(_ k: Int, _ tab: Int, _ sel: Int, _ all: Bool) {
        let rows = rankRows(tab, all && rankAll), n = max(1, rows.count)
        if k != 1 { screen = .rank(tab: tab, sel: (sel + (k == 0 ? n - 1 : 1)) % n, all: all); return }
        guard let c = rows[safe: sel]?.card else { return }
        if let i = teamRows(TeamTab.friends).firstIndex(where: { $0.card.name == c.name }) { screen = .team(sel: i, tab: TeamTab.friends, card: true) }
        else if let i = teamRows(TeamTab.all).firstIndex(where: { $0.card.name == c.name }) { screen = .team(sel: i, tab: TeamTab.all, card: true) }
    }
    /// The pane's: a tab (6000+), a row (6010+: picked; again, its card), the pager (6020 · 6021), 친구 | 전체 (6090 · 6091).
    func rankTap(_ code: Int) {
        guard case .rank(let tab, let sel, let all) = screen else { return }
        let n = rankRows(tab, all && rankAll).count, per = TeamModel.perPage, first = sel / per * per
        switch code {
        case 6000..<6000 + Walker.rankTabs.count: screen = .rank(tab: code - 6000, sel: 0, all: all)
        case 6010..<6010 + per: let i = first + code - 6010; if i == sel { rankPress(1, tab, sel, all) } else if i < n { screen = .rank(tab: tab, sel: i, all: all) }
        case 6020, 6021: let pages = max(1, (n + per - 1) / per); screen = .rank(tab: tab, sel: min(max(0, n - 1), ((first / per + (code == 6020 ? pages - 1 : 1)) % pages) * per), all: all)
        case 6090, 6091: screen = .rank(tab: tab, sel: 0, all: code == 6091)
        default: return
        }
    }
}
