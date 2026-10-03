import Foundation
// The pane's pages as data: what the walker shows under the band (Walker.pane), the card's height for each. Drawn in Core/Page.swift.

// MARK: - models
/// The battle: names, HP, types for the LCD's HP boxes; the message and the choices for the page.
struct SideModel: Equatable {
    struct Card: Equatable { var name: String; var level, hp, max: Int; var out: Bool; var status: String? = nil; var types: [String] = []; var owned = false }   // types / owned: shown for theirs
    struct MoveBtn: Equatable { var name, type: String; var power: Int; var effect: Double; var pp = 0, maxPP = 0; var status = false }
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
/// The status sheet (home's page, and any screen without one of its own): the companion, today, then the rest.
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
    var dupes = 0                                                      // the box's: how many of its species 중복 놓아주기 would let go (the 놓아줄까? row offers it)
    var moves: [String] = []                                           // its four moves
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
/// 기술 바꾸기: its moves (the slots; a free one after them while it knows fewer than 4), the one picked, and once picked what could go there, a page of five.
struct RelearnModel: Equatable {
    struct Row: Equatable { var move: LearnModel.Move; var level: Int?; var slot: Int? }   // level = when it learns it (nil: not by level); slot = where it is now
    struct Pick: Equatable { var sel, count, first: Int; var rows: [Row] }
    static let perPage = 5
    var who: String; var slots: [LearnModel.Move]; var slot: Int; var pick: Pick?
}
/// 배틀 타워's lobby: the run, the party, the button.
struct TowerModel: Equatable {
    struct Member: Equatable { var dex: Int; var name: String; var level: Int; var shiny = false }
    /// Picking who goes in party slot `slot`: count candidates, `rows` the page in view from `first` (slot = where that one is in the party now).
    struct Pick: Equatable {
        struct Row: Equatable { var name: String; var level: Int; var slot: Int?; var shiny = false }
        var slot, sel, count, first: Int; var rows: [Row]
    }
    static let perPage = 5
    var run: Bool; var streak, best, bp, fee: Int; var party: [Member]; var custom = false; var pick: Pick? = nil   // custom = the player's party, not the recommended one
}
/// 코스: every course, a page of five (the pick's picture is on the LCD). note = what opens a locked one; go = the button (nil: locked, or walking it now).
struct CourseModel: Equatable {
    struct Row: Equatable { var name, note: String; var open, here: Bool }
    static let perPage = 5
    var rows: [Row]; var sel, first, count, opened: Int; var go: String?; var about = ""   // about = the pick: its levels and types
}
/// 대단한 특훈 with 은색병뚜껑: the companion's six IVs (hyper = already trained), the pick and its button (nil: nothing to raise / too low a level).
struct TrainModel: Equatable {
    struct Row: Equatable { var name: String; var iv: Int; var hyper: Bool }
    var who: String; var caps: Int; var rows: [Row]; var sel: Int; var go: String?; var note: String; var v = 0   // v = its 31s now
}
/// 도구: everything carried — the walker's and the bag's, a row a kind; the picked one's use (nil = nothing to press) and a line about it.
struct ItemsModel: Equatable {
    struct Row: Equatable { var name: String; var count, onWalker: Int }
    var rows: [Row]; var sel: Int; var walker, bag: Int; var action: String?; var hint: String
}
/// The save server holding the game: what's up, a line or two, and the one button (ID 입력 / 여기서 계속; nil = none).
struct LoginModel: Equatable { var title: String; var lines: [String]; var button: String? }
/// Whatever the pane shows; all nil = no page (the card's idle height).
struct PaneContent: Equatable {
    var login: LoginModel? = nil
    var battle: SideModel?; var dex: DexModel?; var shop: ShopModel?; var menu: MenuModel?; var status: StatusModel?; var grid: GridModel?; var mon: MonModel?
    var radar: RadarModel?; var card: CardModel?; var learn: LearnModel?; var tower: TowerModel?; var items: ItemsModel?; var course: CourseModel?; var train: TrainModel?; var relearn: RelearnModel?
}
extension PaneContent {
    /// The card's height (card points) for a page: the window grows down to it. Pages keep one height while they're up (a fight doesn't jump per turn).
    static let tallest: CGFloat = 484                                                              // a Pokémon's page: the size menu keeps it on the screen
    var height: CGFloat {
        login != nil ? 300 : battle != nil ? 311 : grid?.items != nil ? 472 : grid != nil ? 422 : mon != nil ? 484 : items != nil ? 446 : dex != nil ? 390 : shop != nil ? 406 : menu != nil ? 354
            : radar != nil ? 327 : card != nil ? 230 : learn != nil ? 365 : tower != nil ? 353 : course != nil ? 392 : train != nil ? 392 : relearn != nil ? 353 : status != nil ? 354 : Layout.idle
    }
}
