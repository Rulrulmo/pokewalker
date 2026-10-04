import Foundation
#if os(macOS)
import AppKit
#endif
// The self-test's walkers on the fake server (Core/Cloud.swift's FakeCloud, the shared engine behind it): 3.0's walker changes nothing by
// itself, so a test gives it a trainer there, logged in, and lets its acts come back (drain).

@MainActor var onlineCount = 0
/// A walker logged into a fake server whose trainer has this save (each Pokémon given a uid, as the server does). host: a TestHost by default.
/// 3.8.1's picker (page one): a first click looks at a cell (the card above), a click on the one looked at picks or drops it.
@MainActor func pickAt(_ w: Walker, _ k: Int) { if case .squad(let q) = w.screen, q.at != k { w.pageTap(8750 + k) }; w.pageTap(8750 + k) }
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
    bv.screen = .items(row(bv, "이상한사탕")); bv.press(1); bv.press(1); drain(bv)                 // (3.6: who gets it — the companion, picked already; ● uses it)
    let candySaid = says(bv) == [monNames[19] + " Lv.20!"], noLevelNews = !bv.news.contains { if case .level = $0 { return true }; return false }
    bv.press(1); bv.screen = .home; bv.tick(Date())
    let candyEvolves: Bool = { if case .evolve(let f, let t, _) = bv.screen { return f.dex == 19 && t.dex == 20 }; return false }()
    bv.screen = .items(row(bv, "타우린")); bv.press(1); bv.press(1); drain(bv)
    let vitamin = says(bv).last == "노력치 10" && bv.state.companion.evs?[1] == 10
    let w0 = bv.state.watts; bv.screen = .home; bv.sellAll(); drain(bv)
    let sold = bv.state.watts - w0, soldSaid = says(bv) == ["전부 팔았다", "+\(sold)W"] && sold > 0 && bv.state.count("금구슬") == 0 && bv.state.count("진주") == 0
    check(candySaid && noLevelNews && candyEvolves && vitamin && soldSaid, "3.0 bag: 이상한사탕 (its line, no second 레벨 업!), the evolution it brings at home; 타우린; 전부 팔기",
          "\(candySaid) \(noLevelNews) \(candyEvolves) \(vitamin) \(soldSaid) \(says(bv))")
    let sv = online({ var s = Walk(); s.companion = Mon(dex: 133, level: 20, female: false); s.bag = ["불꽃의돌"]; s.box = (0..<3).map { Mon(dex: 16, level: 5 + $0, female: false) }; return s }())
    sv.screen = .items(0); sv.press(1); sv.press(1); drain(sv)
    let stoned: Bool = { if case .evolve(let f, let t, _) = sv.screen { return f.dex == 133 && t.dex == 136 }; return false }()
    sv.screen = .home; sv.releaseDupes(16); drain(sv)
    check(stoned && sv.state.count("불꽃의돌") == 0 && sv.state.companion.dex == 136 && says(sv).first == "2마리를 놓아줬다" && sv.state.box.count == 1,
          "3.0 bag: 불꽃의돌 → the server evolves 이브이, home shows it; 중복 놓아주기 (2 of 3)", "\(stoned) \(says(sv)) \(sv.state.box.count)")

    // 3.6 (docs/plans/13): no revive by itself — ours goes down with 기력의조각 in the bag: the fight's lost, the 기력의조각 stays (revives: by hand, on the bench)
    let rv = online({ var s = Walk(); s.bag = ["기력의조각"]; return s }(), rng: 7)
    var foe = Mon(dex: 150, level: 100, female: false); foe.known = [94]
    var down = Battle(wild: foe, companion: rv.state.companion); down.mine[0].hp = 1; down.mine[0].moves = [33]; down.mine[0].pp = [35]
    fightOn(rv, down); rv.screen = .moves(down, sel: 0); rv.press(1); drain(rv); playOut(rv)
    check(!rv.inBattle && rv.state.count("기력의조각") == 1 && server(rv).0.rows[server(rv).1]?.play.battle == nil,
          "3.6 fight: ours goes down with 기력의조각 in the bag — no revive by itself: the fight's over, the 기력의조각 stays", "\(rv.screen)")

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

    // 12 (M1): the team — its order and ranks, a card's 인사 (the other side's hello, its companion on home), a teammate dropping by
    let tsv = FakeCloud()
    let ta = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 30, female: false); s.today = 500; return s }(), server: tsv)
    let tb = online({ var s = Walk(); s.companion = Mon(dex: 6, level: 52, female: false); s.today = 900; return s }(), server: tsv)
    for k in 0..<12 { var w = Walk(); w.companion = Mon(dex: 16 + k, level: 10, female: false); w.today = 100 * k; w.owned = Array(1...(10 + k)); w.towerBest = k; tsv.add("팀원\(k)", w) }
    for k in 0..<12 { tsv.befriend(ta.myName, "팀원\(k)") }; tsv.befriend(ta.myName, tb.myName)   // (3.5: the list is me and my friends)
    tb.cloud!.addSteps(3); tb.cloud!.saveNow(); drain(tb)                                         // tb acted just now: walking
    ta.cloud!.teamDue = true; ta.screen = .menu(menuAt("친구")); ta.press(1); drain(ta)          // (its list from its login is under 10 s old: fetched again here)
    let tRows = ta.teamRows(0), ranks = ta.teamRows(2), opened: Bool = { if case .team(0, 0, false) = ta.screen { return true }; return false }()
    let bName = tb.myName, aName = ta.myName
    check(opened && tRows.first?.card.name.lowercased() == bName.lowercased() && tRows.count == 14 && ranks.count == 11 && ranks.last.map { ta.isMe($0.card) } == true && ranks.first?.rank == 1
          && ta.paneContent(Date()).team?.rows.count == TeamModel.perPage,
          "팀: the menu's tile lists everyone (walking now first); a rank tab: the top 10 and me", "\(tRows.map(\.card.name)) \(ranks.count)")
    let bi = tRows.firstIndex { $0.card.name.lowercased() == bName.lowercased() } ?? 0
    ta.screen = .team(sel: bi, tab: 0, card: false); ta.pageTap(6010 + bi % TeamModel.perPage); let cardUp: Bool = { if case .team(bi, 0, true) = ta.screen { return true }; return false }()
    let tActs0 = tsv.acts.count; ta.pageTap(6030); ta.press(1); drain(ta)
    let stays: Bool = { if case .team(bi, 0, true) = ta.screen { return true }; return false }()
    check(cardUp && stays && tsv.acts.count == tActs0 && says(ta).isEmpty, "팀: a click on the pick opens its card; 3.8.1: no 인사 there (its old click, ●: nothing sent)", "\(cardUp) \(ta.screen)")
    ta.screen = .home; _ = ta.cloud!.act(.greet(to: bName)); drain(ta)                               // (an older app's 인사 still goes)
    tb.screen = .home; tb.cloud!.addSteps(1); tb.cloud!.saveNow(); drain(tb); tb.tick(Date())
    let unshown: Bool = { if case .home = tb.screen { return true }; return false }()
    check(unshown && tsv.acts.contains(.greet(to: bName)) && tb.news.isEmpty, "3.8.1: an older app's 인사 (hello) comes and goes unshown — no line, no sticker, no banner", "\(tb.screen)")
    tb.cloud!.addSteps(1); tb.cloud!.saveNow(); drain(tb); ta.cloud!.teamDue = true; drain(ta)       // (tb walking again)
    ta.screen = .home
    for k in 0..<6 { ta.state.total += 700; ta.tick(Date() + Double(k)) }
    check(says(ta).isEmpty && ta.cloud!.team?.cards.contains { Walker.walkingNow($0) && !ta.isMe($0) } == true,
          "3.8.1: no random drop-by (a friend walking now, thousands of steps on home)", "\(says(ta))")

    // home's news: an egg found, its hatch, a new season
    let nv = online(Walk())
    nv.news = [.egg(dex: 175, left: 100), .hatch(mon: Mon(dex: 175, level: 1, female: false)), .season(to: 1)]; nv.screen = .home; nv.tick(Date())
    let egg = says(nv).last == "포켓몬의 알"; nv.press(1)
    let hatch: Bool = { if case .hatch(let m, _) = nv.screen { return m.dex == 175 }; return false }()
    nv.tick(Date() + 6)
    check(egg && hatch && says(nv) == ["여름이 왔다!"], "3.0 home: an egg found, its hatch's show, the season — in order", "\(egg) \(hatch) \(says(nv))")
    return c
}

