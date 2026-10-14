import Foundation
// 5.0 (the user: "전체적으로 좀 상단 패널 꾸며 보는건 어떨까?", then the second round's B: "2-B가 낫긴한데 …"): the LCD's pages dressed. Every page
// that is a title, maybe a Pokémon, and words (포켓몬 · 도감 · 친구 · 교환 · 우편 · 상점 · 가방 · 타워 · 레이드 · 카드 · 코스 …) stands in its group's
// place (LCDScenes.swift), drawn under the dots (PicRun.under: the page's own lines, marks and words stay over them): the title on the group's
// band with its mark; the words on a light panel fitted to them; the Pokémon sized and placed on the stage left of it and clipped to it — never
// over a word, the band or the panel (lcdOverlaps, decoChecks) — on a pad in a glow, a raid's boss lit in its type's colour with its weather
// falling, a Mega's in the rainbow; a message on a card fitted to its lines, edged in the colour of what it says. On a colour LCD the words and
// lines take the group's inks and a picked row its colour (FB.palette), kept inside the panel. lcdDeco off: the plain pages (the shots' LCD_DECO=0).

@MainActor var lcdDeco = true

enum PageGroup: String { case pokemon, dex, social, mail, shop, tower, raid, mega, notice, card, course }

enum LCDDeco {
    /// A group's colours: its band, its light, its pad.
    static func tones(_ g: PageGroup) -> (band: UInt32, light: UInt32, pad: UInt32) {
        switch g {
        case .pokemon: (rgb(120, 196, 120), rgb(226, 242, 214), rgb(118, 176, 92))
        case .dex: (rgb(222, 108, 96), rgb(248, 230, 222), rgb(176, 140, 104))
        case .mail: (rgb(96, 140, 220), rgb(232, 238, 250), rgb(170, 150, 120))
        case .social: (rgb(112, 160, 228), rgb(222, 234, 250), rgb(150, 170, 200))
        case .shop: (rgb(236, 178, 84), rgb(250, 236, 206), rgb(196, 150, 96))
        case .tower: (rgb(132, 146, 186), rgb(226, 230, 242), rgb(150, 156, 178))
        case .raid: (rgb(150, 112, 204), rgb(234, 226, 246), rgb(120, 104, 140))
        case .mega: (rgb(196, 104, 255), rgb(240, 230, 252), rgb(140, 120, 170))
        case .notice: (rgb(206, 196, 172), rgb(246, 242, 232), rgb(190, 180, 160))
        case .card: (rgb(226, 110, 100), rgb(250, 230, 226), rgb(200, 140, 130))
        case .course: (rgb(92, 178, 166), rgb(222, 242, 238), rgb(120, 170, 150))
        }
    }
    /// A group's inks on a colour LCD for shades 0...3 (FB.palette), in place of black and greys: 3 the words (its colour, deep), 2 a grey's, 1 a
    /// faint one's (0: the words' too). A picked row is in the group's colour, light: the words on it in its ink (a faint one, out of reach, a grey's).
    static func palette(_ g: PageGroup) -> [UInt32] {
        let c = tones(g).band, ink = lerpRGB(c, rgb(22, 22, 30), 0.74)
        return [ink, lerpRGB(c, rgb(206, 204, 198), 0.7), lerpRGB(c, rgb(104, 106, 116), 0.62), ink]
    }
    /// A picked row's colour (the dots of a highlight): the band's, a touch lighter.
    static func highlight(_ g: PageGroup) -> UInt32 { lerpRGB(tones(g).band, rgb(255, 255, 255), 0.1) }
    /// The pad the page's Pokémon stands on (an ellipse, 72 x 18), its group's ground.
    static func pad(_ g: PageGroup) -> Pic {
        let t = tones(g), W = 72, H = 18
        var p = Pic(w: W, h: H)
        for y in 0..<H { for x in 0..<W {
            let dx = (Double(x) + 0.5 - Double(W) / 2) / (Double(W) / 2), dy = (Double(y) + 0.5 - Double(H) / 2) / (Double(H) / 2), r = dx * dx + dy * dy
            guard r <= 1 else { continue }
            p.px[y * W + x] = r > 0.78 ? lerpRGB(t.pad, rgb(40, 40, 50), 0.35) : dy < -0.2 ? lerpRGB(t.pad, rgb(255, 255, 255), 0.3) : t.pad
        } }
        return p
    }
    /// A soft glow behind the Pokémon (radius 34), in a colour.
    static func glow(_ c: UInt32) -> Pic {
        let n = 72
        var p = Pic(w: n, h: n)
        for y in 0..<n { for x in 0..<n {
            let r = hypot(Double(x) - 36, Double(y) - 36)
            guard r < 34 else { continue }
            p.px[y * n + x] = argb(UInt8(max(0, min(150, 150 * (1 - r / 34) * (1 - r / 34) * 1.6))), lerpRGB(c, rgb(255, 255, 255), 0.25))
        } }
        return p
    }

