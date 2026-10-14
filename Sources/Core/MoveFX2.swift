import Foundation
// 5.0's quality pass (the user: "전반적으로 이펙트가 좀 구려보이거든?"): a second look for the moves — a prototype behind fxV2 (the shots'
// FX_V2=1), for the user to compare as GIFs before the rest is drawn. Bigger, layered pixel effects at the sprite's resolution, and a hit that
// lands: the target flashes white, the stage shakes (harder when it's super effective or a critical hit), a burst the size of the target.
// Drawn here so far: 불꽃 (a swelling stream of flames, the target engulfed), 물 (a thick beam, a splash crown), 전기 (bolts from the sky, the
// screen lit), 얼음 (a beam of crystals, ice growing over the target, then shattering), 고스트 (a wisping orb, a dark burst) — their special
// moves — and every physical contact move's impact (a big star, speed lines, dust). The rest keeps MoveFX's look.

@MainActor var fxV2 = false

/// Where things are on the stage for a move (half-dots): each side's mouth (where a move leaves it), aim (where one lands), body, its sprite.
struct FXGeo {
    var mouth: [Side: (x: Double, y: Double)], aim: [Side: (x: Double, y: Double)]
    var body: [Side: (x: Double, top: Double, feet: Double)], run: [Side: SpriteRun]
}

