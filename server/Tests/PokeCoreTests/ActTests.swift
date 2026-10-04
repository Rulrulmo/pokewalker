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
