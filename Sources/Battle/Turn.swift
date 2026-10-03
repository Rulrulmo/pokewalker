import Foundation
// A turn: the opening, switching, move order, what stops a move, then the move itself.

// MARK: - a turn
extension Battle {
    /// The opening: the wild one appears (or the trainer sends one out); the course's weather settles over the field; switch-in abilities fire.
    mutating func begin<R: RandomNumberGenerator>(weather: Weather?, _ r: inout R) -> [Beat] {
        seed = r.next() | 1; out = []
        switch weather { case .rain?: sky = .rain; case .snow?: sky = .hail; case .fog?: sky = .fog; default: break }
        out.append(trainer == nil ? .appear : .sendOut(.it, 0))
        switch sky { case .rain: say(.it, "비가 계속 내리고 있다"); case .hail: say(.it, "싸라기눈이 계속 내리고 있다"); case .fog: say(.it, "안개가 깊다..."); default: break }
        entry(.me); entry(.it)
        return out
    }
    /// Switch-in: hazards, then abilities (위협, weather, 다운로드, 트레이스, 프레셔 …).
    mutating func entry(_ s: Side) {
        let t = other(s), n = nm(s), side = sides[si(s)]
        if grounded(s), !f(s).has(98) {
            if side.spikes > 0 { hurt(s, f(s).maxHP * [0, 1, 2, 3][side.spikes] / [1, 8, 12, 16][side.spikes], josa(n, "은", "는") + " 압정뿌리기의 데미지를 입었다!") }
            if side.toxicSpikes > 0 { if f(s).typeList.contains("poison") { sides[si(s)].toxicSpikes = 0; say(s, "독압정이 사라졌다!") } else { inflict(s, side.toxicSpikes >= 2 ? .toxic : .poison, from: t, loud: false, sync: false) } }
        }
        if side.stealthRock, !f(s).has(98) { hurt(s, max(1, Int(Double(f(s).maxHP) * typeEff("rock", s, by: t) / 8)), "뾰족한 바위가 " + josa(n, "을", "를") + " 파고들었다!") }
        if side.healingWish {
            sides[si(s)].healingWish = false; sides[si(s)].lunarDance = false
            if f(s).alive {                                                                          // (not one the hazards just KO'd)
                restore(s, f(s).maxHP, side.lunarDance ? "초승달춤의 힘을 받았다!" : "치유의 소원이 이루어졌다!"); if f(s).status != nil { setStatus(s, nil, "") }
                if side.lunarDance { mod(s) { $0.pp = $0.moves.map { moveTable[$0]?.pp ?? 5 } } }    // 초승달춤: the PP too
            }
        }
        faints()
        guard f(s).alive, !over else { return }
        switch f(s).ability {
        case 22: say(s, josa(n, "의", "의") + " 위협!"); boost(t, 1, -1, from: s)
        case 2: sky = .rain; skyTurns = 0; say(s, josa(n, "의", "의") + " 잔비로 비가 내리기 시작했다!")
        case 70: sky = .sun; skyTurns = 0; say(s, josa(n, "의", "의") + " 가뭄으로 햇살이 강해졌다!")
        case 45: sky = .sand; skyTurns = 0; say(s, josa(n, "의", "의") + " 모래날림으로 모래바람이 불기 시작했다!")
        case 117: sky = .hail; skyTurns = 0; say(s, josa(n, "의", "의") + " 눈퍼뜨리기로 싸라기눈이 내리기 시작했다!")
        case 88 where f(t).alive: boost(s, base(t, 2) < base(t, 4) ? 1 : 3, 1, from: s)
        case 36 where f(t).alive: let a = f(t).ability; if ![0, 36, 121].contains(a) { mod(s) { $0.abilityOver = a }; say(s, josa(n, "은", "는") + " " + monNames[f(t).mon.dex] + "의 " + josa(abilityNames[a]!, "을", "를") + " 트레이스했다!") }
        case 46: say(s, josa(n, "은", "는") + " 프레셔를 발휘하고 있다!")
        case 104: say(s, josa(n, "은", "는") + " 틀을 깼다!")
        case 112: mod(s) { $0.slowStart = 5 }; say(s, josa(n, "은", "는") + " 좀처럼 힘을 낼 수 없다!")
        case 107 where f(t).alive: if f(t).moves.contains(where: { let m = moveTable[$0]!; return !m.isStatus && typeEff(m.type, s, by: t) > 1 }) { say(s, josa(n, "은", "는") + " 몸서리를 쳤다!") }
        case 108 where f(t).alive: if let best = f(t).moves.max(by: { (moveTable[$0]?.power ?? 0) < (moveTable[$1]?.power ?? 0) }) { say(s, josa(monNames[f(t).mon.dex] + "의 " + moveTable[best]!.name, "을", "를") + " 꿰뚫어 보았다!") }
        default: break
        }
        forecast()
    }
    mutating func forecast() {
        for s in [Side.me, .it] where f(s).mon.dex == 351 && f(s).has(59) {
            let ty = ["sun": "fire", "rain": "water", "hail": "ice"]["\(weatherOn)"] ?? "normal"
            if f(s).types != [ty] { mod(s) { $0.types = [ty] }; retyped(s) }
        }
    }
    /// s sends out #i (baton = keep stages, substitute, confusion, seeds...).
    mutating func switchIn(_ s: Side, _ i: Int, baton: Bool = false) {
        let keep = f(s)
        mod(other(s)) { $0.bound = 0; $0.attracted = false; if !baton { $0.trapped = $0.ingrain } }   // the one leaving lets go of what it held on the other (조이기, 헤롱헤롱; 검은눈빛 passes with 바톤터치)
        if f(s).has(30), f(s).status != nil, f(s).alive { mod(s) { $0.status = nil } }             // 자연회복 (quietly, as it leaves)
        mod(s) { $0.clearVolatile() }
        out.append(.sendOut(s, i)); apply(out.last!)
        if s == .me { faced.insert(i) } else { faced = [me] }
        if baton { mod(s) { $0.stage = keep.stage; $0.sub = keep.sub; $0.confused = keep.confused; $0.seeded = keep.seeded; $0.focus = keep.focus; $0.cursed = keep.cursed; $0.ingrain = keep.ingrain; $0.aquaRing = keep.aquaRing; $0.perish = keep.perish; $0.magnetRise = keep.magnetRise
            $0.trapped = keep.trapped; $0.lockOn = keep.lockOn; $0.healBlock = keep.healBlock; $0.embargo = keep.embargo; if keep.abilityOver == 0 { $0.abilityOver = 0 } } }
        entry(s)
    }

