import AppKit
// Home as a sticker travel journal: a notebook page (six papers, each by the hour's light), the course picture as a taped polaroid with the walker in it,
// the companion as a die-cut sticker (its white rim follows its HGSS animation), the walker's catches and the egg as small stickers, a desk calendar for the season.
// No numbers: those are the 상태 sheet's. All pictures at sprite resolution from a finite set of keys; a frame only places them.

/// The 수첩 배경 menu (setting "paper"): the page under everything on home.
let paperNames = ["점 격자 수첩", "모눈 노트", "줄 노트", "크라프트지", "코르크 보드", "체크 무늬 천"]
@MainActor var paperStyle = min(max(settings.int("paper", 0), 0), paperNames.count - 1)
/// The polaroid round courseBox (half-dots): 4 px of white round the photo, 12 under it.
let polaroid = (x: 2 * courseBox.x - 4, y: 2 * courseBox.y - 4, w: 2 * courseBox.w + 8, h: 2 * courseBox.h + 16)
let stickerFeet = (x: 148, y: 114)                                                  // the big companion's feet (half-dots): the widest sprite and its rim still clear the right bezel
/// Whose sticker rims are in the picture store: a new companion lets the old one's go (dozens of animation frames each).
@MainActor var rimDex = 0

extension WalkerView {
    /// Home (and under the menu, which is the pane's): the page, the polaroid and the walker in it, the tape, the calendar, the stickers, the companion, its emote.
    func home(_ fb: inout FB, _ now: Date) {
        let t = now.timeIntervalSinceReferenceDate, me = state.companion, tb = lightBand(state.hour), night = tb == 3, grey = !lcds[lcdStyle].color, tone = "\(night)" + (grey ? "|g" : "")
        let P = polaroid, (fx, fy) = stickerFeet
        fb.pic("nb|paper|\(paperStyle)|\(tb)" + (grey ? "|g" : ""), 96, 64, behind: true) { paperPic(paperStyle, tb, grey: grey) }
        fb.pic("nb|pola|" + tone, P.x + P.w / 2 + 1, P.y + P.h / 2 + 1, behind: true) { lcdReady(polaroidPic(night)) }
        fb.course(state.here.art, courseBox.x, courseBox.y, weather: state.weather ?? .sunny, t: t, hour: state.hour, season: state.season, framed: false)
        walker(&fb, me, now)                                                                     // small, walking the photo
        if paperStyle == 4 { for k in 0..<2 { fb.pic("nb|pin|\(k)|" + tone, k == 0 ? P.x + 8 : P.x + P.w - 9, k == 0 ? P.y + 5 : P.y + P.h - 8, behind: true) { lcdReady(pinPic(k, night)) } } }   // cork: pins
        else { for k in 0..<2 { fb.pic("nb|tape|\(k)|" + tone, k == 0 ? P.x + 6 : P.x + P.w - 5, k == 0 ? P.y + 5 : P.y + P.h - 7, behind: true) { lcdReady(tapePic(k)) } } }
        fb.stuck("nb|cal|\(state.season.rawValue)|" + tone, P.x + P.w - 16, P.y - 3) { lcdReady(sticker(calendarPic(state.season), night: night)) }
        let n = min(3, state.caught.count) + (state.egg == nil ? 0 : 1), u = t.truncatingRemainder(dividingBy: 9), who = Int(t / 9) % max(1, n)
        func hop(_ k: Int) -> Int { k == who && u < 0.45 ? Int((sin(u / 0.45 * .pi) * 4).rounded()) : 0 }   // now and then one of them pops
        for (k, m) in state.caught.prefix(3).enumerated() {                                    // the walker's catches along the bottom, a little staggered
            fb.stuck("nb|icon|\(m.dex)|" + tone, 4 + 30 * k, 90 - 3 * (k % 2) - hop(k)) { lcdReady(sticker(iconPic(m.dex), night: night)) }
        }
        if let e = state.egg {                                                                   // close to hatching it rocks
            let k = min(3, state.caught.count), tau = t.truncatingRemainder(dividingBy: 1.6), ang = e.left < 500 && tau < 0.5 ? 12 * sin(tau / 0.25 * 2 * .pi) * (1 - tau / 0.5) : 0
            fb.pic("nb|egg|" + tone, 20 + 30 * k + Int((11 * sin(ang * .pi / 180)).rounded()), 123 - hop(k) - Int((11 * cos(ang * .pi / 180)).rounded()), angle: ang, behind: true) { lcdReady(sticker(miniEgg, night: night)) }   // about its foot
        }
        if rimDex != me.dex { rimDex = me.dex; picStore = picStore.filter { !$0.key.hasPrefix("nb|me|") }; picImages = picImages.filter { !$0.key.hasPrefix("nb|me|") } }
        let a = animT("home", me.dex, now, start: false), f = a.flatMap { anim(me.dex)?.frame(at: $0) }, an = f.flatMap { _ in anim(me.dex) }
        let bob = now.timeIntervalSince(lastStep) < 3 ? Int(t * 2) % 2 : Int(t) % 2                // steps coming in => breathes twice as fast
        if let f, let an {                                                                       // the rim round this frame of its animation
            fb.stuck("nb|me|\(me.dex)|\(f)|\(night)", fx - 42 + an.x, fy - 82 + an.y) { sticker(animFramePic(an, f), night: night, rimOnly: true) }   // (a rim: the same on any LCD style)
        } else { fb.stuck("nb|me|\(me.dex)|s|\(night)", fx - 42, fy - 82 - bob) { sticker(spritePic(me.dex), night: night, rimOnly: true) } }
        fb.sprite(me, fx / 2 - 16, fy / 2 - 32, bob: bob, anim: a)
        if let e = emote, now < e.until, Int(t * 3) % 3 != 0 { fb.pic("nb|bubble|\(e.kind)", fx - 18, max(10, fy - 84 + spriteTop(me.dex))) { bubblePic(e.kind) } }   // by its head
    }
}
extension FB {
    /// A picture placed by its top-left corner (half-dots), under the sprites; sticker() makes even sizes, so it lands on whole pixels.
    mutating func stuck(_ key: String, _ x: Int, _ y: Int, _ make: () -> Pic) {
        if picStore[key] == nil { picStore[key] = make() }
        let p = picStore[key]!; pic(key, x + p.w / 2, y + p.h / 2, behind: true) { p }
    }
}