    // MARK: the layout
    /// Where a dressed page's parts go, in half-dots (x, y, w, h): the words' panel; a strip across the bottom under the stage (a row of choices
    /// that starts at the left: 수락 · 거절 · 닫기); the stage, the Pokémon's (none without one).
    struct Layout: Equatable { var panel: [Int]; var strip: [Int]?; var stage: [Int]? }
    /// The page's layout from what it drew (band: its title is on the band; mon: its Pokémon at the old box). The panel starts left of the words
    /// right of the old box, in steps (paging through, it stays put); a row from the left edge below the box is the strip's, above it the stage
    /// starts under it.
    @MainActor static func layout(_ fb: FB, band: Bool, mon: Bool) -> Layout {
        let top = band ? 26 : 2
        guard mon else { return Layout(panel: [2, top, 188, 126 - top], strip: nil, stage: nil) }
        var left = 190, stageTop = top + 1, stripTop: Int? = nil
        func row(_ y0: Int, _ y1: Int) { if y0 >= 30 { stripTop = min(stripTop ?? 128, 2 * y0 - 3) } else { stageTop = max(stageTop, 2 * y1 + 2) } }
        for r in fb.runs where !band || r.y >= 11 {
            if r.x >= 28 { left = min(left, 2 * r.x - 5) } else { row(r.y, r.y + r.rows) }
        }
        for y in (band ? 12 : 0)..<64 {                                                              // dots: a row from the left edge (a box picked), or the panel's (a ★, a medal)
            let lit = (0..<96).filter { fb.px[y * 96 + $0] != 0 }
            guard let first = lit.first else { continue }
            if first < 28 { row(y, y + 1) } else { left = min(left, 2 * first - 3) }
        }
        let p = [100, 92, 84, 76, 68].first { $0 <= left } ?? 68, bottom = stripTop ?? 128
        return Layout(panel: [p, top, 190 - p, bottom - 2 - top], strip: stripTop.map { [2, $0, 188, 126 - $0] }, stage: [6, stageTop, p - 10, bottom - 4 - stageTop])
    }
    /// The Pokémon on its stage: as big as fits (up to 1.15 x), centred across it, standing just above its foot; moved, scaled (about its feet)
    /// and clipped to the stage. Its opaque box drawn (half-dots: x0, y0, x1, y1) comes with it.
    @MainActor static func fit(_ r: SpriteRun, _ stage: [Int]) -> (run: SpriteRun, box: [Double]) {
        let b = spriteBox(r.art).map(Double.init), bw = b[2] - b[0], bh = b[3] - b[1]
        let sw = Double(stage[2] - 2), sh = Double(stage[3] - 4)                                     // (room to round to a dot, and to bob)
        let k = min(1.15, sw / bw, sh / bh), free = sh - bh * k, bottom = Double(stage[1] + stage[3]) - min(8, free)
        let fx = Double(stage[0]) + Double(stage[2]) / 2 - ((b[0] + b[2]) / 2 - 40) * k, fy = bottom - (b[3] - 80) * k
        var q = r; q.scale = k; q.x = Int((fx / 2).rounded()) - 16; q.y = Int((fy / 2).rounded(.down)) - 32; q.clip = stage
        let ox = 2 * Double(q.x + 16), oy = 2 * Double(q.y + 32)
        return (q, [ox + (b[0] - 40) * k, oy + (b[1] - 80) * k, ox + (b[2] - 40) * k, oy + (b[3] - 80) * k])
    }
}

