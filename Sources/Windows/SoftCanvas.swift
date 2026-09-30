#if os(Windows) || SOFTCANVAS
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
// Windows' Canvas (Core/Canvas.swift), all in software: premultiplied 0xAARRGGBB pixels (in memory B G R A, a 32-bit DIB's: UpdateLayeredWindow's),
// shapes turned into polygons and filled by their exact area in each pixel (font-rs's accumulation: edges antialias as the Mac's do), pictures
// nearest-neighbour, text the platform's coverage masks (textMasks: GDI's, Windows/WinFonts.swift) coloured and laid on, the keys' three glyphs as
// paths. Nothing here is Win32: -D SOFTCANVAS builds it on the Mac too (to render against the Mac's own).

/// Device pixels, y down: what a SoftCanvas draws into (the window's buffer, --render's PNGs).
final class Raster {
    let w, h: Int
    var px: [UInt32]
    init(_ w: Int, _ h: Int) { self.w = max(0, w); self.h = max(0, h); px = Array(repeating: 0, count: self.w * self.h) }
}

/// A string's coverage (0...255) as the platform rasterises it: w x h, its pen (baseline, left) at (ox + qx / 4, oy) px.
struct TextMask { var w, h, ox, oy: Int; var a: [UInt8] }
/// Text as coverage: the platform's (Windows: GDI through WinFonts), set at launch next to `fonts`. scale = device pixels per point.
@MainActor protocol TextMasks { func mask(_ s: String, _ f: FontSpec, scale: CGFloat, qx: Int) -> TextMask }
@MainActor var textMasks: (any TextMasks)! = nil

struct IRect: Equatable {
    var x0, y0, x1, y1: Int
    var isEmpty: Bool { x1 <= x0 || y1 <= y0 }
    func meet(_ o: IRect) -> IRect { IRect(x0: max(x0, o.x0), y0: max(y0, o.y0), x1: min(x1, o.x1), y1: min(y1, o.y1)) }
}
struct P { var x, y: Double }
extension P { init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) } }
/// A rectangle as its edges (CGRect's insetBy turns null past zero).
struct DR {
    var x0, y0, x1, y1: Double
    init(_ r: CGRect) { let r = r.standardized; x0 = Double(r.minX); y0 = Double(r.minY); x1 = Double(r.maxX); y1 = Double(r.maxY) }
    init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) { self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1 }
    var w: Double { x1 - x0 }
    var h: Double { y1 - y0 }
    func inset(_ d: Double) -> DR { DR(x0 + d, y0 + d, x1 - d, y1 - d) }
}
/// Points → device pixels: x' = a x + c y + tx, y' = b x + d y + ty.
struct Affine {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0
    func at(_ x: Double, _ y: Double) -> P { P(x: a * x + c * y + tx, y: b * x + d * y + ty) }
    func at(_ p: P) -> P { at(p.x, p.y) }
    /// m first, then this.
    func after(_ m: Affine) -> Affine {
        Affine(a: a * m.a + c * m.b, b: b * m.a + d * m.b, c: a * m.c + c * m.d, d: b * m.c + d * m.d, tx: a * m.tx + c * m.ty + tx, ty: b * m.tx + d * m.ty + ty)
    }
    var inverse: Affine { let k = a * d - b * c; return Affine(a: d / k, b: -b / k, c: -c / k, d: a / k, tx: (c * ty - d * tx) / k, ty: (b * tx - a * ty) / k) }
    var axis: Bool { b == 0 && c == 0 }
    var scale: Double { (a * a + b * b).squareRoot() }
}

