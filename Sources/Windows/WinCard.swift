#if os(Windows)
import Foundation
import WinSDK
// Windows' card: one layered, topmost tool window (no taskbar button, like the Mac's panel) that owns the Walker and is its host (Core/Platform.swift).
// The card is drawn by the software canvas (Windows/SoftCanvas.swift) into a buffer laid on the screen with its alpha (UpdateLayeredWindow: the
// rounded corners); it mirrors the Mac's WalkerView (the clock, clicks, keys, the frame timer, the window following the page), SideView (the page's
// hits, the wheel), MenuBar (the menu, showing / hiding: here the tray) and MacHost (banners, the step counter, dialogs).

@MainActor var card: WinCard? = nil
let wmTray = UINT(WM_APP) + 1, wmShow = UINT(WM_APP) + 2, wmRender = UINT(WM_APP) + 3        // the tray icon's clicks, a second launch, a redraw asked for
/// Every message goes to the card (nil = the default handling).
let wndProc: WNDPROC = { hwnd, msg, wp, lp in MainActor.assumeIsolated { card?.handle(msg, wp, lp) } ?? DefWindowProcW(hwnd, msg, wp, lp) }
func lo(_ v: LPARAM) -> Int { Int(Int16(truncatingIfNeeded: v)) }                              // GET_X_LPARAM / GET_Y_LPARAM: signed
func hi(_ v: LPARAM) -> Int { Int(Int16(truncatingIfNeeded: v >> 16)) }
func wide<R>(_ s: String, _ body: (UnsafePointer<WCHAR>) -> R) -> R { s.withCString(encodedAs: UTF16.self, body) }
/// s into a fixed WCHAR array (a struct's szTip / szInfo), cut to fit, 0-terminated.
func put<T>(_ s: String, _ field: inout T) {
    withUnsafeMutableBytes(of: &field) { b in
        let u = Array(s.utf16.prefix(b.count / 2 - 1)) + [0]
        for (i, c) in u.enumerated() { b.storeBytes(of: c, toByteOffset: 2 * i, as: UInt16.self) }
    }
}

@MainActor final class WinCard: Host {
    let walker: Walker
    let page = Page()                                                      // the pane's page: its drawing and its hits
    var hwnd: HWND? = nil
    var dpi: UInt32 = 96
    var raster = Raster(0, 0)                                              // the card as last drawn (device pixels)
    var shown: FB? = nil                                                   // last composed frame; the LCD is drawn again only when it changes
    var needAll = true, needLCD = false, posted = false
    var move: POINT? = nil                                                 // where the next present puts the window (nil: where it is)
    var anchorTop: Int32? = nil                                            // the card's top where the user put it (screen px): a tall page lifts it, the next short one drops it back
    var pressed: Int? = nil, pressedAt = Date()
    var fast = false                                                       // the 30 fps frame timer is on
    var scrolled = 0                                                       // wheel delta not yet a row
    var downOn = 0, clicks = (time: 0, x: 0, y: 0, n: 0)                   // the page a click began on; the last click (for a double's count)
    var steps: UInt32 = 0, keysDown = Set<UInt16>()                        // key downs + clicks since launch (Raw Input); keys held (their repeats aren't steps)
    let started = Date().timeIntervalSince1970                             // "boot": each launch re-baselines the counter
    var memDC: HDC? = CreateCompatibleDC(nil), dib: HBITMAP? = nil, bits: UnsafeMutableRawPointer? = nil, dibSize = (w: 0, h: 0)
    var icon: HICON? = nil, tip = "", menuActions: [@MainActor () -> Void] = []
    var taskbarCreated: UINT = 0

    init(walker: Walker) { self.walker = walker; walker.host = self; page.walker = walker }
    var sc: CGFloat { CGFloat(dpi) / 96 }                                  // device pixels a point
    var size: (w: Int32, h: Int32) { (Int32((Layout.w * K * sc).rounded()), Int32(((walker.cardH * K).rounded() * sc).rounded())) }
    var pageTop: CGFloat { (Layout.pane * K).rounded() }

