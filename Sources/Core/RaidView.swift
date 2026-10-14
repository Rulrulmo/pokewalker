import Foundation
// docs/plans/16 (4.0): the raid as runs. The lobby (this week's species, today's runs and power, my week, 친구 이번 주 / 내 판) is the server's
// (Cloud.raid: RaidLobby, /v2/raid); a run is 1칸 of power at a tier picked here (★1–★5), against a boss of its own (the server's, its shiny
// shown as it comes in), 10 bars on the battle screens; then its ball stage — that boss only, 3 balls (5 for a win), thrown one at a time, or
// given up (raidQuit, asked first). A stage cut off (the app closed, asleep, offline) waits on the server: opening the lobby goes back to it.

/// The raid's pages: the lobby (its two tabs), the tier to fight at, a run's ball stage (RaidPending: Walker.raidStage).
enum RaidStep: Equatable { case lobby(tab: Int), tier(sel: Int), balls }

extension Walker {
    static let raidTabs = ["친구 이번 주", "내 판"]
    var raidPower: Int { state.raidPower ?? 0 }
    var raidCells: Int { raidPower / Engine.raidPowerCost }
    var raidLobby: RaidLobby? { cloud?.raid }
    func isMe(_ name: String) -> Bool { trainerID(name)?.key == trainerID(myName)?.key }
    /// Runs left today (nil: no lobby yet); 0 before runs open.
    var raidLeftToday: Int? { raidLobby.map { max(0, $0.today.max - $0.today.used) } }
    /// A ball stage to go back to: the one on screen, else the server's (cut off).
    var raidWaiting: RaidPending? { raidStage ?? raidLobby?.pending }
    func bossName(_ m: Mon) -> String { (m.shiny == true ? "★" : "") + monNames[m.dex] }
    /// A tier as the server has it now (the lobby's), else as this app was built.
    func raidTierInfo(_ n: Int) -> RaidTier? { raidLobby?.tiers.first { $0.tier == n } ?? RaidRules.tier(n) }
    /// 홈's status row: a ball stage waiting, today's runs and power, the boss.
    var raidStatus: String {
        guard let r = raidLobby else { return "파워 \(raidCells)칸" }
        if let p = raidWaiting { return "잡을 기회가 남았어요! · " + bossName(p.boss) }
        if r.opens != nil { return "새 레이드 곧 열려요" }
        if raidLeftToday == 0 { return "오늘 끝 · 내일 다시 · " + monNames[r.boss.dex] }
        return "오늘 \(raidLeftToday ?? 0)판 · 파워 \(raidCells)칸 · " + monNames[r.boss.dex]
    }
    /// The menu tile's line.
    var raidNote: String {
        guard raidLobby != nil else { return "파워 \(raidCells)칸 · 하루 \(RaidRules.perDay)판" }
        if raidWaiting != nil { return "잡을 기회가 남았어요!" }
        if raidLobby?.opens != nil { return "곧 열려요" }
        if raidLeftToday == 0 { return "오늘 끝 · 내일 다시" }
        return "오늘 \(raidLeftToday ?? 0)판 · 파워 \(raidCells)칸"
    }
    /// The menu's red dot: a ball stage waiting.
    var raidDot: Bool { raidWaiting != nil }
    /// What's left of the week: days, or hours on its last day.
    func raidLeft(_ ends: Int, _ now: Date = Date()) -> String {
        let s = max(0, ends - Int(now.timeIntervalSince1970))
        return s >= 86400 ? "\(s / 86400 + (s % 86400 > 0 ? 1 : 0))일 남음" : s >= 3600 ? "\(s / 3600)시간 남음" : "곧 끝"
    }
    /// A week's runs in a row's few characters: 3승 · 잡음 2 · ★1 (★: caught shiny, as a shiny's ★ everywhere; none fought: -).
    func raidLine(_ w: RaidWeek?) -> String {
        guard let w, w.runs > 0 else { return "-" }
        return "\(w.wins)승 · 잡음 \(w.caught)" + (w.shiny > 0 ? " · ★\(w.shiny)" : "")
    }
    /// 친구 이번 주 (me among them): 승 → 잡음 → 이로치 → 이름; equal weeks share a rank; none fought at the bottom.
    func raidFriendRows(_ r: RaidLobby) -> [(rank: Int, f: RaidFriend)] {
        func key(_ f: RaidFriend) -> [Int] { [f.wins, f.caught, f.shiny] }
        let sorted = r.friends.sorted { a, b in key(a) != key(b) ? key(a).lexicographicallyPrecedes(key(b)) == false : a.name < b.name }
        var out: [(rank: Int, f: RaidFriend)] = [], rank = 0
        for (i, f) in sorted.enumerated() { if i == 0 || key(sorted[i - 1]) != key(f) { rank = i + 1 }; out.append((rank, f)) }
        return out
    }

