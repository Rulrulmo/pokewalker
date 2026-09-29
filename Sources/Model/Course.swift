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
