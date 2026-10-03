import Foundation
// The self-test's walkers on the fake server (Core/Cloud.swift's FakeCloud, the shared engine behind it): 3.0's walker changes nothing by
// itself, so a test gives it a trainer there, logged in, and lets its acts come back (drain).

@MainActor var onlineCount = 0
/// A walker logged into a fake server whose trainer has this save (each Pokémon given a uid, as the server does). host: a TestHost by default.
@MainActor func online(_ s: Walk, server: FakeCloud = FakeCloud(), host: TestHost? = TestHost(), rng: UInt64? = nil) -> Walker {
    onlineCount += 1
    let key = String(format: "zz9%05d", onlineCount), dir = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-online-\(ProcessInfo.processInfo.processIdentifier)-\(onlineCount)", isDirectory: true)
    if let r = rng { server.rng = Seeded(s: r) }
    server.add(key, s)
    let c = Cloud(link: server, dir: dir); c.seat.trainerID = key
    let v = Walker(state: s); v.persist = false; v.host = host; host?.keys = 0
    v.startCloud(c); drain(v)
    return v
}
/// Ticks until the walker's act (and the server's answer, and what the answer showed at home) is in.
@MainActor func drain(_ v: Walker, max: Int = 40) {
    var n = 0
    repeat { v.tick(Date()); n += 1 } while n < max && (v.waiting != nil || v.cloud.map { $0.inFlight != nil || $0.queued != nil || $0.out != nil || $0.asking != nil } == true)
}
/// The fake server under a walker, and its trainer's key.
@MainActor func server(_ v: Walker) -> (FakeCloud, String) { (v.cloud!.link as! FakeCloud, v.cloud!.seat.trainerID!.lowercased()) }
/// An admin's change to the trainer's save on the server (`pokeserver set`), the walker shown it too (its next answer would bring it anyway).
@MainActor func serve(_ v: Walker, _ change: (inout Walk) -> Void) {
    let (srv, key) = server(v)
    guard var w = srv.walk(key) else { return }
    change(&w); for ref in [-1] + w.caught.indices.map({ -2 - $0 }) + Array(w.box.indices) { _ = w.id(ref) }   // (new ones get uids, as the server's would)
    srv.set(key, w)
    (w.counter, w.boot, w.syncedAt, w.counterKind) = (v.state.counter, v.state.boot, v.state.syncedAt, v.state.counterKind)
    v.state = w
}
/// The trainer's save as the server has it.
@MainActor func served(_ v: Walker) -> Walk? { let (srv, key) = server(v); return srv.walk(key) }
/// A fight going on, on the server (its play: ours by uid, for the EXP after it) and on the walker's screen.
@MainActor func fightOn(_ v: Walker, _ b: Battle, tower: Bool = false) {
    let (srv, key) = server(v)
    srv.rows[key]?.play.battle = b; srv.rows[key]?.play.tower = tower
    srv.rows[key]?.play.party = ([-1] + v.state.caught.indices.map { -2 - $0 }).prefix(b.mine.count).compactMap { v.state.mon($0)?.uid }
    v.fight = b; v.screen = .battle(b, sel: 0); v.towerRun = tower
}
/// The beats on the LCD played out (the walker's clock run on).
@MainActor func playOut(_ v: Walker) { var n = 0; while n < 30, case .beats = v.screen { v.tick(Date() + 100); n += 1 }; drain(v) }
/// Nothing going on any more (a fight, a run, a radar): the server's play and the walker's.
@MainActor func calm(_ v: Walker) { let (srv, key) = server(v); srv.rows[key]?.play = Play(); v.dropPlay(); v.screen = .home }
