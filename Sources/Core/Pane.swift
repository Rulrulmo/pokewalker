import Foundation
// The pane's pages as data: what the walker shows under the band (Walker.pane), the card's height for each. Drawn in Core/Page.swift.

// MARK: - models
/// The battle: names, HP, types for the LCD's HP boxes; the message and the choices for the page.
struct SideModel: Equatable {
    struct Card: Equatable { var name: String; var level, hp, max: Int; var out: Bool; var status: String? = nil; var types: [String] = []; var owned = false; var item: String? = nil; var exp: CGFloat? = nil }   // exp (5.0): ours' way to its next level (0…1)   // types / owned: shown for theirs; item: what it holds now (3.7)
    struct MoveBtn: Equatable { var name, type: String; var power: Int; var effect: Double; var pp = 0, maxPP = 0; var status = false; var about = ""; var text: String? = nil }   // about · text: 3.8.2's line under the four
    enum Mode: Equatable { case none, menu([String], Int), moves([MoveBtn], Int), party([Card], Int), items([String], Int), ask(Bool) }   // ask: 아니오 / 예 (true = 예 highlighted)
    var foe: Card; var mine: Card; var message: String; var mode: Mode
    /// 4.0 (16 §8-3): a raid's bars by the menu's prompt — broken, of all, and how much of the one up is left (0...1).
    struct Bars: Equatable { var broken, total: Int; var cur: CGFloat }
    var bars: Bars? = nil
    var turnsLeft: Int? = nil                                          // 5.2 (plan 19 §11.3): a roamer's turns before it runs off (of Expeditions.roamTurns)
    var mega: Bool? = nil                                              // 5.0: the move screen's 메가진화 (nil: it can't now), ticked or not
    var megaTicked = false                                             // 5.1: 메가진화 ticked (any battle screen till the turn's answer: the HP box's tab)
    var megaOff = false                                                // 5.1.4: a duel without it (the other's app before 5.1.4) — ours could: 메가진화 · 이번엔 없음, greyed
}
/// 상점 / BP 교환소: the list, and how many.
struct ShopModel: Equatable {
    struct Row: Equatable { var name, note, price: String; var owned: Int; var can: Bool; var once: Bool
                            var type: String? = nil, team: [Int] = [], teamOK: [Bool] = [] }   // 5.2: a machine's move type; the team's four, who learns it
    var title: String; var rows: [Row]; var sel: Int; var qty: Int?; var most: Int; var total: String
    var hint: String                                                   // the bottom row when nothing is being counted: a message, or why not
    var ask: Bool?                                                     // a once-only row's 정말? (true = 예 highlighted)
    var tabs: [String] = [], tab = 0, ids: [Int] = []                  // 3.6 (docs/plans/13): the tab the pick is on; rows = that tab's (ids: their place in the whole list)
    var tmSort: Int? = nil, tmTeam = false                             // 5.2: on the 기술머신 tab — its sort (Walker.tmSorts), 우리 팀만
}
/// The status sheet (home's page, and any screen without one of its own): the companion, today, then the rest.
struct StatusModel: Equatable {
    struct Row: Equatable { var key, value: String; var bar: Double? = nil }   // bar (5.1): 전설 원정's, between the key and the words
    var art: Int; var name, sex, level, toNext, nature: String; var female: Bool; var v: Int; var exp: CGFloat; var numbers: [Row]; var rows: [Row]
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
    var form: String? = nil, formAt = ""                               // 5.0: the form on show (nil = none to show) and where it is in them (2/3: 1 the species)
}
/// The 도감 / 포켓몬 grid: tabs, a page of box icons (the pick bobbing), the pager; 포켓몬's has the companion and the walker's in a row above.
struct GridModel: Equatable {
    static let perPage = 30, columns = 6                               // 6 x 5
    struct Cell: Equatable { var dex: Int; var look: Int; var shiny = false, v3 = false; var level = 0; var held = false; var art: Int? = nil; var heldItem: String? = nil; var evo = false; var fav = false; var pic: Int { art ?? dex } }   // fav (5.2.2, docs/plans/25): 즐겨찾기, its ♥   // heldItem (5.0): its picture on the cell   // held: it holds an item (3.7)   // look: 0 not met (its number), 1 seen (a shadow), 2 caught / in the box   // art (5.0): a form's picture (Mon.art)
    var tabs: [String]; var tab: Int
    var cells: [Cell]; var first: Int; var sel: Int?                   // this page's cells; first = cells[0]'s place in the whole list; sel = the pick's cell
    var page, pages: Int; var empty: String; var bob: Bool
    var query: String? = nil                                           // 5.0: the 상자's 찾기 words ("" none; nil: the 도감's 찾기)
    var party: [Cell] = []; var partySel: Int? = nil; var items: Int? = nil   // 포켓몬: the companion + the walker's in a row over the box, then the items chip (nil = no row: 도감)
    var regions: [String]? = nil; var region = 0                       // 5.0 도감 (content5): 전국 · 관동 ... 칼로스 under the tabs (nil = no row)
}
/// One Pokémon of the box, in full: nature and ability with what they do, IVs and EVs as hexagons.
struct MonModel: Equatable {
    var nature, natureNote, ability, abilityNote: String; var up, down: Int?   // stat indices the nature raises / lowers (nil = neutral)
    var ivs, evs: [Int]; var hyper: [Int]; var v, evTotal: Int
    var fav: Bool? = nil                                               // 5.2.2 (docs/plans/25): 즐겨찾기 on / off — the ♡ / ♥ first in the buttons; nil: none (a fight on)
    var confirm: Bool                                                  // 놓아줄까? is up: the buttons become 아니오 / 예
    var form: String? = nil                                            // 5.0: its own form (히트로토무, 어택폼 ...), a chip on the 특성 line
    var place = 2                                                      // 0 the companion (nothing to do), 1 the walker's (함께 걷기 / 상자로 보내기), 2 the box's (함께 걷기 / 워커로 / 놓아주기)
    var fetch = false                                                  // the box's: 워커로 is open (the walker has room)
    var dupes = 0                                                      // the box's: how many of its species 중복 놓아주기 would let go (the 놓아줄까? row offers it)
    var moves: [String] = []                                           // its four moves
    var evos: [String] = [], evoAction: String? = nil                  // how it evolves (a line a target); the companion's: what evolves it right now
    var sel: Int?                                                      // the LCD's pick (함께 / 놓아주기 / 닫기, or 아니오 / 예): what ● does is red
    var held: String? = nil, heldNote: String? = nil                   // 3.7: its 지닌 도구 and what it does (the line under 진화; a click: 지니게 하기)
    var formAction: String? = nil                                      // 5.0: 모습 바꾸기 · 합체하기 · 분리하기 (its key item in the bag): a link on the 진화 line
    var evoPick: String? = nil                                         // 5.1.3: 진화 고르기 (배루키 ready to pick): the same link
    var megaLink = false, mega: MegaLookModel? = nil                   // 5.2 (MegaLook.swift): 메가 모습 보기 on the 진화 line; the page as its Mega
}
/// 지니게 하기 (docs/plans/13 ⑤): who, what it holds now, the bag's holdable items (빼기 first while it holds one), the pick's line, the button.
struct HoldModel: Equatable {
    struct Row: Equatable { var name: String; var count: Int; var note: String; var take: Bool; var use = false; var why: String? = nil; var dex: Int? = nil; var form: Int? = nil }   // 5.0: dex = a Pokémon's row (FormView: its icon, no count)   // take: the 빼기 row; use (3.8.5): one to use on it (why: what it wouldn't do, dimmed)
    var who: String; var now: String?; var rows: [Row]; var sel: Int; var action: String?; var hint: String
    var picks = false                                                  // 5.0: FormView's — "지금" is a form, not a held item
}
/// 3.9's 우편함 (15 §6 A): a page of mails (the server's order: gifts to take first), 모두 받기.
struct MailListModel: Equatable {
    static let perPage = 6
    enum Icon: Equatable { case gift, letter, gem, medal(gold: Bool), mon(dex: Int, shiny: Bool), item(String) }   // item (5.0): its own picture
    struct Row: Equatable { var icon: Icon; var title, sub: String; var chips: [String]; var unread, done: Bool }   // unread: not opened, or a gift left (its dot); done: taken (dimmed)
    var rows: [Row]; var sel: Int?; var first, count: Int; var note: String; var all: String?; var empty: String
    var delAll: String? = nil                                          // 5.1 (the user: "우편 삭제 기능도"): 받은 n통 지우기
}
/// One mail: its words, its gifts, 받기 (or 고르기).
struct MailOpenModel: Equatable {
    struct Gift: Equatable { var icon: MailListModel.Icon; var name, note: String }
    var title, from, body: String; var gifts: [Gift]; var button: String?; var off: String
    var del: Bool? = nil; var delWhy: String? = nil                   // 5.1: 지우기 (false: dimmed — a gift left, why above it)
}
/// A pick (15 §6 D): the held items as rows, or the legends as the 포켓몬 menu's cells; the button, or 받을까요? 아니오 / 예.
struct MailPickModel: Equatable {
    static let perPage = 24
    /// A page's rows: the legends' 24 cells; items up to 7 rows, more in pages of 6 (their pager under them, clear of the button) — 5.0 (the user:
    /// 민트 21개가 스크롤도 안 되고 버튼과 겹쳐요).
    static func per(_ count: Int, legend: Bool) -> Int { legend ? perPage : count > 7 ? 6 : 7 }
    struct Row: Equatable { var name, note: String }
    var title, note: String; var rows: [Row]; var cells: [GridModel.Cell]; var sel: Int; var first, count: Int; var go: String?; var ask: Bool?
}
/// 5.1.3 (docs/plans/23): 배루키's pick — a card each (its picture, type, ability, 공격 · 방어), the pick's stats and ability below, the button or
/// 진화할까요? 아니오 / 예.
struct EvoPickModel: Equatable {
    struct Card: Equatable { var dex: Int; var name: String; var types: [String]; var ability: String; var hidden: Bool; var atk, def: Int }
    var who: String; var cards: [Card]; var sel: Int; var stats: [Int]; var abilityNote: String; var shiny: Bool; var ask: Bool?
}
/// 포켓몬 레이더: the four bushes as on the LCD, the one rustling marked.
struct RadarModel: Equatable { var live: Int?; var cursor: Int; var chain: Int; var season = Season.summer }
/// 트레이너 카드: its three pages as tabs; 3.9: the 칭호 and 장식 over them (15 §6 C).
/// 5.0 (content5): 도감 업적 — a row each (전국, the regions, 해금): its count of what it asks, its half mark, a line, the steps paid (전국), 이로치.
struct GoalsModel: Equatable {
    struct Row: Equatable { var name: String; var have, of: Int; var half: Int?; var note: String; var marks: Int?; var of2: Int?; var shiny: String?; var done: Bool }
    var rows: [Row]; var sel: Int; var paid: Int; var hint: String
}
struct CardModel: Equatable {
    var page: Int; var title: String? = nil; var deco: String? = nil; var stones: String? = nil   // stones (5.0): 메가스톤 n/48
    var titles: [String] = [], picked: String? = nil, picking = false                            // 5.0: two or more 칭호 (newest first), the one picked (nil: the newest), the list open
}
/// A new move to learn: it, then the four known ones and 배우지 않는다.
struct LearnModel: Equatable {
    struct Move: Equatable { var name, type: String; var power, pp: Int; var about = ""; var text: String? = nil }   // about: 물리 · 명중 100; text: what it does (3.8.2)
    var who: String; var new: Move; var known: [Move]; var sel: Int
}
/// 기술 바꾸기: its moves (the slots; a free one after them while it knows fewer than 4), the one picked, and once picked what could go there, a page of five.
struct RelearnModel: Equatable {
    struct Row: Equatable { var move: LearnModel.Move; var level: Int?; var slot: Int?; var tag: String? = nil }   // level = when it learns it (nil: not by level); slot = where it is now; tag (5.2): TM26 · 원정
    struct Pick: Equatable { var sel, count, first: Int; var rows: [Row] }
    static let perPage = 5
    var who: String; var slots: [LearnModel.Move]; var slot: Int; var pick: Pick?
    var hint: String? = nil                                            // 5.2: the slots' line (machines too; a machine to teach: its move)
}
/// 배틀 타워's lobby: the run, the party, the button.
struct TowerModel: Equatable {
    struct Member: Equatable { var dex: Int; var name: String; var level: Int; var shiny = false; var art: Int? = nil }
    var run: Bool; var streak, best, bp, fee: Int; var party: [Member]; var custom = false   // custom = the player's party, not the recommended one (3.8.3: picked on the 포켓몬 menu's grid)
    struct Reward: Equatable { var wins: Int; var short: String; var got: Bool; var more = false }   // 3.9 (15 §6 E): the streak rewards — got = mailed (Walk.towerRewards); more: 4.1's every 50 from 150 (its next one)
    var rewards: [Reward] = []; var next = ""; var tycoon: String? = nil                       // next: the next reward in words; tycoon: 은 / 금 when the next fight is the tycoon's
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
    /// 5.2 (TMView.swift): a machine had — its number, move and type, the team's four and who of them learns it.
    struct Machine: Equatable { var label, move, type: String; var team: [Int]; var teamOK: [Bool] }
    struct Row: Equatable { var name: String; var count, onWalker: Int; var tm: Machine? = nil }
    var rows: [Row]; var sel: Int; var walker, bag: Int; var action: String?; var hint: String
    var sellAll: Int? = nil                                            // W for everything sellable at once (nil: nothing to sell)
    var tabs: [String] = [], tab = 0                                   // 3.8.5 (14 §11): the bag's kinds with something in them (rows: the tab's)
}
/// 팀 (docs/plans/12 §2): the tabs, a page of teammates (rank on the rank tabs, the companion, walking now, the tab's number), the pager, a note.
struct TeamModel: Equatable {
    struct Row: Equatable { var rank: Int?; var name: String; var dex: Int; var shiny: Bool; var value: String; var walking: Bool; var me: Bool; var deco: String? = nil; var title: String? = nil }   // 3.9: the medal, the 칭호
    static let perPage = 6
    var tabs: [String]; var tab: Int; var rows: [Row]; var sel, first, count: Int; var note: String; var week: String
    var hint: String? = nil                                            // under the rows (no friends yet: how to add one)
    var scope: Int? = nil                                              // 5.1 (랭킹): 친구 0 / 전체 1, its switch at the top right (nil: no 전체)
}
/// A friend's card: the walker's three, a few lines, its buttons (대전 · 맡기기 · 친구 끊기; 친구 신청 on someone else's; none on mine).
struct TeamCardModel: Equatable {
    struct Mini: Equatable { var dex, level: Int; var shiny: Bool }
    struct Line: Equatable { var key, value: String; var gold = false }
    var name: String; var me, walking: Bool; var when: String; var walker: [Mini]; var lines: [Line]
    var deco: String? = nil                                            // 3.9 (15 §6 C): the medal by the name (a 칭호 is a gold line)
    var remove = false                                                 // 친구 끊기 (a friend's card)
    var duel: String? = nil                                            // 3.6: 대전 신청 (a friend walking now), or why not; nil: none (my own card)
    var visit: String? = nil                                           // 3.8: 맡기기 (a friend walking now, none of mine away), or why not
    var request: String? = nil                                         // 3.8's 전체 tab: 친구 신청 on someone not a friend (or that it's been sent)
}
extension TeamCardModel {
    /// 5.1.4 (the user's 5.1.3 shot, "트레이너 카드 글자 잘리고"): nine lines (a 칭호, 레이드, 메가스톤, 맡김 or 코스) ran under the buttons at 380.
    /// The lines from 272, a step by how many; the buttons at 400 always, under the ninth (the page 440: no jump from one card to the next).
    static let linesTop: CGFloat = 272, buttonsTop: CGFloat = 400, height: CGFloat = 440
    var step: CGFloat { lines.count > 7 ? 14 : lines.count > 6 ? 15 : 17 }
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
    var find: String? = nil, newOnly: Bool? = nil                      // 5.2 (Find52.swift): 찾기 ("" none yet; its words), 안 잡은 종 (nil: not on this side)
    var colour = false, dots: [Int] = []                               // 5.2: the species seen in colour; the cells dotted green (not caught yet)
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
    var chips: [String] = [], filter: Int? = nil, found = false        // 5.2 (Find52.swift): 전체's 찾기 and three filters, the one on; 찾기's words in use
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
    struct Slot: Equatable { var dex: Int; var shiny: Bool; var level: String; var art: Int? = nil }
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
/// 레이드 (4.0, 16 §8-1): this week's species, today's runs (of 3) and my power (3 칸), my week (판 · 승 · 잡음 · 이로치), a tab of rows
/// (친구 이번 주: rank, companion, name, the week; 내 판: the boss, tier and bars, when, 잡음 / 놓침), the button (도전, or back to a ball stage;
/// nil: not now — hint says why).
struct RaidModel: Equatable {
    struct Row: Equatable { var rank: Int?; var dex: Int; var shiny: Bool; var name, value: String; var pill: String?; var me: Bool; var art: Int? = nil }   // art (5.0): a Mega boss's icon
    var boss: String; var left: String
    var todayUsed, todayMax: Int; var todayText: String
    var power: Int; var powerText: String
    var week: [String]
    var tabs: [String]; var tab: Int; var rows: [Row]; var empty: String
    var go: String?; var hint: String
    var tomorrow: String? = nil; var cells = 3; var late = false      // 5.1 (plan 20): by the day — tomorrow's boss, the day's cells, midnight near (its line in red)
    var ranks = true                                                   // 5.0: false = the Mega raid's (its tabs are bosses: no rank column)
    var roomy = false                                                  // 5.0: bigger rows (the Mega raid's runs, three)
    var rule: String? = nil                                            // 5.0: how it goes, a line over the button (the Mega raid's stones)
}
/// The tier to fight at (16 §8-5): a row a tier (★, the boss's level, its 31s, the BP a win pays), the pick, the button.
struct RaidTierModel: Equatable {
    struct Row: Equatable { var tier, level, perfect, bp: Int; var first: String? = nil; var firstGot = false }   // first (5.0): the item a Mega boss's first win at this tier pays (got: paid)
    var boss: String; var note: String; var rows: [Row]; var sel: Int; var note2: String; var go: String
}
/// A run's ball stage (16 §8-4): its bars, the boss (its shiny, what it'd be), the balls (thrown dark; a lost run's +2 as ghosts), the buttons.
struct RaidBallsModel: Equatable {
    var bars, total: Int; var dex: Int; var shiny: Bool; var name, note: String
    var balls, of: Int; var won: Bool; var foot: [String]
    var exp = false                                                    // 5.2 (plan 19 §11.3): an expedition boss's — its 3 bars, 5 balls of 30 %, 나중에 던지기 (the balls are kept)
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
    var raidTier: RaidTierModel? = nil, raidBalls: RaidBallsModel? = nil
    var goals: GoalsModel? = nil                                       // 5.0: 도감 업적
    var exp: ExpModel? = nil                                           // 5.1: 전설 원정
    var friendReqs: FriendReqModel? = nil, board: MarketBoardModel? = nil, post: MarketPostModel? = nil
    var duel: DuelModel? = nil, hold: HoldModel? = nil, visits: VisitsModel? = nil
    var squad: SquadModel? = nil, duelHub: DuelHubModel? = nil
    var mailList: MailListModel? = nil, mailOpen: MailOpenModel? = nil, mailPick: MailPickModel? = nil
    var evoPick: EvoPickModel? = nil                                   // 5.1.3: 배루키's pick
}
extension PaneContent {
    /// The card's height (card points) for a page: the window grows down to it. Pages keep one height while they're up (a fight doesn't jump per turn).
    static let tallest: CGFloat = 484                                                              // a Pokémon's page: the size menu keeps it on the screen
    static var home: CGFloat { Content.v51 ? 468 : 446 }   // (5.1: 홈's sixth row, 전설 원정 — the user: "그냥 한줄 늘리는게 낫지 않아?")                                                                 // 홈's status sheet and the 메뉴 alike: the 메뉴 / 홈 key never resizes the card (3.5.1: 11 tiles at a comfortable size; 5.0: 홈's quick buttons)
    var height: CGFloat {
        login != nil ? 330 : battle != nil ? 316 : grid?.items != nil ? 508 : grid?.regions != nil ? 448 : grid != nil ? 422 : mon != nil ? 484 : items != nil ? 472 : dex != nil ? (dex!.form != nil ? 420 : 390) : shop != nil ? (shop!.tabs.count > 6 ? 458 : 434) : menu != nil ? PaneContent.home
            : team != nil ? (team!.tabs.count > 5 ? 470 : 446) : teamCard != nil ? TeamCardModel.height : trades != nil ? 446 : offer != nil ? 482 : pick != nil ? 480 : raid != nil || raidTier != nil || raidBalls != nil ? 464 : friendReqs != nil ? (friendReqs!.tabs.count > 5 ? 470 : 446) : board != nil ? 474 : post != nil ? 482 : duel != nil ? 330 : hold != nil ? 446 : visits != nil ? 470 : squad != nil ? 480 : duelHub != nil ? 446 : mailList != nil || mailOpen != nil || mailPick != nil ? 466
            : evoPick != nil ? 466 : radar != nil ? 327 : goals != nil || exp != nil ? 466 : card != nil ? (card!.picking ? 270 + 30 * CGFloat(card!.titles.count + 1) : card!.title != nil || card!.deco != nil || card!.stones != nil ? 254 : 230) : learn != nil ? 444 : tower != nil ? 400 : course != nil ? 392 : train != nil ? 392 : relearn != nil ? 408 : status != nil ? PaneContent.home : Layout.idle
    }
}
