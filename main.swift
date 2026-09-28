import AppKit
import UserNotifications

// MARK: - geometry (points; flipped view). All in device dots x PX, so the size menu scales everything.
var PX = CGFloat(max(2, UserDefaults.standard.integer(forKey: "px")))    // 2 / 3 / 4
let dev = (w: CGFloat(144), h: CGFloat(144))                                                  // a Poké Ball: 144-dot circle, screen where the button would be
var devSize: NSSize { NSSize(width: dev.w * PX, height: dev.h * PX) }
var lcdRect: NSRect { NSRect(x: 24 * PX, y: 40 * PX, width: 96 * PX, height: 64 * PX) }      // 96x64 dots, 4 greys, like the real one; centred on the ball
var buttons: [(c: NSPoint, r: CGFloat)] {   // left, enter, right on the white half following its curve; home tucked under enter
    [(NSPoint(x: 49 * PX, y: 120 * PX), 4.6 * PX), (NSPoint(x: 72 * PX, y: 123 * PX), 6 * PX), (NSPoint(x: 95 * PX, y: 120 * PX), 4.6 * PX), (NSPoint(x: 72 * PX, y: 136.5 * PX), 3.4 * PX)]
}

struct Shell { let name: String; let top: NSColor; var band = NSColor(white: 0.10, alpha: 1); var dex = 0; var bp = 0 }   // bp > 0: bought at the BP exchange   // top half, band; the bottom is always white. dex = Pokédex count to unlock
let shells: [Shell] = [
    Shell(name: "몬스터볼", top: NSColor(red: 0.89, green: 0.20, blue: 0.19, alpha: 1)),
    Shell(name: "슈퍼볼", top: NSColor(red: 0.22, green: 0.46, blue: 0.86, alpha: 1)),
    Shell(name: "하이퍼볼", top: NSColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)),
    Shell(name: "마스터볼", top: NSColor(red: 0.47, green: 0.27, blue: 0.66, alpha: 1)),
    Shell(name: "프리미어볼", top: NSColor(white: 0.97, alpha: 1), band: NSColor(red: 0.86, green: 0.20, blue: 0.18, alpha: 1), dex: 15),
    Shell(name: "럭셔리볼", top: NSColor(white: 0.13, alpha: 1), band: NSColor(red: 0.80, green: 0.16, blue: 0.14, alpha: 1), dex: 50),
    Shell(name: "배틀 골드", top: NSColor(red: 0.86, green: 0.68, blue: 0.24, alpha: 1), band: NSColor(white: 0.12, alpha: 1), bp: 40),
]
var theme = min(max(UserDefaults.standard.integer(forKey: "shell"), 0), shells.count - 1)
struct LCD { let name: String; let shades: [NSColor]; var color = false }   // shade 0 (blank) ... 3 (black); `color` = sprites in their HGSS colours
let lcds: [LCD] = [
    LCD(name: "컬러", shades: [(0.97, 0.96, 0.92), (0.80, 0.80, 0.76), (0.47, 0.49, 0.53), (0.12, 0.13, 0.16)].map { NSColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }, color: true),
    LCD(name: "원작", shades: [(0.78, 0.82, 0.72), (0.58, 0.63, 0.54), (0.35, 0.39, 0.33), (0.11, 0.13, 0.11)].map { NSColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }),
    LCD(name: "백라이트", shades: [(0.62, 0.80, 0.96), (0.42, 0.60, 0.82), (0.22, 0.34, 0.55), (0.05, 0.09, 0.20)].map { NSColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }),
]
var lcdStyle = min(max(UserDefaults.standard.integer(forKey: "lcd"), 0), lcds.count - 1)

// MARK: - pixels
/// The real Pokéwalker sprites (tools/gen.py): 493 x 2 frames x 64x48, 2 bpp.
let spriteData: Data = {
    guard let u = Bundle.main.url(forResource: "sprites", withExtension: "bin"), let d = try? Data(contentsOf: u), d.count == 493 * 2 * 768 else { return Data(count: 493 * 2 * 768) }
    return d
}()
func spriteShade(_ dex: Int, _ f: Int, _ x: Int, _ y: Int) -> UInt8 {
    let b = spriteData[((dex - 1) * 2 + f) * 768 + y * 16 + x / 4]
    return (b >> UInt8(6 - 2 * (x % 4))) & 3
}
/// The same sprites in colour (tools/gen.py): per species 15 normal + 15 shiny RGB, then 2 frames x 64x48 at 4 bpp; index 0 = transparent.
let colorData: Data = {
    guard let u = Bundle.main.url(forResource: "color", withExtension: "bin"), let d = try? Data(contentsOf: u), d.count == 493 * 3162 else { return Data(count: 493 * 3162) }
    return d
}()
/// 0 = transparent, else 0xFFRRGGBB.
func spriteColor(_ dex: Int, _ f: Int, _ x: Int, _ y: Int, shiny: Bool) -> UInt32 {
    let o = (dex - 1) * 3162, b = colorData[o + 90 + (f * 48 + y) * 32 + x / 2], i = Int(x % 2 == 0 ? b >> 4 : b & 15)
    guard i > 0 else { return 0 }
    let p = o + (shiny ? 45 : 0) + (i - 1) * 3
    return rgb(colorData[p], colorData[p + 1], colorData[p + 2])
}
func dim(_ c: UInt32, _ k: Double) -> UInt32 { rgb(UInt8(Double(c >> 16 & 255) * k), UInt8(Double(c >> 8 & 255) * k), UInt8(Double(c & 255) * k)) }
func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt32 { 0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }
/// Colour-LCD palettes for the hand-drawn bits, by shade 0...3.
let greens = [rgb(196, 232, 150), rgb(120, 200, 90), rgb(60, 150, 70), rgb(30, 80, 45)]
let ballPal = [rgb(250, 250, 250), rgb(250, 250, 250), rgb(222, 52, 44), rgb(30, 32, 40)]
let redPal = [UInt32](repeating: rgb(226, 48, 40), count: 4)
let gemPal = [rgb(250, 250, 250), rgb(250, 250, 250), rgb(80, 140, 235), rgb(30, 32, 40)]

/// Hand-drawn bits: " .:#" = shade 0...3, "_" = transparent.
func art(_ rows: [String]) -> [[UInt8?]] { rows.map { $0.map { c in c == "_" ? nil : UInt8(" .:#".firstIndex(of: c).map { " .:#".distance(from: " .:#".startIndex, to: $0) } ?? 0) } } }
let bush = art(["____:##:_____", "__:#:..:#____", "_#:..::..#:__", "#:.::..::.:#_", "#..:..::..:.#", "#.::..:..::.#", ":#..::..::.#:", "_:#:..::.:#:_", "__:##::##:___", "____#__#_____"])
let bang = art(["##", "##", "##", "##", "__", "##"])
let ball = art(["__###__", "_#:::#_", "#:::::#", "###.###", "#.....#", "_#...#_", "__###__"])
let foot = art(["_##_##", "_##_##", "______", "#####_", "######", "_####_"])
let gem = art(["_#_", "#:#", "_#_"])
let ballTilt = [art(["_###___", "#:::#__", "#::::#_", "##.####", "_#....#", "_#...#_", "__###__"]), art(["___###_", "__#:::#", "_#::::#", "####.##", "#....#_", "_#...#_", "__###__"])]
let burstArt = art(["#___#___#", "_#__#__#_", "__#___#__", "___###___", "###_#_###", "___###___", "__#___#__", "_#__#__#_", "#___#___#"])
let bubble = art(["_#########_", "#.........#", "#.........#", "#.........#", "#.........#", "#.........#", "#.........#", "_####.####_", "_____##____", "_____#_____"])
let emotes = [art(["__##_", "__#_#", "__#__", "###__", "###__"]), art(["_#_#_", "#####", "#####", "_###_", "__#__"]), art(["__#__", "__#__", "__#__", "_____", "__#__"])]   // ♪ ♥ !
let eggArt = art(["__###__", "_#...#_", "#.....#", "#..:..#", "#.....#", "#.:..:#", "#.....#", "_#...#_", "__###__"])
let eggCrack = art(["__###__", "_#...#_", "#..#..#", "#.#.#.#", "##...##", "#.:..:#", "#.....#", "_#...#_", "__###__"])
let eggPal = [rgb(252, 250, 240), rgb(252, 250, 240), rgb(120, 190, 110), rgb(40, 44, 52)]
let legendDex = Set(courses.flatMap(\.legends))
let spark = art(["__#__", "__#__", "##:##", "__#__", "__#__"])
let sparkPal = [rgb(255, 236, 120), rgb(255, 236, 120), rgb(255, 250, 200), rgb(250, 190, 40)]
let pip = (full: art(["###", "###", "###"]), empty: art(["###", "# #", "###"]))

/// Galmuri (OFL, a pixel font drawn after the Nintendo DS system font) at its native sizes, so every glyph lands on whole dots.
let fontsReady: Bool = {
    for f in ["Galmuri9", "Galmuri7"] { if let u = Bundle.main.url(forResource: f, withExtension: "ttf") { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) } }
    return true
}()
var textCache: [String: [[Bool]]] = [:]
/// 11 rows (Galmuri9 10 px) or, small, 9 rows (Galmuri7 8 px); baseline one row up from the bottom.
@MainActor func textDots(_ s: String, small: Bool = false) -> [[Bool]] {
    let key = (small ? "s|" : "m|") + s
    if let t = textCache[key] { return t }
    _ = fontsReady
    let size: CGFloat = small ? 8 : 10, h = small ? 9 : 11
    let font = NSFont(name: small ? "Galmuri7" : "Galmuri9", size: size) ?? .systemFont(ofSize: size)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]))
    let w = max(1, Int(ceil(CTLineGetTypographicBounds(line, nil, nil, nil))))
    var px = [UInt8](repeating: 0, count: w * h)
    px.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        ctx.setShouldAntialias(false); ctx.setShouldSmoothFonts(false); ctx.setFillColor(gray: 1, alpha: 1)
        ctx.textPosition = CGPoint(x: 0, y: 1); CTLineDraw(line, ctx)
    }
    let t = (0..<h).map { y in (0..<w).map { px[y * w + $0] > 127 } }
    textCache[key] = t; return t
}
/// LCD text: smooth system-font text laid over the dot screen (default), or the old dot font. Sprites, pictures, icons stay dots either way.
var smoothText = UserDefaults.standard.object(forKey: "smoothText") as? Bool ?? true
@MainActor func lcdFont(_ small: Bool) -> NSFont { .systemFont(ofSize: (small ? 6.5 : 8) * PX, weight: small ? .regular : .medium) }
/// A string's width in LCD dots, in whichever text style is on (layout, centring and tap targets all use this).
@MainActor func textWidth(_ s: String, small: Bool = false) -> Int {
    smoothText ? Int(ceil((s as NSString).size(withAttributes: [.font: lcdFont(small)]).width / PX)) : (textDots(s, small: small).first?.count ?? 0)
}
struct TextRun: Equatable { var s: String; var x, y, w, rows: Int; var small: Bool; var shade: UInt8 }

/// 을/를, 이/가, 은/는 by the last syllable's final consonant.
func josa(_ w: String, _ with: String, _ without: String) -> String {
    guard let u = w.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(u) else { return w + without }
    let jong = (u - 0xAC00) % 28
    return w + (jong != 0 && !(with == "으로" && jong == 8) ? with : without)                    // ㄹ takes 로, not 으로
}

