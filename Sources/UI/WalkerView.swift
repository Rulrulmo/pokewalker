import AppKit
// The device view: its state, the clock tick, input events and drawing the device around the LCD.

final class WalkerView: NSView {
    var state: Walk
    var screen = Screen.home
    var lastInput = Date(), lastStep = Date.distantPast, lastSave = Date(), levelled = false
    var boxByLevel = false
    var chainNote: String? = nil                                           // "+6W · 기력의조각" under "연쇄 3!"
    var usedItem = "몬스터볼"                                                // the potion / ball / revive the current beat names
    var towerRefs: [Int] = [], towerRun = false
    var sideOn = false                                                     // the battle side panel exists (not in --selftest): the LCD shows the stage only
    weak var side: SidePanel?                            // who's in the tower party (see Walk.party), and whether a run is on
    lazy var lastSeason = state.season
    var shown: FB? = nil                                                   // last composed frame; draw() only when it changes
    var emote: (kind: Int, until: Date)? = nil                             // ♪ ♥ ! bubble over the companion
    lazy var rewarded = dexCount                                           // dex count already celebrated (no fanfare for old progress)
    var dexCount: Int { (state.owned ?? []).count }
    var pressed: Int? = nil, pressedAt = Date()
    var rng = Seeded(s: .random(in: .min ... .max))
    var clickCount = 1                                                     // the mouse event's, for touch(): a double-click's 2nd click never buys

