import Foundation
// The card as the walker draws it, on any Canvas: the shell's top down to the band (the title row, the LCD in its bezel), the band with the keys;
// the LCD's dots, sprites, pictures, text and a fight's HP boxes. The white page under the band: Core/Page.swift. The Mac's view: Mac/WalkerView.swift.

extension Walker {
    /// The card in `bounds` (lcdOnly: only the screen, most frames). shown = the frame on the LCD (nil: composed now); down = the key held in.
    func drawCard(_ c: any Canvas, _ bounds: CGRect, shown: FB?, down: Int?, lcdOnly: Bool) {
        if lcdOnly { drawLCD(c, shown); return }
        let t = shells[theme], k = K, W = bounds.width, luma = t.top.luma
        let light = luma > 0.6, dark = luma < 0.2                                                   // 프리미어볼 / 배틀 골드: dark ink; 하이퍼볼 / 럭셔리볼: the band and bezel need a lighter edge
        let body = Path.rounded(bounds.insetBy(dx: 0.25, dy: 0.25), Layout.r * k)
        c.save(); c.clip(body)
        c.fill(bounds, .white)
        c.fill(CGRect(x: 0, y: 0, width: W, height: Layout.seam * k), t.top)
        c.fill(CGRect(x: 0, y: (Layout.seam - Layout.band / 2) * k, width: W, height: Layout.band * k), dark && t.band.brightness < 0.3 ? Color(white: 0.34, alpha: 1) : t.band)
        c.restore()
        c.stroke(body, Color(white: 0, alpha: 0.12), width: 0.5)
        // the title row: what the LCD doesn't show; home's ⌄ folds the status sheet
        let tl = title(), fg = light ? Ink.ink : .white, fg2 = light ? Ink.sub : Color(white: 1, alpha: 0.82), cy = 12.5 * k
        c.say(tl.title, 12 * k, cy, font(11, .bold), fg, maxW: 120 * k)
        c.say(tl.meta, (207 - 3 - (chevron != nil ? 13 : 0)) * k, cy, font(9, .medium), fg2, 1, maxW: 110 * k)
        if let open = chevron {
            let cx = 200 * k, s3 = 3 * k, d: CGFloat = open ? -1 : 1
            c.stroke(.poly([CGPoint(x: cx - s3, y: cy - d * s3 / 2), CGPoint(x: cx, y: cy + d * s3 / 2), CGPoint(x: cx + s3, y: cy - d * s3 / 2)], closed: false), fg, width: 1.5 * k, round: true)
        }
        let bezel = CGRect(x: (9 * k).rounded(), y: (24 * k).rounded(), width: (198 * k).rounded(), height: (134 * k).rounded()), bp = Path.rounded(bezel, 7 * k)
        c.fill(bp, Ink.dark)                                                                       // the LCD's bezel
        if dark { c.stroke(bp, Color(white: 1, alpha: 0.22), width: max(1, k)) }
        drawLCD(c, shown)
        drawKeys(c, down)
    }
    /// ◀ ▶ ↩: white keys ringed dark; ● is the ball's own button — a dark ring, the white button, a faint inner ring.
    func drawKeys(_ c: any Canvas, _ down: Int?) {
        let k = K
        for (i, b) in buttons.enumerated() {
            let face = down == i ? Color(white: 0.86, alpha: 1) : .white
            let r = CGRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r)
            if i == 1 {
                c.fill(.oval(r), Ink.dark); c.fill(.oval(r.insetBy(dx: 3 * k, dy: 3 * k)), face)
                c.stroke(.oval(CGRect(x: b.c.x - 5.5 * k, y: b.c.y - 5.5 * k, width: 11 * k, height: 11 * k)), Ink.c(186, 190, 200), width: 1.2 * k)
                continue
            }
            let o = Path.oval(r.insetBy(dx: k, dy: k)); c.fill(o, face); c.stroke(o, Ink.dark, width: 2 * k)
            if i >= 3 {                                                                            // ↩ the back arrow; 메뉴 on home, 홈 elsewhere (dim where it can't go)
                let key = homeKey()
                c.glyph(i == 3 ? .back : key == true ? .menu : .home, b.c, 8.5 * k, Ink.ink, alpha: i == 4 && key == nil ? 0.3 : 1)
            } else { c.triangle(b.c.x + (i == 2 ? 0.6 : -0.6) * k, b.c.y, 4.2 * k, left: i == 0, Ink.ink) }
        }
    }
    /// The 96x64 screen: dots (colour or 4 greys), sprites, smooth text over them, a fight's HP boxes, a shadow from the bezel.
    func drawLCD(_ c: any Canvas, _ shown: FB?) {
        let l = lcds[lcdStyle]
        c.fill(lcdRect, Ink.dark)                                                                  // the rounded corners' bezel (an LCD-only redraw clears the whole square)
        c.save(); c.clip(.rounded(lcdRect, 4 * K))
        defer { c.restore() }
        c.fill(lcdRect, l.shades[0])
        let scale = c.scale, fb = shown ?? compose(Date()), gap = PX * scale >= 8 ? 1 / scale : 0   // a dot grid only once dots are big on screen
        var paths: [[UInt32: Path]] = [[:], [:]], cover = Path()                                     // under the sprites, over them; key: colour, or 0...3 for an LCD shade
        for y in 0..<64 { for x in 0..<96 {
            let i = y * 96 + x, key = l.color && fb.col[i] != 0 ? fb.col[i] : UInt32(fb.px[i]), o = fb.over[i] ? 1 : 0
            if o == 1 { cover.add(CGRect(x: lcdRect.minX + CGFloat(x) * PX, y: lcdRect.minY + CGFloat(y) * PX, width: PX, height: PX)) }   // the whole cell: no sprite through the dot grid
            if key != 0 || o == 1 { paths[o][key, default: Path()].add(CGRect(x: lcdRect.minX + CGFloat(x) * PX, y: lcdRect.minY + CGFloat(y) * PX, width: PX - gap, height: PX - gap)) }
        } }
        func dots(_ layer: [UInt32: Path]) {
            c.antialias(false)
            for (k, path) in layer { c.fill(path, k < 4 ? l.shades[Int(k)] : Color(red: CGFloat(k >> 16 & 255) / 255, green: CGFloat(k >> 8 & 255) / 255, blue: CGFloat(k & 255) / 255, alpha: 1)) }
            c.antialias(true)
        }
        dots(paths[0])
        let s = K, snap = { (v: CGFloat) in (v * scale).rounded() / scale }                            // 1 pt per sprite pixel at 보통, on whole device pixels
        func pictures(behind: Bool) {                                                                  // pictures at sprite resolution: a backdrop under the sprites, a ball or an effect over them
            for r in fb.pics where r.behind == behind {
                guard let img = picImage(r, l) else { continue }
                c.save()
                if r.clip.count == 4 { c.clip(.rect(CGRect(x: lcdRect.minX + CGFloat(r.clip[0]) * s, y: lcdRect.minY + CGFloat(r.clip[1]) * s, width: CGFloat(r.clip[2]) * s, height: CGFloat(r.clip[3]) * s))) }
                let o = CGPoint(x: lcdRect.minX + CGFloat(r.x) * s, y: lcdRect.minY + CGFloat(r.y) * s), w = CGFloat(img.pic.w) * s * r.scale, h = CGFloat(img.pic.h) * s * r.scale
                if r.angle != 0 { c.rotate(r.angle, about: o) }
                let box = r.scale == 1 && r.angle == 0 ? CGRect(x: snap(o.x - w / 2), y: snap(o.y - h / 2), width: w, height: h) : CGRect(x: o.x - w / 2, y: o.y - h / 2, width: w, height: h)
                c.image(img, box, alpha: r.alpha)
                c.restore()
            }
        }
        pictures(behind: true)
        for r in fb.sprites {                                                                         // the sprites: smooth-sized pixels, not LCD dots
            c.save()
            c.clip(.rect(CGRect(x: lcdRect.minX, y: lcdRect.minY, width: lcdRect.width, height: CGFloat(min(64, r.floor)) * PX)))
            let feet = CGPoint(x: lcdRect.minX + CGFloat(r.x + 16) * PX, y: lcdRect.minY + CGFloat(r.y + 32) * PX), k = s * r.scale   // its 80x80 frame (40x40 dots) stands on the run's feet (bottom-centre)
            let a = playing(r), (ox, oy, w, h) = a.map { (CGFloat($0.x), CGFloat($0.y), CGFloat($0.w), CGFloat($0.h)) } ?? (0, 0, 80, 80)   // an animation frame: its box in the 80x80 frame
            let box = r.scale == 1 ? CGRect(x: snap(feet.x + (ox - 40) * s), y: snap(feet.y + (oy - 80) * s - CGFloat(r.bob) * s), width: w * s, height: h * s)
                                   : CGRect(x: feet.x + (ox - 40) * k, y: feet.y + (oy - 80) * k - CGFloat(r.bob) * s, width: w * k, height: h * k)
            c.image(spriteImage(r, l), box, alpha: r.alpha)
            c.restore()
        }
        pictures(behind: false)
        if gap > 0 { c.antialias(false); c.fill(cover, l.shades[0]); c.antialias(true) }
        dots(paths[1])
        for r in fb.runs {                                                                             // smooth text over the dots; flipped where it sits in an inverted box
            let f = lcdFont(r.small), m = fonts.metrics(f), cx = r.x + r.w / 2, cy = r.y + r.rows / 2
            let flipped = fb.flips.contains { cx >= $0[0] && cx < $0[0] + $0[2] && cy >= $0[1] && cy < $0[1] + $0[3] }
            let shade = Int(flipped ? 3 - r.shade : r.shade), ink = l.shades[max(0, min(3, shade))]
            let box = CGRect(x: lcdRect.minX + CGFloat(r.x) * PX, y: lcdRect.minY + CGFloat(r.y) * PX, width: CGFloat(r.w) * PX, height: CGFloat(r.rows) * PX)
            let y = box.midY + m.capHeight / 2 - m.ascender                                            // caps centred on the row, one baseline for Hangul and digits
            c.text(r.s, CGPoint(x: box.minX, y: y), f, ink)
        }
        if let m = hud { drawHUD(c, m) }
        c.gradient(CGRect(x: lcdRect.minX, y: lcdRect.minY, width: lcdRect.width, height: 2 * PX), from: Color(white: 0, alpha: 0.18), to: .clear, angle: 90)
    }
    /// HGSS's HP boxes over the LCD's empty corners: theirs top-left (caught mark, name, Lv, types, HP), ours bottom-right (name, Lv, HP and its numbers).
    /// They fade while a move or a ball flies under them.
    func drawHUD(_ c: any Canvas, _ m: SideModel) {
        let k = K, o = lcdRect.origin
        var fade: CGFloat = 1, foeUp = true
        if case .beats = screen, let s = beatState(Date()) {
            switch s.beat { case .use, .thrown: fade = 0.4; default: break }
            if isIntro(s.beat, s.names), s.u < 2.2 { foeUp = false }                               // the tower's trainer is still out front: no Pokémon to show yet
        }
        c.beginLayer(alpha: fade)
        defer { c.endLayer() }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            let r = CGRect(x: o.x + x * k, y: o.y + y * k, width: w * k, height: h * k), p = Path.rounded(r, 7 * k)
            c.fill(p, Color(white: 1, alpha: 0.92)); c.stroke(p, Ink.ink.withAlphaComponent(0.11), width: 0.5 * k); return r
        }
        func status(_ st: String, _ x: CGFloat, _ cy: CGFloat) -> CGFloat {
            let f = font(7, .bold), w = width(st, f) + 7 * k; c.pill(CGRect(x: x, y: cy - 5 * k, width: w, height: 10 * k), Ink.faint); c.say(st, x + w / 2, cy, f, .white, 0.5); return w
        }
        // theirs: [caught] name · Lv on top; its types (and a status) then the HP bar below
        if foeUp {
            let f = box(4, 4, 110, 30), fr = m.foe.max > 0 ? CGFloat(m.foe.hp) / CGFloat(m.foe.max) : 0
            var x = f.minX + 7 * k
            if m.foe.owned { c.miniBall(CGPoint(x: f.minX + 9.5 * k, y: f.minY + 10 * k), 4.2 * k); x = f.minX + 17 * k }
            let lv = "Lv\(m.foe.level)", lvf = font(8, .semibold)
            let nw = c.say(m.foe.name, x, f.minY + 10.5 * k, font(10, .bold), Ink.ink, maxW: f.maxX - 7 * k - x - width(lv, lvf) - 3 * k)
            c.say(lv, x + nw + 3 * k, f.minY + 11 * k, lvf, Ink.sub)
            var bx = f.minX + 6 * k
            for t in m.foe.types { bx += c.typePill(t, bx, f.minY + 23 * k, h: 9 * k, size: 6.5) + 2 * k }
            if let st = m.foe.status { bx += status(st, bx, f.minY + 23 * k) + 2 * k }
            c.bar(bx + k, f.maxX - 7 * k, f.minY + 23 * k, fr, Ink.hp(fr), h: 4 * k)
        }
        let me = box(98, 86, 90, 38), mr = m.mine.max > 0 ? CGFloat(m.mine.hp) / CGFloat(m.mine.max) : 0
        let lw = c.say("Lv\(m.mine.level)", me.maxX - 7 * k, me.minY + 10 * k, font(8, .semibold), Ink.sub, 1)
        c.say(m.mine.name, me.minX + 7 * k, me.minY + 9.5 * k, font(10, .bold), Ink.ink, maxW: me.width - 17 * k - lw)
        c.bar(me.minX + 7 * k, me.maxX - 7 * k, me.minY + 19.5 * k, mr, Ink.hp(mr), h: 5 * k)
        if let st = m.mine.status { _ = status(st, me.minX + 7 * k, me.minY + 29.5 * k) }
        c.say("\(m.mine.hp) / \(m.mine.max)", me.maxX - 7 * k, me.minY + 29.5 * k, font(10, .semibold), Ink.ink, 1)
    }
}