// MARK: - the papers
/// A page, 192 x 128: each paper a pattern in up to 4 inks (0 = the paper), coloured by the hour (dawn rosier, dusk warmer, night a dark album page)
/// or, on a grey LCD, set on its shades (none dithered: the lines stay whole).
func paperPic(_ s: Int, _ tb: Int, grey: Bool) -> Pic {
    let levels: [UInt32] = [230, 163, 97, 31]
    let pal = grey ? paperGreys[s][tb == 3 ? 1 : 0].map { rgb(UInt8(levels[$0]), UInt8(levels[$0]), UInt8(levels[$0])) }
        : tb == 3 ? paperNight[s] : paperDay[s].map { tb == 1 ? lerpRGB($0, rgb(255, 196, 206), 0.1) : tb == 2 ? lerpRGB($0, rgb(255, 170, 100), 0.14) : $0 }
    var p = Pic(w: 192, h: 128)
    for y in 0..<128 { for x in 0..<192 { p.px[y * 192 + x] = pal[paperInk(s, x, y)] } }
    return p
}
/// Which ink each pixel of paper s takes.
func paperInk(_ s: Int, _ x: Int, _ y: Int) -> Int {
    switch s {
    case 0: return x % 8 == 4 && y % 8 == 4 ? 1 : 0                                              // 점 격자: a dot every 4 dots
    case 1: return x % 32 == 11 || y % 32 == 11 ? 2 : x % 8 == 3 || y % 8 == 3 ? 1 : 0           // 모눈: every 4 dots, bolder every 16
    case 2: return x == 3 || x == 5 ? 2 : y % 11 == 10 && y > 12 ? 1 : 0                          // 줄: rules under a blank top, a double margin
    case 3:                                                                                      // 크라프트지: short fibres, dark and pale, and specks
        if hashXY(x, y, 31) % 97 == 0 { return 3 }
        return hashXY((x + y * 3) / 5, y, 7) % 13 == 0 ? 1 : hashXY((x + y * 5) / 4, y, 9) % 19 == 0 ? 2 : 0
    case 4:                                                                                      // 코르크: granules (2 px), pits, pale chips
        let g = hashXY(x / 2 + y / 2 % 2, y / 2, 11) % 16
        return hashXY(x, y, 13) % 23 == 0 ? 2 : g < 3 ? 1 : g == 3 ? 3 : 0
    default:                                                                                     // 체크 무늬 천: woven gingham, 4-dot bands
        let v = x / 8 % 2 == 1, h = y / 8 % 2 == 1
        return v && h ? 2 : v ? (y % 2 == 0 ? 1 : 3) : h ? (x % 2 == 0 ? 1 : 3) : 0
    }
}
let paperDay: [[UInt32]] = [[rgb(250, 247, 236), rgb(218, 208, 186), 0, 0],
                            [rgb(250, 251, 248), rgb(212, 226, 240), rgb(170, 198, 232), 0],
                            [rgb(252, 251, 246), rgb(186, 206, 232), rgb(240, 156, 166), 0],
                            [rgb(204, 164, 118), rgb(184, 144, 100), rgb(222, 186, 142), rgb(150, 110, 74)],
                            [rgb(198, 150, 98), rgb(166, 118, 72), rgb(126, 86, 52), rgb(226, 188, 136)],
                            [rgb(252, 250, 246), rgb(242, 176, 172), rgb(228, 128, 128), rgb(250, 214, 208)]]
