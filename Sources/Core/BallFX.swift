import Foundation
// The balls: thrown, swallowing the foe, rocking, clicking shut or bursting open; sending a Pokémon out; the tower's trainers.

// MARK: - pictures
/// 몬스터볼 0, 슈퍼볼 and any other 볼 1, 하이퍼볼 2.
func ballKind(_ item: String) -> Int { item == "하이퍼볼" ? 2 : item.hasSuffix("볼") && item != "몬스터볼" ? 1 : 0 }
/// Each kind's top half (1 2 3 = the middle's light / base / shade, 4 5 6 = the sides': a 슈퍼볼's red, a 하이퍼볼's yellow; h = the shine),
/// the lid's rim and its top seen open, and those colours.
private let ballTops: [(rows: [String], rim: String, lid: String, pal: [Character: UInt32])] = [
    ([".....oooo.....", "...oo1222oo...", "..o1hh22223o..", ".o1h12222233o.", ".o122oooo233o.", "o223oLWWLo333o"], "o222222222233o", "..oo122222oo..",
     ["1": rgb(255, 150, 136), "2": rgb(240, 64, 56), "3": rgb(176, 32, 40)]),
    ([".....oooo.....", "...oo1222oo...", "..o4hh22226o..", ".o54h1222256o.", ".o552oooo256o.", "o556oLWWLo566o"], "o555222222566o", "..oo522225oo..",
     ["1": rgb(112, 176, 255), "2": rgb(48, 112, 232), "3": rgb(32, 64, 168), "4": rgb(255, 128, 120), "5": rgb(232, 56, 56), "6": rgb(168, 32, 40)]),
    ([".....oooo.....", "...oo1223oo...", "..o4h122356o..", ".o5442223556o.", ".o555oooo556o.", "o556oLWWLo566o"], "o555522225556o", "..oo512235oo..",
     ["1": rgb(96, 96, 112), "2": rgb(56, 56, 68), "3": rgb(36, 36, 44), "4": rgb(255, 240, 128), "5": rgb(248, 204, 40), "6": rgb(192, 140, 24)]),
]
/// A ball at sprite resolution, 14 px across: frame 0 shut, 1 opening, 2 open (light pouring out), 3 the click (its button lit), 4 caught (gone dark).
/// The open frames are taller (the lid up): 14, 16, 18, 14, 14 rows, all on the shut ball's bottom row.
func ballPic(_ kind: Int, _ frame: Int) -> Pic {
    let t = ballTops[min(max(kind, 0), 2)], o = rgb(40, 40, 48)
    var pal: [Character: UInt32] = ["o": o, "k": rgb(72, 76, 88), "h": rgb(255, 255, 255), "W": rgb(255, 255, 255), "L": rgb(226, 226, 236), "G": rgb(176, 176, 196),
                                    "D": rgb(124, 124, 142), "Y": rgb(255, 250, 214), "y": rgb(255, 226, 120), "i": rgb(96, 40, 48)]
    pal.merge(t.pal) { $1 }
    let low = ["oWLLoLGGDoLGGo", ".oWLLooooLGGo.", ".oLLLLLLGGGDo.", "..oLLLLGGGDo..", "...ooGGDDoo...", ".....oooo....."]   // under the band
    let rows: [String] = switch frame {
    case 1: t.rows[0..<4] + [t.rim, "oiiiiiiiiiiiio", ".ooyyyyyyyyoo.", "..yYYYYYYYYy..", "oooYYYYYYYYooo", "okkkoYYYYokkko"] + low
    case 2: ["", "....oooooo....", t.lid, t.rows[3], ".oiiiiiiiiiio.", "..oooooooooo..", "...y..YY..y...", "..y.y.YY.y.y..", "...YYYYYYYY...", ".ooYYYYYYYYoo.",
             "oYYYYYYYYYYYYo", "okkkoYYYYokkko"] + low
    default: t.rows + ["okkkoWWWGokkko", "okkkoWWGGokkko"] + low
    }
    var p = Pic(rows, pal)
    if frame == 3 { for y in 5...8 { for x in 5...8 { p.set(x, y, [pal["W"]!: rgb(255, 252, 220), pal["L"]!: rgb(255, 236, 150), pal["G"]!: rgb(255, 208, 88)][p.at(x, y)] ?? rgb(232, 160, 48)) } } }
    if frame == 4 { p.px = p.px.map { $0 == 0 || $0 == o ? $0 : dim($0, 0.68) } }
    return p
}
/// The light as a ball opens: a white core, four long rays and four short, yellow edged in orange (so a grey screen still shows it).
func burstPic() -> Pic {
    let n = 41, c = 20
    func on(_ x: Int, _ y: Int) -> Bool {
        guard (0..<n).contains(x), (0..<n).contains(y) else { return false }
        let dx = Double(x - c), dy = Double(y - c), u = (dx + dy) / 2.squareRoot(), v = (dx - dy) / 2.squareRoot()
        if hypot(dx, dy) < 4.6 { return true }
        let (d, a) = (min(abs(dx), abs(dy)), max(abs(dx), abs(dy))), (d2, a2) = (min(abs(u), abs(v)), max(abs(u), abs(v)))
        return a <= 20 && d <= 0.4 + 1.6 * (1 - a / 20) || a2 <= 11 && d2 <= 0.3 + 1.2 * (1 - a2 / 11)
    }
    var p = Pic(w: n, h: n)
    for y in 0..<n { for x in 0..<n {
        let edge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { !on(x + $0.0, y + $0.1) }
        if on(x, y) { p.set(x, y, edge ? rgb(255, 214, 72) : hypot(Double(x - c), Double(y - c)) < 3 ? rgb(255, 255, 255) : rgb(255, 250, 220)) }
        else if [(1, 0), (-1, 0), (0, 1), (0, -1)].contains(where: { on(x + $0.0, y + $0.1) }) { p.set(x, y, rgb(250, 170, 50)) }
    } }
    return p
}
/// A spark flying out of the light.
func glintPic() -> Pic { Pic(["..o..", ".oyo.", "oyWyo", ".oyo.", "..o.."], ["o": rgb(248, 160, 48), "y": rgb(255, 222, 96), "W": rgb(255, 255, 255)]) }
/// A little star (the click of a catch).
func starPic() -> Pic {
    Pic(["....o....", "...oyo...", "...oyo...", ".ooyWyoo.", "oyyWWWyyo", ".ooyWyoo.", "...oyo...", "...oyo...", "....o...."],
        ["o": rgb(216, 120, 24), "y": rgb(255, 222, 64), "W": rgb(255, 255, 255)])
}

