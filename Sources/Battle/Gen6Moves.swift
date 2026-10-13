import Foundation
// docs/plans/18 §2.2 (5.0, content5): the Gen V–VI moves (468–621) that need more than their data — power by a rule, a special effectiveness,
// protection variants, fields and rooms, terrains, hazards, retyping. The data-only ones run through the usual paths (Damage / Effects).
// Their ids never come up with content5 off (moveTableGen4 stops at 467), so nothing here changes a Gen IV fight.

enum Terrain: String, Codable, Equatable { case grassy, misty }

extension Battle {
    // MARK: fields
    /// The terrain under s, if it's on the ground (그래스필드 · 미스트필드 only touch the grounded).
    func terrainUnder(_ s: Side) -> Terrain? { (terrainLeft ?? 0) > 0 && grounded(s) ? terrain : nil }
    var wonderRoomOn: Bool { (wonderRoom ?? 0) > 0 }
    /// A fighter's weight, 바디퍼지 taken off (100 kg each, 0.1 kg at least).
    func weight(_ s: Side) -> Double {                                                          // (헤비메탈 x2, 라이트메탈 x1/2)
        let x = f(s), w = x.body.weight * (x.has(134) ? 2 : x.has(135) ? 0.5 : 1) * (holds(s, "가벼운돌") ? 0.5 : 1)
        return max(0.1, w - 100 * Double(x.lighter ?? 0))
    }

