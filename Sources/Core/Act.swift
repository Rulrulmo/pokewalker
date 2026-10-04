import Foundation
// docs/plans/11 (3.0): the walker's half of "the app sends what the player did, the server makes the save". An act goes to the server (Cloud);
// the keys wait for its answer; the answer brings the save (shown with our unsent steps on top), the act's own screen, and news for home.

extension Walker {
    static let offlineLines = ["연결되면", "할 수 있어요"]

    /// Something the player did: to the server, keys held until it answers (lines: what the LCD says meanwhile). Then `then`'s screen (nil = as
    /// it is), or — offline, or the server's "not now" — its reason and back. quiet: the act shows its own level-ups (a fight's beats, a candy's line).
    func act(_ a: Act, back: Screen, _ now: Date = Date(), lines: [String]? = nil, quiet: Bool = false, then: @escaping @MainActor (Outcome, Date) -> Screen? = { _, _ in nil }) {
        guard let c = cloud, c.act(a) else { screen = .say(Walker.offlineLines, next: back, since: now); return }
        waiting = Waiting(act: a, back: back, since: now, quiet: quiet, then: then)
        if let lines { screen = .say(lines, next: back, since: .distantFuture) }
    }
    /// The tick's: the server's save taken (rebase), then each answer.
    func actTick(_ c: Cloud, _ now: Date) {
        let got = c.takeAnswers()
        if c.rebased { c.rebased = false; rebase(c, now) }
        for (a, r) in got { answered(a, r, now) }
    }
    /// The server's save as ours, the steps it doesn't have yet walked on top (not mid-fight: the server holds those till its end); this PC's
    /// step counter (the save's per-PC fields) kept.
    func rebase(_ c: Cloud, _ now: Date) {
        guard var w = c.base else { return }
        (w.counter, w.boot, w.syncedAt, w.counterKind) = (state.counter, state.boot, state.syncedAt, state.counterKind)
        w.rollover(now); if !inBattle { _ = w.walk(c.ahead, at: now) }
        state = w; save()
    }
    /// An act's answer (nil: none came — offline, or dropped with an old session).
    func answered(_ a: Act, _ r: ActReply?, _ now: Date) {
        let w = waiting?.act == a ? waiting : nil
        if w != nil { waiting = nil }
        guard let r else { if let w { screen = .say(Walker.offlineLines, next: w.back, since: now) }; return }   // (an act out goes again by itself: its answer may still come, late)
        if Walker.isTrade(a) { cloud?.tradesDue = true }                                           // the offers changed (or weren't what we thought): asked again
        if Walker.isMarket(a) { cloud?.marketDue = true }
        switch a { case .friendRequest, .friendAccept, .friendDecline, .friendRemove: cloud?.teamDue = true; default: break }
        news += w?.quiet == true ? r.out.news.filter { if case .level = $0 { return false }; return true } : r.out.news
        if let why = r.out.cannot { if let w { screen = .say(why.components(separatedBy: "\n"), next: w.back, since: now) }; return }
        if let w { if let s = w.then(r.out, now) { screen = s }; return }
        late(r.out, now)
    }
    /// An answer nobody waits for any more (it came after the walker gave up on it): a radar shown then is given up; a fight goes on from here.
    func late(_ o: Outcome, _ now: Date) {
        if o.radar != nil { _ = cloud?.act(.radarPick(bush: -1)); return }
        if let b = o.battle, o.end == nil, !inBattle { fight = b; freshFight(); screen = (o.beats ?? []).isEmpty ? .battle(b, sel: 0) : .beats(b, o.beats!, since: now, from: b) }
    }
    /// What was going on stops here (a lock, another trainer): the server ends it with the session.
    func dropPlay() { waiting = nil; fight = nil; fightEnd = nil; chainNext = nil; growthThen = nil; towerRun = false; raidOn = false; raidThen = nil }

