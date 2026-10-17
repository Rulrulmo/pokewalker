import Foundation
import Testing
@testable import PokeCore

// docs/plans/23 (5.1.3, evo-choice): 배루키 waits at Lv.20 for the player's pick — MonOp.evolve(uid:to:) — wherever it is; off, its steps pick
// at the level-up as before.

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private struct Desk {
    var w: Walk, p = Play(), r = Seeded(s: 23), ids = Issued(next: firstUID + 100), clock = 0.0
    @discardableResult mutating func act(_ a: Act, steps: Int = 0) -> Outcome {
        clock += 1
        return Engine.apply(a, steps: steps, walk: &w, play: &p, rng: &r, now: t0.addingTimeInterval(clock), ids: &ids)
    }
}
/// A 배루키 one EXP short of Lv.20 (or at `level`), with its own moves.
private func tyrogue(_ uid: Int, level: Int = 19, shy: Bool = true) -> Mon {
    var m = Mon(dex: 236, level: level, female: false); m.uid = uid; m.known = [33, 252]
    if shy { m.exp = expTable[growthRate[236]][20] - 1 }
    return m
}
private func evolved(_ o: Outcome, _ u: Int) -> Int? { o.news.lazy.compactMap { n -> Int? in if case .evolve(u, 236, let to, nil) = n { return to }; return nil }.first }

@Test func evoChoiceOffAsBefore() {
    var w = Engine.fresh(now: t0, starter: firstUID); w.companion = tyrogue(firstUID)
    var d = Desk(w: w)
    let o = d.act(.steps, steps: 40)
    #expect(d.w.companion.level >= 20 && [106, 107, 237].contains(d.w.companion.dex) && evolved(o, firstUID) == d.w.companion.dex)   // its steps picked, at once
    var b = Engine.fresh(now: t0, starter: firstUID); b.box = [tyrogue(firstUID + 1, level: 25, shy: false)]
    var e = Desk(w: b)
    #expect(e.w.evoChoices(t0, ref: 0).isEmpty && e.w.evoReady(t0).isEmpty)
    #expect(e.act(.mon(op: .evolve(uid: firstUID + 1, to: 237))).cannot == "고를 수 있는\n진화가 아니에요")
}

@Test func evoChoiceWaitsAndPicks() {
    Content.$testingChoice.withValue(true) {
        var w = Engine.fresh(now: t0, starter: firstUID); w.companion = tyrogue(firstUID); w.companion.shiny = true
        var d = Desk(w: w)
        let o = d.act(.steps, steps: 40)
        #expect(d.w.companion.level >= 20 && d.w.companion.dex == 236 && evolved(o, firstUID) == nil)                // Lv.20: it waits
        #expect(o.news.contains(.level(uid: firstUID, level: d.w.companion.level)))
        #expect(d.w.evoChoices(t0).map(\.to) == [106, 107, 237] && d.w.evoReady(t0) == [firstUID])
        #expect(d.act(.steps, steps: 4000).news.allSatisfy { if case .evolve = $0 { false } else { true } } && d.w.companion.dex == 236)   // more levels: still waiting
        #expect(d.act(.mon(op: .evolve(uid: firstUID, to: 25))).cannot == "그 모습으로는\n진화할 수 없어요")
        #expect(d.act(.mon(op: .evolve(uid: firstUID + 50, to: 237))).cannot == "그 포켓몬은\n없어요")
        let lv = d.w.companion.level, moves = d.w.companion.moves
        let pick = d.act(.mon(op: .evolve(uid: firstUID, to: 237)))
        #expect(pick.cannot == nil && d.w.companion.dex == 237 && d.w.companion.uid == firstUID && d.w.companion.level == lv && evolved(pick, firstUID) == 237)
        #expect(d.w.companion.shiny == true && d.w.companion.moves == moves)                                            // 이로치 and its moves as they were
        #expect((d.w.owned ?? []).contains(237) && (d.w.shinyOwned ?? []).contains(237) && pick.news.contains(.dex(count: (d.w.owned ?? []).count)))
        let ls = learnsets[237], upTo = stride(from: 0, to: ls.count, by: 2).filter { ls[$0] <= lv && Moves.supported(ls[$0 + 1]) }.map { ls[$0 + 1] }
        #expect(!upTo.isEmpty && upTo.allSatisfy(d.w.companion.relearnable.contains))             // 기술 바꾸기: every 카포에라 move up to its level (a late pick misses none)
        #expect(d.w.evoReady(t0).isEmpty && d.act(.mon(op: .evolve(uid: firstUID, to: 106))).cannot == "고를 수 있는\n진화가 아니에요")
    }
}

