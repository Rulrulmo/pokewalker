import Foundation
// 5.0, the LCD's pages dressed (LCDDeco.swift): each group in a place of its own, drawn at the sprite's resolution (192 x 128 half-dots, under
// the dots) — 포켓몬 · 코스 a meadow, 도감 the lab's shelves, 친구 · 교환 the Pokémon Center's link counter, 우편 an airmail letter, 상점 the Poké
// Mart's shelves, 타워 its hall, 레이드 the cave (its boss's weather), 카드 the trainer card; the words' light panel; the title's band with the
// group's mark; a message's card edged by what it says.

enum LCDScenes {
    // MARK: the places
    static func scene(_ g: PageGroup) -> Pic {
        var p = Pic(w: 192, h: 128)
        func f(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32) { p.fill(x, y, w, h, c) }
        func h(_ x: Int, _ y: Int, _ s: Int) -> Int { hashXY(x, y, s) }
        switch g {
        case .pokemon, .notice, .course:                                                         // a meadow: sky, clouds, hills, grass with flowers
            for y in 0..<128 { for x in 0..<192 {
                let hill = 60 + Int(6 * sin(Double(x) / 18) + 3 * sin(Double(x) / 7)), grass = 78 + Int(2 * sin(Double(x) / 11))
                let c: UInt32 = y < hill ? lerpRGB(rgb(140, 200, 244), rgb(222, 240, 252), Double(y) / 64)
                    : y < grass ? (y == hill ? rgb(92, 150, 86) : lerpRGB(rgb(128, 184, 116), rgb(108, 168, 98), Double(y - hill) / 18))
                    : h(x, y, 3) % 11 == 0 ? rgb(96, 158, 78) : h(x, y, 5) % 173 == 0 ? [rgb(255, 255, 255), rgb(255, 222, 80), rgb(255, 150, 180)][h(x, y, 7) % 3] : lerpRGB(rgb(150, 206, 108), rgb(126, 190, 92), Double(y - grass) / 50)
                p.px[y * 192 + x] = c
            } }
            for (cx, cy, r) in [(36, 22, 9), (48, 20, 7), (148, 14, 8), (160, 16, 6)] { for y in -r...r { for x in -2 * r...2 * r where Double(x * x) / 4 + Double(y * y) <= Double(r * r) { p.set(cx + x, cy + y, rgb(255, 255, 255)) } } }
        case .dex:                                                                               // the lab: shelves of books, a floor
            f(0, 0, 192, 128, rgb(236, 228, 208))
            let cols = [rgb(200, 72, 64), rgb(64, 110, 196), rgb(84, 168, 96), rgb(232, 184, 64), rgb(150, 92, 190), rgb(70, 170, 170), rgb(220, 120, 60)]
            for top in [16, 46, 76] {
                f(0, top + 24, 192, 4, rgb(140, 96, 58)); f(0, top + 28, 192, 1, rgb(96, 64, 40))
                var x = 2
                while x < 190 {
                    let w = 4 + h(x, top, 11) % 4, ht = 15 + h(x, top, 13) % 8, c = cols[h(x, top, 17) % cols.count]
                    if h(x, top, 19) % 9 != 0 { f(x, top + 24 - ht, w, ht, c); f(x, top + 24 - ht, 1, ht, lerpRGB(c, rgb(255, 255, 255), 0.35)); f(x + w - 1, top + 24 - ht, 1, ht, lerpRGB(c, rgb(0, 0, 0), 0.3)); f(x, top + 24 - ht + 3, w, 1, lerpRGB(c, rgb(255, 240, 200), 0.5)) }
                    x += w + (h(x, top, 23) % 5 == 0 ? 3 : 0)
                }
            }
            f(0, 106, 192, 22, rgb(206, 178, 136)); for x in stride(from: 0, to: 192, by: 24) { f(x, 106, 1, 22, rgb(176, 146, 106)) }
        case .social:                                                                            // the Pokémon Center: its pink wall, the link windows, the counter, tiles
            f(0, 0, 192, 30, rgb(238, 116, 128)); f(0, 26, 192, 4, rgb(255, 236, 238)); f(0, 30, 192, 60, rgb(252, 244, 240))
            for x0 in [16, 132] { f(x0, 40, 44, 32, rgb(70, 88, 120)); f(x0 + 2, 42, 40, 28, rgb(110, 190, 236)); for k in 0..<4 { f(x0 + 4, 46 + 6 * k, 20 + h(x0, k, 3) % 14, 2, rgb(220, 246, 255)) } }
            f(0, 84, 192, 18, rgb(220, 86, 98)); f(0, 84, 192, 3, rgb(250, 160, 168))
            for y in 102..<128 { for x in 0..<192 { p.px[y * 192 + x] = ((x / 12) + (y - 102) / 8) % 2 == 0 ? rgb(238, 234, 222) : rgb(222, 216, 202) } }
        case .mail:                                                                              // an airmail letter: its striped edge, faint lines, a stamp
            f(0, 0, 192, 128, rgb(252, 248, 236))
            for y in stride(from: 36, to: 124, by: 10) { f(8, y, 176, 1, rgb(226, 220, 204)) }
            for y in 0..<128 { for x in 0..<192 where x < 5 || x > 186 || y < 5 || y > 122 { p.px[y * 192 + x] = ((x + y) / 6) % 3 == 0 ? rgb(214, 64, 64) : ((x + y) / 6) % 3 == 1 ? rgb(252, 248, 236) : rgb(60, 96, 196) } }
            f(10, 94, 26, 26, rgb(255, 255, 255)); f(13, 97, 20, 20, rgb(240, 96, 88)); f(13, 107, 20, 10, rgb(255, 255, 255)); f(13, 106, 20, 2, rgb(40, 40, 50)); f(21, 104, 4, 4, rgb(40, 40, 50))
            for k in stride(from: 10, to: 37, by: 3) { p.set(k, 94, rgb(252, 248, 236)); p.set(k, 119, rgb(252, 248, 236)); p.set(10, 84 + k, rgb(252, 248, 236)); p.set(35, 84 + k, rgb(252, 248, 236)) }
        case .shop:                                                                              // the Poké Mart: blue shelves of boxes, a tiled floor
            f(0, 0, 192, 128, rgb(214, 232, 250))
            let cols = [rgb(236, 80, 80), rgb(80, 160, 236), rgb(250, 200, 70), rgb(120, 200, 110), rgb(200, 120, 220)]
            for top in [18, 50, 82] {
                f(0, top + 22, 192, 5, rgb(60, 110, 190)); f(0, top + 22, 192, 1, rgb(140, 180, 236))
                var x = 3
                while x < 188 { let w = 8 + h(x, top, 5) % 6, ht = 10 + h(x, top, 7) % 10, c = cols[h(x, top, 9) % cols.count]; f(x, top + 22 - ht, w, ht, c); f(x, top + 22 - ht, w, 2, lerpRGB(c, rgb(255, 255, 255), 0.4)); f(x + 2, top + 22 - ht + 4, w - 4, 2, rgb(255, 255, 255)); x += w + 2 }
            }
            for y in 114..<128 { for x in 0..<192 { p.px[y * 192 + x] = ((x / 10) + (y - 114) / 7) % 2 == 0 ? rgb(236, 240, 248) : rgb(214, 224, 240) } }
        case .tower:                                                                             // the Battle Tower's hall: pillars, a checked floor
            for y in 0..<128 { for x in 0..<192 { p.px[y * 192 + x] = lerpRGB(rgb(182, 190, 220), rgb(150, 158, 194), Double(y) / 100) } }
            for x0 in stride(from: 8, to: 192, by: 52) {
                f(x0, 8, 18, 92, rgb(214, 220, 238)); f(x0, 8, 3, 92, rgb(240, 244, 252)); f(x0 + 15, 8, 3, 92, rgb(160, 168, 200))
                f(x0 - 3, 4, 24, 6, rgb(226, 232, 248)); f(x0 - 3, 98, 24, 6, rgb(226, 232, 248))
            }
            for y in 100..<128 { for x in 0..<192 { p.px[y * 192 + x] = ((x + (y - 100) * 2) / 14 + (y - 100) / 7) % 2 == 0 ? rgb(208, 214, 234) : rgb(172, 180, 210) } }
        case .raid, .mega:                                                                       // a cave: rock round, its roof's teeth, a lit hollow
            for y in 0..<128 { for x in 0..<192 {
                let n = h(x / 3, y / 3, 5) % 7, ex = (Double(x) - 60) / 62, ey = (Double(y) - 70) / 58, inside = ex * ex + ey * ey < 1
                let rock = lerpRGB(rgb(78, 66, 102), rgb(44, 38, 62), Double(n) / 7)
                p.px[y * 192 + x] = inside ? lerpRGB(lerpRGB(rgb(66, 56, 94), tones(g).band, 0.35), rgb(206, 196, 226), min(1, max(0, Double(y - 20) / 100)) * 0.6) : rock
            } }
            for x in stride(from: 4, to: 192, by: 13) { let l = 5 + h(x, 1, 3) % 9; for y in 0..<l { f(x + y / 3, y, max(1, 5 - y / 2), 1, rgb(36, 30, 52)) } }
        case .card:                                                                              // the trainer card: its coloured edge, a cream face, a stripe
            f(0, 0, 192, 128, rgb(232, 112, 96)); for y in 0..<128 where y % 6 < 2 { f(0, y, 192, 1, rgb(242, 140, 124)) }
            f(6, 26, 180, 96, rgb(252, 246, 232)); f(6, 26, 180, 2, rgb(255, 255, 255)); f(6, 120, 180, 2, rgb(220, 200, 180))
        }
        return p
    }
    static func tones(_ g: PageGroup) -> (band: UInt32, light: UInt32, pad: UInt32) { LCDDeco.tones(g) }

