import Foundation
// 5.0 (docs/plans/18 §9.6, the user's "메가진화 할때 이펙트 좀 아쉬운데"): a Mega Evolution as X · Y show it, at the LCD's size, over Beat.mega's
// 2.9 s — its stone glints over it; rainbow streaks run in from all round and it's wrapped in a rainbow cocoon; the screen flashes white and
// shakes; the Mega symbol shows as rainbow shards fly off; then the Mega (its animation, once). 원시회귀 in its orb's colours: 그란돈 주홍 (α),
// 가이오가 쪽빛 (Ω). The same for ours, a tower foe's (its first move) and a raid boss's.

enum MegaFX {
    static let reveal = 1.6                                     // the flash: before it the old form (its name, its picture), after it the Mega
    /// The light's colours: a rainbow, or a primal's orb's.
    static func colours(_ dex: Int, _ form: Int) -> [UInt32] {
        guard Forms.of(dex, form)?.kind == .primal else {
            return [rgb(255, 86, 96), rgb(255, 160, 64), rgb(255, 226, 80), rgb(110, 220, 110), rgb(80, 200, 245), rgb(96, 124, 255), rgb(196, 104, 255)]
        }
        return dex == 383 ? [rgb(255, 72, 48), rgb(255, 136, 56), rgb(255, 204, 96), rgb(232, 64, 40)] : [rgb(48, 112, 255), rgb(72, 184, 255), rgb(160, 228, 255), rgb(40, 80, 220)]
    }
    /// The symbol: the Mega's (a ring and the helix in it, in the rainbow round), or α / Ω.
    static func symbolPic(_ dex: Int, _ form: Int) -> Pic {
        let cs = colours(dex, form), n = 25, c = 12.0
        var p = Pic(w: n, h: n)
        if Forms.of(dex, form)?.kind == .primal {
            let rows = dex == 383 ? ["....................", "......ooo....oo.....", "....oo...o..oo......", "...o......o.o.......", "..o.......ooo.......",
                                     "..o........o........", "..o.......o.o.......", "...o.....o...o......", "....oo.oo.....oo....", "......o.........o..."]          // α
                                  : ["......ooooo.......", "....oo.....oo.....", "...o.........o....", "..o...........o...", "..o...........o...",
                                     "..o...........o...", "...o.........o....", "....o.......o.....", "..ooo.......ooo...", "..ooo.......ooo..."]            // Ω
            for (y, r) in rows.enumerated() { for (x, ch) in r.enumerated() where ch == "o" {
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] { p.set(x + 2 + dx, 2 * y + 3 + dy, cs[(x + y) % 3]) }
            } }
            return p
        }
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - c, dy = Double(y) - c, r = hypot(dx, dy), a = atan2(dy, dx)
            let hue = cs[Int(((a + .pi) / (2 * .pi) * Double(cs.count)).rounded(.down)) % cs.count]
            if (9.5...11.8).contains(r) { p.set(x, y, hue) }                                                        // the ring
            let s1 = 3.2 * sin(dy / 3.0), s2 = -s1                                                                  // the helix: two strands crossing
            if abs(dy) < 9, abs(dx - s1) < 1.2 || abs(dx - s2) < 1.2 { p.set(x, y, abs(dx - s1) < 1.2 ? cs[1] : cs[5]) }
            if abs(dy) < 8, Int(dy + 20) % 4 == 0, abs(dx) < abs(s1) { p.set(x, y, rgb(255, 255, 255)) }          // its rungs
        } }
        return p
    }
    /// A streak of light running in (its colour k), lying along x: angle turns it.
    static func streakPic(_ c: UInt32) -> Pic {
        var p = Pic(w: 22, h: 5)
        for x in 0..<22 {
            let a = UInt32(min(255, 40 + x * 11)), core = x > 15 ? lerpRGB(c, rgb(255, 255, 255), Double(x - 15) / 7) : c
            for y in 1...3 { p.set(x, y, (a << 24) | (core & 0xFF_FFFF)) }
            if x > 9 { for y in [0, 4] { p.set(x, y, (UInt32(a / 3) << 24) | (c & 0xFF_FFFF)) } }
        }
        return p
    }
    /// A shard flying off: a small diamond.
    static func shardPic(_ c: UInt32) -> Pic { Pic(["..o..", ".oWo.", "oWWWo", ".oWo.", "..o.."], ["o": c, "W": lerpRGB(c, rgb(255, 255, 255), 0.6)]) }
    /// The stone's glint: a four-pointed star in its colour.
    static func glintPic(_ c: UInt32) -> Pic { Pic(["....o....", "....o....", "...oWo...", ".ooWWWoo.", "ooWWWWWoo", ".ooWWWoo.", "...oWo...", "....o....", "....o...."], ["o": c, "W": rgb(255, 255, 255)]) }
    /// Over the fighter, u seconds in: its sprite's tint (the cocoon: a colour and how much of it), how far the stage shakes (dots).
    static func cocoon(_ u: Double, _ cs: [UInt32]) -> (tint: UInt32, amount: Double)? {
        guard u > 0.6, u < reveal + 0.15 else { return nil }
        let k = min(1, (u - 0.6) / 0.6), c = cs[Int(u * 12) % cs.count]
        return (u < reveal ? lerpRGB(c, rgb(255, 255, 255), min(0.85, max(0, (u - 1.15) / 0.45))) : rgb(255, 255, 255), u < reveal ? 0.35 + 0.65 * k : max(0, 1 - (u - reveal) / 0.15))
    }
    static func shake(_ u: Double) -> Int { u >= reveal - 0.05 && u < reveal + 0.3 ? (Int(u * 40) % 2 == 0 ? 1 : -1) : 0 }
}

