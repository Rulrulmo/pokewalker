import Foundation
// 5.0's quality pass (the user: "전반적으로 이펙트가 좀 구려보이거든?", then "전부다 포함해서 진행"): the moves' second look. Bigger, layered pixel
// effects at the sprite's resolution, each type its own way to fly and to land (FX2.style: 18 types × special — a stream, a beam, bolts, an
// orb, rings, a volley — and a landing — engulfed, a splash, crackling, frozen and shattered, …), a contact move's lunge and impact with its
// type's touch, some moves their own (FX2.signature: 하이퍼빔, 솔라빔, 번개, 불대문자, 눈보라, 사이코키네시스, 용성군, …), and a hit that lands —
// a hit stop (the white target, the burst held a moment), then the stage shakes (harder for super effective and critical hits). Status moves
// and a non-contact physical move's flight keep MoveFX's look; fxV2 off (the shots' FX_V2=0): all MoveFX's.

@MainActor var fxV2 = true

/// Where things are on the stage for a move (half-dots): each side's mouth (where a move leaves it), aim (where one lands), body, its sprite.
struct FXGeo {
    var mouth: [Side: (x: Double, y: Double)], aim: [Side: (x: Double, y: Double)]
    var body: [Side: (x: Double, top: Double, feet: Double)], run: [Side: SpriteRun]
}

enum FX2 {
    /// A flame, flickering (k 0...3): a teardrop, its tones outline → white core (16 x 22); a dragon's in its tones.
    static func flame(_ k: Int, _ type: String = "fire") -> Pic {
        let t = fxTones[type] ?? fxTones["fire"]!, w = 16, h = 22
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
    /// A soft orb (k 0 / 1 its shimmer, 22 x 22) in a type's tones: a rim, its colour, a lit side, a white heart.
    static func orb(_ type: String, _ k: Int) -> Pic {
        let t = fxTones[type] ?? fxTones["normal"]!, n = 22, c = 10.5
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - c, dy = Double(y) - c, d = hypot(dx, dy)
            guard d < 10.5 else { continue }
            let lit = hypot(dx + 3, dy + 3) < 4.5 + Double(k)
            p.px[y * n + x] = d > 9.3 ? t[0] : d > 7.5 ? t[1] : lit ? t[4] : d < 4 ? t[3] : t[2]
        } }
        return p
    }
    /// A thick ring (size k 0...3) in a type's tones.
    static func ring(_ type: String, _ k: Int) -> Pic {
        let t = fxTones[type] ?? fxTones["normal"]!, r = 6.0 + Double(k) * 4, n = Int(2 * r + 6), c = Double(n) / 2
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let d = hypot(Double(x) + 0.5 - c, Double(y) + 0.5 - c)
            if abs(d - r) < 1.0 { p.px[y * n + x] = t[3] } else if abs(d - r) < 2.2 { p.px[y * n + x] = d < r ? t[2] : t[1] }
        } }
        return p
    }
    /// A leaf blade (heading h 0...7, 14 x 14): green, its vein lit.
    static func leaf(_ h: Int) -> Pic {
        let t = fxTones["grass"]!, n = 15, c = 7.0, a = Double(h) * .pi / 4, ca = cos(a), sa = sin(a)
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - c, dy = Double(y) - c, u = dx * ca + dy * sa, v = -dx * sa + dy * ca
            let half = 3.2 * (1 - pow(u / 7, 2))
            guard abs(u) < 7, abs(v) < half else { continue }
            p.px[y * n + x] = abs(v) < 0.6 ? t[3] : abs(v) > half - 1 ? t[0] : v < 0 ? t[2] : t[1]
        } }
        return p
    }
    /// A wind crescent (heading h 0...7, 20 x 20): white, its edge blue.
    static func crescent(_ h: Int) -> Pic {
        let n = 21, c = 10.0, a = Double(h) * .pi / 4
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - c, dy = Double(y) - c, d1 = hypot(dx, dy), d2 = hypot(dx + 3.5 * cos(a), dy + 3.5 * sin(a))
            if d1 < 9.5, d2 > 8.5 { p.px[y * n + x] = d1 > 8.3 || d2 < 9.6 ? rgb(150, 190, 240) : rgb(250, 252, 255) }
        } }
        return p
    }
    /// A blob of sludge (k 0 / 1, 14 x 12): purple, lit at its top, a bubble.
    static func blob(_ k: Int) -> Pic {
        let t = fxTones["poison"]!
        return Pic([".....oooo.....", "...ooMMMMoo...", "..oMMLLMMMMo..", ".oMMLWLMMMMMo.", ".oMMMLMMMMMMo.", "oMMMMMMMMMDMMo", "oMMMMMMMMDDMMo", "oMDMMMMMDDMMMo",
                    ".oDDMMMMMMMDo.", "..oDDDDDDDDo..", k == 0 ? "...oo.oooo...." : "....oooo.oo...", ".............."],
                   ["o": t[0], "M": t[2], "L": t[3], "W": t[4], "D": t[1]])
    }
    /// A twinkle (k 0 / 1, 13 x 13): four points and a glow, in a type's tones (a fairy's pink, a spark's).
    static func twinkle(_ type: String, _ k: Int) -> Pic {
        let t = fxTones[type] ?? fxTones["fairy"]!, n = 13, c = 6.0
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = abs(Double(x) - c), dy = abs(Double(y) - c), arm = (dx < 1 && dy < 6.5 - Double(k)) || (dy < 1 && dx < 6.5 - Double(k)), core = dx + dy < 3
            if core { p.px[y * n + x] = t[4] } else if arm { p.px[y * n + x] = dx + dy < 4 ? t[3] : t[2] } else if hypot(dx, dy) < 4 { p.px[y * n + x] = argb(110, t[2]) }
        } }
        return p
    }
    /// A rock pillar (k 0...2 its height: 14, 22, 30; 14 wide): grey-brown, lit on its left, a sharp top.
    static func pillar(_ k: Int, _ type: String = "rock") -> Pic {
        let t = fxTones[type] ?? fxTones["rock"]!, w = 14, h = 14 + 8 * k
        var p = Pic(w: w, h: h)
        for y in 0..<h { for x in 0..<w {
            let top = 6 - abs(Double(x) - 6.5) * 0.9
            guard Double(y) >= top else { continue }
            p.px[y * w + x] = x == 0 || x == w - 1 || Double(y) < top + 1 ? t[0] : x < 4 ? t[3] : x > 10 ? t[1] : t[2]
        } }
        return p
    }
    /// A meteor (14 x 14 head, its trail drawn apart): an orange-white core, a purple rim.
    static let meteor = Pic(["....oooo....", "..ooYYYYoo..", ".oYYWWWWYYo.", ".oYWWWWWWYo.", "oYWWWWWWWWYo", "oYWWWWWWWWYo", "oYYWWWWWWYYo", ".oYYWWWWYYo.", ".ooYYYYYYoo.", "...oooooo..."],
                            ["o": rgb(120, 60, 180), "Y": rgb(255, 170, 80), "W": rgb(255, 240, 200)])
    /// A moon (26 x 26): pale pink, its craters.
    static let moon: Pic = {
        var p = Pic(w: 26, h: 26)
        for y in 0..<26 { for x in 0..<26 {
            let d = hypot(Double(x) - 12.5, Double(y) - 12.5)
            guard d < 12.5 else { continue }
            let crater = hypot(Double(x) - 8, Double(y) - 9) < 3 || hypot(Double(x) - 16, Double(y) - 16) < 2.2 || hypot(Double(x) - 17, Double(y) - 7) < 1.5
            p.px[y * 26 + x] = d > 11.3 ? rgb(214, 140, 190) : crater ? rgb(246, 200, 226) : rgb(255, 232, 244)
        } }
        return p
    }()
    /// A wave (48 x 30): its curling crest and foam, bands of blue under it, fading at its back.
    static let wave: Pic = {
        var p = Pic(w: 48, h: 30)
        for y in 0..<30 { for x in 0..<48 {
            let fx = Double(x) / 47, crest = 4 + 16 * pow(1 - fx, 1.6) + 2 * sin(Double(x) / 3)
            guard Double(y) >= crest else { continue }
            let depth = Double(y) - crest, a = UInt8(min(255, 120 + fx * 135))
            let col: UInt32 = depth < 2 ? rgb(252, 254, 255) : depth < 4 ? ((x + y) % 3 == 0 ? rgb(252, 254, 255) : rgb(170, 220, 255)) : (Int(depth) / 3 + x / 6) % 2 == 0 ? rgb(70, 140, 236) : rgb(50, 116, 214)
            p.px[y * 48 + x] = argb(a, col)
        } }
        return p
    }()
    /// A ray of light (8 x 60) from its foot: white to clear.
    static func ray(_ c: UInt32) -> Pic {
        var p = Pic(w: 8, h: 60)
        for y in 0..<60 { for x in 0..<8 { let a = (1 - Double(y) / 60) * (1 - abs(Double(x) - 3.5) / 4); if a > 0.05 { p.px[y * 8 + x] = argb(UInt8(min(255, a * 280)), lerpRGB(c, rgb(255, 255, 255), 0.4)) } } }
        return p
    }
    /// The whole stage lit (192 x 128) in a colour.
    static func flash(_ c: UInt32) -> Pic { var p = Pic(w: 192, h: 128); p.fill(0, 0, 192, 128, c); return p }
}

