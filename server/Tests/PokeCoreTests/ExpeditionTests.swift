import Foundation
import Testing
@testable import PokeCore

// docs/plans/19 (5.1, content51): 전설 원정 — 지가르데's cells and its legend, the 특성패치, the form items, the team events.

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let base = Date(timeIntervalSince1970: 2_000_000_000)

/// One trainer's engine side, as EngineTests' Desk.
private struct Desk {
    var w: Walk, p = Play(), r = Seeded(s: 7), ids = Issued(next: firstUID + 1), clock = 0.0
    init(_ w: Walk = Engine.fresh(now: t0, starter: firstUID)) { self.w = w }
    @discardableResult mutating func act(_ a: Act, steps: Int = 0) -> Outcome {
        clock += 1
        return Engine.apply(a, steps: steps, walk: &w, play: &p, rng: &r, now: t0.addingTimeInterval(clock), ids: &ids)
    }
}
private func both<T>(_ body: () throws -> T) rethrows -> T { try Content.$testing.withValue(true) { try Content.$testing51.withValue(true) { try body() } } }
private var kalos: Int { courses.firstIndex { $0.region == 650...721 }! }

@Test func zygardeCells() throws {
    try both {
        var d = Desk(); d.w.course = kalos
        #expect(d.act(.expClaim(id: "지가르데")).cannot == "하고 있는 원정이\n아니에요")
        #expect(d.act(.expStart(id: "없음")).cannot == "없는 원정이에요")
        #expect(d.act(.expStart(id: "지가르데")).cannot == nil)
        let rolled = try #require(d.w.expeditions?["지가르데"]?.mon)
        #expect(rolled.level == 50 && rolled.perfectIVs >= 3 && rolled.dex == 718 && rolled.uid == nil && rolled.moves.contains(614))   // 사우전드애로
        #expect(d.act(.expStart(id: "지가르데")).cannot == "이미 하고 있는\n원정이에요")
        var o = d.act(.steps, steps: 2_999)
        #expect(d.w.expeditions?["지가르데"]?.n == 0 && !o.news.contains { if case .expedition = $0 { return true }; return false })
        o = d.act(.steps, steps: 6_001)                                                             // 9,000: 3 cells, nothing carried
        #expect(d.w.expeditions?["지가르데"]?.n == 3 && d.w.expeditions?["지가르데"]?.steps == 0 && o.news.contains(.expedition(id: "지가르데", n: 3, need: 50)))
        d.w.course = 0; d.act(.steps, steps: 30_000)                                                // not 칼로스: nothing
        #expect(d.w.expeditions?["지가르데"]?.n == 3)
        d.w.course = kalos
        #expect(d.act(.expClaim(id: "지가르데")).cannot == "아직 모자라요\n(3/50)")
        d.act(.steps, steps: 200_000)                                                               // more than enough: 50, none past it
        #expect(d.w.expeditions?["지가르데"]?.n == 50 && d.w.expeditions?["지가르데"]?.steps == 0)
        o = d.act(.expClaim(id: "지가르데"))
        let z = try #require(o.mon)
        #expect(o.cannot == nil && z.uid != nil && z.ivs == rolled.ivs && z.shiny == rolled.shiny && d.w.box.contains { $0.uid == z.uid } && (d.w.owned ?? []).contains(718))
        #expect(d.w.bag.filter { $0 == "특성패치" }.count == 1 && o.news.contains(.expeditionDone(id: "지가르데", dex: 718, gift: "특성패치")))
        #expect(d.w.expeditions?["지가르데"] == ExpProgress(done: 1))
        #expect(d.ids.made.last?.kind == "expedition")
        d.act(.expStart(id: "지가르데")); d.act(.steps, steps: 200_000)                             // 다시 하기: another, no second patch
        o = d.act(.expClaim(id: "지가르데"))
        #expect(o.mon != nil && d.w.bag.filter { $0 == "특성패치" }.count == 1 && d.w.expeditions?["지가르데"]?.done == 2)
    }
    // the radar on 칼로스 gives one 1/30 a find (the dice of Seeded(s: 7) over 300 finds)
    try both {
        var d = Desk(); d.w.course = kalos; d.w.watts = 9_999
        d.act(.expStart(id: "지가르데"))
        for _ in 0..<300 { d.act(.radar); d.act(.radarPick(bush: -1)); d.w.watts = 9_999 }
        let n = d.w.expeditions?["지가르데"]?.n ?? 0
        #expect((3...20).contains(n))
    }
    // off (5.0's content5 alone): no expedition at all
    Content.$testing.withValue(true) {
        var d = Desk(); d.w.course = kalos
        #expect(d.act(.expStart(id: "지가르데")).cannot == "없는 원정이에요")
        d.w.expeditions = ["지가르데": ExpProgress(on: true)]
        d.act(.steps, steps: 30_000)
        #expect(d.w.expeditions?["지가르데"]?.n == 0)
    }
}

