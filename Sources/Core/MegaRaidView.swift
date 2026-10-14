import Foundation
// 5.0 (docs/plans/18 §6.4 · §9.6, content5): the Mega raid on the raid's own screens (raidMega) — its lobby's tabs are the week's two bosses
// (✓: that stone had), its chips the week's runs, 스톤까지 n/30 and the week's stones; ● fights (its tier, then 1–3 of ours: Act.megaRaid), or
// first, with 30 wins, picks one of the week's stones (Act.megaPick). No balls: a win may mail its stone (★1 3 % … ★5 20 %).

extension Walker {
    var megaLobby: MegaRaidLobby? { cloud?.megaRaid }
    /// A Mega boss as a Mon (its Mega form: the picture and the name).
    func megaMon(_ b: MegaBoss, level: Int = 50) -> Mon { var m = Mon(dex: b.dex, level: level, female: false); m.form = b.form; return m }
    func megaName(_ b: MegaBoss) -> String { Forms.of(b.dex, b.form)?.name ?? monNames[b.dex] }
    /// The week's stones still to pick (none had), once 30 wins are in.
    func megaPicks(_ r: MegaRaidLobby) -> [MegaBoss] { r.pity >= r.pityNeed ? r.bosses.filter { $0.had != true } : [] }
    var megaLeftToday: Int? { megaLobby.map { max(0, $0.today.max - $0.today.used) } }
    /// The menu tile's line.
    var megaNote: String {
        guard let r = megaLobby else { return "파워 \(raidCells)칸 · 하루 \(RaidRules.perDay)판" }
        if !megaPicks(r).isEmpty { return "스톤을 고를 수 있어요!" }
        return (megaLeftToday == 0 ? "오늘 끝 · " : "오늘 \(megaLeftToday ?? 0)판 · ") + "스톤까지 \(min(r.pity, r.pityNeed))/\(r.pityNeed)"
    }