let paperNight: [[UInt32]] = [[rgb(46, 52, 84), rgb(72, 80, 120), 0, 0],
                              [rgb(36, 44, 70), rgb(46, 56, 86), rgb(60, 74, 110), 0],
                              [rgb(42, 46, 72), rgb(66, 76, 112), rgb(128, 74, 102), 0],
                              [rgb(64, 50, 46), rgb(54, 42, 40), rgb(80, 64, 56), rgb(44, 34, 32)],
                              [rgb(76, 58, 46), rgb(68, 51, 40), rgb(56, 42, 32), rgb(90, 70, 54)],
                              [rgb(44, 50, 84), rgb(70, 60, 96), rgb(88, 64, 102), rgb(56, 54, 90)]]
/// Grey LCDs: each ink's shade (0 blank ... 3 black), by day and by night.
let paperGreys: [[[Int]]] = [[[0, 1, 0, 0], [3, 2, 3, 3]], [[0, 1, 1, 0], [3, 2, 2, 3]], [[0, 1, 2, 0], [3, 2, 1, 3]],
                             [[1, 2, 0, 2], [3, 3, 2, 3]], [[1, 1, 2, 0], [3, 3, 2, 3]], [[0, 1, 1, 0], [3, 2, 2, 3]]]

// MARK: - the polaroid, tape, pins
/// The polaroid's white card with a warm edge, a hairline under the photo and its shadow (2 px down-right). Colours that land whole on a grey LCD's shades.
func polaroidPic(_ night: Bool) -> Pic {
    let (w, h) = (polaroid.w, polaroid.h), paper = night ? rgb(234, 236, 246) : rgb(254, 252, 246), edge = night ? rgb(150, 156, 184) : rgb(180, 166, 140)
    var p = Pic(w: w + 2, h: h + 2)
    p.fill(2, 2, w, h, argb(night ? 120 : 70, night ? rgb(6, 10, 26) : rgb(120, 96, 60)))
    p.fill(0, 0, w, h, paper)
    for x in 0..<w { p.set(x, 0, edge); p.set(x, h - 1, edge) }
    for y in 0..<h { p.set(0, y, edge); p.set(w - 1, y, edge) }
    for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] { p.set(x, y, 0) }
    for x in 4..<w - 4 { p.set(x, h - 12, night ? rgb(212, 216, 232) : rgb(234, 226, 208)) }
    return p
}
/// Washi tape across a corner at 45 degrees: torn ends, see-through; 0 mint with dots, 1 pink with stripes.
func tapePic(_ k: Int) -> Pic {
    let len = 30, w = 9, S = Int(Double(len + w) * 0.72) + 2, c = k == 0 ? rgb(150, 214, 200) : rgb(246, 180, 190), c2 = k == 0 ? rgb(255, 255, 255) : rgb(255, 226, 232)
    var p = Pic(w: S, h: S)
    for y in 0..<S { for x in 0..<S {
        let dx = Double(x) + 0.5 - Double(S) / 2, dy = Double(y) + 0.5 - Double(S) / 2, u = (dx - dy) / 2.squareRoot(), v = (dx + dy) / 2.squareRoot()   // along, across
        let torn = Double(Int((v + 20) * 1.4) % 2) * 1.2
        guard abs(v) < Double(w) / 2, abs(u) < Double(len) / 2 - torn else { continue }
        let iu = Int((u + 40).rounded(.down)), iv = Int((v + 40).rounded(.down)), mark = k == 0 ? iu % 5 == 0 && iv % 4 == 1 : (iu + iv) % 6 < 2
        p.set(x, y, argb(205, mark ? c2 : abs(v) > Double(w) / 2 - 1 ? dim(c, 0.94) : c))
    } }
    return p
}
/// A push pin from above (the cork board's): a round head lit from the top left, its shadow down-right; 0 red, 1 blue.
func pinPic(_ k: Int, _ night: Bool) -> Pic {
    let head = ["..ooooo..", ".ohhccco.", "ohwhcccdo", "ohhcccddo", "occccddo.", ".occddo..", "..oooo..."]
    let (c, d, h, o) = k == 0 ? (rgb(226, 62, 52), rgb(168, 34, 34), rgb(255, 150, 130), rgb(110, 20, 24)) : (rgb(66, 118, 214), rgb(40, 76, 160), rgb(150, 190, 250), rgb(20, 36, 90))
    let pin = Pic(head, ["o": o, "c": c, "d": d, "h": h, "w": rgb(255, 255, 255)])
    var p = Pic(w: 12, h: 11)
    for y in 0..<pin.h { for x in 0..<pin.w where pin.at(x, y) != 0 { p.set(x + 2, y + 3, argb(night ? 140 : 80, night ? rgb(4, 8, 24) : rgb(90, 60, 30))) } }
    p.paste(pin, 0, 0)
    return p
}