/// How a type's special move flies and how a move of it lands (FX2.style).
enum FXFlight { case stream, beam, bolts, orb, rings, volley, erupt }
enum FXLand { case engulf, splash, crackle, freeze, dark, leaves, psychic, sludge, erupt, wind, sparkle, metal, impact, rocks, buzz }
extension FX2 {
    static let style: [String: (fly: FXFlight, land: FXLand)] = [
        "normal": (.beam, .impact), "fire": (.stream, .engulf), "water": (.beam, .splash), "electric": (.bolts, .crackle), "grass": (.volley, .leaves),
        "ice": (.beam, .freeze), "fighting": (.orb, .impact), "poison": (.volley, .sludge), "ground": (.erupt, .erupt), "flying": (.volley, .wind),
        "psychic": (.rings, .psychic), "bug": (.rings, .buzz), "rock": (.volley, .rocks), "ghost": (.orb, .dark), "dragon": (.stream, .engulf),
        "dark": (.rings, .dark), "steel": (.beam, .metal), "fairy": (.volley, .sparkle),
    ]
    /// The moves with a look of their own (their ids): 하이퍼빔, 솔라빔, 번개, 불대문자, 눈보라, 사이코키네시스, 용성군, 스톤에지, 인파이트, 신속,
    /// 매지컬샤인, 문포스, 사이코브레이크, 근원의파동, 단애의칼, 브레이브버드, 플레어드라이브, 파도타기, 지진, 용의파동, 악의파동, 러스터캐논.
    static let stop = 0.06                                                 // the hit stop: a hit's first moment held (the target white, the burst still)
    static let signature: Set<Int> = [63, 76, 87, 126, 59, 94, 434, 444, 370, 245, 605, 585, 540, 618, 619, 413, 394, 57, 89, 406, 399, 430]
}