    // MARK: the lobby
    func raidPane(_ step: RaidStep, _ now: Date) -> PaneContent {
        switch step {
        case .lobby(let tab): return raidMega ? megaLobbyPane(tab, now) : raidLobbyPane(tab, now)
        case .tier(let sel): return raidTierPane(sel)
        case .balls: return raidBallsPane()
        }
    }
    func raidLobbyPane(_ tab: Int, _ now: Date) -> PaneContent {
        let power = raidPower, toNext = Engine.raidPowerCost - power % Engine.raidPowerCost
        let powerText = power >= Engine.raidPowerMax ? "가득 찼어요" : "다음 칸까지 \(toNext.formatted())걸음"
        guard let r = raidLobby else {
            let note = cloud?.online == false ? "연결되면 볼 수 있어요" : "불러오는 중…"
            return PaneContent(raid: RaidModel(boss: "레이드", left: "", todayUsed: 0, todayMax: RaidRules.perDay, todayText: note, power: power, powerText: powerText,
                                               week: [], tabs: Walker.raidTabs, tab: tab, rows: [], empty: note, go: nil, hint: note))
        }
        var rows: [RaidModel.Row] = []
        if tab == 0 {
            let ranked = raidFriendRows(r).map { x in
                RaidModel.Row(rank: x.f.runs > 0 ? x.rank : nil, dex: x.f.dex, shiny: false, name: x.f.name, value: raidLine(RaidWeek(runs: x.f.runs, wins: x.f.wins, caught: x.f.caught, shiny: x.f.shiny)),
                              pill: nil, me: isMe(x.f.name))
            }
            rows = Array(ranked.prefix(5))
            if let me = ranked.first(where: \.me), !rows.contains(where: \.me) { rows[rows.count - 1] = me }   // me in place of the 5th
        } else {
            rows = r.runs.prefix(5).map { run in
                .init(rank: nil, dex: run.dex, shiny: run.shiny, name: (r.tiers.first { $0.tier == run.tier }.map { "Lv.\($0.level) · " } ?? "") + "\(run.bars)/\(RaidRules.bars)줄" + (run.won ? " · 승" : ""),   // (the tier by its boss's level: ★ is a shiny's mark here)
                      value: ago(max(60, Int(now.timeIntervalSince1970) - run.at)), pill: run.caught ? "잡음" : "놓침", me: false)
            }
        }
        let left = max(0, r.today.max - r.today.used), m = r.mine
        var go: String? = nil, hint = ""
        if let p = raidWaiting { go = "잡을 기회 · 볼 \(p.balls)개" }
        else if r.opens != nil { hint = "새 레이드는 곧 열려요" }
        else if left == 0 { hint = "오늘은 \(r.today.max)판을 다 했어요 · 내일 0시에 다시" }
        else if raidCells == 0 { hint = "파워가 부족해요 (\(Engine.raidPowerCost.formatted())걸음마다 1칸)" }
        else { go = "도전 · 파워 1칸" }
        return PaneContent(raid: RaidModel(boss: monNames[r.boss.dex], left: raidLeft(r.ends, now), todayUsed: r.today.used, todayMax: r.today.max,
                                           todayText: r.opens != nil ? "곧 열려요" : left == 0 ? "내일 다시" : "\(left)판 남음", power: power, powerText: powerText,
                                           week: ["\(m.runs)판", "\(m.wins)승", "잡음 \(m.caught)", "이로치 \(m.shiny)"],
                                           tabs: Walker.raidTabs, tab: tab, rows: rows,
                                           empty: tab == 0 ? "아직 친구가 없어요" : "이번 주에 한 판이 없어요", go: go, hint: hint))
    }