/// 12 §3 (M2): 교환 between two trainers on one fake server — an offer made from a teammate's card (their box, then mine), its news and its
/// page on the other side, 수락 (both evolve by trade at their new trainers, 어버이), the offerer's save on its next act; a 아무거나 one answered
/// from my box (금속코트 from the giver's bag); 거절 and 거두기 heard; a tower run kept through a new session.
@MainActor func tradeChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func act(_ w: Walker) { w.screen = .home; w.cloud!.addSteps(1); w.cloud!.saveNow(); drain(w); drain(w) }   // its next act (steps): what came for it (and the reads after)
    let sv = FakeCloud(), ha = TestHost(), hb = TestHost()
    let ta = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 30, female: false)
                      s.box = [Mon(dex: 93, level: 25, female: false), Mon(dex: 19, level: 5, female: false), Mon(dex: 16, level: 5, female: false)]; return s }(), server: sv, host: ha)
    let tb = online({ var s = Walk(); s.companion = Mon(dex: 6, level: 52, female: false); s.bag = ["금속코트"]
                      s.box = [Mon(dex: 64, level: 20, female: false), Mon(dex: 95, level: 20, female: false), Mon(dex: 129, level: 10, female: false)]; return s }(), server: sv, host: hb)
    let aName = ta.myName, bName = tb.myName
    sv.befriend(aName, bName); act(tb); ta.cloud!.teamDue = true; drain(ta)
    let bi = ta.teamRows(0).firstIndex { $0.card.name.lowercased() == bName.lowercased() } ?? 0
    ta.screen = .team(sel: bi, tab: 0, card: true); let card = ta.paneContent(Date()).teamCard
    ta.startTrade(bName); drain(ta)                                                              // (3.5: the 게시판 replaces 1:1 offers; their screens stay for offers sent from 3.4)
    let opened: Bool = { if case .trade(.pick(let p)) = ta.screen { return p.side == 1 && p.to == bName }; return false }()
    let theirs = ta.pickList({ if case .trade(.pick(let p)) = ta.screen { return p }; return TradePick(to: bName) }())
    check(card?.remove == true && opened && theirs.map(\.dex) == [64, 95, 129] && ta.paneContent(Date()).pick?.any == true,
          "교환 신청 (a teammate's card) → their box, from the server (/v2/box), by number; 아무거나 on until one is picked", "\(String(describing: card?.remove)) \(opened) \(theirs.map(\.dex))")
    ta.pageTap(6150); let afterWant = ta.paneContent(Date()).pick
    let k = ta.myTradeBox.firstIndex { $0.dex == 93 } ?? 0; ta.pageTap(6150 + k); let ready = ta.paneContent(Date()).pick
    check(afterWant?.theirs.dex == 64 && afterWant?.side == 0 && afterWant?.go == nil && ready?.mine.dex == 93 && ready?.go == "교환 신청",
          "a click on theirs picks it (윤겔라) and turns to my box; a click on mine (고우스트): 교환 신청 lights up", "\(String(describing: afterWant)) \(String(describing: ready?.go))")
    let actsHeld = sv.acts.count; _ = ta.key(.enter, held: true); _ = ta.key(.enter, held: true)
    check(sv.acts.count == actsHeld && { if case .trade(.pick) = ta.screen { return true }; return false }(), "a held return on the pick sends nothing (only a fresh press does)")
    ta.pageTap(6190); drain(ta); drain(ta)
    check(says(ta) == [bName + "에게", "교환을 신청했다!"] && sv.offers.count == 1 && ta.cloud!.trades?.outgoing.count == 1 && ta.tradeRows.first.map(ta.mineOffer) == true,
          "교환 신청 → the server's offer; it's on my list (보냄)", "\(says(ta)) \(sv.offers.count)")
    let id = sv.offers.first?.o.id ?? -1
    act(tb)
    let offerSaid = says(tb) == [josa(aName, "이", "가") + " 교환을 신청했다!", "고우스트 Lv.25"]
    let goesToOffer: Bool = { if case .say(_, .trade(.offer(id, nil)), _) = tb.screen { return true }; return false }()
    tb.press(1); let page = tb.paneContent(Date()).offer
    check(offerSaid && goesToOffer && page?.give.dex == 64 && page?.get.dex == 93 && page?.buttons == ["수락", "거절"] && page?.mon.nature.isEmpty == false && tb.tradesIn == 1,
          "the other side's next act brings the offer: said, then its page — 윤겔라 ⇄ 고우스트, the one I'd get in full, 수락 · 거절", "\(says(tb)) \(String(describing: page))")
    tb.pageTap(6130); drain(tb)
    let show: Bool = { if case .traded(let g, let got, let with, _) = tb.screen { return g.dex == 64 && got.dex == 93 && with.lowercased() == aName.lowercased() }; return false }()
    tb.tick(Date() + 7); let evo: Bool = { if case .evolve(let f, let t, _) = tb.screen { return f.dex == 93 && t.dex == 94 }; return false }()
    let ghost = tb.state.box.first { $0.dex == 94 }
    check(hb.asked.last == "교환할까요?" && show && evo && ghost?.ot?.lowercased() == aName.lowercased() && !tb.state.box.contains { $0.dex == 64 } && tb.tradesIn == 0,
          "수락 (asked once: no undo) → the server swaps both: the trade's show, then 고우스트 evolves at its new trainer (팬텀, 어버이 the giver)", "\(hb.asked) \(show) \(evo) \(String(describing: ghost?.ot))")
    if let gi = tb.state.box.firstIndex(where: { $0.dex == 94 }) { tb.screen = .box(gi, act: nil, confirm: false, detail: true) }
    check(tb.title().meta == "어버이: " + aName, "a traded Pokémon's page says where it came from (어버이)", tb.title().meta)
    act(ta); ta.tick(Date() + 7)
    let alakazam = ta.state.box.first { $0.dex == 65 }
    check(alakazam?.ot?.lowercased() == bName.lowercased() && !ta.state.box.contains { $0.dex == 93 } && served(ta)?.box.count == ta.state.box.count && ta.cloud!.trades?.outgoing.isEmpty == true,
          "the offerer's next act brings its new save (the walk, with traded): 윤겔라 came and evolved (후딘, 어버이 B)", "\(ta.state.box.map(\.dex)) \(String(describing: alakazam?.ot))")

    // 아무거나: answered from my box — 롱스톤 given while 금속코트 is in the giver's bag → 강철톤 at the receiver, the item gone from the giver
    ta.screen = .home; ta.startTrade(bName); drain(ta); ta.pageTap(6142)
    let rattata = ta.myTradeBox.firstIndex { $0.dex == 19 } ?? 0; ta.screen = { if case .trade(.pick(var p)) = ta.screen { p.side = 0; return .trade(.pick(p)) }; return ta.screen }()
    ta.pageTap(6150 + rattata); let anyGo = ta.paneContent(Date()).pick?.go; ta.pageTap(6190); drain(ta)
    act(tb); let id2 = sv.offers.last?.o.id ?? -1; tb.screen = .trade(.offer(id: id2, act: nil)); tb.pageTap(6130)
    let answering: Bool = { if case .trade(.pick(let p)) = tb.screen { return p.offer == id2 && p.side == 0 }; return false }()
    let onix = tb.myTradeBox.firstIndex { $0.dex == 95 } ?? 0; tb.pageTap(6150 + onix); let ans = tb.paneContent(Date()).pick; tb.pageTap(6190); drain(tb)
    act(ta); ta.tick(Date() + 7)
    check(anyGo == "교환 신청 (아무거나)" && answering && ans?.go == "이 포켓몬으로 교환" && ans?.theirs.dex == 19 && ta.state.box.contains { $0.dex == 208 } && tb.state.count("금속코트") == 0
          && tb.state.box.contains { $0.dex == 19 },
          "아무거나: the receiver's 수락 picks from its own box; 롱스톤 → 강철톤 at the offerer (금속코트 left the giver's bag)", "\(String(describing: anyGo)) \(answering) \(String(describing: ans?.go)) \(ta.state.box.map(\.dex))")

    // 거절 and 거두기: the other side hears; a Pokémon already offered isn't offered twice
    let pidgey = ta.state.box.first { $0.dex == 16 }?.uid ?? -1, carp = tb.state.box.first { $0.dex == 129 }?.uid
    _ = ta.cloud!.act(.tradeOffer(to: bName, give: pidgey, want: carp)); drain(ta); act(tb)
    let id3 = sv.offers.last?.o.id ?? -1; tb.screen = .trade(.offer(id: id3, act: nil)); tb.pageTap(6131); drain(tb)
    let declined = says(tb) == [josa(aName, "의", "의") + " 신청을", "거절했다"]; act(ta)
    check(declined && says(ta).isEmpty && !(ta.cloud!.trades?.outgoing ?? []).contains { $0.id == id3 }, "거절: said here; the offerer's next act brings it quietly (3.8: no screen, its list updated)", "\(says(ta))")
    _ = ta.cloud!.act(.tradeOffer(to: bName, give: pidgey, want: nil)); drain(ta)
    ta.startTrade(bName); drain(ta); ta.screen = { if case .trade(.pick(var p)) = ta.screen { p.side = 0; return .trade(.pick(p)) }; return ta.screen }()
    ta.pageTap(6150 + (ta.myTradeBox.firstIndex { $0.dex == 16 } ?? 0)); let twice = says(ta)
    ta.screen = .trade(.list(0)); ta.pageTap(6110); ta.pageTap(6110); let mine = ta.paneContent(Date()).offer?.buttons; ta.pageTap(6132); drain(ta)
    let tookBack = says(ta) == ["교환 신청을", "거뒀다"]; act(tb)
    check(twice == ["이미 교환에", "걸어 둔 포켓몬이에요"] && mine == ["거두기"] && tookBack && says(tb).isEmpty,
          "one already offered is dimmed and said so; my offer's page has 거두기 → the other side hears it quietly", "\(twice) \(String(describing: mine)) \(says(tb))")
    ta.screen = .home; ta.act(.tradeOffer(to: bName, give: ta.state.companion.uid ?? 0, want: nil), back: .home); drain(ta)
    check(says(ta) == ["상자의 포켓몬만", "교환할 수 있어요"], "the server's refusal is said (the companion isn't in the box)", "\(says(ta))")

    // a tower run between fights goes on through a new session (an update's restart); with a fight on it ends
    let (_, ak) = server(ta)
    sv.rows[ak]?.play.tower = true; ta.towerRun = true; ta.screen = .home
    let free = ta.installBlocker == nil && ta.cloud!.keepsRuns
    func relaunch() -> Walker {
        let c2 = Cloud(link: sv, dir: ta.cloud!.dir), v = Walker(state: Walk()); v.persist = false; v.host = TestHost(); v.startCloud(c2); drain(v); return v
    }
    let re = relaunch()
    check(free && re.towerRun && sv.rows[ak]?.play.tower == true, "a tower run between fights doesn't hold an update back: a new session keeps it (the login says so)", "\(free) \(re.towerRun)")
    fightOn(re, Battle(wild: Mon(dex: 16, level: 50, female: false), companion: re.state.companion), tower: true)
    let held = re.installBlocker == "배틀이 끝나면", re2 = relaunch()
    check(held && !re2.towerRun && sv.rows[ak]?.play.tower == false, "… a fight on still holds it; a new session mid-fight ends the run", "\(held) \(re2.towerRun)")
    return c
}

