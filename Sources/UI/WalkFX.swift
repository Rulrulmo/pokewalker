import AppKit
// The walker's own shows: the Poké Radar's grass, the egg, hatching, evolving. All at sprite resolution (fb.pic, half-dot pixels).

// MARK: - pictures
/// Tall grass by season: outline, dark, mid, light, tip.
let grassPals: [[UInt32]] = [
    [rgb(30, 72, 44), rgb(52, 132, 70), rgb(92, 184, 84), rgb(156, 222, 110), rgb(214, 246, 164)],      // spring
    [rgb(26, 66, 40), rgb(44, 122, 60), rgb(80, 168, 70), rgb(140, 210, 94), rgb(200, 238, 140)],       // summer
    [rgb(86, 52, 26), rgb(158, 104, 40), rgb(204, 150, 56), rgb(234, 194, 96), rgb(250, 228, 156)],     // autumn
    [rgb(36, 64, 72), rgb(64, 116, 112), rgb(112, 164, 150), rgb(188, 222, 214), rgb(250, 252, 255)],   // winter: frosted
]
/// A small repeatable noise in 0..<1 (blade heights, leaf paths).
func hash01(_ i: Int) -> Double { Double(UInt32(truncatingIfNeeded: (i &+ 7) &* 2_654_435_761) >> 8 & 1023) / 1024 }

