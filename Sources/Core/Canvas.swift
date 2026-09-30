import Foundation
#if canImport(CoreGraphics)
import CoreGraphics                                                                // CGRect's members on Apple platforms (swift-corelibs-foundation has them elsewhere)
#endif
// What the core draws on. The card, the LCD and the pane's pages (Core/Card.swift, Core/Page.swift) are drawn through a Canvas, text is measured
// through `fonts` (the LCD's layout needs widths while composing, with nothing to draw on). A platform sets `fonts` at launch, next to `settings`,
// and hands its views' draws a Canvas. The Mac's: Mac/MacCanvas.swift (the AppKit calls the card was always drawn with).

/// A colour: sRGB components, or (grey) a white level — the Mac keeps its own grey space for those, as the look was drawn; tint < 1: only that much
/// of it over white (Ink.tint).
struct Color: Equatable {
    var red, green, blue: CGFloat, alpha: CGFloat = 1
    var grey = false, tint: CGFloat = 1
    static let white = Color(white: 1), clear = Color(white: 0, alpha: 0), gray = Color(white: 0.5)
    func withAlphaComponent(_ a: CGFloat) -> Color { var c = self; c.alpha = a; return c }
    var luma: CGFloat { 0.299 * red + 0.587 * green + 0.114 * blue }
    var brightness: CGFloat { max(red, green, blue) }                    // HSB's
}
extension Color { init(white: CGFloat, alpha: CGFloat = 1) { self.init(red: white, green: white, blue: white, alpha: alpha, grey: true) } }

/// A font: the system's (SF on the Mac) at a size (points) and weight, or Galmuri at its pixel size (the dot text: textDots).
struct FontSpec: Hashable {
    enum Weight { case regular, medium, semibold, bold }
    enum Face { case system, galmuri9, galmuri7 }
    var size: CGFloat; var weight = Weight.regular; var face = Face.system
}

/// A shape to fill, stroke or clip to: rectangles, ovals, rounded rectangles and lines, in the order added.
struct Path {
    enum Part { case rect(CGRect), oval(CGRect), rounded(CGRect, CGFloat), move(CGPoint), line(CGPoint), close }
    var parts: [Part] = []
    static func rect(_ r: CGRect) -> Path { Path(parts: [.rect(r)]) }
    static func oval(_ r: CGRect) -> Path { Path(parts: [.oval(r)]) }
    static func rounded(_ r: CGRect, _ radius: CGFloat) -> Path { Path(parts: [.rounded(r, radius)]) }
    /// Lines through the points (closed: back to the first).
    static func poly(_ pts: [CGPoint], closed: Bool = true) -> Path { Path(parts: pts.enumerated().map { (i, p) -> Part in i == 0 ? .move(p) : .line(p) } + (closed ? [.close] : [])) }
    mutating func add(_ r: CGRect) { parts.append(.rect(r)) }
}

/// The keys' pictures (the Mac: SF Symbols): ↩, 메뉴 (a grid), 홈 (a house).
enum Glyph { case back, menu, home }

/// Pixels to draw — a sprite, a picture, an icon as the LCD or the pane shows it (0xAARRGGBB, not premultiplied); `native` = the platform's
/// own image of them, made on its first draw and kept as long as this is (the core's caches decide that).
@MainActor final class Bitmap {
    let pic: Pic
    var native: AnyObject? = nil
    init(_ pic: Pic) { self.pic = pic }
}

/// A surface in points, y down (the Mac: a flipped view's). State (clip, rotation, antialiasing, a layer) lasts until restore() / endLayer().
@MainActor protocol Canvas {
    /// Device pixels per point: pictures and sprites snap to whole ones, the LCD's dot grid shows from 8.
    var scale: CGFloat { get }
    /// A plain rectangle (the Mac: a rect fill, not a path), or any path, filled; a path stroked (round: round caps and joins).
    func fill(_ r: CGRect, _ c: Color)
    func fill(_ p: Path, _ c: Color)
    func stroke(_ p: Path, _ c: Color, width: CGFloat, round: Bool)
    func clip(_ p: Path)
    func save()
    func restore()
    func antialias(_ on: Bool)
    /// Turn what follows by `degrees` (clockwise on screen) about c.
    func rotate(_ degrees: CGFloat, about c: CGPoint)
    /// Pixels stretched over r, unsmoothed (nearest neighbour), at alpha.
    func image(_ b: Bitmap, _ r: CGRect, alpha: CGFloat)
    /// One line of text from p, its top-left: the baseline is fonts.metrics(f).ascender below p.
    func text(_ s: String, _ p: CGPoint, _ f: FontSpec, _ c: Color)
    /// A linear gradient over r, from `from` to `to` (angle in degrees, 90 = from the top edge down on a y-down canvas).
    func gradient(_ r: CGRect, from: Color, to: Color, angle: CGFloat)
    /// What follows drawn as one layer, then laid down at alpha (endLayer).
    func beginLayer(alpha: CGFloat)
    func endLayer()
    /// A key's picture centred on c, `size` points, bold, in colour c at alpha.
    func glyph(_ g: Glyph, _ at: CGPoint, _ size: CGFloat, _ c: Color, alpha: CGFloat)
}
extension Canvas { func stroke(_ p: Path, _ c: Color, width: CGFloat) { stroke(p, c, width: width, round: false) } }

/// Text as the platform sets it: widths, the two numbers `say` centres caps by, and Galmuri's dots for the dot text (textDots).
@MainActor protocol Fonts {
    func width(_ s: String, _ f: FontSpec) -> CGFloat
    func metrics(_ f: FontSpec) -> (ascender: CGFloat, capHeight: CGFloat)
    /// s in f, unsmoothed, `rows` tall with the baseline one row up from the bottom: on / off per dot, top row first, as wide as the text.
    func dots(_ s: String, _ f: FontSpec, rows: Int) -> [[Bool]]
}
@MainActor var fonts: (any Fonts)! = nil
