import AppKit
// The course picture on the home screen and the ground a fight stands on: HGSS-style scenery at sprite resolution (1 px = half a dot),
// made once per art / season / light / overcast (fb.pic keys), with small moving bits (clouds, glints, foam, the weather) over it.

/// The game clock's light (as for evolutions): 0 day, 1 dawn 4-6, 2 dusk 17-20, 3 night 20-4.
func lightBand(_ hour: Double) -> Int { hour < 4 || hour >= 20 ? 3 : hour < 6 ? 1 : hour >= 17 ? 2 : 0 }

extension FB {
    /// The course picture, framed like a little window: 42 x 26 dots from (x, y). Sky, clouds drifting behind the land, the land, glints, the weather, the frame.
    mutating func course(_ a: Art, _ x: Int, _ y: Int, weather w: Weather = .sunny, t: Double = 0, hour: Double = 12, season: Season = .summer) {
        let tb = lightBand(hour), grey = w != .sunny, cx = 2 * x + 42, cy = 2 * y + 26, g = lcds[lcdStyle].color ? "" : "|g", key = "route|\(a)|\(season.rawValue)|\(tb)|\(grey)" + g
        if a != .cave {
            pic("route|sky|\(a)|\(tb)|\(grey)" + g, cx, cy, behind: true) { lcdReady(cornered(skyPic(84, 52, horizon: routeHorizon[a]!, tb, grey, sun: a == .forest ? nil : a == .mountain ? (73, 8) : a == .town ? (42, 8) : (64, 10)))) }
            for (k, c) in clouds(grey, tb).enumerated() {                                             // drifting right, fading in at the left edge and out at the right
                let lo = 2 * x + 2 + c.w / 2, span = 80 - c.w, u = (c.at + t * c.speed).truncatingRemainder(dividingBy: Double(span)), fade = min(1, u / 10, (Double(span) - u) / 10)
                pic("route|cloud|\(c.w)|\(tb)|\(grey)" + g, lo + Int(u), 2 * y + c.y, alpha: (max(0, fade) * 4).rounded() / 4, behind: true) { lcdReady(cloudPic(c.w == 24 ? 0 : 1, tb, grey)) }
            }
        }
        pic(key, cx, cy, behind: true) { lcdReady(cornered(scenePic(a, season, tb, grey))) }
        let water: [(Int, Int)] = a == .beach ? [(30, 23), (52, 27), (16, 29), (66, 22), (42, 31)] : a == .lake && season != .winter ? [(22, 29), (48, 33), (62, 27), (34, 36)] : a == .cave ? [(9, 41), (75, 36)] : []
        for (k, (gx, gy)) in water.enumerated() where (Int(t * 2.5) + k * 3) % 7 == 0 { pic("route|glint", 2 * x + gx, 2 * y + gy, behind: true) { skyGlintPic() } }   // water / crystal glints
        if a == .beach { pic("route|foam|\(tb)|\(grey)", cx, 2 * y + 35 + Int((sin(t * 1.3) * 1.3).rounded()), behind: true) { foamPic(tb, grey) } }                // the surf coming and going
        if tb == 3, !grey, a != .cave { for (k, (sx, sy)) in [(14, 6), (58, 4)].enumerated() where (Int(t * 1.5) + k) % 3 != 0 { pic("route|star", 2 * x + sx, 2 * y + sy, behind: true) { skyStarPic() } } }
        weatherFX(w, x + 1, y + 1, 40, 24, t, cave: a == .cave, behind: true)
        pic("route|frame", cx, cy, behind: true) { windowPic(84, 52) }
    }
    /// Home: the course as a wide band, y 12 ..< 50 dots, for the companion to walk in (the sky, the scenery, the ground it walks on at y ~48; the weather over it).
    mutating func homeScene(_ a: Art, weather w: Weather, t: Double, hour: Double, season: Season) {
        let tb = lightBand(hour), grey = w != .sunny, g = lcds[lcdStyle].color ? "" : "|g"
        pic("home|\(a)|\(season.rawValue)|\(tb)|\(grey)" + g, 96, 62, behind: true) { lcdReady(stagePic(a, season, tb, grey, 192, 76, [(-60, 52, 0.1, 0.1)])) }
        weatherFX(w, 0, 12, 96, 38, t, cave: a == .cave, behind: true)
    }
    /// Under a fight: an HGSS battle backdrop (the course's scenery pale on the horizon, the ground, a pad under each side; indoor = the Battle Tower's hall).
    /// With the old in-LCD HUD the stage is only y 14 ..< 50 (dots), so the backdrop is too. Pads: under the feet (at[s].y + 32), centred on at[s].x + 16.
    mutating func battleGround(_ at: [Side: (x: Int, y: Int)], art: Art, hour: Double, season: Season, weather: Weather, indoor: Bool) {
        let top = at[.it]!.y == 8 ? 0 : 28, h = top == 0 ? 128 : 72, tb = indoor ? 0 : lightBand(hour), grey = !indoor && weather != .sunny, g = lcds[lcdStyle].color ? "" : "|g"
        let pads = [(Double(2 * at[.it]!.x + 32), Double(2 * at[.it]!.y + 62 - top), 46.0, 12.0), (Double(2 * at[.me]!.x + 30), Double(2 * at[.me]!.y + 60 - top), 72.0, 18.0)]
        pic("stage|\(indoor ? "tower" : "\(art)|\(season.rawValue)|\(tb)|\(grey)")|\(top)" + g, 96, top + h / 2, behind: true) {
            lcdReady(indoor ? towerPic(192, h, pads) : stagePic(art, season, tb, grey, 192, h, pads))
        }
    }
}
/// A picture's corners cleared (the frame's are round).
private func cornered(_ p: Pic) -> Pic { var q = p; for (x, y) in [(0, 0), (p.w - 1, 0), (0, p.h - 1), (p.w - 1, p.h - 1)] { q.set(x, y, 0) }; return q }
/// On a grey LCD: 4 greys that land exactly on its shades, dithered only close to a step (mapped by brightness alone the scene bands and blurs).
@MainActor private func lcdReady(_ p: Pic) -> Pic {
    guard !lcds[lcdStyle].color else { return p }
    var q = p
    for y in 0..<p.h { for x in 0..<p.w {
        let c = p.px[y * p.w + x]; guard c >> 24 > 0 else { continue }
        let l = (0.299 * Double(c >> 16 & 255) + 0.587 * Double(c >> 8 & 255) + 0.114 * Double(c & 255)) / 255
        let v: UInt32 = [230, 163, 97, 31][max(0, min(3, Int(((0.9 - l) / 0.26 + 0.5 + bayer4(x, y) * 0.6).rounded(.down))))]
        q.px[y * p.w + x] = c & 0xFF00_0000 | v << 16 | v << 8 | v
    } }
    return q
}
/// Self-test checks for this file's drawing (run by selftest()).
@MainActor func routeChecks() -> [(Bool, String)] {
    var fb = FB(); fb.course(.lake, 1, 22, weather: .rain, t: 3, hour: 22, season: .winter)
    let keys = fb.pics.map(\.key), scene = keys.first { $0.hasPrefix("route|lake|") }.flatMap { picStore[$0] }
    var st = FB(); st.battleGround([.it: (60, 8), .me: (8, 32)], art: .field, hour: 12, season: .spring, weather: .sunny, indoor: false)
    let bg = st.pics.first.flatMap { picStore[$0.key] }, pad = bg?.at(152, 76) ?? 0, far = bg?.at(20, 100) ?? 0
    var hudFB = FB(); hudFB.battleGround([.it: (60, 14), .me: (8, 22)], art: .cave, hour: 12, season: .summer, weather: .fog, indoor: true)
    var a = FB(), b = FB(); a.weatherFX(.snow, 0, 0, 96, 64, 10); b.weatherFX(.snow, 0, 0, 96, 64, 10.5)
    return [(keys.first?.hasPrefix("route|sky|lake|3|true") == true && keys.last == "route|frame" && keys.contains { $0.hasPrefix("wx|rain") } && fb.pics.allSatisfy(\.behind), "the course: sky, land, rain and frame at sprite resolution, all under the sprites"),
            (scene.map { $0.w == 84 && $0.h == 52 && $0.at(0, 0) == 0 && $0.at(40, 26) >> 24 == 255 } == true && fb.px.allSatisfy { $0 == 0 }, "the course picture is 42 x 26 dots of pictures (round corners), no dots"),
            (bg?.w == 192 && bg?.h == 128 && pad != far && pad >> 24 == 255, "the battle backdrop fills the stage, a pad under the foe's feet"),
            (hudFB.pics.first.map { $0.key.hasPrefix("stage|tower|28") && $0.y == 64 && picStore[$0.key]?.h == 72 } == true, "the old HUD layout: the tower hall only between the HUD and the message row"),
            (a.pics.count > 20 && a.pics.count == b.pics.count && a.pics.map(\.y) != b.pics.map(\.y) && Set((a.pics + b.pics).map(\.key)).count <= 3, "snow: a few flake pictures, moved by the clock")]
}