/// A picture's opaque box in its 80x80 frame: x0, y0, x1, y1 (x1, y1 past its last pixel); the whole frame if it's blank.
@MainActor var spriteBoxes: [Int: [Int]] = [:]
@MainActor func spriteBox(_ art: Int) -> [Int] {
    if let b = spriteBoxes[art] { return b }
    var b = [80, 80, 0, 0]
    for y in 0..<80 { for x in 0..<80 where spritePixel(art, back: false, x, y, shiny: false) != 0 { b = [min(b[0], x), min(b[1], y), max(b[2], x + 1), max(b[3], y + 1)] } }
    if b[2] <= b[0] { b = [0, 0, 80, 80] }
    spriteBoxes[art] = b; return b
}
/// A sprite's opaque box as drawn (half-dots: x0, y0, x1, y1), its clip and floor applied; nil when nothing shows.
@MainActor func drawnBox(_ s: SpriteRun) -> [Double]? {
    let b = playing(s).map { a in [a.x, a.y, a.x + a.w, a.y + a.h] } ?? spriteBox(s.art)
    let fx = 2 * Double(s.x + 16), fy = 2 * Double(s.y + 32) - Double(s.bob), k = s.scale
    var r = [fx + (Double(b[0]) - 40) * k, fy + (Double(b[1]) - 80) * k, fx + (Double(b[2]) - 40) * k, fy + (Double(b[3]) - 80) * k]
    if s.clip.count == 4 { let c = s.clip.map(Double.init); r = [max(r[0], c[0]), max(r[1], c[1]), min(r[2], c[0] + c[2]), min(r[3], c[1] + c[3])] }
    r[3] = min(r[3], 2 * Double(min(64, s.floor)))
    return r[2] > r[0] && r[3] > r[1] ? r : nil
}
/// What a dressed page's Pokémon covers that it mustn't: a word, the title's band, the words' panel or strip (none: all clear).
@MainActor func lcdOverlaps(_ fb: FB) -> [String] {
    var walls: [(String, [Double])] = fb.runs.map { r in ("“\(r.s)”", [2 * Double(r.x), 2 * Double(r.y) + 2, 2 * Double(r.x + r.w), 2 * Double(r.y + r.rows) - 2]) }
    for r in fb.pics where r.key.hasPrefix("deco|band") || r.key.hasPrefix("deco|panel") || r.key.hasPrefix("deco|strip") {
        guard let p = picStore[r.key] else { continue }
        let w = Double(p.w) * r.scale, h = Double(p.h) * r.scale
        walls.append((String(r.key.split(separator: "|")[1]), [Double(r.x) - w / 2, Double(r.y) - h / 2, Double(r.x) + w / 2, Double(r.y) + h / 2]))
    }
    var subjects: [(String, [Double])] = fb.sprites.filter { !$0.back && $0.alpha > 0 }.compactMap { s in drawnBox(s).map { ("#\(s.art)", $0) } }
    for r in fb.pics where r.key.hasPrefix("focus|") {                                             // a focus page's thing (FocusView.swift)
        guard let p = picStore[r.key] else { continue }
        let w = Double(p.w) * r.scale, h = Double(p.h) * r.scale
        subjects.append((r.key, [Double(r.x) - w / 2, Double(r.y) - h / 2, Double(r.x) + w / 2, Double(r.y) + h / 2]))
    }
    var out: [String] = []
    for (who, b) in subjects {
        for (name, w) in walls where min(b[2], w[2]) - max(b[0], w[0]) > 1 && min(b[3], w[3]) - max(b[1], w[1]) > 1 { out.append("\(who) × \(name)") }
    }
    return out
}

