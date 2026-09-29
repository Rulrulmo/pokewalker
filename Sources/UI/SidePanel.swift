import AppKit
// The pane's pages (right of the ball): battle (HGSS touch screen), 도감, 상점, 메뉴, 상태.

// MARK: - the battle page: names, HP, messages and big buttons on the pane, so the 96x64 screen keeps the stage
struct SideModel: Equatable {
    struct Card: Equatable { var name: String; var level, hp, max: Int; var out: Bool; var status: String? = nil; var types: [String] = []; var owned = false }   // types / owned: shown for theirs
    struct MoveBtn: Equatable { var name, type: String; var power: Int; var effect: Double; var pp = 0, maxPP = 0 }
    enum Mode: Equatable { case none, menu([String], Int), moves([MoveBtn], Int), party([Card], Int), items([String], Int), ask(Bool) }   // ask: 아니오 / 예 (true = 예 highlighted)
    var foe: Card; var foeBalls: [Bool]; var mine: Card; var myBalls: [Bool]; var trainer: String?; var message: String; var mode: Mode
}
/// The 상점 / BP 교환소 page on the side panel: the list with what each does, and the how-many controls.
struct ShopModel: Equatable {
    struct Row: Equatable { var name, note, price: String; var owned: Int; var can: Bool; var once: Bool }
    var title, money: String; var rows: [Row]; var sel: Int; var qty: Int?; var most: Int; var total, after: String
    var hint: String                                                   // the bottom box when nothing is being counted: a message, or why not
    var ask: Bool?                                                     // a once-only row's 정말? (true = 예 highlighted)
}
/// The 홈 page (and the pane on screens without a page of their own): where, the companion, today, then the rest.
struct StatusModel: Equatable {
    struct Row: Equatable { var key, value: String }
    var place, when, name, level, toNext, nature, today, watts: String; var v: Int; var exp: CGFloat; var rows: [Row]
}
/// The 메뉴 page: the LCD's pages as a list, the one on the LCD highlighted.
struct MenuModel: Equatable {
    struct Row: Equatable { var name, note: String }
    var money: String; var rows: [Row]; var sel: Int
}
/// The Pokédex page on the side panel.
struct DexModel: Equatable {
    var num: Int; var name: String; var status: Int                    // 0 not met, 1 seen, 2 caught
    var shiny: Bool; var types: [String]; var stats: [Int]
    var found: [String]; var evos: [String]                            // where to meet it; what it becomes and how
    var owned, seen: Int
    var strip: [Int], stripStatus: [Int]                               // the numbers around it, with their status
}
let typeColor: [String: NSColor] = (["normal": (168, 168, 120), "fire": (240, 128, 48), "water": (104, 144, 240), "grass": (120, 200, 80), "electric": (238, 196, 40),
    "ice": (120, 200, 200), "fighting": (192, 48, 40), "poison": (160, 64, 160), "ground": (210, 176, 90), "flying": (150, 130, 230), "psychic": (248, 88, 136),
    "bug": (160, 176, 32), "rock": (184, 160, 56), "ghost": (112, 88, 152), "dragon": (112, 56, 248), "dark": (112, 88, 72), "steel": (160, 160, 190)] as [String: (CGFloat, CGFloat, CGFloat)])
    .mapValues { NSColor(red: CGFloat($0.0) / 255, green: CGFloat($0.1) / 255, blue: CGFloat($0.2) / 255, alpha: 1) }