// MARK: - stickers
/// Any picture as a die-cut sticker: a white rim 2 px round its own shape and a shadow down-right; the picture at (2, 2) of a canvas 6 px bigger,
/// rounded up to even sizes (whole pixels when centred). rimOnly leaves the picture out (the companion's sprite is drawn over its rim).
func sticker(_ src: Pic, night: Bool, rimOnly: Bool = false) -> Pic {
    let W = (src.w + 7) / 2 * 2, H = (src.h + 7) / 2 * 2
    var mask = [Bool](repeating: false, count: W * H), p = Pic(w: W, h: H)
    for y in 0..<src.h { for x in 0..<src.w where src.px[y * src.w + x] >> 24 > 0 {
        for dy in -2...2 { for dx in -2...2 where dx * dx + dy * dy <= 5 { mask[(y + 2 + dy) * W + x + 2 + dx] = true } }
    } }
    let shade = argb(night ? 140 : 80, night ? rgb(4, 8, 24) : rgb(110, 90, 60)), edge = argb(40, rgb(120, 100, 70)), white = night ? rgb(236, 238, 248) : rgb(255, 255, 255)
    func m(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < W && y < H && mask[y * W + x] }
    for y in 0..<H { for x in 0..<W where !mask[y * W + x] {
        if m(x - 1, y - 2) { p.px[y * W + x] = shade } else if !night, m(x + 1, y) || m(x - 1, y) || m(x, y + 1) || m(x, y - 1) { p.px[y * W + x] = edge }   // the cut, faint by day
    } }
    for k in 0..<W * H where mask[k] { p.px[k] = white }
    if !rimOnly { p.paste(src, 2, 2) }
    return p
}
@MainActor func spritePic(_ dex: Int) -> Pic { var p = Pic(w: 80, h: 80); for k in 0..<6400 { p.px[k] = spritePixel(dex, back: false, k % 80, k / 80, shiny: false) }; return p }
func iconPic(_ dex: Int) -> Pic { var p = Pic(w: 32, h: 32); for k in 0..<1024 { p.px[k] = iconPixel(dex, k % 32, k / 32) }; return p }
/// Frame f of an animation, its own box.
func animFramePic(_ a: Anim, _ f: Int) -> Pic { var p = Pic(w: a.w, h: a.h); for y in 0..<a.h { for x in 0..<a.w { p.px[y * a.w + x] = a.pixel(f, x, y, shiny: false) } }; return p }

