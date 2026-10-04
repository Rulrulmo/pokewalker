import Foundation
// docs/plans/12 §2 (M1): what a teammate's card shows — POST /v2/team's reply, built by the server from each trainer's save and its own counts.

struct TeamCard: Codable, Equatable {
    var name: String
    var companion: Mon, walker: [Mon]
    var owned, seen, shinies: Int                                      // the dex: caught, seen (caught included), species caught as 이로치
    var today, week, total: Int                                        // steps: the server's count today and this week (Mon–Sun, KST), all time
    var towerBest, bestChain, bp: Int
    var course: Int
    var idle: Int                                                      // seconds since its last act (under 60: walking now — the app sends steps every 15 s)

    init(name: String, walk w: Walk, today: Int, week: Int, idle: Int) {
        self.name = name; companion = w.companion; walker = w.caught
        owned = (w.owned ?? []).count; seen = Set((w.seen ?? []) + (w.owned ?? [])).count; shinies = (w.shinyOwned ?? []).count
        self.today = today; self.week = week; total = w.total
        towerBest = w.towerBest ?? 0; bestChain = w.bestChain ?? 0; bp = w.bp ?? 0; course = w.course; self.idle = idle
    }
}
struct TeamReq: Codable, Equatable { var id, session: String }              // /v2/team and /v2/trades
struct TeamReply: Codable, Equatable { var week: String; var cards: [TeamCard] }

/// 12 §3 (M2): an offer — what `from` gives, what it wants of `to` (nil: their choice); state open · done · declined · cancelled · expired · failed.
struct TradeOffer: Codable, Equatable { var id: Int; var from, to: String; var mon: Mon; var want: Mon?; var at: Int; var state: String }
struct TradesReply: Codable, Equatable { var incoming, outgoing: [TradeOffer] }
/// /v2/box: a teammate's box, to pick what to ask for.
struct BoxReq: Codable, Equatable { var id, session, of: String }
struct BoxReply: Codable, Equatable { var name: String; var box: [Mon] }

/// 12 §4.4 (M3): the raid's lobby — POST /v2/raid.
struct RaidFighter: Codable, Equatable { var name: String; var dealt: Int }
struct RaidHit: Codable, Equatable { var name: String; var dex: Int; var dealt: Int; var at: Int }       // dex: that fight's lead
struct RaidMine: Codable, Equatable { var dealt: Int, fights: Int; var balls: Int?; var caught: Bool; var canCatch: Bool }
struct RaidReply: Codable, Equatable {
    var week: String; var boss: Mon; var next: Int
    var hpTotal: Int, hpLeft: Int, barHP: Int, ends: Int                     // ends: the week's end (unix)
    var fighters: [RaidFighter]; var recent: [RaidHit]; var mine: RaidMine
}