    // MARK: damaging moves
    /// The Gen V–VI moves' own power (nil: as the data has it).
    mutating func gen6Power(_ s: Side, _ t: Side, _ m: MoveInfo, _ power: Int) -> Int? {
        switch m.id {
        case 474: return [.poison, .toxic].contains(f(t).status) ? power * 2 : power                   // 베놈쇼크
        case 506: return f(t).status != nil ? power * 2 : power                                         // 병상첨병
        case 512: return held(s) == nil ? power * 2 : power                                             // 애크러뱃
        case 514: return sides[si(s)].lastFaint == turnNo - 1 ? power * 2 : power                       // 원수갚기: one of ours went down last turn
        case 484, 535:                                                                                  // 헤비봄버 · 히트스탬프: by how much heavier
            let r = weight(s) / weight(t); return r >= 5 ? 120 : r >= 4 ? 100 : r >= 3 ? 80 : r >= 2 ? 60 : 40
        case 486:                                                                                       // 일렉트릭볼: by how much faster
            let r = speed(s) / max(1, speed(t)); return r >= 4 ? 150 : r >= 3 ? 120 : r >= 2 ? 80 : r >= 1 ? 60 : 40
        case 497: return 40 * min(5, (f(s).metronome ?? 0) + 1)                                        // 에코보이스: up each turn in a row, to 200
        case 500: return 20 + 20 * f(s).stage[1...7].filter { $0 > 0 }.reduce(0, +)                    // 어시스트파워
        case 558: return f(t).movedThisTurn && f(t).lastMove == 559 ? power * 2 : power                // 크로스플레임 after 크로스썬더
        case 559: return f(t).movedThisTurn && f(t).lastMove == 558 ? power * 2 : power
        default: return nil
        }
    }
    /// Before a Gen V–VI damaging move lands: a reason it fails (said), else nil.
    mutating func gen6Fails(_ s: Side, _ t: Side, _ m: MoveInfo) -> Bool {
        switch m.id {
        case 562 where f(s).spent?.hasSuffix("열매") != true: say(s, "그러나 실패했다!"); return true         // 트림: only after eating a berry
        case 485 where Set(f(s).typeList).isDisjoint(with: f(t).typeList):                               // 싱크로노이즈: a type in common
            say(t, josa(nm(t), "에게는", "에게는") + " 효과가 없는 것 같다..."); return true
        case 614:                                                                                       // 사우전드애로: down it comes, then it's hit as grounded
            if !grounded(t) { mod(t) { $0.smackedDown = true; $0.magnetRise = 0; $0.telekinesis = nil }; say(t, josa(nm(t), "은", "는") + " 땅으로 떨어졌다!") }
            return false
        default: return false
        }
    }
    /// Type effectiveness the Gen V–VI way for the moves that have their own (플라잉프레스, 프리즈드라이).
    func gen6Effect(_ s: Side, _ t: Side, _ m: MoveInfo, _ eff: Double) -> Double {
        switch m.id {
        case 560: return eff * typeEff("flying", t, by: s)                                             // 플라잉프레스: Fighting and Flying both
        case 573 where f(t).typeList.contains("water"): return eff * 4                                 // 프리즈드라이: Water takes it ×2
        default: return eff
        }
    }
    /// After a Gen V–VI damaging move: its aftermath (끄집어내기, 떨어뜨리기, 불태우기 ...).
    mutating func gen6After(_ s: Side, _ t: Side, _ m: MoveInfo, dealt: Int) {
        let tn = nm(t)
        switch m.id {
        case 503, 592: if f(t).alive, !subTook, f(t).status == .freeze { setStatus(t, nil, josa(tn, "의", "의") + " 얼음이 녹았다!") }   // 열탕 · 스팀버스트
        case 499 where f(t).alive && !subTook && dealt > 0:                                             // 클리어스모그
            mod(t) { $0.stage = Array(repeating: 0, count: 8) }; say(t, josa(tn, "의", "의") + " 능력 변화가 원래대로 돌아왔다!")
        case 479 where f(t).alive && !subTook && dealt > 0:                                             // 떨어뜨리기
            let up = !grounded(t) || [19, 340].contains(f(t).semi)
            mod(t) { $0.smackedDown = true; $0.magnetRise = 0; $0.telekinesis = nil; if [19, 340].contains($0.semi) { $0.semi = 0; $0.charging = 0 } }
            if up { say(t, josa(tn, "은", "는") + " 땅으로 떨어졌다!") }
        case 615 where f(t).alive && !subTook && dealt > 0 && !f(t).trapped:                            // 사우전드웨이브
            mod(t) { $0.trapped = true }; say(t, josa(tn, "은", "는") + " 이제 도망칠 수 없다!")
        case 510 where dealt > 0 && !subTook:                                                           // 불태우기: its berry, gone
            if let i = f(t).item, i.hasSuffix("열매"), !keeps(t, by: s) { takeItem(t); say(t, josa(tn + "의 " + i, "은", "는") + " 불타 버렸다!") }
        case 565 where dealt > 0 && !f(t).alive: boost(s, 1, 2, from: s)                               // 마지막일침: a KO, 공격 +2
        case 515: hurt(s, f(s).hp, "")                                                                  // 목숨걸기: all its HP, gone
        case 547 where dealt > 0: relicSong(s)                                                          // 옛노래 (Gen6Forms.swift)
        case 509, 525: if dealt > 0, !subTook, f(t).alive, f(s).alive { blowAway(s, t, loud: false) }   // 배대뒤치기 · 드래곤테일
        default: break
        }
    }
    /// 울부짖기 · 날려버리기 (and, after their hit, 배대뒤치기 · 드래곤테일): a wild one flees, a trainer's (or ours) is swapped for another at random.
    mutating func blowAway(_ s: Side, _ t: Side, loud: Bool) {
        let tn = nm(t)
        if dAb(t, 21, by: s) || f(t).ingrain { if loud { say(t, josa(tn, "은", "는") + " 꿈쩍도 하지 않는다!") }; return }
        if trainer == nil, raidTier == nil { say(t, josa(tn, "은", "는") + " 멀리 날아갔다!"); out.append(s == .me ? .fled : .ran); over = true; return }
        if raidTier != nil, t == .it { if loud { say(s, "그러나 실패했다!") }; return }                 // a raid run (16): the boss stands
        let others = (t == .me ? mine : theirs).indices.filter { $0 != (t == .me ? me : it) && (t == .me ? mine : theirs)[$0].alive }
        guard !others.isEmpty else { if loud { say(s, "그러나 실패했다!") }; return }
        say(t, josa(tn, "은", "는") + " 멀리 날아갔다!"); switchIn(t, others[roll(others.count)])
    }