extension Walker {
    /// The stage's shake as a hit lands (u its time; strong: super effective or a critical hit), in dots — after the hit stop.
    static func hitShake(_ u: Double, strong: Bool) -> Int { u >= FX2.stop && u < (strong ? 0.36 : 0.22) ? (Int(u * 30) % 2 == 0 ? 1 : -1) * (strong ? 2 : 1) : 0 }

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
        func heading(_ a: P, _ z: P) -> Int { (Int((atan2(z.y - a.y, z.x - a.x) / (.pi / 4)).rounded()) + 8) % 8 }
        func flash(_ c: UInt32, _ a: Double) { put("flash|\(c)", 96, 64, alpha: a) { FX2.flash(c) } }

        // MARK: flights
        func stream(_ ty: String, _ a: P, _ z: P, n: Int = 16, big: Double = 1) {                    // flames pouring out, swelling as they go
            for i in 0..<n {
                let q = (u - 0.18 - Double(i) * 0.035) / 0.42; guard (0...1).contains(q) else { continue }
                let p = lerp(a, z, q), wob = sin(q * 9 + Double(i)) * 4, k = (Int(u * 18) + i) % 4
                put("flame|\(ty)|\(k)", p.x, p.y + wob - 6 * q, scale: (0.55 + 0.9 * q) * big, alpha: q > 0.88 ? (1 - q) * 8 : 1) { FX2.flame(k, ty) }
            }
        }
        func beam(_ ty: String, _ a: P, _ z: P, thick: Double = 1) {                                 // a beam growing out to its end, then thinning away
            let head = min(1, max(0, (u - 0.15) / 0.35)), tail = max(0, (u - 0.6) / 0.3), ang = atan2(z.y - a.y, z.x - a.x) * 180 / .pi
            for i in 0..<12 {
                let q = Double(i) / 11; guard q <= head, q >= tail else { continue }
                let p = lerp(a, z, q), k = (Int(u * 20) + i) % 2
                put("beam|\(ty)|\(k)", p.x, p.y, scale: (0.8 + 0.7 * q) * thick, angle: ang) { FX2.beam(ty, k) }
                if ty == "ice", i % 3 == 1 { put("crystal|1", p.x, p.y - 2, angle: u * 360) { FX2.crystal(1) } }
                if ty == "water", i % 4 == 2 { put("fx-drop", p.x + sin(u * 20 + Double(i)) * 8, p.y - 8 - 6 * q) { fxPic(.drop, "water", 6) } }
                if ty == "steel", i % 4 == 1 { put("twinkle|steel|\(k)", p.x, p.y - 7) { FX2.twinkle("steel", k) } }
            }
        }
        func bolts(_ z: P, many: Int = 3, big: Double = 1) {                                          // bolts from the sky, the stage lit
            for k in 0..<many where Int(u * 30 + Double(k)) % 3 != 2 { let seed = (Int(u * 15) + k * 3) % 6; put("bolt|\(seed)", z.x + Double([-10, 2, 13, -20, 22][k % 5]), z.y - 30 * big, scale: (k == 1 ? 1.35 : 1.1) * big) { FX2.bolt(seed) } }
            if Int(u * 30) % 3 == 0 { flash(rgb(255, 248, 200), 0.45) }
        }
        func orb(_ ty: String, _ a: P, _ z: P, big: Double = 1) {                                     // it swells at its user, then flies with its trail
            let k = Int(u * 12) % 4
            if ty == "ghost" {
                if u < 0.35 { put("ghost|\(k)", a.x, a.y, scale: (0.3 + u / 0.35 * 0.7) * big) { FX2.ghostOrb(k) }; return }
                let q = min(1, (u - 0.35) / 0.45), p = lerp(a, z, q)
                for w in 1...3 { let pq = max(0, q - Double(w) * 0.06), pp = lerp(a, z, pq); put("ghost|\((k + w) % 4)", pp.x, pp.y - sin(pq * .pi) * 8, scale: 0.6 * big, alpha: 0.5 - Double(w) * 0.12) { FX2.ghostOrb((k + w) % 4) } }
                if q < 1 { put("ghost|\(k)", p.x, p.y - sin(q * .pi) * 8, scale: big) { FX2.ghostOrb(k) } }
                return
            }
            if u < 0.35 { put("orb|\(ty)|\(k % 2)", a.x, a.y, scale: (0.3 + u / 0.35 * 0.8) * big) { FX2.orb(ty, k % 2) }; return }
            let q = min(1, (u - 0.35) / 0.45), p = lerp(a, z, q)
            for w in 1...3 { let pq = max(0, q - Double(w) * 0.07), pp = lerp(a, z, pq); put("orb|\(ty)|\((k + w) % 2)", pp.x, pp.y - sin(pq * .pi) * 6, scale: (0.9 - Double(w) * 0.18) * big, alpha: 0.6 - Double(w) * 0.15) { FX2.orb(ty, (k + w) % 2) } }
            if q < 1 { put("orb|\(ty)|\(k % 2)", p.x, p.y - sin(q * .pi) * 6, scale: 1.1 * big) { FX2.orb(ty, k % 2) } }
        }
        func rings(_ ty: String, _ a: P, _ z: P, n: Int = 5) {                                         // rings flying out, growing
            for i in 0..<n {
                let q = (u - 0.25 - Double(i) * 0.1) / 0.4; guard (0...1).contains(q) else { continue }
                let p = lerp(a, z, q); put("ring|\(ty)|\(min(3, Int(q * 4)))", p.x, p.y, alpha: q > 0.85 ? (1 - q) * 6 : 1) { FX2.ring(ty, min(3, Int(q * 4))) }
            }
        }
        func volley(_ ty: String, _ a: P, _ z: P, n: Int = 7) {                                        // pieces flying in arcs: leaves, crescents, sludge, rocks, twinkles
            for i in 0..<n {
                let q = (u - 0.25 - Double(i) * 0.06) / 0.4; guard (0...1).contains(q) else { continue }
                let arc = Double([-1, 1, -0.5, 0.6, 0, -0.8, 0.9][i % 7]) * 22 * sin(q * .pi), p = lerp(a, z, q), h = heading(a, z)
                let x = p.x, y = p.y + arc, alpha = q > 0.9 ? (1 - q) * 10 : 1
                switch ty {
                case "grass": put("leaf|\((h + Int(u * 16) + i) % 8)", x, y, alpha: alpha) { FX2.leaf((h + Int(u * 16) + i) % 8) }
                case "flying": put("crescent|\(h)", x, y, scale: 0.8, alpha: alpha) { FX2.crescent(h) }
                case "poison": put("blob|\(i % 2)", x, y, alpha: alpha) { FX2.blob(i % 2) }
                case "rock": put("fx-rock|\((Int(u * 10) + i) % 4)", x, y, alpha: alpha) { fxPic(.rock, "rock", (Int(u * 10) + i) % 4) }
                default: put("twinkle|\(ty)|\(i % 2)", x, y, alpha: alpha) { FX2.twinkle(ty, i % 2) }
                }
            }
        }
        func gatherIn(_ ty: String, _ a: P, _ v: Double) {                                             // power drawn in to its user
            guard (0...1).contains(v) else { return }
            put("glow|\(ty)", a.x, a.y, scale: 0.4 + v * 0.6, alpha: v) { LCDDeco.glow(fxTones[ty]![2]) }
            for i in 0..<6 { let an = Double(i) * .pi / 3 + 0.4, d = 22 * (1 - v); put("twinkle|\(ty)|\(i % 2)", a.x + cos(an) * d, a.y + sin(an) * d, alpha: v * 2) { FX2.twinkle(ty, i % 2) } }
        }