enum FX2 {
    /// A flame, flickering (k 0...3): a teardrop, its tones outline → white core (16 x 22).
    static func flame(_ k: Int) -> Pic {
        let t = fxTones["fire"]!, w = 16, h = 22
        var p = Pic(w: w, h: h)
        for y in 0..<h { for x in 0..<w {
            let fy = Double(y) / Double(h - 1), sway = sin(fy * 5 + Double(k) * 1.6) * 1.4 * (1 - fy)
            let half = (fy < 0.35 ? fy / 0.35 * 0.8 : 0.8 + 0.2 * sin((fy - 0.35) / 0.65 * .pi / 2)) * Double(w) / 2 * (fy > 0.92 ? (1 - fy) / 0.08 : 1)
            let d = abs(Double(x) + 0.5 - Double(w) / 2 - sway) / max(0.5, half)
            guard d < 1 else { continue }
            let core = d < 0.35 && fy > 0.45, mid = d < 0.65 && fy > 0.25
            p.px[y * w + x] = d > 0.85 ? t[1] : core ? (fy > 0.75 ? t[4] : t[3]) : mid ? t[2] : lerpRGB(t[1], t[2], 0.5)
        } }
        return p
    }
    /// A beam's piece (24 x 14) in a type's tones: a soft lozenge, white down its middle; k 0 / 1 its shimmer.
    static func beam(_ type: String, _ k: Int) -> Pic {
        let t = fxTones[type] ?? fxTones["normal"]!, w = 24, h = 14
        var p = Pic(w: w, h: h)
        for y in 0..<h { for x in 0..<w {
            let dy = abs(Double(y) + 0.5 - Double(h) / 2) / (Double(h) / 2), dx = abs(Double(x) + 0.5 - Double(w) / 2) / (Double(w) / 2)
            let r = dy + dx * dx * 0.5
            guard r < 1 else { continue }
            let shimmer = (x + k * 3) % 6 < 2
            p.px[y * w + x] = r > 0.82 ? argb(200, t[1]) : r > 0.55 ? t[2] : r > 0.25 ? (shimmer ? t[4] : t[3]) : t[4]
        } }
        return p
    }
    /// Lightning from above (26 x 84): a jagged bolt, white core and yellow edges — seed 0...5 its path.
    static func bolt(_ seed: Int) -> Pic {
        let t = fxTones["electric"]!, w = 26, h = 84
        var p = Pic(w: w, h: h), x = Double(w) / 2, pts: [(Double, Double)] = [(x, 0)]
        for k in 1...8 { x = max(4, min(Double(w) - 5, x + Double((hashXY(seed, k, 7) % 13) - 6))); pts.append((x, Double(k) * Double(h - 1) / 8)) }
        for y in 0..<h { for xx in 0..<w {
            let seg = Int(Double(y) / Double(h - 1) * 8), a = pts[min(8, seg)], b = pts[min(8, seg + 1)]
            let q = (Double(y) - a.1) / max(1, b.1 - a.1), cx = a.0 + (b.0 - a.0) * q, d = abs(Double(xx) + 0.5 - cx)
            if d < 1 { p.px[y * w + xx] = t[4] } else if d < 2.2 { p.px[y * w + xx] = t[2] } else if d < 3.4 { p.px[y * w + xx] = argb(150, t[1]) }
        } }
        return p
    }
    /// An ice crystal (size 0...3, radius 4...12): six arms with their twigs, white to blue.
    static func crystal(_ size: Int) -> Pic {
        let t = fxTones["ice"]!, r = 4 + size * 3, n = 2 * r + 3, c = Double(n) / 2
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) + 0.5 - c, dy = Double(y) + 0.5 - c, d = hypot(dx, dy), a = atan2(dy, dx)
            guard d <= Double(r) + 0.5 else { continue }
            let arm = abs(sin(3 * a)) * d, twig = d > Double(r) * 0.45 && abs(sin(3 * a + 0.9)) * (d - Double(r) * 0.45) < 0.7 && d < Double(r) * 0.8
            if arm < 0.9 || twig || d < 1.6 { p.px[y * n + x] = d < 2.5 ? t[4] : arm < 0.45 ? t[3] : t[2] }
        } }
        return p
    }
    /// A ghost's orb (28 x 28), wisps turning round it (k 0...3).
    static func ghostOrb(_ k: Int) -> Pic {
        let t = fxTones["ghost"]!, n = 28, c = 13.5
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - c, dy = Double(y) - c, d = hypot(dx, dy), a = atan2(dy, dx) + Double(k) * .pi / 6
            if d < 8 { p.px[y * n + x] = d < 3 ? t[3] : d < 6 ? t[1] : t[0]; continue }
            if d < 9.5 { p.px[y * n + x] = t[2]; continue }
            let wisp = (sin(a * 3) + 1) / 2, reach = 9.5 + wisp * 4.5
            if d < reach { p.px[y * n + x] = argb(UInt8(220 - Int((d - 9.5) * 30)), d < reach - 1.5 ? t[2] : t[1]) }
        } }
        return p
    }
    /// An impact's star (k 0...2 its size: 18, 28, 38): eight points, white middle, yellow and orange out.
    static func star(_ k: Int) -> Pic {
        let n = 18 + 10 * k, c = Double(n) / 2
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) + 0.5 - c, dy = Double(y) + 0.5 - c, d = hypot(dx, dy), a = atan2(dy, dx)
            let edge = c * (0.45 + 0.55 * pow(abs(cos(a * 4)), 6))
            guard d < edge else { continue }
            p.px[y * n + x] = d < edge * 0.45 ? rgb(255, 255, 255) : d < edge * 0.75 ? rgb(255, 236, 140) : d < edge * 0.92 ? rgb(255, 176, 64) : rgb(170, 70, 30)
        } }
        return p
    }
    /// Speed lines (40 x 18): three streaks, light at their back.
    static func speed() -> Pic {
        var p = Pic(w: 40, h: 18)
        for (y, len) in [(2, 30), (8, 38), (14, 26)] { for x in 0..<len { p.set(39 - x, y, argb(UInt8(255 - x * 200 / len), rgb(255, 255, 255))); p.set(39 - x, y + 1, argb(UInt8(160 - x * 140 / len), rgb(220, 230, 255))) } }
        return p
    }
    /// The whole stage lit (192 x 128) in a colour.
    static func flash(_ c: UInt32) -> Pic { var p = Pic(w: 192, h: 128); p.fill(0, 0, 192, 128, c); return p }
}

