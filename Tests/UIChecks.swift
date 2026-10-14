import Foundation
// 5.0 (the user's look at the 5.0 candidate): the side panel's words where they should be — a canvas that keeps what's written, and checks on it.

/// A canvas that draws nothing and keeps each line of text with where it went.
@MainActor final class TextCanvas: Canvas {
    var said: [(s: String, at: CGPoint)] = []
    var scale: CGFloat { 2 }
    func fill(_ r: CGRect, _ c: Color) {}
    func fill(_ p: Path, _ c: Color) {}
    func stroke(_ p: Path, _ c: Color, width: CGFloat, round: Bool) {}
    func clip(_ p: Path) {}
    func save() {}
    func restore() {}
    func antialias(_ on: Bool) {}
    func rotate(_ degrees: CGFloat, about c: CGPoint) {}
    func image(_ b: Bitmap, _ r: CGRect, alpha: CGFloat) {}
    func text(_ s: String, _ p: CGPoint, _ f: FontSpec, _ c: Color) { said.append((s, p)) }
    func gradient(_ r: CGRect, from: Color, to: Color, angle: CGFloat) {}
    func beginLayer(alpha: CGFloat) {}
    func endLayer() {}
    func glyph(_ g: Glyph, _ at: CGPoint, _ size: CGFloat, _ c: Color, alpha: CGFloat) {}
}

/// ② The panel's buttons that do nothing: each one drawn on a fresh walker's page, clicked (Walker.paneTap) — no change to the screen, the
/// panel or the save is a dead one (skip: the codes that rightly do nothing there, the pick already picked).
@MainActor func deadHits(_ make: () -> Walker, skip: Set<Int> = []) -> [Int] {
    func look(_ w: Walker) -> String { "\(w.screen)|\(w.paneContent(Date()))|\(w.state.bag)|\(w.state.box.map { "\($0.dex).\($0.form ?? 0)" })|\(w.waiting != nil)|\(w.megaOn)" }
    let w0 = make(); w0.refreshPane(Date(), force: true)
    let page = Page(); page.walker = w0; page.draw(on: TextCanvas())
    return Set(page.hits.map(\.1)).subtracting(skip).sorted().filter { k in
        let w = make(); w.refreshPane(Date(), force: true); let before = look(w)
        w.calmAt = .distantPast; w.paneTap(k); return look(w) == before
    }
}

