#if os(Windows)
import Foundation
import WinSDK
// Windows' Fonts (Core/Canvas.swift) through GDI: the system face is Malgun Gothic (맑은 고딕, where the Mac has SF), Galmuri comes from the bundled
// files (private to the process, nothing installed). GDI measures in whole pixels: widths and metrics are read at 16x the size and scaled back.
// Malgun Gothic's Hangul is a full em wide (the Mac's Apple SD Gothic Neo: 0.865): the system face is set at `fit` of its size, so Korean lines
// lay out as on the Mac (the widest nature note: 170.9 pt at 1, the Mac 154.7, its line 162).

@MainActor final class WinFonts: Fonts {
    static let over: CGFloat = 16                                                                 // measuring scale
    static let fit: CGFloat = 0.9                                                                 // ponytail: one factor for every script (Latin / digits come out ~20% narrower than SF's); P4: per script, against screenshots
    let dc: HDC = CreateCompatibleDC(nil)
    let files = ["Galmuri9.ttf", "Galmuri7.ttf"].compactMap { resource($0) }                     // kept alive while GDI may read them
    var measuring: [FontSpec: HFONT] = [:], drawing: [FontSpec: HFONT] = [:]
    init() { for d in files { var n: DWORD = 0; _ = d.withUnsafeBytes { AddFontMemResourceEx(UnsafeMutableRawPointer(mutating: $0.baseAddress), DWORD($0.count), nil, &n) } } }

    /// f as a GDI font: for measuring (16x, smoothed), or for dots (its own size, unsmoothed; Galmuri at its pixel size, 9 at 10 px, 7 at 8 px).
    func gdi(_ f: FontSpec, dots: Bool) -> HFONT {
        if let h = (dots ? drawing : measuring)[f] { return h }
        let (face, px): (String, CGFloat) = switch f.face { case .system: ("Malgun Gothic", f.size * WinFonts.fit); case .galmuri9: ("Galmuri9 Regular", 10); case .galmuri7: ("Galmuri7 Regular", 8) }
        let weight: Int32 = switch f.weight { case .regular: 400; case .medium: 500; case .semibold: 600; case .bold: 700 }
        let h: HFONT = face.withCString(encodedAs: UTF16.self) {
            CreateFontW(-Int32((px * (dots ? 1 : WinFonts.over)).rounded()), 0, 0, 0, weight, 0, 0, 0, DWORD(DEFAULT_CHARSET), DWORD(OUT_TT_PRECIS), DWORD(CLIP_DEFAULT_PRECIS),
                        DWORD(dots ? NONANTIALIASED_QUALITY : ANTIALIASED_QUALITY), DWORD(DEFAULT_PITCH), $0)
        }
        if dots { drawing[f] = h } else { measuring[f] = h }
        return h
    }
    /// The face GDI picked for f (a missing one falls back silently).
    func face(_ f: FontSpec) -> String {
        SelectObject(dc, gdi(f, dots: true)); var b = [WCHAR](repeating: 0, count: 64); _ = GetTextFaceW(dc, Int32(b.count), &b)
        return String(decoding: b.prefix { $0 != 0 }, as: UTF16.self)
    }
    /// s's advance in f's GDI font (pixels).
    func advance(_ s: String, _ h: HFONT) -> Int {
        SelectObject(dc, h); let u = Array(s.utf16); var sz = tagSIZE()                          // (SIZE is the 크기 menu's here)
        _ = GetTextExtentPoint32W(dc, u, Int32(u.count), &sz); return Int(sz.cx)
    }
    func width(_ s: String, _ f: FontSpec) -> CGFloat { CGFloat(advance(s, gdi(f, dots: false))) / WinFonts.over }
    /// The Mac's numbers: the hhea ascender (otmMacAscent) and OS/2's cap height.
    func metrics(_ f: FontSpec) -> (ascender: CGFloat, capHeight: CGFloat) {
        SelectObject(dc, gdi(f, dots: false)); var m = OUTLINETEXTMETRICW()
        _ = GetOutlineTextMetricsW(dc, UINT(MemoryLayout<OUTLINETEXTMETRICW>.size), &m)
        return (CGFloat(m.otmMacAscent) / WinFonts.over, CGFloat(m.otmsCapEmHeight) / WinFonts.over)
    }
    /// White on black into a top-down 32-bit DIB, the baseline one row up from the bottom (as the Mac's CoreText draw).
    func dots(_ s: String, _ f: FontSpec, rows h: Int) -> [[Bool]] {
        let font = gdi(f, dots: true), w = max(1, advance(s, font)), u = Array(s.utf16)
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
#endif
