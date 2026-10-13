import Foundation
import Testing
@testable import PokeCore

// docs/plans/18 (5.0): the content5 switch. Off: 4.1's Gen IV tables exactly; on (a test's own, Content.$testing): Gen VI's.

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func gen6<T>(_ body: () throws -> T) rethrows -> T { try Content.$testing.withValue(true, operation: body) }
private func learns(_ d: Int, _ level: Int, _ move: Int) -> Bool { let l = learnsets[d]; return stride(from: 0, to: l.count, by: 2).contains { l[$0] == level && l[$0 + 1] == move } }

@Test func content5OffIsGen4() {
    #expect(!Content.gen6 && dexMax == 493)
    #expect(monTypes[35] == ["normal"] && monTypes[282] == ["psychic"] && typeChart["fairy"] == nil && typeChart["ghost"]?["steel"] == 0.5)
    #expect(moveTable[85]?.power == 95 && moveTable[282]?.power == 20 && moveTable[186]?.type == "normal" && moveTable[468] == nil && moveTable.keys.filter { $0 < 10000 }.max() == 467)
    #expect(baseStats[25] == [35, 55, 30, 50, 40, 90] && abilitySlots[94] == [26] && !learns(36, 46, 585))
    #expect(!evolutions.contains { $0.to > 493 } && evolutions.count == evolutionsGen4.count)
    #expect(monNames.count == 722 && monNames[700] == "님피아" && typeKo["fairy"] == "페어리")    // the shared tables run to 721
}

@Test func content5Tables() {
    gen6 {
        #expect(Content.gen6 && dexMax == 721)
        // the Fairy retcon and the Gen VI chart
        #expect(monTypes[35] == ["fairy"] && monTypes[282] == ["psychic", "fairy"] && monTypes[303] == ["steel", "fairy"] && monTypesGen6Changes.count == 20)
        #expect(typeChart["dragon"]?["fairy"] == 0 && typeChart["fairy"]?["dragon"] == 2 && typeChart["ghost"]?["steel"] == nil && typeChart["dark"]?["steel"] == nil)
        #expect(typeChart["poison"]?["fairy"] == 2 && typeChart["steel"]?["fairy"] == 2 && typeChart["fairy"]?["fire"] == 0.5)
        // moves as of ORAS, and the new ones
        #expect(moveTable[85]?.power == 90 && moveTable[57]?.power == 90 && moveTable[282]?.power == 65 && moveTable[248]?.power == 120 && moveTable[186]?.type == "fairy")
        #expect(moveTable[585]?.type == "fairy" && moveTable[585]?.power == 95 && moveTable[621]?.name == "이차원러시" && moveTable[622] == nil)
        #expect(moveTable[251]?.power == moveTableGen4[251]?.power && moveTable[386]?.power == moveTableGen4[386]?.power)   // the engine works these out
        #expect(moveTable[229]?.stats == [] && moveTable[105]?.pp == 10)                       // 고속스핀 no Speed (Gen VIII's), HP회복 PP 10 (Gen IX's 5)
        #expect(moveTable[33]!.flags & 0x7ff == moveTableGen4[33]!.flags && moveTable[44]!.flags & 8192 != 0 && moveTable[47]!.flags & 2048 != 0)   // 물기: bite; 노래하기: authentic
        // species: Gen VI's stats, learnsets with the Fairy moves (plan 18 §2.1), abilities as of Gen VI
        #expect(baseStats[25] == [35, 55, 40, 50, 50, 90] && baseStats[36][3] == 95 && baseStats[494] == [100, 100, 100, 100, 100, 100])
        #expect(learns(35, 46, 585) && learns(36, 46, 585) && learns(36, 1, 574) && learns(468, 1, 584) && learns(282, 62, 585) && learns(303, 49, 583))
        #expect(learnsets[173] == learnsetsGen4[173] && learns(39, 11, 574) && learns(40, 1, 583))           // 삐: none to add
        #expect(abilitySlots[94] == [26] && hiddenAbility[94] == 0 && hiddenAbility[460] == 43 && hiddenAbility[3] == 34 && abilityNames[191] != nil)
        #expect((1...721).allSatisfy { d in abilitySlots[d].allSatisfy { abilityNames[$0] != nil } && (hiddenAbility[d] == 0 || abilityNames[hiddenAbility[d]] != nil) })
        #expect((1...721).allSatisfy { d in stride(from: 1, to: learnsets[d].count, by: 2).allSatisfy { moveTable[learnsets[d][$0]] != nil } })
    }
    #expect(!Content.gen6 && monTypes[35] == ["normal"])                                       // a test's switch doesn't outlive it
}

@Test func content5Evolutions() {
    gen6 {
        func evo(_ a: Int, _ b: Int) -> [Evo] { evolutions.filter { $0.from == a && $0.to == b } }
        #expect(evo(133, 700).count == 1 && evo(133, 700)[0].way == .friend)                    // 님피아: steps together, not any level-up
        #expect(Set(evo(677, 678).map(\.female)) == [true, false] && evo(665, 666).first?.level == 12)   // 냐오닉스 both; 비비용 at all
        #expect(evo(674, 675).first?.partyType == "dark" && evo(705, 706).first?.weather == "rain" && evo(686, 687).first?.level == 30)
        #expect(evo(588, 589).first?.way == .trade && evo(682, 683).first?.item == "향기주머니" && evo(696, 697).first?.time == "day")
        #expect(evolutions.count > evolutionsGen4.count && evolutions.allSatisfy { $0.to <= 721 })

        // the walker's own checks: 판짱 wants a Dark type with it, 미끄네일 rain; 이브이's friendship splits by steps as before
        var w = Engine.fresh(now: t0, starter: firstUID)
        w.companion = Mon(dex: 674, level: 32, female: false)
        #expect(w.levelEvolution(t0) == nil)
        w.box = [Mon(dex: 197, level: 30, female: false)]
        #expect(w.levelEvolution(t0)?.to == 675)
        w.companion = Mon(dex: 705, level: 50, female: false)
        #expect(w.levelEvolution(t0) == nil)
        w.weather = .rain
        #expect(w.levelEvolution(t0)?.to == 706)
        w.weather = nil
        var e = Mon(dex: 133, level: 20, female: false); e.walked = friendSteps
        w.companion = e; let a = w.levelEvolution(t0)?.to
        e.walked = friendSteps + 1; w.companion = e; let b = w.levelEvolution(t0)?.to
        #expect(w.isDay && Set([a, b]) == [196, 700])                                           // by day: 에브이 or 님피아
    }
    var w = Engine.fresh(now: t0, starter: firstUID); var e = Mon(dex: 133, level: 20, female: false); e.walked = friendSteps + 1; w.companion = e
    #expect(w.levelEvolution(t0)?.to == 196)                                                   // off: no 님피아
}
