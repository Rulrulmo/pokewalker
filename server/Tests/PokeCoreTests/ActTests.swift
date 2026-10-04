import Foundation
import Testing
@testable import PokeCore

// docs/plans/11: POST /v2/act through the database — the session, seq and a resend, the steps allowance and the day's cap, a new trainer's first
// save, the ledger following the save, 2.x turned away once a trainer acts on 3.0, MIN_APP.

private let base = Date(timeIntervalSince1970: 2_000_000_000)
private func reply(_ r: Reply) throws -> ActReply { try JSONDecoder().decode(ActReply.self, from: r.body) }

/// A 3.0 trainer: created with its PIN (the starter issued), its session.
private func newTrainer(_ db: SaveDB, _ id: String, at t: Date = base) async throws -> String {
    let r = await db.create(CreateReq(id: id, device: "mac", device_name: "MAC", app: "3.0", pin: "2468"), now: Int(t.timeIntervalSince1970))
    #expect(r.status == 200)
    return try #require(string(r, "session"))
}
private func act(_ db: SaveDB, _ id: String, _ s: String, _ seq: Int, _ a: Act, steps: Int? = nil, at sec: Double) async -> Reply {
    await db.act(ActReq(id: id, session: s, seq: seq, steps: steps, act: a), now: base.addingTimeInterval(sec))
}

@Test func actSessionSeqAndResend() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let s = try await newTrainer(db, "actor")
    var r = await act(db, "actor", s, 1, .steps, steps: 300, at: 60)
    #expect(r.status == 200)
    let first = try reply(r)
    #expect(first.rev == 1 && first.taken == 300 && first.walk?.companion.uid == firstUID && first.walk?.total == 300)   // the server made its first save
    r = await act(db, "actor", s, 1, .steps, steps: 300, at: 61)                                  // the same seq again: the stored reply, nothing walked twice
    let again = try reply(r)
    #expect(r.status == 200 && again.rev == 1 && again.walk?.total == 300 && again.taken == 300)
    r = await act(db, "actor", s, 3, .steps, at: 62)
    #expect(r.status == 409 && string(r, "error") == "seq" && number(r, "last") == 1)
    r = await act(db, "actor", "not-it", 2, .steps, at: 63)
    #expect(r.status == 409 && string(r, "reason") == "replaced")
    r = await act(db, "actor", s, 2, .radar, at: 64)                                              // 15 W: a radar
    let shown = try reply(r)
    #expect(shown.out.radar != nil && shown.walk?.watts == 5)
    #expect(try await db.count("SELECT count(*) AS n FROM mons WHERE key = 'actor' AND state = 'pending'") == 1)
    r = await act(db, "actor", s, 3, .radarPick(bush: -1), at: 65)
    #expect((try reply(r)).out.missed == true)
    #expect(try await db.count("SELECT count(*) AS n FROM mons WHERE key = 'actor' AND state = 'gone'") == 1)
    r = await act(db, "actor", s, 4, .buy(bp: false, item: "회복약", legend: nil, shell: nil, qty: 1), at: 66)
    let no = try reply(r)
    #expect(r.status == 200 && no.out.cannot == "W가 부족하다" && no.walk == nil && no.rev == 2)       // nothing changed: no save, the same rev
    #expect(try await db.count("SELECT count(*) AS n FROM actions WHERE key = 'actor' AND note LIKE '%cannot%'") == 1)
}

@Test func actStepsAllowanceAndDayCap() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let s = try await newTrainer(db, "walker")
    var r = await act(db, "walker", s, 1, .steps, steps: 50_000, at: 10)                       // 10 s since it was made: 150
    #expect((try reply(r)).taken == 150)
    r = await act(db, "walker", s, 2, .steps, steps: 1_000, at: 20)                             // 10 s later: 150
    #expect((try reply(r)).taken == 150)
    r = await act(db, "walker", s, 3, .steps, steps: 200_000, at: 20 + 86_400 * 3)            // days away: the allowance stops at a day's
    let big = try reply(r)
    #expect(big.taken == Walk.dayCap)
    r = await act(db, "walker", s, 4, .steps, steps: 5_000, at: 20 + 86_400 * 3 + 600)         // the day's cap, counted by the server
    #expect((try reply(r)).taken == 0)
    #expect(try await db.count("SELECT count(*) AS n FROM actions WHERE key = 'walker' AND note LIKE 'steps%'") == 4)
}

