import AppKit
// The device view: its state, the clock tick, input events and drawing the device around the LCD.

final class WalkerView: NSView {
    var state: Walk
    var screen = Screen.home
    var lastInput = Date(), lastStep = Date.distantPast, lastSave = Date(), levelled = false
    var boxSort = 0                                                        // the 상자 grid's order: 번호순 / 레벨순 / V순 / 최근
    var chainNote: String? = nil                                           // "+6W · 기력의조각" under "연쇄 3!"
    var keyShown: Bool?? = .none                                           // the 메뉴 / 홈 key as last drawn (see homeKey)
    var fast: Timer?                                                       // the 30 fps frame timer while a fight or a show plays
    var usedItem = "몬스터볼"                                                // the potion / ball / revive the current beat names
    var towerRefs: [Int] = [], towerRun = false
    var sideOn = false                                                     // the pane carries the battle's text (the app; not --selftest): the LCD shows the stage only
    let page = SideView()                                                  // the pane's page: battle / 도감 / 상점 / 메뉴 / 상태
    lazy var lastSeason = state.season
    var shown: FB? = nil                                                   // last composed frame; draw() only when it changes
    var emote: (kind: Int, until: Date)? = nil                             // ♪ ♥ ! bubble over the companion
    var animOn: (who: String, dex: Int, since: Date)? = nil                // the entry animation playing (Anim.swift): home's companion or a page's Pokémon
    lazy var rewarded = dexCount                                           // dex count already celebrated (no fanfare for old progress)
    var dexCount: Int { (state.owned ?? []).count }
    var pressed: Int? = nil, pressedAt = Date()
    var rng = Seeded(s: .random(in: .min ... .max))
    var clickCount = 1                                                     // the mouse event's, for touch(): a double-click's 2nd click never buys
    var paneAt = Date.distantPast                                          // when the pane's page was last refreshed
    var cardH = Layout.idle                                                  // the card's height now (card points): the page's
    var statusOpen = UserDefaults.standard.bool(forKey: "statusOpen")      // the title row's ⌄: the status sheet under the band where no page is up
    var hud: SideModel? = nil                                              // a fight's HP boxes, drawn over the LCD
    var titleShown = ""                                                    // the title row as last drawn: a change redraws it
    var anchorTop: CGFloat? = nil                                          // where the user put the card's top (screen y): a tall page lifts it off the Dock, the next short one drops it back
    var fitting = false                                                    // our own resize is moving the window (not the user)