// MARK: - the beats
/// One moment of a ball beat. Positions are in half-dots (sprite pixels) from the feet of `side`'s fighter (its pad).
struct BallShot {
    /// The fighter going into or out of the ball: its feet, its scale about them, a white glow over it (0...1), or all red light.
    struct Glow { var x = 0, y = 0; var scale = 1.0, white = 0.0; var red = false; var alpha = 1.0 }
    var side = Side.it, kind = 0
    var ball: (x: Int, y: Int, frame: Int, angle: Double, alpha: Double, behind: Bool)? = nil   // its centre as if shut (see ballPic); behind = under the sprites
    var glow: Glow? = nil                                                                        // nil = that fighter isn't on the stage
    var burst: (x: Int, y: Int, t: Double)? = nil                                                // light bursting from the ball, t seconds since it opened
    var stars: (x: Int, y: Int, t: Double)? = nil                                                // t = seconds since the click
    var trainer: (name: String, dx: Int)? = nil                                                  // standing on the foe's pad, dx to the right
    var shine: Double? = nil                                                                     // a shiny one's stars wheeling round it, t seconds in
}
/// A trainer battle's first beat (the trainer's 승부 and first send-out) — not a switch back to #0 later.
func isIntro(_ beat: Beat, _ b: Battle) -> Bool { beat == .sendOut(.it, 0) && b.trainer != nil && b.turnNo == 0 }

