#if os(macOS)
import AppKit
// The pane's page on the Mac: the card's white bottom under the band. The walker's page draws itself on it (Core/Page.swift); clicks, the scroll wheel
// and the pointer go by what it drew (its hits).

final class SideView: NSView {
    let art = Page()                                                       // the page's drawing and its hits
    var walker: Walker? { get { art.walker } set { art.walker = newValue } }
    var content: PaneContent { art.content }
    var scrolled: CGFloat = 0                                              // trackpad scroll not yet turned into a row step
    var downOn = 0                                                         // the page a click began on: a double-click's 2nd click on another page is dropped
    var pageKind: Int {
        let c = content
        return [c.battle != nil, c.dex != nil, c.grid != nil, c.shop != nil, c.menu != nil, c.mon != nil, c.radar != nil, c.card != nil, c.learn != nil, c.tower != nil, c.items != nil].firstIndex(of: true).map { $0 + 1 } ?? 0
    }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var needsPanelToBecomeKey: Bool { true }                                           // a click here makes the body key: the keys keep working
    override func menu(for event: NSEvent) -> NSMenu? { superview?.menu(for: event) }          // ctrl-click opens the walker's menu, like a right-click
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil), c = content
        guard let k = art.hits.first(where: { $0.0.contains(p) })?.1 else { window?.performDrag(with: e); return }   // not on a button: drag the whole body
        if e.clickCount == 1 { downOn = pageKind } else if c.battle != nil || c.shop?.ask != nil || c.mon != nil || pageKind != downOn { return }   // a double-click's 2nd click on what the 1st one opened (a move, 예, 함께 under 아니오, a cell under 메뉴's tile): ignored
        if k >= 5000, k < 10000 { walker?.pageTap(k) } else if k >= 4000 { walker?.gridTap(k) } else if k >= 3000 { walker?.menuTap(k - 3000) } else if k >= 2000 { walker?.shopTap(k) } else { walker?.sidePick(k) }
    }
    override func scrollWheel(with e: NSEvent) {                                                 // the shop list: a row per notch (or 6 pt of trackpad); a grid: a page (24 pt)
        let grid = content.grid != nil
        guard content.shop != nil || grid else { return super.scrollWheel(with: e) }
        let notch: CGFloat = grid ? 24 : 6
        func step(_ d: Int) { if grid { walker?.gridStep(d * GridModel.perPage) } else { walker?.shopRow(d) } }   // rows only, never the amount
        if !e.hasPreciseScrollingDeltas { if e.scrollingDeltaY != 0 { step(e.scrollingDeltaY > 0 ? -1 : 1) }; return }
        if e.phase == .began { scrolled = 0 }
        scrolled += e.scrollingDeltaY
        while abs(scrolled) >= notch { step(scrolled > 0 ? -1 : 1); scrolled -= scrolled > 0 ? notch : -notch }
    }
    override func resetCursorRects() { for (r, _) in art.hits { addCursorRect(r, cursor: .pointingHand) } }
    override func draw(_ dirty: NSRect) {
        art.draw(on: MacCanvas(scale: window?.backingScaleFactor ?? 2))
        window?.invalidateCursorRects(for: self)
    }
}
#endif
