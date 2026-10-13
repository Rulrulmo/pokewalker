import Foundation
// docs/plans/15 (3.9): the 우편함 — what the server sends (rewards, notices, a trade's Pokémon, one back from the board or from 맡겨 키우기) — and
// the Battle Tower's first-time streak rewards, the tower tycoon. The server mails and claims (server/Sources/PokeCore/ServerMail.swift); these
// are the shapes both sides read, and what a claim does to a save.

/// One mail. kind: trade · returned · visit (a Pokémon) · tower (a streak reward) · notice (words only) · admin (an operator's gift).
struct Mail: Codable, Equatable {
    var id: Int; var kind: String; var from: String; var title: String; var body: String? = nil
    var gifts: [Gift]; var at: Int; var read: Bool; var claimed: Bool
    /// It waits on a choice: claimed with mailClaim(id:pick:) only, never by 모두 받기.
    var picks: Bool { gifts.contains { if case .pickItem = $0 { return true }; if case .pickLegend = $0 { return true }; return false } }
}
/// What a mail carries (labelled: the JSON reads {"items": {"name": …, "count": …}}).
enum Gift: Codable, Equatable {
    case mon(mon: Mon, steps: Int? = nil)              // a Pokémon (steps: 맡겨 키우기's, as EXP when it's claimed)
    case items(name: String, count: Int)
    case bp(amount: Int), watts(amount: Int)
    case title(name: String)                           // 칭호
    case deco(kind: String)                            // 트레이너 카드 장식: "silver" · "gold"
    case pickItem(items: [String])                     // one of these, chosen at the claim
    case pickLegend(dex: [Int], level: Int, shiny: Bool)   // one of these species, made by the server at the claim
}
struct MailReq: Codable, Equatable { var id, session: String; var read: [Int]? = nil }   // read: mails just opened
struct MailReply: Codable, Equatable { var mails: [Mail]; var unread: Int }               // unread: not opened, or a gift still waiting

extension Walk {
    /// A gift that only changes the save (items, BP, W, a title, a decoration). Pokémon and picks are the server's (uids, the ledger).
    mutating func receive(_ g: Gift) {
        switch g {
        case .items(let n, let c): bag += Array(repeating: n, count: max(0, c))
        case .bp(let n): bp = (bp ?? 0) + n
        case .watts(let n): watts = min(9999, watts + n)
        case .title(let t): if !(titles ?? []).contains(t) { titles = (titles ?? []) + [t] }
        case .deco(let d): if Walk.decoRank(d) > Walk.decoRank(deco) { deco = d }
        case .mon, .pickItem, .pickLegend: break
        }
    }
    static func decoRank(_ d: String?) -> Int { ["silver": 1, "gold": 2][d ?? ""] ?? 0 }
}

