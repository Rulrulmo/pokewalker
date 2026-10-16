import Foundation
// docs/plans/19 §1 (5.1, content51): 전설 원정 — one frame for the 19 Gen V–VI legends, each expedition as data. 5.1 has two kinds:
// 수집 (지가르데: a cell every 3,000 steps on 칼로스's courses, the radar there 1/30 more) and 팀 이벤트 (the six mythicals: the team's steps in
// a week, the server's — ServerExpedition.swift). A personal one's progress is in the save (Walk.expeditions): the server moves it on with the
// game's code (EngineRules: walkNow, the radar, expStart / expClaim), the app only draws it. Its count is a number there, never a bag item
// (a 5.0 app would offer to sell one it doesn't know).

enum ExpKind: String, Codable { case collect, team, roam, trial, pair, story }

/// One personal expedition (the team events are the server's rows).
struct Expedition: Equatable {
    let id: String                       // its key in Walk.expeditions: "지가르데"
    let kind: ExpKind
    let legend: Int                      // what it gives (dex)
    let title: String                    // the list's line
    var need = 0                         // collect: how many
    var stepsPer = 0                     // collect: steps on a course that counts, a piece
    var radarOdds = 0.0                  // collect: a radar find there, one more
    var region: ClosedRange<Int>? = nil  // where the steps count: a course of this region (Course.region)
    var piece = ""                       // what is gathered, for the screens ("지가르데 셀")
    var gift: String? = nil              // given at its first finish: the 특성패치 when it closes its kind (plan 19 §1.7, §3)
    /// The steps walked on course c count here.
    func counts(_ c: Course) -> Bool { region.map { c.region == $0 } ?? true }
}

enum Expeditions {
    /// plan 19 §6.1-6: every legend alike — Lv.50, 3 sure 31s, 이로치 1 in 32, its own move.
    static let level = 50, perfect = 3, shinyOdds = 32
    static let patch = "특성패치"
    static let personal: [Expedition] = [
        Expedition(id: "지가르데", kind: .collect, legend: 718, title: "지가르데 셀 모으기", need: 50, stepsPer: 3000, radarOdds: 1.0 / 30, region: 650...721,
                   piece: "지가르데 셀", gift: patch),
    ]
    static func of(_ id: String) -> Expedition? { personal.first { $0.id == id } }
    /// The legend an expedition (or a team event) gives: rolled when it starts, kept in its progress (the 이로치 is fixed then, seen when it comes).
    static func legend<R: RandomNumberGenerator>(_ dex: Int, _ r: inout R) -> Mon {
        var m = Mon.wild(dex, level: level, shiny: Int.random(in: 0..<shinyOdds, using: &r) == 0 ? true : nil, perfect: perfect, &r)
        m.known = m.withSignature(m.moves)                                                          // RaidRules.signature's: 비크티니 V제너레이트, 지가르데 사우전드애로 …
        return m
    }
}

/// A personal expedition's progress (Walk.expeditions[id]). Fields added later must be optional (an older save has none).
struct ExpProgress: Codable, Equatable {
    var on = false                       // the one going on (one at a time); begun but not on = stopped, kept (`mon` set)
    var n = 0                            // gathered (cells)
    var steps = 0                        // steps towards the next one
    var mon: Mon? = nil                  // what it gives, rolled at the start (no uid until it comes); nil = not begun (or done)
    var done = 0                         // finished this many times (다시 하기: plan 19 §6.1-3)
    init(on: Bool = false, n: Int = 0, steps: Int = 0, mon: Mon? = nil, done: Int = 0) { self.on = on; self.n = n; self.steps = steps; self.mon = mon; self.done = done }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false; n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? 0; mon = try c.decodeIfPresent(Mon.self, forKey: .mon)
        done = try c.decodeIfPresent(Int.self, forKey: .done) ?? 0
    }
}

// MARK: - the team events (plan 19 §1.4-6): the server's, these are the shapes both sides read
enum TeamEvents {
    /// The six mythicals in the schedule's order (every other week, then an encore of what each missed).
    static let mythicals = [494, 648, 649, 719, 720, 721]                      // 비크티니 메로엣타 게노세크트 디안시 후파 볼케니온
    static let days = 7, every = 14, goal = 1_500_000, min = 20_000
    /// What comes with one: 후파's 굴레의항아리, 게노세크트's four 카세트.
    static func extras(_ dex: Int) -> [Gift] {
        switch dex {
        case 720: [.items(name: "굴레의항아리", count: 1)]
        case 649: ["아쿠아카세트", "번개카세트", "블레이즈카세트", "프리즈카세트"].map { .items(name: $0, count: 1) }
        default: []
        }
    }
}
/// POST /v2/expedition: the team events, as this trainer sees them.
struct ExpReq: Codable, Equatable { var id, session: String }
/// One team event: its window (unix), the team's goal and steps so far, this trainer's steps and the least that counts, whether its legend came.
/// encore: an encore week's (legend 0) — the mythicals this trainer can still get there.
struct TeamEventView: Codable, Equatable {
    var id: Int, legend: Int, starts: Int, ends: Int, goal: Int, min: Int, team: Int, mine: Int, got: Bool
    var encore: [Int]? = nil
}
struct ExpReply: Codable, Equatable { var events: [TeamEventView] }      // the one on (or the next), then the past ones, newest first
