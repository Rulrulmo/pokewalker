import Foundation
// Status conditions and every status / field move.

extension Battle {
    // MARK: status and field moves
    mutating func ailment(_ t: Side, _ a: String, from s: Side, loud: Bool, move m: MoveInfo) {
        switch a {
        case "paralysis": inflict(t, .paralysis, from: s, loud: loud)
        case "sleep": inflict(t, .sleep, from: s, loud: loud)
        case "freeze": inflict(t, .freeze, from: s, loud: loud)
        case "burn": inflict(t, .burn, from: s, loud: loud)
        case "poison": inflict(t, [92, 305].contains(m.id) ? .toxic : .poison, from: s, loud: loud)          // 맹독, 독엄니: bad poison
        case "confusion": confuse(t, from: s, loud: loud)
        case "infatuation": attract(t, from: s, loud: loud)
        case "leech-seed":
            if f(t).typeList.contains("grass") || f(t).seeded { if loud { say(t, "그러나 실패했다!") }; return }
            mod(t) { $0.seeded = true }; say(t, josa(nm(t), "에게", "에게") + " 씨앗을 심었다!")
        case "yawn": if f(t).status == nil, f(t).yawn == 0 { mod(t) { $0.yawn = 2 }; say(t, josa(nm(t), "의", "의") + " 졸음을 유도했다!") } else if loud { say(t, "그러나 실패했다!") }
        case "nightmare": if f(t).status == .sleep, !f(t).nightmare { mod(t) { $0.nightmare = true }; say(t, josa(nm(t), "은", "는") + " 악몽을 꾸기 시작했다!") } else if loud { say(t, "그러나 실패했다!") }
        case "torment": mod(t) { $0.torment = true }; say(t, josa(nm(t), "은", "는") + " 트집을 잡혔다!")
        case "disable":
            guard f(t).lastMove != 0, f(t).disable == 0 else { if loud { say(t, "그러나 실패했다!") }; return }
            let k = 4 + roll(4); mod(t) { $0.disable = k; $0.disabledMove = $0.lastMove }; say(t, josa(nm(t), "의", "의") + " " + josa(moveTable[f(t).lastMove]!.name, "을", "를") + " 사슬묶기했다!")
        case "heal-block": mod(t) { $0.healBlock = 5 }; say(t, josa(nm(t), "은", "는") + " 회복봉인 당했다!")
        case "no-type-immunity": mod(t) { if m.id == 357 { $0.miracleEye = true } else { $0.identified = true }; $0.stage[7] = min(0, $0.stage[7]) }; say(t, josa(nm(t), "의", "의") + " 정체를 꿰뚫어 보았다!")   // 미라클아이: Psychic on Dark; 꿰뚫어보기 / 냄새구별: Normal & Fighting on Ghost
        case "embargo": mod(t) { $0.embargo = 5 }; say(t, josa(nm(t), "은", "는") + " 도구를 쓸 수 없게 되었다!")
        case "perish-song":
            say(t, "멸망의 노래를 들은 포켓몬은 3턴 후에 쓰러진다!")
            for x in [Side.me, .it] where f(x).perish == 0 && !f(x).has(43) { mod(x) { $0.perish = 4 } }
        case "ingrain": mod(s) { $0.ingrain = true; $0.trapped = true }; say(s, josa(nm(s), "은", "는") + " 뿌리를 내렸다!")
        case "trap": if m.isStatus { mod(t) { $0.trapped = true }; say(t, josa(nm(t), "은", "는") + " 이제 도망칠 수 없다!") }
        default: if loud { say(t, "그러나 아무 일도 일어나지 않았다!") }
        }
    }
    mutating func attract(_ t: Side, from s: Side, loud: Bool) {
        let a = f(s).mon, b = f(t).mon
        guard genderRate[a.dex] >= 0, genderRate[b.dex] >= 0, a.female != b.female, !f(t).attracted, !f(t).has(12) else { if loud { say(t, "그러나 실패했다!") }; return }
        mod(t) { $0.attracted = true }; say(t, josa(nm(t), "은", "는") + " 헤롱헤롱해졌다!")
        if holds(t, "빨간실"), f(s).alive, !f(s).attracted, !f(s).has(12) { mod(s) { $0.attracted = true }; say(s, "빨간실 때문에 " + josa(nm(s), "도", "도") + " 헤롱헤롱해졌다!") }
    }
    mutating func statusMove(_ s: Side, _ t: Side, _ m: MoveInfo) {
        let id = m.id, n = nm(s), tn = nm(t)
        func fail() { say(s, "그러나 실패했다!") }
        switch m.cat {
        case 1: if f(t).sub > 0 && m.onFoe && m.ailment != "perish-song" { fail() } else { ailment(m.onSelf ? s : t, m.ailment, from: s, loud: true, move: m) }; return
        case 2:
            let who = m.onSelf ? s : t
            if id == 445, genderRate[f(s).mon.dex] < 0 || genderRate[f(t).mon.dex] < 0 || f(s).mon.female == f(t).mon.female { fail(); return }
            for k in stride(from: 0, to: m.stats.count, by: 2) { boost(who, m.stats[k] - 1, m.stats[k + 1], from: s) }
            if id == 107 { mod(s) { $0.minimized = true } }; if id == 111 { mod(s) { $0.curled = true } }
            if id == 268 { mod(s) { $0.charge = 2 }; say(s, josa(n, "은", "는") + " 충전했다!") }                    // its next turn's Electric move
            return
        case 3:
            var p = m.healing
            if [234, 235, 236].contains(id) { p = weatherOn == .sun ? 67 : weatherOn == .clear ? 50 : 25 }   // any other weather (fog too): a quarter
            if id == 256 { guard f(s).stockpile > 0 else { fail(); return }; let k = f(s).stockpile; p = [0, 25, 50, 100][k]; mod(s) { $0.stockpile = 0 }; boost(s, 2, -k, from: s); boost(s, 4, -k, from: s) }
            if id == 355 { mod(s) { $0.roosted = true } }
            if f(s).hp == f(s).maxHP { say(s, josa(n, "의", "의") + " HP는 가득하다!"); return }
            restore(s, f(s).maxHP * p / 100, josa(n, "은", "는") + " 체력을 회복했다!"); return
        case 5:
            if f(t).sub > 0 { fail(); return }
            for k in stride(from: 0, to: m.stats.count, by: 2) { boost(t, m.stats[k] - 1, m.stats[k + 1], from: s) }
            confuse(t, from: s, loud: true); return
        default: break
        }
        switch id {                                                                                  // everything with its own rule
        case 150: say(s, "그러나 아무 일도 일어나지 않았다!")
        case 254:                                                                                    // 비축하기: up to 3, each +1 방어 / 특수방어 (토해내기 / 꿀꺽 spend them)
            guard f(s).stockpile < 3 else { fail(); return }
            mod(s) { $0.stockpile += 1 }; say(s, josa(n, "은", "는") + " \(f(s).stockpile)개 비축했다!"); boost(s, 2, 1, from: s); boost(s, 4, 1, from: s)
        case 182, 197, 203:
            let ok = (f(s).protectChain == 0 || roll(1 << min(8, f(s).protectChain)) == 0) && !f(other(s)).movedThisTurn   // fails when used last, and gets less likely in a row
            guard ok else { mod(s) { $0.protectChain = 0 }; fail(); return }
            mod(s) { $0.protectChain += 1; if id == 203 { $0.endure = true } else { $0.protected = true } }
            say(s, josa(n, "은", "는") + (id == 203 ? " 버티기 태세에 들어갔다!" : " 방어 태세에 들어갔다!")); return
        case 113, 115, 219, 54, 381, 366:
            let k = si(s), turns = id == 366 ? 3 : [113, 115].contains(id) && holds(s, "빛의점토") ? 8 : 5
            switch id {
            case 113: guard sides[k].light == 0 else { fail(); return }; sides[k].light = turns; say(s, "빛의장막으로 특수공격에 강해졌다!")
            case 115: guard sides[k].reflect == 0 else { fail(); return }; sides[k].reflect = turns; say(s, "리플렉터로 물리공격에 강해졌다!")
            case 219: guard sides[k].safeguard == 0 else { fail(); return }; sides[k].safeguard = turns; say(s, "신비의 베일에 둘러싸였다!")
            case 54: guard sides[k].mist == 0 else { fail(); return }; sides[k].mist = turns; say(s, "흰안개에 둘러싸였다!")
            case 381: guard sides[k].luckyChant == 0 else { fail(); return }; sides[k].luckyChant = turns; say(s, "행운의 주문으로 급소를 맞지 않게 되었다!")
            default: guard sides[k].tailwind == 0 else { fail(); return }; sides[k].tailwind = turns; say(s, "순풍이 불기 시작했다!")
            }
        case 114: for x in [Side.me, .it] { mod(x) { $0.stage = Array(repeating: 0, count: 8) } }; say(s, "모든 능력 변화가 원래대로 돌아왔다!")
        case 156:
            guard f(s).hp < f(s).maxHP, f(s).status != .sleep, !f(s).has(15), !f(s).has(72) else { fail(); return }
            setStatus(s, .sleep, josa(n, "은", "는") + " 잠들어 체력을 회복했다!"); mod(s) { $0.sleep = 3 }; restore(s, f(s).maxHP, "")   // asleep 2 turns
        case 116: guard !f(s).focus else { fail(); return }; mod(s) { $0.focus = true }; say(s, josa(n, "은", "는") + " 의욕이 넘치고 있다!")
        case 164:
            guard f(s).sub == 0, f(s).hp > f(s).maxHP / 4 else { fail(); return }
            let c = f(s).maxHP / 4; hurt(s, c, josa(n, "의", "의") + " 대타가 나타났다!"); mod(s) { $0.sub = c }
        case 18, 46:
            if dAb(t, 21, by: s) || f(t).ingrain { say(t, josa(tn, "은", "는") + " 꿈쩍도 하지 않는다!"); return }
            if trainer == nil { say(t, josa(tn, "은", "는") + " 멀리 날아갔다!"); out.append(s == .me ? .fled : .ran); over = true; return }
            let others = (t == .me ? mine : theirs).indices.filter { $0 != (t == .me ? me : it) && (t == .me ? mine : theirs)[$0].alive }
            guard !others.isEmpty else { fail(); return }
            say(t, josa(tn, "은", "는") + " 멀리 날아갔다!"); switchIn(t, others[roll(others.count)])
        case 100:
            guard trainer == nil, !f(s).trapped else { fail(); return }
            say(s, josa(n, "은", "는") + " 순간이동했다!"); out.append(s == .me ? .ran : .fled); over = true
        case 144:
            guard f(t).form == nil else { fail(); return }
            let src = f(t)
            mod(s) { if $0.ownMoves == nil { $0.ownMoves = $0.moves; $0.ownPP = $0.pp }; $0.form = src.form ?? src.mon; $0.types = src.typeList; $0.stage = src.stage; $0.moves = src.moves; $0.pp = src.moves.map { _ in 5 }; $0.abilityOver = src.ability }; retyped(s)
            say(s, josa(n, "은", "는") + " " + josa(monNames[src.mon.dex], "으로", "로") + " 변신했다!")
        case 102:
            guard f(t).lastMove != 0, !f(s).moves.contains(f(t).lastMove), let k = f(s).moves.firstIndex(of: 102) else { fail(); return }
            let lm = f(t).lastMove; mod(s) { if $0.ownMoves == nil { $0.ownMoves = $0.moves; $0.ownPP = $0.pp }; $0.moves[k] = lm; $0.pp[k] = 5 }; say(s, josa(n, "은", "는") + " " + josa(moveTable[lm]!.name, "을", "를") + " 흉내 냈다!")
        case 160:
            let ts = f(s).moves.compactMap { moveTable[$0]?.type }.filter { !f(s).typeList.contains($0) && $0 != "" }
            guard let ty = ts.first else { fail(); return }; mod(s) { $0.types = [ty] }; retyped(s); say(s, josa(n, "은", "는") + " " + (typeKo[ty] ?? ty) + " 타입이 되었다!")
        case 176:
            guard let lt = moveTable[f(t).lastMove]?.type else { fail(); return }
            let resist = typeKo.keys.filter { (typeChart[lt]?[$0] ?? 1) < 1 }.sorted()
            guard !resist.isEmpty else { fail(); return }; let ty = resist[roll(resist.count)]; mod(s) { $0.types = [ty] }; retyped(s); say(s, josa(n, "은", "는") + " " + (typeKo[ty] ?? ty) + " 타입이 되었다!")
        case 293: mod(s) { $0.types = ["normal"] }; retyped(s); say(s, josa(n, "은", "는") + " 노말 타입이 되었다!")
        case 169, 212, 335: guard !f(t).trapped else { fail(); return }; mod(t) { $0.trapped = true }; say(t, josa(tn, "은", "는") + " 이제 도망칠 수 없다!")
        case 170, 199: mod(s) { $0.lockOn = 2 }; say(s, josa(n, "은", "는") + " " + josa(tn, "을", "를") + " 노리고 있다!")
        case 174:
            if f(s).typeList.contains("ghost") {
                guard !f(t).cursed else { fail(); return }
                hurt(s, max(1, f(s).maxHP / 2), josa(n, "은", "는") + " 자신의 체력을 깎아 " + josa(tn, "에게", "에게") + " 저주를 걸었다!"); mod(t) { $0.cursed = true }
            } else { boost(s, 5, -1, from: s); boost(s, 1, 1, from: s); boost(s, 2, 1, from: s) }
        case 180:
            guard let k = f(t).moves.firstIndex(of: f(t).lastMove), f(t).pp[k] > 0 else { fail(); return }
            let c = min(f(t).pp[k], 4); mod(t) { $0.pp[k] -= c }; say(t, josa(tn + "의 " + moveTable[f(t).lastMove]!.name, "의", "의") + " PP가 \(c) 줄었다!")   // Gen IV: 4
        case 187:
            guard f(s).hp > f(s).maxHP / 2, f(s).stage[1] < 6 else { fail(); return }
            hurt(s, f(s).maxHP / 2, josa(n, "은", "는") + " 체력을 깎아서 공격을 최대로 올렸다!"); mod(s) { $0.stage[1] = 6 }
        case 191: guard sides[si(t)].spikes < 3 else { fail(); return }; sides[si(t)].spikes += 1; say(t, (t == .it ? "상대" : "우리 편") + " 주위에 압정이 뿌려졌다!")
        case 390: guard sides[si(t)].toxicSpikes < 2 else { fail(); return }; sides[si(t)].toxicSpikes += 1; say(t, (t == .it ? "상대" : "우리 편") + " 주위에 독압정이 뿌려졌다!")
        case 446: guard !sides[si(t)].stealthRock else { fail(); return }; sides[si(t)].stealthRock = true; say(t, (t == .it ? "상대" : "우리 편") + " 주위에 뾰족한 바위가 떠다니기 시작했다!")
        case 194: mod(s) { $0.destinyBond = true }; say(s, josa(n, "은", "는") + " 상대를 길동무로 삼으려 하고 있다!")
        case 201, 240, 241, 258:
            let sk: Sky = [201: .sand, 240: .rain, 241: .sun, 258: .hail][id]!
            guard sky != sk else { fail(); return }
            sky = sk; skyTurns = holds(s, [201: "보송보송바위", 240: "축축한바위", 241: "뜨거운바위", 258: "차가운바위"][id]!) ? 8 : 5; forecast()
            say(s, [201: "모래바람이 불기 시작했다!", 240: "비가 내리기 시작했다!", 241: "햇살이 강해졌다!", 258: "싸라기눈이 내리기 시작했다!"][id]!)
        case 215, 312:
            for i in (s == .me ? mine : theirs).indices { if s == .me { mine[i].status = nil } else { theirs[i].status = nil } }
            setStatus(s, nil, "동료의 상태이상이 모두 나았다!")
        case 220:
            let avg = (f(s).hp + f(t).hp) / 2, ds = f(s).hp - avg, dt = f(t).hp - avg
            if ds > 0 { hurt(s, ds, "") } else if ds < 0 { restore(s, -ds, "") }
            if dt > 0 { hurt(t, dt, "") } else if dt < 0 { restore(t, -dt, "") }
            say(s, "서로의 체력을 나누었다!")
        case 226:
            guard let i = nextAlive(s) else { fail(); return }
            say(s, josa(n, "은", "는") + " 바통을 넘겼다!"); switchIn(s, i, baton: true)
        case 227:
            guard f(t).lastMove != 0, f(t).encore == 0, ![227, 102, 165, 118].contains(f(t).lastMove), let lk = f(t).moves.firstIndex(of: f(t).lastMove), f(t).pp[lk] > 0 else { fail(); return }
            let k = 4 + roll(5); mod(t) { $0.encore = k; $0.encoreMove = $0.lastMove }; say(t, josa(tn, "은", "는") + " 앙코르를 받았다!")
        case 244: let st = f(t).stage; mod(s) { $0.stage = st }; say(s, josa(n, "은", "는") + " " + josa(tn, "의", "의") + " 능력 변화를 복사했다!")
        case 248, 353:
            guard sides[si(t)].future == 0 else { fail(); return }
            let m2 = moveTable[id]!, d = calc(s, t, m2, power: id == 248 ? 80 : 120, type: id == 248 ? "" : "steel", eff: id == 248 ? 1 : typeEff("steel", t, by: s), crit: false)
            sides[si(t)].future = 3; sides[si(t)].futureDmg = d; say(s, josa(n, "은", "는") + (id == 248 ? " 미래를 예지했다!" : " 파멸의 소원을 빌었다!"))
        case 262:
            hurt(s, f(s).hp, ""); boost(t, 1, -2, from: s); boost(t, 3, -2, from: s)
        case 269: guard f(t).taunt == 0 else { fail(); return }; let k = 3 + roll(3); mod(t) { $0.taunt = k }; say(t, josa(tn, "은", "는") + " 도발에 넘어갔다!")
        case 272: let a = f(t).ability; guard ![0, 25, 36].contains(a) else { fail(); return }; mod(s) { $0.abilityOver = a }; say(s, josa(n, "은", "는") + " " + josa(abilityNames[a]!, "을", "를") + " 복사했다!")
        case 273: guard sides[si(s)].wish == 0 else { fail(); return }; sides[si(s)].wish = 2; sides[si(s)].wishHP = f(s).maxHP / 2; say(s, josa(n, "은", "는") + " 희망사항을 빌었다!")
        case 277: mod(s) { $0.magicCoat = true }; say(s, josa(n, "은", "는") + " 매직코트로 몸을 감쌌다!")
        case 285:
            let a = f(s).ability, b = f(t).ability; guard ![25, 121].contains(a), ![25, 121].contains(b) else { fail(); return }
            mod(s) { $0.abilityOver = b }; mod(t) { $0.abilityOver = a }; say(s, "서로의 특성을 바꿨다!")
        case 287: guard [.poison, .toxic, .burn, .paralysis].contains(f(s).status) else { fail(); return }; setStatus(s, nil, josa(n, "은", "는") + " 몸의 상태가 좋아졌다!")
        case 288: mod(s) { $0.grudge = true }; say(s, josa(n, "은", "는") + " 원념을 품었다!")
        case 300: mudSport = true; say(s, "전기의 위력이 약해졌다!")
        case 346: waterSport = true; say(s, "불꽃의 위력이 약해졌다!")
        case 356:
            guard gravity == 0 else { fail(); return }; gravity = 5
            for x in [Side.me, .it] { mod(x) { $0.magnetRise = 0; if [19, 340].contains($0.semi) { $0.semi = 0; $0.charging = 0 } } }   // whoever's up in the air comes down
            say(s, "중력이 강해졌다!")
        case 361, 461: guard nextAlive(s) != nil else { fail(); return }; sides[si(s)].healingWish = true; sides[si(s)].lunarDance = id == 461; hurt(s, f(s).hp, "")
        case 367:
            let ks = (1...7).filter { f(s).stage[$0] < 6 }; guard !ks.isEmpty else { fail(); return }; boost(s, ks[roll(ks.count)], 2, from: s)
        case 375:
            guard let st = f(s).status, f(t).status == nil, f(t).sub == 0 else { fail(); return }
            if inflict(t, st, from: s, loud: true) { setStatus(s, nil, josa(n, "의", "의") + " 상태이상이 옮겨졌다!") }
        case 380: mod(t) { $0.abilityOver = 0 }; say(t, josa(tn, "의", "의") + " 특성이 사라졌다!")
        case 388: guard !f(t).has(54), !f(t).has(121) else { fail(); return }; mod(t) { $0.abilityOver = 15 }; say(t, josa(tn, "은", "는") + " 불면 특성이 되었다!")
        case 384, 385, 391:
            let ks = id == 384 ? [1, 3] : id == 385 ? [2, 4] : Array(1...7)
            var a = f(s).stage, b = f(t).stage; for k in ks { swap(&a[k], &b[k]) }
            mod(s) { $0.stage = a }; mod(t) { $0.stage = b }; say(s, "서로의 능력 변화를 바꿨다!")
        case 379: say(s, "그러나 실패했다!")
        case 392: guard !f(s).aquaRing else { fail(); return }; mod(s) { $0.aquaRing = true }; say(s, josa(n, "은", "는") + " 물의 베일을 둘렀다!")
        case 393: guard f(s).magnetRise == 0, gravity == 0 else { fail(); return }; mod(s) { $0.magnetRise = 5 }; say(s, josa(n, "은", "는") + " 전자력으로 떠올랐다!")
        case 432:
            boost(t, 7, -1, from: s)
            let k = si(t); sides[k].reflect = 0; sides[k].light = 0; sides[k].safeguard = 0; sides[k].mist = 0; sides[k].spikes = 0; sides[k].toxicSpikes = 0; sides[k].stealthRock = false
            if sky == .fog { sky = .clear; say(s, "안개가 걷혔다!") }
        case 271, 415: trick(s, t)
        case 278: recycle(s)
        case 433: trickRoom = trickRoom > 0 ? 0 : 5; say(s, trickRoom > 0 ? "시공이 뒤틀렸다!" : "뒤틀린 시공이 원래대로 돌아왔다!")
        default: say(s, "그러나 아무 일도 일어나지 않았다!")
        }
    }
    func nextAlive(_ s: Side) -> Int? { let fs = s == .me ? mine : theirs, cur = s == .me ? me : it; return fs.indices.first { $0 != cur && fs[$0].alive } }

}
