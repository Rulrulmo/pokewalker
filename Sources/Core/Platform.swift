import Foundation
// What the logic asks of the platform it runs on. A platform sets `settings` (and `fonts`: Core/Canvas.swift) first thing at launch and gives its Walker a host
// (the Mac's: Sources/Mac/MacHost.swift).

/// The menu's choices, kept between launches by key; each read passes the default the app has always had. The Mac: UserDefaults (the same keys as ever).
protocol Settings {
    func bool(_ key: String, _ def: Bool) -> Bool
    func int(_ key: String, _ def: Int) -> Int
    func set(_ key: String, _ v: Bool); func set(_ key: String, _ v: Int)
}
@MainActor var settings: (any Settings)! = nil

/// What the walker calls on (Walker.host): the view that shows it, its window, and the system's banners and step counter. The Mac's: WalkerView.
@MainActor protocol Host: AnyObject {
    /// A banner from the app: title over body.
    func notify(_ title: String, _ body: String)
    /// Keys pressed + mouse clicks this login (it may wrap): the step counter Walk.sync reads.
    func counter() -> UInt32
    /// When this boot began (seconds since 1970): a new boot re-baselines the counter.
    func boot() -> Double
    /// Part of the card changed: draw it again (.all: the LCD composed afresh too).
    func redraw(_ part: CardPart)
    /// The card's size changed (Walker.cardH, or the 크기 menu: SIZE): the window follows.
    func resized()
    /// The card is hidden (in the menu bar); toggleShown() hides it or brings it back (the menu's first row).
    var windowHidden: Bool { get }
    func toggleShown()
    /// At this SIZE the tallest page still fits the screen the card is on (the 크기 menu); beep() when a pick can't be done.
    func fits(size: CGFloat) -> Bool
    func beep()
    /// A yes / no question in front of everything (the one real confirmation: 중복 놓아주기); true = ok was chosen.
    func confirm(_ title: String, _ body: String, ok: String) -> Bool
    func quit()
}
/// What a redraw covers: the LCD, the pane's page, the 메뉴 / 홈 key, the title row, or the whole card.
enum CardPart { case lcd, page, key, title, all }

/// A bundled file's bytes by name ("hgss.bin", "Galmuri9.ttf"), from the app's Resources (the Mac's .app: Bundle.main); nil = missing.
func resource(_ name: String) -> Data? { Bundle.main.resourceURL.flatMap { try? Data(contentsOf: $0.appendingPathComponent(name), options: .mappedIfSafe) } }
