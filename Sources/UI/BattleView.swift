import AppKit
// The battle stage: replaying beats, poses, HUD, messages, and the side panel's model.

extension WalkerView {
    /// Where a playing turn is right now: HP as of this moment, names before this beat's damage lands; pending = a side whose KO'd fighter
    /// hasn't had its faint yet (it stays on the stage through the recoil, drain, U-turn … beats in between).
    func beatState(_ now: Date) -> (hp: Battle, names: Battle, beat: Beat, u: Double, from: Battle, pending: Set<Side>)? {
        guard case .beats(_, let beats, let since, let from) = screen else { return nil }
        var u = now.timeIntervalSince(since), i = 0
        while i < beats.count - 1, u >= beats[i].length { u -= beats[i].length; i += 1 }
        var hp = from
        for (k, bt) in beats.enumerated() where k < i { hp.apply(bt) }
        let names = hp                                                                           // names before this beat lands
        hp.apply(beats[i])
        var pending = Set<Side>(), gone = Set<Side>()
        for bt in beats[i...] {
            switch bt { case .sendOut(let s, _): gone.insert(s); case .fainted(let s) where !gone.contains(s): pending.insert(s); default: break }   // up to its next switch
        }
        return (hp, names, beats[i], u, from, pending)
    }
    /// What the side panel shows; nil = no battle on (panel hidden).
    func sideModel(_ now: Date) -> SideModel? {
        var b: Battle, msg: String, mode: SideModel.Mode
        var sc = screen, said: String? = nil
        if case .say(let lines, let next, _) = sc { said = lines.joined(separator: " "); sc = next }   // a fight's own message (PP가 없다 …): the battle page stays, the message in its box
        switch sc {
        case .battle(let x, let sel): b = x; msg = "무엇을 할까?"; mode = .menu(battleMenu(x), sel)
        case .moves(let x, let sel):
            b = x; msg = "어떤 기술을 쓸까?"
            let f = x.mine[x.me]
            mode = .moves(f.moves.enumerated().map { k, id in                                       // hints from the types it has now, as the damage sees them
                let m = moveTable[id]!, real = x.moveType(.me, m)
                return .init(name: m.name, type: real.type.isEmpty ? m.type : real.type, power: real.power, effect: m.isStatus ? 1 : x.typeEff(real.type, .it, by: .me), pp: f.pp[k], maxPP: m.pp)
            }, sel)
        case .party(let x, let sel): b = x; msg = x.mustReplace ? "다음은 누구를 내보낼까?" : "누구로 교체할까?"; mode = .party(x.mine.enumerated().map { card($1, out: $0 == x.me) }, sel)
        case .forfeit(let x, let yes):
            let s = state.towerStreak ?? 0
            b = x; msg = s > 0 ? "기권할까? \(s)연승이 끝난다" : "기권할까? 참가비 \(Walk.towerFee)W는 돌아오지 않는다"; mode = .ask(yes)
        case .bagBattle(let x, let sel): b = x; msg = "무엇을 사용할까?"; mode = .items(battleItems(x).map { "\($0.name) ×\(state.count($0.name))" }, sel)
        case .beats:
            guard let s = beatState(now) else { return nil }
            b = s.hp; msg = message(s.beat, s.u, s.names); mode = .none
        default: return nil
        }
        if let said { msg = said; mode = .none }
        let foe = b.theirs[b.it], mine = b.mine[b.me]
        var theirs = card(foe, out: true); theirs.types = foe.typeList; theirs.owned = (state.owned ?? []).contains(foe.mon.dex)
        return SideModel(foe: theirs, mine: card(mine, out: true), message: msg, mode: mode)
    }
    func card(_ f: Fighter, out: Bool) -> SideModel.Card { .init(name: monNames[f.mon.dex], level: f.mon.level, hp: f.hp, max: f.maxHP, out: out, status: f.status?.badge) }
    func sidePick(_ k: Int) {                                                                   // a click on the side panel = selecting that row, then ●
        lastInput = Date()
        switch screen {
        case .battle(let b, _): screen = .battle(b, sel: k)
        case .moves(let b, _): screen = .moves(b, sel: k)
        case .party(let b, _): screen = .party(b, sel: k)
        case .bagBattle(let b, _): screen = .bagBattle(b, sel: k)
        case .forfeit(let b, _): screen = .forfeit(b, yes: k == 1)
        default: return
        }
        press(1)
    }
    func battleMenu(_ b: Battle) -> [String] { b.trainer == nil ? ["공격", "볼", "도구", "도망"] : ["공격", "도구", "교체", "기권"] }
    /// Menu labels' x ranges (drawn and tapped from the same layout).
    func menuRanges(_ labels: [String]) -> [Range<Int>] {
        var x = 1, out: [Range<Int>] = []
        for n in labels { let w = textWidth(n, small: true) + 4; out.append(x..<x + w); x += w + 3 }
        return out
    }
    /// A framed 4-row bar: dark outline, green / yellow / red fill, dark grey where HP is gone. Any HP left shows at least one dot.
    func hpBar(_ fb: inout FB, _ x: Int, _ y: Int, _ w: Int, _ hp: Int, _ max: Int) {
        let inner = w - 2, f = hp <= 0 ? 0 : Swift.max(1, hp * inner / Swift.max(1, max))
        let c = hp * 5 > max * 2 ? rgb(72, 200, 90) : hp * 5 > max ? rgb(240, 200, 50) : rgb(230, 70, 60)
        for dx in 0..<w { fb.set(x + dx, y, 3, rgb(40, 44, 52)); fb.set(x + dx, y + 3, 3, rgb(40, 44, 52)) }
        for dy in 1...2 { fb.set(x, y + dy, 3, rgb(40, 44, 52)); fb.set(x + w - 1, y + dy, 3, rgb(40, 44, 52))
            for dx in 0..<inner { fb.set(x + 1 + dx, y + dy, dx < f ? 1 : 2, dx < f ? c : rgb(120, 124, 132)) } }
    }
    /// How the stage moves this moment; the fighter it doesn't name stands idle (or is gone, if fainted).
    enum Pose {
        case idle                                        // both breathing
        case show(Side, dx: Int, dy: Int, flash: Bool, visible: Bool)
        case ball(Beat, Double)                          // a ball beat and how far in: the throw, a send-out, a trainer (BallFX.swift)
    }
    func pose(_ b: Beat, _ u: Double, _ bt: Battle) -> Pose {
        if let p = movePose(b, u, bt) { return p }                                                    // a move's own way of moving (MoveFX.swift)
        func arc(_ a: Double, _ len: Double) -> Double { u < a || u > a + len ? 0 : sin(.pi * (u - a) / len) }   // 0 -> 1 -> 0
        let shake = Int(u * 30) % 2 == 0 ? 2 : -2, blink = Int(u * 12) % 2 == 0
        switch b {
        case .appear where bt.wild.shiny == true || u < 0.6: return .ball(b, u)                    // slides in from the right; a shiny one sparkles (BallFX.swift)
        case .appear: return .idle
        case .use(let s, _): let k = arc(0, 0.45); return .show(s, dx: Int((s == .me ? 10 : -10) * k), dy: s == .me ? 0 : Int(5 * k), flash: false, visible: true)   // the dash at the other (ours level: its back sprite is cut off at the bottom)
        case .hit(let s, _, let d, _, _): return .show(s, dx: d > 0 && u < 0.4 ? shake : 0, dy: 0, flash: false, visible: d == 0 || u > 0.4 || blink)
        case .hurt(let s, _, _): return .show(s, dx: u < 0.4 ? shake : 0, dy: 0, flash: false, visible: u > 0.4 || blink)
        case .heal(let s, _, _): return .show(s, dx: 0, dy: s == .me ? 0 : Int(-4 * arc(0.2, 0.4)), flash: false, visible: u > 0.3 || blink)   // ours stays down: its back is cut off
        case .status(let s, _, _): return .show(s, dx: 0, dy: 0, flash: u < 0.4 && blink, visible: true)
        case .note(let s, _), .retype(let s, _): return .show(s, dx: 0, dy: 0, flash: false, visible: true)
        case .fainted(let s): return u < 0.35 ? .show(s, dx: 0, dy: 0, flash: false, visible: blink) : .show(s, dx: 0, dy: Int(34 * min(1, (u - 0.35) / 0.6)), flash: false, visible: true)   // sinks behind its pad
        case .sendOut, .thrown, .caught, .broke: return .ball(b, u)                                // thrown, swallowing, rocking, clicking or bursting; sending out (BallFX.swift)
        case .fled: return .show(.it, dx: Int(70 * min(1, u / 0.6)), dy: 0, flash: false, visible: true)
        case .ran: return .show(.me, dx: Int(-70 * min(1, u / 0.6)), dy: 0, flash: false, visible: true)
        case .won where bt.trainer != nil: return .ball(b, u)                                       // the beaten trainer comes back
        case .gained, .won, .lost: return .idle
        }
    }
    /// The DS layout: theirs front-on at the top right, ours from behind at the bottom left, each on a pad.
    /// beat = the beat playing and how far into it (the move effects' clock); nil between turns.
    func stage(_ fb: inout FB, _ b: Battle, _ now: Date, _ p: Pose, hud: Bool = true, pending: Set<Side> = [], beat: (Beat, Double)? = nil) {
        let t = now.timeIntervalSinceReferenceDate, f = Int(t * 2) % 2
        let at: [Side: (x: Int, y: Int)] = [.it: (60, hud ? 14 : 8), .me: (8, hud ? 22 : 32)]   // where each stands (feet at y + 32, centre x + 16; sprites are 40 dots): theirs clear of the HP box, ours flush with the bottom
        fb.battleGround(at, art: state.here.art, hour: state.hour, season: state.season, weather: state.weather ?? .sunny, indoor: b.trainer != nil)   // the ground, the pads they stand on
        defer { fb.weatherFX(state.weather ?? .sunny, 0, hud ? 12 : 0, 96, hud ? 38 : 64, t) }                         // over the fighters, under the HUD
        let foe = b.theirs[b.it].mon, mine = b.mine[b.me].mon
        let up: [Side: Bool] = [.it: b.theirs[b.it].alive || pending.contains(.it), .me: b.mine[b.me].alive || pending.contains(.me)]   // fainted = gone, once its faint has played
        var shown: [Side: (dx: Int, dy: Int, flash: Bool, on: Bool)] = [.it: (0, 0, false, up[.it]!), .me: (0, 0, false, up[.me]!)]
        var shot: BallShot? = nil
        switch p {
        case .idle: break
        case .show(let s, let dx, let dy, let flash, let visible): shown[s] = (dx, dy, flash, visible && up[s]!)
        case .ball(let bt, let u):
            let s = ballShot(bt, u, b, ball: usedItem); shot = s
            shown[s.side] = (s.glow.map { $0.x / 2 } ?? 0, s.glow.map { $0.y / 2 } ?? 0, false, up[s.side]! && s.glow != nil)   // in the ball / not out yet = off the stage
        }
        for s in [Side.it, .me] where shown[s]!.on {                                                // theirs first: ours is nearer
            let v = shown[s]!, a = at[s]!
            let alive = s == .me ? b.mine[b.me].alive : b.theirs[b.it].alive                         // only a fainting one sinks behind its pad; a lunge isn't clipped
            fb.sprite(s == .me ? mine : foe, a.x + v.dx, a.y + v.dy, back: s == .me, bob: s == .me ? f - 1 : f, flash: v.flash, floor: alive ? 64 : a.y + 32)   // ours bobs down: its cut-off back never lifts
            if let g = shot?.glow, shot?.side == s { fb.glow(g) }                                     // going into / coming out of a ball
        }
        if case .idle = p, foe.shiny == true, shown[.it]!.on {                                      // sparkles around it, from its head down
            let top = at[.it]!.y + 32 - (80 - spriteTop(foe.dex)) / 2, h = at[.it]!.y + 32 - top          // a sprite pixel is half a dot
            for (k, (sx, sy)) in [(-2, 2), (26, h / 4), (12, -3), (28, h * 3 / 4)].enumerated() where (Int(t * 4) + k) % 3 == 0 { fb.draw(spark, at[.it]!.x + sx, max(0, top + sy), sparkPal) }
        }
        if let (bt, u) = beat { moveFX(&fb, bt, u, b, at) }                                         // a move's effect over the fighters
        if let s = shot { fb.ballFX(s, at) }                                                        // the ball, its light, a trainer
        if let (bt, u) = beat, bt == .appear, !legendDex.contains(b.wild.dex) { fb.entryFlash(u) }   // a wild one: two quick flashes first (a legend's screen flips instead)
        guard hud else { return }
        // HUD: theirs top-left (name, Lv, bar; a trainer's remaining balls), ours top-right; each on its own plate so the sprite's head can't muddle it
        let ft = monNames[foe.dex] + " \(foe.level)" + (b.theirs[b.it].status.map { " " + $0.badge } ?? ""), mt = "\(monNames[mine.dex]) \(mine.level)" + (b.mine[b.me].status.map { " " + $0.badge } ?? "")
        let owned = (state.owned ?? []).contains(foe.dex), lw = max(38, textWidth(ft, small: true) + 2 + (owned ? 7 : 0)) + (b.trainer != nil ? 13 : 0)
        let rw = max(38, textWidth(mt, small: true) + 2)
        for (x0, w) in [(0, lw), (96 - rw, rw)] { for y in 0..<14 { for x in x0..<min(96, x0 + w) { fb.set(x, y, 0) } } }
        fb.text(ft, 1, 0, 3, small: true)
        if owned { fb.draw(caughtMark, textWidth(ft, small: true) + 3, 2, ballPal) }                 // caught before: the HGSS ball mark
        hpBar(&fb, 1, 9, 36, b.theirs[b.it].hp, b.theirs[b.it].maxHP)
        if b.trainer != nil { for (k, x) in b.theirs.enumerated() { fb.draw(gem, 39 + 4 * k, 9, x.alive ? ballPal : [ballPal[3], ballPal[3], ballPal[3], ballPal[3]]) } }
        fb.text(mt, 95, 0, 3, right: true, small: true)
        hpBar(&fb, 59, 9, 36, b.mine[b.me].hp, b.mine[b.me].maxHP)
        fb.fill(0, 50, 96, 1, 2)
    }
    func message(_ beat: Beat, _ u: Double, _ b: Battle) -> String {
        let it = monNames[b.theirs[b.it].mon.dex], me = monNames[b.mine[b.me].mon.dex]
        switch beat {
        case .appear:
            if b.wild.shiny == true && u < 0.9 { return "✦ 반짝! ✦" }
            return legendDex.contains(b.wild.dex) ? "전설의 " + it + " 등장!" : "야생 " + josa(it, "이", "가") + " 나타났다!"
        case .sendOut(.it, let i):
            let t = b.trainer ?? "상대"                                                                // the intro's challenge, then who it sends
            return isIntro(beat, b) && u < 1.7 ? josa(t, "이", "가") + " 승부를 걸어왔다!" : josa(t, "은", "는") + " " + josa(monNames[b.theirs[i].mon.dex], "을", "를") + " 내보냈다!"
        case .sendOut(.me, let i): return "가랏, " + monNames[b.mine[i].mon.dex] + "!"
        case .use(let s, let id): return b.nm(s) + "의 " + moveTable[id]!.name + "!"
        case .hit(let s, let id, _, let e, let crit):
            if crit && (e == 1 || u < 0.8) { return "급소에 맞았다!" }
            return e > 1 ? "효과가 굉장했다!" : e < 1 ? "효과가 별로인 듯하다..." : b.nm(b.other(s)) + "의 " + moveTable[id]!.name + "!"   // a plain hit keeps the move's line
        case .hurt(let s, _, let t): return t.isEmpty ? b.nm(s) + "의 체력이 줄었다!" : t
        case .heal(let s, _, let t): return t.isEmpty ? b.nm(s) + "의 체력이 회복되었다!" : t
        case .status(let s, let st, let t): return t.isEmpty ? josa(b.nm(s), "은", "는") + (st == nil ? " 건강해졌다!" : " " + st!.badge + " 상태가 되었다!") : t
        case .note(_, let t): return t
        case .retype: return ""
        case .fainted(let s): return josa(s == .me ? me : it, "은", "는") + " 쓰러졌다!"
        case .thrown(let n): return u < 1.8 ? "가랏, " + usedItem + "!" : String(repeating: ".", count: min(n, 1 + Int((u - 1.8) / 0.75)))   // a dot a rock
        case .broke: return "앗! 나와버렸다!"
        case .caught: return "딸깍! " + josa(it, "을", "를") + " 잡았다!"
        case .gained(let e, let l, _, let k): let who = monNames[b.mine[k].mon.dex]; return l.map { who + " Lv.\($0)!" } ?? josa(who, "은", "는") + " 경험치 \(e) 획득"
        case .fled: return josa(it, "은", "는") + " 도망쳤다..."
        case .ran: return "무사히 도망쳤다!"
        case .won: return b.trainer.map { josa($0, "과", "와") + "의 승부에서 이겼다!" } ?? "승리!"
        case .lost: return "눈앞이 캄캄해졌다..."
        }
    }

}