        // MARK: landings (uh: after the hit stop)
        func land(_ kind: FXLand, _ ty: String, _ s: Side, _ uh: Double, small: Bool = false) {
            let c = g.aim[s]!, body = g.body[s]!, sc = small ? 0.6 : 1.0, h = body.feet - body.top
            switch kind {
            case .engulf:
                for i in 0..<(small ? 4 : 7) {
                    let q = (uh - Double(i) * 0.05) / 0.55; guard (0...1).contains(q) else { continue }
                    let x = body.x + Double([-20, 18, -8, 10, -26, 24, 0][i]) * sc, y = body.feet - 8 - q * h * 0.75, k = (Int(uh * 18) + i) % 4
                    put("flame|\(ty)|\(k)", x, y, scale: (1.1 - 0.4 * q) * sc, alpha: (1 - q) * 2) { FX2.flame(k, ty) }
                }
                tint(s, ty, fxTones[ty]![2], uh > 0.03 ? max(0, 0.5 - uh) * sc : 0)
            case .splash:
                for i in 0..<(small ? 6 : 10) {
                    let q = uh / 0.6, a = Double(i) / 10 * .pi + .pi; guard q <= 1 else { continue }
                    put("fx-drop|\(i % 8)", c.x + cos(a) * 30 * q * sc, c.y + sin(a) * 26 * q * sc + 50 * q * q, alpha: (1 - q) * 2) { fxPic(.drop, "water", (i * 3) % 8) }
                }
                if uh < 0.5 { put("ring|water|\(min(3, Int(uh * 8)))", body.x, body.feet - 2, scale: 1.2 * sc, alpha: 1 - uh * 2) { FX2.ring("water", min(3, Int(uh * 8))) } }
                tint(s, "water", rgb(110, 170, 255), uh > 0.03 ? max(0, 0.45 - uh) * sc : 0)
            case .crackle:
                for i in 0..<6 where (Int(uh * 20) + i) % 2 == 0 && uh < 0.7 { put("fx-spark|\(i % 2)", body.x + Double([-22, 20, -14, 24, -4, 8][i]) * sc, body.top + h * [0.3, 0.4, 0.7, 0.65, 0.15, 0.85][i]) { fxPic(.spark, "electric", i % 2) } }
                if uh > 0.03, uh < 0.6, Int(uh * 20) % 2 == 0 { tint(s, "para", rgb(255, 224, 48), 0.55 * sc) }
            case .freeze:
                for i in 0..<6 {
                    let a = Double(i) * .pi / 3 + 0.3, r = 18.0 * sc, grow = min(3, Int(uh / 0.12))
                    if uh < 0.5 { put("crystal|\(grow)", c.x + cos(a) * r * 0.8, c.y + sin(a) * r, scale: 1.3 * sc, angle: Double(i) * 15) { FX2.crystal(grow) } }
                    else { let q = (uh - 0.5) / 0.4; guard q <= 1 else { continue }; put("fx-shard|\(i)", c.x + cos(a) * (r + 30 * q), c.y + sin(a) * (r + 30 * q) + 20 * q * q, alpha: (1 - q) * 2) { fxPic(.shard, "ice", i % 8) } }
                }
                tint(s, "ice", rgb(190, 235, 255), uh > 0.03 && uh < 0.5 ? 0.5 * sc : 0)
            case .dark:
                for i in 0..<3 { let q = (uh - Double(i) * 0.08) / 0.45; guard (0...1).contains(q) else { continue }; put("ring|\(ty)|\(min(3, Int(q * 4)))", c.x, c.y, scale: (1 + q) * sc, alpha: (1 - q) * 2) { FX2.ring(ty, min(3, Int(q * 4))) } }
                for i in 0..<(small ? 3 : 6) { let q = uh / 0.6, a = Double(i) * .pi / 3; guard q <= 1 else { continue }; put("ghost|\(i % 4)", c.x + cos(a) * 34 * q * sc, c.y + sin(a) * 26 * q * sc - 10 * q, scale: 0.45, alpha: (1 - q) * 1.5) { FX2.ghostOrb(i % 4) } }
                tint(s, ty, ty == "dark" ? rgb(60, 40, 70) : rgb(90, 50, 140), uh > 0.03 ? max(0, 0.6 - uh) * sc : 0)
            case .leaves:
                for i in 0..<(small ? 5 : 9) { let q = uh / 0.6, a = Double(i) * 2 * .pi / 9 + 0.3; guard q <= 1 else { continue }; let k = (i * 3 + Int(uh * 16)) % 8; put("leaf|\(k)", c.x + cos(a) * 32 * q * sc, c.y + sin(a) * 24 * q * sc + 14 * q * q, alpha: (1 - q) * 2) { FX2.leaf(k) } }
                for i in 0..<4 where uh > 0.15 { let q = (uh - 0.15) / 0.5; guard q <= 1 else { continue }; put("twinkle|grass|\(i % 2)", body.x + Double([-14, 12, -4, 18][i]), body.feet - 6 - q * h * 0.8, alpha: (1 - q) * 2) { FX2.twinkle("grass", i % 2) } }
            case .psychic:
                for i in 0..<4 { let q = (uh - Double(i) * 0.1) / 0.5; guard (0...1).contains(q) else { continue }; put("ring|psychic|\(min(3, Int(q * 4)))", c.x, c.y, scale: (0.8 + q * 1.2) * sc, alpha: (1 - q) * 1.6) { FX2.ring("psychic", min(3, Int(q * 4))) } }
                if uh > 0.03, uh < 0.6 { tint(s, "psy", rgb(255, 120, 200), 0.35 + 0.2 * sin(uh * 30)) }
            case .sludge:
                for i in 0..<(small ? 4 : 7) { let q = uh / 0.55, a = Double(i) / 7 * .pi + .pi; guard q <= 1 else { continue }; put("blob|\(i % 2)", c.x + cos(a) * 26 * q * sc, c.y + sin(a) * 20 * q * sc + 36 * q * q, alpha: (1 - q) * 2) { FX2.blob(i % 2) } }
                for i in 0..<5 { let q = (uh - Double(i) * 0.08) / 0.5; guard (0...1).contains(q) else { continue }; put("fx-bubble|\(i % 3)", body.x + Double([-16, 14, -6, 20, 2][i]), body.feet - 6 - q * h * 0.9, alpha: (1 - q) * 2) { fxPic(.bubble, "poison", i % 3) } }
                tint(s, "poison", rgb(170, 80, 220), uh > 0.03 ? max(0, 0.5 - uh) * sc : 0)
            case .erupt:
                for i in 0..<(small ? 3 : 5) {
                    let q = (uh - Double(i) * 0.06) / 0.35; guard q > 0 else { continue }
                    let x = body.x + Double([-22, 18, -6, 28, -32][i]) * sc, rise = min(1, q) * 1.0, fade = q > 1.6 ? 0 : q > 1 ? 1 - (q - 1) / 0.6 : 1
                    put("pillar|ground|\(min(2, i % 3))", x, body.feet - 8 - 10 * rise, alpha: fade) { FX2.pillar(min(2, i % 3), "ground") }
                }
                for i in 0..<4 { let q = uh / 0.6; guard q <= 1 else { continue }; put("fx-dust|\(min(2, Int(q * 3)))", body.x + Double([-26, 22, -10, 30][i]) * (0.5 + q), body.feet - 4 - 8 * q, alpha: (1 - q) * 2) { fxPic(.dust, "ground", min(2, Int(q * 3))) } }
            case .wind:
                for i in 0..<(small ? 2 : 4) { let q = (uh - Double(i) * 0.07) / 0.3; guard (0...1).contains(q) else { continue }; let hh = [1, 3, 7, 5][i]; put("crescent|\(hh)", c.x + Double([-18, 18, -8, 10][i]) * (1 - q), c.y + Double([-14, -10, 12, 14][i]) * (1 - q), scale: 1.1 * sc, alpha: (1 - q) * 2) { FX2.crescent(hh) } }
                for i in 0..<5 { let q = uh / 0.7, a = Double(i) * 1.3; guard q <= 1 else { continue }; put("fx-gust|\(i % 8)", c.x + cos(a) * 30 * q, c.y + sin(a) * 18 * q + 24 * q * q, alpha: (1 - q) * 2) { fxPic(.gust, "flying", i % 8) } }
            case .sparkle:
                for i in 0..<(small ? 5 : 9) { let q = uh / 0.6, a = Double(i) * 2 * .pi / 9; guard q <= 1 else { continue }; put("twinkle|fairy|\(i % 2)", c.x + cos(a) * 34 * q * sc, c.y + sin(a) * 26 * q * sc, scale: 1.2 - 0.6 * q, alpha: (1 - q) * 2) { FX2.twinkle("fairy", i % 2) } }
                if uh > 0.03, uh < 0.5 { tint(s, "fairy", rgb(255, 170, 220), 0.4 * sc) }
            case .metal:
                put("star|1", c.x, c.y, scale: (uh < 0.2 ? 1 : 1 - (uh - 0.2)) * sc, alpha: (0.6 - uh) * 3) { FX2.star(1) }
                for i in 0..<4 { let q = uh / 0.4, a = Double(i) * .pi / 2 + .pi / 4; guard q <= 1 else { continue }; put("twinkle|steel|\(i % 2)", c.x + cos(a) * 24 * q * sc, c.y + sin(a) * 24 * q * sc, scale: 1.3, alpha: (1 - q) * 2) { FX2.twinkle("steel", i % 2) } }
                if uh > 0.03, uh < 0.3 { tint(s, "steel", rgb(220, 226, 240), 0.5 * sc) }
            case .impact:
                let v = uh / 0.3
                if v < 1 { put("star|\(min(2, Int(v * 4)))", c.x, c.y, scale: (small ? 0.8 : 1.15) * (ty == "fighting" ? 1.1 : 1), alpha: (1 - v) * 2.5) { FX2.star(min(2, Int(v * 4))) } }
                for i in 0..<2 { let q = (uh - Double(i) * 0.08) / 0.35; guard (0...1).contains(q) else { continue }; put("ring|\(ty == "fighting" ? "fighting" : "normal")|\(min(3, Int(q * 4)))", c.x, c.y, scale: 1 + q, alpha: (1 - q) * 1.5) { FX2.ring(ty == "fighting" ? "fighting" : "normal", min(3, Int(q * 4))) } }
            case .rocks:
                for i in 0..<(small ? 4 : 7) { let q = uh / 0.6, a = Double(i) * 2 * .pi / 7 + 0.4; guard q <= 1 else { continue }; let k = 4 + (i % 4); put("fx-rock|\(k)", c.x + cos(a) * 30 * q * sc, c.y + sin(a) * 22 * q * sc + 30 * q * q, alpha: (1 - q) * 2) { fxPic(.rock, "rock", k) } }
                for i in 0..<3 { let q = uh / 0.5; guard q <= 1 else { continue }; put("fx-dust|\(min(2, Int(q * 3)))", body.x + Double([-18, 14, 26][i]), body.feet - 4 - 6 * q, alpha: (1 - q) * 2) { fxPic(.dust, "ground", min(2, Int(q * 3))) } }
            case .buzz:
                for i in 0..<3 { let q = (uh - Double(i) * 0.1) / 0.45; guard (0...1).contains(q) else { continue }; put("ring|bug|\(min(3, Int(q * 4)))", c.x, c.y, scale: (0.8 + q) * sc, alpha: (1 - q) * 1.8) { FX2.ring("bug", min(3, Int(q * 4))) } }
                for i in 0..<5 { let q = uh / 0.6, a = Double(i) * 1.25 + uh * 8; guard q <= 1 else { continue }; put("twinkle|bug|\(i % 2)", c.x + cos(a) * 20 * sc, c.y + sin(a) * 16 * sc, alpha: (1 - q) * 2) { FX2.twinkle("bug", i % 2) } }
            }
        }

