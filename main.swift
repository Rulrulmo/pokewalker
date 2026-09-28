import AppKit

// MARK: - geometry (points; flipped view). All in device dots x PX, so the size menu scales everything.
var PX = CGFloat(max(2, UserDefaults.standard.integer(forKey: "px")))    // 2 / 3 / 4
let dev = (w: CGFloat(144), h: CGFloat(144))                                                  // a Poké Ball: 144-dot circle, screen where the button would be
var devSize: NSSize { NSSize(width: dev.w * PX, height: dev.h * PX) }
var lcdRect: NSRect { NSRect(x: 24 * PX, y: 40 * PX, width: 96 * PX, height: 64 * PX) }      // 96x64 dots, 4 greys, like the real one; centred on the ball
var buttons: [(c: NSPoint, r: CGFloat)] {   // left, enter, right on the white half following its curve; home tucked under enter
    [(NSPoint(x: 49 * PX, y: 120 * PX), 4.6 * PX), (NSPoint(x: 72 * PX, y: 123 * PX), 6 * PX), (NSPoint(x: 95 * PX, y: 120 * PX), 4.6 * PX), (NSPoint(x: 72 * PX, y: 136.5 * PX), 3.4 * PX)]
}

struct Shell { let name: String; let top: NSColor }                  // the top half; the bottom is always white, the band black
let shells: [Shell] = [
    Shell(name: "몬스터볼", top: NSColor(red: 0.89, green: 0.20, blue: 0.19, alpha: 1)),
    Shell(name: "슈퍼볼", top: NSColor(red: 0.22, green: 0.46, blue: 0.86, alpha: 1)),
    Shell(name: "하이퍼볼", top: NSColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)),
    Shell(name: "마스터볼", top: NSColor(red: 0.47, green: 0.27, blue: 0.66, alpha: 1)),
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
/// 을/를, 이/가, 은/는 by the last syllable's final consonant.
func josa(_ w: String, _ with: String, _ without: String) -> String {
    guard let u = w.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(u) else { return w + without }
    return w + ((u - 0xAC00) % 28 != 0 ? with : without)
}