extension Walker {
    /// The page's group, if this screen is one of the LCD's pages (home, a fight, the radar, an evolution, the shows: their own pictures).
    func pageGroup() -> PageGroup? {
        if case .say(_, let next, _) = screen {                                                       // a message: its card, unless a fight's stage stays under it (sideOn)
            switch next { case .battle where sideOn, .moves where sideOn, .party where sideOn, .bagBattle where sideOn, .forfeit where sideOn: return nil; default: return .notice }
        }
        switch screen {
        case .dex: return .dex
        case .mail: return .mail
        case .box, .itemOn, .hold, .formPick, .train, .relearn, .learn, .visitPick: return .pokemon
        case .team, .trade, .market, .duel, .squad: return .social
        case .shop, .shopConfirm, .items: return .shop
        case .tower(nil): return .tower
        case .raid(.lobby), .raid(.tier): return raidMega ? .mega : .raid
        case .card: return .card
        case .course: return .course
        default: return nil
        }
    }
    /// The page dressed (the file's header), under what it drew; its Pokémon fitted to its stage.
    func decorate(_ fb: inout FB, _ now: Date) {
        guard lcdDeco, let g = pageGroup() else { return }
        let n0 = fb.pics.count
        defer { let added = Array(fb.pics[n0...]); fb.pics.removeSubrange(n0...); fb.pics.insert(contentsOf: added, at: 0) }   // (under the page's own: a stone's)
        let grey = !lcds[lcdStyle].color, t = now.timeIntervalSinceReferenceDate, tone = grey ? "|g" : ""
        let ready = { (p: Pic) -> Pic in lcdReady(p) }
        if !grey { fb.palette = LCDDeco.palette(g) }
        if case .say(let lines, _, _) = screen, g == .notice, !lines.isEmpty { decorateNotice(&fb, tone); return }
        let ti = fb.runs.firstIndex { $0.y <= 1 && $0.x <= 3 }, si = fb.sprites.firstIndex { $0.x == 16 && $0.y == 18 && !$0.back }   // the title; the Pokémon (fb.mon at the old box)
        let fi = si == nil ? fb.pics.firstIndex { $0.key.hasPrefix("focus|") } : nil                    // or a focus page's thing (FocusView.swift)
        let lay = LCDDeco.layout(fb, band: ti != nil, mon: si != nil || fi != nil), p = lay.panel
        fb.pic("deco|scene|\(g.rawValue)" + tone, 96, 64, under: true) { ready(LCDScenes.scene(g)) }
        fb.pic("deco|panel|\(g.rawValue)|\(p[2])|\(p[3])" + tone, p[0] + p[2] / 2, p[1] + p[3] / 2, under: true) { ready(LCDScenes.panel(g, p[2], p[3])) }
        if let s = lay.strip { fb.pic("deco|strip|\(g.rawValue)|\(s[3])" + tone, s[0] + s[2] / 2, s[1] + s[3] / 2, under: true) { ready(LCDScenes.panel(g, s[2], s[3])) } }
        if let ti {                                                                                  // the title's band, its mark before it
            fb.pic("deco|band|\(g.rawValue)" + tone, 96, 12, under: true) { ready(LCDScenes.band(g)) }
            fb.pic("deco|mark|\(g.rawValue)" + tone, 9, 12, under: true) { ready(LCDScenes.mark(g)) }
            let r = fb.runs[ti], x0 = max(1, r.x), x1 = min(87, r.x + r.w + 12)                   // what's drawn by the title (a medal) moves with it
            for y in 1..<11 { for x in stride(from: x1 - 1, through: x0, by: -1) {                // (not the card's frame: row 0, columns 0 and 95)
                let i = y * 96 + x, j = i + 8
                fb.px[j] = fb.px[i]; fb.col[j] = fb.col[i]
                if x < x0 + 8 { fb.px[i] = 0; fb.col[i] = 0 }
            } }
            fb.runs[ti].x += 8
            let right = fb.runs.indices.filter { $0 != ti && fb.runs[$0].y <= 2 && fb.runs[$0].x > r.x }.map { fb.runs[$0].x }.min() ?? 96, by = r.x + 8 + r.w
            let end = (by..<min(96, x1 + 8)).last { x in (1..<11).contains { fb.px[$0 * 96 + x] != 0 } }.map { $0 + 1 } ?? by
            if end + 2 > right, !r.small {                                                           // too long for what's on its right (a 칭호, the W): a size smaller, its medal in with it
                let dx = r.w - textWidth(r.s, small: true)
                fb.runs[ti].small = true; fb.runs[ti].w -= dx
                for y in 1..<11 { for x in by..<min(96, x1 + 8) { let i = y * 96 + x; fb.px[i - dx] = fb.px[i]; fb.col[i - dx] = fb.col[i]; fb.px[i] = 0; fb.col[i] = 0 } }
            }
            for k in fb.runs.indices where fb.runs[k].y <= 2 { fb.runs[k].shade = 3 }             // on the band: full ink (a grey one fades into its colour)
        }
        tidy(&fb, g, lay, band: ti != nil)
        if let f = fi, let stage = lay.stage, let pic = picStore[fb.pics[f].key] {                // a focus page's thing: on its stage, as big as fits (up to 2 x, in crisp steps), on a pad
            let fit = min(2, Double(stage[2] - 8) / Double(pic.w), Double(stage[3] - 24) / Double(pic.h)), k = [2, 1.5, 1].first { $0 <= fit } ?? fit
            let cx = stage[0] + stage[2] / 2, cy = stage[1] + stage[3] / 2 - 4, h = Int(Double(pic.h) * k)
            fb.pics[f].x = cx; fb.pics[f].y = cy; fb.pics[f].scale = k
            fb.pic("deco|pad|\(g.rawValue)" + tone, cx, cy + h / 2 + 3, scale: min(1.1, max(0.6, Double(pic.w) * k / 56)), under: true, clip: stage) { ready(LCDDeco.pad(g)) }
            fb.pic("deco|glow|\(g.rawValue)" + tone, cx, cy, scale: min(1.2, max(0.7, Double(max(pic.w, pic.h)) * k / 56)), alpha: 0.8, under: true, clip: stage) { ready(LCDDeco.glow(LCDDeco.tones(g).band)) }
            return
        }
        guard let i = si, let stage = lay.stage else { return }
        let (run, b) = LCDDeco.fit(fb.sprites[i], stage)
        fb.sprites[i] = run
        let cx = Int((b[0] + b[2]) / 2), cy = Int((b[1] + b[3]) / 2), size = max(b[2] - b[0], b[3] - b[1]), clip = stage
        if g == .raid || g == .mega {                                                                // the boss: lit in its type's colour, its weather; a Mega's rainbow
            let dex = raidMega ? (megaLobby?.bosses[safe: raidMegaBoss]?.dex ?? run.art) : (raidLobby?.boss.dex ?? run.art)
            let type = monTypes[min(dex, 721)].first ?? "normal", c = fxTones[type]?[2] ?? rgb(200, 200, 220), k = min(1.3, max(0.8, size / 64))
            if g == .mega {                                                                          // a rainbow ring turning, the Mega symbol, rainbow streaks running in
                fb.pic("deco|aura" + tone, cx, cy, scale: 1.2 * k + 0.05 * sin(t * 2.4), angle: t * 40, under: true, clip: clip) { ready(LCDScenes.rainbowRing()) }
                fb.pic("deco|msym" + tone, cx, cy, scale: 2.4 * k, alpha: 0.85, angle: t * 16, under: true, clip: clip) { ready(MegaFX.symbolPic(6, 1)) }
                let cs = MegaFX.colours(6, 1)
                for n in 0..<10 {
                    let ph = (t * 0.6 + Double(n) / 10).truncatingRemainder(dividingBy: 1), ang = Double(n) * .pi / 5 + t * 0.3, r = (62 * (1 - ph) + 12) * k
                    fb.pic("mega streak 6.1.\(n % cs.count)" + tone, cx + Int(r * cos(ang)), cy + Int(r * sin(ang) * 0.8), alpha: min(1, ph * 4) * min(1, (1 - ph) * 3), angle: ang * 180 / .pi + 180, clip: clip) { MegaFX.streakPic(cs[n % cs.count]) }
                }
                return
            }
            fb.pic("deco|glow|\(type)" + tone, cx, cy, scale: 1.15 * k + 0.08 * sin(t * 2.4), alpha: 0.8 + 0.2 * sin(t * 2.4), under: true, clip: clip) { ready(LCDDeco.glow(c)) }
            let (vx, vy) = LCDScenes.weatherFall(type)
            for n in 0..<(type == "electric" ? 1 : 14) {                                          // its weather in the cave
                if type == "electric" { if Int(t * 3) % 4 == 0 { fb.pic("deco|wx|electric" + tone, clip[0] + 24 + Int(t * 7) % 40, clip[1] + 24, scale: 2, clip: clip) { ready(LCDScenes.weatherBit("electric")) } }; continue }
                let x = (Double(n * 37) + t * vx).truncatingRemainder(dividingBy: Double(clip[2])), y = (Double(n * 53) + t * vy).truncatingRemainder(dividingBy: Double(clip[3]))
                fb.pic("deco|wx|\(type)" + tone, clip[0] + Int(x < 0 ? x + Double(clip[2]) : x), clip[1] + Int(y < 0 ? y + Double(clip[3]) : y), clip: clip) { ready(LCDScenes.weatherBit(type)) }
            }
            return
        }
        fb.pic("deco|pad|\(g.rawValue)" + tone, cx, Int(b[3]) - 2, scale: min(1.2, max(0.5, (b[2] - b[0]) / 56)), under: true, clip: clip) { ready(LCDDeco.pad(g)) }
        fb.pic("deco|glow|\(g.rawValue)" + tone, cx, cy, scale: min(1.3, max(0.6, size / 60)), alpha: 0.7, under: true, clip: clip) { ready(LCDDeco.glow(LCDDeco.tones(g).band)) }
    }
    /// A message: its card fitted to its lines (one too wide for it a size smaller), edged in the colour of what it says, over its place faded.
    /// A Mega stone that came (sayStone): a reward's card across, the stone big on its left in a glow, the words right of it.
    func decorateNotice(_ fb: inout FB, _ tone: String) {
        let ready = { (p: Pic) -> Pic in lcdReady(p) }
        guard case .say(let lines, _, _) = screen, !fb.runs.isEmpty else { return }
        let stone = sayStone.flatMap { $0.lines == lines ? $0.stone : nil }, room = stone == nil ? 82 : 52
        for k in fb.runs.indices where fb.runs[k].w > room && !fb.runs[k].small {
            let w = textWidth(fb.runs[k].s, small: true); fb.runs[k].small = true; fb.runs[k].w = w; fb.runs[k].x = (96 - w) / 2
        }
        if stone != nil { for k in fb.runs.indices { fb.runs[k].x = 61 - fb.runs[k].w / 2 } }
        let x0 = fb.runs.map(\.x).min()!, x1 = fb.runs.map { $0.x + $0.w }.max()!, y0 = fb.runs.map(\.y).min()!, y1 = fb.runs.map { $0.y + $0.rows }.max()!
        let w = stone != nil ? 180 : min(188, max(112, 2 * (x1 - x0) + 24)) / 2 * 2, h = max(stone != nil ? 64 : 0, min(124, 2 * (y1 - y0) + 18)) / 2 * 2
        let k = stone != nil ? .reward : LCDScenes.kind(lines)
        fb.pic("deco|scene|notice" + tone, 96, 64, under: true) { ready(LCDScenes.scene(.notice)) }
        fb.pic("deco|veil" + tone, 96, 64, under: true) { ready(LCDScenes.veil()) }
        fb.pic("deco|card|\(k)|\(w)|\(h)" + tone, 96, y0 + y1, under: true) { ready(LCDScenes.noticeCard(k, w, h)) }
        guard let stone, let b = MegaRaid.bosses.first(where: { $0.stone == stone }) else { return }
        let type = (Forms.of(b.dex, b.form)?.types ?? monTypes[b.dex]).first ?? "normal", t = Date().timeIntervalSinceReferenceDate
        fb.pic("deco|glow|stone" + tone, 42, y0 + y1, scale: 0.95 + 0.05 * sin(t * 3), under: true) { ready(LCDDeco.glow(rgb(255, 214, 90))) }
        fb.pic("deco|stone|\(type)" + tone, 42, y0 + y1, under: true) { ready(LCDScenes.stonePic(type)) }
        if Int(t * 1.5) % 3 == 0 { fb.pic("deco|glint" + tone, 30, y0 + y1 - 14, scale: 0.5 + 0.4 * abs(sin(t * 6)), under: true) { ready(MegaFX.glintPic(rgb(255, 236, 160))) } }
    }
    /// The page's picked rows and lines kept to their panel (or strip), a picked row in the group's colour, its corners round.
    func tidy(_ fb: inout FB, _ g: PageGroup, _ lay: LCDDeco.Layout, band: Bool) {
        let hl = LCDDeco.highlight(g)
        func span(_ y: Int, _ x: Int) -> (Int, Int) {                                                // the dots a row may use there: inside its panel's edge
            if let s = lay.strip, 2 * y >= s[1] { return (s[0] / 2 + 1, (s[0] + s[2]) / 2 - 1) }
            let p = lay.panel
            return 2 * x + 4 >= p[0] ? (p[0] / 2 + 1, (p[0] + p[2]) / 2 - 1) : (1, p[0] / 2 - 1)
        }
        for f in fb.flips where !(f[0] <= 0 && f[1] <= 0 && f[0] + f[2] >= 96 && f[1] + f[3] >= 64) {
            let (lo, hi) = span(f[1], max(f[0], 0) + min(f[2], 96) / 2), x0 = max(f[0], lo), x1 = min(f[0] + f[2], hi)
            for y in max(0, f[1])..<min(64, f[1] + f[3]) { for x in max(0, f[0])..<min(96, f[0] + f[2]) where fb.px[y * 96 + x] == 3 {
                let i = y * 96 + x, corner = (x == x0 || x == x1 - 1) && (y == f[1] || y == f[1] + f[3] - 1)
                if x < x0 || x >= x1 || (corner && f[3] > 4) { fb.px[i] = 0 } else { fb.col[i] = hl }
            } }
        }
        for y in (band ? 12 : 0)..<63 {                                                              // a line across (a divider): inside too
            let lit = (0..<96).filter { fb.px[y * 96 + $0] != 0 }
            guard lit.count >= 48, let a = lit.first, let z = lit.last, a <= 1 || z >= 94 else { continue }
            let (lo, hi) = span(y, 48)
            for x in 0..<96 where x < lo || x >= hi { fb.px[y * 96 + x] = 0; fb.col[y * 96 + x] = 0 }
        }
    }
}

