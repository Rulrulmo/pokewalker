import Foundation
// Which screen the LCD is on.

// MARK: - screens
let menuItems = ["포켓 레이더", "커넥트", "트레이너 카드", "포켓몬", "도감", "상점", "BP 교환소", "배틀 타워"]
/// A tile's place on the menu, by its name (the code never counts tiles).
func menuAt(_ name: String) -> Int { menuItems.firstIndex(of: name)! }
indirect enum Screen {
    case home
    case menu(Int)
    case radar(bush: Int, cursor: Int, since: Date, chain: Int)        // "!" shows on `bush` from 1.5 s after `since`, for `radarWindow(chain)`
    case battle(Battle, sel: Int)                                      // sel = the menu row (공격 / 볼 / 도구 / 도망, or 공격 / 도구 / 교체 / 기권)
    case moves(Battle, sel: Int)                                       // picking one of the 4 moves
    case party(Battle, sel: Int)                                       // picking who to switch in
    case bagBattle(Battle, sel: Int)                                   // picking an item to use
    case forfeit(Battle, yes: Bool)                                    // 기권할까? in a tower fight — yes = the highlighted answer, 아니오 first
    case shop(bp: Bool, sel: Int, qty: Int?)                         // 상점 (W) or BP 교환소: the list, or (qty) how many of row sel
    case shopConfirm(bp: Bool, sel: Int, yes: Bool)                    // a once-only row (전설, 기기 색): 정말? — yes = the highlighted answer, 아니오 first
    case learn(sel: Int)                                               // a new move for state.learn's first: forget one of 4 (sel 0-3), or not learn it (4)
    case tower                                                         // the Battle Tower lobby
    case beats(Battle, [Beat], since: Date, from: Battle)              // one exchange playing out; `from` = HP before it
    case card(Int), items(Int)                                         // 도구: everything carried (the walker's + the bag), the picked row (from 포켓몬's last chip)
    case say([String], next: Screen, since: Date)                      // any button or 3 s
    case evolve(from: Mon, to: Mon, since: Date)                       // already applied to the state; this is the show
    case dex(Int, filter: Int, detail: Bool)                           // the pick's dex number; filter = the grid's tab (전체 / 잡음 / 못 잡음 / 이 코스); detail = the entry page
    case box(Int, act: Int?, confirm: Bool, detail: Bool = false)      // 포켓몬: a ref (-1 the companion, -2-i caught[i], i box[i]; the grid shows boxOrder); act = the ● menu's selection; confirm = "release?"; detail = its page
    case hatch(Mon, since: Date)                                       // already kept; this is the show
}
