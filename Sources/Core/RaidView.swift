import Foundation
// docs/plans/12 §4 (M3): the co-op raid — a boss a week the whole team wears down. The lobby (the boss, the team's HP, my power, 기여 순위 /
// 최근 공격) is the server's (Cloud.raid, /v2/raid); a fight is the server's too (1칸 of power: the tower's three at their own levels against
// three of the boss's bars, 6 turns) and plays on the battle screens; once the team beat it, the balls (a throw on the battle stage).

extension Walker {
    static let raidTabs = ["기여 순위", "최근 공격"]
    var raidPower: Int { state.raidPower ?? 0 }
    var raidCells: Int { raidPower / Engine.raidPowerCost }
    func isMe(_ name: String) -> Bool { trainerID(name)?.key == trainerID(myName)?.key }
    /// The menu tile's line: a ball waiting, the week over, or power and the boss.
    var raidNote: String {
        guard let r = cloud?.raid else { return "파워 \(raidCells)칸 · 팀 보스" }
        if r.hpLeft == 0 { return r.mine.canCatch && (r.mine.balls ?? 1) > 0 ? "잡을 기회!" : "이번 주 보스 쓰러뜨림" }
        return "파워 \(raidCells)칸 · " + monNames[r.boss.dex]
    }
    /// What's left of the week: days, or hours on its last day.
    func raidLeft(_ r: RaidReply, _ now: Date = Date()) -> String {
        let s = max(0, r.ends - Int(now.timeIntervalSince1970))
        return s >= 86400 ? "\(s / 86400 + (s % 86400 > 0 ? 1 : 0))일 남음" : s >= 3600 ? "\(s / 3600)시간 남음" : "곧 끝"
    }

    // MARK: the pane
    func raidPane(_ tab: Int, _ now: Date) -> PaneContent {
        let power = raidPower, cells = raidCells, toNext = Engine.raidPowerCost - power % Engine.raidPowerCost
        let powerText = power >= 3000 ? "가득 찼어요" : "다음 칸까지 \(toNext.formatted())걸음"
        guard let r = cloud?.raid else {
            let note = cloud?.online == false ? "연결되면 볼 수 있어요" : "불러오는 중…"
            return PaneContent(raid: RaidModel(boss: "레이드", left: "", hp: 0, hpText: note, cleared: false, power: power, powerText: powerText, tabs: Walker.raidTabs, tab: tab, rows: [], empty: note, go: nil, hint: note))
        }
        let done = max(1, r.hpTotal - r.hpLeft), pct = r.hpTotal > 0 ? Int((Double(r.hpLeft) / Double(r.hpTotal) * 100).rounded(.up)) : 0
        let bars = r.barHP > 0 ? (r.hpLeft + r.barHP - 1) / r.barHP : 0, total = r.barHP > 0 ? (r.hpTotal + r.barHP - 1) / r.barHP : 0
        var rows: [RaidModel.Row] = []
        if tab == 0 {
            let ranked = r.fighters.enumerated().map { (k, f) in RaidModel.Row(rank: k + 1, dex: nil, name: f.name, value: "\(f.dealt.formatted()) · \(f.dealt * 100 / done)%", me: isMe(f.name)) }
            rows = Array(ranked.prefix(5))
            if let me = ranked.first(where: \.me), !rows.contains(where: \.me) { rows[rows.count - 1] = me }   // me in place of the 5th
        } else {
            rows = r.recent.prefix(5).map { h in .init(rank: nil, dex: h.dex, name: h.name, value: "\(h.dealt.formatted()) · " + ago(max(60, Int(now.timeIntervalSince1970) - h.at)), me: isMe(h.name)) }
        }
        let name = monNames[r.boss.dex], m = r.mine
        var go: String? = nil, hint = ""
        if r.hpLeft > 0 { if cells > 0 { go = "도전 · 파워 1칸" } else { hint = "파워가 부족해요 (1,000걸음마다 1칸)" } }
        else if m.caught { hint = josa(name, "을", "를") + " 잡았어요!" }
        else if !m.canCatch { hint = "이번 주에 싸워야 잡을 수 있어요" }
        else if let b = m.balls, b == 0 { hint = "볼을 모두 던졌어요" }
        else { go = "볼 던지기" + (m.balls.map { " · 남은 \($0)개" } ?? "") }
        return PaneContent(raid: RaidModel(boss: (r.boss.shiny == true ? "★" : "") + name + " Lv.\(r.boss.level)", left: raidLeft(r, now), hp: r.hpTotal > 0 ? CGFloat(r.hpLeft) / CGFloat(r.hpTotal) : 0,
                                           hpText: r.hpLeft == 0 ? "쓰러뜨렸다!" : "\(pct)% · 줄 \(bars.formatted()) / \(total.formatted())", cleared: r.hpLeft == 0,
                                           power: power, powerText: powerText, tabs: Walker.raidTabs, tab: tab, rows: rows,
                                           empty: tab == 0 ? "아직 아무도 싸우지 않았어요" : "아직 공격이 없어요", go: go, hint: hint))
    }

