import AppKit
// Sprites, hand-drawn bits, the fonts and the 96x64 frame buffer.

// MARK: - pixels
/// HGSS battle sprites (tools/gen.py): per species 15 normal + 15 shiny RGB, then front and back 80x80 at 4 bpp; index 0 = transparent.
let hgssData: Data = {
    guard let d = resource("hgss.bin"), d.count == 493 * 6490 else { return Data(count: 493 * 6490) }
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
/// A sprite laid over the dots at 1 pt per pixel (x 1.5 / x 2 on the bigger sizes): its 80x80 frame (40x40 dots) stands on (x + 16, y + 32); `floor` = the dot row it sinks behind.
/// scale (about the feet) and alpha: growing out of / shrinking into a ball; frame = one of its animation's (Anim.swift; nil = the static sprite).
struct SpriteRun: Equatable { var dex: Int; var shiny, back: Bool; var x, y, bob: Int; var tint: UInt32?, tintShade: UInt8; var floor: Int; var inverted = false; var scale = 1.0, alpha = 1.0; var frame: Int? = nil }
@MainActor var spriteCache: [String: NSImage] = [:]
/// The sprite as the LCD shows it: its colours, or on a grey screen 4 shades by brightness (white = the blank screen, like the walker's own art); a tint = a silhouette.
/// Inverted (a full-screen flash) = the grey shades flipped, on any screen, as the dots are.
@MainActor func spriteImage(_ r: SpriteRun, _ l: LCD) -> NSImage {
    let key = "\(r.dex) \(r.shiny) \(r.back) \(l.name) \(r.tint ?? 0) \(r.tintShade) \(r.inverted) \(r.frame ?? -1)"
    if let i = spriteCache[key] { return i }
    if spriteCache.count > 64 { spriteCache.removeAll() }                                   // ponytail: drop all at 64, an LRU if browsing ever stutters
    let shades = l.shades.map { c -> UInt32 in let s = c.usingColorSpace(.sRGB)!; return rgb(UInt8(s.redComponent * 255), UInt8(s.greenComponent * 255), UInt8(s.blueComponent * 255)) }
    let a = playing(r), w = a?.w ?? 80, h = a?.h ?? 80                                         // an animation frame: its own box
    var px = [UInt32](repeating: 0, count: w * h)
    for y in 0..<h { for x in 0..<w {
        let c = a.map { $0.pixel(r.frame!, x, y, shiny: r.shiny) } ?? spritePixel(r.dex, back: r.back, x, y, shiny: r.shiny)
        guard c != 0 else { continue }
        let lum = (0.299 * Double(c >> 16 & 255) + 0.587 * Double(c >> 8 & 255) + 0.114 * Double(c & 255)) / 255
        let shade = Int(r.tint != nil ? r.tintShade : lum > 0.78 ? 0 : lum > 0.5 ? 1 : lum > 0.25 ? 2 : 3)
        px[y * w + x] = r.inverted ? shades[3 - shade] : l.color ? r.tint ?? c : shades[shade]
    } }
    let i = image(px, w, h); spriteCache[key] = i; return i
}
/// 0xAARRGGBB pixels (0 = clear; any alpha) as a w x h image (square if h is left out), for drawing without smoothing.
func image(_ px: [UInt32], _ side: Int, _ h: Int? = nil) -> NSImage {
    let h = h ?? side
    let pre = px.map { c -> UInt32 in                                                               // premultiplied, as CGImage wants it
        let a = c >> 24; guard a < 255 else { return c }
        let r: UInt32 = (c >> 16 & 255) * a / 255, g: UInt32 = (c >> 8 & 255) * a / 255, b: UInt32 = (c & 255) * a / 255
        return a << 24 | r << 16 | g << 8 | b
    }
    let img = CGImage(width: side, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                      provider: CGDataProvider(data: pre.withUnsafeBufferPointer { Data(buffer: $0) } as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return NSImage(cgImage: img, size: NSSize(width: side, height: h))
}

// MARK: - pictures
/// A picture at sprite resolution (1 pixel = half a dot, like the battle sprites): 0xAARRGGBB, 0 = clear, any alpha.
struct Pic {
    var w, h: Int, px: [UInt32]
    init(w: Int, h: Int) { self.w = w; self.h = h; px = Array(repeating: 0, count: w * h) }
    /// Hand-drawn: one character a pixel, looked up in pal (anything not in it = clear).
    init(_ rows: [String], _ pal: [Character: UInt32]) {
        self.init(w: rows.map(\.count).max() ?? 0, h: rows.count)
        for (y, r) in rows.enumerated() { for (x, c) in r.enumerated() { px[y * w + x] = pal[c] ?? 0 } }
    }
    func at(_ x: Int, _ y: Int) -> UInt32 { (0..<w).contains(x) && (0..<h).contains(y) ? px[y * w + x] : 0 }
    mutating func set(_ x: Int, _ y: Int, _ c: UInt32) { if (0..<w).contains(x), (0..<h).contains(y) { px[y * w + x] = c } }
    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32) { for yy in y..<y + h { for xx in x..<x + w { set(xx, yy, c) } } }
    /// Another picture laid on this one, its top-left at (x, y) (clear pixels skipped).
    mutating func paste(_ p: Pic, _ x: Int, _ y: Int) { for yy in 0..<p.h { for xx in 0..<p.w where p.px[yy * p.w + xx] != 0 { set(x + xx, y + yy, p.px[yy * p.w + xx]) } } }
}
/// Where a picture goes: centred on (x, y) in half-dots (the LCD is 192 x 128 of them), scaled and turned (degrees, clockwise) about its centre;
/// behind = under the sprites (a backdrop), else over them (a ball, a move's effect).
struct PicRun: Equatable { var key: String; var x, y: Int; var scale = 1.0, alpha = 1.0, angle = 0.0; var behind = false; var inverted = false; var clip: [Int] = [] }   // clip: x, y, w, h in half-dots
/// Every picture drawn so far, by key. Keys must come from a finite set (animate with position / scale / alpha / angle or a bounded frame number):
/// the store is never emptied, so a frame's FB can be redrawn any time.
@MainActor var picStore: [String: Pic] = [:]
@MainActor var picImages: [String: NSImage] = [:]
/// A picture as the LCD shows it: its colours, or on a grey screen 4 shades by brightness (as the sprites); inverted = a full-screen flash.
@MainActor func picImage(_ r: PicRun, _ l: LCD) -> (NSImage, Pic)? {
    guard let p = picStore[r.key] else { return nil }
    let key = r.key + "|" + l.name + (r.inverted ? "~" : "")
    if let i = picImages[key] { return (i, p) }
    let shades = l.shades.map { c -> UInt32 in let s = c.usingColorSpace(.sRGB)!; return rgb(UInt8(s.redComponent * 255), UInt8(s.greenComponent * 255), UInt8(s.blueComponent * 255)) }
    let px = p.px.map { c -> UInt32 in
        guard c >> 24 > 0 else { return 0 }
        if l.color && !r.inverted { return c }
        let lum: Double = (0.299 * Double(c >> 16 & 255) + 0.587 * Double(c >> 8 & 255) + 0.114 * Double(c & 255)) / 255
        let shade: Int = lum > 0.78 ? 0 : lum > 0.5 ? 1 : lum > 0.25 ? 2 : 3, v: UInt32 = shades[r.inverted ? 3 - shade : shade]
        return (c & 0xFF00_0000) | (v & 0xFF_FFFF)
    }
    let i = image(px, p.w, p.h); picImages[key] = i; return (i, p)
}

/// Other 80x80 frames (tools/gen.py frames.bin): the HGSS egg, then the Battle Tower's trainers. Per frame 15 RGB, then 80x80 at 4 bpp; each stands on row 79.
let frameNames = ["egg", "acetrainer-gen4", "acetrainerf-gen4", "veteran-gen4", "veteranf", "lady-gen4", "hiker-gen4", "scientist-gen4", "blackbelt-gen4",
                  "battlegirl-gen4", "psychic-gen4", "psychicf-gen4", "dragontamer", "schoolkid-gen4", "pokemonranger-gen4", "pokemonrangerf-gen4"]
let frameData: Data = {
    guard let d = resource("frames.bin"), d.count == frameNames.count * 3245 else { return Data(count: frameNames.count * 3245) }
    return d
}()
/// A frame as a picture (for fb.pic): "egg", or a trainer's sprite name (see trainerFrame).
func framePic(_ name: String) -> Pic {
    var p = Pic(w: 80, h: 80)
    guard let f = frameNames.firstIndex(of: name) else { return p }
    let o = f * 3245
    for y in 0..<80 { for x in 0..<80 {
        let b = frameData[o + 45 + y * 40 + x / 2], i = Int(x % 2 == 0 ? b >> 4 : b & 15)
        if i > 0 { p.set(x, y, rgb(frameData[o + (i - 1) * 3], frameData[o + (i - 1) * 3 + 1], frameData[o + (i - 1) * 3 + 2])) }
    } }
    return p
}
/// A tower trainer's sprite, by class (the name's first words) and, where a class has both, the given name's sex.
func trainerFrame(_ trainer: String) -> String {
    let female = ["지은", "서연", "하은", "유나", "보라"].contains { trainer.hasSuffix($0) }
    for (cls, m, f) in [("엘리트 트레이너", "acetrainer-gen4", "acetrainerf-gen4"), ("베테랑", "veteran-gen4", "veteranf"), ("아가씨", "lady-gen4", "lady-gen4"),
                        ("등산가", "hiker-gen4", "hiker-gen4"), ("연구원", "scientist-gen4", "scientist-gen4"), ("격투가", "blackbelt-gen4", "battlegirl-gen4"),
                        ("사이킥", "psychic-gen4", "psychicf-gen4"), ("드래곤 조련사", "dragontamer", "dragontamer"), ("모범 소년", "schoolkid-gen4", "schoolkid-gen4"),
                        ("레인저", "pokemonranger-gen4", "pokemonrangerf-gen4")] where trainer.hasPrefix(cls) { return female ? f : m }
    return female ? "acetrainerf-gen4" : "acetrainer-gen4"
}
/// The Gen IV box icons (tools/gen.py): per species 15 RGB, then 32x32 at 4 bpp; index 0 = transparent.
let iconData: Data = {
    guard let d = resource("icons.bin"), d.count == 493 * 557 else { return Data(count: 493 * 557) }
    return d
}()
func iconPixel(_ dex: Int, _ x: Int, _ y: Int) -> UInt32 {
    let o = (dex - 1) * 557, b = iconData[o + 45 + y * 16 + x / 2], i = Int(x % 2 == 0 ? b >> 4 : b & 15)
    return i > 0 ? rgb(iconData[o + (i - 1) * 3], iconData[o + (i - 1) * 3 + 1], iconData[o + (i - 1) * 3 + 2]) : 0
}
@MainActor var iconCache: [Int: NSImage] = [:]                                            // at most 493 x 2 small images
/// A species' box icon in colour, or (shadow) as a pale silhouette: seen, not caught.
@MainActor func iconImage(_ dex: Int, shadow: Bool = false) -> NSImage {
    if let i = iconCache[dex * 2 + (shadow ? 1 : 0)] { return i }
    let px = (0..<1024).map { k -> UInt32 in let c = iconPixel(dex, k % 32, k / 32); return c == 0 ? 0 : shadow ? rgb(196, 200, 208) : c }
    let i = image(px, 32); iconCache[dex * 2 + (shadow ? 1 : 0)] = i; return i
}
func dim(_ c: UInt32, _ k: Double) -> UInt32 { rgb(UInt8(Double(c >> 16 & 255) * k), UInt8(Double(c >> 8 & 255) * k), UInt8(Double(c & 255) * k)) }
func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt32 { 0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }
/// Colour-LCD palettes for the hand-drawn bits, by shade 0...3.
let ballPal = [rgb(250, 250, 250), rgb(250, 250, 250), rgb(222, 52, 44), rgb(30, 32, 40)]
let gemPal = [rgb(250, 250, 250), rgb(250, 250, 250), rgb(80, 140, 235), rgb(30, 32, 40)]

/// Hand-drawn bits: " .:#" = shade 0...3, "_" = transparent.
func art(_ rows: [String]) -> [[UInt8?]] { rows.map { $0.map { c in c == "_" ? nil : UInt8(" .:#".firstIndex(of: c).map { " .:#".distance(from: " .:#".startIndex, to: $0) } ?? 0) } } }
let ball = art(["__###__", "_#:::#_", "#:::::#", "###.###", "#.....#", "_#...#_", "__###__"])
let gem = art(["_#_", "#:#", "_#_"])
let vDiamond = art(["__#__", "_#:#_", "#:::#", "_#:#_", "__#__"])            // 3V and up (a diamond: the sparkle means 이로치)
let vPal = [rgb(250, 250, 250), rgb(250, 250, 250), rgb(245, 178, 40), rgb(160, 100, 10)]
let caughtMark = art(["_###_", "#:::#", "#####", "#...#", "_###_"])        // a 5-dot Poké Ball: species caught before
let legendDex = Set(courses.flatMap(\.legends))
let spark = art(["__#__", "__#__", "##:##", "__#__", "__#__"])
let sparkPal = [rgb(255, 236, 120), rgb(255, 236, 120), rgb(255, 250, 200), rgb(250, 190, 40)]

/// Galmuri (OFL, a pixel font drawn after the Nintendo DS system font) at its native sizes, so every glyph lands on whole dots: 9 at 10 px, 7 at 8 px, from the bundled files.
@MainActor let galmuri: [CTFont?] = [("Galmuri9", 10.0), ("Galmuri7", 8.0)].map { f, size in
    resource(f + ".ttf").flatMap { CTFontManagerCreateFontDescriptorFromData($0 as CFData) }.map { CTFontCreateWithFontDescriptor($0, size, nil) }
}
@MainActor var textCache: [String: [[Bool]]] = [:]
/// 11 rows (Galmuri9 10 px) or, small, 9 rows (Galmuri7 8 px); baseline one row up from the bottom.
@MainActor func textDots(_ s: String, small: Bool = false) -> [[Bool]] {
    let key = (small ? "s|" : "m|") + s
    if let t = textCache[key] { return t }
    let size: CGFloat = small ? 8 : 10, h = small ? 9 : 11
    let font: AnyObject = galmuri[small ? 1 : 0] ?? NSFont.systemFont(ofSize: size)
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
@MainActor var smoothText = settings.bool("smoothText", true)
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
    var pics: [PicRun] = []                                              // pictures at sprite resolution (see PicRun)
    var over = [Bool](repeating: false, count: 96 * 64)                  // dots set after a sprite: drawn on top of it (a HUD plate, a ball, rain)
    mutating func set(_ x: Int, _ y: Int, _ s: UInt8, _ c: UInt32 = 0) { if (0..<96).contains(x), (0..<64).contains(y) { px[y * 96 + x] = s; col[y * 96 + x] = c; if !sprites.isEmpty { over[y * 96 + x] = true } } }
    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ s: UInt8) { for yy in y..<y + h { for xx in x..<x + w { set(xx, yy, s) } } }
    mutating func draw(_ a: [[UInt8?]], _ x: Int, _ y: Int, _ pal: [UInt32]? = nil, scale k: Int = 1) {
        for (dy, r) in a.enumerated() { for (dx, s) in r.enumerated() { if let s { for i in 0..<k * k { set(x + dx * k + i % k, y + dy * k + i / k, s, pal?[Int(s)] ?? 0) } } } }
    }
    /// A Pokémon in the old 64x48 box: its sprite centred across, standing on the box's bottom. f = 1 bobs it a pixel.
    mutating func mon(_ m: Mon, _ f: Int, _ x: Int, _ y: Int, flash: Bool = false, tint: (UInt8, UInt32)? = nil, anim u: Double? = nil) {   // flash = red silhouette (the ball's beam); tint = any silhouette
        sprite(m, x + 16, y + 16, bob: f, flash: flash, tint: tint, anim: u)
    }
    /// anim = seconds into its entry animation (nil, < 0 or past its end: the static sprite); while a frame shows it doesn't bob.
    mutating func sprite(_ m: Mon, _ x: Int, _ y: Int, back: Bool = false, bob: Int = 0, flash: Bool = false, tint: (UInt8, UInt32)? = nil, floor: Int = 64, anim u: Double? = nil) {
        let t = tint ?? (flash ? (2, rgb(238, 84, 72)) : nil), f = back ? nil : u.flatMap { anim(m.dex)?.frame(at: $0) }
        sprites.append(SpriteRun(dex: m.dex, shiny: m.shiny == true, back: back, x: x, y: y, bob: f == nil ? bob : 0, tint: t?.1, tintShade: t?.0 ?? 0, floor: floor, frame: f))
    }
    /// A picture at sprite resolution centred on (x, y) in half-dots; `make` draws it the first time its key is seen (keys: a finite set).
    mutating func pic(_ key: String, _ x: Int, _ y: Int, scale: Double = 1, alpha: Double = 1, angle: Double = 0, behind: Bool = false, clip: [Int] = [], _ make: () -> Pic) {
        if picStore[key] == nil { picStore[key] = make() }
        pics.append(PicRun(key: key, x: x, y: y, scale: scale, alpha: alpha, angle: angle, behind: behind, clip: clip))
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
    /// A box turned negative. The whole screen (a critical hit, a legend) flips the sprites with it; a smaller box (a highlight) covers them.
    mutating func invert(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        flips.append([x, y, w, h])
        let whole = x <= 0 && y <= 0 && x + w >= 96 && y + h >= 64
        if whole { for i in sprites.indices { sprites[i].inverted.toggle() }; for i in pics.indices { pics[i].inverted.toggle() } }
        for yy in y..<y + h { for xx in x..<x + w where (0..<96).contains(xx) && (0..<64).contains(yy) { px[yy * 96 + xx] = 3 - px[yy * 96 + xx]; col[yy * 96 + xx] = 0; if !sprites.isEmpty, !whole { over[yy * 96 + xx] = true } } }
    }
}