// MARK: - the calendar: the season, drawn
/// A 13 x 13 flower of n round petals (notched: a cherry blossom's), outlined.
private func flower(_ n: Int, r: Double, _ c: [UInt32], centre: UInt32, core: Double, notch: Bool) -> Pic {
    var p = Pic(w: 13, h: 13)
    for y in 0..<13 { for x in 0..<13 {
        let px = Double(x) + 0.5 - 6.5, py = Double(y) + 0.5 - 6.5, d = hypot(px, py), k = abs(cos(Double(n) * (atan2(py, px) + .pi / 2) / 2))
        if d < core { p.set(x, y, centre); continue }
        let edge = r * (notch ? 0.35 + 0.65 * k : 0.45 + 0.55 * k) + 0.2
        guard d < edge, !(notch && k > 0.9 && d > edge - 1.6) else { continue }
        p.set(x, y, d < r * 0.5 ? c[2] : px + py < 0 ? c[1] : c[0])
    } }
    var q = p
    for y in 0..<13 { for x in 0..<13 where p.at(x, y) == 0 && [(1, 0), (-1, 0), (0, 1), (0, -1)].contains(where: { p.at(x + $0.0, y + $0.1) != 0 }) { q.set(x, y, c[3]) } }
    return q
}
func emblem(_ s: Season) -> Pic {
    switch s {
    case .spring: return flower(5, r: 6.0, [rgb(246, 170, 196), rgb(252, 204, 222), rgb(255, 236, 242), rgb(200, 90, 130)], centre: rgb(250, 214, 96), core: 1.6, notch: true)
    case .summer: return flower(12, r: 6.2, [rgb(246, 186, 30), rgb(255, 222, 70), rgb(255, 222, 70), rgb(170, 104, 16)], centre: rgb(124, 72, 30), core: 2.6, notch: false)
    case .autumn:
        return Pic(["......o......", ".....oRo.....", "..o..oRo..o..", "..oo.oRo.oo..", "..oRooRooRo..", "ooRRRrRrRRRoo", ".oRRRRrRRRRo.",
                    "..oRRRrRRRo..", ".ooRRRrRRRoo.", "..ooooroooo..", "......b......", "......b......"],
                   ["o": rgb(140, 40, 24), "R": rgb(226, 88, 44), "r": rgb(250, 150, 70), "b": rgb(110, 60, 30)])
    case .winter:
        return Pic(["......w......", "....w.w.w....", ".....www.....", ".w....w....w.", "..w...w...w..", "...ww.w.ww...", "wwwwwwWwwwwww",
                    "...ww.w.ww...", "..w...w...w..", ".w....w....w.", ".....www.....", "....w.w.w....", "......w......"], ["w": rgb(84, 140, 222), "W": rgb(40, 90, 180)])
    }
}
/// A desk calendar: a red top with two rings, the season drawn on the page.
func calendarPic(_ s: Season) -> Pic {
    let W = 22, H = 24
    var p = Pic(w: W, h: H)
    p.fill(0, 3, W, H - 3, rgb(255, 254, 248))
    p.fill(0, 3, W, 6, rgb(222, 64, 52)); for x in 0..<W { p.set(x, 8, rgb(160, 36, 32)) }
    for rx in [5, 15] { p.fill(rx, 0, 2, 5, rgb(90, 90, 100)); p.set(rx, 0, rgb(160, 160, 170)) }
    for x in 0..<W { p.set(x, H - 1, rgb(214, 206, 190)) }; for y in 9..<H { p.set(W - 1, y, rgb(214, 206, 190)) }
    let e = emblem(s); p.paste(e, (W - e.w) / 2, 9 + (H - 9 - e.h) / 2)
    return p
}