@MainActor struct FB {
    var px = [UInt8](repeating: 0, count: 96 * 64)
    var col = [UInt32](repeating: 0, count: 96 * 64)                      // colour LCD only: 0 = use the shade
    var runs: [TextRun] = [], flips: [[Int]] = []                        // smooth text to draw over the dots, and the inverted boxes it may sit in
    mutating func set(_ x: Int, _ y: Int, _ s: UInt8, _ c: UInt32 = 0) { if (0..<96).contains(x), (0..<64).contains(y) { px[y * 96 + x] = s; col[y * 96 + x] = c } }
    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ s: UInt8) { for yy in y..<y + h { for xx in x..<x + w { set(xx, yy, s) } } }
    mutating func draw(_ a: [[UInt8?]], _ x: Int, _ y: Int, _ pal: [UInt32]? = nil, scale k: Int = 1) {
        for (dy, r) in a.enumerated() { for (dx, s) in r.enumerated() { if let s { for i in 0..<k * k { set(x + dx * k + i % k, y + dy * k + i / k, s, pal?[Int(s)] ?? 0) } } } }
    }
    /// Large = 64x48; small = 32x24, each dot the darkest of its 2x2 (and that dot's colour). Grey shade 0 is see-through; in colour the white body isn't.
    mutating func mon(_ m: Mon, _ f: Int, _ x: Int, _ y: Int, small: Bool = false, flip: Bool = false, flash: Bool = false, tint: (UInt8, UInt32)? = nil) {   // flash = red silhouette (the ball's beam); tint = any silhouette
        let k = small ? 2 : 1, shiny = m.shiny == true
        for sy in 0..<48 / k { for sx in 0..<64 / k {
            var s: UInt8 = 0, c: UInt32 = 0
            for yy in 0..<k { for xx in 0..<k {
                let v = spriteShade(m.dex, f, sx * k + xx, sy * k + yy), vc = spriteColor(m.dex, f, sx * k + xx, sy * k + yy, shiny: shiny)
                if v > s || c == 0 && v == s { s = v; if vc != 0 { c = vc } }
                if c == 0 { c = vc }
            } }
            let X = x + (flip ? 64 / k - 1 - sx : sx), Y = y + sy
            if s > 0 || c != 0, (0..<96).contains(X), (0..<64).contains(Y) {
                if let (s, c) = tint ?? (flash ? (2, rgb(238, 84, 72)) : nil) { px[Y * 96 + X] = s; col[Y * 96 + X] = c } else { if s > 0 { px[Y * 96 + X] = s }; col[Y * 96 + X] = c }
            }
        } }
    }
    /// Too wide for the screen => the small font, one row lower so baselines match.
    @discardableResult mutating func text(_ s: String, _ x: Int, _ y: Int, _ shade: UInt8 = 3, center: Bool = false, right: Bool = false, small: Bool = false) -> Int {
        if smoothText {
            var sm = small, w = textWidth(s, small: small)
            if !small, w > 94 { sm = true; w = textWidth(s, small: true) }
            let x0 = center ? (96 - w) / 2 : right ? x - w : x
            runs.append(TextRun(s: s, x: x0, y: y, w: w, rows: small ? 9 : 11, small: sm, shade: shade)); return w
        }
        var t = textDots(s, small: small), y = y + (small ? 1 : 0)
        if !small, (t.first?.count ?? 0) > 94 { t = textDots(s, small: true); y += 1 }
        let w = t.first?.count ?? 0, x0 = center ? (96 - w) / 2 : right ? x - w : x
        for (dy, r) in t.enumerated() { for (dx, on) in r.enumerated() where on { set(x0 + dx, y + dy, shade) } }
        return w
    }
    /// Rain streaks, drifting snow, fog bands over a w x h box (the course picture, the battle stage).
    mutating func weatherFX(_ wx: Weather, _ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ t: Double, cave: Bool = false) {
        let f = Int(t * 10)
        for y in 0..<h { for x in 0..<w {
            let (X, Y) = (x0 + x, y0 + y)
            switch wx {
            case .rain: if (x * 7 + (y - f * 2 + 1000) + x / 3 * 5) % 11 == 0, (x + y) % 3 != 0 { set(X, Y, 2, rgb(80, 130, 220)) }
            case .snow: if (UInt32(truncatingIfNeeded: (x + (y + f / 3) / 4 % 2) &* 73_856_093) ^ UInt32(truncatingIfNeeded: (y - f / 2 + 10_000) &* 19_349_663)) % 41 == 0 { set(X, Y, 1, px[Y * 96 + X] == 0 && col[Y * 96 + X] == 0 ? rgb(150, 176, 214) : rgb(252, 252, 255)) }   // blue-grey on the bare screen, white on pictures   // hashed flakes, falling and swaying
            case .fog: if (y + f / 6) % 6 == 0, (x + y * 3 + f / 3) % 3 != 0 { set(X, Y, 1, cave ? rgb(150, 144, 150) : rgb(206, 210, 218)) }
            case .sunny: break
            }
        } }
    }
    mutating func invert(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { flips.append([x, y, w, h]); for yy in y..<y + h { for xx in x..<x + w where (0..<96).contains(xx) && (0..<64).contains(yy) { px[yy * 96 + xx] = 3 - px[yy * 96 + xx]; col[yy * 96 + xx] = 0 } } }
    /// 32x24 picture of the course, framed.
    mutating func course(_ a: Art, _ x: Int, _ y: Int, weather w: Weather = .sunny, t: Double = 0, hour: Double = 12, season: Season = .summer) {
        // colour: sky above the course's horizon, its ground/water below
        let horizon = [Art.field: 14, .forest: 17, .mountain: 19, .beach: 10, .lake: 12, .town: 19, .cave: 0][a]!
        let grey = w == .rain || w == .fog || w == .snow && a != .cave
        // game clock: dawn 4-6, day, dusk 17-20, night 20-4 (as for evolutions); overcast greys the sky and hides the sun / moon
        let night = hour < 4 || hour >= 20, dawn = (4..<6).contains(hour), dusk = (17..<20).contains(hour)
        let clear = night ? rgb(34, 44, 92) : dawn ? rgb(250, 196, 170) : dusk ? rgb(248, 150, 104) : rgb(160, 208, 250)
        let orb = night ? rgb(236, 232, 196) : dusk || dawn ? rgb(255, 120, 70) : rgb(255, 222, 96)
        let sky = [grey ? (night ? rgb(70, 76, 92) : rgb(172, 182, 196)) : clear, grey ? (night ? rgb(80, 86, 100) : rgb(200, 204, 212)) : orb, rgb(70, 150, 80), rgb(36, 44, 56)]
        let ground: [UInt32] = switch a {
        case .field, .forest, .town: [rgb(130, 204, 96), rgb(100, 180, 80), rgb(70, 150, 64), rgb(36, 80, 44)]
        case .mountain: [rgb(186, 156, 112), rgb(160, 130, 96), rgb(128, 100, 72), rgb(60, 44, 36)]
        case .beach, .lake: [rgb(96, 170, 240), rgb(80, 150, 230), rgb(96, 170, 96), rgb(40, 90, 180)]
        case .cave: [rgb(90, 76, 70), rgb(110, 96, 88), rgb(128, 108, 96), rgb(40, 32, 30)]
        }
        func p(_ dx: Int, _ dy: Int, _ s: UInt8) {
            guard (0..<32).contains(dx), (0..<24).contains(dy) else { return }
            var c = (dy < horizon ? sky : ground)[Int(s)]
            let green = [.field, .forest, .town].contains(a)
            switch season {                                                                                   // the land by season
            case .spring: if green, dy >= horizon, s == 2, (dx + dy) % 3 == 0 { c = rgb(244, 150, 190) }         // flowers
            case .autumn:
                if green, dy >= horizon { c = [rgb(214, 178, 96), rgb(196, 150, 72), rgb(170, 112, 50), rgb(90, 60, 30)][Int(s)] }
                if a == .forest, dy < horizon, s == 2 { c = (dx + dy) % 2 == 0 ? rgb(222, 120, 48) : rgb(200, 70, 40) }   // red and orange trees
            case .winter:
                if green || a == .mountain, dy >= horizon { c = [rgb(246, 248, 252), rgb(226, 232, 242), rgb(198, 208, 222), rgb(110, 120, 140)][Int(s)] }   // snow cover
                if a == .forest, dy < horizon, s == 2 { c = dy % 3 == 0 ? rgb(240, 244, 250) : rgb(52, 100, 76) }   // snow on the firs
                if a == .mountain, dy < horizon, s == 1 { c = rgb(236, 240, 246) }                                // white peaks
            case .summer: break
            }
            if night, dy >= horizon || a == .cave { c = dim(c, 0.55) }                                           // the ground darkens too
            if night, !grey, dy < horizon, s == 0, (dx * 7 + dy * 13) % 23 == 0 { c = rgb(250, 250, 220) }        // stars
            if a == .mountain, dy < horizon, s == 1 { c = rgb(150, 132, 118) }                                     // rock faces, not sun
            if a == .beach, dy >= 18 { c = [rgb(242, 222, 160), c, rgb(206, 176, 116), c][Int(s)] }                  // sand
            if a == .town, dy < horizon, s == 2 { c = rgb(210, 84, 70) }                                          // roofs
            set(x + dx, y + dy, s, c)
        }
        for dy in 0..<24 { for dx in 0..<32 { p(dx, dy, 0) } }
        func tree(_ cx: Int, _ top: Int) { for i in 0..<9 { for dx in -i / 2...i / 2 { p(cx + dx, top + i, i == 8 || abs(dx) == i / 2 ? 3 : 2) } }; p(cx, top + 9, 3); p(cx, top + 10, 3) }
        func peak(_ cx: Int, _ top: Int, _ h: Int) { for i in 0..<h { for dx in -i...i { p(cx + dx, top + i, abs(dx) == i ? 3 : (i < 3 ? 0 : 1)) } } }
        switch a {
        case .field:
            for dx in 0..<32 { p(dx, 14, 3) }; for dy in 15..<24 { for dx in 0..<32 where (dx * 3 + dy * 5) % 7 == 0 { p(dx, dy, 2) } }
            for dx in [4, 11, 18, 25] { p(dx, 15, 3); p(dx - 1, 16, 3); p(dx + 1, 16, 3) }
            for dy in 3..<7 { for dx in 23..<27 { p(dx, dy, 1) } }
        case .forest: tree(6, 5); tree(16, 2); tree(26, 6); for dx in 0..<32 { p(dx, 17, 3) }; for dy in 18..<24 { for dx in 0..<32 where (dx + dy) % 4 == 0 { p(dx, dy, 1) } }
        case .mountain: peak(10, 4, 15); peak(23, 8, 11); for dx in 0..<32 { p(dx, 19, 3) }; for dy in 20..<24 { for dx in 0..<32 where dx % 3 == dy % 3 { p(dx, dy, 2) } }
        case .beach, .lake:
            let water = a == .beach ? 10 : 12
            for dy in water..<24 { for dx in 0..<32 { p(dx, dy, a == .lake && (dx < 3 || dx > 28) ? 2 : ((dx + dy * 2) % 6 == 0 ? 3 : 1)) } }
            if a == .beach { for dy in 18..<24 { for dx in 0..<32 { p(dx, dy, (dx * 7 + dy) % 5 == 0 ? 2 : 0) } } }
            for dy in 2..<7 { for dx in 3..<8 where !(dy == 2 || dy == 6) || (dx > 3 && dx < 7) { p(dx, dy, 2) } }
        case .town:
            for (hx, hw) in [(3, 11), (17, 12)] {
                for i in 0..<5 { for dx in hx + 2 - i...hx + hw - 3 + i { p(dx, 6 + i, i == 4 || dx == hx + 2 - i || dx == hx + hw - 3 + i ? 3 : 2) } }
                for dy in 11..<19 { for dx in hx..<hx + hw { p(dx, dy, dx == hx || dx == hx + hw - 1 || dy == 18 ? 3 : 0) } }
                for dy in 14..<18 { p(hx + hw / 2, dy, 3); p(hx + hw / 2 + 1, dy, 3) }
            }
            for dx in 0..<32 { p(dx, 19, 3) }
        case .cave:
            for dy in 0..<24 { for dx in 0..<32 { p(dx, dy, (dx * 5 + dy * 3) % 7 == 0 ? 3 : 2) } }
            for dy in 6..<24 { for dx in 8..<24 { let ex = Double(dx) - 15.5, ey = Double(dy) - 24; if ex * ex / 64 + ey * ey / 324 < 1 { p(dx, dy, 3) } } }
        }
        weatherFX(w, x + 1, y + 1, 30, 22, t, cave: a == .cave)
        for dx in 0..<32 { p(dx, 0, 3); p(dx, 23, 3) }; for dy in 0..<24 { p(0, dy, 3); p(31, dy, 3) }
    }
}

// MARK: - notifications (macOS banners); each kind can be switched off in the menu
let notifyKinds = [("pet", "동료가 주워 온 것"), ("hatch", "알 부화"), ("grow", "진화 · 레벨(5의 배수)"), ("weather", "날씨 변화"), ("unlock", "해금 (코스 · 기기)")]
nonisolated(unsafe) var useOsascript = false                                                  // set once at launch, read on the main thread
func notifyOn(_ k: String) -> Bool { UserDefaults.standard.object(forKey: "notify.\(k)") as? Bool ?? true }
final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }
}

// MARK: - screens
var statusItem: NSStatusItem? = nil
let menuItems = ["포켓 레이더", "다우징", "커넥트", "트레이너 카드", "포켓몬 · 도구", "상자", "도감", "배틀 타워"]
indirect enum Screen {
    case home
    case menu(Int)
    case radar(bush: Int, cursor: Int, since: Date, chain: Int)        // "!" shows on `bush` from 1.5 s after `since`, for `radarWindow(chain)`
    case battle(Battle, sel: Int)                                      // sel = the menu row (공격 / 볼 / 도구 / 도망, or 공격 / 도구 / 교체 / 기권)
    case moves(Battle, sel: Int)                                       // picking one of the 4 moves
    case party(Battle, sel: Int)                                       // picking who to switch in
    case tower                                                         // the Battle Tower lobby
    case beats(Battle, [Beat], since: Date, from: Battle)              // one exchange playing out; `from` = HP before it
    case dowse(cursor: Int, prize: Int, tries: Int, hint: String?)
    case card(Int), bag(Int)
    case say([String], next: Screen, since: Date)                      // any button or 3 s
    case evolve(from: Mon, to: Mon, since: Date)                       // already applied to the state; this is the show
    case dex(Int)                                                      // index into the seen list
    case box(Int, act: Int?, confirm: Bool)                            // act = the ● menu's selection; confirm = "release?"
    case hatch(Mon, since: Date)                                       // already kept; this is the show
}

final class WalkerView: NSView {
    var state: Walk
    var screen = Screen.home
    var lastInput = Date(), lastStep = Date.distantPast, lastSave = Date(), levelled = false
    var boxByLevel = false
    var chainNote: String? = nil                                           // "+6W · 기력의조각" under "연쇄 3!"
    var usedItem = "몬스터볼"                                                // the potion / ball / revive the current beat names
    var towerRefs: [Int] = [], towerRun = false
    var sideOn = false                                                     // the battle side panel exists (not in --selftest): the LCD shows the stage only
    weak var side: SidePanel?                            // who's in the tower party (see Walk.party), and whether a run is on
    lazy var lastSeason = state.season
    var shown: FB? = nil                                                   // last composed frame; draw() only when it changes
    var emote: (kind: Int, until: Date)? = nil                             // ♪ ♥ ! bubble over the companion
    lazy var rewarded = dexCount                                           // dex count already celebrated (no fanfare for old progress)
    var dexCount: Int { (state.owned ?? []).count }
    var pressed: Int? = nil, pressedAt = Date()
    var rng = SystemRandomNumberGenerator()

    init(state: Walk) { self.state = state; super.init(frame: NSRect(origin: .zero, size: devSize)) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    static func counter() -> UInt32 {
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown].reduce(UInt32(0)) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }
    static func boot() -> Double { var tv = timeval(), n = MemoryLayout<timeval>.size; sysctlbyname("kern.boottime", &tv, &n, nil, 0); return Double(tv.tv_sec) }

    @objc func tick(_ sender: Any?) {
        let now = Date(), before = state.total
        if state.sync(counter: WalkerView.counter(), boot: WalkerView.boot(), at: now) { levelled = true }
        if state.total != before { lastStep = now }
        if state.season != lastSeason {
            lastSeason = state.season
            notify("weather", state.season.name + "이 왔어요", ["꽃이 피었어요", "햇볕이 쨍쨍해요", "단풍이 들었어요", "눈이 쌓여요"][state.season.rawValue] + " · 게임 속 \(seasonDays)일마다 계절이 바뀌어요")
            if case .home = screen { screen = .say([state.season.name + "이 왔다!"], next: .home, since: now) }
        }
        if state.weatherDue, state.rollWeather(&rng) {
            let w = state.weather ?? .sunny
            notify("weather", w.news, w.types.map { typeKo[$0] ?? $0 }.joined(separator: "·") + " 타입이 자주 나와요 · " + state.here.name)
            if case .home = screen { screen = .say([w.news], next: .home, since: now) }
        }
        if case .home = screen, state.eventDue {
            switch state.petEvent(&rng) {
            case .item(let item):
                screen = .say([josa(monNames[state.companion.dex], "이", "가") + " 무언가를", "주워왔다!", item], next: .home, since: now)
                notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 무언가를 주워왔어요", item)
            case .egg:
                screen = .say([josa(monNames[state.companion.dex], "이", "가") + " 무언가를", "주워왔다!", "포켓몬의 알"], next: .home, since: now)
                notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 알을 주워왔어요", "앞으로 \(state.egg?.left ?? 0)걸음 걸으면 태어나요")
            case nil: if state.total > 0 { emote = (Int.random(in: 0..<3, using: &rng), now.addingTimeInterval(3)) }
            }
        }
        if case .home = screen, state.hatchDue {
            let m = state.hatch(&rng); screen = .hatch(m, since: now); save(nil)
            notify("hatch", "알에서 " + josa(monNames[m.dex], "이", "가") + " 태어났어요!" + (m.shiny == true ? " ✦" : ""), m.shiny == true ? "이로치예요!" : "Lv.1 · 워커에 있어요")
        }
        if state.earned > unlockedAt {                                                           // lifetime watts opened a course
            let new = courses.enumerated().filter { $0.element.watts > unlockedAt && $0.element.watts <= state.earned && state.unlocked($0.offset) }.map(\.element.name)
            unlockedAt = state.earned
            if let n = new.first {
                notify("unlock", "새 코스가 열렸어요", n + " · 우클릭 → 코스")
                if case .home = screen { screen = .say(["새 코스 해금!", n], next: .home, since: now) }
            }
        }
        if case .home = screen, dexCount > rewarded {                                            // Pokédex milestones: event courses and two shells
            let got = courses.filter { (rewarded + 1...dexCount).contains($0.dex) }.map { $0.name + " 코스" } + shells.filter { (rewarded + 1...dexCount).contains($0.dex) }.map { $0.name + " 기기" }
            rewarded = dexCount
            if let g = got.first { screen = .say(["도감 \(dexCount)종 달성!", g + " 해금"] + got.dropFirst().prefix(1), next: .home, since: now); notify("unlock", "도감 \(dexCount)종 달성!", got.joined(separator: " · ") + " 해금") }
        }
        if levelled, case .home = screen {                                                    // shown when it's back home, not mid-menu
            levelled = false
            let name = monNames[state.companion.dex]
            if let e = state.levelEvolution(now) { startEvolving(e, now); notify("grow", "어라...? " + josa(name, "의", "의") + " 모습이...!", josa(name, "이", "가") + " " + josa(monNames[e.to], "으로", "로") + " 진화했어요!") }
            else {
                screen = .say(["레벨 업!", name + " Lv.\(state.companion.level)"], next: .home, since: now)
                if state.companion.level % 5 == 0 { notify("grow", "레벨 업!", name + " Lv.\(state.companion.level)") }
            }
        }
        switch screen {
        case .radar(_, _, let since, let chain) where now.timeIntervalSince(since) > 1.5 + radarWindow(chain):
            screen = .say(chain > 0 ? ["...!", "연쇄가 끊겼다 (\(chain))"] : ["...!", "사라져버렸다"], next: .home, since: now)
        case .beats(let bt, let beats, let since, _) where now.timeIntervalSince(since) >= beats.map(\.length).reduce(0, +):
            screen = beats.last!.ends ? after(bt, beats.last!, now) : .battle(bt, sel: 0)
        case .say(_, let next, let since) where now.timeIntervalSince(since) > 3: screen = next
        case .evolve(_, _, let since) where now.timeIntervalSince(since) > 6.5: screen = .home
        case .hatch(_, let since) where now.timeIntervalSince(since) > 5.5: screen = .home
        case .menu, .card, .bag, .dex, .box, .tower: if now.timeIntervalSince(lastInput) > 20 { screen = .home }
        default: break
        }
        if now.timeIntervalSince(lastSave) > 60 { save(nil) }
        updateStatus()
        side?.show(window?.isVisible == true ? sideModel(now) : nil, dex: window?.isVisible == true ? dexModel() : nil, beside: window)
        guard window?.isVisible ?? true else { return }                                         // hidden in the menu bar: rules keep running, nothing to draw
        let fb = compose(now)
        if fb.px != shown?.px || fb.col != shown?.col || fb.runs != shown?.runs || fb.flips != shown?.flips || now.timeIntervalSince(pressedAt) < 0.3 { shown = fb; needsDisplay = true }   // idle home = ~2 redraws a second
    }
    /// End of a fight. Wild: EXP goes to the companion; caught or beaten => maybe the grass rustles again (a chain). Tower: BP and the next trainer.
    func after(_ b: Battle, _ end: Beat, _ now: Date) -> Screen {
        if end == .lost, let r = state.useRevive() {                                              // a revive in the bag: back up, the fight goes on
            var nb = b; let from = b, hp = max(1, nb.mine[nb.me].maxHP * r.pct / 100); usedItem = r.item
            nb.apply(.revived(hp))                                                                 // the fight goes on from the revived HP (it used to stay at 0)
            return .beats(nb, [.revived(hp)], since: now, from: from)
        }
        let before = state.companion.level
        if b.trainer != nil { state.writeBack(towerRefs, b.mine.map(\.mon)) } else { state.companion = b.mine[0].mon }
        if state.companion.level > before { levelled = true }                                     // the home screen then checks evolutions
        if b.trainer != nil {
            if end == .won { let g = state.towerWin(); return .say(["\(state.towerStreak ?? 0)연승!", "+\(g) BP"], next: .tower, since: now) }
            let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false
            return .say(["\(s)연승에서 끝났다", "BP \(state.bp ?? 0)"], next: .home, since: now)
        }
        switch end {
        case .caught, .won:
            if end == .caught { _ = state.keep(b.wild) }
            guard Double.random(in: 0..<1, using: &rng) < Walk.chainGoesOn(b.chain) else {
                return .say(b.chain > 0 ? ["풀숲이 조용해졌다", "연쇄 \(b.chain)에서 끝"] : ["풀숲이", "조용해졌다"], next: .home, since: now)
            }
            let n = b.chain + 1, item = state.chainReward(n)
            chainNote = "+\(2 * n)W" + (item.map { " · " + $0 } ?? "")
            return .radar(bush: Int.random(in: 0..<4, using: &rng), cursor: 0, since: now, chain: n)
        default: return .home
        }
    }
    func startTower(_ now: Date) {
        let p = state.party(); towerRefs = p.map(\.ref)
        let f = state.towerFoes(&rng), b = Battle(party: p.map(\.mon), trainer: f.trainer, foes: f.foes)
        towerRun = true; screen = .beats(b, [.sendOut(.it, 0)], since: now, from: b)
    }
    func radarWindow(_ chain: Int) -> Double { max(0.8, 2.0 - 0.25 * Double(chain)) }
    var persist = true                                                     // false in --selftest: flows must never touch the real save (nor notify)
    lazy var unlockedAt = state.earned                                     // lifetime watts already announced
    func notify(_ kind: String, _ title: String, _ body: String) {
        guard persist, notifyOn(kind) else { return }
        if useOsascript {                                                                        // shows as "스크립트 편집기" in Notification Center
            func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "display notification \(q(body)) with title \(q("PokeWalker")) subtitle \(q(title))"]
            try? p.run(); return
        }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    @objc func save(_ sender: Any?) { guard persist else { return }; Store.save(state); lastSave = Date() }
    func startEvolving(_ e: Evo, _ now: Date) { let from = state.companion; state.evolve(e); screen = .evolve(from: from, to: state.companion, since: now); save(nil) }
    var seenList: [Int] { Array(Set((state.seen ?? []) + (state.owned ?? []))).sorted() }