    /// One turn. The last beat `ends` the battle when it's over. ball = the thrown ball's catch multiplier.
    mutating func turn<R: RandomNumberGenerator>(_ m: Move, _ r: inout R, ball: Double = 1) -> [Beat] {
        seed = r.next() | 1; out = []; turnNo += 1
        inTurn = true; play(m, ball: ball); inTurn = false
        if let n = foeNext, !over { foeNext = nil; switchIn(.it, n) }                              // a trainer's KO'd one: the next comes out once the turn is over (kept if it ended: a revive goes on)
        return out
    }
    private mutating func play(_ m: Move, ball: Double) {
        for s in [Side.me, .it] { mod(s) { $0.protected = false; $0.endure = false; $0.flinch = false; $0.hitThisTurn = false; $0.movedThisTurn = false; $0.magicCoat = false; $0.turnsOut += 1 } }
        let foe = foeChoice(), (mi, ti) = (me, it)
        planned = [0, foe]
        if trainer != nil, let i = foeSwitch() {                                                   // switching goes before any move; it then doesn't act (ti is gone)
            say(.it, josa(trainer!, "은", "는") + " " + josa(monNames[f(.it).mon.dex], "을", "를") + " 돌아오게 했다!"); switchIn(.it, i); planned[1] = 0
        }
        switch m {
        case .run:
            if trainer != nil { say(.me, "승부 중에는 도망칠 수 없다!"); return }
            if canEscape() { out.append(.ran); over = true; return }
            say(.me, "도망칠 수 없었다!")
        case .capture: if throwBall(ball) { return }
        case .item(let u): useItem(u)
        case .swap(let i): switchIn(.me, i)
        case .fight(let id):
            planned[0] = id
            if moveFirst(id, foe) { act(.me, id, mi); act(.it, foe, ti) } else { act(.it, foe, ti); act(.me, id, mi) }
            if !over { endOfTurn() }
            return
        }
        act(.it, foe, ti)
        if !over { endOfTurn() }
    }
    /// Ours fainted and the player picked who's next (the turn's already over).
    mutating func replace(_ i: Int) -> [Beat] { out = []; mustReplace = false; switchIn(.me, i); return out }
    /// Priority, then speed (Trick Room flips it; 늑장 goes last); ties at random.
    mutating func moveFirst(_ a: Int, _ b: Int) -> Bool {
        let pa = moveTable[a]!.priority, pb = moveTable[b]!.priority
        if pa != pb { return pa > pb }
        if f(.me).has(100) != f(.it).has(100) { return f(.it).has(100) }
        let sa = speed(.me), sb = speed(.it)
        if sa == sb { return roll(2) == 0 }
        return trickRoom > 0 ? sa < sb : sa > sb
    }

