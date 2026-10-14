import Foundation
// 5.0 (the user: "전체적으로 좀 상단 패널 꾸며 보는건 어떨까?"): the LCD's pages dressed — the screens that are a title, a Pokémon and a
// column of words (포켓몬 · 도감 · 친구 · 교환 · 우편 · 상점 · 가방 · 타워 · 레이드 …) get a backdrop, a band under the title and a pad under
// the Pokémon, all below the dots (PicRun.under: the page's own lines, marks and words stay over them). One look for every page, coloured
// by its group; the raids open a cave on the left, its boss lit in its type's colour (a Mega's in the rainbow). decoStyle picks the look
// (0 = the plain page as before): 1 수첩 (the home's paper and tape, the Pokémon as a sticker), 2 게임 (a coloured band, a soft ground, a pad and
// a glow), 3 도트 (the Pokéwalker's own: dithered, quiet).

@MainActor var decoStyle = min(max(settings.int("deco", 0), 0), 3)

enum PageGroup: String { case pokemon, social, shop, tower, raid, mega, notice, card }

enum LCDDeco {
    /// A group's colours: its band, its light (backdrop), its pad.
    static func tones(_ g: PageGroup) -> (band: UInt32, light: UInt32, pad: UInt32) {
        switch g {
        case .pokemon: (rgb(120, 196, 120), rgb(226, 242, 214), rgb(118, 176, 92))
        case .social: (rgb(112, 160, 228), rgb(222, 234, 250), rgb(150, 170, 200))
        case .shop: (rgb(236, 178, 84), rgb(250, 236, 206), rgb(196, 150, 96))
        case .tower: (rgb(132, 146, 186), rgb(226, 230, 242), rgb(150, 156, 178))
        case .raid: (rgb(150, 112, 204), rgb(234, 226, 246), rgb(120, 104, 140))
        case .mega: (rgb(196, 104, 255), rgb(240, 230, 252), rgb(140, 120, 170))
        case .notice: (rgb(206, 196, 172), rgb(246, 242, 232), rgb(190, 180, 160))
        case .card: (rgb(226, 110, 100), rgb(250, 230, 226), rgb(200, 140, 130))
        }
    }
    /// The backdrop, 192 x 128 half-dots: 1 the home's paper; 2 its light fading down, faint stripes; 3 a dot grid.
    static func backdrop(_ g: PageGroup, _ style: Int, paper: Int, tb: Int, grey: Bool) -> Pic {
        if style == 1 { return paperPic(paper, tb, grey: grey) }
        let t = tones(g); var p = Pic(w: 192, h: 128)
        for y in 0..<128 { for x in 0..<192 {
            if style == 2 { let k = Double(y) / 127; p.px[y * 192 + x] = (x + y) % 12 < 1 ? lerpRGB(t.light, rgb(255, 255, 255), 0.2 + 0.5 * k) : lerpRGB(t.light, rgb(252, 251, 246), 0.35 + 0.65 * k) }
            else { p.px[y * 192 + x] = x % 6 == 3 && y % 6 == 3 ? lerpRGB(t.light, t.band, 0.35) : rgb(247, 245, 236) }
        } }
        return p
    }
    /// The band under the title row (24 half-dots high): 1 a strip of washi tape w wide; 2 the group's colour across, lit at its top; 3 dithered.
    static func band(_ g: PageGroup, _ style: Int, _ w: Int) -> Pic {
        let t = tones(g)
        if style == 1 {
            var p = Pic(w: w, h: 20)
            for y in 0..<20 { for x in 0..<w where !(x < 3 && (y / 3) % 2 == (x == 0 ? 1 : 0)) && !(x >= w - 3 && (y / 3) % 2 == (x == w - 1 ? 1 : 0)) {
                p.px[y * w + x] = argb(170, (x / 6 + y / 6) % 2 == 0 ? t.band : lerpRGB(t.band, rgb(255, 255, 255), 0.35))
            } }
            return p
        }
        var p = Pic(w: 192, h: 24)
        for y in 0..<24 { for x in 0..<192 {
            if style == 2 { p.px[y * 192 + x] = y < 2 ? lerpRGB(t.band, rgb(255, 255, 255), 0.45) : y > 21 ? lerpRGB(t.band, rgb(40, 40, 60), 0.25) : lerpRGB(t.band, rgb(255, 255, 255), 0.18) }
            else if (x / 2 + y / 2) % 2 == 0 { p.px[y * 192 + x] = lerpRGB(t.light, t.band, 0.5) }
        } }
        return p
    }
    /// The pad the page's Pokémon stands on (an ellipse, 72 x 18), its group's ground; 3: a dithered shadow.
    static func pad(_ g: PageGroup, _ style: Int) -> Pic {
        let t = tones(g), W = 72, H = 18
        var p = Pic(w: W, h: H)
        for y in 0..<H { for x in 0..<W {
            let dx = (Double(x) + 0.5 - Double(W) / 2) / (Double(W) / 2), dy = (Double(y) + 0.5 - Double(H) / 2) / (Double(H) / 2), r = dx * dx + dy * dy
            guard r <= 1 else { continue }
            if style == 3 { if (x + y) % 2 == 0 { p.px[y * W + x] = argb(110, rgb(90, 90, 80)) }; continue }
            let rim = r > 0.78, top = dy < -0.2
            p.px[y * W + x] = rim ? lerpRGB(t.pad, rgb(40, 40, 50), 0.35) : top ? lerpRGB(t.pad, rgb(255, 255, 255), 0.3) : t.pad
        } }
        return p
    }
    /// A soft glow behind the Pokémon (radius 34), in a colour; rainbow: the Mega's hues round it.
    static func glow(_ c: UInt32, rainbow: Bool) -> Pic {
        let n = 72, cs = MegaFX.colours(6, 1)
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - 36, dy = Double(y) - 36, r = hypot(dx, dy)
            guard r < 34 else { continue }
            let a = UInt8(max(0, min(150, 150 * (1 - r / 34) * (1 - r / 34) * 1.6)))
            let col = rainbow ? cs[Int((atan2(dy, dx) + .pi) / (2 * .pi) * Double(cs.count)) % cs.count] : c
            p.px[y * n + x] = argb(a, lerpRGB(col, rgb(255, 255, 255), 0.25))
        } }
        return p
    }
    /// A message's card (say): 1 a paper note, its tape; 2 a white box in the group's colour; 3 a dotted frame. w x h half-dots.
    static func card(_ g: PageGroup, _ style: Int, _ w: Int, _ h: Int) -> Pic {
        let t = tones(g); var p = Pic(w: w, h: h)
        for y in 0..<h { for x in 0..<w {
            let edge = x < 2 || y < 2 || x >= w - 2 || y >= h - 2, corner = (x < 4 || x >= w - 4) && (y < 4 || y >= h - 4) && hypot(Double(min(x, w - 1 - x) - 4), Double(min(y, h - 1 - y) - 4)) > 4
            if corner { continue }
            switch style {
            case 1: p.px[y * w + x] = y >= h - 3 || x >= w - 3 ? argb(70, rgb(110, 90, 60)) : rgb(255, 253, 244)
            case 2: p.px[y * w + x] = edge ? t.band : y < h / 2 ? rgb(255, 255, 255) : lerpRGB(rgb(255, 255, 255), t.light, 0.6)
            default: if edge, (x + y) % 4 < 2 { p.px[y * w + x] = lerpRGB(t.band, rgb(60, 60, 70), 0.3) }
            }
        } }
        return p
    }
    /// The raid's window: a cave mouth on the left (96 x 104 half-dots), dark rock round a lit hollow where the boss stands.
    static func cave(_ g: PageGroup) -> Pic {
        let W = 100, H = 104, t = tones(g)
        var p = Pic(w: W, h: H)
        for y in 0..<H { for x in 0..<W {
            let n = hashXY(x / 3, y / 3, 5) % 7, ex = (Double(x) - 50) / 46, ey = (Double(y) - 62) / 50, inside = ex * ex + ey * ey < 1
            let rock = lerpRGB(rgb(70, 60, 92), rgb(40, 34, 56), Double(n) / 7)
            if !inside { p.px[y * W + x] = (y < 10 && x % 9 < 4 && y < 10 - x % 9) ? rgb(30, 26, 44) : rock; continue }
            let k = min(1, max(0, (Double(y) - 20) / 84))
            p.px[y * W + x] = lerpRGB(lerpRGB(rgb(60, 52, 86), t.band, 0.35), rgb(200, 190, 220), k * 0.55)
        } }
        return p
    }
}

