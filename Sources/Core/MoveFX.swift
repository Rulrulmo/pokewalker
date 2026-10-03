import Foundation
// What a move looks like on the stage: its effect over the fighters, and how they move while it plays.
// Effects are pictures at sprite resolution (fb.pic): a shape in a type's tones at a small frame number, drawn once per key; the motion is per frame.

// MARK: - tones and shapes
/// Each type's effect tones, outline → white (grey screens read them as shades 3 2 1 0 0); then what the status and stat effects wear.
let fxTones: [String: [UInt32]] = [
    "normal": [rgb(72, 60, 48), rgb(146, 116, 76), rgb(222, 190, 112), rgb(255, 244, 200), rgb(255, 255, 255)],
    "fire": [rgb(120, 24, 16), rgb(214, 64, 24), rgb(248, 152, 40), rgb(255, 228, 120), rgb(255, 255, 224)],
    "water": [rgb(24, 48, 136), rgb(48, 104, 216), rgb(104, 168, 248), rgb(200, 236, 255), rgb(255, 255, 255)],
    "electric": [rgb(88, 52, 8), rgb(192, 112, 8), rgb(248, 200, 40), rgb(255, 244, 136), rgb(255, 255, 232)],
    "grass": [rgb(24, 72, 32), rgb(40, 136, 48), rgb(112, 200, 72), rgb(200, 244, 144), rgb(248, 255, 224)],
    "ice": [rgb(28, 56, 128), rgb(64, 128, 208), rgb(144, 208, 240), rgb(216, 248, 255), rgb(255, 255, 255)],
    "fighting": [rgb(112, 24, 16), rgb(200, 64, 32), rgb(240, 144, 64), rgb(255, 224, 160), rgb(255, 255, 232)],
    "poison": [rgb(64, 24, 96), rgb(128, 56, 168), rgb(184, 112, 216), rgb(236, 196, 248), rgb(255, 240, 255)],
    "ground": [rgb(80, 52, 24), rgb(150, 104, 48), rgb(206, 164, 96), rgb(240, 216, 160), rgb(255, 248, 224)],
    "flying": [rgb(48, 56, 120), rgb(104, 112, 192), rgb(168, 184, 240), rgb(232, 240, 255), rgb(255, 255, 255)],
    "psychic": [rgb(120, 24, 80), rgb(216, 64, 144), rgb(248, 136, 192), rgb(255, 208, 236), rgb(255, 248, 252)],
    "bug": [rgb(48, 68, 12), rgb(104, 144, 24), rgb(176, 208, 48), rgb(232, 248, 152), rgb(255, 255, 224)],
    "rock": [rgb(72, 56, 32), rgb(136, 112, 72), rgb(192, 168, 112), rgb(236, 220, 176), rgb(255, 248, 232)],
    "ghost": [rgb(48, 24, 88), rgb(96, 56, 160), rgb(152, 112, 216), rgb(216, 192, 248), rgb(248, 240, 255)],
    "dragon": [rgb(32, 24, 120), rgb(72, 64, 208), rgb(128, 136, 248), rgb(200, 212, 255), rgb(248, 248, 255)],
    "dark": [rgb(24, 16, 24), rgb(80, 64, 80), rgb(120, 104, 120), rgb(184, 172, 184), rgb(240, 236, 240)],
    "steel": [rgb(48, 56, 80), rgb(112, 120, 144), rgb(184, 192, 212), rgb(236, 240, 248), rgb(255, 255, 255)],
    "heal": [rgb(24, 88, 48), rgb(56, 160, 80), rgb(128, 224, 128), rgb(216, 255, 208), rgb(255, 255, 255)],
    "sleep": [rgb(40, 48, 112), rgb(96, 112, 200), rgb(168, 184, 240), rgb(224, 232, 255), rgb(255, 255, 255)],
    "love": [rgb(136, 24, 72), rgb(232, 72, 128), rgb(248, 144, 184), rgb(255, 216, 232), rgb(255, 255, 255)],
]
let fxTypes = ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground", "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel"]
/// The shapes; a frame k is always from a small range: a size (burst 0-2, orb 0-3, bubble 0-2, ring 0-4, spark 0-2, dust 0-2, zee 0-1), a flicker (flame 0-3, bolt 0-2),
/// a heading in 45° steps (leaf, shard, drop, gust 0-7), a lump (rock 0-3 big, 4-7 a chip), how far drawn (slash 0-3), top / bottom (jaw 0-1).
/// core = an orb's inside, no outline: laid over a row of orbs it joins them into one beam.
enum FXShape: String { case burst, orb, core, bubble, ring, flame, bolt, spark, leaf, shard, drop, gust, rock, dust, slash, jaw, zee, heart }

