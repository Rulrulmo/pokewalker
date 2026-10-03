// Launch: --selftest, or the app — the Mac's menu-bar app with its floating device here, Windows' in Sources/Windows/WinApp.swift.
#if os(macOS)
import AppKit
import UserNotifications

// MARK: - app
settings = UserDefaults.standard                                                               // before anything reads a setting (the look's globals)
fonts = MacFonts()                                                                             // before anything lays out text
if CommandLine.arguments.contains("--selftest") { exit(selftest() ? 0 : 1) }
if let i = CommandLine.arguments.firstIndex(of: "--stage-update"), i + 1 < CommandLine.arguments.count {   // a local build's zip, to try the install (Core/Update.swift)
    exit(Update.stageLocal(URL(fileURLWithPath: CommandLine.arguments[i + 1])) ? 0 : 1)
}
let launch = Update.atLaunch()                                                                 // a downloaded update goes in first: the helper starts it once this exits
if launch == .installing { exit(0) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let loaded = Store.loadChecked(signedBefore: settings.bool("saveSigned", false))             // a save changed by hand: the last one the app made
let walker = Walker(state: loaded.walk), view = WalkerView(walker: walker)                  // the view is the walker's host
walker.startCloud(Cloud.app(persist: walker.persist))                                         // the save server, if on: a 1.x save goes aside first (08 §5)
walker.updater = Updater.app(persist: walker.persist)
/// Opening the app again (Finder, Spotlight, Launchpad) brings a hidden walker back: macOS may hide the menu-bar icon (too many icons, the notch, 메뉴 막대 settings).
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if view.window?.isVisible != true { view.toggleShown(nil) }
        return false
    }
}
let appDelegate = AppDelegate()
app.delegate = appDelegate
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
    b.toolTip = "PokeWalker — 클릭: 보이기/숨기기 (⌃⌥P) · 우클릭: 메뉴"
}
registerHideHotKey { view.toggleShown(nil) }                       // ⌃⌥P from anywhere
walker.state.dex()
walker.levelled = walker.state.sync(counter: view.counter(), boot: view.boot(), at: Date(), away: true)   // steps typed while the app was quit (same login) count
walker.auditAtLaunch(tampered: loaded.tampered)                  // an edited save restored; once: a macro's / an edited save corrected
walker.queueReadyEvolutions()                                    // the walker's ones past their evolution (before 1.4 only the companion evolved) evolve at home
if case .updated(let v) = launch { walker.announceUpdate(v) }
walker.save()
walker.refreshPane(Date(), force: true)                          // the page it opens on (the status sheet): no jump after it shows
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
panel.orderFrontRegardless(); settings.set("hidden", false)                                    // a launch always shows it: a hidden walker whose menu-bar icon is hidden too could never come back
walker.sideOn = true
panel.makeFirstResponder(view)

let timer = Timer(timeInterval: 0.1, target: view, selector: #selector(WalkerView.tick(_:)), userInfo: nil, repeats: true)
timer.tolerance = 0.02
RunLoop.main.add(timer, forMode: .common)
let ws = NSWorkspace.shared.notificationCenter
ws.addObserver(view, selector: #selector(WalkerView.save(_:)), name: NSWorkspace.willSleepNotification, object: nil)
ws.addObserver(view, selector: #selector(WalkerView.woke(_:)), name: NSWorkspace.didWakeNotification, object: nil)
ws.addObserver(view, selector: #selector(WalkerView.poweringOff(_:)), name: NSWorkspace.willPowerOffNotification, object: nil)
NotificationCenter.default.addObserver(view, selector: #selector(WalkerView.quitting(_:)), name: NSApplication.willTerminateNotification, object: nil)
app.run()
#elseif os(Windows)
windowsMain()
#endif