    // MARK: the panel the words sit on, the title's band and mark, the corners
    /// A light panel, rounded, its edge in the group's colour (w x h half-dots).
    static func panel(_ g: PageGroup, _ w: Int, _ h: Int) -> Pic {
        let c = tones(g).band; var p = Pic(w: w, h: h)
        for y in 0..<h { for x in 0..<w {
            let dx = min(x, w - 1 - x), dy = min(y, h - 1 - y)
            if dx < 4, dy < 4, hypot(Double(4 - dx), Double(4 - dy)) > 4.2 { continue }
            p.px[y * w + x] = dx == 0 || dy == 0 ? lerpRGB(c, rgb(60, 60, 70), 0.2) : argb(236, y < 3 ? rgb(255, 255, 255) : rgb(252, 251, 246))
        } }
        return p
    }
    /// The title's band: the group's colour, lit along its top, a darker edge under, its mark's place on the left.
    static func band(_ g: PageGroup) -> Pic {
        let c = tones(g).band; var p = Pic(w: 192, h: 24)
        for y in 0..<24 { for x in 0..<192 {
            p.px[y * 192 + x] = y < 2 ? lerpRGB(c, rgb(255, 255, 255), 0.5) : y > 21 ? lerpRGB(c, rgb(30, 30, 50), 0.35) : (x / 3 + y / 3) % 2 == 0 ? lerpRGB(c, rgb(255, 255, 255), 0.2) : lerpRGB(c, rgb(255, 255, 255), 0.12)
        } }
        return p
    }
    /// The group's mark, 14 x 14: a ball, a book, two heads, an envelope, a bag, the tower, a crystal, a key stone, a card, an i, a map pin.
    static func mark(_ g: PageGroup) -> Pic {
        let o = rgb(40, 40, 52), w = rgb(255, 255, 255), c = tones(g).band, d = lerpRGB(c, rgb(0, 0, 0), 0.35)
        let rows: [String]
        switch g {
        case .pokemon: rows = ["....oooooo....", "..oorrrrrroo..", ".orrrrrrrrrro.", ".orrrrrrrrrro.", "orrrrrooorrrro", "orrrrowwworrro", "oooooowwwooooo", "owwwwowwwowwwo", "owwwwwooowwwwo", ".owwwwwwwwwwo.", ".owwwwwwwwwwo.", "..oowwwwwwoo..", "....oooooo....", ".............."]
        case .dex: rows = ["..............", ".oooooooooooo.", ".occccccccccwo", ".occccccccccwo", ".occwwwwwwccwo", ".occwwwwwwccwo", ".occccccccccwo", ".occccccccccwo", ".occccccccccwo", ".occccccccccwo", ".occccccccccwo", ".oooooooooooo.", "..wwwwwwwwwww.", ".............."]
        case .social: rows = ["..............", "..ooo....ooo..", ".occco..occco.", ".occco..occco.", ".occco..occco.", "..ooo....ooo..", ".ooooo..ooooo.", "occcccooccccco", "occcccooccccco", "occcccooccccco", "occcccooccccco", "oooooooooooooo", "..............", ".............."]
        case .mail: rows = ["..............", "..............", "oooooooooooooo", "oowwwwwwwwwwoo", "owowwwwwwwwowo", "owwowwwwwwowwo", "owwwowwwwowwwo", "owwwwoccowwwwo", "owwwwwccwwwwwo", "owwwwwwwwwwwwo", "oooooooooooooo", "..............", "..............", ".............."]
        case .shop: rows = ["....oooooo....", "...o......o...", "...o......o...", ".oooooooooooo.", ".occccccccccco", ".occccccccccco", ".occcwwwwwccco", ".occcwddwwccco", ".occcwwwwwccco", ".occccccccccco", ".occccccccccco", ".oooooooooooo.", "..............", ".............."]
        case .tower: rows = ["......oo......", ".....occo.....", ".....occo.....", "....occcco....", "....owcwco....", "....occcco....", "...occccccо...", "...owcwcwco...", "...occcccco...", "..occccccccо..", "..owcwcwcwco..", "..occcccccco..", ".oooooooooooo.", ".............."]
        case .raid: rows = ["......o.......", ".....oco......", ".....occo.....", "....occcco....", "....owccco....", "...occcccco...", "...owccccco...", "..occccccccо..", "..owcccccccо..", ".occccccccccо.", ".oooooooooooo.", "..............", "..............", ".............."]
        case .mega: return megaMark()
        case .card: rows = ["..............", "oooooooooooooo", "occccccccccccо", "owwwwwwwwwwwwo", "owoowwwwwwwwwo", "owoowwddddwwwo", "owwwwwwwwwwwwo", "owoowwddddddwo", "owoowwwwwwwwwo", "owwwwwwwwwwwwo", "oooooooooooooo", "..............", "..............", ".............."]
        case .course: rows = ["....oooooo....", "...occcccco...", "..occcwwccco..", "..occwwwwcco..", "..occwwwwcco..", "..occcwwccco..", "...occcccco...", "....occcco....", ".....occo.....", "......oo......", "..............", "...dddddddd...", "..............", ".............."]
        case .notice: rows = ["....oooooo....", "..oowwwwwwoo..", ".owwwwccwwwwo.", ".owwwwccwwwwo.", "owwwwwwwwwwwwo", "owwwwwccwwwwwo", "owwwwwccwwwwwo", "owwwwwccwwwwwo", "owwwwwccwwwwwo", ".owwwwccwwwwo.", ".owwwwwwwwwwo.", "..oowwwwwwoo..", "....oooooo....", ".............."]
        }
        return Pic(rows.map { $0.replacingOccurrences(of: "о", with: "o") }, ["o": o, "w": w, "c": c, "d": d, "r": rgb(230, 70, 70)])
    }
    /// The Mega's mark: a key stone (a rainbow orb, the helix in it in white), not a ring a line runs through (that reads "no").
    static func megaMark() -> Pic {
        let cs = MegaFX.colours(6, 1); var p = Pic(w: 14, h: 14)
        for y in 0..<14 { for x in 0..<14 {
            let dx = Double(x) - 6.5, dy = Double(y) - 6.5, r = hypot(dx, dy)
            guard r < 6.9 else { continue }
            if r > 5.9 { p.set(x, y, rgb(40, 40, 52)); continue }
            let s = 1.9 * sin(dy / 1.5)
            if abs(dy) < 4.6, abs(dx - s) < 0.75 || abs(dx + s) < 0.75 { p.set(x, y, rgb(255, 255, 255)); continue }
            let hue = cs[min(cs.count - 1, Int((dx + dy + 12) / 24 * Double(cs.count)))]
            p.set(x, y, r > 4.6 ? lerpRGB(hue, rgb(30, 30, 50), 0.25) : hue)
        } }
        return p
    }
    /// A white veil over a place (a message's: its card stands out).
    static func veil() -> Pic { var p = Pic(w: 192, h: 128); p.fill(0, 0, 192, 128, argb(120, rgb(255, 253, 246))); return p }