// MARK: - shapes as polygons (clockwise on screen: rect, oval and rounded alike, as NSBezierPath winds them)
/// Segments for a quarter circle of device radius r: the chord strays under 0.1 px.
func quarterSteps(_ r: Double) -> Int { max(2, Int((1.75 * max(0, r).squareRoot()).rounded(.up))) }
func rectPts(_ r: DR) -> [P] { [P(x: r.x0, y: r.y0), P(x: r.x1, y: r.y0), P(x: r.x1, y: r.y1), P(x: r.x0, y: r.y1)] }
func ovalPts(_ r: DR, _ sc: Double) -> [P] {
    let cx = (r.x0 + r.x1) / 2, cy = (r.y0 + r.y1) / 2, rx = r.w / 2, ry = r.h / 2, n = 4 * quarterSteps(max(rx, ry) * sc)
    return (0..<n).map { k in let t = 2 * Double.pi * Double(k) / Double(n); return P(x: cx + rx * cos(t), y: cy + ry * sin(t)) }
}
func roundedPts(_ r: DR, _ radius: Double, _ sc: Double) -> [P] {
    let rr = min(radius, r.w / 2, r.h / 2)
    guard rr > 0 else { return rectPts(r) }
    let n = quarterSteps(rr * sc); var pts: [P] = []
    for (cx, cy, a0) in [(r.x1 - rr, r.y0 + rr, -Double.pi / 2), (r.x1 - rr, r.y1 - rr, 0), (r.x0 + rr, r.y1 - rr, Double.pi / 2), (r.x0 + rr, r.y0 + rr, Double.pi)] {
        for k in 0...n { let t = a0 + Double.pi / 2 * Double(k) / Double(n); pts.append(P(x: cx + rr * cos(t), y: cy + rr * sin(t))) }
    }
    return pts
}
/// Twice the signed area: > 0 = clockwise on a y-down screen.
func area2(_ p: [P]) -> Double { p.indices.reduce(0) { s, i in let q = p[(i + 1) % p.count]; return s + p[i].x * q.y - q.x * p[i].y } }
func clockwise(_ p: [P]) -> [P] { area2(p) < 0 ? p.reversed() : p }
/// A path's outlines to fill (user space); open subpaths close themselves.
func fillPolys(_ p: Path, _ sc: Double) -> [[P]] {
    var out: [[P]] = [], cur: [P] = []
    func flush() { if cur.count > 2 { out.append(cur) }; cur = [] }
    for part in p.parts {
        switch part {
        case .rect(let r): out.append(rectPts(DR(r)))
        case .oval(let r): out.append(ovalPts(DR(r), sc))
        case .rounded(let r, let rad): out.append(roundedPts(DR(r), Double(rad), sc))
        case .move(let q): flush(); cur = [P(q)]
        case .line(let q): cur.append(P(q))
        case .close: let s = cur.first; flush(); cur = s.map { [$0] } ?? []
        }
    }
    flush()
    return out
}
/// The outline of a line through pts stroked hw either side: a quad a segment, joins (round: discs; else mitres, bevelled past 10), round caps;
/// each piece clockwise, so they add up (nonzero) into one shape.
func strokeLine(_ raw: [P], closed: Bool, hw: Double, round: Bool, sc: Double) -> [[P]] {
    var pts: [P] = []
    for p in raw where pts.last.map({ $0.x != p.x || $0.y != p.y }) ?? true { pts.append(p) }
    if closed, pts.count > 2, pts[0].x == pts[pts.count - 1].x, pts[0].y == pts[pts.count - 1].y { pts.removeLast() }
    guard pts.count >= 2 else { return [] }
    let n = pts.count, segs = closed ? n : n - 1
    func unit(_ i: Int) -> P { let a = pts[i], b = pts[(i + 1) % n], l = hypot(b.x - a.x, b.y - a.y); return P(x: (b.x - a.x) / l, y: (b.y - a.y) / l) }
    func disc(_ c: P) -> [P] { ovalPts(DR(c.x - hw, c.y - hw, c.x + hw, c.y + hw), sc) }
    var out: [[P]] = []
    for i in 0..<segs {
        let a = pts[i], b = pts[(i + 1) % n], u = unit(i), nx = -u.y * hw, ny = u.x * hw
        out.append(clockwise([P(x: a.x + nx, y: a.y + ny), P(x: b.x + nx, y: b.y + ny), P(x: b.x - nx, y: b.y - ny), P(x: a.x - nx, y: a.y - ny)]))
    }
    for v in closed ? Array(0..<n) : Array(1..<n - 1) {
        let c = pts[v]
        if round { out.append(disc(c)); continue }
        let u1 = unit((v + n - 1) % n), u2 = unit(v), n1 = P(x: -u1.y, y: u1.x), n2 = P(x: -u2.y, y: u2.x)
        guard abs(u1.x * u2.y - u1.y * u2.x) > 1e-9 else { continue }                              // straight on: nothing to fill
        let s: Double = n1.x * u2.x + n1.y * u2.y > 0 ? -1 : 1, cosn = n1.x * n2.x + n1.y * n2.y   // the side the turn opens up
        let a = P(x: c.x + s * hw * n1.x, y: c.y + s * hw * n1.y), b = P(x: c.x + s * hw * n2.x, y: c.y + s * hw * n2.y)
        if 2 / (1 + cosn) <= 100 { out.append(clockwise([c, a, P(x: c.x + s * hw * (n1.x + n2.x) / (1 + cosn), y: c.y + s * hw * (n1.y + n2.y) / (1 + cosn)), b])) }   // the mitre, up to 10 x hw
        else { out.append(clockwise([c, a, b])) }
    }
    if round, !closed { out += [disc(pts[0]), disc(pts[n - 1])] }
    return out
}

