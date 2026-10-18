import Foundation
import Testing
@testable import PokeCore

// docs/plans/24 (5.1.4, duel-mega): Mega Evolution in live battles — a duel started with both apps 5.1.4 on (and the switch) allows .megaFight,
// once a side; 원시회귀 on coming out as ever; the second player's mirrored view (megaUsed its own, the lines worded for it, stones whole).

private let base = Date(timeIntervalSince1970: 2_000_000_000)
private func reply(_ r: Reply) throws -> ActReply { try JSONDecoder().decode(ActReply.self, from: r.body) }
private func newTrainer(_ db: SaveDB, _ id: String) async throws -> String {
    let r = await db.create(CreateReq(id: id, device: "mac", device_name: "MAC", app: "5.1.3", pin: "2468"), now: Int(base.timeIntervalSince1970))
    return try #require(string(r, "session"))
}
private func setWalk(_ db: SaveDB, _ key: String, _ change: (inout Walk) -> Void) async throws {
    let t = try #require(try await db.trainer(key)), text = try #require(t.walk)
    var w = try #require(decodeWalk(text)); change(&w)
    try await db.setRaw(key, savedText(w))
}
private func mon(_ dex: Int, _ uid: Int, item: String? = nil, known: [Int]? = nil) -> Mon {
    var m = Mon(dex: dex, level: 60, female: false); m.uid = uid; m.item = item; m.known = known; return m
}
private func megas(_ beats: [Beat]) -> [(Side, String)] { beats.compactMap { if case .mega(let s, _, let t) = $0 { (s, t) } else { nil } } }

