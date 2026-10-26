import Foundation
import Testing
@testable import PokeCore

// docs/plans/25 (5.2.2): 즐겨찾기 — Mon.fav (true or nil), .mon(.fav) wherever the Pokémon is, the chain and the radar kept, kept through
// what changes a Pokémon of ours, 중복 놓아주기 skipping it, a single release refused (the trades: ActTests.favGoneWhenTraded).

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// One trainer's engine side, as Exp52Tests' Desk.
private struct Desk {
    var w: Walk, p = Play(), r = Seeded(s: 7), ids = Issued(next: firstUID + 1), clock = 0.0
    init(_ w: Walk = Engine.fresh(now: t0, starter: firstUID)) { self.w = w }
    @discardableResult mutating func act(_ a: Act, steps: Int = 0) -> Outcome {
        clock += 1
        return Engine.apply(a, steps: steps, walk: &w, play: &p, rng: &r, now: t0.addingTimeInterval(clock), ids: &ids)
    }
}
private func mon(_ dex: Int, _ uid: Int, level: Int = 30) -> Mon { var m = Mon(dex: dex, level: level, female: false); m.uid = uid; return m }
private func fav(_ uid: Int, _ on: Bool) -> Act { .mon(op: .fav(uid: uid, on: on)) }

@Test func favOnOff() throws {
    var d = Desk(); d.w.box = [mon(16, 2_000_001)]; d.w.caught = [mon(19, 2_000_002)]
    let c = try #require(d.w.companion.uid)
    #expect(d.act(fav(2_000_001, true)).cannot == nil && d.w.box[0].fav == true)
    let box = d.w.box
    #expect(d.act(fav(2_000_001, true)).cannot == nil && d.w.box == box)                         // the same state again: fine, nothing changes
    #expect(d.act(fav(c, true)).cannot == nil && d.w.companion.fav == true)                      // 동료 · 워커 · 상자 alike
    #expect(d.act(fav(2_000_002, true)).cannot == nil && d.w.caught[0].fav == true)
    #expect(d.act(fav(2_000_001, false)).cannot == nil && d.w.box[0].fav == nil)                 // off: no key
    #expect(d.act(fav(9_999_999, true)).cannot == "그 포켓몬은\n없어요")
    // the wire (plan 25 §3), and a Pokémon without the key (an old save, an old app's) reading as off
    let e = JSONEncoder(); e.outputFormatting = .sortedKeys
    #expect(String(decoding: try e.encode(fav(1_002_521, true)), as: UTF8.self) == #"{"mon":{"op":{"fav":{"on":true,"uid":1002521}}}}"#)
    #expect(try JSONDecoder().decode(Act.self, from: Data(#"{"mon":{"op":{"fav":{"uid":1002521,"on":true}}}}"#.utf8)) == fav(1_002_521, true))
    #expect(try JSONDecoder().decode(Mon.self, from: Data(#"{"dex":16,"level":5,"female":false}"#.utf8)).fav == nil)
    #expect(!String(decoding: try e.encode(mon(16, 1)), as: UTF8.self).contains("fav"))
    #expect(actName(fav(1, true)).hasPrefix("mon fav"))
}

@Test func favKeepsChainAndRadar() throws {                                                      // as 기술 배우기: the bush stays up, the chain holds
    var d = Desk(); d.w.box = [mon(16, 2_000_001)]
    d.p.chain = 4
    d.act(fav(2_000_001, true))
    #expect(d.p.chain == 4)
    d.p.radar = Play.Radar(bush: 1, window: 10, chain: 4, at: t0.timeIntervalSinceReferenceDate, mon: mon(16, 0))
    d.act(fav(2_000_001, false))
    #expect(d.p.radar != nil && d.p.chain == 4)
    #expect(d.act(.mon(op: .fetch(uid: 2_000_001))).cannot == nil && d.p.radar == nil && d.p.chain == nil)   // any other: gives them up, as before
    d.w.watts = 500
    #expect(d.act(.tower).battle != nil)                                                           // in a fight: not now (the app hides the star there)
    #expect(d.act(fav(2_000_001, true)).cannot == "배틀 중이에요")
}