@Test func actTurnsOldAppsAway() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let s = try await newTrainer(db, "moved")
    _ = await act(db, "moved", s, 1, .steps, steps: 10, at: 5)
    var r = await db.login(LoginReq(id: "moved", device: "pc", device_name: "PC", app: "2.2", force: true, pin: "2468"), now: Int(base.timeIntervalSince1970) + 10)
    #expect(r.status == 426 && string(r, "need") == "3.0")                                       // acted on 3.0: 2.x may not come back
    r = await db.radar(RadarReq(id: "moved", session: s, walk: sample()), now: Int(base.timeIntervalSince1970) + 11)
    #expect(r.status == 426)

    let path2 = path + ".min"; defer { try? FileManager.default.removeItem(atPath: path2) }
    let gated = try SaveDB(path: path2, create: true, minApp: "3.0")
    _ = await gated.create(CreateReq(id: "old", device: "pc", device_name: "PC", app: "2.2", pin: "1357"), now: 100)
    r = await gated.login(LoginReq(id: "old", device: "pc", device_name: "PC", app: "2.2", force: true, pin: "1357"), now: 200)
    #expect(r.status == 426 && string(r, "need") == "3.0")
    r = await gated.login(LoginReq(id: "old", device: "pc", device_name: "PC", app: "3.0", force: true, pin: "1357"), now: 300)
    #expect(r.status == 200)
}

@Test func actFightThroughTheServer() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let s = try await newTrainer(db, "fighter")
    var seq = 1, t = 600.0
    func go(_ a: Act, steps: Int? = nil) async throws -> ActReply { t += 2; defer { seq += 1 }; return try reply(await act(db, "fighter", s, seq, a, steps: steps, at: t)) }
    _ = try await go(.steps, steps: 8_000)
    var kept = 0
    for _ in 0..<6 {
        guard let shown = try await go(.radar).out.radar else { break }
        var o = try await go(.radarPick(bush: shown.bush))
        while o.out.battle != nil, o.out.end == nil {
            let b = o.out.battle!
            o = try await go(.battle(cmd: b.mustReplace ? .replace(to: b.mine.indices.first { b.mine[$0].alive && $0 != b.me } ?? 0) : .ball))
        }
        if o.out.end?.result == "caught" { kept += 1 }
    }
    let ledger = try await db.count("SELECT count(*) AS n FROM mons WHERE key = 'fighter' AND state = 'kept'")
    #expect(kept > 0 && ledger == kept + 1)                                                      // the starter and every catch
    #expect(try await db.count("SELECT count(*) AS n FROM mons WHERE key = 'fighter' AND state = 'pending'") == 0)
}

