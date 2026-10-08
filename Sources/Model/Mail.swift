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
    /// The 100-win pick: every legend the game has (courses, shops, the raid).
    static let legends = [144, 145, 146, 150, 151, 243, 244, 245, 249, 250, 251, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386,
                          480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493]
    /// The tycoon: the 49th (은) and 99th (금) fights of a run (as the games' 21st and 49th), BP twice. Its teams here only (the user: 은 · 금).
    static let tycoon = "타워 타이쿤", tycoonFights: Set<Int> = [49, 99]
    static let tycoonTeams: [Int: [(dex: Int, nature: Int, item: String, physical: Bool)]] = [
        49: [(464, 3, "기합의띠", true), (350, 15, "먹다남은음식", false), (149, 3, "생명의구슬", true)],     // 은: 드사이돈 · 밀로틱 · 망나뇽
        99: [(149, 3, "생명의구슬", true), (350, 15, "먹다남은음식", false), (376, 3, "구애머리띠", true)],   // 금: 망나뇽 · 밀로틱 · 메타그로스
    ]
    /// 은 or 금 for the fight after `streak` wins (nil: not the tycoon's).
    static func tycoonPrint(afterWins streak: Int) -> String? { streak + 1 == 49 ? "은" : streak + 1 == 99 ? "금" : nil }
}