// MARK: - the weather
extension FB {
    /// Rain streaks, drifting snow, fog bands over a w x h box of dots (the course picture, the battle stage), at sprite resolution:
    /// each drop / flake / band is a small picture moved by t, so any frame rate stays smooth. behind = under the sprites (the course picture).
    mutating func weatherFX(_ wx: Weather, _ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ t: Double, cave: Bool = false, behind: Bool = false) {
        let (L, T, W, H) = (2 * x0, 2 * y0, 2 * w, 2 * h)
        func wrap(_ v: Double, _ n: Int) -> Int { let m = v.truncatingRemainder(dividingBy: Double(n)); return Int(m < 0 ? m + Double(n) : m) }
        switch wx {
        case .rain:                                                                                  // falling down-left, two kinds of streak
            for k in 0..<W * H / 190 {
                let fall = Double(hashXY(k, 1)) + t * (170 + Double(hashXY(k, 2) % 60)), y = wrap(fall, H - 8), x = wrap(Double(hashXY(k, 3)) - fall / 4, W - 2)
                pic("wx|rain|\(k % 2)", L + 1 + x, T + 4 + y, behind: behind) { rainPic(k % 2) }
            }
        case .snow:                                                                                  // big and small flakes, swaying as they fall
            for k in 0..<W * H / 230 {
                let v = k % 3, s = v == 2 ? 4 : 2, fall = Double(hashXY(k, 1)) + t * (9 + Double(hashXY(k, 2) % 8) + Double(v) * 4)
                let y = wrap(fall, H - s), x = wrap(Double(hashXY(k, 3)) + sin(t * 1.1 + Double(k)) * 3 + t * 2, W - s)
                pic("wx|snow|\(v)", L + s / 2 + x, T + s / 2 + y, behind: behind) { flakePic(v) }
            }
        case .fog:                                                                                   // a veil, and soft bands drifting to and fro
            pic("wx|veil|\(W)x\(H)|\(cave)", L + W / 2, T + H / 2, behind: behind) { var p = Pic(w: W, h: H); p.fill(0, 0, W, H, cave ? 0x3C9A_9098 : 0x44E8_ECF2); return p }
            let n = max(2, H / 24), bw = W * 3 / 4 / 2 * 2, bh = 12
            for k in 0..<n {
                let sway = Int(sin(t * 0.22 + Double(k) * 2.1) * Double(W - bw) / 2 * 0.9)
                pic("wx|fog|\(bw)|\(cave)", L + W / 2 + sway, T + H * (2 * k + 1) / (2 * n), alpha: behind ? 1 : 0.7, behind: behind) { fogPic(bw, bh, cave) }   // lighter over the fighters
            }
        case .sunny: break
        }
    }
}
private func hashXY(_ x: Int, _ y: Int, _ s: Int = 0) -> Int {
    var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ s &* 1_442_695_041)
    h = (h ^ h >> 13) &* 1_274_126_177; return Int((h ^ h >> 16) & 0xFFFF)
}
private func argb(_ a: UInt8, _ c: UInt32) -> UInt32 { UInt32(a) << 24 | c & 0xFF_FFFF }
/// A streak 2 x 8: a darker blue side (reads on the pale backdrops) and a light side (reads on the dark land).
private func rainPic(_ v: Int) -> Pic {
    var p = Pic(w: 2, h: 8)
    for y in 0..<8 { let a = UInt8(70 + y * 20), x = y < 4 ? 1 : 0; p.set(x, y, argb(a, v == 0 ? rgb(236, 244, 255) : rgb(120, 156, 224))) }
    return p
}
private func flakePic(_ v: Int) -> Pic {
    let w = rgb(255, 255, 255), e = rgb(168, 188, 220)
    return v == 2 ? Pic([".ww.", "wWWw", "wWWw", ".ww."], ["w": argb(200, e), "W": w]) : Pic(["Ww", "ww"], ["W": w, "w": argb(v == 0 ? 220 : 150, v == 0 ? w : e)])
}
private func fogPic(_ w: Int, _ h: Int, _ cave: Bool) -> Pic {
    var p = Pic(w: w, h: h); let c = cave ? rgb(176, 166, 170) : rgb(240, 244, 248)
    for y in 0..<h { for x in 0..<w {
        let wave = sin(Double(x) * 0.13) * 1.6 + sin(Double(x) * 0.05 + 1) * 1.2, v = 1 - pow((Double(y) + 0.5 - Double(h) / 2 - wave * 0.5) / (Double(h) / 2 - 1), 2)
        let a = max(0, v) * min(1, Double(x) / 16, Double(w - x) / 16) + bayer4(x, y) * 0.3                      // dithered to three levels, like the DS's
        if a > 0.25 { p.set(x, y, argb(a > 0.8 ? 140 : a > 0.5 ? 100 : 60, c)) }
    } }
    return p
}

