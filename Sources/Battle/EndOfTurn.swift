import Foundation
// End of turn, KOs, the ball, running, bag items, the other side's choice, and what the menus ask.

extension Battle {
    // MARK: end of turn
    mutating func endOfTurn() {
        if sky != .clear, skyTurns > 0 {
            skyTurns -= 1
            if skyTurns == 0 { say(.it, ["sun": "햇살이 약해졌다!", "rain": "비가 그쳤다!", "sand": "모래바람이 가라앉았다!", "hail": "싸라기눈이 그쳤다!"]["\(sky)"] ?? ""); sky = .clear; forecast() }
        }
        for s in [Side.me, .it] where f(s).alive && !over {
            let x = f(s), n = nm(s), guardian = x.has(98)
            switch weatherOn {
            case .sand where !x.typeList.contains(where: { ["rock", "ground", "steel"].contains($0) }) && !x.has(8) && !guardian && ![91, 291].contains(x.semi): hurt(s, max(1, x.maxHP / 16), "모래바람이 " + josa(n, "을", "를") + " 덮쳤다!")   // only underground / underwater is out of it
            case .hail:
                if x.has(115) { restore(s, max(1, x.maxHP / 16), "") } else if !x.typeList.contains("ice"), !x.has(81), !guardian, ![91, 291].contains(x.semi) { hurt(s, max(1, x.maxHP / 16), "싸라기눈이 " + josa(n, "을", "를") + " 덮쳤다!") }   // 아이스바디 (always on an ice type)
            case .rain:
                if x.has(44) { restore(s, max(1, x.maxHP / 16), "") }; if x.has(87) { restore(s, max(1, x.maxHP / 8), "") }
                if x.has(93), x.status != nil { setStatus(s, nil, josa(n, "은", "는") + " 촉촉바디로 나았다!") }
            case .sun: if (x.has(87) || x.has(94)) && !guardian { hurt(s, max(1, x.maxHP / 8), "") }
            default: break
            }
            faints()
        }
        guard !over else { return }                                                                  // a KO that ended it: nothing after the last beat (the screen would read on)
        for s in [Side.me, .it] {
            let k = si(s)
            if sides[k].future > 0 { sides[k].future -= 1; if sides[k].future == 0, f(s).alive { hurt(s, sides[k].futureDmg, josa(nm(s), "은", "는") + " 미래의 공격을 받았다!") } }
            if sides[k].wish > 0 { sides[k].wish -= 1; if sides[k].wish == 0, f(s).alive { restore(s, sides[k].wishHP, "희망사항이 이루어졌다!") } }
        }
        faints()
        for s in [Side.me, .it] where f(s).alive && !over {
            let x = f(s), n = nm(s), t = other(s), guardian = x.has(98)
            if x.ingrain { restore(s, max(1, x.maxHP / 16), josa(n, "은", "는") + " 뿌리로 양분을 흡수했다!") }
            if x.aquaRing { restore(s, max(1, x.maxHP / 16), josa(n, "은", "는") + " 물의 베일로 체력을 회복했다!") }
            if x.seeded, f(t).alive, !guardian {
                let d = min(x.hp, max(1, x.maxHP / 8)); hurt(s, d, "씨뿌리기가 " + josa(n, "의", "의") + " 체력을 빼앗는다!")
                if x.has(64) { hurt(t, d, "") } else { restore(t, d, "") }
            }
            if f(s).alive, !guardian {
                switch x.status {
                case .poison?: if x.has(90) { restore(s, max(1, x.maxHP / 8), "") } else { hurt(s, max(1, x.maxHP / 8), josa(n, "은", "는") + " 독의 데미지를 입었다!") }
                case .toxic?: if x.has(90) { restore(s, max(1, x.maxHP / 8), "") } else { hurt(s, max(1, x.maxHP * x.toxic / 16), josa(n, "은", "는") + " 독의 데미지를 입었다!"); mod(s) { $0.toxic = min(15, $0.toxic + 1) } }
                case .burn?: hurt(s, max(1, x.maxHP / (x.has(85) ? 16 : 8)), josa(n, "은", "는") + " 화상 데미지를 입었다!")   // 내열 halves it
                default: break
                }
            }
            if f(s).alive, x.nightmare, x.status == .sleep, !guardian { hurt(s, max(1, x.maxHP / 4), josa(n, "은", "는") + " 악몽에 시달리고 있다!") }
            if f(s).alive, x.cursed, !guardian { hurt(s, max(1, x.maxHP / 4), josa(n, "은", "는") + " 저주를 받고 있다!") }
            if f(s).alive, x.bound > 0, f(t).alive {                                                   // (its binder KO'd: let go when the next comes out)
                let by = moveTable[x.boundBy]?.name ?? "조이기"
                mod(s) { $0.bound -= 1 }; if f(s).bound == 0 { say(s, josa(n, "은", "는") + " " + by + "에서 풀려났다!") } else if !guardian { hurt(s, max(1, x.maxHP / 16), josa(n, "은", "는") + " " + by + "의 데미지를 입었다!") }
            }
            if f(s).alive, x.has(3), x.turnsOut > 0 { boost(s, 5, 1, from: s) }
            if f(s).alive, x.has(61), f(s).status != nil, pct(30) { setStatus(s, nil, josa(n, "은", "는") + " 탈피로 나았다!") }
            if f(s).alive, x.status == .sleep, f(t).alive, f(t).has(123), !guardian { hurt(s, max(1, x.maxHP / 8), josa(n, "은", "는") + " 나이트메어에 시달리고 있다!") }
            if f(s).alive, x.yawn > 0 { mod(s) { $0.yawn -= 1 }; if f(s).yawn == 0 { inflict(s, .sleep, from: t, loud: false) } }
            if f(s).alive, x.perish > 0 { mod(s) { $0.perish -= 1 }; say(s, josa(n, "의", "의") + " 멸망 카운트가 \(f(s).perish)" + (f(s).perish == 2 ? "가" : "이") + " 되었다!"); if f(s).perish == 0 { hurt(s, f(s).hp, "") } }
            mod(s) {
                if $0.taunt > 0 { $0.taunt -= 1 }; if $0.encore > 0 { $0.encore -= 1 }; if $0.encore > 0, let k = $0.moves.firstIndex(of: $0.encoreMove), $0.pp[k] == 0 { $0.encore = 0 }; if $0.disable > 0 { $0.disable -= 1 }
                if $0.healBlock > 0 { $0.healBlock -= 1 }; if $0.magnetRise > 0 { $0.magnetRise -= 1 }; if $0.embargo > 0 { $0.embargo -= 1 }
                if $0.lockOn > 0 { $0.lockOn -= 1 }; if $0.slowStart > 0 { $0.slowStart -= 1 }; if $0.uproar > 0 { $0.uproar -= 1 }; if $0.charge > 0 { $0.charge -= 1 }
                $0.roosted = false; $0.rage = $0.lastMove == 99 && $0.rage
                if $0.lastMove != 182 && $0.lastMove != 197 && $0.lastMove != 203 { $0.protectChain = 0 }
            }
            faints()
        }
        guard !over else { return }
        for k in 0..<2 {
            let s: Side = k == 0 ? .me : .it
            for (path, text) in [(\SideState.reflect, "리플렉터"), (\SideState.light, "빛의장막"), (\SideState.safeguard, "신비의부적"), (\SideState.mist, "흰안개"), (\SideState.tailwind, "순풍"), (\SideState.luckyChant, "행운의주문")] where sides[k][keyPath: path] > 0 {
                sides[k][keyPath: path] -= 1; if sides[k][keyPath: path] == 0 { say(s, josa(text, "의", "의") + " 효과가 사라졌다!") }
            }
        }
        if trickRoom > 0 { trickRoom -= 1; if trickRoom == 0 { say(.it, "뒤틀린 시공이 원래대로 돌아왔다!") } }
        if gravity > 0 { gravity -= 1; if gravity == 0 { say(.it, "중력이 원래대로 돌아왔다!") } }
        faints()
    }