/// A picture from a rule on its centre-relative pixels (x right, y down, the shape turned `turn`° clockwise): 1...4 = dark, mid, light, white;
/// negative = that tone half see-through; nil = clear. Then HGSS's dark outline round the solid part.
func fxDraw(_ w: Int, _ h: Int, _ t: [UInt32], turn: Double = 0, outline: Bool = true, _ tone: (Double, Double) -> Int?) -> Pic {
    var p = Pic(w: w + 2, h: h + 2)
    let c = cos(turn * .pi / 180), s = sin(turn * .pi / 180)
    for y in 0..<h { for x in 0..<w {
        let dx = Double(x) + 0.5 - Double(w) / 2, dy = Double(y) + 0.5 - Double(h) / 2
        guard let k = tone(dx * c + dy * s, dy * c - dx * s), (1...4).contains(abs(k)) else { continue }
        p.set(x + 1, y + 1, k > 0 ? t[k] : t[-k] & 0xFF_FFFF | 0x9000_0000)
    } }
    guard outline else { return p }
    var o = p
    for y in 0..<p.h { for x in 0..<p.w where p.at(x, y) == 0 && [(1, 0), (-1, 0), (0, 1), (0, -1)].contains(where: { p.at(x + $0.0, y + $0.1) >> 24 == 255 }) { o.set(x, y, t[0]) } }
    return o
}
/// Distance from (x, y) to the segment a-b.
func fxSeg(_ x: Double, _ y: Double, _ a: (Double, Double), _ b: (Double, Double)) -> Double {
    let vx = b.0 - a.0, vy = b.1 - a.1, q = max(0, min(1, ((x - a.0) * vx + (y - a.1) * vy) / max(0.001, vx * vx + vy * vy)))
    return hypot(x - a.0 - q * vx, y - a.1 - q * vy)
}
func fxPic(_ a: FXShape, _ tone: String, _ k: Int) -> Pic {
    let t = fxTones[tone] ?? fxTones["normal"]!, turn = Double(k % 8) * 45
    switch a {
    case .burst:                                                                            // the impact star: 8 points, long and short, white at the heart
        let r = [6.0, 9, 13][min(k, 2)], n = Int(r * 2) + 1
        return fxDraw(n, n, t, turn: 15 * Double(k)) { x, y in
            let c = cos(4 * atan2(y, x)), q = hypot(x, y) / (r * (0.36 + 0.64 * pow(abs(c), 4) * (c > 0 ? 1 : 0.6)))
            return q > 1 ? nil : q < 0.4 ? 4 : q < 0.64 ? 3 : q < 0.86 ? 2 : 1
        }
    case .orb:                                                                              // a lit ball: shadow bottom right, a shine top left
        let r = [3.0, 5, 7, 10][min(k, 3)], n = Int(r * 2)
        return fxDraw(n, n, t) { x, y in
            guard hypot(x, y) <= r else { return nil }
            let d = hypot(x + r * 0.35, y + r * 0.35) / (r * 1.3)
            return d < 0.2 ? 4 : d < 0.5 ? 3 : d < 0.82 ? 2 : 1
        }
    case .core:                                                                             // the same ball's inside: light, white down the middle
        let r = [3.0, 5, 7, 10][min(k, 3)], n = Int(r * 2)
        return fxDraw(n, n, t, outline: false) { x, y in let d = hypot(x, y); return d < r * 0.38 ? 4 : d < r - 1.6 ? 3 : d < r - 0.8 ? 2 : nil }
    case .bubble:                                                                         // see-through, a rim and a shine
        let r = [2.5, 4, 6][min(k, 2)], n = Int(r * 2) + 1
        return fxDraw(n, n, t) { x, y in
            let d = hypot(x, y); guard d <= r else { return nil }
            return hypot(x + r * 0.4, y + r * 0.4) < max(0.8, r * 0.3) ? 4 : d > r - 1.1 ? 2 : -3
        }
    case .ring:
        let r = [4.0, 7, 10, 13, 16][min(k, 4)], n = Int(r * 2) + 3
        return fxDraw(n, n, t) { x, y in let d = hypot(x, y) - r; return abs(d) > 1.2 ? nil : d < 0 ? 3 : 2 }
    case .flame:                                                                            // a flame licking up: a big tongue and two small ones, k = its flicker
        let ph = Double(k % 4) * .pi / 2, f = k % 4
        let tongues: [(cx: Double, tip: Double, w: Double)] = [(0, -9 + [0, 1.5, 0.5, 2][f], 4.6), (-3.4, -3 + [1, 0, 2.5, 0.5][f], 2.3), (3.4, -1 + [0, 2.5, 0.5, 1.5][f], 2.1)]
        return fxDraw(12, 18, t) { x, y in
            for (i, g) in tongues.enumerated() {
                let v = (y - g.tip) / (8.8 - g.tip); guard v > 0, v <= 1 else { continue }          // 0 = its tip, 1 = the base
                let sway = sin(ph + v * 5 + Double(i) * 2) * 1.5 * (1 - v) * (1 - v)
                let hw = v > 0.66 ? g.w * sqrt(max(0, 1 - pow((v - 0.66) / 0.34, 2))) : g.w * pow(v / 0.66, 1.2)
                guard abs(x - g.cx - sway) < hw else { continue }
                let e = hypot(x / 5, (y - 4) / 10)
                return e < 0.3 ? 4 : e < 0.55 ? 3 : e < 0.82 ? 2 : 1
            }
            return nil
        }
    case .bolt:                                                                             // a lightning bolt from the sky, 104 tall, its foot at the bottom; k = its zigzag
        let zig: [[Double]] = [[-2, 5, -4, 6, -5, 3, -6, 4, -3, 0], [3, -4, 6, -3, 5, -6, 4, -4, 3, 0], [0, -6, 3, -5, 6, -2, 5, -5, 2, 0]]
        let pts: [(Double, Double)] = (0..<10).map { (i: Int) -> (Double, Double) in (zig[k % 3][i], -52.0 + Double(i) * 104.0 / 9.0) }, fork: (Double, Double) = (pts[5].0 + 9, pts[5].1 + 14)
        return fxDraw(24, 104, t) { x, y in
            let d = (1..<10).map { fxSeg(x, y, pts[$0 - 1], pts[$0]) }.min()!, f = fxSeg(x, y, pts[5], fork) + 0.8
            let m = min(d, f)
            return m < 0.9 ? 4 : m < 1.8 ? 3 : m < 2.6 ? 2 : nil
        }
    case .spark:                                                                            // a 4-point twinkle; 2 = a long glint
        let r = [3.5, 5.5, 8][min(k, 2)], n = Int(r * 2) + 1
        return fxDraw(n, n, t) { x, y in
            let ax = abs(x), ay = abs(y)
            if ax + ay < r * 0.34 { return 4 }
            if (ax < 0.6 && ay < r) || (ay < 0.6 && ax < r) { return ax + ay < r * 0.62 ? 4 : 3 }
            return k > 0 && abs(ax - ay) < 0.6 && ax < r * 0.36 ? 3 : nil
        }
    case .leaf:
        return fxDraw(13, 13, t, turn: turn) { x, y in
            guard abs(x) < 6 else { return nil }
            let c = y + x * x * 0.03 - 0.5, hw = 3 * (1 - pow(abs(x) / 6, 1.5))              // a lens, slightly curved, pointed at both ends
            guard abs(c) < hw else { return nil }
            return abs(c) < 0.5 && x > -5 ? 1 : c < 0 ? 3 : 2
        }
    case .shard:                                                                            // an ice crystal / a needle, pointing its way
        return fxDraw(13, 13, t, turn: turn) { x, y in
            guard abs(x) / 6 + abs(y) / 2.3 < 1 else { return nil }
            return abs(y) < 0.5 ? 4 : y < 0 ? 3 : 2
        }
    case .drop:                                                                             // a water drop, round head first
        return fxDraw(12, 12, t, turn: turn) { x, y in
            let hx = x - 1.8
            if hypot(hx, y) < 3.2 { return hypot(hx + 1, y + 1.2) < 1.1 ? 4 : hypot(hx + 0.4, y + 0.6) < 2.1 ? 3 : 2 }
            return hx < 0 && hx > -5.5 && abs(y) < 3.2 * (1 + hx / 5.5) ? 3 : nil
        }
    case .gust:                                                                             // a wind crescent, bulging its way
        return fxDraw(15, 15, t, turn: turn) { x, y in
            let a = hypot(x, y), b = hypot(x + 3.2, y)
            guard a < 7, b > 6.3 else { return nil }
            return b > 7.8 && a < 6.2 ? 4 : b > 7.2 ? 3 : 2
        }
    case .rock:                                                                             // a lump lit from the top left, a crack; 4-7 a chip
        let r = k < 4 ? 6.0 : 3.0, n = Int(r * 2) + 2, v = Double(k % 4)
        return fxDraw(n, n, t) { x, y in
            let a = atan2(y, x)
            guard hypot(x, y) < r * (0.84 + 0.1 * sin(3 * a + v * 1.7) + 0.07 * cos(5 * a - v)) else { return nil }
            if k < 4, abs(x * 0.8 - y + v - 1) < 0.5, x > -1 { return 1 }
            let l = (x + y) / (r * 1.2)
            return l < -0.55 ? 4 : l < 0 ? 3 : l < 0.55 ? 2 : 1
        }
    case .dust:                                                                             // a puff: three round lumps
        let r = [3.0, 5, 7][min(k, 2)], lumps: [(Double, Double, Double)] = [(-0.55, 0.25, 0.62), (0.55, 0.25, 0.62), (0, -0.1, 0.78)]
        return fxDraw(Int(r * 3), Int(r * 2), t) { x, y in
            guard lumps.contains(where: { hypot(x - $0.0 * r, y - $0.1 * r) < $0.2 * r }) else { return nil }
            return y < -r * 0.35 ? 4 : y < r * 0.2 ? 3 : 2
        }
    case .slash:                                                                            // three claw marks, top right to bottom left, k = how far drawn
        let f = Double(min(k, 3) + 1) / 4
        return fxDraw(28, 28, t) { x, y in
            let along = (x - y) / 1.414, across = (x + y) / 1.414
            guard along > 12 - 24 * f else { return nil }
            for o in [-6.5, 0, 6.5] {
                let c: Double = across - o, hw: Double = 2.6 * sin(Double.pi * max(0.0, min(1.0, (along + 12.0 - abs(o) * 0.4) / 24.0)))
                if abs(c) < hw { return abs(c) < hw * 0.45 ? 4 : 3 }
            }
            return nil
        }
    case .jaw:                                                                              // a row of fangs, long ones at the ends: 0 the top jaw (fangs down), 1 the bottom
        return fxDraw(30, 15, t) { x, y in
            let yy = (k == 0 ? y : -y) + x * x / 90 - 1                                      // the jaw curves round
            if yy < -6.5 { return nil }
            if yy < -4.8 { return abs(x) < 13.5 ? 3 : nil }                                  // the gum line
            let c = ((x + 15) / 7.5).rounded(.down), l = x + 15 - c * 7.5 - 3.75, len = c == 0 || c == 3 ? 11.0 : 7.5
            let p = (yy + 4.8) / len, w = 3.5 * (1 - p)
            return p <= 1 && abs(l) < w ? (l < -w * 0.35 ? 3 : 4) : nil
        }
    case .zee:
        let n = k == 0 ? 7 : 9, h = Double(n) / 2 - 0.5
        return fxDraw(n, n, t) { x, y in abs(y + h) < 0.5 || abs(y - h) < 0.5 || abs(x + y) < 0.6 ? 4 : nil }   // top, bottom, the diagonal
    case .heart:
        return fxDraw(10, 9, t) { x, y in                                                    // two lobes and a point
            let lobe = hypot(abs(x) - 2.2, y + 1.6) < 2.5, point = y > -1.6 && abs(x) < 4.6 * (1 - (y + 1.6) / 6)
            return lobe || point ? (hypot(x + 2.4, y + 2.2) < 1.2 ? 4 : 3) : nil
        }
    }
}
/// A fighter's sprite as a see-through overlay: one tint, or (stripes: phase 0-5) HGSS's stat streaks, bands 12 pixels apart.
func fxMask(_ dex: Int, back: Bool, _ c: UInt32, stripes k: Int?) -> Pic {
    var p = Pic(w: 80, h: 80)
    for y in 0..<80 { for x in 0..<80 where spritePixel(dex, back: back, x, y, shiny: false) != 0 {
        p.set(x, y, k.map { (y + $0 * 2) % 12 < 5 ? c : c & 0xFF_FFFF | 0x3800_0000 } ?? c)
    } }
    return p
}
/// The type a move shows as: as used (웨더볼, 잠재파워, 노말스킨 …); typeless / unknown = normal.
func fxType(_ b: Battle, _ s: Side, _ m: MoveInfo) -> String { let t = b.moveType(s, m).type; return fxTypes.contains(t) ? t : "normal" }
/// The move's line after it says it didn't land (a miss, a block, no effect, a failure): nothing hits.
func fxMissed(_ t: String) -> Bool { ["빗나갔다", "맞지 않았다", "몸을 지켰다", "실패했다", "효과가 없는", "튕겨냈다"].contains { t.contains($0) } }
/// A move's own look (a small table), else its type and category decide.
enum FXLook { case bite, claw, powder, sound, bolt, thunder, hydro, solar, ball, plain }
func fxLook(_ m: MoveInfo) -> FXLook {
    switch m.id { case 85: return .bolt; case 87: return .thunder; case 56: return .hydro; case 76: return .solar; case 412, 426: return .ball; default: break }   // 에너지볼 진흙폭탄: one ball
    if m.sound { return .sound }
    if m.contact, ["물기", "깨물", "엄니"].contains(where: { m.name.contains($0) }) { return .bite }
    if m.contact, ["할퀴", "베기", "베어", "가르기", "클로", "손톱", "커터", "시저", "풀베기"].contains(where: { m.name.contains($0) }) { return .claw }
    if m.isStatus, m.name.contains("가루") || m.name.contains("포자") { return .powder }
    return .plain
}
/// Each type's particle (what its moves spray and pour) and how a special move of it travels.
let fxBit: [String: FXShape] = ["normal": .spark, "fire": .flame, "water": .drop, "electric": .spark, "grass": .leaf, "ice": .shard, "fighting": .spark, "poison": .bubble,
                                "ground": .rock, "flying": .gust, "psychic": .ring, "bug": .shard, "rock": .rock, "ghost": .flame, "dragon": .flame, "dark": .gust, "steel": .spark]