/// Self-test checks (run by selftest()).
@MainActor func uiChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    // a mail's pick of items (the user: 민트 21개가 스크롤도 안 되고 버튼과 겹쳐요): in pages, the pick's row always in view, no row under the
    // button or past the panel, a short list on one page
    do {
        var bad: [String] = []
        for (count, sel) in [(21, 0), (21, 8), (21, 20), (5, 4), (7, 6), (8, 7)] {
            let w = Walker(state: Walk()); w.persist = false
            let rows = (0..<count).map { MailPickModel.Row(name: Walk.mints[safe: $0] ?? "민트", note: "공격 ↑ · 방어 ↓ 성격으로") }
            w.pane = PaneContent(mailPick: MailPickModel(title: "민트 고르기", note: "하나만 받을 수 있어요", rows: rows, cells: [], sel: sel, first: 0, count: count, go: "받기", ask: nil))
            let page = Page(); page.walker = w; page.draw(on: TextCanvas())
            let drawn = page.hits.filter { (8850..<8880).contains($0.1) }, button = page.hits.first { $0.1 == 8890 }?.0, per = MailPickModel.per(count, legend: false)
            let bottom = (w.pane.height - Layout.pane) * K
            if let b = button, drawn.contains(where: { $0.0.intersects(b) }) { bad.append("\(count)/\(sel): a row under the button") }
            if drawn.contains(where: { $0.0.maxY > bottom }) { bad.append("\(count)/\(sel): a row past the panel") }
            if !drawn.contains(where: { $0.1 - 8850 == sel % per }) || drawn.count != min(per, count - sel / per * per) { bad.append("\(count)/\(sel): the pick's row not in view") }
            if (count > per) != page.hits.contains(where: { $0.1 == 8881 }) { bad.append("\(count)/\(sel): pages") }
        }
        c.append((bad.isEmpty, "5.0 a mail's pick of items: pages of 6 past 7 (21 mints), the pick's row in view, none under the button or past the panel" + (bad.isEmpty ? "" : " — \(bad)")))
    }
    // the panel's ease (UXView.swift): 홈's quick buttons and rows, the box's pick's buttons, the shop's 최대 — each does something; the
    // 메뉴 key back on the tile last used
    do {
        var st = Walk(); st.box = [Mon(dex: 16, level: 5, female: false)]; st.watts = 5000; st.bag = ["상처약"]
        @MainActor func walker(_ s: Screen) -> () -> Walker { { let w = Walker(state: st); w.persist = false; w.screen = s; return w } }
        let dead = [("홈", deadHits(walker(.home))), ("상자", deadHits(walker(.box(0, act: nil, confirm: false)), skip: [4100])), ("상점 수량", deadHits(walker(.shop(bp: false, sel: 0, qty: 1)), skip: [2008, 2100]))]   // (the tab it's on; the row picked)
            .filter { !$0.1.isEmpty }
        let w = Walker(state: st); w.persist = false; w.screen = .home; w.open("배틀 타워"); w.screen = .home; w.calmAt = .distantPast; w.press(4)
        let back: Bool = { if case .menu(nil, let sel) = w.screen { return menuTiles[sel].items.contains("배틀 타워") }; return false }()
        c.append((dead.isEmpty && back, "5.0 the panel's ease: 홈's quick buttons and rows, the box's pick's buttons, the shop's 최대 all do something; the 메뉴 key comes back on the tile last used" + (dead.isEmpty ? "" : " — dead: \(dead)")))
    }
    let hud = hudOverlaps()                                                                       // (the user: "겹침은 해결해주고")
    c.append((hud.isEmpty, "5.0 a fight's HP boxes clear of every picture: theirs front-on with each animation frame (in its stage), ours from behind (\(spriteCount) pictures)" + (hud.isEmpty ? "" : " — \(hud.prefix(6))")))
    Content.$testing.withValue(true) {
        var r = Seeded(s: 4), zard = Mon.wild(6, level: 60, &r); zard.item = "리자몽나이트X"; zard.known = [53, 19, 337, 89]
        let b = Battle(wild: Mon.wild(214, level: 60, &r), companion: zard)
        let w = Walker(state: { var s = Walk(); s.companion = zard; return s }()); w.persist = false; w.fight = b
        @MainActor func words(_ on: Bool) -> [(s: String, at: CGPoint)] {
            w.megaOn = on; w.screen = .moves(b, sel: 0); w.refreshPane(Date(), force: true)
            let page = Page(); page.walker = w; let k = TextCanvas(); page.draw(on: k); return k.said
        }
        let off = words(false), on = words(true)
        let place = { (l: [(s: String, at: CGPoint)], s: String) in l.first { $0.s == s }?.at }
        let same = ["메가", "진화"].allSatisfy { s in place(off, s) != nil && place(off, s) == place(on, s) }
        let centred = place(on, "메가").map { m in place(on, "진화").map { abs((m.x + width("메가", font(10.5, .bold)) / 2) - ($0.x + width("진화", font(10.5, .bold)) / 2)) < 0.5 } ?? false } ?? false
        c.append((same && centred && on.contains { $0.s == "✓" } && !off.contains { $0.s == "✓" },
                  "5.0 the moves' 메가 / 진화: the same two lines, centred, ticked or not; ticked: a ✓ badge (the user: 글자 정렬 안맞음)"))
    }
    // ① a form straight from its page: 로토무 + 로토무카탈로그 → 모습 바꾸기 (the pane's link, the ● menu's 모습); 큐레무 + 유전자쐐기 → 합체; none without the item
    Content.$testing.withValue(true) {
        var r = Seeded(s: 5)
        let w = Walker(state: { var s = Walk(); s.companion = Mon.wild(479, level: 30, &r); s.box = [Mon.wild(646, level: 60, &r), Mon.wild(643, level: 60, &r)]; s.bag = ["로토무카탈로그", "유전자쐐기"]; return s }())
        w.persist = false
        @MainActor func formPage() -> (ref: Int, item: String)? { if case .formPick(let r, let i, _) = w.screen { return (r, i) }; return nil }
        w.screen = .box(-1, act: nil, confirm: false, detail: true); w.refreshPane(Date(), force: true)
        let link = w.paneContent(Date()).mon?.formAction == "모습 바꾸기"
        w.gridTap(4411); let clicked = formPage().map { $0.ref == -1 && $0.item == "로토무카탈로그" } == true
        w.screen = .box(-1, act: nil, confirm: false, detail: true); w.calmAt = .distantPast; w.press(1)
        let menu = { if case .box(-1, .some(0), false, true) = w.screen { return w.boxActs(-1) == ["모습", "닫기"] }; return false }()
        w.press(1); let keyed = formPage()?.item == "로토무카탈로그"
        let acts = w.boxActs(0); w.screen = .box(0, act: acts.firstIndex(of: "합체"), confirm: false, detail: true); w.press(1)
        let fuse = acts.contains("합체") && formPage().map { $0.ref == 0 && $0.item == "유전자쐐기" } == true
        w.state.bag = []; w.screen = .box(0, act: nil, confirm: false, detail: true); w.refreshPane(Date(), force: true)
        let none = w.paneContent(Date()).mon?.formAction == nil && !w.boxActs(0).contains("합체") && w.boxActs(-1).isEmpty
        c.append((link && clicked && menu && keyed && fuse && none,
                  "5.0 ① a form from its page: 로토무's 모습 바꾸기 (link and ● menu), 큐레무's 합체 (● menu) — only with the item" + (link && clicked && menu && keyed && fuse && none ? "" : " — \(link) \(clicked) \(menu) \(keyed) \(fuse) \(none)")))
    }
    // ⑤ the first-time tips: once each (the app's walker only), at home; the Mega raid's when it opens
    Content.$testing.withValue(true) {
        var r = Seeded(s: 6), hid = Mon.wild(6, level: 20, &r); hid.ability = 2
        let w = Walker(state: { var s = Walk(); s.bag = ["리자몽나이트X"]; s.box = [hid]; return s }()); w.persist = false
        let quiet = { () -> Bool in Content.on = true; w.screen = .home; w.calmAt = .distantPast; w.tipTick(Date()); if case .home = w.screen { return true }; return false }()
        w.tipsOn = true
        @MainActor func tip() -> [String] { w.screen = .home; w.calmAt = .distantPast; w.tipTick(Date()); if case .say(let l, _, _) = w.screen { return l }; return [] }
        let said = [tip(), tip(), tip(), tip()]
        w.screen = .home; w.showTip(.megaRaid, next: .home, Date()); let raidOnce = { if case .say = w.screen { return !w.showTip(.megaRaid, next: .home, Date()) }; return false }()
        Content.on = false
        c.append((quiet && said[0] == Tip.content5.lines && said[1] == Tip.megaStone.lines && said[2] == Tip.hidden.lines && said[3].isEmpty && raidOnce && Tip.allCases.allSatisfy { $0.lines.allSatisfy { textWidth($0, small: true) <= 94 } },
                  "5.0 ⑤ first-time tips: 5.0's world, a Mega stone, a hidden ability, the Mega raid — once each, the app's walker only; every line fits the LCD"))
    }
    // ② every button on 5.0's pages does something: 로토무카탈로그's page, 유전자쐐기's, the moves with 메가, a page with its form link, the
    // 도감 entry with its 폼 row, the regions, the W shop's 기타 tab, 배틀's four
    Content.$testing.withValue(true) {
        var r = Seeded(s: 7)
        let rotom = Mon.wild(479, level: 30, &r), kyurem = Mon.wild(646, level: 60, &r), white = Mon.wild(643, level: 60, &r)
        var zard = Mon.wild(6, level: 60, &r); zard.item = "리자몽나이트X"; zard.known = [53, 19, 337, 89]
        let fight = Battle(wild: Mon.wild(214, level: 60, &r), companion: zard)
        @MainActor func walker(_ s: Screen, _ setup: @escaping (inout Walk) -> Void = { _ in }) -> () -> Walker {
            { var st = Walk(); st.companion = rotom; st.box = [kyurem, white]; st.bag = ["로토무카탈로그", "유전자쐐기"]; st.watts = 5000; st.owned = [6, 25, 479, 646, 650]; st.seen = st.owned
              setup(&st); let w = Walker(state: st); w.persist = false; w.fight = fight; w.screen = s; return w }
        }
        let dead: [(String, [Int])] = [
            ("로토무카탈로그", deadHits(walker(.formPick(ref: -1, item: "로토무카탈로그", sel: 0)), skip: [5980, 5981])),   // (row 0: 로토무, the one picked; row 1: itself now… its own form, said)
            ("유전자쐐기", deadHits(walker(.formPick(ref: 0, item: "유전자쐐기", sel: 0)), skip: [5980])),
            ("기술 · 메가", deadHits(walker(.moves(fight, sel: 0) ) { $0.companion = zard }, skip: [0])),
            ("포켓몬 화면", deadHits(walker(.box(-1, act: nil, confirm: false, detail: true)))),
            ("도감 · 폼", deadHits(walker(.dex(479, filter: 0, detail: true)))),
            ("상점 기타", deadHits(walker(.shop(bp: false, sel: 0, qty: nil)), skip: [2900])),        // (the tab it's on)
            ("배틀 메뉴", deadHits(walker(menuFor("배틀 타워")), skip: [3000])),
        ]
        let bad = dead.filter { !$0.1.isEmpty }
        c.append((bad.isEmpty, "5.0 ② every button on 5.0's pages does something (clicked through paneTap, as the Mac's and Windows')" + (bad.isEmpty ? "" : " — dead: \(bad)")))
    }
    return c
}