    // MARK: a message's card, by what it says
    enum Kind { case reward, warn, wait, info }
    static func kind(_ lines: [String]) -> Kind {
        let s = lines.joined(separator: " ")
        if ["BP", "보상", "받았다", "얻었다", "깼다", "이겼다", "잡았다", "왔다!", "올랐다"].contains(where: s.contains) { return .reward }
        if ["중...", "중…", "준비 중", "불러오는"].contains(where: s.contains) { return .wait }
        if ["없어요", "못", "실패", "부족", "연결되면", "할 수 없", "안 돼", "끊겼"].contains(where: s.contains) { return .warn }
        return .info
    }
    /// A message's card (w x h half-dots): white, rounded, a thin edge and a strip along its top in the colour of what it says (보상 gold,
    /// 경고 orange, 기다림 blue, 안내 its grey-blue).
    static func noticeCard(_ k: Kind, _ w: Int, _ h: Int) -> Pic {
        let c: UInt32 = switch k { case .reward: rgb(236, 184, 60); case .warn: rgb(236, 136, 72); case .wait: rgb(110, 164, 228); case .info: rgb(146, 166, 198) }
        var p = Pic(w: w, h: h)
        for y in 0..<h { for x in 0..<w {
            let dx = min(x, w - 1 - x), dy = min(y, h - 1 - y)
            if dx < 5, dy < 5, hypot(Double(5 - dx), Double(5 - dy)) > 5.2 { continue }
            p.px[y * w + x] = dx == 0 || dy == 0 ? lerpRGB(c, rgb(60, 50, 40), 0.3) : y < 4 ? c : y == 4 ? lerpRGB(c, rgb(255, 255, 255), 0.5) : argb(246, rgb(255, 254, 250))
        } }
        return p
    }

