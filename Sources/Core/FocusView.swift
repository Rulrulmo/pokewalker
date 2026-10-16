import Foundation
// 5.0 (the user: "상점 같은것들 … 상단 패널이랑 하단 패널이 결국 보여주는 정보가 같잖아?"): the list pages' LCD as the 도감's — the one picked,
// big (its picture on the stage, its name, its price or count, what it does, n/N), the list itself on the panel below (its tabs, rows, buttons,
// the long words). ◀ ▶ still go through it and ● still takes it: nothing needs the panel. 상점 · BP 교환소, 가방, 기술 (배우기 · 바꾸기 ·
// 떠올리기), 로토무의 모습 · 합체, 도구 주기, 우편's items (the user: "ㅇㅇ 훨씬 보기 좋다"). lcdFocus off (the shots' LCD_FOCUS=0): the old lists.

@MainActor var lcdFocus = true

extension FB {
    /// The page's thing on show (an item's picture, a device colour's): left of its words at the old box's middle; a dressed page moves it to its
    /// stage, bigger (LCDDeco).
    mutating func focusPic(_ key: String, _ make: () -> Pic) { pic("focus|" + key, 34, 66, scale: 1.5, make) }
    /// Words wrapped to w dots (small), at most `lines` rows from (x, y) 9 apart, the last cut with …; the rows used.
    @discardableResult mutating func wrap(_ s: String, _ x: Int, _ y: Int, _ w: Int, lines: Int, _ shade: UInt8 = 2) -> Int {
        let rows = FB.rows(s, w, lines)
        for (k, r) in rows.enumerated() { text(r, x, y + 9 * k, shade, small: true) }
        return rows.count
    }
    /// Words in rows of w dots (small), at most `lines` (5.0: never a … where it can help it) — a list (a · b · c) its parts whole, a part's
    /// words whole (a short word kept with the next: 한 번, 1/10); too many rows: the last parts dropped whole; one part still too long: its last words
    /// dropped; only a single word wider than a row is cut (…, and the renders hear of it).
    @MainActor static func rows(_ s: String, _ w: Int, _ lines: Int) -> [String] {
        func fits(_ t: String) -> Bool { textWidth(t, small: true) <= w }
        func words(_ part: String) -> [String] {                                                  // a one-letter word goes with the next (한 번, 때 한 번); 라티아스·라티오스 may break after its ·
            var out: [String] = [], carry = ""
            for raw in part.split(separator: " ").map(String.init) {
                let pieces = raw.contains("·") ? raw.split(separator: "·", omittingEmptySubsequences: false).enumerated().map { $0.offset < raw.split(separator: "·", omittingEmptySubsequences: false).count - 1 ? $0.element + "·" : String($0.element) } : [raw]
                for (k, wd) in pieces.enumerated() {
                    let t = carry.isEmpty ? wd : carry + (k == 0 ? " " : "") + wd
                    if wd.count <= 1 || wd.hasSuffix("·") && k < pieces.count - 1 && wd.count <= 2 { carry = t; continue }
                    out.append(t); carry = ""
                }
            }
            if !carry.isEmpty { out.append(carry) }
            return out
        }
        func lay(_ parts: [String]) -> [String] {
            var rows: [String] = [], cur = ""
            for (i, part) in parts.enumerated() {
                let joined = cur.isEmpty ? part : cur + " · " + part
                if fits(joined) { cur = joined; continue }
                if !cur.isEmpty { rows.append(cur + (i < parts.count ? " ·" : "")); cur = "" }
                if fits(part) { cur = part; continue }
                for wd in words(part) {                                                           // a part longer than a row: its words
                    let t = cur.isEmpty ? wd : cur + (cur.hasSuffix("·") ? "" : " ") + wd
                    if fits(t) { cur = t } else { if !cur.isEmpty { rows.append(cur) }; cur = wd }
                }
            }
            if !cur.isEmpty { rows.append(cur) }
            return rows.map { $0.hasSuffix(" ·") && !fits($0) ? String($0.dropLast(2)) : $0 }
        }
        var parts = s.components(separatedBy: " · ").filter { !$0.isEmpty }
        var rows = lay(parts)
        while rows.count > lines, parts.count > 1 { parts.removeLast(); rows = lay(parts) }     // the last parts go, whole
        if rows.count > lines, var p = parts.first {                                             // one part, too long: its last words go
            var ws = words(p)
            while rows.count > lines, ws.count > 1 { ws.removeLast(); p = ws.reduce("") { $0.isEmpty ? $1 : $0 + ($0.hasSuffix("·") ? "" : " ") + $1 }; rows = lay([p]) }
        }
        if rows.count > lines { rows = Array(rows.prefix(lines)) }
        rows = rows.map { r in
            guard !fits(r) else { return r }                                                     // a word wider than the row: cut, said
            var t = r; while t.count > 1, !fits(t + "…") { t.removeLast() }; cutTexts?.append("LCD " + r); return t + "…"
        }
        if let last = rows.last, last.hasSuffix(" ·") { rows[rows.count - 1] = String(last.dropLast(2)) }
        return rows
    }
    /// A name: as is where it fits w dots, else small, else cut (…): measured with this machine's font, never past w.
    mutating func name(_ s: String, _ x: Int, _ y: Int, _ w: Int, _ shade: UInt8 = 3) {
        if textWidth(s) <= w { text(s, x, y, shade) } else if textWidth(s, small: true) <= w { text(s, x, y, shade, small: true) } else { line(s, x, y, w, shade) }
    }
    /// One row of words in w dots (small), cut with … if this machine's font makes it wider (a narrow column's words: never past its edge).
    mutating func line(_ s: String, _ x: Int, _ y: Int, _ w: Int, _ shade: UInt8 = 2) { wrap(s, x, y, w, lines: 1, shade) }
}

