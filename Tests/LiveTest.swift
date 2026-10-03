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
            case .home where w.news.isEmpty && idle() && !w.chainNext: return
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
            case .home: return w.news.isEmpty && idle() && !w.chainNext
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
