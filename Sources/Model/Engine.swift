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
    case use(item: String, stat: Int?, on: Int? = nil)           // the bag's use: feed, train (은색병뚜껑's stat), evolve, a mint, sell all of it; on: that one's uid (nil = the companion; 3.6)
    case sellAll
    case mon(op: MonOp)
    case course(index: Int)
    case greet(to: String)                                       // 인사 to a teammate (docs/plans/12 §2.3): the server delivers it, the save doesn't change
    case tradeOffer(to: String, give: Int, want: Int?)           // 교환 (12 §3): one of our box's for one of theirs (nil: what they choose)
    case tradeAccept(id: Int, give: Int?), tradeDecline(id: Int), tradeCancel(id: Int)
    case raid, raidBall                                          // the co-op raid (12 §4): a fight with this week's boss (1칸 of power); a ball once the team beat it
    case friendRequest(to: String), friendAccept(from: String), friendDecline(from: String), friendRemove(name: String)   // 친구 (12 §2.4, 3.5)
    case marketList(give: Int, wish: [Int]), marketUnlist(id: Int)                         // 교환 게시판 (12 §3.3, 3.5): put one up (wished species shown), take it down
    case marketBid(listing: Int, give: Int), marketWithdraw(bid: Int), marketAccept(bid: Int)   // offer one of ours for it, take that back; the poster picks one
    case duelChallenge(to: String), duelAccept(id: Int), duelDecline(id: Int), duelCancel(id: Int)   // 실시간 대전 (12 §5, 3.6): a friend asked, yes / no, taken back
    case duelMove(id: Int, cmd: BattleCmd)                       // this turn's pick: fight(slot) · swap(to) · replace(to) · forfeit
}
enum BattleCmd: Codable, Equatable { case fight(slot: Int), ball, item(name: String, on: Int? = nil), swap(to: Int), replace(to: Int), run, forfeit }   // item on: a party slot (nil = the one out; 3.6)
/// Pokémon by uid (their places move): 함께 걷기, 상자로, 워커로, 놓아주기, 중복 놓아주기, 기술 바꾸기, the waiting move (nil = 배우지 않는다), 통신 진화.
enum MonOp: Codable, Equatable {
    case pair(uid: Int), store(uid: Int), fetch(uid: Int), release(uid: Int), releaseDupes(dex: Int)
    case move(uid: Int, slot: Int, move: Int), learn(slot: Int?), trade
    case hold(uid: Int, item: String?)                                // 지니게 하기 (3.7, docs/plans/13 ⑤): from the bag (what it held goes back), nil = take it back
}

