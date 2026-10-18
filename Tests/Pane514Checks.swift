import Foundation
// 5.1.4 (the user via 회사 10-18: "트레이너 카드 글자 잘리고 메가레이드에서 클리어 했을때 볼 2개 추가 같은 필요없는 문구 수정"): self-test checks
// (run by selftest()). A page's words where they can be read (paneOverflow: over other words, past the page, cut short, across a button's or a
// tile's edge — the words-only look-out missed the 5.1.3 card's 코스 line half under its buttons) on the friends' cards filled as a real one is
// (a 칭호, 721 · 이로치, 레이드, 메가스톤, 대전, long numbers, 맡김 or the longest course) — a friend walking or not, mine, 전체's — and my own card, at
// 크기 2 · 3 · 4; the Mega raid saying nothing of balls or catching (its lobby, tiers, 출전, the fight's 등장 and 승리, the title), the raid's as before.

/// What on the walker's page can't be read as drawn (TextCanvas: the words and the rounded boxes).
@MainActor func paneOverflow(_ w: Walker) -> [String] {
    w.refreshPane(Date(), force: true)
    let canvas = TextCanvas(), page = Page(); page.walker = w
    cutTexts = []; drawnTexts = []
    page.draw(on: canvas)
    let texts = (drawnTexts ?? []).map { (s: $0.s, r: $0.r.offsetBy(dx: 0, dy: -200_000)) }   // (the page's surface: Page.draw's drawnSurface 2)
    let cut = cutTexts ?? []; cutTexts = nil; drawnTexts = nil
    let bottom = (w.pane.height - Layout.pane) * K, right = 207 * K
    var bad = textClashes(texts, width: Layout.w * K) + cut.map { "cut: \($0)" }
    for t in texts where t.r.maxY > bottom + 0.5 || t.r.maxX > right + 0.5 { bad.append("past the page: \(t.s)") }
    for t in texts { for b in canvas.boxes {
        let i = t.r.intersection(b)
        guard !i.isNull, i.width * i.height > 0.15 * t.r.width * t.r.height, !b.insetBy(dx: -1, dy: -1).contains(t.r) else { continue }
        bad.append("\(t.s) across a box's edge")
    } }
    return bad
}

/// The friends' cards as full as a real one gets (content5 on): me (포켓몬 박사, no raid) and four — 트레이너긴이름 walking now (a long 칭호), 김지훈 and
/// 멀리있음 not (메가 마스터), 모르는사람 not a friend (전체) — each 721 · 이로치 145 · 레이드 11판 8승 · 메가스톤 47/48 · 대전 999승 999패 · 1,234,567걸음 ·
/// the longest course's name. (Also the renders': Shots, WinRender.)
@MainActor func fullCards() -> Walker {
    let srv = FakeCloud(), longest = courses.indices.max { textWidth(courses[$0].name) < textWidth(courses[$1].name) } ?? 0
    var r = Seeded(s: 514)
    @MainActor func full(_ title: String, course: Int) -> Walk {
        var w = Walk(); w.companion = Mon.wild(448, level: 100, &r); w.caught = [Mon.wild(6, level: 100, &r), Mon.wild(150, level: 100, &r), Mon.wild(384, level: 100, &r)]
        w.owned = Array(1...721); w.seen = w.owned; w.shinyOwned = Array(1...145); w.today = 1_234_567; w.total = 99_999_999
        w.towerBest = 999; w.bp = 99_999; w.bestChain = 999; w.duelWins = 999; w.duelLosses = 999; w.titles = [title]; w.deco = "gold"; w.course = course
        w.bag = Array(MegaRaid.stones.sorted().prefix(47)); return w
    }
    let me = online({ var s = full("포켓몬 박사", course: 41); s.raidPower = 5000; return s }(), server: srv), key = server(me).1
    for (k, n) in ["트레이너긴이름", "김지훈", "멀리있음", "모르는사람"].enumerated() {
        srv.add(n, full(k == 0 ? "하나·칼로스 도감 마스터" : MegaRaid.master, course: longest)); srv.lastAct[n] = k == 0 ? Date() : Date().addingTimeInterval(-7200)
        if k < 3 { srv.friends.insert(FakeCloud.pair(key, n)) }
        srv.raidRuns[n] = (0..<11).map { j in FakeCloud.RaidRun(tier: 5, boss: Mon(dex: 249, level: 80, female: false), day: "2026-10-1\(j % 7)", at: srv.clockNow - 600 * (j + 1), bars: 10, won: j < 8, caught: j < 4, ended: true) }
    }
    srv.viewAll.insert(key)
    me.cloud!.teamDue = true; drain(me)
    return me
}

