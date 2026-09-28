import AppKit

// MARK: - geometry (points; flipped view). All in device dots x PX, so the size menu scales everything.
var PX = CGFloat(max(2, UserDefaults.standard.integer(forKey: "px")))    // 2 / 3 / 4
let dev = (w: CGFloat(144), h: CGFloat(144))                                                  // a Poké Ball: 144-dot circle, screen where the button would be
var devSize: NSSize { NSSize(width: dev.w * PX, height: dev.h * PX) }
var lcdRect: NSRect { NSRect(x: 24 * PX, y: 40 * PX, width: 96 * PX, height: 64 * PX) }      // 96x64 dots, 4 greys, like the real one; centred on the ball
var buttons: [(c: NSPoint, r: CGFloat)] { [(NSPoint(x: 49 * PX, y: 121 * PX), 4.4 * PX), (NSPoint(x: 72 * PX, y: 125 * PX), 6 * PX), (NSPoint(x: 95 * PX, y: 121 * PX), 4.4 * PX)] }   // left, enter, right: on the white half, following its curve

struct Shell { let name: String; let top: NSColor }                  // the top half; the bottom is always white, the band black
let shells: [Shell] = [
    Shell(name: "몬스터볼", top: NSColor(red: 0.89, green: 0.20, blue: 0.19, alpha: 1)),
    Shell(name: "슈퍼볼", top: NSColor(red: 0.22, green: 0.46, blue: 0.86, alpha: 1)),
    Shell(name: "하이퍼볼", top: NSColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)),
    Shell(name: "마스터볼", top: NSColor(red: 0.47, green: 0.27, blue: 0.66, alpha: 1)),
]
var theme = min(max(UserDefaults.standard.integer(forKey: "shell"), 0), shells.count - 1)
struct LCD { let name: String; let shades: [NSColor] }             // shade 0 (blank) ... 3 (black)
let lcds: [LCD] = [
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
/// Hand-drawn bits: " .:#" = shade 0...3, "_" = transparent.
func art(_ rows: [String]) -> [[UInt8?]] { rows.map { $0.map { c in c == "_" ? nil : UInt8(" .:#".firstIndex(of: c).map { " .:#".distance(from: " .:#".startIndex, to: $0) } ?? 0) } } }
let bush = art(["____:##:_____", "__:#:..:#____", "_#:..::..#:__", "#:.::..::.:#_", "#..:..::..:.#", "#.::..:..::.#", ":#..::..::.#:", "_:#:..::.:#:_", "__:##::##:___", "____#__#_____"])
let bang = art(["##", "##", "##", "##", "__", "##"])
let ball = art(["__###__", "_#:::#_", "#:::::#", "###.###", "#.....#", "_#...#_", "__###__"])
let foot = art(["_##_##", "_##_##", "______", "#####_", "######", "_####_"])
let gem = art(["_#_", "#:#", "_#_"])
let pip = (full: art(["###", "###", "###"]), empty: art(["###", "# #", "###"]))

/// Korean text through CoreText, thresholded to dots (the device font would need a glyph table for every syllable).
var textCache: [String: [[Bool]]] = [:]
@MainActor func textDots(_ s: String) -> [[Bool]] {
    if let t = textCache[s] { return t }
    let font = NSFont(name: "AppleSDGothicNeo-Medium", size: 11) ?? .systemFont(ofSize: 11)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]))
    let w = max(1, Int(ceil(CTLineGetTypographicBounds(line, nil, nil, nil)))), h = 11
    var px = [UInt8](repeating: 0, count: w * h)
    px.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        ctx.setShouldAntialias(false); ctx.setShouldSmoothFonts(false); ctx.setFillColor(gray: 1, alpha: 1)
        ctx.textPosition = CGPoint(x: 0, y: 2); CTLineDraw(line, ctx)
    }
    let t = (0..<h).map { y in (0..<w).map { px[y * w + $0] > 127 } }
    textCache[s] = t; return t
}
/// 을/를, 이/가, 은/는 by the last syllable's final consonant.
func josa(_ w: String, _ with: String, _ without: String) -> String {
    guard let u = w.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(u) else { return w + without }
    return w + ((u - 0xAC00) % 28 != 0 ? with : without)
}