// MARK: - the Battle Tower (docs/plans/15 §3)
enum Tower {
    /// First-time streak rewards: reached once, mailed once (the server's tower_rewards).
    static let rewards: [(wins: Int, gifts: [Gift])] = [
        (7, [.items(name: "이상한사탕", count: 3)]),
        (14, [.pickItem(items: ["구애머리띠", "구애안경", "구애스카프", "생명의구슬", "기합의띠", "먹다남은음식", "달인의띠"])]),
        (21, [.items(name: "은색병뚜껑", count: 1)]),
        (28, [.items(name: "금색병뚜껑", count: 1)]),
        (35, [.bp(amount: 150)]),
        (50, [.deco(kind: "silver"), .items(name: "금색병뚜껑", count: 1)]),
        (70, [.deco(kind: "gold")]),
        (100, [.title(name: "타워 타이쿤"), .pickLegend(dex: Tower.legends, level: 70, shiny: true)]),
    ]
    /// 4.1 (docs/plans/17, the user 10-12): past the table, every 50 from 150 on (150, 200, …, no end) — first time, by mail, as the rest.
    static let endless = (from: 150, every: 50, gifts: [Gift.items(name: "금색병뚜껑", count: 1)])
    /// The first-time reward at `wins` wins (the table's or an endless one); nil = none.
    static func reward(_ wins: Int) -> [Gift]? {
        rewards.first { $0.wins == wins }?.gifts ?? (wins >= endless.from && (wins - endless.from) % endless.every == 0 ? endless.gifts : nil)
    }
    /// Every first-time reward up to `best` wins, in order (the server's mailer).
    static func rewards(upTo best: Int) -> [(wins: Int, gifts: [Gift])] {
        rewards.filter { $0.wins <= best } + stride(from: endless.from, through: best, by: endless.every).map { (wins: $0, gifts: endless.gifts) }
    }
    /// The 100-win pick: every legend the game has (courses, shops, the raid).
    static let legends = [144, 145, 146, 150, 151, 243, 244, 245, 249, 250, 251, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386,
                          480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493]
    /// The tycoon: the 50th (은) and 100th (금) fights of a run (4.1, the user; 3.9–4.0: the 49th · 99th, as the games' 21st and 49th), BP twice.
    /// Its teams here only (the user: 은 · 금), a legend in each (plan 17: 은 루기아, Silver's; 금 as DP's 금 — 망나뇽 · 밀로틱 · 레지기가스).
    static let tycoon = "타워 타이쿤", tycoonFights: Set<Int> = [50, 100]
    static var tycoonTeams: [Int: [(dex: Int, nature: Int, item: String, physical: Bool)]] { Content.gen6 ? tycoonTeamsGen6 : tycoonTeamsGen4 }
    /// 5.0 (plan 18 §6.3): 밀로틱's place a Mega — 은 메가야도란, 금 메가마기라스 (as hard as 4.1's in the sims, §11.4).
    static let tycoonTeamsGen6: [Int: [(dex: Int, nature: Int, item: String, physical: Bool)]] = [
        50: [(464, 3, "기합의띠", true), (80, 15, "야도란나이트", false), (249, 3, "생명의구슬", true)],
        100: [(149, 3, "생명의구슬", true), (248, 3, "마기라스나이트", true), (486, 3, "구애머리띠", true)],
    ]
    static let tycoonTeamsGen4: [Int: [(dex: Int, nature: Int, item: String, physical: Bool)]] = [
        50: [(464, 3, "기합의띠", true), (350, 15, "먹다남은음식", false), (249, 3, "생명의구슬", true)],     // 은: 거대코뿌리 · 밀로틱 · 루기아 (망나뇽's place)
        100: [(149, 3, "생명의구슬", true), (350, 15, "먹다남은음식", false), (486, 3, "구애머리띠", true)],  // 금: 망나뇽 · 밀로틱 · 레지기가스
    ]
    /// 은 or 금 for the fight after `streak` wins (nil: not the tycoon's).
    static func tycoonPrint(afterWins streak: Int) -> String? { streak + 1 == 50 ? "은" : streak + 1 == 100 ? "금" : nil }
    /// 4.1 (docs/plans/17, the user 10-12): one legend at most (any of `legends`, the mythical ones too) in the tower's three. The raid and duels take any.
    static let legendMax = 1, legendWhy = "전설은 1마리만\n나갈 수 있어요"
    static func isLegend(_ dex: Int) -> Bool { legendSet.contains(dex) || Content.gen6 && legendSet6.contains(dex) }
    private static let legendSet = Set(legends)
    /// 5.0 (plan 18 §7): Gen V–VI's 19, the tower's only (as foes from the 101st; one at most in ours) — not the 100-win pick, not courses, not the raid.
    static let legendsGen6Added = [494, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 716, 717, 718, 719, 720, 721]
    private static let legendSet6 = Set(legendsGen6Added)
    /// From the 101st fight of a run on (past the 금 tycoon), every trainer's last one is a legend from `legendFoes` (the user).
    static let legendFrom = 101
    static func legendFight(afterWins streak: Int) -> Bool { streak + 1 >= legendFrom }
    static var legendFoes: [Int] { Content.gen6 ? legends + legendsGen6Added : legends }
    /// 5.0 (plan 18 §6.3): from the 51st, a trainer's first holds a Mega stone — any non-legend's (41 species, 42 forms: 리자몽 X · Y).
    static let megaFrom = 51
    static let megaFoes: [(dex: Int, stone: String)] = monForms.keys.sorted().flatMap { d in
        Tower.legends.contains(d) || legendsGen6Added.contains(d) ? [] : monForms[d]!.compactMap { f in f.kind == .mega ? f.item.map { (d, $0) } : nil }
    }
}