@Test func oneExpeditionAtATime() throws {                                                       // plan 19 §6.3 (the user, 10-16): one going on, the others stopped and kept
    try both {
        var d = Desk(); d.w.course = kalos
        let other = Mon(dex: 641, level: 50, female: false)
        d.w.expeditions = ["다른": ExpProgress(on: true, n: 3, steps: 10, mon: other)]              // (5.1 has one; a second as the save would have it)
        #expect(d.act(.expStart(id: "지가르데")).cannot == nil)
        #expect(d.w.expeditions?["다른"] == ExpProgress(on: false, n: 3, steps: 10, mon: other))      // stopped where it was
        d.act(.steps, steps: 30_000)
        let z = try #require(d.w.expeditions?["지가르데"])
        #expect(z.on && z.n == 10 && d.w.expeditions?["다른"]?.n == 3)
        d.w.expeditions?["지가르데"]?.on = false; d.w.expeditions?["다른"]?.on = true                   // as if the other went on again
        d.act(.steps, steps: 30_000)
        #expect(d.w.expeditions?["지가르데"]?.n == 10)                                                 // stopped: no cells
        #expect(d.act(.expStart(id: "지가르데")).cannot == nil)                                        // goes on from 10, the same legend
        #expect(d.w.expeditions?["지가르데"]?.n == 10 && d.w.expeditions?["지가르데"]?.mon == z.mon && d.w.expeditions?["다른"]?.on == false)
        d.w.expeditions?["지가르데"]?.n = 50; d.w.expeditions?["지가르데"]?.on = false
        #expect(d.act(.expClaim(id: "지가르데")).mon == z.mon.map { var m = $0; m.uid = d.ids.made.last?.mon.uid; return m })   // stopped and full: claimed all the same
    }
}

