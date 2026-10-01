import Foundation
// The pane's pages: the card's white bottom under the band — battle, 도감 (grid / entry), 상자 (grid / one Pokémon), 상점, 메뉴, 상태 (their models: Core/Pane.swift),
// drawn on any Canvas; the look they share with the card's HP boxes. The Mac's view of them: Mac/SideView.swift.

// MARK: - the look (card points x K)
enum Ink {
    static func c(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> Color { Color(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a) }
    static let red = c(214, 46, 42), redTint = c(252, 228, 226), onRed = c(250, 212, 208), dark = c(34, 37, 45)
    static let tile = c(242, 243, 246), board = c(246, 247, 249), line = c(230, 232, 237), ink = c(28, 32, 42), sub = c(112, 118, 130), faint = c(160, 165, 176)
    static let blue = c(58, 132, 236), green = c(52, 178, 88), yellow = c(240, 176, 32), pink = c(226, 80, 120), gold = c(222, 150, 20)
    static func tint(_ col: Color, _ k: CGFloat) -> Color { var t = col; t.tint = k; return t }   // k of it over white
    static func hp(_ f: CGFloat) -> Color { f > 0.5 ? green : f > 0.2 ? yellow : c(230, 70, 60) }
}
let typeColor: [String: Color] = (["normal": (168, 167, 122), "fire": (238, 129, 48), "water": (99, 144, 240), "grass": (122, 199, 76), "electric": (247, 208, 44),
    "ice": (150, 217, 214), "fighting": (194, 46, 40), "poison": (163, 62, 161), "ground": (226, 191, 101), "flying": (169, 143, 243), "psychic": (249, 85, 135),
    "bug": (166, 185, 26), "rock": (182, 161, 54), "ghost": (115, 87, 151), "dragon": (111, 53, 252), "dark": (112, 87, 70), "steel": (183, 183, 206)] as [String: (Int, Int, Int)])
    .mapValues { Ink.c($0.0, $0.1, $0.2) }
@MainActor func font(_ size: CGFloat, _ w: FontSpec.Weight = .regular) -> FontSpec { FontSpec(size: size * K, weight: w) }
@MainActor func width(_ s: String, _ f: FontSpec) -> CGFloat { fonts.width(s, f) }
extension Canvas {
    /// Text centred on the row `cy` (by its caps, one baseline for Hangul and digits); align 0 = starts at x, 0.5 = centred on x, 1 = ends at x.
    @discardableResult func say(_ s: String, _ x: CGFloat, _ cy: CGFloat, _ f: FontSpec, _ c: Color, _ align: CGFloat = 0, maxW: CGFloat? = nil) -> CGFloat {
        var s = s
        if let maxW { while s.count > 1, width(s, f) > maxW { s = String(s.dropLast(2)) + "…" } }
        let w = width(s, f), m = fonts.metrics(f)
        text(s, CGPoint(x: x - w * align, y: cy - m.ascender + m.capHeight / 2), f, c)
        return w
    }
    func pill(_ r: CGRect, _ c: Color) { fill(.rounded(r, min(r.height, r.width) / 2), c) }
    /// The HGSS caught mark: a small Poké Ball of radius r.
    func miniBall(_ c: CGPoint, _ r: CGFloat) {
        fill(.oval(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), Ink.dark)
        let ri = r * 0.8, inner = CGRect(x: c.x - ri, y: c.y - ri, width: 2 * ri, height: 2 * ri)
        save(); clip(.oval(inner))
        fill(CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: ri), Ink.red)
        fill(CGRect(x: inner.minX, y: c.y, width: inner.width, height: ri), .white)
        fill(CGRect(x: inner.minX, y: c.y - r * 0.1, width: inner.width, height: r * 0.2), Ink.dark)
        restore()
        fill(.oval(CGRect(x: c.x - r * 0.42, y: c.y - r * 0.42, width: r * 0.84, height: r * 0.84)), Ink.dark)
        fill(.oval(CGRect(x: c.x - r * 0.26, y: c.y - r * 0.26, width: r * 0.52, height: r * 0.52)), .white)
    }
    /// ◀ / ▶ as a small filled triangle centred on (cx, cy).
    func triangle(_ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, left: Bool, _ c: Color) {
        let d: CGFloat = left ? 1 : -1
        fill(.poly([CGPoint(x: cx + d * s * 0.55, y: cy - s), CGPoint(x: cx - d * s * 0.75, y: cy), CGPoint(x: cx + d * s * 0.55, y: cy + s)]), c)
    }
    /// A type badge ending at `right` (or starting at `left`); returns its width.
    @discardableResult func typePill(_ t: String, _ x: CGFloat, _ cy: CGFloat, h: CGFloat, size: CGFloat, right: Bool = false, grey: Bool = false) -> CGFloat {
        let s = typeKo[t] ?? t, f = font(size, .bold), w = width(s, f) + 9 * K, x0 = right ? x - w : x
        pill(CGRect(x: x0, y: cy - h / 2, width: w, height: h), grey ? Ink.c(196, 198, 204) : typeColor[t] ?? .gray)
        say(s, x0 + w / 2, cy, f, .white, 0.5); return w
    }
    /// A 4-10 pt bar on a track.
    func bar(_ x0: CGFloat, _ x1: CGFloat, _ cy: CGFloat, _ frac: CGFloat, _ c: Color, h: CGFloat, track: Color = Ink.line) {
        pill(CGRect(x: x0, y: cy - h / 2, width: x1 - x0, height: h), track)
        if frac > 0 { pill(CGRect(x: x0, y: cy - h / 2, width: max(h, (x1 - x0) * min(1, frac)), height: h), c) }
    }
}

// MARK: - the page
/// The page as drawn from the walker's pane (Walker.pane, refreshPane redraws it on a change), in its own coordinates (card y 189 = 0);
/// `hits` = what a click there picks, from the last draw.
@MainActor final class Page {
    weak var walker: Walker?
    var content: PaneContent { walker?.pane ?? PaneContent() }
    var shopTop = 0, shopTitle = ""                                        // the list's first visible row: moves only when the pick leaves the window
    var itemTop = 0                                                        // the same for the battle's item list
    var hits: [(CGRect, Int)] = []                                         // clickable: battle index, 2000+ shop, 3000+ menu, 4000+ grid / box controls, 5000+ other pages, 10000+ grid cells
    private var c: (any Canvas)! = nil                                     // while drawing