    // MARK: the raid's weather, by its boss's type
    static func weatherBit(_ type: String) -> Pic {
        switch type {
        case "water": return Pic(["b", "b", "B", "B", "B"], ["b": rgb(150, 200, 255), "B": rgb(90, 150, 240)])
        case "ice": return Pic([".w.", "www", ".w."], ["w": rgb(240, 250, 255)])
        case "fire": return Pic(["oy", "yo"], ["o": rgb(255, 140, 40), "y": rgb(255, 220, 90)])
        case "electric": return Pic(["..yy", ".yy.", "yyyy", ".yy.", "yy.."], ["y": rgb(255, 236, 80)])
        case "grass", "bug": return Pic([".gg", "ggg", "gg."], ["g": rgb(110, 200, 90)])
        case "ground", "rock", "steel": return Pic(["s"], ["s": rgb(214, 190, 140)])
        case "ghost", "dark", "poison": return Pic([".pp.", "pppp", ".pp."], ["p": argb(150, rgb(170, 110, 220))])
        case "psychic", "fairy": return Pic(["..p..", ".pPp.", "..p.."], ["p": rgb(255, 150, 200), "P": rgb(255, 230, 245)])
        default: return Pic(["..w..", ".wWw.", "..w.."], ["w": rgb(220, 220, 255), "W": rgb(255, 255, 255)])
        }
    }
    /// How it falls: (x speed, y speed) half-dots a second.
    static func weatherFall(_ type: String) -> (Double, Double) {
        switch type { case "water": (-30, 150); case "ice": (-8, 24); case "fire": (6, -26); case "electric": (0, 0); case "grass", "bug": (22, 18); case "ground", "rock", "steel": (60, 8); case "ghost", "dark", "poison": (5, -10); default: (4, 12) }
    }