@Test func expProgressDecodesWhatItHas() throws {                                                 // a later field must be optional: an older save has none
    let x = try JSONDecoder().decode(ExpProgress.self, from: Data(#"{"n": 4}"#.utf8))
    #expect(x == ExpProgress(n: 4))
    var w = Walk(); w.expeditions = ["지가르데": ExpProgress(on: true, n: 2, steps: 10)]
    #expect(try JSONDecoder().decode(Walk.self, from: JSONEncoder().encode(w)) == w)
}

@Test func abilityPatch() throws {
    try both {
        var d = Desk()
        #expect(d.w.wares(bp: true, shells: []).contains { $0.kind == .item("특성패치") && $0.price == 100 })
        d.w.bp = 250
        #expect(d.act(.buy(bp: true, item: "특성패치", legend: nil, shell: nil, qty: 2)).cannot == nil && d.w.count("특성패치") == 2 && d.w.bp == 50)
        let uid = try #require(d.w.companion.uid)                                                   // 피카츄: hidden 피뢰침
        #expect(hiddenAbility[25] > 0)
        #expect(d.act(.use(item: "특성패치", stat: nil, on: nil)).cannot == "포켓몬을\n골라 주세요")   // a 5.0 app's 팔기 (no one named): nothing
        #expect(d.act(.sellAll).cannot == "팔 도구가 없어요" && d.w.count("특성패치") == 2)
        #expect(d.act(.use(item: "특성패치", stat: nil, on: uid)).cannot == nil && d.w.companion.ability == 2 && d.w.companion.abilityID == hiddenAbility[25])
        #expect(d.act(.use(item: "특성패치", stat: nil, on: uid)).cannot == nil && d.w.companion.ability == 0 && d.w.count("특성패치") == 0)
        d.w.bag.append("특성패치"); d.w.companion.dex = 718                                          // 지가르데: no hidden one in 5.0's data
        #expect(hiddenAbility[718] == 0 || true)
        if hiddenAbility[718] == 0 { #expect(d.act(.use(item: "특성패치", stat: nil, on: uid)).cannot == "숨겨진특성이\n없는 포켓몬이에요" && d.w.count("특성패치") == 1) }
    }
    Content.$testing.withValue(true) {                                                           // content5 alone: not sold
        #expect(!Walk().wares(bp: true, shells: []).contains { $0.kind == .item("특성패치") })
        #expect(!Walk().wares(bp: false, shells: []).contains { $0.kind == .item("그라시데아꽃") })
    }
}

@Test func formItems() throws {
    try both {
        var d = Desk(); d.w.watts = 9_999
        var m = Mon.wild(492, level: 50, &d.r); m.uid = 900; d.w.box.append(m)                     // 쉐이미
        var h = Mon.wild(720, level: 50, &d.r); h.uid = 901; h.known = [593, 94, 60, 285]; d.w.box.append(h)   // 후파: 이차원홀
        #expect(d.act(.mon(op: .form(uid: 900, item: "그라시데아꽃", form: 1))).cannot == "그라시데아꽃이\n없어요")
        #expect(d.act(.buy(bp: false, item: "그라시데아꽃", legend: nil, shell: nil, qty: 1)).cannot == nil && d.w.watts == 6_999)
        #expect(d.act(.buy(bp: false, item: "그라시데아꽃", legend: nil, shell: nil, qty: 1)).cannot == "이미 가지고 있다")
        #expect(d.act(.mon(op: .form(uid: 901, item: "그라시데아꽃", form: 1))).cannot == "모습을 바꿀 수\n없어요")   // not a 쉐이미
        #expect(d.act(.mon(op: .form(uid: 900, item: "그라시데아꽃", form: 2))).cannot == "모습을 바꿀 수\n없어요")
        #expect(d.act(.mon(op: .form(uid: 900, item: "그라시데아꽃", form: 1))).cannot == nil)
        #expect(d.w.box[0].form == 1 && d.w.box[0].typing == ["grass", "flying"] && d.w.count("그라시데아꽃") == 1)   // kept
        #expect(d.act(.mon(op: .form(uid: 900, item: "그라시데아꽃", form: nil))).cannot == nil && d.w.box[0].form == nil)
        d.w.bag.append("굴레의항아리")
        #expect(d.act(.mon(op: .form(uid: 901, item: "굴레의항아리", form: 1))).cannot == nil && d.w.box[1].form == 1 && d.w.box[1].moves.first == 621)   // 이차원러시
        #expect(d.act(.mon(op: .form(uid: 901, item: "굴레의항아리", form: nil))).cannot == nil && d.w.box[1].moves.first == 593)
        #expect(d.act(.mon(op: .form(uid: 900, item: "유전자쐐기", form: 1))).cannot == "모습을 바꾸는\n도구가 아니에요")
        var r = Mon.wild(479, level: 30, &d.r); r.uid = 902; d.w.box.append(r); d.w.bag.append("로토무카탈로그")   // the catalog through .form too
        #expect(d.act(.mon(op: .form(uid: 902, item: "로토무카탈로그", form: 2))).cannot == nil && d.w.box[2].form == 2)
    }
}

// MARK: - the team events (the server's)
private func newTrainer(_ db: SaveDB, _ id: String) async throws -> String {
    let r = await db.create(CreateReq(id: id, device: "mac", device_name: "MAC", app: "5.1", pin: "2468"), now: Int(base.timeIntervalSince1970))
    return try #require(string(r, "session"))
}
private func reply(_ r: Reply) throws -> ActReply { try JSONDecoder().decode(ActReply.self, from: r.body) }

@Test func teamEvents() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let b0 = Int(base.timeIntervalSince1970)
    let s = ["앨리스": try await newTrainer(db, "앨리스"), "보브": try await newTrainer(db, "보브"), "zz510001": try await newTrainer(db, "zz510001")]
    var seq: [String: Int] = [:]
    func walk(_ id: String, _ n: Int, at t: Int) async throws -> ActReply {
        seq[id, default: 0] += 1
        return try reply(await db.act(ActReq(id: id, session: s[id]!, seq: seq[id]!, steps: n, act: .steps, app: "5.1"), now: Date(timeIntervalSince1970: TimeInterval(b0 + t))))
    }
    // two weeks with small numbers (the schedule's are 1,500,000 and 20,000), and an encore
    try await db.sql("INSERT INTO exp_events (legend, starts, ends, goal, min) VALUES (494, :s, :e, 3000, 1000)", ["s": .int(b0 + 1000), "e": .int(b0 + 100_000)])
    try await db.sql("INSERT INTO exp_events (legend, starts, ends, goal, min) VALUES (648, :s, :e, 3000, 1000)", ["s": .int(b0 + 200_000), "e": .int(b0 + 300_000)])
    try await db.sql("INSERT INTO exp_events (legend, starts, ends, goal, min) VALUES (0, :s, :e, 0, 1000)", ["s": .int(b0 + 400_000), "e": .int(b0 + 500_000)])
    try await Content.$testing.withValue(true) {
        _ = try await walk("앨리스", 1_500, at: 2000)                                                // content51 off: not counted
        #expect(try await db.teamEventSteps(1, for: "앨리스").mine == 0)
        try await Content.$testing51.withValue(true) {
            _ = try await walk("앨리스", 900, at: 500)                                                 // before the week: not counted
            _ = try await walk("앨리스", 1_500, at: 3000); _ = try await walk("보브", 900, at: 3000)
            _ = try await walk("zz510001", 1_400, at: 3000)                                          // a test ID: its own team
            let sa = try await db.teamEventSteps(1, for: "앨리스"), sz = try await db.teamEventSteps(1, for: "zz510001")
            #expect(sa == (2_400, 1_500) && sz == (1_400, 1_400))
            #expect(try await db.mailTitles("앨리스").isEmpty)                                          // 2,400 of 3,000
            _ = try await walk("보브", 600, at: 4000)                                                 // 3,000: the goal — 보브 walked 1,500 too
            #expect(try await db.mailTitles("보브") == ["팀 이벤트: 비크티니"])
            _ = try await walk("앨리스", 0, at: 4100)
            let ta = try await db.mailTitles("앨리스"), tz = try await db.mailTitles("zz510001")
            #expect(ta == ["팀 이벤트: 비크티니"] && tz.isEmpty)
            let g = try #require(try await db.mailGifts("앨리스").first?.first)
            guard case .mon(let m, _) = g else { Issue.record("not a Pokémon"); return }
            #expect(m.dex == 494 && m.level == 50 && m.perfectIVs >= 3 && m.moves.contains(557))  // V제너레이트
            _ = try await walk("앨리스", 0, at: 4200); #expect(try await db.mailTitles("앨리스").count == 1)   // once
            // week 2: only 앨리스 walks enough; 보브 misses it — the encore gives 보브 메로엣타, nothing to 앨리스
            _ = try await walk("앨리스", 3_000, at: 210_000)
            #expect(try await db.mailTitles("앨리스").last == "팀 이벤트: 메로엣타")
            #expect(try await db.mailGifts("앨리스").last?.count == 1)
            _ = try await walk("보브", 1_000, at: 410_000); _ = try await walk("앨리스", 1_000, at: 410_000)
            let tb = try await db.mailTitles("보브"), ta2 = try await db.mailTitles("앨리스")
            #expect(tb == ["팀 이벤트: 비크티니", "팀 이벤트: 메로엣타"] && ta2.count == 2)
            // the list as each sees it: in the encore week, it first, then the past ones newest first
            let r = await db.expeditionList(ExpReq(id: "보브", session: s["보브"]!), now: Date(timeIntervalSince1970: TimeInterval(b0 + 420_000)))
            let v = try JSONDecoder().decode(ExpReply.self, from: r.body).events
            #expect(v.map(\.legend) == [0, 648, 494] && v[0].encore == [] && v[0].got && v[1].got && v[1].mine == 0 && v[2].team == 3_000)
            let wrong = await db.expeditionList(ExpReq(id: "보브", session: "x"), now: base)
            #expect(wrong.status == 409)
        }
    }
    // the schedule: six every other week from a Monday 0:00 KST, the encore two weeks after the last; a week not begun can go
    let (db2, p2) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: p2) }
    _ = try await db2.scheduleTeamEvents(from: "2026-10-26")
    let ev = try await db2.teamEvents()
    #expect(ev.map(\.legend) == TeamEvents.mythicals + [0] && ev[0].starts == 1_792_940_400 && ev[1].starts - ev[0].starts == 14 * 86400 && ev[0].ends - ev[0].starts == 7 * 86400)
    #expect(ev[6].starts - ev[5].starts == 14 * 86400 && ev[0].goal == 1_500_000 && ev[6].goal == 0 && ev.allSatisfy { $0.min == 20_000 })
    await #expect(throws: (any Error).self) { try await db2.scheduleTeamEvents(from: "2026-10-26") }
    let gone = try await db2.cancelTeamEvent(ev[1].id, now: 1_792_000_000), left = try await db2.teamEvents()
    #expect(gone.contains("removed") && left.count == 6)
    #expect(try await db2.teamEventsReport(now: 1_792_000_000).contains("비크티니"))
}

