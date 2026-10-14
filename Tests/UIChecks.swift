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
    Content.$testing.withValue(true) {
        var r = Seeded(s: 4), zard = Mon.wild(6, level: 60, &r); zard.item = "리자몽나이트X"; zard.known = [53, 19, 337, 89]
        let b = Battle(wild: Mon.wild(214, level: 60, &r), companion: zard)
        let w = Walker(state: { var s = Walk(); s.companion = zard; return s }()); w.persist = false; w.sideOn = true; w.fight = b
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
        w.persist = false; w.sideOn = true
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
              setup(&st); let w = Walker(state: st); w.persist = false; w.sideOn = true; w.fight = fight; w.screen = s; return w }
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