/// 12 §4 (M3): the co-op raid on one fake server — the menu's tile and the lobby (/v2/raid), a fight on the battle screens (후퇴, no ball,
/// the boss's bars on the HUD), its damage said; the clearing hit (its reply says so), the other fighter's raidCleared, the balls (the first
/// with the week's reward), and what's refused.
@MainActor func raidChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func lobby(_ w: Walker) { w.screen = .menu(menuAt("레이드")); w.press(1); drain(w); drain(w) }
    /// The fight played to its end: 공격 with the first move each turn (후퇴 if asked), the beats run out.
    func fightOut(_ w: Walker, retreat: Bool = false) {
        var n = 0
        while n < 60, w.inBattle || { if case .beats = w.screen { return true }; return false }() {
            n += 1
            switch w.screen {
            case .beats: playOut(w)
            case .battle(let b, _): w.screen = .battle(b, sel: retreat ? w.battleMenu(b).count - 1 : 0); w.press(1); drain(w)
            case .moves(let b, _): w.screen = .moves(b, sel: b.mine[b.me].pp.firstIndex { $0 > 0 } ?? 0); w.press(1); drain(w)   // (루기아's 프레셔: 2 PP a use)
            case .party(let b, _): w.screen = .party(b, sel: b.mine.indices.first { b.mine[$0].alive } ?? 0); w.press(1); drain(w)
            case .say: w.press(1)
            default: n = 60
            }
        }
    }
    let sv = FakeCloud(); sv.raidOpen(1_000_000)
    func strong() -> Walk { var s = Walk(); s.companion = Mon(dex: 150, level: 100, female: false); s.caught = [Mon(dex: 149, level: 100, female: false), Mon(dex: 248, level: 100, female: false)]; return s }
    let cost = Engine.raidPowerCost, per = "(\(cost.formatted())걸음마다 1칸)"                     // (3.8: 10,000 a 칸)
    let ra = online({ var s = strong(); s.raidPower = 2 * cost + cost / 2; return s }(), server: sv)
    let rb = online({ var s = strong(); s.raidPower = cost + cost / 2; return s }(), server: sv)
    let rc = online({ var s = Walk(); s.raidPower = cost * 2 / 5; return s }(), server: sv)
    lobby(ra); let pane = ra.paneContent(Date()).raid
    let opened: Bool = { if case .raid(0) = ra.screen { return true }; return false }()
    check(opened && pane?.boss == "루기아 Lv.70" && pane?.go == "도전 · 파워 1칸" && pane?.powerText == "다음 칸까지 \((cost / 2).formatted())걸음" && pane?.hpText.hasPrefix("100% · 줄") == true && ra.raidNote == "파워 2칸 · 루기아",
          "레이드 (the menu's tile) → the lobby from the server: the boss, the team's HP, my power in 칸, 도전", "\(String(describing: pane))")
    lobby(rc); let weak = rc.paneContent(Date()).raid; rc.press(1)
    check(weak?.go == nil && weak?.hint == "파워가 부족해요 " + per && says(rc) == ["파워가 부족하다", per], "under 1칸 of power: no 도전, and ● says why", "\(String(describing: weak?.hint)) \(says(rc))")

    // rb: who goes (3.8: the tower's three offered, one dropped), in, and 후퇴 at once (it still fought this week)
    lobby(rb); rb.pageTap(7010); let offered = rb.paneContent(Date()).squad; rb.pageTap(8742); let two = rb.paneContent(Date()).squad
    let fewer = rb.state.party().count
    rb.pageTap(8790); drain(rb)
    let fought2 = (rb.fight?.mine.count ?? 0) == 2
    check(offered?.title == "레이드 출전" && offered?.strip.count == 3 && offered?.strip.compactMap { $0?.level } == ["Lv.100", "Lv.100", "Lv.100"] && offered?.go == "이 3마리로 도전" && two?.go == "이 2마리로 도전" && fewer == 3 && fought2,
          "3.8: 도전 → who goes (1–3, the tower's three offered at their own levels); one dropped → those two fight", "\(String(describing: offered)) \(String(describing: two?.go)) \(fought2)")
    var menu: [String] = [], title = ("", "")
    while case .beats = rb.screen { playOut(rb) }
    if case .battle(let b, _) = rb.screen { menu = rb.battleMenu(b); title = rb.title() }
    let hud = rb.raidOn && served(rb)?.raidPower == cost / 2
    fightOut(rb, retreat: true)
    let retreated = says(rb).first == "0 데미지!"; let back: Bool = { if case .say(_, .raid(0), _) = rb.screen { return true }; return false }()
    check(menu == ["공격", "도구", "교체", "후퇴"] && title.0 == "레이드 배틀" && title.1.hasPrefix("남은 줄 3 / 3") && hud && retreated && back && !rb.raidOn && sv.raidFights.count == 1,
          "도전 → the raid on the battle screens (1칸 spent; 공격 · 도구 · 교체 · 후퇴, no ball; 레이드 배틀 · 남은 줄); 후퇴 → 0 데미지, back to the lobby", "\(menu) \(title) \(hud) \(says(rb))")

    // ra: the hit that clears it (its own reply says so)
    sv.raidLeft = 40
    ra.screen = .raid(tab: 0); ra.pageTap(7010); ra.pageTap(8790); drain(ra); fightOut(ra)
    let clearedSaid = says(ra) == ["40 데미지!" + (ra.state.bp ?? 0 > 0 ? " +\(ra.state.bp ?? 0)BP" : ""), "보스를 쓰러뜨렸다!", "볼을 던질 수 있다"] || (says(ra).first?.hasPrefix("40 데미지!") == true && says(ra).dropFirst().first == "보스를 쓰러뜨렸다!")
    check(clearedSaid && sv.raidLeft == 0 && sv.raidDealt.values.contains(40) && !ra.news.contains { if case .raidCleared = $0 { return true }; return false },
          "the clearing fight: its damage (up to what was left) and 보스를 쓰러뜨렸다! said at its end, not again at home", "\(says(ra)) \(sv.raidLeft)")
    rb.screen = .home; rb.cloud!.addSteps(1); rb.cloud!.saveNow(); drain(rb)
    let toLobby: Bool = { if case .say(_, .raid(0), _) = rb.screen { return true }; return false }()
    check(says(rb) == ["팀이 루기아를", "쓰러뜨렸다!", "볼을 던질 수 있다"] && toLobby, "the other fighter's next act brings raidCleared: said, then the lobby", "\(says(rb))")

    // the balls: the first misses (with the week's reward), the next catches it
    lobby(ra); let ballGo = ra.paneContent(Date()).raid?.go; let bp0 = ra.state.bp ?? 0, candy0 = ra.state.count("이상한사탕")
    sv.raidOdds = [false, true]; ra.pageTap(7010); drain(ra)
    let thrown: Bool = { if case .beats(_, let bs, _, _) = ra.screen { return bs.last == .broke }; return false }()
    playOut(ra); let missed = says(ra); ra.press(1); let reward = says(ra)
    check(ballGo == "볼 던지기" && thrown && missed.first == "놓쳤다..." && reward.first == "클리어 보상!" && (ra.state.bp ?? 0) == bp0 + 25 && ra.state.count("이상한사탕") == candy0 + 5 && ra.state.count("은색병뚜껑") == 1,
          "볼 던지기: the throw on the battle stage; missed — then the week's reward (25BP · 이상한사탕 ×5 · 은색병뚜껑)", "\(String(describing: ballGo)) \(thrown) \(missed) \(reward)")
    lobby(ra); let left = ra.paneContent(Date()).raid?.go; ra.pageTap(7010); drain(ra); playOut(ra)
    let caught = says(ra) == ["루기아를 잡았다!", "상자로 보냈다"] && ra.state.box.contains { $0.dex == 249 && $0.level == 70 }
    lobby(ra); let done = ra.paneContent(Date()).raid
    check(left?.hasPrefix("볼 던지기 · 남은") == true && caught && done?.go == nil && done?.hint == "루기아를 잡았어요!" && ra.raidNote == "이번 주 보스 쓰러뜨림",
          "the next ball catches it (into the box); then the lobby says so and offers nothing", "\(String(describing: left)) \(says(ra)) \(String(describing: done?.hint))")
    lobby(rc); let notFought = rc.paneContent(Date()).raid?.hint; rc.press(3)
    let menuBack: Bool = { if case .menu(let i) = rc.screen { return i == menuAt("레이드") }; return false }()
    check(notFought == "이번 주에 싸워야 잡을 수 있어요" && menuBack, "one who didn't fight this week can't throw; ↩ → the menu", "\(String(describing: notFought))")
    ra.screen = .raid(tab: 1); let recent = ra.paneContent(Date()).raid?.rows ?? []
    check(recent.count == 2 && recent.first?.value.hasPrefix("40 ·") == true && recent.allSatisfy { $0.dex != nil }, "최근 공격: the last fights (their lead, damage, when)", "\(recent)")
    return c
}

