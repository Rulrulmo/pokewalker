import Foundation
// The pane's pages as data: what the walker shows under the band (Walker.pane), the card's height for each. Drawn in Core/Page.swift.

// MARK: - models
/// The battle: names, HP, types for the LCD's HP boxes; the message and the choices for the page.
struct SideModel: Equatable {
    struct Card: Equatable { var name: String; var level, hp, max: Int; var out: Bool; var status: String? = nil; var types: [String] = []; var owned = false; var item: String? = nil }   // types / owned: shown for theirs; item: what it holds now (3.7)
    struct MoveBtn: Equatable { var name, type: String; var power: Int; var effect: Double; var pp = 0, maxPP = 0; var status = false; var about = ""; var text: String? = nil }   // about · text: 3.8.2's line under the four
    enum Mode: Equatable { case none, menu([String], Int), moves([MoveBtn], Int), party([Card], Int), items([String], Int), ask(Bool) }   // ask: 아니오 / 예 (true = 예 highlighted)
    var foe: Card; var mine: Card; var message: String; var mode: Mode
}
/// 상점 / BP 교환소: the list, and how many.
struct ShopModel: Equatable {
    struct Row: Equatable { var name, note, price: String; var owned: Int; var can: Bool; var once: Bool }
    var title: String; var rows: [Row]; var sel: Int; var qty: Int?; var most: Int; var total: String
    var hint: String                                                   // the bottom row when nothing is being counted: a message, or why not
    var ask: Bool?                                                     // a once-only row's 정말? (true = 예 highlighted)
    var tabs: [String] = [], tab = 0, ids: [Int] = []                  // 3.6 (docs/plans/13): the tab the pick is on; rows = that tab's (ids: their place in the whole list)
}
/// The status sheet (home's page, and any screen without one of its own): the companion, today, then the rest.
struct StatusModel: Equatable {
    struct Row: Equatable { var key, value: String }
    var dex: Int; var name, sex, level, toNext, nature: String; var female: Bool; var v: Int; var exp: CGFloat; var numbers: [Row]; var rows: [Row]
}
/// 메뉴: the LCD's pages as tiles, the one on the LCD picked.
struct MenuModel: Equatable {
    struct Row: Equatable { var name, note: String; var off = false; var dot = false; var items = "" }   // off: it needs the server, and it isn't there (dimmed); dot: something waits there (3.8's red dot); items: a group's (▸) features
    var rows: [Row]; var sel: Int
    var group: String? = nil                                           // 3.9: a group's page (its name), nil = the first page's 8 tiles
}
/// The 도감 entry (the LCD shows its number, name and types): base stats, where to meet it, how it evolves.
struct DexModel: Equatable {
    var num: Int; var status: Int                                      // 0 not met, 1 seen, 2 caught
    var stats: [Int]; var found: [String]; var evos: [String]          // up to 3 places, 2 evolutions: a line each
}
/// The 도감 / 포켓몬 grid: tabs, a page of box icons (the pick bobbing), the pager; 포켓몬's has the companion and the walker's in a row above.
struct GridModel: Equatable {
    static let perPage = 30, columns = 6                               // 6 x 5
    struct Cell: Equatable { var dex: Int; var look: Int; var shiny = false, v3 = false; var level = 0; var held = false }   // held: it holds an item (3.7)   // look: 0 not met (its number), 1 seen (a shadow), 2 caught / in the box
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
    var held: String? = nil, heldNote: String? = nil                   // 3.7: its 지닌 도구 and what it does (the line under 진화; a click: 지니게 하기)
}
/// 지니게 하기 (docs/plans/13 ⑤): who, what it holds now, the bag's holdable items (빼기 first while it holds one), the pick's line, the button.
struct HoldModel: Equatable {
    struct Row: Equatable { var name: String; var count: Int; var note: String; var take: Bool; var use = false; var why: String? = nil }   // take: the 빼기 row; use (3.8.5): one to use on it (why: what it wouldn't do, dimmed)
    var who: String; var now: String?; var rows: [Row]; var sel: Int; var action: String?; var hint: String
}
/// 포켓몬 레이더: the four bushes as on the LCD, the one rustling marked.
struct RadarModel: Equatable { var live: Int?; var cursor: Int; var chain: Int; var season = Season.summer }
/// 트레이너 카드: its three pages as tabs.
struct CardModel: Equatable { var page: Int }
/// A new move to learn: it, then the four known ones and 배우지 않는다.
struct LearnModel: Equatable {
    struct Move: Equatable { var name, type: String; var power, pp: Int; var about = ""; var text: String? = nil }   // about: 물리 · 명중 100; text: what it does (3.8.2)
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
    var run: Bool; var streak, best, bp, fee: Int; var party: [Member]; var custom = false   // custom = the player's party, not the recommended one (3.8.3: picked on the 포켓몬 menu's grid)
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
    var sellAll: Int? = nil                                            // W for everything sellable at once (nil: nothing to sell)
    var tabs: [String] = [], tab = 0                                   // 3.8.5 (14 §11): the bag's kinds with something in them (rows: the tab's)
}
/// 팀 (docs/plans/12 §2): the tabs, a page of teammates (rank on the rank tabs, the companion, walking now, the tab's number), the pager, a note.
struct TeamModel: Equatable {
    struct Row: Equatable { var rank: Int?; var name: String; var dex: Int; var shiny: Bool; var value: String; var walking: Bool; var me: Bool }
    static let perPage = 6
    var tabs: [String]; var tab: Int; var rows: [Row]; var sel, first, count: Int; var note: String; var week: String
    var hint: String? = nil                                            // under the rows (no friends yet: how to add one)
}
/// A friend's card: the walker's three, a few lines, its buttons (대전 · 맡기기 · 친구 끊기; 친구 신청 on someone else's; none on mine).
struct TeamCardModel: Equatable {
    struct Mini: Equatable { var dex, level: Int; var shiny: Bool }
    struct Line: Equatable { var key, value: String }
    var name: String; var me, walking: Bool; var when: String; var walker: [Mini]; var lines: [Line]
    var remove = false                                                 // 친구 끊기 (a friend's card)
    var duel: String? = nil                                            // 3.6: 대전 신청 (a friend walking now), or why not; nil: none (my own card)
    var visit: String? = nil                                           // 3.8: 맡기기 (a friend walking now, none of mine away), or why not
    var request: String? = nil                                         // 3.8's 전체 tab: 친구 신청 on someone not a friend (or that it's been sent)
}
/// 교환 (12 §3): a Pokémon in an offer as its tile shows it; dex nil = none (name says what goes there instead: 아무거나, 골라 주세요).
struct TradeSlot: Equatable { var label: String; var dex: Int? = nil; var level = 0; var shiny = false; var name: String; var v = 0; var more: [Int] = [] }   // more: the 게시판's wished species after the first
/// 교환's list (팀's 교환 tab): a page of the open offers — to me (whose, for what), then mine (to whom) — the pager, a note.
struct TradeListModel: Equatable {
    struct Row: Equatable { var mine: Bool; var line: String; var sub: String; var dex: Int; var shiny: Bool }
    static let perPage = 6
    var tabs: [String]; var rows: [Row]; var sel, first, count: Int; var note: String
}
/// One offer: what I'd give and get, the one I'd get in full (its page's body), the buttons (수락 · 거절, or 거두기; sel = the LCD's pick).
struct TradeOfferModel: Equatable { var title, note: String; var give, get: TradeSlot; var mon: MonModel; var buttons: [String]; var sel: Int? }
/// Making an offer, or answering a 아무거나 one: the two slots (the side being picked from ringed), its box a page at a time, 아무거나
/// (their side, while making one), the button (nil: not yet — hint says why).
struct TradePickModel: Equatable {
    static let perPage = 24, columns = 6                               // 6 x 4
    var title, note: String; var mine, theirs: TradeSlot; var side: Int; var fixed: Bool   // fixed: theirs is set (answering)
    var boxTitle: String; var cells: [GridModel.Cell]; var sel, picked: Int?; var first, count: Int; var empty: String
    var any: Bool?; var go: String?; var hint: String; var bob: Bool
    var marks: [Int] = []                                              // cells marked too (the 게시판's wished species)
    var base = 6100                                                    // its click codes: 교환's 6100s, the 게시판's 8100s
}
/// 친구's 신청 tab (12 §2.4): requests to me (수락 · 거절), mine out (거두기), a page at a time; 친구 신청 by ID.
struct FriendReqModel: Equatable {
    struct Row: Equatable { var name: String; var mine: Bool }
    static let perPage = 5                                                                         // (five clear the pager with two rows of tabs)
    var tabs: [String]; var rows: [Row]; var first, count: Int; var note: String; var friends: Int
}
/// The 교환 게시판 (12 §3.3): 전체 · 내 글 · 내 제안, a page of rows (its Pokémon, a line, a subline, a pill), 글 올리기.
struct MarketBoardModel: Equatable {
    struct Row: Equatable { var dex: Int; var shiny: Bool; var line, sub: String; var pill: String?; var tint: Int }   // tint: 0 grey, 1 green (offers for me), 2 blue (mine)
    static let perPage = 6
    var tabs: [String]; var tab: Int; var rows: [Row]; var sel, first, count: Int; var note: String; var empty: String; var post: String?   // post: 글 올리기 (nil: 3 up)
    var footer: String? = nil                                          // the button's place when there's none to press (받기: how it works)
}
/// One post in full: its Pokémon and the species wished for; another's: the Pokémon's page body and 제안 (or my offer, 거두기);
/// mine: the offers on it (the picked one ringed) and 이 제안으로 교환 · 글 내리기.
struct MarketPostModel: Equatable {
    struct Offer: Equatable { var dex: Int; var shiny: Bool; var line, sub: String }
    var title, note: String; var mon, wish: TradeSlot; var body: MonModel?; var offers: [Offer]; var sel: Int?; var buttons: [String]; var strong: Int?
}
/// 3.8 (docs/plans/14 §3): 맡겨 키우기 — mine away (데려오기), the ones I'm raising (돌려보내기), how it works.
struct VisitsModel: Equatable {
    struct Row: Equatable { var dex: Int; var shiny: Bool; var line, sub: String; var button: String; var mine: Bool }
    var tabs: [String]; var tab: Int; var rows: [Row]; var note: String; var hint: String
    var first = 0, sel = 0                                             // 3.8.5: a window of five (rows: all; one a friend can be many), the pick
    static let shown = 5
}
/// 3.8 (14 §4–5): picking several in order — the strip (who goes, in order; a click drops one), a duel's other six (species only), ours
/// (a page of 6 × 4, each picked one numbered), the button (nil: the hint; goSel: the cursor's on it).
struct SquadModel: Equatable {
    struct Slot: Equatable { var dex: Int; var shiny: Bool; var level: String }
    static let perPage = 24                                                                        // 6 × 4, as the 포켓몬 menu's cells (3.8.3)
    var title, note: String; var strip: [Slot?]; var theirs: [GridModel.Cell]?
    var tabs: [String]?; var tab: Int                                                              // the 포켓몬 menu's sort (none: a duel's six)
    var boxTitle: String; var cells: [GridModel.Cell]; var order: [Int?]; var sel: Int?; var first, count: Int
    var empty: String; var go: String?; var goSel: Bool; var hint: String
    var off = ""                                                       // the button's words when there's nothing to press (none: the hint)
}
/// 3.8's 대전 menu (14 §5): 대전 (the registered six, friends walking now to challenge, 랜덤 매칭) · 전적 (the last 20, a page at a time).
struct DuelHubModel: Equatable {
    struct Row: Equatable { var name, sub: String; var pill: String? }
    struct Rec: Equatable { var won: Bool; var line, sub: String; var mine, theirs: [Int] }
    static let perPage = 5
    var tabs: [String]; var tab: Int; var note: String
    var party: [SquadModel.Slot?]; var partyNote: String; var friends: [Row]; var recs: [Rec]; var first, count: Int
    var sel: Int; var go: String?; var hint: String; var empty: String
}
/// 실시간 대전's invitation (12 §5): who, the rules in a line, the time left, its buttons (수락 · 거절, or 신청 취소).
struct DuelModel: Equatable { var title, line, note: String; var buttons: [String]; var record: String }
/// 레이드 (12 §4): this week's boss, the team's HP, my power (3 칸), a tab of rows (기여 순위: rank, name, damage and share; 최근 공격: the
/// fight's lead, name, damage, when), the button (도전 / 볼 던지기; nil: not now — hint says why).
struct RaidModel: Equatable {
    struct Row: Equatable { var rank: Int?; var dex: Int?; var name, value: String; var me: Bool }
    var boss: String; var left: String; var hp: CGFloat; var hpText: String; var cleared: Bool
    var power: Int; var powerText: String
    var tabs: [String]; var tab: Int; var rows: [Row]; var empty: String
    var go: String?; var hint: String
}
/// The save server holding the game: what's up, a line or two, and the one button (ID 입력 / 여기서 계속; nil = none).
struct LoginModel: Equatable { var title: String; var lines: [String]; var button: String? }
/// Whatever the pane shows; all nil = no page (the card's idle height).
struct PaneContent: Equatable {
    var login: LoginModel? = nil
    var battle: SideModel?; var dex: DexModel?; var shop: ShopModel?; var menu: MenuModel?; var status: StatusModel?; var grid: GridModel?; var mon: MonModel?
    var radar: RadarModel?; var card: CardModel?; var learn: LearnModel?; var tower: TowerModel?; var items: ItemsModel?; var course: CourseModel?; var train: TrainModel?; var relearn: RelearnModel?
    var team: TeamModel? = nil, teamCard: TeamCardModel? = nil
    var trades: TradeListModel? = nil, offer: TradeOfferModel? = nil, pick: TradePickModel? = nil
    var raid: RaidModel? = nil
    var friendReqs: FriendReqModel? = nil, board: MarketBoardModel? = nil, post: MarketPostModel? = nil
    var duel: DuelModel? = nil, hold: HoldModel? = nil, visits: VisitsModel? = nil
    var squad: SquadModel? = nil, duelHub: DuelHubModel? = nil
}
extension PaneContent {
    /// The card's height (card points) for a page: the window grows down to it. Pages keep one height while they're up (a fight doesn't jump per turn).
    static let tallest: CGFloat = 484                                                              // a Pokémon's page: the size menu keeps it on the screen
    static let home: CGFloat = 406                                                                 // 홈's status sheet and the 메뉴 alike: the 메뉴 / 홈 key never resizes the card (3.5.1: 11 tiles at a comfortable size)
    var height: CGFloat {
        login != nil ? 330 : battle != nil ? 316 : grid?.items != nil ? 472 : grid != nil ? 422 : mon != nil ? 484 : items != nil ? 472 : dex != nil ? 390 : shop != nil ? (shop!.tabs.count > 6 ? 458 : 434) : menu != nil ? PaneContent.home
            : team != nil ? (team!.tabs.count > 5 ? 470 : 446) : teamCard != nil ? 420 : trades != nil ? 446 : offer != nil ? 482 : pick != nil ? 480 : raid != nil ? 464 : friendReqs != nil ? (friendReqs!.tabs.count > 5 ? 470 : 446) : board != nil ? 474 : post != nil ? 482 : duel != nil ? 330 : hold != nil ? 446 : visits != nil ? 470 : squad != nil ? 480 : duelHub != nil ? 446
            : radar != nil ? 327 : card != nil ? 230 : learn != nil ? 444 : tower != nil ? 353 : course != nil ? 392 : train != nil ? 392 : relearn != nil ? 408 : status != nil ? PaneContent.home : Layout.idle
    }
}