/// What came of it for the player to see, in the order home shows them (docs/plans/11 §3 news).
enum News: Codable, Equatable {
    case find(item: String), egg(dex: Int, left: Int), hatch(mon: Mon)
    case weather(to: Weather), season(to: Int)                                             // Season's rawValue
    case level(uid: Int, level: Int), evolve(uid: Int, from: Int, to: Int, shed: Mon?), learn(uid: Int, move: Int, learned: Bool)
    case unlock(course: Int), dex(count: Int)
    case chain(n: Int, bonus: Int, reward: String?)
    case hello(from: String, dex: Int, shiny: Bool)                                         // a teammate's 인사, with its companion (12 §2.3; app 3.2 on)
    case tradeOffer(id: Int, from: String, mon: Mon, want: Mon?)                            // 교환 (12 §3; app 3.3 on): an offer came
    case traded(id: Int, with: String, gave: Mon, got: Mon)                                 // it went through (got: after a trade evolution)
    case tradeClosed(id: Int, with: String, why: String)                                    // declined, taken back, out of time, or a Pokémon gone
    case raidCleared(dex: Int)                                                              // the team beat this week's boss (12 §4.3; app 3.4 on): a ball awaits
    case friendRequest(from: String), friendAdded(name: String)                             // 친구 (12 §2.4; app 3.5 on): someone asked; it's mutual now
    case marketBid(listing: Int, from: String, mon: Mon)                                    // an offer on my 게시판 post (12 §3.3; app 3.5 on)
    case duelInvite(id: Int, from: String)                                                  // a friend wants a live battle (12 §5; app 3.6 on)
}
struct RadarShown: Codable, Equatable { var bush: Int, window: Double, chain: Int }
/// result: caught · won · lost · fled (it got away) · ran (we did) · forfeit. chain: a wild fight's (0 = over); streak · bp: the tower's.
struct BattleEnd: Codable, Equatable { var result: String; var chain: Int? = nil, streak: Int? = nil, bp: Int? = nil, dealt: Int? = nil }   // dealt: a raid's damage (12 §4.2)
/// A raid ball (12 §4.3): did it hold, how it rocked, balls left, what came, and whether the week's clear reward came with it.
struct RaidThrow: Codable, Equatable { var caught: Bool, shakes: Int, balls: Int; var mon: Mon? = nil; var reward = false }
struct Outcome: Codable, Equatable {
    var news: [News] = []
    var changed = false                                          // the save changed: the reply carries it (rev + 1)
    var radar: RadarShown? = nil, missed: Bool? = nil
    var battle: Battle? = nil, beats: [Beat]? = nil, end: BattleEnd? = nil, ball: String? = nil   // a fight's state after the turn, its beats from before it
    var mon: Mon? = nil, watts: Int? = nil                       // a legend bought; W from a sale or a release
    var raidThrow: RaidThrow? = nil
    var duel: DuelView? = nil                                    // a live battle as this player sees it (12 §5)
    var cannot: String? = nil                                    // not now, and why (the LCD's lines, "\n" between): nothing of the act happened, its steps did
    static func no(_ why: String) -> Outcome { var o = Outcome(); o.cannot = why; return o }
}
extension Outcome {
    /// Read news one by one, skipping kinds this app doesn't know (docs/plans/12 §1: later additions need no version gate); the rest as synthesized.
    /// A new Outcome field goes here too (the server's engineOutcomeRoundTrip test sets every one and fails on a forgotten one).
    init(from d: Decoder) throws {
        struct Lossy: Decodable { let news: News?; init(from d: Decoder) throws { news = try? News(from: d) } }
        let c = try d.container(keyedBy: CodingKeys.self)
        news = (try c.decodeIfPresent([Lossy].self, forKey: .news) ?? []).compactMap(\.news)
        changed = try c.decodeIfPresent(Bool.self, forKey: .changed) ?? false
        radar = try c.decodeIfPresent(RadarShown.self, forKey: .radar); missed = try c.decodeIfPresent(Bool.self, forKey: .missed)
        battle = try c.decodeIfPresent(Battle.self, forKey: .battle); beats = try c.decodeIfPresent([Beat].self, forKey: .beats)
        end = try c.decodeIfPresent(BattleEnd.self, forKey: .end); ball = try c.decodeIfPresent(String.self, forKey: .ball)
        mon = try c.decodeIfPresent(Mon.self, forKey: .mon); watts = try c.decodeIfPresent(Int.self, forKey: .watts)
        raidThrow = try c.decodeIfPresent(RaidThrow.self, forKey: .raidThrow)
        duel = try c.decodeIfPresent(DuelView.self, forKey: .duel)
        cannot = try c.decodeIfPresent(String.self, forKey: .cannot)
    }
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
    var raid: String? = nil                                      // the week of the raid fight on (its damage goes to that week's boss)
    var raidBoss: RaidBoss? = nil                                // this week's boss as the server has it, for a raid act (set by the server)
}
/// 12 §4: the week's boss and what's left of the team's HP.
struct RaidBoss: Codable, Equatable { var week: String; var boss: Mon; var left: Int }
/// POST /v2/act. steps: walked first, whatever the act (capped by the server first: `taken`).
struct ActReq: Codable, Equatable { var id, session: String; var seq: Int; var steps: Int? = nil; var act: Act; var app: String? = nil }   // app: news kinds it knows (12 §1)
struct ActReply: Codable { var rev: Int; var walk: Walk? = nil; var taken: Int? = nil; var out: Outcome }
/// New Pokémon get their uids from here (the server's ledger counts on: never reused), and it remembers what it made and why.
struct Issued { var next: Int; var made: [(mon: Mon, kind: String)] = [] }
