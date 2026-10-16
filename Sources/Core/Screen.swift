import Foundation
// Which screen the LCD is on.

// MARK: - screens
/// 3.9: the menu in two steps (docs/plans/15 §6 G) — the first page's 8 tiles (2 x 4), each a feature or a group (▸) of them.
var menuTiles: [(name: String, items: [String])] {                       // 5.0 (content5): 메가 레이드 after 레이드; 5.1 (content51): 모험 ▸ 코스 · 전설 원정 (the user: "모험으로 바꾸고 코스와 전설원정 넣는 방식")
    [("포켓 레이더", []), Content.v51 ? ("모험", ["코스", "전설 원정"]) : ("코스", []), ("포켓몬", []), ("기록", ["도감"] + (Content.gen6 ? ["도감 업적"] : []) + ["트레이너 카드"]), ("배틀", ["배틀 타워", "레이드"] + (Content.gen6 ? ["메가 레이드"] : []) + ["대전"]),
     ("친구", ["친구", "교환"]), ("상점", ["상점", "BP 교환소"]), ("우편함", [])]
}
/// Every feature on the menu, in order.
var menuItems: [String] { menuTiles.flatMap { $0.items.isEmpty ? [$0.name] : $0.items } }
/// A menu page's tiles: the first page's (group nil), or a group's features.
func menuNames(_ group: Int?) -> [String] { group.map { menuTiles[$0].items } ?? menuTiles.map(\.name) }
/// The menu page on that feature's tile (where ↩ from it lands).
func onMenu(_ sc: Screen, _ name: String) -> Bool { if case .menu(let g, let i) = sc, case .menu(let g2, let i2) = menuFor(name) { return g == g2 && i == i2 }; return false }
/// Where a feature sits on the menu, by its name (the code never counts tiles): its group's page on it, or the first page on its tile — where ↩ from it lands.
func menuFor(_ name: String) -> Screen {
    if let g = menuTiles.firstIndex(where: { $0.items.contains(name) }) { return .menu(group: g, sel: menuTiles[g].items.firstIndex(of: name)!) }
    return .menu(group: nil, sel: menuTiles.firstIndex { $0.name == name }!)
}
indirect enum Screen {
    case home
    case menu(group: Int?, sel: Int)                                   // 3.9: the first page (group nil: menuTiles), or a group's (menuTiles[group].items); sel = the tile picked
    case team(sel: Int, tab: Int, card: Bool)                          // 12 (M1; 친구 since 3.5): the friends' list on a tab (친구 · 걸음 · 도감 · 타워 · 신청), or the picked one's card
    case trade(TradeStep)                                              // 12 (M2): 교환 — the open offers (팀's 교환 tab), one in full, making or answering one
    case traded(gave: Mon, got: Mon, with: String, since: Date)        // a trade gone through (already in the save): this is the show
    case market(MarketStep)                                            // 12 §3.3 (3.5): the 교환 게시판 — the posts, one in full, putting one up or offering on one
    case raid(RaidStep)                                                // 4.0 (16 §8): the raid — its lobby (친구 이번 주 / 내 판), the tier, a run's ball stage
    case radar(bush: Int, cursor: Int, since: Date, chain: Int)        // "!" shows on `bush` from 1.5 s after `since`, for `radarWindow(chain)`
    case battle(Battle, sel: Int)                                      // sel = the menu row (공격 / 볼 / 도구 / 도망, or 공격 / 도구 / 교체 / 기권)
    case moves(Battle, sel: Int)                                       // picking one of the 4 moves
    case party(Battle, sel: Int)                                       // picking who to switch in
    case bagBattle(Battle, sel: Int)                                   // picking an item to use
    case forfeit(Battle, yes: Bool)                                    // 기권할까? in a tower fight — yes = the highlighted answer, 아니오 first
    case shop(bp: Bool, sel: Int, qty: Int?)                         // 상점 (W) or BP 교환소: the list, or (qty) how many of row sel
    case shopConfirm(bp: Bool, sel: Int, yes: Bool)                    // a once-only row (전설, 기기 색): 정말? — yes = the highlighted answer, 아니오 first
    case learn(sel: Int)                                               // a new move for state.learn's first: forget one of 4 (sel 0-3), or not learn it (4)
    case tower(pick: (slot: Int, at: Int)?)                            // the Battle Tower lobby; pick = choosing who goes in party slot `slot`, `at` the ref under the cursor (a level-up reorders the list: it stays on that one)
    case beats(Battle, [Beat], since: Date, from: Battle)              // one exchange playing out; `from` = HP before it
    case card(Int), items(Int)                                         // 도구: everything carried (the walker's + the bag), the picked row (from 포켓몬's last chip)
    case course(Int)                                                   // 코스: the pick (an index into courses; its picture on the LCD)
    case train(Int)                                                    // 대단한 특훈 with 은색병뚜껑: the stat picked (0 HP … 5 스피드), on Walker.trainRef (3.6: any of ours)
    case itemOn(ItemOn)                                                // 3.6 (docs/plans/13): who gets the 도구 page's item
    case visitPick(ItemOn)                                             // 3.8: which of ours goes to a friend for 맡겨 키우기 (item = the friend's name)
    case hold(ref: Int, sel: Int)                                      // 3.7: 지니게 하기 for one of ours (ref as box's), the row picked
    case formPick(ref: Int, item: String, sel: Int)                    // 5.0: 로토무카탈로그's forms / 유전자쐐기's partners or 분리 for that one (FormView.swift)
    case duel(DuelStep)                                                // 12 §5 (3.6): a live battle's invitation (mine out, or one to me); the fight itself is on the battle screens; 3.8: the 대전 menu, the queue
    case mail(MailStep)                                                // 3.9 (15 §6 A · D): the 우편함 — the list, one mail, a pick of its gift
    case squad(Squad)                                                  // 3.8 (14 §4–5): several of ours in order — the 대전 파티, a raid's party, a duel's 3 of my 6
    case say([String], next: Screen, since: Date)                      // any button or 3 s
    case evolve(from: Mon, to: Mon, since: Date)                       // already applied to the state; this is the show
    case expedition(Int)                                               // 5.1 (content51, ExpView.swift): 전설 원정 — the row picked
    case assemble(Mon, since: Date)                                    // 5.1: 지가르데's cells put together (already in the box; this is the show)
    case goals(Int)                                                    // 5.0 (content5): 도감 업적 — the row picked (0 전국, 1… the regions, last 해금: GoalsView.swift)
    case dex(Int, filter: Int, detail: Bool)                           // the pick's dex number; filter = the grid's tab (전체 / 잡음 / 못 잡음 / 이 코스); detail = the entry page
    case box(Int, act: Int?, confirm: Bool, detail: Bool = false)      // 포켓몬: a ref (-1 the companion, -2-i caught[i], i box[i]; the grid shows boxOrder); act = the ● menu's selection; confirm = "release?"; detail = its page
    case hatch(Mon, since: Date)                                       // already kept; this is the show
    case relearn(ref: Int, slot: Int, at: Int?)                        // 기술 바꾸기 from a Pokémon's page (ref as box's): slot = the one picked (its move count = the free one); at = choosing what goes there, the move under the cursor
}