@Test func teamCardsAndHello() async throws {                                                     // docs/plans/12 M1
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let a = try await newTrainer(db, "앨리스"), b = try await newTrainer(db, "보브")
    _ = await act(db, "앨리스", a, 1, .steps, steps: 300, at: 60)
    _ = await act(db, "보브", b, 1, .steps, steps: 100, at: 60)
    var r = await db.team(TeamReq(id: "앨리스", session: a), now: base.addingTimeInterval(70))
    #expect(r.status == 200)
    let team = try JSONDecoder().decode(TeamReply.self, from: r.body)
    #expect(team.week.contains("-W") && team.cards.map(\.name).sorted() == ["보브", "앨리스"])
    let alice = try #require(team.cards.first { $0.name == "앨리스" })
    #expect(alice.today == 300 && alice.week == 300 && alice.total == 300 && alice.companion.dex == 25 && alice.idle == 10)
    r = await db.team(TeamReq(id: "앨리스", session: "not-it"), now: base.addingTimeInterval(71))
    #expect(r.status == 409)
    let z = try await newTrainer(db, "zz123456")                                                     // a test ID: only test IDs see it
    _ = await act(db, "zz123456", z, 1, .steps, steps: 10, at: 60)
    r = await db.team(TeamReq(id: "앨리스", session: a), now: base.addingTimeInterval(72))
    #expect(try JSONDecoder().decode(TeamReply.self, from: r.body).cards.count == 2)
    r = await db.team(TeamReq(id: "zz123456", session: z), now: base.addingTimeInterval(72))
    #expect(try JSONDecoder().decode(TeamReply.self, from: r.body).cards.count == 3)

    r = await act(db, "앨리스", a, 2, .greet(to: "보브"), at: 80)
    #expect((try reply(r)).out.cannot == nil)
    r = await act(db, "앨리스", a, 3, .greet(to: "보브"), at: 90)
    #expect((try reply(r)).out.cannot == "조금 뒤에 다시\n인사할 수 있어요")                          // once an hour
    r = await act(db, "앨리스", a, 4, .greet(to: "앨리스"), at: 91)
    #expect((try reply(r)).out.cannot == "인사할 수 없는\n트레이너예요")
    r = await act(db, "앨리스", a, 5, .greet(to: "없는사람"), at: 92)
    #expect((try reply(r)).out.cannot == "인사할 수 없는\n트레이너예요")

    r = await db.act(ActReq(id: "보브", session: b, seq: 2, act: .steps, app: "3.1.1"), now: base.addingTimeInterval(100))
    #expect((try reply(r)).out.news.isEmpty)                                                          // 3.1.1 can't read it: kept
    r = await db.act(ActReq(id: "보브", session: b, seq: 3, act: .steps, app: "3.2"), now: base.addingTimeInterval(101))
    #expect((try reply(r)).out.news == [.hello(from: "앨리스", dex: 25, shiny: false)])
    r = await db.act(ActReq(id: "보브", session: b, seq: 4, act: .steps, app: "3.2"), now: base.addingTimeInterval(102))
    #expect((try reply(r)).out.news.isEmpty)                                                          // once
    r = await act(db, "앨리스", a, 6, .greet(to: "보브"), at: 80 + 3600)
    #expect((try reply(r)).out.cannot == nil)                                                         // an hour on: again
}

/// A trainer's save as the test sets it (box and bag), straight into the row.
private func setWalk(_ db: SaveDB, _ key: String, _ change: (inout Walk) -> Void) async throws {
    let t = try #require(try await db.trainer(key)), text = try #require(t.walk)
    var w = try #require(decodeWalk(text)); change(&w)
    try await db.setRaw(key, savedText(w))
    for m in w.box { try await db.record(key, m, kind: "test", now: 0) }                           // in the ledger, as every Pokémon is
}
extension SaveDB { func setRaw(_ key: String, _ text: String) throws { try db.rows("UPDATE trainers SET walk = :w WHERE key = :k", ["w": .text(text), "k": .text(key)]) } }