    init(state: Walk) {
        self.state = state; super.init(frame: NSRect(origin: .zero, size: devSize))
        page.walker = self; addSubview(page); layoutPage()
    }
    /// The page view's place under the band (after a size change too).
    func layoutPage() { let y = (Layout.pane * K).rounded(); page.frame = NSRect(x: 0, y: y, width: Layout.w * K, height: max(0, (cardH * K).rounded() - y)); page.needsDisplay = true }   // whole points: crisp at 크게 on a 1x screen
    /// The window follows the page: its top stays where the user put it (the LCD and keys never move); a page too tall for the space under it
    /// lifts the card, and a shorter one lets it back down.
    func fitWindow() {
        let size = NSSize(width: Layout.w * K, height: (cardH * K).rounded())
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
    /// The pane now: its page (and the window's height), the LCD's HP boxes, the title row.
    func refreshPane(_ now: Date, force: Bool = false) {
        let c = paneContent(now)
        if force || c.status == nil || page.status == nil || now.timeIntervalSince(paneAt) >= 1 { page.show(c); paneAt = now }   // steps tick the 상태 sheet: once a second is plenty
        let h = SideView.height(page.content)
        if h != cardH { cardH = h; fitWindow() }
        let hb = sideOn ? c.battle : nil
        if hb != hud { hud = hb; setNeedsDisplay(lcdRect) }
        if homeKey() != keyShown { keyShown = homeKey(); setNeedsDisplay(NSRect(x: 0, y: (Layout.seam - 16) * K, width: bounds.width, height: 32 * K)) }   // the 메뉴 / 홈 key's face
        let t = title(), key = t.title + "|" + t.meta + "|" + "\(t.chevron.map { $0 ? 1 : 0 } ?? 2)"
        if key != titleShown { titleShown = key; setNeedsDisplay(NSRect(x: 0, y: 0, width: bounds.width, height: Layout.top * K)) }
    }
    /// The status sheet open or shut (the title row's chevron).
    func toggleStatus() { statusOpen.toggle(); if persist { UserDefaults.standard.set(statusOpen, forKey: "statusOpen") }; refreshPane(Date(), force: true) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    static func counter() -> UInt32 {
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown].reduce(UInt32(0)) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }
    static func boot() -> Double { var tv = timeval(), n = MemoryLayout<timeval>.size; sysctlbyname("kern.boottime", &tv, &n, nil, 0); return Double(tv.tv_sec) }

    @objc func tick(_ sender: Any?) {
        let now = Date(), before = state.total
        if state.sync(counter: WalkerView.counter(), boot: WalkerView.boot(), at: now) { levelled = true }
        perk(now, stepped: state.total != before)                                               // the companion's animation now and then
        if state.total != before { lastStep = now }
        if state.season != lastSeason {
            lastSeason = state.season
            notify("weather", state.season.name + "이 왔어요", ["꽃이 피었어요", "햇볕이 쨍쨍해요", "단풍이 들었어요", "눈이 쌓여요"][state.season.rawValue] + " · 게임 속 \(seasonDays)일마다 계절이 바뀌어요")
            if case .home = screen { screen = .say([state.season.name + "이 왔다!"], next: .home, since: now) }
        }
        if state.weatherDue, state.rollWeather(&rng) {
            let w = state.weather ?? .sunny
            notify("weather", w.news, w.types.map { typeKo[$0] ?? $0 }.joined(separator: "·") + " 타입이 자주 나와요 · " + state.here.name)
            if case .home = screen { screen = .say([w.news], next: .home, since: now) }
        }
        if case .home = screen, state.eventDue {
            switch state.petEvent(&rng) {
            case .item(let item):
                screen = .say([josa(monNames[state.companion.dex], "이", "가") + " 무언가를", "주워왔다!", item], next: .home, since: now)
                notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 무언가를 주워왔어요", item)
            case .egg:
                screen = .say([josa(monNames[state.companion.dex], "이", "가") + " 무언가를", "주워왔다!", "포켓몬의 알"], next: .home, since: now)
                notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 알을 주워왔어요", "앞으로 \(state.egg?.left ?? 0)걸음 걸으면 태어나요")
            case nil: if state.total > 0 { emote = (Int.random(in: 0..<3, using: &rng), now.addingTimeInterval(3)) }
            }
        }
        if case .home = screen, state.hatchDue {
            let m = state.hatch(&rng); screen = .hatch(m, since: now); save(nil)
            notify("hatch", "알에서 " + josa(monNames[m.dex], "이", "가") + " 태어났어요!" + (m.shiny == true ? " ✦" : ""), m.shiny == true ? "이로치예요!" : "Lv.1 · 워커에 있어요")
        }
        if state.earned > unlockedAt {                                                           // lifetime watts opened a course
            let new = courses.enumerated().filter { $0.element.watts > unlockedAt && $0.element.watts <= state.earned && state.unlocked($0.offset) }.map(\.element.name)
            unlockedAt = state.earned
            if let n = new.first {
                notify("unlock", "새 코스가 열렸어요", n + " · 우클릭 → 코스")
                if case .home = screen { screen = .say(["새 코스 해금!", n], next: .home, since: now) }
            }
        }
        if case .home = screen, dexCount > rewarded {                                            // Pokédex milestones: event courses and two shells
            let got = courses.filter { (rewarded + 1...dexCount).contains($0.dex) }.map { $0.name + " 코스" } + shells.filter { (rewarded + 1...dexCount).contains($0.dex) }.map { $0.name + " 기기" }
            rewarded = dexCount
            if let g = got.first { screen = .say(["도감 \(dexCount)종 달성!", g + " 해금"] + got.dropFirst().prefix(1), next: .home, since: now); notify("unlock", "도감 \(dexCount)종 달성!", got.joined(separator: " · ") + " 해금") }
        }
        if levelled, case .home = screen {                                                    // shown when it's back home, not mid-menu
            levelled = false
            let name = monNames[state.companion.dex]
            if let e = state.levelEvolution(now) { startEvolving(e, now); notify("grow", "어라...? " + josa(name, "의", "의") + " 모습이...!", josa(name, "이", "가") + " " + josa(monNames[e.to], "으로", "로") + " 진화했어요!") }
            else {
                screen = .say(["레벨 업!", name + " Lv.\(state.companion.level)"], next: .home, since: now)
                if state.companion.level % 5 == 0 { notify("grow", "레벨 업!", name + " Lv.\(state.companion.level)") }
            }
        }
        if case .home = screen, (state.learning ?? []).count >= 2 { nextLearn(now) }
        switch screen {
        case .radar(_, _, let since, let chain) where now.timeIntervalSince(since) > 1.5 + radarWindow(chain):
            screen = .say(chain > 0 ? ["...!", "연쇄가 끊겼다 (\(chain))"] : ["...!", "사라져버렸다"], next: .home, since: now)
        case .beats(let bt, let beats, let since, _) where now.timeIntervalSince(since) >= beats.map(\.length).reduce(0, +):
            screen = beats.last!.ends ? after(bt, beats.last!, now) : bt.mustReplace ? .party(bt, sel: bt.mine.indices.first { bt.mine[$0].alive } ?? 0) : .battle(bt, sel: 0)
        case .say(_, let next, let since) where now.timeIntervalSince(since) > 3: screen = next
        case .evolve(_, _, let since) where now.timeIntervalSince(since) > 6.5: screen = .home
        case .hatch(_, let since) where now.timeIntervalSince(since) > 5.5: screen = .home
        case .menu, .card, .items, .dex, .box, .tower, .shop, .shopConfirm: if now.timeIntervalSince(lastInput) > 20 { screen = .home }
        default: break
        }
        if now.timeIntervalSince(lastSave) > 60 { save(nil) }
        updateStatus()
        frame(nil)
        let busy: Bool = { switch screen { case .beats, .hatch, .evolve, .radar: true; default: false } }() || animating   // fights, shows and animations play at 30 fps, the rest at the tick's 10
        if busy != (fast != nil) {
            fast?.invalidate(); fast = nil
            if busy { let t = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(frame(_:)), userInfo: nil, repeats: true); t.tolerance = 0.005; RunLoop.main.add(t, forMode: .common); fast = t }
        }
    }
    /// The pane and the screen, redrawn if the frame changed (the tick's, and 30 a second while something plays).
    @objc func frame(_ sender: Any?) {
        let now = Date()
        if window?.isVisible == true { refreshPane(now) }
        guard window?.isVisible ?? true else { return }                                         // hidden in the menu bar: rules keep running, nothing to draw
        let fb = compose(now)
        if fb.px != shown?.px || fb.col != shown?.col || fb.runs != shown?.runs || fb.flips != shown?.flips || fb.sprites != shown?.sprites || fb.pics != shown?.pics || fb.over != shown?.over || now.timeIntervalSince(pressedAt) < 0.3 { shown = fb; setNeedsDisplay(now.timeIntervalSince(pressedAt) < 0.3 ? bounds : lcdRect) }   // idle home = ~2 redraws a second
    }
    var persist = true                                                     // false in --selftest: flows must never touch the real save (nor notify)
    lazy var unlockedAt = state.earned                                     // lifetime watts already announced
    var lastStatus = ""