// MARK: - the course picture
private let routeHorizon: [Art: Int] = [.field: 24, .forest: 14, .mountain: 30, .beach: 20, .lake: 18, .town: 22, .cave: 0]
private func bayer4(_ x: Int, _ y: Int) -> Double { ([0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5][(y & 3) * 4 + (x & 3)] + 0.5) / 16 - 0.5 }
private func lerpRGB(_ a: UInt32, _ b: UInt32, _ k: Double) -> UInt32 {
    func f(_ s: UInt32) -> UInt8 { let u = Double(a >> s & 255), v = Double(b >> s & 255); return UInt8(max(0, min(255, (u + (v - u) * k).rounded()))) }
    return rgb(f(16), f(8), f(0))
}
/// The land at this light: dawn rosy, dusk warm, night blue and dim; overcast greyer and flatter.
private func graded(_ c: UInt32, _ tb: Int, _ grey: Bool) -> UInt32 {
    guard c >> 24 > 0 else { return c }
    var r = Double(c >> 16 & 255), g = Double(c >> 8 & 255), b = Double(c & 255)
    if grey { let l = 0.3 * r + 0.59 * g + 0.11 * b; (r, g, b) = ((r * 0.6 + l * 0.4) * 0.9, (g * 0.6 + l * 0.4) * 0.9, (b * 0.6 + l * 0.4) * 0.9 + 12) }
    switch tb {
    case 1: (r, g, b) = (r * 0.98 + 8, g * 0.86 + 2, b * 0.88 + 14)
    case 2: (r, g, b) = (r * 1.0 + 14, g * 0.78 + 4, b * 0.62)
    case 3: (r, g, b) = (r * 0.34 + 10, g * 0.4 + 16, b * 0.58 + 44)
    default: break
    }
    let q = { (v: Double) in UInt32(max(0, min(255, v))) }
    return c & 0xFF00_0000 | q(r) << 16 | q(g) << 8 | q(b)
}
/// Underground neither the sky nor the weather reaches: only a little dimmer at night.
private func caveLight(_ c: UInt32, _ tb: Int) -> UInt32 { tb == 3 && c >> 24 > 0 ? dim(c, 0.82) : c }
/// The sky, top to horizon, in 4 bands.
private func skyBands(_ tb: Int, _ grey: Bool) -> [UInt32] {
    if grey { return [[rgb(146, 156, 176), rgb(164, 174, 192), rgb(184, 192, 206), rgb(204, 210, 222)], [rgb(150, 144, 164), rgb(172, 162, 176), rgb(194, 182, 190), rgb(214, 202, 202)],
                      [rgb(144, 134, 150), rgb(168, 152, 158), rgb(192, 172, 170), rgb(212, 190, 180)], [rgb(40, 44, 62), rgb(50, 54, 74), rgb(62, 66, 86), rgb(76, 80, 100)]][tb] }
    return [[rgb(80, 150, 240), rgb(110, 176, 248), rgb(150, 204, 252), rgb(196, 230, 252)], [rgb(112, 124, 200), rgb(184, 150, 200), rgb(240, 170, 176), rgb(252, 210, 170)],
            [rgb(84, 84, 164), rgb(180, 100, 136), rgb(240, 134, 96), rgb(252, 190, 106)], [rgb(14, 22, 62), rgb(22, 34, 82), rgb(34, 50, 104), rgb(50, 70, 126)]][tb]
}
/// The sky down to the horizon (and on, for what stands in front): bands dithered where they meet, the sun low at dawn and dusk, the moon and stars at night.
private func skyPic(_ w: Int, _ h: Int, horizon hz: Int, _ tb: Int, _ grey: Bool, sun at: (Double, Double)?) -> Pic {
    var p = Pic(w: w, h: h); let c = skyBands(tb, grey), hz = max(8, hz)
    for y in 0..<h { for x in 0..<w { p.set(x, y, c[max(0, min(3, Int(Double(y) / Double(hz) * 4 + bayer4(x, y) * 0.6)))]) } }
    guard !grey, let at else { return p }
    let (sx, sy, r): (Double, Double, Double) = [(at.0, at.1, 4.5), (18, Double(hz) - 3, 6), (62, Double(hz) - 2, 7), (at.0, at.1 - 1, 4)][tb]
    let (core, rim) = [(rgb(255, 250, 214), rgb(255, 226, 120)), (rgb(255, 224, 190), rgb(252, 160, 130)), (rgb(255, 214, 140), rgb(250, 128, 72)), (rgb(248, 242, 208), rgb(214, 208, 176))][tb]
    for y in 0..<h { for x in 0..<w {
        let d = hypot(Double(x) + 0.5 - sx, Double(y) + 0.5 - sy)
        if tb == 3 { if d < r, hypot(Double(x) + 0.5 - sx - 2.2, Double(y) + 0.5 - sy + 1.2) > r - 1 { p.set(x, y, d > r - 1 ? rim : core) }; continue }   // a crescent
        if d < r { p.set(x, y, d > r - 1.2 ? rim : core) } else if d < r + 2.5, (x + y) % 2 == 0 || d < r + 1.2 { p.set(x, y, lerpRGB(p.at(x, y), core, 0.45)) }   // a dithered glow
    } }
    if tb == 3 { for k in 0..<22 { let x = hashXY(k, 9) % w, y = hashXY(k, 10) % max(1, hz - 2); if hypot(Double(x) - sx, Double(y) - sy) > r + 3 { p.set(x, y, k % 3 == 0 ? rgb(255, 255, 230) : rgb(170, 184, 224)) } } }
    return p
}
private func clouds(_ grey: Bool, _ tb: Int) -> [(w: Int, y: Int, at: Double, speed: Double)] {
    grey ? [(24, 8, 10, 1.6), (16, 15, 40, 1.1), (24, 11, 50, 1.3), (16, 7, 5, 0.9)] : tb == 3 ? [(24, 13, 20, 0.8)] : [(24, 8, 12, 1.4), (16, 14, 44, 1.0)]   // inside the frame
}
private func cloudPic(_ k: Int, _ tb: Int, _ grey: Bool) -> Pic {
    let (hi, lo): (UInt32, UInt32) = grey ? (tb == 3 ? (rgb(84, 88, 106), rgb(64, 68, 86)) : (rgb(228, 230, 236), rgb(180, 186, 200)))
        : [(rgb(255, 255, 255), rgb(206, 226, 248)), (rgb(255, 238, 236), rgb(236, 186, 200)), (rgb(255, 222, 196), rgb(228, 150, 146)), (rgb(78, 92, 138), rgb(56, 68, 112))][tb]
    var p = Pic(w: k == 0 ? 24 : 16, h: k == 0 ? 10 : 8)
    p.canopy(k == 0 ? [(6, 6.5, 4), (12.5, 5, 5), (18.5, 6.5, 4)] : [(4.5, 5, 3), (8.5, 4, 3.6), (12, 5.2, 3)], [0, lo, lo, hi, hi], line: false, cut: k == 0 ? 9 : 7)
    return p
}
private func skyGlintPic() -> Pic { Pic(["wWWw", "...."], ["w": argb(140, rgb(250, 254, 255)), "W": rgb(250, 254, 255)]) }
private func skyStarPic() -> Pic { Pic([".w..", "wWw.", ".w..", "...."], ["w": argb(170, rgb(220, 226, 255)), "W": rgb(255, 255, 240)]) }
private func foamPic(_ tb: Int, _ grey: Bool) -> Pic {
    var p = Pic(w: 80, h: 4); let c = graded(rgb(250, 252, 255), tb, grey)
    for x in 0..<80 { let y = 1 + Int((sin(Double(x) * 0.31) * 0.9 + sin(Double(x) * 0.11)).rounded()); p.set(x, max(0, y), c); if x % 3 != 0 { p.set(x, min(3, y + 1), argb(140, c)) } }
    return p
}
/// The picture's frame: a dark outline with rounded corners and a light inner rim, like the DS windows.
private func windowPic(_ w: Int, _ h: Int) -> Pic {
    var p = Pic(w: w, h: h); let o = rgb(52, 60, 72), i = rgb(250, 250, 246)
    for x in 0..<w { for y in [0, h - 1] { p.set(x, y, o) }; for y in [1, h - 2] { p.set(x, y, i) } }
    for y in 0..<h { for x in [0, w - 1] { p.set(x, y, o) }; for x in [1, w - 2] { p.set(x, y, i) } }
    for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] { p.set(x, y, 0) }
    for (x, y) in [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)] { p.set(x, y, o) }
    return p
}

// MARK: - palettes (darkest first: outline, shadow, mid, light, highlight)
private func leafRamp(_ s: Season, blossom: Bool = false) -> [UInt32] {
    switch s {
    case .spring: blossom ? [rgb(128, 60, 92), rgb(214, 124, 164), rgb(238, 164, 196), rgb(250, 200, 222), rgb(255, 232, 242)]
                          : [rgb(26, 74, 42), rgb(58, 138, 66), rgb(96, 178, 82), rgb(144, 208, 104), rgb(194, 232, 144)]
    case .summer: [rgb(18, 62, 40), rgb(40, 112, 58), rgb(62, 152, 72), rgb(102, 190, 86), rgb(158, 222, 118)]
    case .autumn: blossom ? [rgb(96, 44, 22), rgb(196, 110, 36), rgb(232, 158, 52), rgb(246, 198, 84), rgb(252, 230, 140)]
                          : [rgb(96, 36, 24), rgb(180, 66, 40), rgb(220, 104, 48), rgb(240, 154, 64), rgb(252, 204, 110)]
    case .winter: [rgb(52, 70, 80), rgb(96, 124, 124), rgb(196, 210, 222), rgb(232, 238, 246), rgb(255, 255, 255)]
    }
}
private func firRamp(_ s: Season) -> [UInt32] { s == .winter ? [rgb(20, 50, 48), rgb(40, 84, 72), rgb(62, 112, 88), rgb(92, 142, 108), rgb(130, 172, 132)] : [rgb(14, 48, 40), rgb(28, 88, 62), rgb(44, 120, 76), rgb(72, 156, 90), rgb(112, 188, 108)] }
/// Ground cover by season: shadow, mid, light, highlight.
private func grassRamp(_ s: Season) -> [UInt32] {
    switch s {
    case .spring: [rgb(70, 150, 72), rgb(104, 192, 88), rgb(136, 214, 104), rgb(178, 232, 138)]
    case .summer: [rgb(54, 134, 62), rgb(86, 174, 72), rgb(118, 198, 86), rgb(160, 222, 110)]
    case .autumn: [rgb(150, 118, 54), rgb(192, 158, 72), rgb(214, 184, 96), rgb(232, 208, 128)]
    case .winter: [rgb(170, 186, 210), rgb(208, 220, 236), rgb(234, 240, 250), rgb(252, 252, 255)]
    }
}
private let bark = [rgb(62, 40, 30), rgb(110, 72, 46), rgb(150, 102, 62), rgb(184, 136, 88)]
private let rockRamp = [rgb(70, 60, 60), rgb(118, 106, 100), rgb(158, 146, 134), rgb(196, 184, 166), rgb(224, 216, 198)]
private let snowWhite = rgb(250, 252, 255), snowShade = rgb(206, 218, 238)