/// A patch of HGSS tall grass, w x h: three rows of pointed blades (back dark, front lit), each outlined so the rows stay apart.
/// f 0...5 = the idle sway (a wave through the tips); rustle f 0...3 = thrown hard left, right, left, right; flip = mirrored (neighbours differ).
func grassPic(_ w: Int, _ h: Int, _ season: Season, _ f: Int, rustle: Bool = false, flip: Bool = false) -> Pic {
    let pal = grassPals[season.rawValue]
    var p = Pic(w: w, h: h)
    let W = Double(w), H = Double(h), bw = max(4.5, W / 6.4)
    func blade(_ x: Double, _ base: Int, _ tall: Int, _ lean: Double, _ bw: Double, body: UInt32, lit: UInt32, tip: UInt32) {
        for i in 0...tall {
            let t = Double(i) / Double(tall), y = base - tall + i
            let cx = x + lean * (1 - t) * (1 - t), hw = 0.5 + (bw / 2 - 0.5) * pow(t, 0.7)
            let l = Int((cx - hw).rounded()), r = Int((cx + hw).rounded())
            for xx in l...r {
                let edge = xx == l || xx == r || i == 0 || i == tall
                p.set(xx, y, edge ? pal[0] : t < 0.22 ? tip : Double(xx - l) < Double(r - l) * 0.45 ? lit : body)
            }
        }
    }
    let m = max(4, Int(W / 9.6))                                                                     // blades a row: 5 at 48 px
    let rows: [(n: Int, drop: Double, tall: Double, spread: Double, bw: Double, body: Int, lit: Int, tip: Int)] =
        [(m, 0.3, 0.6, 0.62, bw, 1, 2, 2), (m - 1, 0.15, 0.52, 0.6, bw, 1, 2, 3), (m + 1, 0, 0.42, 0.84, bw * 0.8, 2, 3, 4)]
    var n = 0
    for row in rows {
        for k in 0..<row.n {
            let fx = (Double(k) + 0.5) / Double(row.n) - 0.5, edge = abs(fx) * 2                          // -0.5...0.5 across; 0 centre ... 1 edge
            let x = W / 2 + fx * row.spread * W, base = Int((H - 1 - row.drop * H - edge * edge * H * 0.1).rounded())
            let tall = Int((row.tall * (1 - 0.3 * edge * edge) + 0.06 * (hash01(n) - 0.5)) * H)
            let sway = rustle ? (f % 2 == 0 ? 1 : -1) * (f < 2 ? 4.0 : 2.5) * (0.7 + 0.3 * hash01(n + 50)) : 1.2 * sin(Double(f) / 6 * 2 * .pi + Double(n) * 0.9)
            blade(x, base, tall, fx * Double(tall) * 0.6 + sway * Double(tall) / (0.5 * H), row.bw, body: pal[row.body], lit: pal[row.lit], tip: pal[row.tip])
            n += 1
        }
    }
    for y in Int(H * 0.5)..<h {                                                                      // the clump's foot: gaps between blade bases = shade between them
        guard let l = (0..<w).first(where: { p.at($0, y) != 0 }), let r = (0..<w).last(where: { p.at($0, y) != 0 }), l < r else { continue }
        var x = l
        while x < r {                                                                                    // low down every gap; higher up only pinholes (1-2 px)
            guard p.at(x, y) == 0 else { x += 1; continue }
            let e: Int = (x...r).first(where: { p.at($0, y) != 0 }) ?? r
            if Double(y) >= H * 0.78 || e - x <= 2 { for xx in x..<e { p.set(xx, y, pal[1]) } }
            x = e
        }
    }
    guard flip else { return p }
    var q = p
    for y in 0..<h { for x in 0..<w { q.set(x, y, p.at(w - 1 - x, y)) } }
    return q
}
/// A soft ellipse on the ground under a patch or an egg.
func shadePic(_ w: Int, _ h: Int = 6) -> Pic {
    var p = Pic(w: w, h: h)
    for y in 0..<h { for x in 0..<w {
        let dx = (Double(x) + 0.5) / Double(w) * 2 - 1, dy = (Double(y) + 0.5) / Double(h) * 2 - 1
        if dx * dx + dy * dy < 1 { p.set(x, y, 0x4818_2818) }
    } }
    return p
}
/// The cursor: HGSS's red arrow, pointing right (down = the same turned).
func pointerPic(down: Bool) -> Pic {
    let rows = ["oo.....", "oho....", "ohro...", "ohrro..", "orrrro.", "orrrrro", "orrrdo.", "orrdo..", "ordo...", "odo....", "oo....."]
    let p = Pic(rows, ["o": rgb(56, 24, 24), "h": rgb(255, 170, 150), "r": rgb(232, 64, 48), "d": rgb(170, 34, 30)])
    guard down else { return p }
    var q = Pic(w: p.h, h: p.w)
    for y in 0..<p.h { for x in 0..<p.w { q.set(y, x, p.at(x, y)) } }
    return q
}
/// "!" in a white balloon, its tail down to the grass.
let bangPic = Pic(["..ooooooooo..", ".owwwwwwwwwo.", "owwwwrrrwwwwo", "owwwrrrrdwwwo", "owwwrrrrdwwwo", "owwwwrrdwwwwo", "owwwwrrdwwwwo", "owwwwwrwwwwwo",
                   "owwwwwwwwwwwo", "owwwwrrdwwwwo", "owwwwrrdwwwwo", "ogwwwwwwwwwgo", ".ogggggggggo.", "..oooowwooo..", ".....owo.....", ".....oo......"],
                  ["o": rgb(40, 40, 48), "w": rgb(255, 255, 255), "g": rgb(208, 212, 222), "r": rgb(236, 52, 40), "d": rgb(176, 28, 24)])
/// The Poké Radar's pulse: a ring of radius r (px), light edged.
func ringPic(_ r: Int) -> Pic {
    var p = Pic(w: 2 * r + 1, h: 2 * r + 1)
    for y in 0...2 * r { for x in 0...2 * r {
        let d = (Double((x - r) * (x - r) + (y - r) * (y - r))).squareRoot(), R = Double(r)
        if d <= R, d > R - 1 { p.set(x, y, rgb(72, 150, 220)) } else if d <= R - 1, d > R - 3 { p.set(x, y, 0xC0B0_E0FF) }
    } }
    return p
}
/// The HGSS egg's colours: 1 outline, 2 soft outline, 3...5 greens, 6...9 shell (shadow to shine).
let eggColors: [Character: UInt32] = ["1": rgb(24, 24, 24), "2": rgb(90, 82, 65), "3": rgb(131, 180, 106), "4": rgb(156, 205, 131), "5": rgb(205, 230, 180),
                                      "6": rgb(213, 205, 164), "7": rgb(238, 230, 189), "8": rgb(255, 246, 222), "9": rgb(255, 255, 255)]
