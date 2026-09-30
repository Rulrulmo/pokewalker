import AppKit
// The pane's pages: the card's white bottom under the band — battle, 도감 (grid / entry), 상자 (grid / one Pokémon), 상점, 메뉴, 상태.

// MARK: - models
/// The battle: names, HP, types for the LCD's HP boxes; the message and the choices for the page.
struct SideModel: Equatable {
    struct Card: Equatable { var name: String; var level, hp, max: Int; var out: Bool; var status: String? = nil; var types: [String] = []; var owned = false }   // types / owned: shown for theirs
    struct MoveBtn: Equatable { var name, type: String; var power: Int; var effect: Double; var pp = 0, maxPP = 0 }
    enum Mode: Equatable { case none, menu([String], Int), moves([MoveBtn], Int), party([Card], Int), items([String], Int), ask(Bool) }   // ask: 아니오 / 예 (true = 예 highlighted)
    var foe: Card; var mine: Card; var message: String; var mode: Mode
}
/// 상점 / BP 교환소: the list, and how many.
struct ShopModel: Equatable {
    struct Row: Equatable { var name, note, price: String; var owned: Int; var can: Bool; var once: Bool }
    var title: String; var rows: [Row]; var sel: Int; var qty: Int?; var most: Int; var total: String
    var hint: String                                                   // the bottom row when nothing is being counted: a message, or why not
    var ask: Bool?                                                     // a once-only row's 정말? (true = 예 highlighted)
}
/// The status sheet (the title row's ⌄): the companion, today, then the rest.
struct StatusModel: Equatable {
    struct Row: Equatable { var key, value: String }
    var dex: Int; var name, sex, level, toNext, nature: String; var female: Bool; var v: Int; var exp: CGFloat; var numbers: [Row]; var rows: [Row]
}
/// 메뉴: the LCD's pages as tiles, the one on the LCD picked.
struct MenuModel: Equatable {
    struct Row: Equatable { var name, note: String }
    var rows: [Row]; var sel: Int
}
/// The 도감 entry (the LCD shows its number, name and types): base stats, where to meet it, how it evolves.
struct DexModel: Equatable {
    var num: Int; var status: Int                                      // 0 not met, 1 seen, 2 caught
    var stats: [Int]; var found: [String]; var evos: [String]          // up to 3 places, 2 evolutions: a line each
}
/// The 도감 / 포켓몬 grid: tabs, a page of box icons (the pick bobbing), the pager; 포켓몬's has the companion and the walker's in a row above.
struct GridModel: Equatable {
    static let perPage = 30, columns = 6                               // 6 x 5
    struct Cell: Equatable { var dex: Int; var look: Int; var shiny = false, v3 = false; var level = 0 }   // look: 0 not met (its number), 1 seen (a shadow), 2 caught / in the box
    var tabs: [String]; var tab: Int
    var cells: [Cell]; var first: Int; var sel: Int?                   // this page's cells; first = cells[0]'s place in the whole list; sel = the pick's cell
    var page, pages: Int; var empty: String; var bob: Bool
    var party: [Cell] = []; var partySel: Int? = nil; var items: Int? = nil   // 포켓몬: the companion + the walker's in a row over the box, then the items chip (nil = no row: 도감)
}
/// One Pokémon of the box, in full: nature and ability with what they do, IVs and EVs as hexagons.
struct MonModel: Equatable {
    var nature, natureNote, ability, abilityNote: String; var up, down: Int?   // stat indices the nature raises / lowers (nil = neutral)
    var ivs, evs: [Int]; var hyper: [Int]; var v, evTotal: Int
    var confirm: Bool                                                  // 놓아줄까? is up: the buttons become 아니오 / 예
    var place = 2                                                      // 0 the companion (nothing to do), 1 the walker's (함께 걷기 / 상자로 보내기), 2 the box's (함께 걷기 / 놓아주기)
    var sel: Int?                                                      // the LCD's pick (함께 / 놓아주기 / 닫기, or 아니오 / 예): what ● does is red
}
/// 포켓몬 레이더: the four bushes as on the LCD, the one rustling marked.
struct RadarModel: Equatable { var live: Int?; var cursor: Int; var chain: Int; var season = Season.summer }
/// 트레이너 카드: its three pages as tabs.
struct CardModel: Equatable { var page: Int }
/// A new move to learn: it, then the four known ones and 배우지 않는다.
struct LearnModel: Equatable {
    struct Move: Equatable { var name, type: String; var power, pp: Int }
    var who: String; var new: Move; var known: [Move]; var sel: Int
}
/// 배틀 타워's lobby: the run, the party, the button.
struct TowerModel: Equatable {
    struct Member: Equatable { var dex: Int; var name: String; var level: Int }
    var run: Bool; var streak, best, bp, fee: Int; var party: [Member]
}
/// Whatever the pane shows; all nil = no page (the card's idle height).
struct PaneContent: Equatable {
    var battle: SideModel?; var dex: DexModel?; var shop: ShopModel?; var menu: MenuModel?; var status: StatusModel?; var grid: GridModel?; var mon: MonModel?
    var radar: RadarModel?; var card: CardModel?; var learn: LearnModel?; var tower: TowerModel?; var items: [String]?
}

// MARK: - the look (card points x K)
enum Ink {
    static func c(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor { NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a) }
    static let red = c(214, 46, 42), redTint = c(252, 228, 226), onRed = c(250, 212, 208), dark = c(34, 37, 45)
    static let tile = c(242, 243, 246), board = c(246, 247, 249), line = c(230, 232, 237), ink = c(28, 32, 42), sub = c(112, 118, 130), faint = c(160, 165, 176)
    static let blue = c(58, 132, 236), green = c(52, 178, 88), yellow = c(240, 176, 32), pink = c(226, 80, 120), gold = c(222, 150, 20)
    static func tint(_ col: NSColor, _ k: CGFloat) -> NSColor { col.blended(withFraction: 1 - k, of: .white) ?? col }
    static func hp(_ f: CGFloat) -> NSColor { f > 0.5 ? green : f > 0.2 ? yellow : c(230, 70, 60) }
}
let typeColor: [String: NSColor] = (["normal": (168, 167, 122), "fire": (238, 129, 48), "water": (99, 144, 240), "grass": (122, 199, 76), "electric": (247, 208, 44),
    "ice": (150, 217, 214), "fighting": (194, 46, 40), "poison": (163, 62, 161), "ground": (226, 191, 101), "flying": (169, 143, 243), "psychic": (249, 85, 135),
    "bug": (166, 185, 26), "rock": (182, 161, 54), "ghost": (115, 87, 151), "dragon": (111, 53, 252), "dark": (112, 87, 70), "steel": (183, 183, 206)] as [String: (Int, Int, Int)])
    .mapValues { Ink.c($0.0, $0.1, $0.2) }