    /// KOs: EXP (and EVs) for ours, the next one out, or the end of the battle.
    mutating func faints() {
        guard !over else { return }
        if !f(.it).alive, !f(.it).down {
            mod(.it) { $0.down = true }; out.append(.fainted(.it))
            let share = faced.filter { mine[$0].alive }.sorted()                                  // Gen IV: EXP split among those that faced it, EVs in full
            if !share.isEmpty {
                let foe = f(.it).mon, e = max(1, baseExp[foe.dex] * foe.level / 7 * (trainer == nil ? 2 : 3) / 2 / share.count)
                for k in share {
                    var probe = mine[k].mon; let up = probe.gainBattleExp(e)
                    out.append(.gained(exp: e, level: up ? probe.level : nil, foe: foe.dex, to: k)); apply(out.last!)
                }
            }
            if let n = theirs.indices.first(where: { theirs[$0].alive }) { if inTurn { foeNext = n } else { switchIn(.it, n) } } else { out.append(.won); over = true; return }   // mid-turn: at its end
        }
        if !f(.me).alive, !f(.me).down {
            mod(.me) { $0.down = true }; out.append(.fainted(.me))
            if mine.contains(where: \.alive) { mustReplace = true } else { out.append(.lost); over = true }
        }
    }

    // MARK: ball, escape, items, the other side's choice
    mutating func throwBall(_ ball: Double) -> Bool {
        let t = f(.it), bonus: Double = [.sleep, .freeze].contains(t.status) ? 2 : t.status != nil ? 1.5 : 1
        let a = Double((3 * t.maxHP - 2 * t.hp) * catchRate[t.mon.dex]) * ball * bonus / Double(3 * t.maxHP)
        let b = a >= 255 ? 65536 : 1048560 / sqrt(sqrt(16711680 / max(a, 0.1)))                 // Gen III-IV shake check
        var shakes = 0
        while shakes < 4, Double(roll(65536)) < b { shakes += 1 }
        out.append(.thrown(shakes: min(shakes, 3)))
        if shakes == 4 { out.append(.caught); over = true; return true }
        out.append(.broke); return false
    }
    /// Gen IV: sure if we're faster, else by the speed ratio and how many tries; trapping moves and abilities stop it.
    mutating func canEscape() -> Bool {
        if f(.me).has(50) { return true }
        if trapped(.me) { return false }
        let a = speed(.me), b = max(1, speed(.it)); escapes += 1
        if a >= b { return true }
        return roll(256) < (Int(a * 128 / b) + 30 * escapes) % 256
    }
    mutating func useItem(_ u: ItemUse) {
        let n = nm(.me)
        switch u {
        case .heal(let h): restore(.me, h, josa(n, "의", "의") + " 체력이 회복되었다!")
        case .restore:
            if f(.me).hp < f(.me).maxHP { restore(.me, f(.me).maxHP, josa(n, "의", "의") + " 체력이 회복되었다!") }
            if f(.me).status != nil { setStatus(.me, nil, josa(n, "은", "는") + " 건강해졌다!") }
            mod(.me) { $0.confused = 0 }
        case .cure(let sts, let conf):
            if let st = f(.me).status, sts.contains(st) || (st == .toxic && sts.contains(.poison)) { setStatus(.me, nil, josa(n, "의", "의") + " " + st.badge + " 상태가 나았다!") }
            if conf, f(.me).confused > 0 { mod(.me) { $0.confused = 0 }; say(.me, josa(n, "의", "의") + " 혼란이 풀렸다!") }
        case .pp(let k, let all):
            mod(.me) { x in
                func short(_ i: Int) -> Int { (moveTable[x.moves[i]]?.pp ?? 5) - x.pp[i] }
                let idx = all ? Array(x.moves.indices) : [x.moves.indices.max { short($0) < short($1) } ?? 0]   // the move missing the most
                for i in idx { x.pp[i] = min(moveTable[x.moves[i]]?.pp ?? 5, x.pp[i] + k) }
            }
            say(.me, josa(n, "의", "의") + " PP가 회복되었다!")
        case .x(let k, let by): boost(.me, k, by, from: .me)
        case .guardSpec: sides[0].mist = 5; say(.me, "흰안개에 둘러싸였다!")
        case .direHit: mod(.me) { $0.focus = true }; say(.me, josa(n, "은", "는") + " 의욕이 넘치고 있다!")
        }
    }
    /// The other side's pick. Wild ones pick at random, as in the games; a trainer mostly takes what hits hardest on paper
    /// (and sets up or heals when it makes sense), sometimes anything.
    mutating func foeChoice() -> Int {
        let x = f(.it)
        if x.charging != 0 { return x.charging }; if x.lock > 0 { return x.lockMove }; if x.bide > 0 { return 117 }
        let ok = usable(.it)
        guard !ok.isEmpty else { return 165 }
        if trainer == nil || roll(5) == 0 { return ok[roll(ok.count)] }
        let d = f(.me)
        func score(_ id: Int) -> Double {
            let m = moveTable[id]!
            if m.isStatus {
                if m.cat == 1 { return d.status == nil && m.ailment != "none" ? 45 : 0 }
                if m.cat == 3 { return x.hp * 2 < x.maxHP ? 90 : 0 }
                if m.cat == 2 { return m.onSelf ? (x.stage[1] < 2 ? 35 : 0) : 20 }
                return 15
            }
            let p = m.power > 0 ? Double(m.power) : 60
            return p * (x.typeList.contains(m.type) ? 1.5 : 1) * typeEff(m.type, .me, by: .it) * Double(m.accuracy == 0 ? 100 : m.accuracy) / 100
        }
        return ok.max { score($0) < score($1) }!
    }
}

