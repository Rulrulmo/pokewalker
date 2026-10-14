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
// ★×5 BP instead), and 20 wins on one boss while its stone is missing (any tier, any week) bring that stone by mail (the user, 10-14:
// "보스별로 20번", in place of 10-13's 30 shared wins and a pick).
enum MegaRaid {
    static let app = "5.0"
    /// The rotation (monForms' order): every Mega with a stone but 메가디안시 (not in 5.0), and both 원시 — 48 (메가레쿠쟈 has none: 화룡점정).
    static let bosses: [MegaBoss] = monForms.keys.sorted().flatMap { d -> [MegaBoss] in
        d == 719 ? [] : monForms[d]!.enumerated().compactMap { k, f in (f.kind == .mega || f.kind == .primal) ? f.item.map { MegaBoss(dex: d, form: k + 1, stone: $0) } : nil }
    }
    /// The rotation (the user, 10-14: "섞자"): 24 weeks of two, fixed. Each week one of the hardest with one of the easiest (10-14's RaidSim, the
    /// strong teams' ★4: the i-th hardest with the i-th easiest), the six hardest weeks never back to back nor first, a species' X · Y, the two
    /// primals and 라티아스 · 라티오스 6 weeks apart or more (plan 18 §6.4's table). (dex, form)
    static let rotation: [(dex: Int, form: Int)] = [
        (9, 1), (142, 1),               //  1 메가거북왕 · 메가프테라
        (319, 1), (359, 1),             //  2 메가샤크니아 · 메가앱솔
        (65, 1), (445, 1),              //  3 메가후딘 · 메가한카리아스
        (150, 2), (362, 1),             //  4 메가뮤츠Y · 메가얼음귀신
        (306, 1), (323, 1),             //  5 메가보스로라 · 메가폭타
        (6, 1), (229, 1),               //  6 메가리자몽X · 메가헬가
        (115, 1), (475, 1),             //  7 메가캥카 · 메가엘레이드
        (310, 1), (354, 1),             //  8 메가썬더볼트 · 메가다크펫
        (127, 1), (376, 1),             //  9 메가쁘사이저 · 메가메타그로스
        (254, 1), (460, 1),             // 10 메가나무킹 · 메가눈설왕
        (150, 1), (257, 1),             // 11 메가뮤츠X · 메가번치코
        (15, 1), (18, 1),               // 12 메가독침붕 · 메가피죤투
        (181, 1), (380, 1),             // 13 메가전룡 · 메가라티아스
        (248, 1), (303, 1),             // 14 메가마기라스 · 메가입치트
        (6, 2), (302, 1),               // 15 메가리자몽Y · 메가깜까미
        (3, 1), (448, 1),               // 16 메가이상해꽃 · 메가루카리오
        (130, 1), (383, 1),             // 17 메가갸라도스 · 원시그란돈
        (212, 1), (260, 1),             // 18 메가핫삼 · 메가대짱이
        (334, 1), (428, 1),             // 19 메가파비코리 · 메가이어롭
        (308, 1), (373, 1),             // 20 메가요가램 · 메가보만다
        (282, 1), (381, 1),             // 21 메가가디안 · 메가라티오스
        (94, 1), (214, 1),              // 22 메가팬텀 · 메가헤라크로스
        (208, 1), (531, 1),             // 23 메가강철톤 · 메가다부니
        (80, 1), (382, 1),              // 24 메가야도란 · 원시가이오가
    ]
    static let order: [MegaBoss] = rotation.map { p in bosses.first { $0.dex == p.dex && $0.form == p.form }! }
    /// The rotation's week n's two (24 weeks a round; n: `round`).
    static func week(_ n: Int) -> [MegaBoss] { [order[(2 * n) % order.count], order[(2 * n + 1) % order.count]] }
    /// The rotation's week: weeks since the one content5 first went on in (its two the first: settings' content5_since), not the ISO week's
    /// number, which goes 52 → 53 → 1 at a year's end (2026 has 53) and would show some pairs twice and skip others. Before it: 0.
    static func round(_ now: Date, from start: Date, _ cal: Calendar) -> Int {
        guard let a = cal.dateInterval(of: .weekOfYear, for: start)?.start, let s = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return max(0, (cal.dateComponents([.day], from: a, to: s).day ?? 0) / 7)
    }
    static let stoneOdds = [3, 5, 8, 10, 20]                    // % a win, ★1–★5 (the user, 10-13)
    static let bossWins = 20                                    // wins on one boss (its stone missing) for that stone, by mail
    static func duplicateBP(_ tier: Int) -> Int { 5 * tier }
    /// A win's stone mail title (one had: its BP instead). 쪽빛구슬 · 주홍구슬 take 을.
    static func mailTitle(_ stone: String, had: Bool) -> String { had ? "\(stone) 대신 BP" : josa(stone, "을", "를") + " 얻었다!" }
    /// The 20 wins' stone mail: its title (ends as a drop's: "…를 얻었다!") and line.
    static func winsTitle(_ stone: String) -> String { "\(bossWins)승! " + josa(stone, "을", "를") + " 얻었다!" }
    static func winsBody(_ b: MegaBoss) -> String { josa(Forms.of(b.dex, b.form)?.name ?? b.stone, "을", "를") + " \(bossWins)번 이겨서 스톤이 왔어요." }
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
struct MegaBoss: Codable, Equatable { var dex, form: Int; var stone: String; var had: Bool? = nil; var wins: Int? = nil }   // (the lobby's: had, its count of bossWins)
/// POST /v2/raid with kind "mega" (5.0): the week's two (had: that stone already), next week's, the day's runs (both raids'), the week's Mega
/// runs, each boss's count (MegaBoss.wins of pityNeed: bossWins), the odds by tier.
struct MegaRaidLobby: Codable, Equatable {
    var week: String; var bosses: [MegaBoss]; var next: [MegaBoss]; var ends: Int
    var today: RaidToday; var resetAt: Int
    var mine: RaidWeek; var runs: [RaidRunRow]
    var pityNeed: Int; var odds: [Int]; var tiers: [RaidTier]
}