    /// Everything that can stop a move before it starts; then the move.
    mutating func act(_ s: Side, _ id0: Int, _ index: Int) {
        guard !over, f(s).alive, (s == .me ? me : it) == index else { return }                     // a replacement doesn't move the turn it comes in
        mod(s) { $0.movedThisTurn = true; $0.destinyBond = false; $0.grudge = false }                // 길동무 / 원념 last until it moves again
        let n = nm(s)
        var id = id0
        if f(s).recharge { mod(s) { $0.recharge = false }; say(s, josa(n, "은", "는") + " 공격의 반동으로 움직일 수 없다!"); return }
        if f(s).charging != 0 { id = f(s).charging } else if f(s).lock > 0 { id = f(s).lockMove } else if f(s).bide > 0 { id = 117 } else if f(s).encore > 0 { id = f(s).encoreMove }
        if f(s).status == .sleep {
            mod(s) { $0.sleep -= $0.has(48) ? 2 : 1 }
            if f(s).sleep <= 0 { setStatus(s, nil, josa(n, "은", "는") + " 눈을 떴다!"); mod(s) { $0.nightmare = false } }
            else if id != 173 && id != 214 { say(s, josa(n, "은", "는") + " 쿨쿨 잠들어 있다"); stop(s); return }
        }
        if f(s).status == .freeze {
            if moveTable[id]!.defrosts || pct(20) { setStatus(s, nil, josa(n, "의", "의") + " 얼음이 녹았다!") }
            else { say(s, josa(n, "은", "는") + " 얼어버려서 움직일 수 없다!"); stop(s); return }
        }
        if f(s).has(54) { if f(s).truantSkip { mod(s) { $0.truantSkip = false }; say(s, josa(n, "은", "는") + " 게으름을 피우고 있다"); stop(s); return }; mod(s) { $0.truantSkip = true } }
        if f(s).flinch { say(s, josa(n, "은", "는") + " 풀이 죽어 기술을 쓸 수 없다!"); if f(s).has(80) { boost(s, 5, 1, from: s) }; stop(s); return }
        if f(s).disable > 0, f(s).disabledMove == id { say(s, josa(n, "의", "의") + " " + josa(moveTable[id]!.name, "은", "는") + " 사용할 수 없다!"); stop(s); return }
        if f(s).taunt > 0, moveTable[id]!.isStatus { say(s, josa(n, "은", "는") + " 도발당해서 " + josa(moveTable[id]!.name, "을", "를") + " 쓸 수 없다!"); stop(s); return }
        if f(s).torment, id == f(s).lastMove, id != 165 { say(s, josa(n, "은", "는") + " 트집 때문에 같은 기술을 쓸 수 없다!"); stop(s); return }
        if f(s).confused > 0 {
            mod(s) { $0.confused -= 1 }
            if f(s).confused == 0 { say(s, josa(n, "의", "의") + " 혼란이 풀렸다!") }
            else {
                say(s, josa(n, "은", "는") + " 혼란스러워 하고 있다!")
                if pct(50) { hurt(s, confusionHit(s), "영문도 모른 채 자신을 공격했다!"); stop(s); faints(); return }
            }
        }
        if f(s).attracted { say(s, josa(n, "은", "는") + " 사랑에 빠져 있다!"); if pct(50) { say(s, josa(n, "은", "는") + " 헤롱헤롱해서 기술을 쓸 수 없었다!"); stop(s); return } }
        if f(s).status == .paralysis, pct(25) { say(s, josa(n, "은", "는") + " 몸이 저려서 움직일 수 없다!"); stop(s); return }
        if gravity > 0, [19, 340, 26, 136, 150].contains(id) { say(s, "중력 때문에 " + josa(moveTable[id]!.name, "을", "를") + " 쓸 수 없다!"); stop(s); return }
        if moveTable[id]!.onFoe, !f(other(s)).alive { stop(s); return }                         // its target fainted (a replacement comes at the end of the turn): the turn's checks still count
        let lk = f(s).lock, bd = f(s).bide
        execute(s, id, called: false)
        if lk > 0, f(s).lock == lk { mod(s) { $0.lock = 0; $0.rollout = 0; $0.uproar = 0 } }      // a locked move that missed or was blocked ends there (no confusion)
        if bd > 0, f(s).bide == bd { mod(s) { $0.bide = 0 } }                                     // so does 참기 that met an immunity
        faints()
    }
    /// A move that didn't happen ends whatever it was in the middle of: charging, flying up, a rampage, 참기, 소란, 구르기, 연속자르기.
    mutating func stop(_ s: Side) { mod(s) { $0.charging = 0; $0.semi = 0; $0.lock = 0; $0.bide = 0; $0.uproar = 0; $0.rollout = 0; $0.furyCutter = 0 } }
    mutating func confusionHit(_ s: Side) -> Int {
        let a = f(s), A = Double(base(s, 1)) * mult(a.stage[1]), D = Double(base(s, 2)) * mult(a.stage[2])
        return max(1, Int((floor(floor(Double(2 * a.mon.level / 5 + 2) * 40 * A / D) / 50) + 2) * Double(85 + roll(16)) / 100))
    }
    mutating func deductPP(_ s: Side, _ id: Int) {
        let cost = f(other(s)).alive && f(other(s)).has(46) ? 2 : 1
        mod(s) { if let k = $0.moves.firstIndex(of: id) { $0.pp[k] = max(0, $0.pp[k] - cost); if $0.pp[k] == 0, $0.encore > 0, $0.encoreMove == id { $0.encore = 0 } } }   // 앙코르 ends with the PP
    }