    func megaLobbyPane(_ tab: Int, _ now: Date) -> PaneContent {
        let power = raidPower, toNext = Engine.raidPowerCost - power % Engine.raidPowerCost
        let powerText = power >= Engine.raidPowerMax ? "가득 찼어요" : "다음 칸까지 \(toNext.formatted())걸음"
        guard let r = megaLobby, let b = r.bosses[safe: tab] else {
            let note = cloud?.online == false ? "연결되면 볼 수 있어요" : "불러오는 중…"
            return PaneContent(raid: RaidModel(boss: "메가 레이드", left: "", todayUsed: 0, todayMax: RaidRules.perDay, todayText: note, power: power, powerText: powerText,
                                               week: [], tabs: ["", ""], tab: tab, rows: [], empty: note, go: nil, hint: note, ranks: false))
        }
        let rows = r.runs.filter { $0.dex == b.dex }.prefix(5).map { run in
            RaidModel.Row(rank: nil, dex: run.dex, shiny: false, name: (r.tiers.first { $0.tier == run.tier }.map { "Lv.\($0.level) · " } ?? "") + "\(run.bars)/\(RaidRules.bars)줄",
                          value: ago(max(60, Int(now.timeIntervalSince1970) - run.at)), pill: run.won ? "승" : "패", me: false, art: artIndex(b.dex, b.form))
        }
        let left = max(0, r.today.max - r.today.used), picks = megaPicks(r)
        var go: String? = nil, hint = ""
        if !picks.isEmpty { go = "\(r.pityNeed)승! 스톤 고르기" }
        else if left == 0 { hint = "오늘은 \(r.today.max)판을 다 했어요 · 내일 0시에 다시" }
        else if raidCells == 0 { hint = "파워가 부족해요 (\(Engine.raidPowerCost.formatted())걸음마다 1칸)" }
        else { go = "도전 · 파워 1칸" }
        return PaneContent(raid: RaidModel(boss: megaName(b), left: raidLeft(r.ends, now), todayUsed: r.today.used, todayMax: r.today.max,
                                           todayText: left == 0 ? "내일 다시" : "\(left)판 남음", power: power, powerText: powerText,
                                           week: ["\(r.mine.runs)판 · \(r.mine.wins)승", "스톤까지 \(min(r.pity, r.pityNeed))/\(r.pityNeed)", "이번 주 스톤 \(r.bosses.filter { $0.had == true }.count)/\(r.bosses.count)"],
                                           tabs: r.bosses.map { megaName($0) + ($0.had == true ? " ✓" : "") }, tab: tab, rows: Array(rows),
                                           empty: "이번 주에 이 보스와 한 판이 없어요", go: go, hint: hint, ranks: false))
    }
    func megaTierNote(_ t: RaidTier?) -> String {
        guard let t, let r = megaLobby, let b = r.bosses[safe: raidMegaBoss] else { return "" }
        let odds = r.odds[safe: t.tier - 1] ?? 0
        return b.had == true ? "이기면 \(odds)% 확률로 BP \(MegaRaid.duplicateBP(t.tier)) (스톤은 이미 있어요)" : "이기면 \(odds)% 확률로 \(b.stone) · 볼 없음"
    }
    func megaLCD(_ fb: inout FB, _ tab: Int, _ now: Date) {
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        guard let r = megaLobby, let b = r.bosses[safe: tab] else { fb.text("메가 레이드", 2, 0); fb.fill(0, 12, 96, 1, 2); fb.text(cloud?.online == false ? "연결되면 볼 수 있다" : "불러오는 중...", 0, 30, 2, center: true); return }
        let m = megaMon(b)
        fb.text(megaName(b), 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(m, half, 0, 2, anim: animT("mega raid \(tab)", m.art, now))
        fb.text(b.had == true ? "스톤 ✓" : "메가 레이드", 94, 15, 2, right: true, small: true)
        fb.text(raidLeft(r.ends, now), 94, 26, 2, right: true, small: true)
        fb.text((megaLeftToday ?? 0) == 0 ? "내일 다시" : "오늘 \(megaLeftToday ?? 0)판", 94, 37, (megaLeftToday ?? 0) > 0 ? 3 : 1, right: true, small: true)
        fb.text("스톤까지 \(min(r.pity, r.pityNeed))/\(r.pityNeed)", 94, 52, megaPicks(r).isEmpty ? 2 : 3, right: true, small: true)
    }
    /// The lobby's ● (and its button): with 30 wins the stone's pick first, else a run — its tier first. ◀ ▶: the other boss.
    func megaLobbyPress(_ k: Int, _ tab: Int, _ now: Date) {
        if k != 1 { screen = .raid(.lobby(tab: 1 - tab)); return }
        guard calm, let r = megaLobby else { return }
        if !megaPicks(r).isEmpty { screen = .raid(.pick(sel: 0)); return }
        if (megaLeftToday ?? 0) == 0 { screen = .say(["오늘은 \(r.today.max)판을", "다 했어요"], next: .raid(.lobby(tab: tab)), since: now); return }
        guard raidCells > 0 else { screen = .say(["파워가 부족하다", "(\(Engine.raidPowerCost.formatted())걸음마다 1칸)"], next: .raid(.lobby(tab: tab)), since: now); return }
        raidMegaBoss = tab; screen = .raid(.tier(sel: raidTierIndex))
    }

    // MARK: the 30 wins' stone
    func megaPickRows() -> [MegaBoss] { megaLobby?.bosses ?? [] }
    func megaPickPane(_ sel: Int) -> PaneContent {
        guard let r = megaLobby else { return PaneContent() }
        let bs = megaPickRows(), s = min(sel, max(0, bs.count - 1)), b = bs[safe: s]
        let rows = bs.map { HoldModel.Row(name: $0.stone, count: 0, note: megaName($0) + "의 스톤", take: false, use: true, why: $0.had == true ? "이미 가지고 있어요" : nil, dex: $0.dex, form: $0.form) }
        return PaneContent(hold: HoldModel(who: "스톤 고르기 · \(r.pityNeed)승", now: nil, rows: rows, sel: s, action: b.flatMap { $0.had == true ? nil : $0.stone + " 받기" },
                                           hint: "\(r.pityNeed)승마다 스톤 하나 · 남은 승은 이어져요", picks: true))
    }
    func megaPickLCD(_ fb: inout FB, _ sel: Int) {
        fb.text("스톤 고르기", 2, 1, 3, small: true); fb.fill(0, 10, 96, 1, 2)
        for (k, b) in megaPickRows().enumerated() {
            let y = 14 + 12 * k
            fb.text(b.stone, 2, y, b.had == true ? 1 : 3, small: true)
            if b.had == true { fb.text("가짐", 94, y, 1, right: true, small: true) }
            if k == sel { fb.invert(0, y - 1, 96, 11) }
        }
    }
    func megaPickPress(_ k: Int, _ sel: Int, _ now: Date) {
        let bs = megaPickRows(), n = bs.count
        guard n > 0 else { screen = .raid(.lobby(tab: raidMegaBoss)); return }
        if k != 1 { screen = .raid(.pick(sel: ((sel + (k == 0 ? -1 : 1)) % n + n) % n)); return }
        guard let b = bs[safe: min(sel, n - 1)] else { return }
        if b.had == true { screen = .say(["이미 가지고 있어요"], next: .raid(.pick(sel: sel)), since: now); return }
        act(.megaPick(stone: b.stone), back: .raid(.pick(sel: sel)), now) { [weak self] _, now in
            self?.cloud?.megaRaidDue = true
            return .say([josa(b.stone, "을", "를"), "받았다!"], next: .raid(.lobby(tab: self?.raidMegaBoss ?? 0)), since: now)
        }
    }
    func megaPickTap(_ code: Int, _ now: Date) {
        guard case .raid(.pick(let sel)) = screen else { return }
        switch code {
        case 5980..<5995: let n = megaPickRows().count; screen = .raid(.pick(sel: min(max(0, n - 1), code - 5980)))
        case 5999: megaPickPress(1, sel, now)
        default: _ = sel
        }
    }
    /// A Mega raid run over: its bars, its BP; a stone (or BP for one had) comes by mail — said; then its lobby (no balls).
    func megaRaidEnded(_ b: Battle, _ e: BattleEnd, _ now: Date) -> Screen {
        raidOn = false; cloud?.megaRaidDue = true; cloud?.raidDue = true
        var stone: String? = nil, weekly = false
        news.removeAll {
            guard case .mailNew(_, let t) = $0 else { return false }
            if t.hasSuffix("를 얻었다!") || t.hasSuffix("을 얻었다!") || t.hasSuffix("대신 BP") { stone = t; mailNews(t); return true }
            if t.hasPrefix("레이드") { weekly = true; mailNews(t); return true }
            return false
        }
        let won = e.result == "won", bars = e.bars ?? b.theirs.filter { !$0.alive }.count
        let paid = (e.gifts ?? []).map(giftName).joined(separator: " · ")
        var lines = won ? ["\(RaidRules.bars)줄을 모두 깼다!"] + (paid.isEmpty ? [] : [paid]) : [bars > 0 ? "\(bars)줄을 깼다" : "줄을 깨지 못했다"]
        if let s = stone { lines.append(s.hasSuffix("대신 BP") ? "스톤 대신 BP가 우편함에 왔다" : "스톤이 우편함에 왔다!") }
        if weekly { lines.append("우편함에 이번 주 보상이 왔다") }
        if !news.isEmpty { growthThen = .raid(.lobby(tab: raidMegaBoss)) }
        return .say(lines, next: news.isEmpty ? .raid(.lobby(tab: raidMegaBoss)) : .home, since: now)
    }
}
