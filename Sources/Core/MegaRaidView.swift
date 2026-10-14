import Foundation
// 5.0 (docs/plans/18 §6.4 · §9.6, content5): the Mega raid on the raid's own screens (raidMega) — its lobby's tabs are the week's two bosses
// (✓: that stone had), its chips the week's runs and that boss's 스톤까지 n/20; ● fights (its tier, then 1–3 of ours: Act.megaRaid). No balls:
// a win may mail its stone (★1 3 % … ★5 20 %), and 20 wins on one boss while its stone is missing bring it for sure (the user, 10-14: "보스별로
// 20번"); either says so after the run, the stone big on its card.

extension Walker {
    var megaLobby: MegaRaidLobby? { cloud?.megaRaid }
    /// A Mega boss as a Mon (its Mega form: the picture and the name).
    func megaMon(_ b: MegaBoss, level: Int = 50) -> Mon { var m = Mon(dex: b.dex, level: level, female: false); m.form = b.form; return m }
    func megaName(_ b: MegaBoss) -> String { Forms.of(b.dex, b.form)?.name ?? monNames[b.dex] }
    /// A boss's way to its stone: 스톤까지 n/20, or 스톤 보유.
    func megaWinsText(_ b: MegaBoss, _ r: MegaRaidLobby) -> String { b.had == true ? "스톤 보유" : "스톤까지 \(min(b.wins ?? 0, r.pityNeed))/\(r.pityNeed)" }
    var megaLeftToday: Int? { megaLobby.map { max(0, $0.today.max - $0.today.used) } }
    /// The menu tile's line.
    var megaNote: String {
        guard let r = megaLobby else { return "파워 \(raidCells)칸 · 하루 \(RaidRules.perDay)판" }
        let near = r.bosses.filter { $0.had != true }.max { ($0.wins ?? 0) < ($1.wins ?? 0) }          // (the week's boss nearest its stone)
        return (megaLeftToday == 0 ? "오늘 끝 · " : "오늘 \(megaLeftToday ?? 0)판 · ") + (near.map { megaWinsText($0, r) } ?? "스톤 모두 보유")
    }