        switch beat {
        case .use(let s, let id):
            guard let m = moveTable[id] else { return false }
            let ty = fxType(b, s, m), t = b.other(s), next = upcoming(beat)
            let miss: Bool = { if case .note(_, let x)? = next { return fxMissed(x) }; return false }()
            let only: Bool = { if m.charges, case .note(let w, _)? = next, w == s { return true }; return false }()   // turn 1 of a two-turn move: it only gathers
            let from = g.mouth[s]!, aimed = g.aim[t]!, to: P = miss ? (aimed.x + (t == .it ? 34 : -34), aimed.y - 24) : aimed   // a miss flies past
            if m.isStatus { return false }
            if only { gatherIn(ty, from, u / 0.6); return true }
            if m.physical {                                                                        // the lunge (its pose), speed lines behind it; a non-contact one: MoveFX's flight
                guard m.contact else { return false }
                let v = (u - 0.25) / 0.4
                if id == 245 || id == 413 || id == 394 {                                            // 신속 · 브레이브버드 · 플레어드라이브: an aura, longer lines
                    let aura = id == 245 ? "normal" : id == 413 ? "flying" : "fire"
                    put("glow|\(aura)", from.x, from.y, scale: 1.2, alpha: min(1, u * 3) * 0.9) { LCDDeco.glow(fxTones[aura]![2]) }
                    if id != 245 { for i in 0..<5 { let k = (Int(u * 18) + i) % 4; put("flame|\(id == 413 ? "water" : "fire")|\(k)", from.x + Double([-14, 10, -4, 16, 2][i]), from.y + Double([-6, 4, 10, -10, 0][i]), scale: 0.8) { FX2.flame(k, id == 413 ? "water" : "fire") } } }
                }
                if (0...1).contains(v) { for k in 0..<(FX2.signature.contains(id) ? 3 : 1) { put("speed", from.x - (s == .me ? 22 : -22) - Double(k * 12) * (s == .me ? 1 : -1), from.y + Double(k * 6 - 6), alpha: (1 - v) * 2, angle: s == .me ? 0 : 180) { FX2.speed() } } }
                return true
            }
            if FX2.signature.contains(id) {                                                         // its own look
                switch id {
                case 63: gatherIn("normal", from, u / 0.3); if u > 0.3 { beam("normal", from, to, thick: 2); if u > 0.5 { flash(rgb(255, 230, 180), 0.3) } }   // 하이퍼빔
                case 76: gatherIn("grass", from, u / 0.3); if u > 0.3 { beam("grass", from, to, thick: 1.8) }                                                  // 솔라빔
                case 87: if u > 0.35 { put("bolt|\(Int(u * 15) % 6)", to.x, to.y - 40, scale: 2.4) { FX2.bolt(Int(u * 15) % 6) }; if Int(u * 30) % 2 == 0 { flash(rgb(255, 255, 255), 0.6) } }   // 번개
                case 126: stream("fire", from, to, n: 12)                                                                                                      // 불대문자 (its 大 on landing)
                case 59:                                                                                                                                    // 눈보라: the stage in a storm
                    for i in 0..<16 { let x = (Double(i * 23) + u * 260).truncatingRemainder(dividingBy: 220) - 14, y = Double((i * 37) % 120) + sin(u * 8 + Double(i)) * 6; put("crystal|\(i % 2)", x, y, angle: u * 400 + Double(i) * 20) { FX2.crystal(i % 2) } }
                    flash(rgb(220, 240, 255), 0.25)
                case 94, 540: gatherIn("psychic", from, u / 0.3); if u > 0.3 { rings("psychic", from, to, n: 6) }; if id == 540, u > 0.5 { flash(rgb(255, 180, 230), 0.2) }   // 사이코키네시스 · 사이코브레이크
                case 434:                                                                                                                                   // 용성군: meteors from the sky
                    gatherIn("dragon", from, u / 0.25)
                    for i in 0..<5 { let q = (u - 0.2 - Double(i) * 0.09) / 0.38; guard (0...1).contains(q) else { continue }; let st: P = (to.x - 110 + Double(i) * 14, -24), en: P = (to.x + Double([-16, 12, -4, 20, -24][i]), to.y + Double([0, -6, 8, 4, -2][i])), p = lerp(st, en, q)
                        for w in 1...4 { let pp = lerp(st, en, max(0, q - Double(w) * 0.06)); put("orb|dragon|\(w % 2)", pp.x, pp.y, scale: 1.0 - Double(w) * 0.17, alpha: 0.75 - Double(w) * 0.12) { FX2.orb("dragon", w % 2) } }
                        put("meteor", p.x, p.y, scale: 1.7) { FX2.meteor } }
                    if u > 0.55 { flash(rgb(255, 200, 150), 0.18) }
                case 444, 619: break                                                                                                                         // 스톤에지 · 단애의칼: all on landing
                case 605:                                                                                                                                   // 매지컬샤인: rays from its user over the stage
                    for i in 0..<8 { let a = Double(i) * 45 + u * 30; put("ray|fairy", from.x, from.y, scale: 2.2, alpha: min(1, u * 3) * 0.8, angle: a) { FX2.ray(rgb(255, 190, 230)) } }
                    if u > 0.4 { flash(rgb(255, 240, 250), 0.35 * (1 - u)) }
                case 585:                                                                                                                                   // 문포스: the moon over its user, its light at the foe
                    put("glow|fairy", 96, 28, scale: 1.6, alpha: min(1, u * 3) * 0.8) { LCDDeco.glow(rgb(255, 190, 230)) }
                    put("moon", 96, 28, scale: 1.2 + min(0.6, u), alpha: min(1, u * 4)) { FX2.moon }
                    if u > 0.45 { beam("fairy", (96, 34), to, thick: 1.5) }
                case 618:                                                                                                                                   // 근원의파동: rings of the sea, a beam
                    rings("water", from, to, n: 6); if u > 0.4 { beam("water", from, to, thick: 1.6) }
                case 57:                                                                                                                                    // 파도타기: a wave across the stage
                    let q = min(1, max(0, (u - 0.15) / 0.65)), x = (s == .me ? -30 + 250 * q : 222 - 250 * q)
                    put("wave", x, 100, scale: 1.8, alpha: q < 0.95 ? 1 : (1 - q) * 20) { FX2.wave }
                case 406: gatherIn("dragon", from, u / 0.3); if u > 0.3 { beam("dragon", from, to, thick: 1.3); stream("dragon", from, to, n: 8) }               // 용의파동
                case 399: rings("dark", from, to, n: 7); flash(rgb(40, 20, 50), 0.15)                                                                          // 악의파동
                case 430: gatherIn("steel", from, u / 0.3); if u > 0.3 { beam("steel", from, to, thick: 1.6) }                                                  // 러스터캐논
                default: break
                }
                return true
            }
            guard let st = FX2.style[ty] else { return false }
            if st.fly != .erupt && st.fly != .bolts { gatherIn(ty, from, u / 0.25) }
            switch st.fly {
            case .stream: stream(ty, from, to)
            case .beam: beam(ty, from, to)
            case .bolts: if u > 0.45 { bolts(to) } else { for i in 0..<4 where (Int(u * 20) + i) % 2 == 0 { put("fx-spark|\(i % 2)", from.x + Double([-10, 12, -6, 8][i]), from.y + Double([-8, -4, 8, 6][i])) { fxPic(.spark, "electric", i % 2) } } }
            case .orb: orb(ty, from, to)
            case .rings: rings(ty, from, to)
            case .volley: volley(ty, from, to)
            case .erupt: if u > 0.4 { for i in 0..<5 where (Int(u * 20) + i) % 3 == 0 { put("fx-dust|\(i % 3)", to.x + Double([-20, 16, -6, 24, -30][i]), g.body[t]!.feet - 2) { fxPic(.dust, "ground", i % 3) } } }   // the ground under it stirs
            }
            return true
        case .hit(let s, let id, let d, let e, let crit):
            guard let m = moveTable[id], d > 0, !m.isStatus else { return false }
            let ty = fxType(b, b.other(s), m), c = g.aim[s]!, body = g.body[s]!, strong = e > 1 || crit
            let uh = max(0, u - FX2.stop)                                                          // the hit stop: the burst held its first frames
            if u < FX2.stop + 0.04 { tint(s, "white", rgb(255, 255, 255), 0.95) }                   // the hit lands: white
            let kind = FX2.style[ty]?.land ?? .impact
            if m.physical {                                                                        // a contact move: the big star, its type's touch; any physical one: dust
                if m.contact || ty == "normal" || ty == "fighting" { land(.impact, ty, s, uh, small: false) }
                if ty != "normal", ty != "fighting" { land(kind, ty, s, uh, small: m.contact) }
                for i in 0..<4 { let q = (uh - 0.03) / 0.4; guard (0...1).contains(q) else { continue }; put("fx-dust|\(min(2, Int(q * 3)))", body.x + Double([-18, 16, -8, 22][i]) * (0.5 + q), body.feet - 4 - 6 * q, alpha: (1 - q) * 2) { fxPic(.dust, "ground", min(2, Int(q * 3))) } }
                if id == 370 { for k in 0..<5 { let q = (u - Double(k) * 0.1) / 0.18; guard (0...1).contains(q) else { continue }; put("star|\(min(2, Int(q * 3)))", c.x + Double([-14, 12, -4, 16, 0][k]), c.y + Double([-10, 6, 12, -6, 0][k]), scale: 0.8, alpha: (1 - q) * 2) { FX2.star(min(2, Int(q * 3))) } } }   // 인파이트: blow after blow
                if id == 89 { flash(rgb(200, 170, 120), max(0, 0.25 - uh)) }                         // 지진
                if id == 444 {                                                                        // 스톤에지: stone rising round it
                    for i in 0..<6 { let q = (uh - Double(i) * 0.05) / 0.25; guard q > 0 else { continue }; let x = c.x + Double([-26, 22, -10, 30, -36, 8][i]), fade = q > 2.2 ? 0 : q > 1.6 ? 1 - (q - 1.6) / 0.6 : 1
                        put("pillar|rock|\(i % 3)", x, body.feet - 10 - 12 * min(1, q), scale: 1.3, alpha: fade) { FX2.pillar(i % 3, "rock") } }
                }
            } else {
                switch id {
                case 126:                                                                          // 불대문자: its 大 of flames
                    for (k, o) in [(0.0, -22.0), (0, -8), (0, 6), (-14, -2), (14, -2), (-12, 16), (12, 16)].enumerated() { let q = (uh - Double(k) * 0.03) / 0.6; guard (0...1).contains(q) else { continue }; put("flame|fire|\((Int(uh * 18) + k) % 4)", c.x + o.0, c.y + o.1, scale: 1.4, alpha: (1 - q) * 2) { FX2.flame((Int(uh * 18) + k) % 4, "fire") } }
                    tint(s, "fire", fxTones["fire"]![2], max(0, 0.5 - uh))
                case 444, 619:                                                                     // 스톤에지 · 단애의칼: stone rising round it
                    for i in 0..<6 { let q = (uh - Double(i) * 0.05) / 0.25; guard q > 0 else { continue }; let x = c.x + Double([-26, 22, -10, 30, -36, 8][i]), fade = q > 2.2 ? 0 : q > 1.6 ? 1 - (q - 1.6) / 0.6 : 1
                        put("pillar|\(id == 619 ? "ground" : "rock")|\(i % 3)", x, body.feet - 10 - 12 * min(1, q), scale: 1.2, alpha: fade) { FX2.pillar(i % 3, id == 619 ? "ground" : "rock") } }
                case 87: land(.crackle, "electric", s, uh); flash(rgb(255, 255, 255), max(0, 0.3 - uh))
                case 63: land(.impact, "normal", s, uh); flash(rgb(255, 210, 160), max(0, 0.4 - uh))
                default: land(kind, ty, s, uh)
                }
            }
            if strong, uh < 0.2 { put("star|1", c.x, c.y, scale: 1.2, alpha: (0.2 - uh) * 5) { FX2.star(1) } }   // super effective, critical: a star over the type's burst
            return true
        default: return false
        }
    }
}
