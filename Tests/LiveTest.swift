import Foundation
// `PokeWalker --live-test <id> <pin>` (a dev build only: main.swift): the app's own logic — a Walker and its Cloud — against the real save server,
// headless and in real time, the ID and PIN boxes answered by a TestHost. What the self-test does with FakeCloud, here with HTTPLink: a new ID
// (or a login with its PIN), steps for W, the server's radar (a catch, a chain if it comes, a KO, a flight, a miss), and when the trainer has them
// (an admin's `pokeserver set`) an egg's hatch, a legend bought, a 껍질몬. Everything in a temp folder: the save and the dev data are never touched.

@MainActor func liveTest(_ id: String, _ pin: String) -> Bool {
    var failed = 0
    func check(_ ok: Bool, _ name: String) { if !ok { failed += 1 }; print((ok ? "ok   " : "FAIL ") + name) }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-live-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
    let c = Cloud(link: HTTPLink(), dir: tmp, on: true)
    w.startCloud(c, file: tmp.appendingPathComponent("state.json"), bak: tmp.appendingPathComponent("state.json.bak"))   // (never the real save's 08 §5 move)
    h.texts = [id]; h.pins = [pin, pin, pin]
    /// Ticks in real time until done (or the time's up); true = done.
    @discardableResult func run(_ secs: Double, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { w.tick(Date()); if done() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return done()
    }
    func radarUp() -> Bool { if case .radar = w.screen { return true }; return false }
    func settled() -> Bool { w.mintWaiting == nil && c.mints.isEmpty && c.inFlight == nil }

    check(run(30) { c.phase == .on }, "live: \(id) logged in (\(h.asked.contains("새 트레이너") ? "a new trainer, its PIN set" : "its PIN")) — server \(HTTPLink.base.host ?? "")")
    guard c.phase == .on else { print("FAIL \(failed) — not logged in (phase \(c.phase))"); return false }
    if h.asked.contains("새 트레이너") { check(w.state.companion.uid == 1_000_000, "live: the new trainer's companion is the server's starter (uid 1,000,000)") }

    let need = 45                                                                                // W for the four radars, walked: ~900 steps at a person's rate
    if w.state.watts < need {
        let t0 = Date(); var k: UInt32 = 0
        run(150) { k += 1; h.keys &+= [2, 1, 1, 2, 0, 1, 2][Int(k) % 7]; return w.state.watts >= need }   // ~13 a second, uneven (StepGate: 15 a second, 600 a minute)
        check(w.state.watts >= need, "live: steps → \(w.state.watts) W in \(Int(Date().timeIntervalSince(t0))) s (total \(w.state.total))")
    }

    /// From home: a radar opened (the server's find), then its live bush pressed (hit) or the next one; the fight, if it began.
    func radar(hit: Bool, opened: Bool = false) -> Battle? {
        if !opened { w.screen = .menu(menuAt("포켓 레이더")); w.press(1) }
        guard run(20, until: radarUp), case .radar(let b, _, let since, let chain) = w.screen else { return nil }
        w.screen = .radar(bush: b, cursor: hit ? b : (b + 1) % 4, since: since, chain: chain)
        while Date().timeIntervalSince(since) < 1.6 { Thread.sleep(forTimeInterval: 0.05) }   // inside the bush's window (no tick meanwhile: its timeout)
        w.press(1)
        if case .beats(let f, _, _, _) = w.screen { return f }
        return nil
    }
    /// A fight's end as the battle would report it, then the server's answer.
    func end(_ f: Battle, _ how: Beat) { w.screen = w.after(f, how, Date()); run(20, until: settled) }

    var w0 = w.state.watts
    if let f = radar(hit: true) {
        let uid = f.wild.uid ?? 0
        check(uid > 1_000_000 && w.state.watts == w0 - 10, "live radar: the server's find \(monNames[f.wild.dex]) Lv.\(f.wild.level) uid \(uid); 10 W after it answered")
        w0 = w.state.watts; end(f, .caught)
        let kept = w.state.box.contains { $0.uid == uid }
        if radarUp(), case .radar(_, _, _, let n) = w.screen {
            check(kept && n == 1 && w.state.watts == w0 + 2 && w.state.bestChain ?? 0 >= 1, "live radar: caught (uid \(uid) kept); the server's chain 1: +2 W, the next radar free")
            w0 = w.state.watts
            if let g = radar(hit: true, opened: true) {
                check((g.wild.uid ?? 0) > uid && w.state.watts == w0, "live radar: the chain's fight \(monNames[g.wild.dex]) uid \(g.wild.uid ?? 0), no fee")
                end(g, .won); check(!w.state.box.contains { $0.uid == g.wild.uid }, "live radar: defeated (reported; not kept) → chain \(radarUp() ? "goes on" : "over")")
                if radarUp(), case .radar(let b, _, let s, let ch) = w.screen { w.screen = .radar(bush: b, cursor: (b + 1) % 4, since: s, chain: ch); while Date().timeIntervalSince(s) < 1.6 { Thread.sleep(forTimeInterval: 0.05) }; w.press(1); run(10, until: settled) }
            } else { check(false, "live radar: the chain's radar didn't come up") }
        } else { check(kept, "live radar: caught (uid \(uid) kept); the server ended the chain (no bonus)") }
    } else { check(false, "live radar: no fight began") }
    w.screen = .home
    if let f = radar(hit: true) { end(f, .won); check(!w.state.box.contains { $0.uid == f.wild.uid }, "live radar: a KO from a new radar (uid \(f.wild.uid ?? 0)) reported"); if radarUp() { w.screen = .home; w.radarMissed(Date()); run(10, until: settled) } }
    w.screen = .home
    if let f = radar(hit: true) { end(f, .ran); check(!radarUp() && !w.state.box.contains { $0.uid == f.wild.uid }, "live radar: fled (uid \(f.wild.uid ?? 0)) — the chain ends") }
    w.screen = .home; w0 = w.state.watts
    let missed = radar(hit: false); run(10, until: settled)
    check(missed == nil && w.radarMon == nil && w.state.watts == w0 - 10, "live radar: a wrong bush → missed, reported; its 10 W spent")

    w.screen = .home
    if w.state.hatchDue {                                                                        // an egg walked to the end (or an admin's, ready: pokeserver set) — never forced here
        let before = w.state.box.count
        run(20) { w.state.egg == nil }
        let m = w.state.box.last
        check(w.state.egg == nil && w.state.box.count == before + 1 && (m?.uid ?? 0) > 1_000_000, "live hatch: the server's \(m.map { monNames[$0.dex] } ?? "?") Lv.1 uid \(m?.uid ?? 0)")
    } else { print("skip live hatch: " + (w.state.egg.map { "its egg needs \($0.left) more steps" } ?? "no egg") + " (pokeserver set …'$.egg' {…, left: 0})") }
    if w.state.watts >= 9999, let k = w.wares(false).firstIndex(where: { if case .legend = $0.kind { return true }; return false }) {
        w.screen = .home; w.buyWare(w.wares(false)[k], 1, bp: false, sel: k, Date()); run(20, until: settled)
        let m = w.state.box.last
        check(m?.dex == 250 && (m?.uid ?? 0) > 1_000_000 && w.state.watts < 9999 && w.state.legendBought(250), "live buy: the server's 칠색조 uid \(m?.uid ?? 0); 9,999 W paid")
    } else { print("skip live buy: \(w.state.watts) W (9,999 needed: pokeserver set …'$.watts' 9999)") }
    if let i = w.state.box.lastIndex(where: { $0.dex == 290 && ($0.uid ?? 0) > 0 }), let e = evolutions.first(where: { $0.from == 290 && $0.to == 291 }) {
        let before = w.state.box.count
        w.screen = .home; w.startEvolving(e, Date(), ref: i); run(20, until: settled)
        check(w.state.box.count == before + 1 && w.state.box.last?.dex == 292, "live evolve: 토중몬 → 아이스크, the server's 껍질몬 uid \(w.state.box.last?.uid ?? 0)")
    } else { print("skip live evolve: no 토중몬 issued") }

    w.screen = .home; c.soon(Date()); run(10) { c.inFlight == nil && c.due == nil }; c.flush(&w.state)
    print("box: " + w.state.box.map { "\(monNames[$0.dex]) #\($0.uid ?? 0)" }.joined(separator: ", ") + " · \(w.state.watts) W · rev \(w.state.cloudRev ?? 0)")
    print(failed == 0 ? "PASS live" : "FAIL \(failed)")
    return failed == 0
}
