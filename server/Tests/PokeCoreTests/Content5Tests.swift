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
        #expect(evo(133, 700).count == 1 && evo(133, 700)[0].way == .friend && evo(133, 700)[0].moveType == "fairy")   // 님피아: steps together and a Fairy move
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
        // 님피아 (the user, 10-14: as the games): 1만 걸음 and a Fairy move → 님피아, before 에브이 · 블래키; without one, by day 에브이, by night 블래키
        var e = Mon(dex: 133, level: 20, female: false); e.walked = friendSteps
        #expect(Mon(dex: 133, level: 9, female: false).moves.contains(186) && moveTable[186]?.type == "fairy" && e.relearnable.contains(186))   // 천사의키스 at 9
        e.known = [33, 39, 28, 98]
        let plain = [friendSteps, friendSteps + 1].map { n -> Int? in e.walked = n; w.companion = e; return w.levelEvolution(t0)?.to }
        #expect(w.isDay && plain == [196, 196])
        e.known = [33, 39, 186, 98]
        let fairy = [friendSteps, friendSteps + 1].map { n -> Int? in e.walked = n; w.companion = e; return w.levelEvolution(t0)?.to }
        #expect(fairy == [700, 700])
        w.total = 650; #expect(!w.isDay && w.levelEvolution(t0)?.to == 700)                     // by night too
        e.known = [33, 39, 28, 98]; w.companion = e; #expect(w.levelEvolution(t0)?.to == 197)
        e.walked = friendSteps - 1; e.known = [186]; w.companion = e; #expect(w.levelEvolution(t0) == nil)   // the steps first
    }
    var w = Engine.fresh(now: t0, starter: firstUID); var e = Mon(dex: 133, level: 20, female: false); e.walked = friendSteps + 1; w.companion = e
    #expect(w.levelEvolution(t0)?.to == 196)                                                   // off: no 님피아
}

@Test func content5Forms() {
    #expect(monForms.values.joined().filter { $0.kind == .mega }.count == 48 && Forms.stones.count == 49 && Set(Forms.stones).count == 49)   // 47 stones + 2 orbs
    let x = Forms.mega(6, holding: "리자몽나이트X"), y = Forms.mega(6, holding: "리자몽나이트Y")
    #expect(x?.n == 1 && x?.form.types == ["fire", "dragon"] && x?.form.abilities == [181] && y?.n == 2 && y?.form.types == nil && y?.form.abilities == [70])
    #expect(Forms.mega(6, holding: "생명의구슬") == nil && Forms.mega(384, holding: nil) == nil && Forms.of(384, 1)?.item == nil)   // 메가레쿠쟈: 화룡점정
    #expect(Forms.of(65, 1)?.stats == [55, 50, 65, 175, 95, 150])                                // 메가후딘 as of Gen VI (Gen VII: 특수방어 105)
    #expect(Forms.mega(382, holding: "쪽빛구슬")?.form.kind == .primal && abilityNames[Forms.of(382, 1)!.abilities![0]] == "시작의바다")
    #expect(Forms.of(479, 1)?.name == "히트로토무" && Forms.of(479, 1)?.types == ["electric", "fire"] && monForms[479]?.count == 5)
    #expect(abilityNames[Forms.of(646, 1)!.abilities![0]] == "테라볼티지" && abilityNames[Forms.of(646, 2)!.abilities![0]] == "터보블레이즈")
    #expect(Forms.of(646, 1)?.learnset?.contains(559) == true && Forms.of(678, 1)?.hidden == 172 && Forms.of(386, 1)?.learnset != nil)
    #expect(monForms[201]?.count == 27 && monForms[201]!.allSatisfy { $0.kind == .look } && Forms.of(201, 28) == nil && Forms.of(201, 0) == nil)
    #expect(monForms[25] == nil && monForms[493] == nil && monForms[649] == nil && monForms.keys.allSatisfy { $0 <= 721 })
}

// MARK: - stage 2: Fairy and the Gen VI rules (plan 18 §3), each against Gen IV's
private func mon(_ dex: Int, _ level: Int = 50, moves: [Int]? = nil, ability: Int? = nil) -> Mon {
    var m = Mon(dex: dex, level: level, female: false); m.known = moves; m.nature = 0; m.ivs = Array(repeating: 31, count: 6)
    if let a = ability { m.ability = abilitySlots[dex].firstIndex(of: a) }
    return m
}
private func duel(_ a: Mon, _ b: Mon, seed: UInt64 = 7) -> Battle { var x = Battle(wild: b, party: [a]); x.seed = seed; return x }
private func both<T>(_ body: () -> T) -> (gen4: T, gen6: T) { (Content.$testing.withValue(false, operation: body), Content.$testing.withValue(true, operation: body)) }

@Test func gen6Crits() {
    let r = both { () -> (Double, Bool) in
        let b = duel(mon(6, 100, moves: [53]), mon(143, 100)), m = moveTable[53]!
        var x = b, y = b
        let plain = x.calc(.me, .it, m, power: 90, type: "fire", eff: 1, crit: false), crit = y.calc(.me, .it, m, power: 90, type: "fire", eff: 1, crit: true)
        var z = duel(mon(6, 100), mon(143, 100)); z.mod(.me) { $0.focus = true }                   // 기합에너지 +2 and 베어가르기's +1: stage 3
        let always = (0..<200).allSatisfy { _ in z.critical(.me, .it, moveTable[163]!) }
        return (Double(crit) / Double(plain), always)
    }
    #expect(abs(r.gen4.0 - 2) < 0.06 && !r.gen4.1 && abs(r.gen6.0 - 1.5) < 0.06 && r.gen6.1)
}

@Test func gen6Statuses() {
    let para = both { () -> Bool in var b = duel(mon(25), mon(19)); return b.inflict(.me, .paralysis, from: .it, loud: true) }
    #expect(para.gen4 && !para.gen6)                                                                   // Electric: no paralysis
    let sleeps = both { () -> Set<Int> in Set((1...200).map { k in var b = duel(mon(19), mon(19), seed: UInt64(k)); b.inflict(.me, .sleep, from: .it, loud: true); return b.f(.me).sleep }) }
    #expect(sleeps.gen4 == [2, 3, 4, 5] && sleeps.gen6 == [2, 3, 4])                                    // 1-4 turns → 1-3
    let ghost = both { () -> (Bool, Bool) in
        var b = duel(mon(94), mon(19)); b.mod(.me) { $0.trapped = true; $0.bound = 3 }; let held = b.trapped(.me)
        b.mod(.me) { $0.ingrain = true }; return (held, b.trapped(.me))
    }
    #expect(ghost.gen4 == (true, true) && ghost.gen6 == (false, true))                                  // a Ghost gets away (its own 뿌리박기 aside)
}