extension Walker {
    /// The stage's shake as a hit lands (u its time; strong: super effective or a critical hit), in dots.
    static func hitShake(_ u: Double, strong: Bool) -> Int { u < (strong ? 0.32 : 0.18) ? (Int(u * 30) % 2 == 0 ? 1 : -1) * (strong ? 2 : 1) : 0 }

    /// The second look for a move's flight (.use) and landing (.hit): true when drawn here (else MoveFX's own).
    func moveFX2(_ fb: inout FB, _ beat: Beat, _ u: Double, _ b: Battle, _ g: FXGeo) -> Bool {
        typealias P = (x: Double, y: Double)
        func put(_ key: String, _ x: Double, _ y: Double, scale: Double = 1, alpha: Double = 1, angle: Double = 0, _ make: () -> Pic) {
            guard alpha > 0.01 else { return }
            fb.pic("fx2|" + key, Int(x.rounded()), Int(y.rounded()), scale: scale, alpha: min(1, alpha), angle: angle, make)
        }
        func tint(_ s: Side, _ name: String, _ c: UInt32, _ a: Double) {                              // the sprite in a colour (a hit's white, the type's glow)
            guard let r = g.run[s], a > 0.01 else { return }
            fb.pic("fx2|mask|\(r.art)|\(r.back)|\(name)", (r.x + 16) * 2, (r.y + 32) * 2 - 40 - r.bob, alpha: min(1, a)) { fxMask(r.art, back: r.back, c, stripes: nil) }
        }
        func lerp(_ a: P, _ z: P, _ q: Double) -> P { (a.x + (z.x - a.x) * q, a.y + (z.y - a.y) * q) }
        switch beat {
        case .use(let s, let id):
            guard let m = moveTable[id] else { return false }
            let ty = fxType(b, s, m), t = b.other(s), from = g.mouth[s]!, to = g.aim[t]!
            if m.physical {                                                                        // contact or not, physical: the lunge (its pose) and speed lines behind it
                guard m.contact else { return false }
                let v = (u - 0.25) / 0.4
                if (0...1).contains(v) { put("speed", from.x - (s == .me ? 22 : -22), from.y, alpha: (1 - v) * 2, angle: s == .me ? 0 : 180) { FX2.speed() } }
                return true
            }
            guard ["fire", "water", "electric", "ice", "ghost"].contains(ty), !m.isStatus else { return false }
            let gatherV = u / 0.25
            if gatherV < 1 { put("glow|\(ty)", from.x, from.y, scale: 0.4 + gatherV * 0.6, alpha: gatherV) { LCDDeco.glow(fxTones[ty]![2]) } }
            switch ty {
            case "fire":                                                                           // flames pouring out, swelling as they go
                for i in 0..<16 {
                    let q = (u - 0.18 - Double(i) * 0.035) / 0.42; guard (0...1).contains(q) else { continue }
                    let p = lerp(from, to, q), wob = sin(q * 9 + Double(i)) * 4
                    put("flame|\((Int(u * 18) + i) % 4)", p.x, p.y + wob - 6 * q, scale: 0.55 + 0.9 * q, alpha: q > 0.88 ? (1 - q) * 8 : 1) { FX2.flame((Int(u * 18) + i) % 4) }
                }
            case "water", "ice":                                                                   // a thick beam (ice: its crystals ride it)
                let head = min(1, max(0, (u - 0.15) / 0.35)), tail = max(0, (u - 0.6) / 0.3)
                for i in 0..<12 {
                    let q = Double(i) / 11; guard q <= head, q >= tail else { continue }
                    let p = lerp(from, to, q), ang = atan2(to.y - from.y, to.x - from.x) * 180 / .pi
                    put("beam|\(ty)|\((Int(u * 20) + i) % 2)", p.x, p.y, scale: 0.8 + 0.7 * q, angle: ang) { FX2.beam(ty, (Int(u * 20) + i) % 2) }
                    if ty == "ice", i % 3 == 1 { put("crystal|1", p.x, p.y - 2, angle: u * 360) { FX2.crystal(1) } }
                    if ty == "water", i % 4 == 2 { put("fx-drop", p.x + sin(u * 20 + Double(i)) * 8, p.y - 8 - 6 * q) { fxPic(.drop, "water", 6) } }
                }
            case "electric":                                                                       // sparks round its user, then the bolts
                for i in 0..<4 where (Int(u * 20) + i) % 2 == 0 && u < 0.45 { put("fx-spark|\(i % 2)", from.x + Double([-10, 12, -6, 8][i]), from.y + Double([-8, -4, 8, 6][i])) { fxPic(.spark, "electric", i % 2) } }
                if u > 0.45 {
                    for k in 0..<3 where Int(u * 30 + Double(k)) % 3 != 2 { let seed = (Int(u * 15) + k * 3) % 6; put("bolt|\(seed)", to.x + Double([-10, 2, 13][k]), to.y - 30, scale: k == 1 ? 1.35 : 1.1) { FX2.bolt(seed) } }
                    if Int(u * 30) % 3 == 0 { put("flash|electric", 96, 64, alpha: 0.45) { FX2.flash(rgb(255, 248, 200)) } }
                }
            default:                                                                               // ghost: the orb swells, then flies with its wisps
                let k = Int(u * 12) % 4
                if u < 0.35 { put("ghost|\(k)", from.x, from.y, scale: 0.3 + u / 0.35 * 0.7) { FX2.ghostOrb(k) } }
                else {
                    let q = min(1, (u - 0.35) / 0.45), p = lerp(from, to, q)
                    for w in 1...3 { let pq = max(0, q - Double(w) * 0.06), pp = lerp(from, to, pq); put("ghost|\((k + w) % 4)", pp.x, pp.y - sin(pq * .pi) * 8, scale: 0.6, alpha: 0.5 - Double(w) * 0.12) { FX2.ghostOrb((k + w) % 4) } }
                    put("ghost|\(k)", p.x, p.y - sin(q * .pi) * 8, alpha: q < 1 ? 1 : 0) { FX2.ghostOrb(k) }
                }
            }
            return true
        case .hit(let s, let id, let d, let e, let crit):
            guard let m = moveTable[id] else { return false }
            let ty = fxType(b, b.other(s), m), c = g.aim[s]!, body = g.body[s]!, strong = e > 1 || crit
            let drawn = (m.physical && m.contact) || (["fire", "water", "electric", "ice", "ghost"].contains(ty) && !m.physical && !m.isStatus)
            guard drawn, d > 0 else { return false }
            if u < 0.08 { tint(s, "white", rgb(255, 255, 255), 0.95) }                               // the hit lands: white for two frames
            if m.physical {                                                                        // a big star, dust at its feet
                let v = u / 0.3
                if v < 1 { put("star|\(min(2, Int(v * 4)))", c.x, c.y, scale: strong ? 1.25 : 1, alpha: (1 - v) * 2.5) { FX2.star(min(2, Int(v * 4))) } }
                for i in 0..<4 { let q = (u - 0.05) / 0.4; guard (0...1).contains(q) else { continue }; put("fx-dust|\(min(2, Int(q * 3)))", body.x + Double([-18, 16, -8, 22][i]) * (0.5 + q), body.feet - 4 - 6 * q, alpha: (1 - q) * 2) { fxPic(.dust, "ground", min(2, Int(q * 3))) } }
                return true
            }
            switch ty {
            case "fire":                                                                           // engulfed: flames rising round it, an orange glow
                for i in 0..<7 {
                    let q = (u - Double(i) * 0.05) / 0.55; guard (0...1).contains(q) else { continue }
                    let x = body.x + Double([-20, 18, -8, 10, -26, 24, 0][i]), y = body.feet - 8 - q * (body.feet - body.top) * 0.75
                    put("flame|\((Int(u * 18) + i) % 4)", x, y, scale: 1.1 - 0.4 * q, alpha: (1 - q) * 2) { FX2.flame((Int(u * 18) + i) % 4) }
                }
                tint(s, "fire", rgb(255, 140, 40), u > 0.08 ? max(0, 0.55 - u) : 0)
            case "water":                                                                          // a splash crown, falling drops
                for i in 0..<10 {
                    let q = u / 0.6, a = Double(i) / 10 * .pi + .pi; guard q <= 1 else { continue }
                    put("fx-drop|\(i % 8)", c.x + cos(a) * 30 * q, c.y + sin(a) * 26 * q + 50 * q * q, alpha: (1 - q) * 2) { fxPic(.drop, "water", (i * 3) % 8) }
                }
                if u < 0.5 { put("fx-ring|\(min(4, Int(u * 10)))", body.x, body.feet - 2, scale: 1.4, alpha: 1 - u * 2) { fxPic(.ring, "water", min(4, Int(u * 10))) } }
                tint(s, "water", rgb(110, 170, 255), u > 0.08 ? max(0, 0.5 - u) : 0)
            case "electric":                                                                       // it crackles: sparks round it, flickering yellow
                for i in 0..<6 where (Int(u * 20) + i) % 2 == 0 && u < 0.7 { put("fx-spark|\(i % 2)", body.x + Double([-22, 20, -14, 24, -4, 8][i]), body.top + (body.feet - body.top) * [0.3, 0.4, 0.7, 0.65, 0.15, 0.85][i]) { fxPic(.spark, "electric", i % 2) } }
                if u > 0.08, u < 0.6, Int(u * 20) % 2 == 0 { tint(s, "para", rgb(255, 224, 48), 0.55) }
            case "ice":                                                                            // ice grows over it, then shatters
                for i in 0..<6 {
                    let a = Double(i) * .pi / 3 + 0.3, r = 18.0, grow = min(3, Int(u / 0.12))
                    if u < 0.55 { put("crystal|\(grow)", c.x + cos(a) * r * 0.8, c.y + sin(a) * r, scale: 1.3, angle: Double(i) * 15) { FX2.crystal(grow) } }
                    else { let q = (u - 0.55) / 0.4; guard q <= 1 else { continue }; put("fx-shard|\(i)", c.x + cos(a) * (r + 30 * q), c.y + sin(a) * (r + 30 * q) + 20 * q * q, alpha: (1 - q) * 2) { fxPic(.shard, "ice", i % 8) } }
                }
                tint(s, "ice", rgb(190, 235, 255), u > 0.08 && u < 0.55 ? 0.5 : 0)
            default:                                                                               // ghost: a dark burst, rings and wisps
                for i in 0..<3 { let q = (u - Double(i) * 0.08) / 0.45; guard (0...1).contains(q) else { continue }; put("fx-ring|ghost|\(min(4, Int(q * 5)))", c.x, c.y, scale: 1 + q, alpha: (1 - q) * 2) { fxPic(.ring, "ghost", min(4, Int(q * 5))) } }
                for i in 0..<6 { let q = u / 0.6, a = Double(i) * .pi / 3; guard q <= 1 else { continue }; put("ghost|\(i % 4)", c.x + cos(a) * 34 * q, c.y + sin(a) * 26 * q - 10 * q, scale: 0.45, alpha: (1 - q) * 1.5) { FX2.ghostOrb(i % 4) } }
                tint(s, "ghost", rgb(90, 50, 140), u > 0.08 ? max(0, 0.6 - u) : 0)
            }
            if strong, u < 0.2 { put("star|1", c.x, c.y, scale: 1.2, alpha: (0.2 - u) * 5) { FX2.star(1) } }   // super effective, critical: a star over the type's burst
            return true
        default: return false
        }
    }
}