/// A ball beat u seconds in (b = the battle as of the beat; item = the ball thrown): the throw, the swallow and the rocks; the click or the break;
/// a send-out (a 몬스터볼); a trainer coming and going.
func ballShot(_ beat: Beat, _ u: Double, _ b: Battle, ball item: String) -> BallShot {
    var s = BallShot(kind: ballKind(item))
    func span(_ a: Double, _ len: Double) -> Double { min(1, max(0, (u - a) / len)) }                  // 0 -> 1 across [a, a + len]
    func mix(_ a: Int, _ b: Int, _ k: Double) -> Int { a + Int((Double(b - a) * k).rounded()) }
    func hop(_ k: Double, _ h: Double) -> Int { Int((4 * h * k * (1 - k)).rounded()) }                  // up and down again
    let ground = (x: 0, y: -9), hit = (x: -8, y: -46), open = (x: -14, y: -56)                        // on the foe's pad; where the ball meets the foe; where it opens
    func fly(_ a: (x: Int, y: Int), _ z: (x: Int, y: Int), _ h: Double, _ turns: Double, _ k: Double) { s.ball = (mix(a.x, z.x, k), mix(a.y, z.y, k) - hop(k, h), 0, 360 * turns * k, 1, false) }
    func pop(_ o: (x: Int, y: Int), _ u0: Double) {                                                   // opens at o: a flash, and the fighter grows out white, then in its colours
        let t = u - u0, g = 1 - pow(1 - span(u0, 0.4), 2)
        if t < 0.3 { s.ball = (o.x, o.y - Int(6 * t / 0.3), t < 0.05 ? 1 : 2, 0, 1 - span(u0 + 0.15, 0.15), true) }
        if t < 0.45 { s.burst = (o.x, o.y - 4, t) }
        s.glow = .init(x: mix(o.x, 0, g), y: mix(o.y + 7, 0, g), scale: 0.15 + 0.85 * g, white: 1 - span(u0 + 0.1, 0.4))
    }
    switch beat {
    case .thrown(let n):
        s.glow = .init()
        if u < 0.45 { fly((-170, 12), hit, 40, 2, u / 0.45) }                                          // from behind us, over, spinning
        else if u < 0.55 { let k = 1 - pow(1 - span(0.45, 0.1), 2); s.ball = (mix(hit.x, open.x, k), mix(hit.y, open.y, k), 0, -40 * k, 1, false) }   // knocked back off it
        else if u < 1.1 {                                                                              // open: the foe flashes white, turns to red light, is pulled in
            s.ball = (open.x, open.y, u < 0.6 || u > 1.0 ? 1 : 2, 0, 1, false)
            if u < 1 { s.burst = (open.x, open.y - 4, u - 0.55) }
            if u < 0.64 { s.glow!.white = 1 } else if u < 0.98 { let k = span(0.64, 0.34); s.glow = .init(x: mix(0, open.x, k), y: mix(0, open.y + 4, k), scale: max(0.04, 1 - k), red: true, alpha: 1 - 0.4 * k) } else { s.glow = nil }
        } else {
            s.glow = nil
            let bottom = (x: ground.x, y: ground.y + 7), t = u - 1.36
            let up = u < 1.36 ? 0 : t < 0.16 ? hop(t / 0.16, 9) : t < 0.26 ? hop((t - 0.16) / 0.1, 3) : 0   // two bounces
            let w = u - 1.8, j = Int(max(0, w) / 0.75), r = max(0, w) - 0.75 * Double(j)
            let a = w > 0 && j < n && r < 0.42 ? -28 * sin(2 * .pi * r / 0.42) : 0                  // a rock: over to the left, to the right, upright; then a pause
            if u < 1.36 { let k = span(1.14, 0.22); s.ball = (mix(open.x, ground.x, k), mix(open.y, ground.y, k * k), 0, 0, 1, false) }   // shut, it drops
            else { s.ball = (bottom.x + Int((7 * sin(a * .pi / 180) + 3 * a * .pi / 180).rounded()), bottom.y - Int((7 * cos(a * .pi / 180)).rounded()) - up, 0, a, 1, false) }   // rocking on its bottom, rolling a little
        }
    case .caught: s.ball = (ground.x, ground.y, u < 0.15 ? 3 : 4, 0, 1, false); if u > 0.1 { s.stars = (ground.x, ground.y - 6, u - 0.1) }
    case .broke:
        if u < 0.1 { s.ball = (ground.x, ground.y - hop(u / 0.1, 3), 0, 0, 1, false) } else { pop(ground, 0.1) }   // a jolt, then it bursts open
    case .appear:
        s.glow = .init(x: 2 * Int(60 * pow(1 - span(0, 0.6), 2)))                                     // slides in from the right
        if b.wild.shiny == true, u > 0.6 { s.shine = u - 0.6 }
    case .sendOut(let side, let i):
        s.side = side; s.kind = 0
        let intro = isIntro(beat, b), u0 = intro ? 1.6 : 0
        if intro, let t = b.trainer, u < 2 { s.trainer = (t, u < 0.45 ? Int(64 * pow(1 - u / 0.45, 2)) : Int(130 * pow(span(1.55, 0.4), 2))) }   // in; its 승부; off to the right as it throws
        let o = side == .it ? (x: 0, y: -30) : (x: 4, y: -40), from = side == .me ? (x: -80, y: -10) : intro ? (x: 12, y: -50) : (x: 70, y: -90)
        if u >= u0 + 0.3 { pop(o, u0 + 0.3) } else if u >= u0 { fly(from, o, side == .me ? 26 : 16, 1, (u - u0) / 0.3) }
        if (side == .me ? b.mine : b.theirs)[i].mon.shiny == true, u > u0 + 0.7 { s.shine = u - u0 - 0.7 }
    case .won: s.trainer = b.trainer.map { ($0, Int(64 * pow(1 - span(0, 0.45), 2))) }                  // the beaten trainer comes back
    default: break
    }
    return s
}