    /// The tier to fight at: the lobby's tiers (the server's), the pick, its button.
    /// The tiers as the lobby has them (the Mega raid's own, 5.0), else as this app was built.
    var raidTiers: [RaidTier] { (raidMega ? megaLobby?.tiers : raidLobby?.tiers) ?? RaidRules.tiers }
    func raidTierPane(_ sel: Int) -> PaneContent {
        let tiers = raidTiers, t = tiers[safe: sel] ?? tiers.first
        let boss = raidMega ? megaLobby?.bosses[safe: raidMegaBoss].map(megaName) ?? "" : raidLobby.map { monNames[$0.boss.dex] } ?? ""
        return PaneContent(raidTier: RaidTierModel(boss: boss, note: (raidMega ? megaLeftToday : raidLeftToday).map { "오늘 \($0)판 남음" } ?? "",
                                                   rows: tiers.map { t in let f = raidMega ? megaFirst(t.tier) : nil; return .init(tier: t.tier, level: t.level, perfect: t.perfect, bp: t.bp, first: f?.item, firstGot: f?.got ?? false) }, sel: sel,
                                                   note2: raidMega ? megaTierNote(t) : t.map { $0.level > 100 ? "★\($0.tier)" + ([1, 3].contains($0.tier) ? "은" : "는") + " Lv.\($0.level)으로 싸우고, 잡히면 Lv.100이에요" : "10줄을 다 깨면 승리 · 볼 3개, 이기면 5개" } ?? "",
                                                   go: "★\(t?.tier ?? 1) · 출전 고르기"))
    }