    // MARK: home: the server's news, one at a time
    /// Home: the news in order (a level, an evolution, a move, a find …); once none is left, where a fight was going on to: the chain's next
    /// bush (asked for now: its clock starts when it shows; "연쇄 n!" meanwhile, never a bare home), or the tower's lobby.
    func settle(_ now: Date) {
        guard case .home = screen, waiting == nil else { return }
        if chainNext != nil {                                                                      // 3.8 (docs/plans/14 §2.3): a chain going on — only what stays home now;
            while case .home = screen, let i = news.firstIndex(where: { !Walker.leavesHome($0) }) { show(news.remove(at: i), now) }   // the rest after the chain
        } else {
            while case .home = screen, !news.isEmpty { show(news.removeFirst(), now) }
        }
        guard case .home = screen else { return }
        if let n = chainNext { chainNext = nil; nextBush(n, now); return }
        if let t = growthThen { growthThen = nil; lastInput = now; screen = t }               // the lobby's idle time starts now, not at the fight's last press
    }
    /// News whose screen takes the walker away from home (a page, a show from others): held back while a chain goes on (its next bush first).
    static func leavesHome(_ n: News) -> Bool {
        switch n {
        case .find, .egg, .hatch, .weather, .season, .level, .evolve, .learn, .unlock, .dex, .chain: false
        default: true
        }
    }
    func show(_ n: News, _ now: Date) {
        let me = monNames[state.companion.dex]
        switch n {
        case .find(let item):
            screen = .say([josa(me, "이", "가") + " 무언가를", "주워왔다!", item], next: .home, since: now)
            notify("pet", josa(me, "이", "가") + " 무언가를 주워왔어요", item)
        case .egg(_, let left):
            screen = .say([josa(me, "이", "가") + " 무언가를", "주워왔다!", "포켓몬의 알"], next: .home, since: now)
            notify("pet", josa(me, "이", "가") + " 알을 주워왔어요", "앞으로 \(left)걸음 걸으면 태어나요")
        case .hatch(let m): screen = .hatch(m, since: now); notifyHatch(m)
        case .weather(to: let w):
            notify("weather", w.news, w.types.map { typeKo[$0] ?? $0 }.joined(separator: "·") + " 타입이 자주 나와요 · " + state.here.name)
            screen = .say([w.news], next: .home, since: now)
        case .season(to: let s):
            let se = Season(rawValue: s) ?? state.season
            notify("weather", se.name + "이 왔어요", ["꽃이 피었어요", "햇볕이 쨍쨍해요", "단풍이 들었어요", "눈이 쌓여요"][se.rawValue] + " · 게임 속 \(seasonDays)일마다 계절이 바뀌어요")
            screen = .say([se.name + "이 왔다!"], next: .home, since: now)
        case .level(let u, let lv):                                                               // the companion's (the walker's level quietly; a fight showed its own)
            guard u == state.companion.uid else { break }
            if case .evolve(u, _, _, _)? = news.first { break }                                    // its evolution says it all
            screen = .say(["레벨 업!", me + " Lv.\(lv)"], next: .home, since: now)
            if lv % 5 == 0 { notify("grow", "레벨 업!", me + " Lv.\(lv)") }
        case .evolve(let u, let from, let to, _):
            guard let r = state.ref(uid: u), let m = state.mon(r) else { break }
            var f = m; f.dex = from
            screen = .evolve(from: f, to: m, since: now)
            notify("grow", "어라...? " + josa(monNames[from], "의", "의") + " 모습이...!", josa(monNames[from], "이", "가") + " " + josa(monNames[to], "으로", "로") + " 진화했어요!")
        case .learn(let u, let mv, let learned):
            guard let r = state.ref(uid: u), let m = state.mon(r) else { break }
            if learned { screen = .say([josa(monNames[m.dex], "은", "는") + " 새로", josa(moveTable[mv]!.name, "을", "를") + " 배웠다!"], next: .home, since: now) }
            else if state.nextToLearn() != nil { screen = .learn(sel: 4) }                          // on 배우지 않는다: a reflex ● forgets nothing (it stays in 기술 바꾸기)
        case .unlock(let i):
            notify("unlock", "새 코스가 열렸어요", courses[i].name + " · 메뉴 → 코스")
            screen = .say(["새 코스 해금!", courses[i].name], next: .home, since: now)
        case .dex(let count):                                                                     // Pokédex milestones: event courses and two shells
            guard count > rewarded else { break }
            let got = courses.filter { (rewarded + 1...count).contains($0.dex) }.map { $0.name + " 코스" } + shells.filter { (rewarded + 1...count).contains($0.dex) }.map { $0.name + " 기기" }
            rewarded = count
            if let g = got.first { screen = .say(["도감 \(count)종 달성!", g + " 해금"] + got.dropFirst().prefix(1), next: .home, since: now); notify("unlock", "도감 \(count)종 달성!", got.joined(separator: " · ") + " 해금") }
        case .chain(_, let bonus, let reward): chainNote = "+\(bonus)W" + (reward.map { " · " + $0 } ?? "")   // under "연쇄 n!" on the next bush
        case .hello(let from, let dex, let shiny):                                               // a teammate's 인사 (12 §2.3): its companion drops by, ♥
            visitor = Visitor(name: from, dex: dex, shiny: shiny, until: now.addingTimeInterval(90), hello: true)
            screen = .say([josa(from, "이", "가") + " 인사했다! ♥"], next: .home, since: now)
            notify("pet", josa(from, "이", "가") + " 인사했어요 ♥", josa(monNames[dex], "과", "와") + " 함께 · 눌러서 답인사")
        case .tradeOffer, .traded, .tradeClosed: tradeNews(n, now)                                   // 교환 (12 §3): an offer come, one gone through or closed (Core/TradeView.swift)
        case .raidCleared(let dex): raidNews(dex, now)                                            // the co-op raid (12 §4.3): the team beat the boss (Core/RaidView.swift)
        case .friendRequest, .friendAdded: friendNews(n, now)                                     // 친구 (12 §2.4): someone asked; it's mutual now (Core/TeamView.swift)
        case .marketBid(let id, let from, let m): marketNews(id, from, m, now)                    // the 게시판 (12 §3.3): an offer on my post (Core/MarketView.swift)
        case .duelInvite(let id, let from): duelInvited(id, from, now)                            // 실시간 대전 (12 §5): a friend asked (Core/DuelScreen.swift)
        case .claimReady, .visitCame, .visitDone: break                                         // 3.8 (docs/plans/14): minimal — the red dot, 맡겨 키우기 are the Mac's
        }
    }