// MARK: - drawing bits
private func pk(_ x: Int, _ y: Int) -> Int { (y + 512) << 10 | (x + 512) }
private extension Pic {
    /// A dark line round a shape (the pixels just outside it).
    mutating func outline(_ inside: Set<Int>, _ c: UInt32) {
        for k in inside { let x = k & 1023 - 512, y = k >> 10 - 512; for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !inside.contains(pk(x + dx, y + dy)) { set(x + dx, y + dy, c) } }
    }
    /// Every column from top(x) down to y1: body(x, y), the first row `rim` if given (a hill, a field, the sea).
    mutating func ridge(_ y1: Int, rim: UInt32? = nil, _ top: (Int) -> Int, _ body: (Int, Int) -> UInt32) {
        for x in 0..<w { let t = top(x); for y in stride(from: max(0, t), to: min(h, y1), by: 1) { set(x, y, y == t && rim != nil ? rim! : body(x, y)) } }
    }
    /// An oval, coloured by where each pixel sits: dx, dy -1 ... 1 across it, d 0 at the centre to 1 at the edge (nil = leave it).
    mutating func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: (Double, Double, Double) -> UInt32?) {
        for y in Int(cy - ry - 1)...Int(cy + ry + 1) { for x in Int(cx - rx - 1)...Int(cx + rx + 1) {
            let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry, d = (dx * dx + dy * dy).squareRoot()
            if d < 1, let v = c(dx, dy, d) { set(x, y, v) }
        } }
    }
    /// Round clusters lit from the top left (a canopy, a bush, a rock, a cloud), back to front: a tone by each pixel's lean to the light,
    /// a seam where a cluster's shaded rim lies over one behind it, an outline; rows from `cut` down left off (a flat base).
    mutating func canopy(_ balls: [(x: Double, y: Double, r: Double)], _ ramp: [UInt32], line: Bool = true, cut: Int = .max) {
        var inside = Set<Int>()
        let x0 = Int(balls.map { $0.x - $0.r }.min()!) - 1, x1 = Int(balls.map { $0.x + $0.r }.max()!) + 1
        let y0 = Int(balls.map { $0.y - $0.r }.min()!) - 1, y1 = min(cut - 1, Int(balls.map { $0.y + $0.r }.max()!) + 1)
        guard y0 <= y1 else { return }
        for y in y0...y1 { for x in x0...x1 {
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            guard let k = balls.lastIndex(where: { hypot(px - $0.x, py - $0.y) < $0.r }) else { continue }
            let b = balls[k], dx = (px - b.x) / b.r, dy = (py - b.y) / b.r, lean = -0.55 * dx - 0.83 * dy + 0.3 * bayer4(x, y)
            let seam = hypot(dx, dy) > 0.8 && lean < 0.1 && balls[..<k].contains { hypot(px - $0.x, py - $0.y) < $0.r - 0.5 }
            set(x, y, ramp[seam ? 1 : lean > 0.52 ? 4 : lean > 0.08 ? 3 : lean > -0.42 ? 2 : 1]); inside.insert(pk(x, y))
        } }
        if line { outline(inside, ramp[0]) }
    }
    /// A round tree standing on (x, y): a short trunk, a canopy of about radius r.
    mutating func tree(_ x: Double, _ y: Double, _ r: Double, _ ramp: [UInt32]) {
        let tw = r >= 5 ? 3 : 2, tx = Int(x) - tw / 2, cy = y - r * 1.3
        var trunk = Set<Int>()
        for yy in Int(cy + r * 0.6)..<Int(y) { for xx in tx..<tx + tw { set(xx, yy, xx == tx ? bark[3] : xx == tx + tw - 1 ? bark[1] : bark[2]); trunk.insert(pk(xx, yy)) } }
        outline(trunk, bark[0])
        canopy([(x + 0.05 * r, cy - 0.38 * r, 0.62 * r), (x - 0.44 * r, cy + 0.04 * r, 0.56 * r), (x + 0.46 * r, cy + 0.02 * r, 0.56 * r), (x - 0.02 * r, cy + 0.34 * r, 0.58 * r)], ramp)
    }
    /// A fir: tiers widening downwards, lit from the left, outlined; snow along each tier's top in winter.
    mutating func fir(_ cx: Int, _ top: Int, _ h: Int, _ ramp: [UInt32], snow: Bool) {
        var inside = Set<Int>(); let tiers = max(2, (h + 2) / 6), th = Double(h) / Double(tiers)
        for yy in 0..<h {
            let tier = min(tiers - 1, Int(Double(yy) / th)), r = Double(yy) - Double(tier) * th, half = Int(0.6 + Double(tier) * th * 0.42 + r * 0.62)
            for dx in -half...half {
                let side = Double(dx) / Double(max(1, half))
                var c = side < -0.3 ? ramp[3] : side < 0.35 ? ramp[2] : ramp[1]
                if r > th - 1.6, abs(dx) > half / 3 { c = ramp[1] }                                      // the tier's hem in shade
                if side < -0.5, r < th * 0.55 { c = ramp[4] }
                if snow, r < (side < 0 ? 2.2 : 1.4) { c = side < 0.4 ? snowWhite : snowShade }
                set(cx + dx, top + yy, c); inside.insert(pk(cx + dx, top + yy))
            }
        }
        for yy in top + h..<top + h + 2 { set(cx - 1, yy, bark[2]); set(cx, yy, bark[1]); inside.insert(pk(cx - 1, yy)); inside.insert(pk(cx, yy)) }
        outline(inside, ramp[0])
    }
    /// Mountains standing on y1, apexes ps: lit left of each ridge, shaded right, cracks, snow `snow` rows down from the apex, an outlined skyline.
    mutating func peaks(_ ps: [(x: Double, y: Double)], _ y1: Int, _ ramp: [UInt32], snow: Double, seed: Int) {
        for x in 0..<w {
            var top = Double(h), k = 0
            for (i, p) in ps.enumerated() { let d = Double(x) + 0.5 - p.x, v = p.y + abs(d) * (d < 0 ? 0.8 : 1.0) + Double(hashXY(x / 2, i, seed) % 3) * 0.4; if v < top { top = v; k = i } }
            let t = Int(top), p = ps[k]
            for y in stride(from: max(0, t), to: min(h, y1), by: 1) {
                let d = Double(x) + 0.5 - p.x - (Double(y) - p.y) * 0.22 + Double(hashXY(y / 2, k, seed) % 3) - 1, dep = Double(y) - p.y
                var c = d < 0 ? ramp[3] : ramp[2]
                if dep > 4, hashXY(x / 3, y / 3, seed) % 3 != 0, d < -2 ? (x + y) % 9 == 0 : d > 1 && (x - y + 900) % 7 == 0 { c = d < 0 ? ramp[2] : ramp[1] }   // rock facets
                if d < 0, d > -2, dep > 2 { c = ramp[4] }                                             // the ridge catches the light
                if dep < snow + 2 * sin(Double(x) * 0.6 + Double(seed)) + 1.2 * sin(Double(x) * 1.7) { c = d < 0 ? snowWhite : snowShade }
                set(x, y, y == t ? ramp[0] : c)
            }
        }
    }
    /// An HGSS house on the ground at y: a tiled roof (roof: outline, shade, mid, light) over a cream wall, windows, a door; returns the window panes (lit at night).
    mutating func house(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ roof: [UInt32], snow: Bool) -> [(Int, Int)] {
        let rh = h * 9 / 20, wall = [rgb(72, 64, 64), rgb(206, 194, 172), rgb(236, 228, 208), rgb(250, 246, 232)], top = y - h
        var inside = Set<Int>(), panes: [(Int, Int)] = []
        func put(_ px: Int, _ py: Int, _ c: UInt32) { set(px, py, c); inside.insert(pk(px, py)) }
        for yy in top + rh..<y { for xx in x..<x + w { put(xx, yy, yy == y - 1 ? wall[1] : xx >= x + w - 3 ? wall[1] : wall[2]) } }   // the wall, shaded on the right
        for r in 0..<rh {                                                                            // the roof, one tile row every 3 lines
            let inset = (rh - 1 - r) / 2, row = rh - 1 - r
            for xx in x - 1 + inset..<x + w + 1 - inset { put(xx, top + r, r == rh - 1 ? roof[1] : row % 3 == 0 ? roof[1] : snow && r < 3 ? (xx < x + w * 2 / 3 ? snowWhite : snowShade) : xx < x + w / 3 ? roof[3] : roof[2]) }
        }
        for yy in top - 2..<top + 1 { for xx in x + w - 7..<x + w - 4 { put(xx, yy, snow && yy == top - 2 ? snowWhite : xx == x + w - 5 ? roof[1] : wall[1]) } }   // a chimney
        let door = x + w / 2 - 2
        for yy in y - 7..<y - 1 { for xx in door..<door + 5 { set(xx, yy, xx == door || xx == door + 4 || yy == y - 7 ? wall[0] : xx == door + 3 ? rgb(116, 72, 46) : rgb(150, 98, 60)) } }
        set(door + 3, y - 4, rgb(240, 208, 96))
        for wx in [x + 3, x + w - 8] where abs(wx + 2 - (door + 2)) > 4 {                                  // windows: framed panes, a glint
            for yy in top + rh + 2..<top + rh + 7 { for xx in wx..<wx + 5 {
                let edge = xx == wx || xx == wx + 4 || yy == top + rh + 2 || yy == top + rh + 6
                set(xx, yy, edge ? wall[0] : xx == wx + 1 && yy == top + rh + 3 ? rgb(236, 248, 255) : rgb(104, 168, 228)); if !edge { panes.append((xx, yy)) }
            } }
        }
        outline(inside, wall[0])
        return panes
    }
}