@Test func gen6Moves() {
    // 울음소리 (sound) through a substitute; 버섯포자 on a Grass type
    let growl = both { () -> Int in var b = duel(mon(19, moves: [45]), mon(1)); b.mod(.it) { $0.sub = 20 }; b.execute(.me, 45, called: true); return b.f(.it).stage[1] }
    #expect(growl.gen4 == 0 && growl.gen6 == -1)
    let spore = both { () -> Status? in var b = duel(mon(286, moves: [147]), mon(1)); b.execute(.me, 147, called: true); return b.f(.it).status }
    #expect(spore.gen4 == .sleep && spore.gen6 == nil)
    // 피뢰침 takes 10만볼트 and 전기자석파 in (특수공격 +1); 옹골참 holds at full HP
    let rod = both { () -> (Int, Int, Int) in
        var b = duel(mon(25, 100, moves: [85, 86]), mon(310, 30, ability: 31)); let hp = b.f(.it).hp
        b.execute(.me, 85, called: true); let a = (hp - b.f(.it).hp, b.f(.it).stage[3])
        var c = duel(mon(25, 100, moves: [86]), mon(310, 30, ability: 31)); c.execute(.me, 86, called: true)
        return (a.0, a.1, c.f(.it).stage[3])
    }
    #expect(rod.gen4.0 > 0 && rod.gen4.1 == 0 && rod.gen6 == (0, 1, 1))
    let sturdy = both { () -> Int in var b = duel(mon(9, 100, moves: [57]), mon(74, 10, ability: 5)); b.execute(.me, 57, called: true); return b.f(.it).hp }
    #expect(sturdy.gen4 == 0 && sturdy.gen6 == 1)
    // an ability's weather lasts 5 turns; the course's still lasts
    let sun = both { () -> (Int, Int) in
        var r = Seeded(s: 3); var b = duel(mon(383), mon(19)); _ = b.begin(weather: nil, &r)
        var c = duel(mon(19), mon(19)); _ = c.begin(weather: .rain, &r); return (b.skyTurns, c.skyTurns)
    }
    #expect(sun.gen4 == (0, 0) && sun.gen6 == (5, 0))
    // 잠재파워 60; 미래예지 Psychic (none on a Dark type)
    #expect(both { () -> Int in let b = duel(mon(25), mon(19)); return b.moveType(.me, moveTable[237]!).power }.gen6 == 60)
    let future = both { () -> Int in var b = duel(mon(65, 50, moves: [248]), mon(197, 50)); b.execute(.me, 248, called: true); return b.sides[1].futureDmg }
    #expect(future.gen4 > 0 && future.gen6 == 0)
}

// MARK: - stage 3: the Gen V–VI moves (plan 18 §2.2, Battle/Gen6Moves.swift)
private func trainerFight(_ ours: [Mon], _ foes: [Mon], seed: UInt64 = 7) -> Battle { var x = Battle(party: ours, trainer: "테스트", foes: foes); x.seed = seed; return x }
private func dmg(_ b: Battle, _ id: Int) -> Int { var x = b; let hp = x.f(.it).hp; x.execute(.me, id, called: true); return hp - x.f(.it).hp }

@Test func gen6MoveTable() {
    gen6 {
        #expect(Moves.supported(468) && Moves.supported(585) && !Moves.supported(476) && !Moves.supported(507) && !Moves.supported(605) && !Moves.supported(622))
        #expect((468...621).filter(Moves.supported).count == 154 - 24)                              // 18 no one learns, 5 doubles-only, 프리폴
        var b = duel(mon(25, moves: [118]), mon(19)); var seen = Set<Int>()
        for k in 0..<400 { b.seed = UInt64(k); var x = b; x.execute(.me, 118, called: true); if case .use(.me, let id)? = x.out.dropFirst().first(where: { if case .use = $0 { return true }; return false }) { seen.insert(id) } }
        #expect(!seen.contains { [476, 588, 596, 507, 605].contains($0) })                          // 손가락흔들기 never calls them
    }
    #expect(!Moves.supported(468))                                                                     // off: no Gen V–VI moves at all
}

@Test func gen6MovePower() {
    gen6 {
        let a = duel(mon(18, 50, moves: [512]), mon(143, 100)); var held = a; held.mod(.me) { $0.item = "자석" }
        #expect(dmg(a, 512) > dmg(held, 512) * 3 / 2)                                                 // 애크러뱃: twice with nothing held
        var p = duel(mon(89, 50, moves: [474]), mon(25, 50)); let plain = dmg(p, 474); p.mod(.it) { $0.status = .poison }
        #expect(dmg(p, 474) > plain * 3 / 2)                                                           // 베놈쇼크 on a poisoned one
        var s = duel(mon(65, 50, moves: [500]), mon(143, 100)); let s0 = dmg(s, 500); s.mod(.me) { $0.stage[3] = 2; $0.stage[5] = 2 }
        #expect(s.gen6Power(.me, .it, moveTable[500]!, 20) == 100 && dmg(s, 500) > s0 * 3)             // 어시스트파워 20 + 20 × 4
        let heavy = duel(mon(376, 50, moves: [484]), mon(25, 50)), light = duel(mon(25, 50, moves: [484]), mon(376, 50))
        var h = heavy, l = light
        #expect(h.gen6Power(.me, .it, moveTable[484]!, 0) == 120 && l.gen6Power(.me, .it, moveTable[484]!, 0) == 40)   // 헤비봄버 by weight
        var e = duel(mon(25, 50, moves: [486]), mon(143, 50)); let e0 = e.gen6Power(.me, .it, moveTable[486]!, 0); e.mod(.it) { $0.stage[5] = -6 }
        #expect(e0 == 80 && e.gen6Power(.me, .it, moveTable[486]!, 0) == 150)                         // 일렉트릭볼 by speed: 110 / 50, then / 12.5
        var echo = duel(mon(25, 50, moves: [497]), mon(143, 50)); echo.mod(.me) { $0.metronome = 2 }
        #expect(echo.gen6Power(.me, .it, moveTable[497]!, 40) == 120)                                  // 에코보이스's third in a row
    }
}

