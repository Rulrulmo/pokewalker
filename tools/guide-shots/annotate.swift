// The guide's pictures from the renders (GuideShots.swift's <name>.png + .json): red numbered circles with boxes, before / after crops.
// swiftc -O tools/guide-shots/annotate.swift -o annotate && ./annotate <renders> docs/guide/img
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: annotate <renders dir> <out dir>"); exit(2) }
let raw = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

struct Shot {
    let img: CGImage, w: CGFloat, h: CGFloat, scale: CGFloat, texts: [(s: String, r: CGRect)]
    /// A word's box (points): the nth one that is it, else the nth that starts with it.
    func t(_ s: String, _ nth: Int = 0) -> CGRect {
        let exact = texts.filter { $0.s == s }, start = texts.filter { $0.s.hasPrefix(s) }
        guard let r = (exact.count > nth ? exact[nth] : start.count > nth ? start[nth] : nil)?.r else { print("no text '\(s)'"); exit(1) }
        return r
    }
}
func load(_ name: String) -> Shot {
    guard let src = CGImageSourceCreateWithURL(raw.appendingPathComponent(name + ".png") as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
          let d = try? Data(contentsOf: raw.appendingPathComponent(name + ".json")), let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let w = m["w"] as? Double, let h = m["h"] as? Double, let ts = m["texts"] as? [[String: Any]] else { print("no render \(name)"); exit(1) }
    let texts = ts.map { t in (s: t["s"] as? String ?? "", r: CGRect(x: t["x"] as? Double ?? 0, y: t["y"] as? Double ?? 0, width: t["w"] as? Double ?? 0, height: t["h"] as? Double ?? 0)) }
    return Shot(img: img, w: w, h: h, scale: CGFloat(img.width) / w, texts: texts)
}

/// A number: its box (what it points at) and where the circle sits (outside the box: a line joins them).
struct Mark { var n: Int; var box: CGRect; var at: CGPoint }
let red = NSColor(srgbRed: 0.90, green: 0.12, blue: 0.16, alpha: 1)
var written: [String] = []

/// The render (or a part of it: crop), margins left and right (and pads above and below, white) for the circles, boxes without numbers.
func make(_ name: String, _ s: Shot, crop: CGRect? = nil, left: CGFloat = 0, right: CGFloat = 0, top: CGFloat = 0, bottom: CGFloat = 0, marks: [Mark] = [], boxes: [CGRect] = []) {
    let c = crop ?? CGRect(x: 0, y: 0, width: s.w, height: s.h), k = s.scale
    let W = Int((c.width + left + right) * k), H = Int((c.height + top + bottom) * k)
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: k, y: -k)                        // points, y down, the canvas' corner at (0, 0)
    ctx.translateBy(x: left - c.minX, y: top - c.minY)                                     // the render's own points from here on
    if top > 0 || bottom > 0 { ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: c.minX, y: c.minY - top, width: c.width, height: c.height + top + bottom)) }
    ctx.saveGState(); ctx.clip(to: c)
    ctx.translateBy(x: 0, y: s.h); ctx.scaleBy(x: 1, y: -1); ctx.interpolationQuality = .none
    ctx.draw(s.img, in: CGRect(x: 0, y: 0, width: s.w, height: s.h))
    ctx.restoreGState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let frames = boxes + marks.map(\.box)                                                     // white under every box first: boxes side by side keep both red lines
    for (color, width) in [(NSColor.white, 3.2), (red, 1.6)] as [(NSColor, CGFloat)] {
        for r in frames { ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width); ctx.strokePath() }
    }
    for m in marks where !m.box.insetBy(dx: -1, dy: -1).contains(m.at) {                      // the line from the circle to the box's nearest edge
        let e = CGPoint(x: min(max(m.at.x, m.box.minX), m.box.maxX), y: min(max(m.at.y, m.box.minY), m.box.maxY))
        ctx.move(to: m.at); ctx.addLine(to: e); ctx.setStrokeColor(red.cgColor); ctx.setLineWidth(1.4); ctx.strokePath()
    }
    for m in marks {
        let R: CGFloat = 8, o = CGRect(x: m.at.x - R, y: m.at.y - R, width: 2 * R, height: 2 * R)
        ctx.setShadow(offset: CGSize(width: 0, height: 0.6), blur: 1.5, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(red.cgColor); ctx.fillEllipse(in: o); ctx.setShadow(offset: .zero, blur: 0)
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(1.6); ctx.strokeEllipse(in: o.insetBy(dx: 0.8, dy: 0.8))
        let t = NSAttributedString(string: "\(m.n)", attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .heavy), .foregroundColor: NSColor.white])
        let z = t.size(); t.draw(at: CGPoint(x: m.at.x - z.width / 2, y: m.at.y - z.height / 2))
    }
    NSGraphicsContext.current = nil
    guard let img = ctx.makeImage(), let dst = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst); written.append(name)
}

