#if os(Windows)
import Foundation
import WinSDK
// The ID box and the PIN box on Windows (Core/Platform.swift's askText / askPIN; the Mac's are NSAlerts): a small modal window over the card — the message, an EDIT box
// (the IME as Windows has it), 확인 / 취소. Enter = 확인, Esc and the title bar's X = 취소 (IsDialogMessage turns them into IDOK / IDCANCEL).

nonisolated(unsafe) private var inputAnswer: Int32 = 0                                          // IDOK / IDCANCEL once given; 0 while it's up
private let inputProc: WNDPROC = { hwnd, msg, wp, lp in
    switch msg {
    case UINT(WM_COMMAND): let id = Int32(wp & 0xFFFF); if id == IDOK || id == IDCANCEL { inputAnswer = id; return 0 }
    case UINT(WM_CLOSE): inputAnswer = IDCANCEL; return 0
    default: break
    }
    return DefWindowProcW(hwnd, msg, wp, lp)
}

extension WinCard {
    func askText(title: String, message: String) -> String? { input(title, message, pin: false) }
    func askPIN(title: String, message: String) -> String? { input(title, message, pin: true) }
    /// pin: the EDIT box hides what's typed, takes digits only, 4 at most.
    private func input(_ title: String, _ message: String, pin: Bool) -> String? {
        let inst = GetModuleHandleW(nil), cls = "PokeWalkerInput"
        _ = wide(cls) { name -> ATOM in                                                          // once; a second time it's there already
            var wc = WNDCLASSEXW(); wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size); wc.lpfnWndProc = inputProc; wc.hInstance = inst
            wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)); wc.hbrBackground = HBRUSH(bitPattern: Int(COLOR_BTNFACE + 1)); wc.lpszClassName = name   // IDC_ARROW
            return RegisterClassExW(&wc)
        }
        let s = Double(dpi) / 96, px = { (v: Double) in Int32(v * s) }, w = px(340), h = px(170)
        var at = RECT(); _ = GetWindowRect(hwnd, &at)                                              // over the card, kept on its screen's work area
        var mi = MONITORINFO(); mi.cbSize = DWORD(MemoryLayout<MONITORINFO>.size); _ = GetMonitorInfoW(MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST)), &mi)
        let x = max(mi.rcWork.left, min(mi.rcWork.right - w, at.left + (at.right - at.left - w) / 2)), y = max(mi.rcWork.top, min(mi.rcWork.bottom - h, at.top + px(60)))
        guard let box = wide(cls, { c in wide(title) { t in
            CreateWindowExW(DWORD(WS_EX_TOPMOST | WS_EX_DLGMODALFRAME | WS_EX_CONTROLPARENT), c, t, DWORD(truncatingIfNeeded: WS_POPUP) | DWORD(WS_CAPTION | WS_SYSMENU), x, y, w, h, hwnd, nil, inst, nil)
        } }) else { return nil }
        var inner = RECT(); _ = GetClientRect(box, &inner)
        let cw = inner.right - inner.left, pad = px(12), font = GetStockObject(DEFAULT_GUI_FONT)
        func child(_ kind: String, _ text: String, _ style: Int32, _ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32, _ id: Int32) -> HWND? {
            let c = wide(kind) { k in wide(text) { t in
                CreateWindowExW(DWORD(kind == "EDIT" ? WS_EX_CLIENTEDGE : 0), k, t, DWORD(WS_CHILD | WS_VISIBLE | style), x, y, w, h, box, HMENU(bitPattern: Int(id)), inst, nil)
            } }
            _ = SendMessageW(c, UINT(WM_SETFONT), WPARAM(UInt(bitPattern: font)), 1)
            return c
        }
        _ = child("STATIC", message.replacingOccurrences(of: "\n", with: "\r\n"), 0, pad, pad, cw - 2 * pad, px(40), 0)
        let edit = child("EDIT", "", WS_TABSTOP | ES_AUTOHSCROLL | (pin ? ES_PASSWORD | ES_NUMBER : 0), pad, pad + px(46), pin ? px(90) : cw - 2 * pad, px(26), 100)
        if pin { _ = SendMessageW(edit, UINT(EM_LIMITTEXT), 4, 0) }
        let bw = px(88), bh = px(28), by = inner.bottom - pad - bh
        _ = child("BUTTON", "확인", WS_TABSTOP | BS_DEFPUSHBUTTON, cw - pad - 2 * bw - px(8), by, bw, bh, IDOK)
        _ = child("BUTTON", "취소", WS_TABSTOP, cw - pad - bw, by, bw, bh, IDCANCEL)
        _ = EnableWindow(hwnd, false)                                                             // modal: the card waits (its timer still ticks)
        _ = ShowWindow(box, SW_SHOW); _ = SetForegroundWindow(box); _ = SetFocus(edit)
        inputAnswer = 0
        var msg = MSG(), quitting = false
        while inputAnswer == 0 {
            guard Bool(GetMessageW(&msg, nil, 0, 0)) else { quitting = true; break }            // WM_QUIT: hand it back to the main loop
            if !Bool(IsDialogMessageW(box, &msg)) { _ = TranslateMessage(&msg); _ = DispatchMessageW(&msg) }
        }
        var text = [WCHAR](repeating: 0, count: Int(GetWindowTextLengthW(edit)) + 1)
        _ = GetWindowTextW(edit, &text, Int32(text.count))
        _ = EnableWindow(hwnd, true); _ = DestroyWindow(box); _ = SetForegroundWindow(hwnd)
        if quitting { PostQuitMessage(Int32(truncatingIfNeeded: msg.wParam)); return nil }
        return inputAnswer == IDOK ? String(decoding: text.prefix { $0 != 0 }, as: UTF16.self) : nil
    }
}
#endif