/// The egg on the home screen's bottom row: the HGSS egg drawn small (12 x 15).
let miniEgg = Pic(["....2222....", "..22999822..", ".1899999881.", ".1889998881.", "148888888881", "144888888871", "144448848871", "144488444871",
                   "184888844471", "188888854471", "178888885431", ".1668888631.", ".1666666631.", "..11666611..", "....1111...."], eggColors)
/// The HGSS egg cut out of its frame (28 x 30), cracked in stages 0...3 (3: light through the cracks).
func eggPic(_ stage: Int) -> Pic {
    let f = framePic("egg"); var p = Pic(w: 28, h: 30)
    for y in 0..<30 { for x in 0..<28 { p.set(x, y, f.at(x + 26, y + 50)) } }
    let cracks: [[(Int, Int)]] = [[(14, 2), (12, 5), (15, 7), (13, 10)], [(13, 10), (10, 12), (7, 11)], [(15, 7), (18, 9), (21, 8)],
                                  [(1, 14), (4, 11), (7, 14), (10, 11), (13, 14), (16, 11), (19, 14), (22, 11), (26, 14)]]
    let n = [0, 1, 3, 4][max(0, min(3, stage))], ink = rgb(24, 24, 24)
    for c in cracks.prefix(n) {
        for (a, b) in zip(c, c.dropFirst()) {
            let steps = max(abs(b.0 - a.0), abs(b.1 - a.1))
            for s in 0...steps {
                let x = a.0 + (b.0 - a.0) * s / steps, y = a.1 + (b.1 - a.1) * s / steps
                guard p.at(x, y) != 0 else { continue }
                p.set(x, y, ink)
                if stage == 3, p.at(x, y + 1) != 0, p.at(x, y + 1) != ink { p.set(x, y + 1, rgb(255, 244, 170)) }   // light leaking out
            }
        }
    }
    return p
}
/// Bits of shell flying off at the hatch.
let shellPics = [Pic([".11...", "18811.", "188871", "148877", ".11111"], eggColors), Pic(["..1..", ".181.", "18871", "17771", "11111"], eggColors),
                 Pic(["111..", "18411", "18871", ".111."], eggColors)]
/// A soft light, rx x ry px out; hot = white at the heart (the hatch's burst), else all its colour (the glow behind an evolving Pokémon).
func glowPic(_ rx: Int, _ ry: Int, _ c: UInt32, hot: Bool) -> Pic {
    var p = Pic(w: 2 * rx, h: 2 * ry)
    for y in 0..<2 * ry { for x in 0..<2 * rx {
        let dx = (Double(x - rx) + 0.5) / Double(rx), dy = (Double(y - ry) + 0.5) / Double(ry), d = (dx * dx + dy * dy).squareRoot()
        guard d < 1 else { continue }
        let w = hot ? max(0, 1 - d / 0.55) : 0, mix = { (v: UInt32) in UInt32(Double(v) + (255 - Double(v)) * w) }
        p.set(x, y, UInt32(pow(1 - d, hot ? 0.8 : 1.3) * 255) << 24 | mix(c >> 16 & 255) << 16 | mix(c >> 8 & 255) << 8 | mix(c & 255))
    } }
    return p
}
/// A four-point star: 9 x 9 or (small) 5 x 5.
func sparklePic(small: Bool) -> Pic {
    let pal: [Character: UInt32] = ["W": rgb(255, 255, 255), "y": rgb(255, 238, 136), "o": rgb(246, 180, 40)]
    return small ? Pic(["..o..", "..y..", "oyWyo", "..y..", "..o.."], pal) : Pic(["....o....", "....y....", "....y....", "...yWy...", "oyyWWWyyo", "...yWy...", "....y....", "....y....", "....o...."], pal)
}
/// A mote of light, 5 x 5, soft edged.
let orbPic: Pic = {
    var p = Pic(w: 5, h: 5)
    for y in 0..<5 { for x in 0..<5 {
        let d = (Double((x - 2) * (x - 2) + (y - 2) * (y - 2))).squareRoot()
        if d < 2.6 { p.set(x, y, UInt32((1 - d / 2.6) * 255 + 0.5) << 24 | (d < 1 ? 0xFF_FFFF : 0xD8_F0FF)) }
    } }
    return p
}()
/// A plain box (the white-out, the lights going down), w x h px.
func panelPic(_ w: Int, _ h: Int, _ c: UInt32) -> Pic { var p = Pic(w: w, h: h); p.fill(0, 0, w, h, c); return p }