extension Walker {
    /// The page's group, if this screen is one of the LCD's pages (home, a fight, the radar, a course, the shows: their own pictures).
    func pageGroup() -> PageGroup? {
        var sc = screen; if case .say(_, let next, _) = sc { if case .home = next { return .notice }; sc = next }
        switch sc {
        case .box, .dex, .itemOn, .hold, .formPick, .train, .relearn, .learn, .visitPick: return .pokemon
        case .team, .trade, .market, .mail, .duel, .squad: return .social
        case .shop, .shopConfirm, .items: return .shop
        case .tower(nil): return .tower
        case .raid(.lobby), .raid(.tier), .raid(.pick): return raidMega ? .mega : .raid
        case .card: return .card
        case .say: return .notice
        default: return nil
        }
    }
    /// The page dressed (LCDDeco), under what's drawn: its backdrop, the band under its title, its Pokémon's pad (and a glow; a raid's cave).
    func decorate(_ fb: inout FB, _ now: Date) {
        guard decoStyle > 0, let g = pageGroup() else { return }
        let style = decoStyle, grey = !lcds[lcdStyle].color, t = now.timeIntervalSinceReferenceDate, tone = grey ? "|g" : ""
        let ready = { (p: Pic) -> Pic in lcdReady(p) }
        fb.pic("deco|bg|\(g.rawValue)|\(style)|\(paperStyle)|\(lightBand(state.hour))" + tone, 96, 64, under: true) { ready(LCDDeco.backdrop(g, style, paper: paperStyle, tb: lightBand(state.hour), grey: grey)) }
        if case .say(let lines, _, _) = screen, g == .notice, !lines.isEmpty {                       // a message: its card
            fb.pic("deco|card|\(style)|\(lines.count)" + tone, 96, 64, under: true) { ready(LCDDeco.card(g, style, 176, min(120, 28 * lines.count + 28))) }
            if style == 1 { fb.pic("deco|tape|\(g.rawValue)|40" + tone, 96, 64 - min(60, 14 * lines.count + 14), angle: -4, under: true) { ready(LCDDeco.band(.notice, 1, 40)) } }
            return
        }
        let title = fb.runs.first { $0.y <= 1 && $0.x <= 3 }
        if style == 1, let r = title { let w = min(184, 2 * r.w + 12); fb.pic("deco|tape|\(g.rawValue)|\(w)" + tone, 1 + w / 2, 12, under: true) { ready(LCDDeco.band(g, 1, w)) } }
        else if style > 1, title != nil { fb.pic("deco|band|\(g.rawValue)|\(style)" + tone, 96, 12, under: true) { ready(LCDDeco.band(g, style, 192)) } }
        guard let s = fb.sprites.first(where: { $0.x == 16 && $0.y == 18 && !$0.back }) else { return }   // the page's Pokémon (fb.mon at the old box)
        let fx = 64, feet = 100                                                                        // its feet (half-dots)
        if g == .raid || g == .mega {                                                                 // the raid's cave, its boss lit
            fb.pic("deco|cave|\(g.rawValue)" + tone, 50, 26 + 52, under: true) { ready(LCDDeco.cave(g)) }
            let type = monTypes[raidLobby?.boss.dex ?? min(s.art, 721)].first ?? "normal", c = fxTones[type]?[2] ?? rgb(200, 200, 220)
            fb.pic("deco|glow|\(g == .mega ? "mega" : type)" + tone, fx, feet - 34, scale: 1 + 0.06 * sin(t * 2.4), alpha: 0.75 + 0.2 * sin(t * 2.4), under: true) { ready(LCDDeco.glow(c, rainbow: g == .mega)) }
            if g == .mega { fb.pic("deco|msym" + tone, fx, feet - 34, scale: 2.1, alpha: 0.22, angle: t * 12, under: true) { ready(MegaFX.symbolPic(6, 1)) } }
            return
        }
        switch style {
        case 1: if s.frame == nil, s.tint == nil { fb.pic("deco|rim|\(s.art)" + tone, fx + 1, feet - 40 + 1 - s.bob, under: true) { sticker(spritePic(s.art), night: false, rimOnly: true) } }
        case 2:
            fb.pic("deco|pad|\(g.rawValue)|2" + tone, fx, feet - 3, under: true) { ready(LCDDeco.pad(g, 2)) }
            fb.pic("deco|glow|\(g.rawValue)" + tone, fx, feet - 34, alpha: 0.6, under: true) { ready(LCDDeco.glow(LCDDeco.tones(g).band, rainbow: false)) }
        default: fb.pic("deco|pad|\(g.rawValue)|3" + tone, fx, feet - 2, under: true) { LCDDeco.pad(g, 3) }
        }
    }
}
