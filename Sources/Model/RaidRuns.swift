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
    static let tiers: [RaidTier] = [                                    // the user (10-12): Lv.20 · 40 · 60 · 90 · 120 (★5 fights above 100)
        RaidTier(tier: 1, level: 20, perfect: 3, bp: 1), RaidTier(tier: 2, level: 40, perfect: 3, bp: 1), RaidTier(tier: 3, level: 60, perfect: 4, bp: 2),
        RaidTier(tier: 4, level: 90, perfect: 4, bp: 2), RaidTier(tier: 5, level: 120, perfect: 5, bp: 3),
    ]
    static let caughtMax = 100                                          // a boss caught above it comes in at Lv.100 (its EXP that level's least)
    static func tier(_ n: Int?) -> RaidTier? { tiers.first { $0.tier == n } }
    /// Each boss's own move (the user, 10-12): 루기아 에어로블라스트, 가이오가 해수스파우팅, 그란돈 분화, 디아루가 시간의포효, 펄기아 공간절단,
    /// 기라티나 섀도다이브 (레쿠쟈 has none in gen 4).
    static var signature: [Int: Int] { Content.gen6 ? signatureGen6 : signatureGen4 }
    static let signatureGen4: [Int: Int] = [249: 177, 382: 323, 383: 284, 483: 459, 484: 460, 487: 467]
    /// 5.0 (plan 18 §7): the Gen V–VI legends' too (비크티니 V제너레이트, 레시라무 크로스플레임, 제크로무 크로스썬더, 큐레무 얼어붙은세계, 케르디오 신비의칼,
    /// 메로엣타 옛노래, 게노세크트 테크노버스터, 제르네아스 지오컨트롤, 이벨타르 데스윙, 지가르데 사우전드애로, 디안시 다이아스톰, 후파 이차원홀, 볼케니온 스팀버스트).
    static let signatureGen6 = signatureGen4.merging([494: 557, 643: 558, 644: 559, 646: 549, 647: 548, 648: 547, 649: 546, 716: 601, 717: 613, 718: 614,
                                                      719: 591, 720: 593, 721: 592]) { $1 }
    /// A run's boss: the species at the tier's level and V, its four the last it learned by now (as a wild one's) with its own move among them
    /// from the level it learns it (★3 on: 43–50; ★1 · ★2 as they were — plan 16 §3.7). Caught, it keeps them.
    static func boss<R: RandomNumberGenerator>(_ dex: Int, _ t: RaidTier, shiny: Bool, _ r: inout R) -> Mon {
        var m = Mon.wild(dex, level: t.level, shiny: shiny ? true : nil, perfect: t.perfect, &r)
        if let sig = signature[dex], let at = m.learnLevel(sig), t.level >= at { m.known = m.withSignature(m.moves) }
        return m
    }
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
struct RaidReq: Codable, Equatable { var id, session: String; var app: String? = nil; var kind: String? = nil }   // kind "mega": the Mega raid's lobby (5.0)

extension Mon {
    /// These four with its own move (RaidRules.signature) in the place of the weakest attack (towerScore) if it isn't one of them.
    func withSignature(_ ms: [Int]) -> [Int] {
        guard let sig = RaidRules.signature[dex], !ms.contains(sig) else { return ms }
        if ms.count < 4 { return ms + [sig] }
        var out = ms, hits = ms.indices.filter { !moveTable[ms[$0]]!.isStatus }
        if hits.isEmpty { hits = [3] }
        out[hits.min { towerScore(moveTable[ms[$0]]!) < towerScore(moveTable[ms[$1]]!) }!] = sig
        return out
    }
}

// MARK: - 5.0 (content5): the Mega raid (docs/plans/18 §6.4)
// Apart from the raid: its own menu and its own two bosses a week, the same power and 3 a day (both raids count them, and the weekly mail's
// wins); the same tiers. The boss comes as its Mega (or 원시) form; no balls — a win may give that boss's stone (★1 3 % … ★5 20 %; one had:
// ★×5 BP instead), and every 30 Mega raid wins (any boss, any tier) one stone of the week's two is the trainer's to pick (megaPick).
enum MegaRaid {
    static let app = "5.0"
    /// The rotation (monForms' order): every Mega with a stone but 메가디안시 (not in 5.0), and both 원시 — 48 (메가레쿠쟈 has none: 화룡점정).
    static let bosses: [MegaBoss] = monForms.keys.sorted().flatMap { d -> [MegaBoss] in
        d == 719 ? [] : monForms[d]!.enumerated().compactMap { k, f in (f.kind == .mega || f.kind == .primal) ? f.item.map { MegaBoss(dex: d, form: k + 1, stone: $0) } : nil }
    }
    /// An ISO week's two (24 weeks a round).
    static func week(_ isoWeek: Int) -> [MegaBoss] { [bosses[(2 * isoWeek) % bosses.count], bosses[(2 * isoWeek + 1) % bosses.count]] }
    static let stoneOdds = [3, 5, 8, 10, 20]                    // % a win, ★1–★5 (the user, 10-13)
    static let pity = 30                                        // wins for one pick
    static func duplicateBP(_ tier: Int) -> Int { 5 * tier }
    /// Its Mega's own move: 메가뮤츠 사이코브레이크, 원시가이오가 근원의파동, 원시그란돈 단애의칼 (in the place of the weakest attack).
    static let signature: [Int: Int] = [150: 540, 382: 618, 383: 619]
    /// A run's boss: the species at the tier's level and IVs with its stone (it fights as its Mega: RaidBoss.mega).
    static func boss<R: RandomNumberGenerator>(_ b: MegaBoss, _ t: RaidTier, _ r: inout R) -> Mon {
        var m = Mon.wild(b.dex, level: t.level, perfect: t.perfect, &r); m.item = b.stone
        if let sig = signature[b.dex] {
            var ms = m.moves
            if !ms.contains(sig) { if ms.count < 4 { ms.append(sig) } else if let k = ms.indices.filter({ !moveTable[ms[$0]]!.isStatus }).min(by: { m.towerScore(moveTable[ms[$0]]!) < m.towerScore(moveTable[ms[$1]]!) }) { ms[k] = sig } else { ms[3] = sig } }
            m.known = ms
        }
        return m
    }
    /// The stones a trainer has: in the bag, on the walker, held by any of theirs.
    static func stonesHad(_ w: Walk) -> Set<String> { Set(w.bag + w.items + ([w.companion] + w.caught + w.box).compactMap(\.item)) }
}
struct MegaBoss: Codable, Equatable { var dex, form: Int; var stone: String; var had: Bool? = nil }
/// POST /v2/raid with kind "mega" (5.0): the week's two (had: that stone already), next week's, the day's runs (both raids'), the week's Mega
/// runs, the pick's count (pity of pityNeed), the odds by tier.
struct MegaRaidLobby: Codable, Equatable {
    var week: String; var bosses: [MegaBoss]; var next: [MegaBoss]; var ends: Int
    var today: RaidToday; var resetAt: Int
    var mine: RaidWeek; var runs: [RaidRunRow]
    var pity: Int; var pityNeed: Int; var odds: [Int]; var tiers: [RaidTier]
}