/// The course's land (clear where the sky shows), far to near, in the season's colours, then the hour's light; lit windows and lamps stay bright at night.
private func scenePic(_ a: Art, _ s: Season, _ tb: Int, _ grey: Bool) -> Pic {
    var p = Pic(w: 84, h: 52), lights: [(Int, Int, UInt32)] = []
    let sky = skyBands(tb, grey), gr = grassRamp(s), lv = leafRamp(s), winter = s == .winter, hz = routeHorizon[a]!
    func far(_ c: UInt32, _ k: Double = 0.45) -> UInt32 { lerpRGB(c, tb == 3 ? rgb(170, 190, 220) : sky[3], k) }   // aerial haze on what's far
    func farRamp(_ r: [UInt32], _ k: Double = 0.35) -> [UInt32] { r.map { far($0, k) } }
    func tufts(_ y0: Int, _ y1: Int, _ c: UInt32, _ hi: UInt32, seed: Int) {                       // little "ʌ" grass marks in loose staggered rows
        for (r, y) in stride(from: y0, to: y1, by: 5).enumerated() { for x in stride(from: (r % 2) * 5 + hashXY(r, 0, seed) % 3, to: 84, by: 10) where hashXY(x, y, seed) % 3 != 0 {
            p.set(x, y, c); p.set(x - 1, y + 1, c); p.set(x + 1, y + 1, c); p.set(x, y + 1, hi)
        } }
    }
    func flowers(_ y0: Int, _ y1: Int, _ n: Int, seed: Int) {
        let cols = s == .spring ? [rgb(250, 150, 190), rgb(255, 255, 255), rgb(252, 220, 90)] : [rgb(238, 72, 64), rgb(252, 214, 64)]
        for k in 0..<n { let x = 2 + hashXY(k, 1, seed) % 80, y = y0 + hashXY(k, 2, seed) % max(1, y1 - y0), c = cols[k % cols.count]
            p.set(x, y - 1, c); p.set(x - 1, y, c); p.set(x + 1, y, c); p.set(x, y + 1, c); p.set(x, y, rgb(252, 236, 120)) }
    }
    func tallGrass(_ x0: Int, _ y0: Int, _ cols: Int, _ rows: Int) {                               // HGSS tall grass: rows of pointed blades, outlined
        let g = s == .winter ? [rgb(84, 112, 104), rgb(150, 178, 170), rgb(214, 226, 236), rgb(250, 252, 255)] : s == .autumn ? [rgb(96, 70, 30), rgb(170, 128, 50), rgb(206, 166, 70), rgb(236, 206, 118)] : [rgb(24, 84, 44), rgb(44, 136, 60), rgb(76, 176, 76), rgb(132, 214, 104)]
        let blade = Pic(["..o...o.", ".ohoo.ho", ".ollo.lo", "ollllolo", "olllmolm", "omlmmomm", "mmmmmmmm"], ["o": g[0], "m": g[1], "l": g[2], "h": g[3]])
        for r in 0..<rows { for c in 0..<cols - (r % 2) { p.paste(blade, x0 + c * 8 + (r % 2) * 4, y0 + r * 4) } }
    }
    switch a {
    case .field:
        p.ridge(hz + 8, rim: far(gr[3], 0.5), { x in hz - 4 - Int(2.5 * sin(Double(x) * 0.07 + 1) + 1.5 * sin(Double(x) * 0.23)) }) { _, _ in far(gr[1], 0.55) }   // far hills
        for (x, r) in [(5.0, 4.2), (13, 3.4), (61, 3.6), (70, 4.4), (79, 3.4)] { p.tree(x, Double(hz + 3), r, farRamp(s == .spring && x == 13 ? leafRamp(s, blossom: true) : lv, 0.25)) }
        p.ridge(52, rim: gr[3], { x in hz + 2 + (x < 20 || x > 58 ? 1 : 0) }) { x, y in y < hz + 7 ? gr[2] : (y + x / 16) % 6 == 0 ? gr[2] : gr[1] }
        tufts(hz + 6, 52, gr[0], gr[3], seed: 1)
        let path = [rgb(176, 142, 94), rgb(222, 194, 136), rgb(236, 214, 164)].map { winter ? lerpRGB($0, snowShade, 0.7) : $0 }
        for y in hz + 3..<52 {
            let k = Double(y - hz - 3), c = 44 - k * 0.42 + sin(k * 0.16) * 2.5, half = 1 + k * 0.3
            for x in Int(c - half)...Int(c + half) { p.set(x, y, x == Int(c - half) || x == Int(c + half) ? path[0] : Double(x) < c - half * 0.3 ? path[2] : path[1]) }
        }
        if s == .spring || s == .summer { flowers(hz + 8, 50, s == .spring ? 14 : 6, seed: 3) }
        tallGrass(52, 38, 4, 3)
        p.tree(10, 50, 8.5, s == .spring ? leafRamp(s, blossom: true) : lv)
    case .forest:
        for k in 0..<13 { let x = k * 7 + (k % 2) * 2 - 2, h = 18 + hashXY(k, 1) % 8; p.fir(x, hz + 16 - h, h, farRamp(firRamp(s), 0.4), snow: winter) }   // the far wood
        p.ridge(52, rim: lerpRGB(gr[1], gr[0], 0.3), { _ in hz + 16 }) { x, y in lerpRGB((y + x / 12) % 5 == 0 ? gr[1] : gr[0], rgb(20, 60, 40), winter ? 0.15 : 0.35) }   // the shaded floor
        for (x, h) in [(18, 22), (64, 26), (40, 18)] { p.fir(x, hz + 18 - h, h, firRamp(s), snow: winter) }
        for (x, y, rx) in [(30.0, 40.0, 7.0), (58, 44, 9), (44, 49, 6)] { p.oval(x, y, rx, rx / 3.5) { _, _, d in d < 0.7 ? gr[2] : lerpRGB(gr[1], gr[2], 0.5) } }   // sun through the leaves
        let trail = [rgb(120, 88, 56), rgb(170, 130, 86), rgb(196, 160, 110)].map { winter ? lerpRGB($0, snowShade, 0.7) : $0 }
        for y in hz + 17..<52 { let k = Double(y - hz - 17), c = 42 - k * 0.3 + sin(k * 0.3) * 2, half = 1 + k * 0.28
            for x in Int(c - half)...Int(c + half) { p.set(x, y, x == Int(c - half) || x == Int(c + half) ? trail[0] : Double(x) < c ? trail[2] : trail[1]) } }
        tufts(hz + 19, 52, lerpRGB(gr[0], rgb(20, 50, 30), 0.4), gr[2], seed: 4)
        p.tree(6, 48, 9, s == .autumn ? leafRamp(s, blossom: true) : lv); p.tree(78, 47, 8, lv)
        let cap = Pic([".rrr.", "rwrrr", "rrrwr", ".oso."], ["r": rgb(222, 58, 48), "w": rgb(250, 246, 236), "o": rgb(96, 60, 40), "s": rgb(238, 226, 206)])
        if !winter { p.paste(cap, 26, 44); p.paste(cap, 58, 46) }
    case .mountain:
        p.peaks([(12, 12), (46, 8), (78, 13)], 38, farRamp(rockRamp, 0.5), snow: 4, seed: 2)                                          // the far range, pale
        p.peaks([(28, 4), (64, 11)], 44, rockRamp, snow: winter ? 18 : 7, seed: 7)
        p.ridge(52, rim: gr[3], { x in 33 + Int(2 * sin(Double(x) * 0.12 + 2)) }) { x, y in (x + y * 3) % 9 == 0 ? gr[2] : gr[1] }       // green foothills
        let dirt = [rgb(118, 86, 58), rgb(170, 128, 86), rgb(206, 170, 118), rgb(226, 198, 148)].map { winter ? lerpRGB($0, snowShade, 0.75) : $0 }
        p.ridge(52, { x in 39 + Int(sin(Double(x) * 0.2)) }) { x, y in y < 41 + Int(sin(Double(x) * 0.2)) ? dirt[1] : hashXY(x, y, 6) % 9 == 0 ? dirt[2] : dirt[3] }   // a ledge, then the path
        p.ridge(42, rim: dirt[0], { x in 39 + Int(sin(Double(x) * 0.2)) }) { _, _ in dirt[1] }
        for (x, y, r) in [(8.0, 50.0, 5.0), (74, 48, 4), (58, 51, 2.6)] { p.canopy([(x - r * 0.3, y - r * 0.5, r * 0.8), (x + r * 0.35, y - r * 0.35, r * 0.7)], rockRamp, cut: Int(y)) }
    case .beach:
        let sea = (winter ? [rgb(58, 104, 168), rgb(76, 128, 190), rgb(100, 152, 206), rgb(160, 198, 228)] : [rgb(48, 120, 220), rgb(70, 150, 236), rgb(98, 178, 244), rgb(168, 220, 252)])
        p.ridge(36, { _ in hz }) { x, y in hashXY(x / 3, y, 8) % 11 == 0 ? sea[3] : sea[min(2, (y - hz) / 5)] }
        p.canopy([(70, 19.5, 4), (75, 19, 3)], farRamp(leafRamp(.summer), 0.3), cut: 20); p.ridge(21, { x in x >= 64 && x < 80 ? 20 : 99 }) { _, _ in far(rgb(236, 214, 156), 0.3) }   // an island far out
        let sand = [rgb(196, 166, 108), rgb(218, 190, 130), rgb(240, 220, 162), rgb(250, 238, 196)]
        p.ridge(52, { _ in 36 }) { x, y in y < 39 ? sand[1] : hashXY(x, y, 9) % 7 == 0 ? sand[1] : (x + y) % 11 == 0 ? sand[3] : sand[2] }
        for (x, y) in [(40, 44), (60, 48), (24, 49)] { p.set(x, y, rgb(248, 160, 160)); p.set(x + 1, y, rgb(252, 208, 200)) }
        var palm = Set<Int>()                                                                        // a palm leaning in from the left
        for k in 0..<30 { let f = Double(k) / 30, x = Int(8 + 9 * f * f), y = 51 - Int(f * 34)
            for dx in 0..<3 { p.set(x + dx, y, dx == 0 ? bark[3] : k % 3 == 0 ? bark[1] : bark[2]); palm.insert(pk(x + dx, y)) } }
        p.outline(palm, bark[0])
        let fr = leafRamp(.summer).map { winter ? lerpRGB($0, snowShade, 0.25) : $0 }, crown = (18.0, 16.0)          // evergreen
        for (ang, len) in [(-2.9, 13.0), (-2.2, 11.0), (-1.2, 9.0), (-0.4, 12.0), (0.25, 13.0)] {
            var leaf = Set<Int>()
            for i in 0..<Int(len * 2) { let d = Double(i) / 2, x = crown.0 + cos(ang) * d, y = crown.1 + sin(ang) * d + d * d * 0.045
                let px = Int(x), py = Int(y); p.set(px, py, fr[3]); p.set(px, py + 1, d < len * 0.7 ? fr[2] : fr[1]); leaf.insert(pk(px, py)); leaf.insert(pk(px, py + 1)) }
            p.outline(leaf, fr[0])
        }
        p.canopy([(17, 18, 1.8), (20, 18.5, 1.8)], [bark[0], bark[1], bark[1], bark[2], bark[3]])
    case .lake:
        p.ridge(hz + 6, rim: far(gr[3], 0.55), { x in hz - 3 - Int(3 * sin(Double(x) * 0.06 + 2)) }) { _, _ in far(gr[1], 0.6) }
        for k in 0..<12 { let x = 3 + k * 7 + hashXY(k, 2) % 3; k % 3 == 1 ? p.fir(x, hz - 4, 9, farRamp(firRamp(s), 0.35), snow: winter) : p.tree(Double(x), Double(hz + 5), 3.2, farRamp(lv, 0.3)) }
        let ice = winter, water = ice ? [rgb(172, 204, 232), rgb(196, 222, 244), rgb(222, 238, 250), rgb(250, 252, 255)] : [rgb(52, 116, 204), rgb(74, 146, 226), rgb(118, 182, 240), rgb(176, 222, 250)]
        p.ridge(42, { _ in hz + 5 }) { x, y in
            let k = y - hz - 5
            if ice { return (x * 3 + y * 7) % 29 == 0 || (x - y * 2) % 31 == 0 ? water[0] : k < 4 ? water[2] : water[1] }
            if k < 5, hashXY(x / 4, 1) % 3 == 0, y % 2 == 0 { return lerpRGB(water[1], lv[1], 0.35) }                              // the far wood mirrored
            return hashXY(x / 3, y, 11) % 13 == 0 ? water[3] : k < 3 ? water[2] : water[k < 10 ? 1 : 0]
        }
        if !ice { for (x, y) in [(58, 38), (70, 40)] { p.oval(Double(x), Double(y), 4, 1.6) { dx, _, d in d > 0.75 ? lv[1] : dx < -0.2 ? lv[3] : lv[2] } } }   // lily pads
        p.ridge(52, rim: gr[3], { x in 42 - Int(1.5 * sin(Double(x) * 0.1)) }) { x, y in (x + y * 2) % 7 == 0 ? gr[2] : gr[1] }
        tufts(45, 52, gr[0], gr[3], seed: 12)
        for k in 0..<7 { let x = 3 + k * 2 + k % 2, top = 30 + hashXY(k, 4) % 6                                       // reeds, cattails on some
            for y in top..<46 { p.set(x, y, winter ? rgb(150, 136, 104) : rgb(62, 118, 56)) }
            if k % 2 == 0 { for y in top..<top + 3 { p.set(x, y, rgb(124, 80, 46)); p.set(x + 1, y, rgb(96, 60, 36)) } } }
        p.canopy([(70, 47, 4.5), (75, 48, 3.5)], rockRamp, cut: 49)
    case .town:
        p.ridge(hz + 4, rim: far(gr[3], 0.5), { x in hz - 2 - Int(2 * sin(Double(x) * 0.09)) }) { _, _ in far(gr[1], 0.55) }
        for k in 0..<7 { p.tree(Double(k * 13 + 4), Double(hz + 4), 3.6, farRamp(lv, 0.3)) }
        p.ridge(52, { _ in hz + 12 }) { x, y in (x / 2 + y) % 8 == 0 ? gr[2] : gr[1] }
        let red = [rgb(96, 30, 26), rgb(168, 52, 40), rgb(214, 80, 58), rgb(238, 120, 88)], blue = [rgb(28, 46, 96), rgb(54, 88, 170), rgb(80, 122, 214), rgb(120, 164, 238)]
        let panes = p.house(6, 38, 28, 26, red, snow: winter) + p.house(50, 38, 28, 26, blue, snow: winter)
        if tb == 3 || tb == 2 { lights += panes.map { ($0.0, $0.1, $0.1 % 2 == 0 ? rgb(255, 230, 130) : rgb(255, 208, 96)) } }
        let pave = [rgb(150, 140, 128), rgb(206, 198, 182), rgb(226, 220, 206)].map { winter ? lerpRGB($0, snowShade, 0.6) : $0 }
        for y in 43..<52 { for x in 0..<84 { p.set(x, y, y == 43 ? pave[0] : (x + (y / 3) * 5) % 10 == 0 || y % 3 == 1 ? pave[1] : pave[2]) } }   // a paved street
        for x in stride(from: 1, to: 84, by: 4) where !(15...22).contains(x) && !(59...66).contains(x) {           // a white picket fence, open at the doors
            for y in 37..<42 { p.set(x, y, rgb(250, 248, 240)); p.set(x + 1, y, rgb(214, 206, 196)) }; p.set(x, 36, rgb(120, 110, 104)); p.set(x + 1, 36, rgb(120, 110, 104))
            p.set(x + 2, 38, rgb(236, 230, 220)); p.set(x + 3, 38, rgb(236, 230, 220)); p.set(x + 2, 40, rgb(214, 206, 196)); p.set(x + 3, 40, rgb(214, 206, 196)) }
        if s == .spring || s == .summer { flowers(35, 37, 8, seed: 5) }
        for y in 26..<43 { p.set(41, y, rgb(70, 74, 86)); p.set(42, y, rgb(120, 126, 140)) }                               // a street lamp
        p.fill(39, 23, 6, 3, rgb(70, 74, 86)); p.fill(40, 24, 4, 1, rgb(252, 244, 200))
        if tb == 3 { lights += [(40, 24, rgb(255, 250, 210)), (41, 24, rgb(255, 250, 210)), (42, 24, rgb(255, 250, 210)), (43, 24, rgb(255, 250, 210))] }
    case .cave:
        let wall = [rgb(40, 30, 30), rgb(78, 58, 50), rgb(108, 82, 66), rgb(138, 108, 84), rgb(166, 134, 104)]
        p.ridge(52, { _ in 0 }) { _, _ in wall[1] }
        for r in 0..<5 { for c in 0..<8 {                                                                 // the walls: rows of boulders, lit from the top left
            let x = Double(c * 12 + (r % 2) * 6 + hashXY(c, r, 15) % 4), y = Double(r * 9 + 3 + hashXY(c, r, 16) % 3), s = 6 + Double(hashXY(c, r, 17) % 3)
            p.canopy([(x, y, s), (x + s * 0.7, y + 1.5, s * 0.75)], wall)
        } }
        p.oval(42, 30, 17, 20) { _, _, d in d > 0.86 ? wall[1] : lerpRGB(rgb(20, 14, 18), wall[0], d * d) }                   // the passage on into the dark
        let floor = [rgb(96, 72, 56), rgb(142, 110, 82), rgb(170, 138, 104), rgb(194, 164, 126)]
        p.ridge(52, rim: floor[3], { x in 36 + Int(2 * cos(Double(x - 42) * 0.07)) }) { x, y in hashXY(x, y, 14) % 8 == 0 ? floor[1] : (x + y) % 9 == 0 ? floor[3] : floor[2] }
        for (x, len) in [(6, 12), (15, 7), (27, 5), (58, 6), (69, 11), (78, 7)] {                                                // stalactites
            var st = Set<Int>()
            for y in 0..<len { let half = Int(Double(len - y) / Double(len) * 3.2); for dx in -half...half { p.set(x + dx, y, dx < 0 ? wall[3] : dx == 0 ? wall[2] : wall[1]); st.insert(pk(x + dx, y)) } }
            p.outline(st, wall[0])
        }
        for (x, y, r) in [(20.0, 46.0, 4.0), (64, 44, 5), (34, 50, 2.5)] { p.canopy([(x - r * 0.3, y - r * 0.5, r * 0.8), (x + r * 0.35, y - r * 0.4, r * 0.7)], [wall[0], wall[1], wall[2], wall[3], wall[4]], cut: Int(y)) }
        let gem = Pic(["...o...", "..olo..", ".oolmo.", "oolhlmo", "olhlmmo", "ollmmmo", ".oommo."], ["o": rgb(40, 50, 110), "m": rgb(86, 110, 210), "l": rgb(130, 170, 240), "h": rgb(220, 240, 255)])
        p.paste(gem, 6, 38); p.paste(gem, 72, 33)
    }
    p.px = p.px.map { a == .cave ? caveLight($0, tb) : graded($0, tb, grey) }
    for (x, y, c) in lights { p.set(x, y, c) }
    return p
}