    // MARK: protection
    /// Whether t's protection stops this move (방어 · 판별 any protectable one; 킹실드 · 마룻바닥세워막기 damaging ones; 와이드가드 spread
    /// moves; 패스트가드 priority ones; 트릭가드 status moves aimed at it).
    func guards(_ t: Side, _ m: MoveInfo, by s: Side) -> Bool {
        guard f(t).protected else { return false }
        switch f(t).shield {
        case 588?, 561?: return m.protectable && !m.isStatus
        case 469?: return [9, 11, 14].contains(m.target)
        case 501?: return priority(s, m.id) > 0
        case 578?: return m.isStatus && m.onFoe
        default: return m.protectable
        }
    }
    /// A contact move that met 킹실드 (공격 -2) or 니들가드 (1/8).
    mutating func spikes(_ s: Side, _ t: Side, _ m: MoveInfo) {
        guard m.contact, f(s).alive else { return }
        if f(t).shield == 588 { boost(s, 1, -2, from: t) }
        if f(t).shield == 596, !f(s).has(98) { hurt(s, max(1, f(s).maxHP / 8), josa(nm(s), "은", "는") + " 상처를 입었다!") }
    }

    // MARK: status and field moves
    /// The Gen V–VI status moves with their own rule. False: not one of them (the caller says nothing happened).
    mutating func gen6Status(_ s: Side, _ t: Side, _ m: MoveInfo) -> Bool {
        let id = m.id, n = nm(s), tn = nm(t)
        func fail() { say(s, "그러나 실패했다!") }
        switch id {
        case 504: for k in stride(from: 0, to: m.stats.count, by: 2) { boost(s, m.stats[k] - 1, m.stats[k + 1], from: s) }   // 껍질깨기
        case 579:                                                                                        // 플라워가드: every Grass type's 방어
            let grass = [Side.me, .it].filter { f($0).alive && f($0).typeList.contains("grass") }; guard !grass.isEmpty else { fail(); return true }
            for x in grass { boost(x, 2, 1, from: s) }
        case 470, 471:                                                                                   // 가드셰어 · 파워셰어: the two stats averaged
            let ks = id == 470 ? [2, 4] : [1, 3]
            var a = f(s).statOver ?? f(s).body.stats, b = f(t).statOver ?? f(t).body.stats
            for k in ks { let v = (a[k] + b[k]) / 2; a[k] = v; b[k] = v }
            mod(s) { $0.statOver = a }; mod(t) { $0.statOver = b }; say(s, id == 470 ? "서로의 가드를 나누었다!" : "서로의 파워를 나누었다!")
        case 576:                                                                                        // 뒤집어엎기
            guard f(t).stage[1...7].contains(where: { $0 != 0 }) else { fail(); return true }
            mod(t) { for k in 1...7 { $0.stage[k] = -$0.stage[k] } }; say(t, josa(tn, "의", "의") + " 능력 변화가 뒤집혔다!")
        case 588, 596:                                                                                   // 킹실드 · 니들가드: 방어's odds in a row
            let odds = [1, 3, 9, 27, 81, 243, 729][min(6, f(s).protectChain)]
            guard (f(s).protectChain == 0 || roll(odds) == 0) && !f(other(s)).movedThisTurn else { mod(s) { $0.protectChain = 0 }; fail(); return true }
            mod(s) { $0.protectChain += 1; $0.protected = true; $0.shield = id }; say(s, josa(n, "은", "는") + " 방어 태세에 들어갔다!")
        case 561:                                                                                        // 마룻바닥세워막기: its first turn out only
            guard f(s).turnsOut <= 1, !f(other(s)).movedThisTurn else { fail(); return true }
            mod(s) { $0.protected = true; $0.shield = id }; say(s, josa(n, "은", "는") + " 다다미를 세워서 막았다!")
        case 469, 501, 578:                                                                              // 와이드가드 · 패스트가드 · 트릭가드 (Gen VI: never fail in a row)
            guard !f(other(s)).movedThisTurn else { fail(); return true }
            mod(s) { $0.protected = true; $0.shield = id }; say(s, josa(n, "은", "는") + " " + josa(m.name, "으로", "로") + " 몸을 지켰다!")
        case 564:                                                                                        // 끈적끈적네트
            guard sides[si(t)].stickyWeb != true else { fail(); return true }
            sides[si(t)].stickyWeb = true; say(t, (t == .it ? "상대" : "우리 편") + " 주위에 끈적끈적네트가 펼쳐졌다!")
        case 487:                                                                                        // 물붓기
            guard f(t).typeList != ["water"], !f(t).has(121) else { fail(); return true }
            mod(t) { $0.types = ["water"]; $0.addedType = nil }; retyped(t); say(t, josa(tn, "은", "는") + " 물 타입이 되었다!")
        case 567, 571:                                                                                   // 핼러윈 · 숲의저주: a third type (the other's one off)
            let ty = id == 567 ? "ghost" : "grass"
            guard !f(t).typeList.contains(ty) else { fail(); return true }
            mod(t) { $0.addedType = ty }; retyped(t); say(t, josa(tn, "에게", "에게") + " " + (typeKo[ty] ?? ty) + " 타입이 추가되었다!")
        case 493:                                                                                        // 심플빔
            guard ![86, 121, 54, 176].contains(f(t).ability) else { fail(); return true }
            mod(t) { $0.abilityOver = 86 }; say(t, josa(tn, "은", "는") + " 단순 특성이 되었다!")
        case 494:                                                                                        // 동료만들기: its ability on the other
            let a = f(s).ability
            guard a != f(t).ability, ![36, 59, 122, 149, 150, 161, 121, 176].contains(a), ![121, 54, 176].contains(f(t).ability) else { fail(); return true }
            mod(t) { $0.abilityOver = a }; say(t, josa(tn, "은", "는") + " " + josa(abilityNames[a] ?? "", "이", "가") + " 되었다!")
        case 600: mod(t) { $0.powdered = true }; say(t, josa(tn, "에게", "에게") + " 분진을 뿌렸다!")       // 분진
        case 580, 581:                                                                                   // 그래스필드 · 미스트필드: 5 turns
            let tr: Terrain = id == 580 ? .grassy : .misty
            guard terrain != tr || (terrainLeft ?? 0) == 0 else { fail(); return true }
            terrain = tr; terrainLeft = 5; say(s, tr == .grassy ? "발밑에 풀이 무성해졌다!" : "발밑이 안개로 자욱해졌다!")
        case 472:                                                                                        // 원더룸 (again: back)
            wonderRoom = wonderRoomOn ? 0 : 5; say(s, wonderRoomOn ? "방어와 특수방어가 바뀌는 이상한 공간을 만들었다!" : "원더룸이 해제되어 방어와 특수방어가 원래대로 돌아왔다!")
        case 478:                                                                                        // 매직룸 (again: back)
            magicRoom = (magicRoom ?? 0) > 0 ? 0 : 5; say(s, (magicRoom ?? 0) > 0 ? "도구의 효과가 없어지는 이상한 공간을 만들었다!" : "매직룸이 해제되어 도구의 효과가 원래대로 돌아왔다!")
        case 569: ionDeluge = turnNo; say(s, "전자가 흩어지는 비가 쏟아졌다!")                          // 플라스마샤워: Normal moves are Electric this turn
        case 582:                                                                                        // 송전: its move this turn is Electric
            guard !f(t).movedThisTurn else { fail(); return true }
            mod(t) { $0.electrified = true }; say(t, josa(tn + "의 기술", "에", "에") + " 전기가 흐르기 시작했다!")
        case 587: fairyLock = turnNo + 1; say(s, "다음 턴에는 도망칠 수 없게 되었다!")                  // 페어리록
        case 477:                                                                                        // 텔레키네시스: 3 turns up in the air, every move hits it
            guard (f(t).telekinesis ?? 0) == 0, gravity == 0, f(t).smackedDown != true, !f(t).ingrain else { fail(); return true }
            mod(t) { $0.telekinesis = 3 }; say(t, josa(tn, "은", "는") + " 공중에 떠올랐다!")
        default: return false
        }
        return true
    }
    /// The stat moves (category 2) with a condition the data doesn't carry: true = done here (said), false = go on as usual.
    mutating func gen6StatRule(_ s: Side, _ t: Side, _ m: MoveInfo) -> Bool {
        switch m.id {
        case 599 where ![.poison, .toxic].contains(f(t).status): say(s, "그러나 실패했다!"); return true   // 베놈트랩: a poisoned one only
        case 602 where !f(s).has(57) && !f(s).has(58): say(s, "그러나 실패했다!"); return true             // 자기장조작: 플러스 · 마이너스
        case 563:                                                                                        // 일구기: every grounded Grass type's 공격 · 특수공격
            let grass = [Side.me, .it].filter { f($0).alive && grounded($0) && f($0).typeList.contains("grass") }
            guard !grass.isEmpty else { say(s, "그러나 실패했다!"); return true }
            for x in grass { boost(x, 1, 1, from: s); boost(x, 3, 1, from: s) }; return true
        default: return false
        }
    }
    /// After a category-2 move: 바디퍼지's weight, 막말내뱉기's way out.
    mutating func gen6StatAfter(_ s: Side, _ m: MoveInfo) {
        if m.id == 475 { mod(s) { $0.lighter = ($0.lighter ?? 0) + 1 }; say(s, josa(nm(s), "은", "는") + " 가벼워졌다!") }
        if m.id == 575, f(s).alive, let i = nextAlive(s) { say(s, josa(nm(s), "은", "는") + " 돌아왔다!"); switchIn(s, i) }
    }