@MainActor func font(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: size * K, weight: w) }
/// Text centred on the row `cy` (by its caps, one baseline for Hangul and digits); align 0 = starts at x, 0.5 = centred on x, 1 = ends at x.
@MainActor @discardableResult func say(_ s: String, _ x: CGFloat, _ cy: CGFloat, _ f: NSFont, _ c: NSColor, _ align: CGFloat = 0, maxW: CGFloat? = nil) -> CGFloat {
    var s = s
    if let maxW { while s.count > 1, width(s, f) > maxW { s = String(s.dropLast(2)) + "…" } }
    let w = width(s, f)
    (s as NSString).draw(at: NSPoint(x: x - w * align, y: cy - f.ascender + f.capHeight / 2), withAttributes: [.font: f, .foregroundColor: c])
    return w
}
func width(_ s: String, _ f: NSFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: f]).width }
func pill(_ r: NSRect, _ c: NSColor) { NSBezierPath(roundedRect: r, xRadius: min(r.height, r.width) / 2, yRadius: min(r.height, r.width) / 2).fill(with: c) }
func rounded(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
/// The HGSS caught mark: a small Poké Ball of radius r.
func miniBall(_ c: NSPoint, _ r: CGFloat) {
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill(with: Ink.dark)
    let ri = r * 0.8, inner = NSRect(x: c.x - ri, y: c.y - ri, width: 2 * ri, height: 2 * ri)
    NSGraphicsContext.saveGraphicsState(); NSBezierPath(ovalIn: inner).addClip()
    Ink.red.setFill(); NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: ri).fill()
    NSColor.white.setFill(); NSRect(x: inner.minX, y: c.y, width: inner.width, height: ri).fill()
    Ink.dark.setFill(); NSRect(x: inner.minX, y: c.y - r * 0.1, width: inner.width, height: r * 0.2).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.42, y: c.y - r * 0.42, width: r * 0.84, height: r * 0.84)).fill(with: Ink.dark)
    NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.26, y: c.y - r * 0.26, width: r * 0.52, height: r * 0.52)).fill(with: .white)
}
/// ◀ / ▶ as a small filled triangle centred on (cx, cy).
func triangle(_ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, left: Bool, _ c: NSColor) {
    let p = NSBezierPath(), d: CGFloat = left ? 1 : -1
    p.move(to: NSPoint(x: cx + d * s * 0.55, y: cy - s)); p.line(to: NSPoint(x: cx - d * s * 0.75, y: cy)); p.line(to: NSPoint(x: cx + d * s * 0.55, y: cy + s)); p.close(); p.fill(with: c)
}
/// A type badge ending at `right` (or starting at `left`); returns its width.
@MainActor @discardableResult func typePill(_ t: String, _ x: CGFloat, _ cy: CGFloat, h: CGFloat, size: CGFloat, right: Bool = false, grey: Bool = false) -> CGFloat {
    let s = typeKo[t] ?? t, f = font(size, .bold), w = width(s, f) + 9 * K, x0 = right ? x - w : x
    pill(NSRect(x: x0, y: cy - h / 2, width: w, height: h), grey ? Ink.c(196, 198, 204) : typeColor[t] ?? .gray)
    say(s, x0 + w / 2, cy, f, .white, 0.5); return w
}
/// A 4-10 pt bar on a track.
func bar(_ x0: CGFloat, _ x1: CGFloat, _ cy: CGFloat, _ frac: CGFloat, _ c: NSColor, h: CGFloat, track: NSColor = Ink.line) {
    pill(NSRect(x: x0, y: cy - h / 2, width: x1 - x0, height: h), track)
    if frac > 0 { pill(NSRect(x: x0, y: cy - h / 2, width: max(h, (x1 - x0) * min(1, frac)), height: h), c) }
}