    func press(_ k: Int) {                                    // 0 left, 1 enter, 2 right, 3 home
        let now = Date(); lastInput = now; defer { save(nil); shown = nil; needsDisplay = true }
        if k == 3 {                                           // home from anywhere; mid-battle it counts as running away (or giving up a tower fight)
            switch screen {
            case .beats: return
            case .moves(let b, _), .party(let b, _): screen = .battle(b, sel: 0)                    // back out of the sub-menu
            case .battle(let b, _) where b.trainer != nil: let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false; screen = .say(["기권했다", "\(s)연승에서 끝"], next: .home, since: now)
            case .battle: screen = .say(["무사히", "도망쳤다!"], next: .home, since: now)
            case .tower where towerRun: let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false; screen = .say(["타워를 나왔다", "\(s)연승 기록"], next: .home, since: now)
            default: screen = .home
            }
            return
        }
        let n = menuItems.count
        switch screen {
        case .home: screen = .menu(k == 0 ? n - 1 : 0)
        case .menu(let i):
            if k == 0 { screen = i == 0 ? .home : .menu(i - 1) }
            else if k == 2 { screen = i == n - 1 ? .home : .menu(i + 1) }
            else { open(i, now) }
        case .radar(let b, let c, let since, let chain):
            if k != 1 { screen = .radar(bush: b, cursor: (c + (k == 0 ? 3 : 1)) % 4, since: since, chain: chain); return }
            let u = now.timeIntervalSince(since)
            if c == b, u >= 1.5 {
                let s = state.encounter(&rng, chain: chain), l = state.legend(&rng, chain: chain)
                let m = Mon(dex: l ?? s.dex, level: l == nil ? s.level : l == 493 ? 80 : 50, female: l == nil ? s.female : Bool.random(using: &rng),
                            shiny: Int.random(in: 0..<Walk.chainShinyOdds(chain), using: &rng) == 0 ? true : nil)   // chains raise 이로치 odds too
                let b = Battle(wild: m, companion: state.companion, chain: chain); state.see(m.dex); screen = .beats(b, [.appear], since: now, from: b)
            } else { screen = .say(chain > 0 ? ["빗나갔다...", "연쇄 끝 (\(chain))"] : ["아무것도", "없었다..."], next: .home, since: now) }
        case .battle(var b, let sel):
            let opts = battleMenu(b), n = opts.count
            if k == 0 { screen = .battle(b, sel: (sel + n - 1) % n); return }
            if k == 2 { screen = .battle(b, sel: (sel + 1) % n); return }
            let from = b
            switch opts[sel] {
            case "공격": screen = .moves(b, sel: 0)
            case "교체": screen = .party(b, sel: b.me)
            case "기권": let s = state.towerStreak ?? 0; state.towerEnd(); towerRun = false; screen = .say(["기권했다", "\(s)연승에서 끝"], next: .home, since: now)
            case "도구":
                let f = b.mine[b.me]
                guard f.hp < f.maxHP else { screen = .say(["HP가 가득하다"], next: .battle(b, sel: sel), since: now); return }
                guard let h = state.useHeal(missing: f.maxHP - f.hp) else { screen = .say(["쓸 수 있는", "회복 도구가 없다"], next: .battle(b, sel: sel), since: now); return }
                usedItem = h.item; let beats = b.turn(.item, &rng, heal: h.hp); screen = .beats(b, beats, since: now, from: from)
            case "볼":
                var boost = 1.0; usedItem = "몬스터볼"
                if let x = state.useBall() { boost = x.boost; usedItem = x.item }
                let beats = b.turn(.capture, &rng, ball: boost); screen = .beats(b, beats, since: now, from: from)
            default: let beats = b.turn(.run, &rng); screen = .beats(b, beats, since: now, from: from)
            }
        case .moves(var b, let sel):
            let ms = b.mine[b.me].mon.moves
            if k == 0 { screen = .moves(b, sel: (sel + ms.count - 1) % ms.count) }
            else if k == 2 { screen = .moves(b, sel: (sel + 1) % ms.count) }
            else { let from = b; let beats = b.turn(.fight(ms[min(sel, ms.count - 1)]), &rng); screen = .beats(b, beats, since: now, from: from) }
        case .party(var b, let sel):
            let n = b.mine.count
            if k == 0 { screen = .party(b, sel: (sel + n - 1) % n) }
            else if k == 2 { screen = .party(b, sel: (sel + 1) % n) }
            else if sel == b.me { screen = .say(["이미 싸우고 있다"], next: .party(b, sel: sel), since: now) }
            else if !b.mine[sel].alive { screen = .say(["기절해서", "싸울 수 없다"], next: .party(b, sel: sel), since: now) }
            else { let from = b; let beats = b.turn(.swap(sel), &rng); screen = .beats(b, beats, since: now, from: from) }
        case .tower:
            guard k == 1 else { return }
            if towerRun { startTower(now) }
            else if state.spend(Walk.towerFee) { state.towerStreak = 0; startTower(now) }
            else { screen = .say(["W가 부족하다", "(\(Walk.towerFee)W 필요)"], next: .tower, since: now) }
        case .dowse(let c, let prize, let tries, _):
            if k != 1 { screen = .dowse(cursor: (c + (k == 0 ? 5 : 1)) % 6, prize: prize, tries: tries, hint: nil); return }
            if c == prize {
                let item = state.dowse(&rng)
                screen = .say(state.keep(item) ? [josa(item, "을", "를"), "찾았다!"] : [josa(item, "을", "를") + " 찾았다!", "가방으로 보냈다"], next: .home, since: now)
            } else if tries == 1 { screen = .say(["아무것도", "없었다..."], next: .home, since: now) }
            else { screen = .dowse(cursor: c, prize: prize, tries: 1, hint: abs(c - prize) == 1 ? "가깝다!" : "멀다...") }
        case .card(let p): screen = k == 1 ? .menu(3) : .card((p + (k == 0 ? 2 : 1)) % 3)
        case .bag(let p):
            let n = bagPages
            if k != 1 { screen = .bag((p + (k == 0 ? n - 1 : 1)) % n) }
            else if state.caught.indices.contains(p), p < n - 1 {                           // ● on a Pokémon: walk with it
                state.pair(p, onWalker: true)
                screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: .home, since: now)
            } else { screen = .menu(4) }
        case .say(_, let next, _): screen = next
        case .dex(let i): let n = max(1, seenList.count); screen = k == 1 ? .menu(6) : .dex((i + (k == 0 ? n - 1 : 1)) % n)
        case .box(let i, let act, let confirm):
            let n = max(1, state.box.count)
            if state.box.isEmpty { screen = .menu(5) }
            else if confirm {                                                                     // "놓아줄까?" 아니오 / 예
                if k != 1 { screen = .box(i, act: (act ?? 0) == 0 ? 1 : 0, confirm: true) }
                else if act == 1 { let name = monNames[state.box[i].dex], w = state.release(i); screen = .say([josa(name, "은", "는") + " 풀숲으로", "돌아갔다 (+\(w)W)"], next: .box(min(i, max(0, state.box.count - 1)), act: nil, confirm: false), since: now) }
                else { screen = .box(i, act: nil, confirm: false) }
            } else if let a = act {                                                              // 함께 걷기 / 놓아주기 / 정렬 / 취소
                if k != 1 { screen = .box(i, act: (a + (k == 0 ? 3 : 1)) % 4, confirm: false); return }
                switch a {
                case 0: state.pair(i); screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: .home, since: now)
                case 1: screen = .box(i, act: 0, confirm: true)
                case 2: boxByLevel.toggle(); state.sortBox(byLevel: boxByLevel); screen = .say([boxByLevel ? "레벨순으로" : "번호순으로", "정렬했다"], next: .box(0, act: nil, confirm: false), since: now)
                default: screen = .box(i, act: nil, confirm: false)
                }
            } else if k == 1 { screen = .box(i, act: 0, confirm: false) }
            else { screen = .box((i + (k == 0 ? n - 1 : 1)) % n, act: nil, confirm: false) }
        case .beats, .evolve, .hatch: break
        }
    }
    func open(_ i: Int, _ now: Date) {
        switch i {
        case 0: screen = state.spend(10) ? .radar(bush: Int.random(in: 0..<4), cursor: 0, since: now, chain: 0) : .say(["W가 부족하다", "(10W 필요)"], next: .menu(0), since: now)
        case 1: screen = state.spend(3) ? .dowse(cursor: 0, prize: Int.random(in: 0..<6), tries: 2, hint: nil) : .say(["W가 부족하다", "(3W 필요)"], next: .menu(1), since: now)
        case 2:
            let n = state.caught.count + state.items.count
            state.connect()
            if let e = state.tradeEvolution(now) { startEvolving(e, now); return }                 // Connect is the walker's link cable
            screen = .say(n == 0 ? ["보낼 것이", "없다"] : ["상자로", "\(n)개 보냈다"], next: .menu(2), since: now)
        case 3: screen = .card(0)
        case 4: screen = .bag(0)
        case 5: screen = .box(0, act: nil, confirm: false)
        case 7: screen = .tower
        default: screen = .dex(max(0, seenList.firstIndex(of: state.companion.dex) ?? 0))
        }
    }

    func compose(_ now: Date) -> FB {
        var fb = FB()
        let t = now.timeIntervalSinceReferenceDate, half = Int(t * 2) % 2, me = state.companion
        func header(_ title: String) { if fb.text(title, 2, 0) < 62 { fb.text("\(state.watts)W", 94, 1, 2, right: true, small: true) }; fb.fill(0, 12, 96, 1, 2) }   // long names win over the W
        switch screen {
        case .home:
            let f = now.timeIntervalSince(lastStep) < 3 ? half : Int(t) % 2        // steps coming in => walks twice as fast
            fb.mon(me, f, 32, 0)
            if let e = emote, now < e.until, Int(t * 3) % 3 != 0 { fb.draw(bubble, 32, 0, ballPal); fb.draw(emotes[e.kind], 35, 2, redPal) }
            fb.course(state.here.art, 1, 22, weather: state.weather ?? .sunny, t: t, hour: state.hour, season: state.season)
            fb.text("\(state.watts)W", 1, 1, 2, small: true)
            for i in 0..<state.caught.count { fb.draw(ball, 1 + 8 * i, 13, ballPal) }
            for i in 0..<state.items.count { fb.draw(gem, 26 + 4 * i, 15, gemPal) }
            fb.fill(0, 49, 96, 1, 2)
            fb.draw(foot, 2, 54)
            fb.text("Lv.\(me.level)", 11, 53, 2, small: true)
            if let e = state.egg { fb.draw(eggArt, 42 + (e.left < 500 && Int(t * 4) % 2 == 0 ? 1 : 0), 52, eggPal) }   // wobbles when it's close
            fb.text("\(state.today)", 94, 52, 3, right: true)
        case .menu(let i):
            fb.text("◀", 1, 26, 2); fb.text("▶", 95, 26, 2, right: true)
            fb.text(menuItems[i], 0, 20, center: true)
            let sub = [" 10W", " 3W", "상자로 보내기", "", "", "\(state.box.count)마리", "\(dexCount) / 493", "\(state.bp ?? 0)BP"][i]
            if !sub.isEmpty { fb.text(sub.trimmingCharacters(in: .whitespaces), 0, 34, 2, center: true) }
            fb.text("\(state.watts)W", 94, 1, 2, right: true, small: true)
            for k in 0..<menuItems.count { fb.fill(36 + 5 * k, 58, 3, 3, k == i ? 3 : 1) }
        case .radar(let b, let c, let since, let chain):
            let u = now.timeIntervalSince(since), live = (1.5...(1.5 + radarWindow(chain))).contains(u)
            if chain > 0, u < 1.5 { fb.text("연쇄 \(chain)!", 0, 13, 3, center: true); if let n = chainNote { fb.text(n, 0, 25, 2, center: true, small: true) } }   // between the bush rows
            for k in 0..<4 {
                let x = 14 + (k % 2) * 56, y = 8 + (k / 2) * 28, shake = live && k == b ? (half == 0 ? -1 : 1) : 0
                fb.draw(bush, x + shake, y, greens)
                if live && k == b && Int(t * 6) % 2 == 0 { fb.draw(bang, x + 15, y - 6, redPal) }
                if k == c { fb.text("▶", x - 2, y, 3, right: true) }
            }
        case .battle(let b, _) where sideOn, .moves(let b, _) where sideOn, .party(let b, _) where sideOn:
            stage(&fb, b, now, .idle, hud: false)                                                   // the side panel carries names, HP, menus
        case .beats where sideOn:
            let s = beatState(now)!
            stage(&fb, s.hp, now, pose(s.beat, s.u, s.hp), hud: false)
            if case .used(_, _, _, _, true) = s.beat, (0.45..<0.6).contains(s.u) { fb.invert(0, 0, 96, 64) }
            if s.beat == .appear, legendDex.contains(s.from.wild.dex), s.u < 0.5, Int(s.u * 10) % 2 == 0 { fb.invert(0, 0, 96, 64) }
        case .battle(let b, let sel):
            stage(&fb, b, now, .idle)
            let opts = battleMenu(b)
            for (k, r) in menuRanges(opts).enumerated() { fb.text(opts[k], r.lowerBound + 1, 52, 3, small: true); if k == sel { fb.invert(r.lowerBound, 52, r.count, 12) } }
        case .moves(let b, let sel):
            stage(&fb, b, now, .idle)
            let ms = b.mine[b.me].mon.moves, foe = b.theirs[b.it].mon.dex
            fb.fill(0, 37, 96, 27, 0); for y in 37..<64 { for x in 0..<96 { fb.col[y * 96 + x] = 0 } }; fb.fill(0, 37, 96, 1, 2)
            for (k, id) in ms.enumerated() {                                                          // 2 x 2: name, then ▲ super effective / ▼ not very / × none
                let m = moveTable[id]!, x = (k % 2) * 48, y = 39 + (k / 2) * 12, e = effectiveness(m.type, on: foe)
                let w = fb.text(m.name, x + 2, y, 3, small: true)
                fb.text(e == 0 ? "×" : e > 1 ? "▲" : e < 1 ? "▼" : "", x + 46, y, 2, right: true, small: true)
                if k == sel { fb.invert(x, y - 1, max(w + 3, 47), 11) }
            }
        case .party(let b, let sel):
            stage(&fb, b, now, .idle)
            fb.fill(0, 13, 96, 51, 0); for y in 13..<64 { for x in 0..<96 { fb.col[y * 96 + x] = 0 } }; fb.fill(0, 13, 96, 1, 2)
            for (k, f) in b.mine.enumerated() {
                let y = 16 + 15 * k
                fb.text((k == b.me ? "▶" : "") + monNames[f.mon.dex] + " Lv.\(f.mon.level)", 2, y, f.alive ? 3 : 1, small: true)
                hpBar(&fb, 2, y + 9, 60, f.hp, f.maxHP); fb.text("\(f.hp)/\(f.maxHP)", 94, y + 3, 2, right: true, small: true)
                if k == sel { fb.invert(0, y - 1, 96, 14) }
            }
        case .beats(_, let beats, let since, let from):
            var u = now.timeIntervalSince(since), i = 0
            while i < beats.count - 1, u >= beats[i].length { u -= beats[i].length; i += 1 }
            var hp = from                                                                        // who's out and their HP as of this moment
            for (k, bt) in beats.enumerated() where k < i { hp.apply(bt) }
            let names = hp                                                                       // names/sprites before this beat's HP lands
            if case .used = beats[i] { if u >= 0.45 { hp.apply(beats[i]) } } else if case .gained = beats[i] {} else { hp.apply(beats[i]) }
            stage(&fb, hp, now, pose(beats[i], u, hp))
            fb.text(message(beats[i], u, names), 2, 52)
            if case .used(_, _, _, _, true) = beats[i], (0.45..<0.6).contains(u) { fb.invert(0, 0, 96, 64) }   // critical: the whole screen flashes
            if beats[i] == .appear, legendDex.contains(from.wild.dex), u < 0.5, Int(u * 10) % 2 == 0 { fb.invert(0, 0, 96, 64) }   // a legend: two flashes first
        case .tower:
            fb.text("배틀 타워", 2, 0); fb.text("\(state.bp ?? 0)BP", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
            fb.text(towerRun ? "\(state.towerStreak ?? 0)연승 중 · 최고 \(state.towerBest ?? 0)" : "최고 \(state.towerBest ?? 0)연승", 2, 14, 2, small: true)
            for (k, p) in state.party().enumerated() { fb.text(monNames[p.mon.dex] + " Lv.\(p.mon.level)", 2, 24 + 9 * k, 3, small: true) }
            fb.fill(0, 51, 96, 1, 2)
            fb.text(towerRun ? "● 다음 상대  ⌂ 나가기" : "● 도전 \(Walk.towerFee)W", 0, 53, 3, center: true, small: true)
        case .dowse(let c, _, let tries, let hint):
            fb.text(hint ?? "어디에 있을까?", 0, 2, center: true)
            for k in 0..<6 { let x = 2 + 16 * k; fb.draw(bush, x, 28, greens); if k == c { fb.text("▼", x + 6, 16, 3, center: false) } }
            for k in 0..<tries { fb.draw(pip.full, 88 - 5 * k, 56) }
        case .card(let p):
            header(["트레이너 카드", "최근 7일", "알"][p])
            if p == 2 {
                if let e = state.egg {
                    fb.draw(eggArt, 40, 18, eggPal, scale: 2)
                    fb.text(e.left > 0 ? "앞으로 \(e.left)걸음" : "곧 태어난다!", 0, 52, 3, center: true)
                } else { fb.text("갖고 있지 않다", 0, 30, 2, center: true) }
            } else if p == 0 {
                fb.text(state.here.name, 2, 14)
                fb.text("오늘  \(state.today)걸음", 2, 26)
                fb.text("\(state.season.name) \(state.gameDay % seasonDays + 1)일째 · " + (state.hour < 4 || state.hour >= 20 ? "밤" : state.hour < 6 ? "새벽" : state.hour >= 17 ? "저녁" : "낮"), 2, 38)
                let w = state.weather ?? .sunny
                fb.text("날씨 \(w.name) · " + w.types.map { typeKo[$0] ?? $0 }.joined(separator: "·") + "↑", 2, 50, 2)
            } else {
                let days = Array(([state.today] + state.history).prefix(8)), top = max(1, days.max()!)
                for (k, v) in days.enumerated() { let h = v * 34 / top, x = 84 - 11 * k; fb.fill(x, 60 - h, 8, h, k == 0 ? 3 : 2); fb.fill(x, 61, 8, 1, 1) }
                fb.text("\(top)", 94, 23, 1, right: true, small: true)
                fb.text("합계 \(state.total)" + (state.bestChain.map { " · 최고 연쇄 \($0)" } ?? ""), 2, 14, 2, small: true)
            }
        case .bag(let p):
            let m = p < bagPages - 1 ? state.caught[safe: p] : nil
            header(m.map { ($0.shiny == true ? "★" : "") + monNames[$0.dex] + " Lv.\($0.level)" } ?? (p < bagPages - 1 ? "포켓몬" : "도구"))
            if p < bagPages - 1 {
                if let m {
                    fb.mon(m, half, 0, 14)
                    fb.text("\(p + 1)/\(state.caught.count)", 94, 15, 2, right: true, small: true)
                    fb.text("●", 80, 32, 3, center: false); fb.text("함께", 94, 42, 2, right: true, small: true); fb.text("걷기", 94, 51, 2, right: true, small: true)
                }
                else { fb.text("없음", 0, 30, 2, center: true) }
            } else {
                if state.items.isEmpty { fb.text("없음", 0, 30, 2, center: true) }
                for (k, it) in state.items.enumerated() { fb.draw(gem, 4, 18 + 12 * k, gemPal); fb.text(it, 12, 14 + 12 * k) }
            }
        case .dex(let i):
            let list = seenList, d = list[safe: i] ?? state.companion.dex, owned = (state.owned ?? []).contains(d)
            fb.text(String(format: "No.%03d ", d) + monNames[d], 2, 0)
            if owned { fb.draw(ball, 88, 2, ballPal) }
            fb.fill(0, 12, 96, 1, 2)
            let m = Mon(dex: d, level: 1, female: false)
            let shinyNow = (state.shinyOwned ?? []).contains(d) && Int(t / 2) % 2 == 1                        // caught as 이로치: both colours, 2 s each
            if owned { fb.mon(Mon(dex: d, level: 1, female: false, shiny: shinyNow ? true : nil), half, 0, 14) } else { fb.mon(m, 0, 0, 14, tint: (3, rgb(70, 74, 84))) }   // only seen: a shadow
            if shinyNow { fb.text("★이로치", 94, 32, 3, right: true, small: true) }
            fb.text(monTypes[d].map { typeKo[$0] ?? $0 }.joined(separator: "·"), 94, 16, 2, right: true, small: true)
            fb.text(owned ? "잡음" : "봤음", 94, 42, 2, right: true, small: true)
            fb.text("\(i + 1)/\(max(1, list.count))", 94, 52, 1, right: true, small: true)
        case .box(let i, let act, let confirm):
            guard let m = state.box[safe: i] else { header("상자"); fb.text("상자가 비어 있다", 0, 30, 2, center: true); break }
            header((m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)")
            fb.mon(m, half, 0, 14)
            fb.text("\(i + 1)/\(state.box.count)", 94, 15, 2, right: true, small: true)
            fb.text(m.female ? "암컷" : "수컷", 94, 26, 2, right: true, small: true)
            if let a = act {
                fb.fill(0, 50, 96, 14, 0); fb.fill(0, 50, 96, 1, 2)
                let opts = confirm ? ["놓아줄까?", "아니오", "예"] : ["함께", "놓아주기", "정렬", "닫기"]
                var x = 1
                for (k, o) in opts.enumerated() {
                    let w = fb.text(o, x + 1, 52, 3, small: true) + 2
                    if confirm ? k - 1 == a : k == a { fb.invert(x, 52, w, 11) }
                    x += w + 1
                }
            } else { fb.text("● 메뉴", 94, 52, 2, right: true, small: true) }
        case .hatch(let m, let since):
            let u = now.timeIntervalSince(since)
            if u < 2.6 {                                                                                    // the egg rocks, harder and harder, then cracks
                let k = u / 2.6, dx = Int(sin(u * (8 + 30 * k)) * (1 + 3 * k))
                fb.draw(u > 2.0 ? eggCrack : eggArt, 38 + dx, 12, eggPal, scale: 3)
                fb.text("어라...?", 0, 52, 3, center: true)
            } else if u < 2.9 { for y in 0..<50 { for x in 0..<96 { fb.set(x, y, 0, rgb(255, 255, 255)) } } }
            else {
                fb.mon(m, half, 16, 1)
                if m.shiny == true { for (k, (sx, sy)) in [(8, 6), (70, 10), (30, 2), (78, 34)].enumerated() where (Int(u * 4) + k) % 3 == 0 { fb.draw(spark, sx, sy, sparkPal) } }
                fb.text(josa(monNames[m.dex], "이", "가") + " 태어났다!", 2, 52)
            }
            fb.fill(0, 50, 96, 1, 2)
        case .evolve(let from, let to, let since):
            let u = now.timeIntervalSince(since)
            for y in 0..<50 { for x in 0..<96 { fb.set(x, y, 3, rgb(22, 26, 44)) } }                         // lights down
            if u < 1.2 { fb.mon(from, half, 16, 1) }
            else if u < 4.0 {                                                                                // flicker between the two shapes, faster and faster
                let k = (u - 1.2) / 2.8, phase = Int(pow(k, 2) * 40) % 2
                fb.mon(phase == 0 ? from : to, 0, 16, 1, tint: (0, rgb(255, 255, 255)))
            } else if u < 4.4 { fb.fill(0, 0, 96, 50, 0); for y in 0..<50 { for x in 0..<96 { fb.set(x, y, 0, rgb(255, 255, 255)) } } }
            else { fb.mon(to, half, 16, 1); for (k, (sx, sy)) in [(8, 6), (70, 10), (30, 2), (78, 34), (4, 30)].enumerated() where (Int(u * 4) + k) % 3 == 0 { fb.draw(spark, sx, sy, sparkPal) } }
            fb.fill(0, 50, 96, 1, 2)
            fb.text(u < 4.4 ? "어라...? " + josa(monNames[from.dex], "이", "가") + "...!" : josa(monNames[to.dex], "으로", "로") + " 진화했다!", 2, 52)
        case .say(let lines, _, _):
            for (k, l) in lines.enumerated() { fb.text(l, 0, 32 - lines.count * 7 + 14 * k, center: true) }
        }
        return fb
    }
    var bagPages: Int { max(1, state.caught.count) + 1 }
    /// Where a playing turn is right now: HP as of this moment, names before this beat's damage lands.
    func beatState(_ now: Date) -> (hp: Battle, names: Battle, beat: Beat, u: Double, from: Battle)? {
        guard case .beats(_, let beats, let since, let from) = screen else { return nil }
        var u = now.timeIntervalSince(since), i = 0
        while i < beats.count - 1, u >= beats[i].length { u -= beats[i].length; i += 1 }
        var hp = from
        for (k, bt) in beats.enumerated() where k < i { hp.apply(bt) }
        let names = hp
        if case .used = beats[i] { if u >= 0.45 { hp.apply(beats[i]) } } else if case .gained = beats[i] {} else { hp.apply(beats[i]) }
        return (hp, names, beats[i], u, from)
    }
    /// What the side panel shows; nil = no battle on (panel hidden).
    func sideModel(_ now: Date) -> SideModel? {
        let b: Battle, msg: String, mode: SideModel.Mode
        switch screen {
        case .battle(let x, let sel): b = x; msg = "무엇을 할까?"; mode = .menu(battleMenu(x), sel)
        case .moves(let x, let sel):
            b = x; msg = "어떤 기술을 쓸까?"
            mode = .moves(x.mine[x.me].mon.moves.map { id in let m = moveTable[id]!; return .init(name: m.name, type: m.type, power: m.power, effect: effectiveness(m.type, on: x.theirs[x.it].mon.dex)) }, sel)
        case .party(let x, let sel): b = x; msg = "누구로 교체할까?"; mode = .party(x.mine.enumerated().map { .init(name: monNames[$1.mon.dex], level: $1.mon.level, hp: $1.hp, max: $1.maxHP, out: $0 == x.me) }, sel)
        case .beats:
            guard let s = beatState(now) else { return nil }
            b = s.hp; msg = message(s.beat, s.u, s.names); mode = .none
        default: return nil
        }
        let foe = b.theirs[b.it], mine = b.mine[b.me]
        return SideModel(foe: .init(name: monNames[foe.mon.dex], level: foe.mon.level, hp: foe.hp, max: foe.maxHP, out: true), foeBalls: b.trainer == nil ? [] : b.theirs.map(\.alive),
                         mine: .init(name: monNames[mine.mon.dex], level: mine.mon.level, hp: mine.hp, max: mine.maxHP, out: true), myBalls: b.mine.count > 1 ? b.mine.map(\.alive) : [],
                         trainer: b.trainer, message: msg, mode: mode)
    }
    func evoText(_ e: Evo) -> String {
        let when = e.time.map { $0 == "day" ? "낮" : "밤" }, sex = e.female.map { $0 ? "♀" : "♂" }
        let place = e.place.map { ["cave": "동굴 코스", "forest": "숲 코스"][$0] ?? "얼음 산길" }
        switch e.way {
        case .level: let parts = [e.level > 0 ? "Lv.\(e.level)" : nil, when, sex, place, e.item.map { $0 + " 소지" }, e.party.map { monNames[$0] + " 보유" }].compactMap { $0 }; return parts.isEmpty ? "레벨 업" : parts.joined(separator: " · ")
        case .friend: return (["친밀도(함께 1만 걸음)"] + [when].compactMap { $0 }).joined(separator: " · ")
        case .item: return e.item! + " 사용" + (sex.map { " · " + $0 } ?? "")
        case .trade: return "커넥트(통신)" + (e.item.map { " · " + $0 + " 소지" } ?? "")
        }
    }
    /// What the side panel shows on the Pokédex screen; nil elsewhere.
    func dexModel() -> DexModel? {
        guard case .dex(let i) = screen else { return nil }
        let list = seenList, d = list[safe: i] ?? state.companion.dex
        let owned = Set(state.owned ?? []), seen = Set(list), st = owned.contains(d) ? 2 : seen.contains(d) ? 1 : 0
        var found: [String] = [], evos: [String] = []
        if st > 0 {
            for (ci, c) in courses.enumerated() {
                let tag = c.legends.contains(d) ? "전설" : c.slots.contains { $0.dex == d } ? "" : c.extra.contains { $0.dex == d } ? "추가" : c.guests.contains(d) ? "손님" : nil
                if let tag { found.append((state.unlocked(ci) ? "" : "🔒") + c.name + (tag.isEmpty ? "" : " (\(tag))")) }
            }
            if eggPool.contains(d) { found.append("알에서 부화") }
            if let l = Walk.legendShop.first(where: { $0.dex == d }) { found.append(l.watts > 0 ? "상점 · \(l.watts.formatted())W" : "BP 교환소 · \(l.bp)BP") }
            for e in evolutions where e.to == d { found.append(monNames[e.from] + "에서 진화") }
            if d == 292 { found.append("토중몬 → 아이스크 진화 때") }
            if found.count > 3 { let n = found.count - 2; found = Array(found.prefix(2)) + ["외 \(n)곳"] }
            let mine = evolutions.filter { $0.from == d }                                          // one line per target, its ways joined (리피아: 숲 코스 / 리프의돌)
            evos = mine.map(\.to).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.map { to in "→ " + monNames[to] + " · " + mine.filter { $0.to == to }.map(evoText).joined(separator: " / ") }
            if evos.count > 2 { let n = evos.count - 1; evos = [evos[0], "외 \(n)갈래"] }
        }
        let lo = max(1, min(484, d - 4)), strip = Array(lo..<(lo + 10))
        return DexModel(num: d, name: st > 0 ? monNames[d] : "???", status: st, shiny: (state.shinyOwned ?? []).contains(d), types: st > 0 ? monTypes[d] : [],
                        stats: st > 0 ? baseStats[d] : [], found: found, evos: evos, owned: owned.count, seen: seen.count,
                        strip: strip, stripStatus: strip.map { owned.contains($0) ? 2 : seen.contains($0) ? 1 : 0 })
    }
    func dexJump(_ n: Int) { if let i = seenList.firstIndex(of: n) { lastInput = Date(); screen = .dex(i); shown = nil } }
    func sidePick(_ k: Int) {                                                                   // a click on the side panel = selecting that row, then ●
        lastInput = Date()
        switch screen {
        case .battle(let b, _): screen = .battle(b, sel: k)
        case .moves(let b, _): screen = .moves(b, sel: k)
        case .party(let b, _): screen = .party(b, sel: k)
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
        func other(_ s: Side) -> Side { s == .me ? .it : .me }
        switch b {
        case .appear: return u < 0.6 ? .show(.it, dx: Int(-80 * pow(1 - u / 0.6, 2)), dy: 0, flash: false, visible: true) : .idle
        case .sendOut(let s, _): let k = pow(1 - min(1, u / 0.6), 2); return .show(s, dx: Int((s == .me ? 80 : -80) * k), dy: 0, flash: false, visible: true)
        case .used(let s, _, let d, _, _):
            if u < 0.45 { return .show(s, dx: Int((s == .me ? 18 : -18) * arc(0, 0.45)), dy: 0, flash: false, visible: true) }   // the dash
            return .show(other(s), dx: d > 0 && u < 0.85 ? shake : 0, dy: 0, flash: false, visible: d == 0 || u > 0.85 || blink)
        case .missed(let s, _):
            if u < 0.45 { return .show(s, dx: Int((s == .me ? 18 : -18) * arc(0, 0.45)), dy: 0, flash: false, visible: true) }
            return .show(other(s), dx: Int((s == .me ? -14 : 14) * arc(0.45, 0.45)), dy: 0, flash: false, visible: true)     // sidestep
        case .fainted(let s): return u < 0.35 ? .show(s, dx: 0, dy: 0, flash: false, visible: blink) : .show(s, dx: 0, dy: Int(60 * min(1, (u - 0.35) / 0.6)), flash: false, visible: true)
        case .thrown(let shakes):                                                                  // arcs in, swallows it, drops, rocks
            if u < 0.55 { let k = u / 0.55; return .ball(x: Int(80 - 39 * k), y: Int(34 - 28 * k) - Int(16 * sin(.pi * k)), tilt: nil, burst: false, stars: false) }
            if u < 0.8 { return Int(u * 20) % 2 == 0 ? .show(.it, dx: 0, dy: 0, flash: true, visible: true) : .ball(x: 41, y: 6, tilt: nil, burst: false, stars: false) }
            if u < 1.25 { let k = min(1, (u - 0.8) / 0.25); return .ball(x: 41, y: Int(6 + 24 * k * k) - Int(4 * arc(1.05, 0.15)), tilt: nil, burst: false, stars: false) }
            let w = u - 1.25; return .ball(x: 41, y: 30, tilt: w < 0.6 * Double(shakes) && w.truncatingRemainder(dividingBy: 0.6) < 0.3 ? Int(w / 0.6) % 2 : nil, burst: false, stars: false)
        case .caught: return .ball(x: 41, y: 30, tilt: nil, burst: false, stars: Int(u * 8) % 2 == 0)
        case .broke: return u < 0.25 ? .ball(x: 41, y: 30, tilt: nil, burst: true, stars: false) : .show(.it, dx: 0, dy: 0, flash: u < 0.4, visible: true)
        case .healed, .revived: return .show(.me, dx: 0, dy: Int(-4 * arc(0.2, 0.4)), flash: false, visible: u > 0.3 || blink)
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
        let lw = max(38, textWidth(monNames[foe.dex] + " \(foe.level)", small: true) + 2) + (b.trainer != nil ? 13 : 0)
        let rw = max(38, textWidth("\(monNames[mine.dex]) \(mine.level)", small: true) + 2)
        for (x0, w) in [(0, lw), (96 - rw, rw)] { for y in 0..<14 { for x in x0..<min(96, x0 + w) { fb.set(x, y, 0) } } }
        fb.text(monNames[foe.dex] + " \(foe.level)", 1, 0, 3, small: true)
        hpBar(&fb, 1, 9, 36, b.theirs[b.it].hp, b.theirs[b.it].maxHP)
        if b.trainer != nil { for (k, x) in b.theirs.enumerated() { fb.draw(gem, 39 + 4 * k, 9, x.alive ? ballPal : [ballPal[3], ballPal[3], ballPal[3], ballPal[3]]) } }
        fb.text("\(monNames[mine.dex]) \(mine.level)", 95, 0, 3, right: true, small: true)
        hpBar(&fb, 59, 9, 36, b.mine[b.me].hp, b.mine[b.me].maxHP)
        fb.fill(0, 50, 96, 1, 2)
    }
    func message(_ beat: Beat, _ u: Double, _ b: Battle) -> String {
        let it = monNames[b.theirs[b.it].mon.dex], me = monNames[b.mine[b.me].mon.dex], dots = String(repeating: ".", count: 1 + Int(u / 0.6))
        func who(_ s: Side) -> String { s == .me ? me : (b.trainer == nil ? "야생 " : "상대 ") + it }
        switch beat {
        case .appear:
            if b.wild.shiny == true && u < 0.9 { return "✦ 반짝! ✦" }
            return legendDex.contains(b.wild.dex) ? "전설의 " + it + " 등장!" : "야생 " + josa(it, "이", "가") + " 나타났다!"
        case .sendOut(.it, let i): return i == 0 && u < 0.7 ? (b.trainer ?? "") + "의 승부!" : "상대는 " + josa(monNames[b.theirs[i].mon.dex], "을", "를") + " 내보냈다"
        case .sendOut(.me, let i): return "가랏, " + monNames[b.mine[i].mon.dex] + "!"
        case .used(let s, let id, let d, let e, let crit):
            if u < 0.45 { return who(s) + "의 " + moveTable[id]!.name + "!" }
            if d == 0 || e == 0 { return "효과가 없는 것 같다..." }
            if crit && (e == 1 || u < 1.1) { return "급소에 맞았다!" }
            return e > 1 ? "효과가 굉장했다!" : e < 1 ? "효과가 별로인 듯하다..." : who(s) + "의 " + moveTable[id]!.name + "!"
        case .missed(let s, let id): return u < 0.45 ? who(s) + "의 " + moveTable[id]!.name + "!" : "빗나갔다!"
        case .fainted(let s): return josa(s == .me ? me : it, "은", "는") + " 쓰러졌다!"
        case .thrown: return u < 1.25 ? "가랏, " + usedItem + "!" : dots
        case .broke: return "앗! 나와버렸다!"
        case .caught: return "딸깍! " + josa(it, "을", "를") + " 잡았다!"
        case .healed(let n): return usedItem + " · HP +\(n)"
        case .revived: return josa(usedItem, "으로", "로") + " 되살아났다!"
        case .gained(let e, let l): return l.map { me + " Lv.\($0)!" } ?? "경험치 \(e) 획득"
        case .fled: return josa(it, "은", "는") + " 도망쳤다..."
        case .ran: return "무사히 도망쳤다!"
        case .won: return b.trainer == nil ? "승리!" : (b.trainer ?? "") + "에게 이겼다!"
        case .lost: return "눈앞이 캄캄해졌다..."
        }
    }

    // MARK: input
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let i = buttons.firstIndex(where: { hypot($0.c.x - p.x, $0.c.y - p.y) <= $0.r + PX }) {
            pressed = i; pressedAt = Date(); press(i)
            perform(#selector(tick(_:)), with: nil, afterDelay: 0.15, inModes: [.common])
        } else if lcdRect.contains(p), touch(Int((p.x - lcdRect.minX) / PX), Int((p.y - lcdRect.minY) / PX)) { needsDisplay = true }
        else { window?.performDrag(with: e) }
    }
    /// Tap on the screen (dot coords 96x64). Returns false where the click should drag the device instead.
    func touch(_ x: Int, _ y: Int) -> Bool {
        func pick(_ select: () -> Void) { select(); press(1) }
        switch screen {
        case .home, .say: press(1)
        case .menu, .card, .bag, .dex: press(x < 32 ? 0 : x >= 64 ? 2 : 1)
        case .box(_, let act, _):
            if act != nil, y >= 50 { press(1) } else { press(x < 32 ? 0 : x >= 64 ? 2 : 1) }                             // left third ◀, middle ●, right third ▶
        case .radar(let b, _, let since, let chain): pick { screen = .radar(bush: b, cursor: (x < 48 ? 0 : 1) + (y < 32 ? 0 : 2), since: since, chain: chain) }
        case .battle(let b, _):
            guard y >= 50, let k = menuRanges(battleMenu(b)).firstIndex(where: { $0.contains(x) }) else { return false }
            pick { screen = .battle(b, sel: k) }
        case .moves(let b, _):
            guard y >= 37 else { press(3); return true }                                           // tap the stage = back
            let k = (x < 48 ? 0 : 1) + (y < 50 ? 0 : 2)
            guard k < b.mine[b.me].mon.moves.count else { return false }
            pick { screen = .moves(b, sel: k) }
        case .party(let b, _):
            let k = (y - 15) / 15
            guard y >= 15, k < b.mine.count else { press(3); return true }
            pick { screen = .party(b, sel: k) }
        case .tower: press(1)
        case .dowse(_, let prize, let tries, _):
            guard (20..<48).contains(y) else { return false }
            pick { screen = .dowse(cursor: min(5, max(0, (x - 2) / 16)), prize: prize, tries: tries, hint: nil) }
        case .beats, .evolve, .hatch: return false
        }
        return true
    }
    override func keyDown(with e: NSEvent) { if let i = [123: 0, 36: 1, 49: 1, 124: 2, 53: 3][Int(e.keyCode)] { press(i) } else { super.keyDown(with: e) } }   // ← return/space → esc
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(lcdRect, cursor: .pointingHand); for b in buttons { addCursorRect(NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r), cursor: .pointingHand) } }

    override func menu(for event: NSEvent) -> NSMenu? { buildMenu() }
    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: window?.isVisible == false ? "워커 보이기" : "메뉴 막대로 숨기기", action: #selector(toggleShown(_:)), keyEquivalent: "").target = self
        m.addItem(withTitle: "\(state.here.name) · 오늘 \(state.today)걸음 · \(state.watts)W", action: nil, keyEquivalent: "")
        m.addItem(.separator())
        let ch = m.addItem(withTitle: "코스 · \(state.here.name)", action: nil, keyEquivalent: ""), cm = NSMenu()
        for (i, c) in courses.enumerated() {
            let it = cm.addItem(withTitle: state.unlocked(i) ? c.name : c.dex > 0 ? "\(c.name) — 도감 \(c.dex)" : "\(c.name) — \(c.watts)W", action: state.unlocked(i) ? #selector(setCourse(_:)) : nil, keyEquivalent: "")
            it.target = self; it.tag = i; it.state = i == state.course ? .on : .off
        }
        ch.submenu = cm
        let ph = m.addItem(withTitle: "함께 걷기 · \(state.companion.shiny == true ? "★ " : "")\(monNames[state.companion.dex])", action: nil, keyEquivalent: ""), pm = NSMenu()
        if state.box.isEmpty && state.caught.isEmpty { pm.addItem(withTitle: "잡은 포켓몬이 없다", action: nil, keyEquivalent: "") }
        let all = state.caught.enumerated().map { (-1 - $0, $1, " · 워커") } + state.box.enumerated().map { ($0, $1, "") }   // tag < 0 = on the walker
        func individual(_ into: NSMenu, _ e: (Int, Mon, String), named: Bool, count: Int = 1) {
            let (tag, b, whereIs) = e
            let it = into.addItem(withTitle: "\(b.shiny == true ? "★ " : "")\(named ? monNames[b.dex] + " " : "")Lv.\(b.level) \(b.female ? "♀" : "♂")\(whereIs)\(count > 1 ? " ×\(count)" : "")", action: #selector(pair(_:)), keyEquivalent: "")
            it.target = self; it.tag = tag
        }
        func species(_ into: NSMenu, _ groups: [(key: Int, value: [(Int, Mon, String)])]) {        // one row per species, the individuals inside
            for (dex, group) in groups {
                let head = into.addItem(withTitle: "\(monNames[dex])\(group.contains { $0.1.shiny == true } ? " ★" : "") · \(group.count)", action: nil, keyEquivalent: ""), sm = NSMenu()
                // look-alikes (same level, sex, 이로치, place) are one row "×n"; picking it takes the one with the most EXP
                let rows = Dictionary(grouping: group, by: { "\($0.1.shiny == true)|\($0.1.level)|\($0.1.female)|\($0.2)" }).values
                    .map { (best: $0.max(by: { $0.1.points < $1.1.points })!, n: $0.count) }
                    .sorted { ($0.best.1.shiny == true ? 1 : 0, $0.best.1.points) > ($1.best.1.shiny == true ? 1 : 0, $1.best.1.points) }
                for r in rows.prefix(rows.count > 10 ? 8 : 10) { individual(sm, r.best, named: false, count: r.n) }
                if rows.count > 10 {                                                                   // the long tail, by level band
                    let rest = rows.dropFirst(8), mh = sm.addItem(withTitle: "그 밖 \(rest.reduce(0) { $0 + $1.n })마리", action: nil, keyEquivalent: ""), mm = NSMenu()
                    for (band, rs) in Dictionary(grouping: rest, by: { ($0.best.1.level - 1) / 10 }).sorted(by: { $0.key > $1.key }) {
                        let bh = mm.addItem(withTitle: "Lv.\(band * 10 + 1)–\(band * 10 + 10) · \(rs.reduce(0) { $0 + $1.n })마리", action: nil, keyEquivalent: ""), bm = NSMenu()
                        for r in rs { individual(bm, r.best, named: false, count: r.n) }
                        bh.submenu = bm
                    }
                    mh.submenu = mm
                }
                let dupes = state.box.filter { $0.dex == dex && $0.shiny != true }.count - 1
                if dupes > 0 {
                    sm.addItem(.separator())
                    let it = sm.addItem(withTitle: "중복 놓아주기 · 상자의 \(dupes)마리", action: #selector(releaseDupes(_:)), keyEquivalent: ""); it.target = self; it.tag = dex
                }
                head.submenu = sm
            }
        }
        let groups = Dictionary(grouping: all, by: { $0.1.dex }).sorted(by: { $0.key < $1.key })
        if groups.count <= 12 { species(pm, groups) }
        else {                                                                                   // many species: recent + shinies up top, the rest by dex number in 50s
            pm.addItem(withTitle: "최근 잡은 포켓몬", action: nil, keyEquivalent: "")
            let recent: [(Int, Mon, String)] = Array(state.caught.enumerated().map { (-1 - $0.offset, $0.element, " · 워커") }.reversed()) + Array(state.box.enumerated().map { ($0.offset, $0.element, "") }.reversed())
            for e in recent.prefix(5) { individual(pm, e, named: true) }
            let shinies = all.filter { $0.1.shiny == true }
            if !shinies.isEmpty {
                let sh = pm.addItem(withTitle: "★ 이로치 · \(shinies.count)", action: nil, keyEquivalent: ""), sm = NSMenu()
                for e in shinies.sorted(by: { $0.1.dex < $1.1.dex }) { individual(sm, e, named: true) }
                sh.submenu = sm
            }
            pm.addItem(.separator())
            for (bucket, g) in Dictionary(grouping: groups, by: { ($0.key - 1) / 50 }).sorted(by: { $0.key < $1.key }) {
                let head = pm.addItem(withTitle: String(format: "No.%03d–%03d · %d종", bucket * 50 + 1, bucket * 50 + 50, g.count), action: nil, keyEquivalent: ""), sm = NSMenu()
                species(sm, g); head.submenu = sm
            }
        }
        ph.submenu = pm
        let now = Date(), stones = state.stoneEvolutions(now)
        if !stones.isEmpty {
            let sh = m.addItem(withTitle: "진화의 돌 쓰기", action: nil, keyEquivalent: ""), sm = NSMenu()
            for (i, e) in stones.enumerated() { let it = sm.addItem(withTitle: "\(e.item!) → \(monNames[e.to])", action: #selector(useStone(_:)), keyEquivalent: ""); it.target = self; it.tag = i }
            sh.submenu = sm
        }
        let sh = m.addItem(withTitle: "상점 · \(state.watts)W", action: nil, keyEquivalent: ""), shm = NSMenu()
        for (i, w) in Walk.shop.enumerated() {
            let it = shm.addItem(withTitle: "\(w.item) — \(w.watts)W", action: state.watts >= w.watts ? #selector(buyShop(_:)) : nil, keyEquivalent: ""); it.target = self; it.tag = i
        }
        for (i, l) in Walk.legendShop.enumerated() where l.watts > 0 { shm.addItem(.separator()); legendItem(shm, i, l.dex, "\(l.watts.formatted())W", state.watts >= l.watts) }
        sh.submenu = shm
        let bh2 = m.addItem(withTitle: "BP 교환소 · \(state.bp ?? 0)BP", action: nil, keyEquivalent: ""), bpm = NSMenu()
        for (i, w) in Walk.bpShop.enumerated() {
            let it = bpm.addItem(withTitle: "\(w.item) — \(w.bp)BP", action: (state.bp ?? 0) >= w.bp ? #selector(buyBP(_:)) : nil, keyEquivalent: ""); it.target = self; it.tag = i
        }
        for (i, s) in shells.enumerated() where s.bp > 0 {
            let owned = (state.bought ?? []).contains(s.name)
            let it = bpm.addItem(withTitle: "기기 색: \(s.name) — \(owned ? "보유" : "\(s.bp)BP")", action: !owned && (state.bp ?? 0) >= s.bp ? #selector(buyShell(_:)) : nil, keyEquivalent: ""); it.target = self; it.tag = i
        }
        for (i, l) in Walk.legendShop.enumerated() where l.bp > 0 { bpm.addItem(.separator()); legendItem(bpm, i, l.dex, "\(l.bp)BP", (state.bp ?? 0) >= l.bp) }
        bh2.submenu = bpm
        let wares = state.evolutionItems()
        if !wares.isEmpty {                                                                     // HGSS sold these for Pokéathlon points; here, watts
            let xh = m.addItem(withTitle: "교환소 · \(price)W", action: nil, keyEquivalent: ""), xm = NSMenu()
            for (i, w) in wares.enumerated() { let it = xm.addItem(withTitle: "\(w)\(state.bag.contains(w) ? " (있음)" : "")", action: state.watts >= price ? #selector(buy(_:)) : nil, keyEquivalent: ""); it.target = self; it.tag = i }
            xh.submenu = xm
        }
        let inv = state.inventory
        if !inv.isEmpty {                                                                         // everything carried: walker + bag
            let bh = m.addItem(withTitle: "가방 · \(state.items.count + state.bag.count)개", action: nil, keyEquivalent: ""), bm = NSMenu()
            if state.count("이상한사탕") > 0 { bm.addItem(withTitle: "이상한사탕 먹이기 (×\(state.count("이상한사탕")))", action: #selector(useCandy(_:)), keyEquivalent: "").target = self }
            let berries = inv.filter { ItemKind.of($0) == .berry }
            if !berries.isEmpty {
                let fh = bm.addItem(withTitle: "열매 먹이기 · 친밀도 +500걸음", action: nil, keyEquivalent: ""), fm = NSMenu()
                for b in berries { let it = fm.addItem(withTitle: "\(b) ×\(state.count(b))", action: #selector(useBerry(_:)), keyEquivalent: ""); it.target = self; it.representedObject = b }
                fh.submenu = fm
            }
            let wares = inv.compactMap { i -> (String, Int)? in if case .sell(let p) = ItemKind.of(i) { return (i, p) }; return nil }
            if !wares.isEmpty {
                let total = wares.reduce(0) { $0 + $1.1 * state.count($1.0) }
                let sh = bm.addItem(withTitle: "팔기 · 전부 \(total)W", action: nil, keyEquivalent: ""), sm = NSMenu()
                sm.addItem(withTitle: "전부 팔기 (\(total)W)", action: #selector(sellAll(_:)), keyEquivalent: "").target = self
                sm.addItem(.separator())
                for (i, p) in wares { let it = sm.addItem(withTitle: "\(i) ×\(state.count(i)) — \(p * state.count(i))W", action: #selector(sellOne(_:)), keyEquivalent: ""); it.target = self; it.representedObject = i }
                sh.submenu = sm
            }
            bm.addItem(.separator())
            for i in inv {
                let use: String = switch ItemKind.of(i) {
                case .heal(let n): "배틀 HP +\(n)"; case .revive(let n): "쓰러지면 HP \(n)로 부활"; case .ball(let x): "포획 ×\(x == 2 ? "2" : "1.5")"
                case .candy: "레벨 +1"; case .berry: "친밀도 +500걸음"; case .evolution: "진화"; case .sell(let p): "\(p)W"
                }
                bm.addItem(withTitle: "\(i) ×\(state.count(i)) · \(use)", action: nil, keyEquivalent: "")
            }
            bh.submenu = bm
        }
        func sub(_ title: String, _ items: [(String, Int)], _ current: Int, _ sel: Selector) {
            let head = m.addItem(withTitle: "\(title) · \(items.first { $0.1 == current }?.0 ?? "")", action: nil, keyEquivalent: ""), sm = NSMenu()
            for (t, tag) in items { let i = sm.addItem(withTitle: t, action: sel, keyEquivalent: ""); i.target = self; i.tag = tag; i.state = tag == current ? .on : .off }
            head.submenu = sm
        }
        m.addItem(.separator())
        sub("크기", [("보통", 2), ("크게", 3), ("아주 크게", 4)], Int(PX), #selector(setSize(_:)))
        sub("기기", shells.enumerated().map { ($1.dex > dexCount ? "\($1.name) — 도감 \($1.dex)" : !shellOpen($1) ? "\($1.name) — \($1.bp)BP" : $1.name, $0) }, theme, #selector(setTheme(_:)))
        sub("화면", lcds.enumerated().map { ($1.name, $0) }, lcdStyle, #selector(setLCD(_:)))
        sub("화면 글씨", [("매끈하게", 1), ("도트", 0)], smoothText ? 1 : 0, #selector(setTextStyle(_:)))
        m.addItem(.separator())
        let nh = m.addItem(withTitle: "알림", action: nil, keyEquivalent: ""), nm = NSMenu()
        for (i, (k, name)) in notifyKinds.enumerated() { let it = nm.addItem(withTitle: name, action: #selector(toggleNotify(_:)), keyEquivalent: ""); it.target = self; it.tag = i; it.state = notifyOn(k) ? .on : .off }
        nm.addItem(.separator())
        nm.addItem(withTitle: "테스트 알림 보내기", action: #selector(testNotify(_:)), keyEquivalent: "").target = self
        nh.submenu = nm
        m.addItem(.separator())
        m.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        return m
    }
    @objc func releaseDupes(_ i: NSMenuItem) {
        let dex = i.tag, n = state.box.filter { $0.dex == dex && $0.shiny != true }.count - 1
        guard n > 0 else { return }
        NSApp.activate(ignoringOtherApps: true)                                                   // the only time it takes focus: a real confirmation
        let a = NSAlert(); a.messageText = "\(monNames[dex]) \(n)마리를 놓아줄까요?"
        a.informativeText = "상자에서 이로치와 가장 레벨이 높은 1마리만 남아요. 되돌릴 수 없어요."
        a.addButton(withTitle: "놓아주기"); a.addButton(withTitle: "취소")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let r = state.releaseDuplicates(of: dex)
        screen = .say(["\(r.count)마리를 놓아줬다", "+\(r.watts)W"], next: .home, since: Date()); save(nil)
    }
    @objc func testNotify(_ i: NSMenuItem) { notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 인사해요", "알림이 이렇게 와요 · 지금 \(state.watts)W") }
    @objc func toggleNotify(_ i: NSMenuItem) { let k = notifyKinds[i.tag].0; UserDefaults.standard.set(!notifyOn(k), forKey: "notify.\(k)") }
    /// Walker <-> menu bar. Hiding parks it on the home screen so the events (which wait for home) keep coming.
    @objc func toggleShown(_ sender: Any?) {
        guard let w = window else { return }
        if w.isVisible { screen = .home; w.orderOut(nil) } else { shown = nil; w.orderFrontRegardless() }
        UserDefaults.standard.set(!w.isVisible, forKey: "hidden")
    }
    var lastStatus = ""
    func updateStatus() {
        let s = "\(state.watts)W" + (state.egg.map { $0.left < 500 ? " ·알" : "" } ?? "")                 // watts: what the radar / dowsing spend
        if s != lastStatus { lastStatus = s; statusItem?.button?.title = " " + s }
    }
    @objc func statusClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            statusItem?.menu = buildMenu(); statusItem?.button?.performClick(nil); statusItem?.menu = nil   // pop the menu once, keep left-click as the toggle
        } else { toggleShown(nil) }
    }
    @objc func setCourse(_ i: NSMenuItem) { state.setCourse(i.tag, &rng); screen = .say(["커넥트 완료", state.here.name], next: .home, since: Date()); save(nil) }
    let price = 1000
    func legendItem(_ menu: NSMenu, _ i: Int, _ dex: Int, _ cost: String, _ afford: Bool) {
        let owned = state.legendBought(dex)
        let it = menu.addItem(withTitle: "전설: \(monNames[dex]) Lv.\(Walk.legendShop[i].level) — \(owned ? "보유" : cost)", action: !owned && afford ? #selector(buyLegend(_:)) : nil, keyEquivalent: "")
        it.target = self; it.tag = i
    }
    @objc func buyLegend(_ i: NSMenuItem) {
        let l = Walk.legendShop[i.tag]
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "\(monNames[l.dex])을(를) 데려올까요?"
        a.informativeText = (l.watts > 0 ? "\(l.watts.formatted())W" : "\(l.bp)BP") + "가 들어요. 한 번만 살 수 있어요."
        a.addButton(withTitle: "데려오기"); a.addButton(withTitle: "취소")
        guard a.runModal() == .alertFirstButtonReturn, let m = state.buyLegend(i.tag) else { return }
        screen = .say(["전설의 " + monNames[m.dex] + "!", "Lv.\(m.level) · 워커에 왔다"], next: .home, since: Date()); save(nil)
        notify("unlock", "전설의 \(monNames[m.dex])", "Lv.\(m.level)이 워커에 왔어요")
    }
    @objc func buyShop(_ i: NSMenuItem) { let w = Walk.shop[i.tag]; guard state.buy(w.item, watts: w.watts) else { return }; screen = .say([josa(w.item, "을", "를"), "샀다! (-\(w.watts)W)"], next: .home, since: Date()); save(nil) }
    @objc func buyBP(_ i: NSMenuItem) { let w = Walk.bpShop[i.tag]; guard state.buy(w.item, bp: w.bp) else { return }; screen = .say([josa(w.item, "을", "를"), "받았다! (-\(w.bp)BP)"], next: .home, since: Date()); save(nil) }
    @objc func buyShell(_ i: NSMenuItem) {
        let s = shells[i.tag]; guard (state.bp ?? 0) >= s.bp else { return }
        state.bp = (state.bp ?? 0) - s.bp; state.bought = (state.bought ?? []) + [s.name]; theme = i.tag; UserDefaults.standard.set(theme, forKey: "shell")
        screen = .say(["기기 색", s.name + " 획득!"], next: .home, since: Date()); save(nil)
    }
    @objc func useCandy(_ i: NSMenuItem) {
        guard state.feedCandy() else { return }
        levelled = true; screen = .home; save(nil)                                              // the home screen shows the level-up (or an evolution)
    }
    @objc func useBerry(_ i: NSMenuItem) {
        guard let b = i.representedObject as? String, state.feedBerry(b) else { return }
        screen = .say([josa(monNames[state.companion.dex], "이", "가") + " " + josa(b, "을", "를"), "맛있게 먹었다!"], next: .home, since: Date()); save(nil)
    }
    @objc func sellOne(_ i: NSMenuItem) { guard let n = i.representedObject as? String else { return }; let w = state.sell(n); screen = .say([n + " 판매", "+\(w)W"], next: .home, since: Date()); save(nil) }
    @objc func sellAll(_ i: NSMenuItem) {
        let w = state.inventory.reduce(0) { $0 + state.sell($1) }
        screen = .say(["전부 팔았다", "+\(w)W"], next: .home, since: Date()); save(nil)
    }
    @objc func useStone(_ i: NSMenuItem) { let s = state.stoneEvolutions(Date()); guard s.indices.contains(i.tag) else { return }; startEvolving(s[i.tag], Date()) }
    @objc func buy(_ i: NSMenuItem) {
        let w = state.evolutionItems(); guard w.indices.contains(i.tag), state.spend(price) else { return }
        state.bag.append(w[i.tag]); screen = .say([josa(w[i.tag], "을", "를"), "받았다!"], next: .home, since: Date()); save(nil)
    }
    @objc func pair(_ i: NSMenuItem) {
        if i.tag < 0 { guard state.caught.indices.contains(-1 - i.tag) else { return }; state.pair(-1 - i.tag, onWalker: true) }
        else { guard state.box.indices.contains(i.tag) else { return }; state.pair(i.tag) }
        screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: .home, since: Date()); save(nil)
    }
    @objc func setSize(_ item: NSMenuItem) {                     // keeps the top-right corner
        guard let w = window else { return }
        var f = w.frame; f.origin.x += f.width - CGFloat(item.tag) * dev.w; f.origin.y += f.height - CGFloat(item.tag) * dev.h
        PX = CGFloat(item.tag); UserDefaults.standard.set(item.tag, forKey: "px")
        f.size = devSize
        if let s = w.screen?.visibleFrame { f.origin.x = min(max(f.origin.x, s.minX), s.maxX - f.width); f.origin.y = min(max(f.origin.y, s.minY), s.maxY - f.height) }
        w.setFrame(f, display: true); setFrameSize(devSize); window?.invalidateCursorRects(for: self); needsDisplay = true
    }
    func shellOpen(_ s: Shell) -> Bool { s.dex <= dexCount && (s.bp == 0 || (state.bought ?? []).contains(s.name)) }
    @objc func setTheme(_ item: NSMenuItem) { guard shellOpen(shells[item.tag]) else { return }; theme = item.tag; UserDefaults.standard.set(theme, forKey: "shell"); needsDisplay = true }
    @objc func setTextStyle(_ item: NSMenuItem) { smoothText = item.tag == 1; UserDefaults.standard.set(smoothText, forKey: "smoothText"); shown = nil; needsDisplay = true }
    @objc func setLCD(_ item: NSMenuItem) { shown = nil; lcdStyle = item.tag; UserDefaults.standard.set(lcdStyle, forKey: "lcd"); needsDisplay = true }

    // MARK: drawing
    override func draw(_ dirty: NSRect) {
        let t = shells[theme], l = lcds[lcdStyle], ink = NSColor(white: 0.10, alpha: 1), white = NSColor(white: 0.96, alpha: 1), light = t.name == "프리미어볼"
        let ballRect = NSRect(origin: .zero, size: devSize).insetBy(dx: PX, dy: PX), ball = NSBezierPath(ovalIn: ballRect)
        // flat halves: top colour, white bottom, black band through the middle; one hairline, depth from the window shadow
        NSGraphicsContext.saveGraphicsState(); ball.addClip()
        t.top.setFill(); NSRect(x: 0, y: 0, width: devSize.width, height: 72 * PX).fill()
        white.setFill(); NSRect(x: 0, y: 72 * PX, width: devSize.width, height: 72 * PX).fill()
        switch t.name {
        case "하이퍼볼": NSColor(red: 0.98, green: 0.80, blue: 0.20, alpha: 1).setFill(); for x in [30, 106] { NSRect(x: CGFloat(x) * PX, y: 0, width: 8 * PX, height: 34 * PX).fill() }   // yellow
        case "마스터볼": NSColor(red: 0.93, green: 0.40, blue: 0.62, alpha: 1).setFill(); for x in [18, 110] { NSBezierPath(ovalIn: NSRect(x: CGFloat(x) * PX, y: 22 * PX, width: 16 * PX, height: 12 * PX)).fill() }   // pink spots
        case "럭셔리볼": NSColor(red: 0.95, green: 0.78, blue: 0.30, alpha: 1).setFill(); for y in [62, 78] { NSRect(x: 0, y: CGFloat(y) * PX, width: devSize.width, height: 2 * PX).fill() }; NSRect(x: 70 * PX, y: 1 * PX, width: 4 * PX, height: 60 * PX).fill()   // gold trim
        default: break
        }
        t.band.setFill(); NSRect(x: 0, y: 68 * PX, width: devSize.width, height: 8 * PX).fill()
        NSGraphicsContext.restoreGraphicsState()
        ink.withAlphaComponent(0.6).setStroke(); ball.lineWidth = 1; ball.stroke()
        // the screen sits where the ball's button is: black ring, white ring, black bezel
        for (out, r, c) in [(8.0, 11.0, ink), (5.0, 8.0, white), (2.0, 4.0, ink)] as [(CGFloat, CGFloat, NSColor)] {
            c.setFill(); NSBezierPath(roundedRect: lcdRect.insetBy(dx: -out * PX, dy: -out * PX), xRadius: r * PX, yRadius: r * PX).fill()
        }
        l.shades[0].setFill(); lcdRect.fill()
        let fb = shown ?? compose(Date()), gap = PX >= 3 ? 1 / (window?.backingScaleFactor ?? 2) : 0
        var paths: [UInt32: NSBezierPath] = [:]                                                        // key: colour, or 1...3 for an LCD shade
        for y in 0..<64 { for x in 0..<96 {
            let i = y * 96 + x, key = l.color && fb.col[i] != 0 ? fb.col[i] : UInt32(fb.px[i])
            if key != 0 { if paths[key] == nil { paths[key] = NSBezierPath() }; paths[key]!.appendRect(NSRect(x: lcdRect.minX + CGFloat(x) * PX, y: lcdRect.minY + CGFloat(y) * PX, width: PX - gap, height: PX - gap)) }
        } }
        NSGraphicsContext.current!.shouldAntialias = false
        for (k, path) in paths {
            (k < 4 ? l.shades[Int(k)] : NSColor(red: CGFloat(k >> 16 & 255) / 255, green: CGFloat(k >> 8 & 255) / 255, blue: CGFloat(k & 255) / 255, alpha: 1)).setFill(); path.fill()
        }
        NSGraphicsContext.current!.shouldAntialias = true
        for r in fb.runs {                                                                             // smooth text over the dots; flipped where it sits in an inverted box
            let f = lcdFont(r.small), cx = r.x + r.w / 2, cy = r.y + r.rows / 2
            let flipped = fb.flips.contains { cx >= $0[0] && cx < $0[0] + $0[2] && cy >= $0[1] && cy < $0[1] + $0[3] }
            let shade = Int(flipped ? 3 - r.shade : r.shade), c = l.shades[max(0, min(3, shade))]
            let box = NSRect(x: lcdRect.minX + CGFloat(r.x) * PX, y: lcdRect.minY + CGFloat(r.y) * PX, width: CGFloat(r.w) * PX, height: CGFloat(r.rows) * PX)
            let y = box.midY + f.capHeight / 2 - f.ascender                                            // caps centred on the row, one baseline for Hangul and digits
            (r.s as NSString).draw(at: NSPoint(x: box.minX, y: y), withAttributes: [.font: f, .foregroundColor: c])
        }
        NSGradient(starting: NSColor(white: 0, alpha: 0.22), ending: .clear)!.draw(in: NSRect(x: lcdRect.minX, y: lcdRect.minY, width: lcdRect.width, height: 2 * PX), angle: 90)
        let now = Date()
        for (i, b) in buttons.enumerated() {                                                          // white caps with a black ring and a printed icon; a lip underneath until pressed
            let down = pressed == i && now.timeIntervalSince(pressedAt) < 0.15, dy = down ? 0.7 * PX : 0
            let r = NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r)
            if !down { NSColor(white: 0.62, alpha: 1).setFill(); NSBezierPath(ovalIn: r.offsetBy(dx: 0, dy: 0.9 * PX)).fill() }
            let cap = NSBezierPath(ovalIn: r.offsetBy(dx: 0, dy: dy))
            (down ? NSColor(white: 0.84, alpha: 1) : white).setFill(); cap.fill()
            ink.setStroke(); cap.lineWidth = 1.0 * PX; cap.stroke()
            let c = NSPoint(x: b.c.x, y: b.c.y + dy), s = b.r * 0.42, icon = NSBezierPath()
            switch i {
            case 0: icon.move(to: NSPoint(x: c.x - s, y: c.y)); icon.line(to: NSPoint(x: c.x + s * 0.7, y: c.y - s)); icon.line(to: NSPoint(x: c.x + s * 0.7, y: c.y + s)); icon.close()
            case 2: icon.move(to: NSPoint(x: c.x + s, y: c.y)); icon.line(to: NSPoint(x: c.x - s * 0.7, y: c.y - s)); icon.line(to: NSPoint(x: c.x - s * 0.7, y: c.y + s)); icon.close()
            case 1: icon.appendOval(in: NSRect(x: c.x - s * 0.8, y: c.y - s * 0.8, width: s * 1.6, height: s * 1.6))
            default:                                                                                   // a little house
                icon.move(to: NSPoint(x: c.x, y: c.y - s * 1.1)); icon.line(to: NSPoint(x: c.x + s * 1.1, y: c.y)); icon.line(to: NSPoint(x: c.x + s * 0.7, y: c.y))
                icon.line(to: NSPoint(x: c.x + s * 0.7, y: c.y + s)); icon.line(to: NSPoint(x: c.x - s * 0.7, y: c.y + s)); icon.line(to: NSPoint(x: c.x - s * 0.7, y: c.y))
                icon.line(to: NSPoint(x: c.x - s * 1.1, y: c.y)); icon.close()
            }
            ink.setFill(); icon.fill()
        }
        let centred = NSMutableParagraphStyle(); centred.alignment = .center
        ("Pokéwalker" as NSString).draw(in: NSRect(x: 42 * PX, y: 20 * PX, width: 60 * PX, height: 6 * PX),
            withAttributes: [.font: NSFont.systemFont(ofSize: 3.4 * PX, weight: .heavy), .foregroundColor: light ? NSColor(red: 0.86, green: 0.20, blue: 0.18, alpha: 1) : NSColor(white: 1, alpha: 0.85), .paragraphStyle: centred, .kern: 0.3 * PX])
    }
}

// MARK: - battle side panel: names, HP, messages and big buttons next to the device, so the 96x64 screen keeps the stage
struct SideModel: Equatable {
    struct Card: Equatable { var name: String; var level, hp, max: Int; var out: Bool }
    struct MoveBtn: Equatable { var name, type: String; var power: Int; var effect: Double }
    enum Mode: Equatable { case none, menu([String], Int), moves([MoveBtn], Int), party([Card], Int) }
    var foe: Card; var foeBalls: [Bool]; var mine: Card; var myBalls: [Bool]; var trainer: String?; var message: String; var mode: Mode
}
/// The Pokédex page on the side panel.
struct DexModel: Equatable {
    var num: Int; var name: String; var status: Int                    // 0 not met, 1 seen, 2 caught
    var shiny: Bool; var types: [String]; var stats: [Int]
    var found: [String]; var evos: [String]                            // where to meet it; what it becomes and how
    var owned, seen: Int
    var strip: [Int], stripStatus: [Int]                               // the numbers around it, with their status
}
let typeColor: [String: NSColor] = ["normal": (168, 168, 120), "fire": (240, 128, 48), "water": (104, 144, 240), "grass": (120, 200, 80), "electric": (238, 196, 40),
    "ice": (120, 200, 200), "fighting": (192, 48, 40), "poison": (160, 64, 160), "ground": (210, 176, 90), "flying": (150, 130, 230), "psychic": (248, 88, 136),
    "bug": (160, 176, 32), "rock": (184, 160, 56), "ghost": (112, 88, 152), "dragon": (112, 56, 248), "dark": (112, 88, 72), "steel": (160, 160, 190)]
    .mapValues { NSColor(red: CGFloat($0.0) / 255, green: CGFloat($0.1) / 255, blue: CGFloat($0.2) / 255, alpha: 1) }

final class SideView: NSView {
    var model: SideModel?
    var dex: DexModel?
    var hits: [(NSRect, Int)] = []                                         // clickable rows: index, or -1 = back
    weak var walker: WalkerView?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let k = hits.first(where: { $0.0.contains(p) })?.1 else { return }
        if k >= 1000 { walker?.dexJump(k - 1000) } else if k < 0 { walker?.press(3) } else { walker?.sidePick(k) }
    }
    override func resetCursorRects() { for (r, _) in hits { addCursorRect(r, cursor: .pointingHand) } }
    // text: Galmuri at 3x its pixel size on a Retina screen (15 / 12 pt at the normal size), so every glyph pixel is whole
    /// The panel's layout unit (the device's dot size, a bit smaller): about as tall as the device. The panel is plain UI in the
    /// system font — sharp at any scale; the pixel look stays on the LCD. (Pixel text had to be 2x on 1x monitors, making it huge.)
    static func unit(_ backing: CGFloat) -> CGFloat { PX * 0.85 }
    var backing: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    var u0: CGFloat { SideView.unit(backing) }
    var body: NSFont { .systemFont(ofSize: 7.5 * u0, weight: .medium) }
    var small: NSFont { .systemFont(ofSize: 6 * u0, weight: .regular) }
    var big: NSFont { .systemFont(ofSize: 10.5 * u0, weight: .bold) }
    static let ink = NSColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1), dim = NSColor(red: 0.42, green: 0.45, blue: 0.52, alpha: 1)
    func width(_ str: String, _ f: NSFont) -> CGFloat { (str as NSString).size(withAttributes: [.font: f]).width }
    /// Plain text with its top-left at (x, y); `right` aligns its end there instead.
    func text(_ str: String, _ x: CGFloat, _ y: CGFloat, _ f: NSFont, _ c: NSColor, shadow: NSColor? = nil, right: CGFloat? = nil, maxW: CGFloat? = nil) {
        var str = str
        if let maxW { while str.count > 1, width(str, f) > maxW { str = String(str.dropLast(2)) + "…" } }
        let x0 = right.map { $0 - width(str, f) } ?? x, g = max(1, f.pointSize / 14)
        if let shadow { (str as NSString).draw(at: NSPoint(x: x0, y: y + g), withAttributes: [.font: f, .foregroundColor: shadow]) }
        (str as NSString).draw(at: NSPoint(x: x0, y: y), withAttributes: [.font: f, .foregroundColor: c])
    }
    /// Text centred in `r` by its ink, not its line box (the pixel font's leading made labels ride high).
    func label(_ str: String, in r: NSRect, _ f: NSFont, _ c: NSColor, shadow: NSColor? = nil, alignLeft: CGFloat? = nil, alignRight: CGFloat? = nil) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: str, attributes: [.font: f]))
        let ink = CTLineGetImageBounds(line, nil), w = width(str, f)
        let y = r.midY - f.ascender + ink.origin.y + ink.height / 2
        let x = alignLeft.map { r.minX + $0 } ?? alignRight.map { r.maxX - $0 - w } ?? r.midX - w / 2
        text(str, x, y, f, c, shadow: shadow)
    }
    func round(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
    func hpColor(_ f: CGFloat) -> NSColor { f > 0.5 ? NSColor(red: 0.30, green: 0.82, blue: 0.40, alpha: 1) : f > 0.2 ? NSColor(red: 0.98, green: 0.78, blue: 0.16, alpha: 1) : NSColor(red: 0.95, green: 0.28, blue: 0.24, alpha: 1) }

    override func draw(_ dirty: NSRect) {
        hits = []
        if let d = dex { drawDex(d); return }
        guard let m = model else { return }
        let u = SideView.unit(backing), W = bounds.width, H = bounds.height, ink = SideView.ink, dim = SideView.dim, paper = NSColor(white: 0.98, alpha: 1)
        /// "HP" tag + bar, the HGSS way: dark track, the colour on top with a little shine.
        func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hp: Int, _ max: Int) {
            let f = max > 0 ? CGFloat(hp) / CGFloat(max) : 0, tag = NSRect(x: x, y: y, width: 15 * u, height: 7 * u)
            round(tag, 2 * u).fill(with: ink); label("HP", in: tag, small, NSColor(red: 1, green: 0.78, blue: 0.2, alpha: 1))
            let tr = NSRect(x: tag.maxX - u, y: y, width: w - 14 * u, height: 7 * u)
            round(tr, 2 * u).fill(with: ink)
            let inner = tr.insetBy(dx: 1.5 * u, dy: 1.5 * u), fw = hp > 0 ? Swift.max(u, inner.width * f) : 0
            NSColor(white: 0.30, alpha: 1).setFill(); inner.fill()
            hpColor(f).setFill(); NSRect(x: inner.minX, y: inner.minY, width: fw, height: inner.height).fill()
            NSColor(white: 1, alpha: 0.35).setFill(); NSRect(x: inner.minX, y: inner.minY, width: fw, height: inner.height / 3).fill()
        }
        // backdrop: deep blue with faint diagonal stripes (the HGSS bottom screen)
        let bgPath = round(bounds.insetBy(dx: u / 2, dy: u / 2), 9 * u)
        NSGraphicsContext.saveGraphicsState(); bgPath.addClip()
        NSGradient(starting: NSColor(red: 0.20, green: 0.30, blue: 0.52, alpha: 1), ending: NSColor(red: 0.10, green: 0.15, blue: 0.30, alpha: 1))!.draw(in: bounds, angle: -90)
        NSColor(white: 1, alpha: 0.05).setStroke()
        for i in stride(from: -H, to: W, by: 6 * u) { let p = NSBezierPath(); p.move(to: NSPoint(x: i, y: 0)); p.line(to: NSPoint(x: i + H, y: H)); p.lineWidth = 2 * u; p.stroke() }
        NSGraphicsContext.restoreGraphicsState()
        ink.setStroke(); bgPath.lineWidth = 1.2; bgPath.stroke()
        func box(_ r: NSRect) { round(r.offsetBy(dx: 0, dy: u), 4 * u).fill(with: NSColor(white: 0, alpha: 0.35)); let p = round(r, 4 * u); p.fill(with: paper); ink.setStroke(); p.lineWidth = u; p.stroke() }
        func teamDots(_ bs: [Bool], _ r: NSRect) { for (i, a) in bs.enumerated() { round(NSRect(x: r.minX + CGFloat(i) * 7 * u, y: r.minY, width: 5 * u, height: 5 * u), 2.5 * u).fill(with: a ? NSColor(red: 0.9, green: 0.22, blue: 0.2, alpha: 1) : NSColor(white: 0.7, alpha: 1)) } }
        // their box: name, Lv, (a trainer's team), bar
        let fr = NSRect(x: 6 * u, y: 6 * u, width: W - 12 * u, height: 26 * u)
        box(fr)
        label(m.foe.name, in: NSRect(x: fr.minX, y: fr.minY + 2 * u, width: fr.width, height: 10 * u), body, ink, alignLeft: 5 * u)
        label("Lv\(m.foe.level)", in: NSRect(x: fr.minX, y: fr.minY + 2 * u, width: fr.width, height: 10 * u), small, dim, alignRight: 5 * u)
        if !m.foeBalls.isEmpty { teamDots(m.foeBalls, NSRect(x: fr.maxX - 32 * u - CGFloat(m.foeBalls.count) * 7 * u, y: fr.minY + 4.5 * u, width: 0, height: 0)) }
        bar(fr.minX + 5 * u, fr.minY + 15 * u, fr.width - 10 * u, m.foe.hp, m.foe.max)
        // ours: + HP numbers (and the team)
        let mr = NSRect(x: 6 * u, y: 36 * u, width: W - 12 * u, height: 36 * u)
        box(mr)
        label(m.mine.name, in: NSRect(x: mr.minX, y: mr.minY + 2 * u, width: mr.width, height: 10 * u), body, ink, alignLeft: 5 * u)
        label("Lv\(m.mine.level)", in: NSRect(x: mr.minX, y: mr.minY + 2 * u, width: mr.width, height: 10 * u), small, dim, alignRight: 5 * u)
        bar(mr.minX + 5 * u, mr.minY + 15 * u, mr.width - 10 * u, m.mine.hp, m.mine.max)
        label("\(m.mine.hp) / \(m.mine.max)", in: NSRect(x: mr.minX, y: mr.minY + 24 * u, width: mr.width, height: 9 * u), body, ink, alignRight: 5 * u)
        if !m.myBalls.isEmpty { teamDots(m.myBalls, NSRect(x: mr.minX + 5 * u, y: mr.minY + 26 * u, width: 0, height: 0)) }
        // message: the DS dialogue box, double frame
        let msg = NSRect(x: 6 * u, y: 77 * u, width: W - 12 * u, height: 30 * u)
        round(msg, 3 * u).fill(with: ink); round(msg.insetBy(dx: u, dy: u), 2.5 * u).fill(with: NSColor(red: 0.62, green: 0.70, blue: 0.86, alpha: 1)); round(msg.insetBy(dx: 2 * u, dy: 2 * u), 2 * u).fill(with: paper)
        var lines: [String] = [], cur = ""                                                        // wrap by hand so each line goes through the pixel-snapped text()
        for ch in m.message { if width(cur + String(ch), body) > msg.width - 10 * u { lines.append(cur); cur = "" }; cur.append(ch) }
        lines.append(cur)
        for (j, l) in lines.prefix(2).enumerated() { text(l.trimmingCharacters(in: .whitespaces), msg.minX + 5 * u, msg.minY + 4 * u + CGFloat(j) * 11 * u, body, ink) }
        // buttons
        func button(_ r: NSRect, _ c: NSColor, _ on: Bool, _ idx: Int) {
            round(r.offsetBy(dx: 0, dy: 1.5 * u), 4 * u).fill(with: c.blended(withFraction: 0.55, of: .black)!)                       // the lip
            let p = round(r, 4 * u)
            NSGraphicsContext.saveGraphicsState(); p.addClip()
            NSGradient(starting: c.blended(withFraction: 0.18, of: .white)!, ending: c)!.draw(in: r, angle: -90)
            NSColor(white: 1, alpha: 0.28).setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 2 * u).fill()
            NSGraphicsContext.restoreGraphicsState()
            (on ? NSColor.white : c.blended(withFraction: 0.6, of: .black)!).setStroke(); p.lineWidth = on ? 2 * u : u; p.stroke()
            hits.append((r, idx))
        }
        let shadow = NSColor(white: 0, alpha: 0.45), top = 112 * u, bottom = H - 7 * u
        let colors: [String: NSColor] = ["공격": NSColor(red: 0.90, green: 0.26, blue: 0.24, alpha: 1), "볼": NSColor(red: 0.95, green: 0.72, blue: 0.14, alpha: 1),
                                         "도구": NSColor(red: 0.28, green: 0.70, blue: 0.36, alpha: 1), "교체": NSColor(red: 0.28, green: 0.70, blue: 0.36, alpha: 1),
                                         "도망": NSColor(red: 0.24, green: 0.50, blue: 0.90, alpha: 1), "기권": NSColor(red: 0.50, green: 0.52, blue: 0.58, alpha: 1)]
        switch m.mode {
        case .none: break
        case .menu(let opts, let sel):                                                            // big FIGHT, three below
            let bigR = NSRect(x: 6 * u, y: top, width: W - 12 * u, height: 26 * u)
            button(bigR, colors[opts[0]] ?? .red, sel == 0, 0); label(opts[0], in: bigR, big, .white, shadow: shadow)
            let bw = (W - 12 * u - 6 * u) / 3, y2 = bigR.maxY + 5 * u
            for i in 1..<opts.count {
                let r = NSRect(x: 6 * u + CGFloat(i - 1) * (bw + 3 * u), y: y2, width: bw, height: bottom - y2)
                button(r, colors[opts[i]] ?? .gray, sel == i, i); label(opts[i], in: r, body, .white, shadow: shadow)
            }
        case .moves(let ms, let sel):                                                             // four type-coloured plates
            let gw = (W - 12 * u - 4 * u) / 2, gh = (bottom - top - 4 * u) / 2
            for (i, mv) in ms.enumerated() {
                let r = NSRect(x: 6 * u + CGFloat(i % 2) * (gw + 4 * u), y: top + CGFloat(i / 2) * (gh + 4 * u), width: gw, height: gh), c = typeColor[mv.type] ?? .gray
                button(r, c, i == sel, i)
                label(mv.name, in: NSRect(x: r.minX, y: r.minY + 1.5 * u, width: r.width, height: r.height * 0.52), body, .white, shadow: shadow)
                let tk = typeKo[mv.type] ?? mv.type, badge = NSRect(x: r.minX + 3 * u, y: r.maxY - 9.5 * u, width: width(tk, small) + 6 * u, height: 7.5 * u)
                round(badge, 3.5 * u).fill(with: NSColor(white: 0, alpha: 0.3)); label(tk, in: badge, small, .white)
                let e = mv.effect == 0 ? "× 없음" : mv.effect > 1 ? "▲ 굉장" : mv.effect < 1 ? "▼ 별로" : "위력 \(mv.power)"
                label(e, in: NSRect(x: r.minX, y: badge.minY, width: r.width, height: badge.height), small,
                      mv.effect > 1 ? NSColor(red: 1, green: 0.95, blue: 0.5, alpha: 1) : .white, shadow: shadow, alignRight: 3 * u)
            }
        case .party(let ps, let sel):
            let rh = (bottom - top - 2 * 3 * u) / 3
            for (i, p) in ps.enumerated() {
                let r = NSRect(x: 6 * u, y: top + CGFloat(i) * (rh + 3 * u), width: W - 12 * u, height: rh)
                button(r, p.hp > 0 ? NSColor(red: 0.28, green: 0.56, blue: 0.80, alpha: 1) : NSColor(white: 0.45, alpha: 1), i == sel, i)
                let row = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - 4 * u)
                label((p.out ? "▶ " : "") + p.name + "  Lv\(p.level)", in: row, small, .white, shadow: shadow, alignLeft: 4 * u)
                label("\(p.hp)/\(p.max)", in: row, small, .white, shadow: shadow, alignRight: 4 * u)
                let br = NSRect(x: r.minX + 4 * u, y: r.maxY - 4.5 * u, width: r.width - 8 * u, height: 2 * u), f = p.max > 0 ? CGFloat(p.hp) / CGFloat(p.max) : 0
                ink.setFill(); br.fill(); hpColor(f).setFill(); NSRect(x: br.minX, y: br.minY, width: br.width * f, height: br.height).fill()
            }
        }
        switch m.mode {                                                                           // "◀ 뒤로" on the dialogue box
        case .moves, .party:
            let r = NSRect(x: msg.maxX - 30 * u, y: msg.maxY - 12 * u, width: 26 * u, height: 9 * u)
            round(r, 4.5 * u).fill(with: ink); label("◀ 뒤로", in: r, small, .white); hits.append((r, -1))
        default: break
        }
        window?.invalidateCursorRects(for: self)
    }
}
extension SideView {
    /// The Pokédex page: a red handheld-dex body, a white entry card (types, base stats), where to find it, how it evolves, and a number strip.
    func drawDex(_ d: DexModel) {
        let u = SideView.unit(backing), W = bounds.width, ink = SideView.ink, dim = SideView.dim, red = NSColor(red: 0.80, green: 0.20, blue: 0.18, alpha: 1)
        let bodyPath = round(bounds.insetBy(dx: u / 2, dy: u / 2), 9 * u)
        NSGraphicsContext.saveGraphicsState(); bodyPath.addClip()
        NSGradient(starting: NSColor(red: 0.90, green: 0.24, blue: 0.22, alpha: 1), ending: NSColor(red: 0.66, green: 0.12, blue: 0.13, alpha: 1))!.draw(in: bounds, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        ink.setStroke(); bodyPath.lineWidth = 1.2; bodyPath.stroke()
        round(NSRect(x: 6 * u, y: 5 * u, width: 10 * u, height: 10 * u), 5 * u).fill(with: .white)                  // the blue lens
        round(NSRect(x: 7.5 * u, y: 6.5 * u, width: 7 * u, height: 7 * u), 3.5 * u).fill(with: NSColor(red: 0.30, green: 0.62, blue: 0.95, alpha: 1))
        let head = NSRect(x: 0, y: 4 * u, width: W, height: 12 * u)
        label("도감", in: head, body, .white, alignLeft: 19 * u)
        label("잡음 \(d.owned) · 봤음 \(d.seen)", in: head, small, NSColor(white: 1, alpha: 0.9), alignRight: 7 * u)
        func panel(_ r: NSRect) { let p = round(r, 4 * u); p.fill(with: NSColor(white: 0.98, alpha: 1)); ink.setStroke(); p.lineWidth = u; p.stroke() }
        // entry card
        let card = NSRect(x: 5 * u, y: 19 * u, width: W - 10 * u, height: 76 * u)
        panel(card)
        let title = NSRect(x: card.minX, y: card.minY + 2 * u, width: card.width, height: 11 * u)
        label(String(format: "No.%03d  ", d.num) + d.name, in: title, body, d.status > 0 ? ink : dim, alignLeft: 5 * u)
        if d.status > 0 {
            let tag = d.status == 2 ? (d.shiny ? "★ 이로치" : "잡음") : "봤음", tw = width(tag, small) + 8 * u
            let tr = NSRect(x: card.maxX - 5 * u - tw, y: title.minY + 1.5 * u, width: tw, height: 8 * u)
            round(tr, 4 * u).fill(with: d.status == 2 ? NSColor(red: 0.90, green: 0.26, blue: 0.24, alpha: 1) : dim); label(tag, in: tr, small, .white)
            var x = card.minX + 5 * u
            for ty in d.types {
                let str = typeKo[ty] ?? ty, r = NSRect(x: x, y: card.minY + 15 * u, width: width(str, small) + 9 * u, height: 8.5 * u)
                round(r, 2.5 * u).fill(with: typeColor[ty] ?? .gray); label(str, in: r, small, .white); x += r.width + 3 * u
            }
            for (j, (name, v)) in zip(["HP", "공격", "방어", "특공", "특방", "스피드"], d.stats).enumerated() {
                let row = NSRect(x: card.minX, y: card.minY + 26 * u + CGFloat(j) * 8 * u, width: card.width, height: 8 * u)
                label(name, in: row, small, dim, alignLeft: 5 * u)
                label("\(v)", in: row, small, ink, alignRight: 5 * u)
                let bx = card.minX + 29 * u, bw = card.width - 29 * u - 20 * u, br = NSRect(x: bx, y: row.midY - 1.75 * u, width: bw, height: 3.5 * u)
                round(br, 1.75 * u).fill(with: NSColor(white: 0.88, alpha: 1))
                let c = v >= 100 ? NSColor(red: 0.28, green: 0.72, blue: 0.40, alpha: 1) : v >= 60 ? NSColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 1) : NSColor(red: 0.90, green: 0.36, blue: 0.30, alpha: 1)
                round(NSRect(x: bx, y: br.minY, width: bw * CGFloat(min(v, 180)) / 180, height: br.height), 1.75 * u).fill(with: c)
            }
        } else { label("아직 만나지 못했다", in: card, body, dim) }
        // where + evolutions
        let info = NSRect(x: 5 * u, y: 99 * u, width: W - 10 * u, height: 66 * u)
        panel(info)
        if d.status > 0 {
            func line(_ str: String, _ j: CGFloat, _ c: NSColor, _ f: NSFont) { label(str, in: NSRect(x: info.minX, y: info.minY + 2 * u + j * 8.5 * u, width: info.width - 5 * u, height: 8.5 * u), f, c, alignLeft: 5 * u) }
            line("만나는 곳", 0, red, small)
            for (j, str) in (d.found.isEmpty ? ["알 수 없음"] : d.found).enumerated() { line("· " + fit(str, info.width - 14 * u), CGFloat(1 + j), ink, small) }
            line("진화", 4, red, small)
            for (j, str) in (d.evos.isEmpty ? ["더 이상 진화하지 않는다"] : d.evos).enumerated() { line(fit(str, info.width - 10 * u), CGFloat(5 + j), d.evos.isEmpty ? dim : ink, small) }
        }
        // number strip: white = caught, pale = seen, dark = not met; click a met one to go there
        let cw = (W - 10 * u) / 10
        for (j, (n, st)) in zip(d.strip, d.stripStatus).enumerated() {
            let r = NSRect(x: 5 * u + CGFloat(j) * cw, y: 169 * u, width: cw - 1.5 * u, height: 12 * u)
            round(r, 2.5 * u).fill(with: st == 2 ? NSColor.white : st == 1 ? NSColor(white: 1, alpha: 0.55) : NSColor(white: 0, alpha: 0.2))
            if n == d.num { let p = round(r, 2.5 * u); NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 1).setStroke(); p.lineWidth = 1.5 * u; p.stroke() }
            label("\(n)", in: r, small, st == 0 ? NSColor(white: 1, alpha: 0.7) : n == d.num ? red : ink)
            if st > 0 { hits.append((r, 1000 + n)) }
        }
        window?.invalidateCursorRects(for: self)
    }
    func fit(_ str: String, _ w: CGFloat) -> String { var x = str; while x.count > 1, width(x, small) > w { x = String(x.dropLast(2)) + "…" }; return x }
}
extension NSBezierPath { func fill(with c: NSColor) { c.setFill(); fill() } }
/// The panel beside the device; a child window, so it moves with it. Sits on whichever side has room.
final class SidePanel: NSPanel {
    let view = SideView()
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false; backgroundColor = .clear; hasShadow = true; level = .floating; hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; contentView = view
    }
    func show(_ m: SideModel?, dex: DexModel?, beside parent: NSWindow?) {
        guard m != nil || dex != nil, let parent else { if isVisible { parent?.removeChildWindow(self); orderOut(nil) }; view.model = nil; view.dex = nil; return }
        let u = SideView.unit(parent.backingScaleFactor), size = NSSize(width: 140 * u, height: (dex != nil ? 186 : 172) * u)   // grows with the text on a 1x screen
        if !isVisible {
            let f = parent.frame, room = parent.screen?.visibleFrame ?? f
            let x = f.maxX + 6 + size.width <= room.maxX ? f.maxX + 6 : f.minX - 6 - size.width
            setFrame(NSRect(x: x, y: f.maxY - size.height, width: size.width, height: size.height), display: false)
            parent.addChildWindow(self, ordered: .above); orderFrontRegardless()
        } else if frame.size != size { setContentSize(size) }
        if view.model != m || view.dex != dex { view.model = m; view.dex = dex; view.needsDisplay = true }
    }
}

// MARK: - app
if CommandLine.arguments.contains("--selftest") { exit(selftest() ? 0 : 1) }     // after the globals above: main.swift initialises them in order
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let view = WalkerView(state: Store.load())
let notifyDelegate = NotifyDelegate()
UNUserNotificationCenter.current().delegate = notifyDelegate
UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { @Sendable ok, _ in   // called off the main thread
    // An ad-hoc signed app (no Apple certificate) is refused outright (UNErrorDomain 1) — fall back to osascript's banners
    DispatchQueue.main.async { useOsascript = !ok }
}
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let b = statusItem?.button {
    b.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in                   // a Poké Ball, as a template so it follows the bar's colour
        let o = NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1.5)); o.lineWidth = 1.6; NSColor.black.setStroke(); o.stroke()
        let top = NSBezierPath(); top.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 6.5, startAngle: 0, endAngle: 180); top.close(); NSColor.black.setFill(); top.fill()
        NSColor.black.setFill(); NSRect(x: 1.5, y: 7.2, width: 13, height: 1.6).fill()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 5.6, y: 5.6, width: 4.8, height: 4.8)).fill()
        let btn = NSBezierPath(ovalIn: NSRect(x: 5.6, y: 5.6, width: 4.8, height: 4.8)); btn.lineWidth = 1.4; NSColor.black.setStroke(); btn.stroke()
        return true
    }
    b.image?.isTemplate = true
    b.imagePosition = .imageLeft
    b.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    b.target = view; b.action = #selector(WalkerView.statusClick(_:)); b.sendAction(on: [.leftMouseUp, .rightMouseUp])
    b.toolTip = "PokeWalker — 클릭: 보이기/숨기기 · 우클릭: 메뉴"
}
view.state.dex()
view.levelled = view.state.sync(counter: WalkerView.counter(), boot: WalkerView.boot(), at: Date())      // steps typed while the app was quit (same login) count
view.save(nil)
final class Panel: NSPanel { override var canBecomeKey: Bool { true } }                    // arrow keys work after a click; still never activates the app
let panel = Panel(contentRect: NSRect(origin: .zero, size: devSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.hidesOnDeactivate = false
panel.becomesKeyOnlyIfNeeded = true
panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
panel.contentView = view
if !panel.setFrameUsingName("pokewalker"), let s = NSScreen.screens.first {
    panel.setFrameOrigin(NSPoint(x: s.visibleFrame.maxX - devSize.width - 24, y: s.visibleFrame.minY + 24))
}
panel.setFrameAutosaveName("pokewalker")
panel.setContentSize(devSize)
if !UserDefaults.standard.bool(forKey: "hidden") { panel.orderFrontRegardless() }
let sidePanel = SidePanel(); sidePanel.view.walker = view; view.side = sidePanel; view.sideOn = true
panel.makeFirstResponder(view)

let timer = Timer(timeInterval: 0.1, target: view, selector: #selector(WalkerView.tick(_:)), userInfo: nil, repeats: true)
timer.tolerance = 0.02
RunLoop.main.add(timer, forMode: .common)
let ws = NSWorkspace.shared.notificationCenter
ws.addObserver(view, selector: #selector(WalkerView.save(_:)), name: NSWorkspace.willSleepNotification, object: nil)
NotificationCenter.default.addObserver(view, selector: #selector(WalkerView.save(_:)), name: NSApplication.willTerminateNotification, object: nil)
app.run()

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