extension FB {
    /// A ball beat's moment over the stage (see BallShot); at = where each side stands (feet at y + 32, centre x + 16, in dots).
    mutating func ballFX(_ s: BallShot, _ at: [Side: (x: Int, y: Int)]) {
        let a = at[s.side]!, fx = (a.x + 16) * 2, fy = (a.y + 32) * 2
        if let (name, dx) = s.trainer { let f = trainerFrame(name); pic("trainer " + f, fx + dx, fy - 40, behind: true) { framePic(f) } }
        if let b = s.ball { pic("ball \(s.kind) \(b.frame)", fx + b.x, fy + b.y - [0, 1, 2, 0, 0][b.frame], alpha: b.alpha, angle: b.angle, behind: b.behind) { ballPic(s.kind, b.frame) } }
        if let (x, y, t) = s.burst {                                                                       // the flash growing and fading; sparks flying out
            if t < 0.3 { let k = t / 0.3; pic("ball burst", fx + x, fy + y, scale: 0.35 + 0.9 * k, alpha: 1 - k * k) { burstPic() } }
            if t < 0.45 {
                let k = 1 - pow(1 - t / 0.45, 2), al = 1 - max(0, t - 0.2) / 0.25
                for i in 0..<8 { let a = (Double(i) + 0.5) * .pi / 4, r = 4 + 30 * k * (1 + 0.2 * sin(Double(i) * 2.3)); pic("ball glint", fx + x + Int(r * cos(a)), fy + y + Int(r * sin(a)), alpha: al) { glintPic() } }
            }
        }
        if let (x, y, t) = s.stars {                                                                       // three pop out and up, then drift down and fade
            let k = 1 - pow(1 - min(1, t / 0.4), 2), fall = Int(max(0, t - 0.4) * 16), fade = 1 - min(1, max(0, t - 0.7) / 0.4)
            for (dx, dy) in [(-18.0, -9.0), (0, -16), (18, -9)] { pic("ball star", fx + x + Int(dx * k), fy + y + Int(dy * k) + fall, alpha: fade) { starPic() } }
        }
        if let t = s.shine, t < 0.7 {                                                                     // six stars wheeling in round its middle, fading
            for i in 0..<6 { let a = (Double(i) / 3 + t * 0.8) * .pi, r = 30 - 14 * t; pic("ball star", fx + Int(r * cos(a)), fy - 30 + Int(0.8 * r * sin(a)), alpha: 1 - max(0, t - 0.45) / 0.25) { starPic() } }
        }
    }
    /// The tower's hall (its lobby on the LCD): a tiled floor, the three who go (their box icons, hopping in turn), the next trainer still a silhouette.
    mutating func towerHall(_ party: [Int], _ t: Double) {
        for y in 50..<64 { for x in 0..<96 { set(x, y, y == 50 ? 2 : 1, y == 50 ? rgb(150, 158, 178) : y == 56 || (x + (y > 56 ? 8 : 0)) % 16 == 0 ? rgb(190, 196, 214) : rgb(216, 220, 232)) } }
        pic("tower rival", 146, 76, behind: true) { var p = framePic("acetrainer-gen4"); p.px = p.px.map { $0 == 0 ? 0 : rgb(56, 60, 78) }; return p }
        text("?", 71, 31, 0)
        for (k, dex) in party.prefix(3).enumerated() {
            pic("tower icon \(dex)", 26 + 34 * k, 100 - ((Int(t * 3) + k) % 3 == 0 ? 2 : 0)) { var p = Pic(w: 32, h: 32); for i in 0..<1024 { p.set(31 - i % 32, i / 32, iconPixel(dex, i % 32, i / 32)) }; return p }   // turned to face it
        }
    }
    /// A battle's start: the screen flashes white twice in its first 0.3 s.
    mutating func entryFlash(_ u: Double) {
        guard u < 0.1 || (0.17..<0.27).contains(u) else { return }
        pic("entry flash", 96, 64, alpha: 0.9) { var p = Pic(w: 192, h: 128); p.fill(0, 0, 192, 128, rgb(255, 255, 255)); return p }
    }
    /// The sprite just added, going into or out of a ball (see BallShot.Glow): a white copy over it for the glow.
    mutating func glow(_ g: BallShot.Glow) {
        guard var r = sprites.popLast() else { return }
        r.scale = g.scale; r.alpha = g.alpha
        if g.red { r.tint = rgb(255, 104, 128); r.tintShade = 2 }
        sprites.append(r)
        if g.white > 0 { r.tint = rgb(255, 255, 255); r.tintShade = 1; r.alpha = g.white * g.alpha; sprites.append(r) }
    }
}