@Test func gen6MoveStats() {
    gen6 {
        // 사이코쇼크 hits 방어, 속임수 with the target's 공격, 업어후리기 always crits, 야금야금 past the stages
        var b = duel(mon(65, 50, moves: [473]), mon(143, 50)); let d0 = dmg(b, 473)
        b.mod(.it) { $0.stage[4] = 6 }; let spd = dmg(b, 473); b.mod(.it) { $0.stage[4] = 0; $0.stage[2] = 6 }
        #expect(abs(spd - d0) <= d0 / 6 && dmg(b, 473) < d0 / 2)
        var f = duel(mon(197, 50, moves: [492]), mon(143, 100)); let f0 = dmg(f, 492); f.mod(.it) { $0.stage[1] = 2 }
        #expect(dmg(f, 492) > f0 * 8 / 5)
        var c = duel(mon(68, 50), mon(143, 50)); #expect((0..<50).allSatisfy { _ in c.critical(.me, .it, moveTable[480]!) })
        var ch = duel(mon(68, 50, moves: [498]), mon(143, 50)); let c0 = dmg(ch, 498); ch.mod(.it) { $0.stage[2] = 6 }
        #expect(abs(dmg(ch, 498) - c0) <= c0 / 6)
        // 플라잉프레스 (Fighting + Flying) on a Grass type; 프리즈드라이 on Water
        let fp = duel(mon(701, 50), mon(152, 50)); #expect(fp.gen6Effect(.me, .it, moveTable[560]!, fp.typeEff("fighting", .it, by: .me)) == 2)
        let fd = duel(mon(131, 50), mon(7, 50)); #expect(fd.gen6Effect(.me, .it, moveTable[573]!, fd.typeEff("ice", .it, by: .me)) == 2)
        // 껍질깨기, 클리어스모그, 베놈트랩 (only on a poisoned one)
        var sm = duel(mon(91, 50, moves: [504]), mon(19)); sm.execute(.me, 504, called: true)
        #expect(Array(sm.f(.me).stage[1...5]) == [2, -1, 2, -1, 2])
        var cs = duel(mon(89, 50, moves: [499]), mon(143, 50)); cs.mod(.it) { $0.stage[1] = 4 }; cs.execute(.me, 499, called: true); #expect(cs.f(.it).stage[1] == 0)
        var vd = duel(mon(89, 50, moves: [599]), mon(143, 50)); vd.execute(.me, 599, called: true); #expect(vd.f(.it).stage[1] == 0)
        vd.mod(.it) { $0.status = .poison }; vd.execute(.me, 599, called: true); #expect(vd.f(.it).stage[1] == -1 && vd.f(.it).stage[5] == -1)
    }
}

@Test func gen6MoveShields() {
    gen6 {
        var k = duel(mon(68, 50, moves: [33]), mon(681, 50, moves: [588])); k.execute(.it, 588, called: true); let hp = k.f(.it).hp
        k.execute(.me, 33, called: true); #expect(k.f(.it).hp == hp && k.f(.me).stage[1] == -2)        // 킹실드: 공격 -2 on contact
        var sp = duel(mon(68, 50, moves: [33]), mon(650, 50, moves: [596])); sp.execute(.it, 596, called: true); let mine = sp.f(.me).hp
        sp.execute(.me, 33, called: true); #expect(sp.f(.me).hp == mine - sp.f(.me).maxHP / 8)         // 니들가드: 1/8 back
        var w = duel(mon(76, 50, moves: [89, 33]), mon(76, 50, moves: [469])); w.execute(.it, 469, called: true)
        #expect(dmg(w, 89) == 0 && dmg(w, 33) > 0)                                                      // 와이드가드: 지진, not 몸통박치기
        var q = duel(mon(25, 50, moves: [98]), mon(143, 50, moves: [501])); q.execute(.it, 501, called: true); #expect(dmg(q, 98) == 0)   // 패스트가드: 전광석화
        var cr = duel(mon(25, 50, moves: [86]), mon(143, 50, moves: [578])); cr.execute(.it, 578, called: true); cr.execute(.me, 86, called: true)
        #expect(cr.f(.it).status == nil)                                                                // 트릭가드: 전기자석파
    }
}

@Test func gen6MoveFields() {
    gen6 {
        // 끈적끈적네트 on the next one out
        var web = trainerFight([mon(595, 50, moves: [564])], [mon(19, 50), mon(20, 50)]); web.execute(.me, 564, called: true); web.switchIn(.it, 1)
        #expect(web.sides[1].stickyWeb == true && web.f(.it).stage[5] == -1)
        // 그래스필드: Grass moves ×1.5 and 1/16 back; 미스트필드: no status on the ground
        var g = duel(mon(1, 50, moves: [75, 580]), mon(143, 50)); let leaf = dmg(g, 75); g.execute(.me, 580, called: true)
        #expect(g.terrain == .grassy && dmg(g, 75) > leaf * 4 / 3)
        g.mod(.me) { $0.hp = $0.maxHP / 2 }; let half = g.f(.me).hp; g.endOfTurn(); #expect(g.f(.me).hp == half + g.f(.me).maxHP / 16 && g.terrainLeft == 4)
        var mist = duel(mon(35, 50, moves: [581]), mon(143, 50)); mist.execute(.me, 581, called: true)
        #expect(!mist.inflict(.it, .sleep, from: .me, loud: true) && mist.inflict(.me, .burn, from: .it, loud: true) == false)
        // 원더룸 swaps 방어 / 특수방어; 매직룸 takes the items away
        var room = duel(mon(68, 50, moves: [33]), mon(80, 50)); let before = dmg(room, 33); room.wonderRoom = 5; #expect(dmg(room, 33) > before)   // 야도란: 방어 110, 특수방어 80
        var magic = duel(mon(25, 50), mon(143, 50)); magic.mod(.me) { $0.item = "자석" }; magic.magicRoom = 5; #expect(magic.held(.me) == nil)
        // 떨어뜨리기 grounds a flier; 사우전드애로 hits one; 텔레키네시스 lifts one off the ground
        var sd = duel(mon(76, 50, moves: [479, 89]), mon(18, 50)); #expect(dmg(sd, 89) == 0); sd.execute(.me, 479, called: true)
        #expect(sd.grounded(.it) && dmg(sd, 89) > 0)
        let ta = duel(mon(718, 50, moves: [614]), mon(18, 50)); #expect(dmg(ta, 614) > 0)
        var tk = duel(mon(65, 50, moves: [477, 89]), mon(76, 50)); tk.execute(.me, 477, called: true); #expect(!tk.grounded(.it) && dmg(tk, 89) == 0)
        // 물붓기, 핼러윈; 페어리록 holds both in the next turn
        var soak = duel(mon(7, 50, moves: [487]), mon(4, 50)); soak.execute(.me, 487, called: true); #expect(soak.f(.it).typeList == ["water"])
        var tt = duel(mon(708, 50, moves: [567]), mon(4, 50)); tt.execute(.me, 567, called: true); #expect(tt.f(.it).typeList == ["fire", "ghost"])
        var lock = duel(mon(35, 50, moves: [587]), mon(143, 50)); lock.execute(.me, 587, called: true); #expect(lock.trapped(.me) && lock.trapped(.it))
    }
}