    func megaLobbyPane(_ tab: Int, _ now: Date) -> PaneContent {
        let power = raidPower, toNext = Engine.raidPowerCost - power % Engine.raidPowerCost
        let powerText = power >= Engine.raidPowerMax ? "가득 찼어요" : "다음 칸까지 \(toNext.formatted())걸음"
        guard let r = megaLobby, let b = r.bosses[safe: tab] else {
            let note = cloud?.online == false ? "연결되면 볼 수 있어요" : "불러오는 중…"
            return PaneContent(raid: RaidModel(boss: "메가 레이드", left: "", todayUsed: 0, todayMax: RaidRules.perDay, todayText: note, power: power, powerText: powerText,
                                               week: [], tabs: ["", ""], tab: tab, rows: [], empty: note, go: nil, hint: note, ranks: false))
        }
        let rows = r.runs.filter { $0.dex == b.dex }.prefix(3).map { run in
            RaidModel.Row(rank: nil, dex: run.dex, shiny: false, name: (r.tiers.first { $0.tier == run.tier }.map { "Lv.\($0.level) · " } ?? "") + "\(run.bars)/\(RaidRules.bars)줄",
                          value: ago(max(60, Int(now.timeIntervalSince1970) - run.at)), pill: run.won ? "승" : "패", me: false, art: artIndex(b.dex, b.form))
        }
        let left = max(0, r.today.max - r.today.used)
        var go: String? = nil, hint = ""
        if left == 0 { hint = "오늘은 \(r.today.max)판을 다 했어요 · 내일 0시에 다시" }
        else if raidCells == 0 { hint = "파워가 부족해요 (\(Engine.raidPowerCost.formatted())걸음마다 1칸)" }
        else { go = "도전 · 파워 1칸" }
        return PaneContent(raid: RaidModel(boss: megaName(b), left: raidLeft(r.ends, now), todayUsed: r.today.used, todayMax: r.today.max,
                                           todayText: left == 0 ? "내일 다시" : "\(left)판 남음", power: power, powerText: powerText,
                                           week: ["\(r.mine.runs)판 · \(r.mine.wins)승", megaWinsText(b, r)],   // (this boss's; the week's stones: the tabs' ✓)
                                           tabs: r.bosses.map { megaName($0) + ($0.had == true ? " ✓" : "") }, tab: tab, rows: Array(rows),
                                           empty: "이번 주에 이 보스와 한 판이 없어요", go: go, hint: hint, ranks: false, roomy: true,
                                           rule: "이기면 확률로 메가스톤 · 같은 보스 \(r.pityNeed)승이면 확정"))   // 5.0 (the user: 처음 보는 사람도 바로)
    }
    /// A tier's first-win reward for this boss (the user, 10-14: ★4 은색병뚜껑 · ★5 금색병뚜껑, once a boss and tier): its item, its words, whether
    /// it's been paid (nil: none at this tier, or a lobby without firstGot).
    func megaFirst(_ tier: Int) -> (item: String, text: String, got: Bool)? {
        guard let item = MegaRaid.firstWins[tier], let got = megaLobby?.bosses[safe: raidMegaBoss]?.firstGot.map({ $0.contains(tier) }) else { return nil }
        return (item, got ? "첫 승리 받음" : "첫 승리 " + item, got)
    }
    func megaTierNote(_ t: RaidTier?) -> String {
        guard let t, let r = megaLobby, let b = r.bosses[safe: raidMegaBoss] else { return "" }
        let odds = r.odds[safe: t.tier - 1] ?? 0
        let first = megaFirst(t.tier).flatMap { $0.got ? nil : " · 첫 승리 " + $0.item }               // 5.0: this tier's first-win cap, still to come
        return (b.had == true ? "이기면 \(odds)% 확률로 BP \(MegaRaid.duplicateBP(t.tier))" + (first == nil ? " (스톤은 이미 있어요)" : "") : "이기면 \(odds)% 확률로 \(b.stone)" + (first == nil ? " · 볼 없음" : "")) + (first ?? "")
    }
    func megaLCD(_ fb: inout FB, _ tab: Int, _ now: Date) {
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        guard let r = megaLobby, let b = r.bosses[safe: tab] else { fb.text("메가 레이드", 2, 0); fb.fill(0, 12, 96, 1, 2); fb.text(cloud?.online == false ? "연결되면 볼 수 있다" : "불러오는 중...", 0, 30, 2, center: true); return }
        let m = megaMon(b)
        fb.text(megaName(b), 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(m, half, 0, 2, anim: animT("mega raid \(tab)", m.art, now))
        fb.text("메가 레이드", 94, 15, 2, right: true, small: true)
        fb.text(raidLeft(r.ends, now), 94, 26, 2, right: true, small: true)
        fb.text((megaLeftToday ?? 0) == 0 ? "내일 다시" : "오늘 \(megaLeftToday ?? 0)판", 94, 37, (megaLeftToday ?? 0) > 0 ? 3 : 1, right: true, small: true)
        fb.text(megaWinsText(b, r), 94, 52, b.had == true ? 2 : 3, right: true, small: true)
    }
    /// The lobby's ● (and its button): a run — its tier first. ◀ ▶: the other boss.
    func megaLobbyPress(_ k: Int, _ tab: Int, _ now: Date) {
        if k != 1 { screen = .raid(.lobby(tab: 1 - tab)); return }
        guard calm, let r = megaLobby else { return }
        if (megaLeftToday ?? 0) == 0 { screen = .say(["오늘은 \(r.today.max)판을", "다 했어요"], next: .raid(.lobby(tab: tab)), since: now); return }
        guard raidCells > 0 else { screen = .say(["파워가 부족하다", "(\(Engine.raidPowerCost.formatted())걸음마다 1칸)"], next: .raid(.lobby(tab: tab)), since: now); return }
        raidMegaBoss = tab; screen = .raid(.tier(sel: raidTierIndex))
    }

    /// A Mega raid run over: its bars, its BP (or BP for a stone had: by mail); then a stone that came (a drop or the boss's 20th win) on its
    /// own card, the stone big (sayStone); then its lobby (no balls).
    func megaRaidEnded(_ b: Battle, _ e: BattleEnd, _ now: Date) -> Screen {
        raidOn = false; cloud?.megaRaidDue = true; cloud?.raidDue = true
        var stone: String? = nil, first: String? = nil, weekly = false
        news.removeAll {
            guard case .mailNew(_, let t) = $0 else { return false }
            if t.hasSuffix("를 얻었다!") || t.hasSuffix("을 얻었다!") || t.hasSuffix("대신 BP") { stone = t; mailNews(t); return true }
            if t.hasSuffix("첫 승리!") { first = t; mailNews(t); return true }                      // 5.0: a tier's first win (★4 은색병뚜껑, ★5 금색병뚜껑)
            if t.hasPrefix("레이드") { weekly = true; mailNews(t); return true }
            return false
        }
        let won = e.result == "won", bars = e.bars ?? b.theirs.filter { !$0.alive }.count
        let paid = (e.gifts ?? []).map(giftName).joined(separator: " · ")
        var lines = won ? ["\(RaidRules.bars)줄을 모두 깼다!"] + (paid.isEmpty ? [] : [paid]) : [bars > 0 ? "\(bars)줄을 깼다" : "줄을 깨지 못했다"]
        if stone?.hasSuffix("대신 BP") == true { lines.append("스톤 대신 BP가 우편함에 왔다") }
        if let f = first, let tier = f.split(separator: "★").last?.split(separator: " ").first.flatMap({ Int($0) }), let item = MegaRaid.firstWins[tier] {
            lines.append("★\(tier) 첫 승리! " + josa(item, "이", "가") + " 왔다")
        }
        if weekly { lines.append("우편함에 이번 주 보상이 왔다") }
        if !news.isEmpty { growthThen = .raid(.lobby(tab: raidMegaBoss)) }
        let after: Screen = news.isEmpty ? .raid(.lobby(tab: raidMegaBoss)) : .home
        guard let t = stone, !t.hasSuffix("대신 BP"), let name = Forms.stones.first(where: { t.contains(josa($0, "을", "를")) }) else { return .say(lines, next: after, since: now) }
        let got = [t.hasPrefix("\(MegaRaid.bossWins)승!") ? "같은 보스 \(MegaRaid.bossWins)승!" : "행운의 메가스톤!", josa(name, "을", "를"), "얻었다!", "우편함에서 받아요"]
        sayStone = (got, name)
        return .say(lines, next: .say(got, next: after, since: .distantFuture), since: now)
    }
}