extension FB {
    /// The light round a Mega Evolution (MegaFX) at side s, u seconds in; at = where each stands (BattleView.stage), top = its head (half-dots above its feet).
    mutating func megaFX(_ s: Side, _ u: Double, dex: Int, form: Int, at: [Side: (x: Int, y: Int)], top: Int, stage: [Int] = []) {   // stage: a clip (half-dots) under the HUD
        let a = at[s]!, fx = (a.x + 16) * 2, fy = (a.y + 32) * 2, cy = fy - max(18, top / 2), cs = MegaFX.colours(dex, form)
        if u < 0.75 {                                                                                     // the stone glints over it
            let k = u / 0.75, c = cs[Int(u * 8) % cs.count], i = cs.firstIndex(of: c) ?? 0
            pic("mega glint \(dex).\(form).\(i)", fx + (s == .me ? 14 : 10), fy - top - 4, scale: 0.6 + 0.6 * abs(sin(u * 9)), alpha: k < 0.85 ? 1 : (1 - k) / 0.15, clip: stage) { MegaFX.glintPic(c) }
        }
        if u > 0.35, u < MegaFX.reveal {                                                                  // rainbow streaks run in from all round
            for i in 0..<12 {
                let start = 0.35 + Double(i % 4) * 0.12, t = (u - start) / 0.5
                guard t > 0 else { continue }
                let ph = t.truncatingRemainder(dividingBy: 1), ang = Double(i) * .pi / 6 + Double(Int(t)) * 0.4, r = 74 * (1 - ph) + 6
                let c = cs[i % cs.count]
                pic("mega streak \(dex).\(form).\(i % cs.count)", fx + Int(r * cos(ang)), cy + Int(r * sin(ang) * 0.8), alpha: min(1, ph * 3) * (u > MegaFX.reveal - 0.2 ? (MegaFX.reveal - u) / 0.2 : 1),
                    angle: ang * 180 / .pi + 180, clip: stage) { MegaFX.streakPic(c) }
            }
        }
        if u >= MegaFX.reveal - 0.05, u < MegaFX.reveal + 0.2 {                                          // the screen flashes white
            let k = (u - MegaFX.reveal + 0.05) / 0.25
            pic("entry flash", 96, 64, alpha: 0.95 * (1 - k)) { var p = Pic(w: 192, h: 128); p.fill(0, 0, 192, 128, rgb(255, 255, 255)); return p }
        }
        if u >= MegaFX.reveal, u < MegaFX.reveal + 0.9 {                                                 // its symbol, and shards flying off
            let t = u - MegaFX.reveal
            pic("mega symbol \(dex).\(form)", fx, cy, scale: 0.6 + 0.9 * min(1, t / 0.25), alpha: t < 0.55 ? 1 : max(0, 1 - (t - 0.55) / 0.35), clip: stage) { MegaFX.symbolPic(dex, form) }
            if t < 0.7 {
                let k = 1 - pow(1 - t / 0.7, 2)
                for i in 0..<14 {
                    let ang = (Double(i) + 0.3) * .pi / 7, r = 8 + 62 * k * (1 + 0.25 * sin(Double(i) * 1.7)), c = cs[i % cs.count]
                    pic("mega shard \(dex).\(form).\(i % cs.count)", fx + Int(r * cos(ang)), cy + Int(r * sin(ang) * 0.8) + Int(t * t * 30), alpha: 1 - max(0, t - 0.4) / 0.3, clip: stage) { MegaFX.shardPic(c) }
                }
            }
        }
    }
    /// The sprite just added, in its cocoon: tinted in the light's colour (amount: how much).
    mutating func megaTint(_ c: UInt32, _ amount: Double, floor: Int = 64) {                        // floor: the dot row it stops at (the LCD's message strip)
        guard amount > 0, var r = sprites.last else { return }
        r.tint = c; r.tintShade = 0; r.alpha = amount; r.floor = min(r.floor, floor); sprites.append(r)
    }
}