@Test func gen6MoveSwitches() {
    gen6 {
        var v = trainerFight([mon(25, 50, moves: [521]), mon(1, 50)], [mon(143, 70)]); v.execute(.me, 521, called: true)
        #expect(v.me == 1)                                                                              // 볼트체인지: out it goes
        var dt = duel(mon(149, 50, moves: [525]), mon(143, 50)); dt.execute(.me, 525, called: true); #expect(dt.over)   // 드래곤테일: a wild one's gone
        var t2 = trainerFight([mon(149, 50, moves: [525])], [mon(143, 70), mon(19, 30)]); t2.execute(.me, 525, called: true); #expect(t2.it == 1)
        var fg = duel(mon(68, 50, moves: [515]), mon(143, 100)); let mine = fg.f(.me).hp; let d = dmg(fg, 515); fg.execute(.me, 515, called: true)
        #expect(d == mine && !fg.f(.me).alive)                                                          // 목숨걸기
        var pw = duel(mon(4, 50, moves: [52]), mon(12, 50, moves: [600])); pw.execute(.it, 600, called: true); let hp = pw.f(.me).hp
        pw.execute(.me, 52, called: true); #expect(pw.f(.me).hp == hp - pw.f(.me).maxHP / 4)          // 분진: the Fire move blows up on it
        var belch = duel(mon(89, 50, moves: [562]), mon(143, 50)); #expect(dmg(belch, 562) == 0)          // 트림: no berry eaten yet
        belch.mod(.me) { $0.spent = "오랭열매" }; #expect(dmg(belch, 562) > 0)
    }
}