@Test func duelMega() async throws {
    try await Content.$testing.withValue(true) { try await Content.$testingDuelMega.withValue(true) {
        let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
        let sess = ["앨리스": try await newTrainer(db, "앨리스"), "보브": try await newTrainer(db, "보브"), "캐럴": try await newTrainer(db, "캐럴")]
        var seq = ["앨리스": 1, "보브": 1, "캐럴": 1], t = 60.0
        let apps = ["앨리스": "5.1.4", "보브": "5.1.4", "캐럴": "5.1.3"]
        func go(_ who: String, _ x: Act, steps: Int? = nil) async throws -> ActReply {
            t += 1; defer { seq[who]! += 1 }
            return try reply(await db.act(ActReq(id: who, session: sess[who]!, seq: seq[who]!, steps: steps, act: x, app: apps[who]), now: base.addingTimeInterval(t)))
        }
        func look(_ who: String, since: Int = 0) async throws -> DuelView {
            try #require(try JSONDecoder().decode(DuelReply.self, from: await db.duel(DuelReq(id: who, session: sess[who]!, since: since), now: base.addingTimeInterval(t)).body).duel)
        }
        for who in ["앨리스", "보브", "캐럴"] { _ = try await go(who, .steps, steps: 10) }
        try await setWalk(db, "앨리스") { $0.companion = mon(384, firstUID, known: [620, 337, 245, 200]); $0.caught = [mon(6, firstUID + 1, item: "리자몽나이트X"), mon(9, firstUID + 2)] }   // 레쿠쟈 (화룡점정)
        try await setWalk(db, "보브") { $0.companion = mon(6, firstUID, item: "리자몽나이트Y"); $0.caught = [mon(382, firstUID + 1, item: "쪽빛구슬"), mon(3, firstUID + 2)] }
        try await setWalk(db, "캐럴") { $0.companion = mon(6, firstUID, item: "리자몽나이트Y"); $0.caught = [mon(143, firstUID + 1), mon(3, firstUID + 2)] }
        for (x, y) in [("앨리스", "보브"), ("앨리스", "캐럴")] { _ = try await go(x, .friendRequest(to: y)); _ = try await go(y, .friendRequest(to: x)) }
        for who in ["앨리스", "보브", "캐럴"] { #expect(try await go(who, .duelParty(uids: [firstUID, firstUID + 1, firstUID + 2])).out.cannot == nil) }
        func start(_ x: String, _ y: String, theirs: [Int] = [0, 1, 2]) async throws -> Int {
            let id = try #require(try await go(x, .duelChallenge(to: y)).out.duel?.id)
            _ = try await go(y, .duelAccept(id: id)); _ = try await go(y, .duelPick(id: id, slots: theirs)); _ = try await go(x, .duelPick(id: id, slots: [0, 1, 2]))
            return id
        }
        func end(_ id: Int, _ x: String, _ y: String) async throws {                                  // give up as soon as one may (a replacement first, if owed)
            for _ in 0..<6 {
                for who in [x, y] {
                    let v = try await look(who)
                    guard v.state == "active", let need = v.need, let b = v.battle else { continue }
                    _ = try await go(who, .duelMove(id: id, cmd: need == "move" ? .forfeit : .replace(to: b.mine.indices.first { b.mine[$0].alive && $0 != b.me } ?? 0)))
                }
                if try await look(x).state == "over" { return }
            }
        }

        // both 5.1.4: allowed, each side once — 보브 alone first (his view: megaUsed his own), then 앨리스's 메가레쿠쟈
        let id = try await start("앨리스", "보브")
        var av = try await look("앨리스"), bv = try await look("보브")
        #expect(av.state == "active" && av.mega == true && bv.mega == true && av.battle?.canMega(.me) == true && bv.battle?.canMega(.me) == true)
        #expect(try await go("앨리스", .duelMove(id: id, cmd: .fight(slot: 1))).out.cannot == nil)               // 드래곤클로, no Mega
        #expect(try await go("보브", .duelMove(id: id, cmd: .megaFight(slot: 0))).out.cannot == nil)
        av = try await look("앨리스"); bv = try await look("보브")
        let bm = megas(bv.beats), am = megas(av.beats)
        #expect(bm.count == 1 && bm[0].0 == .me && bm[0].1.hasPrefix("리자몽의 리자몽나이트Y") && bm[0].1.contains("\n리자몽은 메가리자몽Y로 메가진화했다!") && !bm[0].1.contains("상대"))
        #expect(am.count == 1 && am[0].0 == .it && am[0].1.hasPrefix("상대 리자몽의 리자몽나이트Y") && am[0].1.contains("상대 리자몽은 메가리자몽Y로"))
        #expect(av.battle?.megaUsed == [false, true] && bv.battle?.megaUsed == [true, false])                     // each sees its own first
        #expect(av.battle?.canMega(.me) == true && bv.battle?.canMega(.me) == false)
        if bv.need == "replace" { _ = try await go("보브", .duelMove(id: id, cmd: .replace(to: 2))) }
        if (try await look("보브")).need == "move" {
            #expect(try await go("보브", .duelMove(id: id, cmd: .megaFight(slot: 0))).out.cannot == "메가진화할 수\n없다!")   // once a side
            #expect(try await go("보브", .duelMove(id: id, cmd: .fight(slot: 0))).out.cannot == nil)
        }
        if (try await look("앨리스")).need == "move" {
            let n = (try await look("앨리스")).turn
            #expect(try await go("앨리스", .duelMove(id: id, cmd: .megaFight(slot: 0))).out.cannot == nil)
            av = try await look("앨리스", since: n); bv = try await look("보브", since: n)
            if bv.turn > n {                                                                               // the turn played (the other's pick was in)
                let a2 = megas(av.beats), b2 = megas(bv.beats)
                #expect(a2.count == 1 && a2[0].0 == .me && a2[0].1 == "레쿠쟈는 화룡점정의 힘에 휩싸였다!\n레쿠쟈는 메가레쿠쟈로 메가진화했다!")
                #expect(b2.count == 1 && b2[0].0 == .it && b2[0].1 == "상대 레쿠쟈는 화룡점정의 힘에 휩싸였다!\n상대 레쿠쟈는 메가레쿠쟈로 메가진화했다!")
                #expect(av.battle?.megaUsed == [true, true] && bv.battle?.megaUsed == [true, true])
            }
        }
        try await end(id, "앨리스", "보브")
        #expect(try await look("앨리스").state == "over")

        // a 5.1.3 app in it: no Mega on either side (its menu hides the button)
        let id2 = try await start("앨리스", "캐럴")
        av = try await look("앨리스")
        let cv = try await look("캐럴")
        #expect(av.state == "active" && av.mega == nil && cv.mega == nil)
        #expect(try await go("앨리스", .duelMove(id: id2, cmd: .megaFight(slot: 0))).out.cannot == "이번 대전에서는\n메가진화를 쓸 수 없어요")
        try await end(id2, "앨리스", "캐럴")

        // 원시회귀 as it comes out (no switch, no pick): 보브 leads with 가이오가 — his view his own, worded so; 앨리스's the other's
        let id3 = try await start("앨리스", "보브", theirs: [1, 0, 2])
        av = try await look("앨리스"); bv = try await look("보브")
        #expect(megas(bv.beats).map { "\($0.0)" + $0.1 } == ["me가이오가의 원시회귀!\n고대의 모습을 되찾았다!"])
        #expect(megas(av.beats).map { "\($0.0)" + $0.1 } == ["it상대 가이오가의 원시회귀!\n고대의 모습을 되찾았다!"])
        #expect(av.mega == true && bv.battle?.canMega(.me) == false)                                     // (a primal one is no Mega to come)
        // the switch off: a new duel has none; one going on loses it at once (its view, the move)
        let (offView, offMove) = try await Content.$testingDuelMega.withValue(false) { () async throws -> (DuelView, ActReply) in
            (try await look("앨리스"), try await go("앨리스", .duelMove(id: id3, cmd: .megaFight(slot: 0))))
        }
        #expect(offView.mega == nil && offMove.out.cannot == "이번 대전에서는\n메가진화를 쓸 수 없어요")
        try await end(id3, "앨리스", "보브")
        let offNew = try await Content.$testingDuelMega.withValue(false) { () async throws -> DuelView in
            let id4 = try await start("보브", "앨리스"); let v = try await look("보브")
            try await end(id4, "보브", "앨리스"); return v
        }
        #expect(offNew.state == "active" && offNew.mega == nil)
    } }
}

/// Both players Mega Evolve the same turn: before any move, the faster first (Gen VI: the turn's order as it was before them).
@Test func duelMegaBothOneTurn() {
    Content.$testing.withValue(true) {
        var x = mon(6, 1, item: "리자몽나이트X"), y = mon(445, 2, item: "한카리아스나이트")
        x.level = 50; y.level = 50
        var b = Battle(party: [x], trainer: "앨리스", foes: [y]); b.pvp = true
        var g = Seeded(s: 24); _ = b.begin(weather: nil, &g)
        let fasterIsGarchomp = b.speed(.it) > b.speed(.me)
        b.foePlan = .megaFight(b.f(.it).moves[0])
        let beats = b.turn(.megaFight(b.f(.me).moves[0]), &g)
        let order = beats.compactMap { if case .mega(let s, _, _) = $0 { s } else { nil } }
        #expect(order == (fasterIsGarchomp ? [.it, .me] : [.me, .it]))
        let firstUse = beats.firstIndex { if case .use = $0 { true } else { false } } ?? beats.count
        let lastMega = beats.lastIndex { if case .mega = $0 { true } else { false } } ?? 0
        #expect(lastMega < firstUse && b.megaUsed == [true, true] && b.mine[0].mega != nil && b.theirs[0].mega != nil)
    }
}
