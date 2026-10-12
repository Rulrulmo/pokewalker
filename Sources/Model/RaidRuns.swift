import Foundation
// docs/plans/16 (4.0): the raid as runs — one a day's power-칸 (3 a day), each against a boss of its own (this week's species, the tier's level,
// a shiny 1 in 32, shown as it comes in), 10 bars; then a ball stage for that boss only: 3 balls, 2 more for a win, thrown until caught, out, or
// given up (raidQuit). A stage cut off (the app closed, asleep, offline) waits on the server until then. The server makes the boss and keeps the
// runs (server/Sources/PokeCore/ServerRaid.swift); these are the shapes both sides read, and the rules the engine needs.

enum RaidRules {
    static let app = "4.0"                                              // the app that knows runs (the server turns them on: pokeserver raid-runs on; test IDs always)
    static let bars = 10, perDay = 3, balls = 3, winBalls = 2
    static let shinyOdds = 32                                           // the user: 1 in 32 (the radar's 1 in 64)
    static let newOdds = 0.30, ownedOdds = 0.10                         // a ball: a species not caught yet (a shiny boss: not caught as shiny yet); one owned
    static let expShare = 5                                             // a bar's EXP: a wild KO's 1/5 (10 bars = 2); EVs on the first bar only
    static let tiers: [RaidTier] = [                                    // the user (10-12): Lv.40 · 60 · 80 · 100 · 120 (★5 fights above 100)
        RaidTier(tier: 1, level: 40, perfect: 3, bp: 1), RaidTier(tier: 2, level: 60, perfect: 3, bp: 1), RaidTier(tier: 3, level: 80, perfect: 4, bp: 2),
        RaidTier(tier: 4, level: 100, perfect: 4, bp: 2), RaidTier(tier: 5, level: 120, perfect: 5, bp: 3),
    ]
    static let caughtMax = 100                                          // a boss caught above it comes in at Lv.100 (its EXP that level's least)
    static func tier(_ n: Int?) -> RaidTier? { tiers.first { $0.tier == n } }
    /// This week's wins that mail a reward (any tier): the 1st, 3rd and 7th (plan 16 §4.3).
    static let weekly: [(wins: Int, gifts: [Gift])] = [
        (1, [.bp(amount: 25)]), (3, [.items(name: "이상한사탕", count: 5)]), (7, [.items(name: "은색병뚜껑", count: 1)]),
    ]
}

/// A tier to pick (plan 16 §4.1): the boss's level, how many of its IVs are 31, the BP a win pays.
struct RaidTier: Codable, Equatable { var tier, level, perfect, bp: Int }
/// A trainer's week of runs: fought, won, caught (shiny: caught as shiny), the highest tier won (nil: none yet). Also on a TeamCard (`raid`).
struct RaidWeek: Codable, Equatable { var runs = 0, wins = 0, caught = 0, shiny = 0; var best: Int? = nil }
/// One of my runs this week, newest first (the lobby's 내 판: a record only).
struct RaidRunRow: Codable, Equatable { var dex, tier: Int; var shiny: Bool; var bars: Int; var won, caught: Bool; var at: Int }
/// A friend's week (me among them), for the lobby's 친구 이번 주 (sorted there: 승 → 잡음 → 이로치 → 이름).
struct RaidFriend: Codable, Equatable { var name: String; var dex: Int; var runs, wins, caught, shiny: Int; var best: Int? = nil }   // dex: its companion
/// A ball stage not finished (cut off): that run's boss and the balls left. The lobby goes straight back to it; a new run waits for it.
struct RaidPending: Codable, Equatable { var boss: Mon; var tier, bars: Int; var won: Bool; var balls: Int }
struct RaidToday: Codable, Equatable { var used, max: Int }
/// POST /v2/raid for 4.0 (the request's `app`): this week's species (Lv.70, plain), next week's, when it ends; today's runs
/// (resetAt: tomorrow 0:00 KST); my week, my runs, my friends' weeks; a cut-off ball stage; the tiers. opens: runs start then (unix; until then
/// nothing can start — the team before the server turns them on; test IDs have them always).
struct RaidLobby: Codable, Equatable {
    var week: String; var boss: Mon; var next: Int; var ends: Int
    var today: RaidToday; var resetAt: Int
    var mine: RaidWeek; var runs: [RaidRunRow]; var friends: [RaidFriend]
    var pending: RaidPending? = nil
    var tiers: [RaidTier]
    var opens: Int? = nil
}
/// What /v2/raid takes: who, and (4.0 on) the app's version (else the User-Agent's).
struct RaidReq: Codable, Equatable { var id, session: String; var app: String? = nil }