/// The fight's HP boxes (Card.drawHUD, half-dots over the LCD: theirs 4…114 × 4…34, ours 98…188 × 86…124) against every picture as it stands
/// on the stage (theirs front-on at (60, 8) with all its animation's frames, ours from behind at (8, 32)): the art numbers that reach under one.
@MainActor func hudOverlaps() -> [String] {
    let boxes: [(String, [Double])] = [("theirs", Walker.hudBoxes[0]), ("ours", Walker.hudBoxes[1])], clip = Walker.foeStage.map(Double.init)
    func inStage(_ b: [Double]) -> [Double] { [max(b[0], clip[0]), max(b[1], clip[1]), min(b[2], clip[0] + clip[2]), min(b[3], clip[1] + clip[3])] }   // (theirs is drawn in its stage)
    func hits(_ b: [Double]) -> [String] { boxes.filter { min(b[2], $0.1[2]) - max(b[0], $0.1[0]) > 1 && min(b[3], $0.1[3]) - max(b[1], $0.1[1]) > 1 }.map(\.0) }
    var out: [String] = []
    for art in 1...spriteCount {
        let front = SpriteRun(art: art, shiny: false, back: false, x: 60, y: 8, bob: 1, tint: nil, tintShade: 0, floor: 64, clip: Walker.foeStage)
        for h in drawnBox(front).map(hits) ?? [] { out.append("#\(art) front × \(h)") }
        if let a = anim(art) {                                                                   // each animation frame's pixels (a jump or a stretch may leave the 80 x 80)
            let fx = 2 * Double(60 + 16), fy = 2 * Double(8 + 32)
            for f in 0..<a.ms.count {
                var fb = [Double(a.w), Double(a.h), 0, 0]
                for y in 0..<a.h { for x in 0..<a.w where a.pixel(f, x, y, shiny: false) != 0 { fb = [min(fb[0], Double(x)), min(fb[1], Double(y)), max(fb[2], Double(x + 1)), max(fb[3], Double(y + 1))] } }
                guard fb[2] > fb[0] else { continue }
                for h in hits(inStage([fx + Double(a.x) + fb[0] - 40, fy + Double(a.y) + fb[1] - 80, fx + Double(a.x) + fb[2] - 40, min(128, fy + Double(a.y) + fb[3] - 80)])) { out.append("#\(art) anim × \(h)") }
            }
        }
        let back = SpriteRun(art: art, shiny: false, back: true, x: 8, y: 32, bob: 1, tint: nil, tintShade: 0, floor: 64)
        var bb = [80.0, 80, 0, 0]
        for y in 0..<80 { for x in 0..<80 where spritePixel(art, back: true, x, y, shiny: false) != 0 { bb = [min(bb[0], Double(x)), min(bb[1], Double(y)), max(bb[2], Double(x + 1)), max(bb[3], Double(y + 1))] } }
        if bb[2] > bb[0] { let fx = 2 * Double(back.x + 16), fy = 2 * Double(back.y + 32); for h in hits([fx + bb[0] - 40, fy + bb[1] - 80, fx + bb[2] - 40, min(128, fy + bb[3] - 80)]) { out.append("#\(art) back × \(h)") } }
    }
    return Array(Set(out)).sorted()
}
