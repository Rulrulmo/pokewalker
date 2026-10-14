import Foundation
// The battle stage: replaying beats, poses, HUD, messages, and the side panel's model.

extension Walker {
    /// Where a playing turn is right now: HP as of this moment, names before this beat's damage lands; pending = a side whose KO'd fighter
    /// hasn't had its faint yet (it stays on the stage through the recoil, drain, U-turn … beats in between).
    func beatState(_ now: Date) -> (hp: Battle, names: Battle, beat: Beat, u: Double, from: Battle, pending: Set<Side>)? {
        guard case .beats(let end, let beats, let since, let from) = screen else { return nil }
        var u = now.timeIntervalSince(since) * battleSpeed, i = 0                                  // 배틀 속도 runs the whole show faster
        while i < beats.count - 1, u >= shownLength(beats[i]) { u -= shownLength(beats[i]); i += 1 }
        var hp = from; hp.turnNo = end.turnNo; hp.sky = end.sky; hp.skyTurns = end.skyTurns   // the weather on the stage: the battle's, from its first beat                                                    // the turn these beats belong to (the opening's is 0: only its send-out is the trainer's intro)
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
        case .battle(let x, _) where duelOn && duelWait: b = x; msg = "상대를 기다리는 중…" + (duelLeft(now).map { " (\($0)초)" } ?? ""); mode = .none   // 12 §5: our pick is in
        case .battle(let x, let sel): b = x; msg = "무엇을 할까?" + (duelOn ? duelLeft(now).map { " (\($0)초)" } ?? "" : ""); mode = .menu(battleMenu(x), sel)
        case .moves(let x, let sel):
            b = x; msg = "어떤 기술을 쓸까?"
            let f = x.mine[x.me]
            mode = .moves(f.moves.enumerated().map { k, id in                                       // hints from the types it has now, as the damage sees them
                let m = moveTable[id]!, real = x.moveType(.me, m)
                return .init(name: m.name, type: real.type.isEmpty ? m.type : real.type, power: Moves.fixedOrVariable.contains(id) ? 0 : real.power, effect: x.hint(id, real.type), pp: f.pp[k], maxPP: m.pp, status: m.isStatus, about: moveAbout(m), text: moveText(id))
            }, sel)
        case .party(let x, let sel): b = x; msg = itemFor.map { josa($0, "을", "를") + " 누구에게 쓸까?" } ?? (x.mustReplace ? "다음은 누구를 내보낼까?" : "누구로 교체할까?"); mode = .party(x.mine.enumerated().map { card($1, out: $0 == x.me) }, sel)
        case .forfeit(let x, let yes):
            let s = state.towerStreak ?? 0
            b = x; msg = duelOn ? "기권할까? 이 대전은 지게 된다" : s > 0 ? "기권할까? \(s)연승이 끝난다" : "기권할까? 참가비 \(Walk.towerFee)W는 돌아오지 않는다"; mode = .ask(yes)
        case .bagBattle(let x, let sel): b = x; msg = "무엇을 사용할까?"; mode = .items(battleItems(x).map { "\($0.name) ×\(state.count($0.name))" }, sel)
        case .beats:
            guard let s = beatState(now) else { return nil }
            b = drained(s.hp, s.names, s.beat, s.u); msg = message(s.beat, s.u, s.names); mode = .none   // the bar drains (MoveFX.swift)
        default: return nil
        }
        if let said { msg = said; mode = .none }
        let foe = b.theirs[b.it], mine = b.mine[b.me]
        var theirs = card(foe, out: true); theirs.types = foe.typeList; theirs.owned = (state.owned ?? []).contains(foe.mon.dex)
        if raidOn, foe.mon.shiny == true { theirs.name = "★" + theirs.name }                         // 4.0: a shiny boss, as the pixel HUD says it
        var m = SideModel(foe: theirs, mine: card(mine, out: true), message: msg, mode: mode)
        if case .moves = mode, b.canMega(.me) { m.mega = megaOn }                                   // 5.0: the 메가진화 button (ticked or not)
        if let s = megaGathering(now) { if s == .me { m.mine.name = monNames[mine.mon.dex] } else { m.foe.name = monNames[foe.mon.dex] } }   // its own name till the light bursts
        if raidOn { m.bars = .init(broken: b.theirs.filter { !$0.alive }.count, total: b.theirs.count, cur: CGFloat(foe.hp) / CGFloat(max(1, foe.maxHP))) }   // (the pane's strip by a prompt, the HP boxes' ×n)
        return m
    }
    func card(_ f: Fighter, out: Bool) -> SideModel.Card { .init(name: f.mega.flatMap { Forms.of(f.mon.dex, $0)?.name } ?? monNames[f.mon.dex], level: f.mon.level, hp: f.hp, max: f.maxHP, out: out, status: f.status?.badge, item: f.item) }
    func sidePick(_ k: Int) {                                                                   // a click on the side panel = selecting that row, then ●
        guard !frozen, waiting == nil else { return }
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
    func battleMenu(_ b: Battle) -> [String] { duelOn ? ["공격"] + (b.mine.count > 1 ? ["교체"] : []) + ["기권"] : raidOn ? ["공격", "도구"] + (b.mine.count > 1 ? ["교체"] : []) + ["후퇴"] : b.trainer == nil ? ["공격", "볼", "도구"] + (b.mine.count > 1 ? ["교체"] : []) + ["도망"] : ["공격", "도구", "교체", "기권"] }   // wild: 교체 once the walker has someone
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
        if fxV2 {                                                                                  // 5.0's quality pass (the prototype, with MoveFX2): HGSS's bar — round ends, a lit top row, a shaded bottom one
            let o = rgb(40, 44, 52)
            for dx in 1..<w - 1 { fb.set(x + dx, y, 3, o); fb.set(x + dx, y + 3, 3, o) }
            fb.set(x, y + 1, 3, o); fb.set(x, y + 2, 3, o); fb.set(x + w - 1, y + 1, 3, o); fb.set(x + w - 1, y + 2, 3, o)
            for dx in 0..<inner { let on = dx < f
                fb.set(x + 1 + dx, y + 1, on ? 1 : 2, on ? lerpRGB(c, rgb(255, 255, 255), 0.35) : rgb(150, 154, 160)); fb.set(x + 1 + dx, y + 2, on ? 1 : 2, on ? lerpRGB(c, rgb(0, 0, 0), 0.18) : rgb(112, 116, 124)) }
            return
        }
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
        case .mega(let s, _, _): return .show(s, dx: 0, dy: 0, flash: false, visible: true)         // 5.0: the light is stage's (megaShot)
        case .reform(let s, _, _): return .show(s, dx: 0, dy: Int(-3 * arc(0.1, 0.3)), flash: false, visible: u > 0.35 || blink)   // a form for now: a hop and a flicker
        case .fainted(let s): return u < 0.35 ? .show(s, dx: 0, dy: 0, flash: false, visible: blink) : .show(s, dx: 0, dy: Int(34 * min(1, (u - 0.35) / 0.6)), flash: false, visible: true)   // sinks behind its pad
        case .sendOut(.it, let k) where raidOn && k > 0:                                           // 4.0 (16 §8-3): a raid's next bar — it gets up again where it stood (no ball), quickly
            return .show(.it, dx: 0, dy: Int(14 * pow(1 - min(1, u / 0.35), 2)), flash: u < 0.35 && blink, visible: true)
        case .sendOut, .thrown, .caught, .broke: return .ball(b, u)                                // thrown, swallowing, rocking, clicking or bursting; sending out (BallFX.swift)
        case .fled: return .show(.it, dx: Int(70 * min(1, u / 0.6)), dy: 0, flash: false, visible: true)
        case .ran: return .show(.me, dx: Int(-70 * min(1, u / 0.6)), dy: 0, flash: false, visible: true)
        case .won where bt.trainer != nil: return .ball(b, u)                                       // the beaten trainer comes back
        case .gained where bt.theirs[bt.it].alive: return .ball(.thrown(shakes: 0), Beat.thrown(shakes: 0).length)   // a catch's EXP (1.14): the ball rests shut on its pad, the caught one stays inside
        case .gained, .won, .lost: return .idle
        }
    }
    /// 5.0: the side whose Mega Evolution is still gathering its light (before the burst it shows as it was: name, mark).
    func megaGathering(_ now: Date) -> Side? {
        guard case .beats = screen, let s = beatState(now), case .mega(let side, _, _) = s.beat, s.u < MegaFX.reveal else { return nil }
        return side
    }
    /// The DS layout: theirs front-on at the top right, ours from behind at the bottom left, each on a pad.
    /// beat = the beat playing and how far into it (the move effects' clock); nil between turns.
    func stage(_ fb: inout FB, _ b: Battle, _ now: Date, _ p: Pose, hud: Bool = true, pending: Set<Side> = [], beat: (Beat, Double)? = nil) {
        let t = now.timeIntervalSinceReferenceDate, f = Int(t * 2) % 2
        let at: [Side: (x: Int, y: Int)] = [.it: (60, hud ? 14 : 8), .me: (8, hud ? 22 : 32)]   // where each stands (feet at y + 32, centre x + 16; sprites are 40 dots): theirs clear of the HP box, ours flush with the bottom
        let sky: Weather = switch b.weatherOn { case .rain: .rain; case .hail: .snow; case .fog: .fog; default: .sunny }   // the battle's own weather (a 비바라기 shows), not the course's
        fb.battleGround(at, art: state.here.art, hour: state.hour, season: state.season, weather: sky, indoor: b.trainer != nil)   // the ground, the pads they stand on
        defer { fb.weatherFX(sky, 0, hud ? 12 : 0, 96, hud ? 38 : 64, t) }   // over the fighters, under the HUD (the tower is indoors)
        let foe = b.theirs[b.it].mon, mine = b.mine[b.me].mon                                          // the HUD: who it is (its own name, level, shine)
        let veiled: Side? = { if let (bt, u) = beat, case .mega(let s, _, _) = bt, u < MegaFX.reveal { return s }; return nil }()   // 5.0: still its old form, in its light
        func look(_ f: Fighter, _ s: Side) -> Mon { var m = f.mon; let x = f.body; if veiled != s { m.dex = x.dex; m.form = x.form }; return m }   // the sprite: 변신 shows what it became; 5.0: a Mega / battle form its own
        let foeLook = look(b.theirs[b.it], .it), mineLook = look(b.mine[b.me], .me)
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
        var mega: (side: Side, u: Double, dex: Int, form: Int)? = nil                               // 5.0: a Mega Evolution's light (MegaFX)
        if let (bt, u) = beat, case .mega(let s, let n, _) = bt { mega = (s, u, (s == .me ? b.mine[b.me] : b.theirs[b.it]).mon.dex, n) }
        for s in [Side.it, .me] where shown[s]!.on {                                                // theirs first: ours is nearer
            var v = shown[s]!; let a = at[s]!
            if let m = mega { v.dx += MegaFX.shake(m.u) }                                              // the flash shakes the stage
            if fxV2, let (bt, u) = beat, case .hit(_, _, let d, let e, let c) = bt, d > 0 { v.dx += Walker.hitShake(u, strong: e > 1 || c) }   // 5.0 (MoveFX2): a hit shakes it
            let alive = s == .me ? b.mine[b.me].alive : b.theirs[b.it].alive                         // only a fainting one sinks behind its pad; a lunge isn't clipped
            let plain = s == .it && alive && shot?.glow == nil && !v.flash && { if case .ball = p { return false }; return true }() && (mega.map { $0.side != s || $0.u > MegaFX.reveal + 0.3 } ?? true)   // out and standing: HGSS plays its own animation once (a Mega: once it shows)
            fb.sprite(s == .me ? mineLook : foeLook, a.x + v.dx, a.y + v.dy, back: s == .me, bob: s == .me ? f - 1 : f, flash: v.flash, floor: alive ? 64 : a.y + 32,
                      anim: plain ? animT("foe \(b.it)", foeLook.art, now) : nil)   // ours bobs down: its cut-off back never lifts
            if let g = shot?.glow, shot?.side == s { fb.glow(g) }                                     // going into / coming out of a ball
            if let m = mega, m.side == s, let k = MegaFX.cocoon(m.u, MegaFX.colours(m.dex, m.form)) { fb.megaTint(k.tint, k.amount, floor: hud ? 50 : 64) }   // its cocoon of light
        }
        if case .idle = p, foe.shiny == true, shown[.it]!.on {                                      // sparkles around it, from its head down
            let top = at[.it]!.y + 32 - (80 - spriteTop(foeLook.art)) / 2, h = at[.it]!.y + 32 - top          // a sprite pixel is half a dot
            for (k, (sx, sy)) in [(-2, 2), (26, h / 4), (12, -3), (28, h * 3 / 4)].enumerated() where (Int(t * 4) + k) % 3 == 0 { fb.draw(spark, at[.it]!.x + sx, max(0, top + sy), sparkPal) }
        }
        if let (bt, u) = beat { moveFX(&fb, bt, u, b, at) }                                         // a move's effect over the fighters
        if let m = mega { fb.megaFX(m.side, m.u, dex: m.dex, form: m.form, at: at, top: 80 - spriteTop((m.side == .me ? mineLook : foeLook).art, back: m.side == .me), stage: hud ? [0, 24, 192, 76] : []) }   // (the LCD's HUD and message strip kept clear)
        if raidOn, let (bt, u) = beat, Walker.isShinyReveal(bt) {                                  // 4.0 (16 §8-2): a shiny boss — light bursting from it, stars wheeling round
            var s = BallShot(); s.burst = (0, -30, u * 0.8); s.shine = u * 0.55; shot = s
        }
        if let s = shot { fb.ballFX(s, at) }                                                        // the ball, its light, a trainer
        if let (bt, u) = beat, bt == .appear, !legendDex.contains(b.wild.dex) { fb.entryFlash(u) }   // a wild one: two quick flashes first (a legend's screen flips instead)
        if b.trainer == Tower.tycoon { fb.decoFrame(gold: Tower.tycoonPrint(afterWins: state.towerStreak ?? 0) == "금") }   // 3.9 (15 §6 E): the tycoon's fight in 은 or 금
        if raidOn, let (bt, u) = beat, Walker.isShinyReveal(bt), u < 0.8, Int(u * 5) % 2 == 0 { fb.decoFrame(gold: true) }   // ... and the gold frame, twice
        guard hud else { return }
        // HUD: theirs top-left (name, Lv, bar; a trainer's remaining balls), ours top-right; each on its own plate so the sprite's head can't muddle it
        let gathering = megaGathering(now)                                                           // 5.0: a Mega's mark after its name (both names in full don't fit), once its light bursts
        let fm = b.theirs[b.it].mega != nil && gathering != .it, mm = b.mine[b.me].mega != nil && gathering != .me, owned = (state.owned ?? []).contains(foe.dex)
        let fn = (raidOn && foe.shiny == true ? "★" : "") + monNames[foe.dex], fs = b.theirs[b.it].status?.badge, ms = b.mine[b.me].status?.badge
        let marks = 2 + (owned ? 7 : 0) + (fm ? 7 : 0) + (b.trainer != nil ? 13 : 0) + 2 + (mm ? 7 : 0)
        var ft = "", mt = ""
        for (lv, st) in [(true, true), (false, true), (true, false), (false, false)] {                // 5.0: both in one row on any font — the levels go first, then the statuses
            ft = fn + (lv ? " \(foe.level)" : "") + (st ? fs.map { " " + $0 } ?? "" : ""); mt = monNames[mine.dex] + (lv ? " \(mine.level)" : "") + (st ? ms.map { " " + $0 } ?? "" : "")
            if textWidth(ft, small: true) + textWidth(mt, small: true) + marks <= 95 { break }
        }
        let lw = max(38, textWidth(ft, small: true) + 2 + (owned ? 7 : 0) + (fm ? 7 : 0)) + (b.trainer != nil ? 13 : 0)
        let rw = max(38, textWidth(mt, small: true) + 2 + (mm ? 7 : 0))
        for (x0, w) in [(0, lw), (96 - rw, rw)] { for y in 0..<14 { for x in x0..<min(96, x0 + w) { fb.set(x, y, 0) } } }
        fb.text(ft, 1, 0, 3, small: true)
        if fxV2 {                                                                                  // (the prototype: a status on a pill in its colour)
            for (st, right) in [(b.theirs[b.it].status, false), (b.mine[b.me].status, true)] { guard let st, (right ? mt : ft).hasSuffix(st.badge) else { continue }
                let bw = textWidth(st.badge, small: true), bx = right ? 95 - bw : textWidth(ft, small: true) + 1 - bw
                let c: UInt32 = switch st { case .burn: rgb(255, 150, 90); case .paralysis: rgb(250, 214, 70); case .poison, .toxic: rgb(200, 140, 230); case .sleep: rgb(170, 180, 200); case .freeze: rgb(150, 210, 245) }
                for y in 0..<9 { for x in (bx - 1)...(bx + bw) where !((x == bx - 1 || x == bx + bw) && (y == 0 || y == 8)) { fb.set(x, y, 1, c) } }   // (dots: over the plate)
            }
        }
        if owned { fb.draw(caughtMark, textWidth(ft, small: true) + 3, 2, ballPal) }                 // caught before: the HGSS ball mark
        if fm { fb.draw(megaMark, textWidth(ft, small: true) + 3 + (owned ? 7 : 0), 2, megaPal) }
        let hp = beat == nil ? b : beatState(now).map { drained($0.hp, $0.names, $0.beat, $0.u) } ?? b   // the bars drain (MoveFX.swift)
        hpBar(&fb, 1, 9, 36, hp.theirs[b.it].hp, b.theirs[b.it].maxHP)
        if raidOn { fb.text("×\(b.theirs.filter(\.alive).count)", 39, 6, 3, small: true) }            // 4.0 (16 §8-3): its bars left, this one counted (ten don't fit as gems)
        else if b.trainer != nil { for (k, x) in b.theirs.enumerated() { fb.draw(gem, 39 + 4 * k, 9, x.alive ? ballPal : [ballPal[3], ballPal[3], ballPal[3], ballPal[3]]) } }
        fb.text(mt, 95, 0, 3, right: true, small: true)
        if mm { fb.draw(megaMark, 95 - textWidth(mt, small: true) - 7, 2, megaPal) }
        hpBar(&fb, 59, 9, 36, hp.mine[b.me].hp, b.mine[b.me].maxHP)
        fb.fill(0, 50, 96, 1, 2)
    }
    /// 3.9: a wild KO's EXP for the ones not out (the walker's share it) as one line: in each run of EXP beats, the one out and any level-up keep
    /// their own lines, the rest fold into the first of them (다른 포켓몬도 …) — the end's state is the server's, so the HUD loses nothing.
    static func shown(_ beats: [Beat], from: Battle) -> [Beat] {
        var st = from, out: [Beat] = [], run: (own: [Beat], rest: [Beat]) = ([], [])
        func flush() { out += run.own + run.rest.prefix(1); run = ([], []) }
        for bt in beats {
            if case .gained(_, let l, _, let k) = bt { if l == nil && k != st.me { run.rest.append(bt) } else { run.own.append(bt) } } else { flush(); out.append(bt) }
            st.apply(bt)
        }
        flush(); return out
    }
    /// How long a beat stays on screen here: the engine's length, but a raid's next bar (nine a fight in 4.0) gets up quickly.
    func shownLength(_ bt: Beat) -> Double {
        if raidOn, case .sendOut(.it, let k) = bt, k > 0 { return 0.8 }
        return bt.length
    }
    /// 4.0 (16 §8-2): the line a shiny raid boss gets after it appears (raidShown puts it in; the stage bursts and frames it in gold).
    static let shinyRevealMark = "✦ 색이 다른 "
    static func isShinyReveal(_ bt: Beat) -> Bool { if case .note(.it, let t) = bt { return t.hasPrefix(shinyRevealMark) }; return false }
    /// A raid fight's opening as shown: a shiny boss's line after it appears (✦ 색이 다른 루기아다! ✦).
    static func raidShown(_ beats: [Beat], from: Battle) -> [Beat] {
        guard from.wild.shiny == true, let i = beats.firstIndex(of: .appear) else { return beats }
        var out = beats; out.insert(.note(.it, text: shinyRevealMark + monNames[from.wild.dex] + "다! ✦"), at: i + 1); return out
    }
    /// A beat's line; a raid's boss isn't 야생 (the engine's own lines name it so).
    func message(_ beat: Beat, _ u: Double, _ b: Battle) -> String {
        let m = beatLine(beat, u, b)
        return raidOn ? m.replacingOccurrences(of: "야생 ", with: "") : m
    }
    /// A line the LCD can't hold even small (96 dots), as two halves split at the space nearest its middle; else the line.
    static func lcdHalves(_ l: String) -> [String] {
        guard textWidth(l, small: true) > 94 else { return [l] }
        let words = l.components(separatedBy: " "), mid = l.count / 2
        guard words.count > 1 else { return [l] }
        var best = 1, at = 0, d = Int.max
        for k in 1..<words.count { at = words[..<k].joined(separator: " ").count; if abs(at - mid) < d { d = abs(at - mid); best = k } }
        return [words[..<best].joined(separator: " "), words[best...].joined(separator: " ")]
    }
    func beatLine(_ beat: Beat, _ u: Double, _ b: Battle) -> String {
        let it = monNames[b.theirs[b.it].mon.dex]
        switch beat {
        case .appear:
            if b.wild.shiny == true && u < 0.9 { return "✦ 반짝! ✦" }
            return raidOn ? "레이드 보스 " + it + " 등장!" : legendDex.contains(b.wild.dex) ? "전설의 " + it + " 등장!" : "야생 " + josa(it, "이", "가") + " 나타났다!"
        case .sendOut(.it, let k) where b.trainer == nil: return josa(it, "이", "가") + " 다시 일어섰다! (남은 줄 \(b.theirs.count - k))"   // a raid: its next bar
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
        case .fainted(let s): return josa(b.nm(s), "은", "는") + " 쓰러졌다!"
        case .thrown(let n): return u < 1.8 ? "가랏, " + usedItem + "!" : String(repeating: ".", count: min(n, 1 + Int((u - 1.8) / 0.75)))   // a dot a rock
        case .broke: return "앗! 나와버렸다!"
        case .caught: return "딸깍! " + josa(it, "을", "를") + " 잡았다!"
        case .gained(_, nil, _, let k) where k != b.me: return "다른 포켓몬도 경험치를 받았다!"                 // 3.9: the ones not out, folded (shown)
        case .gained(let e, let l, _, let k): let who = monNames[b.mine[k].mon.dex]; return l.map { who + " Lv.\($0)!" } ?? josa(who, "은", "는") + " 경험치 \(e) 획득"
        case .fled: return raidOn ? "레이드가 끝났다" : josa(b.nm(.it), "은", "는") + " 도망쳤다..."
        case .ran: return raidOn ? "후퇴했다!" : "무사히 도망쳤다!"
        case .won: return raidOn ? "\(b.theirs.count)줄을 모두 깼다! 볼 +\(RaidRules.winBalls)" : b.trainer.map { josa($0, "과", "와") + "의 승부에서 이겼다!" } ?? "승리!"
        case .lost: return "눈앞이 캄캄해졌다..."
        case .mega(_, _, let t), .reform(_, _, let t):                                                 // 5.0 (plan 18 §14.4): its lines one after the other, over the beat
            // a Mega's first line while its light gathers, the second once it shows (MegaFX.reveal); a line too long for the LCD in two halves
            let ls = t.components(separatedBy: "\n"), split = { (l: String) -> [String] in Walker.lcdHalves(l) }
            if case .mega = beat, ls.count == 2 {
                let (p, a, b) = u < MegaFX.reveal ? (split(ls[0]), 0.0, MegaFX.reveal) : (split(ls[1]), MegaFX.reveal, beat.length)
                return p[min(p.count - 1, Int((u - a) / max(0.1, b - a) * Double(p.count)))]
            }
            let ps = ls.flatMap(split); return ps[min(ps.count - 1, Int(u / max(0.1, beat.length) * Double(ps.count)))]
        }
    }

}