@Test func favRelease() {
    var d = Desk()
    d.w.box = [mon(16, 2_000_001, level: 10), mon(16, 2_000_002, level: 20), mon(16, 2_000_003, level: 5), mon(16, 2_000_004, level: 6)]
    #expect(d.w.duplicates(of: 16) == [0, 2, 3] && d.w.releasableDuplicates(of: 16) == [0, 2, 3])   // the best (Lv.20) stays
    d.act(fav(2_000_003, true))
    #expect(d.w.duplicates(of: 16) == [0, 2, 3] && d.w.releasableDuplicates(of: 16) == [0, 3])     // the count the app shows: the same rule
    #expect(d.act(.mon(op: .release(uid: 2_000_003))).cannot == "즐겨찾기한 포켓몬이에요\n먼저 풀어 주세요" && d.w.box.count == 4)
    let x = d.act(.mon(op: .releaseDupes(dex: 16)))
    #expect(x.cannot == nil && x.watts == 5 + 3 && d.w.box.compactMap(\.uid) == [2_000_002, 2_000_003])   // the best and the 즐겨찾기 stay
    #expect(d.act(.mon(op: .releaseDupes(dex: 16))).cannot == "놓아줄 포켓몬이\n없어요")
    #expect(d.act(fav(2_000_003, false)).cannot == nil && d.act(.mon(op: .release(uid: 2_000_003))).cannot == nil)   // 풀고 놓아주기 (the 5.2.2 app): off, then go
    #expect(d.w.box.compactMap(\.uid) == [2_000_002])
    d.w.box = [mon(16, 2_000_005, level: 50), mon(16, 2_000_006, level: 7)]; d.act(fav(2_000_005, true))   // the one kept a 즐겨찾기 too: the rest go
    #expect(d.act(.mon(op: .releaseDupes(dex: 16))).cannot == nil && d.w.box.compactMap(\.uid) == [2_000_005])
}

@Test func favKeptThroughChanges() throws {                                                      // the same Mon changed: evolution, held items, moves, forms, fusion
    var d = Desk()
    var e = mon(133, 2_000_001); e.fav = true; d.w.box = [e]; d.w.bag = ["물의돌", "자뭉열매"]
    #expect(d.act(.use(item: "물의돌", stat: nil, on: 2_000_001)).cannot == nil && d.w.box[0].dex == 134 && d.w.box[0].fav == true)
    #expect(d.act(.mon(op: .hold(uid: 2_000_001, item: "자뭉열매"))).cannot == nil && d.w.box[0].item == "자뭉열매" && d.w.box[0].fav == true)
    let mv = try #require(d.w.relearnable(d.w.box[0]).first { !d.w.box[0].moves.contains($0) })
    #expect(d.act(.mon(op: .move(uid: 2_000_001, slot: 0, move: mv))).cannot == nil && d.w.box[0].moves.first == mv && d.w.box[0].fav == true)
    #expect(d.act(.mon(op: .fetch(uid: 2_000_001))).cannot == nil && d.w.caught.last?.fav == true)  // 상자 → 워커 → 상자
    #expect(d.act(.mon(op: .store(uid: 2_000_001))).cannot == nil && d.w.box.last?.fav == true)
    try Content.$testing.withValue(true) {                                                          // 5.0's 큐레무: the one inside keeps its own
        var k = mon(646, 2_000_010, level: 60); k.fav = true; var r = mon(643, 2_000_011, level: 60); r.fav = true
        var f = Desk(); f.w.box = [k, r]; f.w.bag = ["유전자쐐기"]
        #expect(f.act(.mon(op: .fuse(uid: 2_000_010, with: 2_000_011))).cannot == nil)
        #expect(f.w.box.count == 1 && f.w.box[0].fav == true && f.w.box[0].fused?.first?.fav == true)
        #expect(f.act(.mon(op: .release(uid: 2_000_010))).cannot == "합체를 먼저\n풀어 주세요")
        #expect(f.act(.mon(op: .unfuse(uid: 2_000_010))).cannot == nil && f.w.box.allSatisfy { $0.fav == true } && f.w.box.count == 2)
    }
}