@MainActor struct FB {
    var px = [UInt8](repeating: 0, count: 96 * 64)
    var col = [UInt32](repeating: 0, count: 96 * 64)                      // colour LCD only: 0 = use the shade
    mutating func set(_ x: Int, _ y: Int, _ s: UInt8, _ c: UInt32 = 0) { if (0..<96).contains(x), (0..<64).contains(y) { px[y * 96 + x] = s; col[y * 96 + x] = c } }
    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ s: UInt8) { for yy in y..<y + h { for xx in x..<x + w { set(xx, yy, s) } } }
    mutating func draw(_ a: [[UInt8?]], _ x: Int, _ y: Int, _ pal: [UInt32]? = nil, scale k: Int = 1) {
        for (dy, r) in a.enumerated() { for (dx, s) in r.enumerated() { if let s { for i in 0..<k * k { set(x + dx * k + i % k, y + dy * k + i / k, s, pal?[Int(s)] ?? 0) } } } }
    }
    /// Large = 64x48; small = 32x24, each dot the darkest of its 2x2 (and that dot's colour). Grey shade 0 is see-through; in colour the white body isn't.
    mutating func mon(_ m: Mon, _ f: Int, _ x: Int, _ y: Int, small: Bool = false, flip: Bool = false, flash: Bool = false) {   // flash = red silhouette (into / out of the ball)
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
                if flash { px[Y * 96 + X] = 2; col[Y * 96 + X] = rgb(238, 84, 72) } else { if s > 0 { px[Y * 96 + X] = s }; col[Y * 96 + X] = c }
            }
        } }
    }
    /// Too wide for the screen => the small font, one row lower so baselines match.
    @discardableResult mutating func text(_ s: String, _ x: Int, _ y: Int, _ shade: UInt8 = 3, center: Bool = false, right: Bool = false, small: Bool = false) -> Int {
        var t = textDots(s, small: small), y = y + (small ? 1 : 0)
        if !small, (t.first?.count ?? 0) > 94 { t = textDots(s, small: true); y += 1 }
        let w = t.first?.count ?? 0, x0 = center ? (96 - w) / 2 : right ? x - w : x
        for (dy, r) in t.enumerated() { for (dx, on) in r.enumerated() where on { set(x0 + dx, y + dy, shade) } }
        return w
    }
    mutating func invert(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { for yy in y..<y + h { for xx in x..<x + w where (0..<96).contains(xx) && (0..<64).contains(yy) { px[yy * 96 + xx] = 3 - px[yy * 96 + xx]; col[yy * 96 + xx] = 0 } } }
    /// 32x24 picture of the course, framed.
    mutating func course(_ a: Art, _ x: Int, _ y: Int) {
        // colour: sky above the course's horizon, its ground/water below
        let horizon = [Art.field: 14, .forest: 17, .mountain: 19, .beach: 10, .lake: 12, .town: 19, .cave: 0][a]!
        let sky = [rgb(160, 208, 250), rgb(255, 222, 96), rgb(70, 150, 80), rgb(36, 44, 56)]
        let ground: [UInt32] = switch a {
        case .field, .forest, .town: [rgb(130, 204, 96), rgb(100, 180, 80), rgb(70, 150, 64), rgb(36, 80, 44)]
        case .mountain: [rgb(186, 156, 112), rgb(160, 130, 96), rgb(128, 100, 72), rgb(60, 44, 36)]
        case .beach, .lake: [rgb(96, 170, 240), rgb(80, 150, 230), rgb(96, 170, 96), rgb(40, 90, 180)]
        case .cave: [rgb(90, 76, 70), rgb(110, 96, 88), rgb(128, 108, 96), rgb(40, 32, 30)]
        }
        func p(_ dx: Int, _ dy: Int, _ s: UInt8) {
            guard (0..<32).contains(dx), (0..<24).contains(dy) else { return }
            var c = (dy < horizon ? sky : ground)[Int(s)]
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
        for dx in 0..<32 { p(dx, 0, 3); p(dx, 23, 3) }; for dy in 0..<24 { p(0, dy, 3); p(31, dy, 3) }
    }
}

// MARK: - screens
let menuItems = ["포켓 레이더", "다우징", "커넥트", "트레이너 카드", "포켓몬 · 도구"]
let moveNames = ["공격", "피하기", "볼", "도망"]
indirect enum Screen {
    case home
    case menu(Int)
    case radar(bush: Int, cursor: Int, since: Date)                    // "!" shows on `bush` 1.5 ... 3.5 s after `since`
    case battle(Battle, sel: Int)
    case beats(Battle, [Beat], since: Date, from: Battle)              // one exchange playing out; `from` = HP before it
    case dowse(cursor: Int, prize: Int, tries: Int, hint: String?)
    case card(Int), bag(Int)
    case say([String], next: Screen, since: Date)                      // any button or 3 s
}

final class WalkerView: NSView {
    var state: Walk
    var screen = Screen.home
    var lastInput = Date(), lastStep = Date.distantPast, lastSave = Date()
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
        state.sync(counter: WalkerView.counter(), boot: WalkerView.boot(), at: now)
        if state.total != before { lastStep = now }
        switch screen {
        case .radar(_, _, let since) where now.timeIntervalSince(since) > 3.5:
            screen = .say(["...!", "사라져버렸다"], next: .home, since: now)
        case .beats(let bt, let beats, let since, _) where now.timeIntervalSince(since) >= beats.map(\.length).reduce(0, +):
            screen = beats.last!.ends ? after(bt, beats.last!, now) : .battle(bt, sel: 0)
        case .say(_, let next, let since) where now.timeIntervalSince(since) > 3: screen = next
        case .menu, .card, .bag: if now.timeIntervalSince(lastInput) > 20 { screen = .home }
        default: break
        }
        if now.timeIntervalSince(lastSave) > 60 { save(nil) }
        needsDisplay = true
    }
    func after(_ b: Battle, _ end: Beat, _ now: Date) -> Screen {
        let name = monNames[b.wild.dex]
        switch end {
        case .caught: return state.keep(b.wild) ? .home : .say([josa(name, "은", "는"), "상자로 보냈다"], next: .home, since: now)
        default: return .home
        }
    }
    @objc func save(_ sender: Any?) { Store.save(state); lastSave = Date() }

    func press(_ k: Int) {                                    // 0 left, 1 enter, 2 right, 3 home
        let now = Date(); lastInput = now; defer { save(nil); needsDisplay = true }
        if k == 3 {                                           // home from anywhere; mid-battle it counts as running away
            switch screen {
            case .beats: return
            case .battle: screen = .say(["무사히", "도망쳤다!"], next: .home, since: now)
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
        case .radar(let b, let c, let since):
            if k != 1 { screen = .radar(bush: b, cursor: (c + (k == 0 ? 3 : 1)) % 4, since: since); return }
            let u = now.timeIntervalSince(since)
            if c == b, u >= 1.5 {
                let s = state.encounter(&rng), m = Mon(dex: s.dex, level: s.level, female: s.female, shiny: Int.random(in: 0..<shinyOdds, using: &rng) == 0 ? true : nil)
                let b = Battle(wild: m); screen = .beats(b, [.appear], since: now, from: b)
            } else { screen = .say(["아무것도", "없었다..."], next: .home, since: now) }
        case .battle(var b, let sel):
            if k == 0 { screen = .battle(b, sel: (sel + 3) % 4) } else if k == 2 { screen = .battle(b, sel: (sel + 1) % 4) }
            else { let from = b, beats = b.act(Move(rawValue: sel)!, &rng); screen = .beats(b, beats, since: now, from: from) }
        case .dowse(let c, let prize, let tries, _):
            if k != 1 { screen = .dowse(cursor: (c + (k == 0 ? 5 : 1)) % 6, prize: prize, tries: tries, hint: nil); return }
            if c == prize {
                let item = state.dowse(&rng)
                screen = .say(state.keep(item) ? [josa(item, "을", "를"), "찾았다!"] : [josa(item, "을", "를") + " 찾았다!", "가방으로 보냈다"], next: .home, since: now)
            } else if tries == 1 { screen = .say(["아무것도", "없었다..."], next: .home, since: now) }
            else { screen = .dowse(cursor: c, prize: prize, tries: 1, hint: abs(c - prize) == 1 ? "가깝다!" : "멀다...") }
        case .card(let p): screen = k == 1 ? .menu(3) : .card((p + 1) % 2)
        case .bag(let p): let n = bagPages; screen = k == 1 ? .menu(4) : .bag((p + (k == 0 ? n - 1 : 1)) % n)
        case .say(_, let next, _): screen = next
        case .beats: break
        }
    }
    func open(_ i: Int, _ now: Date) {
        switch i {
        case 0: screen = state.spend(10) ? .radar(bush: Int.random(in: 0..<4), cursor: 0, since: now) : .say(["W가 부족하다", "(10W 필요)"], next: .menu(0), since: now)
        case 1: screen = state.spend(3) ? .dowse(cursor: 0, prize: Int.random(in: 0..<6), tries: 2, hint: nil) : .say(["W가 부족하다", "(3W 필요)"], next: .menu(1), since: now)
        case 2:
            let n = state.caught.count + state.items.count
            state.connect(); screen = .say(n == 0 ? ["보낼 것이", "없다"] : ["상자로", "\(n)개 보냈다"], next: .menu(2), since: now)
        case 3: screen = .card(0)
        default: screen = .bag(0)
        }
    }

    func compose(_ now: Date) -> FB {
        var fb = FB()
        let t = now.timeIntervalSinceReferenceDate, half = Int(t * 2) % 2, me = state.companion
        func header(_ title: String) { fb.text(title, 2, 0); fb.text("\(state.watts)W", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2) }
        switch screen {
        case .home:
            let f = now.timeIntervalSince(lastStep) < 3 ? half : Int(t) % 2        // steps coming in => walks twice as fast
            fb.mon(me, f, 32, 0)
            fb.course(state.here.art, 1, 22)
            fb.text("\(state.watts)W", 1, 1, 2, small: true)
            for i in 0..<state.caught.count { fb.draw(ball, 1 + 8 * i, 13, ballPal) }
            for i in 0..<state.items.count { fb.draw(gem, 26 + 4 * i, 15, gemPal) }
            fb.fill(0, 49, 96, 1, 2)
            fb.draw(foot, 2, 54)
            fb.text("\(state.today)", 94, 52, 3, right: true)
        case .menu(let i):
            fb.text("◀", 1, 26, 2); fb.text("▶", 95, 26, 2, right: true)
            fb.text(menuItems[i], 0, 20, center: true)
            let sub = [" 10W", " 3W", "상자로 보내기", "", ""][i]
            if !sub.isEmpty { fb.text(sub.trimmingCharacters(in: .whitespaces), 0, 34, 2, center: true) }
            fb.text("\(state.watts)W", 94, 1, 2, right: true, small: true)
            for k in 0..<menuItems.count { fb.fill(36 + 5 * k, 58, 3, 3, k == i ? 3 : 1) }
        case .radar(let b, let c, let since):
            let u = now.timeIntervalSince(since), live = (1.5...3.5).contains(u)
            for k in 0..<4 {
                let x = 14 + (k % 2) * 56, y = 8 + (k / 2) * 28, shake = live && k == b ? (half == 0 ? -1 : 1) : 0
                fb.draw(bush, x + shake, y, greens)
                if live && k == b && Int(t * 6) % 2 == 0 { fb.draw(bang, x + 15, y - 6, redPal) }
                if k == c { fb.text("▶", x - 2, y, 3, right: true) }
            }
        case .battle(let b, let sel):
            stage(&fb, b, now, .idle(b.wild))
            for (k, r) in moveRanges().enumerated() { fb.text(moveNames[k], r.lowerBound + 1, 52); if k == sel { fb.invert(r.lowerBound, 52, r.count, 12) } }
        case .beats(_, let beats, let since, let from):
            var u = now.timeIntervalSince(since), i = 0
            while i < beats.count - 1, u >= beats[i].length { u -= beats[i].length; i += 1 }
            var hp = from                                                                        // HP as of this moment in the exchange
            for (k, bt) in beats.enumerated() where k < i || (k == i && u >= 0.45) { hp.apply(bt) }
            stage(&fb, hp, now, pose(beats[i], u, from.wild))
            fb.text(message(beats[i], u, from.wild), 2, 52)
            if beats[i] == .hit(crit: true), (0.45..<0.6).contains(u) { fb.invert(0, 0, 96, 64) }   // critical: the whole screen flashes
        case .dowse(let c, _, let tries, let hint):
            fb.text(hint ?? "어디에 있을까?", 0, 2, center: true)
            for k in 0..<6 { let x = 2 + 16 * k; fb.draw(bush, x, 28, greens); if k == c { fb.text("▼", x + 6, 16, 3, center: false) } }
            for k in 0..<tries { fb.draw(pip.full, 88 - 5 * k, 56) }
        case .card(let p):
            header(p == 0 ? "트레이너 카드" : "최근 7일")
            if p == 0 {
                fb.text(state.here.name, 2, 14)
                fb.text("오늘  \(state.today)걸음", 2, 26)
                fb.text("합계  \(state.total)걸음", 2, 38)
                fb.text("\(state.days)일째 · 도감 \(Set(([me] + state.caught + state.box).map(\.dex)).count)", 2, 50, 2)
            } else {
                let days = Array(([state.today] + state.history).prefix(8)), top = max(1, days.max()!)
                for (k, v) in days.enumerated() { let h = v * 34 / top, x = 84 - 11 * k; fb.fill(x, 60 - h, 8, h, k == 0 ? 3 : 2); fb.fill(x, 61, 8, 1, 1) }
                fb.text("\(top)", 94, 14, 1, right: true)
            }
        case .bag(let p):
            let m = p < bagPages - 1 ? state.caught[safe: p] : nil
            header(m.map { ($0.shiny == true ? "★" : "") + monNames[$0.dex] + " Lv.\($0.level)" } ?? (p < bagPages - 1 ? "포켓몬" : "도구"))
            if p < bagPages - 1 {
                if let m { fb.mon(m, half, 16, 14); fb.text("\(p + 1)/\(state.caught.count)", 94, 54, 2, right: true, small: true) }
                else { fb.text("없음", 0, 30, 2, center: true) }
            } else {
                if state.items.isEmpty { fb.text("없음", 0, 30, 2, center: true) }
                for (k, it) in state.items.enumerated() { fb.draw(gem, 4, 18 + 12 * k, gemPal); fb.text(it, 12, 14 + 12 * k) }
            }
        case .say(let lines, _, _):
            for (k, l) in lines.enumerated() { fb.text(l, 0, 32 - lines.count * 7 + 14 * k, center: true) }
        }
        return fb
    }
    var bagPages: Int { max(1, state.caught.count) + 1 }
    /// Battle menu labels' x ranges (drawn and tapped from the same layout).
    func moveRanges() -> [Range<Int>] {
        var x = 1, out: [Range<Int>] = []
        for n in moveNames { let w = (textDots(n).first?.count ?? 0) + 2; out.append(x..<x + w); x += w + 3 }
        return out
    }
    /// What the 64x48 stage shows: one fighter at full size (the other one is never squeezed to half resolution).
    enum Pose {
        case idle(Mon)                                   // the wild one, breathing
        case wild(dx: Int, dy: Int, flash: Bool, visible: Bool)
        case me(dx: Int, dy: Int, visible: Bool)
        case ball(x: Int, y: Int, tilt: Int?, burst: Bool, stars: Bool)
    }
    func pose(_ b: Beat, _ u: Double, _ wild: Mon) -> Pose {
        func arc(_ a: Double, _ len: Double) -> Double { u < a || u > a + len ? 0 : sin(.pi * (u - a) / len) }   // 0 -> 1 -> 0
        let shake = Int(u * 30) % 2 == 0 ? 2 : -2, blink = Int(u * 12) % 2 == 0
        switch b {
        case .appear: return u < 0.6 ? .wild(dx: Int(-80 * pow(1 - u / 0.6, 2)), dy: 0, flash: false, visible: true) : .idle(wild)   // slides in
        case .hit, .missed:
            if u < 0.45 { return .me(dx: Int(18 * arc(0, 0.45)), dy: 0, visible: true) }                      // our dash
            if b == .missed { return .wild(dx: Int(-14 * arc(0.45, 0.45)), dy: 0, flash: false, visible: true) }   // it sidesteps
            return .wild(dx: u < 0.85 ? shake : 0, dy: 0, flash: false, visible: u > 0.85 || blink)
        case .struck, .dodged:
            if u < 0.45 { return .wild(dx: Int(-18 * arc(0, 0.45)), dy: 0, flash: false, visible: true) }     // its lunge
            if b == .dodged { return .me(dx: 0, dy: Int(-12 * arc(0.45, 0.5)), visible: true) }               // we hop out of the way
            return .me(dx: u < 0.85 ? shake : 0, dy: 0, visible: u > 0.85 || blink)
        case .thrown:                                                                                       // arcs in, swallows it, drops
            if u < 0.55 { let k = u / 0.55; return .ball(x: Int(80 - 39 * k), y: Int(34 - 28 * k) - Int(16 * sin(.pi * k)), tilt: nil, burst: false, stars: false) }
            if u < 0.8 { return Int(u * 20) % 2 == 0 ? .wild(dx: 0, dy: 0, flash: true, visible: true) : .ball(x: 41, y: 6, tilt: nil, burst: false, stars: false) }
            let k = min(1, (u - 0.8) / 0.25)
            return .ball(x: 41, y: Int(6 + 24 * k * k) - Int(4 * arc(1.05, 0.15)), tilt: nil, burst: false, stars: false)
        case .broke, .caught:
            let wobbles = b == .caught ? 3 : 2, end = 0.6 * Double(wobbles)
            if u < end { return .ball(x: 41, y: 30, tilt: u.truncatingRemainder(dividingBy: 0.6) < 0.3 ? Int(u / 0.6) % 2 : nil, burst: false, stars: false) }
            if b == .caught { return .ball(x: 41, y: 30, tilt: nil, burst: false, stars: Int(u * 8) % 2 == 0) }
            if u < end + 0.25 { return .ball(x: 41, y: 30, tilt: nil, burst: true, stars: false) }
            return .wild(dx: 0, dy: 0, flash: u < end + 0.4, visible: true)
        case .fled: return .wild(dx: Int(-90 * min(1, u / 0.6)), dy: 0, flash: false, visible: true)
        case .ran: return .me(dx: Int(90 * min(1, u / 0.6)), dy: 0, visible: true)
        case .won: return u < 0.35 ? .wild(dx: 0, dy: 0, flash: false, visible: blink) : .wild(dx: 0, dy: Int(60 * min(1, (u - 0.35) / 0.6)), flash: false, visible: true)
        case .lost: return u < 0.35 ? .me(dx: 0, dy: 0, visible: blink) : .me(dx: 0, dy: Int(60 * min(1, (u - 0.35) / 0.6)), visible: true)
        }
    }
    func stage(_ fb: inout FB, _ b: Battle, _ now: Date, _ p: Pose) {
        let t = now.timeIntervalSinceReferenceDate, f = Int(t * 2) % 2
        for y in 41..<48 { for x in 14..<82 { let ex = Double(x - 48) / 34, ey = Double(y - 44) / 3.6; if ex * ex + ey * ey < 1 { fb.set(x, y, 1, ex * ex + ey * ey > 0.7 ? rgb(150, 200, 110) : rgb(186, 222, 146)) } } }   // the grass pad they stand on
        switch p {
        case .idle(let m):
            fb.mon(m, f, 16, 0)
            if m.shiny == true { for (k, (sx, sy)) in [(6, 4), (50, 8), (28, 1), (56, 30)].enumerated() where (Int(t * 4) + k) % 3 == 0 { fb.draw(spark, 16 + sx - 6, sy, sparkPal) } }
        case .wild(let dx, let dy, let flash, let visible): if visible { fb.mon(b.wild, f, 16 + dx, dy, flash: flash) }
        case .me(let dx, let dy, let visible): if visible { fb.mon(state.companion, f, 16 + dx, dy, flip: true) }
        case .ball(let x, let y, let tilt, let burst, let stars):
            if burst { fb.draw(burstArt, x - 2, y - 2, sparkPal, scale: 2) }
            fb.draw(tilt.map { ballTilt[$0] } ?? ball, x, y, ballPal, scale: 2)
            if stars { for (sx, sy) in [(-8, -4), (16, -5), (-9, 9), (17, 8)] { fb.draw(spark, x + sx, y + sy, sparkPal) } }
        }
        for i in 0..<4 { fb.draw(i < b.wildHP ? pip.full : pip.empty, 2 + 4 * i, 2) }                    // HUD: theirs top-left, ours (with a ball) top-right
        fb.draw(ball, 72, 0, ballPal)
        for i in 0..<4 { fb.draw(i < b.myHP ? pip.full : pip.empty, 80 + 4 * i, 2) }
        fb.fill(0, 50, 96, 1, 2)
    }
    func message(_ beat: Beat, _ u: Double, _ wild: Mon) -> String {
        let it = monNames[wild.dex], me = monNames[state.companion.dex], dots = String(repeating: ".", count: 1 + Int(u / 0.6))
        switch beat {
        case .appear: return wild.shiny == true && u < 0.9 ? "✦ 반짝! ✦" : "야생 " + josa(it, "이", "가") + " 나타났다!"
        case .hit(let crit): return crit && u >= 0.45 ? "급소에 맞았다!" : me + "의 공격!"
        case .missed: return u < 0.45 ? me + "의 공격!" : "빗나갔다!"
        case .struck: return it + "의 공격!"
        case .dodged: return u < 0.45 ? it + "의 공격!" : "휙! 피했다!"
        case .thrown: return "가랏, 몬스터볼!"
        case .broke: return u < 1.2 ? dots : "앗! 나와버렸다!"
        case .caught: return u < 1.8 ? dots : "딸깍! " + josa(it, "을", "를") + " 잡았다!"
        case .fled: return josa(it, "은", "는") + " 도망쳤다..."
        case .ran: return "무사히 도망쳤다!"
        case .won: return josa(it, "은", "는") + " 쓰러졌다!"
        case .lost: return josa(me, "은", "는") + " 쓰러졌다..."
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
        case .menu, .card, .bag: press(x < 32 ? 0 : x >= 64 ? 2 : 1)                             // left third ◀, middle ●, right third ▶
        case .radar(let b, _, let since): pick { screen = .radar(bush: b, cursor: (x < 48 ? 0 : 1) + (y < 32 ? 0 : 2), since: since) }
        case .battle(let b, _):
            guard y >= 50, let k = moveRanges().firstIndex(where: { $0.contains(x) }) else { return false }
            pick { screen = .battle(b, sel: k) }
        case .dowse(_, let prize, let tries, _):
            guard (20..<48).contains(y) else { return false }
            pick { screen = .dowse(cursor: min(5, max(0, (x - 2) / 16)), prize: prize, tries: tries, hint: nil) }
        case .beats: return false
        }
        return true
    }
    override func keyDown(with e: NSEvent) { if let i = [123: 0, 36: 1, 49: 1, 124: 2, 53: 3][Int(e.keyCode)] { press(i) } else { super.keyDown(with: e) } }   // ← return/space → esc
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(lcdRect, cursor: .pointingHand); for b in buttons { addCursorRect(NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r), cursor: .pointingHand) } }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "\(state.here.name) · 오늘 \(state.today)걸음 · \(state.watts)W", action: nil, keyEquivalent: "")
        m.addItem(.separator())
        let ch = m.addItem(withTitle: "코스 · \(state.here.name)", action: nil, keyEquivalent: ""), cm = NSMenu()
        for (i, c) in courses.enumerated() {
            let it = cm.addItem(withTitle: state.unlocked(i) ? c.name : "\(c.name) — \(c.watts)W", action: state.unlocked(i) ? #selector(setCourse(_:)) : nil, keyEquivalent: "")
            it.target = self; it.tag = i; it.state = i == state.course ? .on : .off
        }
        ch.submenu = cm
        let ph = m.addItem(withTitle: "함께 걷기 · \(state.companion.shiny == true ? "★ " : "")\(monNames[state.companion.dex])", action: nil, keyEquivalent: ""), pm = NSMenu()
        if state.box.isEmpty { pm.addItem(withTitle: "상자가 비어 있다", action: nil, keyEquivalent: "") }
        for (i, b) in state.box.enumerated() { let it = pm.addItem(withTitle: "\(b.shiny == true ? "★ " : "")\(monNames[b.dex]) Lv.\(b.level)", action: #selector(pair(_:)), keyEquivalent: ""); it.target = self; it.tag = i }
        ph.submenu = pm
        if !state.bag.isEmpty {
            let bh = m.addItem(withTitle: "가방 · \(state.bag.count)개", action: nil, keyEquivalent: ""), bm = NSMenu()
            for (n, k) in Dictionary(state.bag.map { ($0, 1) }, uniquingKeysWith: +).sorted(by: { $0.key < $1.key }) { bm.addItem(withTitle: "\(n) ×\(k)", action: nil, keyEquivalent: "") }
            bh.submenu = bm
        }
        func sub(_ title: String, _ items: [(String, Int)], _ current: Int, _ sel: Selector) {
            let head = m.addItem(withTitle: "\(title) · \(items.first { $0.1 == current }?.0 ?? "")", action: nil, keyEquivalent: ""), sm = NSMenu()
            for (t, tag) in items { let i = sm.addItem(withTitle: t, action: sel, keyEquivalent: ""); i.target = self; i.tag = tag; i.state = tag == current ? .on : .off }
            head.submenu = sm
        }
        m.addItem(.separator())
        sub("크기", [("보통", 2), ("크게", 3), ("아주 크게", 4)], Int(PX), #selector(setSize(_:)))
        sub("기기", shells.enumerated().map { ($1.name, $0) }, theme, #selector(setTheme(_:)))
        sub("화면", lcds.enumerated().map { ($1.name, $0) }, lcdStyle, #selector(setLCD(_:)))
        m.addItem(.separator())
        m.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        return m
    }
    @objc func setCourse(_ i: NSMenuItem) { state.setCourse(i.tag, &rng); screen = .say(["커넥트 완료", state.here.name], next: .home, since: Date()); save(nil) }
    @objc func pair(_ i: NSMenuItem) { guard state.box.indices.contains(i.tag) else { return }; state.pair(i.tag, &rng); screen = .say(["커넥트 완료", josa(monNames[state.companion.dex], "과", "와") + " 함께"], next: .home, since: Date()); save(nil) }
    @objc func setSize(_ item: NSMenuItem) {                     // keeps the top-right corner
        guard let w = window else { return }
        var f = w.frame; f.origin.x += f.width - CGFloat(item.tag) * dev.w; f.origin.y += f.height - CGFloat(item.tag) * dev.h
        PX = CGFloat(item.tag); UserDefaults.standard.set(item.tag, forKey: "px")
        f.size = devSize
        if let s = w.screen?.visibleFrame { f.origin.x = min(max(f.origin.x, s.minX), s.maxX - f.width); f.origin.y = min(max(f.origin.y, s.minY), s.maxY - f.height) }
        w.setFrame(f, display: true); setFrameSize(devSize); window?.invalidateCursorRects(for: self); needsDisplay = true
    }
    @objc func setTheme(_ item: NSMenuItem) { theme = item.tag; UserDefaults.standard.set(theme, forKey: "shell"); needsDisplay = true }
    @objc func setLCD(_ item: NSMenuItem) { lcdStyle = item.tag; UserDefaults.standard.set(lcdStyle, forKey: "lcd"); needsDisplay = true }

    // MARK: drawing
    override func draw(_ dirty: NSRect) {
        let t = shells[theme], l = lcds[lcdStyle], ink = NSColor(white: 0.10, alpha: 1), white = NSColor(white: 0.96, alpha: 1)
        let ballRect = NSRect(origin: .zero, size: devSize).insetBy(dx: PX, dy: PX), ball = NSBezierPath(ovalIn: ballRect)
        // flat halves: top colour, white bottom, black band through the middle; one hairline, depth from the window shadow
        NSGraphicsContext.saveGraphicsState(); ball.addClip()
        t.top.setFill(); NSRect(x: 0, y: 0, width: devSize.width, height: 72 * PX).fill()
        white.setFill(); NSRect(x: 0, y: 72 * PX, width: devSize.width, height: 72 * PX).fill()
        if theme == 2 { NSColor(red: 0.98, green: 0.80, blue: 0.20, alpha: 1).setFill(); for x in [30, 106] { NSRect(x: CGFloat(x) * PX, y: 0, width: 8 * PX, height: 34 * PX).fill() } }   // Ultra Ball's yellow
        if theme == 3 { NSColor(red: 0.93, green: 0.40, blue: 0.62, alpha: 1).setFill(); for x in [18, 110] { NSBezierPath(ovalIn: NSRect(x: CGFloat(x) * PX, y: 22 * PX, width: 16 * PX, height: 12 * PX)).fill() } }   // Master Ball's pink spots
        ink.setFill(); NSRect(x: 0, y: 68 * PX, width: devSize.width, height: 8 * PX).fill()
        NSGraphicsContext.restoreGraphicsState()
        ink.withAlphaComponent(0.6).setStroke(); ball.lineWidth = 1; ball.stroke()
        // the screen sits where the ball's button is: black ring, white ring, black bezel
        for (out, r, c) in [(8.0, 11.0, ink), (5.0, 8.0, white), (2.0, 4.0, ink)] as [(CGFloat, CGFloat, NSColor)] {
            c.setFill(); NSBezierPath(roundedRect: lcdRect.insetBy(dx: -out * PX, dy: -out * PX), xRadius: r * PX, yRadius: r * PX).fill()
        }
        l.shades[0].setFill(); lcdRect.fill()
        let fb = compose(Date()), gap = PX >= 3 ? 1 / (window?.backingScaleFactor ?? 2) : 0
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
            withAttributes: [.font: NSFont.systemFont(ofSize: 3.4 * PX, weight: .heavy), .foregroundColor: NSColor(white: 1, alpha: 0.85), .paragraphStyle: centred, .kern: 0.3 * PX])
    }
}

// MARK: - app
if CommandLine.arguments.contains("--selftest") { exit(selftest() ? 0 : 1) }     // after the globals above: main.swift initialises them in order
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let view = WalkerView(state: Store.load())
view.state.sync(counter: WalkerView.counter(), boot: WalkerView.boot(), at: Date())      // steps typed while the app was quit (same login) count
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
panel.orderFrontRegardless()
panel.makeFirstResponder(view)

let timer = Timer(timeInterval: 0.1, target: view, selector: #selector(WalkerView.tick(_:)), userInfo: nil, repeats: true)
timer.tolerance = 0.02
RunLoop.main.add(timer, forMode: .common)
let ws = NSWorkspace.shared.notificationCenter
ws.addObserver(view, selector: #selector(WalkerView.save(_:)), name: NSWorkspace.willSleepNotification, object: nil)
NotificationCenter.default.addObserver(view, selector: #selector(WalkerView.save(_:)), name: NSApplication.willTerminateNotification, object: nil)
app.run()

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