final class SideView: NSView {
    var model: SideModel?
    var dex: DexModel?
    var shop: ShopModel?
    var status: StatusModel?                                               // the 홈 page (and everywhere without a page of its own)
    var menuPage: MenuModel?
    var scrolled: CGFloat = 0                                              // trackpad scroll not yet turned into a row step
    var shopTop = 0, shopTitle = ""                                        // the list's first visible row: moves only when the pick leaves the window
    var hits: [(NSRect, Int)] = []                                         // clickable rows: battle index, 1000+ dex strip, 2000+ shop, 3000+ menu
    weak var walker: WalkerView?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var needsPanelToBecomeKey: Bool { true }                                           // a click here makes the body key: the keys keep working
    override func menu(for event: NSEvent) -> NSMenu? { walker?.menu(for: event) }             // ctrl-click opens the walker's menu, like a right-click
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let k = hits.first(where: { $0.0.contains(p) })?.1 else { window?.performDrag(with: e); return }   // not on a button: drag the whole body
        if e.clickCount > 1, model != nil || shop?.ask != nil { return }                         // a double-click's 2nd click lands on the next page's button (a move, 예): ignore it
        if k >= 3000 { walker?.menuTap(k - 3000) } else if k >= 2000 { walker?.shopTap(k) } else if k >= 1000 { walker?.dexJump(k - 1000) } else { walker?.sidePick(k) }
    }
    override func scrollWheel(with e: NSEvent) {                                                 // the shop list scrolls a row per notch (or per 6 pt of trackpad)
        guard shop != nil else { return super.scrollWheel(with: e) }
        if !e.hasPreciseScrollingDeltas { if e.scrollingDeltaY != 0 { walker?.shopRow(e.scrollingDeltaY > 0 ? -1 : 1) }; return }   // rows only, never the amount
        if e.phase == .began { scrolled = 0 }
        scrolled += e.scrollingDeltaY
        while abs(scrolled) >= 6 { walker?.shopRow(scrolled > 0 ? -1 : 1); scrolled -= scrolled > 0 ? 6 : -6 }
    }
    override func resetCursorRects() { for (r, _) in hits { addCursorRect(r, cursor: .pointingHand) } }
    /// The pages' layout unit (paneUnit, in step with the ball). Plain UI in the system font — sharp at any scale; the pixel look stays on the LCD.
    static func unit(_ backing: CGFloat = 0) -> CGFloat { paneUnit }
    var u0: CGFloat { paneUnit }
    var body: NSFont { .systemFont(ofSize: 7.5 * u0, weight: .medium) }
    var small: NSFont { .systemFont(ofSize: 6 * u0, weight: .regular) }
    var big: NSFont { .systemFont(ofSize: 10.5 * u0, weight: .bold) }
    static let ink = NSColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1), dim = NSColor(red: 0.42, green: 0.45, blue: 0.52, alpha: 1)
    func width(_ str: String, _ f: NSFont) -> CGFloat { (str as NSString).size(withAttributes: [.font: f]).width }
    /// Plain text with its top-left at (x, y); `right` aligns its end there instead.
    func text(_ str: String, _ x: CGFloat, _ y: CGFloat, _ f: NSFont, _ c: NSColor, shadow: NSColor? = nil, right: CGFloat? = nil, maxW: CGFloat? = nil) {
        var str = str
        if let maxW { while str.count > 1, width(str, f) > maxW { str = String(str.dropLast(2)) + "…" } }
        let x0 = right.map { $0 - width(str, f) } ?? x, g = max(1, f.pointSize / 14)
        if let shadow { (str as NSString).draw(at: NSPoint(x: x0, y: y + g), withAttributes: [.font: f, .foregroundColor: shadow]) }
        (str as NSString).draw(at: NSPoint(x: x0, y: y), withAttributes: [.font: f, .foregroundColor: c])
    }
    /// Text centred in `r` by its ink, not its line box (the pixel font's leading made labels ride high).
    func label(_ str: String, in r: NSRect, _ f: NSFont, _ c: NSColor, shadow: NSColor? = nil, alignLeft: CGFloat? = nil, alignRight: CGFloat? = nil) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: str, attributes: [.font: f]))
        let ink = CTLineGetImageBounds(line, nil), w = width(str, f)
        let y = r.midY - f.ascender + ink.origin.y + ink.height / 2
        let x = alignLeft.map { r.minX + $0 } ?? alignRight.map { r.maxX - $0 - w } ?? r.midX - w / 2
        text(str, x, y, f, c, shadow: shadow)
    }
    func round(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
    func hpColor(_ f: CGFloat) -> NSColor { f > 0.5 ? NSColor(red: 0.30, green: 0.82, blue: 0.40, alpha: 1) : f > 0.2 ? NSColor(red: 0.98, green: 0.78, blue: 0.16, alpha: 1) : NSColor(red: 0.95, green: 0.28, blue: 0.24, alpha: 1) }

    override func draw(_ dirty: NSRect) {
        hits = []; defer { window?.invalidateCursorRects(for: self) }                            // every page, the 상태 page too (it has none)
        if let d = dex { drawDex(d); return }
        if let s = shop { drawShop(s); return }
        if let m = menuPage { drawMenu(m); return }
        if let s = status { drawStatus(s); return }
        guard let m = model else { return }
        let u = paneUnit, W = bounds.width, H = bounds.height, ink = SideView.ink, dim = SideView.dim, paper = NSColor(white: 0.98, alpha: 1)
        /// "HP" tag + bar, the HGSS way: dark track, the colour on top with a little shine.
        func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hp: Int, _ max: Int) {
            let f = max > 0 ? CGFloat(hp) / CGFloat(max) : 0, tag = NSRect(x: x, y: y, width: 15 * u, height: 7 * u)
            round(tag, 2 * u).fill(with: ink); label("HP", in: tag, small, NSColor(red: 1, green: 0.78, blue: 0.2, alpha: 1))
            let tr = NSRect(x: tag.maxX - u, y: y, width: w - 14 * u, height: 7 * u)
            round(tr, 2 * u).fill(with: ink)
            let inner = tr.insetBy(dx: 1.5 * u, dy: 1.5 * u), fw = hp > 0 ? Swift.max(u, inner.width * f) : 0
            NSColor(white: 0.30, alpha: 1).setFill(); inner.fill()
            hpColor(f).setFill(); NSRect(x: inner.minX, y: inner.minY, width: fw, height: inner.height).fill()
            NSColor(white: 1, alpha: 0.35).setFill(); NSRect(x: inner.minX, y: inner.minY, width: fw, height: inner.height / 3).fill()
        }
        func box(_ r: NSRect) { round(r.offsetBy(dx: 0, dy: u), 4 * u).fill(with: NSColor(white: 0, alpha: 0.35)); let p = round(r, 4 * u); p.fill(with: paper); ink.setStroke(); p.lineWidth = u; p.stroke() }
        func teamDots(_ bs: [Bool], _ r: NSRect) { for (i, a) in bs.enumerated() { round(NSRect(x: r.minX + CGFloat(i) * 7 * u, y: r.minY, width: 5 * u, height: 5 * u), 2.5 * u).fill(with: a ? NSColor(red: 0.9, green: 0.22, blue: 0.2, alpha: 1) : NSColor(white: 0.7, alpha: 1)) } }
        func statusPill(_ st: String?, _ right: CGFloat, _ y: CGFloat) {                      // 독 / 마비 / 잠듦 …, ending at `right`
            guard let st else { return }
            let c: NSColor = switch st { case "독", "맹독": NSColor(red: 0.62, green: 0.30, blue: 0.66, alpha: 1); case "화상": NSColor(red: 0.90, green: 0.45, blue: 0.20, alpha: 1)
                case "마비": NSColor(red: 0.86, green: 0.70, blue: 0.10, alpha: 1); case "얼음": NSColor(red: 0.35, green: 0.70, blue: 0.85, alpha: 1); default: NSColor(white: 0.5, alpha: 1) }
            let r = NSRect(x: right - width(st, small) - 6 * u, y: y, width: width(st, small) + 6 * u, height: 7.5 * u)
            round(r, 3.5 * u).fill(with: c); label(st, in: r, small, .white)
        }
        /// The HGSS "caught" mark: a small Poké Ball, `d` across, top-left at (x, y).
        func caughtBall(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat) {
            let r = NSRect(x: x, y: y, width: d, height: d), o = NSBezierPath(ovalIn: r)
            NSColor.white.setFill(); o.fill()
            NSGraphicsContext.saveGraphicsState(); o.addClip(); NSColor(red: 0.90, green: 0.22, blue: 0.20, alpha: 1).setFill(); NSRect(x: x, y: y, width: d, height: d / 2).fill(); NSGraphicsContext.restoreGraphicsState()
            ink.setFill(); NSRect(x: x, y: y + d / 2 - d * 0.07, width: d, height: d * 0.14).fill()
            ink.setStroke(); o.lineWidth = d * 0.1; o.stroke()
            let c = NSBezierPath(ovalIn: NSRect(x: x + d * 0.34, y: y + d * 0.34, width: d * 0.32, height: d * 0.32)); NSColor.white.setFill(); c.fill(); c.lineWidth = d * 0.09; c.stroke()
        }
        // their box: name (+ the caught mark), Lv, (a trainer's team), bar, their types
        let fr = NSRect(x: 6 * u, y: 6 * u, width: W - 12 * u, height: 36 * u)
        box(fr)
        label(m.foe.name, in: NSRect(x: fr.minX, y: fr.minY + 2 * u, width: fr.width, height: 10 * u), body, ink, alignLeft: 5 * u)
        if m.foe.owned { caughtBall(fr.minX + 5 * u + width(m.foe.name, body) + 2.5 * u, fr.minY + 3.5 * u, 7 * u) }
        label("Lv\(m.foe.level)", in: NSRect(x: fr.minX, y: fr.minY + 2 * u, width: fr.width, height: 10 * u), small, dim, alignRight: 5 * u)
        let pillRight = fr.maxX - 5 * u - width("Lv\(m.foe.level)", small) - 3 * u
        statusPill(m.foe.status, pillRight, fr.minY + 3.5 * u)
        let dotsRight = pillRight - (m.foe.status.map { width($0, small) + 6 * u + 3 * u } ?? 0)       // a trainer's team: left of the status pill, never under it
        if !m.foeBalls.isEmpty { teamDots(m.foeBalls, NSRect(x: dotsRight - CGFloat(m.foeBalls.count) * 7 * u + 2 * u, y: fr.minY + 4.5 * u, width: 0, height: 0)) }
        bar(fr.minX + 5 * u, fr.minY + 15 * u, fr.width - 10 * u, m.foe.hp, m.foe.max)
        var tx = fr.minX + 5 * u                                                                  // type badges, in their colours
        for t in m.foe.types {
            let tk = typeKo[t] ?? t, r = NSRect(x: tx, y: fr.minY + 25.5 * u, width: width(tk, small) + 8 * u, height: 7.5 * u)
            round(r, 3.5 * u).fill(with: typeColor[t] ?? .gray); label(tk, in: r, small, .white, shadow: NSColor(white: 0, alpha: 0.35)); tx = r.maxX + 2 * u
        }
        // ours: + HP numbers (and the team)
        let mr = NSRect(x: 6 * u, y: 46 * u, width: W - 12 * u, height: 36 * u)
        box(mr)
        label(m.mine.name, in: NSRect(x: mr.minX, y: mr.minY + 2 * u, width: mr.width, height: 10 * u), body, ink, alignLeft: 5 * u)
        label("Lv\(m.mine.level)", in: NSRect(x: mr.minX, y: mr.minY + 2 * u, width: mr.width, height: 10 * u), small, dim, alignRight: 5 * u)
        statusPill(m.mine.status, mr.maxX - 5 * u - width("Lv\(m.mine.level)", small) - 3 * u, mr.minY + 3.5 * u)
        bar(mr.minX + 5 * u, mr.minY + 15 * u, mr.width - 10 * u, m.mine.hp, m.mine.max)
        label("\(m.mine.hp) / \(m.mine.max)", in: NSRect(x: mr.minX, y: mr.minY + 24 * u, width: mr.width, height: 9 * u), body, ink, alignRight: 5 * u)
        if !m.myBalls.isEmpty { teamDots(m.myBalls, NSRect(x: mr.minX + 5 * u, y: mr.minY + 26 * u, width: 0, height: 0)) }
        // message: the DS dialogue box, double frame
        let msg = NSRect(x: 6 * u, y: 87 * u, width: W - 12 * u, height: 30 * u)
        round(msg, 3 * u).fill(with: ink); round(msg.insetBy(dx: u, dy: u), 2.5 * u).fill(with: NSColor(red: 0.62, green: 0.70, blue: 0.86, alpha: 1)); round(msg.insetBy(dx: 2 * u, dy: 2 * u), 2 * u).fill(with: paper)
        var lines: [String] = [], cur = ""                                                        // wrap by hand so each line goes through the pixel-snapped text()
        for ch in m.message { if width(cur + String(ch), body) > msg.width - 10 * u { lines.append(cur); cur = "" }; cur.append(ch) }
        lines.append(cur)
        for (j, l) in lines.prefix(2).enumerated() { text(l.trimmingCharacters(in: .whitespaces), msg.minX + 5 * u, msg.minY + 4 * u + CGFloat(j) * 11 * u, body, ink) }
        // buttons
        func button(_ r: NSRect, _ c: NSColor, _ on: Bool, _ idx: Int) {
            round(r.offsetBy(dx: 0, dy: 1.5 * u), 4 * u).fill(with: c.blended(withFraction: 0.55, of: .black)!)                       // the lip
            let p = round(r, 4 * u)
            NSGraphicsContext.saveGraphicsState(); p.addClip()
            NSGradient(starting: c.blended(withFraction: 0.18, of: .white)!, ending: c)!.draw(in: r, angle: -90)
            NSColor(white: 1, alpha: 0.28).setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 2 * u).fill()
            NSGraphicsContext.restoreGraphicsState()
            (on ? NSColor.white : c.blended(withFraction: 0.6, of: .black)!).setStroke(); p.lineWidth = on ? 2 * u : u; p.stroke()
            hits.append((r, idx))
        }
        let shadow = NSColor(white: 0, alpha: 0.45), top = 122 * u, bottom = H - 7 * u
        let colors: [String: NSColor] = ["공격": NSColor(red: 0.90, green: 0.26, blue: 0.24, alpha: 1), "볼": NSColor(red: 0.95, green: 0.72, blue: 0.14, alpha: 1),
                                         "도구": NSColor(red: 0.28, green: 0.70, blue: 0.36, alpha: 1), "교체": NSColor(red: 0.28, green: 0.70, blue: 0.36, alpha: 1),
                                         "도망": NSColor(red: 0.24, green: 0.50, blue: 0.90, alpha: 1), "기권": NSColor(red: 0.50, green: 0.52, blue: 0.58, alpha: 1)]
        switch m.mode {
        case .none: break
        case .menu(let opts, let sel):                                                            // big FIGHT, three below
            let bigR = NSRect(x: 6 * u, y: top, width: W - 12 * u, height: 26 * u)
            button(bigR, colors[opts[0]] ?? .red, sel == 0, 0); label(opts[0], in: bigR, big, .white, shadow: shadow)
            let bw = (W - 12 * u - 6 * u) / 3, y2 = bigR.maxY + 5 * u
            for i in 1..<opts.count {
                let r = NSRect(x: 6 * u + CGFloat(i - 1) * (bw + 3 * u), y: y2, width: bw, height: bottom - y2)
                button(r, colors[opts[i]] ?? .gray, sel == i, i); label(opts[i], in: r, body, .white, shadow: shadow)
            }
        case .moves(let ms, let sel):                                                             // four type-coloured plates
            let gw = (W - 12 * u - 4 * u) / 2, gh = (bottom - top - 4 * u) / 2
            for (i, mv) in ms.enumerated() {
                let r = NSRect(x: 6 * u + CGFloat(i % 2) * (gw + 4 * u), y: top + CGFloat(i / 2) * (gh + 4 * u), width: gw, height: gh), c = typeColor[mv.type] ?? .gray
                button(r, c, i == sel, i)
                label(mv.name, in: NSRect(x: r.minX, y: r.minY + 1.5 * u, width: r.width, height: r.height * 0.52), body, .white, shadow: shadow)
                let tk = typeKo[mv.type] ?? mv.type, badge = NSRect(x: r.minX + 3 * u, y: r.maxY - 9.5 * u, width: width(tk, small) + 6 * u, height: 7.5 * u)
                round(badge, 3.5 * u).fill(with: NSColor(white: 0, alpha: 0.3)); label(tk, in: badge, small, .white)
                let e = (mv.effect == 0 ? "× " : mv.effect > 1 ? "▲ " : mv.effect < 1 ? "▼ " : "") + "PP \(mv.pp)/\(mv.maxPP)"
                label(e, in: NSRect(x: r.minX, y: badge.minY, width: r.width, height: badge.height), small,
                      mv.effect > 1 ? NSColor(red: 1, green: 0.95, blue: 0.5, alpha: 1) : .white, shadow: shadow, alignRight: 3 * u)
            }
        case .party(let ps, let sel):
            let rh = (bottom - top - 2 * 3 * u) / 3
            for (i, p) in ps.enumerated() {
                let r = NSRect(x: 6 * u, y: top + CGFloat(i) * (rh + 3 * u), width: W - 12 * u, height: rh)
                button(r, p.hp > 0 ? NSColor(red: 0.28, green: 0.56, blue: 0.80, alpha: 1) : NSColor(white: 0.45, alpha: 1), i == sel, i)
                let row = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - 4 * u)
                label((p.out ? "▶ " : "") + p.name + "  Lv\(p.level)" + (p.status.map { "  " + $0 } ?? ""), in: row, small, .white, shadow: shadow, alignLeft: 4 * u)
                label("\(p.hp)/\(p.max)", in: row, small, .white, shadow: shadow, alignRight: 4 * u)
                let br = NSRect(x: r.minX + 4 * u, y: r.maxY - 4.5 * u, width: r.width - 8 * u, height: 2 * u), f = p.max > 0 ? CGFloat(p.hp) / CGFloat(p.max) : 0
                ink.setFill(); br.fill(); hpColor(f).setFill(); NSRect(x: br.minX, y: br.minY, width: br.width * f, height: br.height).fill()
            }
        case .items(let names, let sel):                                                          // up to 5 rows, the pick kept in view
            let n = 5, rh = (bottom - top - CGFloat(n - 1) * 3 * u) / CGFloat(n), first = max(0, min(sel - 2, names.count - n))
            for (i, name) in names.enumerated() where i >= first && i < first + n {
                let r = NSRect(x: 6 * u, y: top + CGFloat(i - first) * (rh + 3 * u), width: W - 12 * u, height: rh)
                button(r, NSColor(red: 0.28, green: 0.70, blue: 0.36, alpha: 1), i == sel, i); label(name, in: r, small, .white, shadow: shadow, alignLeft: 4 * u)
            }
        case .ask(let yes):                                                                       // 아니오 / 예, side by side
            let half = (W - 12 * u - 4 * u) / 2
            for (i, (t, c)) in [("아니오", NSColor(red: 0.42, green: 0.47, blue: 0.58, alpha: 1)), ("예", NSColor(red: 0.90, green: 0.26, blue: 0.24, alpha: 1))].enumerated() {
                let r = NSRect(x: 6 * u + CGFloat(i) * (half + 4 * u), y: top, width: half, height: bottom - top)
                button(r, c, (i == 1) == yes, i); label(t, in: r, big, .white, shadow: shadow)
            }
        }
        window?.invalidateCursorRects(for: self)
    }
}
extension SideView {
    /// What the pane shows now (redrawn only when it changes).
    func show(_ m: SideModel?, dex d: DexModel?, shop sh: ShopModel?, menu mn: MenuModel?, status st: StatusModel?) {
        guard model != m || dex != d || shop != sh || menuPage != mn || status != st else { return }
        model = m; dex = d; shop = sh; menuPage = mn; status = st; needsDisplay = true
    }
    func paperBox(_ r: NSRect) {
        let u = u0; round(r.offsetBy(dx: 0, dy: u), 4 * u).fill(with: NSColor(white: 0, alpha: 0.35))
        let p = round(r, 4 * u); p.fill(with: NSColor(white: 0.98, alpha: 1)); SideView.ink.setStroke(); p.lineWidth = u; p.stroke()
    }
    /// 홈: where we are, the companion (Lv, EXP to next, V, nature), today's steps and W, then egg / tower / totals / dex.
    func drawStatus(_ s: StatusModel) {
        let u = u0, W = bounds.width, ink = SideView.ink, dim = SideView.dim, gold = NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)
        let head = NSRect(x: 0, y: 4 * u, width: W, height: 12 * u)
        label(s.place, in: head, body, .white, alignLeft: 8 * u); label(s.when, in: head, small, gold, alignRight: 8 * u)
        let card = NSRect(x: 6 * u, y: 19 * u, width: W - 12 * u, height: 48 * u); paperBox(card)
        let row = NSRect(x: card.minX, y: card.minY + 2 * u, width: card.width, height: 11 * u)
        label(s.name, in: row, body, ink, alignLeft: 5 * u); label(s.level, in: row, small, dim, alignRight: 5 * u)
        if s.v > 0 {                                                                               // nV: amber from 3V, like the menu
            let t = "\(s.v)V", w = width(t, small) + 7 * u
            let r = NSRect(x: card.maxX - 5 * u - width(s.level, small) - 3 * u - w, y: row.minY + 2 * u, width: w, height: 7.5 * u)
            round(r, 3.5 * u).fill(with: s.v >= 3 ? NSColor(red: 0.95, green: 0.66, blue: 0.16, alpha: 1) : NSColor(red: 0.42, green: 0.47, blue: 0.58, alpha: 1)); label(t, in: r, small, .white)
        }
        let tag = NSRect(x: card.minX + 5 * u, y: card.minY + 16 * u, width: 17 * u, height: 6.5 * u)
        round(tag, 2 * u).fill(with: ink); label("EXP", in: tag, .systemFont(ofSize: 4.8 * u, weight: .bold), NSColor(red: 0.45, green: 0.78, blue: 1, alpha: 1))
        let tr = NSRect(x: tag.maxX - u, y: tag.minY, width: card.maxX - 5 * u - tag.maxX + u, height: 6.5 * u)
        round(tr, 2 * u).fill(with: ink)
        let inner = tr.insetBy(dx: 1.5 * u, dy: 1.5 * u)
        NSColor(white: 0.30, alpha: 1).setFill(); inner.fill()
        NSColor(red: 0.25, green: 0.62, blue: 0.98, alpha: 1).setFill(); NSRect(x: inner.minX, y: inner.minY, width: inner.width * max(0, min(1, s.exp)), height: inner.height).fill()
        let r2 = NSRect(x: card.minX, y: card.minY + 24.5 * u, width: card.width, height: 9 * u)
        label("다음 레벨까지", in: r2, small, dim, alignLeft: 5 * u); label(s.toNext, in: r2, small, ink, alignRight: 5 * u)
        label(s.nature, in: NSRect(x: card.minX, y: card.minY + 35 * u, width: card.width, height: 9 * u), small, dim, alignLeft: 5 * u)
        let tw = (W - 12 * u - 4 * u) / 2
        for (i, (k, v)) in [("오늘 걸음", s.today), ("와트", s.watts)].enumerated() {
            let r = NSRect(x: 6 * u + CGFloat(i) * (tw + 4 * u), y: 72 * u, width: tw, height: 32 * u); paperBox(r)
            label(k, in: NSRect(x: r.minX, y: r.minY + 2.5 * u, width: r.width, height: 9 * u), small, dim, alignLeft: 5 * u)
            label(v, in: NSRect(x: r.minX, y: r.minY + 13 * u, width: r.width, height: 15 * u), big, ink, alignRight: 5 * u)
        }
        let box = NSRect(x: 6 * u, y: 109 * u, width: W - 12 * u, height: CGFloat(s.rows.count) * 17 * u + 4 * u); paperBox(box)
        for (j, rw) in s.rows.enumerated() {
            let r = NSRect(x: box.minX, y: box.minY + 2 * u + CGFloat(j) * 17 * u, width: box.width, height: 17 * u)
            if j > 0 { NSColor(white: 0, alpha: 0.08).setFill(); NSRect(x: r.minX + 4 * u, y: r.minY, width: r.width - 8 * u, height: 1).fill() }
            label(rw.key, in: r, small, dim, alignLeft: 5 * u); label(rw.value, in: r, body, ink, alignRight: 5 * u)
        }
    }
    /// 메뉴: the LCD's pages as a list, the one on the LCD highlighted; a click picks it, a click on the picked one opens it.
    func drawMenu(_ m: MenuModel) {
        let u = u0, W = bounds.width, H = bounds.height, ink = SideView.ink, dim = SideView.dim
        let head = NSRect(x: 0, y: 4 * u, width: W, height: 12 * u)
        label("메뉴", in: head, body, .white, alignLeft: 8 * u); label(m.money, in: head, body, NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1), alignRight: 8 * u)
        let list = NSRect(x: 6 * u, y: 19 * u, width: W - 12 * u, height: H - 19 * u - 6 * u)
        let lp = round(list, 4 * u); lp.fill(with: NSColor(white: 0.98, alpha: 1)); ink.setStroke(); lp.lineWidth = u; lp.stroke()
        let rh = (list.height - 4 * u) / CGFloat(max(1, m.rows.count))
        for (i, rw) in m.rows.enumerated() {
            let r = NSRect(x: list.minX + 2 * u, y: list.minY + 2 * u + CGFloat(i) * rh, width: list.width - 4 * u, height: rh), on = i == m.sel
            if on { round(r, 3 * u).fill(with: NSColor(red: 0.30, green: 0.56, blue: 0.86, alpha: 1)) }
            else if i > 0, i != m.sel + 1 { NSColor(white: 0, alpha: 0.07).setFill(); NSRect(x: r.minX + 3 * u, y: r.minY, width: r.width - 6 * u, height: 1).fill() }
            label("\(i + 1)", in: NSRect(x: r.minX, y: r.minY, width: 10.5 * u, height: r.height), small, on ? NSColor(white: 1, alpha: 0.8) : dim, alignRight: 0)
            label(rw.name, in: r, body, on ? .white : ink, alignLeft: 13 * u)
            label(rw.note, in: r, small, on ? NSColor(white: 1, alpha: 0.85) : dim, alignRight: 4 * u)
            hits.append((r, 3000 + i))
        }
        window?.invalidateCursorRects(for: self)
    }
    /// The shop page: the HGSS blue, a list (name, what it does, price, how many carried), then how many and 구매.
    func drawShop(_ s: ShopModel) {
        let u = paneUnit, W = bounds.width, H = bounds.height, ink = SideView.ink, dim = SideView.dim, paper = NSColor(white: 0.98, alpha: 1)
        let head = NSRect(x: 0, y: 4 * u, width: W, height: 12 * u)
        label(s.title, in: head, body, .white, alignLeft: 8 * u); label(s.money, in: head, body, NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1), alignRight: 8 * u)
        // the list: 6 rows, the pick kept in view
        let listR = NSRect(x: 6 * u, y: 19 * u, width: W - 12 * u, height: 6 * 17 * u + 4 * u), rows = 6
        round(listR, 4 * u).fill(with: paper); ink.setStroke(); let lp = round(listR, 4 * u); lp.lineWidth = u; lp.stroke()
        if s.title != shopTitle { shopTitle = s.title; shopTop = max(0, s.sel - 2) }             // a stable window: a click never scrolls the row under the pointer away
        if s.sel < shopTop { shopTop = s.sel } else if s.sel >= shopTop + rows { shopTop = s.sel - rows + 1 }
        shopTop = max(0, min(shopTop, s.rows.count - rows)); let first = shopTop
        for (i, r) in s.rows.enumerated() where i >= first && i < first + rows {
            let rr = NSRect(x: listR.minX + 2 * u, y: listR.minY + 2 * u + CGFloat(i - first) * 17 * u, width: listR.width - 4 * u, height: 17 * u)
            if i == s.sel { round(rr, 3 * u).fill(with: NSColor(red: 0.30, green: 0.56, blue: 0.86, alpha: 1)) }
            let fg = i == s.sel ? NSColor.white : r.can ? ink : dim, fg2 = i == s.sel ? NSColor(white: 1, alpha: 0.85) : dim
            label(r.name, in: NSRect(x: rr.minX, y: rr.minY + 1 * u, width: rr.width, height: 9 * u), body, fg, alignLeft: 3 * u)
            label(r.price, in: NSRect(x: rr.minX, y: rr.minY + 1 * u, width: rr.width, height: 9 * u), small, fg, alignRight: 3 * u)
            label(r.note, in: NSRect(x: rr.minX, y: rr.minY + 9.5 * u, width: rr.width, height: 7 * u), small, fg2, alignLeft: 3 * u)
            if !r.once { label("보유 \(r.owned)", in: NSRect(x: rr.minX, y: rr.minY + 9.5 * u, width: rr.width, height: 7 * u), small, fg2, alignRight: 3 * u) }
            hits.append((rr, 2100 + i))
        }
        if s.rows.count > rows {                                                                    // where in the list: a thin bar on the right
            let track = NSRect(x: listR.maxX - 2 * u, y: listR.minY + 3 * u, width: 1.2 * u, height: listR.height - 6 * u)
            NSColor(white: 0, alpha: 0.12).setFill(); track.fill()
            let h = track.height * CGFloat(rows) / CGFloat(s.rows.count), y = track.minY + (track.height - h) * CGFloat(first) / CGFloat(s.rows.count - rows)
            NSColor(white: 0, alpha: 0.35).setFill(); NSRect(x: track.minX, y: y, width: track.width, height: h).fill()
        }
        // how many, then 구매
        let box = NSRect(x: 6 * u, y: listR.maxY + 4 * u, width: W - 12 * u, height: H - listR.maxY - 11 * u)
        round(box, 4 * u).fill(with: paper); ink.setStroke(); let bp = round(box, 4 * u); bp.lineWidth = u; bp.stroke()
        func button(_ r: NSRect, _ t: String, _ c: NSColor, _ code: Int, _ on: Bool = true) {
            round(r, 3 * u).fill(with: on ? c : NSColor(white: 0.8, alpha: 1)); label(t, in: r, small, .white); if on { hits.append((r, code)) }
        }
        if let yes = s.ask, let r = s.rows[safe: s.sel] {                                          // 정말? for a once-only row
            label("\(r.name) · \(s.total)", in: NSRect(x: box.minX, y: box.minY + 4 * u, width: box.width, height: 9 * u), body, ink)
            label("정말 살까요? 한 번만 살 수 있어요 (남음 \(s.after))", in: NSRect(x: box.minX, y: box.minY + 14 * u, width: box.width, height: 8 * u), small, dim)
            let half = (box.width - 13 * u) / 2, by = box.minY + 25 * u, h = box.maxY - by - 4 * u
            for (k, (t, c, code)) in [("아니오", NSColor(red: 0.42, green: 0.47, blue: 0.58, alpha: 1), 2007), ("예", NSColor(red: 0.90, green: 0.26, blue: 0.24, alpha: 1), 2006)].enumerated() {
                let br = NSRect(x: box.minX + 5 * u + CGFloat(k) * (half + 3 * u), y: by, width: half, height: h)
                button(br, t, c, code)
                if (k == 1) == yes { NSColor.white.setStroke(); let o = round(br.insetBy(dx: u, dy: u), 3 * u); o.lineWidth = u; o.stroke() }
            }
            window?.invalidateCursorRects(for: self); return
        }
        guard let q = s.qty else { label(s.hint, in: box, small, dim); window?.invalidateCursorRects(for: self); return }
        let bw = (box.width - 10 * u - 4 * 2 * u - 22 * u) / 4, by = box.minY + 4 * u, grey = NSColor(red: 0.42, green: 0.47, blue: 0.58, alpha: 1)
        var x = box.minX + 5 * u
        for (t, code, on) in [("−10", 2000, q > 1), ("−1", 2001, q > 1)] { button(NSRect(x: x, y: by, width: bw, height: 10 * u), t, grey, code, on); x += bw + 2 * u }
        label("× \(q)", in: NSRect(x: x, y: by, width: 22 * u, height: 10 * u), body, ink); x += 22 * u + 2 * u
        for (t, code, on) in [("+1", 2002, q < s.most), ("+10", 2003, q < s.most)] { button(NSRect(x: x, y: by, width: bw, height: 10 * u), t, grey, code, on); x += bw + 2 * u }
        label("\(s.total) → 남음 \(s.after)", in: NSRect(x: box.minX, y: by + 12 * u, width: box.width, height: 8 * u), small, dim, alignLeft: 5 * u)
        button(NSRect(x: box.maxX - 5 * u - 20 * u, y: by + 12 * u, width: 20 * u, height: 8 * u), "최대 \(s.most)", grey, 2004, q < s.most)
        let buy = NSRect(x: box.minX + 5 * u, y: by + 22 * u, width: box.width - 10 * u, height: box.maxY - by - 26 * u)
        button(buy, "구매", NSColor(red: 0.90, green: 0.26, blue: 0.24, alpha: 1), 2005)
        window?.invalidateCursorRects(for: self)
    }
    /// The Pokédex page: a red handheld-dex body, a white entry card (types, base stats), where to find it, how it evolves, and a number strip.
    func drawDex(_ d: DexModel) {
        let u = paneUnit, W = bounds.width, ink = SideView.ink, dim = SideView.dim, red = NSColor(red: 0.80, green: 0.20, blue: 0.18, alpha: 1)
        let red0 = NSRect(x: 2 * u, y: 2 * u, width: W - 4 * u, height: bounds.height - 5 * u), bodyPath = round(red0, 8 * u)   // inside the pane's navy, off the deck
        NSGraphicsContext.saveGraphicsState(); bodyPath.addClip()
        NSGradient(starting: NSColor(red: 0.90, green: 0.24, blue: 0.22, alpha: 1), ending: NSColor(red: 0.66, green: 0.12, blue: 0.13, alpha: 1))!.draw(in: red0, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        ink.setStroke(); bodyPath.lineWidth = 1.2; bodyPath.stroke()
        round(NSRect(x: 6 * u, y: 5 * u, width: 10 * u, height: 10 * u), 5 * u).fill(with: .white)                  // the blue lens
        round(NSRect(x: 7.5 * u, y: 6.5 * u, width: 7 * u, height: 7 * u), 3.5 * u).fill(with: NSColor(red: 0.30, green: 0.62, blue: 0.95, alpha: 1))
        let head = NSRect(x: 0, y: 4 * u, width: W, height: 12 * u)
        label("도감", in: head, body, .white, alignLeft: 19 * u)
        label("잡음 \(d.owned) · 봤음 \(d.seen)", in: head, small, NSColor(white: 1, alpha: 0.9), alignRight: 7 * u)
        func panel(_ r: NSRect) { let p = round(r, 4 * u); p.fill(with: NSColor(white: 0.98, alpha: 1)); ink.setStroke(); p.lineWidth = u; p.stroke() }
        // entry card
        let card = NSRect(x: 5 * u, y: 19 * u, width: W - 10 * u, height: 76 * u)
        panel(card)
        let title = NSRect(x: card.minX, y: card.minY + 2 * u, width: card.width, height: 11 * u)
        label(String(format: "No.%03d  ", d.num) + d.name, in: title, body, d.status > 0 ? ink : dim, alignLeft: 5 * u)
        if d.status > 0 {
            let tag = d.status == 2 ? (d.shiny ? "★ 이로치" : "잡음") : "봤음", tw = width(tag, small) + 8 * u
            let tr = NSRect(x: card.maxX - 5 * u - tw, y: title.minY + 1.5 * u, width: tw, height: 8 * u)
            round(tr, 4 * u).fill(with: d.status == 2 ? NSColor(red: 0.90, green: 0.26, blue: 0.24, alpha: 1) : dim); label(tag, in: tr, small, .white)
            var x = card.minX + 5 * u
            for ty in d.types {
                let str = typeKo[ty] ?? ty, r = NSRect(x: x, y: card.minY + 15 * u, width: width(str, small) + 9 * u, height: 8.5 * u)
                round(r, 2.5 * u).fill(with: typeColor[ty] ?? .gray); label(str, in: r, small, .white); x += r.width + 3 * u
            }
            for (j, (name, v)) in zip(["HP", "공격", "방어", "특공", "특방", "스피드"], d.stats).enumerated() {
                let row = NSRect(x: card.minX, y: card.minY + 26 * u + CGFloat(j) * 8 * u, width: card.width, height: 8 * u)
                label(name, in: row, small, dim, alignLeft: 5 * u)
                label("\(v)", in: row, small, ink, alignRight: 5 * u)
                let bx = card.minX + 29 * u, bw = card.width - 29 * u - 20 * u, br = NSRect(x: bx, y: row.midY - 1.75 * u, width: bw, height: 3.5 * u)
                round(br, 1.75 * u).fill(with: NSColor(white: 0.88, alpha: 1))
                let c = v >= 100 ? NSColor(red: 0.28, green: 0.72, blue: 0.40, alpha: 1) : v >= 60 ? NSColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 1) : NSColor(red: 0.90, green: 0.36, blue: 0.30, alpha: 1)
                round(NSRect(x: bx, y: br.minY, width: bw * CGFloat(min(v, 180)) / 180, height: br.height), 1.75 * u).fill(with: c)
            }
        } else { label("아직 만나지 못했다", in: card, body, dim) }
        // where + evolutions
        let info = NSRect(x: 5 * u, y: 99 * u, width: W - 10 * u, height: 66 * u)
        panel(info)
        if d.status > 0 {
            func line(_ str: String, _ j: CGFloat, _ c: NSColor, _ f: NSFont) { label(str, in: NSRect(x: info.minX, y: info.minY + 2 * u + j * 8.5 * u, width: info.width - 5 * u, height: 8.5 * u), f, c, alignLeft: 5 * u) }
            line("만나는 곳", 0, red, small)
            for (j, str) in (d.found.isEmpty ? ["알 수 없음"] : d.found).enumerated() { line("· " + fit(str, info.width - 14 * u), CGFloat(1 + j), ink, small) }
            line("진화", 4, red, small)
            for (j, str) in (d.evos.isEmpty ? ["더 이상 진화하지 않는다"] : d.evos).enumerated() { line(fit(str, info.width - 10 * u), CGFloat(5 + j), d.evos.isEmpty ? dim : ink, small) }
        }
        // number strip: white = caught, pale = seen, dark = not met; click a met one to go there
        let cw = (W - 10 * u) / 10
        for (j, (n, st)) in zip(d.strip, d.stripStatus).enumerated() {
            let r = NSRect(x: 5 * u + CGFloat(j) * cw, y: 169 * u, width: cw - 1.5 * u, height: 12 * u)
            round(r, 2.5 * u).fill(with: st == 2 ? NSColor.white : st == 1 ? NSColor(white: 1, alpha: 0.55) : NSColor(white: 0, alpha: 0.2))
            if n == d.num { let p = round(r, 2.5 * u); NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 1).setStroke(); p.lineWidth = 1.5 * u; p.stroke() }
            label("\(n)", in: r, small, st == 0 ? NSColor(white: 1, alpha: 0.7) : n == d.num ? red : ink)
            if st > 0 { hits.append((r, 1000 + n)) }
        }
        window?.invalidateCursorRects(for: self)
    }
    func fit(_ str: String, _ w: CGFloat) -> String { var x = str; while x.count > 1, width(x, small) > w { x = String(x.dropLast(2)) + "…" }; return x }
}
extension NSBezierPath { func fill(with c: NSColor) { c.setFill(); fill() } }
