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
        toHome(); w.screen = .menu(menuAt("포켓 레이더")); w.press(1)
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
/// sees the other on the team (test IDs see test IDs), A's 인사 reaches B as hello on B's next act, a second one within the hour is refused.
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
    wa.screen = .home; wa.greet(b, back: .home); run(15) { wa.waiting == nil && idle(ca) }
    let said = { if case .say(let l, _, _) = wa.screen { return l.last == "인사했다! ♥" }; return false }()
    check(said, "live 인사: A → B, the server took it")
    wa.greeted = [:]; wa.greet(b, back: .home); run(15) { wa.waiting == nil && idle(ca) }
    let refused = { if case .say(let l, _, _) = wa.screen { return l.joined().contains("조금 뒤에") }; return false }()
    check(refused, "live 인사: again within the hour → 조금 뒤에 다시 인사할 수 있어요 (the server's limit)")
    wb.screen = .home; cb.addSteps(2); cb.saveNow(); run(20) { wb.visitor != nil }
    check(wb.visitor.map { $0.hello && $0.name.lowercased() == a.lowercased() && $0.dex == 25 } == true, "live hello: B's next act brings A's 인사 — A's 피카츄 on B's home with ♥")
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
    let heard = next(wa, ca) { says(wa).last == "상대가 거절했어요" }
    check(declined && heard, "live 거절 (a 아무거나 one): said at B; A's next act hears 상대가 거절했어요")
    wa.act(.tradeOffer(to: b, give: rattata, want: nil), back: .home); run(15) { wa.waiting == nil && idle(ca) }
    ca.tradesDue = true; run(10) { ca.trades?.outgoing.count == 1 && idle(ca) }
    wa.screen = .trade(.list(0)); wa.pageTap(6110 + max(0, wa.tradeRows.firstIndex { wa.mineOffer($0) } ?? 0)); wa.pageTap(6132); run(15) { wa.waiting == nil && idle(ca) }
    let took = says(wa) == ["교환 신청을", "거뒀다"]
    let told = next(wb, cb) { says(wb).last == "상대가 거뒀어요" || { if case .say(_, .trade(.offer), _) = wb.screen { return false }; return false }() }
    check(took && told, "live 거두기: said at A; B's next act hears 상대가 거뒀어요 (\(says(wb)))")
    print(failed == 0 ? "PASS live trade" : "FAIL \(failed)")
    return failed == 0
}