/// 12 §2.4 · 3.3 (3.5): 친구 and the 교환 게시판 on one fake server — a request by ID (the box), its news and the 신청 tab (수락), the list
/// then holding each other (and 인사 only to friends), a request taken back, 거절, 친구 끊기; a post with wished species, an offer on it from
/// another's page, the poster's news and pick (both evolve by trade), a second offer closed, 거두기 and 내리기 heard.
@MainActor func socialChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func act(_ w: Walker) { w.news = []; w.screen = .home; w.cloud!.addSteps(1); w.cloud!.saveNow(); drain(w); drain(w) }   // (news from before, still waiting for home, cleared: this act's come first)
    func list(_ w: Walker) { w.cloud!.teamDue = true; drain(w); drain(w) }
    let sv = FakeCloud(), ha = TestHost(), hb = TestHost()
    let fa = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 30, female: false); s.seen = [25, 64, 93, 19]
                      s.box = [Mon(dex: 93, level: 25, female: false), Mon(dex: 19, level: 5, female: false)]; return s }(), server: sv, host: ha)
    let fb = online({ var s = Walk(); s.companion = Mon(dex: 6, level: 52, female: false)
                      s.box = [Mon(dex: 64, level: 20, female: false), Mon(dex: 129, level: 10, female: false)]; return s }(), server: sv, host: hb)
    let fc = online(Walk(), server: sv)
    let aName = fa.myName, bName = fb.myName, cName = fc.myName
    list(fa); fa.screen = .team(sel: 0, tab: 0, card: false); let alone = fa.teamRows(0).count, note = fa.paneContent(Date()).team?.note
    fa.screen = .menu(menuAt("친구")); fa.press(1); drain(fa); fa.pageTap(6004); ha.texts = [bName]; fa.pageTap(6240); drain(fa)
    check(alone == 1 && note == "아직 친구가 없어요" && says(fa) == [josa(bName, "에게", "에게"), "친구 신청을 했다!"] && sv.friendAsks[bName.lowercased()]?.contains(aName.lowercased()) == true,
          "친구: only me at first; 신청 → ID로 친구 신청 (the box) → the server's request", "\(alone) \(String(describing: note)) \(says(fa))")
    list(fa); let sent = fa.paneContent(Date()).friendReqs?.rows
    act(fb); let heard = says(fb) == [josa(aName, "이", "가") + " 친구 신청을 했다!"]
    let toTab: Bool = { if case .say(_, .team(_, 4, false), _) = fb.screen { return true }; return false }()
    fb.press(1); list(fb); let req = fb.paneContent(Date()).friendReqs; fb.pageTap(6200); drain(fb)
    check(sent == [.init(name: bName, mine: true)] && heard && toTab && req?.rows == [.init(name: aName, mine: false)] && req?.tabs[safe: 4] == "신청 1" && sv.isFriend(aName.lowercased(), bName.lowercased()),
          "the request's news on the other side (→ 신청, which says 신청 1); 수락 → friends", "\(String(describing: sent)) \(says(fb)) \(String(describing: req))")
    act(fa); let added = says(fa) == [josa(bName, "과", "와") + " 친구가 되었다!"]; list(fa); list(fb)
    check(added && fa.teamRows(0).count == 2 && fb.teamRows(0).count == 2 && fa.paneContent(Date()).menu == nil,
          "friendAdded on the asker's next act; each now lists the other", "\(says(fa)) \(fa.teamRows(0).count)")
    ha.texts = [cName]; fa.screen = .team(sel: 0, tab: 4, card: false); fa.askFriend(); drain(fa); list(fa)
    let mine = fa.friendReqRows.first { $0.mine }; fa.screen = .team(sel: 0, tab: 4, card: false); fa.pageTap(6200); drain(fa); list(fa)
    check(mine?.name == cName && says(fa) == [cName + "에게 보낸", "신청을 거뒀다"] && fa.friendReqRows.isEmpty, "a request of mine taken back (거두기)", "\(says(fa)) \(fa.friendReqRows)")
    fc.screen = .home; fc.act(.friendRequest(to: aName), back: .home); drain(fc); list(fa); fa.screen = .team(sel: 0, tab: 4, card: false); fa.pageTap(6210); drain(fa); list(fa)
    check(says(fa) == [josa(cName, "의", "의") + " 신청을", "거절했다"] && fa.friendReqRows.isEmpty && !sv.isFriend(aName.lowercased(), cName.lowercased()), "거절: gone, and no friend", "\(says(fa))")
    let bi = fa.teamRows(0).firstIndex { !fa.isMe($0.card) } ?? 0; fa.screen = .team(sel: bi, tab: 0, card: true); fa.pageTap(6031); drain(fa); list(fa)
    check(ha.asked.last == "친구를 끊을까요?" && says(fa) == [josa(bName, "과", "와") + " 친구를", "끊었다"] && fa.teamRows(0).count == 1, "친구 끊기 (asked first) → off the list", "\(says(fa))")

    // the 게시판: fa posts 고우스트 wishing for 윤겔라; fb and fc offer; fa picks fb's
    fa.screen = .menu(menuAt("교환")); fa.press(1); drain(fa); fa.pageTap(8030)
    let k = fa.myTradeBox.firstIndex { $0.dex == 93 } ?? 0; fa.pageTap(8150 + k)
    let toWish: Bool = { if case .market(.pick(let p)) = fa.screen { return p.side == 1 }; return false }()
    let w64 = fa.marketPickList({ if case .market(.pick(let p)) = fa.screen { return p }; return MarketPick() }()).firstIndex { $0.dex == 64 }
    if case .market(.pick(var p)) = fa.screen { p.at = w64 ?? 0; fa.screen = .market(.pick(p)); fa.pageTap(8150 + (w64 ?? 0) % TradePickModel.perPage) }
    let posting = fa.paneContent(Date()).pick; fa.pageTap(8190); drain(fa); drain(fa)
    check(toWish && posting?.theirs.dex == 64 && posting?.go == "글 올리기" && says(fa) == ["게시판에", "글을 올렸다!"] && sv.listings.first?.l.wish == [64] && fa.myPosts.count == 1,
          "교환 → 글 올리기: mine from the box, then the species wished (seen ones) → up on the board", "\(toWish) \(String(describing: posting?.go)) \(says(fa))")
    let post = sv.listings.first?.l.id ?? -1
    fb.screen = .menu(menuAt("교환")); fb.press(1); drain(fb); let row = fb.paneContent(Date()).board?.rows.first
    fb.pageTap(8010); fb.pageTap(8010); let page = fb.paneContent(Date()).post; fb.pageTap(8130)
    let alakazamish = fb.myTradeBox.firstIndex { $0.dex == 64 } ?? 0; fb.pageTap(8150 + alakazamish); let bidGo = fb.paneContent(Date()).pick?.go; fb.pageTap(8190); drain(fb); drain(fb)
    check(row?.line == josa(aName, "의", "의") + " 고우스트 Lv.25" && row?.sub.hasSuffix("원해요 윤겔라") == true && page?.buttons == ["내 포켓몬으로 제안"] && page?.body != nil
          && bidGo == "이 포켓몬으로 제안" && says(fb).first == "교환을 제안했다!" && fb.market?.myBids.count == 1,
          "another's post: its row (원해요 …), its page in full, 내 포켓몬으로 제안 → my box → the offer", "\(String(describing: row)) \(String(describing: page?.buttons)) \(says(fb))")
    fc.screen = .home; fc.act(.marketBid(listing: post, give: 1_000_000), back: .home); drain(fc)
    let boxOnly = says(fc) == ["상자의 포켓몬만", "제안할 수 있어요"]
    serve(fc) { $0.box = [Mon(dex: 133, level: 15, female: false)] }; fc.cloud!.marketDue = true; drain(fc)
    fc.act(.marketBid(listing: post, give: fc.state.box[0].uid ?? -1), back: .home); drain(fc)
    act(fa); let bidNews = says(fa).isEmpty                                                       // 3.8: quiet — the 교환 tile's red dot
    fa.cloud!.marketDue = true; drain(fa); drain(fa); fa.screen = .menu(menuAt("교환"))
    let toPost = fa.marketDot && fa.paneContent(Date()).menu?.rows.first { $0.name == "교환" }?.dot == true && (fa.market?.unseen ?? 0) == 2
    fa.openPost(post); drain(fa); drain(fa)
    let seenNow = (fa.market?.unseen ?? -1) == 0 && !fa.marketDot
    let mp = fa.paneContent(Date()).post, pick = mp?.offers.firstIndex { $0.line.hasPrefix(josa(bName, "의", "의")) } ?? 0
    fa.pageTap(8110 + pick); let picked = fa.paneContent(Date()).post?.strong; fa.pageTap(8130); drain(fa)
    let afterAccept = "\(says(fa)) \(String(describing: picked)) \(ha.asked.last ?? "-") \(fa.screen)".prefix(300)
    let show: Bool = { if case .traded(let g, let got, _, _) = fa.screen { return g.dex == 93 && got.dex == 64 }; return false }()
    fa.tick(Date() + 7)
    check(boxOnly && bidNews && toPost && seenNow && mp?.offers.count == 2 && picked == 0 && ha.asked.last == "교환할까요?" && show && fa.state.box.contains { $0.dex == 65 && $0.ot?.lowercased() == bName.lowercased() },
          "offers come quietly: the 교환 tile's red dot (2 unseen); the post opened, seen; one picked (asked first) → the trade's show, 윤겔라 evolves at the poster (후딘, 어버이)", "\(boxOnly) \(bidNews) \(toPost) \(seenNow) \(afterAccept) \(show)")
    act(fb); fb.cloud!.marketDue = true; drain(fb); drain(fb)
    let kb = fb.claims.first { $0.kind == "traded" }, held = !fb.state.box.contains { $0.dex == 64 }
    fb.screen = .market(.board(tab: 3, sel: 0)); let claimRows = fb.paneContent(Date()).board?.rows; fb.pageTap(8010); drain(fb)
    let gotSaid = { if case .say(let l, _, _) = fb.screen { return l.first == "고우스트를 받았다!" }; return false }()
    fb.screen = .home; fb.tick(Date()); fb.tick(Date() + 7)
    act(fc); fc.cloud!.marketDue = true; drain(fc); drain(fc)
    check(held && kb?.mon.dex == 93 && claimRows?.first?.pill == "받기" && gotSaid && fb.state.box.contains { $0.dex == 94 && $0.ot?.lowercased() == aName.lowercased() }
          && fc.claims.first?.kind == "returned" && fc.claims.first?.mon.dex == 133 && !fc.state.box.contains { $0.dex == 133 } && sv.listings.allSatisfy { !$0.open },
          "3.8's 받기: the bidder's offer was out of its box; 고우스트 waits in its 받기 함 — a click takes it (팬텀 now, 어버이 A); the other bidder's comes back as returned",
          "\(held) \(String(describing: kb)) \(gotSaid) \(fb.state.box.map(\.dex)) \(fc.claims)")
    // 거두기 and 내리기
    fa.screen = .home; fa.act(.marketList(give: fa.state.box.first { $0.dex == 19 }?.uid ?? -1, wish: []), back: .home); drain(fa)
    let p2 = sv.listings.last?.l.id ?? -1; fb.cloud!.marketDue = true; drain(fb)
    fb.screen = .home; fb.act(.marketBid(listing: p2, give: fb.state.box.first { $0.dex == 129 }?.uid ?? -1), back: .home); drain(fb); drain(fb)
    fb.screen = .market(.post(id: p2, sel: nil)); let withdrawLabel = fb.paneContent(Date()).post?.buttons.first; fb.pageTap(8130); drain(fb)
    act(fa); let withdrawn = says(fa)
    check(withdrawLabel?.hasPrefix("제안 거두기") == true && withdrawn.isEmpty && fb.state.box.contains { $0.dex == 129 }, "제안 거두기 → straight back into my box; the poster hears it quietly", "\(String(describing: withdrawLabel)) \(withdrawn) \(fb.state.box.map(\.dex))")
    fa.cloud!.marketDue = true; drain(fa); fa.screen = .market(.post(id: p2, sel: nil)); fa.pageTap(8131); drain(fa)
    check(says(fa) == ["글을 내렸다"] && sv.listings.allSatisfy { !$0.open } && fa.state.box.contains { $0.dex == 19 }, "글 내리기 → off the board, the Pokémon back in the box", "\(says(fa)) \(fa.state.box.map(\.dex))")
    return c
}

