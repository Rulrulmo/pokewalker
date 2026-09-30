#if os(Windows)
import Foundation
import WinSDK
// Windows' Fonts (Core/Canvas.swift) through GDI: the system face is Malgun Gothic (맑은 고딕, where the Mac has SF + Apple SD Gothic Neo), Galmuri comes
// from the bundled files (private to the process, nothing installed). GDI measures in whole pixels: widths and metrics are read at 16x the size.
// Malgun Gothic's Hangul is a full em wide (the Mac's Apple SD Gothic Neo: 0.865): Hangul is set at `fit` of the size, the rest at the size (Malgun's
// Latin and digits are SF's height, 9 % narrower), so lines lay out as on the Mac (the widest nature note: 170.9 pt at 1, the Mac 154.7, its line 162).
// Malgun has only a regular and a bold: medium and semibold are the regular grown by a stroke (emboldened), as are the rest a little (the Mac's
// text is heavier than GDI's).

@MainActor final class WinFonts: Fonts {
    static let over: CGFloat = 16                                                                 // measuring scale
    static let fit: CGFloat = 0.9                                                                 // Hangul's share of the size
    static let embolden: [FontSpec.Weight: CGFloat] = [.regular: 0.015, .medium: 0.035, .semibold: 0.045, .bold: 0.02]   // ponytail: grown by eye off the CI renders (ink ≈ the Mac's)
    let dc: HDC = CreateCompatibleDC(nil)
    let files = ["Galmuri9.ttf", "Galmuri7.ttf"].compactMap { resource($0) }                     // kept alive while GDI may read them
    struct FontKey: Hashable { let f: FontSpec; let hangul: Bool; let k: CGFloat?; let smooth: Bool }
    var cache: [FontKey: HFONT] = [:]
    struct MaskKey: Hashable { let s: String; let f: FontSpec; let scale: CGFloat; let qx: Int }
    var masks: [MaskKey: TextMask] = [:], metricCache: [FontSpec: (ascender: CGFloat, capHeight: CGFloat)] = [:]
    init() { for d in files { var n: DWORD = 0; _ = d.withUnsafeBytes { AddFontMemResourceEx(UnsafeMutableRawPointer(mutating: $0.baseAddress), DWORD($0.count), nil, &n) } } }

