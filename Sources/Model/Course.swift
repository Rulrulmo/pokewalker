import Foundation
// Course, slot, item-find and evolution records (the instances live in the generated Sources/Data/Data.swift).

// MARK: - course data (instances in the generated Data.swift)
struct Slot { let dex, level, steps: Int; let chance: Double; let female: Bool }   // steps = min course steps before it can appear
struct Find { let item: String; let steps, chance: Int }
enum Art { case field, forest, mountain, beach, lake, town, cave }
struct Course {
    let name: String; let watts: Int; let dex: Int; let legends: [Int]; let types: [String]; let art: Art
    let slots: [Slot]                    // the original walker's 6: A A B B C C
    let extra: [Slot]                    // not in the original: 2 more per group, same steps / chance as the group (A A B B C C)
    let guests: [Int]                    // not in the original: habitat visitors, 10 % of radar finds
    let items: [Find]
    var all: [Slot] { slots + extra }
    func group(_ g: Int) -> [Slot] { [slots[2 * g], slots[2 * g + 1], extra[2 * g], extra[2 * g + 1]] }   // A = 0, B = 1, C = 2
    func group(of s: Slot) -> Int? { (0..<3).first { group($0).contains { $0.dex == s.dex && $0.steps == s.steps && $0.level == s.level } } }
}
/// 1.14 (docs/plans/09 §5): wild levels by when a course opens — its W, or for an event course its dex count as the W you'd have then
/// (the owner had 110 species around 5,000 W) — so a course still pays its EXP when you get there under the level-scaled formula.
let courseBands: [String: ClosedRange<Int>] = [
    "상쾌한 들판": 5...10, "웅성웅성 숲": 5...11, "울퉁불퉁 산길": 6...12, "아름다운 해변": 8...14, "교외": 10...16, "어둑어둑 동굴": 12...20, "푸른 호수": 15...25,
    "마을 변두리": 18...28, "호연 들판": 22...34, "따뜻한 해변": 25...38, "화산 길": 28...42, "나무 위 집": 32...46, "무서운 동굴": 35...50, "신오 들판": 38...52,
    "얼음 산길": 40...54, "커다란 숲": 42...56, "하얀 호수": 45...58, "거친 해변": 48...60, "리조트": 50...62, "고요한 동굴": 52...65,
    "노란 숲": 12...20, "바다 건너편": 14...22, "밤하늘의 끝": 15...25, "랠리": 18...28, "쇼핑": 20...30, "챔피언의 길": 22...32, "우정의 초원": 22...34,
    "전설의 새 둥지": 32...46, "방황하는 들판": 35...50, "고대 유적": 38...52, "호연의 하늘과 바다": 40...54, "신오 호수": 42...56, "시공의 틈": 45...58,
    "환상의 숲": 48...62, "시작의 방": 52...65]
extension Course {
    /// Its slots' levels stretched over band b, keeping their order (a flat course, all one level: by group — A the top, B the middle, C the bottom).
    func banded(_ b: ClosedRange<Int>) -> Course {
        let lv = all.map(\.level), lo = lv.min() ?? 1, hi = lv.max() ?? 1
        func move(_ s: Slot, _ group: Int) -> Slot {
            let t = hi > lo ? Double(s.level - lo) / Double(hi - lo) : Double(2 - group) / 2
            return Slot(dex: s.dex, level: b.lowerBound + Int((Double(b.upperBound - b.lowerBound) * t).rounded()), steps: s.steps, chance: s.chance, female: s.female)
        }
        return Course(name: name, watts: watts, dex: dex, legends: legends, types: types, art: art, slots: slots.enumerated().map { move($1, $0 / 2) },
                      extra: extra.enumerated().map { move($1, $0 / 2) }, guests: guests, items: items)
    }
}
let courses: [Course] = rawCourses.map { c in courseBands[c.name].map(c.banded) ?? c }
let guestOdds = 0.10   // slots: A A B B C C, items rarest first; dex = Pokédex count (event courses)

/// Gen IV evolution, mapped onto a walker (see tools/gen.py): level = on level-up at `level`+; friend = on level-up after `friendSteps` together;
/// item = use a stone from the bag; trade = Connect while it's the companion. `item` on level/trade = must be in the bag (and is used up).
enum EvoWay { case level, friend, item, trade }
struct Evo { let from, to: Int; let way: EvoWay; let level: Int; let item: String?; let female: Bool?; let time: String?; let place: String?; let party: Int? }
let friendSteps = 10_000                 // stands in for friendship 220 (Gen IV: +1 per 128 steps from ~70 is ~19k; levels add more)

/// Rerolled every `weatherSteps` steps; the matching types show up 1.5x as often. Not in the original walker.
enum Weather: String, Codable, CaseIterable {
    case sunny, rain, snow, fog
    var name: String { ["맑음", "비", "눈", "안개"][Weather.allCases.firstIndex(of: self)!] }
    var types: [String] { [["fire", "grass"], ["water", "electric"], ["ice"], ["ghost", "psychic"]][Weather.allCases.firstIndex(of: self)!] }
    var news: String { ["날씨가 맑아졌다!", "비가 내리기 시작했다!", "눈이 내리기 시작했다!", "안개가 끼었다!"][Weather.allCases.firstIndex(of: self)!] }
}
let weatherSteps = 1000

/// Game time runs on steps, not the wall clock: a day is `dayLength` steps (starting at 6:00), a season `seasonDays` days.
let dayLength = 1000, seasonDays = 7
enum Season: Int, CaseIterable { case spring, summer, autumn, winter; var name: String { ["봄", "여름", "가을", "겨울"][rawValue] } }