// the panel's sides (points): its rows and buttons run 9 … 206.5
let X0: CGFloat = 8, X1: CGFloat = 208, L: CGFloat = -12, M: CGFloat = 24        // L: a circle in the left margin (M wide)
func span(_ y0: CGFloat, _ y1: CGFloat, _ x0: CGFloat = X0, _ x1: CGFloat = X1) -> CGRect { CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) }
func around(_ rs: CGRect..., pad: CGFloat = 3) -> CGRect { rs.dropFirst().reduce(rs[0]) { $0.union($1) }.insetBy(dx: -pad, dy: -pad) }
func button(_ t: CGRect) -> CGRect { span(t.midY - 16.5, t.midY + 16.5) }
func left(_ n: Int, _ b: CGRect, _ y: CGFloat? = nil) -> Mark { Mark(n: n, box: b, at: CGPoint(x: L, y: y ?? b.midY)) }
func right(_ n: Int, _ b: CGRect, _ w: CGFloat = 216, _ y: CGFloat? = nil) -> Mark { Mark(n: n, box: b, at: CGPoint(x: w + 12, y: y ?? b.midY)) }

// 01 걸음 — 홈: ① 동료 (the LCD's and its line) ② 워커의 셋 ③ 알 ④ 오늘 걸음 ⑤ 와트; the menu's first page as it is
do {
    let s = load("home")
    make("01-1-home.png", s, left: M, right: M, marks: [
        right(1, CGRect(x: 131, y: 69, width: 72, height: 72)), left(1, span(195, 236.5)),
        left(2, CGRect(x: 23, y: 123, width: 84, height: 30)),
        Mark(n: 3, box: CGRect(x: 110, y: 127, width: 20, height: 21), at: CGPoint(x: 101, y: 114)), left(3, around(s.t("알"), s.t("앞으로"))),
        Mark(n: 4, box: around(s.t("오늘 걸음"), s.t("6,240")), at: CGPoint(x: 41, y: 283)),
        Mark(n: 5, box: around(s.t("와트"), s.t("12,480W")), at: CGPoint(x: 107, y: 283))])
    make("01-2-menu.png", load("menu"))
}
// 03 잡기 — the radar (① 흔들리는 풀숲 ② 연쇄), a wild one's menu (① 상대 HP ② 공격 ③ 볼), the ball on its way
do {
    let s = load("radar"), c = s.t("연쇄 3")
    make("03-1-radar.png", s, left: M, marks: [left(1, CGRect(x: 8, y: 270, width: 98.5, height: 48)),
        left(2, CGRect(x: 11, y: 29, width: 43, height: 20)), left(2, CGRect(x: c.minX - 3, y: c.minY - 3, width: 37.5, height: c.height + 6))])
    let b = load("battle_menu")
    make("03-2-battle.png", b, left: M, marks: [left(1, CGRect(x: 14, y: 30, width: 108, height: 32)), left(2, span(220, 259)), left(3, CGRect(x: 8, y: 264, width: 65, height: 38))])
    make("03-3-throw.png", load("battle_throw_10"))
}
// 04 레벨 — 홈's companion line: ① 레벨 ② 경험치 (다음 레벨까지)
do {
    let s = load("home")
    make("04-1-level.png", s, crop: CGRect(x: 0, y: 190, width: 216, height: 46), top: 16, bottom: 16, marks: [
        Mark(n: 1, box: CGRect(x: s.t("Lv.55").minX - 3.5, y: 199.5, width: s.t("Lv.55").width + 7, height: 14), at: CGPoint(x: 110, y: 185)),
        Mark(n: 2, box: span(215.5, 235, 43, 207), at: CGPoint(x: 125, y: 244))])
}
// 05 진화 — 배루키's pick: ① 셋 중 하나 ② 고른 모습의 능력치 ③ 진화
do {
    let s = load("evo_pick")
    make("05-1-evo-pick.png", s, left: M, marks: [left(1, span(215, 315)), left(2, span(317, 382)), left(3, button(s.t("시라소몬으로 진화")))])
}
// 06 강하게 만들기 — the page (① … ⑧), then each change: before / after, and the screens that make them
do {
    let p = load("page")
    make("06-01-page.png", p, left: M, right: M, marks: [
        left(1, CGRect(x: 11, y: 27, width: 126, height: 23)),
        left(2, span(195, 225)), left(3, span(231, 260)),
        left(4, span(275, 382, X0, 107)), right(5, span(275, 382, 109, X1)),
        right(8, span(384, 397)), left(6, span(398.6, 410)), left(7, span(412, 441.5))])
    let hex = CGRect(x: 0, y: 272, width: 216, height: 114)
    func stat(_ s: Shot, _ n: String, _ k: Int) -> CGRect {                              // a hexagon's stat: its name and the number under it (k: 0 개체값's, 1 노력치's)
        let t = s.t(n, k), v = s.texts.first { $0.r.minY > t.minY && $0.r.minY < t.minY + 12 && abs($0.r.midX - t.midX) < 8 }!.r
        return around(t, v, pad: 2.5)
    }
    for (file, name) in [("06-02-evs-before.png", "page"), ("06-02-evs-after.png", "evs_after")] {
        let s = load(name)
        make(file, s, crop: hex, boxes: [stat(s, "특공", 1), around(s.t("합 "), pad: 2)])
    }
    let mp = load("mint_pick")
    make("06-03-mint.png", mp, left: M, marks: [left(1, CGRect(x: 7, y: 213.5, width: 94, height: 44.5)), left(2, around(mp.t("이상해꽃 · 지금"))), left(3, button(mp.t("이상해꽃에게 쓰기")))])
    let nature = CGRect(x: 0, y: 190, width: 216, height: 38)
    for (file, name) in [("06-04-mint-before.png", "page"), ("06-04-mint-after.png", "mint_after")] {
        let s = load(name), up = s.texts.first { $0.s.hasSuffix("↑") }!.r, down = s.texts.first { $0.s.hasSuffix("↓") }!.r
        make(file, s, crop: nature, boxes: [around(s.t("고집"), pad: 3.5), around(up, down, pad: 3.5)])
    }
    let cp = load("cap_pick")
    make("06-05-silvercap.png", cp, left: M, marks: [left(1, span(280, 305.5)), left(2, button(cp.t("특공 24 → 31")))])
    func ivBoxes(_ s: Shot, _ stats: [(String, Int)]) -> [CGRect] {                     // the stats raised (개체값's), and its 3V …
        stats.map { stat(s, $0.0, $0.1) } + [around(s.texts.first { $0.s.hasSuffix("V") && $0.r.minY < 290 }!.r, pad: 2)]
    }
    for (file, name) in [("06-06-silvercap-before.png", "page"), ("06-06-silvercap-after.png", "silver_after")] { let s = load(name); make(file, s, crop: hex, boxes: ivBoxes(s, [("특공", 0)])) }
    for (file, name) in [("06-07-goldcap-before.png", "silver_after"), ("06-07-goldcap-after.png", "gold_after")] { let s = load(name); make(file, s, crop: hex, boxes: ivBoxes(s, [("공격", 0), ("스피드", 0)])) }
    let pp = load("patch_pick")
    make("06-08-patch.png", pp, left: M, marks: [left(1, around(pp.t("이상해꽃 · 특성"))), left(2, button(pp.t("이상해꽃에게 쓰기")))])
    let h = load("hold"), stone = h.t("이상해꽃나이트")
    make("06-09-hold.png", h, left: M, right: M, marks: [left(1, span(stone.minY - 4, stone.minY + 25)), right(2, around(h.t("지금 기적의씨"))), left(3, button(h.t("이상해꽃나이트 지니게")))])
    let mv = load("moves"), petal = mv.t("꽃잎댄스")
    make("06-10-moves.png", mv, left: M, marks: [left(1, around(mv.t("4번 기가드레인"))), left(2, span(petal.minY - 6.5, petal.maxY + 6.5)), left(3, span(347, 398))])
    let mg = load("mega"), tag = mg.t("메가진화 ✓")
    make("06-11-mega.png", mg, left: M, right: M, marks: [right(1, CGRect(x: 145, y: 275, width: 67.5, height: 40), 216, 296),
        left(2, CGRect(x: 8, y: 277, width: 135, height: 38)), left(3, CGRect(x: 8, y: 198, width: 98, height: 39)),
        right(4, around(tag, pad: 2.5), 216, tag.midY)])
}
// 08 쓰는 곳 — the tower, the raids, the Mega raid, 전설 원정
do {
    let t = load("tower")
    make("08-1-tower.png", t, left: M, marks: [left(1, around(t.t("최고 21연승"))), left(2, span(214, 302)), left(3, span(304.5, 345)), left(4, span(347, 397))])
    let r = load("raid")
    make("08-2-raid.png", r, left: M, marks: [left(1, around(r.t("오늘의 보스"))), left(2, span(214, 257)), left(3, span(262, 288)), left(4, span(289, 401)), left(5, button(r.t("도전 · 파워")))])
    let m = load("mega_raid")
    make("08-3-mega-raid.png", m, left: M, right: M, marks: [left(1, around(m.t("오늘의 보스"))), left(2, span(214, 257)), right(3, CGRect(x: 108, y: 262, width: 101, height: 26)), left(4, button(m.t("도전 · 파워")))])
    let e = load("expedition")
    make("08-4-expedition.png", e, left: M, marks: [left(1, span(212.5, 243.5)), left(2, span(244.8, 392)), left(3, span(396, 424))])
}
print(written.joined(separator: "\n"))
