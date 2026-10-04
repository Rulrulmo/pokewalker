import Foundation
// docs/plans/12 §2 (M1): the team — its cards (who's walking now first), this week's ranks, a teammate's trainer card, 인사; and on home a
// teammate's companion dropping by now and then (a tap = 인사), a 인사 come in with its sender's companion. The list is the server's
// (Cloud.team, /v2/team); the walker only sorts and shows it.

extension Walker {
    static let teamTabs = ["팀", "걸음", "도감", "타워", "교환"]                                   // 교환 = the trades' list (Core/TradeView.swift)
    /// A teammate is walking now: an act within the last minute (the app sends steps every 15 s).
    static func walkingNow(_ c: TeamCard) -> Bool { c.idle < 60 }
    var myName: String { cloud?.seat.trainerID ?? "" }
    func isMe(_ c: TeamCard) -> Bool { trainerID(c.name)?.key == trainerID(myName)?.key }
    /// The cards as a tab orders them: 팀 = walking now first, then today's steps; 걸음 · 도감 · 타워 = this week's ranks, the top 10 and me
    /// (ties share a rank). rank: nil on 팀.
    func teamRows(_ tab: Int) -> [(rank: Int?, card: TeamCard)] {
        let cards = cloud?.team?.cards ?? []
        guard tab > 0 else {
            return cards.sorted { a, b in Walker.walkingNow(a) != Walker.walkingNow(b) ? Walker.walkingNow(a) : a.today != b.today ? a.today > b.today : a.name < b.name }.map { (nil, $0) }
        }
        func key(_ c: TeamCard) -> Int { tab == 1 ? c.week : tab == 2 ? c.owned : c.towerBest }
        let sorted = cards.sorted { key($0) != key($1) ? key($0) > key($1) : $0.name < $1.name }
        var ranked: [(rank: Int?, card: TeamCard)] = [], rank = 0
        for (i, c) in sorted.enumerated() { if i == 0 || key(sorted[i - 1]) != key(c) { rank = i + 1 }; ranked.append((rank, c)) }
        return Array(ranked.prefix(10)) + ranked.dropFirst(10).filter { isMe($0.card) }
    }
    /// What a row says on the tab's terms.
    func teamValue(_ c: TeamCard, _ tab: Int) -> String {
        switch tab {
        case 1: "\(c.week.formatted())걸음"
        case 2: "도감 \(c.owned)"
        case 3: "\(c.towerBest)연승"
        default: Walker.walkingNow(c) || isMe(c) ? "오늘 \(c.today.formatted())걸음" : ago(c.idle)
        }
    }
    func ago(_ secs: Int) -> String { secs < 3600 ? "\(max(1, secs / 60))분 전" : secs < 86400 ? "\(secs / 3600)시간 전" : "\(secs / 86400)일 전" }