enum FXShot { case stream, orb, volley, rings, bolt }
let fxShot: [String: FXShot] = ["normal": .stream, "fire": .stream, "water": .stream, "electric": .bolt, "grass": .volley, "ice": .stream, "fighting": .orb, "poison": .volley,
                                "ground": .volley, "flying": .volley, "psychic": .rings, "bug": .rings, "rock": .volley, "ghost": .orb, "dragon": .stream, "dark": .rings, "steel": .stream]

extension Walker {
    /// The beat after this one in the playing turn (its first match; 0-length retypes skipped): does the move land, or only charge?
    func upcoming(_ beat: Beat) -> Beat? {
        guard case .beats(_, let bs, _, _) = screen, let i = bs.firstIndex(of: beat) else { return nil }
        return bs[(i + 1)...].first { if case .retype = $0 { return false }; return true }
    }
    /// HGSS drains the bar: a hit / hurt / heal side's HP slides from before the beat (`before`) to after, over 0.3-0.8 s by how much of the bar moves.
    func drained(_ hp: Battle, _ before: Battle, _ beat: Beat, _ u: Double) -> Battle {
        let s: Side
        switch beat { case .hit(let x, _, _, _, _), .hurt(let x, _, _), .heal(let x, _, _): s = x; default: return hp }
        let a = before.f(s).hp, z = hp.f(s).hp, k = min(1, u / (0.3 + 0.5 * Double(abs(z - a)) / Double(max(1, hp.f(s).maxHP))))
        var out = hp; out.mod(s) { $0.hp = a + Int((Double(z - a) * k).rounded()) }
        return out
    }