@Test func tradesBothWays() async throws {                                                       // docs/plans/12 M2
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let a = try await newTrainer(db, "앨리스"), b = try await newTrainer(db, "보브")
    _ = await act(db, "앨리스", a, 1, .steps, steps: 10, at: 60)
    _ = await act(db, "보브", b, 1, .steps, steps: 10, at: 60)
    func mon(_ dex: Int, _ uid: Int) -> Mon { var m = Mon(dex: dex, level: 30, female: false); m.uid = uid; return m }
    try await setWalk(db, "앨리스") { $0.box = [mon(64, 1_000_001), mon(95, 1_000_002), mon(16, 1_000_003)]; $0.bag = ["금속코트"]; $0.lastUID = 1_000_003 }
    try await setWalk(db, "보브") { $0.box = [mon(19, 1_000_001), mon(41, 1_000_002)]; $0.lastUID = 1_000_002 }
    func go(_ who: String, _ s: String, _ seq: Int, _ a: Act, at t: Double) async throws -> ActReply {
        try reply(await db.act(ActReq(id: who, session: s, seq: seq, act: a, app: "3.3"), now: base.addingTimeInterval(t)))
    }
    #expect(try await go("앨리스", a, 2, .tradeOffer(to: "보브", give: firstUID, want: nil), at: 70).out.cannot == "상자의 포켓몬만\n교환할 수 있어요")   // the companion
    #expect(try await go("앨리스", a, 3, .tradeOffer(to: "보브", give: 1_000_001, want: 1_000_001), at: 71).out.cannot == nil)   // 윤겔라 for 레트라
    #expect(try await go("앨리스", a, 4, .tradeOffer(to: "보브", give: 1_000_001, want: nil), at: 72).out.cannot == "이미 교환에\n걸어 둔 포켓몬이에요")
    let offered = try await go("보브", b, 2, .steps, at: 73)
    guard case .tradeOffer(let id, "앨리스", let m, let want)? = offered.out.news.first else { Issue.record("\(offered.out.news)"); return }
    #expect(m.dex == 64 && want?.dex == 19)
    let list = try JSONDecoder().decode(TradesReply.self, from: await db.trades(TeamReq(id: "보브", session: b), now: base.addingTimeInterval(74)).body)
    #expect(list.incoming.map(\.id) == [id] && list.outgoing.isEmpty)
    let peek = try JSONDecoder().decode(BoxReply.self, from: await db.box(BoxReq(id: "앨리스", session: a, of: "보브"), now: base.addingTimeInterval(74)).body)
    #expect(peek.name == "보브" && peek.box.map(\.dex) == [19, 41])

    let done = try await go("보브", b, 3, .tradeAccept(id: id, give: nil), at: 75)                 // the wanted one goes: no choice
    #expect(done.out.cannot == nil && done.walk != nil)
    guard case .traded(id, "앨리스", let gave, let got)? = done.out.news.first else { Issue.record("\(done.out.news)"); return }
    #expect(gave.dex == 19 && got.dex == 65 && got.ot == "앨리스")                                   // 윤겔라 became 후딘 here, by trade
    #expect(done.out.news.contains { if case .evolve(_, 64, 65, _) = $0 { return true }; return false })
    #expect(done.walk?.box.map(\.dex) == [41, 65] && (done.walk?.owned ?? []).contains(65))
    let back = try await go("앨리스", a, 5, .steps, at: 76)                                          // the other side: the news and its new save
    #expect(back.walk?.box.map(\.dex) == [95, 16, 19] && back.walk?.box.last?.ot == "보브")
    guard case .traded(id, "보브", let gave2, let got2)? = back.out.news.first else { Issue.record("\(back.out.news)"); return }
    #expect(gave2.dex == 64 && got2.dex == 19)
    let traded = try await db.count("SELECT count(*) AS n FROM mons WHERE state = 'traded'"), arrived = try await db.count("SELECT count(*) AS n FROM mons WHERE kind = 'trade'")
    #expect(traded == 2 && arrived == 2)

    // an item along: 롱스톤 + 금속코트 → 강철톤 at 보브's, the 코트 gone from 앨리스's bag
    #expect(try await go("앨리스", a, 6, .tradeOffer(to: "보브", give: 1_000_002, want: nil), at: 80).out.cannot == nil)
    let o2 = try JSONDecoder().decode(TradesReply.self, from: await db.trades(TeamReq(id: "보브", session: b), now: base.addingTimeInterval(81)).body).incoming[0].id
    #expect(try await go("보브", b, 4, .tradeAccept(id: o2, give: nil), at: 82).out.cannot == "줄 포켓몬을\n골라 주세요")
    let steel = try await go("보브", b, 5, .tradeAccept(id: o2, give: done.walk!.box[0].uid), at: 83)
    #expect(steel.walk?.box.contains { $0.dex == 208 } == true)
    #expect(try await go("앨리스", a, 7, .steps, at: 84).walk?.bag.contains("금속코트") == false)

    // declined, taken back, out of time
    #expect(try await go("앨리스", a, 8, .tradeOffer(to: "보브", give: 1_000_003, want: nil), at: 90).out.cannot == nil)
    let o3 = try JSONDecoder().decode(TradesReply.self, from: await db.trades(TeamReq(id: "보브", session: b), now: base.addingTimeInterval(91)).body).incoming[0].id
    #expect(try await go("보브", b, 6, .tradeDecline(id: o3), at: 92).out.cannot == nil)
    #expect(try await go("앨리스", a, 9, .steps, at: 93).out.news == [.tradeClosed(id: o3, with: "보브", why: "상대가 거절했어요")])
    #expect(try await go("앨리스", a, 10, .tradeOffer(to: "보브", give: 1_000_003, want: nil), at: 94).out.cannot == nil)
    #expect(try await go("보브", b, 7, .tradeAccept(id: o3 + 1, give: 1_000_002), at: 94 + 86_401).out.cannot == "그 교환은 이제\n없어요")
    let late = try await go("앨리스", a, 11, .steps, at: 94 + 86_402).out.news
    #expect(late == [.tradeClosed(id: o3 + 1, with: "보브", why: "시간이 지났어요")])
}