    // MARK: the LCD
    func raidLCD(_ fb: inout FB, _ step: RaidStep, _ now: Date) {
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        switch step {
        case .balls: raidBallsLCD(&fb, now); return
        case .lobby(let tab) where raidMega: megaLCD(&fb, tab, now); return
        case .tier(let sel):
            guard let t = raidTiers[safe: sel], let dex = raidMega ? megaLobby?.bosses[safe: raidMegaBoss]?.dex : raidLobby?.boss.dex else { break }
            var boss = Mon(dex: dex, level: t.level, female: false); if raidMega { boss.form = megaLobby?.bosses[safe: raidMegaBoss]?.form }
            let tname = raidMega ? megaLobby?.bosses[safe: raidMegaBoss].map(megaName) ?? monNames[boss.dex] : monNames[boss.dex]   // 5.0: its Mega's name
            fb.text(tname + " Lv.\(t.level)", 2, 0); fb.fill(0, 12, 96, 1, 2)
            fb.mon(boss, half, 0, 2, anim: animT("raid tier", boss.art, now))
            fb.text(String(repeating: "★", count: t.tier), 94, 15, 3, right: true, small: true)
            fb.text("\(t.perfect)V", 94, 28, 2, right: true, small: true)
            if let f = raidMega ? megaFirst(t.tier) : nil { fb.text(f.text, 94, 40, f.got ? 1 : 3, right: true, small: true) }   // 5.0: a Mega boss's first win's cap here (no catching there)
            else if t.level > 100, !raidMega { fb.text("잡히면 Lv.100", 94, 40, 2, right: true, small: true) }   // (a boss above 100 is caught at 100)
            fb.text("이기면 BP \(t.bp)", 94, 52, 2, right: true, small: true)
            return
        case .lobby: break
        }
        guard let r = raidLobby else { fb.text("레이드", 2, 0); fb.fill(0, 12, 96, 1, 2); fb.text(cloud?.online == false ? "연결되면 볼 수 있다" : "불러오는 중...", 0, 30, 2, center: true); return }
        fb.text(monNames[r.boss.dex], 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(r.boss, half, 0, 2, anim: animT("raid", r.boss.art, now))
        let left = raidLeftToday ?? 0
        fb.text("레이드", 94, 15, 2, right: true, small: true)
        fb.text(raidLeft(r.ends, now), 94, 26, 2, right: true, small: true)
        fb.text(r.opens != nil ? "곧 열림" : left == 0 ? "내일 다시" : "오늘 \(left)판", 94, 37, left > 0 && r.opens == nil ? 3 : 1, right: true, small: true)
        fb.text("파워 \(raidCells)칸", 94, 52, raidCells > 0 ? 3 : 1, right: true, small: true)
    }

    // MARK: what you press
    /// The lobby's ● (and its button): back to a ball stage waiting, else a run — its tier first. ◀ ▶: the tabs.
    func raidPress(_ k: Int, _ step: RaidStep, _ now: Date) {
        switch step {
        case .lobby(let tab) where raidMega: megaLobbyPress(k, tab, now)
        case .lobby(let tab):
            if k != 1 { screen = .raid(.lobby(tab: 1 - tab)); return }
            guard calm else { return }                                                             // (3.8.6: not the ● that ended the fight's last line)
            if let p = raidWaiting { raidStage = p; screen = .raid(.balls); return }
            guard let r = raidLobby else { return }
            if r.opens != nil { screen = .say(["새 레이드는", "곧 열려요"], next: .raid(.lobby(tab: tab)), since: now); return }
            if (raidLeftToday ?? 0) == 0 { screen = .say(["오늘은 \(r.today.max)판을", "다 했어요"], next: .raid(.lobby(tab: tab)), since: now); return }
            guard raidCells > 0 else { screen = .say(["파워가 부족하다", "(\(Engine.raidPowerCost.formatted())걸음마다 1칸)"], next: .raid(.lobby(tab: tab)), since: now); return }
            screen = .raid(.tier(sel: raidTierIndex))
        case .tier(let sel):
            let n = raidTiers.count
            if k != 1 { if n > 0 { screen = .raid(.tier(sel: (sel + (k == 0 ? n - 1 : 1)) % n)) }; return }
            guard let t = raidTiers[safe: sel] else { return }
            raidTier = t.tier; if persist { settings.set("raidTier", t.tier) }; raidPick(now)
        case .balls:
            if k == 1 { raidBall(now) }
        }
    }
    /// The tier last fought at (else the highest whose boss isn't above our strongest), as a row of the lobby's tiers.
    var raidTierIndex: Int {
        let tiers = raidTiers, saved = raidTier > 0 ? raidTier : persist ? settings.int("raidTier", 0) : 0
        if let i = tiers.firstIndex(where: { $0.tier == saved }) { return i }
        let best = ([state.companion] + state.caught + state.box).map(\.level).max() ?? 1
        return tiers.lastIndex { $0.level <= best } ?? 0
    }
    func raidTap(_ code: Int, _ now: Date) {
        guard case .raid(let step) = screen else { return }
        switch (step, code) {
        case (.lobby, 7000...7001): screen = .raid(.lobby(tab: code - 7000))
        case (.lobby(let tab), 7010): raidPress(1, .lobby(tab: tab), now)
        case (.tier(let sel), 7020...7029): if code - 7020 == sel { raidPress(1, step, now) } else { screen = .raid(.tier(sel: code - 7020)) }   // a row: picked; again: on
        case (.tier, 7030): raidPress(1, step, now)
        case (.balls, 7040): raidBall(now)
        case (.balls, 7041): raidLeave(home: false, now)
        default: return
        }
    }
    /// ↩ on the raid's pages: the tier → the lobby; the ball stage → given up (asked first); the lobby → the menu.
    func raidBack(_ step: RaidStep, _ now: Date) {
        switch step {
        case .lobby: screen = menuFor(raidMega ? "메가 레이드" : "레이드")
        case .tier: screen = .raid(.lobby(tab: raidMega ? raidMegaBoss : 0))
        case .balls: raidLeave(home: false, now)
        }
    }

    // MARK: a run
    /// A run at the tier picked, with the party picked (1–3): the server takes 1칸 and makes its boss; it plays on the battle screens (raidOn:
    /// its menu, lines, HUD) — a shiny boss's line after it appears (raidShown).
    func raidFight(party: [Int]? = nil, back: Screen, _ now: Date) {
        act(raidMega ? .megaRaid(party: party, tier: raidTier, boss: raidMegaBoss) : .raid(party: party, tier: raidTier), back: back, now, lines: [raidMega ? "메가 레이드" : "레이드", "보스에게 가는 중..."], quiet: true) { [weak self] o, now in
            guard let self, let f = o.battle else { return nil }
            raidOn = true; raidStage = nil; fight = f; freshFight()
            return (o.beats ?? []).isEmpty ? .battle(f, sel: 0) : .beats(f, Walker.raidShown(o.beats!, from: f), since: now, from: f)
        }
    }
    /// A run over: the bars it broke, what it paid and its balls (a weekly reward mailed with it: said); then its ball stage.
    func raidEnded(_ b: Battle, _ e: BattleEnd, _ now: Date) -> Screen {
        if raidMega { return megaRaidEnded(b, e, now) }                                            // 5.0: no balls
        raidOn = false; cloud?.raidDue = true
        var mailed = false
        news.removeAll { if case .mailNew(_, let t) = $0, t.hasPrefix("레이드") { mailed = true; mailNews(t); return true }; return false }
        let won = e.result == "won", bars = e.bars ?? b.theirs.filter { !$0.alive }.count, balls = e.balls ?? RaidRules.balls + (won ? RaidRules.winBalls : 0)
        raidStage = RaidPending(boss: b.wild, tier: b.raidTier ?? raidTier, bars: bars, won: won, balls: balls)
        let paid = (e.gifts ?? []).map(giftName).joined(separator: " · ")
        let lines = won ? ["\(RaidRules.bars)줄을 모두 깼다!", (paid.isEmpty ? "" : paid + " · ") + "볼 \(balls)개!"]
                        : [bars > 0 ? "\(bars)줄을 깼다" : "줄을 깨지 못했다", "볼 \(balls)개"]
        return .say(lines + (mailed ? ["우편함에 이번 주 보상이 왔다"] : []), next: .raid(.balls), since: now)
    }
    /// Where a run goes once its ball stage is over: the lobby (내 판), after home's news if any (a level, a move to learn …).
    func raidAfter() -> Screen {
        raidStage = nil; cloud?.raidStageOver()
        if !news.isEmpty { growthThen = .raid(.lobby(tab: 1)); return .home }
        return .raid(.lobby(tab: 1))
    }

    /// A new lobby came: one with a ball stage cut off (the app closed, asleep, offline) goes back to it, if the lobby is up.
    func raidResume(_ now: Date) {
        guard case .raid(.lobby) = screen, !raidMega, raidStage == nil, waiting == nil, let p = cloud?.raid?.pending else { return }
        raidStage = p; screen = .say(["잡을 기회가", "남았어요!"], next: .raid(.balls), since: now)
    }

    // MARK: the ball stage
    func raidBallsPane() -> PaneContent {
        guard let p = raidStage else { return PaneContent() }
        let tier = raidTierInfo(p.tier)
        return PaneContent(raidBalls: RaidBallsModel(bars: p.bars, total: RaidRules.bars, dex: p.boss.dex, shiny: p.boss.shiny == true,
                                                     name: monNames[p.boss.dex] + " Lv.\(p.boss.level)", note: "잡히면 " + (p.boss.level > 100 ? "Lv.100 · " : "") + "\(tier?.perfect ?? p.boss.perfectIVs)V · ★\(p.tier)",
                                                     balls: p.balls, of: RaidRules.balls + (p.won ? RaidRules.winBalls : 0), won: p.won,
                                                     foot: ["남은 볼은 이 \(monNames[p.boss.dex])에게만 던질 수 있어요.", "이 화면을 나가면 사라져요."]))
    }
    /// The boss on its stage (no HUD), its balls along the bottom (left lit, thrown dark).
    func raidBallsLCD(_ fb: inout FB, _ now: Date) {
        guard let p = raidStage else { return }
        let b = Battle(wild: p.boss, companion: state.companion)
        stage(&fb, b, now, .idle)
        let of = RaidRules.balls + (p.won ? RaidRules.winBalls : 0)
        for k in 0..<of { fb.draw(caughtMark, 2 + 7 * k, 2, k < p.balls ? ballPal : [ballPal[3], rgb(120, 124, 132), rgb(120, 124, 132), ballPal[3]]) }   // (top left: the HUD's place, empty here)
    }
    /// One ball at the run's boss (the server's dice): the throw on the battle stage, then caught (into the box) or the stage again — or, the
    /// last one gone, the boss leaves.
    func raidBall(_ now: Date) {
        guard let p = raidStage, p.balls > 0, calm else { return }
        act(.raidBall, back: .raid(.balls), now, lines: ["볼을", "던질 준비..."]) { [weak self] o, now in
            guard let self, let t = o.raidThrow else { return nil }
            let name = monNames[p.boss.dex]
            raidStage?.balls = t.balls
            if t.caught { raidThen = .say([josa(name, "을", "를") + " 잡았다!", "상자로 보냈다"], next: raidAfter(), since: .distantFuture) }
            else if t.balls > 0 { raidThen = .say(["놓쳤다...", "남은 볼 \(t.balls)개"], next: .raid(.balls), since: .distantFuture) }
            else { raidThen = .say(["놓쳤다...", josa(name, "은", "는") + " 돌아갔다"], next: raidAfter(), since: .distantFuture) }
            usedItem = "몬스터볼"
            let b = Battle(wild: t.mon ?? p.boss, companion: state.companion)
            return .beats(b, [.thrown(shakes: t.caught ? 3 : t.shakes), t.caught ? .caught : .broke], since: now, from: b)
        }
    }
    /// The ball's beats are over: where it goes (its lines; the say's clock starts now).
    func raidThrown(_ now: Date) -> Screen? {
        guard var s = raidThen else { return nil }
        raidThen = nil
        func restart(_ s: Screen, _ at: Date) -> Screen { if case .say(let l, let n, _) = s { return .say(l, next: restart(n, at + 3), since: at) }; return s }   // each its 3 s, in turn
        s = restart(s, now); return s
    }
    /// Leaving the ball stage (그만두기, ↩, 홈): with balls left it's asked first, then given up at the server (raidQuit: the run 놓침).
    func raidLeave(home: Bool, _ now: Date) {
        guard let p = raidStage else { screen = home ? .home : .raid(.lobby(tab: 0)); return }
        if p.balls > 0 {
            let who = (p.boss.shiny == true ? "이로치 " : "") + josa(monNames[p.boss.dex], "은", "는")
            guard host?.confirm("그만둘까요?", "남은 볼 \(p.balls)개가 사라지고 \(who) 돌아가요.", ok: "그만두기") ?? true else { return }
        }
        act(.raidQuit, back: .raid(.balls), now) { [weak self] _, _ in
            guard let self else { return nil }
            let next = raidAfter()
            return home ? .home : next
        }
    }
}