    /// A move's effect, drawn over the fighters while `beat` plays (u = seconds into it); at = where each side stands (feet at y + 32, centre x + 16, in dots).
    func moveFX(_ fb: inout FB, _ beat: Beat, _ u: Double, _ b: Battle, _ at: [Side: (x: Int, y: Int)]) {
        typealias P = (x: Double, y: Double)
        let low = at[.me]!.y == 22 ? 100.0 : 128                                                // the stage's bottom (the old HUD's message row below)
        /// A fighter's body now, in half-dots: its centre across, head, middle, feet; its sprite run, if drawn (dash, shake and bob included).
        func body(_ s: Side) -> (x: Double, top: Double, y: Double, feet: Double, run: SpriteRun?) {
            let run = fb.sprites.last { $0.back == (s == .me) }, a = at[s]!, dex = (s == .me ? b.mine[b.me] : b.theirs[b.it]).mon.dex
            let rx: Int = run?.x ?? a.x, ry: Int = run?.y ?? a.y, bob: Int = run?.bob ?? 0      // (typed in steps: the ?? arithmetic in one go cost seconds to type-check)
            let x = Double((rx + 16) * 2), feet = Double((ry + 32) * 2 - bob), top: Double = feet - Double(80 - spriteTop(dex, back: s == .me))
            return (x, top, (top + min(feet, low)) / 2, feet, run)
        }
        func mouth(_ s: Side) -> P {                                                            // where a move leaves its user
            let p = body(s)
            if s == .me { return (p.x + 16, p.top + (min(p.feet, low) - p.top) * 0.35) }
            return (p.x - 12, p.top + (p.feet - p.top) * 0.35)
        }
        func aim(_ s: Side) -> P { let p = body(s); return s == .me ? (p.x + 6, p.y - 6) : (p.x, p.y) }                                           // where it lands
        func put(_ a: FXShape, _ t: String, _ k: Int, _ x: Double, _ y: Double, alpha: Double = 1) {
            fb.pic("fx|\(a.rawValue)|\(t)|\(k)", Int(x.rounded()), Int(y.rounded()), alpha: max(0, min(1, alpha))) { fxPic(a, t, k) }
        }
        /// A sprite-shaped overlay on s: a tint, or stat streaks (phase 0-5); only while its sprite is drawn.
        func mask(_ s: Side, _ name: String, _ c: UInt32, stripes k: Int? = nil, alpha: Double) {
            guard let r = body(s).run, alpha > 0 else { return }
            fb.pic("fx|mask|\(r.dex)|\(r.back)|\(name)|\(k ?? -1)", (r.x + 16) * 2, (r.y + 32) * 2 - 40 - r.bob, alpha: min(1, alpha)) { fxMask(r.dex, back: r.back, c, stripes: k) }
        }
        func heading(_ dx: Double, _ dy: Double) -> Int { (Int((atan2(dy, dx) / (.pi / 4)).rounded()) + 8) % 8 }
        /// A particle's frame: heading shapes point their way, flames flicker, the rest vary by i.
        func frame(_ a: FXShape, _ dx: Double, _ dy: Double, _ i: Int) -> Int {
            switch a {
            case .leaf: (heading(dx, dy) + Int(u * 16) + i) % 8                                   // leaves spin as they fly
            case .shard, .drop, .gust: heading(dx, dy)
            case .flame: (Int(u * 15) + i) % 4
            case .spark: (Int(u * 12) + i) % 2
            case .rock: (Int(u * 10) + i) % 4
            case .ring, .burst: 0
            case .bubble, .orb, .core: 1 + i % 2
            default: i % 2
            }
        }
        func ease(_ q: Double) -> Double { 1 - (1 - q) * (1 - q) }
        /// n particles out from p over v 0...1, fading at the end.
        func splash(_ a: FXShape, _ t: String, _ p: P, _ v: Double, n: Int, reach: Double = 24, turn: Double = 20) {
            guard (0...1).contains(v) else { return }
            for i in 0..<n {
                let ang = (turn + Double(i) * 360 / Double(n)) * .pi / 180, d = 5 + reach * ease(v) * (i % 2 == 0 ? 1 : 0.75)
                let dx = cos(ang), dy = sin(ang) - (a == .flame || a == .bubble ? 0.4 : 0)
                put(a, t, a == .rock ? 4 + i % 4 : frame(a, dx, dy, i), p.x + dx * d, p.y + dy * d + (a == .rock || a == .drop ? 12 * v * v : 0), alpha: (1 - v) * 3)   // rocks shed chips
            }
        }
        /// n particles poured from a to z over [t0, t1], each flying `fly` s; wave = their sideways wobble; grow = small orbs until they leave the mouth.
        /// beam = orbs, then their cores over them: one outlined tube.
        func stream(_ sh: FXShape, _ t: String, _ a: P, _ z: P, _ t0: Double, _ t1: Double, n: Int, fly: Double, wave: Double, grow: Bool = false, beam: Bool = false) {
            let dx = z.x - a.x, dy = z.y - a.y, len = max(1, hypot(dx, dy)), nx = -dy / len, ny = dx / len
            for pass in beam ? [FXShape.orb, .core] : [sh] { for i in 0..<n {
                let q = (u - t0 - Double(i) * (t1 - t0 - fly) / Double(max(1, n - 1))) / fly
                guard (0...1).contains(q) else { continue }
                let w = sin(q * .pi * 2 + Double(i) * 1.7) * wave * sin(q * .pi), small = grow && q < 0.2
                let k = beam ? min(2, 1 + Int(q * 4)) : small ? Int(q * 10) : frame(pass, dx, dy, i)          // a beam swells as it leaves the mouth
                put(small && !beam ? .orb : pass, t, k, a.x + dx * q + nx * w, a.y + dy * q + ny * w, alpha: q > 0.9 ? (1 - q) * 10 : 1)
            } }
        }
        /// Particles drawn in to p (a move gathering its power) over v 0...1.
        func gather(_ t: String, _ p: P, _ v: Double) {
            guard (0...1).contains(v) else { return }
            for i in 0..<6 { let ang = Double(i) * 60 * .pi / 180 + 0.4, d = 20 * (1 - v); put(.spark, t, i % 2 == 0 ? 1 : 0, p.x + cos(ang) * d, p.y + sin(ang) * d, alpha: v * 3) }
        }
        /// A big orb flying a to z over v 0...1 (a slight arc), sparks trailing.
        func orb(_ t: String, _ a: P, _ z: P, _ v: Double) {
            guard (0...1).contains(v) else { return }
            let x = a.x + (z.x - a.x) * v, y = a.y + (z.y - a.y) * v - sin(v * .pi) * 6
            for i in 1...3 { let w = Double(i) * 0.07; put(.spark, t, 0, x - (z.x - a.x) * w + Double([3, -3, 2][i - 1]), y - (z.y - a.y) * w + Double([-3, 3, 0][i - 1]), alpha: 1 - Double(i) * 0.25) }
            put(.orb, t, 2 + Int(u * 12) % 2, x, y)
        }
        /// Rings flying a to z, growing as they go.
        func rings(_ t: String, _ a: P, _ z: P, _ t0: Double, _ t1: Double) {
            for i in 0..<5 {
                let q = (u - t0 - Double(i) * (t1 - t0 - 0.3) / 4) / 0.3
                guard (0...1).contains(q) else { continue }
                put(.ring, t, min(3, Int(q * 4)), a.x + (z.x - a.x) * q, a.y + (z.y - a.y) * q, alpha: q > 0.85 ? (1 - q) * 6 : 1)
            }
        }
        /// A bolt from the sky onto p, flickering, sparks round its foot.
        func strike(_ t: String, _ p: P, _ t0: Double, _ t1: Double, dx: Double = 0) {
            guard u >= t0, u <= t1 else { return }
            let f = Int(u * 20) % 3
            if Int(u * 30) % 4 != 3 { put(.bolt, t, f, p.x + dx + Double([0, 2, -2][f]), p.y - 52) }
            for i in 0..<4 where (Int(u * 20) + i) % 2 == 0 { put(.spark, t, i % 2, p.x + Double([-14, 12, -8, 16][i]), p.y + Double([-6, -2, 8, 6][i])) }
        }
        /// Rocks tumbling down onto p from above the screen, from t0; a miss lands them to the side.
        func rocksFall(_ t: String, _ p: P, _ t0: Double, miss: Bool) {
            for i in 0..<5 {
                let q = (u - t0 - Double(i) * 0.08) / 0.26; guard q >= 0, q < 1.5 else { continue }   // falls, then lies there a moment and fades
                let x = p.x + Double([-12, 10, -2, 16, -18][i]) + (miss ? 34 : 0), y0 = -14.0, y1 = p.y + Double([-6, 2, -12, 6, 4][i])
                put(.rock, t, q < 1 ? (i + Int(u * 10)) % 4 : i % 4, x, q < 1 ? y0 + (y1 - y0) * q * q : y1 - 3 * sin((q - 1) * 2 * .pi), alpha: (1.5 - q) * 3)
            }
        }
        /// Dust thrown up along the ground under s (a quake), v 0...1.
        func quake(_ s: Side, _ v: Double) {
            guard (0...1).contains(v) else { return }
            let p = body(s), g = min(p.feet, low) - 3
            for i in 0..<5 {
                let q = (v * 1.6 - Double(i) * 0.12); guard (0...1).contains(q) else { continue }
                let x = p.x + Double(-28 + 14 * i)
                put(.dust, "ground", min(2, Int(q * 3)), x, g - q * 6, alpha: (1 - q) * 3)
                put(.rock, "ground", 4 + i % 4, x + Double(i % 2 == 0 ? 4 : -4), g - 14 * sin(q * .pi), alpha: (1 - q) * 4)
            }
        }
        /// Particles rising up s's body (a buff, a heal, a status), v 0...1.
        func rise(_ a: FXShape, _ t: String, _ s: Side, _ v: Double, n: Int = 6, k: Int? = nil) {
            guard (0...1).contains(v) else { return }
            let p = body(s), h = min(p.feet, low) - p.top
            for i in 0..<n {
                let q = v * 1.5 - Double(i) * 0.5 / Double(n); guard (0...1).contains(q) else { continue }
                let x = p.x + Double([-16, 14, -6, 20, -22, 6, 0, -12][i % 8]), y = min(p.feet, low) - 4 - q * h * 0.9
                put(a, t, k ?? frame(a, 0, -1, i), x + sin(q * 9 + Double(i)) * 2, y, alpha: (1 - q) * 4)
            }
        }
        /// Particles flickering round s's body, v 0...1.
        func around(_ a: FXShape, _ t: String, _ s: Side, _ v: Double, n: Int = 4) {
            guard (0...1).contains(v) else { return }
            let p = body(s), h = min(p.feet, low) - p.top
            for i in 0..<n where (Int(u * 12) + i) % 3 != 0 {
                put(a, t, frame(a, 0, -1, i), p.x + Double([-18, 16, -10, 20, 2, -22][i % 6]), p.top + h * [0.3, 0.45, 0.75, 0.7, 0.15, 0.55][i % 6], alpha: (1 - v) * 4)
            }
        }
        /// Z's floating up off its head.
        func zees(_ s: Side, _ v: Double) {
            let p = body(s), hx = p.x + (s == .me ? 12 : -8)
            for i in 0..<3 {
                let q = v * 1.6 - Double(i) * 0.3; guard (0...1).contains(q) else { continue }
                put(.zee, "sleep", i == 1 ? 0 : 1, hx + q * 14 + sin(q * 6) * 2, p.top + 2 - q * 18, alpha: (1 - q) * 4)
            }
        }
        func pulse(_ v: Double, _ peak: Double) -> Double { v < 0 || v > 1 ? 0 : peak * (0.55 + 0.45 * sin(v * .pi * 6)) * min(1, (1 - v) * 4) }

        switch beat {
        case .use(let s, let id):                                                               // the move's flight: its user, then towards its target
            let m = moveTable[id]!, ty = fxType(b, s, m), t = b.other(s), next = upcoming(beat), look = fxLook(m)
            let miss: Bool = { if case .note(_, let x)? = next { return fxMissed(x) }; return false }()
            let only: Bool = { if m.charges, case .note(let w, _)? = next, w == s { return true }; return false }()   // turn 1 of a two-turn move: it only gathers
            let from = mouth(s), z = miss ? (aim(t).x + (t == .it ? 30 : -30), aim(t).y - 24) : aim(t)   // a miss flies past
            if only { gather(ty, aim(s), u / 0.6); return }
            if m.isStatus {
                let v = (u - 0.1) / 0.8
                if m.onFoe || look == .sound {
                    if look == .sound { rings(ty, from, z, 0.1, 0.85); return }
                    if look == .powder {                                                        // a powder drifting down over it
                        let pt = m.name.contains("저리") ? "electric" : m.name.contains("수면") ? "sleep" : m.name.contains("독") ? "poison" : "grass", p = body(t)
                        for i in 0..<9 where !miss || i < 3 {
                            let q = (u - 0.15 - Double(i) * 0.05) / 0.55; guard (0...1).contains(q) else { continue }
                            put(.orb, pt, 0, p.x + Double([-18, -8, 4, 14, 22, -14, 8, -2, 18][i]) + sin(q * 8 + Double(i)) * 3, p.top - 10 + q * (p.y - p.top + 16), alpha: (1 - q) * 5)
                        }
                        return
                    }
                    gather(ty, from, u / 0.3)
                    rings(ty, from, z, 0.25, 0.65)
                    if !miss { around(fxBit[ty]!, ty, t, (u - 0.55) / 0.35) }
                } else {                                                                        // on itself: sparkles rising, a glow
                    rise(fxBit[ty] == .ring ? .spark : fxBit[ty]!, ty, s, v)
                    put(.ring, ty, min(4, Int(max(0, v) * 5)), aim(s).x, aim(s).y, alpha: v < 0 ? 0 : (1 - v) * 2)
                    mask(s, "glow", rgb(255, 255, 255), alpha: pulse(v, 0.45))
                }
                return
            }
            if m.physical && m.contact {                                                        // the lunge (movePose); its afterimages
                if (0.45...0.72).contains(u), let r = body(s).run { for (i, w) in [0.55, 0.3].enumerated() {
                    let back = Double((i + 1) * 4) * (s == .me ? -1 : 1)
                    fb.pic("fx|mask|\(r.dex)|\(r.back)|ghost|-1", (r.x + 16) * 2 + Int(back * 2), (r.y + 32) * 2 - 40 - r.bob, alpha: w, behind: true) { fxMask(r.dex, back: r.back, rgb(255, 255, 255), stripes: nil) }
                } }
                return
            }
            if m.physical {                                                                     // no contact: rocks drop on it, the ground quakes, or it's thrown
                if ty == "rock" { rocksFall(ty, aim(t), 0.4, miss: miss); return }
                if ty == "ground" { if !miss { quake(t, (u - 0.25) / 0.65) }; return }
                stream(fxBit[ty]!, ty, from, z, 0.25, 0.88, n: 6, fly: 0.28, wave: 6)
                return
            }
            gather(ty, from, u / 0.3)                                                           // special: it gathers, then it flies
            if look == .bolt || look == .thunder || fxShot[ty] == .bolt, !miss, u > 0.45 { mask(t, "para", rgb(255, 236, 80), alpha: Int(u * 20) % 2 == 0 ? 0.6 : 0) }   // the bolt lights it up
            switch look {
            case .bolt: strike(ty, z, 0.45, 0.9); return
            case .thunder: strike(ty, z, 0.4, 0.9); strike(ty, z, 0.55, 0.9, dx: -14); return
            case .hydro:
                stream(.orb, "water", from, z, 0.28, 0.88, n: 24, fly: 0.2, wave: 1, beam: true)
                stream(.drop, "water", from, z, 0.3, 0.88, n: 10, fly: 0.2, wave: 10); stream(.bubble, "water", from, z, 0.34, 0.88, n: 5, fly: 0.2, wave: 13); return
            case .solar: stream(.orb, "grass", from, z, 0.28, 0.88, n: 24, fly: 0.2, wave: 0, beam: true); stream(.spark, "grass", from, z, 0.3, 0.88, n: 9, fly: 0.2, wave: 10); return
            case .sound: rings(ty, from, z, 0.25, 0.88); return
            case .ball: orb(ty, from, z, (u - 0.3) / 0.58); return
            default: break
            }
            switch fxShot[ty]! {
            case .stream:                                                                       // fire pours flames; the rest is a beam, the type's bits riding it
                if fxBit[ty] == .flame { stream(.flame, ty, from, z, 0.28, 0.88, n: 16, fly: 0.24, wave: 3, grow: true); break }
                stream(.orb, ty, from, z, 0.28, 0.88, n: 22, fly: 0.24, wave: 0, beam: true)
                if ty != "normal" { stream(fxBit[ty]!, ty, from, z, 0.3, 0.88, n: 7, fly: 0.24, wave: 8) }
            case .orb: orb(ty, from, z, (u - 0.3) / 0.58)
            case .volley: stream(ty == "poison" || ty == "ground" ? .orb : fxBit[ty]!, ty, from, z, 0.28, 0.88, n: 5, fly: 0.3, wave: 6)
            case .rings: rings(ty, from, z, 0.28, 0.88)
            case .bolt: strike(ty, z, 0.45, 0.9)
            }
        case .hit(let s, let id, _, let e, _):                                                  // the impact: a burst, the type's particles thrown off
            let m = moveTable[id]!, ty = fxType(b, b.other(s), m), c = aim(s), look = fxLook(m), v = u / 0.3, n = e > 1 ? 8 : e < 1 ? 3 : 5
            if look == .bite, u < 0.4 {                                                         // fangs snap shut, then the burst
                let q = min(1, u / 0.14), gap = 14 * (1 - q * q)
                put(.jaw, ty == "normal" ? "dark" : ty, 0, c.x, c.y - 5 - gap, alpha: (0.4 - u) * 8); put(.jaw, ty == "normal" ? "dark" : ty, 1, c.x, c.y + 5 + gap, alpha: (0.4 - u) * 8)
                if u > 0.12 { put(.burst, ty, min(2, Int((u - 0.12) / 0.06)), c.x, c.y, alpha: (0.4 - u) * 6) }
            } else if look == .claw, u < 0.4 {
                put(.slash, ty == "normal" ? "steel" : ty, min(3, Int(u / 0.04)), c.x, c.y, alpha: (0.4 - u) * 6)
            } else if (0...1).contains(v) {
                put(.burst, ty, min(2, Int(v * 5)), c.x + (e > 1 ? 2 : 0), c.y, alpha: (1 - v) * 3)
                if e > 1, v > 0.2 { put(.burst, ty, min(2, Int((v - 0.2) * 5)), c.x - 12, c.y + 8, alpha: (1 - v) * 3) }
            }
            let bit = fxBit[ty]!
            splash(bit, ty, c, (u - 0.04) / 0.5, n: m.physical ? max(3, n - 2) : n, reach: bit == .ring ? 12 : 24)
            if m.physical, ty == "rock" || ty == "ground" { splash(.dust, "ground", (c.x, min(body(s).feet, low) - 6), u / 0.5, n: 3, reach: 14, turn: -30) }
        case .status(let s, let st, _):                                                         // a status taking hold (or its cure)
            let v = u / 1.1
            switch st {
            case .burn?: around(.flame, "fire", s, v, n: 5); mask(s, "burn", rgb(255, 96, 48), alpha: pulse(v, 0.5))
            case .poison?, .toxic?: rise(.bubble, "poison", s, v, n: 7); mask(s, "poison", rgb(168, 72, 216), alpha: pulse(v, 0.5))
            case .paralysis?: around(.spark, "electric", s, v, n: 6); mask(s, "para", rgb(255, 224, 48), alpha: Int(u * 10) % 2 == 0 ? pulse(v, 0.6) : 0)
            case .sleep?: zees(s, v)
            case .freeze?: around(.shard, "ice", s, v, n: 6); mask(s, "ice", rgb(170, 226, 255), alpha: min(0.6, u * 2) * min(1, (1.2 - u) * 3))
            case nil: around(.spark, "normal", s, v, n: 6)
            }
        case .note(let s, let t):                                                               // stat changes, and statuses holding a fighter back
            let v = u / 1.1
            if t.contains("올라갔다") || t.contains("떨어졌다") {
                let up = t.contains("올라갔다"), ph = Int(u * 30) % 6
                mask(s, up ? "up" : "down", up ? rgb(170, 222, 255) : rgb(208, 56, 56), stripes: up ? ph : 5 - ph, alpha: min(1, u * 6) * min(1, (1.15 - u) * 5) * 0.8)   // up pale (light bands on a grey screen), down dark
            } else if t.contains("잠들어 있다") { zees(s, v) }
            else if t.contains("몸이 저려") { around(.spark, "electric", s, v, n: 6); mask(s, "para", rgb(255, 224, 48), alpha: Int(u * 10) % 2 == 0 ? pulse(v, 0.6) : 0) }
            else if t.contains("얼어버려") { around(.shard, "ice", s, v, n: 5); mask(s, "ice", rgb(170, 226, 255), alpha: 0.5 * min(1, (1.2 - u) * 3)) }
            else if t.contains("혼란스러워") || t.contains("혼란에 빠졌다") {                   // stars circling its head
                let p = body(s)
                for i in 0..<3 { let a = u * 7 + Double(i) * 2.1; put(.spark, "electric", 1, p.x + cos(a) * 16, p.top + 2 + sin(a) * 4, alpha: min(1, (1.2 - u) * 4)) }
            } else if t.contains("사랑에 빠") { rise(.heart, "love", s, v, n: 4, k: 0) }
        case .heal(let s, _, let t):                                                            // green twinkles rising; a drain first pulls orbs across
            if t.contains("흡수") { stream(.orb, "heal", aim(b.other(s)), aim(s), 0, 0.6, n: 6, fly: 0.3, wave: 8) }
            let v = (u - (t.contains("흡수") ? 0.4 : 0.05)) / 0.9
            rise(.spark, "heal", s, v, n: 7)
            mask(s, "heal", rgb(208, 255, 200), alpha: pulse(v, 0.3))
        case .hurt(let s, _, let t):                                                            // what hurts it now
            let v = u / 0.9, c = aim(s)
            if t.contains("독의 데미지") { rise(.bubble, "poison", s, v, n: 6); mask(s, "poison", rgb(168, 72, 216), alpha: pulse(v, 0.5)) }
            else if t.contains("화상") { around(.flame, "fire", s, v, n: 4); mask(s, "burn", rgb(255, 96, 48), alpha: pulse(v, 0.45)) }
            else if t.contains("모래바람") {                                                     // sand blown across
                let p = body(s)
                for i in 0..<10 where u < 1 {                                                   // each grain its own row and pace, left to right
                    let q = (u * (1.8 + Double(i % 3) * 0.4) + [0.1, 0.55, 0.3, 0.85, 0.45, 0.7, 0.2, 0.95, 0.6, 0.35][i]).truncatingRemainder(dividingBy: 1)
                    put(i % 3 == 0 ? .dust : .rock, "ground", i % 3 == 0 ? 0 : 4 + i % 4, p.x - 34 + q * 68, p.top + 4 + (min(p.feet, low) - p.top - 8) * Double(i) / 9, alpha: min(1, (1 - u) * 3, q * 6, (1 - q) * 6))
                }
            } else if t.contains("싸라기눈") {                                                   // hail pelting down
                let p = body(s)
                for i in 0..<6 { let q = (u * 1.8 - Double(i) * 0.13); if (0...1).contains(q) { put(.shard, "ice", 2, p.x + Double([-16, 8, -4, 18, -10, 12][i]), p.top - 16 + q * (p.y - p.top + 16), alpha: (1 - q) * 5) } }
            } else if t.contains("씨뿌리기") { stream(.orb, "heal", c, aim(b.other(s)), 0.1, 0.8, n: 5, fly: 0.35, wave: 6) }
            else if t.contains("저주") || t.contains("악몽") || t.contains("나이트메어") { around(.flame, "ghost", s, v, n: 4) }
            else if t.contains("뾰족한 바위") { rocksFall("rock", c, 0, miss: false) }
            else if t.contains("미래") { rings("psychic", (c.x, c.y - 40), c, 0, 0.6) }
            else if u < 0.3 { put(.burst, "normal", min(2, Int(u / 0.06)), c.x, c.y, alpha: (0.3 - u) * 8) }   // recoil, confusion, hazards …
        default: break
        }
    }
    /// How the fighters move for this beat, if a move has its own way; nil = the stage's usual pose.
    func movePose(_ beat: Beat, _ u: Double, _ b: Battle) -> Pose? {
        func arc(_ a: Double, _ len: Double) -> Double { u < a || u > a + len ? 0 : sin(.pi * (u - a) / len) }   // 0 -> 1 -> 0
        switch beat {
        case .use(let s, let id):
            let m = moveTable[id]!, dir = s == .me ? 1.0 : -1.0
            if m.isStatus { return .show(s, dx: 0, dy: Int((s == .me ? 3 : -4) * arc(0.05, 0.3)), flash: false, visible: true) }   // a hop (ours dips: its back is cut off)
            if m.physical && m.contact {                                                        // wind up, lunge, snap back: the hit's burst (next beat) meets the return
                let k = u < 0.2 ? 0 : u < 0.4 ? -0.25 * sin(.pi / 2 * (u - 0.2) / 0.2) : u < 0.7 ? -0.25 + 1.25 * pow((u - 0.4) / 0.3, 2) : u < 0.76 ? 1 : max(0, 1 - (u - 0.76) / 0.12)
                return .show(s, dx: Int((12 * dir * k).rounded()), dy: s == .me ? 0 : Int((5 * k).rounded()), flash: false, visible: true)
            }
            if m.physical, fxType(b, s, m) == "ground", case .hit? = upcoming(beat), u > 0.3 {  // a quake: the target's the one shaking
                return .show(b.other(s), dx: Int(u * 30) % 2 == 0 ? 2 : -2, dy: 0, flash: false, visible: true)
            }
            return .show(s, dx: Int((dir * (2 * arc(0.3, 0.5) - arc(0, 0.3))).rounded()), dy: 0, flash: false, visible: true)   // it braces, then fires
        case .status(let s, _, _): return .show(s, dx: 0, dy: 0, flash: false, visible: true)   // its own tint instead of the red flash
        default: return nil
        }
    }
}
/// Self-test checks for this file (run by selftest()).
@MainActor func moveChecks() -> [(Bool, String)] {
    var out: [(Bool, String)] = []
    var r = Seeded(s: 21)
    let v = Walker(state: Walk()); v.persist = false
    var b = Battle(wild: Mon.wild(4, level: 20, &r), companion: Mon.wild(25, level: 20, &r))
    let before = b, hit = Beat.hit(.it, move: 53, damage: b.theirs[0].hp / 2, effect: 1, crit: false); b.apply(hit)
    let hp = [0, 0.2, 5].map { v.drained(b, before, hit, $0).theirs[0].hp }
    out.append((hp[0] == before.theirs[0].hp && hp[1] < hp[0] && hp[1] > b.theirs[0].hp && hp[2] == b.theirs[0].hp, "HP drains from before the hit to after"))
    out.append((fxTypes.allSatisfy { fxTones[$0] != nil && fxBit[$0] != nil && fxShot[$0] != nil && fxPic(fxBit[$0]!, $0, 0).px.contains { $0 != 0 } }, "every type has tones, a particle and a flight"))
    let at: [Side: (x: Int, y: Int)] = [.it: (60, 8), .me: (8, 32)]
    let beats: [Beat] = [9, 53, 56, 85, 89, 94, 157, 247, 44, 10, 45, 77, 14].flatMap { [.use(.me, move: $0), .hit(.it, move: $0, damage: 5, effect: 2, crit: false)] }
        + [.status(.it, .burn, text: ""), .status(.it, .sleep, text: ""), .status(.me, nil, text: ""), .note(.it, text: "파이리의 공격이 떨어졌다!"),
           .note(.me, text: "피카츄의 공격이 올라갔다!"), .heal(.me, amount: 5, text: "체력을 흡수했다!"), .hurt(.it, damage: 3, text: "독의 데미지를 입었다!")]
    func run(_ dt: Double) -> Int { for bt in beats { for f in 0..<Int(bt.length * 30) { var fb = FB(); fb.sprite(b.theirs[0].mon, 60, 8); fb.sprite(b.mine[0].mon, 8, 32, back: true); v.moveFX(&fb, bt, Double(f) / 30 + dt, b, at) } }; return picStore.keys.count }
    _ = run(0); _ = run(1 / 60.0)
    let names = Set(["glow", "ghost", "burn", "poison", "para", "ice", "up", "down", "heal"])
    let keys = picStore.keys.filter { $0.hasPrefix("fx|") }.map { $0.split(separator: "|").map(String.init) }
    out.append((!keys.isEmpty && keys.allSatisfy { k in
        k.count == 4 ? FXShape(rawValue: k[1]) != nil && fxTones[k[2]] != nil && (0..<8).contains(Int(k[3]) ?? -9)
                     : k.count == 6 && k[1] == "mask" && (1...493).contains(Int(k[2]) ?? 0) && names.contains(k[4]) && (-1...5).contains(Int(k[5]) ?? -9)
    }, "move effect pictures come from a finite set of keys (\(keys.count))"))
    func reach(_ next: Beat) -> Int {                                                           // how far right a 물대포 of ours flies, just before it lands
        let use = Beat.use(.me, move: 55); v.screen = .beats(b, [use, next], since: Date(), from: b)
        var fb = FB(); fb.sprite(b.theirs[0].mon, 60, 8); fb.sprite(b.mine[0].mon, 8, 32, back: true); v.moveFX(&fb, use, 0.8, b, at)
        return fb.pics.map(\.x).max() ?? 0
    }
    out.append((reach(.note(.it, text: "피카츄의 공격은 빗나갔다!")) > reach(.hit(.it, move: 55, damage: 5, effect: 1, crit: false)) + 10, "a miss flies past its target"))
    v.screen = .home
    return out
}