/// Self-test checks for this file (run by selftest()).
@MainActor func ballChecks() -> [(Bool, String)] {
    var r = Seeded(s: 9)
    var tb = Battle(party: [Mon.wild(25, level: 20, &r)], trainer: "레인저 보라", foes: [Mon.wild(1, level: 20, &r), Mon.wild(4, level: 20, &r)])
    let opening = tb.begin(weather: nil, &r); var later = tb; later.turnNo = 1
    let wild = Battle(wild: Mon.wild(16, level: 5, &r), companion: Mon.wild(25, level: 20, &r))
    let rests = (0...3).allSatisfy { n in let b = ballShot(.thrown(shakes: n), Beat.thrown(shakes: n).length - 0.01, wild, ball: "슈퍼볼").ball; return b?.angle == 0 && b?.x == 0 && b?.y == -9 }
    let out = [Beat.sendOut(.me, 0), .sendOut(.it, 1), .sendOut(.it, 0)].allSatisfy { bt in let s = ballShot(bt, bt.length - 0.01, tb, ball: ""); return s.ball == nil && abs((s.glow?.scale ?? 0) - 1) < 1e-9 && s.glow?.white == 0 && s.trainer == nil }
    let intro = ballShot(.sendOut(.it, 0), 1.0, tb, ball: ""), back = ballShot(.sendOut(.it, 0), 1.0, later, ball: "")
    return [
        (["몬스터볼", "슈퍼볼", "네트볼", "하이퍼볼", "상처약"].map(ballKind) == [0, 1, 1, 2, 0], "balls: 몬스터볼, 슈퍼볼 (and any other 볼), 하이퍼볼"),
        ((0...4).map { ballPic($0 % 3, $0).w } == [14, 14, 14, 14, 14] && (0...4).map { ballPic(0, $0).h } == [14, 16, 18, 14, 14], "ball frames share the shut ball's width and bottom row"),
        (rests && ballShot(.thrown(shakes: 1), 1.9, wild, ball: "").ball?.angle != 0 && ballShot(.thrown(shakes: 1), 1.2, wild, ball: "").glow == nil, "a thrown ball swallows the foe, rocks, and ends upright on its pad"),
        (out, "a send-out ends with the fighter standing in its colours, the ball gone"),
        (opening.first.map { isIntro($0, tb) } == true && !isIntro(.sendOut(.it, 0), later) && intro.trainer?.dx == 0 && intro.glow == nil && back.trainer == nil,
         "a trainer's intro plays only for its first send-out, not a later switch back to #0"),
    ]
}