/// A picture as the pane draws it (colour, 1 pt a pixel x K), from the same store as the LCD's.
@MainActor func paneImage(_ key: String, _ make: () -> Pic) -> NSImage {
    if picStore[key] == nil { picStore[key] = make() }
    return picImage(PicRun(key: key, x: 0, y: 0), lcds[0])!.0
}
/// A grass patch for the pane, the same picture as the LCD's.
@MainActor func grassImage(_ w: Int, _ h: Int, _ season: Season, _ f: Int, rustle: Bool = false, flip: Bool = false) -> NSImage {
    paneImage(grassKey(w, h, season, f, rustle: rustle, flip: flip)) { grassPic(w, h, season, f, rustle: rustle, flip: flip) }
}
func grassKey(_ w: Int, _ h: Int, _ season: Season, _ f: Int, rustle: Bool, flip: Bool) -> String { "w.grass|\(w)x\(h)|\(season.rawValue)|" + (rustle ? "r" : "") + "\(f)" + (flip ? "m" : "") }

// MARK: - the shows
extension FB {
    /// 포켓 레이더 on the LCD, over the course picture (the pane has the four patches to pick): the Radar's pulse spreading from the companion
    /// standing at feet (half-dots); live = seconds since something turned up: "!" pops over its head.
    mutating func radarFX(feet: (x: Int, y: Int), live: Double?, u: Double) {
        for i in 0..<2 {                                                                               // two rings spreading from it
            let k = (u - 0.35 * Double(i)) / 0.9
            if (0..<1).contains(k) { let r = 3 + Int(k * 24); pic("w.ring|\(r)", feet.x, feet.y - 12, alpha: 1 - k) { ringPic(r * 4) } }
        }
        guard let v = live else { return }
        let pop = v < 0.12 ? v / 0.12 * 1.35 : v < 0.24 ? 1.35 - (v - 0.12) / 0.12 * 0.35 : 1          // "!": pops up, settles, then bobs
        pic("w.bang", feet.x + 10, feet.y - 36 - Int(6 * pop) - (v > 0.24 && Int(v * 4) % 2 == 0 ? 1 : 0), scale: pop) { bangPic }
    }
    /// An egg picture standing on (x, y) half-dots, h px tall, rocking about its foot by `angle`.
    mutating func egg(_ key: String, _ x: Int, _ y: Int, _ h: Int, scale: Double = 1, angle: Double = 0, shade: Int = 0, _ make: () -> Pic) {
        if shade > 0 { pic("w.shade|\(shade)", x, y - 1, behind: true) { shadePic(shade) } }
        let a = angle * .pi / 180, r = Double(h) * scale / 2
        pic(key, x + Int((r * sin(a)).rounded()), y - Int((r * cos(a)).rounded()), scale: scale, angle: angle, make)
    }
    /// The home screen's egg (bottom row); close to hatching it rocks every so often.
    mutating func homeEgg(close: Bool, t: Double) {
        let tau = t.truncatingRemainder(dividingBy: 1.6)
        egg("w.egg|mini", 91, 122, 15, angle: close && tau < 0.5 ? 16 * sin(tau / 0.25 * 2 * .pi) * (1 - tau / 0.5) : 0) { miniEgg }
    }
    /// The card's egg page: the HGSS egg, big; close to hatching it rocks gently now and then.
    mutating func cardEgg(close: Bool, t: Double) {
        let tau = t.truncatingRemainder(dividingBy: 2.4)
        egg("w.egg|0", 96, 96, 30, scale: 2, angle: close && tau < 0.8 ? 7 * sin(tau / 0.4 * 2 * .pi) * (1 - tau / 0.8) : 0, shade: 40) { eggPic(0) }
    }
    /// A Pokémon on the shows' spot (its feet on dot (48, 49)), scaled about its middle; tint = a silhouette in that colour.
    mutating func showMon(_ m: Mon, scale s: Double = 1, alpha: Double = 1, tint: UInt32? = nil, bob: Int = 0, anim u: Double? = nil) {
        let mid = Double(80 - spriteTop(m.dex)) / 4                                                      // its middle, in dots above its feet
        sprite(m, 32, 17 - Int((mid * (1 - s)).rounded()), bob: bob, tint: tint.map { (0, $0) }, floor: 50, anim: u)   // a wing's swing stays off the message row
        sprites[sprites.count - 1].scale = s; sprites[sprites.count - 1].alpha = alpha
    }
    /// A glow on (x, y) half-dots, cut off at the message row (y 100) so the light stays on the stage.
    mutating func stageGlow(_ name: String, _ x: Int, _ y: Int, _ rx: Int, _ ry: Int, _ c: UInt32, hot: Bool, alpha: Double = 1) {
        pic("w.glow|\(name)|\(y)", x, y, alpha: alpha, behind: true) {
            var p = glowPic(rx, ry, c, hot: hot)
            for row in max(0, min(p.h, 100 - (y - ry)))..<p.h { for col in 0..<p.w { p.set(col, row, 0) } }
            return p
        }
    }
    /// The white-out over the stage (above the message row), at `a`.
    mutating func whiteOut(_ a: Double) { if a > 0 { pic("w.white|stage", 96, 50, alpha: min(1, a)) { panelPic(192, 100, rgb(255, 255, 255)) } } }
    /// Stars popping in turn around (x, y) half-dots, r out; n of them, `big` = the large ones too. Kept above the message row.
    mutating func sparkles(_ u: Double, _ x: Int, _ y: Int, _ r: Double, n: Int, big: Bool) {
        for i in 0..<n {
            let tau = (u / 0.9 + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1), a = Double(i) * 2.4 + 0.6
            guard tau < 0.6 else { continue }
            let s = sin(tau / 0.6 * .pi), sx = x + Int(cos(a) * r * (0.8 + 0.3 * hash01(i))), sy = min(92, y + Int(sin(a) * r * 0.8 * (0.8 + 0.3 * hash01(i + 5))))
            let large = big && i % 2 == 0
            pic("w.spark|\(large)", sx, sy, scale: max(0.2, s)) { sparklePic(small: !large) }
        }
    }
    /// 부화 (5.5 s): the egg rocks harder and harder, cracks in three stages, bursts in light with its shell flying; a white-out;
    /// the Pokémon grows out of the light (2.95 s on) with sparkles. The message row is the caller's.
    mutating func hatchFX(_ m: Mon, _ u: Double, bob: Int) {
        let ex = 96, ey = 84, cy = ey - 30, glow = rgb(255, 236, 150)                                  // the egg's foot and middle (half-dots)
        if u < 2.6 {
            var a = 0.0
            for (s, e, deg, hz) in [(0.5, 1.1, 6.0, 3.3), (1.3, 1.9, 10.0, 4.0), (2.05, 2.6, 15.0, 7.0)] where (s..<e).contains(u) { a = deg * sin((u - s) * hz * 2 * .pi) }
            let stage = u < 1.1 ? 0 : u < 1.9 ? 1 : u < 2.3 ? 2 : 3
            let jolt = [1.1, 1.9, 2.3].contains { (0..<0.08).contains(u - $0) } ? 2 : 0                  // each new crack jolts it
            if u > 2.2 { pic("w.glow|egg", ex, cy, scale: 1 + (u - 2.2), alpha: min(1, (u - 2.2) / 0.3), behind: true) { glowPic(34, 32, glow, hot: true) } }
            egg("w.egg|\(stage)", ex, ey - jolt, 30, scale: 2, angle: a, shade: 40) { eggPic(stage) }
        } else if u < 2.9 {
            pic("w.glow|burst", ex, cy, scale: min(1, 0.35 + (u - 2.6) / 0.15 * 0.65)) { glowPic(96, 46, glow, hot: true) }   // the burst of light, up to the stage's edges
        }
        if u >= 2.95 {                                                                               // out of the light: a white shape growing, then its colours
            let g = min(1, (u - 2.95) / 0.45), s = 0.3 + 0.7 * (1 - (1 - g) * (1 - g)), top = spriteTop(m.dex)
            if u < 3.9 { stageGlow("born", ex, 98 - (80 - top) / 2, 40, 36, glow, hot: true, alpha: min(1, (3.9 - u) / 0.6)) }
            showMon(m, scale: s, bob: u > 3.8 ? bob : 0, anim: u > 3.8 ? u - 3.8 : nil)             // out of the light: its own HGSS animation
            if u < 3.75 { showMon(m, scale: s, alpha: min(1, (3.75 - u) / 0.4), tint: rgb(255, 255, 255)) }
        }
        whiteOut(u < 2.7 ? 0 : u < 2.85 ? (u - 2.7) / 0.15 : u < 3.0 ? 1 : 1 - (u - 3.0) / 0.45)
        if (2.6..<3.6).contains(u) {                                                                  // the shell flies off, over the white, and falls behind the message row
            let d = u - 2.6 + 0.04                                                                     // they start just off the egg
            for i in 0..<8 {
                let a = -Double.pi / 2 + (Double(i) - 3.5) * 0.42, v = 120 + 50 * hash01(i + 3)
                let x = Double(ex) + cos(a) * v * d * 1.3, y = Double(cy) + sin(a) * v * d + 150 * d * d
                if y < 94 { pic("w.shell|\(i % 3)", Int(x), Int(y), scale: 2, alpha: d < 0.7 ? 1 : max(0, (1 - d) / 0.3), angle: (i % 2 == 0 ? 1 : -1) * d * 600) { shellPics[i % 3] } }
            }
        }
        if u > 3.3 { let top = spriteTop(m.dex); sparkles(u - 3.3, 96, 98 - (80 - top) / 2, Double(80 - top) / 2 + 14, n: m.shiny == true ? 8 : 6, big: m.shiny == true || u < 4.6) }
    }
    /// 진화 (6.5 s): lights down and it glows white (to 1.2 s); the two shapes take turns, the old shrinking as the new grows, faster and faster,
    /// with motes of light spiralling in (to 4.0 s); a white flash (to 4.4 s); the new form, sparkling. The message row is the caller's.
    mutating func evolveFX(_ from: Mon, _ to: Mon, _ u: Double, bob: Int) {
        pic("w.dark|stage", 96, 50, alpha: min(1, u / 0.7), behind: true) { panelPic(192, 100, rgb(18, 22, 42)) }
        let mid = { (m: Mon) in 98 - (80 - spriteTop(m.dex)) / 2 }                                     // a form's middle, half-dots
        if u < 4.0 {
            let on = min(1, max(0, (u - 0.5) / 0.7))
            stageGlow("evo", 96, mid(from), 54, 50, rgb(70, 120, 230), hot: false, alpha: on * (0.65 + 0.15 * sin(u * 7)))
            for i in 0..<16 {                                                                         // motes spiralling in and up, quicker as it goes
                let g = u / 1.3 + max(0, u - 1.2) * max(0, u - 1.2) * 0.3, tau = (g + Double(i) / 16).truncatingRemainder(dividingBy: 1)
                let a = Double(i) * 2.4 + tau * 4, r = 84 * (1 - tau) + 6, y = mid(from) + Int(sin(a) * r * 0.55 - 18 * tau)
                if y < 96 { pic("w.orb", 96 + Int(cos(a) * r), y, alpha: sin(tau * .pi) * min(1, u / 0.6)) { orbPic } }
            }
        }
        if u < 1.2 {
            showMon(from, bob: bob)
            if u > 0.5 { showMon(from, alpha: min(1, (u - 0.5) / 0.7), tint: rgb(255, 255, 255)) }
        } else if u < 4.0 {
            let k = (u - 1.2) / 2.8, n = 1.5 * k + 11 * k * k                                            // half-turns so far: 12.5 by 4.0 s
            showMon(Int(n + 0.5) % 2 == 0 ? from : to, scale: 0.3 + 0.7 * abs(cos(n * .pi)), tint: rgb(255, 255, 255))
        } else {
            showMon(to, bob: u > 4.9 ? bob : 0, anim: u > 4.9 ? u - 4.9 : nil)
            if u > 4.5 { sparkles(u - 4.5, 96, mid(to), Double(98 - mid(to)) + 14, n: 8, big: true) }
        }
        whiteOut(u < 3.85 ? 0 : u < 4.0 ? (u - 3.85) / 0.15 : u < 4.4 ? 1 : 1 - (u - 4.4) / 0.5)
    }
}