@Test func evoChoiceWalkerBoxAndStone() {
    Content.$testingChoice.withValue(true) {
        var w = Engine.fresh(now: t0, starter: firstUID)
        w.caught = [tyrogue(firstUID + 1)]                                                         // on the walker, a level-up away
        w.box = [tyrogue(firstUID + 2, level: 25, shy: false), tyrogue(firstUID + 3, level: 15, shy: false), tyrogue(firstUID + 4, level: 30, shy: false)]
        w.box[2].item = "변함없는돌"
        var wurmple = Mon(dex: 265, level: 6, female: false); wurmple.uid = firstUID + 5; wurmple.exp = expTable[growthRate[265]][7] - 1
        w.caught.append(wurmple); w.lastUID = firstUID + 5
        var d = Desk(w: w)
        #expect(d.w.evoReady(t0) == [firstUID + 2])                                                // already Lv.25 in the box: ready at once
        let o = d.act(.steps, steps: 40)
        #expect(d.w.caught[0].dex == 236 && d.w.caught[0].level >= 20 && evolved(o, firstUID + 1) == nil)   // the walker's waits too
        #expect([266, 268].contains(d.w.caught[1].dex))                                           // 개무소: its steps, as before
        #expect(d.w.evoReady(t0) == [firstUID + 1, firstUID + 2])
        #expect(d.act(.mon(op: .evolve(uid: firstUID + 3, to: 106))).cannot == "Lv.20부터\n진화할 수 있어요")
        #expect(d.act(.mon(op: .evolve(uid: firstUID + 4, to: 106))).cannot == "변함없는돌을\n지니고 있어요")
        #expect(d.act(.mon(op: .hold(uid: firstUID + 4, item: nil))).cannot == nil && d.w.evoReady(t0).contains(firstUID + 4))   // taken off: ready, no level-up needed
        #expect(d.act(.mon(op: .evolve(uid: firstUID + 2, to: 106))).cannot == nil && d.w.box[0].dex == 106)
        #expect(d.act(.mon(op: .evolve(uid: firstUID + 1, to: 107))).cannot == nil && d.w.caught[0].dex == 107)
        #expect(d.act(.mon(op: .evolve(uid: firstUID + 5, to: 267))).cannot == "고를 수 있는\n진화가 아니에요")
    }
    var w = Engine.fresh(now: t0, starter: firstUID); w.companion = tyrogue(firstUID, level: 22, shy: false)   // switched off with one waiting:
    w.companion.exp = expTable[growthRate[236]][23] - 1
    var d = Desk(w: w)
    #expect(d.act(.steps).news.isEmpty && d.w.companion.dex == 236)                               // its steps pick at its next level-up
    #expect([106, 107, 237].contains(evolved(d.act(.steps, steps: 40), firstUID) ?? 0))
}

@Test func evoChoiceSwitch() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    func flag(_ r: Reply) -> Bool? { fields(r)["evoChoice"] as? Bool }                            // the app's Content.onChoice (login and create)
    #expect(flag(await db.create(CreateReq(id: "고르기전", device: "mac", device_name: "MAC", app: "5.1.3", pin: "2468"), now: 100)) == nil)
    await Content.$testingChoice.withValue(true) {
        #expect(flag(await db.create(CreateReq(id: "고르기", device: "mac", device_name: "MAC", app: "5.1.3", pin: "2468"), now: 100)) == true)
        #expect(flag(await db.login(LoginReq(id: "고르기", device: "mac", device_name: "MAC", app: "5.1.3", force: true, pin: "2468"), now: 200)) == true)
    }
    #expect(try await db.evoChoice() == false)
    _ = try await db.setEvoChoice(true); #expect(try await db.evoChoice() == true)
    _ = try await db.setEvoChoice(false); #expect(try await db.evoChoice() == false)
    let mon = try JSONDecoder().decode(Act.self, from: JSONEncoder().encode(Act.mon(op: .evolve(uid: 7, to: 237))))   // the wire: {"mon":{"op":{"evolve":{"uid":7,"to":237}}}}
    #expect(mon == .mon(op: .evolve(uid: 7, to: 237)))
    #expect(String(decoding: try JSONEncoder().encode(MonOp.evolve(uid: 7, to: 237)), as: UTF8.self).contains(#""evolve""#))
}
