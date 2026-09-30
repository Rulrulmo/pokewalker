#if os(macOS)
import AppKit
// The menu on the Mac: the walker's MenuItem tree (Core/Menu.swift) as an NSMenu (right-click, the menu-bar item), the menu-bar item, showing and
// hiding the card, the 크기 menu's screen.

/// A row's action: the NSMenuItem's target, kept alive by its representedObject (target is weak).
@MainActor final class MenuAction: NSObject {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    @objc func fire(_ sender: Any?) { run() }
}
@MainActor var statusItem: NSStatusItem? = nil

extension WalkerView {
    /// The 3V+ colour: amber, darker on light menus (systemOrange there is ~2:1 on white), orange on dark ones.
    static let vColor = NSColor(name: "vMark") { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .systemOrange : NSColor(red: 0.69, green: 0.40, blue: 0, alpha: 1) }
    /// The tree as an NSMenu: no autoenabling (each row says whether it's on); a row's strong part bold in vColor.
    static func nsMenu(_ items: [MenuItem]) -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        for i in items {
            if i.isSeparator { m.addItem(.separator()); continue }
            let it = m.addItem(withTitle: i.title, action: i.action == nil ? nil : #selector(MenuAction.fire(_:)), keyEquivalent: i.key)
            if let f = i.action { let a = MenuAction(f); it.target = a; it.representedObject = a }
            it.isEnabled = i.enabled; it.state = i.checked ? .on : .off; it.toolTip = i.tip
            if let v = i.strong, let r = i.title.range(of: v, options: .backwards) {
                let base = NSFont.menuFont(ofSize: 0), s = NSMutableAttributedString(string: i.title, attributes: [.font: base])
                s.addAttributes([.foregroundColor: WalkerView.vColor, .font: NSFont.boldSystemFont(ofSize: base.pointSize)], range: NSRange(r, in: i.title))
                it.attributedTitle = s
            }
            if let c = i.children { it.submenu = nsMenu(c) }
        }
        return m
    }
    func buildMenu() -> NSMenu { WalkerView.nsMenu(walker.menu()) }
    /// Walker <-> menu bar. Hiding parks it on the home screen so the events (which wait for home) keep coming.
    @objc func toggleShown(_ sender: Any?) {
        guard let w = window else { return }
        if w.isVisible { if !walker.inBattle { walker.screen = .home }; w.orderOut(nil) } else { shown = nil; walker.refreshPane(Date(), force: true); w.orderFrontRegardless() }   // a fight just waits while hidden; back at today's page and height
        settings.set("hidden", !w.isVisible)
    }
    func updateStatus() {
        let s = "\(walker.state.watts)W" + (walker.state.egg.map { $0.left < 500 ? " ·알" : "" } ?? "")   // watts: what the radar / dowsing spend
        if s != lastStatus { lastStatus = s; statusItem?.button?.title = " " + s }
    }
    @objc func statusClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            statusItem?.menu = buildMenu(); statusItem?.button?.performClick(nil); statusItem?.menu = nil   // pop the menu once, keep left-click as the toggle
        } else { toggleShown(nil) }
    }
    /// The tallest page (포켓몬 · 도구) at that size fits the screen the card is on.
    func fits(size: CGFloat) -> Bool { PaneContent.tallest * size / 2 <= (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? .infinity }
    /// A frame pulled back inside a screen's visible area (the body is wide: a spot near an edge must not push it off).
    static func onScreen(_ f: NSRect, in s: NSRect?) -> NSRect {
        guard let s else { return f }
        var g = f; g.origin.x = min(max(g.minX, s.minX), s.maxX - g.width); g.origin.y = min(max(g.minY, s.minY), s.maxY - g.height); return g
    }
}
#endif
