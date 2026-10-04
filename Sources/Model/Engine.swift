import Foundation
// docs/plans/11 (3.0): the app sends what the player did (Act); the server runs it (EngineRules.swift) with the game's own rules and its own
// dice, and sends back what came of it (Outcome) with the save it made. The wire is these types' synthesized Codable, defined once here for
// the server, the app and the app's self-test fake.

/// What the player did.
enum Act: Codable, Equatable {
    case steps                                                   // nothing but the request's steps
    case radar                                                   // the radar (10 W) or, a chain holding, its next bush (free)
    case radarPick(bush: Int)                                    // the bush picked; -1 = gave up (the time ran out, too early, left)
    case battle(cmd: BattleCmd)
    case tower                                                   // into the tower (50 W) or, on a run, its next trainer
    case towerPick(slot: Int, uid: Int), towerReset              // the lobby's picker (Walk.towerSet), 추천으로
    case buy(bp: Bool, item: String?, legend: Int?, shell: String?, qty: Int)   // one of item / legend (Walk.legendShop index) / shell (a device colour)
    case use(item: String, stat: Int?)                           // the bag's use: feed, train (은색병뚜껑's stat), evolve, sell all of it
    case sellAll
    case mon(op: MonOp)
    case course(index: Int)
    case greet(to: String)                                       // 인사 to a teammate (docs/plans/12 §2.3): the server delivers it, the save doesn't change
}
enum BattleCmd: Codable, Equatable { case fight(slot: Int), ball, item(name: String), swap(to: Int), replace(to: Int), run, forfeit }
/// Pokémon by uid (their places move): 함께 걷기, 상자로, 워커로, 놓아주기, 중복 놓아주기, 기술 바꾸기, the waiting move (nil = 배우지 않는다), 통신 진화.
enum MonOp: Codable, Equatable {
    case pair(uid: Int), store(uid: Int), fetch(uid: Int), release(uid: Int), releaseDupes(dex: Int)
    case move(uid: Int, slot: Int, move: Int), learn(slot: Int?), trade
}

/// What came of it for the player to see, in the order home shows them (docs/plans/11 §3 news).
enum News: Codable, Equatable {
    case find(item: String), egg(dex: Int, left: Int), hatch(mon: Mon)
    case weather(to: Weather), season(to: Int)                                             // Season's rawValue
    case level(uid: Int, level: Int), evolve(uid: Int, from: Int, to: Int, shed: Mon?), learn(uid: Int, move: Int, learned: Bool)
    case unlock(course: Int), dex(count: Int)
    case chain(n: Int, bonus: Int, reward: String?)
    case hello(from: String, dex: Int, shiny: Bool)                                         // a teammate's 인사, with its companion (12 §2.3; app 3.2 on)
}
struct RadarShown: Codable, Equatable { var bush: Int, window: Double, chain: Int }
/// result: caught · won · lost · fled (it got away) · ran (we did) · forfeit. chain: a wild fight's (0 = over); streak · bp: the tower's.
struct BattleEnd: Codable, Equatable { var result: String; var chain: Int? = nil, streak: Int? = nil, bp: Int? = nil }
struct Outcome: Codable, Equatable {
    var news: [News] = []
    var changed = false                                          // the save changed: the reply carries it (rev + 1)
    var radar: RadarShown? = nil, missed: Bool? = nil
    var battle: Battle? = nil, beats: [Beat]? = nil, end: BattleEnd? = nil, ball: String? = nil   // a fight's state after the turn, its beats from before it
    var mon: Mon? = nil, watts: Int? = nil                       // a legend bought; W from a sale or a release
    var cannot: String? = nil                                    // not now, and why (the LCD's lines, "\n" between): nothing of the act happened, its steps did
    static func no(_ why: String) -> Outcome { var o = Outcome(); o.cannot = why; return o }
}
/// What goes on between actions and isn't in the save: the radar shown, a chain holding, the fight on, a tower run, steps held during a fight.
/// A new session starts it over (docs/plans/11 §0).
struct Play: Codable, Equatable {
    struct Radar: Codable, Equatable { var bush: Int, window: Double, chain: Int, at: Double, mon: Mon }   // at: seconds since 2001 (the server's clock)
    var radar: Radar? = nil
    var chain: Int? = nil                                        // the next radar is free, at this chain length
    var battle: Battle? = nil, party: [Int]? = nil               // a wild fight's party by uid: its EXP goes back to them
    var tower = false
    var held = 0
}
/// POST /v2/act. steps: walked first, whatever the act (capped by the server first: `taken`).
struct ActReq: Codable, Equatable { var id, session: String; var seq: Int; var steps: Int? = nil; var act: Act; var app: String? = nil }   // app: news kinds it knows (12 §1)
struct ActReply: Codable { var rev: Int; var walk: Walk? = nil; var taken: Int? = nil; var out: Outcome }
/// New Pokémon get their uids from here (the server's ledger counts on: never reused), and it remembers what it made and why.
struct Issued { var next: Int; var made: [(mon: Mon, kind: String)] = [] }
