import Foundation
// docs/plans/12 §5 (3.6): live battles — a challenge to a friend walking now, the invitation (수락 · 거절 within a minute), then the fight on
// the battle screens (공격 · 교체 · 기권, 30 s a pick, the other player's pick waited for), the result. The battle is the server's: polls on the
// duel's own lane (Cloud.duelPoll: "since" the turns already played, long-polling until the version moves) bring the turns as beats; an act
// only hands in this side's pick (its reply's state is kept, never its beats: the poll brings those, once).
// 3.8 (docs/plans/14 §5): the 대전 menu — the 대전 파티 (3–6 registered, Lv.50), a friend walking now or the random queue (a minute), then each
// picks 3 of their six in a minute (the other's six seen by species) before the fight; the 전적 (the last 20).

/// The invitation's pages: one to me (from, accept / decline), mine out (to, cancel).
enum DuelStep: Equatable { case invite(id: Int, from: String), waitAccept(id: Int, to: String), hub(tab: Int, sel: Int), queued }

extension Walker {
    static let duelTurn = 30
    /// Seconds left to pick (the server's deadline), nil when none runs.
    func duelLeft(_ now: Date = Date()) -> Int? { duel?.deadline.map { max(0, $0 - Int(now.timeIntervalSince1970)) } }

    // MARK: in and out
    /// 대전 신청 from a friend's card (walking now): the server tells them; this side waits for the answer.
    func challenge(_ name: String, _ now: Date = Date()) {
        guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: screen, since: now); return }
        guard duelSix.count >= 3 else { screen = .say(["대전 파티를", "먼저 정해 주세요"], next: .squad(Squad(kind: .duelParty, picked: [], at: 0)), since: now); return }   // 3.8: the six first
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
        let open = duel.map { ["invited", "active", "queued", "picking"].contains($0.state) } ?? true
        c.duelPoll = DuelReq(id: "", session: "", since: duelSeen, wait: open && duel?.deadline != nil, version: duel?.version)
    }
    /// 3.8's 전적: asked on the duel's lane while no duel is followed (its reply's view is let be).
    func duelRecordTick(_ c: Cloud) {
        guard !duelOn, c.duelRecordDue, c.duelPoll == nil, !c.duelInFlight else { return }
        c.duelRecordDue = false; c.duelPoll = DuelReq(id: "", session: "", record: true)
    }
    /// A view from a poll: new turns play (from the battle last shown); else where it stands now (whose pick, the end).
    func duelGot(_ v: DuelView?, _ now: Date) {
        guard duelOn, let v else { return }
        if let d = duel, d.id == v.id, v.version < d.version { return }                            // (an older one, overtaken)
        if v.state == "picking", duel?.state == "queued" { notify("pet", "대전 상대를 찾았어요", "1분 안에 나갈 3마리를 골라 주세요") }
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
        case "queued": return .duel(.queued)
        case "picking":
            if case .squad(let s) = screen, s.kind == .duelPick(id: v.id) { return screen }          // (the picks so far stay)
            return .squad(Squad(kind: .duelPick(id: v.id), picked: v.parties?.picked ?? [], at: 0))
        case "unmatched": duelStop(); return .say(["상대를 찾지 못했다", "잠시 뒤에 다시 해 봐요"], next: .duel(.hub(tab: 0, sel: 0)), since: now)
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
        case .squad(let s) where s.kind == .duelPick(id: duel?.id ?? -1): break
        case .moves, .forfeit: if duel?.need == "move", !duelWait { return }                      // mid-choice: left alone
        default: if ["active", "invited", "queued"].contains(duel?.state ?? "") { return }          // elsewhere (a menu): the poll waits for the fight's screens (a match found: its pick comes)
        }
        if case .duel(.hub) = screen { return }                                                    // (the 대전 menu: no duel shown there)
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

    // MARK: the 대전 menu (3.8)
    static let duelHubTabs = ["대전", "전적"]
    /// The menu tile's line: a duel going on, the party to set, or the record.
    var duelNote: String {
        if duelOn, let s = duel?.state { return s == "queued" ? "상대를 찾는 중" : s == "picking" ? "3마리 고르는 중" : s == "invited" ? "대전 신청 중" : "대전 중" }
        return duelSix.count < 3 ? "대전 파티를 정해 주세요" : "\(state.duelWins ?? 0)승 \(state.duelLosses ?? 0)패 · 친구 · 랜덤"
    }
    /// Friends walking now (a challenge's): the 대전 tab's rows.
    var duelFriends: [TeamCard] { (cloud?.team?.cards ?? []).filter { !isMe($0) && Walker.walkingNow($0) }.sorted { $0.name < $1.name } }
    /// 대전 tab's ◀ ▶ stops: 랜덤 매칭, each friend walking now (신청), 대전 파티, 전적.
    var duelHubStops: Int { duelFriends.prefix(3).count + 3 }
    func openDuelHub(_ now: Date) {
        guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: screen, since: now); return }
        c.wantTeam(now); c.duelRecordDue = true
        screen = duelOn ? duelScreen(now) : .duel(.hub(tab: 0, sel: 0))                          // a duel going on: its page
    }
    func duelHubPane(_ tab: Int, _ sel: Int, _ now: Date) -> PaneContent {
        let rec = "\(state.duelWins ?? 0)승 \(state.duelLosses ?? 0)패 · 이기면 +3BP"
        let six = duelSix, slots = (0..<6).map { six[safe: $0].map { SquadModel.Slot(dex: $0.dex, shiny: $0.shiny == true, level: "Lv.\(Walk.towerLevel)") } }
        var m = DuelHubModel(tabs: Walker.duelHubTabs, tab: tab, note: rec, party: slots, partyNote: six.count >= 3 ? "대전 파티 · \(six.count)마리" : "대전 파티를 정해 주세요 (3~6마리)",
                             friends: [], recs: [], first: 0, count: 0, sel: sel, go: nil, hint: "", empty: "")
        if tab == 0 {
            m.friends = duelFriends.prefix(3).map { .init(name: $0.name, sub: "오늘 \($0.today.formatted())걸음 · 대전 \($0.duelWins)승 \($0.duelLosses)패", pill: "신청") }
            m.empty = cloud?.team == nil ? "불러오는 중…" : "지금 걷는 친구가 없어요"
            if six.count >= 3 { m.go = "랜덤 매칭" } else { m.hint = "대전 파티를 먼저 정해 주세요" }
        } else {
            let all = cloud?.duelRecord?.recent ?? [], per = DuelHubModel.perPage, first = min(sel, max(0, all.count - 1)) / per * per
            m.recs = all.dropFirst(first).prefix(per).map { r in
                let why = r.why == "timeout" ? (r.won ? "상대의 시간 초과" : "시간 초과") : r.why == "forfeit" ? (r.won ? "상대의 기권" : "기권") : ""
                return .init(won: r.won, line: "vs " + r.opponent, sub: (why.isEmpty ? "" : why + " · ") + ago(max(60, Int(now.timeIntervalSince1970) - r.at)), mine: r.mine, theirs: r.theirs)
            }
            m.first = first; m.count = all.count
            m.empty = cloud?.duelRecord == nil ? "불러오는 중…" : "아직 대전 기록이 없어요"
        }
        return PaneContent(duelHub: m)
    }
    func duelHubLCD(_ fb: inout FB, _ tab: Int, _ sel: Int, _ now: Date) {
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        fb.text(tab == 0 ? "대전" : "전적", 2, 0); fb.text("\(state.duelWins ?? 0)승 \(state.duelLosses ?? 0)패", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
        if tab == 1 {
            guard let r = cloud?.duelRecord?.recent[safe: sel] else { fb.text(cloud?.duelRecord == nil ? "불러오는 중..." : "기록이 없다", 0, 30, 2, center: true); return }
            fb.text((r.won ? "승 " : "패 ") + r.opponent, 2, 15, 3, small: true)
            for (k, d) in r.mine.prefix(3).enumerated() { fb.text(monNames[d], 2, 26 + 9 * k, 2, small: true) }
            for (k, d) in r.theirs.prefix(3).enumerated() { fb.text(monNames[d], 94, 26 + 9 * k, 2, right: true, small: true) }
            return
        }
        let six = duelSix
        if let f = six.first { fb.mon(f, half, 0, 2, anim: animT("hub", f.dex, now)) } else { fb.mon(state.companion, half, 0, 2, anim: animT("hub", state.companion.dex, now)) }
        let friends = duelFriends.prefix(3).map(\.name), stop = min(sel, duelHubStops - 1)
        let label = stop == 0 ? (six.count >= 3 ? "랜덤 매칭" : "파티 정하기") : stop <= friends.count ? friends[stop - 1] + "에게" : stop == friends.count + 1 ? "대전 파티" : "전적 보기"
        fb.text(six.count >= 3 ? "파티 \(six.count)마리" : "파티 없음", 94, 15, 2, right: true, small: true)
        if stop >= 1, stop <= friends.count { fb.text("대전 신청", 94, 37, 2, right: true, small: true) }
        fb.text("● " + label, 94, 52, 3, right: true, small: true)
    }
    func duelHubPress(_ k: Int, _ tab: Int, _ sel: Int, _ now: Date) {
        if tab == 1 {
            let n = cloud?.duelRecord?.recent.count ?? 0
            if k == 1 || n == 0 { screen = .duel(.hub(tab: 0, sel: 0)); return }
            screen = .duel(.hub(tab: 1, sel: ((sel + (k == 0 ? -1 : 1)) % n + n) % n)); return
        }
        let n = duelHubStops
        if k != 1 { screen = .duel(.hub(tab: 0, sel: ((min(sel, n - 1) + (k == 0 ? -1 : 1)) % n + n) % n)); return }
        let friends = duelFriends.prefix(3).map(\.name), stop = min(sel, n - 1)
        if stop == 0 { duelQueue(now) } else if stop <= friends.count { challenge(friends[stop - 1], now) }
        else if stop == friends.count + 1 { duelPartyPick() } else { cloud?.duelRecordDue = true; screen = .duel(.hub(tab: 1, sel: 0)) }
    }
    func duelHubTap(_ code: Int, _ tab: Int, _ sel: Int, _ now: Date) {
        switch code {
        case 6320...6321: if code - 6320 == 1 { cloud?.duelRecordDue = true }; screen = .duel(.hub(tab: code - 6320, sel: 0))
        case 6330: duelPartyPick()
        case 6331: duelQueue(now)
        case 6340...6342: if let f = Array(duelFriends.prefix(3))[safe: code - 6340] { challenge(f.name, now) }
        case 6350...6351:
            let per = DuelHubModel.perPage, n = cloud?.duelRecord?.recent.count ?? 0, pages = max(1, (n + per - 1) / per)
            screen = .duel(.hub(tab: 1, sel: min(max(0, n - 1), ((min(sel, max(0, n - 1)) / per + (code == 6350 ? pages - 1 : 1)) % pages) * per)))
        default: return
        }
    }
    /// 랜덤 매칭 (14 §5.2): into the queue (another waiting: matched at once — the pick); a minute at most.
    func duelQueue(_ now: Date) {
        guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: screen, since: now); return }
        guard duelSix.count >= 3 else { screen = .say(["대전 파티를", "먼저 정해 주세요"], next: .squad(Squad(kind: .duelParty, picked: [], at: 0)), since: now); return }
        act(.duelQueue, back: screen, now) { [weak self] o, now in
            guard let self, let v = o.duel else { return nil }
            duelStart(v); return duelScreen(now)
        }
    }
    func duelQueueCancel(_ now: Date) {
        act(.duelQueueCancel, back: screen, now) { [weak self] _, now in self?.duelStop(); return .say(["랜덤 매칭을", "그만뒀다"], next: .duel(.hub(tab: 0, sel: 0)), since: now) }
    }

    // MARK: the invitation's page
    func duelPane(_ s: DuelStep, _ now: Date) -> PaneContent {
        let left = duelLeft(now).map { "\($0)초 남음" } ?? ""
        let rec = "내 기록 \(state.duelWins ?? 0)승 \(state.duelLosses ?? 0)패"
        switch s {
        case .hub(let tab, let sel): return duelHubPane(tab, sel, now)
        case .queued:
            return PaneContent(duel: DuelModel(title: "랜덤 매칭", line: "대전 상대를 찾는 중…", note: left, buttons: ["그만두기"], record: rec))
        case .invite(_, let from):
            return PaneContent(duel: DuelModel(title: josa(from, "의", "의") + " 대전 신청", line: "Lv.50 · 대전 파티에서 3마리 · 이기면 +3BP", note: left, buttons: ["수락", "거절"], record: rec))
        case .waitAccept(_, let to):
            return PaneContent(duel: DuelModel(title: to + "에게 대전 신청", line: "상대의 수락을 기다리는 중…", note: left, buttons: ["신청 취소"], record: rec))
        }
    }
    func duelLCD(_ fb: inout FB, _ s: DuelStep, _ now: Date) {
        if case .hub(let tab, let sel) = s { duelHubLCD(&fb, tab, sel, now); return }
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2, dots = String(repeating: ".", count: Int(now.timeIntervalSinceReferenceDate * 2) % 4)
        fb.text(s == .queued ? "랜덤 매칭" : "실시간 대전", 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(duelSix.first ?? state.companion, half, 0, 2, anim: animT("duel", (duelSix.first ?? state.companion).dex, now))
        let who: String = { switch s { case .invite(_, let f): f; case .waitAccept(_, let t): t; default: "" } }()
        if !who.isEmpty { fb.text("vs", 94, 15, 2, right: true, small: true); fb.text(who, 94, 26, 3, right: true, small: true) }
        if let l = duelLeft(now) { fb.text("\(l)초", 94, 37, 2, right: true, small: true) }
        switch s {
        case .invite: fb.text("● 수락", 94, 52, 2, right: true, small: true)
        case .waitAccept: fb.text("기다리는 중" + dots, 94, 52, 2, right: true, small: true)
        case .queued: fb.text("찾는 중" + dots, 94, 15, 2, right: true, small: true); fb.text("● 그만두기", 94, 52, 2, right: true, small: true)
        case .hub: break
        }
    }
    func duelPress(_ k: Int, _ s: DuelStep, _ now: Date) {
        if case .hub(let tab, let sel) = s { duelHubPress(k, tab, sel, now); return }
        guard k == 1 else { return }
        switch s { case .invite: duelAnswer("수락", now); case .waitAccept: duelAnswer("신청 취소", now); case .queued: duelQueueCancel(now); case .hub: break }
    }
    func duelTap(_ code: Int, _ now: Date) {
        guard case .duel(let s) = screen else { return }
        switch (s, code) {
        case (.hub(let tab, let sel), _): duelHubTap(code, tab, sel, now)
        case (.invite, 6300): duelAnswer("수락", now)
        case (.invite, 6301): duelAnswer("거절", now)
        case (.waitAccept, 6300): duelAnswer("신청 취소", now)
        case (.queued, 6300): duelQueueCancel(now)
        default: return
        }
    }
}