// MARK: - pixels
/// s (premultiplied) laid over d at k / 255.
@inline(__always) func over(_ d: UInt32, _ s: UInt32, _ k: UInt32) -> UInt32 {
    if k == 255, s >> 24 == 255 { return s }
    let inv = 255 - ((s >> 24) * k + 127) / 255
    func ch(_ sh: UInt32) -> UInt32 { min(255, ((s >> sh & 255) * k + 127) / 255 + ((d >> sh & 255) * inv + 127) / 255) }
    return ch(24) << 24 | ch(16) << 16 | ch(8) << 8 | ch(0)
}
/// c premultiplied, times alpha: sRGB as it is (a grey too); tint < 1 = that much of it over white as NSColor.blended mixes them, in Generic RGB
/// (γ 1.8, primaries a hair off sRGB's: the matrices measured off the Mac; it gives 221 232 251 for 20 % of Ink.blue, not a plain mix's 216 230 251).
func packed(_ c: Color, _ alpha: Double = 1) -> UInt32 {
    var r = Double(c.red), g = Double(c.green), b = Double(c.blue), a = Double(c.alpha)
    if c.tint < 1 {
        func dec(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func enc(_ l: Double) -> Double { let l = min(1, max(0, l)); return l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055 }
        let t = Double(c.tint), (lr, lg, lb) = (dec(r), dec(g), dec(b))
        let gen = [0.974858 * lr + 0.027294 * lg - 0.002154 * lb, -0.020008 * lr + 1.054230 * lg - 0.034222 * lb, 0.001684 * lr + 0.001556 * lg + 0.996761 * lb]
            .map { pow(pow(max(0, $0), 1 / 1.8) * t + 1 - t, 1.8) }
        r = enc(1.025243 * gen[0] - 0.026545 * gen[1] + 0.001304 * gen[2]); g = enc(0.019401 * gen[0] + 0.948009 * gen[1] + 0.03259 * gen[2]); b = enc(-0.001762 * gen[0] - 0.001435 * gen[1] + 1.003196 * gen[2])
        a = a * t + 1 - t
    }
    a *= alpha
    func q(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
    return q(a) << 24 | q(r * a) << 16 | q(g * a) << 8 | q(b * a)
}
/// A Bitmap's pixels premultiplied, made on its first draw (Bitmap.native).
final class SoftImage { let w, h: Int; let px: [UInt32]; init(_ p: Pic) { w = p.w; h = p.h; px = p.px.map { c in let a = c >> 24; return a == 255 ? c : a << 24 | ((c >> 16 & 255) * a / 255) << 16 | ((c >> 8 & 255) * a / 255) << 8 | (c & 255) * a / 255 } } }

// MARK: - the canvas
@MainActor final class SoftCanvas: Canvas {
    struct State { var t: Affine; var clip: IRect; var mask: (r: IRect, a: [UInt8])?; var aa = true }
    let scale: CGFloat
    private(set) var target: Raster
    private var g: State, stack: [State] = []
    private var layers: [(parent: Raster, alpha: Double, box: IRect)] = [], spare: [Raster] = []
    private var acc: [Float] = []                                          // the rasteriser's rows, kept between fills

    /// Onto r at `pixels` device pixels a point; scale = what the core is told (the Mac's snapshots say 2 at any size: --render copies them).
    init(_ r: Raster, scale: CGFloat, pixels: CGFloat? = nil) {
        target = r; self.scale = scale; let k = Double(pixels ?? scale)
        g = State(t: Affine(a: k, d: k), clip: IRect(x0: 0, y0: 0, x1: r.w, y1: r.h))
    }
    func translate(_ dx: CGFloat, _ dy: CGFloat) { g.t = g.t.after(Affine(tx: Double(dx), ty: Double(dy))) }

    typealias Mask = (r: IRect, a: [UInt8])
    /// k at (x, y) through the clip's mask m (g.mask, taken once a draw).
    @inline(__always) private func clipped(_ k: UInt32, _ x: Int, _ y: Int, _ m: Mask?) -> UInt32 {
        guard let m else { return k }
        let mx = x - m.r.x0, my = y - m.r.y0
        guard mx >= 0, my >= 0, mx < m.r.x1 - m.r.x0, my < m.r.y1 - m.r.y0 else { return 0 }
        return k * UInt32(m.a[my * (m.r.x1 - m.r.x0) + mx]) / 255
    }
    /// Coverage (0...255) laid on in colour col over box, clipped.
    private func paint(_ box: IRect, _ cov: [UInt8], _ col: UInt32) {
        let bw = box.x1 - box.x0, W = target.w
        let m = g.mask
        target.px.withUnsafeMutableBufferPointer { px in
            for y in box.y0..<box.y1 { for x in box.x0..<box.x1 {
                let k = clipped(UInt32(cov[(y - box.y0) * bw + x - box.x0]), x, y, m)
                if k > 0 { px[y * W + x] = over(px[y * W + x], col, k) }
            } }
        }
    }
    /// The device bounds of polygons, inside the clip.
    private func bounds(_ polys: [[P]]) -> IRect {
        var x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
        for p in polys { for q in p { x0 = min(x0, q.x); y0 = min(y0, q.y); x1 = max(x1, q.x); y1 = max(y1, q.y) } }
        guard x0 < x1, y0 < y1, x0.isFinite, y1.isFinite else { return IRect(x0: 0, y0: 0, x1: 0, y1: 0) }
        return IRect(x0: Int(max(-1e6, x0.rounded(.down))), y0: Int(max(-1e6, y0.rounded(.down))), x1: Int(min(1e6, x1.rounded(.up))), y1: Int(min(1e6, y1.rounded(.up)))).meet(g.clip)
    }
    /// Device polygons' coverage over box, 0...255 a pixel: exact area, |winding| clamped to 1 (nonzero), hard-edged at half without antialiasing.
    private func coverage(_ polys: [[P]], _ box: IRect) -> [UInt8] {
        let bw = box.x1 - box.x0, bh = box.y1 - box.y0, stride = bw + 2, n = stride * bh
        if acc.count < n { acc = Array(repeating: 0, count: n) }
        var out = [UInt8](repeating: 0, count: bw * bh)
        acc.withUnsafeMutableBufferPointer { a in
            let a = a.baseAddress!
            a.update(repeating: 0, count: n)
            let W = Double(bw), ox = Double(box.x0), oy = Double(box.y0)
            /// One edge's signed area into the rows (font-rs), x inside 0...W.
            func edge(_ p: P, _ q: P) {
                guard p.y != q.y else { return }
                let (dir, s, e): (Float, P, P) = p.y < q.y ? (1, p, q) : (-1, q, p)
                let dxdy = (e.x - s.x) / (e.y - s.y)
                var x = s.x, y0 = s.y
                if y0 < 0 { x -= y0 * dxdy; y0 = 0 }
                let y1 = min(e.y, Double(bh))
                guard y0 < y1 else { return }
                var y = Int(y0)
                while Double(y) < y1 {
                    let row = y * stride, dy = min(Double(y + 1), y1) - max(Double(y), y0), xn = x + dxdy * dy, d = Float(dy) * dir
                    let l = min(max(0, min(x, xn)), W), r = min(max(0, max(x, xn)), W), lf = l.rounded(.down), li = Int(lf), rc = r.rounded(.up), ri = Int(rc)
                    if ri <= li + 1 {
                        let xm = Float((l + r) / 2 - lf)
                        a[row + li] += d - d * xm; a[row + li + 1] += d * xm
                    } else {
                        let sl = Float(1 / (r - l)), x0f = Float(l - lf), a0 = 0.5 * sl * (1 - x0f) * (1 - x0f), x1f = Float(r - rc + 1), am = 0.5 * sl * x1f * x1f
                        a[row + li] += d * a0
                        if ri == li + 2 { a[row + li + 1] += d * (1 - a0 - am) } else {
                            let a1 = sl * (1.5 - x0f)
                            a[row + li + 1] += d * (a1 - a0)
                            for xi in li + 2 ..< ri - 1 { a[row + xi] += d * sl }
                            a[row + ri - 1] += d * (1 - (a1 + Float(ri - li - 3) * sl) - am)
                        }
                        a[row + ri] += d * am
                    }
                    x = xn; y += 1
                }
            }
            /// Split where it leaves 0...W: the part outside runs down the border (it still covers what's right of it).
            func clippedEdge(_ p: P, _ q: P) {
                if p.x >= 0, p.x <= W, q.x >= 0, q.x <= W { edge(p, q); return }
                var ts = [0.0, 1.0]
                for b in [0.0, W] where (p.x - b) * (q.x - b) < 0 { ts.append((b - p.x) / (q.x - p.x)) }
                ts.sort()
                for i in 0..<ts.count - 1 {
                    let pa = P(x: p.x + (q.x - p.x) * ts[i], y: p.y + (q.y - p.y) * ts[i]), pb = P(x: p.x + (q.x - p.x) * ts[i + 1], y: p.y + (q.y - p.y) * ts[i + 1])
                    edge(P(x: min(max(pa.x, 0), W), y: pa.y), P(x: min(max(pb.x, 0), W), y: pb.y))
                }
            }
            for poly in polys where poly.count > 2 {
                for i in poly.indices { let s = poly[i], e = poly[(i + 1) % poly.count]; clippedEdge(P(x: s.x - ox, y: s.y - oy), P(x: e.x - ox, y: e.y - oy)) }
            }
            let aa = g.aa
            out.withUnsafeMutableBufferPointer { o in
                for y in 0..<bh {
                    var s: Float = 0
                    for x in 0..<bw {
                        s += a[y * stride + x]; let c = min(1, abs(s))
                        o[y * bw + x] = aa ? UInt8(c * 255 + 0.5) : c >= 0.5 ? 255 : 0
                    }
                }
            }
        }
        return out
    }
    private func fillDevice(_ polys: [[P]], _ col: UInt32) {
        let box = bounds(polys)
        guard !box.isEmpty, col >> 24 > 0 else { return }
        paint(box, coverage(polys, box), col)
    }
    /// An upright rectangle in device pixels: its exact coverage (antialiased), or the pixels whose centres it holds.
    private func fillDeviceRect(_ r: DR, _ col: UInt32) {
        let box: IRect = g.aa ? IRect(x0: Int(r.x0.rounded(.down)), y0: Int(r.y0.rounded(.down)), x1: Int(r.x1.rounded(.up)), y1: Int(r.y1.rounded(.up))).meet(g.clip)
                              : IRect(x0: Int((r.x0 - 0.5).rounded(.up)), y0: Int((r.y0 - 0.5).rounded(.up)), x1: Int((r.x1 - 0.5).rounded(.up)), y1: Int((r.y1 - 0.5).rounded(.up))).meet(g.clip)
        guard !box.isEmpty, col >> 24 > 0 else { return }
        let aa = g.aa, W = target.w
        func span(_ i: Int, _ a: Double, _ b: Double) -> Double { aa ? max(0, min(b, Double(i + 1)) - max(a, Double(i))) : 1 }
        let m = g.mask
        target.px.withUnsafeMutableBufferPointer { px in
            for y in box.y0..<box.y1 {
                let cy = span(y, r.y0, r.y1)
                for x in box.x0..<box.x1 {
                    let k = clipped(UInt32(cy * span(x, r.x0, r.x1) * 255 + 0.5), x, y, m)
                    if k > 0 { px[y * W + x] = over(px[y * W + x], col, k) }
                }
            }
        }
    }

    // MARK: Canvas
    func fill(_ r: CGRect, _ c: Color) { fill(.rect(r), c) }
    func fill(_ p: Path, _ c: Color) {
        let col = packed(c)
        if g.t.axis, p.parts.allSatisfy({ if case .rect = $0 { true } else { false } }) {                // rects (the LCD's dots): straight onto pixels
            for case .rect(let r) in p.parts { let d = DR(r), a = g.t.at(d.x0, d.y0), b = g.t.at(d.x1, d.y1); fillDeviceRect(DR(min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y)), col) }
            return
        }
        fillDevice(fillPolys(p, g.t.scale).map { $0.map(g.t.at) }, col)
    }
    func stroke(_ p: Path, _ c: Color, width: CGFloat, round: Bool) {
        let hw = Double(width) / 2, sc = g.t.scale
        var out: [[P]] = [], cur: [P] = []
        func flush(_ closed: Bool) { out += strokeLine(cur, closed: closed, hw: hw, round: round, sc: sc); cur = [] }
        for part in p.parts {
            switch part {                                                                              // closed shapes: the band between them grown and shrunk
            case .rect(let r):
                let d = DR(r); out.append(rectPts(d.inset(-hw))); if d.w > 2 * hw, d.h > 2 * hw { out.append(rectPts(d.inset(hw)).reversed()) }
            case .oval(let r):
                let d = DR(r); out.append(ovalPts(d.inset(-hw), sc)); if d.w > 2 * hw, d.h > 2 * hw { out.append(ovalPts(d.inset(hw), sc).reversed()) }
            case .rounded(let r, let rad):
                let d = DR(r), rr = min(Double(rad), d.w / 2, d.h / 2)
                out.append(roundedPts(d.inset(-hw), rr + hw, sc)); if d.w > 2 * hw, d.h > 2 * hw { out.append(roundedPts(d.inset(hw), max(0, rr - hw), sc).reversed()) }
            case .move(let q): flush(false); cur = [P(q)]
            case .line(let q): cur.append(P(q))
            case .close: let s = cur.first; flush(true); cur = s.map { [$0] } ?? []
            }
        }
        flush(false)
        fillDevice(out.map { $0.map(g.t.at) }, packed(c))
    }
    func clip(_ p: Path) {
        if g.t.axis, p.parts.count == 1, case .rect(let r) = p.parts[0] {                             // an upright rectangle: whole pixels
            let d = DR(r), a = g.t.at(d.x0, d.y0), b = g.t.at(d.x1, d.y1)
            g.clip = g.clip.meet(IRect(x0: Int(min(a.x, b.x).rounded()), y0: Int(min(a.y, b.y).rounded()), x1: Int(max(a.x, b.x).rounded()), y1: Int(max(a.y, b.y).rounded())))
            return
        }
        let polys = fillPolys(p, g.t.scale).map { $0.map(g.t.at) }, box = bounds(polys)
        guard !box.isEmpty else { g.clip = IRect(x0: 0, y0: 0, x1: 0, y1: 0); return }
        var cov = coverage(polys, box)
        let m = g.mask
        for y in box.y0..<box.y1 { for x in box.x0..<box.x1 { let i = (y - box.y0) * (box.x1 - box.x0) + x - box.x0; cov[i] = UInt8(clipped(UInt32(cov[i]), x, y, m)) } }
        g.clip = box; g.mask = (box, cov)
    }
    func save() { stack.append(g) }
    func restore() { if let s = stack.popLast() { g = s } }
    func antialias(_ on: Bool) { g.aa = on }
    func rotate(_ degrees: CGFloat, about c: CGPoint) {
        let t = Double(degrees) * Double.pi / 180, cs = cos(t), sn = sin(t), cx = Double(c.x), cy = Double(c.y)
        g.t = g.t.after(Affine(a: cs, b: sn, c: -sn, d: cs, tx: cx - cs * cx + sn * cy, ty: cy - sn * cx - cs * cy))
    }
    func image(_ b: Bitmap, _ r: CGRect, alpha: CGFloat) {
        let img = (b.native as? SoftImage) ?? { let s = SoftImage(b.pic); b.native = s; return s }()
        let k = UInt32(max(0, min(255, (Double(alpha) * 255).rounded()))), d = DR(r), t = g.t, W = target.w
        guard img.w > 0, img.h > 0, k > 0, d.w > 0, d.h > 0 else { return }
        if t.axis {                                                                                    // upright: the pixels whose centres it holds, a lookup a column
            let a = t.at(d.x0, d.y0), e = t.at(d.x1, d.y1), x0 = min(a.x, e.x), x1 = max(a.x, e.x), y0 = min(a.y, e.y), y1 = max(a.y, e.y)
            let box = IRect(x0: Int((x0 - 0.5).rounded(.up)), y0: Int((y0 - 0.5).rounded(.up)), x1: Int((x1 - 0.5).rounded(.up)), y1: Int((y1 - 0.5).rounded(.up))).meet(g.clip)
            guard !box.isEmpty else { return }
            let sx = (box.x0..<box.x1).map { i in min(img.w - 1, max(0, Int((Double(i) + 0.5 - x0) / (x1 - x0) * Double(img.w)))) }
            let m = g.mask
        target.px.withUnsafeMutableBufferPointer { px in
                for y in box.y0..<box.y1 {
                    let sy = min(img.h - 1, max(0, Int((Double(y) + 0.5 - y0) / (y1 - y0) * Double(img.h)))) * img.w
                    for x in box.x0..<box.x1 {
                        let s = img.px[sy + sx[x - box.x0]]; guard s != 0 else { continue }
                        let kk = clipped(k, x, y, m); if kk > 0 { px[y * W + x] = over(px[y * W + x], s, kk) }
                    }
                }
            }
            return
        }
        let inv = t.inverse, corners = [t.at(d.x0, d.y0), t.at(d.x1, d.y0), t.at(d.x1, d.y1), t.at(d.x0, d.y1)], box = bounds([corners])   // turned: each pixel's centre looked up
        guard !box.isEmpty else { return }
        let m = g.mask
        target.px.withUnsafeMutableBufferPointer { px in
            for y in box.y0..<box.y1 { for x in box.x0..<box.x1 {
                let u = inv.at(Double(x) + 0.5, Double(y) + 0.5), fx = (u.x - d.x0) / d.w, fy = (u.y - d.y0) / d.h
                guard fx >= 0, fx < 1, fy >= 0, fy < 1 else { continue }
                let s = img.px[Int(fy * Double(img.h)) * img.w + Int(fx * Double(img.w))]; guard s != 0 else { continue }
                let kk = clipped(k, x, y, m); if kk > 0 { px[y * W + x] = over(px[y * W + x], s, kk) }
            } }
        }
    }
    func text(_ s: String, _ p: CGPoint, _ f: FontSpec, _ c: Color) {
        guard !s.isEmpty, let tm = textMasks else { return }
        let o = g.t.at(Double(p.x), Double(p.y + fonts.metrics(f).ascender.rounded())), fx = o.x.rounded(.down)   // the pen where AppKit puts it: the ascender rounded (points),
        let ix = Int(fx), qx = Int(((o.x - fx) * 2).rounded(.down)) * 2, iy = Int((o.y - 1e-6).rounded(.up))      // then down to a half pixel across, up onto a pixel row
        let mk = tm.mask(s, f, scale: CGFloat(g.t.scale), qx: qx)
        let box = IRect(x0: ix - mk.ox, y0: iy - mk.oy, x1: ix - mk.ox + mk.w, y1: iy - mk.oy + mk.h)
        let vis = box.meet(g.clip)
        guard !vis.isEmpty else { return }
        let col = packed(c), W = target.w
        let m = g.mask
        target.px.withUnsafeMutableBufferPointer { px in
            for y in vis.y0..<vis.y1 { for x in vis.x0..<vis.x1 {
                let k = clipped(UInt32(mk.a[(y - box.y0) * mk.w + x - box.x0]), x, y, m)
                if k > 0 { px[y * W + x] = over(px[y * W + x], col, k) }
            } }
        }
    }
    func gradient(_ r: CGRect, from: Color, to: Color, angle: CGFloat) {
        let d = DR(r), t = Double(angle) * Double.pi / 180, ux = cos(t), uy = sin(t)
        let proj = rectPts(d).map { $0.x * ux + $0.y * uy }, p0 = proj.min()!, p1 = proj.max()!
        let corners = rectPts(d).map(g.t.at), box = bounds([corners]), inv = g.t.inverse, W = target.w
        guard !box.isEmpty, p1 > p0 else { return }
        let cov = coverage([corners], box), bw = box.x1 - box.x0
        func mix(_ a: CGFloat, _ b: CGFloat, _ f: Double) -> CGFloat { a + (b - a) * CGFloat(f) }
        let m = g.mask
        target.px.withUnsafeMutableBufferPointer { px in
            for y in box.y0..<box.y1 { for x in box.x0..<box.x1 {
                let k = clipped(UInt32(cov[(y - box.y0) * bw + x - box.x0]), x, y, m); guard k > 0 else { continue }
                let u = inv.at(Double(x) + 0.5, Double(y) + 0.5), f = min(1, max(0, (u.x * ux + u.y * uy - p0) / (p1 - p0)))
                let c = Color(red: mix(from.red, to.red, f), green: mix(from.green, to.green, f), blue: mix(from.blue, to.blue, f), alpha: mix(from.alpha, to.alpha, f))
                px[y * W + x] = over(px[y * W + x], packed(c), k)
            } }
        }
    }
    func beginLayer(alpha: CGFloat) {
        save()
        let l = spare.popLast().flatMap { $0.w == target.w && $0.h == target.h ? $0 : nil } ?? Raster(target.w, target.h), b = g.clip
        if !b.isEmpty { for y in b.y0..<b.y1 { l.px.withUnsafeMutableBufferPointer { $0.baseAddress!.advanced(by: y * l.w + b.x0).update(repeating: 0, count: b.x1 - b.x0) } } }
        layers.append((target, Double(alpha), b)); target = l
    }
    func endLayer() {
        guard let (parent, alpha, b) = layers.popLast() else { return }
        let k = UInt32(max(0, min(255, (alpha * 255).rounded()))), l = target, W = l.w
        if !b.isEmpty { parent.px.withUnsafeMutableBufferPointer { px in for y in b.y0..<b.y1 { for x in b.x0..<b.x1 where l.px[y * W + x] != 0 { px[y * W + x] = over(px[y * W + x], l.px[y * W + x], k) } } } }
        spare.append(l); target = parent; restore()
    }
    /// The Mac's SF Symbols (arrow.uturn.backward, square.grid.2x2.fill, house.fill; bold) as paths, measured off its keys at 8.5 pt.
    func glyph(_ gl: Glyph, _ at: CGPoint, _ size: CGFloat, _ c: Color, alpha: CGFloat) {
        let u = Double(size) / 8.5
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: Double(at.x) + x * u, y: Double(at.y) + y * u) }
        if alpha < 1 { beginLayer(alpha: alpha) }                                                  // one picture at alpha, as the symbol's image is
        switch gl {
        case .menu:
            fill(Path(parts: [(-4.0, -4.0), (0.45, -4.0), (-4.0, 0.45), (0.45, 0.45)].map { x, y -> Path.Part in .rounded(CGRect(origin: pt(x, y), size: CGSize(width: 3.55 * u, height: 3.55 * u)), CGFloat(1.1 * u)) }), c)
        case .home:
            stroke(.poly([pt(-4.9, 0), pt(-0.4, -3.7), pt(3.9, 0)], closed: false), c, width: CGFloat(1.1 * u), round: true)   // the roof
            fill(.rect(CGRect(origin: pt(2.4, -3.6), size: CGSize(width: 1.1 * u, height: 2.1 * u))), c)                     // the chimney
            fill(Path(parts: Path.poly([pt(-0.3, -2.1), pt(3.5, 0.9), pt(3.5, 5), pt(-4, 5), pt(-4, 0.9)]).parts                    // the house, its door the other way round: a hole
                      + Path.poly([pt(-1.5, 1.5), pt(-1.5, 4), pt(1, 4), pt(1, 1.5)]).parts), c)
        case .back:
            let arc = (0...12).map { k -> CGPoint in let t = -Double.pi / 2 + Double.pi * Double(k) / 12; return pt(0.45 + 2.25 * cos(t), 1.5 + 2.25 * sin(t)) }
            stroke(Path(parts: Path.poly([pt(-1.7, -3.45), pt(-3.95, -0.75), pt(-1.85, 1.6)], closed: false).parts
                        + Path.poly([pt(-3.95, -0.75)] + arc + [pt(-0.7, 3.75)], closed: false).parts), c, width: CGFloat(1.1 * u), round: true)
        }
        if alpha < 1 { endLayer() }
    }
}