    /// The move itself: charging, callers, protection, accuracy, then damage or its effect. depth = callers above it (흉내쟁이 → 따라하기 → 자연의힘 → 트라이어택 is 3);
    /// past that a call fails rather than recursing on.
    mutating func execute(_ s: Side, _ id: Int, called: Bool, depth: Int = 0) {
        if depth > 3 { say(s, "그러나 실패했다!"); return }
        let m = moveTable[id]!, t = other(s), n = nm(s)
        if m.charges, f(s).charging != id, !(id == 76 && weatherOn == .sun) {                  // turn 1 of a two-turn move
            if !called { deductPP(s, id) }
            mod(s) { $0.charging = id; if Moves.semiInvulnerable.contains(id) { $0.semi = id } }
            let line = [76: "빛을 흡수했다!", 19: "하늘 높이 날아올랐다!", 91: "땅으로 파고들었다!", 291: "물속으로 잠수했다!", 340: "높이 뛰어올랐다!", 467: "모습을 감췄다!",
                        13: "회오리를 일으켰다!", 130: "목을 움츠렸다!", 143: "강렬한 빛에 휩싸였다!"][id] ?? "힘을 모으고 있다!"
            out.append(.use(s, move: id)); say(s, josa(n, "은", "는") + " " + line)
            if id == 130 { boost(s, 2, 1, from: s) }
            return
        }
        let second = f(s).charging == id
        mod(s) { $0.charging = 0; $0.semi = 0 }
        if !called && !second && f(s).lock == 0 && f(s).bide == 0 { deductPP(s, id) }           // a rampage's / 참기's later turns are free
        out.append(.use(s, move: id))
        if !called { mod(s) { $0.lastMove = id } }                                                 // 앙코르 / 사슬묶기 / 트집 see the caller, not what 손가락흔들기 & co. called
        if id != 210 { mod(s) { $0.furyCutter = 0 } }                                              // 연속자르기's streak breaks on anything else
        let before = lastUsed; lastUsed = id
        switch id {                                                                                  // moves that pick another move
        case 118:
            let pool = moveTable.keys.filter { Moves.supported($0) && ![118, 165, 102, 144, 214, 119, 383, 267, 264, 182, 197, 203, 68, 243, 194].contains($0) }.sorted()
            let pick = pool[roll(pool.count)]; say(s, "손가락흔들기로 " + josa(moveTable[pick]!.name, "이", "가") + " 나왔다!"); execute(s, pick, called: true, depth: depth + 1); return
        case 214:
            let ok = f(s).moves.filter { ![214, 117, 118, 119, 383, 264, 253, 13, 19, 76, 91, 130, 143, 291, 340, 467].contains($0) }
            guard f(s).status == .sleep, !ok.isEmpty else { say(s, "그러나 실패했다!"); return }
            execute(s, ok[roll(ok.count)], called: true, depth: depth + 1); return
        case 119:                                                                                    // only a move aimed at us: not 칼춤, nor 흉내쟁이 & co. (they target their user — 흉내쟁이 ↔ 따라하기 would call each other forever)
            let last = f(t).lastMove
            guard last != 0, Moves.supported(last), last != 119, moveTable[last]!.onFoe else { say(s, "그러나 실패했다!"); return }
            execute(s, last, called: true, depth: depth + 1); return
        case 383: guard before != 0, before != 383 else { say(s, "그러나 실패했다!"); return }; execute(s, before, called: true, depth: depth + 1); return
        case 267: say(s, "자연의힘은 트라이어택이 되었다!"); execute(s, 161, called: true, depth: depth + 1); return
        default: break
        }
        if m.onFoe && m.protectable && f(t).protected && id != 364 { say(t, josa(nm(t), "은", "는") + " 공격으로부터 몸을 지켰다!"); crash(s, t, m); return }
        if m.onFoe && m.reflectable && f(t).magicCoat { say(t, josa(nm(t), "은", "는") + " 매직코트로 " + josa(m.name, "을", "를") + " 튕겨냈다!"); statusMove(t, s, m); return }
        if m.onFoe, f(t).semi != 0, !canHitSemi(id, f(t).semi), !(f(s).has(99) || f(t).has(99)), f(s).lockOn == 0 { say(t, josa(nm(t), "에게는", "에게는") + " 맞지 않았다!"); crash(s, t, m); return }
        if (m.onFoe || m.accuracy > 0) && !m.onSelf, !hits(s, t, m) { say(t, josa(n, "의", "의") + " 공격은 빗나갔다!"); crash(s, t, m); mod(s) { $0.rollout = 0; $0.furyCutter = 0 }; return }
        if m.onFoe, m.sound, id != 195, dAb(t, 43, by: s) { say(t, josa(nm(t), "은", "는") + " 방음으로 소리를 막았다!"); return }
        if id == 86, typeEff("electric", t, by: s) == 0 || dAb(t, 10, by: s) || dAb(t, 78, by: s) {        // 전기자석파 is the one status move type immunity stops
            say(t, josa(nm(t), "에게는", "에게는") + " 효과가 없는 것 같다..."); return
        }
        if (m.power > 0 || Moves.fixedOrVariable.contains(id)) && id != 248 && id != 353 { damageMove(s, t, m) } else { statusMove(s, t, m) }   // 미래예지 / 파멸의소원 land later
    }
}