    /// The Mega raid's aura: a ring of the rainbow round the boss (72 x 72), brightest at its middle, soft at its edges.
    static func rainbowRing() -> Pic {
        let n = 72, cs = MegaFX.colours(6, 1); var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - 35.5, dy = Double(y) - 35.5, r = hypot(dx, dy)
            guard r > 12, r < 35 else { continue }
            let k = 1 - abs(r - 24) / 11, a = (atan2(dy, dx) + .pi) / (2 * .pi) * Double(cs.count)
            let col = lerpRGB(cs[Int(a) % cs.count], cs[(Int(a) + 1) % cs.count], a - a.rounded(.down))
            p.px[y * n + x] = argb(UInt8(max(0, min(210, 230 * k))), lerpRGB(col, rgb(255, 255, 255), 0.15))
        } }
        return p
    }

    // MARK: a Mega stone, big
    /// The stone of a Mega in its type's tones: an orb, lit at its top left, the helix swirling inside (48 x 48).
    static func stonePic(_ type: String) -> Pic {
        let t = fxTones[type] ?? fxTones["normal"]!, n = 48, c = 23.5
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - c, dy = Double(y) - c, r = hypot(dx, dy)
            guard r < 22 else { continue }
            let lit = max(0, 1 - hypot(dx + 8, dy + 8) / 26), edge = r > 20.5
            var col = edge ? t[0] : lerpRGB(t[1], t[3], lit)
            let s1 = 6 * sin(dy / 5), s2 = -s1
            if !edge, abs(dy) < 15, abs(dx - s1) < 1.6 || abs(dx - s2) < 1.6 { col = abs(dx - s1) < 1.6 ? lerpRGB(t[4], rgb(255, 255, 255), 0.3) : lerpRGB(t[2], t[0], 0.4) }
            if hypot(dx + 9, dy + 10) < 3.5 { col = rgb(255, 255, 255) }
            p.px[y * n + x] = col
        } }
        return p
    }
}