// MARK: - the card
/// The whole card as the Mac's view draws it: the card (Core/Card.swift), then the pane's page in its frame under the band (Core/Page.swift).
@MainActor func drawWhole(_ w: Walker, _ page: Page, _ c: SoftCanvas, shown: FB?, down: Int?) {
    let size = CGSize(width: Layout.w * K, height: (w.cardH * K).rounded()), top = (Layout.pane * K).rounded()
    w.drawCard(c, CGRect(origin: .zero, size: size), shown: shown, down: down, lcdOnly: false)
    c.save(); c.translate(0, top); c.clip(.rect(CGRect(x: 0, y: 0, width: size.width, height: max(0, size.height - top))))
    page.draw(on: c); c.restore()
}

// MARK: - PNG
let crcTable: [UInt32] = (0..<256).map { n in (0..<8).reduce(UInt32(n)) { c, _ in c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 } }
extension Raster {
    /// RGBA PNG bytes of `box` (default all): zlib's stored blocks, nothing to compress with (the CI zips the artifact).
    func png(_ box: IRect? = nil) -> Data {
        let b = (box ?? IRect(x0: 0, y0: 0, x1: w, y1: h)).meet(IRect(x0: 0, y0: 0, x1: w, y1: h)), bw = max(0, b.x1 - b.x0), bh = max(0, b.y1 - b.y0)
        var raw: [UInt8] = []; raw.reserveCapacity((bw * 4 + 1) * bh)
        for y in b.y0..<b.y0 + bh {
            raw.append(0)
            for x in b.x0..<b.x0 + bw {
                let p = px[y * w + x], a = p >> 24
                func un(_ v: UInt32) -> UInt8 { a == 0 ? 0 : UInt8(min(255, (v * 255 + a / 2) / a)) }
                raw.append(un(p >> 16 & 255)); raw.append(un(p >> 8 & 255)); raw.append(un(p & 255)); raw.append(UInt8(a))
            }
        }
        var z: [UInt8] = [0x78, 0x01], s1: UInt32 = 1, s2: UInt32 = 0
        for v in raw { s1 = (s1 + UInt32(v)) % 65521; s2 = (s2 + s1) % 65521 }
        var i = 0
        repeat {
            let n = min(65535, raw.count - i), last: UInt8 = i + n == raw.count ? 1 : 0
            z += [last, UInt8(n & 255), UInt8(n >> 8), UInt8(~n & 255), UInt8(~n >> 8 & 255)] + raw[i..<i + n]; i += n
        } while i < raw.count
        let adler = s2 << 16 | s1
        z += [24, 16, 8, 0].map { UInt8(adler >> $0 & 255) }
        func be(_ v: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8(UInt32(v) >> $0 & 255) } }
        func chunk(_ t: String, _ d: [UInt8]) -> [UInt8] {
            let body = Array(t.utf8) + d, crc = ~body.reduce(0xFFFF_FFFF as UInt32) { c, v in crcTable[Int((c ^ UInt32(v)) & 255)] ^ (c >> 8) }
            return be(d.count) + body + be(Int(crc))
        }
        return Data([137, 80, 78, 71, 13, 10, 26, 10] + chunk("IHDR", be(bw) + be(bh) + [8, 6, 0, 0, 0]) + chunk("IDAT", z) + chunk("IEND", []))
    }
}
#endif
