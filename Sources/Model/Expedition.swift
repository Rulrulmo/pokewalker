import Foundation
// docs/plans/19 §1 (5.1, content51): 전설 원정 — one frame for the 19 Gen V–VI legends, each expedition as data. 5.1 has two kinds:
// 수집 (지가르데: a cell every 3,000 steps on 칼로스's courses, the radar there 1/30 more) and 팀 이벤트 (the six mythicals: the team's steps in
// a week, the server's — ServerExpedition.swift). A personal one's progress is in the save (Walk.expeditions): the server moves it on with the
// game's code (EngineRules: walkNow, the radar, expStart / expClaim), the app only draws it. Its count is a number there, never a bag item
// (a 5.0 app would offer to sell one it doesn't know).

enum ExpKind: String, Codable { case collect, team, roam, trial, pair, story }

/// 5.2 (docs/plans/19 §11.2): an expedition in steps, one after another (ExpProgress.stage). 지가르데 (5.1) is its own fields, one collect.
enum ExpStep: String, Codable { case collect, walk, meet, fight, companion }
struct ExpStage: Equatable {
    let kind: ExpStep
    var need = 0                         // collect: pieces; walk · companion: steps
    var stepsPer = 0                     // collect: steps a piece; meet: steps a meeting (2 banked at most: Expeditions.meetsMax)
    var radarOdds = 0.0                  // collect: a radar find there, one more piece; meet: the roamer, on its course today
    var arts: Set<Art>? = nil            // where steps count: a course of these pictures (nil: any)
    var region: ClosedRange<Int>? = nil  // … of this region (Course.region; nil: any)
    var piece = ""                       // collect: what is gathered ("운석 조각")
    var level = 0, perfect = 0, bars = 0 // fight: the boss (Lv., its 31s, how many times it stands up); meet: the roamer's level
    var balls = 0                        // fight: the ball stage after a win (0: the legend comes with the win)
    var with: Set<Int> = []              // companion: the steps count while the companion is one of these
    /// The steps walked on course c count here.
    func counts(_ c: Course) -> Bool { (region.map { c.region == $0 } ?? true) && (arts.map { $0.contains(c.art) } ?? true) }
}

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
    // 5.2 (plan 19 §11.2): the steps (empty: 지가르데's one collect above), the ones to finish first, what else its first finish gives (비추는거울)
    var stages: [ExpStage] = []
    var after: [String] = []
    var item: String? = nil
    /// The steps walked on course c count here.
    func counts(_ c: Course) -> Bool { region.map { c.region == $0 } ?? true }
    /// Its steps, 지가르데's as one collect.
    var steps: [ExpStage] { stages.isEmpty ? [ExpStage(kind: .collect, need: need, stepsPer: stepsPer, radarOdds: radarOdds, region: region, piece: piece)] : stages }
}