/// Self-test checks for this file (run by selftest()).
@MainActor func walkChecks() -> [(Bool, String)] {
    var keys = Set<String>(), later = Set<String>(), spill = 0, low: [String: Int] = [:]
    let a = Mon(dex: 4, level: 16, female: false), b = Mon(dex: 5, level: 16, female: false), egg = Mon(dex: 175, level: 1, female: false)
    for f in 0..<400 {                                                                                // 30 fps through each show, then the same again an hour on
        let u = Double(f % 200) / 30, t = u + (f < 200 ? 0 : 3600.3)
        var h = FB(); h.hatchFX(egg, u, bob: 0); var e = FB(); e.evolveFX(a, b, u, bob: 0)
        var r = FB(); r.radarFX(feet: (96, 90), live: u > 1.5 ? u - 1.5 : nil, u: u)
        var d = FB(); d.homeEgg(close: true, t: t); d.cardEgg(close: true, t: t)
        for p in h.pics + e.pics + r.pics + d.pics { if f < 200 { keys.insert(p.key) } else { later.insert(p.key) } }
        for p in h.pics + e.pics {                                                                  // the lowest opaque row of each picture, on screen
            guard let q = picStore[p.key] else { continue }
            if low[p.key] == nil { low[p.key] = (0..<q.h).last { y in (0..<q.w).contains { q.at($0, y) != 0 } } ?? 0 }
            if Double(p.y) + (Double(low[p.key]!) + 1 - Double(q.h) / 2) * p.scale > 101 { spill += 1 }
        }
    }
    let shell = eggPic(0), opaque = shell.px.filter { $0 != 0 }.count
    return [(later.isSubset(of: keys) && keys.count < 200, "walk FX: picture keys come from a finite set, not the clock (\(keys.count))"),
            (spill == 0, "hatch / evolve: no light or shell spills into the message row (\(spill))"),
            (opaque > 600 && (0..<28).contains { shell.at($0, 29) != 0 } && (0..<28).contains { shell.at($0, 0) != 0 }, "the HGSS egg is cut whole out of its frame (\(opaque) px)")]
}