    // MARK: the LCD
    func raidLCD(_ fb: inout FB, _ now: Date) {
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        guard let r = cloud?.raid else { fb.text("레이드", 2, 0); fb.fill(0, 12, 96, 1, 2); fb.text(cloud?.online == false ? "연결되면 볼 수 있다" : "불러오는 중...", 0, 30, 2, center: true); return }
        fb.text((r.boss.shiny == true ? "★" : "") + monNames[r.boss.dex] + " Lv.\(r.boss.level)", 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(r.boss, half, 0, 2, anim: animT("raid", r.boss.dex, now))
        fb.text("레이드", 94, 15, 2, right: true, small: true)
        fb.text(raidLeft(r, now), 94, 26, 2, right: true, small: true)
        fb.text("파워 \(raidCells)칸", 94, 37, raidCells > 0 ? 3 : 1, right: true, small: true)
        if r.hpLeft == 0 { fb.text("쓰러졌다!", 94, 52, 3, right: true, small: true) } else { hpBar(&fb, 50, 55, 44, r.hpLeft, max(1, r.hpTotal)) }
    }

    // MARK: what you press
    /// ● (and the pane's button): a fight (1칸), or once the team beat it a ball. ◀ ▶: the tabs.
    func raidPress(_ k: Int, _ tab: Int, _ now: Date) {
        if k != 1 { screen = .raid(tab: 1 - tab); return }
        guard let r = cloud?.raid else { return }
        if r.hpLeft > 0 {
            guard raidCells > 0 else { screen = .say(["파워가 부족하다", "(1,000걸음마다 1칸)"], next: .raid(tab: tab), since: now); return }
            raidFight(tab, now)
        } else if r.mine.canCatch, (r.mine.balls ?? 1) > 0 { raidBall(tab, now) }
    }
    func raidTap(_ code: Int, _ now: Date) {
        guard case .raid(let tab) = screen else { return }
        switch code {
        case 7000...7001: screen = .raid(tab: code - 7000)
        case 7010: raidPress(1, tab, now)
        default: return
        }
    }
    /// A fight with the week's boss: the server takes 1칸 and starts it; it plays on the battle screens (raidOn: its menu, lines, HUD).
    func raidFight(_ tab: Int, _ now: Date) {
        act(.raid, back: .raid(tab: tab), now, lines: ["레이드", "보스에게 가는 중..."], quiet: true) { [weak self] o, now in
            guard let self, let f = o.battle else { return nil }
            raidOn = true; fight = f; freshFight()
            return (o.beats ?? []).isEmpty ? .battle(f, sel: 0) : .beats(f, o.beats!, since: now, from: f)
        }
    }
    /// A raid fight over: its damage (and BP), the team's clear if this one did it; then the lobby (after home's news, if any).
    func raidEnded(_ e: BattleEnd, _ now: Date) -> Screen {
        raidOn = false; cloud?.raidDue = true
        var cleared = false
        news.removeAll { if case .raidCleared = $0 { cleared = true; return true }; return false }
        let dealt = e.dealt ?? 0, bp = e.bp ?? 0
        let lines = ["\(dealt.formatted()) 데미지!" + (bp > 0 ? " +\(bp)BP" : "")] + (cleared ? ["보스를 쓰러뜨렸다!", "볼을 던질 수 있다"] : e.result == "fled" ? ["기세에 밀려났다"] : [])
        if !news.isEmpty { growthThen = .raid(tab: 0); return .say(lines, next: .home, since: now) }
        return .say(lines, next: .raid(tab: 0), since: now)
    }
    /// A ball at the beaten boss (12 §4.3): the throw plays on the battle stage, then caught or not (and the week's clear reward with the first).
    func raidBall(_ tab: Int, _ now: Date) {
        guard let boss = cloud?.raid?.boss else { return }
        act(.raidBall, back: .raid(tab: tab), now, lines: ["볼을", "던질 준비..."]) { [weak self] o, now in
            guard let self, let t = o.raidThrow else { return nil }
            cloud?.raidDue = true
            let name = monNames[t.mon?.dex ?? boss.dex], back = Screen.raid(tab: tab)
            let reward = Screen.say(["클리어 보상!", "25BP · 이상한사탕 ×5", "은색병뚜껑"], next: back, since: .distantFuture)
            let after: [String] = t.caught ? [josa(name, "을", "를") + " 잡았다!", "상자로 보냈다"] : ["놓쳤다...", t.balls > 0 ? "남은 볼 \(t.balls)개" : "볼을 모두 던졌다"]
            raidThen = .say(after, next: t.reward ? reward : back, since: .distantFuture)
            usedItem = "몬스터볼"
            let b = Battle(wild: t.mon ?? boss, companion: state.companion)
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
    /// The team beat it (12 §4.3; the one who did hears it at the fight's end): said, then the lobby with its balls.
    func raidNews(_ dex: Int, _ now: Date) {
        cloud?.raidDue = true
        screen = .say(["팀이 " + josa(monNames[dex], "을", "를"), "쓰러뜨렸다!", "볼을 던질 수 있다"], next: .raid(tab: 0), since: now)
        notify("unlock", "팀이 " + josa(monNames[dex], "을", "를") + " 쓰러뜨렸어요", "메뉴 → 레이드에서 볼을 던질 수 있어요")
    }
}