    // MARK: the radar, fights, the tower
    /// 포켓 레이더: the server picks the bush (10 W, or free while a chain holds).
    func openRadar(back: Screen, _ now: Date) {
        guard state.watts >= Engine.radarFee else { screen = .say(["W가 부족하다", "(10W 필요)"], next: back, since: now); return }
        act(.radar, back: back, now, lines: ["포켓 레이더", "준비 중..."]) { [weak self] o, now in self?.radarShown(o, now) }
    }
    /// A chain's next bush, asked for (free): "연쇄 n! / 풀숲이 흔들린다" while the server picks it, as 2.x said it.
    func nextBush(_ n: Int, _ now: Date) {
        act(.radar, back: .home, now, lines: ["연쇄 \(n)!", "풀숲이 흔들린다"]) { [weak self] o, now in self?.radarShown(o, now) }
    }
    func radarShown(_ o: Outcome, _ now: Date) -> Screen? {
        guard let r = o.radar else { return nil }
        if r.chain == 0 { chainNote = nil }
        return .radar(bush: r.bush, cursor: 0, since: now, chain: r.chain)
    }
    /// ● on the radar: the bush that rustled, in time — the server starts the fight; else missed here at once (the server hears: the chain's over).
    func pickBush(_ b: Int, cursor c: Int, since: Date, chain: Int, _ now: Date) {
        if c == b, now.timeIntervalSince(since) >= 1.5 {
            act(.radarPick(bush: b), back: .home, now) { [weak self] o, now in
                guard let self else { return nil }
                if o.missed == true { return .say(chain > 0 ? ["...!", "연쇄가 끊겼다 (\(chain))"] : ["...!", "사라져버렸다"], next: .home, since: now) }   // (the server's clock: too late)
                guard let f = o.battle else { return .home }
                fight = f; freshFight()
                return (o.beats ?? []).isEmpty ? .battle(f, sel: 0) : .beats(f, o.beats!, since: now, from: f)   // (its opening changes no HP: it plays from its own state)
            }
        } else { giveUpRadar(); screen = .say(chain > 0 ? ["빗나갔다...", "연쇄 끝 (\(chain))"] : ["아무것도", "없었다..."], next: .home, since: now) }
    }
    /// The bushes went by (a wrong one, too early, too slow): the server hears, and the chain is over.
    func giveUpRadar() { chainNote = nil; _ = cloud?.act(.radarPick(bush: -1)) }
    /// A fight's act from the fight as shown (b): the server plays the turn; its beats play from b; an end waits for them (endOfFight).
    func turn(_ cmd: BattleCmd, from b: Battle, back: Screen, _ now: Date) {
        if duelOn { duelPick(cmd, b, back: back, now); return }                                    // a live battle: this side's pick, nothing played here
        act(.battle(cmd: cmd), back: back, now, quiet: true) { [weak self] o, now in self?.played(o, from: b, now) }
    }
    func played(_ o: Outcome, from b: Battle, _ now: Date) -> Screen? {
        guard let nb = o.battle else { return nil }
        if let ball = o.ball { usedItem = ball }
        fight = o.end == nil ? nb : nil; fightEnd = o.end
        guard let beats = o.beats, !beats.isEmpty else { return o.end != nil ? endOfFight(nb, now) : .battle(nb, sel: 0) }
        return .beats(nb, beats, since: now, from: b)
    }
    /// The beats are over: the fight goes on (its menu, or who comes in next), or it ended (the server's end).
    func beatsDone(_ b: Battle, _ last: Beat, _ now: Date) -> Screen {
        if let s = raidThrown(now) { return s }                                                    // a raid ball's throw (no fight behind it)
        if duelOn { return duelAfterBeats(now) }                                                   // a live battle: whatever the server says next
        if last.ends || fightEnd != nil { return endOfFight(b, now) }
        return b.mustReplace ? .party(b, sel: b.mine.indices.first { b.mine[$0].alive } ?? 0) : .battle(b, sel: 0)
    }
    /// How a fight ended, as the server said. Wild: caught or beaten with the chain going on → its next bush at once (its W and item under
    /// "연쇄 n!"), or — a level's evolution, a move to learn first — home's news, then the bush; else the grass goes quiet. Tower: the streak
    /// and its BP, the lobby (after home's news, if any); a loss ends the run.
    func endOfFight(_ b: Battle, _ now: Date) -> Screen {
        let e = fightEnd; fightEnd = nil; fight = nil
        guard let e else { return .home }
        if raidOn { return raidEnded(e, now) }                                                     // 12 §4: its damage, then the lobby
        if b.trainer != nil {
            if e.result == "won" {
                if !news.isEmpty { growthThen = .tower(pick: nil) }
                return .say(["\(e.streak ?? 0)연승!", "+\(e.bp ?? 0) BP"], next: news.isEmpty ? .tower(pick: nil) : .home, since: now)
            }
            towerRun = false
            return .say(["\(e.streak ?? 0)연승에서 끝났다", "BP \(state.bp ?? 0)"], next: .home, since: now)
        }
        guard e.result == "caught" || e.result == "won" else { chainNote = nil; return .home }
        if let n = e.chain, n > 0 {
            news.removeAll { if case .chain(_, let bonus, let reward) = $0 { chainNote = "+\(bonus)W" + (reward.map { " · " + $0 } ?? ""); return true }; return false }
            if news.allSatisfy(Walker.leavesHome) { nextBush(n, now); return screen }              // straight on: no home in between (others' news wait for the chain's end)
            chainNext = n; return .home                                                             // its bush once home's news have played (settle)
        }
        chainNote = nil
        return .say(b.chain > 0 ? ["풀숲이 조용해졌다", "연쇄 \(b.chain)에서 끝"] : ["풀숲이", "조용해졌다"], next: .home, since: now)
    }
    /// 배틀 타워's ●: in (50 W) or, on a run, the next trainer.
    func towerNext(_ now: Date) {
        guard towerRun || state.watts >= Walk.towerFee else { screen = .say(["W가 부족하다", "(\(Walk.towerFee)W 필요)"], next: .tower(pick: nil), since: now); return }
        act(.tower, back: .tower(pick: nil), now, quiet: true) { [weak self] o, now in
            guard let self, let f = o.battle else { return nil }
            towerRun = true; fight = f; freshFight()
            return (o.beats ?? []).isEmpty ? .battle(f, sel: 0) : .beats(f, o.beats!, since: now, from: f)
        }
    }
    /// Launch: steps typed while the app was quit (the same login: at most 3,000 an hour) go up with the first act.
    func awaySteps(counter: UInt32, boot: Double, _ now: Date = Date()) {
        let gap = state.syncedAt.map { now.timeIntervalSinceReferenceDate - $0 } ?? 3600
        let n = state.roomToday(min(state.take(counter: counter, boot: boot, at: now), Int(max(0, gap) / 3600 * 3000)))
        cloud?.addSteps(n); _ = state.walk(n, at: now)
    }
}
