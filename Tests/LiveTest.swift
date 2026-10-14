import Foundation
// `PokeWalker --live-test <id> <pin>` (a dev build only: main.swift): 3.0's walker against the real save server (docs/plans/11), headless and
// in real time, the ID and PIN boxes answered by a TestHost. A new zz test ID (never a real trainer: a 3.0 act turns its 2.x away): its first
// act brings the server's save with the starter; steps at a person's rate for W; the server's radar to a catch (balls until it's in) and, if
// the chain holds, its next bush asked for and given up; a wrong bush; a shop buy; the box's acts. Everything in a temp folder.

@MainActor func liveTest(_ id: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-live-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
    let c = Cloud(link: HTTPLink(), dir: tmp)
    w.startCloud(c, file: tmp.appendingPathComponent("state.json"), bak: tmp.appendingPathComponent("state.json.bak"))   // (never the real save's 08 §5 move)
    h.texts = [id]; h.pins = [pin, pin, pin]
    /// Ticks in real time until done (or the time's up); true = done.
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { w.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func idle() -> Bool { w.waiting == nil && c.inFlight == nil && c.queued == nil && c.out == nil }
    func says() -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    /// Home, with the news played: shows waited out, messages closed, a move to learn passed on.
    func toHome(_ secs: Double = 40) {
        let end = Date().addingTimeInterval(secs)
        while Date() < end {
            switch w.screen {
            case .home where w.news.isEmpty && idle() && w.chainNext == nil: return
            case .learn: w.screen = .learn(sel: 4); w.press(1)
            case .say: if w.waiting == nil { w.press(1) }
            case .home, .evolve, .hatch, .beats, .radar: break
            default: w.screen = .home
            }
            w.tick(Date()); Thread.sleep(forTimeInterval: 0.1)
        }
    }

    check(run(30) { c.phase == .on && c.base != nil }, "live: \(id) logged in (\(h.asked.contains("새 트레이너") ? "a new trainer, its PIN set" : "its PIN")), the server's save in — \(HTTPLink.base.host ?? "")")
    guard c.phase == .on, c.base != nil else { print("FAIL \(failed) — not logged in (phase \(c.phase))"); return false }
    if h.asked.contains("새 트레이너") { check(w.state.companion.uid == 1_000_000, "live: the new trainer's companion is the server's starter (uid 1,000,000)") }
    toHome()

    let need = 45                                                                                // W for the radars and a buy: ~900 steps at a person's rate
    if w.state.watts < need {
        let t0 = Date(); var k: UInt32 = 0
        run(150) { k += 1; h.keys &+= [2, 1, 1, 2, 0, 1, 2][Int(k) % 7]; return w.state.watts >= need && c.ahead == 0 }   // ~13 a second, uneven (the server: 15 a second)
        run(20) { c.ahead == 0 && idle() }
        check(c.base.map { $0.watts >= need } == true && w.state.watts == c.base?.watts, "live: steps up to the server → \(c.base?.watts ?? 0) W in \(Int(Date().timeIntervalSince(t0))) s (the server's total \(c.base?.total ?? 0))")
    }

    /// From home: the radar (the server's bush), then ● on it (hit) or on the next one; true = a fight began.
    func radar(hit: Bool) -> Bool {
        toHome(); w.openFeature("포켓 레이더")
        guard run(20, until: { if case .radar = w.screen { return true }; return false }), case .radar(let b, _, let since, let chain) = w.screen else { return false }
        w.screen = .radar(bush: b, cursor: hit ? b : (b + 1) % 4, since: since, chain: chain)
        while Date().timeIntervalSince(since) < 1.6 { Thread.sleep(forTimeInterval: 0.05) }   // inside the bush's window (no tick meanwhile: its timeout)
        w.press(1)
        return run(20) { if case .beats = w.screen { return true }; return idle() && !w.inBattle }
            && w.inBattle
    }
    /// The fight's menu, then the beats played out; the server's end, if it came.
    var lastEnd: String? = nil
    func pick(_ what: String) {
        run(30) { if case .battle = w.screen { return true }; return !w.inBattle && idle() }
        guard case .battle(let b, _) = w.screen, let i = w.battleMenu(b).firstIndex(of: what) else { return }
        w.screen = .battle(b, sel: i); w.press(1)
        run(40) { if let e = w.fightEnd { lastEnd = e.result }; if case .beats = w.screen { return false }; return idle() }
    }

    var w0 = w.state.watts
    if radar(hit: true), case .beats(let f, _, _, _) = w.screen {
        let uid = f.wild.uid ?? 0
        check(uid > 1_000_000 && w.state.watts == w0 - 10, "live radar: the server's \(monNames[f.wild.dex]) Lv.\(f.wild.level) uid \(uid); 10 W")
        var balls = 0
        while w.inBattle, balls < 12 { pick("볼"); balls += 1 }
        let caught = w.state.box.contains { $0.uid == uid }
        check(!w.inBattle && (caught ? lastEnd == "caught" : lastEnd != nil), "live fight: \(balls) ball\(balls == 1 ? "" : "s") (\(w.usedItem)) — " + (caught ? "caught, uid \(uid) in the box" : "it ended \(lastEnd ?? "?") (the dice), as the server said"))
        var chainUp = false                                                                       // home's news, then the chain's bush (if it held) — not pressed through
        run(40) {
            switch w.screen {
            case .radar: chainUp = true; return true
            case .say: if w.waiting == nil { w.press(1) }; return false
            case .home: return w.news.isEmpty && idle() && w.chainNext == nil
            case .evolve, .hatch, .beats: return false
            default: w.screen = .home; return false
            }
        }
        if chainUp, case .radar(let b, _, _, let ch) = w.screen {                                  // the chain held: its bush came after home's news (free)
            check(ch == 1 && w.state.watts == w0 - 10 + 2, "live chain: held — its bush asked for once home was done, free; +2 W (\(w.state.watts) W)")
            w.screen = .radar(bush: b, cursor: (b + 1) % 4, since: .distantPast, chain: ch); w.press(1); run(10, until: idle)
            check(!w.inBattle && idle() && { if case .radar = w.screen { return false }; return true }(), "live chain: a wrong bush gives it up")
        } else { check(true, "live chain: the server ended it (no bonus)") }
    } else { check(false, "live radar: no fight began") }
    toHome(); w0 = w.state.watts
    let missed = radar(hit: false); run(10, until: idle)
    check(!missed && w.state.watts == w0 - 10 && !w.inBattle, "live radar: a wrong bush → missed; its 10 W spent")

    toHome(); w0 = w.state.watts
    if let k = w.wares(false).firstIndex(where: { if case .item("상처약") = $0.kind { return true }; return false }), w.state.canBuy(w.wares(false)[k], bp: false) >= 1 {
        let n0 = w.state.count("상처약"); w.screen = .shop(bp: false, sel: k, qty: 1); w.press(1); run(10, until: idle)
        check(w.state.count("상처약") == n0 + 1 && w.state.watts == w0 - w.wares(false)[k].price, "live shop: 상처약 bought (\(w.wares(false)[k].price) W)")
    } else { print("skip live shop: \(w.state.watts) W") }

    toHome()
    if let i = w.state.box.indices.last, let u = w.state.box[i].uid {
        w.screen = .box(i, act: 1, confirm: false, detail: true); w.press(1); run(10, until: idle)  // 워커로
        let onWalker = w.state.caught.contains { $0.uid == u }
        w.screen = .home; _ = w.touch(2, 50); run(10, until: idle)                                // its sticker: walk with it
        check(onWalker && w.state.companion.uid == u, "live box: 워커로, then its sticker → it walks with us (the server's)")
        w.screen = .box(-1, act: nil, confirm: false); w.screen = .box(w.state.box.indices.last ?? 0, act: nil, confirm: false)
    }
    w.screen = .home; c.saveNow(); run(10, until: idle); c.flush()
    print("walk: \(monNames[w.state.companion.dex]) #\(w.state.companion.uid ?? 0) · box: " + w.state.box.map { "\(monNames[$0.dex]) #\($0.uid ?? 0)" }.joined(separator: ", ") + " · \(w.state.watts) W · rev \(c.rev)")
    print(failed == 0 ? "PASS live" : "FAIL \(failed)")
    return failed == 0
}

/// `PokeWalker --live-team <idA> <idB> <pin>` (a dev build only): docs/plans/12's M1 against the real server with two new zz test IDs — each
/// sees the other on the team (test IDs see test IDs). (3.8.1: no 인사.)
@MainActor func liveTeamTest(_ a: String, _ b: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-liveteam-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    func walker(_ id: String) -> (Walker, Cloud, TestHost) {
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
        let c = Cloud(link: HTTPLink(), dir: tmp.appendingPathComponent(id, isDirectory: true))
        h.texts = [id]; h.pins = [pin, pin, pin]                                                   // (before startCloud: it may ask at once)
        w.startCloud(c, file: tmp.appendingPathComponent(id + ".json"), bak: tmp.appendingPathComponent(id + ".bak"))
        return (w, c, h)
    }
    let (wa, ca, ha) = walker(a), (wb, cb, hb) = walker(b)
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { wa.tick(Date()); wb.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func idle(_ c: Cloud) -> Bool { c.inFlight == nil && c.queued == nil && c.out == nil }
    check(run(40) { ca.phase == .on && cb.phase == .on && ca.base != nil && cb.base != nil }, "live team: \(a) and \(b) made, each with the server's save (\(ca.phase), \(cb.phase); asked \(ha.asked.suffix(2)), \(hb.asked.suffix(2)))")
    run(11) { false }                                                                            // the server reuses a team list for 10 s
    ca.teamDue = true; cb.teamDue = true; run(20) { idle(ca) && idle(cb) && ca.team != nil && cb.team != nil && !ca.teamDue && !cb.teamDue }
    let seesB = ca.team?.cards.contains { $0.name.lowercased() == b.lowercased() } == true, seesA = cb.team?.cards.contains { $0.name.lowercased() == a.lowercased() } == true
    check(seesB && seesA && ca.team?.week.isEmpty == false, "live team: each sees the other (\(ca.team?.cards.count ?? 0) on A's list, week \(ca.team?.week ?? "-"))")
    let bCard = ca.team?.cards.first { $0.name.lowercased() == b.lowercased() }
    check(bCard.map { Walker.walkingNow($0) && $0.companion.uid == 1_000_000 } == true, "live team: B walking now (idle \(bCard?.idle ?? -1) s), its starter as its companion")
    print(failed == 0 ? "PASS live team" : "FAIL \(failed)")
    return failed == 0
}

/// `PokeWalker --live-trade <idA> <idB> <pin>` (a dev build only): docs/plans/12's M2 against the real server, through the walker's own pages.
/// Two zz test IDs whose boxes the server's admin seeded: A has 윤겔라 and 꼬렛, B has 롱스톤 with 금속코트 in its bag. A asks for 롱스톤 with 윤겔라;
/// B takes it (both evolve by trade at their new trainers: 후딘 at B, 강철톤 at A, 금속코트 gone from B); then 꼬렛 for 아무거나, turned down;
/// again, taken back.
@MainActor func liveTradeTest(_ a: String, _ b: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-livetrade-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    func walker(_ id: String) -> (Walker, Cloud, TestHost) {                                        // (the host comes back: the walker holds it weakly)
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
        let c = Cloud(link: HTTPLink(), dir: tmp.appendingPathComponent(id, isDirectory: true))
        h.texts = [id]; h.pins = [pin, pin, pin]                                                   // (before startCloud: it may ask at once)
        w.startCloud(c, file: tmp.appendingPathComponent(id + ".json"), bak: tmp.appendingPathComponent(id + ".bak"))
        return (w, c, h)
    }
    let (wa, ca, ha) = walker(a), (wb, cb, hb) = walker(b)
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { wa.tick(Date()); wb.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func idle(_ c: Cloud) -> Bool { c.inFlight == nil && c.queued == nil && c.out == nil }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func next(_ w: Walker, _ c: Cloud, until: () -> Bool) -> Bool { w.screen = .home; c.addSteps(2); c.saveNow(); return run(25, until: until) }   // its next act: what came for it
    check(run(40) { ca.phase == .on && cb.phase == .on && ca.base != nil && cb.base != nil }, "live trade: \(a) and \(b) logged in (\(ca.phase), \(cb.phase); asked \(ha.asked), \(hb.asked))")
    let seeded = wa.state.box.contains { $0.dex == 64 } && wa.state.box.contains { $0.dex == 19 } && wb.state.box.contains { $0.dex == 95 } && wb.state.count("금속코트") > 0
    check(seeded, "live trade: the boxes as seeded (A: 윤겔라 · 꼬렛, B: 롱스톤 + 금속코트) — A \(wa.state.box.map(\.dex)), B \(wb.state.box.map(\.dex)) \(wb.state.bag)")
    guard seeded else { print("FAIL \(failed)"); return false }

    // A: 롱스톤 for 윤겔라, from B's card (B's box from /v2/box)
    wa.startTrade(b); run(15) { wa.theirBox(b) != nil && idle(ca) }
    guard case .trade(.pick(var p)) = wa.screen, let onix = wa.theirBox(b)?.firstIndex(where: { $0.dex == 95 }) else { check(false, "live trade: B's box came"); print("FAIL \(failed)"); return false }
    p.at = onix; wa.screen = .trade(.pick(p)); wa.pageTap(6150 + onix % TradePickModel.perPage)
    if case .trade(.pick(let q)) = wa.screen, let k = wa.myTradeBox.firstIndex(where: { $0.dex == 64 }) { var q = q; q.at = k; wa.screen = .trade(.pick(q)); wa.pageTap(6150 + k % TradePickModel.perPage) }
    let go = wa.paneContent(Date()).pick?.go; wa.pageTap(6190); run(15) { wa.waiting == nil && idle(ca) }
    check(go == "교환 신청" && says(wa) == [b + "에게", "교환을 신청했다!"], "live 교환 신청: B's 롱스톤 for my 윤겔라 — the server took it (\(String(describing: go)), \(says(wa)))")
    run(15) { ca.trades?.outgoing.count == 1 }
    let id = ca.trades?.outgoing.first?.id ?? -1
    check(ca.trades?.outgoing.first.map { $0.mon.dex == 64 && $0.want?.dex == 95 } == true, "live /v2/trades: my offer on my list (id \(id))")

    // B: the news, its page, 수락 → both evolve at their new trainers
    let came = next(wb, cb) { if case .say(_, .trade(.offer(id, nil)), _) = wb.screen { return true }; return false }
    check(came && says(wb).first == josa(a, "이", "가") + " 교환을 신청했다!", "live tradeOffer news: B's next act brings it — \(says(wb))")
    wb.press(1); let page = wb.paneContent(Date()).offer
    check(page?.give.dex == 95 && page?.get.dex == 64 && page?.buttons == ["수락", "거절"], "live: the offer's page (롱스톤 ⇄ 윤겔라, 수락 · 거절)")
    wb.pageTap(6130); run(20) { wb.waiting == nil && idle(cb) && { if case .traded = wb.screen { return true }; return false }() }
    let show: Bool = { if case .traded(let g, let got, _, _) = wb.screen { return g.dex == 95 && got.dex == 64 }; return false }()
    run(10) { if case .evolve = wb.screen { return true }; return false }
    let alakazam = wb.state.box.first { $0.dex == 65 }
    check(show && alakazam?.ot.map { trainerID($0)?.key == trainerID(a)?.key } == true && wb.state.count("금속코트") == 0 && !wb.state.box.contains { $0.dex == 95 },
          "live 수락: the trade's show; 윤겔라 → 후딘 at B (어버이 \(alakazam?.ot ?? "-")), 금속코트 went with 롱스톤 — B \(wb.state.box.map(\.dex))")
    let got = next(wa, ca) { wa.state.box.contains { $0.dex == 208 } }
    let steelix = wa.state.box.first { $0.dex == 208 }
    check(got && steelix?.ot.map { trainerID($0)?.key == trainerID(b)?.key } == true && !wa.state.box.contains { $0.dex == 64 },
          "live: A's next act brings its new save — 롱스톤 → 강철톤 at A (어버이 \(steelix?.ot ?? "-")) — A \(wa.state.box.map(\.dex))")

    // 꼬렛 for 아무거나: B turns it down; again, A takes it back
    run(8) { false }; wb.screen = .home; wa.screen = .home
    let rattata = wa.state.box.first { $0.dex == 19 }?.uid ?? -1
    wa.act(.tradeOffer(to: b, give: rattata, want: nil), back: .home); run(15) { wa.waiting == nil && idle(ca) }
    _ = next(wb, cb) { if case .say(_, .trade(.offer), _) = wb.screen { return true }; return false }
    if case .say(_, .trade(.offer(let id2, _)), _) = wb.screen { wb.screen = .trade(.offer(id: id2, act: nil)); wb.pageTap(6131); run(15) { wb.waiting == nil && idle(cb) } }
    let declined = says(wb).last == "거절했다"
    let heard = next(wa, ca) { ca.trades?.outgoing.isEmpty == true && idle(ca) } && says(wa).isEmpty
    check(declined && heard, "live 거절 (a 아무거나 one): said at B; A's next act brings it quietly (3.8: off its list, no screen)")
    wa.act(.tradeOffer(to: b, give: rattata, want: nil), back: .home); run(15) { wa.waiting == nil && idle(ca) }
    ca.tradesDue = true; run(10) { ca.trades?.outgoing.count == 1 && idle(ca) }
    wa.screen = .trade(.list(0)); wa.pageTap(6110 + max(0, wa.tradeRows.firstIndex { wa.mineOffer($0) } ?? 0)); wa.pageTap(6132); run(15) { wa.waiting == nil && idle(ca) }
    let took = says(wa) == ["교환 신청을", "거뒀다"]
    let told = next(wb, cb) { cb.trades?.incoming.isEmpty == true && idle(cb) } && says(wb).isEmpty
    check(took && told, "live 거두기: said at A; B's next act brings it quietly (\(says(wb)))")
    print(failed == 0 ? "PASS live trade" : "FAIL \(failed)")
    return failed == 0
}

/// `PokeWalker --live-raid <idA> <idB> <pin>` (a dev build only): docs/plans/16's raid runs (4.0) against the real server (test IDs: runs always
/// on, their own "-test" week). Two zz IDs, friends, the server's admin seeded: A with power and a strong party, B with power. A: 도전 → ★1 →
/// its three strongest → won (10 bars; BP; 5 balls; the week's first win mailed) → throws until caught or out; then a second run retreated, its
/// ball stage cut off here (the app closed) — the lobby goes back to it, 홈 gives it up (asked). B: one alone, 후퇴 at once (3 balls), 그만두기
/// (asked) → 놓침. Then each other's weeks: the lobby's 친구 이번 주, the friends' 레이드 tab.
@MainActor func liveRaidTest(_ a: String, _ b: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-liveraid-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    func walker(_ id: String) -> (Walker, Cloud, TestHost) {                                        // (the host comes back: the walker holds it weakly)
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
        let c = Cloud(link: HTTPLink(), dir: tmp.appendingPathComponent(id, isDirectory: true))
        h.texts = [id]; h.pins = [pin, pin, pin]
        w.startCloud(c, file: tmp.appendingPathComponent(id + ".json"), bak: tmp.appendingPathComponent(id + ".bak"))
        return (w, c, h)
    }
    let (wa, ca, ha) = walker(a), (wb, cb, hb) = walker(b)
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { wa.tick(Date()); wb.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func idle(_ c: Cloud) -> Bool { c.inFlight == nil && c.queued == nil && c.out == nil }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func step(_ w: Walker) -> RaidStep? { if case .raid(let s) = w.screen { return s }; if case .say(_, .raid(let s), _) = w.screen { return s }; return nil }
    func lobby(_ w: Walker, _ c: Cloud) { w.openFeature("레이드"); c.raidDue = true; run(15) { !c.raidDue && idle(c) && w.waiting == nil } }
    /// A fight played out in real time: beats wait out their length; 공격 with a move that has PP (or 후퇴); a message goes on; stops at its end's lines.
    func play(_ w: Walker, _ c: Cloud, retreat: Bool = false, secs: Double = 240) {
        let end = Date().addingTimeInterval(secs)
        while Date() < end {
            run(0.3) { false }
            guard w.waiting == nil, idle(c) else { continue }
            switch w.screen {
            case .beats: continue
            case .battle(let bt, _): w.screen = .battle(bt, sel: retreat ? w.battleMenu(bt).count - 1 : 0); w.press(1)
            case .moves(let bt, _): w.screen = .moves(bt, sel: bt.mine[bt.me].pp.firstIndex { $0 > 0 } ?? 0); w.press(1)
            case .party(let bt, _): w.screen = .party(bt, sel: bt.mine.indices.first { bt.mine[$0].alive } ?? 0); w.press(1)
            case .learn: w.screen = .learn(sel: 4); w.press(1)
            default: return
            }
        }
    }
    /// The lobby (fresh: left alone it goes home after 20 s), 도전 → ★1 → who goes (the strongest `n`), in.
    func start(_ w: Walker, _ c: Cloud, strongest n: Int) {
        lobby(w, c); w.calmAt = .distantPast; w.pageTap(7010); w.pageTap(7020); w.pageTap(7020)
        if case .squad(var q) = w.screen {
            q.picked = Array(w.squadKeys(q).sorted { (w.squadMon(q, $0)?.level ?? 0) > (w.squadMon(q, $1)?.level ?? 0) }.prefix(n)); w.screen = .squad(q)
        }
        w.pageTap(8790); run(15) { w.waiting == nil && idle(c) }
    }
    check(run(40) { ca.phase == .on && cb.phase == .on && ca.base != nil && cb.base != nil }, "live raid: \(a) and \(b) logged in (\(ca.phase), \(cb.phase); asked \(ha.asked), \(hb.asked))")
    lobby(wa, ca); lobby(wb, cb)
    let open = ca.raid.map { $0.opens == nil && $0.today.max == RaidRules.perDay } ?? false
    check(open && wa.raidCells >= 2 && wb.raidCells >= 1, "live /v2/raid (4.0): \(ca.raid?.week ?? "-") \(ca.raid.map { monNames[$0.boss.dex] } ?? "-"), today \(ca.raid?.today.used ?? -1)/\(ca.raid?.today.max ?? -1); power A \(wa.raidPower), B \(wb.raidPower)")
    guard open else { print("FAIL \(failed)"); return false }

    // A: ★1, won
    let bp0 = wa.state.bp ?? 0, mails0 = ca.mail?.mails.count ?? 0
    start(wa, ca, strongest: 3)
    let bars = wa.fight?.theirs.count ?? 0, tier = wa.fight?.raidTier, shiny = wa.fight?.wild.shiny == true
    play(wa, ca)
    let won = says(wa)
    check(bars == RaidRules.bars && tier == 1 && won.first == "\(RaidRules.bars)줄을 모두 깼다!" && won.dropFirst().first?.hasSuffix("볼 \(RaidRules.balls + RaidRules.winBalls)개!") == true && (wa.state.bp ?? 0) > bp0,
          "live run ★1 (\(shiny ? "이로치!" : "보통")): 10 bars, won — \(won), BP \(bp0) → \(wa.state.bp ?? 0)")
    wa.press(1); run(3) { false }
    check(step(wa) == .balls && wa.raidStage?.balls == RaidRules.balls + RaidRules.winBalls, "live: its ball stage (\(wa.raidStage?.balls ?? -1) balls)")
    var tossed = 0, caught = false
    while tossed < 6, !caught, step(wa) == .balls {
        wa.calmAt = .distantPast; wa.pageTap(7040); run(15) { wa.waiting == nil && idle(ca) }
        guard case .beats = wa.screen else { break }
        tossed += 1; run(10) { if case .beats = wa.screen { return false }; return true }
        caught = says(wa).first?.hasSuffix("잡았다!") == true
        print("     throw \(tossed): \(says(wa))")
        wa.press(1); run(2) { false }
    }
    let over = wa.raidStage == nil && step(wa) != .balls                                         // (the lobby, or home first: a level's news)
    ca.raidDue = true; ca.mailDue = true; run(15) { idle(ca) && !ca.raidDue }
    let rec = ca.raid?.runs.first
    check(tossed > 0 && over && rec?.won == true && rec?.tier == 1 && rec?.caught == caught && (ca.mail?.mails.count ?? 0) >= mails0,
          "live raidBall: \(tossed) throw(s), \(caught ? "caught (\(wa.state.box.last.map { monNames[$0.dex] + " Lv.\($0.level)" } ?? "-"))" : "out of balls"); the lobby's 내 판 has it (\(String(describing: rec)))")

    // A: a second run, retreated; its ball stage cut off (the app closed) — the lobby goes back to it; 홈 gives it up
    start(wa, ca, strongest: 1); play(wa, ca, retreat: true); wa.press(1); run(2) { false }
    let held = step(wa) == .balls && wa.raidStage?.balls == RaidRules.balls
    wa.raidStage = nil; wa.screen = .home
    lobby(wa, ca); run(5) { step(wa) == .balls || says(wa).first == "잡을 기회가" }
    let back = says(wa); wa.press(1)
    ha.answer = true; wa.press(4); run(15) { wa.waiting == nil && idle(ca) }
    ca.raidDue = true; run(15) { idle(ca) && !ca.raidDue }
    check(held && back == ["잡을 기회가", "남았어요!"] && ha.asked.last == "그만둘까요?" && ca.raid?.pending == nil && ca.raid?.runs.first?.caught == false,
          "live cut off: the stage waits on the server; the lobby goes back to it (\(back)); 홈 → 그만둘까요? → raidQuit (pending \(ca.raid?.pending == nil ? "gone" : "still there"))")

    // B: alone, 후퇴 at once — 3 balls; 그만두기 (asked)
    start(wb, cb, strongest: 1); play(wb, cb, retreat: true)
    let lost = says(wb); wb.press(1); run(2) { false }
    let three = wb.raidStage?.balls
    hb.answer = true; wb.pageTap(7041); run(15) { wb.waiting == nil && idle(cb) }
    cb.raidDue = true; run(15) { idle(cb) && !cb.raidDue }
    check(lost == ["줄을 깨지 못했다", "볼 \(RaidRules.balls)개"] && three == RaidRules.balls && hb.asked.last == "그만둘까요?" && step(wb) == .lobby(tab: 1) && cb.raid?.runs.first?.caught == false,
          "live B: 후퇴 at once → \(lost), \(three ?? -1) balls; 그만두기 (asked) → the lobby, 놓침")

    // each other's weeks
    let mates = cb.raid?.friends ?? []
    let aWeek = mates.first { trainerID($0.name)?.key == trainerID(a)?.key }
    wb.openFeature("친구"); cb.teamDue = true; run(15) { idle(cb) && cb.team != nil && !cb.teamDue }
    let card = cb.team?.cards.first { trainerID($0.name)?.key == trainerID(a)?.key }?.raid
    check(aWeek?.runs ?? 0 >= 2 && (aWeek?.wins ?? 0) >= 1 && card?.wins == aWeek?.wins, "live friends: B sees A's week in the lobby (\(String(describing: aWeek))) and on A's card (\(String(describing: card)))")
    print(failed == 0 ? "PASS live raid" : "FAIL \(failed)")
    return failed == 0
}

/// `PokeWalker --live-social <idA> <idB> <pin>` (a dev build only): docs/plans/12 §2.4 and §3.3 against the real server, through the walker's own
/// pages. Two zz IDs the admin seeded (A's box: 고우스트 and 꼬렛, 윤겔라 seen; B's: 윤겔라 and 잉어킹). A asks B by ID, B accepts on its 신청 tab,
/// each lists the other; A puts 고우스트 up wishing for 윤겔라, B offers 윤겔라 from the post's page, A picks it (both evolve by trade
/// at their new trainers); B puts 잉어킹 up, A offers 꼬렛 and takes it back, B hears it and takes its post down; A unfriends B.
@MainActor func liveSocialTest(_ a: String, _ b: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-livesocial-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    func walker(_ id: String) -> (Walker, Cloud, TestHost) {                                        // (the host comes back: the walker holds it weakly)
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
        let c = Cloud(link: HTTPLink(), dir: tmp.appendingPathComponent(id, isDirectory: true))
        h.texts = [id]; h.pins = [pin, pin, pin]
        w.startCloud(c, file: tmp.appendingPathComponent(id + ".json"), bak: tmp.appendingPathComponent(id + ".bak"))
        return (w, c, h)
    }
    let (wa, ca, ha) = walker(a), (wb, cb, hb) = walker(b)
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { wa.tick(Date()); wb.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func idle(_ c: Cloud) -> Bool { c.inFlight == nil && c.queued == nil && c.out == nil }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func settle(_ w: Walker, _ c: Cloud) { run(15) { w.waiting == nil && idle(c) } }
    /// Its next act (steps): what came for it, the first of it on the LCD.
    func next(_ w: Walker, _ c: Cloud, until: () -> Bool) -> Bool { w.news = []; w.screen = .home; c.addSteps(2); c.saveNow(); return run(25, until: until) }
    func lists(_ w: Walker, _ c: Cloud) { c.teamDue = true; c.marketDue = true; c.mailDue = true; run(15) { !c.teamDue && !c.marketDue && !c.mailDue && idle(c) }; run(2) { false } }
    check(run(40) { ca.phase == .on && cb.phase == .on && ca.base != nil && cb.base != nil }, "live social: \(a) and \(b) logged in (\(ha.asked), \(hb.asked))")
    let seeded = wa.state.box.count >= 2 && wb.state.box.count >= 2                             // (first run: A 고우스트 · 꼬렛, B 윤겔라 · 잉어킹; a rerun takes what's there)
    check(seeded, "live social: the boxes as seeded — A \(wa.state.box.map(\.dex)), B \(wb.state.box.map(\.dex))")
    guard seeded else { print("FAIL \(failed)"); return false }

    // 친구 (from scratch: a friendship from an earlier run undone first)
    lists(wa, ca); if wa.teamRows(0).count > 1 { wa.screen = .home; wa.act(.friendRemove(name: b), back: .home); settle(wa, ca) }
    wa.openFeature("친구"); settle(wa, ca); wa.pageTap(6000 + TeamTab.requests); ha.texts = [b]; wa.pageTap(6240); settle(wa, ca)
    check(says(wa) == [josa(b, "에게", "에게"), "친구 신청을 했다!"], "live friendRequest: A asks B by ID — \(says(wa))")
    let asked = next(wb, cb) { says(wb).first == josa(a, "이", "가") + " 친구 신청을 했다!" }
    wb.press(1); lists(wb, cb); let row = wb.friendReqRows.first
    wb.screen = .team(sel: 0, tab: TeamTab.requests, card: false); wb.pageTap(6200); settle(wb, cb)
    check(asked && row?.name.lowercased() == a.lowercased() && row?.mine == false, "live: B's next act brings the request; its 신청 tab has it; 수락")
    let added = next(wa, ca) { says(wa).first == josa(b, "과", "와") + " 친구가 되었다!" }
    lists(wa, ca); lists(wb, cb)
    check(added && wa.teamRows(0).count == 2 && wb.teamRows(0).count == 2, "live friendAdded: A hears it; each lists the other (\(wa.teamRows(0).count), \(wb.teamRows(0).count))")

    // the 게시판: A puts 고우스트 up wishing for 윤겔라; B offers 윤겔라; A picks it
    wa.openFeature("교환"); settle(wa, ca); lists(wa, ca); wa.pageTap(8030)
    let giveA = wa.myTradeBox.first { $0.dex == 93 } ?? wa.myTradeBox[0]
    if case .market(.pick(var p)) = wa.screen { p.give = giveA.uid; p.wish = [64]; wa.screen = .market(.pick(p)); wa.pageTap(8190); settle(wa, ca) }
    let posted = says(wa); lists(wa, ca); let post = wa.myPosts.first
    check(posted == ["게시판에", "글을 올렸다!"] && post?.mon.uid == giveA.uid && post?.wish == [64], "live marketList: \(monNames[giveA.dex]) up, wishing 윤겔라 (id \(post?.id ?? -1)) — \(posted)")
    lists(wb, cb); let seen = wb.market?.listings.first { $0.id == post?.id }
    if let id = seen?.id { wb.screen = .market(.post(id: id, sel: nil)); wb.pageTap(8130) }
    let giveB = wb.myTradeBox.first { $0.dex == 64 } ?? wb.myTradeBox[0]
    if case .market(.pick(var p)) = wb.screen { p.give = giveB.uid; wb.screen = .market(.pick(p)); wb.pageTap(8190); settle(wb, cb) }
    check(seen != nil && says(wb).first == "교환을 제안했다!", "live marketBid: B sees the post and offers \(monNames[giveB.dex]) — \(says(wb))")
    let bidHeard = next(wa, ca) { says(wa).first == josa(b, "이", "가") + " 교환을 제안했다!" }
    wa.press(1); lists(wa, ca)
    if let id = post?.id { wa.screen = .market(.post(id: id, sel: 0)); wa.pageTap(8130); run(20) { wa.waiting == nil && idle(ca) && { if case .traded = wa.screen { return true }; return false }() } }
    let show: Bool = { if case .traded(let g, let got, _, _) = wa.screen { return g.dex == giveA.dex && got.dex == giveB.dex }; return false }()
    run(10) { if case .evolve = wa.screen { return true }; return false }
    let fromB = { (w: Walker, n: String) in w.state.box.contains { $0.ot.map { trainerID($0)?.key == trainerID(n)?.key } == true } }
    check(bidHeard && show && fromB(wa, b), "live marketAccept: A hears the offer, picks it — the trade's show; B's comes to A (A \(wa.state.box.map(\.dex)))")
    let gotIt = next(wb, cb) { fromB(wb, a) }
    check(gotIt, "live: B's next act brings its save — A's comes to B (B \(wb.state.box.map(\.dex)))")

    // B puts 잉어킹 up; A offers 꼬렛 and takes it back; B takes the post down
    wb.screen = .home; wb.act(.marketList(give: wb.state.box.first { $0.uid != nil && !wb.marketUsed.contains($0.uid!) }?.uid ?? -1, wish: []), back: .home); settle(wb, cb); lists(wb, cb)
    let p2 = wb.myPosts.first?.id ?? -1; lists(wa, ca)
    wa.screen = .home; wa.act(.marketBid(listing: p2, give: wa.state.box.first { $0.uid != nil && !wa.marketUsed.contains($0.uid!) }?.uid ?? -1), back: .home); settle(wa, ca); lists(wa, ca)
    wa.screen = .market(.post(id: p2, sel: nil)); wa.pageTap(8130); settle(wa, ca)
    let took = says(wa) == ["제안을 거뒀다"]
    _ = next(wb, cb) { says(wb).last == "제안을 거뒀어요" }
    let told = says(wb).last == "제안을 거뒀어요"
    lists(wb, cb); wb.screen = .market(.post(id: p2, sel: nil)); wb.pageTap(8131); settle(wb, cb); let down = says(wb); lists(wb, cb)
    check(took && told && down == ["글을 내렸다"] && wb.myPosts.isEmpty, "live 제안 거두기 (B hears 제안을 거뒀어요) and 글 내리기 — \(took) \(told) \(down)")

    // A unfriends B
    lists(wa, ca); let bi = wa.teamRows(0).firstIndex { !wa.isMe($0.card) } ?? 0
    wa.screen = .team(sel: bi, tab: 0, card: true); wa.pageTap(6031); settle(wa, ca); let cut = says(wa); lists(wa, ca)
    check(cut.last == "끊었다" && wa.teamRows(0).count == 1, "live friendRemove: 친구 끊기 → only me on A's list — \(cut)")
    print(failed == 0 ? "PASS live social" : "FAIL \(failed)")
    return failed == 0
}

/// `PokeWalker --live-duel <idA> <idB> <pin>` (a dev build only): docs/plans/12 §5 against the real server with two new zz test IDs (their starters
/// as Lv.50 copies): friends first (request, accept), A challenges B from its card, B's next act brings the invitation, 수락, then both pick in
/// real time (the polls bring each turn) to the end — the winner's +3 BP and both records; then a declined one.
@MainActor func liveDuelTest(_ a: String, _ b: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-liveduel-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    func walker(_ id: String) -> (Walker, Cloud, TestHost) {                                        // (the host comes back: the walker holds it weakly)
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
        let c = Cloud(link: HTTPLink(), dir: tmp.appendingPathComponent(id, isDirectory: true))
        h.texts = [id]; h.pins = [pin, pin, pin]
        w.startCloud(c, file: tmp.appendingPathComponent(id + ".json"), bak: tmp.appendingPathComponent(id + ".bak"))
        return (w, c, h)
    }
    let (wa, ca, ha) = walker(a), (wb, cb, hb) = walker(b)
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { wa.tick(Date()); wb.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func idle(_ c: Cloud) -> Bool { c.inFlight == nil && c.queued == nil && c.out == nil }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func settle(_ w: Walker, _ c: Cloud) { run(15) { w.waiting == nil && idle(c) } }
    func next(_ w: Walker, _ c: Cloud, until: () -> Bool) -> Bool { w.news = []; w.screen = .home; c.addSteps(2); c.saveNow(); return run(25, until: until) }
    check(run(40) { ca.phase == .on && cb.phase == .on && ca.base != nil && cb.base != nil }, "live duel: \(a) and \(b) logged in (\(ha.asked), \(hb.asked))")
    wa.screen = .home; wa.act(.friendRequest(to: b), back: .home); settle(wa, ca)
    _ = next(wb, cb) { says(wb).first?.hasSuffix("친구 신청을 했다!") == true }
    wb.screen = .home; wb.act(.friendAccept(from: a), back: .home); settle(wb, cb)
    _ = next(wb, cb) { idle(cb) }; ca.teamDue = true; run(15) { ca.team?.cards.count == 2 && idle(ca) }
    let bi = wa.teamRows(0).firstIndex { !wa.isMe($0.card) } ?? 0
    wa.screen = .team(sel: bi, tab: 0, card: true); let card = wa.paneContent(Date()).teamCard
    check(card?.duel == "대전 신청", "live: friends, B walking now — 대전 신청 on its card (\(card?.duel ?? "-"))")
    wa.pageTap(6032); settle(wa, ca)
    let waiting: Bool = { if case .duel(.waitAccept) = wa.screen { return true }; return false }()
    check(waiting && wa.duelOn, "live duelChallenge: the invitation out — A waits (\(wa.screen))")
    let invited = next(wb, cb) { says(wb).first == josa(a, "이", "가") + " 대전을 신청했다!" }
    wb.press(1); run(10) { wb.duel?.deadline != nil }
    check(invited && wb.duel?.deadline != nil, "live duelInvite: B's next act brings it; its poll the minute left (\(wb.duelLeft() ?? -1) s)")
    wb.pageTap(6300); settle(wb, cb)
    let started = run(30) { if case .beats = wa.screen { return true }; if case .battle = wa.screen { return true }; return false }
    check(started, "live duelAccept: the opening plays on both sides (A's through its long poll)")
    var turns = 0, end = Date().addingTimeInterval(240)
    while Date() < end, wa.duelOn || wb.duelOn {
        run(0.3) { false }
        for (w, c) in [(wa, ca), (wb, cb)] where w.waiting == nil && idle(c) {
            switch w.screen {
            case .beats(_, let bs, let since, _) where Date().timeIntervalSince(since) * w.battleSpeed > bs.map(\.length).reduce(0, +): w.tick(Date())
            case .battle(let bt, _) where !w.duelWait:
                w.screen = .battle(bt, sel: 0); w.press(1)
                if case .moves(let x, _) = w.screen { w.screen = .moves(x, sel: x.mine[x.me].pp.firstIndex { $0 > 0 } ?? 0); w.press(1); if w === wa { turns += 1 } }
            case .party(let bt, _): w.screen = .party(bt, sel: bt.mine.indices.first { bt.mine[$0].alive && $0 != bt.me } ?? 0); w.press(1)
            default: break
            }
        }
    }
    let ra = says(wa), rb = says(wb), aWon = ra.first == "이겼다!", bWon = rb.first == "이겼다!"
    check(!wa.duelOn && !wb.duelOn && aWon != bWon && (aWon ? rb : ra).first?.hasSuffix("졌다...") == true, "live duel: \(turns) turns to the end — A \(ra), B \(rb)")
    let winner = aWon ? wa : wb, wc = aWon ? ca : cb, bp0 = winner.state.bp ?? 0
    _ = next(winner, wc) { (winner.state.duelWins ?? 0) == 1 }
    check((winner.state.duelWins ?? 0) == 1 && (winner.state.bp ?? 0) >= bp0, "live: the winner's save — 1승, BP \(winner.state.bp ?? 0)")
    wa.screen = .home; wa.challenge(b); settle(wa, ca)
    _ = next(wb, cb) { says(wb).first?.hasSuffix("대전을 신청했다!") == true }
    wb.press(1); wb.pageTap(6301); settle(wb, cb)
    let declined = says(wb) == ["대전 신청을", "거절했다"]
    let heard = run(30) { says(wa) == ["대전이", "상대가 거절했다"] }
    check(declined && heard, "live duelDecline: B says so; A hears it through its poll — \(says(wa))")
    print(failed == 0 ? "PASS live duel" : "FAIL \(failed)")
    return failed == 0
}

/// `PokeWalker --live-hold <id> <pin>` (a dev build only): docs/plans/13 ⑤ against the real server with one zz ID the admin seeded (a box
/// Pokémon; 구애머리띠 and 먹다남은음식 in the bag): the companion holds one from its page, another is swapped in, it's taken off; the bag's
/// hold-only one goes onto the box one.
@MainActor func liveHoldTest(_ id: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-livehold-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
    let c = Cloud(link: HTTPLink(), dir: tmp); h.texts = [id]; h.pins = [pin, pin, pin]
    w.startCloud(c, file: tmp.appendingPathComponent("state.json"), bak: tmp.appendingPathComponent("state.json.bak"))
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { w.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func settle() { run(15) { w.waiting == nil && c.inFlight == nil && c.queued == nil && c.out == nil } }
    func says() -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    check(run(40) { c.phase == .on && c.base != nil }, "live hold: \(id) logged in (\(h.asked))")
    let seeded = w.state.count("구애머리띠") > 0 && w.state.count("먹다남은음식") > 0 && !w.state.box.isEmpty
    check(seeded, "live hold: seeded — bag \(w.state.bag), box \(w.state.box.map(\.dex))")
    guard seeded else { print("FAIL \(failed)"); return false }
    w.screen = .box(-1, act: nil, confirm: false, detail: true); w.gridTap(4410)
    w.screen = .hold(ref: -1, sel: w.holdRows(-1).firstIndex { $0.name == "구애머리띠" } ?? 0); w.press(1); settle()
    let first = says(); check(w.state.companion.item == "구애머리띠" && w.state.count("구애머리띠") == 0, "live hold: 구애머리띠 on the companion — \(first)")
    w.screen = .hold(ref: -1, sel: w.holdRows(-1).firstIndex { $0.name == "먹다남은음식" } ?? 0); w.press(1); settle()
    check(w.state.companion.item == "먹다남은음식" && w.state.count("구애머리띠") == 1, "live hold: 먹다남은음식 swapped in (구애머리띠 back to the bag)")
    w.screen = .hold(ref: -1, sel: 0); w.press(1); settle()
    check(w.state.companion.item == nil && w.state.count("먹다남은음식") == 1, "live hold: 빼기 — \(says())")
    w.screen = .items(w.state.inventory.firstIndex(of: "구애머리띠") ?? 0); w.press(1)
    if case .itemOn(var p) = w.screen { p.at = w.itemRefs.firstIndex(of: 0) ?? 0; w.screen = .itemOn(p); w.press(1); w.press(1) }; settle()
    check(w.state.box.first?.item == "구애머리띠", "live hold: the bag's hold-only one onto a box Pokémon — \(says())")
    print(failed == 0 ? "PASS live hold" : "FAIL \(failed)")
    return failed == 0
}

/// `PokeWalker --live-v38 <idA> <idB> <pin>` (a dev build only): docs/plans/14 (3.8) against the real server with two zz IDs the admin seeded
/// (A's box: 고우스트 · 꼬렛 · 이브이 · 잉어킹; B's: 윤겔라 · 롱스톤 · 잉어킹; not friends): friends; A posts 고우스트 with a 한마디 wishing 윤겔라, B
/// offers 윤겔라 (out of its box), A's offer comes quietly (the 교환 tile's red dot), A opens the post (seen) and picks it, B takes its 받기; A sends
/// 이브이 to B for 맡겨 키우기, B walks with it, sends it back (its BP), A takes it home (the EXP); both set a 대전 파티, a friend match (3 picked of
/// each six, A gives up), the random queue (the same), the 전적.
@MainActor func liveV38Test(_ a: String, _ b: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-livev38-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    func walker(_ id: String) -> (Walker, Cloud, TestHost) {                                        // (the host comes back: the walker holds it weakly)
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
        let c = Cloud(link: HTTPLink(), dir: tmp.appendingPathComponent(id, isDirectory: true))
        h.texts = [id]; h.pins = [pin, pin, pin]
        w.startCloud(c, file: tmp.appendingPathComponent(id + ".json"), bak: tmp.appendingPathComponent(id + ".bak"))
        return (w, c, h)
    }
    let (wa, ca, ha) = walker(a), (wb, cb, hb) = walker(b)
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { wa.tick(Date()); wb.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func idle(_ c: Cloud) -> Bool { c.inFlight == nil && c.queued == nil && c.out == nil }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func settle(_ w: Walker, _ c: Cloud) { run(15) { w.waiting == nil && idle(c) } }
    func next(_ w: Walker, _ c: Cloud, until: () -> Bool) -> Bool { w.news = []; w.screen = .home; c.addSteps(2); c.saveNow(); return run(25, until: until) }
    func lists(_ w: Walker, _ c: Cloud) { c.teamDue = true; c.marketDue = true; c.mailDue = true; run(15) { !c.teamDue && !c.marketDue && !c.mailDue && idle(c) }; run(2) { false } }
    func box(_ w: Walker) -> String { w.state.box.map { monNames[$0.dex] }.joined(separator: " ") }
    check(run(40) { ca.phase == .on && cb.phase == .on && ca.base != nil && cb.base != nil }, "live 3.8: \(a) and \(b) logged in (\(ha.asked), \(hb.asked))")
    let seeded = wa.state.box.count >= 3 && wb.state.box.count >= 2                             // (first run: as seeded; a rerun takes what's there)
    check(seeded, "live 3.8: seeded — A \(box(wa)), B \(box(wb))")
    guard seeded else { print("FAIL \(failed)"); return false }

    // friends (a rerun: already)
    lists(wa, ca)
    if !wa.isFriend(b) {
        wa.screen = .home; wa.act(.friendRequest(to: b), back: .home); settle(wa, ca)
        _ = next(wb, cb) { says(wb).first?.hasSuffix("친구 신청을 했다!") == true }
        wb.screen = .home; wb.act(.friendAccept(from: a), back: .home); settle(wb, cb)
    }
    lists(wa, ca); lists(wb, cb)
    check(wa.isFriend(b) && wb.isFriend(a), "live: friends (\(wa.teamRows(0).count), \(wb.teamRows(0).count))")

    // 3.9 (docs/plans/15 §3.1): the back-pay — A's best streak mailed 7연승's reward on an act; the 우편함 takes it (a rerun: taken before)
    if let t = wa.mails.first(where: { $0.title == "7연승 달성 보상" && !$0.claimed }) {
        let c0 = wa.state.count("이상한사탕"); wa.screen = .mail(.open(id: t.id)); wa.pageTap(8840); settle(wa, ca); let took = says(wa)
        check(took.first?.hasPrefix("이상한사탕 ×3") == true && wa.state.count("이상한사탕") == c0 + 3, "live 3.9 우편함: 7연승 보상 (소급) — \(took), 사탕 \(c0) → \(wa.state.count("이상한사탕"))")
    } else { check(wa.mails.contains { $0.title == "7연승 달성 보상" } && (wa.state.towerRewards ?? []).contains(7), "live 3.9 우편함: 7연승 보상 mailed (taken before) — \(wa.mails.map(\.title)) \(String(describing: wa.state.towerRewards))") }

    // ① the 게시판: a 한마디, an offer held out of the box, the red dot, seen on opening, accepted → B's 받기
    wa.openFeature("교환"); settle(wa, ca); lists(wa, ca); wa.pageTap(8030)
    let ghost = wa.myTradeBox.first { $0.dex == 93 } ?? wa.myTradeBox.first { $0.dex != 133 }!, kadabra = wb.myTradeBox.first { $0.dex == 64 } ?? wb.myTradeBox[0]
    let note = monNames[kadabra.dex] + " 구해요!"
    ha.texts = [note]
    if case .market(.pick(var p)) = wa.screen { p.give = ghost.uid; p.wish = [kadabra.dex]; wa.screen = .market(.pick(p)); wa.pageTap(8190); settle(wa, ca) }
    let posted = says(wa); lists(wa, ca); let post = wa.myPosts.first
    check(posted == ["게시판에", "글을 올렸다!"] && post?.note == note && !wa.state.box.contains { $0.uid == ghost.uid },
          "live marketList (3.8): \(monNames[ghost.dex]) up with its 한마디 (\(post?.note ?? "-")), out of A's box — \(posted) A \(box(wa))")
    lists(wb, cb); let seen = wb.market?.listings.first { $0.id == post?.id }
    if let id = seen?.id { wb.screen = .market(.post(id: id, sel: nil)); wb.pageTap(8130) }
    if case .market(.pick(var p)) = wb.screen { p.give = kadabra.uid; wb.screen = .market(.pick(p)); wb.pageTap(8190); settle(wb, cb) }
    check(seen?.note == note && says(wb).first == "교환을 제안했다!" && !wb.state.box.contains { $0.uid == kadabra.uid },
          "live marketBid: B sees the note, offers \(monNames[kadabra.dex]) (out of B's box) — \(says(wb)) B \(box(wb))")
    _ = next(wa, ca) { idle(ca) }; run(3) { false }; let quiet = says(wa).isEmpty
    lists(wa, ca)
    let dot = wa.marketDot && (wa.market?.unseen ?? 0) >= 1
    if let id = post?.id { wa.openPost(id); run(10) { (ca.market?.unseen ?? 1) == 0 && idle(ca) } }
    check(quiet && dot && (ca.market?.unseen ?? -1) == 0, "live: the offer comes quietly — the 교환 tile's red dot (unseen \(wa.market?.unseen ?? -1)); opening the post marks it seen")
    if let id = post?.id { wa.screen = .market(.post(id: id, sel: 0)); wa.pageTap(8130); run(20) { wa.waiting == nil && idle(ca) && { if case .traded = wa.screen { return true }; return false }() } }
    let show: Bool = { if case .traded(let g, let got, _, _) = wa.screen { return g.dex == ghost.dex && got.dex == kadabra.dex }; return false }()
    run(10) { if case .evolve = wa.screen { return true }; return false }
    check(show && wa.state.box.contains { $0.ot.map { trainerID($0)?.key == trainerID(b)?.key } == true }, "live marketAccept: A's show; \(monNames[kadabra.dex]) comes to A (A \(box(wa)))")
    _ = next(wb, cb) { cb.mailDue || wb.mails.contains { $0.kind == "trade" && !$0.claimed } }; lists(wb, cb)
    let k = wb.mails.first { $0.kind == "trade" && !$0.claimed && giftMon($0)?.dex == ghost.dex }
    if let k { wb.screen = .mail(.open(id: k.id)); wb.pageTap(8840); settle(wb, cb) }; let took = says(wb); run(10) { if case .evolve = wb.screen { return true }; return false }
    check(k != nil && took.first == josa(monNames[ghost.dex], "을", "를") + " 받았다!" && wb.state.box.contains { $0.ot.map { trainerID($0)?.key == trainerID(a)?.key } == true },
          "live 3.9 우편함: B's mail has \(monNames[ghost.dex]) (trade: \(k?.title ?? "-")); 받기 takes it — \(took) (B \(box(wb)))")

    // ② 맡겨 키우기: A sends 이브이 to B (walking now), B raises it, sends it back (BP), A takes it home (EXP)
    _ = next(wb, cb) { idle(cb) }; lists(wa, ca)
    let bi = wa.teamRows(0).firstIndex { !wa.isMe($0.card) } ?? 0
    wa.screen = .team(sel: bi, tab: 0, card: true); let card = wa.paneContent(Date()).teamCard; wa.pageTap(6034)
    let eevee = wa.state.box.first { $0.dex == 133 } ?? wa.state.box.first { $0.ot == nil } ?? wa.state.box[0], lv0 = eevee.level
    if case .visitPick(var p) = wa.screen, let at = wa.visitRefs.firstIndex(where: { wa.state.mon($0)?.uid == eevee.uid }) { p.at = at; wa.screen = .visitPick(p); wa.press(1); wa.press(1); settle(wa, ca) }
    let sentSaid = says(wa)
    check(card?.visit == "맡기기" && sentSaid.dropFirst().first == "맡겼다!" && !wa.state.box.contains { $0.uid == eevee.uid }, "live visitSend: \(monNames[eevee.dex]) to B — \(sentSaid)")
    let came = next(wb, cb) { says(wb).dropFirst().first == "맡았다!" }
    lists(wb, cb)
    check(came && wb.guests.count == 1 && wb.guests.first?.mon.uid == eevee.uid, "live visitCame: B hears it; its 맡기기 tab has the guest")
    let walkEnd = Date().addingTimeInterval(150)                                                    // (the server takes at most 15 steps a second)
    while Date() < walkEnd, (wb.guests.first?.steps ?? 0) < 2000 { wb.screen = .home; cb.addSteps(240); cb.saveNow(); run(15) { false }; cb.teamDue = true; run(5) { !cb.teamDue && idle(cb) } }
    let raised = wb.guests.first?.steps ?? 0, bp0 = wb.state.bp ?? 0
    wb.screen = .team(sel: 0, tab: TeamTab.visits, card: false); wb.pageTap(6400); settle(wb, cb); let back = says(wb)
    check(raised >= 2000 && back.dropFirst().first == "돌려보냈다" && (wb.state.bp ?? 0) == bp0 + raised / 2000, "live visitEnd: \(raised) steps raised; 돌려보내기 → B's BP \(bp0) → \(wb.state.bp ?? 0) — \(back)")
    _ = next(wa, ca) { wa.mails.contains { $0.kind == "visit" && !$0.claimed } || ca.mailDue }; lists(wa, ca)
    let vk = wa.mails.first { $0.kind == "visit" && !$0.claimed && giftMon($0)?.uid == eevee.uid }
    if let vk { wa.screen = .mail(.open(id: vk.id)); wa.pageTap(8840); settle(wa, ca) }
    run(10) { false }
    let home = wa.state.box.first { $0.uid == eevee.uid }
    check(vk != nil && (home?.level ?? 0) > lv0, "live 3.9: A's 우편함 (visit) → \(monNames[eevee.dex]) home, Lv.\(lv0) → Lv.\(home?.level ?? 0)")

    // ③ the 대전 menu: parties, a friend match (pick 3), the queue, the 전적
    for (w, c) in [(wa, ca), (wb, cb)] {
        w.openFeature("대전"); settle(w, c); w.pageTap(6330)
        if case .squad(var q) = w.screen { q.picked = []; w.screen = .squad(q) }                   // (a rerun: picked afresh)
        for k in 0..<3 { pickAt(w, k) }
        w.pageTap(8790); settle(w, c)
    }
    check((wa.state.duelParty?.count ?? 0) >= 3 && (wb.state.duelParty?.count ?? 0) >= 3, "live duelParty: both set (A \(wa.state.duelParty ?? []), B \(wb.state.duelParty ?? []))")
    func pickThree(_ w: Walker, _ c: Cloud) { if case .squad(let q) = w.screen, case .duelPick = q.kind { for k in [2, 0, 1] { pickAt(w, k) }; w.pageTap(8790); settle(w, c) } }
    func isPick(_ w: Walker) -> Bool { if case .squad(let q) = w.screen, case .duelPick = q.kind { return true }; return false }
    /// Both sides to the end: A gives up at its first menu, B attacks.
    func fightOut() -> (String, String) {
        let end = Date().addingTimeInterval(180)
        while Date() < end, wa.duelOn || wb.duelOn {
            run(0.3) { false }
            for (w, c) in [(wa, ca), (wb, cb)] where w.waiting == nil && idle(c) {
                switch w.screen {
                case .beats(_, let bs, let since, _) where Date().timeIntervalSince(since) * w.battleSpeed > bs.map(\.length).reduce(0, +): w.tick(Date())
                case .battle(let bt, _) where !w.duelWait:
                    if w === wa { w.screen = .battle(bt, sel: w.battleMenu(bt).firstIndex(of: "기권") ?? 0); w.press(1); w.press(2); w.press(1) }
                    else { w.screen = .battle(bt, sel: 0); w.press(1); if case .moves(let x, _) = w.screen { w.screen = .moves(x, sel: x.mine[x.me].pp.firstIndex { $0 > 0 } ?? 0); w.press(1) } }
                case .party(let bt, _): w.screen = .party(bt, sel: bt.mine.indices.first { bt.mine[$0].alive && $0 != bt.me } ?? 0); w.press(1)
                default: break
                }
            }
        }
        return (says(wa).joined(separator: " "), says(wb).joined(separator: " "))
    }
    _ = next(wb, cb) { idle(cb) }; lists(wa, ca)
    wa.screen = .duel(.hub(tab: 0, sel: 0)); let hub = wa.paneContent(Date()).duelHub; wa.pageTap(6340); settle(wa, ca)
    let out: Bool = { if case .duel(.waitAccept) = wa.screen { return true }; return false }()
    check(hub?.friends.first?.name.lowercased() == b.lowercased() && out, "live duelChallenge (3.8): from the 대전 menu's friend row — \(wa.screen)")
    _ = next(wb, cb) { says(wb).first?.hasSuffix("대전을 신청했다!") == true }
    wb.press(1); wb.pageTap(6300); settle(wb, cb)
    run(30) { isPick(wa) && isPick(wb) }
    let theirSix = wb.paneContent(Date()).squad?.theirs?.count ?? 0
    check(isPick(wa) && isPick(wb) && theirSix >= 3, "live duelAccept → picking on both sides (the other's \(theirSix) by species, \(wb.duelLeft() ?? -1) s)")
    pickThree(wa, ca); let waitingPick = wa.paneContent(Date()).squad?.hint; pickThree(wb, cb)
    let started = run(30) { if case .beats = wa.screen { return true }; if case .battle = wa.screen { return true }; return false }
    let order = wa.fight?.mine.map(\.mon.dex) ?? [], six = wa.state.duelParty?.compactMap { wa.state.ref(uid: $0).flatMap { wa.state.mon($0)?.dex } } ?? []
    check(started && order.count == 3 && order == [six[safe: 2], six[safe: 0], six[safe: 1]].compactMap { $0 }, "live duelPick: A's three in its order (\(order.map { monNames[$0] })), waited (\(waitingPick ?? "-")), the fight on")
    let (ra, rb) = fightOut()
    check(!wa.duelOn && !wb.duelOn && rb.hasPrefix("이겼다!") && ra.contains("졌다"), "live: A gave up — A \(ra) · B \(rb)")
    wa.screen = .duel(.hub(tab: 0, sel: 0)); wa.pageTap(6331); settle(wa, ca)
    let queued: Bool = { if case .duel(.queued) = wa.screen { return true }; return isPick(wa) }()
    wb.screen = .duel(.hub(tab: 0, sel: 0)); wb.pageTap(6331); settle(wb, cb)
    run(30) { isPick(wa) && isPick(wb) }
    check(queued && isPick(wa) && isPick(wb), "live duelQueue: A waits; B joins → both on the pick")
    pickThree(wa, ca); pickThree(wb, cb)
    run(30) { if case .beats = wa.screen { return true }; if case .battle = wa.screen { return true }; return false }
    let (qa, qb) = fightOut()
    check(qb.hasPrefix("이겼다!"), "live: the queue's duel to its end — A \(qa) · B \(qb)")
    wa.openFeature("대전"); run(15) { ca.duelRecord != nil && idle(ca) }; wa.pageTap(6321)
    let recs = wa.paneContent(Date()).duelHub?.recs ?? []
    check(recs.count >= 2 && recs.prefix(2).allSatisfy { !$0.won && $0.line.lowercased() == "vs " + b.lowercased() && $0.mine.count == 3 }, "live 전적: \(recs.prefix(2).map { "\($0.won ? "승" : "패") \($0.line) \($0.sub)" })")
    print(failed == 0 ? "PASS live 3.8" : "FAIL \(failed)")
    return failed == 0
}

/// `--live-tower <id> <pin>` (4.1, plan 17): the tower's one legend against the real server, with a seeded test ID — box 뮤츠 · 루기아 · 망나뇽 ·
/// 한카리아스 (+ others), a pick from before 4.1 holding two legends (뮤츠 · 루기아 · 망나뇽), W for a run. That pick can't start (legendWhy, no fee)
/// and can't be sent as it is; it comes down to one; another legend is a shadow on the picker; a legend swaps in last; a second one sent anyway is
/// refused; then a run starts (no legend at the 1st fight) and is given up. The strip from 7 (the reset's 0s).
@MainActor func liveTowerTest(_ id: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-livetower-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
    let c = Cloud(link: HTTPLink(), dir: tmp); h.texts = [id]; h.pins = [pin, pin, pin]
    w.startCloud(c, file: tmp.appendingPathComponent("state.json"), bak: tmp.appendingPathComponent("state.json.bak"))
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { w.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func settle() { run(20) { w.waiting == nil && c.inFlight == nil && c.queued == nil && c.out == nil } }
    func says() -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func party() -> [Int] { w.state.party().map(\.mon.dex) }
    func uid(_ dex: Int) -> Int { (w.state.box.first { $0.dex == dex } ?? w.state.caught.first { $0.dex == dex })?.uid ?? -1 }
    func squad() -> Squad? { if case .squad(let q) = w.screen { return q }; return nil }
    func cell(_ dex: Int) -> Int? { squad().flatMap { q in w.squadKeys(q).firstIndex { w.squadMon(q, $0)?.dex == dex } } }
    func tap(_ dex: Int) { guard var q = squad(), let i = cell(dex) else { return }; q.at = i; w.screen = .squad(q); w.press(1) }   // ● at its cell (the pages don't matter)
    check(run(40) { c.phase == .on && c.base != nil }, "live tower: \(id) logged in (\(h.asked))")
    let seeded = [150, 249, 149, 445].allSatisfy { uid($0) >= 0 } && w.state.watts >= 2 * Walk.towerFee
    check(seeded, "live tower: seeded — box \(w.state.box.map(\.dex)), \(w.state.watts) W, pick \(String(describing: w.state.towerPick))")
    guard seeded else { print("FAIL \(failed)"); return false }
    settle(); w.calmAt = .distantPast
    let w0 = w.state.watts, old = party(), two = w.state.legends(w.state.party().map(\.ref)) > 1
    check(two, "live tower: the seed's pick from before 4.1 holds two legends (\(old)) — reseed if not (a run leaves one)")
    guard two else { print("FAIL \(failed)"); return false }
    w.towerRun = false; w.screen = .tower(pick: nil); w.pageTap(5400); settle()
    check(says() == Walker.noLegend && !w.inBattle && w.state.watts == w0, "live tower: … it can't start — \(says()), no fee (\(w0) → \(w.state.watts) W)")
    w.screen = .tower(pick: nil); w.pageTap(5410)
    let mine = squad()?.picked.count ?? 0
    w.pageTap(8790); check(says() == Walker.noLegend, "live tower: … nor be sent as it is (the picker says why) — \(says())")
    w.towerPartyPick(); for _ in 0..<mine { w.pageTap(8740) }
    tap(150); tap(149); tap(445); w.pageTap(8790); settle()
    check(party() == [150, 149, 445], "live tower: down to one legend — 뮤츠 · 망나뇽 · 한카리아스 set (\(party()))")
    w.towerPartyPick(); let shadow = squad().flatMap { q in cell(249).map { w.squadPane(q, Date()).squad?.cells[safe: $0 % SquadModel.perPage]?.look } } ?? nil
    tap(249); let why = says(); if !why.isEmpty { w.press(1) }
    check(shadow == 1 && why == Walker.noLegend, "live tower: with 뮤츠 in, 루기아 is a shadow and ● on it says why — \(why)")
    w.towerPartyPick(); for _ in 0..<3 { w.pageTap(8740) }; tap(149); tap(445); tap(249); w.pageTap(8790); settle()
    check(party() == [149, 445, 249] && says().isEmpty, "live tower: a legend for a legend (루기아 last, sent last) — \(party()) \(says())")
    w.screen = .tower(pick: nil)
    w.act(.towerPick(slot: 0, uid: uid(150)), back: .tower(pick: nil), Date()) { _, _ in .tower(pick: nil) }; settle()
    check(says() == Walker.noLegend && party() == [149, 445, 249], "live tower: a second legend sent anyway — the server's refusal (\(says())), the party as it was")
    w.screen = .tower(pick: nil); let strip = w.paneContent(Date()).tower, w1 = w.state.watts
    w.calmAt = .distantPast; w.pageTap(5400); run(30) { w.inBattle || !says().isEmpty }        // (● right after a message is held back a moment: 3.8.6)
    let foes = w.fight?.theirs.map(\.mon.dex) ?? []
    check(w.inBattle && foes.count == 3 && !foes.contains(where: Tower.isLegend) && w.state.watts == w1 - Walk.towerFee,
          "live tower: one legend in, a run starts (\(w1) → \(w.state.watts) W; the 1st fight's \(foes.map { monNames[$0] }), no legend)")
    if let b = w.fight { run(30) { if case .battle = w.screen { return true }; if case .moves = w.screen { return true }; return false }; w.screen = .forfeit(b, yes: true); w.press(1); settle() }
    check(!w.inBattle && (w.state.towerStreak ?? 0) == 0, "live tower: given up — \(says())")
    check(strip?.rewards.first?.wins == 7 || strip?.rewards.last?.more == true, "live tower: the strip — \(strip?.rewards.map { "\($0.got ? "✓" : "")\($0.wins)\($0.more ? "~" : "")" } ?? []) · \(strip?.next ?? "") (best \(w.state.towerBest ?? -1), rewards \(String(describing: w.state.towerRewards)))")
    print(failed == 0 ? "PASS live tower" : "FAIL \(failed)")
    return failed == 0
}

/// `PokeWalker --live-five <id> <pin>` (a dev build only, against a local 5.0 server: POKEWALKER_SERVER=http://127.0.0.1:8799, content5 on,
/// MIN_APP 5.0 — docs/plans/18 §12 A6): one zz ID, made by a first run and then seeded by the local server's admin (`pokeserver set`): the
/// companion 리자몽 Lv.60 holding 리자몽나이트X, a 로토무 in the box, 1,000 W+, raid power for a run. The login turns content5 on (721);
/// the shop sells 로토무카탈로그 and the catalog turns the 로토무 into 히트로토무 (오버히트); a radar fight's 메가진화 (the toggle, then a move:
/// the server's Mega beat); 메가 레이드's lobby (the week's two), a ★1 run to its end, its 내 판; 5.0's pictures drawn.
@MainActor func liveFiveTest(_ id: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-livefive-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
    let c = Cloud(link: HTTPLink(), dir: tmp); h.texts = [id]; h.pins = [pin, pin, pin]; h.answer = true
    w.startCloud(c, file: tmp.appendingPathComponent("state.json"), bak: tmp.appendingPathComponent("state.json.bak"))
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { w.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func idle() -> Bool { w.waiting == nil && c.inFlight == nil && c.queued == nil && c.out == nil }
    func settle() { run(15, until: idle) }
    func says() -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func toHome() { run(20) { if !w.news.isEmpty || !idle() { return false }; if case .home = w.screen { return true }; w.screen = .home; return false } }
    print("server: \(HTTPLink.base)")
    check(run(40) { c.phase == .on && c.base != nil }, "live 5.0: \(id) logged in (\(c.phase); asked \(h.asked))")
    check(Content.on && dexMax == 721 && w.dexList(0).count == 721, "live 5.0: the login's content5 on — 도감 \(w.dexList(0).count), dexMax \(dexMax)")
    let seeded = w.state.companion.dex == 6 && w.state.companion.item == "리자몽나이트X" && w.state.box.contains { $0.dex == 479 } && w.state.watts >= 1000 && w.raidCells >= 1
    check(seeded, "live 5.0: seeded — companion \(monNames[w.state.companion.dex]) Lv.\(w.state.companion.level) \(w.state.companion.item ?? "-"), box \(w.state.box.map(\.dex)), \(w.state.watts) W, raid cells \(w.raidCells)")
    guard seeded else { print("FAIL \(failed) (seed it on the local server, then run again)"); return false }

    // 상점: 로토무카탈로그; then the catalog on the box's 로토무 → 히트로토무 (its move 오버히트)
    if let k = w.wares(false).firstIndex(where: { $0.kind == .item("로토무카탈로그") }) {
        w.screen = .shopConfirm(bp: false, sel: k, yes: true); w.press(1); settle()                     // (a key item: once, 정말 살까?)
        check(w.state.count("로토무카탈로그") == 1, "live 5.0 shop: 로토무카탈로그 bought (\(w.wares(false)[k].price) W)")
    } else { check(false, "live 5.0 shop: no 로토무카탈로그 among \(w.wares(false).count) wares") }
    if let r = w.state.box.firstIndex(where: { $0.dex == 479 }), let u = w.state.box[r].uid {
        w.calmAt = .distantPast; w.screen = .formPick(ref: r, item: "로토무카탈로그", sel: 1); w.press(1); settle()
        let m = w.state.ref(uid: u).flatMap { w.state.mon($0) }
        check(m?.form == 1 && m?.moves.contains(315) == true && w.formName(m!) == "히트로토무", "live 5.0 로토무카탈로그: \(says()) — form \(m?.form ?? 0), moves \(m?.moves ?? [])")
        w.press(1)
    }

    // a radar fight: 메가진화 ticked, then a move — the server's Mega beat, 메가리자몽X on our side
    toHome(); let w0 = w.state.watts
    w.openFeature("포켓 레이더")
    if run(20, until: { if case .radar = w.screen { return true }; return false }), case .radar(let b, _, let since, let chain) = w.screen {
        w.screen = .radar(bush: b, cursor: b, since: since, chain: chain)
        while Date().timeIntervalSince(since) < 1.6 { Thread.sleep(forTimeInterval: 0.05) }
        w.press(1)
        run(20) { if case .battle = w.screen { return true }; return idle() && !w.inBattle && { if case .beats = w.screen { return false }; return true }() }
        if case .battle(let bt, _) = w.screen {
            check(bt.canMega(.me), "live 5.0: a fight with 리자몽나이트X: 메가진화 offered (wild \(monNames[bt.wild.dex]) Lv.\(bt.wild.level), \(w0) W → \(w.state.watts))")
            w.screen = .moves(bt, sel: bt.mine[bt.me].moves.count); w.calmAt = .distantPast; w.press(1)
            let ticked = w.megaOn
            w.screen = .moves(bt, sel: 0); w.calmAt = .distantPast; w.press(1)
            var megaBeat = false, megaSide = false
            run(20) {
                if case .beats(let after, let bs, _, _) = w.screen {
                    megaBeat = bs.contains { if case .mega(.me, 1, _) = $0 { return true }; return false }; megaSide = after.mine[after.me].mega == 1; return true
                }
                return idle() && !w.inBattle
            }
            check(ticked && megaBeat && megaSide, "live 5.0 메가진화: ticked \(ticked), the server's Mega beat \(megaBeat), 메가리자몽X on our side \(megaSide)")
            run(60) { if case .beats = w.screen { return false }; if case .battle(let bt2, _) = w.screen, w.waiting == nil { w.screen = .battle(bt2, sel: w.battleMenu(bt2).count - 1); w.press(1) }; return !w.inBattle && idle() }   // (then away)
        } else { check(false, "live 5.0: no radar fight began (\(w.screen))") }
    } else { check(false, "live 5.0: no radar") }

    // 메가 레이드: the lobby (the week's two, 스톤까지 n/30), ★1 with the strongest three, played to its end, its 내 판
    toHome(); w.openFeature("메가 레이드"); c.megaRaidDue = true; run(15) { !c.megaRaidDue && idle() && w.waiting == nil }
    let lob = c.megaRaid
    check(w.raidMega && lob?.bosses.count == 2 && lob?.pityNeed == MegaRaid.bossWins && lob?.bosses.allSatisfy { $0.wins != nil } == true && lob?.today.max == RaidRules.perDay,
          "live 5.0 메가 레이드: \(lob?.week ?? "-") — \(lob?.bosses.map { w.megaName($0) + " (\($0.stone)) \($0.had == true ? "보유" : "\($0.wins ?? -1)/\(lob?.pityNeed ?? -1)")" } ?? []), today \(lob?.today.used ?? -1)/\(lob?.today.max ?? -1)")
    let runs0 = lob?.mine.runs ?? 0
    w.calmAt = .distantPast; w.pageTap(7010); w.pageTap(7020); w.pageTap(7020)
    if case .squad(var q) = w.screen {
        q.picked = Array(w.squadKeys(q).sorted { (w.squadMon(q, $0)?.level ?? 0) > (w.squadMon(q, $1)?.level ?? 0) }.prefix(3)); w.screen = .squad(q)
    }
    w.pageTap(8790); settle()
    let boss = w.fight?.wild, bossMega = w.fight?.theirs.first?.mega
    check(boss != nil && bossMega != nil && w.fight?.raidTier == 1, "live 5.0 메가 레이드 ★1: in — \(boss.map { monNames[$0.dex] + " Lv.\($0.level)" } ?? "-"), its Mega form \(bossMega ?? 0)")
    let end = Date().addingTimeInterval(240)
    while Date() < end {
        run(0.3) { false }
        guard w.waiting == nil, idle() else { continue }
        switch w.screen {
        case .beats: continue
        case .battle(let bt, _): w.screen = .battle(bt, sel: 0); w.press(1)
        case .moves(let bt, _): w.screen = .moves(bt, sel: bt.mine[bt.me].pp.firstIndex { $0 > 0 } ?? 0); w.press(1)
        case .party(let bt, _): w.screen = .party(bt, sel: bt.mine.indices.first { bt.mine[$0].alive } ?? 0); w.press(1)
        case .learn: w.screen = .learn(sel: 4); w.press(1)
        default: break
        }
        if !w.inBattle, case .say = w.screen { break }
    }
    let lines = says(); w.press(1); run(3) { false }
    c.megaRaidDue = true; run(15) { !c.megaRaidDue && idle() }
    check(!w.inBattle && !lines.isEmpty && (c.megaRaid?.mine.runs ?? 0) == runs0 + 1 && c.megaRaid?.runs.first?.tier == 1,
          "live 5.0 메가 레이드: over — \(lines); 내 판 \(runs0) → \(c.megaRaid?.mine.runs ?? -1), 스톤까지 \(c.megaRaid?.bosses.map { $0.had == true ? "보유" : "\($0.wins ?? -1)/\(MegaRaid.bossWins)" } ?? [])")

    // 5.0's pictures: the box's and the 도감's past 493 (hg-engine's)
    check(spriteCount > 721 && (0..<80).contains { spritePixel(658, back: false, $0, 79, shiny: false) != 0 } && !w.compose(Date()).sprites.isEmpty, "live 5.0: pictures past 493 (\(spriteCount) in the bundle)")
    print(failed == 0 ? "PASS live five" : "FAIL \(failed)")
    return failed == 0
}