@Test func towerRunAcrossSessions() async throws {                                               // a run between fights survives a relaunch; one mid-fight ends
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let s1 = try await newTrainer(db, "타워")
    _ = await act(db, "타워", s1, 1, .steps, steps: 10, at: 60)
    try await setWalk(db, "타워") { $0.watts = 500; $0.towerStreak = 3 }
    var p = Play(); p.tower = true
    try await db.setPlay("타워", p)
    func login(_ t: Double) async throws -> (String, Bool?) {
        let r = await db.login(LoginReq(id: "타워", device: "mac", device_name: "MAC", app: "3.3", force: true, pin: "2468"), now: Int(base.timeIntervalSince1970 + t))
        return (try #require(string(r, "session")), flag(r, "tower"))
    }
    let (s2, carries) = try await login(100)
    #expect(carries == true)
    var o = try reply(await act(db, "타워", s2, 1, .tower, at: 101))                                   // the next trainer: no fee, the streak on
    #expect(o.out.battle?.trainer != nil && !o.out.changed && o.walk?.watts == 500 && o.walk?.towerStreak == 3)   // nothing paid (the save: a new session's first reply)
    let (s3, mid) = try await login(200)                                                              // a relaunch mid-fight: that run is over
    #expect(mid == false)
    o = try reply(await act(db, "타워", s3, 1, .steps, at: 201))
    #expect(o.walk?.towerStreak == 0 && o.walk?.towerBest == 3)
    o = try reply(await act(db, "타워", s3, 2, .tower, at: 202))
    #expect(o.walk?.watts == 450)                                                                     // a new run pays again
}
extension SaveDB { func setPlay(_ key: String, _ p: Play) throws { try db.rows("UPDATE play SET state = :s WHERE key = :k", ["s": .text(String(decoding: try JSONEncoder().encode(p), as: UTF8.self)), "k": .text(key)]) } }

@Test func adminChangesReachTheApp() async throws {                                              // a `pokeserver set` between acts: the next reply carries the save
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let s = try await newTrainer(db, "관리")
    #expect(try reply(await act(db, "관리", s, 1, .steps, steps: 10, at: 60)).walk != nil)          // a new session's first: always
    #expect(try reply(await act(db, "관리", s, 2, .steps, at: 61)).walk == nil)                     // nothing new
    _ = try await db.set("관리", path: "$.watts", value: "777", now: Int(base.timeIntervalSince1970) + 62)
    let o = try reply(await act(db, "관리", s, 3, .steps, at: 63))
    #expect(o.walk?.watts == 777 && o.out.changed == false)
    #expect(try reply(await act(db, "관리", s, 4, .steps, at: 64)).walk == nil)                     // once
}

@Test func coopRaid() async throws {                                                               // docs/plans/12 M3
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let a = try await newTrainer(db, "앨리스"), b = try await newTrainer(db, "보브")
    func go(_ who: String, _ s: String, _ seq: Int, _ act: Act, steps: Int? = nil, at t: Double) async throws -> ActReply {
        try reply(await db.act(ActReq(id: who, session: s, seq: seq, steps: steps, act: act, app: "3.4"), now: base.addingTimeInterval(t)))
    }
    _ = try await go("앨리스", a, 1, .steps, steps: 3000, at: 200)
    _ = try await go("보브", b, 1, .steps, steps: 3000, at: 200)
    try await setWalk(db, "앨리스") { w in                                                            // a party that can hurt a Lv.70 legend
        var c = Mon(dex: 445, level: 100, female: false); c.uid = firstUID; c.known = [89, 200, 337, 14]; c.ivs = Array(repeating: 31, count: 6); w.companion = c
    }
    var lobby = try JSONDecoder().decode(RaidReply.self, from: await db.raidLobby(TeamReq(id: "앨리스", session: a), now: base.addingTimeInterval(201)).body)
    #expect(raidRotation.contains(lobby.boss.dex) && lobby.boss.level == 70 && lobby.boss.perfectIVs >= 4)
    #expect(lobby.hpTotal == lobby.barHP * raidBarsPerFighter * 2 && lobby.hpLeft == lobby.hpTotal)          // two walked lately: 28 bars
    var seq = 2, t = 202.0
    var lastNews: [News] = []
    func fight(_ who: String, _ s: String, _ q: inout Int) async throws -> BattleEnd? {
        var o = try await go(who, s, q, .raid, at: t); q += 1; t += 1
        while let bt = o.out.battle, o.out.end == nil, o.out.cannot == nil {
            let x = bt.mine[bt.me], slot = x.pp.indices.first { x.pp[$0] > 0 && moveTable[x.moves[$0]]?.isStatus == false } ?? 0   // (프레셔: 2 PP a move)
            o = try await go(who, s, q, .battle(cmd: bt.mustReplace ? .replace(to: bt.mine.indices.first { bt.mine[$0].alive && $0 != bt.me } ?? 0) : .fight(slot: slot)), at: t); q += 1; t += 1
        }
        lastNews = o.out.news
        return o.out.end
    }
    let end = try #require(try await fight("앨리스", a, &seq))
    lobby = try JSONDecoder().decode(RaidReply.self, from: await db.raidLobby(TeamReq(id: "앨리스", session: a), now: base.addingTimeInterval(t)).body)
    #expect(lobby.hpLeft == lobby.hpTotal - (end.dealt ?? 0) && lobby.mine.fights == 1 && lobby.fighters.map(\.name) == ["앨리스"])
    #expect(try await go("앨리스", a, seq, .raidBall, at: t).out.cannot == "아직 보스가\n쓰러지지 않았어요"); seq += 1

    try await db.squeezeRaid(lobby.week, to: lobby.hpTotal - lobby.hpLeft + 1)                          // 1 HP left: the next fight beats it
    let last = try #require(try await fight("앨리스", a, &seq))
    #expect(last.dealt == 1 && (last.bp ?? 0) <= 1)                                                  // BP only for what counted: 1 HP = at most the one bar it finished
    #expect(lastNews.contains(.raidCleared(dex: lobby.boss.dex)))                                     // in the very reply that beat it
    var thrown = 0, caught = false
    while !caught {
        let o = try await go("앨리스", a, seq, .raidBall, at: t); seq += 1; t += 1
        guard let th = o.out.raidThrow else { #expect(o.out.cannot == "볼이 남아 있지\n않아요"); break }
        if thrown == 0 { #expect(th.reward && o.walk?.bag.filter { $0 == "이상한사탕" }.count == 5) } else { #expect(!th.reward) }
        thrown += 1; caught = th.caught
        if caught { #expect(th.mon?.dex == lobby.boss.dex && o.walk?.box.contains { $0.uid == th.mon?.uid } == true) }
    }
    #expect(thrown >= 1 && thrown <= 5)
    #expect(try await go("보브", b, 2, .raidBall, at: t).out.cannot == "이번 주에 싸워야\n잡을 수 있어요")   // didn't fight
    let z = try await newTrainer(db, "zz654321")                                                        // a tester: its own raid
    _ = try await go("zz654321", z, 1, .steps, steps: 10, at: t)
    let zl = try JSONDecoder().decode(RaidReply.self, from: await db.raidLobby(TeamReq(id: "zz654321", session: z), now: base.addingTimeInterval(t)).body)
    #expect(zl.week == lobby.week + "-test" && zl.hpLeft == zl.hpTotal)
}
extension SaveDB { func squeezeRaid(_ week: String, to total: Int) throws { try db.rows("UPDATE raids SET hp_total = :t WHERE week = :w", ["t": .int(total), "w": .text(week)]) } }