/// docs/plans/13 (3.6): items on any of ours (the 도구 page asks who: a box one's 이상한사탕 evolves it, a mint on the walker's, a stone on a box
/// one), in a fight on the bench and on a fainted one (no revive by itself any more); the shops' tabs.
@MainActor func itemChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    var rat = Mon(dex: 19, level: 19, female: false); rat.exp = expTable[growthRate[19]][19]
    let iw = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 30, female: false); s.caught = [Mon(dex: 16, level: 10, female: false)]
                      s.box = [rat, Mon(dex: 133, level: 20, female: false)]; s.bag = ["이상한사탕", "고집민트", "불꽃의돌"]; return s }())
    func useOn(_ item: String, _ ref: Int) {
        iw.screen = .items(iw.state.inventory.firstIndex(of: item) ?? 0); iw.press(1)
        if case .itemOn(var p) = iw.screen { p.at = iw.itemRefs.firstIndex(of: ref) ?? 0; iw.screen = .itemOn(p); iw.press(1); iw.press(1) }
        drain(iw)
    }
    iw.screen = .items(iw.state.inventory.firstIndex(of: "이상한사탕") ?? 0); let label = iw.paneContent(Date()).items?.action; iw.press(1)
    let picker = iw.paneContent(Date()).pick
    let ratRef = iw.state.box.firstIndex { $0.dex == 19 } ?? 0
    useOn("이상한사탕", ratRef); let candySaid = says(iw); iw.press(1); iw.screen = .home; iw.tick(Date())
    let evolved: Bool = { if case .evolve(let f, let t, _) = iw.screen { return f.dex == 19 && t.dex == 20 }; return false }()
    check(label == "쓸 포켓몬 고르기" && picker?.mine.dex == 25 && picker?.base == 8300 && candySaid == ["꼬렛 Lv.20!"] && evolved && iw.state.box.contains { $0.dex == 20 },
          "도구 → who (the companion picked first) → a box one: 이상한사탕 levels it, and it evolves (home shows it)", "\(String(describing: label)) \(candySaid) \(evolved) \(iw.state.box.map(\.dex))")
    iw.tick(Date() + 7); useOn("고집민트", -2)
    let k = natures.firstIndex { $0.name == "고집" } ?? 0, pidgey = iw.state.caught.first, mintSaid = says(iw)
    iw.screen = .box(-2, act: nil, confirm: false, detail: true); let page = iw.paneContent(Date()).mon
    check(pidgey?.mint == k && mintSaid.last == "능력치가 고집 성격처럼" && page?.nature.contains("(민트: 고집)") == true && page?.up == natures[k].up,
          "고집민트 on the walker's: its stats follow 고집, its page says both", "\(String(describing: pidgey?.mint)) \(mintSaid) \(String(describing: page?.nature))")
    useOn("불꽃의돌", iw.state.box.firstIndex { $0.dex == 133 } ?? 0)
    check(iw.state.box.contains { $0.dex == 136 } && iw.state.count("불꽃의돌") == 0, "불꽃의돌 on a box 이브이 → 부스터", "\(iw.state.box.map(\.dex))")
    iw.screen = .items(0); serve(iw) { $0.bag = ["이상한사탕"]; $0.companion.level = 100; $0.caught[0].level = 100; for i in $0.box.indices { $0.box[i].level = 100 } }
    check(iw.paneContent(Date()).items?.action == nil, "an item nobody could use offers nothing", "\(String(describing: iw.paneContent(Date()).items?.action))")

    // in a fight: the bench's HP, a fainted one back up; none by itself
    let bw = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 30, female: false); s.caught = [Mon(dex: 16, level: 30, female: false)]; s.bag = ["좋은상처약", "기력의조각"]; return s }())
    var b = Battle(wild: Mon(dex: 129, level: 3, female: false), party: [bw.state.companion, bw.state.caught[0]]); b.mine[1].hp = 5
    fightOn(bw, b)
    let list = bw.battleItems(b).map(\.name)
    bw.screen = .bagBattle(b, sel: list.firstIndex(of: "좋은상처약") ?? 0); bw.press(1)
    let asks: Bool = { if case .party(_, 1) = bw.screen { return bw.itemFor == "좋은상처약" }; return false }(), msg = bw.sideModel(Date())?.message
    bw.press(1); drain(bw); playOut(bw)
    check(list == ["좋은상처약"] && asks && msg == "좋은상처약을 누구에게 쓸까?" && (bw.fight?.mine[1].hp ?? 0) > 5 && bw.state.count("좋은상처약") == 0,
          "a fight's bag: 좋은상처약 asks who (the bench one, hurt) → its HP back", "\(list) \(asks) \(String(describing: msg)) \(bw.fight?.mine[1].hp ?? -1)")
    calm(bw); serve(bw) { $0.bag = ["기력의조각"] }
    var fb2 = Battle(wild: Mon(dex: 129, level: 3, female: false), party: [bw.state.companion, bw.state.caught[0]]); fb2.mine[1].hp = 0; fb2.mine[1].down = true
    fightOn(bw, fb2); bw.screen = .bagBattle(fb2, sel: 0); bw.press(1); bw.press(1); drain(bw); playOut(bw)
    check((bw.fight?.mine[1].hp ?? 0) > 0 && bw.state.count("기력의조각") == 0, "기력의조각 on the fainted bench one: back up", "\(bw.fight?.mine[1].hp ?? -1)")

    // the shops' tabs
    let sw = online({ var s = Walk(); s.watts = 9999; return s }())
    sw.screen = .shop(bp: false, sel: 0, qty: nil); let m0 = sw.shopModel()
    _ = sw.key(.tab); let m1 = sw.shopModel(); sw.shopTap(2900 + (sw.shopTabs(false).firstIndex(of: "민트") ?? 0)); let mints = sw.shopModel()
    sw.press(0); let wrapped = sw.shopModel()
    check(m0?.tabs.first == "회복" && m0?.tab == 0 && m1?.tab == 1 && mints?.rows.count == Walk.mints.count && mints?.rows.allSatisfy { $0.name.hasSuffix("민트") } == true
          && wrapped?.sel == Walk.mints.count - 1 && wrapped?.tab == mints?.tab,
          "the shop's tabs: 회복 first; Tab the next; a tab's click its rows (21 민트); ◀ goes round within the tab", "\(String(describing: m0?.tabs)) \(String(describing: mints?.rows.count))")
    return c
}