// MARK: - the emote
/// A speech bubble with ♪ ♥ or ! (WalkerView.emote's kinds), its tail down to the right, toward the head.
func bubblePic(_ kind: Int) -> Pic {
    var p = Pic(["..oooooooooooo..", ".owwwwwwwwwwwwo.", "owwwwwwwwwwwwwwo", "owwwwwwwwwwwwwwo", "owwwwwwwwwwwwwwo", "owwwwwwwwwwwwwwo", "owwwwwwwwwwwwwwo",
                 "owwwwwwwwwwwwwwo", "owwwwwwwwwwwwwgo", ".oggwwwwwwwwggo.", "..oooooowwoooo..", "........owwo....", ".........owo....", "..........oo...."],
                ["o": rgb(56, 60, 76), "w": rgb(255, 255, 255), "g": rgb(214, 220, 232)])
    let glyph = [["...bb..", "...bbb.", "...b.bb", "...b..b", ".bbb...", "bbbb...", ".bb...."],
                 [".oo.oo.", "oRHoRRo", "oHRRRRo", "oRRRRRo", ".oRRRo.", "..oRo..", "...o..."],
                 ["..RRo..", "..RRo..", "..RRo..", "..RRo..", "...o...", ".......", "..RRo.."]][max(0, min(2, kind))]
    p.paste(Pic(glyph, ["b": rgb(58, 96, 200), "o": rgb(150, 30, 40), "R": rgb(236, 64, 72), "H": rgb(255, 180, 180)]), 5, 2)
    return p
}

