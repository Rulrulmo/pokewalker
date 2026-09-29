import AppKit
// The battle stage: replaying beats, poses, HUD, messages, and the side panel's model.

extension WalkerView {
    /// Where a playing turn is right now: HP as of this moment, names before this beat's damage lands.
    func beatState(_ now: Date) -> (hp: Battle, names: Battle, beat: Beat, u: Double, from: Battle)? {
        guard case .beats(_, let beats, let since, let from) = screen else { return nil }
        var u = now.timeIntervalSince(since), i = 0
        while i < beats.count - 1, u >= beats[i].length { u -= beats[i].length; i += 1 }
        var hp = from
        for (k, bt) in beats.enumerated() where k < i { hp.apply(bt) }
        let names = hp                                                                           // names before this beat lands
        hp.apply(beats[i])
        return (hp, names, beats[i], u, from)
    }
    /// What the side panel shows; nil = no battle on (panel hidden).
    func sideModel(_ now: Date) -> SideModel? {
        let b: Battle, msg: String, mode: SideModel.Mode
        switch screen {
        case .battle(let x, let sel): b = x; msg = "무엇을 할까?"; mode = .menu(battleMenu(x), sel)
        case .moves(let x, let sel):
            b = x; msg = "어떤 기술을 쓸까?"
            let f = x.mine[x.me]
            mode = .moves(f.moves.enumerated().map { k, id in let m = moveTable[id]!; return .init(name: m.name, type: m.type, power: m.power, effect: m.isStatus ? 1 : effectiveness(m.type, on: x.theirs[x.it].mon.dex), pp: f.pp[k], maxPP: m.pp) }, sel)
        case .party(let x, let sel): b = x; msg = "누구로 교체할까?"; mode = .party(x.mine.enumerated().map { card($1, out: $0 == x.me) }, sel)
        case .bagBattle(let x, let sel): b = x; msg = "무엇을 사용할까?"; mode = .items(battleItems(x).map { "\($0.name) ×\(state.count($0.name))" }, sel)
        case .beats:
            guard let s = beatState(now) else { return nil }
            b = s.hp; msg = message(s.beat, s.u, s.names); mode = .none
        default: return nil
        }
        let foe = b.theirs[b.it], mine = b.mine[b.me]
        return SideModel(foe: card(foe, out: true), foeBalls: b.trainer == nil ? [] : b.theirs.map(\.alive),
                         mine: card(mine, out: true), myBalls: b.mine.count > 1 ? b.mine.map(\.alive) : [],
                         trainer: b.trainer, message: msg, mode: mode)
    }
    func card(_ f: Fighter, out: Bool) -> SideModel.Card { .init(name: monNames[f.mon.dex], level: f.mon.level, hp: f.hp, max: f.maxHP, out: out, status: f.status?.badge) }
    func sidePick(_ k: Int) {                                                                   // a click on the side panel = selecting that row, then ●
        lastInput = Date()
        switch screen {
        case .battle(let b, _): screen = .battle(b, sel: k)
        case .moves(let b, _): screen = .moves(b, sel: k)
        case .party(let b, _): screen = .party(b, sel: k)
        case .bagBattle(let b, _): screen = .bagBattle(b, sel: k)
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
    /// What the 64x48 stage shows: one fighter at full size (the other one is never squeezed to half resolution).
    enum Pose {
        case idle                                        // their current one, breathing
        case show(Side, dx: Int, dy: Int, flash: Bool, visible: Bool)
        case ball(x: Int, y: Int, tilt: Int?, burst: Bool, stars: Bool)
        case nobody
    }
    func pose(_ b: Beat, _ u: Double, _ bt: Battle) -> Pose {
        func arc(_ a: Double, _ len: Double) -> Double { u < a || u > a + len ? 0 : sin(.pi * (u - a) / len) }   // 0 -> 1 -> 0
        let shake = Int(u * 30) % 2 == 0 ? 2 : -2, blink = Int(u * 12) % 2 == 0
        switch b {
        case .appear: return u < 0.6 ? .show(.it, dx: Int(-80 * pow(1 - u / 0.6, 2)), dy: 0, flash: false, visible: true) : .idle
        case .sendOut(let s, _): let k = pow(1 - min(1, u / 0.6), 2); return .show(s, dx: Int((s == .me ? 80 : -80) * k), dy: 0, flash: false, visible: true)
        case .use(let s, _): return .show(s, dx: Int((s == .me ? 18 : -18) * arc(0, 0.45)), dy: 0, flash: false, visible: true)   // the dash
        case .hit(let s, _, let d, _, _): return .show(s, dx: d > 0 && u < 0.4 ? shake : 0, dy: 0, flash: false, visible: d == 0 || u > 0.4 || blink)
        case .hurt(let s, _, _): return .show(s, dx: u < 0.4 ? shake : 0, dy: 0, flash: false, visible: u > 0.4 || blink)
        case .heal(let s, _, _): return .show(s, dx: 0, dy: Int(-4 * arc(0.2, 0.4)), flash: false, visible: u > 0.3 || blink)
        case .status(let s, _, _): return .show(s, dx: 0, dy: 0, flash: u < 0.4 && blink, visible: true)
        case .note(let s, _): return .show(s, dx: 0, dy: 0, flash: false, visible: bt.f(s).alive)
        case .fainted(let s): return u < 0.35 ? .show(s, dx: 0, dy: 0, flash: false, visible: blink) : .show(s, dx: 0, dy: Int(60 * min(1, (u - 0.35) / 0.6)), flash: false, visible: true)
        case .thrown(let shakes):                                                                  // arcs in, swallows it, drops, rocks
            if u < 0.55 { let k = u / 0.55; return .ball(x: Int(80 - 39 * k), y: Int(34 - 28 * k) - Int(16 * sin(.pi * k)), tilt: nil, burst: false, stars: false) }
            if u < 0.8 { return Int(u * 20) % 2 == 0 ? .show(.it, dx: 0, dy: 0, flash: true, visible: true) : .ball(x: 41, y: 6, tilt: nil, burst: false, stars: false) }
            if u < 1.25 { let k = min(1, (u - 0.8) / 0.25); return .ball(x: 41, y: Int(6 + 24 * k * k) - Int(4 * arc(1.05, 0.15)), tilt: nil, burst: false, stars: false) }
            let w = u - 1.25; return .ball(x: 41, y: 30, tilt: w < 0.6 * Double(shakes) && w.truncatingRemainder(dividingBy: 0.6) < 0.3 ? Int(w / 0.6) % 2 : nil, burst: false, stars: false)
        case .caught: return .ball(x: 41, y: 30, tilt: nil, burst: false, stars: Int(u * 8) % 2 == 0)
        case .broke: return u < 0.25 ? .ball(x: 41, y: 30, tilt: nil, burst: true, stars: false) : .show(.it, dx: 0, dy: 0, flash: u < 0.4, visible: true)
        case .gained: return .show(.me, dx: 0, dy: 0, flash: false, visible: true)
        case .fled: return .show(.it, dx: Int(-90 * min(1, u / 0.6)), dy: 0, flash: false, visible: true)
        case .ran: return .show(.me, dx: Int(90 * min(1, u / 0.6)), dy: 0, flash: false, visible: true)
        case .won: return bt.trainer == nil ? .show(.me, dx: 0, dy: 0, flash: false, visible: true) : .nobody
        case .lost: return .nobody
        }
    }
    func stage(_ fb: inout FB, _ b: Battle, _ now: Date, _ p: Pose, hud: Bool = true) {
        let t = now.timeIntervalSinceReferenceDate, f = Int(t * 2) % 2, oy = hud ? 0 : 8        // no HUD: the stage sits lower, centred
        let pad: (UInt32, UInt32) = switch state.season {                                                         // the pad they stand on, by season
        case .spring: (rgb(150, 206, 120), rgb(196, 230, 160)); case .summer: (rgb(130, 190, 96), rgb(176, 216, 136))
        case .autumn: (rgb(200, 150, 80), rgb(226, 190, 120)); case .winter: (rgb(200, 212, 228), rgb(236, 242, 250))
        }
        for y in 41..<48 { for x in 14..<82 { let ex = Double(x - 48) / 34, ey = Double(y - 44) / 3.6; if ex * ex + ey * ey < 1 { fb.set(x, y + oy, 1, ex * ex + ey * ey > 0.7 ? pad.0 : pad.1) } } }
        defer { fb.weatherFX(state.weather ?? .sunny, 0, hud ? 12 : 0, 96, hud ? 38 : 64, t) }                         // over the fighters, under the HUD
        let foe = b.theirs[b.it].mon, mine = b.mine[b.me].mon
        switch p {
        case .idle:
            fb.mon(foe, f, 16, oy)
            if foe.shiny == true { for (k, (sx, sy)) in [(6, 4), (50, 8), (28, 1), (56, 30)].enumerated() where (Int(t * 4) + k) % 3 == 0 { fb.draw(spark, 16 + sx - 6, sy + oy, sparkPal) } }
        case .show(let s, let dx, let dy, let flash, let visible): if visible { fb.mon(s == .me ? mine : foe, f, 16 + dx, dy + oy, flip: s == .me, flash: flash) }
        case .ball(let x, let y0, let tilt, let burst, let stars):
            let y = y0 + oy
            if burst { fb.draw(burstArt, x - 2, y - 2, sparkPal, scale: 2) }
            let top = usedItem == "하이퍼볼" ? rgb(44, 44, 52) : usedItem.hasSuffix("볼") && usedItem != "몬스터볼" ? rgb(60, 110, 220) : rgb(222, 52, 44)   // 슈퍼볼 & co blue, 하이퍼볼 black
            fb.draw(tilt.map { ballTilt[$0] } ?? ball, x, y, [ballPal[0], ballPal[1], top, ballPal[3]], scale: 2)
            if stars { for (sx, sy) in [(-8, -4), (16, -5), (-9, 9), (17, 8)] { fb.draw(spark, x + sx, y + sy, sparkPal) } }
        case .nobody: break
        }
        guard hud else { return }
        // HUD: theirs top-left (name, Lv, bar; a trainer's remaining balls), ours top-right; each on its own plate so the sprite's head can't muddle it
        let ft = monNames[foe.dex] + " \(foe.level)" + (b.theirs[b.it].status.map { " " + $0.badge } ?? ""), mt = "\(monNames[mine.dex]) \(mine.level)" + (b.mine[b.me].status.map { " " + $0.badge } ?? "")
        let lw = max(38, textWidth(ft, small: true) + 2) + (b.trainer != nil ? 13 : 0)
        let rw = max(38, textWidth(mt, small: true) + 2)
        for (x0, w) in [(0, lw), (96 - rw, rw)] { for y in 0..<14 { for x in x0..<min(96, x0 + w) { fb.set(x, y, 0) } } }
        fb.text(ft, 1, 0, 3, small: true)
        hpBar(&fb, 1, 9, 36, b.theirs[b.it].hp, b.theirs[b.it].maxHP)
        if b.trainer != nil { for (k, x) in b.theirs.enumerated() { fb.draw(gem, 39 + 4 * k, 9, x.alive ? ballPal : [ballPal[3], ballPal[3], ballPal[3], ballPal[3]]) } }
        fb.text(mt, 95, 0, 3, right: true, small: true)
        hpBar(&fb, 59, 9, 36, b.mine[b.me].hp, b.mine[b.me].maxHP)
        fb.fill(0, 50, 96, 1, 2)
    }
    func message(_ beat: Beat, _ u: Double, _ b: Battle) -> String {
        let it = monNames[b.theirs[b.it].mon.dex], me = monNames[b.mine[b.me].mon.dex], dots = String(repeating: ".", count: 1 + Int(u / 0.6))
        switch beat {
        case .appear:
            if b.wild.shiny == true && u < 0.9 { return "✦ 반짝! ✦" }
            return legendDex.contains(b.wild.dex) ? "전설의 " + it + " 등장!" : "야생 " + josa(it, "이", "가") + " 나타났다!"
        case .sendOut(.it, let i): return i == 0 && u < 0.7 ? (b.trainer ?? "") + "의 승부!" : "상대는 " + josa(monNames[b.theirs[i].mon.dex], "을", "를") + " 내보냈다"
        case .sendOut(.me, let i): return "가랏, " + monNames[b.mine[i].mon.dex] + "!"
        case .use(let s, let id): return b.nm(s) + "의 " + moveTable[id]!.name + "!"
        case .hit(let s, let id, _, let e, let crit):
            if crit && (e == 1 || u < 0.8) { return "급소에 맞았다!" }
            return e > 1 ? "효과가 굉장했다!" : e < 1 ? "효과가 별로인 듯하다..." : b.nm(b.other(s)) + "의 " + moveTable[id]!.name + "!"   // a plain hit keeps the move's line
        case .hurt(let s, _, let t): return t.isEmpty ? b.nm(s) + "의 체력이 줄었다!" : t
        case .heal(let s, _, let t): return t.isEmpty ? b.nm(s) + "의 체력이 회복되었다!" : t
        case .status(let s, let st, let t): return t.isEmpty ? josa(b.nm(s), "은", "는") + (st == nil ? " 건강해졌다!" : " " + st!.badge + " 상태가 되었다!") : t
        case .note(_, let t): return t
        case .fainted(let s): return josa(s == .me ? me : it, "은", "는") + " 쓰러졌다!"
        case .thrown: return u < 1.25 ? "가랏, " + usedItem + "!" : dots
        case .broke: return "앗! 나와버렸다!"
        case .caught: return "딸깍! " + josa(it, "을", "를") + " 잡았다!"
        case .gained(let e, let l, _): return l.map { me + " Lv.\($0)!" } ?? "경험치 \(e) 획득"
        case .fled: return josa(it, "은", "는") + " 도망쳤다..."
        case .ran: return "무사히 도망쳤다!"
        case .won: return b.trainer == nil ? "승리!" : (b.trainer ?? "") + "에게 이겼다!"
        case .lost: return "눈앞이 캄캄해졌다..."
        }
    }

}