/// 12 §5 (3.6): a live battle on one fake server — the challenge from a friend's card (walking now), the invitation's news and page, 수락: the
/// opening plays on both sides (the other's through its poll), picks in turn (the first one waits for the other's), to the end: 이겼다 +3BP
/// and the record; a declined one and a cancelled one.
@MainActor func duelChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func act(_ w: Walker) { w.news = []; w.screen = .home; w.cloud!.addSteps(1); w.cloud!.saveNow(); drain(w); drain(w) }
    func pump(_ ws: [Walker]) { for _ in 0..<4 { for w in ws { w.tick(Date()); drain(w) } } }
    let sv = FakeCloud()
    let da = online({ var s = Walk(); s.companion = Mon(dex: 150, level: 70, female: false); s.caught = [Mon(dex: 149, level: 70, female: false), Mon(dex: 248, level: 70, female: false)]; return s }(), server: sv)
    let db = online({ var s = Walk(); s.companion = Mon(dex: 10, level: 5, female: false); s.caught = [Mon(dex: 16, level: 5, female: false), Mon(dex: 19, level: 5, female: false)]; return s }(), server: sv)
    let aName = da.myName, bName = db.myName
    sv.befriend(aName, bName); act(db); da.cloud!.teamDue = true; drain(da); drain(da)
    let bi = da.teamRows(0).firstIndex { $0.card.name.lowercased() == bName.lowercased() } ?? 0
    // 3.8: no 대전 파티 yet → set it first (the 대전 menu: 정하기, three clicks, the button)
    da.screen = .team(sel: bi, tab: 0, card: true); let card = da.paneContent(Date()).teamCard; da.pageTap(6032)
    let noParty: Bool = { if case .say(["대전 파티를", "먼저 정해 주세요"], .squad(let q), _) = da.screen { return q.kind == .duelParty }; return false }()
    da.screen = .menu(menuAt("대전")); let tile = da.paneContent(Date()).menu?.rows.first { $0.name == "대전" }; da.press(1); drain(da)
    let hub0 = da.paneContent(Date()).duelHub
    da.pageTap(6330); let look0 = da.paneContent(Date()).squad?.detail; da.pageTap(8751); let looked = da.paneContent(Date()).squad
    pickAt(da, 0); pickAt(da, 1); let two = da.paneContent(Date()).squad; pickAt(da, 2); let three = da.paneContent(Date()).squad
    da.pageTap(8790); drain(da); let setSaid = says(da); da.press(1); let hub1 = da.paneContent(Date()).duelHub
    check(look0?.title == "뮤츠 Lv.70 → 50" && look0?.ivs.count == 6 && look0?.evs == [0, 0, 0, 0, 0, 0] && look0?.moves.isEmpty == false && look0?.item == "도구 없음" && looked?.order.allSatisfy { $0 == nil } == true
          && looked?.detail?.dex == 149 && looked?.sel == 1,
          "3.8.1: the picker's card — the one looked at (name, Lv → 50, nature · ability · item, IVs, EVs, moves); a first click only looks", "\(String(describing: look0)) \(String(describing: looked?.detail))")
    check(card?.duel == "대전 신청" && noParty && tile?.note == "대전 파티를 정해 주세요" && hub0?.go == nil && hub0?.hint == "대전 파티를 먼저 정해 주세요" && hub0?.friends.map(\.name) == [bName]
          && two?.go == nil && two?.strip.count == 6 && two?.order.prefix(3) == [1, 2, nil] && three?.go == "이 3마리로 정하기" && setSaid == ["대전 파티를", "정했다!"]
          && da.state.duelParty?.count == 3 && served(da)?.duelParty == da.state.duelParty && hub1?.party.compactMap { $0?.dex } == [150, 149, 248] && hub1?.go == "랜덤 매칭",
          "3.8: 대전 신청 with no 대전 파티 → set it first; the 대전 tile → its menu (friends walking now); 정하기: 3–6 clicked in order, the button keeps it (the server's too)",
          "\(noParty) \(String(describing: tile)) \(String(describing: hub0)) \(String(describing: three?.go)) \(setSaid) \(String(describing: da.state.duelParty))")
    db.screen = .squad(Squad(kind: .duelParty, picked: [], at: 0)); db.press(1); db.press(2); db.press(1); db.press(2); db.press(1)
    let dbOnButton: Bool = { if case .squad(let q) = db.screen { return q.at == 3 && q.picked.count == 3 }; return false }()
    db.press(1); drain(db); db.press(1)
    // the challenge, 수락 → each picks 3 of the six in a minute (the other's six seen)
    da.screen = .team(sel: bi, tab: 0, card: true); da.pageTap(6032); drain(da)
    let waiting: Bool = { if case .duel(.waitAccept(_, let to)) = da.screen { return to.lowercased() == bName.lowercased() }; return false }()
    check(dbOnButton && db.state.duelParty?.count == 3 && waiting && da.duelOn && sv.duels.count == 1 && da.paneContent(Date()).duel?.buttons == ["신청 취소"],
          "● alone sets it too (● picks, ▶ moves; the last one in: onto the button); 대전 신청 → the server's invitation; this side waits (신청 취소)", "\(dbOnButton) \(waiting)")
    act(db); let invited = says(db) == [josa(aName, "이", "가") + " 대전을 신청했다!"]; db.press(1)
    let page = db.paneContent(Date()).duel
    db.pageTap(6300); drain(db)
    let bPick = db.paneContent(Date()).squad
    let bPicking: Bool = { if case .squad(let q) = db.screen { return q.kind == .duelPick(id: sv.duels[0].id) }; return false }()
    pump([da, db])
    let aPicking: Bool = { if case .squad(let q) = da.screen { return q.kind == .duelPick(id: sv.duels[0].id) }; return false }()
    check(invited && page?.buttons == ["수락", "거절"] && bPicking && aPicking && bPick?.theirs?.map(\.dex) == [150, 149, 248] && bPick?.cells.map(\.dex) == [10, 16, 19] && bPick?.strip.count == 3
          && bPick?.note.hasSuffix("초 남음") == true && db.title().0 == "실시간 대전",
          "the invitation → 수락 → both on the pick (my six, the other's six by species, a minute)", "\(invited) \(bPicking) \(aPicking) \(String(describing: bPick))")
    pickAt(da, 2); pickAt(da, 0); pickAt(da, 1); da.pageTap(8790); drain(da)
    let aSent = da.paneContent(Date()).squad
    db.press(1); db.press(2); db.press(1); db.press(2); db.press(1); db.press(1); drain(db)
    var guard1 = 0; while guard1 < 6, !{ if case .beats = db.screen { return true }; return false }() { guard1 += 1; pump([da, db]) }
    let opening: Bool = { if case .beats = db.screen { return true }; return false }()
    playOut(db); pump([da, db]); playOut(da)
    let aLead = da.fight?.mine.map(\.mon.dex)
    let dbMenu: Bool = { if case .battle(let b, 0) = db.screen { return db.battleMenu(b) == ["공격", "교체", "기권"] && !db.duelWait }; return false }()
    let daMenu: Bool = { if case .battle = da.screen { return !da.duelWait }; return false }()
    check(aSent?.go == nil && aSent?.hint == "상대가 고르는 중…" && aSent?.strip.compactMap { $0?.dex } == [248, 150, 149] && opening && aLead == [248, 150, 149] && dbMenu && daMenu && da.title().0 == "실시간 대전",
          "my three sent (in the order clicked) → the other's awaited; both in: the opening plays on both sides, then each picks", "\(String(describing: aSent)) \(opening) \(String(describing: aLead)) \(dbMenu) \(daMenu) \(da.screen)")
    da.press(1); da.press(1); drain(da)
    let daWaits = da.duelWait && da.sideModel(Date())?.message.hasPrefix("상대를 기다리는 중") == true
    db.press(1); db.press(1); drain(db); pump([da, db])
    var n = 0
    while n < 40, da.duelOn || db.duelOn {                                                            // to the end: each picks when asked
        n += 1
        for w in [da, db] {
            switch w.screen {
            case .beats: playOut(w)
            case .battle(let b, _) where !w.duelWait: w.screen = .battle(b, sel: 0); w.press(1); if case .moves(let x, _) = w.screen { w.screen = .moves(x, sel: x.mine[x.me].pp.firstIndex { $0 > 0 } ?? 0); w.press(1) }; drain(w)
            case .party(let b, _): w.screen = .party(b, sel: b.mine.indices.first { b.mine[$0].alive && $0 != b.me } ?? 0); w.press(1); drain(w)
            default: break
            }
        }
        pump([da, db])
    }
    let won = says(da), lost = says(db)
    act(da); act(db)
    check(daWaits && won == ["이겼다!", "+3 BP"] && lost.first == josa(aName, "에게", "에게") + " 졌다..." && da.state.bp == 3 && da.state.duelWins == 1 && db.state.duelLosses == 1 && sv.duels.first?.state == "over",
          "a pick waits for the other's (상대를 기다리는 중); turn by turn to the end: 이겼다! +3 BP, the record on both sides", "\(daWaits) \(won) \(lost) \(String(describing: da.state.bp)) \(String(describing: sv.duels.first?.state))")
    // 전적: asked with the menu, on its tab
    da.screen = .menu(menuAt("대전")); da.press(1); pump([da]); da.pageTap(6321); pump([da])
    let recs = da.paneContent(Date()).duelHub
    check(recs?.tab == 1 && recs?.recs.first?.won == true && recs?.recs.first?.line == "vs " + bName && recs?.recs.first?.mine == [248, 150, 149] && recs?.recs.first?.theirs.count == 3 && da.cloud!.duelRecord?.wins == 1,
          "전적: the last ones (won or lost, with whom, the three on each side)", "\(String(describing: recs))")
    // 랜덤 매칭: alone it waits (그만두기); two meet → the pick; a minute unpicked → the first three; a minute alone → 상대를 찾지 못했다
    da.screen = .duel(.hub(tab: 0, sel: 0)); da.pageTap(6331); drain(da)
    let queued: Bool = { if case .duel(.queued) = da.screen { return true }; return false }()
    let qPage = da.paneContent(Date()).duel; da.pageTap(6300); drain(da)
    let quit = says(da) == ["랜덤 매칭을", "그만뒀다"] && !da.duelOn && sv.duels.last?.state == "cancelled"
    da.screen = .duel(.hub(tab: 0, sel: 0)); da.press(1); drain(da)                                  // (● on 랜덤 매칭)
    db.screen = .duel(.hub(tab: 0, sel: 0)); db.pageTap(6331); drain(db); pump([da, db])
    let matched = { (w: Walker) -> Bool in if case .squad(let q) = w.screen, case .duelPick = q.kind { return true }; return false }
    let bothPick = matched(da) && matched(db)
    sv.now = Date() + 61; act(da); pump([da, db]); sv.now = nil
    var g2 = 0; while g2 < 6, !{ if case .beats = da.screen { return true }; return false }() { g2 += 1; pump([da, db]) }
    let firstThree = da.fight?.mine.map(\.mon.dex) == [150, 149, 248]
    playOut(da); pump([da, db]); playOut(db); pump([da, db])
    if case .battle(let f, _) = da.screen { da.screen = .battle(f, sel: da.battleMenu(f).firstIndex(of: "기권")!); da.press(1); da.press(2); da.press(1); drain(da) }   // 기권 (the turn waits for the other's pick)
    if case .battle(let f, _) = db.screen, !db.duelWait { db.screen = .battle(f, sel: 0); db.press(1); if case .moves(let x, _) = db.screen { db.screen = .moves(x, sel: 0); db.press(1) }; drain(db) }
    for _ in 0..<6 { pump([da, db]); for w in [da, db] { if case .beats = w.screen { playOut(w) } } }
    da.screen = .home; db.screen = .home; act(da); act(db)
    let quitOver = sv.duels.last?.state == "over" && sv.duels.last?.why == "forfeit"
    da.screen = .duel(.hub(tab: 0, sel: 0)); da.pageTap(6331); drain(da); sv.now = Date() + 61; act(da); pump([da]); sv.now = nil
    let unmatched = says(da) == ["상대를 찾지 못했다", "잠시 뒤에 다시 해 봐요"] && !da.duelOn
    check(queued && qPage?.buttons == ["그만두기"] && quit && bothPick && firstThree && quitOver && unmatched,
          "랜덤 매칭: alone it waits (그만두기); two meet → both on the pick; a minute unpicked → the first three; a minute alone → 상대를 찾지 못했다",
          "\(queued) \(quit) \(bothPick) \(firstThree) \(quitOver) \(says(da)) \(sv.duels.map(\.state))")
    // declined; cancelled
    da.screen = .home; da.challenge(bName); drain(da); act(db); db.press(1); db.pageTap(6301); drain(db)
    let declined = says(db) == ["대전 신청을", "거절했다"]; pump([da, db])
    let heard = says(da) == ["대전이", "상대가 거절했다"]
    da.screen = .home; da.challenge(bName); drain(da); da.pageTap(6300); drain(da)
    let cancelled = says(da) == ["대전 신청을", "취소했다"] && !da.duelOn
    check(declined && heard && cancelled, "거절: said there, heard here (its poll); 신청 취소", "\(says(db)) \(says(da))")
    return c
}

