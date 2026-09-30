import AppKit
// The Mac's Canvas and Fonts (Core/Canvas.swift): AppKit into the current NSGraphicsContext — the very calls the card was always drawn with, so it looks
// the same to the pixel. A Bitmap becomes an NSImage on its first draw (kept on it); Galmuri comes from the bundled files.

extension Color {
    var ns: NSColor {
        let c = grey ? NSColor(white: red, alpha: alpha) : NSColor(red: red, green: green, blue: blue, alpha: alpha)
        return tint < 1 ? c.blended(withFraction: 1 - tint, of: .white) ?? c : c
    }
}
extension FontSpec {
    var ns: NSFont {
        let w: NSFont.Weight = switch weight { case .regular: .regular; case .medium: .medium; case .semibold: .semibold; case .bold: .bold }
        return .systemFont(ofSize: size, weight: w)
    }
}
extension Path {
    var ns: NSBezierPath {
        let b = NSBezierPath()
        for p in parts {
            switch p {
            case .rect(let r): b.appendRect(r)
            case .oval(let r): b.appendOval(in: r)
            case .rounded(let r, let rad): b.appendRoundedRect(r, xRadius: rad, yRadius: rad)
            case .move(let q): b.move(to: q)
            case .line(let q): b.line(to: q)
            case .close: b.close()
            }
        }
        return b
    }
}
/// The pixels as an NSImage (premultiplied, as CGImage wants it), made once per Bitmap.
@MainActor func nsImage(_ b: Bitmap) -> NSImage {
    if let i = b.native as? NSImage { return i }
    let p = b.pic, pre = p.px.map { c -> UInt32 in
        let a = c >> 24; guard a < 255 else { return c }
        let r: UInt32 = (c >> 16 & 255) * a / 255, g: UInt32 = (c >> 8 & 255) * a / 255, b: UInt32 = (c & 255) * a / 255
        return a << 24 | r << 16 | g << 8 | b
    }
    let img = CGImage(width: p.w, height: p.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: p.w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                      provider: CGDataProvider(data: pre.withUnsafeBufferPointer { Data(buffer: $0) } as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let i = NSImage(cgImage: img, size: NSSize(width: p.w, height: p.h)); b.native = i; return i
}

/// Draws into NSGraphicsContext.current (a view's draw); scale = its window's backing scale (2 without one: renders, the self-test).
@MainActor struct MacCanvas: Canvas {
    let scale: CGFloat
    var g: NSGraphicsContext { NSGraphicsContext.current! }
    func fill(_ r: CGRect, _ c: Color) { c.ns.setFill(); r.fill() }
    func fill(_ p: Path, _ c: Color) { c.ns.setFill(); p.ns.fill() }
    func stroke(_ p: Path, _ c: Color, width: CGFloat, round: Bool) {
        let b = p.ns; c.ns.setStroke(); b.lineWidth = width
        if round { b.lineCapStyle = .round; b.lineJoinStyle = .round }
        b.stroke()
    }
    func clip(_ p: Path) { p.ns.addClip() }
    func save() { NSGraphicsContext.saveGraphicsState() }
    func restore() { NSGraphicsContext.restoreGraphicsState() }
    func antialias(_ on: Bool) { g.shouldAntialias = on }
    func rotate(_ degrees: CGFloat, about c: CGPoint) { let t = NSAffineTransform(); t.translateX(by: c.x, yBy: c.y); t.rotate(byDegrees: degrees); t.translateX(by: -c.x, yBy: -c.y); t.concat() }
    func image(_ b: Bitmap, _ r: CGRect, alpha: CGFloat) {
        g.imageInterpolation = .none
        nsImage(b).draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
    }
    func text(_ s: String, _ p: CGPoint, _ f: FontSpec, _ c: Color) { (s as NSString).draw(at: p, withAttributes: [.font: f.ns, .foregroundColor: c.ns]) }
    func gradient(_ r: CGRect, from: Color, to: Color, angle: CGFloat) { NSGradient(starting: from.ns, ending: to.ns)!.draw(in: r, angle: angle) }
    func beginLayer(alpha: CGFloat) { let cg = g.cgContext; cg.saveGState(); cg.setAlpha(alpha); cg.beginTransparencyLayer(auxiliaryInfo: nil) }
    func endLayer() { let cg = g.cgContext; cg.endTransparencyLayer(); cg.restoreGState() }
    func glyph(_ gl: Glyph, _ at: CGPoint, _ size: CGFloat, _ c: Color, alpha: CGFloat) {
        let (name, label) = switch gl { case .back: ("arrow.uturn.backward", "뒤로"); case .menu: ("square.grid.2x2.fill", "메뉴"); case .home: ("house.fill", "홈") }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: size, weight: .bold).applying(.init(paletteColors: [c.ns])))
        if let img { let s = img.size; img.draw(in: NSRect(x: at.x - s.width / 2, y: at.y - s.height / 2, width: s.width, height: s.height), from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil) }
    }
}

/// Galmuri at its native sizes (9 at 10 px, 7 at 8 px), from the bundled files.
@MainActor let galmuri: [CTFont?] = [("Galmuri9", 10.0), ("Galmuri7", 8.0)].map { f, size in
    resource(f + ".ttf").flatMap { CTFontManagerCreateFontDescriptorFromData($0 as CFData) }.map { CTFontCreateWithFontDescriptor($0, size, nil) }
}
/// AppKit's text metrics; the dot text through CoreText, unsmoothed, into a grey bitmap.
@MainActor final class MacFonts: Fonts {
    func width(_ s: String, _ f: FontSpec) -> CGFloat { (s as NSString).size(withAttributes: [.font: f.ns]).width }
    func metrics(_ f: FontSpec) -> (ascender: CGFloat, capHeight: CGFloat) { let n = f.ns; return (n.ascender, n.capHeight) }
    func dots(_ s: String, _ f: FontSpec, rows h: Int) -> [[Bool]] {
        let g: CTFont? = f.face == .system ? nil : galmuri[f.face == .galmuri9 ? 0 : 1], font: AnyObject = g ?? NSFont.systemFont(ofSize: f.size)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]))
        let w = max(1, Int(ceil(CTLineGetTypographicBounds(line, nil, nil, nil))))
        var px = [UInt8](repeating: 0, count: w * h)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            ctx.setShouldAntialias(false); ctx.setShouldSmoothFonts(false); ctx.setFillColor(gray: 1, alpha: 1)
            ctx.textPosition = CGPoint(x: 0, y: 1); CTLineDraw(line, ctx)
        }
        return (0..<h).map { y in (0..<w).map { px[y * w + $0] > 127 } }
    }
}
