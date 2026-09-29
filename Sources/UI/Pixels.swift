import AppKit
// Sprites, hand-drawn bits, the fonts and the 96x64 frame buffer.

// MARK: - pixels
/// HGSS battle sprites (tools/gen.py): per species 15 normal + 15 shiny RGB, then front and back 80x80 at 4 bpp; index 0 = transparent.
let hgssData: Data = {
    guard let u = Bundle.main.url(forResource: "hgss", withExtension: "bin"), let d = try? Data(contentsOf: u), d.count == 493 * 6490 else { return Data(count: 493 * 6490) }
    return d
}()
/// 0 = transparent, else 0xFFRRGGBB.
func spritePixel(_ dex: Int, back: Bool, _ x: Int, _ y: Int, shiny: Bool) -> UInt32 {
    let o = (dex - 1) * 6490, b = hgssData[o + 90 + (back ? 3200 : 0) + y * 40 + x / 2], i = Int(x % 2 == 0 ? b >> 4 : b & 15)
    guard i > 0 else { return 0 }
    let p = o + (shiny ? 45 : 0) + (i - 1) * 3
    return rgb(hgssData[p], hgssData[p + 1], hgssData[p + 2])
}
/// The first opaque row of a frame (gen.py stands every frame on row 79), for what sits over its head.
@MainActor var spriteTops: [Int: Int] = [:]
@MainActor func spriteTop(_ dex: Int, back: Bool = false) -> Int {
    if let t = spriteTops[dex * 2 + (back ? 1 : 0)] { return t }
    let t: Int = (0..<80).first(where: { y in (0..<80).contains { spritePixel(dex, back: back, $0, y, shiny: false) != 0 } }) ?? 79
    spriteTops[dex * 2 + (back ? 1 : 0)] = t; return t
}
/// A sprite laid over the dots at 1 pt per pixel (x 1.5 / x 2 on the bigger sizes): its 80x80 box is 32x32 dots at (x, y); `floor` = the dot row it sinks behind.
struct SpriteRun: Equatable { var dex: Int; var shiny, back: Bool; var x, y, bob: Int; var tint: UInt32?, tintShade: UInt8; var floor: Int; var inverted = false }
@MainActor var spriteCache: [String: NSImage] = [:]
/// The sprite as the LCD shows it: its colours, or on a grey screen 4 shades by brightness (white = the blank screen, like the walker's own art); a tint = a silhouette.
/// Inverted (a full-screen flash) = the grey shades flipped, on any screen, as the dots are.
@MainActor func spriteImage(_ r: SpriteRun, _ l: LCD) -> NSImage {
    let key = "\(r.dex) \(r.shiny) \(r.back) \(l.name) \(r.tint ?? 0) \(r.tintShade) \(r.inverted)"
    if let i = spriteCache[key] { return i }
    if spriteCache.count > 64 { spriteCache.removeAll() }                                   // ponytail: drop all at 64, an LRU if browsing ever stutters
    let shades = l.shades.map { c -> UInt32 in let s = c.usingColorSpace(.sRGB)!; return rgb(UInt8(s.redComponent * 255), UInt8(s.greenComponent * 255), UInt8(s.blueComponent * 255)) }
    var px = [UInt32](repeating: 0, count: 80 * 80)
    for y in 0..<80 { for x in 0..<80 {
        let c = spritePixel(r.dex, back: r.back, x, y, shiny: r.shiny)
        guard c != 0 else { continue }
        let lum = (0.299 * Double(c >> 16 & 255) + 0.587 * Double(c >> 8 & 255) + 0.114 * Double(c & 255)) / 255
        let shade = Int(r.tint != nil ? r.tintShade : lum > 0.78 ? 0 : lum > 0.5 ? 1 : lum > 0.25 ? 2 : 3)
        px[y * 80 + x] = r.inverted ? shades[3 - shade] : l.color ? r.tint ?? c : shades[shade]
    } }
    let i = image(px, 80); spriteCache[key] = i; return i
}
/// A square of 0xFFRRGGBB pixels (0 = clear) as an image, for drawing without smoothing.
func image(_ px: [UInt32], _ side: Int) -> NSImage {
    let img = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                      provider: CGDataProvider(data: px.withUnsafeBufferPointer { Data(buffer: $0) } as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return NSImage(cgImage: img, size: NSSize(width: side, height: side))
}
/// The Gen IV box icons (tools/gen.py): per species 15 RGB, then 32x32 at 4 bpp; index 0 = transparent.
let iconData: Data = {
    guard let u = Bundle.main.url(forResource: "icons", withExtension: "bin"), let d = try? Data(contentsOf: u), d.count == 493 * 557 else { return Data(count: 493 * 557) }
    return d
}()
func iconPixel(_ dex: Int, _ x: Int, _ y: Int) -> UInt32 {
    let o = (dex - 1) * 557, b = iconData[o + 45 + y * 16 + x / 2], i = Int(x % 2 == 0 ? b >> 4 : b & 15)
    return i > 0 ? rgb(iconData[o + (i - 1) * 3], iconData[o + (i - 1) * 3 + 1], iconData[o + (i - 1) * 3 + 2]) : 0
}
@MainActor var iconCache: [Int: NSImage] = [:]                                            // at most 493 x 2 small images
/// A species' box icon in colour, or (shadow) as a dark silhouette: seen, not caught.
@MainActor func iconImage(_ dex: Int, shadow: Bool = false) -> NSImage {
    if let i = iconCache[dex * 2 + (shadow ? 1 : 0)] { return i }
    let px = (0..<1024).map { k -> UInt32 in let c = iconPixel(dex, k % 32, k / 32); return c == 0 ? 0 : shadow ? rgb(54, 58, 70) : c }
    let i = image(px, 32); iconCache[dex * 2 + (shadow ? 1 : 0)] = i; return i
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
let vDiamond = art(["__#__", "_#:#_", "#:::#", "_#:#_", "__#__"])            // 3V and up (a diamond: the sparkle means 이로치)
let vPal = [rgb(250, 250, 250), rgb(250, 250, 250), rgb(245, 178, 40), rgb(160, 100, 10)]
let caughtMark = art(["_###_", "#:::#", "#####", "#...#", "_###_"])        // a 5-dot Poké Ball: species caught before
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
@MainActor var textCache: [String: [[Bool]]] = [:]
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
@MainActor var smoothText = UserDefaults.standard.object(forKey: "smoothText") as? Bool ?? true
@MainActor func lcdFont(_ small: Bool) -> NSFont { .systemFont(ofSize: (small ? 6.5 : 8) * PX, weight: small ? .regular : .medium) }
/// A string's width in LCD dots, in whichever text style is on (layout, centring and tap targets all use this).
@MainActor func textWidth(_ s: String, small: Bool = false) -> Int {
    smoothText ? Int(ceil((s as NSString).size(withAttributes: [.font: lcdFont(small)]).width / PX)) : (textDots(s, small: small).first?.count ?? 0)
}
struct TextRun: Equatable { var s: String; var x, y, w, rows: Int; var small: Bool; var shade: UInt8 }


@MainActor struct FB {
    var px = [UInt8](repeating: 0, count: 96 * 64)
    var col = [UInt32](repeating: 0, count: 96 * 64)                      // colour LCD only: 0 = use the shade
    var runs: [TextRun] = [], flips: [[Int]] = []                        // smooth text to draw over the dots, and the inverted boxes it may sit in
    var sprites: [SpriteRun] = []
    var over = [Bool](repeating: false, count: 96 * 64)                  // dots set after a sprite: drawn on top of it (a HUD plate, a ball, rain)
    mutating func set(_ x: Int, _ y: Int, _ s: UInt8, _ c: UInt32 = 0) { if (0..<96).contains(x), (0..<64).contains(y) { px[y * 96 + x] = s; col[y * 96 + x] = c; if !sprites.isEmpty { over[y * 96 + x] = true } } }
    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ s: UInt8) { for yy in y..<y + h { for xx in x..<x + w { set(xx, yy, s) } } }
    mutating func draw(_ a: [[UInt8?]], _ x: Int, _ y: Int, _ pal: [UInt32]? = nil, scale k: Int = 1) {
        for (dy, r) in a.enumerated() { for (dx, s) in r.enumerated() { if let s { for i in 0..<k * k { set(x + dx * k + i % k, y + dy * k + i / k, s, pal?[Int(s)] ?? 0) } } } }
    }
    /// A Pokémon in the old 64x48 box: its 32x32 sprite centred across, standing on the box's bottom. f = 1 bobs it a pixel.
    mutating func mon(_ m: Mon, _ f: Int, _ x: Int, _ y: Int, flash: Bool = false, tint: (UInt8, UInt32)? = nil) {   // flash = red silhouette (the ball's beam); tint = any silhouette
        sprite(m, x + 16, y + 16, bob: f, flash: flash, tint: tint)
    }
    mutating func sprite(_ m: Mon, _ x: Int, _ y: Int, back: Bool = false, bob: Int = 0, flash: Bool = false, tint: (UInt8, UInt32)? = nil, floor: Int = 64) {
        let t = tint ?? (flash ? (2, rgb(238, 84, 72)) : nil)
        sprites.append(SpriteRun(dex: m.dex, shiny: m.shiny == true, back: back, x: x, y: y, bob: bob, tint: t?.1, tintShade: t?.0 ?? 0, floor: floor))
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
            case .snow: if (UInt32(truncatingIfNeeded: (x + (y + f / 3) / 4 % 2) &* 73_856_093) ^ UInt32(truncatingIfNeeded: (y - f / 2 + 10_000) &* 19_349_663)) % 41 == 0 { set(X, Y, 1, px[Y * 96 + X] == 0 && col[Y * 96 + X] == 0 && !sprites.contains { (0..<32).contains(X - $0.x) && (0..<32).contains(Y - $0.y) } ? rgb(150, 176, 214) : rgb(252, 252, 255)) }   // blue-grey on the bare screen, white on pictures   // hashed flakes, falling and swaying
            case .fog: if (y + f / 6) % 6 == 0, (x + y * 3 + f / 3) % 3 != 0 { set(X, Y, 1, cave ? rgb(150, 144, 150) : rgb(206, 210, 218)) }
            case .sunny: break
            }
        } }
    }
    /// A box turned negative. The whole screen (a critical hit, a legend) flips the sprites with it; a smaller box (a highlight) covers them.
    mutating func invert(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        flips.append([x, y, w, h])
        let whole = x <= 0 && y <= 0 && x + w >= 96 && y + h >= 64
        if whole { for i in sprites.indices { sprites[i].inverted.toggle() } }
        for yy in y..<y + h { for xx in x..<x + w where (0..<96).contains(xx) && (0..<64).contains(yy) { px[yy * 96 + xx] = 3 - px[yy * 96 + xx]; col[yy * 96 + xx] = 0; if !sprites.isEmpty, !whole { over[yy * 96 + xx] = true } } }
    }
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