/// Self-test checks for this file (run by selftest()): every picture fits its stage, the pages' Pokémon clear of their words, band and panel,
/// a picked row inside its panel in its group's colour, a message's card round its lines.
@MainActor func decoChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let stages = [[6, 27, 90, 97], [6, 27, 58, 97], [6, 27, 90, 60]], arts = Array(1...spriteCount)
    let bad = arts.filter { a in stages.contains { st in
        let (r, b) = LCDDeco.fit(SpriteRun(art: a, shiny: false, back: false, x: 16, y: 18, bob: 1, tint: nil, tintShade: 0, floor: 64), st)
        return b[0] < Double(st[0]) - 0.5 || b[1] < Double(st[1]) - 0.5 || b[2] > Double(st[0] + st[2]) + 0.5 || b[3] > Double(st[1] + st[3]) + 0.5 || r.scale > 1.15 || r.scale < 0.5
    } }
    c.append((bad.isEmpty, "5.0 LCD: every picture (\(arts.count)) fits its stage, as big as it may be (a wide, a narrow and a short one)" + (bad.isEmpty ? "" : " — \(bad.prefix(8))")))
    let was = (lcdDeco, lcdStyle); lcdDeco = true; lcdStyle = 0
    defer { lcdDeco = was.0; lcdStyle = was.1 }
    Content.$testing.withValue(true) {
        var r = Seeded(s: 9), tall: [Mon] = [130, 321, 249, 384, 208, 95, 282, 666, 6, 149, 25].map { Mon.wild($0, level: 50, &r) }
        if let m = Forms.mega(6, holding: "리자몽나이트Y") { var y = Mon.wild(6, level: 50, &r); y.form = m.n; tall.append(y) }
        @MainActor func page(_ m: Mon, _ s: Screen) -> FB { var st = Walk(); st.companion = m; st.owned = [m.dex]; st.seen = [m.dex]; st.dex(); let w = Walker(state: st); w.persist = false; w.screen = s; return w.compose(Date()) }
        let over = tall.flatMap { m in [page(m, .box(-1, act: nil, confirm: false)), page(m, .dex(m.dex, filter: 0, detail: false))].flatMap(lcdOverlaps) }
        c.append((over.isEmpty, "5.0 LCD: a page's Pokémon (Gyarados, Wailord, Lugia, Rayquaza, Mega Charizard Y …) clear of its words, band and panel" + (over.isEmpty ? "" : " — \(over.prefix(6))")))
        let shop: FB = { var st = Walk(); st.watts = 5000; let w = Walker(state: st); w.persist = false; w.screen = .shop(bp: false, sel: 2, qty: nil); return w.compose(Date()) }()
        let lit = (0..<96 * 64).filter { i in shop.px[i] == 3 && shop.flips.contains { f in f[3] < 64 && i % 96 >= f[0] && i % 96 < f[0] + f[2] && i / 96 >= f[1] && i / 96 < f[1] + f[3] } }
        let inside = !lit.isEmpty && lit.allSatisfy { ($0 % 96) >= 2 && ($0 % 96) <= 93 && shop.col[$0] == LCDDeco.highlight(.shop) }
        c.append((inside && shop.palette == LCDDeco.palette(.shop), "5.0 LCD: a picked row inside its panel, in its group's colour; the words in its inks"))
        let say: FB = { let w = Walker(state: Walk()); w.persist = false; w.screen = .say(["10줄을 모두 깼다!", "2BP · 볼 5개!", "우편함에 이번 주 보상이 왔다"], next: .home, since: Date()); return w.compose(Date()) }()
        let card = say.pics.first { $0.key.hasPrefix("deco|card") }.flatMap { r in picStore[r.key].map { (r, $0) } }
        let round = card.map { r, p in say.runs.allSatisfy { 2 * $0.x >= r.x - p.w / 2 + 6 && 2 * ($0.x + $0.w) <= r.x + p.w / 2 - 6 && 2 * $0.y >= r.y - p.h / 2 && 2 * ($0.y + $0.rows) <= r.y + p.h / 2 } } ?? false
        c.append((round, "5.0 LCD: a message's card round all its lines (a long one a size smaller)"))
    }
    return c
}