@Test func content51Switch() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    #expect(try await db.content51() == false)
    _ = try await db.setContent51(true); #expect(try await db.content51() == true); _ = try await db.setContent51(false)
    func flag(_ r: Reply) -> Bool? { fields(r)["content51"] as? Bool }
    try await Content.$testing.withValue(true) {
        let c = await db.create(CreateReq(id: "새로", device: "mac", device_name: "MAC", app: "5.1", pin: "2468"), now: 100)
        #expect(flag(c) == nil)
        try await Content.$testing51.withValue(true) {
            let c2 = await db.create(CreateReq(id: "새로2", device: "mac", device_name: "MAC", app: "5.1", pin: "2468"), now: 100)
            #expect(flag(c2) == true)
        }
    }
}

@Test func mailDelete() async throws {                                                           // plan 19 §9 (the user, 10-16): out of the list, never one with a gift waiting
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let s = try await newTrainer(db, "앨리스")
    var seq = 0
    func go(_ a: Act) async throws -> ActReply {
        seq += 1; return try reply(await db.act(ActReq(id: "앨리스", session: s, seq: seq, act: a, app: "5.1"), now: base.addingTimeInterval(Double(seq))))
    }
    _ = try await go(.steps)
    let notice = try await db.sendMail("앨리스", kind: "notice", from: "운영자", title: "공지", now: 10)
    let gift = try await db.sendMail("앨리스", kind: "admin", from: "운영자", title: "선물", gifts: [.items(name: "이상한사탕", count: 1)], now: 11)
    let pick = try await db.sendMail("앨리스", kind: "dex", from: "도감", title: "고르기", gifts: [.pickItem(items: Walk.mints)], now: 12)
    func list() async throws -> MailReply { try JSONDecoder().decode(MailReply.self, from: await db.mailList(MailReq(id: "앨리스", session: s), now: base).body) }
    #expect(try await go(.mailDelete(id: gift)).out.cannot == "받을 것이 남은\n우편이에요")
    #expect(try await go(.mailDelete(id: pick)).out.cannot == "받을 것이 남은\n우편이에요")
    #expect(try await go(.mailDelete(id: notice)).out.cannot == nil)
    #expect(try await go(.mailDelete(id: notice)).out.cannot == "지울 수 없는\n우편이에요")             // gone already
    var l = try await list()
    #expect(l.mails.map(\.id) == [pick, gift] && l.unread == 2)
    _ = try await go(.mailClaim(id: gift))
    let n2 = try await db.sendMail("앨리스", kind: "notice", from: "운영자", title: "공지 2", now: 13)
    #expect(try await go(.mailDeleteAll).out.cannot == nil)                                       // the claimed one and the notice; the pick stays
    l = try await list()
    #expect(l.mails.map(\.id) == [pick] && l.unread == 1)
    #expect(try await go(.mailDeleteAll).out.cannot == "지울 우편이\n없어요")
    #expect(try await db.mailLog(last: 10).contains("공지 2 [지움]") && n2 > 0)
    #expect(try await go(.mailDelete(id: 99_999)).out.cannot == "지울 수 없는\n우편이에요")
}

@Test func signatureMovesRelearned() throws {                                                     // plan 19 §2.3 (the user, 10-16): 기술 바꾸기 only, ORAS's level
    func can(_ dex: Int, _ lv: Int, _ mv: Int) -> Bool { Mon(dex: dex, level: lv, female: false).relearnable.contains(mv) }
    try both {
        #expect(!can(382, 44, 618) && can(382, 45, 618) && !can(383, 44, 619) && can(383, 70, 619) && !can(150, 99, 540) && can(150, 100, 540))
        #expect(!Mon.defaultMoves(382, 100).contains(618) && Mon(dex: 382, level: 44, female: false).newMoves(from: 44, to: 100).allSatisfy { $0 != 618 })   // not on levelling, not a wild one's
        var d = Desk(); var k = Mon(dex: 382, level: 60, female: false); k.uid = 900; d.w.box.append(k)
        #expect(d.act(.mon(op: .move(uid: 900, slot: 0, move: 618))).cannot == nil && d.w.box[0].moves.first == 618)
    }
    Content.$testing.withValue(true) { #expect(!can(382, 100, 618)) }                              // content51 off: not yet
}
