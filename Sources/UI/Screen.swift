import Foundation
// Which screen the LCD is on.

// MARK: - screens
let menuItems = ["포켓 레이더", "다우징", "커넥트", "트레이너 카드", "포켓몬 · 도구", "상자", "도감", "배틀 타워"]
indirect enum Screen {
    case home
    case menu(Int)
    case radar(bush: Int, cursor: Int, since: Date, chain: Int)        // "!" shows on `bush` from 1.5 s after `since`, for `radarWindow(chain)`
    case battle(Battle, sel: Int)                                      // sel = the menu row (공격 / 볼 / 도구 / 도망, or 공격 / 도구 / 교체 / 기권)
    case moves(Battle, sel: Int)                                       // picking one of the 4 moves
    case party(Battle, sel: Int)                                       // picking who to switch in
    case bagBattle(Battle, sel: Int)                                   // picking an item to use
    case learn(sel: Int)                                               // a new move for state.learn's first: forget one of 4 (sel 0-3), or not learn it (4)
    case tower                                                         // the Battle Tower lobby
    case beats(Battle, [Beat], since: Date, from: Battle)              // one exchange playing out; `from` = HP before it
    case dowse(cursor: Int, prize: Int, tries: Int, hint: String?)
    case card(Int), bag(Int)
    case say([String], next: Screen, since: Date)                      // any button or 3 s
    case evolve(from: Mon, to: Mon, since: Date)                       // already applied to the state; this is the show
    case dex(Int)                                                      // index into the seen list
    case box(Int, act: Int?, confirm: Bool)                            // act = the ● menu's selection; confirm = "release?"
    case hatch(Mon, since: Date)                                       // already kept; this is the show
}