/// Self-test checks for this file (run by selftest()).
@MainActor func notebookChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func lum(_ p: Pic) -> Double { p.px.reduce(0) { $0 + 0.3 * Double($1 >> 16 & 255) + 0.59 * Double($1 >> 8 & 255) + 0.11 * Double($1 & 255) } / Double(p.px.count) }
    var pages = true
    for s in paperNames.indices { for grey in [false, true] {
        let ps = (0..<4).map { paperPic(s, $0, grey: grey) }
        if ps.contains(where: { $0.w != 192 || $0.h != 128 || $0.px.contains { $0 >> 24 != 255 } || Set($0.px).count < 2 }) || lum(ps[3]) >= lum(ps[0]) - 40 { pages = false }
    } }
    c.append((pages, "수첩 배경: every paper x time of day renders, colour and grey (opaque, patterned, dark by night)"))
    var s = Walk(); s.owned = [25]; s.caught = [Mon(dex: 16, level: 5, female: false), Mon(dex: 41, level: 5, female: false), Mon(dex: 60, level: 5, female: false)]; s.egg = Egg(dex: 175, left: 300)
    let v = WalkerView(state: s); v.persist = false; v.screen = .home
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var early = Set<String>(), later = Set<String>()
    for f in 0..<900 {                                                                            // 90 s walking and standing, a pat, an emote; then the same an hour on
        let now = t0.addingTimeInterval(Double(f % 450) * 0.1 + (f < 450 ? 0 : 3600.3))
        v.lastStep = f % 150 < 70 ? now : .distantPast; v.strollAt = now.addingTimeInterval(-0.1)
        if f % 450 == 200 { v.animOn = ("home", 25, now); v.emote = (1, now.addingTimeInterval(2)) }
        v.stroll(now); for p in v.compose(now).pics { if f < 450 { early.insert(p.key) } else { later.insert(p.key) } }
    }
    c.append((later.isSubset(of: early) && early.count < 120 && early.contains { $0.hasPrefix("nb|me|25|0|") } && early.contains("nb|bubble|1"),
              "home's picture keys come from a finite set, not the clock (\(early.count)); the rim follows the animation's frames"))
    v.animOn = nil; v.emote = nil
    var stickers = true
    for n in 0...3 { for egg in [false, true] {
        v.state.caught = Array(s.caught.prefix(n)); v.state.egg = egg ? s.egg : nil
        let keys = v.compose(t0).pics.map(\.key)
        if keys.filter({ $0.hasPrefix("nb|icon|") }).count != n || keys.contains(where: { $0.hasPrefix("nb|egg|") }) != egg { stickers = false }
    } }
    c.append((stickers, "home: a sticker for each of the walker's 0-3 catches, and the egg's when there is one"))
    let fb = v.compose(t0), rim = fb.pics.first { $0.key.hasPrefix("nb|me|25|s|") }, rp = rim.flatMap { picStore[$0.key] }, sp = fb.sprites.first
    let under = rp.map { p in (0..<6400).allSatisfy { k in spritePixel(25, back: false, k % 80, k / 80, shiny: false) == 0 || p.at(k % 80 + 2, k / 80 + 2) == rgb(255, 255, 255) } } ?? false
    c.append((sp.map { 2 * ($0.x + 16) == stickerFeet.x && 2 * ($0.y + 32) == stickerFeet.y && $0.frame == nil } == true && rim.map { $0.x - rp!.w / 2 == stickerFeet.x - 42 } == true && under,
              "home: the companion stands on its sticker, the white rim under every pixel of its sprite"))
    let photo = (x: 2 * courseBox.x, y: 2 * courseBox.y, w: 2 * courseBox.w, h: 2 * courseBox.h)
    var inside = polaroid.x + 4 == photo.x && polaroid.y + 4 == photo.y && polaroid.w == photo.w + 8
    for x in stride(from: v.strollRange.lowerBound, through: v.strollRange.upperBound, by: 3) {
        v.strollX = x; v.lastStep = t0
        guard let w = v.compose(t0).pics.first(where: { $0.key.hasPrefix("walk|") }), w.clip.count == 4 else { inside = false; break }
        if w.clip[0] < photo.x || w.clip[1] < photo.y || w.clip[0] + w.clip[2] > photo.x + photo.w || w.clip[1] + w.clip[3] > photo.y + photo.h || w.x - 16 < photo.x || w.x + 16 > photo.x + photo.w { inside = false }
    }
    c.append((inside, "home: the walker walks the polaroid's photo, clipped to it, end to end"))
    var right = 0                                                                              // the rightmost opaque column of any front sprite
    for d in 1...493 { for x in stride(from: 79, to: right, by: -1) where (0..<80).contains(where: { spritePixel(d, back: false, x, $0, shiny: false) != 0 }) { right = x; break } }
    let edge: Int = stickerFeet.x - 40 + right + 3
    c.append((edge < 192, "home: the widest companion and its sticker rim clear the right bezel"))
    v.state.companion = Mon(dex: 6, level: 30, female: false); _ = v.compose(t0)
    c.append((!picStore.keys.contains { $0.hasPrefix("nb|me|25|") } && picStore.keys.contains { $0.hasPrefix("nb|me|6|") }, "home: a new companion lets the old one's sticker rims go"))
    return c
}