extension Walker {
    /// 상점 · BP 교환소: the ware picked — its picture (an item's, a device colour's, a legend: itself), name, price and how many are had, what it
    /// does, n/N.
    func shopFocusLCD(_ fb: inout FB, _ bp: Bool, _ sel: Int) {
        let ws = wares(bp), unit = bp ? "BP" : "W"
        guard let w = ws[safe: min(sel, ws.count - 1)] else { fb.text("팔 것이 없다", 0, 30, 2, center: true); return }
        let can = state.canBuy(w, bp: bp) > 0, had = w.once && state.owned(w) > 0, x = 44
        switch w.kind {
        case .item(let i): fb.focusPic("item|" + i) { itemPic(i) }
        case .shell(let s): fb.focusPic("shell|" + s) { shellPic(s) }
        case .legend(let k): fb.mon(Mon(dex: Walk.legendShop[k].dex, level: Walk.legendShop[k].level, female: false), 0, 0, 2)
        }
        fb.name(state.wareName(w).replacingOccurrences(of: " (전설)", with: "").replacingOccurrences(of: " (기기 색)", with: ""), x, 13, 94 - x, can ? 3 : 1)
        fb.line(had ? "보유" : "\(w.price)\(unit)", x, 25, 94 - x - (!had && state.owned(w) > 0 ? textWidth("보유 \(state.owned(w))", small: true) + 3 : 0), can ? 3 : 1)
        if !had, state.owned(w) > 0 { fb.text("보유 \(state.owned(w))", 94, 25, 2, right: true, small: true) }
        fb.wrap(state.wareNote(w).replacingOccurrences(of: "지니게 하기: ", with: "지니면 "), x, 35, 94 - x, lines: 2)
        fb.text("\(min(sel, ws.count - 1) + 1)/\(ws.count)", 94, 53, 1, right: true, small: true)
    }
    /// 가방: the item picked — its picture, name, how many (and on the walker), what it does, n/N.
    func itemsFocusLCD(_ fb: inout FB, _ sel: Int) {
        let rows = state.inventory, x = 44
        guard let n = rows[safe: min(sel, rows.count - 1)] else { fb.text("없음", 0, 30, 2, center: true); return }
        fb.focusPic("item|" + n) { itemPic(n) }
        fb.name(n, x, 13, 94 - x)
        fb.line("×\(state.count(n))" + (state.items.contains(n) ? " · 워커 \(state.items.filter { $0 == n }.count)" : ""), x, 25, 94 - x)
        fb.wrap(ItemKind.of(n).summary.replacingOccurrences(of: "지니게 하기: ", with: "지니면 "), x, 35, 94 - x, lines: 2)
        fb.text("\(min(sel, rows.count - 1) + 1)/\(rows.count)", 94, 53, 1, right: true, small: true)
    }
    /// A move on show (기술 배우기's slot to forget, 기술 바꾸기's slot, 떠올리기's pick): its name, its type on a pill, power · accuracy · PP, what
    /// it does (two rows); `foot` on the last row's left, n/N on its right.
    func moveFocusLCD(_ fb: inout FB, _ id: Int, foot: String, _ n: Int, _ of: Int) {
        guard let mv = moveTable[id] else { return }
        let type = typeKo[mv.type] ?? mv.type, tw = textWidth(type, small: true), c = fxTones[mv.type]?[2] ?? rgb(200, 200, 210)
        fb.name(mv.name, 2, 13, 90 - tw - 8)
        fb.pic("pill|type|\(mv.type)", 94 * 2 - tw - 4, 2 * 13 + 11, under: true) { lcdReady(typePill(c, 2 * tw + 8)) }
        fb.text(type, 94 - tw - 2, 14, 3, small: true)
        let kind = ["물리", "특수", "변화"][safe: mv.kind] ?? ""
        fb.line([kind, mv.power > 0 ? "위력 \(mv.power)" : nil, mv.accuracy > 0 ? "명중 \(mv.accuracy)" : "반드시 명중", "PP \(mv.pp)"].compactMap { $0 }.joined(separator: " · "), 2, 25, 92)
        fb.wrap(moveText(id) ?? "", 2, 34, 92, lines: 2)
        let nw = fb.text("\(n)/\(of)", 94, 53, 1, right: true, small: true); fb.line(foot, 2, 53, 92 - nw - 3)
    }
    /// 도구 주기: the row picked — its item (or the one held, to take off) on the stage, its name, what it does, what's held now, n/N; the
    /// Pokémon's name by the title.
    func holdFocusLCD(_ fb: inout FB, _ m: Mon, _ ref: Int, _ sel: Int) {
        let rows = holdRows(ref), x = 44
        fb.text("도구 주기", 2, 0); fb.text(monNames[m.dex], 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
        guard let r = rows[safe: min(sel, max(0, rows.count - 1))] else { fb.text("줄 도구가 없다", 0, 30, 2, center: true); return }
        let item = r.take ? m.item ?? r.name : r.name
        fb.focusPic("item|" + item) { itemPic(item) }
        fb.name(r.take ? "빼기" : r.name, x, 13, 94 - x, r.why == nil ? 3 : 1)
        fb.wrap(r.take ? josa(item, "을", "를") + " 가방으로" : r.why ?? ItemKind.of(r.name).summary.replacingOccurrences(of: "지니게 하기: ", with: "지니면 "), x, 25, 94 - x, lines: 2, r.why == nil ? 2 : 1)
        fb.line("지금 " + (m.item ?? "없음"), x, 44, 94 - x, 1)
        fb.text("\(min(sel, rows.count - 1) + 1)/\(rows.count)", 94, 53, 1, right: true, small: true)
    }
    /// 로토무의 모습 · 합체: the form the pick would make (its picture on the stage), its name, what comes with it, why not, n/N.
    func formFocusLCD(_ fb: inout FB, _ m: Mon, _ o: [FormOption], _ sel: Int) {
        guard let x = o[safe: min(sel, o.count - 1)] else { return }
        var after = m; after.fused = nil
        switch x.op { case .rotom(_, let f)?: after.form = f; case .fuse?: after.form = x.dex == 643 ? 2 : 1; case .unfuse?: after.form = nil; default: break }
        fb.mon(after, 0, 0, 2)
        let label = x.op.map { if case .fuse = $0 { Forms.of(646, after.form)?.name ?? x.label } else if case .unfuse = $0 { monNames[646] } else { x.label } } ?? x.label
        fb.name(label, 50, 13, 44, x.why == nil ? 3 : 1)
        fb.wrap(x.op.map { if case .fuse = $0 { "+ " + x.label } else { x.note } } ?? x.note, 50, 26, 44, lines: 2)
        if let why = x.why { fb.wrap(why, 50, 44, 44, lines: 1, 1) }
        fb.text("\(min(sel, o.count - 1) + 1)/\(o.count)", 94, 53, 1, right: true, small: true)
    }
}

/// A type's pill (w x 18 half-dots): its colour, light, round ends.
func typePill(_ c: UInt32, _ w: Int) -> Pic {
    var p = Pic(w: w, h: 18)
    for y in 0..<18 { for x in 0..<w {
        let edge: Int = min(x, w - 1 - x), dx: Double = edge < 9 ? Double(9 - edge) : 0, dy: Double = Double(y) - 8.5
        if hypot(dx, dy) < 9 { p.px[y * w + x] = lerpRGB(c, rgb(255, 255, 255), y < 4 ? 0.55 : 0.4) }
    } }
    return p
}
/// A device colour on show: a small walker in that shell's top and band (40 x 34).
@MainActor func shellPic(_ name: String) -> Pic {
    guard let s = shells.first(where: { $0.name == name }) else { return Pic(w: 1, h: 1) }
    func u(_ c: Color) -> UInt32 { rgb(UInt8(c.red * 255), UInt8(c.green * 255), UInt8(c.blue * 255)) }
    var p = Pic(w: 40, h: 34)
    for y in 0..<34 { for x in 0..<40 {
        let dx = min(x, 39 - x), dy = min(y, 33 - y)
        if dx < 5, dy < 5, hypot(Double(5 - dx), Double(5 - dy)) > 5.3 { continue }
        p.px[y * 40 + x] = dx == 0 || dy == 0 ? rgb(40, 44, 52) : y < 15 ? u(s.top) : y < 19 ? u(s.band) : rgb(250, 250, 250)
    } }
    p.fill(8, 4, 24, 9, rgb(150, 170, 140)); p.fill(9, 5, 22, 7, rgb(196, 210, 180))                   // its LCD
    for (cx, r) in [(12, 3), (20, 4), (28, 3)] { for y in -r...r { for x in -r...r {                   // its keys
        let d: Int = x * x + y * y
        if d <= r * r { p.set(cx + x, 25 + y, d >= (r - 1) * (r - 1) ? rgb(40, 44, 52) : rgb(255, 255, 255)) }
    } } }
    return p
}

/// Self-test checks for this file (run by selftest()): every item sold (W, BP) and every Mega stone has a picture of its own; the focus pages'
/// things clear of their words, band and panel, nothing past the LCD's edge.
@MainActor func focusChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let sold = (Walk().wares(bp: false, shells: []) + Walk().wares(bp: true, shells: Engine.bpShells)).compactMap { if case .item(let i) = $0.kind { i } else { nil } }
    let bare = Set(sold + Forms.stones).filter { !itemPacked($0) && !$0.hasSuffix("민트") && !["로토무카탈로그", "순백떡", "특성패치"].contains($0) }.sorted()
    c.append((bare.isEmpty, "5.0 focus: every item sold and every Mega stone has its own picture (items.bin; the mints, 로토무카탈로그, 순백떡 and 5.1's 특성패치 drawn)" + (bare.isEmpty ? "" : " — none: \(bare)")))
    let was = (lcdFocus, lcdDeco, lcdStyle); lcdFocus = true; lcdDeco = true; lcdStyle = 0
    defer { lcdFocus = was.0; lcdDeco = was.1; lcdStyle = was.2 }
    var st = Walk(); st.watts = 99_999; st.bp = 9_999; st.bag = ["구애머리띠", "이상한사탕", "오랭열매"]
    let w = Walker(state: st); w.persist = false
    var bad: [String] = []
    for k in [1.0, 1.15] {                                                                        // (and as if a font 15 % wider: another OS's)
        textWidthScale = k; defer { textWidthScale = 1 }
        for s in [Screen.shop(bp: false, sel: 0, qty: nil), .shop(bp: true, sel: 3, qty: nil), .shop(bp: true, sel: 16, qty: nil), .items(0), .items(2)] {
            w.screen = s; let fb = w.compose(Date())
            bad += lcdOverlaps(fb) + fb.runs.filter { $0.x < 0 || $0.x + $0.w > 96 }.map { "past the edge ×\(k): \($0.s)" } + runClashes(fb.runs)
            if !fb.pics.contains(where: { $0.key.hasPrefix("focus|") }) { bad.append("no picture: \(s)") }
        }
    }
    c.append((bad.isEmpty, "5.0 focus: the shop's and the bag's thing on its stage, clear of the words and panel, nothing past the edge" + (bad.isEmpty ? "" : " — \(bad.prefix(5))")))
    return c
}