// MARK: - the battle backdrop
/// Pad colours by course and season: rim shadow (the pad's side), rim, top, highlight.
private func padRamp(_ a: Art, _ s: Season) -> [UInt32] {
    if s == .winter, a != .cave, a != .beach { return [rgb(150, 168, 196), rgb(196, 210, 230), rgb(226, 234, 246), rgb(246, 250, 255)] }
    switch a {
    case .mountain: return [rgb(150, 116, 84), rgb(192, 158, 116), rgb(218, 190, 146), rgb(236, 214, 176)]
    case .beach: return [rgb(196, 164, 108), rgb(224, 198, 140), rgb(242, 224, 172), rgb(250, 240, 204)]
    case .cave: return [rgb(118, 96, 80), rgb(156, 132, 110), rgb(184, 162, 138), rgb(206, 188, 164)]
    default:
        let g = grassRamp(s); return [lerpRGB(g[0], rgb(90, 80, 50), 0.2), g[1], g[2], g[3]]
    }
}
/// A pad: its side in shadow under a lit top, a darker rim, an inner ring, a highlight towards the light.
private func pad(_ p: inout Pic, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: [UInt32]) {
    let edge = lerpRGB(c[0], rgb(40, 40, 40), 0.3)
    p.oval(cx, cy + 3, rx, ry) { _, _, d in d > 0.94 ? edge : c[0] }
    p.oval(cx, cy, rx, ry) { dx, dy, d in
        if d > 0.94 { return edge }
        if d > 0.84 { return c[1] }
        if d > 0.66, d < 0.72 { return lerpRGB(c[1], c[2], 0.5) }
        return hypot(dx + 0.25, (dy + 0.3) * 1.2) < 0.42 + bayer4(Int(dx * rx), Int(dy * ry)) * 0.12 ? c[3] : c[2]
    }
}
/// Outdoors: the sky, the course's scenery pale on the horizon, a ground plane in soft bands, the pads. Low contrast, so the sprites and the HUD read.
private func stagePic(_ a: Art, _ s: Season, _ tb: Int, _ grey: Bool, _ W: Int, _ H: Int, _ pads: [(Double, Double, Double, Double)]) -> Pic {
    var p = Pic(w: W, h: H); let hz = Int(pads[0].1) - 22, sky = skyBands(tb, grey).map { tb == 3 ? $0 : lerpRGB($0, rgb(255, 255, 255), 0.3) }
    let haze = tb == 3 ? rgb(120, 140, 180) : sky[3], gr = grassRamp(s), lv = leafRamp(s)
    func far(_ c: UInt32, _ k: Double) -> UInt32 { lerpRGB(c, haze, k) }
    func farRamp(_ r: [UInt32], _ k: Double) -> [UInt32] { r.map { far($0, k) } }
    for y in 0..<H { for x in 0..<W { p.set(x, y, sky[max(0, min(3, Int(Double(y) / Double(max(8, hz)) * 4 + bayer4(x, y) * 0.6)))]) } }
    var ground = a == .mountain ? [rgb(200, 170, 128), rgb(214, 188, 146)] : a == .beach ? [rgb(236, 216, 164), rgb(244, 228, 184)] : a == .cave ? [rgb(160, 134, 110), rgb(174, 150, 124)] : [gr[1], gr[2]]
    if s == .winter, a != .beach, a != .cave { ground = [rgb(222, 230, 242), rgb(236, 242, 250)] }
    switch a {
    case .field, .town:
        p.ridge(hz + 4, rim: far(gr[3], 0.55), { x in hz - 10 - Int(4 * sin(Double(x) * 0.035 + 1) + 2 * sin(Double(x) * 0.1)) }) { _, _ in far(gr[1], 0.6) }
        for k in 0..<22 { p.tree(Double(k * 9 + hashXY(k, 5) % 5), Double(hz - 1), 2.6 + Double(hashXY(k, 6) % 2), farRamp(lv, 0.66)) }       // two rows of trees, the back one paler
        for k in 0..<16 { let x = Double(k * 13 + hashXY(k, 1) % 7); p.tree(x, Double(hz + 2), 3.5 + Double(hashXY(k, 2) % 4), farRamp(lv, 0.5)) }
        if a == .town { for k in 0..<4 { let x = 8 + k * 50 + hashXY(k, 3) % 12, w = 18 + hashXY(k, 4) % 8                                 // rooftops among them
            for r in 0..<7 { for xx in x + (6 - r) / 2..<x + w - (6 - r) / 2 { p.set(xx, hz - 10 + r, far(r == 6 ? rgb(150, 50, 40) : k % 2 == 0 ? rgb(214, 80, 58) : rgb(80, 122, 214), 0.5)) } }
            p.fill(x + 1, hz - 3, w - 2, 5, far(rgb(236, 228, 208), 0.4)); p.fill(x + w / 2 - 1, hz - 1, 3, 3, far(rgb(150, 98, 60), 0.4)) } }
    case .forest:
        for k in 0..<30 { let x = k * 7 + hashXY(k, 1) % 4 - 3, h = 24 + hashXY(k, 2) % 14; p.fir(x, hz + 2 - h, h, farRamp(firRamp(s), 0.55), snow: s == .winter) }
        for k in 0..<9 { let x = Double(k * 24 + hashXY(k, 3) % 9); p.tree(x, Double(hz + 3), 7 + Double(hashXY(k, 4) % 3), farRamp(lv, 0.42)) }
    case .mountain:
        p.peaks([(20, Double(hz - 34)), (70, Double(hz - 26)), (120, Double(hz - 38)), (176, Double(hz - 28))], hz + 2, farRamp(rockRamp, 0.55), snow: s == .winter ? 18 : 8, seed: 3)
    case .beach, .lake:
        let water = s == .winter && a == .lake ? [rgb(200, 222, 240), rgb(226, 238, 250)] : [rgb(96, 170, 240), rgb(150, 206, 250)]
        if a == .lake { p.ridge(hz - 6, rim: far(gr[3], 0.55), { x in hz - 14 - Int(3 * sin(Double(x) * 0.05)) }) { _, _ in far(gr[1], 0.6) }
            for k in 0..<18 { p.tree(Double(k * 11 + hashXY(k, 1) % 5), Double(hz - 6), 3 + Double(hashXY(k, 2) % 2), farRamp(lv, 0.5)) } }
        p.ridge(hz + 3, { _ in a == .lake ? hz - 6 : hz - 12 }) { x, y in hashXY(x / 4, y, 5) % 9 == 0 ? far(water[1], 0.1) : far(water[0], 0.35) }
    case .cave:
        let wall = [rgb(112, 88, 74), rgb(138, 112, 92), rgb(152, 126, 104), rgb(168, 142, 118), rgb(184, 160, 134)]
        p.fill(0, 0, W, hz + 2, wall[1])
        for r in 0...(hz + 2) / 14 { for c in 0..<10 {                                                 // pale boulders, like the course's cave
            let x = Double(c * 22 + (r % 2) * 11 + hashXY(c, r, 15) % 6), y = Double(r * 14 + 5 + hashXY(c, r, 16) % 4), sz = 9 + Double(hashXY(c, r, 17) % 4)
            p.canopy([(x, y, sz), (x + sz * 0.7, y + 2, sz * 0.75)], wall)
        } }
        for k in 0..<12 { let x = k * 17 + hashXY(k, 1) % 8, len = 8 + hashXY(k, 2) % 14
            for y in 0..<len { let half = Int(Double(len - y) / Double(len) * 4); for dx in -half...half { p.set(x + dx, y, dx < 0 ? wall[3] : wall[0]) } } }
    }
    for y in hz + 2..<H { let k = Double(y - hz) / Double(H - hz), band = Int((Double(y - hz)).squareRoot() * 1.7) % 2                 // bands widening towards us
        for x in 0..<W { p.set(x, y, far(ground[band == 0 || (hashXY(x, y, 3) % 5 == 0 && band == 1) ? 0 : 1], 0.4 * (1 - k))) } }
    for (k, (cx, cy, rx, ry)) in pads.enumerated() { pad(&p, cx, cy, rx, ry, padRamp(a, s).map { k == 0 ? lerpRGB($0, haze, 0.12) : $0 }) }
    p.px = p.px.map { a == .cave ? caveLight($0, tb) : graded($0, tb, grey) }
    return p
}
/// The Battle Tower's hall: panelled walls with a band of lights, a tiled floor running away to the back, lit platforms.
private func towerPic(_ W: Int, _ H: Int, _ pads: [(Double, Double, Double, Double)]) -> Pic {
    var p = Pic(w: W, h: H); let hz = Int(pads[0].1) - 24, vx = Double(W) / 2, vy = Double(hz) - 60
    for y in 0..<hz { for x in 0..<W {                                                              // the wall: a band of lights and their glow, panels, a blue stripe, a skirting
        let panel = x % 32, lamp = panel > 4 && panel < 28, wall = lerpRGB(rgb(226, 230, 246), rgb(204, 210, 234), Double(y) / Double(hz))
        let c: UInt32 = y < 3 ? rgb(170, 178, 208) : y < 8 ? (lamp ? (y == 3 ? rgb(255, 255, 250) : rgb(250, 246, 222)) : rgb(190, 198, 226)) : y < 13 && lamp && (x + y) % 2 == 0 && y < 13 - (x % 3) ? lerpRGB(wall, rgb(255, 252, 236), 0.6)
            : y >= hz - 6 ? (y == hz - 6 ? rgb(166, 174, 206) : rgb(186, 194, 222)) : (hz - 17..<hz - 13).contains(y) ? (y == hz - 17 ? rgb(236, 240, 252) : rgb(150, 170, 224))
            : panel == 0 ? lerpRGB(wall, rgb(150, 160, 196), 0.35) : panel == 1 ? rgb(238, 242, 252) : wall
        p.set(x, y, c)
    } }
    for y in hz..<H { for x in 0..<W {                                                              // tiles in perspective, lighter where the lights fall
        let d = Double(y) - vy, u = (Double(x) - vx) / d * 5, v = 400 / d, edge = abs(u - u.rounded()) < 0.04 * 5 * 60 / d / 5 || abs(v - v.rounded()) < 0.05
        let tile = (Int(floor(u)) + Int(floor(v))) % 2 == 0, lit = pads.contains { hypot((Double(x) - $0.0) / ($0.2 * 1.6), (Double(y) - $0.1) / ($0.3 * 2.4)) < 1 }
        var c = edge ? rgb(186, 192, 216) : tile ? rgb(226, 230, 242) : rgb(210, 216, 234)
        if lit { c = lerpRGB(c, rgb(255, 255, 255), 0.35) }
        p.set(x, y, c)
    } }
    for (cx, cy, rx, ry) in pads {
        p.oval(cx, cy + 3, rx, ry) { _, _, _ in rgb(96, 110, 156) }
        p.oval(cx, cy, rx, ry) { dx, dy, d in d > 0.9 ? rgb(120, 144, 206) : d > 0.8 ? rgb(236, 240, 250) : d > 0.72 ? rgb(170, 186, 228) : hypot(dx + 0.25, dy + 0.35) < 0.4 ? rgb(248, 250, 255) : rgb(230, 234, 246) }
    }
    return p
}
