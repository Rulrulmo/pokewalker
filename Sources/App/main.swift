import AppKit
import UserNotifications
// Launch: --selftest, or the menu-bar app with its floating device.

// MARK: - app
if CommandLine.arguments.contains("--selftest") { exit(selftest() ? 0 : 1) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let view = WalkerView(state: Store.load())
let notifyDelegate = NotifyDelegate()
UNUserNotificationCenter.current().delegate = notifyDelegate
UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { @Sendable ok, _ in   // called off the main thread
    // An ad-hoc signed app (no Apple certificate) is refused outright (UNErrorDomain 1) — fall back to osascript's banners
    DispatchQueue.main.async { useOsascript = !ok }
}
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let b = statusItem?.button {
    b.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in                   // a Poké Ball, as a template so it follows the bar's colour
        let o = NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1.5)); o.lineWidth = 1.6; NSColor.black.setStroke(); o.stroke()
        let top = NSBezierPath(); top.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 6.5, startAngle: 0, endAngle: 180); top.close(); NSColor.black.setFill(); top.fill()
        NSColor.black.setFill(); NSRect(x: 1.5, y: 7.2, width: 13, height: 1.6).fill()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 5.6, y: 5.6, width: 4.8, height: 4.8)).fill()
        let btn = NSBezierPath(ovalIn: NSRect(x: 5.6, y: 5.6, width: 4.8, height: 4.8)); btn.lineWidth = 1.4; NSColor.black.setStroke(); btn.stroke()
        return true
    }
    b.image?.isTemplate = true
    b.imagePosition = .imageLeft
    b.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    b.target = view; b.action = #selector(WalkerView.statusClick(_:)); b.sendAction(on: [.leftMouseUp, .rightMouseUp])
    b.toolTip = "PokeWalker — 클릭: 보이기/숨기기 · 우클릭: 메뉴"
}
view.state.dex()
view.levelled = view.state.sync(counter: WalkerView.counter(), boot: WalkerView.boot(), at: Date())      // steps typed while the app was quit (same login) count
view.save(nil)
view.refreshPane(Date(), force: true)                          // the page it opens on (the status sheet, if it was left open): no jump after it shows
let size = view.frame.size
let panel = Panel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.hidesOnDeactivate = false
panel.becomesKeyOnlyIfNeeded = true
panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
panel.contentView = view
if !panel.setFrameUsingName("pokewalker", force: true), let s = NSScreen.screens.first {          // force: the saved size too (an old 288x288 device), so its screen is found right
    panel.setFrame(NSRect(x: s.visibleFrame.maxX - size.width - 24, y: s.visibleFrame.minY + 24, width: size.width, height: size.height), display: false)
}
panel.setFrameAutosaveName("pokewalker")
do {                                                                                              // grow from the saved top-left, kept on the screen it was on
    let old = panel.frame, top = NSPoint(x: old.minX, y: old.maxY)
    let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: top.x, y: top.y - 1)) } ?? panel.screen
    panel.setFrame(WalkerView.onScreen(NSRect(x: top.x, y: top.y - size.height, width: size.width, height: size.height), in: screen?.visibleFrame), display: false)
    view.anchorTop = top.y
}
if !UserDefaults.standard.bool(forKey: "hidden") { panel.orderFrontRegardless() }
view.sideOn = true
panel.makeFirstResponder(view)

let timer = Timer(timeInterval: 0.1, target: view, selector: #selector(WalkerView.tick(_:)), userInfo: nil, repeats: true)
timer.tolerance = 0.02
RunLoop.main.add(timer, forMode: .common)
let ws = NSWorkspace.shared.notificationCenter
ws.addObserver(view, selector: #selector(WalkerView.save(_:)), name: NSWorkspace.willSleepNotification, object: nil)
NotificationCenter.default.addObserver(view, selector: #selector(WalkerView.save(_:)), name: NSApplication.willTerminateNotification, object: nil)
app.run()