/// docs/plans/14 §3 (3.8): 맡겨 키우기 — sent from a friend's card (one of the box's), out of the box; the host hears it and walks with it
/// (home's stickers), its steps raise it; 돌려보내기 early → the host's BP (a 2,000 steps), the owner's 받기 함 (the EXP when taken). 전체 (VIEW_ALL).
@MainActor func visitChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func act(_ w: Walker, _ n: Int = 1) { w.news = []; w.screen = .home; w.cloud!.addSteps(n); w.cloud!.saveNow(); drain(w); drain(w) }
    func team(_ w: Walker) { w.cloud!.teamDue = true; w.cloud!.tick(Date()); drain(w); drain(w) }
    let sv = FakeCloud()
    let va = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 20, female: false); s.box = [Mon(dex: 133, level: 10, female: false)]; return s }(), server: sv)
    let vb = online({ var s = Walk(); s.companion = Mon(dex: 1, level: 20, female: false); return s }(), server: sv)
    let other = online(Walk(), server: sv)
    let aName = va.myName, bName = vb.myName
    sv.befriend(aName, bName); act(vb); team(va)
    let bi = va.teamRows(0).firstIndex { $0.card.name.lowercased() == bName.lowercased() } ?? 0
    va.screen = .team(sel: bi, tab: 0, card: true); let card = va.paneContent(Date()).teamCard; va.pageTap(6034)
    let pick = va.paneContent(Date()).pick
    va.press(1); va.press(1); drain(va); let sent = says(va); va.press(1); team(va)
    va.screen = .team(sel: 0, tab: 5, card: false); let mine = va.paneContent(Date()).visits
    check(card?.visit == "맡기기" && pick?.title == josa(bName, "에게", "에게") + " 맡기기" && pick?.count == 1 && sent == [bName + "에게 이브이를", "맡겼다!", "5시간 뒤 받기로 돌아와요"]
          && !va.state.box.contains { $0.dex == 133 } && mine?.rows.first?.button == "데려오기" && mine?.rows.first?.mine == true && va.teamTabLabels[5] == "맡기기 1",
          "a friend walking now: 맡기기 → pick one (the walker's · box's) → it goes (out of my box); my 맡기기 tab has it (데려오기)",
          "\(String(describing: card?.visit)) \(String(describing: pick?.title)) \(sent) \(String(describing: mine))")
    act(vb); let came = says(vb); vb.press(1); team(vb)
    vb.screen = .team(sel: 0, tab: 5, card: false); let guestRow = vb.paneContent(Date()).visits?.rows.first
    act(vb, 4500); team(vb); let raised = vb.guests.first?.steps ?? 0
    check(came == [josa(aName, "의", "의") + " 이브이를", "맡았다!", "5시간 같이 걸어요"] && guestRow?.button == "돌려보내기" && vb.guests.count == 1 && raised >= 4500,
          "the host hears it (맡았다!) and walks with it: its steps go to it", "\(came) \(String(describing: guestRow)) \(raised)")
    let bp0 = vb.state.bp ?? 0
    vb.screen = .team(sel: 0, tab: 5, card: false); vb.pageTap(6400); drain(vb); let back = says(vb); vb.press(1); vb.screen = .home; vb.tick(Date()); let again = says(vb)
    check(back == [josa(aName, "의", "의") + " 이브이를", "돌려보냈다", "+2BP"] && again.isEmpty && (vb.state.bp ?? 0) == bp0 + 2,
          "돌려보내기 (early): settled with the steps so far — the host's +2BP (a 2,000 steps)", "\(back) \(again) \(String(describing: vb.state.bp))")
    act(va); va.cloud!.marketDue = true; drain(va); drain(va)
    let k = va.claims.first, dot = va.marketDot
    va.screen = .market(.board(tab: 3, sel: 0)); let row = va.paneContent(Date()).board?.rows.first; va.pageTap(8010); drain(va)
    let home = va.state.box.first { $0.dex == 133 }; team(va)
    check(k?.kind == "visit" && dot && row?.pill == "받기" && (home?.level ?? 0) > 10 && va.visits?.away == nil,
          "home through the owner's 받기 함 (the red dot): taken, it has the EXP of the steps raised", "\(String(describing: k)) \(dot) \(String(describing: row)) \(String(describing: home?.level))")
    // 전체 (VIEW_ALL): every trainer — only for its accounts
    sv.viewAll.insert(aName.lowercased()); team(va); team(vb)
    let labels = va.teamTabLabels, all = va.teamRows(6).map { $0.card.name.lowercased() }
    va.screen = .team(sel: all.firstIndex(of: other.myName.lowercased()) ?? 0, tab: 6, card: true); let stranger = va.paneContent(Date()).teamCard
    check(labels.last == "전체" && va.teamTabCount == 7 && vb.teamTabCount == 6 && all.contains(other.myName.lowercased()) && stranger?.duel == nil && stranger?.request == "친구 신청",
          "전체 (VIEW_ALL's): every trainer, a tab of its own only there; a stranger's card: 친구 신청, no 대전", "\(labels) \(all) \(String(describing: stranger))")
    return c
}