@MainActor struct FB {
    var px = [UInt8](repeating: 0, count: 96 * 64)
    mutating func set(_ x: Int, _ y: Int, _ s: UInt8) { if (0..<96).contains(x), (0..<64).contains(y) { px[y * 96 + x] = s } }
    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ s: UInt8) { for yy in y..<y + h { for xx in x..<x + w { set(xx, yy, s) } } }
    mutating func draw(_ a: [[UInt8?]], _ x: Int, _ y: Int) { for (dy, r) in a.enumerated() { for (dx, s) in r.enumerated() { if let s { set(x + dx, y + dy, s) } } } }
    /// Large = 64x48; small = 32x24, each dot the darkest of its 2x2. Shade 0 is see-through.
    mutating func mon(_ dex: Int, _ f: Int, _ x: Int, _ y: Int, small: Bool = false, flip: Bool = false) {
        let k = small ? 2 : 1
        for sy in 0..<48 / k { for sx in 0..<64 / k {
            var s: UInt8 = 0
            for yy in 0..<k { for xx in 0..<k { s = max(s, spriteShade(dex, f, sx * k + xx, sy * k + yy)) } }
            if s > 0 { set(x + (flip ? 64 / k - 1 - sx : sx), y + sy, s) }
        } }
    }
    @discardableResult mutating func text(_ s: String, _ x: Int, _ y: Int, _ shade: UInt8 = 3, center: Bool = false, right: Bool = false) -> Int {
        let t = textDots(s), w = t.first?.count ?? 0, x0 = center ? (96 - w) / 2 : right ? x - w : x
        for (dy, r) in t.enumerated() { for (dx, on) in r.enumerated() where on { set(x0 + dx, y + dy, shade) } }
        return w
    }
    mutating func invert(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { for yy in y..<y + h { for xx in x..<x + w where (0..<96).contains(xx) && (0..<64).contains(yy) { px[yy * 96 + xx] = 3 - px[yy * 96 + xx] } } }
    /// 32x24 picture of the course, framed.
    mutating func course(_ a: Art, _ x: Int, _ y: Int) {
        func p(_ dx: Int, _ dy: Int, _ s: UInt8) { if (0..<32).contains(dx), (0..<24).contains(dy) { set(x + dx, y + dy, s) } }
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
    case beats(Battle, [Beat], since: Date)                            // one exchange playing out, 1.2 s per beat
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
        case .beats(let bt, let beats, let since) where now.timeIntervalSince(since) >= 1.2 * Double(beats.count):
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
        case .caught: return .say(state.keep(b.wild) ? [josa(name, "을", "를"), "잡았다!"] : [josa(name, "을", "를") + " 잡았다!", "상자로 보냈다"], next: .home, since: now)
        default: return .home
        }
    }
    @objc func save(_ sender: Any?) { Store.save(state); lastSave = Date() }

    func press(_ k: Int) {                                    // 0 left, 1 enter, 2 right
        let now = Date(); lastInput = now; defer { save(nil); needsDisplay = true }
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
                let s = state.encounter(&rng), m = Mon(dex: s.dex, level: s.level, female: s.female)
                screen = .say(["야생 " + josa(monNames[s.dex], "이", "가"), "튀어나왔다!"], next: .battle(Battle(wild: m), sel: 0), since: now)
            } else { screen = .say(["아무것도", "없었다..."], next: .home, since: now) }
        case .battle(var b, let sel):
            if k == 0 { screen = .battle(b, sel: (sel + 3) % 4) } else if k == 2 { screen = .battle(b, sel: (sel + 1) % 4) }
            else { let beats = b.act(Move(rawValue: sel)!, &rng); screen = .beats(b, beats, since: now) }
        case .dowse(let c, let prize, let tries, _):
            if k != 1 { screen = .dowse(cursor: (c + (k == 0 ? 5 : 1)) % 6, prize: prize, tries: tries, hint: nil); return }
            if c == prize {
                let item = state.dowse(&rng)
                screen = .say(state.keep(item) ? [josa(item, "을", "를"), "찾았다!"] : [josa(item, "을", "를") + " 찾았다!", "가방으로 보냈다"], next: .home, since: now)
            } else if tries == 1 { screen = .say(["아무것도", "없었다..."], next: .home, since: now) }
            else { screen = .dowse(cursor: c, prize: prize, tries: 1, hint: abs(c - prize) == 1 ? "가깝다!" : "멀다...") }
        case .card(let p): screen = k == 1 ? .menu(3) : .card((p + 1) % 2)
        case .bag(let p): screen = k == 1 ? .menu(4) : .bag((p + 1) % 2)
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
        func header(_ title: String) { fb.text(title, 2, 0); fb.text("\(state.watts)W", 94, 0, 2, right: true); fb.fill(0, 12, 96, 1, 2) }
        switch screen {
        case .home:
            let f = now.timeIntervalSince(lastStep) < 3 ? half : Int(t) % 2        // steps coming in => walks twice as fast
            fb.mon(me.dex, f, 32, 0)
            fb.course(state.here.art, 1, 22)
            fb.text("\(state.watts)W", 1, 0, 2)
            for i in 0..<state.caught.count { fb.draw(ball, 1 + 8 * i, 13) }
            for i in 0..<state.items.count { fb.draw(gem, 26 + 4 * i, 15) }
            fb.fill(0, 49, 96, 1, 2)
            fb.draw(foot, 2, 54)
            fb.text("\(state.today)", 94, 52, 3, right: true)
        case .menu(let i):
            fb.text("◀", 1, 26, 2); fb.text("▶", 95, 26, 2, right: true)
            fb.text(menuItems[i], 0, 20, center: true)
            let sub = [" 10W", " 3W", "상자로 보내기", "", ""][i]
            if !sub.isEmpty { fb.text(sub.trimmingCharacters(in: .whitespaces), 0, 34, 2, center: true) }
            fb.text("\(state.watts)W", 94, 0, 2, right: true)
            for k in 0..<menuItems.count { fb.fill(36 + 5 * k, 58, 3, 3, k == i ? 3 : 1) }
        case .radar(let b, let c, let since):
            let u = now.timeIntervalSince(since), live = (1.5...3.5).contains(u)
            for k in 0..<4 {
                let x = 14 + (k % 2) * 56, y = 8 + (k / 2) * 28, shake = live && k == b ? (half == 0 ? -1 : 1) : 0
                fb.draw(bush, x + shake, y)
                if live && k == b && Int(t * 6) % 2 == 0 { fb.draw(bang, x + 15, y - 6) }
                if k == c { fb.text("▶", x - 2, y, 3, right: true) }
            }
        case .battle(let b, let sel):
            battleScene(&fb, b, now, blinkWild: false, blinkMe: false, ballOut: false)
            var x = 1
            for (k, n) in moveNames.enumerated() { let w = fb.text(n, x + 1, 52); if k == sel { fb.invert(x, 52, w + 2, 12) }; x += w + 4 }
        case .beats(let b, let beats, let since):
            let i = min(beats.count - 1, Int(now.timeIntervalSince(since) / 1.2)), beat = beats[i], blink = Int(t * 8) % 2 == 0
            battleScene(&fb, b, now, blinkWild: blink && (beat == .hit(crit: false) || beat == .hit(crit: true)), blinkMe: blink && beat == .struck,
                        ballOut: [.thrown, .caught].contains(beat), gone: [.won, .fled, .ran].contains(beat) ? .wild : beat == .lost ? .me : nil)
            fb.text(line(beat, b), 2, 52)
        case .dowse(let c, _, let tries, let hint):
            fb.text(hint ?? "어디에 있을까?", 0, 2, center: true)
            for k in 0..<6 { let x = 2 + 16 * k; fb.draw(bush, x, 28); if k == c { fb.text("▼", x + 6, 16, 3, center: false) } }
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
            header(p == 0 ? "포켓몬" : "도구")
            if p == 0 {
                if state.caught.isEmpty { fb.text("없음", 0, 30, 2, center: true) }
                for (k, m) in state.caught.enumerated() { fb.mon(m.dex, half, 32 * k, 14, small: true); fb.text(monNames[m.dex], 32 * k + 1, 40 + (k % 2) * 11, 2) }
            } else {
                if state.items.isEmpty { fb.text("없음", 0, 30, 2, center: true) }
                for (k, it) in state.items.enumerated() { fb.draw(gem, 4, 18 + 12 * k); fb.text(it, 12, 14 + 12 * k) }
            }
        case .say(let lines, _, _):
            for (k, l) in lines.enumerated() { fb.text(l, 0, 32 - lines.count * 7 + 14 * k, center: true) }
        }
        return fb
    }
    enum Side { case wild, me }
    func battleScene(_ fb: inout FB, _ b: Battle, _ now: Date, blinkWild: Bool, blinkMe: Bool, ballOut: Bool, gone: Side? = nil) {
        let f = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        if ballOut { fb.draw(ball, 28, 20) } else if !blinkWild && gone != .wild { fb.mon(b.wild.dex, f, 0, 0) }
        if !blinkMe && gone != .me { fb.mon(state.companion.dex, f, 64, 24, small: true, flip: true) }
        for i in 0..<4 { fb.draw(i < b.wildHP ? pip.full : pip.empty, 66 + 5 * i, 2); fb.draw(i < b.myHP ? pip.full : pip.empty, 2 + 5 * i, 44) }
        fb.fill(0, 50, 96, 1, 2)
    }
    func line(_ beat: Beat, _ b: Battle) -> String {
        let it = monNames[b.wild.dex], me = monNames[state.companion.dex]
        switch beat {
        case .hit(let crit): return crit ? "급소에 맞았다!" : josa(me, "의", "의") + " 공격!"
        case .missed: return "빗나갔다!"
        case .struck: return josa(it, "의", "의") + " 공격!"
        case .dodged: return josa(me, "은", "는") + " 피했다!"
        case .thrown: return "몬스터볼 던지기!"
        case .broke: return "앗! 나와버렸다!"
        case .caught: return josa(it, "을", "를") + " 잡았다!"
        case .fled: return josa(it, "은", "는") + " 도망쳤다"
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
        } else { window?.performDrag(with: e) }
    }
    override func keyDown(with e: NSEvent) { if let i = [123: 0, 36: 1, 49: 1, 124: 2][Int(e.keyCode)] { press(i) } else { super.keyDown(with: e) } }   // ← return/space →
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { for b in buttons { addCursorRect(NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r), cursor: .pointingHand) } }

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
        let ph = m.addItem(withTitle: "함께 걷기 · \(monNames[state.companion.dex])", action: nil, keyEquivalent: ""), pm = NSMenu()
        if state.box.isEmpty { pm.addItem(withTitle: "상자가 비어 있다", action: nil, keyEquivalent: "") }
        for (i, b) in state.box.enumerated() { let it = pm.addItem(withTitle: "\(monNames[b.dex]) Lv.\(b.level)", action: #selector(pair(_:)), keyEquivalent: ""); it.target = self; it.tag = i }
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
        let paths = (0..<4).map { _ in NSBezierPath() }
        for y in 0..<64 { for x in 0..<96 { let s = Int(fb.px[y * 96 + x]); if s > 0 { paths[s].appendRect(NSRect(x: lcdRect.minX + CGFloat(x) * PX, y: lcdRect.minY + CGFloat(y) * PX, width: PX - gap, height: PX - gap)) } } }
        NSGraphicsContext.current!.shouldAntialias = false
        for s in 1..<4 { l.shades[s].setFill(); paths[s].fill() }
        NSGraphicsContext.current!.shouldAntialias = true
        NSGradient(starting: NSColor(white: 0, alpha: 0.22), ending: .clear)!.draw(in: NSRect(x: lcdRect.minX, y: lcdRect.minY, width: lcdRect.width, height: 2 * PX), angle: 90)
        let now = Date()
        for (i, b) in buttons.enumerated() {                                                          // little Poké Ball buttons: white cap, black ring
            let down = pressed == i && now.timeIntervalSince(pressedAt) < 0.15
            let cap = NSBezierPath(ovalIn: NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r))
            (down ? NSColor(white: 0.78, alpha: 1) : white).setFill(); cap.fill()
            ink.setStroke(); cap.lineWidth = 1.1 * PX; cap.stroke()
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