    /// The pane: the list (tabs, a page of rows, the pager) or one teammate's card.
    func teamPane(_ sel: Int, _ tab: Int, _ card: Bool) -> PaneContent {
        let rows = teamRows(tab), s = min(sel, max(0, rows.count - 1))
        let walking = (cloud?.team?.cards ?? []).filter { Walker.walkingNow($0) && !isMe($0) }.count
        let note = cloud?.team == nil ? (cloud?.online == false ? "연결되면 볼 수 있어요" : "불러오는 중…") : "\(cloud?.team?.cards.count ?? 0)명 · 지금 걷는 중 \(walking)명"
        if card, let c = rows[safe: s]?.card {
            func mini(_ m: Mon) -> TeamCardModel.Mini { .init(dex: m.dex, level: m.level, shiny: m.shiny == true) }
            let lines: [TeamCardModel.Line] = [
                .init(key: "도감", value: "잡음 \(c.owned) · 봤음 \(c.seen)" + (c.shinies > 0 ? " · 이로치 \(c.shinies)" : "")),
                .init(key: "타워", value: "최고 \(c.towerBest)연승 · BP \(c.bp.formatted())"),
                .init(key: "레이더", value: "최고 연쇄 \(c.bestChain)"),
                .init(key: "걸음", value: "오늘 \(c.today.formatted()) · 이번 주 \(c.week.formatted())"),
                .init(key: "누적", value: "\(c.total.formatted())걸음"),
                .init(key: "코스", value: courses[safe: c.course]?.name ?? "-"),
            ]
            return PaneContent(teamCard: TeamCardModel(name: c.name, me: isMe(c), walking: Walker.walkingNow(c) && !isMe(c), when: isMe(c) ? "" : ago(c.idle), walker: c.walker.prefix(3).map(mini), lines: lines,
                                                       greet: isMe(c) ? nil : visitorGreeted(c.name) ? "인사했어요 ♥" : "인사하기 ♥", trade: !isMe(c)))
        }
        let per = TeamModel.perPage, first = s / per * per
        let page = rows[first..<min(rows.count, first + per)].map { r in
            TeamModel.Row(rank: r.rank, name: r.card.name, dex: r.card.companion.dex, shiny: r.card.companion.shiny == true, value: teamValue(r.card, tab), walking: Walker.walkingNow(r.card) && !isMe(r.card), me: isMe(r.card))
        }
        return PaneContent(team: TeamModel(tabs: teamTabLabels, tab: tab, rows: page, sel: s, first: first, count: rows.count, note: note, week: cloud?.team?.week ?? ""))
    }
    /// The LCD on the team's pages: the picked teammate's companion, its name, level, and whether it's walking now.
    func teamLCD(_ fb: inout FB, _ sel: Int, _ tab: Int, _ now: Date) {
        let rows = teamRows(tab)
        guard let r = rows[safe: min(sel, max(0, rows.count - 1))] else { fb.text("팀", 2, 0); fb.fill(0, 12, 96, 1, 2); fb.text(cloud?.team == nil ? "불러오는 중..." : "아직 아무도 없다", 0, 30, 2, center: true); return }
        let c = r.card, half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        fb.text(c.name, 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(c.companion, half, 0, 2, anim: animT("team", c.companion.dex, now))
        fb.text("Lv.\(c.companion.level)", 94, 16, 2, right: true, small: true)
        if isMe(c) { fb.text("나", 94, 30, 2, right: true, small: true) } else { fb.text(Walker.walkingNow(c) ? "걷는 중" : ago(c.idle), 94, 30, Walker.walkingNow(c) ? 3 : 2, right: true, small: true) }
        if c.companion.shiny == true { fb.text("★이로치", 94, 42, 3, right: true, small: true) }
        fb.text(r.rank.map { "\($0)위" } ?? "\(min(sel, rows.count - 1) + 1)/\(rows.count)", 94, 52, 1, right: true, small: true)
    }
    /// ◀ ▶ (and the wheel, ↑ ↓): a row (on a card: the next teammate's card), round.
    func teamStep(_ d: Int, wrap: Bool = true) {
        guard case .team(let sel, let tab, let card) = screen else { return }
        let n = teamRows(tab).count; guard n > 0 else { return }
        lastInput = Date(); host?.redraw(.all)
        screen = .team(sel: wrap ? ((sel + d) % n + n) % n : max(0, min(n - 1, sel + d)), tab: tab, card: card)
    }
    /// 인사 to a teammate (12 §2.3): the server delivers it; once an hour each.
    func greet(_ name: String, back: Screen, _ now: Date = Date()) {
        guard trainerID(name)?.key != trainerID(myName)?.key, !visitorGreeted(name) else { return }   // not ourselves; once an hour each (the server's rule too)
        act(.greet(to: name), back: back, now) { [weak self] _, now in
            self?.greeted[trainerID(name)?.key ?? name] = now
            return .say([josa(name, "에게", "에게"), "인사했다! ♥"], next: back, since: now)
        }
    }
    func visitorGreeted(_ name: String) -> Bool { greeted[trainerID(name)?.key ?? name].map { Date().timeIntervalSince($0) < 3600 } ?? false }

    // MARK: home: a teammate's companion drops by
    /// Home, now and then (every 300–600 steps): one of those walking now drops by as a sticker for a while; a tap on it = 인사.
    func visitTick(_ now: Date) {
        if let v = visitor, now >= v.until { visitor = nil; host?.redraw(.lcd) }
        guard case .home = screen, waiting == nil, news.isEmpty, let c = cloud, c.online, let team = c.team else { return }
        if nextVisit == 0 { nextVisit = state.total + Int.random(in: 300...600, using: &rng); return }
        guard state.total >= nextVisit, visitor == nil else { return }
        let here = team.cards.filter { Walker.walkingNow($0) && !isMe($0) }
        guard let pick = here.randomElement(using: &rng) else { nextVisit = state.total + 150; return }   // nobody walking: look again a little later
        nextVisit = state.total + Int.random(in: 300...600, using: &rng)
        visitor = Visitor(name: pick.name, dex: pick.companion.dex, shiny: pick.companion.shiny == true, until: now.addingTimeInterval(90), hello: false)
        screen = .say([josa(pick.name, "의", "의") + " " + josa(monNames[pick.companion.dex], "이", "가"), "놀러 왔다!"], next: .home, since: now)
    }
    /// Where the visitor's sticker sits (half-dots, top-left), over the page's top-right corner.
    static let visitorAt = (x: 150, y: 2)
    /// The visitor's sticker on home (and its ♥ once greeted or come with a 인사).
    func drawVisitor(_ fb: inout FB, _ now: Date, night: Bool, tone: String) {
        guard let v = visitor, now < v.until else { return }
        let t = now.timeIntervalSinceReferenceDate, hop = Int(t * 2) % 4 == 0 ? 2 : 0
        fb.stuck("nb|visit|\(v.dex)|" + tone, Walker.visitorAt.x, Walker.visitorAt.y - hop) { lcdReady(sticker(iconPic(v.dex), night: night)) }
        if v.hello || visitorGreeted(v.name), Int(t * 3) % 3 != 0 { fb.pic("nb|bubble|1", Walker.visitorAt.x + 30, Walker.visitorAt.y + 6) { bubblePic(1) } }   // ♥
    }
    /// A tap on the visitor (LCD dots): 인사 to its trainer.
    func visitorTouched(_ x: Int, _ y: Int) -> Bool {
        guard let v = visitor, Date() < v.until else { return false }
        guard (Walker.visitorAt.x / 2..<Walker.visitorAt.x / 2 + 20).contains(x), (Walker.visitorAt.y / 2..<Walker.visitorAt.y / 2 + 20).contains(y) else { return false }
        if !visitorGreeted(v.name) { greet(v.name, back: screen) }
        return true
    }
}
/// A teammate's companion on home for a while: dropped by (hello false) or with a 인사 (true).
struct Visitor: Equatable { var name: String; var dex: Int; var shiny: Bool; var until: Date; var hello: Bool }