// MARK: - what the menus need
extension Battle {
    /// Held in place: 검은눈빛 / 조이기 / 뿌리박기, or their 그림자밟기 (not on another), 개미지옥 (on the ground), 자력 (on steel).
    func trapped(_ s: Side) -> Bool {
        let x = f(s), y = f(other(s))
        if x.trapped || x.bound > 0 || x.ingrain { return true }
        return y.alive && (y.has(23) && !x.has(23) || y.has(71) && grounded(s) || y.has(42) && x.typeList.contains("steel"))
    }
    /// Ours is mid-move (charging, rampaging, recharging, biding): 공격 (or giving up) is all the player can do.
    var locked: Bool { let x = mine[me]; return x.charging != 0 || x.lock > 0 || x.bide > 0 || x.recharge }
    /// Why ours can't switch out now (nil = it can).
    var switchBlock: String? {
        if locked { return "지금은 교체할 수 없다!" }
        return trapped(.me) ? josa(nm(.me), "은", "는") + " 돌아올 수 없다!" : nil
    }
    /// The moves that side may pick this turn: PP left, not disabled, no status move under 도발, not the same one under 트집, the encored one only.
    func usable(_ s: Side) -> [Int] {
        let x = f(s)
        return x.moves.indices.filter { i in
            let id = x.moves[i], m = moveTable[id]!
            return x.pp[i] > 0 && !(x.disable > 0 && x.disabledMove == id) && !(x.taunt > 0 && m.isStatus) && !(x.torment && id == x.lastMove) && !(x.encore > 0 && id != x.encoreMove)
        }.map { x.moves[$0] }
    }
    /// A trainer pulls back one that can't hurt ours but gets hit hard, for a teammate that resists all of ours' attacks. Not two turns running.
    mutating func foeSwitch() -> Int? {
        let x = f(.it), y = f(.me)
        guard x.alive, !trapped(.it), x.charging == 0, x.lock == 0, x.bide == 0, !x.recharge, turnNo - foeSwapTurn > 2 else { return nil }
        func eff(_ type: String, _ on: [String]) -> Double { on.reduce(1) { $0 * (typeChart[type]?[$1] ?? 1) } }
        func threat(_ on: [String]) -> Double { y.moves.compactMap { moveTable[$0] }.filter { !$0.isStatus && $0.power > 0 }.map { eff($0.type, on) }.max() ?? 1 }
        func offense(_ z: Fighter) -> Double { z.moves.compactMap { moveTable[$0] }.filter { !$0.isStatus && $0.power > 0 }.map { eff($0.type, y.typeList) }.max() ?? 0 }
        guard threat(x.typeList) >= 2, offense(x) <= 1 else { return nil }
        let safe = theirs.indices.filter { $0 != it && theirs[$0].alive && threat(theirs[$0].typeList) <= 0.5 }
        guard let i = safe.max(by: { offense(theirs[$0]) < offense(theirs[$1]) }), pct(60) else { return nil }
        foeSwapTurn = turnNo; return i
    }
    /// The ▲ / ▼ / 효과 없음 hint on our move button: the type chart as that move will meet theirs (fixed damage only minds an immunity; a status move only 전기자석파's).
    func hint(_ id: Int, _ type: String) -> Double {
        let e = typeEff(type, .it, by: .me)
        if id == 248 { return 1 }                                                                  // 미래예지: typeless in Gen IV
        if moveTable[id]!.isStatus { return id == 86 && e == 0 ? 0 : 1 }
        return Moves.fixedDamage.contains(id) ? (e == 0 ? 0 : 1) : e
    }
    /// Ours can't pick this turn (charging, rampaging, recharging, biding, encored): the move it's stuck with.
    var forced: Int? {
        let x = mine[me]
        if x.charging != 0 { return x.charging }; if x.lock > 0 { return x.lockMove }; if x.bide > 0 { return 117 }
        if x.recharge { return x.lastMove }; if x.encore > 0 { return x.encoreMove }
        return nil
    }
    /// Whether this item would do anything for ours right now (the bag hides the rest).
    func usable(_ u: ItemUse) -> Bool {
        let x = mine[me]
        guard x.embargo == 0 else { return false }                                                 // 금제: no items at all
        switch u {
        case .heal: return x.hp < x.maxHP
        case .restore: return x.hp < x.maxHP || x.status != nil || x.confused > 0
        case .cure(let sts, let conf): return x.status.map { sts.contains($0) || ($0 == .toxic && sts.contains(.poison)) } ?? false || (conf && x.confused > 0)
        case .pp: return x.moves.indices.contains { x.pp[$0] < (moveTable[x.moves[$0]]?.pp ?? 5) }
        case .x(let k, _): return x.stage[k] < 6
        case .guardSpec: return sides[0].mist == 0
        case .direHit: return !x.focus
        }
    }
}
