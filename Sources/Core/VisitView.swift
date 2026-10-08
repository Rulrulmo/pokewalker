import Foundation
// docs/plans/14 §3 (3.8): 맡겨 키우기 — one of ours (the walker's or the box's) sent to a friend walking now, raised by their steps for 5 hours
// (a step = 1 EXP), back through the 우편함 (3.9; 받기 before); they earn a BP per 2,000 steps (5 at most). The friends' 맡기기 tab lists mine away and the ones I'm
// raising (2 at most since 3.8.1; either side can end it early); on home they sit above the companion; a friend's card sends one.

extension Walker {
    static let visitHours = 5
    var visits: Visits? { cloud?.team?.visits }
    var guests: [Visit] { visits?.guests ?? [] }
    /// 3.8.5: mine away — one a friend at a time (the server's `out`; an older server's one `away`).
    var visitsOut: [Visit] { visits?.out ?? (visits?.away.map { [$0] } ?? []) }
    func visitTo(_ name: String) -> Visit? { visitsOut.first { trainerID($0.host)?.key == trainerID(name)?.key } }
    func visitLeft(_ v: Visit, _ now: Date = Date()) -> String {
        let s = max(0, v.ends - Int(now.timeIntervalSince1970))
        return s >= 3600 ? "\(s / 3600)시간 \(s % 3600 / 60)분 남음" : "\(max(1, s / 60))분 남음"
    }

    // MARK: the 맡기기 tab
    func visitsPane(_ sel: Int, _ now: Date) -> PaneContent {
        var rows: [VisitsModel.Row] = []
        for a in visitsOut {
            rows.append(.init(dex: a.mon.dex, shiny: a.mon.shiny == true, line: "내 " + monLine(a.mon) + " → " + a.host, sub: "\(a.steps.formatted())걸음 키움 · " + visitLeft(a, now), button: "데려오기", mine: true))
        }
        for g in guests {
            rows.append(.init(dex: g.mon.dex, shiny: g.mon.shiny == true, line: josa(g.owner, "의", "의") + " " + monLine(g.mon), sub: "\(g.steps.formatted())걸음 · +\(min(5, g.steps / 2000))BP · " + visitLeft(g, now),
                              button: "돌려보내기", mine: false))
        }
        let note = cloud?.team == nil ? "불러오는 중…" : "보낸 포켓몬 \(visitsOut.count) · 맡은 포켓몬 \(guests.count)/\(Walker.guestsMax)"
        let s = min(sel, max(0, rows.count - 1)), first = max(0, min(s - 2, rows.count - VisitsModel.shown))
        return PaneContent(visits: VisitsModel(tabs: teamTabLabels, tab: 5, rows: rows, note: note,
                                               hint: "지금 걷는 친구의 카드에서 맡기기 · 친구마다 1마리 · 5시간 · 키운 걸음만큼 경험치 · 맡은 쪽은 2,000걸음마다 1BP (최대 5)", first: first, sel: s))
    }
    func visitsLCD(_ fb: inout FB, _ sel: Int, _ now: Date) {
        let all = visitsOut + guests
        fb.text("맡겨 키우기", 2, 0); fb.fill(0, 12, 96, 1, 2)
        guard let v = all[safe: min(sel, max(0, all.count - 1))] else { fb.text("맡긴 포켓몬이 없다", 0, 30, 2, center: true); return }
        fb.mon(v.mon, Int(now.timeIntervalSinceReferenceDate * 2) % 2, 0, 2, anim: animT("visit \(v.id)", v.mon.dex, now))
        fb.text(trainerID(v.owner)?.key == trainerID(myName)?.key ? "→ " + v.host : v.owner, 94, 15, 3, right: true, small: true)
        fb.text("\(v.steps.formatted())걸음", 94, 26, 2, right: true, small: true)
    }
    /// 데려오기 (mine) · 돌려보내기 (theirs): settled with the steps so far.
    func visitEnd(_ row: Int, _ now: Date) {
        let all = visitsOut + guests
        guard let v = all[safe: row] else { return }
        let mine = trainerID(v.owner)?.key == trainerID(myName)?.key
        let back = Screen.team(sel: row, tab: 5, card: false)
        act(.visitEnd(id: v.id), back: back, now) { [weak self] _, now in
            guard let self else { return nil }
            cloud?.teamDue = true; cloud?.marketDue = true
            if mine { return .say([josa(monNames[v.mon.dex], "을", "를") + " 데려왔다", "우편함으로 돌아와요"], next: back, since: now) }
            var bp = 0                                                                              // (its visitDone: said here, not again at home)
            news.removeAll { if case .visitDone(_, let d, _, let b) = $0, d == v.mon.dex { bp = b; return true }; return false }
            return .say([josa(v.owner, "의", "의") + " " + josa(monNames[v.mon.dex], "을", "를"), "돌려보냈다"] + (bp > 0 ? ["+\(bp)BP"] : []), next: back, since: now)
        }
    }