/// docs/plans/13 ⑤ (3.7): 지닌 도구 — from a Pokémon's page (지니게 하기, another one swapped in, 빼기), the bag's hold-only ones on a box one,
/// the battle panel showing it, a trade's notice that it goes along, the shops' 지닌 도구 · 열매 tabs (two rows of tabs).
@MainActor func holdChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    let h = TestHost()
    let hw = online({ var s = Walk(); s.companion = Mon(dex: 25, level: 30, female: false); s.box = [Mon(dex: 19, level: 10, female: false)]
                      s.bag = ["먹다남은음식", "구애머리띠", "오랭열매"]; return s }(), host: h)
    hw.screen = .box(-1, act: nil, confirm: false, detail: true); let page0 = hw.paneContent(Date()).mon
    hw.gridTap(4410); let rows = hw.paneContent(Date()).hold?.rows.map(\.name)
    let leftovers = rows?.firstIndex(of: "먹다남은음식") ?? 0; hw.screen = .hold(ref: -1, sel: leftovers); hw.press(1); drain(hw)
    let held = says(hw), page1: MonModel? = { hw.screen = .box(-1, act: nil, confirm: false, detail: true); return hw.paneContent(Date()).mon }()
    check(page0?.held == nil && rows == ["구애머리띠", "먹다남은음식", "오랭열매"] && held == ["피카츄에게 먹다남은음식을", "지니게 했다!"] && hw.state.companion.item == "먹다남은음식"
          && hw.state.count("먹다남은음식") == 0 && page1?.held == "먹다남은음식" && page1?.heldNote?.isEmpty == false,
          "a Pokémon's page → 지니게 하기: the bag's holdable ones; held now (out of the bag), the page says so", "\(String(describing: rows)) \(held) \(String(describing: page1?.held))")
    hw.gridTap(4410); let swapRows = hw.paneContent(Date()).hold?.rows
    hw.screen = .hold(ref: -1, sel: swapRows?.firstIndex { $0.name == "구애머리띠" } ?? 0); hw.press(1); drain(hw)
    let swapped = hw.state.companion.item == "구애머리띠" && hw.state.count("먹다남은음식") == 1 && swapRows?.first?.take == true
    hw.screen = .hold(ref: -1, sel: 0); hw.press(1); drain(hw)
    check(swapped && hw.state.companion.item == nil && hw.state.count("구애머리띠") == 1 && says(hw) == ["피카츄의 구애머리띠를", "뺐다"],
          "another swapped in (the old one back to the bag); 빼기 first while it holds one", "\(swapped) \(says(hw))")
    hw.screen = .items(hw.state.inventory.firstIndex(of: "먹다남은음식") ?? 0); let act = hw.paneContent(Date()).items?.action; hw.press(1)
    if case .itemOn(var p) = hw.screen { p.at = hw.itemRefs.firstIndex(of: 0) ?? 0; hw.screen = .itemOn(p); hw.press(1); hw.press(1) }; drain(hw)
    hw.screen = .box(-1, act: nil, confirm: false); let cell = hw.paneContent(Date()).grid?.cells.first
    check(act == "지니게 할 포켓몬 고르기" && hw.state.box.first?.item == "먹다남은음식" && cell?.held == true, "the bag's hold-only one: who holds it (a box one); its cell marked", "\(String(describing: act)) \(String(describing: hw.state.box.first?.item))")
    serve(hw) { $0.companion.item = "먹다남은음식" }
    let b = Battle(wild: Mon(dex: 129, level: 3, female: false), companion: hw.state.companion); fightOn(hw, b)
    check(hw.sideModel(Date())?.mine.item == "먹다남은음식", "the battle panel shows what ours holds", "\(String(describing: hw.sideModel(Date())?.mine.item))")
    calm(hw); h.answer = false
    hw.screen = .market(.pick(MarketPick(give: hw.state.box.first?.uid))); hw.pageTap(8190); drain(hw)
    check(h.asked.last == "꼬렛은 먹다남은음식을 지니고 있어요" && !server(hw).0.listings.contains { $0.open }, "putting one up that holds an item asks first (it goes along); no: nothing put up", "\(h.asked.last ?? "-")")
    let sw = online({ var s = Walk(); s.watts = 9999; return s }())
    sw.screen = .shop(bp: false, sel: 0, qty: nil); let shop = sw.shopModel(), bpTabs: ShopModel? = { sw.screen = .shop(bp: true, sel: 0, qty: nil); return sw.shopModel() }()
    check(shop?.tabs.contains("지닌 도구") == true && shop?.tabs.contains("열매") == true && (shop?.tabs.count ?? 0) > 6 && sw.paneContent(Date()).shop != nil && bpTabs?.tabs.contains("지닌 도구") == true,
          "the shops: 지닌 도구 (and 열매) tabs, two rows of them", "\(String(describing: shop?.tabs)) \(String(describing: bpTabs?.tabs))")
    return c
}

/// docs/plans/14 §2.3 (3.8): a chain going on — news that would take the walker away from home (others': an offer, an invitation) wait for the
/// chain's end; a level or a find still shows; the next bush is asked for at once.
@MainActor func chainNewsChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    let cw = online({ var s = Walk(); s.watts = 100; return s }())
    cw.screen = .home; cw.chainNext = 2
    cw.news = [.marketBid(listing: 1, from: "민수", mon: Mon(dex: 25, level: 5, female: false)), .duelInvite(id: 3, from: "지은"), .find(item: "상처약")]
    cw.settle(Date())
    let found: Bool = { if case .say(let l, _, _) = cw.screen { return l.last == "상처약" }; return false }()
    let held = cw.news.count == 2 && cw.news.allSatisfy(Walker.leavesHome)
    cw.screen = .home; cw.settle(Date()); drain(cw)
    let bush: Bool = { if case .radar = cw.screen { return true }; if case .say(let l, _, _) = cw.screen { return l.first == "연쇄 2!" }; return false }()
    check(found && held && bush && cw.news.count == 2, "a chain going on: a find shows, others' news (an offer, an invitation) wait; the next bush goes at once", "\(found) \(held) \(bush) \(cw.screen)")
    cw.dropPlay(); cw.screen = .home; cw.settle(Date())
    let after: Bool = { if case .say(let l, _, _) = cw.screen { return l.first == "지은이 대전을 신청했다!" }; return false }()   // (3.8: the offer is quiet — the red dot)
    check(after, "… and show once the chain's over", "\(cw.screen)")
    return c
}