@MainActor func pane514Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func add(_ t: (Bool, String, String)) { c.append((t.0, t.1)); if !t.0 { print("pane514: \(t.1.prefix(32))… — \(t.2)") } }
    let size = SIZE; defer { SIZE = size }

    Content.$testing.withValue(true) {
        // the friends' cards, as full as a real one gets
        let me = fullCards()
        var r = Seeded(s: 515)
        var bad: [String] = [], seen = 0
        let rows = me.teamRows(0), all = me.teamRows(TeamTab.all)
        for px in [2, 3, 4] as [CGFloat] {
            SIZE = px
            for (i, row) in rows.enumerated() {
                me.screen = .team(sel: i, tab: 0, card: true)
                let p = me.paneContent(Date()).teamCard; seen += p?.lines.count == 9 ? 1 : 0
                bad += paneOverflow(me).map { "×\(Int(px)) \(row.card.name): \($0)" }
                let lastLine = TeamCardModel.linesTop + (p?.step ?? 0) * CGFloat(max(0, (p?.lines.count ?? 1) - 1))
                if lastLine + 8 > TeamCardModel.buttonsTop { bad.append("×\(Int(px)) \(row.card.name): its last line at \(lastLine)") }
            }
            if let j = all.firstIndex(where: { $0.card.name == "모르는사람" }) { me.screen = .team(sel: j, tab: TeamTab.all, card: true); bad += paneOverflow(me).map { "×\(Int(px)) 전체: \($0)" } }
            me.screen = .card(0); bad += paneOverflow(me).map { "×\(Int(px)) 내 카드: \($0)" }
        }
        SIZE = size
        let friend = rows.firstIndex { $0.card.name == "트레이너긴이름" }.flatMap { me.screen = .team(sel: $0, tab: 0, card: true); return me.paneContent(Date()).teamCard }
        let buttons = friend.map { [$0.duel, $0.visit].compactMap { $0 } + ($0.remove ? ["친구 끊기"] : []) } ?? []
        add((bad.isEmpty && seen >= 9 && buttons == ["대전 신청", "맡기기", "친구 끊기"] && me.paneContent(Date()).height == TeamCardModel.height,
             "5.1.4 the friends' cards full (칭호 · 721 · 이로치 145 · 레이드 11판 · 메가스톤 47/48 · 대전 999승 · 1,234,567걸음 · the longest course), a friend's walking or not, mine, 전체's, and my own card: no words over words, past the page, cut, or across a button (크기 2 · 3 · 4)",
             "\(seen) \(buttons) \(bad.prefix(6))"))

        // the Mega raid: nothing of balls or catching; the raid's own words as before
        let msrv = FakeCloud(); msrv.megaWeekNo = 0
        var mew = Mon.wild(150, level: 100, &r); mew.known = [94, 105, 58, 247]
        let mw = online({ var s = Walk(); s.companion = mew; s.raidPower = 25_000; return s }(), server: msrv)
        mw.openFeature("메가 레이드"); drain(mw); drain(mw)
        var words: [String] = []
        @MainActor func look(_ s: Screen) { mw.screen = s; mw.refreshPane(Date(), force: true); let canvas = TextCanvas(), page = Page(); page.walker = mw; page.draw(on: canvas); words += canvas.said.map(\.s) + mw.compose(Date()).runs.map(\.s) + [mw.title().0, mw.title().1] }
        for t in 0..<2 { look(.raid(.lobby(tab: t))) }
        for k in RaidRules.tiers.indices { mw.raidMegaBoss = 0; look(.raid(.tier(sel: k))) }
        mw.raidTier = 3; look(.squad(Squad(kind: .raid, picked: [], at: 0)))
        let boss = msrv.megaRaidStart(server(mw).1, 3, 0).boss
        var lines: [String] = [], appear = ""
        if let b = boss {
            var mb = Battle(wild: b.boss, companion: mew); mb.theirs += Array(repeating: Fighter(b.boss), count: RaidRules.bars - 1); mb.raidTier = 3
            for i in mb.theirs.indices { mb.theirs[i].mega = b.mega }
            mw.raidOn = true; mw.fight = mb; look(.battle(mb, sel: 0))
            appear = mw.message(.appear, 2, mb); lines = [appear, mw.message(.won, 0, mb), mw.message(.fled, 0, mb)]
            mw.raidOn = false
        }
        words += lines
        let balls = words.filter { ($0.contains("볼") && !$0.contains("볼 수")) || $0.contains("잡") }
        let megaName = boss.flatMap { b in b.mega.flatMap { Forms.of(b.boss.dex, $0)?.name } } ?? "?"
        mw.raidMega = false
        let raidWon = { @MainActor () -> String in let lu = Mon(dex: 249, level: 50, female: false); var rb = Battle(wild: lu, companion: mew); rb.theirs += Array(repeating: Fighter(lu), count: RaidRules.bars - 1); rb.raidTier = 1; mw.raidOn = true; defer { mw.raidOn = false }; return mw.message(.won, 0, rb) }()
        add((boss != nil && balls.isEmpty && appear == "메가 레이드 보스 \(megaName) 등장!" && lines[safe: 1] == "\(RaidRules.bars)줄을 모두 깼다!" && raidWon == "\(RaidRules.bars)줄을 모두 깼다! 볼 +\(RaidRules.winBalls)"
             && words.contains("메가 레이드 출전") && words.contains { $0.contains("스톤까지") },
             "5.1.4 메가 레이드: nothing of balls or catching (its lobby, every tier, 출전, the fight, its 등장 as its Mega, 승리 with no 볼 +2; the tier's note 스톤까지 n/20); the raid's 승리 keeps 볼 +2",
             "\(balls.prefix(4)) \(appear) \(lines) \(raidWon)"))
    }
    return c
}