    init(state: Walk) { self.state = state; super.init(frame: NSRect(origin: .zero, size: devSize)) }
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
        case .menu, .card, .bag, .dex, .box, .tower, .shop, .shopConfirm: if now.timeIntervalSince(lastInput) > 20 { screen = .home }
        default: break
        }
        if now.timeIntervalSince(lastSave) > 60 { save(nil) }
        updateStatus()
        let seen = window?.isVisible == true
        side?.show(seen ? sideModel(now) : nil, dex: seen ? dexModel() : nil, shop: seen ? shopModel() : nil, beside: window)
        guard window?.isVisible ?? true else { return }                                         // hidden in the menu bar: rules keep running, nothing to draw
        let fb = compose(now)
        if fb.px != shown?.px || fb.col != shown?.col || fb.runs != shown?.runs || fb.flips != shown?.flips || now.timeIntervalSince(pressedAt) < 0.3 { shown = fb; needsDisplay = true }   // idle home = ~2 redraws a second
    }
    var persist = true                                                     // false in --selftest: flows must never touch the real save (nor notify)
    lazy var unlockedAt = state.earned                                     // lifetime watts already announced
    var lastStatus = ""

    // MARK: input
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        clickCount = e.clickCount
        var buying: Bool { switch screen { case .shop(_, _, .some), .shopConfirm: true; default: false } }
        if let i = buttons.firstIndex(where: { hypot($0.c.x - p.x, $0.c.y - p.y) <= $0.r + PX }) {
            if i == 1, e.clickCount > 1, buying { return }                                         // ● twice fast on how-many: once
            pressed = i; pressedAt = Date(); press(i)
            perform(#selector(tick(_:)), with: nil, afterDelay: 0.15, inModes: [.common])
        } else if lcdRect.contains(p), touch(Int((p.x - lcdRect.minX) / PX), Int((p.y - lcdRect.minY) / PX)) { needsDisplay = true }
        else { window?.performDrag(with: e) }
    }
    override func keyDown(with e: NSEvent) {                                                  // ← return/space → esc; in a shop ↑ ↓ = a row, or ±10
        if case .shop(_, _, let q) = screen, let d = [126: -1, 125: 1][Int(e.keyCode)] { shopStep(q == nil ? d : -10 * d); return }
        switch screen { case .shop, .shopConfirm: if e.isARepeat, [36, 49].contains(Int(e.keyCode)) { return }; default: break }   // a held return / space doesn't keep buying
        if let i = [123: 0, 36: 1, 49: 1, 124: 2, 53: 3][Int(e.keyCode)] { press(i) } else { super.keyDown(with: e) }
    }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(lcdRect, cursor: .pointingHand); for b in buttons { addCursorRect(NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r), cursor: .pointingHand) } }

    override func menu(for event: NSEvent) -> NSMenu? { buildMenu() }

    // MARK: drawing
    override func draw(_ dirty: NSRect) {
        let t = shells[theme], l = lcds[lcdStyle], ink = NSColor(white: 0.10, alpha: 1), white = NSColor(white: 0.96, alpha: 1), light = t.name == "프리미어볼"
        let ballRect = NSRect(origin: .zero, size: devSize).insetBy(dx: PX, dy: PX), ball = NSBezierPath(ovalIn: ballRect)
        // flat halves: top colour, white bottom, black band through the middle; one hairline, depth from the window shadow
        NSGraphicsContext.saveGraphicsState(); ball.addClip()
        t.top.setFill(); NSRect(x: 0, y: 0, width: devSize.width, height: 72 * PX).fill()
        white.setFill(); NSRect(x: 0, y: 72 * PX, width: devSize.width, height: 72 * PX).fill()
        switch t.name {
        case "하이퍼볼": NSColor(red: 0.98, green: 0.80, blue: 0.20, alpha: 1).setFill(); for x in [30, 106] { NSRect(x: CGFloat(x) * PX, y: 0, width: 8 * PX, height: 34 * PX).fill() }   // yellow
        case "마스터볼": NSColor(red: 0.93, green: 0.40, blue: 0.62, alpha: 1).setFill(); for x in [18, 110] { NSBezierPath(ovalIn: NSRect(x: CGFloat(x) * PX, y: 22 * PX, width: 16 * PX, height: 12 * PX)).fill() }   // pink spots
        case "럭셔리볼": NSColor(red: 0.95, green: 0.78, blue: 0.30, alpha: 1).setFill(); for y in [62, 78] { NSRect(x: 0, y: CGFloat(y) * PX, width: devSize.width, height: 2 * PX).fill() }; NSRect(x: 70 * PX, y: 1 * PX, width: 4 * PX, height: 60 * PX).fill()   // gold trim
        default: break
        }
        t.band.setFill(); NSRect(x: 0, y: 68 * PX, width: devSize.width, height: 8 * PX).fill()
        NSGraphicsContext.restoreGraphicsState()
        ink.withAlphaComponent(0.6).setStroke(); ball.lineWidth = 1; ball.stroke()
        // the screen sits where the ball's button is: black ring, white ring, black bezel
        for (out, r, c) in [(8.0, 11.0, ink), (5.0, 8.0, white), (2.0, 4.0, ink)] as [(CGFloat, CGFloat, NSColor)] {
            c.setFill(); NSBezierPath(roundedRect: lcdRect.insetBy(dx: -out * PX, dy: -out * PX), xRadius: r * PX, yRadius: r * PX).fill()
        }
        l.shades[0].setFill(); lcdRect.fill()
        let fb = shown ?? compose(Date()), gap = PX >= 3 ? 1 / (window?.backingScaleFactor ?? 2) : 0
        var paths: [UInt32: NSBezierPath] = [:]                                                        // key: colour, or 1...3 for an LCD shade
        for y in 0..<64 { for x in 0..<96 {
            let i = y * 96 + x, key = l.color && fb.col[i] != 0 ? fb.col[i] : UInt32(fb.px[i])
            if key != 0 { if paths[key] == nil { paths[key] = NSBezierPath() }; paths[key]!.appendRect(NSRect(x: lcdRect.minX + CGFloat(x) * PX, y: lcdRect.minY + CGFloat(y) * PX, width: PX - gap, height: PX - gap)) }
        } }
        NSGraphicsContext.current!.shouldAntialias = false
        for (k, path) in paths {
            (k < 4 ? l.shades[Int(k)] : NSColor(red: CGFloat(k >> 16 & 255) / 255, green: CGFloat(k >> 8 & 255) / 255, blue: CGFloat(k & 255) / 255, alpha: 1)).setFill(); path.fill()
        }
        NSGraphicsContext.current!.shouldAntialias = true
        for r in fb.runs {                                                                             // smooth text over the dots; flipped where it sits in an inverted box
            let f = lcdFont(r.small), cx = r.x + r.w / 2, cy = r.y + r.rows / 2
            let flipped = fb.flips.contains { cx >= $0[0] && cx < $0[0] + $0[2] && cy >= $0[1] && cy < $0[1] + $0[3] }
            let shade = Int(flipped ? 3 - r.shade : r.shade), c = l.shades[max(0, min(3, shade))]
            let box = NSRect(x: lcdRect.minX + CGFloat(r.x) * PX, y: lcdRect.minY + CGFloat(r.y) * PX, width: CGFloat(r.w) * PX, height: CGFloat(r.rows) * PX)
            let y = box.midY + f.capHeight / 2 - f.ascender                                            // caps centred on the row, one baseline for Hangul and digits
            (r.s as NSString).draw(at: NSPoint(x: box.minX, y: y), withAttributes: [.font: f, .foregroundColor: c])
        }
        NSGradient(starting: NSColor(white: 0, alpha: 0.22), ending: .clear)!.draw(in: NSRect(x: lcdRect.minX, y: lcdRect.minY, width: lcdRect.width, height: 2 * PX), angle: 90)
        let now = Date()
        for (i, b) in buttons.enumerated() {                                                          // white caps with a black ring and a printed icon; a lip underneath until pressed
            let down = pressed == i && now.timeIntervalSince(pressedAt) < 0.15, dy = down ? 0.7 * PX : 0
            let r = NSRect(x: b.c.x - b.r, y: b.c.y - b.r, width: 2 * b.r, height: 2 * b.r)
            if !down { NSColor(white: 0.62, alpha: 1).setFill(); NSBezierPath(ovalIn: r.offsetBy(dx: 0, dy: 0.9 * PX)).fill() }
            let cap = NSBezierPath(ovalIn: r.offsetBy(dx: 0, dy: dy))
            (down ? NSColor(white: 0.84, alpha: 1) : white).setFill(); cap.fill()
            ink.setStroke(); cap.lineWidth = 1.0 * PX; cap.stroke()
            let c = NSPoint(x: b.c.x, y: b.c.y + dy), s = b.r * 0.42, icon = NSBezierPath()
            switch i {
            case 0: icon.move(to: NSPoint(x: c.x - s, y: c.y)); icon.line(to: NSPoint(x: c.x + s * 0.7, y: c.y - s)); icon.line(to: NSPoint(x: c.x + s * 0.7, y: c.y + s)); icon.close()
            case 2: icon.move(to: NSPoint(x: c.x + s, y: c.y)); icon.line(to: NSPoint(x: c.x - s * 0.7, y: c.y - s)); icon.line(to: NSPoint(x: c.x - s * 0.7, y: c.y + s)); icon.close()
            case 1: icon.appendOval(in: NSRect(x: c.x - s * 0.8, y: c.y - s * 0.8, width: s * 1.6, height: s * 1.6))
            default:                                                                                   // a little house
                icon.move(to: NSPoint(x: c.x, y: c.y - s * 1.1)); icon.line(to: NSPoint(x: c.x + s * 1.1, y: c.y)); icon.line(to: NSPoint(x: c.x + s * 0.7, y: c.y))
                icon.line(to: NSPoint(x: c.x + s * 0.7, y: c.y + s)); icon.line(to: NSPoint(x: c.x - s * 0.7, y: c.y + s)); icon.line(to: NSPoint(x: c.x - s * 0.7, y: c.y))
                icon.line(to: NSPoint(x: c.x - s * 1.1, y: c.y)); icon.close()
            }
            ink.setFill(); icon.fill()
        }
        let centred = NSMutableParagraphStyle(); centred.alignment = .center
        ("Pokéwalker" as NSString).draw(in: NSRect(x: 42 * PX, y: 20 * PX, width: 60 * PX, height: 6 * PX),
            withAttributes: [.font: NSFont.systemFont(ofSize: 3.4 * PX, weight: .heavy), .foregroundColor: light ? NSColor(red: 0.86, green: 0.20, blue: 0.18, alpha: 1) : NSColor(white: 1, alpha: 0.85), .paragraphStyle: centred, .kern: 0.3 * PX])
    }
}