    // MARK: the turn
    /// 분진: a Fire move from a powdered one explodes (1/4 of its HP) instead of going off. True: it did.
    mutating func powderBlast(_ s: Side, _ id: Int) -> Bool {
        guard f(s).powdered == true, moveType(s, moveTable[id]!).type == "fire" else { return false }
        say(s, "분진이 폭발했다!"); hurt(s, max(1, f(s).maxHP / 4), ""); return true
    }
    /// 끈적끈적네트 on coming out (grounded: 스피드 -1).
    mutating func stickyWebEntry(_ s: Side) {
        guard sides[si(s)].stickyWeb == true, grounded(s), f(s).alive else { return }
        say(s, josa(nm(s), "은", "는") + " 끈적끈적네트에 걸렸다!"); boost(s, 5, -1, from: other(s))
    }
    /// The end of a turn's Gen V–VI part: 그래스필드's healing, the fields and rooms running out, 텔레키네시스.
    mutating func gen6EndOfTurn() {
        if terrainUnder(.me) == .grassy || terrainUnder(.it) == .grassy {
            for s in [Side.me, .it] where f(s).alive && terrainUnder(s) == .grassy && f(s).hp < f(s).maxHP { restore(s, max(1, f(s).maxHP / 16), josa(nm(s), "은", "는") + " 그래스필드로 체력을 회복했다!") }
        }
        if let k = terrainLeft, k > 0 { terrainLeft = k - 1; if k == 1 { say(.it, terrain == .grassy ? "발밑의 풀이 사라졌다!" : "발밑의 안개가 사라졌다!"); terrain = nil } }
        if let k = wonderRoom, k > 0 { wonderRoom = k - 1; if k == 1 { say(.it, "원더룸이 해제되어 방어와 특수방어가 원래대로 돌아왔다!") } }
        if let k = magicRoom, k > 0 { magicRoom = k - 1; if k == 1 { say(.it, "매직룸이 해제되어 도구의 효과가 원래대로 돌아왔다!") } }
        for s in [Side.me, .it] where (f(s).telekinesis ?? 0) > 0 {
            mod(s) { $0.telekinesis = $0.telekinesis! - 1 }; if f(s).telekinesis == 0 { mod(s) { $0.telekinesis = nil }; say(s, josa(nm(s), "은", "는") + " 땅으로 내려왔다!") }
        }
    }
}
