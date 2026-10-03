import Foundation
#if os(macOS)
import AppKit
#endif
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

/// 3.0's client paths on the fake server (the shared engine): what the walker sends, and what it shows of the answers.
@MainActor func actChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func isHome(_ w: Walker) -> Bool { if case .home = w.screen { return true }; return false }
    func row(_ w: Walker, _ item: String) -> Int { w.state.inventory.firstIndex(of: item) ?? -1 }

    // steps waiting go with the next act, whatever it is (W counts them)
    let ra = online({ var s = Walk(); s.watts = 50; return s }()), (rs, _) = server(ra)
    ra.cloud!.addSteps(9); ra.screen = .menu(menuAt("포켓 레이더")); ra.press(1); drain(ra)
    check(rs.acts.last == .radar && rs.steps.last == 9 && served(ra)?.total == 9, "3.0 steps: those waiting go with a radar (not only with the 15 s ones)", "\(rs.acts.suffix(2)) \(rs.steps.suffix(2))")

    // a tower run: in for 50 W, a win (streak, BP), the next trainer with no fee, then 기권
    var strong = Mon(dex: 6, level: 50, female: false); strong.known = [53]
    let tv = online({ var s = Walk(); s.watts = 100; s.companion = strong; return s }(), rng: 3)
    tv.screen = .tower(pick: nil); tv.press(1); drain(tv)
    let paid = tv.state.watts == 50 && tv.towerRun && tv.inBattle
    var near = Battle(party: [tv.state.companion], trainer: "엘리트 x", foes: [Mon(dex: 10, level: 2, female: false)]); near.theirs[0].hp = 1
    fightOn(tv, near, tower: true); tv.screen = .moves(near, sel: 0); tv.press(1); drain(tv); playOut(tv)
    let won = says(tv) == ["1연승!", "+1 BP"] && tv.state.towerStreak == 1 && tv.state.bp == 1 && tv.towerRun
    tv.press(1); let lobby: Bool = { if case .tower(nil) = tv.screen { return true }; return false }()
    tv.press(1); drain(tv); let nextFree = tv.inBattle && tv.state.watts == 50
    if let f = tv.fight { tv.screen = .battle(f, sel: tv.battleMenu(f).firstIndex(of: "기권")!); tv.press(1); tv.press(2); tv.press(1); drain(tv) }
    check(paid && won && lobby && nextFree && says(tv) == ["기권했다", "1연승에서 끝"] && !tv.towerRun && tv.state.towerStreak == 0 && !tv.inBattle,
          "3.0 tower: in for 50 W; a win → 1연승! +1 BP, the lobby; the next trainer free; 기권 ends the run", "\(paid) \(won) \(lobby) \(nextFree) \(says(tv))")

    // the bag: a candy that levels into an evolution, a vitamin, a 진화의 돌, 전부 팔기; 중복 놓아주기
    var rat = Mon(dex: 19, level: 19, female: false); rat.exp = expTable[growthRate[19]][19]
    let bv = online({ var s = Walk(); s.companion = rat; s.bag = ["이상한사탕", "타우린", "금구슬", "진주"]; return s }(), rng: 5)
    bv.screen = .items(row(bv, "이상한사탕")); bv.press(1); drain(bv)
    let candySaid = says(bv) == [monNames[19] + " Lv.20!"], noLevelNews = !bv.news.contains { if case .level = $0 { return true }; return false }
    bv.press(1); bv.screen = .home; bv.tick(Date())
    let candyEvolves: Bool = { if case .evolve(let f, let t, _) = bv.screen { return f.dex == 19 && t.dex == 20 }; return false }()
    bv.screen = .items(row(bv, "타우린")); bv.press(1); drain(bv)
    let vitamin = says(bv).last == "노력치 10" && bv.state.companion.evs?[1] == 10
    let w0 = bv.state.watts; bv.screen = .home; bv.sellAll(); drain(bv)
    let sold = bv.state.watts - w0, soldSaid = says(bv) == ["전부 팔았다", "+\(sold)W"] && sold > 0 && bv.state.count("금구슬") == 0 && bv.state.count("진주") == 0
    check(candySaid && noLevelNews && candyEvolves && vitamin && soldSaid, "3.0 bag: 이상한사탕 (its line, no second 레벨 업!), the evolution it brings at home; 타우린; 전부 팔기",
          "\(candySaid) \(noLevelNews) \(candyEvolves) \(vitamin) \(soldSaid) \(says(bv))")
    let sv = online({ var s = Walk(); s.companion = Mon(dex: 133, level: 20, female: false); s.bag = ["불꽃의돌"]; s.box = (0..<3).map { Mon(dex: 16, level: 5 + $0, female: false) }; return s }())
    sv.screen = .items(0); sv.press(1); drain(sv)
    let stoned: Bool = { if case .evolve(let f, let t, _) = sv.screen { return f.dex == 133 && t.dex == 136 }; return false }()
    sv.screen = .home; sv.releaseDupes(16); drain(sv)
    check(stoned && sv.state.count("불꽃의돌") == 0 && sv.state.companion.dex == 136 && says(sv).first == "2마리를 놓아줬다" && sv.state.box.count == 1,
          "3.0 bag: 불꽃의돌 → the server evolves 이브이, home shows it; 중복 놓아주기 (2 of 3)", "\(stoned) \(says(sv)) \(sv.state.box.count)")

    // a revive mid-fight: ours goes down, 기력의조각 brings it back, the fight goes on (no end)
    let rv = online({ var s = Walk(); s.bag = ["기력의조각"]; return s }(), rng: 7)
    var foe = Mon(dex: 150, level: 100, female: false); foe.known = [94]
    var down = Battle(wild: foe, companion: rv.state.companion); down.mine[0].hp = 1; down.mine[0].moves = [33]; down.mine[0].pp = [35]
    fightOn(rv, down); rv.screen = .moves(down, sel: 0); rv.press(1); drain(rv)
    let healed: Bool = { if case .beats(_, let bs, _, _) = rv.screen { return bs.contains { if case .heal(.me, _, _) = $0 { return true }; return false } }; return false }()
    playOut(rv)
    check(healed && rv.inBattle && rv.fightEnd == nil && rv.state.count("기력의조각") == 0 && server(rv).0.rows[server(rv).1]?.play.battle != nil,
          "3.0 fight: ours goes down with 기력의조각 in the bag — back up, the fight goes on (no end)", "\(healed) \(rv.screen)")

    // steps piled up offline, more than the allowance: the server takes some (taken), the rest are gone; the walker shows the server's
    let ov = online(Walk()), (os, _) = server(ov)
    os.stepCap = 100; ov.cloud!.addSteps(500); ov.cloud!.saveNow(); drain(ov)
    check(served(ov)?.total == 100 && ov.state.total == 100 && ov.cloud!.ahead == 0, "3.0 steps: more than the allowance — the server takes what it allows (taken), the rest aren't sent again", "\(served(ov)?.total ?? -1) \(ov.state.total)")

    // another PC takes the trainer mid-fight: locked, the fight dropped; 여기서 계속 → a new session, nothing going on
    let pv = online(Walk()), (ps, pk) = server(pv)
    fightOn(pv, Battle(wild: Mon(dex: 16, level: 3, female: false), companion: pv.state.companion))
    _ = ps.answer("v1/login", ["id": pk, "device": "another", "force": true]); pv.cloud!.addSteps(1); pv.cloud!.saveNow(); drain(pv)
    let lockedOut = pv.frozen && !pv.inBattle && pv.fight == nil
    pv.press(1); drain(pv)
    check(lockedOut && !pv.frozen && !pv.inBattle && ps.rows[pk]?.play.battle == nil && isHome(pv), "3.0 session: another PC mid-fight → locked, the fight dropped; 여기서 계속: a new session, nothing going on")

    // 포켓몬's grid: a Pokémon dragged between the walker's row and the box — what a press carries, where it lands, the act it makes
    let dv = online({ var s = Walk(); s.caught = [Mon(dex: 16, level: 5, female: false)]; s.box = [Mon(dex: 19, level: 7, female: false), Mon(dex: 41, level: 9, female: false)]; return s }())
    dv.screen = .box(-1, act: nil, confirm: false)
    let carries = [4500, 4501, 4502, 10000, 10002].map(dv.dragsFrom), lands = [(10000, 4501), (10000, 4520), (4501, 4520), (4501, 4502), (4501, 4500), (10000, 4500)].map { dv.canDrop($0.0, $0.1) }
    #if os(macOS)
    let sideV = SideView(); sideV.walker = dv; sideV.frame = NSRect(x: 0, y: 0, width: Layout.w * K, height: 700); dv.refreshPane(Date(), force: true)
    if let rep = sideV.bitmapImageRepForCachingDisplay(in: sideV.bounds) { sideV.cacheDisplay(in: sideV.bounds, to: rep) }
    let dropCodes = sideV.art.drops.map(\.1)
    #else
    let dropCodes = [4500, 4501, 4502, 4503, 4520]
    #endif
    let toWalker = dv.state.box[dv.boxOrder[0]].dex, acts0 = server(dv).0.acts.count
    dv.gridDrop(10000, nil); let nowhere = server(dv).0.acts.count == acts0 && dv.drag == nil
    dv.gridDrop(10000, 4502); drain(dv); let fetched = dv.state.caught.contains { $0.dex == toWalker } && says(dv).last == "워커로 데려왔다"
    dv.screen = .box(-1, act: nil, confirm: false); let k16 = dv.state.caught.firstIndex { $0.dex == 16 }!
    dv.gridDrop(4501 + k16, 4520); drain(dv); let stored = dv.state.box.contains { $0.dex == 16 } && !dv.state.caught.contains { $0.dex == 16 } && says(dv).last == "상자로 보냈다"
    dv.screen = .box(-1, act: nil, confirm: false); let j41 = dv.boxOrder.firstIndex { dv.state.box[$0].dex == 41 }!
    dv.gridDrop(10000 + j41, 4500); drain(dv); let paired = dv.state.companion.dex == 41 && says(dv).last == "함께 걷는다!" && { if case .say(_, .box(-1, nil, false, false), _) = dv.screen { return true }; return false }()
    check(carries == [false, true, false, true, false] && lands == [true, false, true, false, true, true] && dropCodes == [4500, 4501, 4502, 4503, 4520] && nowhere && fetched && stored && paired,
          "포켓몬 drag: the walker's and the box's can be carried (not the companion); dropped on the walker's row = 워커로, on the box = 상자로, on the companion = 함께; nowhere = nothing",
          "\(carries) \(lands) \(dropCodes) \(nowhere) \(fetched) \(stored) \(paired)")
    serve(dv) { $0.caught = [Mon(dex: 16, level: 5, female: false), Mon(dex: 19, level: 5, female: false), Mon(dex: 21, level: 5, female: false)] }; dv.screen = .box(-1, act: nil, confirm: false)
    check(!dv.canDrop(10000, 4501) && dv.canDrop(4501, 4520), "… the walker full (3): the box's can't land on its row")

    // 도구: the wheel and ↑ ↓ move the row (as the shop's); 팔 수 있는 것 전부 팔기 from its header; 코스: 잡음 n/m on the open ones
    let iv = online({ var s = Walk(); s.bag = ["상처약", "금구슬", "진주", "이상한사탕", "타우린", "해독제", "큰진주"]; s.owned = [16, 25]; return s }())
    iv.screen = .items(0); iv.listRow(1); let wheel = { if case .items(1) = iv.screen { return true }; return false }()
    _ = iv.key(.down); _ = iv.key(.down); let down2 = { if case .items(3) = iv.screen { return true }; return false }()
    _ = iv.key(.pageDown); let paged = { if case .items(6) = iv.screen { return true }; return false }(); _ = iv.key(.up)
    let ups = { if case .items(5) = iv.screen { return true }; return false }(); iv.listRow(-99); let top = { if case .items(0) = iv.screen { return true }; return false }()
    let sellW = iv.paneContent(Date()).items?.sellAll ?? 0, iw0 = iv.state.watts
    iv.pageTap(5711); drain(iv)
    let soldAll = iv.state.watts == iw0 + sellW && ["금구슬", "진주", "큰진주"].allSatisfy { iv.state.count($0) == 0 } && iv.state.count("상처약") == 1 && says(iv) == ["전부 팔았다", "+\(sellW)W"]
        && { if case .say(_, .items(0), _) = iv.screen { return true }; return false }() && iv.paneContent(Date()).items?.sellAll == nil
    check(wheel && down2 && paged && ups && top && sellW > 0 && soldAll, "도구: the wheel and ↑ ↓ / page keys move the row; 팔 수 있는 것 전부 팔기 sells only those (W as shown), back to the list; none left: no button",
          "\(wheel) \(down2) \(paged) \(ups) \(top) \(sellW) \(soldAll) \(iv.screen)")
    iv.screen = .course(0); let rows = iv.paneContent(Date()).course?.rows ?? []
    let first = iv.courseSpecies(0), mine = first.filter { [16, 25].contains($0) }.count
    check(rows.first?.note == "잡음 \(mine)/\(first.count)" && rows.filter { !$0.open }.allSatisfy { !$0.note.hasPrefix("잡음") } && rows.contains { !$0.open },
          "코스: an open course says 잡음 n/m (of what walks there, as the 도감's 이 코스 tab); a locked one still says what opens it", "\(rows.map(\.note))")

    // home's news: an egg found, its hatch, a new season
    let nv = online(Walk())
    nv.news = [.egg(dex: 175, left: 100), .hatch(mon: Mon(dex: 175, level: 1, female: false)), .season(to: 1)]; nv.screen = .home; nv.tick(Date())
    let egg = says(nv).last == "포켓몬의 알"; nv.press(1)
    let hatch: Bool = { if case .hatch(let m, _) = nv.screen { return m.dex == 175 }; return false }()
    nv.tick(Date() + 6)
    check(egg && hatch && says(nv) == ["여름이 왔다!"], "3.0 home: an egg found, its hatch's show, the season — in order", "\(egg) \(hatch) \(says(nv))")
    return c
}