    /// f's GDI font for Hangul or the rest, at k times its size (nil: its own; Galmuri at its pixel size, 9 at 10 px, 7 at 8 px), greyscale-smoothed
    /// (never ClearType) or not.
    func font(_ f: FontSpec, hangul: Bool, k: CGFloat?, smooth: Bool) -> HFONT {
        let key = FontKey(f: f, hangul: hangul, k: k, smooth: smooth)
        if let h = cache[key] { return h }
        let (face, px): (String, CGFloat) = switch f.face { case .system: ("Malgun Gothic", f.size * (hangul ? WinFonts.fit : 1)); case .galmuri9: ("Galmuri9 Regular", 10); case .galmuri7: ("Galmuri7 Regular", 8) }
        let h: HFONT? = face.withCString(encodedAs: UTF16.self) {
            CreateFontW(-Int32((px * (k ?? 1)).rounded()), 0, 0, 0, f.weight == .bold ? 700 : 400, 0, 0, 0, DWORD(DEFAULT_CHARSET), DWORD(OUT_TT_PRECIS), DWORD(CLIP_DEFAULT_PRECIS),
                        DWORD(smooth ? ANTIALIASED_QUALITY : NONANTIALIASED_QUALITY), DWORD(DEFAULT_PITCH), $0)
        }
        cache[key] = h!; return h!
    }
    /// s cut where it goes in or out of Hangul (syllables, jamo).
    func runs(_ s: String) -> [(s: String, hangul: Bool)] {
        var out: [(s: String, hangul: Bool)] = []
        for u in s.unicodeScalars {
            let h = (0xAC00...0xD7A3).contains(u.value) || (0x1100...0x11FF).contains(u.value) || (0x3130...0x318F).contains(u.value)
            if out.last?.hangul == h { out[out.count - 1].s.unicodeScalars.append(u) } else { out.append((String(u), h)) }
        }
        return out
    }
    /// The face GDI picked for f (a missing one falls back silently).
    func face(_ f: FontSpec) -> String {
        SelectObject(dc, font(f, hangul: false, k: nil, smooth: false)); var b = [WCHAR](repeating: 0, count: 64); _ = GetTextFaceW(dc, Int32(b.count), &b)
        return String(decoding: b.prefix { $0 != 0 }, as: UTF16.self)
    }
    /// s's advance in a GDI font (pixels).
    func advance(_ s: String, _ h: HFONT) -> Int {
        SelectObject(dc, h); let u = Array(s.utf16); var sz = tagSIZE()                          // (SIZE is the 크기 menu's here)
        _ = GetTextExtentPoint32W(dc, u, Int32(u.count), &sz); return Int(sz.cx)
    }
    func width(_ s: String, _ f: FontSpec) -> CGFloat {
        CGFloat(runs(s).reduce(0) { $0 + advance($1.s, font(f, hangul: $1.hangul, k: WinFonts.over, smooth: true)) }) / WinFonts.over
    }
    /// The Mac's numbers (NSFont.ascender / capHeight: hhea's ascender, OS/2's cap height), the Latin face's (caps are centred by it), read off
    /// the font's own tables (OUTLINETEXTMETRIC's cap height isn't filled in).
    func metrics(_ f: FontSpec) -> (ascender: CGFloat, capHeight: CGFloat) {
        if let m = metricCache[f] { return m }
        SelectObject(dc, font(f, hangul: false, k: WinFonts.over, smooth: true))
        func int16(_ tag: String, _ at: Int) -> CGFloat {                                        // a big-endian 16-bit field of a table ('head', 'hhea', 'OS/2')
            let t = tag.utf8.reversed().reduce(DWORD(0)) { $0 << 8 | DWORD($1) }; var b: [UInt8] = [0, 0]
            guard GetFontData(dc, t, DWORD(at), &b, 2) == 2 else { return 0 }
            return CGFloat(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1])))
        }
        let em = int16("head", 18), m = em > 0 ? (int16("hhea", 4) / em * f.size, int16("OS/2", 88) / em * f.size) : (0, 0)
        metricCache[f] = m; return m
    }
    /// White on black into a top-down 32-bit DIB, the baseline one row up from the bottom (as the Mac's CoreText draw).
    func dots(_ s: String, _ f: FontSpec, rows h: Int) -> [[Bool]] {
        let font = font(f, hangul: false, k: nil, smooth: false), w = max(1, advance(s, font)), u = Array(s.utf16)
        var bi = BITMAPINFO(); bi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bi.bmiHeader.biWidth = LONG(w); bi.bmiHeader.biHeight = -LONG(h); bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32   // BI_RGB (0), zero-filled
        var bits: UnsafeMutableRawPointer? = nil
        guard let bmp = CreateDIBSection(dc, &bi, UINT(DIB_RGB_COLORS), &bits, nil, 0), let bits else { return Array(repeating: Array(repeating: false, count: w), count: h) }
        let old = SelectObject(dc, bmp); SelectObject(dc, font)
        SetBkMode(dc, TRANSPARENT); SetTextColor(dc, 0xFF_FFFF); SetTextAlign(dc, UINT(TA_BASELINE))
        _ = TextOutW(dc, 0, Int32(h - 1), u, Int32(u.count)); GdiFlush()
        let px = bits.assumingMemoryBound(to: UInt32.self)
        let on = (0..<h).map { y in (0..<w).map { x in px[y * w + x] >> 8 & 255 > 127 } }
        SelectObject(dc, old); DeleteObject(bmp)
        return on
    }
}