enum Expeditions {
    /// plan 19 §6.1-6: every legend alike — Lv.50, 3 sure 31s, 이로치 1 in 32, its own move.
    static let level = 50, perfect = 3, shinyOdds = 32
    static let patch = "특성패치"
    /// 5.1's, and 5.2's with content52 (Content.v52).
    static var personal: [Expedition] { Content.v52 ? since51 + since52 : since51 }
    static let since51: [Expedition] = [
        Expedition(id: "지가르데", kind: .collect, legend: 718, title: "지가르데 셀 모으기", need: 50, stepsPer: 3000, radarOdds: 1.0 / 30, region: 650...721,
                   piece: "지가르데 셀", gift: patch),
    ]
    /// 5.2 (plan 19 §11.2–3, the user 10-23 "나머진 추천대로"): 배회 (하나's courses; 랜드로스 after both), 시련 (a picture's courses; 케르디오
    /// after the three, walking with one of them), 레쿠쟈 (운석 조각 → 하늘기둥 → 결전: 화룡점정, plan 19 §1.8).
    static let unova = 494...649, meetsMax = 2, roamTurns = 3
    static let since52: [Expedition] = {
        func roam(_ id: String, _ dex: Int) -> Expedition {
            Expedition(id: id, kind: .roam, legend: dex, title: id + " 쫓기",
                       stages: [ExpStage(kind: .meet, stepsPer: 5000, radarOdds: 1.0 / 30, region: unova, level: level)])
        }
        func trial(_ id: String, _ dex: Int, _ art: Art, _ place: String) -> Expedition {
            Expedition(id: id, kind: .trial, legend: dex, title: id + "의 시련(" + place + ")",
                       stages: [ExpStage(kind: .walk, need: 30_000, arts: [art]), boss(60)])
        }
        func boss(_ lv: Int, balls: Int = 5) -> ExpStage { ExpStage(kind: .fight, level: lv, perfect: 4, bars: 3, balls: balls) }
        return [
            roam("토네로스", 641), roam("볼트로스", 642),
            Expedition(id: "랜드로스", kind: .roam, legend: 645, title: "랜드로스의 하나 지방", gift: patch,
                       stages: [ExpStage(kind: .walk, need: 20_000, region: unova), boss(60)], after: ["토네로스", "볼트로스"], item: "비추는거울"),
            trial("코바르온", 638, .cave, "동굴"), trial("테라키온", 639, .mountain, "산"), trial("비리디온", 640, .forest, "숲"),
            Expedition(id: "케르디오", kind: .trial, legend: 647, title: "세 검사와 걷기", gift: patch,
                       stages: [ExpStage(kind: .companion, need: 10_000, with: [638, 639, 640])], after: ["코바르온", "테라키온", "비리디온"]),
            Expedition(id: "레쿠쟈", kind: .trial, legend: 384, title: "하늘기둥의 레쿠쟈",
                       stages: [ExpStage(kind: .collect, need: 20, stepsPer: 3000, radarOdds: 1.0 / 30, arts: [.mountain, .cave], piece: "운석 조각"),
                                ExpStage(kind: .walk, need: 30_000, arts: [.mountain]), boss(70, balls: 0)]),
        ]
    }()
    static func of(_ id: String) -> Expedition? { personal.first { $0.id == id } }
    /// 배회: where the roamer is today — one of the 하나 courses this trainer has open, the same all day (by the day and the expedition: the
    /// team sees the same course where it's open). nil: none open (the first, 하나 들판, always is with content5).
    static func roamCourse(_ id: String, day: String, open: (Int) -> Bool) -> Int? {
        let here = courses.indices.filter { courses[$0].region == unova && open($0) }
        guard !here.isEmpty else { return nil }
        return here[Int(fnv(day + "/" + id) % UInt64(here.count))]
    }
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
    // 5.2 (plan 19 §11.7): the step on (nil = the first), meetings banked (배회), the roamer's HP and status left (nil = full, none), the day
    // of the last boss fight (Walk.key), the ball stage's balls (nil = none). `steps` and `n` are the step's own (they start over at the next).
    var stage: Int? = nil, meets: Int? = nil, hp: Int? = nil, status: Status? = nil, fought: String? = nil, balls: Int? = nil
    init(on: Bool = false, n: Int = 0, steps: Int = 0, mon: Mon? = nil, done: Int = 0, stage: Int? = nil, meets: Int? = nil, hp: Int? = nil,
         status: Status? = nil, fought: String? = nil, balls: Int? = nil) {
        self.on = on; self.n = n; self.steps = steps; self.mon = mon; self.done = done
        self.stage = stage; self.meets = meets; self.hp = hp; self.status = status; self.fought = fought; self.balls = balls
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false; n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? 0; mon = try c.decodeIfPresent(Mon.self, forKey: .mon)
        done = try c.decodeIfPresent(Int.self, forKey: .done) ?? 0
        stage = try c.decodeIfPresent(Int.self, forKey: .stage); meets = try c.decodeIfPresent(Int.self, forKey: .meets)
        hp = try c.decodeIfPresent(Int.self, forKey: .hp); status = try c.decodeIfPresent(Status.self, forKey: .status)
        fought = try c.decodeIfPresent(String.self, forKey: .fought); balls = try c.decodeIfPresent(Int.self, forKey: .balls)
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
