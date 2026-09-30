import Foundation
// What the logic asks of the platform it runs on. A platform sets `settings` first thing at launch and gives its Walker a host (the Mac's: Sources/Mac/MacHost.swift).

/// The menu's choices, kept between launches by key; each read passes the default the app has always had. The Mac: UserDefaults (the same keys as ever).
protocol Settings {
    func bool(_ key: String, _ def: Bool) -> Bool
    func int(_ key: String, _ def: Int) -> Int
    func string(_ key: String, _ def: String) -> String
    func data(_ key: String) -> Data?
    func set(_ key: String, _ v: Bool); func set(_ key: String, _ v: Int); func set(_ key: String, _ v: String); func set(_ key: String, _ v: Data)
}
@MainActor var settings: (any Settings)! = nil

/// What the walker calls on (Walker.host): the view that shows it, and the system's banners and step counter. The Mac's: WalkerView.
@MainActor protocol Host: AnyObject {
    /// A banner from the app: title over body.
    func notify(_ title: String, _ body: String)
    /// Keys pressed + mouse clicks this login (it may wrap): the step counter Walk.sync reads.
    func counter() -> UInt32
    /// When this boot began (seconds since 1970): a new boot re-baselines the counter.
    func boot() -> Double
    /// Part of the card changed: draw it again (.all: the LCD composed afresh too).
    func redraw(_ part: CardPart)
    /// The card's height changed (Walker.cardH): the window follows.
    func resized()
}
/// What a redraw covers: the LCD, the pane's page, the 메뉴 / 홈 key, the title row, or the whole card.
enum CardPart { case lcd, page, key, title, all }

/// A bundled file's bytes by name ("hgss.bin", "Galmuri9.ttf"), from the app's Resources (the Mac's .app: Bundle.main); nil = missing.
func resource(_ name: String) -> Data? { Bundle.main.resourceURL.flatMap { try? Data(contentsOf: $0.appendingPathComponent(name), options: .mappedIfSafe) } }