/// The canvas's text (Windows/SoftCanvas.swift): GDI draws s white on black at 4x its device size, greyscale-smoothed, a run a script, grown by the
/// weight's stroke; 4 x 4 pixels average down into one: its coverage, with the fractional sizes and soft edges of the Mac's (GDI alone rounds sizes
/// to whole pixels and hints hard).
extension WinFonts: TextMasks {
    func mask(_ s: String, _ f: FontSpec, scale: CGFloat, qx: Int) -> TextMask {
        let key = MaskKey(s: s, f: f, scale: scale, qx: qx)
        if let m = masks[key] { return m }
        if masks.count > 2000 { masks.removeAll() }                                          // ponytail: drop all (the LCD's counts change), an LRU if it ever shows
        var bf = f; bf.size *= scale                                                             // fonts by device size
        let parts = runs(s).map { r -> (u: [UInt16], font: HFONT, adv: Int) in
            let h = font(bf, hangul: r.hangul, k: 4, smooth: true); return (Array(r.s.utf16), h, advance(r.s, h))
        }
        var ascent = 0, descent = 0
        for p in parts { SelectObject(dc, p.font); var tm = TEXTMETRICW(); _ = GetTextMetricsW(dc, &tm); ascent = max(ascent, Int(tm.tmAscent)); descent = max(descent, Int(tm.tmDescent)) }
        let pad = 12, grow = Int(((WinFonts.embolden[f.weight] ?? 0) * bf.size * 4).rounded())    // 4x pixels
        let oy = (pad + ascent + 3) / 4, W = (parts.reduce(0) { $0 + $1.adv } + 2 * pad + 3) / 4 + 1, H = oy + (descent + pad + 3) / 4, w4 = W * 4, h4 = H * 4
        var bi = BITMAPINFO(); bi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bi.bmiHeader.biWidth = LONG(w4); bi.bmiHeader.biHeight = -LONG(h4); bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32
        var bits: UnsafeMutableRawPointer? = nil
        guard let bmp = CreateDIBSection(dc, &bi, UINT(DIB_RGB_COLORS), &bits, nil, 0), let bits else { return TextMask(w: 0, h: 0, ox: 0, oy: 0, a: []) }
        let old = SelectObject(dc, bmp)
        SetBkMode(dc, TRANSPARENT); SetTextColor(dc, 0xFF_FFFF); SetTextAlign(dc, UINT(TA_BASELINE))
        var pen = pad + qx
        for p in parts { SelectObject(dc, p.font); _ = TextOutW(dc, Int32(pen), Int32(oy * 4), p.u, Int32(p.u.count)); pen += p.adv }
        GdiFlush()
        let px = bits.assumingMemoryBound(to: UInt32.self)
        var g = (0..<w4 * h4).map { UInt8(px[$0] >> 8 & 255) }
        SelectObject(dc, old); DeleteObject(bmp)
        if grow > 0 {                                                                            // the stroke grown: a max over grow + 1 pixels across, then down
            let l = grow / 2
            var t = g
            for y in 0..<h4 { for x in 0..<w4 { var m: UInt8 = 0; for d in max(0, x - l)...min(w4 - 1, x - l + grow) { m = max(m, g[y * w4 + d]) }; t[y * w4 + x] = m } }
            for y in 0..<h4 { for x in 0..<w4 { var m: UInt8 = 0; for d in max(0, y - l)...min(h4 - 1, y - l + grow) { m = max(m, t[d * w4 + x]) }; g[y * w4 + x] = m } }
        }
        var a = [UInt8](repeating: 0, count: W * H)
        for y in 0..<H { for x in 0..<W {
            var sum = 0
            for j in 0..<4 { for i in 0..<4 { sum += Int(g[(y * 4 + j) * w4 + x * 4 + i]) } }
            a[y * W + x] = UInt8(sum / 16)
        } }
        let m = TextMask(w: W, h: H, ox: pad / 4, oy: oy, a: a); masks[key] = m; return m
    }
}
#endif