// MARK: - the page view
final class SideView: NSView {
    var content = PaneContent()
    var model: SideModel? { content.battle }
    var dex: DexModel? { content.dex }
    var shop: ShopModel? { content.shop }
    var status: StatusModel? { content.status }
    var menuPage: MenuModel? { content.menu }
    var grid: GridModel? { content.grid }
    var scrolled: CGFloat = 0                                              // trackpad scroll not yet turned into a row step
    var shopTop = 0, shopTitle = ""                                        // the list's first visible row: moves only when the pick leaves the window
    var itemTop = 0                                                        // the same for the battle's item list
    var downOn = 0                                                         // the page a click began on: a double-click's 2nd click on another page is dropped
    var pageKind: Int {
        let c = content
        return [c.battle != nil, c.dex != nil, c.grid != nil, c.shop != nil, c.menu != nil, c.mon != nil, c.radar != nil, c.card != nil, c.learn != nil, c.tower != nil, c.items != nil].firstIndex(of: true).map { $0 + 1 } ?? 0
    }
    var hits: [(NSRect, Int)] = []                                         // clickable: battle index, 2000+ shop, 3000+ menu, 4000+ grid / box controls, 5000+ other pages, 10000+ grid cells
    weak var walker: WalkerView?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var needsPanelToBecomeKey: Bool { true }                                           // a click here makes the body key: the keys keep working
    override func menu(for event: NSEvent) -> NSMenu? { walker?.menu(for: event) }             // ctrl-click opens the walker's menu, like a right-click
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let k = hits.first(where: { $0.0.contains(p) })?.1 else { window?.performDrag(with: e); return }   // not on a button: drag the whole body
        if e.clickCount == 1 { downOn = pageKind } else if model != nil || shop?.ask != nil || content.mon != nil || pageKind != downOn { return }   // a double-click's 2nd click on what the 1st one opened (a move, 예, 함께 under 아니오, a cell under 메뉴's tile): ignored
        if k >= 5000, k < 10000 { walker?.pageTap(k) } else if k >= 4000 { walker?.gridTap(k) } else if k >= 3000 { walker?.menuTap(k - 3000) } else if k >= 2000 { walker?.shopTap(k) } else { walker?.sidePick(k) }
    }
    override func scrollWheel(with e: NSEvent) {                                                 // the shop list: a row per notch (or 6 pt of trackpad); a grid: a page (24 pt)
        guard shop != nil || grid != nil else { return super.scrollWheel(with: e) }
        let notch: CGFloat = grid != nil ? 24 : 6
        func step(_ d: Int) { if grid != nil { walker?.gridStep(d * GridModel.perPage) } else { walker?.shopRow(d) } }   // rows only, never the amount
        if !e.hasPreciseScrollingDeltas { if e.scrollingDeltaY != 0 { step(e.scrollingDeltaY > 0 ? -1 : 1) }; return }
        if e.phase == .began { scrolled = 0 }
        scrolled += e.scrollingDeltaY
        while abs(scrolled) >= notch { step(scrolled > 0 ? -1 : 1); scrolled -= scrolled > 0 ? notch : -notch }
    }
    override func resetCursorRects() { for (r, _) in hits { addCursorRect(r, cursor: .pointingHand) } }
    func show(_ c: PaneContent) { guard c != content else { return }; content = c; needsDisplay = true }

    /// Card coordinates → this view (it starts at the pane's top, card y 189).
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * K, y: (y - Layout.pane) * K, width: w * K, height: h * K) }
    func y(_ v: CGFloat) -> CGFloat { (v - Layout.pane) * K }
    func x(_ v: CGFloat) -> CGFloat { v * K }
    /// The card's height (card points) for a page: the window grows down to it. Pages keep one height while they're up (a fight doesn't jump per turn).
    static let tallest: CGFloat = 472                                                              // 포켓몬's grid: the size menu keeps it on the screen
    static func height(_ c: PaneContent) -> CGFloat {
        c.battle != nil ? 311 : c.grid?.items != nil ? 472 : c.grid != nil || c.mon != nil ? 422 : c.items != nil ? 330 : c.dex != nil ? 390 : c.shop != nil ? 406 : c.menu != nil ? 344
            : c.radar != nil ? 327 : c.card != nil ? 230 : c.learn != nil ? 365 : c.tower != nil ? 353 : c.status != nil ? 354 : Layout.idle
    }

    override func draw(_ dirty: NSRect) {
        hits = []; defer { window?.invalidateCursorRects(for: self) }
        let c = content
        if let d = c.dex { drawDex(d) } else if let g = c.grid { drawGrid(g) } else if let m = c.mon { drawMon(m) } else if let s = c.shop { drawShop(s) }
        else if let m = c.menu { drawMenu(m) } else if let m = c.battle { drawBattle(m) } else if let i = c.items { drawItems(i) } else if let r = c.radar { drawRadar(r) }
        else if let k = c.card { tabs(["트레이너 카드", "최근 7일", "알"], k.page, 198, code: 5200) } else if let l = c.learn { drawLearn(l) }
        else if let t = c.tower { drawTower(t) } else if let s = c.status { drawStatus(s) }
    }
    let X0: CGFloat = 9, X1: CGFloat = 207                                                         // the content column (card points): the bezel's edges

    // MARK: battle: the message, then the choices (HP lives on the LCD)
    func drawBattle(_ m: SideModel) {
        let top: CGFloat = 198, w = X1 - X0
        func button(_ rc: NSRect, _ label: String, _ fill: NSColor, _ fg: NSColor, _ idx: Int, _ size: CGFloat = 11) {
            rounded(rc, 10 * K).fill(with: fill); say(label, rc.midX, rc.midY, font(size, .bold), fg, 0.5); hits.append((rc, idx))
        }
        switch m.mode {
        case .none:                                                                               // a turn playing: the message, up to three lines
            var lines: [String] = [], cur = "", f = font(11, .medium)
            for word in m.message.split(separator: " ") {                                          // by words, as HGSS's box does ("!" never alone on a line)
                let t = cur.isEmpty ? String(word) : cur + " " + word
                if width(t, f) > x(w - 4), !cur.isEmpty { lines.append(cur); cur = String(word) } else { cur = t }
            }
            lines.append(cur); if lines.count > 3 { f = font(10, .medium) }
            for (j, l) in lines.prefix(4).enumerated() { say(l.trimmingCharacters(in: .whitespaces), x(X0 + 2), y(top + 8 + CGFloat(j) * 17), f, Ink.ink) }
            return
        default: say(m.message, x(X0 + 2), y(top + 8), font(11, .medium), Ink.ink, maxW: x(w - 4))
        }
        let y0 = top + 23
        switch m.mode {
        case .menu(let opts, let sel):                                                            // big 공격, three below; the pick is red
            let tints: [String: NSColor] = ["볼": Ink.yellow, "도구": Ink.green, "교체": Ink.blue, "도망": Ink.blue, "기권": Ink.faint]
            button(r(X0, y0, w, 38), opts[0], sel == 0 ? Ink.red : Ink.redTint, sel == 0 ? .white : Ink.red, 0, 13)
            let cw = (w - 10) / 3
            for i in 1..<opts.count {
                let rc = r(X0 + CGFloat(i - 1) * (cw + 5), y0 + 44, cw, 36)
                button(rc, opts[i], sel == i ? Ink.red : Ink.tint(tints[opts[i]] ?? Ink.faint, 0.2), sel == i ? .white : Ink.ink, i)
            }
        case .moves(let ms, let sel):                                                             // 2 x 2 in their type's tint, the pick ringed
            let cw = (w - 5) / 2
            for (i, mv) in ms.enumerated() {
                let rc = r(X0 + CGFloat(i % 2) * (cw + 5), y0 + CGFloat(i / 2) * 43, cw, 38), dead = mv.effect == 0 || mv.pp == 0, c = typeColor[mv.type] ?? .gray
                let p = rounded(rc, 10 * K); p.fill(with: dead ? Ink.tile : Ink.tint(c, 0.2))
                if i == sel { Ink.red.setStroke(); p.lineWidth = 2 * K; p.stroke() }
                say(mv.name, rc.minX + x(9), rc.minY + x(12), font(11, .bold), dead ? Ink.faint : Ink.ink, maxW: rc.width - x(14))
                typePill(mv.type, rc.minX + x(8), rc.minY + x(27), h: x(11), size: 7.5, grey: dead)
                let e = mv.effect == 0 ? "효과 없음" : (mv.effect > 1 ? "▲ " : mv.effect < 1 ? "▼ " : "") + "PP \(mv.pp)/\(mv.maxPP)"
                say(e, rc.maxX - x(8), rc.minY + x(27.5), font(8, .semibold), mv.effect > 1 ? Ink.red : Ink.sub, 1)
                hits.append((rc, i))
            }
        case .party(let ps, let sel):                                                             // three rows: name, HP
            for (i, p) in ps.enumerated() {
                let rc = r(X0, y0 + CGFloat(i) * 27.5, w, 25), path = rounded(rc, 9 * K), f = p.max > 0 ? CGFloat(p.hp) / CGFloat(p.max) : 0
                path.fill(with: i == sel ? Ink.redTint : Ink.tile); if i == sel { Ink.red.setStroke(); path.lineWidth = 1.5 * K; path.stroke() }
                let nx = say((p.out ? "▶ " : "") + p.name, rc.minX + x(9), rc.minY + x(9.5), font(10, .bold), p.hp > 0 ? Ink.ink : Ink.faint)
                let lx = rc.minX + x(9) + nx + x(4) + say("Lv\(p.level)", rc.minX + x(13) + nx, rc.minY + x(10), font(8, .semibold), Ink.sub)
                if let st = p.status { let sw = width(st, font(7.5, .bold)) + x(8); pill(NSRect(x: lx + x(4), y: rc.minY + x(4.5), width: sw, height: x(11)), Ink.faint); say(st, lx + x(4) + sw / 2, rc.minY + x(10), font(7.5, .bold), .white, 0.5) }
                say("\(p.hp)/\(p.max)", rc.maxX - x(9), rc.minY + x(9.5), font(9, .semibold), Ink.ink, 1)
                bar(rc.minX + x(9), rc.maxX - x(9), rc.minY + x(19), f, Ink.hp(f), h: x(3))
                hits.append((rc, i))
            }
        case .items(let names, let sel):                                                          // three rows, the pick kept in view
            if sel < itemTop { itemTop = sel } else if sel >= itemTop + 3 { itemTop = sel - 2 }
            itemTop = max(0, min(itemTop, names.count - 3))
            for (i, n) in names.enumerated() where i >= itemTop && i < itemTop + 3 {
                let rc = r(X0, y0 + CGFloat(i - itemTop) * 27.5, w, 25), path = rounded(rc, 9 * K)
                path.fill(with: i == sel ? Ink.redTint : Ink.tile); if i == sel { Ink.red.setStroke(); path.lineWidth = 1.5 * K; path.stroke() }
                let parts = n.components(separatedBy: " ×")
                say(parts[0], rc.minX + x(9), rc.midY, font(10, .bold), Ink.ink); if parts.count > 1 { say("×" + parts[1], rc.maxX - x(9), rc.midY, font(9, .semibold), Ink.sub, 1) }
                hits.append((rc, i))
            }
            if names.count > 3 { say("\(sel + 1) / \(names.count)", x(X1 - 2), y(top + 8), font(8, .semibold), Ink.sub, 1) }
        case .ask(let yes):                                                                       // 아니오 / 예, the pick red
            let cw = (w - 5) / 2
            for (i, t) in ["아니오", "예"].enumerated() { let on = (i == 1) == yes; button(r(X0 + CGFloat(i) * (cw + 5), y0, cw, 40), t, on ? Ink.red : Ink.tile, on ? .white : Ink.ink, i, 13) }
        case .none: break
        }
    }

    // MARK: 도감 / 상자 grid
    func drawGrid(_ g: GridModel) {
        var top: CGFloat = 198
        let scale = window?.backingScaleFactor ?? 2
        if let n = g.items {                                                                        // 포켓몬: the companion and the walker's 3 over the box, then the items
            let cw = (X1 - X0 - 4 * 4) / 5, snap = { (v: CGFloat) in (v * scale).rounded() / scale }
            NSGraphicsContext.current?.imageInterpolation = .none
            for i in 0..<5 {
                let rc = r(X0 + CGFloat(i) * (cw + 4), top, cw, 42), on = i == g.partySel, path = rounded(rc, 10 * K)
                path.fill(with: on ? Ink.redTint : Ink.tile); if on { Ink.red.setStroke(); path.lineWidth = 1.5 * K; path.stroke() }
                if i == 4 { pixelArt(gem, gemPal, NSPoint(x: rc.midX, y: rc.minY + x(15)), 3 * K); say("도구 \(n)", rc.midX, rc.maxY - x(7), font(8, .bold), Ink.sub, 0.5); hits.append((rc, 4510)) }
                else if let c = g.party[safe: i] {
                    let lift = on && g.bob ? K : 0
                    iconImage(c.dex).draw(in: NSRect(x: snap(rc.midX - 16 * K), y: snap(rc.minY - x(3) - lift), width: 32 * K, height: 32 * K), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
                    say(i == 0 ? "함께" : "Lv.\(c.level)", rc.midX, rc.maxY - x(7), font(8, .bold), i == 0 ? Ink.red : Ink.sub, 0.5)
                    if c.shiny { say("★", rc.maxX - x(5), rc.minY + x(6), font(7, .bold), Ink.gold, 1) }
                    hits.append((rc, 4500 + i))
                } else { say("비어 있음", rc.midX, rc.midY, font(7.5, .medium), Ink.faint, 0.5) }   // the walker holds 3
            }
            top += 50
        }
        tabs(g.tabs, g.tab, top)
        let board = r(X0, top + 28, X1 - X0, 5 * 33)
        rounded(board, 11 * K).fill(with: Ink.board)
        if g.cells.isEmpty { say(g.empty, board.midX, board.midY, font(10, .medium), Ink.sub, 0.5) }
        let side = 32 * K, snap = { (v: CGFloat) in (v * scale).rounded() / scale }
        NSGraphicsContext.current?.imageInterpolation = .none
        for (k, c) in g.cells.enumerated() {
            let cell = r(X0 + CGFloat(k % GridModel.columns) * 33, top + 28 + CGFloat(k / GridModel.columns) * 33, 33, 33)
            if k == g.sel { let p = rounded(cell.insetBy(dx: 1.5 * K, dy: 1.5 * K), 8 * K); p.fill(with: Ink.redTint); Ink.red.setStroke(); p.lineWidth = 1.5 * K; p.stroke() }
            if c.look == 0 { say(String(format: "%03d", c.dex), cell.midX, cell.midY, font(8, .medium), Ink.faint, 0.5) }
            else {
                let lift = k == g.sel && g.bob ? K : 0                                                    // the pick hops a pixel, twice a second
                iconImage(c.dex, shadow: c.look == 1).draw(in: NSRect(x: snap(cell.midX - side / 2), y: snap(cell.midY - side / 2 - lift - 0.5 * K), width: side, height: side),
                                                             from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
            }
            if c.shiny { say("★", cell.maxX - x(4), cell.minY + x(6), font(7, .bold), Ink.gold, 1) }
            if c.v3 {                                                                                   // 3V and up: the amber diamond, as on the LCD
                let d = NSBezierPath(), cx = cell.minX + x(6), cy = cell.maxY - x(6), rr = 2.4 * K
                d.move(to: NSPoint(x: cx, y: cy - rr)); d.line(to: NSPoint(x: cx + rr, y: cy)); d.line(to: NSPoint(x: cx, y: cy + rr)); d.line(to: NSPoint(x: cx - rr, y: cy)); d.close()
                d.fill(with: Ink.c(245, 178, 40)); Ink.c(160, 100, 10).setStroke(); d.lineWidth = 0.5 * K; d.stroke()
            }
            hits.append((cell, 10000 + g.first + k))
        }
        pager("\(g.page) / \(g.pages)", top + 198, prev: g.pages > 1, next: g.pages > 1)   // the last page's ▶ goes round to #1
    }
    /// A pill track of tabs, the picked one solid red.
    func tabs(_ labels: [String], _ sel: Int, _ top: CGFloat, code: Int = 4100) {
        let track = r(X0, top, X1 - X0, 22), sw = track.width / CGFloat(labels.count)
        pill(track, Ink.tile)
        for (i, s) in labels.enumerated() {
            let cell = NSRect(x: track.minX + CGFloat(i) * sw, y: track.minY, width: sw, height: track.height)
            if i == sel { pill(cell.insetBy(dx: 2 * K, dy: 2 * K), Ink.red) }
            say(s, cell.midX, cell.midY, font(10, i == sel ? .bold : .medium), i == sel ? .white : Ink.sub, 0.5)
            hits.append((cell, code + i))
        }
    }
    /// ◀ n / m ▶, centred.
    func pager(_ label: String, _ top: CGFloat, prev: Bool, next: Bool) {
        let f = font(10, .semibold), cy = y(top + 9), tw = width(label, f)
        say(label, x(Layout.w / 2), cy, f, Ink.ink, 0.5)
        for (dx, left, on, code) in [(-tw / 2 - x(16), true, prev, 4200), (tw / 2 + x(16), false, next, 4201)] {
            let c = NSRect(x: x(Layout.w / 2) + dx - x(9), y: cy - x(9), width: x(18), height: x(18))
            NSBezierPath(ovalIn: c).fill(with: Ink.tile); triangle(c.midX + (left ? -0.5 : 0.5) * K, c.midY, 3 * K, left: left, on ? Ink.sub : Ink.line)
            if on { hits.append((c, code)) }
        }
    }

    // MARK: 도감 entry: base stats, where, evolutions
    func drawDex(_ d: DexModel) {
        var yy: CGFloat = 198
        guard d.status > 0 else { say("아직 만나지 못했다", x(Layout.w / 2), y(yy + 60), font(10, .medium), Ink.sub, 0.5); return }
        for (name, v) in zip(["HP", "공격", "방어", "특공", "특방", "스피드"], d.stats) {
            say(name, x(X0 + 2), y(yy + 8), font(9, .medium), Ink.sub)
            say("\(v)", x(X0 + 58), y(yy + 8), font(10, .semibold), Ink.ink, 1)
            bar(x(X0 + 66), x(X1 - 2), y(yy + 8), CGFloat(v) / 150, v >= 100 ? Ink.green : Ink.yellow, h: x(5), track: Ink.tile)
            yy += 16
        }
        yy += 4; Ink.line.setFill(); NSRect(x: x(X0 + 2), y: y(yy), width: x(X1 - X0 - 4), height: max(0.5, 0.5 * K)).fill(); yy += 4
        for (label, vals, n) in [("만나는 곳", d.found.isEmpty ? ["알 수 없음"] : d.found, 3), ("진화", d.evos.isEmpty ? ["더 이상 진화하지 않는다"] : d.evos, 2)] {   // a line each
            say(label, x(X0 + 2), y(yy + 10), font(9, .medium), Ink.sub)
            for (j, v) in vals.prefix(n).enumerated() { say(v, x(X0 + 58), y(yy + 10 + CGFloat(j) * 14), font(10, .medium), Ink.ink, maxW: x(X1 - X0 - 60)) }
            yy += CGFloat(n) * 14 + 6
        }
    }

    // MARK: 상자: one Pokémon — nature, ability, IVs and EVs, and 함께 / 놓아주기
    func drawMon(_ m: MonModel) {
        let yy = monBody(m, 198)
        // 함께 걷기 / 상자로 보내기 (the walker's) or 놓아주기 (the box's; 놓아줄까? → 아니오 / 예); the companion: nothing to do
        let cw = (X1 - X0 - 5) / 2
        if m.place == 0 { let rc = r(X0, yy, X1 - X0, 30); rounded(rc, 10 * K).fill(with: Ink.tile); say("함께 걷는 중", rc.midX, rc.midY, font(11, .bold), Ink.sub, 0.5); return }
        let opts: [(String, Int)] = m.confirm ? [("아니오", 4402), ("예 · 놓아주기", 4403)] : [("함께 걷기", 4400), m.place == 1 ? ("상자로 보내기", 4404) : ("놓아주기", 4401)]
        for (i, (t, code)) in opts.enumerated() {
            let rc = r(X0 + CGFloat(i) * (cw + 5), yy, cw, 30), strong = m.sel == i                   // red = what ● does now (the LCD's pick); none while nothing is picked
            rounded(rc, 10 * K).fill(with: strong ? Ink.red : Ink.tile); say(t, rc.midX, rc.midY, font(11, .bold), strong ? .white : Ink.ink, 0.5); hits.append((rc, code))
        }
    }
    /// A Pokémon in full, from `top`: nature, ability, the IV / EV hexagons. Returns where the buttons go.
    func monBody(_ m: MonModel, _ top: CGFloat) -> CGFloat {
        var yy = top
        let statNames = ["HP", "공격", "방어", "특공", "특방", "스피드"]
        // 성격: name, the stats it moves, what that means
        say("성격", x(X0 + 2), y(yy + 7), font(9, .medium), Ink.sub)
        say(m.nature, x(X0 + 34), y(yy + 7), font(11, .bold), Ink.ink)
        var px = x(X1 - 2)
        let chips: [(String, NSColor)] = m.up.map { u in [(statNames[m.down!] + " ↓", Ink.blue), (statNames[u] + " ↑", Ink.red)] } ?? [("변화 없음", Ink.faint)]
        for (t, c) in chips { let f = font(8, .bold), w = width(t, f) + x(10); pill(NSRect(x: px - w, y: y(yy + 7) - x(6), width: w, height: x(12)), Ink.tint(c, 0.16)); say(t, px - w / 2, y(yy + 7), f, c, 0.5); px -= w + x(4) }
        say(m.natureNote, x(X0 + 34), y(yy + 20), font(9, .regular), Ink.sub, maxW: x(X1 - X0 - 36))
        yy += 30; Ink.line.setFill(); NSRect(x: x(X0 + 2), y: y(yy), width: x(X1 - X0 - 4), height: max(0.5, 0.5 * K)).fill(); yy += 6
        // 특성: name, then its description (two lines at most)
        say("특성", x(X0 + 2), y(yy + 7), font(9, .medium), Ink.sub)
        say(m.ability, x(X0 + 34), y(yy + 7), font(11, .bold), Ink.ink)
        var lines: [String] = [], cur = "", f = font(9)
        for word in m.abilityNote.split(separator: " ") { let t = cur.isEmpty ? String(word) : cur + " " + word; if width(t, f) > x(X1 - X0 - 36), !cur.isEmpty { lines.append(cur); cur = String(word) } else { cur = t } }
        lines.append(cur)
        for (j, l) in lines.prefix(2).enumerated() { say(l, x(X0 + 34), y(yy + 20 + CGFloat(j) * 12), f, Ink.sub, maxW: x(X1 - X0 - 36)) }
        yy += 40; Ink.line.setFill(); NSRect(x: x(X0 + 2), y: y(yy), width: x(X1 - X0 - 4), height: max(0.5, 0.5 * K)).fill(); yy += 4
        // IVs and EVs: two hexagons, the nature's stats in red / blue
        let half = (X1 - X0) / 2
        hexagon(title: "개체값", note: m.v > 0 ? "\(m.v)V" : "", values: m.ivs, max: 31, center: NSPoint(x: x(X0 + half / 2), y: y(yy + 57)), color: Ink.blue, up: m.up, down: m.down, gold: m.hyper, top: y(yy + 6))
        hexagon(title: "노력치", note: "합 \(m.evTotal)", values: m.evs, max: 252, center: NSPoint(x: x(X0 + half * 1.5), y: y(yy + 57)), color: Ink.c(236, 120, 40), up: m.up, down: m.down, gold: [], top: y(yy + 6))
        return yy + 104
    }
    /// A six-sided chart: HP on top, then 공격 · 방어 · 스피드 · 특방 · 특공 clockwise (the games' order); rings at thirds.
    func hexagon(title: String, note: String, values: [Int], max: CGFloat, center c: NSPoint, color: NSColor, up: Int?, down: Int?, gold: [Int], top: CGFloat) {
        let order = [0, 1, 2, 5, 4, 3], names = ["HP", "공격", "방어", "특공", "특방", "스피드"], R = 24 * K
        say(title, c.x - x(2), top, font(9, .bold), Ink.ink, 1); say(note, c.x + x(2), top, font(9, .semibold), note.hasSuffix("V") ? Ink.gold : Ink.sub)
        func pt(_ i: Int, _ f: CGFloat) -> NSPoint { let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 3; return NSPoint(x: c.x + cos(a) * R * f, y: c.y + sin(a) * R * f) }
        for ring in [1.0, 2.0 / 3, 1.0 / 3] as [CGFloat] {
            let p = NSBezierPath(); p.move(to: pt(0, ring)); for i in 1..<6 { p.line(to: pt(i, ring)) }; p.close()
            if ring == 1 { p.fill(with: Ink.board) }; Ink.line.setStroke(); p.lineWidth = 0.7 * K; p.stroke()
        }
        for i in 0..<6 { let p = NSBezierPath(); p.move(to: c); p.line(to: pt(i, 1)); Ink.line.setStroke(); p.lineWidth = 0.5 * K; p.stroke() }
        let poly = NSBezierPath()
        for (i, s) in order.enumerated() { let q = pt(i, Swift.max(0.02, CGFloat(values[s]) / max)); if i == 0 { poly.move(to: q) } else { poly.line(to: q) } }
        poly.close(); poly.fill(with: color.withAlphaComponent(0.32)); color.setStroke(); poly.lineWidth = 1.2 * K; poly.stroke()
        for (i, s) in order.enumerated() {                                                     // name over value, outside the corner
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 3, lx = c.x + cos(a) * (R + x(15)), ly = c.y + sin(a) * (R + x(10)) + (i == 0 ? -x(3) : i == 3 ? x(3) : 0)
            let nc = s == up ? Ink.red : s == down ? Ink.blue : Ink.sub
            say(names[s], lx, ly - x(4.5), font(7.5, .medium), nc, 0.5)
            say("\(values[s])", lx, ly + x(4.5), font(8.5, .bold), gold.contains(s) ? Ink.gold : Ink.ink, 0.5)
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
            if on { rounded(rc, 8 * K).fill(with: Ink.redTint) } else if i > first, i != s.sel + 1 { Ink.line.setFill(); NSRect(x: x(X0 + 8), y: y(yy), width: x(X1 - X0 - 16), height: max(0.5, 0.5 * K)).fill() }
            let fg = row.can ? Ink.ink : Ink.faint
            say(row.price, x(X1 - 8), y(yy + 9.5), font(10, .semibold), on ? Ink.red : fg, 1)
            say(row.name, x(X0 + 8), y(yy + 9.5), font(10, .bold), fg, maxW: x(X1 - X0 - 20) - width(row.price, font(10, .semibold)))
            let own = row.once ? "" : "보유 \(row.owned)"
            say(own, x(X1 - 8), y(yy + 20), font(8, .medium), Ink.sub, 1)
            say(row.note, x(X0 + 8), y(yy + 20), font(8, .medium), Ink.sub, maxW: x(X1 - X0 - 24) - width(own, font(8, .medium)))
            hits.append((rc, 2100 + i))
        }
        if s.rows.count > rows {                                                                   // where in the list: a thin bar on the right
            let track = r(X1 - 1.5, top + 4, 1.2, CGFloat(rows) * rh - 8)
            Ink.line.setFill(); track.fill()
            let h = track.height * CGFloat(rows) / CGFloat(s.rows.count), yy = track.minY + (track.height - h) * CGFloat(first) / CGFloat(s.rows.count - rows)
            Ink.faint.setFill(); NSRect(x: track.minX, y: yy, width: track.width, height: h).fill()
        }
        let by = top + CGFloat(rows) * rh + 8
        if let yes = s.ask {                                                                       // 정말? for a once-only row
            let cw = (X1 - X0 - 5) / 2
            for (i, (t, code)) in [("아니오", 2007), ("예 · \(s.total)", 2006)].enumerated() {
                let rc = r(X0 + CGFloat(i) * (cw + 5), by, cw, 30), on = (i == 1) == yes
                pill(rc, on ? Ink.red : Ink.tile); say(t, rc.midX, rc.midY, font(11, .bold), on ? .white : Ink.ink, 0.5); hits.append((rc, code))
            }
            return
        }
        guard let q = s.qty else {
            let rc = r(X0, by, X1 - X0, 30); pill(rc, Ink.tile); say(s.hint, rc.midX, rc.midY, font(9, .medium), Ink.sub, 0.5, maxW: rc.width - x(16)); return
        }
        let step = r(X0, by, 94, 30); pill(step, Ink.tile)
        for (cx, plus, on, code) in [(X0 + 16, false, q > 1, 2001), (X0 + 78, true, q < s.most, 2002)] {
            let c = on ? Ink.ink : Ink.line, hr = NSRect(x: x(cx - 13), y: step.minY, width: x(26), height: step.height)
            c.setFill(); NSRect(x: x(cx - 4), y: step.midY - 0.8 * K, width: x(8), height: 1.6 * K).fill()
            if plus { NSRect(x: x(cx) - 0.8 * K, y: step.midY - x(4), width: 1.6 * K, height: x(8)).fill() }
            if on { hits.append((hr, code)) }
        }
        say("\(q)개", step.midX, step.midY, font(11, .bold), Ink.ink, 0.5)
        let buy = r(X0 + 100, by, X1 - X0 - 100, 30); pill(buy, Ink.red); say("\(s.total) 사기", buy.midX, buy.midY, font(11, .bold), .white, 0.5, maxW: buy.width - x(12)); hits.append((buy, 2005))
    }

    // MARK: 메뉴: 2 x 5 tiles, the one on the LCD red
    func drawMenu(_ m: MenuModel) {
        let rh: CGFloat = 31, gap: CGFloat = 4, cw = (X1 - X0 - gap) / 2
        for (i, row) in m.rows.enumerated() {
            let rc = r(X0 + CGFloat(i % 2) * (cw + gap), 198 + CGFloat(i / 2) * (rh + gap), cw, rh), on = i == m.sel
            rounded(rc, 9 * K).fill(with: on ? Ink.red : Ink.tile)
            say(row.name, rc.minX + x(9), rc.minY + x(10.5), font(10, .bold), on ? .white : Ink.ink, maxW: rc.width - x(14))
            say(row.note, rc.minX + x(9), rc.minY + x(22), font(8, .medium), on ? Ink.onRed : Ink.sub, maxW: rc.width - x(14))
            hits.append((rc, 3000 + i))
        }
    }

    // MARK: 상태: the companion, three numbers, the rest
    func drawStatus(_ s: StatusModel) {
        var yy: CGFloat = 200
        let scale = window?.backingScaleFactor ?? 2, snap = { (v: CGFloat) in (v * scale).rounded() / scale }
        NSGraphicsContext.current?.imageInterpolation = .none
        iconImage(s.dex).draw(in: NSRect(x: snap(x(X0 - 1)), y: snap(y(yy)), width: 32 * K, height: 32 * K), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        let tx = X0 + 36
        var w = say(s.name, x(tx), y(yy + 8), font(11, .bold), Ink.ink)
        if !s.sex.isEmpty { w += x(2) + say(s.sex, x(tx) + w + x(2), y(yy + 8.5), font(10, .bold), s.female ? Ink.pink : Ink.blue) }
        w += x(5) + say(s.level, x(tx) + w + x(5), y(yy + 8.5), font(10, .semibold), Ink.sub)
        if s.v > 0 { let t = "\(s.v)V", f = font(7.5, .bold), vw = width(t, f) + x(8); pill(NSRect(x: x(tx) + w + x(5), y: y(yy + 8.5) - x(5.5), width: vw, height: x(11)), s.v >= 3 ? Ink.c(242, 168, 40) : Ink.faint); say(t, x(tx) + w + x(5) + vw / 2, y(yy + 8.5), f, .white, 0.5); w += x(5) + vw }
        say(s.nature, x(X1 - 2), y(yy + 8.5), font(9, .medium), Ink.sub, 1, maxW: x(X1 - 2) - (x(tx) + w + x(8)))   // never over the name / Lv / V
        bar(x(tx), x(X1 - 2), y(yy + 19.5), s.exp, Ink.blue, h: x(5))
        say("다음 레벨까지", x(tx), y(yy + 29), font(8, .medium), Ink.sub)
        say(s.toNext, x(X1 - 2), y(yy + 29), font(9, .semibold), Ink.ink, 1)
        yy += 40; Ink.line.setFill(); NSRect(x: x(X0 + 2), y: y(yy), width: x(X1 - X0 - 4), height: max(0.5, 0.5 * K)).fill(); yy += 6
        let cw = (X1 - X0) / CGFloat(max(1, s.numbers.count))
        for (i, n) in s.numbers.enumerated() {
            let cx = X0 + CGFloat(i) * cw + cw / 2
            say(n.key, x(cx), y(yy + 7), font(8, .medium), Ink.sub, 0.5); say(n.value, x(cx), y(yy + 21), font(13, .bold), Ink.ink, 0.5, maxW: x(cw - 4))
            if i > 0 { Ink.line.setFill(); NSRect(x: x(X0 + CGFloat(i) * cw), y: y(yy + 2), width: max(0.5, 0.5 * K), height: x(26)).fill() }
        }
        yy += 36; Ink.line.setFill(); NSRect(x: x(X0 + 2), y: y(yy), width: x(X1 - X0 - 4), height: max(0.5, 0.5 * K)).fill(); yy += 6
        for row in s.rows {
            say(row.key, x(X0 + 2), y(yy + 10), font(9, .medium), Ink.sub)
            say(row.value, x(X1 - 2), y(yy + 10), font(10, .medium), Ink.ink, 1)
            yy += 20
        }
    }
}
extension SideView {
    /// A few-colour pixel picture (" .:#" shades, `_` clear) at `px` points a pixel, centred on c.
    func pixelArt(_ a: [[UInt8?]], _ pal: [UInt32], _ c: NSPoint, _ px: CGFloat) {
        let w = CGFloat(a.first?.count ?? 0) * px, h = CGFloat(a.count) * px
        for (y, row) in a.enumerated() { for (x, v) in row.enumerated() { if let v {
            let col = pal[Int(v)]; NSColor(red: CGFloat(col >> 16 & 255) / 255, green: CGFloat(col >> 8 & 255) / 255, blue: CGFloat(col & 255) / 255, alpha: 1).setFill()
            NSRect(x: c.x - w / 2 + CGFloat(x) * px, y: c.y - h / 2 + CGFloat(y) * px, width: px, height: px).fill()
        } } }
    }
    /// A picture at sprite resolution (1 pt a pixel x K), unsmoothed, centred on c.
    func pixelPic(_ img: NSImage, _ c: NSPoint) {
        let w = img.size.width * K, h = img.size.height * K
        img.draw(in: NSRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
    }
    /// 포켓몬 레이더: tap the patch that rustles, where it is on the LCD.
    func drawRadar(_ m: RadarModel) {
        say(m.chain > 0 ? "연쇄 \(m.chain) · 흔들리는 풀숲을 골라요" : "흔들리는 풀숲을 골라요", x(X0 + 2), y(206), font(11, .medium), Ink.ink)
        let cw = (X1 - X0 - 5) / 2
        for k in 0..<4 {
            let rc = r(X0 + CGFloat(k % 2) * (cw + 5), 220 + CGFloat(k / 2) * 51, cw, 46), live = m.live == k, path = rounded(rc, 10 * K)
            path.fill(with: live ? Ink.redTint : Ink.tile)
            if k == m.cursor { Ink.red.setStroke(); path.lineWidth = 1.5 * K; path.stroke() }
            pixelPic(grassImage(48, 36, m.season, live ? 1 : 0, rustle: live, flip: k == 1 || k == 2), NSPoint(x: rc.midX, y: rc.midY + x(2)))
            if live { pixelPic(paneImage("w.bang") { bangPic }, NSPoint(x: rc.midX + x(30), y: rc.midY - x(10))) }
            hits.append((rc, 5000 + k))
        }
    }
    /// A new move: it on top, then which to forget (or not learn it).
    func drawLearn(_ m: LearnModel) {
        func line(_ mv: LearnModel.Move, _ rc: NSRect, _ label: String? = nil) {                  // the numbers and type first: the name gets the rest
            var xr = rc.maxX - x(9)
            if !mv.type.isEmpty {
                xr -= say(mv.power > 0 ? "위력 \(mv.power) · PP \(mv.pp)" : "PP \(mv.pp)", xr, rc.midY, font(8, .semibold), Ink.sub, 1) + x(5)
                xr -= typePill(mv.type, xr, rc.midY, h: x(11), size: 7.5, right: true) + x(6)
            }
            say(label ?? mv.name, rc.minX + x(9), rc.midY, font(10, .bold), Ink.ink, maxW: xr - rc.minX - x(9))
        }
        let head = r(X0, 198, X1 - X0, 26); rounded(head, 9 * K).fill(with: Ink.tint(typeColor[m.new.type] ?? Ink.faint, 0.18))
        line(m.new, head, "새 기술 · " + m.new.name)
        say(m.who + "의 기술을 하나 잊는다", x(X0 + 2), y(236), font(9, .medium), Ink.sub)
        for (i, mv) in (m.known + [LearnModel.Move(name: "배우지 않는다", type: "", power: 0, pp: 0)]).enumerated() {
            let rc = r(X0, 246 + CGFloat(i) * 21.5, X1 - X0, 19), path = rounded(rc, 7 * K)
            path.fill(with: i == m.sel ? Ink.redTint : Ink.tile); if i == m.sel { Ink.red.setStroke(); path.lineWidth = 1.5 * K; path.stroke() }
            line(mv, rc); hits.append((rc, 5300 + i))
        }
    }
    /// 배틀 타워's lobby: the run, the three who go, then 도전 (or the next trainer) and 나가기.
    func drawTower(_ m: TowerModel) {
        say(m.run ? "\(m.streak)연승 중 · 최고 \(m.best)연승" : "최고 \(m.best)연승 · \(m.bp)BP", x(X0 + 2), y(206), font(11, .medium), Ink.ink)
        let scale = window?.backingScaleFactor ?? 2, snap = { (v: CGFloat) in (v * scale).rounded() / scale }
        NSGraphicsContext.current?.imageInterpolation = .none
        for (i, p) in m.party.enumerated() {
            let rc = r(X0, 220 + CGFloat(i) * 27.5, X1 - X0, 25); rounded(rc, 9 * K).fill(with: Ink.tile)
            iconImage(p.dex).draw(in: NSRect(x: snap(rc.minX + x(2)), y: snap(rc.midY - 16 * K - x(2)), width: 32 * K, height: 32 * K), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
            say(p.name, rc.minX + x(38), rc.midY, font(10, .bold), Ink.ink); say("Lv.\(p.level)", rc.maxX - x(9), rc.midY, font(9, .semibold), Ink.sub, 1)
        }
        let go = r(X0, 307, X1 - X0 - 64, 36), out = r(X1 - 59, 307, 59, 36)
        rounded(go, 12 * K).fill(with: Ink.red); say(m.run ? "다음 상대" : "도전 · \(m.fee)W", go.midX, go.midY, font(13, .bold), .white, 0.5); hits.append((go, 5400))
        rounded(out, 12 * K).fill(with: Ink.tile); say("나가기", out.midX, out.midY, font(11, .bold), Ink.ink, 0.5); hits.append((out, 5401))
    }
    /// The walker's 도구 (포켓몬's last chip).
    func drawItems(_ items: [String]) {
        say("워커의 도구 · 커넥트하면 가방으로 가요", x(X0 + 2), y(206), font(9, .medium), Ink.sub)
        if items.isEmpty { say("없음", x(Layout.w / 2), y(250), font(10, .medium), Ink.sub, 0.5) }
        for (i, it) in items.enumerated() {
            let rc = r(X0, 216 + CGFloat(i) * 29, X1 - X0, 26); rounded(rc, 9 * K).fill(with: Ink.tile)
            pixelArt(gem, gemPal, NSPoint(x: rc.minX + x(14), y: rc.midY), 2.5 * K); say(it, rc.minX + x(28), rc.midY, font(10, .bold), Ink.ink)
        }
    }
}
extension NSBezierPath { func fill(with c: NSColor) { c.setFill(); fill() } }