@Test func gen6Fuzz() {                                                                            // 3 vs 3 across 1-721, any supported move: always ends, HP in range
    gen6 {
        let pool = moveTable.keys.filter(Moves.supported).sorted()
        var r = Seeded(s: 2026_10_14), ended = 0
        for round in 0..<200 {
            func one() -> Mon {
                var m = Mon.wild(Int.random(in: 1...721, using: &r), level: Int.random(in: 30...80, using: &r), &r)
                m.known = (0..<4).map { _ in pool.randomElement(using: &r)! }; m.ability = Int.random(in: 0...1, using: &r)
                return m
            }
            var b = Battle(party: [one(), one(), one()], trainer: "퍼저", foes: [one(), one(), one()])
            _ = b.begin(weather: [nil, .rain, .snow, .fog].randomElement(using: &r)!, &r)
            for _ in 0..<400 where !b.over {
                if b.mustReplace, let i = b.mine.indices.first(where: { b.mine[$0].alive && $0 != b.me }) { _ = b.replace(i); continue }
                _ = b.turn(.fight(b.usable(.me).randomElement(using: &r) ?? 165), &r)
                for x in b.mine + b.theirs { #expect(x.hp >= 0 && x.hp <= x.maxHP, "round \(round)") }
            }
            if b.over { ended += 1 }
        }
        #expect(ended >= 190)
    }
}

// MARK: - stage 4: the Gen V–VI abilities and hidden abilities (plan 18 §2.3, §4; Battle/Gen6Abilities.swift)
private func with(_ b: Battle, _ s: Side, _ a: Int) -> Battle { var x = b; x.mod(s) { $0.abilityOver = a }; return x }

@Test func gen6HiddenAbilities() {
    var m = Mon(dex: 3, level: 50, female: false); m.ability = 2
    let id = both { m.abilityID }
    #expect(id.gen4 == abilitySlotsGen4[3].last && id.gen6 == 34)                                     // 이상해꽃: 엽록소 (Gen IV: no slot 2, the last one)
    #expect(Walk.chainHiddenOdds(4) == 0 && Walk.chainHiddenOdds(5) == 0.10 && Walk.chainHiddenOdds(10) == 0.25)
    let share = both { () -> (Int, Int) in
        var w = Walk(), r = Seeded(s: 11), hidden = 0, could = 0
        for _ in 0..<600 { let x = w.radarMon(&r, chain: 10).mon; if hiddenAbility[x.dex] > 0 { could += 1; if x.ability == 2 { hidden += 1 } } }
        _ = w.owned; return (hidden, could)
    }
    #expect(share.gen4.0 == 0 && share.gen6.1 > 300 && (15...35).contains(100 * share.gen6.0 / share.gen6.1))   // about a quarter at a chain of 10
}

@Test func gen6AbilitiesStats() {
    gen6 {
        var c = with(duel(mon(25), mon(19)), .me, 126); c.boost(.me, 1, -1, from: .it); #expect(c.f(.me).stage[1] == 1)        // 심술꾸러기
        var d = with(duel(mon(25), mon(19)), .me, 128); d.boost(.me, 2, -1, from: .it); #expect(d.f(.me).stage[1] == 2)        // 오기
        var k = with(duel(mon(25), mon(19)), .me, 172); k.boost(.me, 5, -1, from: .it); #expect(k.f(.me).stage[3] == 2)        // 승기
        var p = with(duel(mon(25), mon(19)), .me, 145); p.boost(.me, 2, -1, from: .it); #expect(p.f(.me).stage[2] == 0)        // 부풀린가슴
        let pr = with(duel(mon(25, moves: [86]), mon(19)), .me, 158), gw = with(duel(mon(18, moves: [17]), mon(19)), .me, 177)
        #expect(pr.priority(.me, 86) == 1 && pr.priority(.me, 85) == 0 && gw.priority(.me, 17) == 1)   // 짓궂은마음, 질풍날개
        var sand = with(duel(mon(25), mon(19)), .me, 146); let v = sand.speed(.me); sand.sky = .sand; #expect(sand.speed(.me) == v * 2)   // 모래헤치기
        let heavy = with(duel(mon(25), mon(19)), .me, 134); #expect(heavy.weight(.me) == weightKg[25] * 2)                    // 헤비메탈
    }
}

@Test func gen6AbilitiesDamage() {
    gen6 {
        let base = duel(mon(25, 50, moves: [33, 85]), mon(143, 100))
        #expect(dmg(with(base, .it, 136), 33) * 2 <= dmg(base, 33) + 1)                                          // 멀티스케일 at full HP
        #expect(dmg(with(base, .it, 169), 33) * 2 <= dmg(base, 33) + 1 && dmg(with(base, .it, 169), 85) == dmg(base, 85))   // 퍼코트: physical only
        var skin = with(duel(mon(35, 50, moves: [33]), mon(143, 100)), .me, 182)
        #expect(skin.moveType(.me, moveTable[33]!).type == "fairy" && dmg(skin, 33) * 10 > dmg(duel(mon(35, 50, moves: [33]), mon(143, 100)), 33) * 18)   // 페어리스킨: Fairy, ×1.3 and STAB
        skin.mod(.it) { $0.abilityOver = 0 }
        var bond = with(duel(mon(115, 50, moves: [33]), mon(143, 100)), .me, 185); bond.execute(.me, 33, called: true)
        #expect(bond.out.filter { if case .hit = $0 { return true }; return false }.count == 2)                // 부자유친: twice
        let sheer = with(duel(mon(130, 50, moves: [44]), mon(143, 100)), .me, 125)                              // 물기 (flinch 30 %)
        #expect(dmg(sheer, 44) > dmg(duel(mon(130, 50, moves: [44]), mon(143, 100)), 44) * 6 / 5)
        var nofl = sheer; for k in 0..<40 { nofl.seed = UInt64(k); var x = nofl; x.execute(.me, 44, called: true); #expect(!x.f(.it).flinch) }
        #expect(dmg(with(duel(mon(76, 50, moves: [88]), mon(143, 50)), .it, 171), 88) > 0)                   // 방탄 doesn't stop 돌떨구기 (not a ball)
        #expect(dmg(with(duel(mon(5, 50, moves: [188]), mon(143, 50)), .it, 171), 188) == 0)                 // 방탄: 오물폭탄
        var sap = with(duel(mon(1, 50, moves: [75]), mon(143, 50)), .it, 157); sap.execute(.me, 75, called: true)
        #expect(sap.f(.it).hp == sap.f(.it).maxHP && sap.f(.it).stage[1] == 1)                                // 초식
    }
}

@Test func gen6AbilitiesMoments() {
    gen6 {
        var pro = with(duel(mon(658, 50, moves: [85]), mon(143, 50)), .me, 168); pro.execute(.me, 85, called: true)
        #expect(pro.f(.me).typeList == ["electric"])                                                       // 변환자재
        var mir = with(duel(mon(25, 50, moves: [86]), mon(143, 50)), .it, 156); mir.execute(.me, 86, called: true)
        #expect(mir.f(.it).status == nil && mir.f(.me).status == nil)                                      // 매직미러 (back on an Electric type: no 마비 either)
        var mir2 = with(duel(mon(19, 50, moves: [86]), mon(143, 50)), .it, 156); mir2.execute(.me, 86, called: true)
        #expect(mir2.f(.it).status == nil && mir2.f(.me).status == .paralysis)
        var regen = trainerFight([mon(80, 50), mon(1, 50)], [mon(19, 50)]); regen.mod(.me) { $0.abilityOver = 144; $0.hp = 10 }
        regen.switchIn(.me, 1); #expect(regen.mine[0].hp == 10 + regen.mine[0].maxHP / 3)                  // 재생력
        var barb = with(duel(mon(68, 50, moves: [33]), mon(143, 50)), .it, 160); let hp = barb.f(.me).hp; barb.execute(.me, 33, called: true)
        #expect(barb.f(.me).hp == hp - barb.f(.me).maxHP / 8)                                                // 철가시
        var nerve = with(duel(mon(25), mon(19)), .it, 127); nerve.mod(.me) { $0.item = "자뭉열매"; $0.hp = 1 }; nerve.heldCheck(.me)
        #expect(nerve.f(.me).item == "자뭉열매")                                                            // 긴장감: no berry
        var veil = with(duel(mon(25), mon(19)), .me, 175); let slept = veil.inflict(.me, .sleep, from: .it, loud: true); #expect(!slept)   // 스위트베일
        var r = Seeded(s: 5); var ditto = Mon(dex: 132, level: 50, female: false); ditto.ability = 2
        var imp = duel(ditto, mon(143, 50)); _ = imp.begin(weather: nil, &r); #expect(imp.f(.me).form?.dex == 143)   // 괴짜: 메타몽 comes out 변신
    }
}

// MARK: - stage 5: forms, Mega, 원시회귀, the Gen V–VI items (plan 18 §2.4 §5 §6; Model/Forms.swift, Battle/Gen6Forms.swift, Gen6Items.swift)
private func holding(_ m: Mon, _ i: String) -> Mon { var x = m; x.item = i; return x }
private func formed(_ dex: Int, _ f: Int?, _ level: Int = 50) -> Mon { var m = mon(dex, level); m.form = f; return m }

@Test func gen6StoredForms() {
    let heat = formed(479, 1)
    #expect(both { heat.typing }.gen4 == ["electric", "ghost"] && both { heat.typing }.gen6 == ["electric", "fire"])   // off: no forms
    gen6 {
        #expect(formed(386, 1).baseStat == [50, 180, 20, 180, 20, 150] && formed(386, 1).learnset != learnsets[386])   // 테오키스 어택폼
        #expect(abilityNames[formed(646, 1).abilityID] == "테라볼티지" && formed(646, 1).stats[1] > mon(646).stats[1])   // 블랙큐레무
        var r = Seeded(s: 1)
        let letters = Set((0..<300).map { _ in Mon.wild(201, level: 10, &r).form ?? 0 }); #expect(letters.count > 20)   // 안농: a letter each
        let cats = (0..<100).map { _ in Mon.wild(678, level: 30, &r) }; #expect(cats.allSatisfy { $0.form == ($0.female ? 1 : nil) })   // 냐오닉스 ♀
        #expect(Forms.placeForm(mon(585), season: .winter, art: .field) == 3 && Forms.placeForm(mon(412), season: .spring, art: .cave) == 1)
        var east = formed(422, 1, 30); east.uid = 7; #expect(Forms.evolved(east, into: 423) == 1)                           // 깝질무 동쪽바다 → 트리토돈 동쪽바다
        var burmy = formed(412, 1); burmy.female = true; #expect(Forms.evolved(burmy, into: 413) == 1)
        #expect(formed(413, 1).typing == ["bug", "ground"] && Forms.evolved(burmy, into: 414) == nil)                     // 모래땅 도롱마담; 나메일 none
    }
    var r = Seeded(s: 1); #expect(Mon.wild(201, level: 10, &r).form == nil)                                              // off: never rolled
}

@Test func gen6MegaEvolution() {
    gen6 {
        var b = trainerFight([holding(mon(6, 50, moves: [53]), "리자몽나이트Y"), mon(25, 50)], [mon(143, 50)]); var r = Seeded(s: 3)
        #expect(b.canMega(.me) && b.megaForm(.me)?.n == 2)
        _ = b.turn(.megaFight(53), &r)
        #expect(b.f(.me).mega == 2 && b.f(.me).typeList == ["fire", "flying"] && b.f(.me).ability == 70 && b.sky == .sun && !b.canMega(.me))
        #expect(b.out.contains { if case .mega(.me, 2, let t) = $0 { return t.contains("메가리자몽Y") }; return false })
        b.switchIn(.me, 1); b.switchIn(.me, 0); #expect(b.f(.me).mega == 2)                                  // a Mega stays one
        var x = trainerFight([holding(mon(6, 50, moves: [53]), "리자몽나이트X")], [mon(143, 50)]); _ = x.turn(.megaFight(53), &r)
        #expect(x.f(.me).typeList == ["fire", "dragon"] && abilityNames[x.f(.me).ability] == "단단한발톱")
        var foe = trainerFight([mon(143, 50, moves: [33])], [holding(mon(248, 50), "마기라스나이트")]); _ = foe.turn(.fight(33), &r)
        #expect(foe.f(.it).mega == 1 && foe.sky == .sand)                                                     // the trainer's first turn
        var wild = duel(mon(143, 50, moves: [33]), holding(mon(248, 50), "마기라스나이트")); _ = wild.turn(.fight(33), &r)
        #expect(wild.f(.it).mega == nil)                                                                      // a wild one never
        var ko = duel(mon(68, 50, moves: [282]), holding(mon(6, 50), "리자몽나이트X")); ko.execute(.me, 282, called: true); #expect(ko.f(.it).item == "리자몽나이트X")   // its stone stays
    }
    var off = trainerFight([holding(mon(6, 50, moves: [53]), "리자몽나이트Y")], [mon(143, 50)]); #expect(!off.canMega(.me))
}

@Test func gen6PrimalAndBattleForms() {
    gen6 {
        var r = Seeded(s: 4)
        var p = trainerFight([holding(mon(382, 60, moves: [57]), "쪽빛구슬"), mon(25, 50)], [mon(6, 50, moves: [53])]); _ = p.begin(weather: nil, &r)
        #expect(p.f(.me).mega == 1 && p.extreme == 189 && p.sky == .rain)
        var fire = p; fire.execute(.it, 53, called: true); #expect(fire.f(.me).hp == fire.f(.me).maxHP)          // 시작의바다: no Fire attack
        p.switchIn(.me, 1); #expect(p.extreme == nil && p.sky == .clear)                                         // its bringer gone
        var ray = trainerFight([mon(384, 70, moves: [620])], [mon(144, 50, moves: [58])]); _ = ray.turn(.megaFight(620), &r)
        #expect(ray.f(.me).mega == 1 && ray.extreme == 191 && ray.typeEff("ice", .me, by: .it) == 2)           // 델타스트림: Flying's weakness gone (Dragon's stays)
        var aegis = duel(mon(681, 50, moves: [33, 588]), mon(143, 50)); aegis.execute(.me, 33, called: true)
        #expect(aegis.f(.me).battleForm == 1 && aegis.base(.me, 1) > aegis.base(.me, 2)); aegis.execute(.me, 588, called: true); #expect(aegis.f(.me).battleForm == nil)
        var z = mon(555, 50); z.ability = 2; var zen = duel(z, mon(143, 50));                                // 달마모드: its hidden ability
        zen.mod(.me) { $0.hp = $0.maxHP / 3 }; zen.endOfTurn(); #expect(zen.f(.me).battleForm == 1 && zen.f(.me).typeList == ["fire", "psychic"])
        var meloetta = duel(mon(648, 50, moves: [547]), mon(143, 50)); meloetta.execute(.me, 547, called: true); #expect(meloetta.f(.me).typeList == ["normal", "fighting"])
        let origin = duel(holding(mon(487, 70), "백금옥"), mon(143, 50)); #expect(origin.f(.me).ability == 26)      // 기라티나 오리진폼: 부유
    }
}

@Test func gen6HeldItems() {
    gen6 {
        var av = duel(holding(mon(143, 50, moves: [33, 156]), "돌격조끼"), mon(19)); #expect(av.usable(.me) == [33])
        let plain = duel(mon(25, 50, moves: [85]), mon(143, 100)); #expect(dmg(plain, 85) * 2 >= dmg(duel(mon(25, 50, moves: [85]), holding(mon(143, 100), "돌격조끼")), 85) * 3 - 3)
        var wp = duel(mon(68, 50, moves: [7]), holding(mon(143, 100), "약점보험")); wp.mod(.it) { $0.types = ["grass"] }; wp.execute(.me, 7, called: true)
        #expect(wp.f(.it).stage[1] == 2 && wp.f(.it).stage[3] == 2 && wp.f(.it).item == nil)
        var bal = duel(mon(76, 50, moves: [89, 33]), holding(mon(143, 50), "풍선")); #expect(dmg(bal, 89) == 0); bal.execute(.me, 33, called: true); #expect(bal.f(.it).item == nil && dmg(bal, 89) > 0)
        var helm = duel(mon(68, 50, moves: [33]), holding(mon(143, 100), "울퉁불퉁멧")); let hp = helm.f(.me).hp; helm.execute(.me, 33, called: true); #expect(helm.f(.me).hp == hp - helm.f(.me).maxHP / 6)
        var red = duel(holding(mon(143, 100), "레드카드"), mon(19, 30, moves: [33])); red.execute(.it, 33, called: true); #expect(red.over)   // the wild one's sent off
        var ej = trainerFight([holding(mon(143, 100), "탈출버튼"), mon(25)], [mon(19, 30, moves: [33])]); ej.execute(.it, 33, called: true); #expect(ej.me == 1)
        let gem = holding(mon(25, 50, moves: [85]), "전기주얼"); var g = duel(gem, mon(143, 100)); let d1 = dmg(g, 85); g.execute(.me, 85, called: true)
        #expect(d1 * 10 >= dmg(plain, 85) * 12 && g.f(.me).item == nil)
        #expect(dmg(duel(mon(68, 50, moves: [33]), holding(mon(92, 50), "겨냥표적")), 33) > 0)                         // 겨냥표적: 고스트 takes a Normal hit
        let evio = duel(mon(68, 50, moves: [33]), holding(mon(133, 50), "진화의휘석")); #expect(dmg(evio, 33) * 3 <= dmg(duel(mon(68, 50, moves: [33]), mon(133, 50)), 33) * 2 + 3)
        #expect(Walk.heldBP.contains { $0.item == "돌격조끼" } && !Walk.heldBP.contains { Forms.stones.contains($0.item) } && Held.summary("리자몽나이트X") == "리자몽 메가진화")
    }
    #expect(!Walk.heldBP.contains { $0.item == "돌격조끼" })                                                    // off: 4.1's shop
}

@Test func gen6RotomAndKyurem() {
    gen6 {
        var w = Engine.fresh(now: t0, starter: firstUID); var rot = Mon(dex: 479, level: 40, female: false); rot.known = [84, 109, 506, 247]; w.box = [rot]
        #expect(w.rotomForm(0, 1) == "로토무카탈로그가\n없어요")
        w.bag = ["로토무카탈로그"]
        #expect(w.rotomForm(0, 1) == nil && w.box[0].form == 1 && w.box[0].moves == [84, 109, 506, 315] && w.box[0].typing == ["electric", "fire"])   // 히트: 오버히트
        #expect(w.rotomForm(0, 2) == nil && w.box[0].moves == [84, 109, 506, 56])                                      // 워시: 하이드로펌프 in its place
        #expect(w.rotomForm(0, nil) == nil && w.box[0].form == nil && w.box[0].moves == [84, 109, 506])                // back: its move goes
        var k = Mon(dex: 646, level: 60, female: false); k.known = [549, 58, 225, 304]; let z = Mon(dex: 644, level: 60, female: false)
        w.box = [k, z]
        #expect(w.fuse(0, with: 1) == "유전자쐐기가\n없어요")
        w.bag.append("유전자쐐기")
        #expect(w.fuse(0, with: 1) == nil && w.box.count == 1 && w.box[0].form == 1 && w.box[0].fused?.first?.dex == 644 && w.box[0].moves.first == 553)   // 블랙큐레무: 프리즈볼트
        #expect(abilityNames[w.box[0].abilityID] == "테라볼티지" && w.box[0].stats[1] > k.stats[1])
        #expect(w.unfuse(0) == nil && w.box.count == 2 && w.box[0].form == nil && w.box[0].moves.first == 549 && w.box[1].dex == 644)
        #expect(w.fuse(1, with: 0) == "합체할 수\n없어요")                                                            // the other way round: no
    }
    var w = Engine.fresh(now: t0, starter: firstUID); w.bag = ["유전자쐐기"]; w.box = [Mon(dex: 646, level: 60, female: false), Mon(dex: 643, level: 60, female: false)]
    #expect(w.fuse(0, with: 1) == "유전자쐐기가\n없어요")                                                              // off: no fusing
}

// MARK: - stage 6: courses, eggs, the tower (plan 18 §6.3 §7 §8)
@Test func gen6CoursesAndEggs() {
    gen6 {
        #expect(courses.count == 44 && courses[35].name == "하나 들판" && courses[41].name == "칼로스 들판" && courses[35].region == 494...649)
        #expect(courses[35...].allSatisfy { c in c.legends.isEmpty && c.all.allSatisfy { (494...721).contains($0.dex) && !Tower.isLegend($0.dex) } && c.guests.count == 5 })
        var w = Walk(); #expect(w.unlocked(35) && w.unlocked(41) && !w.unlocked(36) && !w.unlocked(42))         // each region's first: open to all
        w.owned = Array(1...300); #expect(!w.unlocked(36)); w.owned = Array(494...503); #expect(w.unlocked(36) && !w.unlocked(37))   // 하나's own count
        #expect(courses[35].all.map(\.level).min()! >= 15 && courses[40].all.map(\.level).max()! <= 62)
        #expect(eggPool.contains(495) && eggPool.contains(696) && eggPool.count == eggPoolGen4.count + 10)
    }
    #expect(courses.count == 35 && !eggPool.contains(495))                                              // off: 4.1's
}

@Test func gen6TowerFoes() {
    gen6 {
        var w = Walk(); var r = Seeded(s: 2026)
        w.towerStreak = 60
        for _ in 0..<200 {
            let f = w.towerFoes(&r)
            #expect(f.foes[0].item.map { Forms.mega(f.foes[0].dex, holding: $0) != nil } == true && !f.foes.contains { Tower.isLegend($0.dex) })   // a Mega first, no legends
        }
        w.towerStreak = 30; #expect((0..<50).allSatisfy { _ in let f = w.towerFoes(&r); return f.foes[0].item.map { Forms.mega(f.foes[0].dex, holding: $0) == nil } ?? true })
        w.towerStreak = 120; var newOnes = Set<Int>()
        for _ in 0..<600 { let f = w.towerFoes(&r); #expect(Tower.isLegend(f.foes[2].dex)); if Tower.legendsGen6Added.contains(f.foes[2].dex) { newOnes.insert(f.foes[2].dex) } }
        #expect(newOnes.count >= 15 && Tower.legendFoes.count == 54 && Tower.isLegend(646) && Tower.legends.count == 35)   // the 100-win pick stays 35
        w.towerStreak = 49; let silver = w.towerFoes(&r); #expect(silver.foes.map(\.dex) == [464, 80, 249] && silver.foes[1].item == "야도란나이트")
        w.towerStreak = 99; let gold = w.towerFoes(&r); #expect(gold.foes.map(\.dex) == [149, 376, 486] && gold.foes[1].item == "메타그로스나이트")
        #expect(Tower.megaFoes.count == 42 && RaidRules.signature[643] == 558)
    }
    #expect(!Tower.isLegend(646) && Tower.legendFoes.count == 35 && Tower.tycoonTeams[50]![1].dex == 350)   // off
}

@Test func gen6BagKinds() {
    #expect(ItemKind.of("로토무카탈로그") == .key && ItemKind.of("유전자쐐기") == .key && Walk.bagTab("유전자쐐기") == "기타")
    var w = Walk(); w.bag = ["로토무카탈로그", "유전자쐐기", "금구슬"]; let sold = w.sell("로토무카탈로그"); #expect(sold == 0 && w.bag.contains("로토무카탈로그"))   // never sold
    gen6 { #expect(Walk.bagTab("리자몽나이트X") == "메가스톤" && Walk.bagTab("쪽빛구슬") == "메가스톤" && Walk.bagTabs.count == 9 && Walk.bagTab("돌격조끼") == "지닌 도구") }
    #expect(Walk.bagTabs.count == 8)                                                                     // off: 4.1's eight
}

@Test func megaStoneCard() {                                                                     // 5.0 (10-14): the card's 메가스톤 n/48, as the save has them
    var w = Walk(); w.bag = ["리자몽나이트X", "리자몽나이트X", "쪽빛구슬", "생명의구슬"]; w.box = [{ var m = Mon(dex: 130, level: 40, female: false); m.item = "갸라도스나이트"; return m }()]
    #expect(TeamCard(name: "a", walk: w, today: 0, week: 0, idle: 0).megaStones == nil)                // off: none
    gen6 { #expect(TeamCard(name: "a", walk: w, today: 0, week: 0, idle: 0).megaStones == 3 && MegaRaid.collected(w) == 3) }
}

@Test func cardTitlePick() {                                                                     // 5.0 (the user, 10-14): two 칭호 or more → the card's is picked (nil: the newest)
    var w = Engine.fresh(now: t0, starter: firstUID), p = Play(), r = Seeded(s: 1), ids = Issued(next: firstUID + 1)
    func pick(_ t: String?) -> String? { Engine.apply(.cardTitle(name: t), steps: 0, walk: &w, play: &p, rng: &r, now: t0, ids: &ids).cannot }
    #expect(w.shownTitle == nil && pick("메가 마스터") == "받은 칭호가\n아니에요")
    w.titles = ["타워 타이쿤", "메가 마스터"]
    #expect(w.shownTitle == "메가 마스터" && pick("타워 타이쿤") == nil && w.shownTitle == "타워 타이쿤" && TeamCard(name: "a", walk: w, today: 0, week: 0, idle: 0).title == "타워 타이쿤")
    #expect(pick(nil) == nil && w.cardTitle == nil && w.shownTitle == "메가 마스터")
    w.cardTitle = "없는 칭호"; #expect(w.shownTitle == "메가 마스터")                                       // (one not earned: the newest)
}

@Test func gen6ShopTabs() {                                                                      // 5.0: the 상점's 로토무카탈로그 under 기타 (it was under no tab: never shown), once
    func tabs(_ w: Walk) -> [Bool: [String]] {                                                   // the tabs with a row, every row (both shops) under one of the shop's own
        var out: [Bool: [String]] = [:]
        for bp in [false, true] {
            let ws = w.wares(bp: bp, shells: [("은", 30)])
            for ware in ws { #expect(Walk.shopTabs(bp: bp).contains(Walk.shopTab(ware, bp: bp)), "\(w.wareName(ware)) → \(Walk.shopTab(ware, bp: bp))") }
            out[bp] = Walk.shopTabs(bp: bp).filter { t in ws.contains { Walk.shopTab($0, bp: bp) == t } }
        }
        return out
    }
    let off = tabs(Engine.fresh(now: t0, starter: firstUID))
    #expect(off[false] == ["회복", "배틀", "육성", "민트", "지닌 도구", "열매", "진화", "전설"] && !off[true]!.contains("기타"))   // off: 4.1's
    gen6 {
        var w = Engine.fresh(now: t0, starter: firstUID); w.watts = 5000
        #expect(tabs(w)[false] == ["회복", "배틀", "육성", "민트", "지닌 도구", "열매", "진화", "기타", "전설"])
        let cat = w.wares(bp: false, shells: []).first { $0.kind == .item("로토무카탈로그") }!
        #expect(Walk.shopTab(cat) == "기타" && cat.once && cat.price == 1000 && w.canBuy(cat, bp: false) == 1)
        #expect(w.purchase(cat, 1, bp: false) == .items("로토무카탈로그", 1) && w.watts == 4000 && w.canBuy(cat, bp: false) == 0 && w.purchase(cat, 1, bp: false) == nil)
    }
}

@Test func megaRotation() {                                                                      // plan 18 §6.4: fixed and shuffled, from content5's first week
    #expect(MegaRaid.order.count == 48 && Set(MegaRaid.order.map { "\($0.dex)-\($0.form)" }) == Set(MegaRaid.bosses.map { "\($0.dex)-\($0.form)" }))   // all 48 once
    let weeks = (0..<24).map(MegaRaid.week)
    #expect(weeks.allSatisfy { $0[0].dex != $0[1].dex } && MegaRaid.week(24) == weeks[0])            // no species twice a week (리자몽 · 뮤츠 X · Y)
    func at(_ n: Int, _ d: Int) -> Int { weeks.firstIndex { $0.contains { $0.dex == d && $0.form == n } }! }
    func apart(_ a: Int, _ b: Int) -> Int { let d = abs(a - b); return min(d, 24 - d) }
    #expect(apart(at(1, 6), at(2, 6)) >= 6 && apart(at(1, 150), at(2, 150)) >= 6 && apart(at(1, 382), at(1, 383)) >= 6 && apart(at(1, 380), at(1, 381)) >= 6)
    let hardest: Set<Int> = [115, 373, 383, 382, 445, 460]                                             // 10-14's RaidSim: the strong teams' ★4 ≤ 10 %
    let hard = weeks.map { w in w.contains { hardest.contains($0.dex) } }
    #expect(hard.filter { $0 }.count == 6 && weeks.allSatisfy { w in w.filter { hardest.contains($0.dex) }.count <= 1 })
    #expect(!hard[0] && !hard[1] && (0..<24).allSatisfy { !(hard[$0] && hard[($0 + 1) % 24]) })       // not first, never back to back
    #expect(weeks[0].map(\.dex) == [9, 142])                                                           // 메가거북왕 · 메가프테라 first
    var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 14) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }
    let on = day(2026, 10, 21)                                                                         // first on a Wednesday: its week is 0
    #expect([day(2026, 10, 19, 0), day(2026, 10, 25, 23), day(2026, 10, 26, 0), day(2026, 12, 28), day(2027, 1, 4)].map { MegaRaid.round($0, from: on, cal) } == [0, 0, 1, 10, 11])
    #expect(MegaRaid.round(day(2026, 10, 1), from: on, cal) == 0 && MegaRaid.round(day(2027, 4, 5), from: on, cal) == 24)   // (before it: 0)
}
