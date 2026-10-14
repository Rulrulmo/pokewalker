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
    return c
}
