#if os(macOS)
import AppKit
// The Mac's device view: it owns the Walker (Core/Walker.swift) and is its host — it passes on the clock, clicks and keys; the walker draws the card
// on it (Core/Card.swift, through Mac/MacCanvas.swift).

final class WalkerView: NSView {
    let walker: Walker
    var stickersShown: [CGRect] = []                                     // the walker's stickers the cursor rects were made for
    var fast: Timer?                                                       // the 30 fps frame timer while a fight or a show plays
    let page = SideView()                                                  // the pane's page: battle / 도감 / 상점 / 메뉴 / 상태
    var shown: FB? = nil                                                   // last composed frame; draw() only when it changes
    var pressed: Int? = nil, pressedAt = Date()
    var anchorTop: CGFloat? = nil                                          // where the user put the card's top (screen y): a tall page lifts it off the Dock, the next short one drops it back
    var fitting = false                                                    // our own resize is moving the window (not the user)
    var lastStatus = ""

    init(walker: Walker) {
        self.walker = walker; super.init(frame: NSRect(origin: .zero, size: devSize))
        walker.host = self; page.walker = walker; addSubview(page); layoutPage()
    }
    /// The page view's place under the band (after a size change too).
    func layoutPage() { let y = (Layout.pane * K).rounded(); page.frame = NSRect(x: 0, y: y, width: Layout.w * K, height: max(0, (walker.cardH * K).rounded() - y)); page.needsDisplay = true }   // whole points: crisp at 크게 on a 1x screen
    /// The window follows the page: its top stays where the user put it (the LCD and keys never move); a page too tall for the space under it
    /// lifts the card, and a shorter one lets it back down.
    func fitWindow() {
        let size = NSSize(width: Layout.w * K, height: (walker.cardH * K).rounded())
        if let w = window {
            let f = w.frame, top = anchorTop ?? f.maxY
            if anchorTop == nil { anchorTop = top }
            let g = WalkerView.onScreen(NSRect(x: f.minX, y: top - size.height, width: size.width, height: size.height), in: w.screen?.visibleFrame)
            if g != f { fitting = true; w.setFrame(g, display: true); fitting = false; w.invalidateShadow() }   // the card's shadow follows its new outline
        } else if frame.size != size { setFrameSize(size) }
        layoutPage(); window?.invalidateCursorRects(for: self)
    }
    override func viewDidMoveToWindow() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: nil)
        if let w = window { NotificationCenter.default.addObserver(self, selector: #selector(windowMoved(_:)), name: NSWindow.didMoveNotification, object: w) }
    }
    @objc func windowMoved(_ n: Notification) { if !fitting, let w = window { anchorTop = w.frame.maxY } }   // the user dragged it: that's the new place
    // MARK: the walker's host (the banners and the step counter: Mac/MacHost.swift)
    func redraw(_ part: CardPart) {
        switch part {
        case .all: shown = nil; needsDisplay = true; window?.invalidateCursorRects(for: self)          // (the stickers' hands follow the screen)
        case .lcd: setNeedsDisplay(lcdRect)
        case .page: page.needsDisplay = true
        case .key: setNeedsDisplay(NSRect(x: 0, y: (Layout.seam - 16) * K, width: bounds.width, height: 32 * K))
        case .title: setNeedsDisplay(NSRect(x: 0, y: 0, width: bounds.width, height: Layout.top * K))
        }
    }
    func resized() { fitWindow() }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The clock, 10 a second (main.swift's timer): the walker's rules, the menu-bar title, the frame; 30 fps while something plays.
    @objc func tick(_ sender: Any?) {
        walker.tick(Date())
        let st = walker.stickerRects + (walker.chevron != nil ? [chevronRect] : []); if st != stickersShown { stickersShown = st; window?.invalidateCursorRects(for: self) }   // the hands over the stickers / ⌄ follow the screen
        updateStatus()
        frame(nil)
        let busy = walker.busy
        if busy != (fast != nil) {
            fast?.invalidate(); fast = nil
            if busy { let t = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(frame(_:)), userInfo: nil, repeats: true); t.tolerance = 0.005; RunLoop.main.add(t, forMode: .common); fast = t }
        }
    }
    /// The pane and the screen, redrawn if the frame changed (the tick's, and 30 a second while something plays).
    @objc func frame(_ sender: Any?) {
        let now = Date()
        if window?.isVisible == true { walker.refreshPane(now) }
        guard window?.isVisible ?? true else { return }                                         // hidden in the menu bar: rules keep running, nothing to draw
        walker.stroll(now)
        let fb = walker.compose(now)
        if fb.px != shown?.px || fb.col != shown?.col || fb.runs != shown?.runs || fb.flips != shown?.flips || fb.sprites != shown?.sprites || fb.pics != shown?.pics || fb.over != shown?.over || now.timeIntervalSince(pressedAt) < 0.3 { shown = fb; setNeedsDisplay(now.timeIntervalSince(pressedAt) < 0.3 ? bounds : lcdRect) }   // idle home = ~2 redraws a second
    }
    @objc func save(_ sender: Any?) { walker.save() }                                           // going to sleep
    @objc func woke(_ sender: Any?) { walker.woke() }                                           // awake: what changed goes up
    @objc func poweringOff(_ sender: Any?) { walker.shuttingDown = true }                       // logout / shutdown: no update goes in at this quit
    @objc func quitting(_ sender: Any?) { walker.quitSave() }                                     // quitting: the steps a fight held back count

    // MARK: input
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let i = buttons.firstIndex(where: { hypot($0.c.x - p.x, $0.c.y - p.y) <= $0.r + 2 * K }) {
            if i == 1 || i == 4, e.clickCount > 1 { return }                                        // ● or 메뉴 twice fast: once (the 2nd would act on what the 1st opened)
            pressed = i; pressedAt = Date(); walker.press(i)
            perform(#selector(tick(_:)), with: nil, afterDelay: 0.15, inModes: [.common])
        } else if chevronRect.contains(p), walker.chevron != nil { walker.toggleStatus() }
        else if lcdRect.contains(p), e.clickCount == 1 || walker.stickerAt(Int((p.x - lcdRect.minX) / PX), Int((p.y - lcdRect.minY) / PX)) == nil,   // a sticker's 2nd click would swap back
                  walker.touch(Int((p.x - lcdRect.minX) / PX), Int((p.y - lcdRect.minY) / PX)) { needsDisplay = true }
        else { window?.performDrag(with: e) }
    }
    override func keyDown(with e: NSEvent) {                                                  // ← → ↑ ↓, page up / down, tab, return / space, esc (= ↩ 뒤로), M (= 메뉴 / 홈): Walker.key
        let keys: [UInt16: Walker.Key] = [123: .left, 124: .right, 126: .up, 125: .down, 116: .pageUp, 121: .pageDown, 48: .tab, 36: .enter, 49: .enter, 53: .back, 46: .menu]
        if let k = keys[e.keyCode], walker.key(k, shift: e.modifierFlags.contains(.shift), held: e.isARepeat) { return }
        super.keyDown(with: e)
    }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() {
        for b in buttons { addCursorRect(NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r), cursor: .pointingHand) }
        for r in walker.stickerRects { addCursorRect(r, cursor: .pointingHand) }
        if walker.chevron != nil { addCursorRect(chevronRect, cursor: .pointingHand) }                     // the walker's stickers on home: a tap walks with that one
    }

    override func menu(for event: NSEvent) -> NSMenu? { buildMenu() }

    // MARK: drawing (Core/Card.swift)
    override func draw(_ dirty: NSRect) {
        let down = pressed.flatMap { Date().timeIntervalSince(pressedAt) < 0.15 ? $0 : nil }
        walker.drawCard(MacCanvas(scale: window?.backingScaleFactor ?? 2), bounds, shown: shown, down: down, lcdOnly: lcdRect.contains(dirty))   // most frames: only the screen changed
    }
}
final class Panel: NSPanel { override var canBecomeKey: Bool { true } }                    // arrow keys work after a click; still never activates the app
#endif