    // MARK: sending one (a friend's card)
    /// Ours that can go: the walker's and the box's (not the companion).
    var visitRefs: [Int] { state.caught.indices.map { -2 - $0 } + boxOrder }
    func visitPickPane(_ p: ItemOn, _ now: Date) -> PaneContent {
        let refs = visitRefs, per = TradePickModel.perPage, at = min(p.at, max(0, refs.count - 1)), first = at / per * per
        let cells = refs[min(first, refs.count)..<min(refs.count, first + per)].compactMap { r -> GridModel.Cell? in
            state.mon(r).map { GridModel.Cell(dex: $0.dex, look: 2, shiny: $0.shiny == true, v3: $0.perfectIVs >= 3, level: $0.level, held: $0.item != nil) }
        }
        let m = p.pick.flatMap { state.mon($0) }
        let mine = m.map { TradeSlot(label: "맡길 포켓몬", dex: $0.dex, level: $0.level, shiny: $0.shiny == true, name: monNames[$0.dex], v: $0.perfectIVs) } ?? TradeSlot(label: "맡길 포켓몬", name: "골라 주세요")
        return PaneContent(pick: TradePickModel(title: p.item + "에게 맡기기", note: "5시간", mine: mine, theirs: TradeSlot(label: "키워 줄 친구", name: p.item),
                                                side: 0, fixed: true, boxTitle: "워커 · 상자 · \(refs.count.formatted())마리", cells: cells, sel: refs.isEmpty ? nil : at - first,
                                                picked: p.pick.flatMap { refs.firstIndex(of: $0) }.flatMap { (first..<first + per).contains($0) ? $0 - first : nil },
                                                first: first, count: refs.count, empty: "워커 · 상자에 포켓몬이 없어요", any: nil, go: m.map { josa(monNames[$0.dex], "을", "를") + " 맡기기" },
                                                hint: "맡길 포켓몬을 골라 주세요 (동료는 안 돼요)", bob: Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0, base: 8500))
    }
    func visitPickLCD(_ fb: inout FB, _ p: ItemOn, _ now: Date) {
        guard let r = visitRefs[safe: min(p.at, max(0, visitRefs.count - 1))], let m = state.mon(r) else { return }
        fb.text((m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)", 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(m, Int(now.timeIntervalSinceReferenceDate * 2) % 2, 0, 2, anim: animT("vpick \(r)", m.dex, now))
        fb.text("→ " + p.item, 94, 15, 2, right: true, small: true)
        fb.text(p.pick == r ? "● 맡기기" : "● 고르기", 94, 52, 2, right: true, small: true)
    }
    func visitPickPress(_ k: Int, _ p0: ItemOn, _ now: Date) {
        var p = p0; let n = visitRefs.count; guard n > 0 else { return }
        if k != 1 { p.at = ((min(p.at, n - 1) + (k == 0 ? -1 : 1)) % n + n) % n; screen = .visitPick(p); return }
        let r = visitRefs[min(p.at, n - 1)]
        if p.pick == r { visitSend(p, now) } else { p.pick = r; screen = .visitPick(p) }
    }
    func visitPickTap(_ code: Int, _ now: Date) {
        guard case .visitPick(var p) = screen else { return }
        let per = TradePickModel.perPage, n = visitRefs.count
        switch code {
        case 8550..<8580: let at = min(p.at, max(0, n - 1)) / per * per + code - 8550; if let r = visitRefs[safe: at] { p.at = at; p.pick = r; screen = .visitPick(p) }
        case 8580...8581: let pages = max(1, (n + per - 1) / per); p.at = min(max(0, n - 1), ((min(p.at, max(0, n - 1)) / per + (code == 8580 ? pages - 1 : 1)) % pages) * per); screen = .visitPick(p)
        case 8590: visitSend(p, now)
        default: return
        }
    }
    /// 맡기기: it goes (out of the walker / box) for 5 hours.
    func visitSend(_ p: ItemOn, _ now: Date) {
        guard let r = p.pick, let m = state.mon(r), let u = m.uid else { return }
        let back = teamRows(0).firstIndex { trainerID($0.card.name)?.key == trainerID(p.item)?.key }.map { Screen.team(sel: $0, tab: 0, card: true) } ?? .team(sel: 0, tab: 0, card: false)
        act(.visitSend(to: p.item, uid: u), back: .visitPick(p), now) { [weak self] _, now in
            self?.cloud?.teamDue = true
            return .say([p.item + "에게 " + josa(monNames[m.dex], "을", "를"), "맡겼다!", "5시간 뒤 우편함으로 와요"], next: back, since: now)
        }
    }
    func startVisit(_ name: String, _ now: Date = Date()) {
        guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: screen, since: now); return }
        screen = .visitPick(ItemOn(item: name, pick: nil, at: 0))
    }

    // MARK: home: the guests walk along; the news
    /// Where the guests' stickers sit (half-dots): the top-right corner first, then along the bottom between the walker's and the companion.
    nonisolated static let guestsMax = 2                                                                    // 3.8.1 (the user): two at a time (the server's rule)
    /// 3.8.1 (the user): above the companion, side by side beside the calendar (clear of even a tall one's head).
    func guestPlaces(_ now: Date) -> [(Visit, x: Int, y: Int)] {
        zip(guests.prefix(Walker.guestsMax), [(x: 158, y: 1), (x: 126, y: 5)]).map { ($0, $1.x, $1.y) }
    }
    func drawGuests(_ fb: inout FB, _ now: Date, night: Bool, tone: String) {
        let t = now.timeIntervalSinceReferenceDate
        for (k, p) in guestPlaces(now).enumerated() {
            let hop = Int(t * 2 + Double(k)) % 4 == 0 ? 2 : 0
            fb.stuck("nb|visit|\(p.0.mon.dex)|" + tone, p.x, p.y - hop) { lcdReady(sticker(iconPic(p.0.mon.dex), night: night)) }
        }
    }
    /// A tap on a guest: the 맡기기 tab (3.8.1: no 인사).
    func guestTouched(_ x: Int, _ y: Int) -> Bool {
        for p in guestPlaces(Date()) where (p.x / 2..<p.x / 2 + 17).contains(x) && (p.y / 2..<p.y / 2 + 17).contains(y) {
            cloud?.teamDue = true; screen = .team(sel: 0, tab: 5, card: false); return true
        }
        return false
    }
    func visitNews(_ n: News, _ now: Date) {
        cloud?.teamDue = true
        switch n {
        case .visitCame(_, let owner, let dex, _):
            screen = .say([josa(owner, "의", "의") + " " + josa(monNames[dex], "을", "를"), "맡았다!", "5시간 같이 걸어요"], next: .home, since: now)
            notify("pet", josa(owner, "이", "가") + " " + josa(monNames[dex], "을", "를") + " 맡겼어요", "5시간 동안 같이 걸어요 · 2,000걸음마다 1BP")
        case .visitDone(let owner, let dex, let steps, let bp):
            screen = .say([josa(owner, "의", "의") + " " + josa(monNames[dex], "이", "가"), "돌아갔다", "\(steps.formatted())걸음" + (bp > 0 ? " · +\(bp)BP" : "")], next: .home, since: now)
        default: break
        }
    }
}
