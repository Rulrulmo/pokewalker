import Foundation
// The pane's pages as data: what the walker shows under the band (Walker.pane), the card's height for each. Drawn in Core/Page.swift.

// MARK: - models
/// The battle: names, HP, types for the LCD's HP boxes; the message and the choices for the page.
struct SideModel: Equatable {
    struct Card: Equatable { var name: String; var level, hp, max: Int; var out: Bool; var status: String? = nil; var types: [String] = []; var owned = false }   // types / owned: shown for theirs
    struct MoveBtn: Equatable { var name, type: String; var power: Int; var effect: Double; var pp = 0, maxPP = 0 }
    enum Mode: Equatable { case none, menu([String], Int), moves([MoveBtn], Int), party([Card], Int), items([String], Int), ask(Bool) }   // ask: 아니오 / 예 (true = 예 highlighted)
    var foe: Card; var mine: Card; var message: String; var mode: Mode
}
/// 상점 / BP 교환소: the list, and how many.
struct ShopModel: Equatable {
    struct Row: Equatable { var name, note, price: String; var owned: Int; var can: Bool; var once: Bool }
    var title: String; var rows: [Row]; var sel: Int; var qty: Int?; var most: Int; var total: String
    var hint: String                                                   // the bottom row when nothing is being counted: a message, or why not
    var ask: Bool?                                                     // a once-only row's 정말? (true = 예 highlighted)
}
/// The status sheet (the title row's ⌄): the companion, today, then the rest.
struct StatusModel: Equatable {
    struct Row: Equatable { var key, value: String }
    var dex: Int; var name, sex, level, toNext, nature: String; var female: Bool; var v: Int; var exp: CGFloat; var numbers: [Row]; var rows: [Row]
}
/// 메뉴: the LCD's pages as tiles, the one on the LCD picked.
struct MenuModel: Equatable {
    struct Row: Equatable { var name, note: String }
    var rows: [Row]; var sel: Int
}
/// The 도감 entry (the LCD shows its number, name and types): base stats, where to meet it, how it evolves.
struct DexModel: Equatable {
    var num: Int; var status: Int                                      // 0 not met, 1 seen, 2 caught
    var stats: [Int]; var found: [String]; var evos: [String]          // up to 3 places, 2 evolutions: a line each
}
/// The 도감 / 포켓몬 grid: tabs, a page of box icons (the pick bobbing), the pager; 포켓몬's has the companion and the walker's in a row above.
struct GridModel: Equatable {
    static let perPage = 30, columns = 6                               // 6 x 5
    struct Cell: Equatable { var dex: Int; var look: Int; var shiny = false, v3 = false; var level = 0 }   // look: 0 not met (its number), 1 seen (a shadow), 2 caught / in the box
    var tabs: [String]; var tab: Int
    var cells: [Cell]; var first: Int; var sel: Int?                   // this page's cells; first = cells[0]'s place in the whole list; sel = the pick's cell
    var page, pages: Int; var empty: String; var bob: Bool
    var party: [Cell] = []; var partySel: Int? = nil; var items: Int? = nil   // 포켓몬: the companion + the walker's in a row over the box, then the items chip (nil = no row: 도감)
}
/// One Pokémon of the box, in full: nature and ability with what they do, IVs and EVs as hexagons.
struct MonModel: Equatable {
    var nature, natureNote, ability, abilityNote: String; var up, down: Int?   // stat indices the nature raises / lowers (nil = neutral)
    var ivs, evs: [Int]; var hyper: [Int]; var v, evTotal: Int
    var confirm: Bool                                                  // 놓아줄까? is up: the buttons become 아니오 / 예
    var place = 2                                                      // 0 the companion (nothing to do), 1 the walker's (함께 걷기 / 상자로 보내기), 2 the box's (함께 걷기 / 워커로 / 놓아주기)
    var fetch = false                                                  // the box's: 워커로 is open (the walker has room)
    var evos: [String] = [], evoAction: String? = nil                  // how it evolves (a line a target); the companion's: what evolves it right now
    var sel: Int?                                                      // the LCD's pick (함께 / 놓아주기 / 닫기, or 아니오 / 예): what ● does is red
}
/// 포켓몬 레이더: the four bushes as on the LCD, the one rustling marked.
struct RadarModel: Equatable { var live: Int?; var cursor: Int; var chain: Int; var season = Season.summer }
/// 트레이너 카드: its three pages as tabs.
struct CardModel: Equatable { var page: Int }
/// A new move to learn: it, then the four known ones and 배우지 않는다.
struct LearnModel: Equatable {
    struct Move: Equatable { var name, type: String; var power, pp: Int }
    var who: String; var new: Move; var known: [Move]; var sel: Int
}
/// 배틀 타워's lobby: the run, the party, the button.
struct TowerModel: Equatable {
    struct Member: Equatable { var dex: Int; var name: String; var level: Int }
    var run: Bool; var streak, best, bp, fee: Int; var party: [Member]
}
/// 도구: everything carried — the walker's and the bag's, a row a kind; the picked one's use (nil = nothing to press) and a line about it.
struct ItemsModel: Equatable {
    struct Row: Equatable { var name: String; var count, onWalker: Int }
    var rows: [Row]; var sel: Int; var walker, bag: Int; var action: String?; var hint: String
}
/// Whatever the pane shows; all nil = no page (the card's idle height).
struct PaneContent: Equatable {
    var battle: SideModel?; var dex: DexModel?; var shop: ShopModel?; var menu: MenuModel?; var status: StatusModel?; var grid: GridModel?; var mon: MonModel?
    var radar: RadarModel?; var card: CardModel?; var learn: LearnModel?; var tower: TowerModel?; var items: ItemsModel?
}
extension PaneContent {
    /// The card's height (card points) for a page: the window grows down to it. Pages keep one height while they're up (a fight doesn't jump per turn).
    static let tallest: CGFloat = 472                                                              // 포켓몬's grid: the size menu keeps it on the screen
    var height: CGFloat {
        battle != nil ? 311 : grid?.items != nil ? 472 : grid != nil ? 422 : mon != nil ? 454 : items != nil ? 446 : dex != nil ? 390 : shop != nil ? 406 : menu != nil ? 344
            : radar != nil ? 327 : card != nil ? 230 : learn != nil ? 365 : tower != nil ? 353 : status != nil ? 354 : Layout.idle
    }
}