    // MARK: the window
    /// The window, placed where it was left (or the primary screen's bottom right), then the tray icon, the step counter, the clock.
    func open() {
        wide("PokeWalker") { name in
            var wc = WNDCLASSEXW(); wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size); wc.lpfnWndProc = wndProc
            wc.hInstance = GetModuleHandleW(nil); wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)); wc.lpszClassName = name   // IDC_ARROW
            _ = RegisterClassExW(&wc)
            let sx = settings.int("win.x", Int.min), sy = settings.int("win.y", Int.min)
            hwnd = CreateWindowExW(DWORD(WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW), name, name, DWORD(truncatingIfNeeded: WS_POPUP),
                                   sx == Int.min ? 0 : Int32(clamping: sx), sy == Int.min ? 0 : Int32(clamping: sy), 1, 1, nil, nil, GetModuleHandleW(nil), nil)
            dpi = GetDpiForWindow(hwnd)
            var r = RECT(); _ = GetWindowRect(hwnd, &r)
            let s = size, w = work(r)
            let at = sx == Int.min ? POINT(x: w.right - s.w - 24, y: w.bottom - s.h - 24) : POINT(x: r.left, y: r.top)
            dpi = GetDpiForWindow(hwnd)
            move = at; anchorTop = at.y; fit()
        }
        noIME()
        taskbarCreated = wide("TaskbarCreated") { RegisterWindowMessageW($0) }
        icon = ballIcon(Int(GetSystemMetrics(SM_CXSMICON))); tray(DWORD(NIM_ADD))
        var devs = [RAWINPUTDEVICE(usUsagePage: 1, usUsage: 6, dwFlags: DWORD(RIDEV_INPUTSINK), hwndTarget: hwnd),   // keyboards, mice: counted, never read
                    RAWINPUTDEVICE(usUsagePage: 1, usUsage: 2, dwFlags: DWORD(RIDEV_INPUTSINK), hwndTarget: hwnd)]
        _ = RegisterRawInputDevices(&devs, UINT(devs.count), UINT(MemoryLayout<RAWINPUTDEVICE>.size))
        render()
        _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE)
        _ = SetTimer(hwnd, 1, 100, nil)
    }
    /// The work area (the screen less the taskbar) of the monitor nearest r.
    func work(_ r: RECT) -> RECT {
        var r = r, mi = MONITORINFO(); mi.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        _ = GetMonitorInfoW(MonitorFromRect(&r, DWORD(MONITOR_DEFAULTTONEAREST)), &mi); return mi.rcWork
    }
    /// The window follows the page: its top stays where the user put it (the LCD and keys never move); a page too tall for the space under it lifts
    /// the card, a shorter one lets it back down; kept on its monitor.
    func fit() {
        var r = RECT(); _ = GetWindowRect(hwnd, &r)
        let s = size, x = move?.x ?? r.left, top = anchorTop ?? move?.y ?? r.top
        if anchorTop == nil { anchorTop = top }
        let w = work(RECT(left: x, top: top, right: x + s.w, bottom: top + s.h))
        move = POINT(x: min(max(x, w.left), w.right - s.w), y: min(max(top, w.top), w.bottom - s.h))
        needAll = true; post()
    }
    func post() { if !posted, let hwnd { posted = true; _ = PostMessageW(hwnd, wmRender, 0, 0) } }
    /// Draw what changed into the buffer and lay it on the screen.
    func render() {
        posted = false
        let s = size
        if raster.w != Int(s.w) || raster.h != Int(s.h) { raster = Raster(Int(s.w), Int(s.h)); needAll = true }
        guard needAll || needLCD else { return }
        let c = SoftCanvas(raster, scale: sc), down = pressed.flatMap { Date().timeIntervalSince(pressedAt) < 0.15 ? $0 : nil }
        if needAll {
            raster.px.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
            drawWhole(walker, page, c, shown: shown, down: down)
        } else { walker.drawCard(c, CGRect(x: 0, y: 0, width: Layout.w * K, height: (walker.cardH * K).rounded()), shown: shown, down: down, lcdOnly: true) }   // most frames: the LCD
        needAll = false; needLCD = false
        present()
    }
    func present() {
        let w = raster.w, h = raster.h
        guard w > 0, h > 0 else { return }
        if dibSize != (w, h) {
            var bi = BITMAPINFO(); bi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
            bi.bmiHeader.biWidth = LONG(w); bi.bmiHeader.biHeight = -LONG(h); bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32   // top-down BGRA
            let old = dib; dib = CreateDIBSection(memDC, &bi, UINT(DIB_RGB_COLORS), &bits, nil, 0); _ = SelectObject(memDC, dib)
            if let old { _ = DeleteObject(old) }
            dibSize = (w, h)
        }
        guard let bits else { return }
        raster.px.withUnsafeBytes { bits.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        var sz = tagSIZE(cx: LONG(w), cy: LONG(h)), src = POINT(x: 0, y: 0)
        var blend = BLENDFUNCTION(BlendOp: BYTE(AC_SRC_OVER), BlendFlags: 0, SourceConstantAlpha: 255, AlphaFormat: BYTE(AC_SRC_ALPHA))
        if var at = move { _ = UpdateLayeredWindow(hwnd, nil, &at, &sz, memDC, &src, 0, &blend, DWORD(ULW_ALPHA)); move = nil }
        else { _ = UpdateLayeredWindow(hwnd, nil, nil, &sz, memDC, &src, 0, &blend, DWORD(ULW_ALPHA)) }
    }
    /// Turns the IME off for the card: M stays M (not ㅡ) with a Korean keyboard (imm32, looked up: not every SDK module has it).
    func noIME() {
        guard let m = wide("imm32.dll", { LoadLibraryW($0) }), let f = GetProcAddress(m, "ImmAssociateContext") else { return }
        typealias Assoc = @convention(c) (HWND?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        _ = unsafeBitCast(f, to: Assoc.self)(hwnd, nil)
    }

    // MARK: the clock (10 a second; 30 a second while something plays)
    func tick() {
        walker.tick(Date())
        updateStatus()
        frame()
        let busy = walker.busy
        if busy != fast { fast = busy; if busy { _ = SetTimer(hwnd, 2, 33, nil) } else { _ = KillTimer(hwnd, 2) } }
    }
    /// The pane and the screen, drawn again if the frame changed.
    func frame() {
        let now = Date(), visible = Bool(IsWindowVisible(hwnd))
        if visible { walker.refreshPane(now) }
        guard visible else { return }                                                             // hidden in the tray: rules keep running, nothing to draw
        walker.stroll(now)
        let fb = walker.compose(now), recent = now.timeIntervalSince(pressedAt) < 0.3
        if fb.px != shown?.px || fb.col != shown?.col || fb.runs != shown?.runs || fb.flips != shown?.flips || fb.sprites != shown?.sprites || fb.pics != shown?.pics || fb.over != shown?.over || recent {
            shown = fb; if recent { needAll = true } else { needLCD = true }                      // idle home = ~2 redraws a second
        }
        render()
    }
    func updateStatus() {
        let s = "오늘 \(walker.state.today.formatted())걸음 · \(walker.state.watts)W" + (walker.state.egg.map { $0.left < 500 ? " · 알" : "" } ?? "")
        let t = "PokeWalker — 클릭: 보이기/숨기기 · 우클릭: 메뉴\n" + s
        if t != tip { tip = t; tray(DWORD(NIM_MODIFY)) }
    }

    // MARK: the walker's host
    func redraw(_ part: CardPart) {
        switch part {
        case .all: shown = nil; needAll = true
        case .lcd: needLCD = true
        case .page, .key, .title: needAll = true
        }
        post()
    }
    func resized() { fit() }
    func notify(_ title: String, _ body: String) {                                              // a tray balloon (a toast on Windows 10 / 11)
        var n = trayData(); n.uFlags = UINT(NIF_INFO); put(title, &n.szInfoTitle); put(body, &n.szInfo); n.dwInfoFlags = DWORD(NIIF_INFO) | DWORD(NIIF_NOSOUND)
        _ = Shell_NotifyIconW(DWORD(NIM_MODIFY), &n)
    }
    func counter() -> UInt32 { steps }
    func boot() -> Double { started }
    var windowHidden: Bool { !Bool(IsWindowVisible(hwnd)) }
    /// Card <-> tray. Hiding parks it on the home screen so the events (which wait for home) keep coming.
    func toggleShown() {
        if Bool(IsWindowVisible(hwnd)) { if !walker.inBattle { walker.screen = .home }; _ = ShowWindow(hwnd, SW_HIDE) }
        else { shown = nil; walker.refreshPane(Date(), force: true); needAll = true; render(); _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE) }   // back at today's page and height
        settings.set("hidden", !Bool(IsWindowVisible(hwnd)))
    }
    /// The tallest page (포켓몬 · 도구) at that size fits the monitor the card is on.
    func fits(size: CGFloat) -> Bool {
        var r = RECT(); _ = GetWindowRect(hwnd, &r); let w = work(r)
        return PaneContent.tallest * size / 2 * sc <= CGFloat(w.bottom - w.top)
    }
    func beep() { _ = MessageBeep(UINT(MB_OK)) }
    func confirm(_ title: String, _ body: String, ok: String) -> Bool {
        wide(body + "\n\n확인 = " + ok) { b in wide(title) { t in MessageBoxW(hwnd, b, t, UINT(MB_OKCANCEL) | UINT(MB_ICONQUESTION) | UINT(MB_TOPMOST) | UINT(MB_SETFOREGROUND)) } } == IDOK
    }
    func quit() { walker.save(); tray(DWORD(NIM_DELETE)); _ = DestroyWindow(hwnd) }

    // MARK: the tray
    func trayData() -> NOTIFYICONDATAW {
        var n = NOTIFYICONDATAW(); n.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size); n.hWnd = hwnd; n.uID = 1; return n
    }
    func tray(_ op: DWORD) {
        var n = trayData(); n.uFlags = UINT(NIF_ICON) | UINT(NIF_MESSAGE) | UINT(NIF_TIP); n.uCallbackMessage = wmTray; n.hIcon = icon; put(tip, &n.szTip)
        _ = Shell_NotifyIconW(op, &n)
    }
    /// A Poké Ball (the core's caught mark) in pixels, as an icon.
    func ballIcon(_ side: Int) -> HICON? {
        let r = Raster(side, side), c = SoftCanvas(r, scale: 1)
        c.miniBall(CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2), CGFloat(side) / 2 - 0.5)
        var bi = BITMAPINFO(); bi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bi.bmiHeader.biWidth = LONG(side); bi.bmiHeader.biHeight = -LONG(side); bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32
        var bits: UnsafeMutableRawPointer? = nil
        guard let color = CreateDIBSection(nil, &bi, UINT(DIB_RGB_COLORS), &bits, nil, 0), let bits else { return nil }
        let px = bits.assumingMemoryBound(to: UInt32.self)
        for (i, p) in r.px.enumerated() {                                                          // icons want straight alpha
            let a = p >> 24; func un(_ v: UInt32) -> UInt32 { a == 0 ? 0 : min(255, (v * 255 + a / 2) / a) }
            px[i] = a << 24 | un(p >> 16 & 255) << 16 | un(p >> 8 & 255) << 8 | un(p & 255)
        }
        var zeros = [UInt8](repeating: 0, count: (side + 15) / 16 * 2 * side)
        let mask = CreateBitmap(Int32(side), Int32(side), 1, 1, &zeros)
        var ii = ICONINFO(fIcon: true, xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color)
        let h = CreateIconIndirect(&ii)
        _ = DeleteObject(color); _ = DeleteObject(mask)
        return h
    }

    // MARK: the menu: the walker's tree (Core/Menu.swift) as a popup; a row's action comes back as WM_COMMAND
    func showMenu() {
        menuActions = []
        func build(_ items: [MenuItem]) -> HMENU? {
            let m = CreatePopupMenu()
            for i in items {
                if i.isSeparator { _ = AppendMenuW(m, UINT(MF_SEPARATOR), 0, nil); continue }
                var flags = UINT(MF_STRING)
                if !i.enabled { flags |= UINT(MF_GRAYED) }
                if i.checked { flags |= UINT(MF_CHECKED) }
                let title = i.title.replacingOccurrences(of: "&", with: "&&")                        // no mnemonics
                if let c = i.children, let sub = build(c) { _ = wide(title) { AppendMenuW(m, flags | UINT(MF_POPUP), UINT_PTR(UInt(bitPattern: sub)), $0) }; continue }
                menuActions.append(i.action ?? {})
                _ = wide(title) { AppendMenuW(m, flags, UINT_PTR(menuActions.count), $0) }
            }
            return m
        }
        guard let m = build(walker.menu()) else { return }
        var at = POINT(); _ = GetCursorPos(&at)
        _ = SetForegroundWindow(hwnd)                                                              // so a click elsewhere closes it
        _ = TrackPopupMenu(m, UINT(TPM_RIGHTBUTTON), at.x, at.y, 0, hwnd, nil)
        _ = PostMessageW(hwnd, UINT(WM_NULL), 0, 0)
        _ = DestroyMenu(m)
    }

    // MARK: input
    /// A click, in card points: a key, the chevron, the LCD (a touch only ends a message), the page's hits; anything else drags the card.
    func mouseDown(_ p: CGPoint, count n: Int) {
        if p.y >= pageTop, p.y < (walker.cardH * K).rounded() { pageDown(CGPoint(x: p.x, y: p.y - pageTop), count: n); return }   // the page is its own view on the Mac
        if let i = buttons.firstIndex(where: { hypot($0.c.x - p.x, $0.c.y - p.y) <= $0.r + 2 * K }) {
            if i == 1 || i == 4, n > 1 { return }                                                  // ● or 메뉴 twice fast: once (the 2nd would act on what the 1st opened)
            pressed = i; pressedAt = Date(); walker.press(i)
            _ = SetTimer(hwnd, 3, 150, nil)                                                        // the key comes back up
        } else if chevronRect.contains(p), walker.title().chevron != nil { walker.toggleStatus() }
        else if lcdRect.contains(p), walker.touch(Int((p.x - lcdRect.minX) / PX), Int((p.y - lcdRect.minY) / PX)) { needAll = true; post() }
        else { drag() }
    }
    var pageKind: Int {
        let c = walker.pane
        return [c.battle != nil, c.dex != nil, c.grid != nil, c.shop != nil, c.menu != nil, c.mon != nil, c.radar != nil, c.card != nil, c.learn != nil, c.tower != nil, c.items != nil].firstIndex(of: true).map { $0 + 1 } ?? 0
    }
    func pageDown(_ p: CGPoint, count n: Int) {
        let c = walker.pane
        guard let k = page.hits.first(where: { $0.0.contains(p) })?.1 else { drag(); return }    // not on a button: drag the whole card
        if n == 1 { downOn = pageKind } else if c.battle != nil || c.shop?.ask != nil || c.mon != nil || pageKind != downOn { return }   // a double-click's 2nd click on what the 1st one opened: ignored
        if k >= 5000, k < 10000 { walker.pageTap(k) } else if k >= 4000 { walker.gridTap(k) } else if k >= 3000 { walker.menuTap(k - 3000) } else if k >= 2000 { walker.shopTap(k) } else { walker.sidePick(k) }
    }
    func drag() { _ = ReleaseCapture(); _ = SendMessageW(hwnd, UINT(WM_NCLBUTTONDOWN), WPARAM(HTCAPTION), 0) }
    /// The wheel over the page: the shop list a row a notch, a grid a page.
    func wheel(_ delta: Int, at p: CGPoint) {
        let grid = walker.pane.grid != nil
        guard p.y >= pageTop, walker.pane.shop != nil || grid else { return }
        scrolled += delta
        while abs(scrolled) >= 120 { let d = scrolled > 0 ? -1 : 1; if grid { walker.gridStep(d * GridModel.perPage) } else { walker.shopRow(d) }; scrolled += d * 120 }
    }
    /// ← → ↑ ↓, page up / down, tab, return / space, esc (= ↩ 뒤로), M (= 메뉴 / 홈): Walker.key.
    func keyDown(_ wp: WPARAM, _ lp: LPARAM) -> Bool {
        var vk = Int32(truncatingIfNeeded: wp)
        if vk == VK_PROCESSKEY { vk = Int32(MapVirtualKeyW(UINT(lp >> 16 & 0xFF), UINT(MAPVK_VSC_TO_VK))) }   // an IME had it: the key itself
        let keys: [Int32: Walker.Key] = [VK_LEFT: .left, VK_RIGHT: .right, VK_UP: .up, VK_DOWN: .down, VK_PRIOR: .pageUp, VK_NEXT: .pageDown, VK_TAB: .tab, VK_RETURN: .enter, VK_SPACE: .enter, VK_ESCAPE: .back, 0x4D: .menu]
        guard let k = keys[vk] else { return false }
        return walker.key(k, shift: GetKeyState(VK_SHIFT) < 0, held: lp >> 30 & 1 == 1)
    }
    /// A key down or a click anywhere (Raw Input): a step. A held key's repeats aren't.
    func rawInput(_ lp: LPARAM) {
        guard let h = HRAWINPUT(bitPattern: Int(lp)) else { return }
        let head = UINT(MemoryLayout<RAWINPUTHEADER>.size)
        var size: UINT = 0; _ = GetRawInputData(h, UINT(RID_INPUT), nil, &size, head)
        guard size >= head, size <= 1024 else { return }
        var buf = [UInt8](repeating: 0, count: Int(size))
        guard GetRawInputData(h, UINT(RID_INPUT), &buf, &size, head) == size else { return }
        buf.withUnsafeBytes { b in
            let type = b.load(as: RAWINPUTHEADER.self).dwType
            if type == DWORD(RIM_TYPEKEYBOARD) {
                let k = b.load(fromByteOffset: Int(head), as: RAWKEYBOARD.self), id = k.VKey | (k.Flags & UInt16(RI_KEY_E0) != 0 ? 0x100 : 0)
                if k.Flags & UInt16(RI_KEY_BREAK) != 0 { keysDown.remove(id) } else if keysDown.insert(id).inserted { steps &+= 1 }
            } else if type == DWORD(RIM_TYPEMOUSE) {
                let f = b.load(fromByteOffset: Int(head) + 4, as: UInt16.self)                   // RAWMOUSE.usButtonFlags
                if f & UInt16(RI_MOUSE_LEFT_BUTTON_DOWN) != 0 { steps &+= 1 }
                if f & UInt16(RI_MOUSE_RIGHT_BUTTON_DOWN) != 0 { steps &+= 1 }
            }
        }
    }
    /// Over a key, the chevron or one of the page's buttons: the hand (the LCD is to look at).
    func cursorHand(_ p: CGPoint) -> Bool {
        if p.y >= pageTop { let q = CGPoint(x: p.x, y: p.y - pageTop); return page.hits.contains { $0.0.contains(q) } }
        return buttons.contains { hypot($0.c.x - p.x, $0.c.y - p.y) <= $0.r } || (walker.title().chevron != nil && chevronRect.contains(p))
    }
    func client(_ lp: LPARAM) -> CGPoint { CGPoint(x: CGFloat(lo(lp)) / sc, y: CGFloat(hi(lp)) / sc) }

    // MARK: messages
    func handle(_ msg: UINT, _ wp: WPARAM, _ lp: LPARAM) -> LRESULT? {
        switch msg {
        case UINT(WM_TIMER):
            switch wp { case 1: tick(); case 2: frame(); default: _ = KillTimer(hwnd, wp); tick() }
            return 0
        case wmRender: render(); return 0
        case UINT(WM_LBUTTONDOWN):
            let t = Int(GetMessageTime()), x = lo(lp), y = hi(lp)                                  // a double-click's count, as the Mac's clickCount
            let same = t - clicks.time <= Int(GetDoubleClickTime()) && abs(x - clicks.x) <= Int(GetSystemMetrics(SM_CXDOUBLECLK)) / 2 && abs(y - clicks.y) <= Int(GetSystemMetrics(SM_CYDOUBLECLK)) / 2
            clicks = (t, x, y, same ? clicks.n + 1 : 1)
            mouseDown(client(lp), count: clicks.n)
            return 0
        case UINT(WM_RBUTTONUP): showMenu(); return 0
        case UINT(WM_COMMAND):
            let id = Int(wp & 0xFFFF)
            if id >= 1, id <= menuActions.count { menuActions[id - 1]() }
            return 0
        case UINT(WM_MOUSEWHEEL):
            var at = POINT(x: Int32(lo(lp)), y: Int32(hi(lp))); _ = ScreenToClient(hwnd, &at)
            wheel(Int(Int16(truncatingIfNeeded: wp >> 16)), at: CGPoint(x: CGFloat(at.x) / sc, y: CGFloat(at.y) / sc))
            return 0
        case UINT(WM_KEYDOWN): return keyDown(wp, lp) ? 0 : nil
        case UINT(WM_INPUT): rawInput(lp); return nil                                             // then the default (its cleanup)
        case UINT(WM_SETCURSOR):
            guard lp & 0xFFFF == LPARAM(HTCLIENT) else { return nil }
            var at = POINT(); _ = GetCursorPos(&at); _ = ScreenToClient(hwnd, &at)
            _ = SetCursor(LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: cursorHand(CGPoint(x: CGFloat(at.x) / sc, y: CGFloat(at.y) / sc)) ? 32649 : 32512)))   // IDC_HAND / IDC_ARROW
            return 1
        case UINT(WM_EXITSIZEMOVE):                                                               // the user dragged it: that's the new place
            var r = RECT(); _ = GetWindowRect(hwnd, &r); anchorTop = r.top
            settings.set("win.x", Int(r.left)); settings.set("win.y", Int(r.top))
            return 0
        case UINT(WM_DPICHANGED):                                                                 // onto another monitor: its scale, the place Windows suggests
            dpi = UInt32(wp & 0xFFFF)
            if let r = UnsafePointer<RECT>(bitPattern: Int(lp))?.pointee { move = POINT(x: r.left, y: r.top); anchorTop = r.top }
            fit(); shown = nil
            return 0
        case wmTray:
            switch UINT(lp & 0xFFFF) { case UINT(WM_LBUTTONUP): toggleShown(); case UINT(WM_RBUTTONUP): showMenu(); default: break }
            return 0
        case wmShow: if windowHidden { toggleShown() }; return 0                                  // launched again: a hidden card comes back
        case taskbarCreated: tray(DWORD(NIM_ADD)); return 0                                       // Explorer restarted: the icon again
        case UINT(WM_QUERYENDSESSION): walker.save(); return 1
        case UINT(WM_ENDSESSION): if wp != 0 { walker.save() }; return 0
        case UINT(WM_POWERBROADCAST): if wp == WPARAM(PBT_APMSUSPEND) { walker.save() }; return nil   // going to sleep
        case UINT(WM_CLOSE): quit(); return 0
        case UINT(WM_DESTROY): PostQuitMessage(0); return 0
        default: return nil
        }
    }
}
#endif
