import Foundation
// docs/plans/12 §2 (M1): what a teammate's card shows — POST /v2/team's reply, built by the server from each trainer's save and its own counts.

struct TeamCard: Codable, Equatable {
    var name: String
    var companion: Mon, walker: [Mon]
    var owned, seen, shinies: Int                                      // the dex: caught, seen (caught included), species caught as 이로치
    var today, week, total: Int                                        // steps: the server's count today and this week (Mon–Sun, KST), all time
    var towerBest, bestChain, bp: Int
    var duelWins = 0, duelLosses = 0                                   // 실시간 대전 (12 §5)
    var course: Int
    var idle: Int                                                      // seconds since its last act (under 60: walking now — the app sends steps every 15 s)
    var title: String? = nil, deco: String? = nil                      // 3.9 (docs/plans/15 §3.2): the newest 칭호, the card's 장식

    init(name: String, walk w: Walk, today: Int, week: Int, idle: Int) {
        self.name = name; companion = w.companion; walker = w.caught
        owned = (w.owned ?? []).count; seen = Set((w.seen ?? []) + (w.owned ?? [])).count; shinies = (w.shinyOwned ?? []).count
        self.today = today; self.week = week; total = w.total
        towerBest = w.towerBest ?? 0; bestChain = w.bestChain ?? 0; bp = w.bp ?? 0; course = w.course; self.idle = idle
        duelWins = w.duelWins ?? 0; duelLosses = w.duelLosses ?? 0
        title = w.titles?.last; deco = w.deco
    }
}
struct TeamReq: Codable, Equatable { var id, session: String }              // /v2/team and /v2/trades
struct TeamReply: Codable, Equatable {
    var week: String; var cards: [TeamCard]; var requests: [String]? = nil, sent: [String]? = nil   // 3.5: me and my friends; requests to me, mine out
    var visits: Visits? = nil                                          // 3.8 (14 §3): mine away, the ones I'm raising
    var all: [TeamCard]? = nil                                         // 3.8 (14 §4): every trainer, for the accounts in VIEW_ALL only (the 전체 tab)
}
/// 14 §3 (3.8): 맡겨 키우기 — `owner`'s Pokémon raised by `host` until `ends` (unix); steps = what it's been raised so far.
struct Visit: Codable, Equatable { var id: Int; var owner, host: String; var mon: Mon; var steps: Int; var ends: Int }
struct Visits: Codable, Equatable { var away: Visit?; var guests: [Visit]; var out: [Visit]? = nil }   // away: the newest of mine (apps before 3.8.5); out: all of mine (one a friend)

/// 12 §3 (M2): an offer — what `from` gives, what it wants of `to` (nil: their choice); state open · done · declined · cancelled · expired · failed.
struct TradeOffer: Codable, Equatable { var id: Int; var from, to: String; var mon: Mon; var want: Mon?; var at: Int; var state: String }
struct TradesReply: Codable, Equatable { var incoming, outgoing: [TradeOffer] }
/// 12 §3.3 (3.5): the 교환 게시판 — POST /v2/market. A post (its Pokémon, the species wished for, how many offers), an offer on one.
struct Listing: Codable, Equatable { var id: Int; var from: String; var mon: Mon; var wish: [Int]; var at: Int; var bids: Int; var mine: Bool; var note: String? = nil }   // note: 3.8's 한마디
struct Bid: Codable, Equatable { var id: Int; var listing: Int; var from: String; var mon: Mon; var at: Int; var state: String }
struct MarketReply: Codable, Equatable {
    var listings: [Listing]; var offers: [Bid]; var myBids: [Bid]     // every open post; offers on mine; mine on others'
    var claims: [Claim]? = nil, unseen: Int? = nil                     // 3.8 (14 §2.2): the 받기 함; offers on my posts not looked at yet (the red dot)
}
/// POST /v2/market (3.8: seen = one of my posts just opened: its offers count as seen).
struct MarketReq: Codable, Equatable { var id, session: String; var seen: Int? = nil }
/// 14 §2.2: a Pokémon waiting for me — kind traded (got in a trade) · returned (my post's or offer's, back) · visit (home from 맡겨 키우기).
struct Claim: Codable, Equatable { var id: Int; var kind: String; var from: String; var mon: Mon; var at: Int; var note: String? = nil }
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

/// 12 §5 (3.6): a live battle as one player sees it. state: invited · active · over · declined · cancelled · expired. battle: from this player's side
/// (the second player's mirrored); beats: the turns after the asked `since` (worded for this player); need: what this player owes now ("move" ·
/// "replace", nil = waiting for the other or nothing); deadline: when an unmade pick is made for it (unix); result once over.
struct DuelView: Codable, Equatable {
    var id: Int; var state: String; var opponent: String; var challenger: Bool
    var battle: Battle? = nil; var beats: [Beat] = []; var turn = 0; var need: String? = nil; var deadline: Int? = nil
    var result: DuelResult? = nil; var version = 0
    var parties: DuelParties? = nil                                    // 3.8 (14 §5.3): state picking — my 6, theirs as species only
    var opponentTitle: String? = nil                                   // 3.9 (docs/plans/15 §3.2): its 칭호, by its name
}
struct DuelMon: Codable, Equatable { var dex: Int; var female: Bool; var shiny: Bool }
struct DuelParties: Codable, Equatable { var mine: [Mon]; var theirs: [DuelMon]; var picked: [Int]?; var theyPicked: Bool }
/// 14 §5.4: the 전적 — wins, losses, the last 20 (mine / theirs = the three that fought, by dex).
struct DuelRecord: Codable, Equatable { var id: Int; var opponent: String; var won: Bool; var why: String; var at: Int; var mine, theirs: [Int] }
struct DuelRecords: Codable, Equatable { var wins, losses: Int; var recent: [DuelRecord] }
/// why: faint · forfeit · timeout; bp: what this player got.
struct DuelResult: Codable, Equatable { var won: Bool; var why: String; var bp: Int }
/// POST /v2/duel: my open or last live battle; since = the turns I've seen; wait = hold (up to 25 s) until it moves past `version`.
struct DuelReq: Codable, Equatable { var id, session: String; var since: Int? = nil; var wait: Bool? = nil; var version: Int? = nil; var record: Bool? = nil }   // record: 3.8's 전적 with it
struct DuelReply: Codable, Equatable { var duel: DuelView?; var record: DuelRecords? = nil }   // record: 3.8
