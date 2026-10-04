import Foundation
// docs/plans/12 §5 (3.6): live battles — a challenge to a friend walking now, the invitation (수락 · 거절 within a minute), then the fight on
// the battle screens (공격 · 교체 · 기권, 30 s a pick, the other player's pick waited for), the result. The battle is the server's: polls on the
// duel's own lane (Cloud.duelPoll: "since" the turns already played, long-polling until the version moves) bring the turns as beats; an act
// only hands in this side's pick (its reply's state is kept, never its beats: the poll brings those, once).

/// The invitation's pages: one to me (from, accept / decline), mine out (to, cancel).
enum DuelStep { case invite(id: Int, from: String), waitAccept(id: Int, to: String) }

extension Walker {
    static let duelTurn = 30
    /// Seconds left to pick (the server's deadline), nil when none runs.
    func duelLeft(_ now: Date = Date()) -> Int? { duel?.deadline.map { max(0, $0 - Int(now.timeIntervalSince1970)) } }

    // MARK: in and out
    /// 대전 신청 from a friend's card (walking now): the server tells them; this side waits for the answer.
    func challenge(_ name: String, _ now: Date = Date()) {
        guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: screen, since: now); return }
        act(.duelChallenge(to: name), back: screen, now) { [weak self] o, now in
            guard let self, let v = o.duel else { return nil }
            duelStart(v); return .duel(.waitAccept(id: v.id, to: name))
        }
    }
    /// A duel to follow from here: its view kept, nothing played yet, the polls going (cloudTick: duelTick).
    func duelStart(_ v: DuelView) { duel = v; duelOn = true; duelSeen = 0; duelShown = nil; duelWait = false }
    func duelStop() { duelOn = false; duelWait = false; cloud?.duelPoll = nil }
    /// The invitation's news: said, then its page (the poll brings its deadline, and a cancel or its end).
    func duelInvited(_ id: Int, _ from: String, _ now: Date) {
        duel = DuelView(id: id, state: "invited", opponent: from, challenger: false); duelOn = true; duelSeen = 0; duelShown = nil; duelWait = false
        screen = .say([josa(from, "이", "가") + " 대전을 신청했다!"], next: .duel(.invite(id: id, from: from)), since: now)
        notify("pet", josa(from, "이", "가") + " 대전을 신청했어요", "1분 안에 수락하면 바로 시작해요 (Lv.50 · 타워 파티)")
    }
    /// 수락 (the fight starts: its opening plays at once), 거절, 신청 취소.
    func duelAnswer(_ what: String, _ now: Date) {
        guard let d = duel else { return }
        switch what {
        case "수락":
            act(.duelAccept(id: d.id), back: screen, now) { [weak self] o, now in
                guard let self, let v = o.duel else { return nil }
                duel = v; return duelPlay(v, now) ?? duelScreen(now)                                  // (since 0: its opening, once)
            }
        case "거절":
            act(.duelDecline(id: d.id), back: screen, now) { [weak self] _, now in self?.duelStop(); return .say(["대전 신청을", "거절했다"], next: .home, since: now) }
        default:
            act(.duelCancel(id: d.id), back: screen, now) { [weak self] _, now in self?.duelStop(); return .say(["대전 신청을", "취소했다"], next: .home, since: now) }
        }
    }

    // MARK: the poll's answers
    /// The cloud tick's: answers taken, the next poll asked for (since the turns played, waiting on this version) while one is on.
    func duelTick(_ c: Cloud, _ now: Date) {
        for v in c.takeDuel() { duelGot(v, now) }
        guard duelOn, c.duelPoll == nil, !c.duelInFlight else { return }
        let open = duel.map { ["invited", "active"].contains($0.state) } ?? true
        c.duelPoll = DuelReq(id: "", session: "", since: duelSeen, wait: open && duel?.deadline != nil, version: duel?.version)
    }
    /// A view from a poll: new turns play (from the battle last shown); else where it stands now (whose pick, the end).
    func duelGot(_ v: DuelView?, _ now: Date) {
        guard duelOn, let v else { return }
        if let d = duel, d.id == v.id, v.version < d.version { return }                            // (an older one, overtaken)
        duel = v
        if case .beats = screen { return }                                                         // its end looks again (beatsDone)
        if let s = duelPlay(v, now) { screen = s; return }
        if waiting == nil { duelSettle(now) }
    }
    /// The turns after those played, as beats from the battle last shown; nil when there are none new.
    func duelPlay(_ v: DuelView, _ now: Date) -> Screen? {
        guard v.turn > duelSeen, !v.beats.isEmpty, let b = v.battle else { duelSeen = max(duelSeen, v.turn); return nil }
        let from = duelShown ?? b
        duelSeen = v.turn; duelShown = b; duelWait = false; fight = b
        return .beats(b, v.beats, since: now, from: from)
    }
    /// Where the duel stands: the invitation's page, whose pick (the menu, who's next, or the wait), or how it went.
    func duelScreen(_ now: Date) -> Screen {
        guard let v = duel else { duelStop(); return .home }
        switch v.state {
        case "invited": return v.challenger ? .duel(.waitAccept(id: v.id, to: v.opponent)) : .duel(.invite(id: v.id, from: v.opponent))
        case "active":
            guard let b = v.battle else { return .home }
            duelShown = duelShown ?? b; fight = b
            switch v.need {
            case "move": duelWait = false; return .battle(b, sel: 0)
            case "replace": duelWait = false; return .party(b, sel: b.mine.indices.first { b.mine[$0].alive && $0 != b.me } ?? 0)
            default: duelWait = true; return .battle(b, sel: 0)                                     // the other's pick: 상대를 기다리는 중
            }
        case "over":
            duelStop(); fight = nil; cloud?.saveNow()                                              // (the record and BP: the next act brings the save)
            let r = v.result
            let why = r.map { $0.why == "timeout" ? ($0.won ? "상대의 시간 초과" : "시간 초과") : $0.why == "forfeit" ? ($0.won ? "상대가 기권했다" : "기권했다") : "" } ?? ""
            let lines = (r?.won == true ? ["이겼다!", "+\(r?.bp ?? 0) BP"] : [josa(v.opponent, "에게", "에게") + " 졌다..."]) + (why.isEmpty ? [] : [why])
            notify("grow", r?.won == true ? josa(v.opponent, "과", "와") + "의 대전에서 이겼어요" : josa(v.opponent, "과", "와") + "의 대전에서 졌어요", why)
            return .say(lines, next: .home, since: now)
        default:
            duelStop()
            let why = v.state == "declined" ? "상대가 거절했다" : v.state == "cancelled" ? "상대가 취소했다" : "시간이 지났다"
            return .say(["대전이", why], next: .home, since: now)
        }
    }
    func duelSettle(_ now: Date) {
        switch screen {
        case .battle, .party, .duel, .home, .say: break
        case .moves, .forfeit: if duel?.need == "move", !duelWait { return }                      // mid-choice: left alone
        default: if duel?.state == "active" || duel?.state == "invited" { return }                  // elsewhere (a menu): the poll waits for the fight's screens
        }
        if case .say(_, let n, _) = screen { if case .duel = n {} else { return } }                 // a message up: its own next
        if case .battle = screen, duel?.need == "move", !duelWait, duel?.state == "active" { return }   // already choosing
        screen = duelScreen(now)
    }
    /// The beats are over: where it stands now (a newer view may have come meanwhile: its turns play first).
    func duelAfterBeats(_ now: Date) -> Screen {
        if let v = duel, let s = duelPlay(v, now) { return s }
        return duelScreen(now)
    }

    // MARK: this side's pick
    /// 공격 · 교체 · 다음 포켓몬 · 기권 go to the server as this turn's pick; then the other's is waited for (the poll brings the turn).
    func duelPick(_ cmd: BattleCmd, _ b: Battle, back: Screen, _ now: Date) {
        guard let d = duel else { return }
        act(.duelMove(id: d.id, cmd: cmd), back: back, now) { [weak self] o, now in
            guard let self else { return nil }
            if case .beats = screen { return nil }                                                  // the poll brought the turn first: it's playing
            if let v = o.duel, v.version >= (duel?.version ?? 0) { var kept = v; kept.beats = []; kept.turn = min(v.turn, duelSeen); duel = kept }   // its state (never its beats)
            duelWait = true; cloud?.duelPoll = nil
            return .battle(duelShown ?? b, sel: 0)
        }
    }

    // MARK: the invitation's page
    func duelPane(_ s: DuelStep, _ now: Date) -> PaneContent {
        let left = duelLeft(now).map { "\($0)초 남음" } ?? ""
        let rec = "내 기록 \(state.duelWins ?? 0)승 \(state.duelLosses ?? 0)패"
        switch s {
        case .invite(_, let from):
            return PaneContent(duel: DuelModel(title: josa(from, "의", "의") + " 대전 신청", line: "Lv.50 · 각자의 타워 파티 · 이기면 +3BP", note: left, buttons: ["수락", "거절"], record: rec))
        case .waitAccept(_, let to):
            return PaneContent(duel: DuelModel(title: to + "에게 대전 신청", line: "상대의 수락을 기다리는 중…", note: left, buttons: ["신청 취소"], record: rec))
        }
    }
    func duelLCD(_ fb: inout FB, _ s: DuelStep, _ now: Date) {
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        fb.text("실시간 대전", 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(state.companion, half, 0, 2, anim: animT("duel", state.companion.dex, now))
        let who: String = { switch s { case .invite(_, let f): f; case .waitAccept(_, let t): t } }()
        fb.text("vs", 94, 15, 2, right: true, small: true); fb.text(who, 94, 26, 3, right: true, small: true)
        if let l = duelLeft(now) { fb.text("\(l)초", 94, 37, 2, right: true, small: true) }
        switch s {
        case .invite: fb.text("● 수락", 94, 52, 2, right: true, small: true)
        case .waitAccept: fb.text("기다리는 중" + String(repeating: ".", count: Int(now.timeIntervalSinceReferenceDate * 2) % 4), 94, 52, 2, right: true, small: true)
        }
    }
    func duelPress(_ k: Int, _ s: DuelStep, _ now: Date) {
        guard k == 1 else { return }
        switch s { case .invite: duelAnswer("수락", now); case .waitAccept: duelAnswer("신청 취소", now) }
    }
    func duelTap(_ code: Int, _ now: Date) {
        guard case .duel(let s) = screen else { return }
        switch (s, code) {
        case (.invite, 6300): duelAnswer("수락", now)
        case (.invite, 6301): duelAnswer("거절", now)
        case (.waitAccept, 6300): duelAnswer("신청 취소", now)
        default: return
        }
    }
}