    // MARK: input
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        clickCount = e.clickCount
        var buying: Bool { switch screen { case .shop(_, _, .some), .shopConfirm: true; default: false } }
        if let i = buttons.firstIndex(where: { hypot($0.c.x - p.x, $0.c.y - p.y) <= $0.r + 2 * K }) {
            if i == 1 || i == 4, e.clickCount > 1 { return }                                        // ● or 메뉴 twice fast: once (the 2nd would act on what the 1st opened)
            pressed = i; pressedAt = Date(); press(i)
            perform(#selector(tick(_:)), with: nil, afterDelay: 0.15, inModes: [.common])
        } else if chevronRect.contains(p), title().chevron != nil { toggleStatus() }
        else if lcdRect.contains(p), touch(Int((p.x - lcdRect.minX) / PX), Int((p.y - lcdRect.minY) / PX)) { needsDisplay = true }
        else { window?.performDrag(with: e) }
    }
    override func keyDown(with e: NSEvent) {                                                  // ← return/space → esc (= ↩ 뒤로); in a shop ↑ ↓ = a row, or ±10
        if case .shop(_, _, let q) = screen, let d = [126: -1, 125: 1][Int(e.keyCode)] { shopStep(q == nil ? d : -10 * d); return }
        switch screen { case .dex(_, _, false), .box(_, .none, _, false): if let d = [126: -6, 125: 6, 116: -30, 121: 30][Int(e.keyCode)] { gridStep(d, ends: abs(d) == 30); return }; default: break }   // the grids: ↑ ↓ a row, page up / down a page
        if e.keyCode == 48 {                                                                      // tab: a grid's next tab (shift: the one before); where no page is up, the status sheet
            let back = e.modifierFlags.contains(.shift)
            switch screen {
            case .dex(_, let f, false): gridTap(4100 + (f + (back ? 3 : 1)) % 4)
            case .box(_, .none, _, false): gridTap(4100 + (boxSort + (back ? 3 : 1)) % 4)
            default: if title().chevron != nil { toggleStatus() }
            }
            return
        }
        switch screen { case .shop, .shopConfirm: if e.isARepeat, [36, 49].contains(Int(e.keyCode)) { return }; default: break }   // a held return / space doesn't keep buying
        if let i = [123: 0, 36: 1, 49: 1, 124: 2, 53: 3, 46: 4][Int(e.keyCode)] { press(i) } else { super.keyDown(with: e) }
    }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() {
        if title().chevron != nil { addCursorRect(chevronRect, cursor: .pointingHand) }                   // the LCD is to look at: no hand over it
        for b in buttons { addCursorRect(NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r), cursor: .pointingHand) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { buildMenu() }

    // MARK: drawing
    /// The card: the shell's top down to the band (the title row, the LCD in its bezel), the band with the four keys, the white page below.
    override func draw(_ dirty: NSRect) {
        if lcdRect.contains(dirty) { drawLCD(); return }                                           // most frames: only the screen changed
        let t = shells[theme], k = K, W = bounds.width, luma = t.top.usingColorSpace(.sRGB).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent } ?? 0
        let light = luma > 0.6, dark = luma < 0.2                                                   // 프리미어볼 / 배틀 골드: dark ink; 하이퍼볼 / 럭셔리볼: the band and bezel need a lighter edge
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: Layout.r * k, yRadius: Layout.r * k)
        NSGraphicsContext.saveGraphicsState(); body.addClip()
        NSColor.white.setFill(); bounds.fill()
        t.top.setFill(); NSRect(x: 0, y: 0, width: W, height: Layout.seam * k).fill()
        (dark && (t.band.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) < 0.3 ? NSColor(white: 0.34, alpha: 1) : t.band).setFill(); NSRect(x: 0, y: (Layout.seam - Layout.band / 2) * k, width: W, height: Layout.band * k).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0, alpha: 0.12).setStroke(); body.lineWidth = 0.5; body.stroke()
        // the title row: what the LCD doesn't show; home's ⌄ opens the status sheet
        let tl = title(), fg = light ? Ink.ink : .white, fg2 = light ? Ink.sub : NSColor(white: 1, alpha: 0.82), cy = 12.5 * k
        say(tl.title, 12 * k, cy, font(11, .bold), fg, maxW: 120 * k)
        say(tl.meta, (207 - 3 - (tl.chevron != nil ? 13 : 0)) * k, cy, font(9, .medium), fg2, 1, maxW: 110 * k)
        if let open = tl.chevron {
            let p = NSBezierPath(), cx = 200 * k, s3 = 3 * k, d: CGFloat = open ? -1 : 1
            p.move(to: NSPoint(x: cx - s3, y: cy - d * s3 / 2)); p.line(to: NSPoint(x: cx, y: cy + d * s3 / 2)); p.line(to: NSPoint(x: cx + s3, y: cy - d * s3 / 2))
            fg.setStroke(); p.lineWidth = 1.5 * k; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        }
        let bezel = NSRect(x: (9 * k).rounded(), y: (24 * k).rounded(), width: (198 * k).rounded(), height: (134 * k).rounded()), bp = rounded(bezel, 7 * k)
        bp.fill(with: Ink.dark)                                                                    // the LCD's bezel
        if dark { NSColor(white: 1, alpha: 0.22).setStroke(); bp.lineWidth = max(1, k); bp.stroke() }
        drawLCD()
        drawKeys()
    }
    /// ◀ ▶ ↩: white keys ringed dark; ● is the ball's own button — a dark ring, the white button, a faint inner ring.
    func drawKeys() {
        let k = K, now = Date()
        for (i, b) in buttons.enumerated() {
            let down = pressed == i && now.timeIntervalSince(pressedAt) < 0.15, face = down ? NSColor(white: 0.86, alpha: 1) : .white
            let r = NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r)
            if i == 1 {
                NSBezierPath(ovalIn: r).fill(with: Ink.dark); NSBezierPath(ovalIn: r.insetBy(dx: 3 * k, dy: 3 * k)).fill(with: face)
                let ring = NSBezierPath(ovalIn: NSRect(x: b.c.x - 5.5 * k, y: b.c.y - 5.5 * k, width: 11 * k, height: 11 * k)); Ink.c(186, 190, 200).setStroke(); ring.lineWidth = 1.2 * k; ring.stroke()
                continue
            }
            let c = NSBezierPath(ovalIn: r.insetBy(dx: k, dy: k)); c.fill(with: face); Ink.dark.setStroke(); c.lineWidth = 2 * k; c.stroke()
            if i >= 3 {                                                                            // ↩ the back arrow; 메뉴 on home, 홈 elsewhere (dim where it can't go)
                let key = homeKey(), name = i == 3 ? "arrow.uturn.backward" : key == true ? "square.grid.2x2.fill" : "house.fill"
                let img = NSImage(systemSymbolName: name, accessibilityDescription: i == 3 ? "뒤로" : key == true ? "메뉴" : "홈")?.withSymbolConfiguration(.init(pointSize: 8.5 * k, weight: .bold).applying(.init(paletteColors: [Ink.ink])))
                if let img { let s = img.size; img.draw(in: NSRect(x: b.c.x - s.width / 2, y: b.c.y - s.height / 2, width: s.width, height: s.height), from: .zero, operation: .sourceOver, fraction: i == 4 && key == nil ? 0.3 : 1, respectFlipped: true, hints: nil) }
            } else { triangle(b.c.x + (i == 2 ? 0.6 : -0.6) * k, b.c.y, 4.2 * k, left: i == 0, Ink.ink) }
        }
    }
    /// The title row for this screen: what it is, one line of what the LCD doesn't show, and home's chevron (nil = none; true = open).
    func title() -> (title: String, meta: String, chevron: Bool?) {
        var sc = screen; if case .say(_, let next, _) = sc { sc = next }
        let fight: Battle? = switch sc { case .battle(let b, _), .moves(let b, _), .party(let b, _), .bagBattle(let b, _), .forfeit(let b, _), .beats(let b, _, _, _): b; default: nil }
        if let b = fight {
            guard let tr = b.trainer else { return ("야생 배틀", state.here.name, nil) }
            let left = { (fs: [Fighter]) in fs.filter(\.alive).count }
            return (tr, "배틀 타워 · 남은 \(left(b.theirs)) : \(left(b.mine))", nil)
        }
        let when = "\(state.season.name) \(state.gameDay % seasonDays + 1)일째 · \((state.weather ?? .sunny).name)"
        switch sc {
        case .dex: return ("도감", "잡음 \(dexCount) · 봤음 \(seenList.count)", nil)
        case .box, .items: return ("포켓몬", "워커 \(state.caught.count) · 상자 \(state.box.count.formatted()) · 도구 \(state.items.count)", nil)
        case .menu: return ("메뉴", "", nil)
        case .shop(let bp, _, _), .shopConfirm(let bp, _, _): return (bp ? "BP 교환소" : "상점", "", nil)
        case .radar: return ("포켓 레이더", state.here.name, nil)
        case .card: return ("트레이너 카드", "", nil)
        case .learn: return ("기술 배우기", "", nil)
        case .tower: return ("배틀 타워", "\((state.bp ?? 0).formatted())BP", nil)
        default: return (state.here.name, when, statusOpen)                                      // screens without a page of their own: the status sheet's ⌄
        }
    }
    /// The 96x64 screen: dots (colour or 4 greys), sprites, smooth text over them, a fight's HP boxes, a shadow from the bezel.
    func drawLCD() {
        let l = lcds[lcdStyle]
        Ink.dark.setFill(); lcdRect.fill()                                                         // the rounded corners' bezel (an LCD-only redraw clears the whole square)
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: lcdRect, xRadius: 4 * K, yRadius: 4 * K).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        l.shades[0].setFill(); lcdRect.fill()
        let scale = window?.backingScaleFactor ?? 2, fb = shown ?? compose(Date()), gap = PX * scale >= 8 ? 1 / scale : 0   // a dot grid only once dots are big on screen
        var paths: [[UInt32: NSBezierPath]] = [[:], [:]], cover = NSBezierPath()                       // under the sprites, over them; key: colour, or 0...3 for an LCD shade
        for y in 0..<64 { for x in 0..<96 {
            let i = y * 96 + x, key = l.color && fb.col[i] != 0 ? fb.col[i] : UInt32(fb.px[i]), o = fb.over[i] ? 1 : 0
            if o == 1 { cover.appendRect(NSRect(x: lcdRect.minX + CGFloat(x) * PX, y: lcdRect.minY + CGFloat(y) * PX, width: PX, height: PX)) }   // the whole cell: no sprite through the dot grid
            if key != 0 || o == 1 { if paths[o][key] == nil { paths[o][key] = NSBezierPath() }; paths[o][key]!.appendRect(NSRect(x: lcdRect.minX + CGFloat(x) * PX, y: lcdRect.minY + CGFloat(y) * PX, width: PX - gap, height: PX - gap)) }
        } }
        func dots(_ layer: [UInt32: NSBezierPath]) {
            NSGraphicsContext.current!.shouldAntialias = false
            for (k, path) in layer { (k < 4 ? l.shades[Int(k)] : NSColor(red: CGFloat(k >> 16 & 255) / 255, green: CGFloat(k >> 8 & 255) / 255, blue: CGFloat(k & 255) / 255, alpha: 1)).setFill(); path.fill() }
            NSGraphicsContext.current!.shouldAntialias = true
        }
        dots(paths[0])
        let s = K, snap = { (v: CGFloat) in (v * scale).rounded() / scale }                            // 1 pt per sprite pixel at 보통, on whole device pixels
        func pictures(behind: Bool) {                                                                  // pictures at sprite resolution: a backdrop under the sprites, a ball or an effect over them
            for r in fb.pics where r.behind == behind {
                guard let (img, p) = picImage(r, l) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current!.imageInterpolation = .none
                let c = NSPoint(x: lcdRect.minX + CGFloat(r.x) * s, y: lcdRect.minY + CGFloat(r.y) * s), w = CGFloat(p.w) * s * r.scale, h = CGFloat(p.h) * s * r.scale
                if r.angle != 0 { let t = NSAffineTransform(); t.translateX(by: c.x, yBy: c.y); t.rotate(byDegrees: r.angle); t.translateX(by: -c.x, yBy: -c.y); t.concat() }
                let box = r.scale == 1 && r.angle == 0 ? NSRect(x: snap(c.x - w / 2), y: snap(c.y - h / 2), width: w, height: h) : NSRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
                img.draw(in: box, from: .zero, operation: .sourceOver, fraction: r.alpha, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        pictures(behind: true)
        for r in fb.sprites {                                                                         // the sprites: smooth-sized pixels, not LCD dots
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: lcdRect.minX, y: lcdRect.minY, width: lcdRect.width, height: CGFloat(min(64, r.floor)) * PX)).addClip()
            NSGraphicsContext.current!.imageInterpolation = .none
            let feet = NSPoint(x: lcdRect.minX + CGFloat(r.x + 16) * PX, y: lcdRect.minY + CGFloat(r.y + 32) * PX), k = s * r.scale   // its 80x80 frame stands on the run's feet (bottom-centre)
            let a = playing(r), (ox, oy, w, h) = a.map { (CGFloat($0.x), CGFloat($0.y), CGFloat($0.w), CGFloat($0.h)) } ?? (0, 0, 80, 80)   // an animation frame: its box in the 80x80 frame
            let box = r.scale == 1 ? NSRect(x: snap(feet.x + (ox - 40) * s), y: snap(feet.y + (oy - 80) * s - CGFloat(r.bob) * s), width: w * s, height: h * s)
                                   : NSRect(x: feet.x + (ox - 40) * k, y: feet.y + (oy - 80) * k - CGFloat(r.bob) * s, width: w * k, height: h * k)
            spriteImage(r, l).draw(in: box, from: .zero, operation: .sourceOver, fraction: r.alpha, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
            NSGraphicsContext.restoreGraphicsState()
        }
        pictures(behind: false)
        if gap > 0 { NSGraphicsContext.current!.shouldAntialias = false; l.shades[0].setFill(); cover.fill(); NSGraphicsContext.current!.shouldAntialias = true }
        dots(paths[1])
        for r in fb.runs {                                                                             // smooth text over the dots; flipped where it sits in an inverted box
            let f = lcdFont(r.small), cx = r.x + r.w / 2, cy = r.y + r.rows / 2
            let flipped = fb.flips.contains { cx >= $0[0] && cx < $0[0] + $0[2] && cy >= $0[1] && cy < $0[1] + $0[3] }
            let shade = Int(flipped ? 3 - r.shade : r.shade), c = l.shades[max(0, min(3, shade))]
            let box = NSRect(x: lcdRect.minX + CGFloat(r.x) * PX, y: lcdRect.minY + CGFloat(r.y) * PX, width: CGFloat(r.w) * PX, height: CGFloat(r.rows) * PX)
            let y = box.midY + f.capHeight / 2 - f.ascender                                            // caps centred on the row, one baseline for Hangul and digits
            (r.s as NSString).draw(at: NSPoint(x: box.minX, y: y), withAttributes: [.font: f, .foregroundColor: c])
        }
        if let m = hud { drawHUD(m) }
        NSGradient(starting: NSColor(white: 0, alpha: 0.18), ending: .clear)!.draw(in: NSRect(x: lcdRect.minX, y: lcdRect.minY, width: lcdRect.width, height: 2 * PX), angle: 90)
    }
    /// HGSS's HP boxes over the LCD's empty corners: theirs top-left (caught mark, name, Lv, types, HP), ours bottom-right (name, Lv, HP and its numbers).
    /// They fade while a move or a ball flies under them.
    func drawHUD(_ m: SideModel) {
        let k = K, o = lcdRect.origin
        var fade: CGFloat = 1, foeUp = true
        if case .beats = screen, let s = beatState(Date()) {
            switch s.beat { case .use, .thrown: fade = 0.4; default: break }
            if isIntro(s.beat, s.names), s.u < 2.2 { foeUp = false }                               // the tower's trainer is still out front: no Pokémon to show yet
        }
        let cg = NSGraphicsContext.current!.cgContext; cg.saveGState(); cg.setAlpha(fade); cg.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { cg.endTransparencyLayer(); cg.restoreGState() }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            let r = NSRect(x: o.x + x * k, y: o.y + y * k, width: w * k, height: h * k), p = rounded(r, 7 * k)
            p.fill(with: NSColor(white: 1, alpha: 0.92)); Ink.ink.withAlphaComponent(0.11).setStroke(); p.lineWidth = 0.5 * k; p.stroke(); return r
        }
        func status(_ st: String, _ x: CGFloat, _ cy: CGFloat) -> CGFloat {
            let f = font(7, .bold), w = width(st, f) + 7 * k; pill(NSRect(x: x, y: cy - 5 * k, width: w, height: 10 * k), Ink.faint); say(st, x + w / 2, cy, f, .white, 0.5); return w
        }
        // theirs: [caught] name · Lv on top; its types (and a status) then the HP bar below
        if foeUp {
            let f = box(4, 4, 110, 30), fr = m.foe.max > 0 ? CGFloat(m.foe.hp) / CGFloat(m.foe.max) : 0
            var x = f.minX + 7 * k
            if m.foe.owned { miniBall(NSPoint(x: f.minX + 9.5 * k, y: f.minY + 10 * k), 4.2 * k); x = f.minX + 17 * k }
            let lv = "Lv\(m.foe.level)", lvf = font(8, .semibold)
            let nw = say(m.foe.name, x, f.minY + 10.5 * k, font(10, .bold), Ink.ink, maxW: f.maxX - 7 * k - x - width(lv, lvf) - 3 * k)
            say(lv, x + nw + 3 * k, f.minY + 11 * k, lvf, Ink.sub)
            var bx = f.minX + 6 * k
            for t in m.foe.types { bx += typePill(t, bx, f.minY + 23 * k, h: 9 * k, size: 6.5) + 2 * k }
            if let st = m.foe.status { bx += status(st, bx, f.minY + 23 * k) + 2 * k }
            bar(bx + k, f.maxX - 7 * k, f.minY + 23 * k, fr, Ink.hp(fr), h: 4 * k)
        }
        let me = box(98, 86, 90, 38), mr = m.mine.max > 0 ? CGFloat(m.mine.hp) / CGFloat(m.mine.max) : 0
        let lw = say("Lv\(m.mine.level)", me.maxX - 7 * k, me.minY + 10 * k, font(8, .semibold), Ink.sub, 1)
        say(m.mine.name, me.minX + 7 * k, me.minY + 9.5 * k, font(10, .bold), Ink.ink, maxW: me.width - 17 * k - lw)
        bar(me.minX + 7 * k, me.maxX - 7 * k, me.minY + 19.5 * k, mr, Ink.hp(mr), h: 5 * k)
        if let st = m.mine.status { _ = status(st, me.minX + 7 * k, me.minY + 29.5 * k) }
        say("\(m.mine.hp) / \(m.mine.max)", me.maxX - 7 * k, me.minY + 29.5 * k, font(10, .semibold), Ink.ink, 1)
    }
}