    /// Card coordinates → the page's (it starts at the pane's top, card y 189).
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * K, y: (y - Layout.pane) * K, width: w * K, height: h * K) }
    func y(_ v: CGFloat) -> CGFloat { (v - Layout.pane) * K }
    func x(_ v: CGFloat) -> CGFloat { v * K }

    func draw(on canvas: any Canvas) {
        hits = []; c = canvas; defer { c = nil }
        let p = content
        if let d = p.dex { drawDex(d) } else if let g = p.grid { drawGrid(g) } else if let m = p.mon { drawMon(m) } else if let s = p.shop { drawShop(s) }
        else if let m = p.menu { drawMenu(m) } else if let m = p.battle { drawBattle(m) } else if let i = p.items { drawItems(i) } else if let r = p.radar { drawRadar(r) }
        else if let k = p.card { tabs(["트레이너 카드", "최근 7일", "알"], k.page, 198, code: 5200) } else if let l = p.learn { drawLearn(l) }
        else if let t = p.tower { drawTower(t) } else if let s = p.status { drawStatus(s) }
    }
    let X0: CGFloat = 9, X1: CGFloat = 207                                                         // the content column (card points): the bezel's edges
    /// A hairline across the column at y (page coordinates).
    func rule(_ yy: CGFloat, _ x0: CGFloat = 2, _ inset: CGFloat = 4) { c.fill(CGRect(x: x(X0 + x0), y: yy, width: x(X1 - X0 - inset), height: max(0.5, 0.5 * K)), Ink.line) }
    /// A rounded tile, ringed red when it's the pick (1.5 pt).
    func tile(_ rc: CGRect, _ radius: CGFloat, on: Bool, _ fill: Color? = nil) { let p = Path.rounded(rc, radius * K); c.fill(p, fill ?? (on ? Ink.redTint : Ink.tile)); if on { c.stroke(p, Ink.red, width: 1.5 * K) } }

    // MARK: battle: the message, then the choices (HP lives on the LCD)
    func drawBattle(_ m: SideModel) {
        let top: CGFloat = 198, w = X1 - X0
        func button(_ rc: CGRect, _ label: String, _ fill: Color, _ fg: Color, _ idx: Int, _ size: CGFloat = 11) {
            c.fill(.rounded(rc, 10 * K), fill); c.say(label, rc.midX, rc.midY, font(size, .bold), fg, 0.5); hits.append((rc, idx))
        }
        switch m.mode {
        case .none:                                                                               // a turn playing: the message, up to three lines
            var lines: [String] = [], cur = "", f = font(11, .medium)
            for word in m.message.split(separator: " ") {                                          // by words, as HGSS's box does ("!" never alone on a line)
                let t = cur.isEmpty ? String(word) : cur + " " + word
                if width(t, f) > x(w - 4), !cur.isEmpty { lines.append(cur); cur = String(word) } else { cur = t }
            }
            lines.append(cur); if lines.count > 3 { f = font(10, .medium) }
            for (j, l) in lines.prefix(4).enumerated() { c.say(l.trimmingCharacters(in: .whitespaces), x(X0 + 2), y(top + 8 + CGFloat(j) * 17), f, Ink.ink) }
            return
        case .moves: break                                                                        // the four buttons need the room (HGSS's move screen has no prompt either)
        default: c.say(m.message, x(X0 + 2), y(top + 8), font(11, .medium), Ink.ink, maxW: x(w - 4))
        }
        let y0 = top + 23
        switch m.mode {
        case .menu(let opts, let sel):                                                            // big 공격, three below; the pick is red
            let tints: [String: Color] = ["볼": Ink.yellow, "도구": Ink.green, "교체": Ink.blue, "도망": Ink.blue, "기권": Ink.faint]
            button(r(X0, y0, w, 38), opts[0], sel == 0 ? Ink.red : Ink.redTint, sel == 0 ? .white : Ink.red, 0, 13)
            let cw = (w - 10) / 3
            for i in 1..<opts.count {
                let rc = r(X0 + CGFloat(i - 1) * (cw + 5), y0 + 44, cw, 36)
                button(rc, opts[i], sel == i ? Ink.red : Ink.tint(tints[opts[i]] ?? Ink.faint, 0.2), sel == i ? .white : Ink.ink, i)
            }
        case .moves(let ms, let sel):                                                             // 2 x 2 in their type's tint, the pick ringed: name; type, 위력; PP
            let cw = (w - 5) / 2
            for (i, mv) in ms.enumerated() {
                let rc = r(X0 + CGFloat(i % 2) * (cw + 5), top + 3 + CGFloat(i / 2) * 53, cw, 48), dead = mv.effect == 0 || mv.pp == 0, col = typeColor[mv.type] ?? .gray
                let p = Path.rounded(rc, 10 * K); c.fill(p, dead ? Ink.tile : Ink.tint(col, 0.2))
                if i == sel { c.stroke(p, Ink.red, width: 2 * K) }
                c.say(mv.name, rc.minX + x(9), rc.minY + x(12), font(11, .bold), dead ? Ink.faint : Ink.ink, maxW: rc.width - x(14))
                c.typePill(mv.type, rc.minX + x(8), rc.minY + x(27), h: x(11), size: 7.5, grey: dead)
                c.say(mv.status ? "변화" : "위력 " + (mv.power > 1 ? "\(mv.power)" : "—"), rc.maxX - x(8), rc.minY + x(27.5), font(8, .semibold), dead ? Ink.faint : Ink.sub, 1)   // a power that varies: —
                let e = mv.effect == 0 ? "효과 없음" : (mv.effect > 1 ? "▲ " : mv.effect < 1 ? "▼ " : "") + "PP \(mv.pp)/\(mv.maxPP)"
                c.say(e, rc.maxX - x(8), rc.minY + x(39.5), font(8, .semibold), mv.effect > 1 ? Ink.red : Ink.sub, 1)
                hits.append((rc, i))
            }
        case .party(let ps, let sel):                                                             // three rows: name, HP
            for (i, p) in ps.enumerated() {
                let rc = r(X0, y0 + CGFloat(i) * 27.5, w, 25), f = p.max > 0 ? CGFloat(p.hp) / CGFloat(p.max) : 0
                tile(rc, 9, on: i == sel)
                let nx = c.say((p.out ? "▶ " : "") + p.name, rc.minX + x(9), rc.minY + x(9.5), font(10, .bold), p.hp > 0 ? Ink.ink : Ink.faint)
                let lx = rc.minX + x(9) + nx + x(4) + c.say("Lv\(p.level)", rc.minX + x(13) + nx, rc.minY + x(10), font(8, .semibold), Ink.sub)
                if let st = p.status { let sw = width(st, font(7.5, .bold)) + x(8); c.pill(CGRect(x: lx + x(4), y: rc.minY + x(4.5), width: sw, height: x(11)), Ink.faint); c.say(st, lx + x(4) + sw / 2, rc.minY + x(10), font(7.5, .bold), .white, 0.5) }
                c.say("\(p.hp)/\(p.max)", rc.maxX - x(9), rc.minY + x(9.5), font(9, .semibold), Ink.ink, 1)
                c.bar(rc.minX + x(9), rc.maxX - x(9), rc.minY + x(19), f, Ink.hp(f), h: x(3))
                hits.append((rc, i))
            }
        case .items(let names, let sel):                                                          // three rows, the pick kept in view
            if sel < itemTop { itemTop = sel } else if sel >= itemTop + 3 { itemTop = sel - 2 }
            itemTop = max(0, min(itemTop, names.count - 3))
            for (i, n) in names.enumerated() where i >= itemTop && i < itemTop + 3 {
                let rc = r(X0, y0 + CGFloat(i - itemTop) * 27.5, w, 25)
                tile(rc, 9, on: i == sel)
                let parts = n.components(separatedBy: " ×")
                c.say(parts[0], rc.minX + x(9), rc.midY, font(10, .bold), Ink.ink); if parts.count > 1 { c.say("×" + parts[1], rc.maxX - x(9), rc.midY, font(9, .semibold), Ink.sub, 1) }
                hits.append((rc, i))
            }
            if names.count > 3 { c.say("\(sel + 1) / \(names.count)", x(X1 - 2), y(top + 8), font(8, .semibold), Ink.sub, 1) }
        case .ask(let yes):                                                                       // 아니오 / 예, the pick red
            let cw = (w - 5) / 2
            for (i, t) in ["아니오", "예"].enumerated() { let on = (i == 1) == yes; button(r(X0 + CGFloat(i) * (cw + 5), y0, cw, 40), t, on ? Ink.red : Ink.tile, on ? .white : Ink.ink, i, 13) }
        case .none: break
        }
    }

    // MARK: 도감 / 상자 grid
    func drawGrid(_ g: GridModel) {
        var top: CGFloat = 198
        let scale = c.scale
        if let n = g.items {                                                                        // 포켓몬: the companion and the walker's 3 over the box, then the items
            let cw = (X1 - X0 - 4 * 4) / 5, snap = { (v: CGFloat) in (v * scale).rounded() / scale }
            for i in 0..<5 {
                let rc = r(X0 + CGFloat(i) * (cw + 4), top, cw, 42), on = i == g.partySel
                tile(rc, 10, on: on)
                if i == 4 { pixelArt(gem, gemPal, CGPoint(x: rc.midX, y: rc.minY + x(15)), 3 * K); c.say("도구 \(n)", rc.midX, rc.maxY - x(7), font(8, .bold), Ink.sub, 0.5); hits.append((rc, 4510)) }
                else if let e = g.party[safe: i] {
                    let lift = on && g.bob ? K : 0
                    c.image(iconImage(e.dex), CGRect(x: snap(rc.midX - 16 * K), y: snap(rc.minY - x(3) - lift), width: 32 * K, height: 32 * K), alpha: 1)
                    c.say(i == 0 ? "함께" : "Lv.\(e.level)", rc.midX, rc.maxY - x(7), font(8, .bold), i == 0 ? Ink.red : Ink.sub, 0.5)
                    if e.shiny { c.say("★", rc.maxX - x(5), rc.minY + x(6), font(7, .bold), Ink.gold, 1) }
                    hits.append((rc, 4500 + i))
                } else { c.say("비어 있음", rc.midX, rc.midY, font(7.5, .medium), Ink.faint, 0.5) }   // the walker holds 3
            }
            top += 50
        }
        tabs(g.tabs, g.tab, top)
        let board = r(X0, top + 28, X1 - X0, 5 * 33)
        c.fill(.rounded(board, 11 * K), Ink.board)
        if g.cells.isEmpty { c.say(g.empty, board.midX, board.midY, font(10, .medium), Ink.sub, 0.5) }
        let side = 32 * K, snap = { (v: CGFloat) in (v * scale).rounded() / scale }
        for (k, e) in g.cells.enumerated() {
            let cell = r(X0 + CGFloat(k % GridModel.columns) * 33, top + 28 + CGFloat(k / GridModel.columns) * 33, 33, 33)
            if k == g.sel { let p = Path.rounded(cell.insetBy(dx: 1.5 * K, dy: 1.5 * K), 8 * K); c.fill(p, Ink.redTint); c.stroke(p, Ink.red, width: 1.5 * K) }
            if e.look == 0 { c.say(String(format: "%03d", e.dex), cell.midX, cell.midY, font(8, .medium), Ink.faint, 0.5) }
            else {
                let lift = k == g.sel && g.bob ? K : 0                                                    // the pick hops a pixel, twice a second
                c.image(iconImage(e.dex, shadow: e.look == 1), CGRect(x: snap(cell.midX - side / 2), y: snap(cell.midY - side / 2 - lift - 0.5 * K), width: side, height: side), alpha: 1)
            }
            if e.shiny { c.say("★", cell.maxX - x(4), cell.minY + x(6), font(7, .bold), Ink.gold, 1) }
            if e.v3 {                                                                                   // 3V and up: the amber diamond, as on the LCD
                let cx = cell.minX + x(6), cy = cell.maxY - x(6), rr = 2.4 * K
                let d = Path.poly([CGPoint(x: cx, y: cy - rr), CGPoint(x: cx + rr, y: cy), CGPoint(x: cx, y: cy + rr), CGPoint(x: cx - rr, y: cy)])
                c.fill(d, Ink.c(245, 178, 40)); c.stroke(d, Ink.c(160, 100, 10), width: 0.5 * K)
            }
            hits.append((cell, 10000 + g.first + k))
        }
        pager("\(g.page) / \(g.pages)", top + 198, prev: g.pages > 1, next: g.pages > 1)   // the last page's ▶ goes round to #1
    }
    /// A pill track of tabs, the picked one solid red.
    func tabs(_ labels: [String], _ sel: Int, _ top: CGFloat, code: Int = 4100) {
        let track = r(X0, top, X1 - X0, 22), sw = track.width / CGFloat(labels.count)
        c.pill(track, Ink.tile)
        for (i, s) in labels.enumerated() {
            let cell = CGRect(x: track.minX + CGFloat(i) * sw, y: track.minY, width: sw, height: track.height)
            if i == sel { c.pill(cell.insetBy(dx: 2 * K, dy: 2 * K), Ink.red) }
            c.say(s, cell.midX, cell.midY, font(10, i == sel ? .bold : .medium), i == sel ? .white : Ink.sub, 0.5)
            hits.append((cell, code + i))
        }
    }
    /// ◀ n / m ▶, centred (codes: the grids' by default).
    func pager(_ label: String, _ top: CGFloat, prev: Bool, next: Bool, codes: (Int, Int) = (4200, 4201)) {
        let f = font(10, .semibold), cy = y(top + 9), tw = width(label, f)
        c.say(label, x(Layout.w / 2), cy, f, Ink.ink, 0.5)
        for (dx, left, on, code) in [(-tw / 2 - x(16), true, prev, codes.0), (tw / 2 + x(16), false, next, codes.1)] {
            let o = CGRect(x: x(Layout.w / 2) + dx - x(9), y: cy - x(9), width: x(18), height: x(18))
            c.fill(.oval(o), Ink.tile); c.triangle(o.midX + (left ? -0.5 : 0.5) * K, o.midY, 3 * K, left: left, on ? Ink.sub : Ink.line)
            if on { hits.append((o, code)) }
        }
    }

    // MARK: 도감 entry: base stats, where, evolutions
    func drawDex(_ d: DexModel) {
        var yy: CGFloat = 198
        guard d.status > 0 else { c.say("아직 만나지 못했다", x(Layout.w / 2), y(yy + 60), font(10, .medium), Ink.sub, 0.5); return }
        for (name, v) in zip(["HP", "공격", "방어", "특공", "특방", "스피드"], d.stats) {
            c.say(name, x(X0 + 2), y(yy + 8), font(9, .medium), Ink.sub)
            c.say("\(v)", x(X0 + 58), y(yy + 8), font(10, .semibold), Ink.ink, 1)
            c.bar(x(X0 + 66), x(X1 - 2), y(yy + 8), CGFloat(v) / 150, v >= 100 ? Ink.green : Ink.yellow, h: x(5), track: Ink.tile)
            yy += 16
        }
        yy += 4; rule(y(yy)); yy += 4
        for (label, vals, n) in [("만나는 곳", d.found.isEmpty ? ["알 수 없음"] : d.found, 3), ("진화", d.evos.isEmpty ? ["더 이상 진화하지 않는다"] : d.evos, 2)] {   // a line each
            c.say(label, x(X0 + 2), y(yy + 10), font(9, .medium), Ink.sub)
            for (j, v) in vals.prefix(n).enumerated() { c.say(v, x(X0 + 58), y(yy + 10 + CGFloat(j) * 14), font(10, .medium), Ink.ink, maxW: x(X1 - X0 - 60)) }
            yy += CGFloat(n) * 14 + 6
        }
    }

    // MARK: 상자: one Pokémon — nature, ability, IVs and EVs, and 함께 / 놓아주기
    func drawMon(_ m: MonModel) {
        var yy = monBody(m, 198) + 4
        rule(y(yy - 2))                                                                            // 진화: how it evolves, a line a target
        c.say("진화", x(X0 + 2), y(yy + 6), font(9, .medium), Ink.sub)
        for (j, l) in m.evos.prefix(2).enumerated() { c.say(l, x(X0 + 34), y(yy + 6 + CGFloat(j) * 13), font(9, j == 0 ? .medium : .regular), l.hasPrefix("→") ? Ink.ink : Ink.sub, maxW: x(X1 - X0 - 36)) }
        yy += 32
        if m.place == 0 {                                                                          // the companion: what evolves it now, if anything; else nothing to do
            let rc = r(X0, yy, X1 - X0, 30); c.fill(.rounded(rc, 10 * K), m.evoAction == nil ? Ink.tile : Ink.red)
            c.say(m.evoAction ?? "함께 걷는 중", rc.midX, rc.midY, font(11, .bold), m.evoAction == nil ? Ink.sub : .white, 0.5); if m.evoAction != nil { hits.append((rc, 4406)) }
            return
        }
        // 함께 걷기 / 상자로 보내기 (the walker's) or 워커로 / 놓아주기 (the box's; 놓아줄까? → 아니오 / 예)
        let opts: [(String, Int)] = m.confirm ? [("아니오", 4402), ("예 · 놓아주기", 4403)]
            : m.place == 1 ? [("함께 걷기", 4400), ("상자로 보내기", 4404)] : [("함께 걷기", 4400)] + (m.fetch ? [("워커로", 4407)] : []) + [("놓아주기", 4401)]
        let cw = (X1 - X0 - 5 * CGFloat(opts.count - 1)) / CGFloat(opts.count)
        for (i, (t, code)) in opts.enumerated() {
            let rc = r(X0 + CGFloat(i) * (cw + 5), yy, cw, 30), strong = m.sel == i                   // red = what ● does now (the LCD's pick); none while nothing is picked
            c.fill(.rounded(rc, 10 * K), strong ? Ink.red : Ink.tile); c.say(t, rc.midX, rc.midY, font(11, .bold), strong ? .white : Ink.ink, 0.5); hits.append((rc, code))
        }
    }
    /// A Pokémon in full, from `top`: nature, ability, the IV / EV hexagons. Returns where the buttons go.
    func monBody(_ m: MonModel, _ top: CGFloat) -> CGFloat {
        var yy = top
        let statNames = ["HP", "공격", "방어", "특공", "특방", "스피드"]
        // 성격: name, the stats it moves, what that means
        c.say("성격", x(X0 + 2), y(yy + 7), font(9, .medium), Ink.sub)
        c.say(m.nature, x(X0 + 34), y(yy + 7), font(11, .bold), Ink.ink)
        var px = x(X1 - 2)
        let chips: [(String, Color)] = m.up.map { u in [(statNames[m.down!] + " ↓", Ink.blue), (statNames[u] + " ↑", Ink.red)] } ?? [("변화 없음", Ink.faint)]
        for (t, col) in chips { let f = font(8, .bold), w = width(t, f) + x(10); c.pill(CGRect(x: px - w, y: y(yy + 7) - x(6), width: w, height: x(12)), Ink.tint(col, 0.16)); c.say(t, px - w / 2, y(yy + 7), f, col, 0.5); px -= w + x(4) }
        c.say(m.natureNote, x(X0 + 34), y(yy + 20), font(9, .regular), Ink.sub, maxW: x(X1 - X0 - 36))
        yy += 30; rule(y(yy)); yy += 6
        // 특성: name, then its description (two lines at most)
        c.say("특성", x(X0 + 2), y(yy + 7), font(9, .medium), Ink.sub)
        c.say(m.ability, x(X0 + 34), y(yy + 7), font(11, .bold), Ink.ink)
        var lines: [String] = [], cur = "", f = font(9)
        for word in m.abilityNote.split(separator: " ") { let t = cur.isEmpty ? String(word) : cur + " " + word; if width(t, f) > x(X1 - X0 - 36), !cur.isEmpty { lines.append(cur); cur = String(word) } else { cur = t } }
        lines.append(cur)
        for (j, l) in lines.prefix(2).enumerated() { c.say(l, x(X0 + 34), y(yy + 20 + CGFloat(j) * 12), f, Ink.sub, maxW: x(X1 - X0 - 36)) }
        yy += 40; rule(y(yy)); yy += 4
        // IVs and EVs: two hexagons, the nature's stats in red / blue
        let half = (X1 - X0) / 2
        hexagon(title: "개체값", note: m.v > 0 ? "\(m.v)V" : "", values: m.ivs, max: 31, center: CGPoint(x: x(X0 + half / 2), y: y(yy + 57)), color: Ink.blue, up: m.up, down: m.down, gold: m.hyper, top: y(yy + 6))
        hexagon(title: "노력치", note: "합 \(m.evTotal)", values: m.evs, max: 252, center: CGPoint(x: x(X0 + half * 1.5), y: y(yy + 57)), color: Ink.c(236, 120, 40), up: m.up, down: m.down, gold: [], top: y(yy + 6))
        return yy + 104
    }
    /// A six-sided chart: HP on top, then 공격 · 방어 · 스피드 · 특방 · 특공 clockwise (the games' order); rings at thirds.
    func hexagon(title: String, note: String, values: [Int], max: CGFloat, center o: CGPoint, color: Color, up: Int?, down: Int?, gold: [Int], top: CGFloat) {
        let order = [0, 1, 2, 5, 4, 3], names = ["HP", "공격", "방어", "특공", "특방", "스피드"], R = 24 * K
        c.say(title, o.x - x(2), top, font(9, .bold), Ink.ink, 1); c.say(note, o.x + x(2), top, font(9, .semibold), note.hasSuffix("V") ? Ink.gold : Ink.sub)
        func pt(_ i: Int, _ f: CGFloat) -> CGPoint { let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 3; return CGPoint(x: o.x + cos(a) * R * f, y: o.y + sin(a) * R * f) }
        for ring in [1.0, 2.0 / 3, 1.0 / 3] as [CGFloat] {
            let p = Path.poly((0..<6).map { pt($0, ring) })
            if ring == 1 { c.fill(p, Ink.board) }; c.stroke(p, Ink.line, width: 0.7 * K)
        }
        for i in 0..<6 { c.stroke(.poly([o, pt(i, 1)], closed: false), Ink.line, width: 0.5 * K) }
        let poly = Path.poly(order.enumerated().map { i, s in pt(i, Swift.max(0.02, CGFloat(values[s]) / max)) })
        c.fill(poly, color.withAlphaComponent(0.32)); c.stroke(poly, color, width: 1.2 * K)
        for (i, s) in order.enumerated() {                                                     // name over value, outside the corner
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 3, lx = o.x + cos(a) * (R + x(15)), ly = o.y + sin(a) * (R + x(10)) + (i == 0 ? -x(3) : i == 3 ? x(3) : 0)
            let nc = s == up ? Ink.red : s == down ? Ink.blue : Ink.sub
            c.say(names[s], lx, ly - x(4.5), font(7.5, .medium), nc, 0.5)
            c.say("\(values[s])", lx, ly + x(4.5), font(8.5, .bold), gold.contains(s) ? Ink.gold : Ink.ink, 0.5)
        }
    }

    // MARK: 상점: rows, then how many
    func drawShop(_ s: ShopModel) {
        let top: CGFloat = 196, rows = 6, rh: CGFloat = 27
        if s.title != shopTitle { shopTitle = s.title; shopTop = max(0, s.sel - 2) }             // a stable window: a click never scrolls the row under the pointer away
        if s.sel < shopTop { shopTop = s.sel } else if s.sel >= shopTop + rows { shopTop = s.sel - rows + 1 }
        shopTop = max(0, min(shopTop, s.rows.count - rows)); let first = shopTop
        for (i, row) in s.rows.enumerated() where i >= first && i < first + rows {
            let yy = top + CGFloat(i - first) * rh, rc = r(X0, yy + 1, X1 - X0, rh - 2), on = i == s.sel
            if on { c.fill(.rounded(rc, 8 * K), Ink.redTint) } else if i > first, i != s.sel + 1 { rule(y(yy), 8, 16) }
            let fg = row.can ? Ink.ink : Ink.faint
            c.say(row.price, x(X1 - 8), y(yy + 9.5), font(10, .semibold), on ? Ink.red : fg, 1)
            c.say(row.name, x(X0 + 8), y(yy + 9.5), font(10, .bold), fg, maxW: x(X1 - X0 - 20) - width(row.price, font(10, .semibold)))
            let own = row.once ? "" : "보유 \(row.owned)"
            c.say(own, x(X1 - 8), y(yy + 20), font(8, .medium), Ink.sub, 1)
            c.say(row.note, x(X0 + 8), y(yy + 20), font(8, .medium), Ink.sub, maxW: x(X1 - X0 - 24) - width(own, font(8, .medium)))
            hits.append((rc, 2100 + i))
        }
        if s.rows.count > rows {                                                                   // where in the list: a thin bar on the right
            let track = r(X1 - 1.5, top + 4, 1.2, CGFloat(rows) * rh - 8)
            c.fill(track, Ink.line)
            let h = track.height * CGFloat(rows) / CGFloat(s.rows.count), yy = track.minY + (track.height - h) * CGFloat(first) / CGFloat(s.rows.count - rows)
            c.fill(CGRect(x: track.minX, y: yy, width: track.width, height: h), Ink.faint)
        }
        let by = top + CGFloat(rows) * rh + 8
        if let yes = s.ask {                                                                       // 정말? for a once-only row
            let cw = (X1 - X0 - 5) / 2
            for (i, (t, code)) in [("아니오", 2007), ("예 · \(s.total)", 2006)].enumerated() {
                let rc = r(X0 + CGFloat(i) * (cw + 5), by, cw, 30), on = (i == 1) == yes
                c.pill(rc, on ? Ink.red : Ink.tile); c.say(t, rc.midX, rc.midY, font(11, .bold), on ? .white : Ink.ink, 0.5); hits.append((rc, code))
            }
            return
        }
        guard let q = s.qty else {
            let rc = r(X0, by, X1 - X0, 30); c.pill(rc, Ink.tile); c.say(s.hint, rc.midX, rc.midY, font(9, .medium), Ink.sub, 0.5, maxW: rc.width - x(16)); return
        }
        let step = r(X0, by, 94, 30); c.pill(step, Ink.tile)
        for (cx, plus, on, code) in [(X0 + 16, false, q > 1, 2001), (X0 + 78, true, q < s.most, 2002)] {
            let ink = on ? Ink.ink : Ink.line, hr = CGRect(x: x(cx - 13), y: step.minY, width: x(26), height: step.height)
            c.fill(CGRect(x: x(cx - 4), y: step.midY - 0.8 * K, width: x(8), height: 1.6 * K), ink)
            if plus { c.fill(CGRect(x: x(cx) - 0.8 * K, y: step.midY - x(4), width: 1.6 * K, height: x(8)), ink) }
            if on { hits.append((hr, code)) }
        }
        c.say("\(q)개", step.midX, step.midY, font(11, .bold), Ink.ink, 0.5)
        let buy = r(X0 + 100, by, X1 - X0 - 100, 30); c.pill(buy, Ink.red); c.say("\(s.total) 사기", buy.midX, buy.midY, font(11, .bold), .white, 0.5, maxW: buy.width - x(12)); hits.append((buy, 2005))
    }

    // MARK: 메뉴: 2 x 5 tiles, the one on the LCD red
    func drawMenu(_ m: MenuModel) {
        let rh: CGFloat = 31, gap: CGFloat = 4, cw = (X1 - X0 - gap) / 2
        for (i, row) in m.rows.enumerated() {
            let rc = r(X0 + CGFloat(i % 2) * (cw + gap), 203 + CGFloat(i / 2) * (rh + gap), cw, rh), on = i == m.sel
            c.fill(.rounded(rc, 9 * K), on ? Ink.red : Ink.tile)
            c.say(row.name, rc.minX + x(9), rc.minY + x(10.5), font(10, .bold), on ? .white : Ink.ink, maxW: rc.width - x(14))
            c.say(row.note, rc.minX + x(9), rc.minY + x(22), font(8, .medium), on ? Ink.onRed : Ink.sub, maxW: rc.width - x(14))
            hits.append((rc, 3000 + i))
        }
    }

    // MARK: 상태: the companion, three numbers, the rest
    func drawStatus(_ s: StatusModel) {
        var yy: CGFloat = 200
        let scale = c.scale, snap = { (v: CGFloat) in (v * scale).rounded() / scale }
        c.image(iconImage(s.dex), CGRect(x: snap(x(X0 - 1)), y: snap(y(yy)), width: 32 * K, height: 32 * K), alpha: 1)
        let tx = X0 + 36
        var w = c.say(s.name, x(tx), y(yy + 8), font(11, .bold), Ink.ink)
        if !s.sex.isEmpty { w += x(2) + c.say(s.sex, x(tx) + w + x(2), y(yy + 8.5), font(10, .bold), s.female ? Ink.pink : Ink.blue) }
        w += x(5) + c.say(s.level, x(tx) + w + x(5), y(yy + 8.5), font(10, .semibold), Ink.sub)
        if s.v > 0 { let t = "\(s.v)V", f = font(7.5, .bold), vw = width(t, f) + x(8); c.pill(CGRect(x: x(tx) + w + x(5), y: y(yy + 8.5) - x(5.5), width: vw, height: x(11)), s.v >= 3 ? Ink.c(242, 168, 40) : Ink.faint); c.say(t, x(tx) + w + x(5) + vw / 2, y(yy + 8.5), f, .white, 0.5); w += x(5) + vw }
        c.say(s.nature, x(X1 - 2), y(yy + 8.5), font(9, .medium), Ink.sub, 1, maxW: x(X1 - 2) - (x(tx) + w + x(8)))   // never over the name / Lv / V
        c.bar(x(tx), x(X1 - 2), y(yy + 19.5), s.exp, Ink.blue, h: x(5))
        c.say("다음 레벨까지", x(tx), y(yy + 29), font(8, .medium), Ink.sub)
        c.say(s.toNext, x(X1 - 2), y(yy + 29), font(9, .semibold), Ink.ink, 1)
        yy += 40; rule(y(yy)); yy += 6
        let cw = (X1 - X0) / CGFloat(max(1, s.numbers.count))
        for (i, n) in s.numbers.enumerated() {
            let cx = X0 + CGFloat(i) * cw + cw / 2
            c.say(n.key, x(cx), y(yy + 7), font(8, .medium), Ink.sub, 0.5); c.say(n.value, x(cx), y(yy + 21), font(13, .bold), Ink.ink, 0.5, maxW: x(cw - 4))
            if i > 0 { c.fill(CGRect(x: x(X0 + CGFloat(i) * cw), y: y(yy + 2), width: max(0.5, 0.5 * K), height: x(26)), Ink.line) }
        }
        yy += 36; rule(y(yy)); yy += 6
        for row in s.rows {
            c.say(row.key, x(X0 + 2), y(yy + 10), font(9, .medium), Ink.sub)
            c.say(row.value, x(X1 - 2), y(yy + 10), font(10, .medium), Ink.ink, 1)
            yy += 20
        }
    }
}
extension Page {
    /// A few-colour pixel picture (" .:#" shades, `_` clear) at `px` points a pixel, centred on o.
    func pixelArt(_ a: [[UInt8?]], _ pal: [UInt32], _ o: CGPoint, _ px: CGFloat) {
        let w = CGFloat(a.first?.count ?? 0) * px, h = CGFloat(a.count) * px
        for (y, row) in a.enumerated() { for (x, v) in row.enumerated() { if let v {
            let col = pal[Int(v)]
            c.fill(CGRect(x: o.x - w / 2 + CGFloat(x) * px, y: o.y - h / 2 + CGFloat(y) * px, width: px, height: px), Color(red: CGFloat(col >> 16 & 255) / 255, green: CGFloat(col >> 8 & 255) / 255, blue: CGFloat(col & 255) / 255, alpha: 1))
        } } }
    }
    /// A picture at sprite resolution (1 pt a pixel x K), unsmoothed, centred on o.
    func pixelPic(_ img: Bitmap, _ o: CGPoint) {
        let w = CGFloat(img.pic.w) * K, h = CGFloat(img.pic.h) * K
        c.image(img, CGRect(x: o.x - w / 2, y: o.y - h / 2, width: w, height: h), alpha: 1)
    }
    /// 포켓몬 레이더: tap the patch that rustles, where it is on the LCD.
    func drawRadar(_ m: RadarModel) {
        c.say(m.chain > 0 ? "연쇄 \(m.chain) · 흔들리는 풀숲을 골라요" : "흔들리는 풀숲을 골라요", x(X0 + 2), y(206), font(11, .medium), Ink.ink)
        let cw = (X1 - X0 - 5) / 2
        for k in 0..<4 {
            let rc = r(X0 + CGFloat(k % 2) * (cw + 5), 220 + CGFloat(k / 2) * 51, cw, 46), live = m.live == k
            tile(rc, 10, on: k == m.cursor, live ? Ink.redTint : Ink.tile)
            pixelPic(grassImage(48, 36, m.season, live ? 1 : 0, rustle: live, flip: k == 1 || k == 2), CGPoint(x: rc.midX, y: rc.midY + x(2)))
            if live { pixelPic(paneImage("w.bang") { bangPic }, CGPoint(x: rc.midX + x(30), y: rc.midY - x(10))) }
            hits.append((rc, 5000 + k))
        }
    }
    /// A new move: it on top, then which to forget (or not learn it).
    func drawLearn(_ m: LearnModel) {
        func line(_ mv: LearnModel.Move, _ rc: CGRect, _ label: String? = nil) {                  // the numbers and type first: the name gets the rest
            var xr = rc.maxX - x(9)
            if !mv.type.isEmpty {
                xr -= c.say(mv.power > 0 ? "위력 \(mv.power) · PP \(mv.pp)" : "PP \(mv.pp)", xr, rc.midY, font(8, .semibold), Ink.sub, 1) + x(5)
                xr -= c.typePill(mv.type, xr, rc.midY, h: x(11), size: 7.5, right: true) + x(6)
            }
            c.say(label ?? mv.name, rc.minX + x(9), rc.midY, font(10, .bold), Ink.ink, maxW: xr - rc.minX - x(9))
        }
        let head = r(X0, 198, X1 - X0, 26); c.fill(.rounded(head, 9 * K), Ink.tint(typeColor[m.new.type] ?? Ink.faint, 0.18))
        line(m.new, head, "새 기술 · " + m.new.name)
        c.say(m.who + "의 기술을 하나 잊는다", x(X0 + 2), y(236), font(9, .medium), Ink.sub)
        for (i, mv) in (m.known + [LearnModel.Move(name: "배우지 않는다", type: "", power: 0, pp: 0)]).enumerated() {
            let rc = r(X0, 246 + CGFloat(i) * 21.5, X1 - X0, 19)
            tile(rc, 7, on: i == m.sel)
            line(mv, rc); hits.append((rc, 5300 + i))
        }
    }
    /// 배틀 타워's lobby: the run, the three who go (a click: who goes there instead; 추천으로 once it's the player's own), then 도전 (or the next trainer) and 나가기.
    func drawTower(_ m: TowerModel) {
        if let p = m.pick { drawTowerPick(p); return }
        c.say(m.run ? "\(m.streak)연승 중 · 최고 \(m.best)연승" : "최고 \(m.best)연승 · \(m.bp)BP", x(X0 + 2), y(206), font(11, .medium), Ink.ink)
        if m.custom {
            let t = "추천으로", f = font(8.5, .bold), w = width(t, f) + x(14), rc = CGRect(x: x(X1) - w, y: y(206) - x(7.5), width: w, height: x(15))
            c.pill(rc, Ink.redTint); c.say(t, rc.midX, rc.midY, f, Ink.red, 0.5); hits.append((rc, 5420))
        } else { c.say("추천 파티", x(X1 - 2), y(206), font(9, .medium), Ink.faint, 1) }
        let scale = c.scale, snap = { (v: CGFloat) in (v * scale).rounded() / scale }, hint = font(8, .semibold)
        for (i, p) in m.party.enumerated() {
            let rc = r(X0, 220 + CGFloat(i) * 27.5, X1 - X0, 25); c.fill(.rounded(rc, 9 * K), Ink.tile)
            c.image(iconImage(p.dex), CGRect(x: snap(rc.minX + x(2)), y: snap(rc.midY - 16 * K - x(2)), width: 32 * K, height: 32 * K), alpha: 1)
            let hw = c.say("바꾸기", rc.maxX - x(9), rc.midY, hint, Ink.faint, 1)
            c.say(p.name, rc.minX + x(38), rc.midY, font(10, .bold), Ink.ink); c.say("Lv.\(p.level)", rc.maxX - x(9) - hw - x(8), rc.midY, font(9, .semibold), Ink.sub, 1)
            hits.append((rc, 5410 + i))
        }
        let go = r(X0, 307, X1 - X0 - 64, 36), out = r(X1 - 59, 307, 59, 36)
        c.fill(.rounded(go, 12 * K), Ink.red); c.say(m.run ? "다음 상대" : "도전 · \(m.fee)W", go.midX, go.midY, font(13, .bold), .white, 0.5); hits.append((go, 5400))
        c.fill(.rounded(out, 12 * K), Ink.tile); c.say("나가기", out.midX, out.midY, font(11, .bold), Ink.ink, 0.5); hits.append((out, 5401))
    }
    /// The tower's picker: who could go in the slot, by level, a page of five (the party's marked with where they are; picking one of them swaps the two).
    func drawTowerPick(_ p: TowerModel.Pick) {
        c.say("\(p.slot + 1)번째 자리 · 누구로 바꿀까?", x(X0 + 2), y(206), font(11, .medium), Ink.ink)
        for (i, row) in p.rows.enumerated() {
            let rc = r(X0, 216 + CGFloat(i) * 22, X1 - X0, 20)
            tile(rc, 7, on: p.first + i == p.sel)
            var xr = rc.maxX - x(9)
            if let s = row.slot {
                let t = "\(s + 1)번", f = font(7.5, .bold), w = width(t, f) + x(8), mine = s == p.slot
                c.pill(CGRect(x: xr - w, y: rc.midY - x(5.5), width: w, height: x(11)), mine ? Ink.red : Ink.tint(Ink.blue, 0.16)); c.say(t, xr - w / 2, rc.midY, f, mine ? .white : Ink.blue, 0.5)
                xr -= w + x(6)
            }
            xr -= c.say("Lv.\(row.level)", xr, rc.midY, font(9, .semibold), Ink.sub, 1)
            c.say(row.name, rc.minX + x(9), rc.midY, font(10, .bold), Ink.ink, maxW: xr - rc.minX - x(17))
            hits.append((rc, 5430 + i))
        }
        let per = TowerModel.perPage, pages = (p.count + per - 1) / per
        if pages > 1 { pager("\(p.first / per + 1) / \(pages)", 327, prev: true, next: true, codes: (5440, 5441)) }
    }
    /// 도구: everything carried, a row a kind (six in view, the pick kept there; a click picks it), then what the pick does and its button.
    func drawItems(_ m: ItemsModel) {
        c.say("워커 \(m.walker)개 · 가방 \(m.bag)개", x(X0 + 2), y(206), font(9, .medium), Ink.sub)
        if m.rows.isEmpty { c.say("없음", x(Layout.w / 2), y(260), font(10, .medium), Ink.sub, 0.5); return }
        let top = max(0, min(m.sel - 2, m.rows.count - 6))
        for (i, row) in m.rows.enumerated() where i >= top && i < top + 6 {
            let rc = r(X0, 216 + CGFloat(i - top) * 29, X1 - X0, 26)
            tile(rc, 9, on: i == m.sel)
            pixelArt(gem, gemPal, CGPoint(x: rc.minX + x(14), y: rc.midY), 2.5 * K); c.say(row.name, rc.minX + x(28), rc.midY, font(10, .bold), Ink.ink, maxW: rc.width - x(90))
            var xr = rc.maxX - x(9) - c.say("×\(row.count)", rc.maxX - x(9), rc.midY, font(10, .semibold), Ink.ink, 1)
            if row.onWalker > 0 { let t = "워커", f = font(7.5, .bold), w = width(t, f) + x(8); xr -= x(5); c.pill(CGRect(x: xr - w, y: rc.midY - x(5.5), width: w, height: x(11)), Ink.tint(Ink.blue, 0.16)); c.say(t, xr - w / 2, rc.midY, f, Ink.blue, 0.5) }
            hits.append((rc, 5600 + i))
        }
        c.say(m.hint, x(X0 + 2), y(398), font(9, .medium), Ink.sub, maxW: x(X1 - X0 - 4))
        let rc = r(X0, 408, X1 - X0, 30); c.fill(.rounded(rc, 10 * K), m.action == nil ? Ink.tile : Ink.red)
        c.say(m.action ?? "여기선 쓸 수 없어요", rc.midX, rc.midY, font(11, .bold), m.action == nil ? Ink.sub : .white, 0.5); if m.action != nil { hits.append((rc, 5700)) }
    }
}
