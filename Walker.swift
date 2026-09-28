import Foundation

// MARK: - course data (instances in the generated Data.swift)
struct Slot { let dex, level, steps: Int; let chance: Double; let female: Bool }   // steps = min course steps before it can appear
struct Find { let item: String; let steps, chance: Int }
enum Art { case field, forest, mountain, beach, lake, town, cave }
struct Course { let name: String; let watts: Int; let dex: Int; let legends: [Int]; let types: [String]; let art: Art; let slots: [Slot]; let items: [Find] }   // slots: A A B B C C, items rarest first; dex = Pokédex count (event courses)

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

/// An egg carried on the walker: hatches after `left` more steps (egg cycles x 255, Gen IV).
struct Egg: Codable, Equatable { var dex: Int; var left: Int }
enum PetFind: Equatable { case item(String), egg(Int) }
let legendOdds = (base: 0.02, perChain: 0.01)          // a legend course's radar: 2 % + 1 % per chain link (up to 4)

struct Mon: Codable, Equatable {
    var dex: Int; var level: Int; var female: Bool
    var shiny: Bool? = nil               // Optionals: saves from before these fields still decode
    var exp: Int? = nil                  // nil = the minimum for `level`
    var walked: Int? = nil               // steps as the companion (friendship)

    var points: Int { exp ?? expTable[growthRate[dex]][level] }
    static func level(dex: Int, exp: Int) -> Int { let t = expTable[growthRate[dex]]; return (1...100).last { t[$0] <= exp } ?? 1 }
    /// 1 step = 1 EXP, like HGSS. Returns true on a level-up.
    mutating func gain(_ n: Int) -> Bool {
        let e = points + n, before = level
        exp = e; walked = (walked ?? 0) + n; level = max(level, Mon.level(dex: dex, exp: e))
        return level > before
    }
}
/// 이로치 odds. Gen IV is 1/8192, which at a few radar fights a day would never show up.
let shinyOdds = 128

/// Everything the device remembers, plus the "game" side (box/bag) that Connect sends things to.
struct Walk: Codable, Equatable {
    var version = 1
    var companion = Mon(dex: 25, level: 5, female: false)
    var course = 0
    var picks = [0, 2, 4]                  // the one slot per group A/B/C this pairing carries; rerolled on every course change
    var courseSteps = 0                    // since the course was set; gates the rarer slots and items
    var today = 0, total = 0, watts = 0, earned = 0     // earned = lifetime watts (unlocks courses); watts = spendable, max 9999
    var remainder = 0                      // steps towards the next watt (20 per watt)
    var day = ""                           // yyyy-MM-dd that `today` belongs to
    var history: [Int] = []                // previous days' steps, newest first, max 7 (missed days = 0)
    var days = 1                           // days walked with this device
    var caught: [Mon] = [], items: [String] = []        // on the walker, max 3 each
    var box: [Mon] = [], bag: [String] = []             // sent back by Connect; overflow goes straight here
    var counter: UInt32 = 0, boot: Double = 0           // system input-event counter at the last poll, and the boot it belongs to
    var seen: [Int]? = nil, owned: [Int]? = nil         // Pokédex, sorted; Optional so older saves decode (see `dex()`)
    var shinyOwned: [Int]? = nil                        // species ever owned as 이로치 (the dex shows those colours too)
    var weather: Weather? = nil, weatherAt: Int? = nil  // nil = sunny; total steps at the last roll
    var nextEvent: Int? = nil                           // total steps of the companion's next little event
    var egg: Egg? = nil

    var here: Course { courses[course] }
    /// A companion of one of the course's 3 types needs 25 % fewer steps: same as walking 4/3 as far.
    var bonus: Bool { monTypes[companion.dex].contains { here.types.contains($0) } }
    var effSteps: Int { bonus ? courseSteps * 4 / 3 : courseSteps }
    func unlocked(_ i: Int) -> Bool { earned >= courses[i].watts && (owned ?? []).count >= courses[i].dex }

    static func key(_ d: Date) -> String { let c = Calendar.current.dateComponents([.year, .month, .day], from: d); return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!) }

    /// New calendar day: today's count moves into history (plus zeros for days skipped entirely).
    mutating func rollover(_ now: Date) {
        let k = Walk.key(now)
        guard k != day else { return }
        if !day.isEmpty, let last = DateFormatter.day.date(from: day) {
            let gap = max(1, Calendar.current.dateComponents([.day], from: last, to: Calendar.current.startOfDay(for: now)).day ?? 1)
            history.insert(today, at: 0)
            for _ in 1..<min(gap, 8) { history.insert(0, at: 0) }
            history = Array(history.prefix(7)); days += gap
        }
        today = 0; day = k
    }

    /// Returns true when the companion levelled up.
    @discardableResult mutating func walk(_ n: Int, at now: Date) -> Bool {
        rollover(now)
        guard n > 0 else { return false }
        today += n; total += n; courseSteps += n; remainder += n
        let w = remainder / 20; remainder %= 20
        watts = min(9999, watts + w); earned += w
        egg?.left -= n
        return companion.gain(n)
    }

    // MARK: companion events: every 150-400 steps it emotes, and 1 in 4 times brings back an item from the course
    var eventDue: Bool { nextEvent.map { total >= $0 } ?? true }
    /// What it brought back (already kept), or nil for just an emote. 1 in 8: an egg (if it isn't carrying one), else 1 in 4: an item.
    mutating func petEvent<R: RandomNumberGenerator>(_ r: inout R) -> PetFind? {
        let first = nextEvent == nil
        nextEvent = total + Int.random(in: 150...400, using: &r)
        guard !first else { return nil }
        if egg == nil, Int.random(in: 0..<8, using: &r) == 0 {
            let fresh = eggPool.filter { !(owned ?? []).contains($0) }, d = (fresh.isEmpty ? eggPool : fresh).randomElement(using: &r)!   // new species first
            egg = Egg(dex: d, left: eggCycles[d] * 255); return .egg(d)
        }
        guard Int.random(in: 0..<4, using: &r) == 0 else { return nil }
        let i = dowse(&r); _ = keep(i); return .item(i)
    }
    var hatchDue: Bool { (egg?.left ?? 1) <= 0 }
    mutating func hatch<R: RandomNumberGenerator>(_ r: inout R) -> Mon {
        let m = Mon(dex: egg!.dex, level: 1, female: Bool.random(using: &r), shiny: Int.random(in: 0..<shinyOdds, using: &r) == 0 ? true : nil)
        egg = nil; _ = keep(m); return m
    }
    /// On a legend course the radar sometimes turns up one you don't have yet.
    func legend<R: RandomNumberGenerator>(_ r: inout R, chain: Int) -> Int? {
        let left = here.legends.filter { !(owned ?? []).contains($0) }
        guard !left.isEmpty, Double.random(in: 0..<1, using: &r) < legendOdds.base + legendOdds.perChain * Double(min(chain, 4)) else { return nil }
        return left.randomElement(using: &r)
    }

    // MARK: box
    /// Lets box[i] go; a few watts back as thanks (level / 2, at least 1).
    mutating func release(_ i: Int) -> Int { let w = max(1, box.remove(at: i).level / 2); watts = min(9999, watts + w); return w }
    mutating func sortBox(byLevel: Bool) { box.sort { byLevel ? ($0.points, $1.dex) > ($1.points, $0.dex) : ($0.dex, $1.points) < ($1.dex, $0.points) } }

    // MARK: weather
    var weatherDue: Bool { total / weatherSteps != (weatherAt ?? 0) / weatherSteps }
    /// Odds by course kind: beaches rain, mountains snow (얼음 산길 nearly always), caves only ever fog.
    mutating func rollWeather<R: RandomNumberGenerator>(_ r: inout R) -> Bool {
        weatherAt = total
        var odds: [Weather: Int] = switch here.art {
        case .beach, .lake: [.sunny: 45, .rain: 40, .fog: 15]
        case .mountain: here.name == "얼음 산길" ? [.snow: 70, .sunny: 20, .fog: 10] : [.sunny: 45, .snow: 30, .rain: 15, .fog: 10]
        case .cave: [.sunny: 70, .fog: 30]
        default: [.sunny: 50, .rain: 30, .fog: 10, .snow: 10]
        }
        // the season tilts it: snowy winters, sunny summers, wet springs, foggy autumns
        switch season {
        case .winter: if here.art != .cave, here.art != .beach { odds[.snow, default: 0] += 30 }
        case .summer: odds[.sunny, default: 0] += 20; odds[.snow] = odds[.snow].map { $0 / 3 }
        case .spring: if here.art != .cave { odds[.rain, default: 0] += 15 }
        case .autumn: odds[.fog, default: 0] += 15
        }
        var k = Int.random(in: 0..<odds.values.reduce(0, +), using: &r), pick = Weather.sunny
        for w in Weather.allCases { if let n = odds[w] { if k < n { pick = w; break }; k -= n } }
        defer { weather = pick }
        return pick != (weather ?? .sunny)
    }

    // MARK: Pokédex
    mutating func see(_ d: Int) { if !(seen ?? []).contains(d) { seen = ((seen ?? []) + [d]).sorted() } }
    mutating func own(_ d: Int, shiny: Bool? = nil) {
        see(d); if !(owned ?? []).contains(d) { owned = ((owned ?? []) + [d]).sorted() }
        if shiny == true, !(shinyOwned ?? []).contains(d) { shinyOwned = ((shinyOwned ?? []) + [d]).sorted() }
    }
    /// Backfills the dex from what's already here (saves from before the Pokédex).
    mutating func dex() { for m in [companion] + caught + box { own(m.dex, shiny: m.shiny) } }

    // MARK: evolution
    var clock: Int { total + dayLength / 4 }                                               // step 0 = 6:00 on day 1
    var hour: Double { Double(clock % dayLength) / Double(dayLength) * 24 }
    var gameDay: Int { clock / dayLength }                                                 // 0-based
    var season: Season { Season(rawValue: gameDay / seasonDays % 4)! }
    var isDay: Bool { (4..<20).contains(hour) }                                            // HGSS morning + day; night 20-4
    func allows(_ e: Evo, _ m: Mon, _ now: Date) -> Bool {
        if let f = e.female, f != m.female { return false }
        if let t = e.time, (t == "day") != isDay { return false }
        if let i = e.item, !(bag + items).contains(i) { return false }
        if let p = e.party, !(caught + box).contains(where: { $0.dex == p }) { return false }
        if let p = e.place { switch p { case "cave": if here.art != .cave { return false }; case "forest": if here.art != .forest { return false }; default: if here.name != "얼음 산길" { return false } } }
        return true
    }
    /// What the companion becomes on this level-up, if anything. Several fits (Wurmple, Tyrogue): picked by its steps, fixed per moment.
    func levelEvolution(_ now: Date) -> Evo? {
        let m = companion
        let fits = evolutions.filter { $0.from == m.dex && ($0.way == .level && m.level >= $0.level || $0.way == .friend && (m.walked ?? 0) >= friendSteps) && allows($0, m, now) }
        return fits.isEmpty ? nil : fits[(m.walked ?? 0) % fits.count]
    }
    func stoneEvolutions(_ now: Date) -> [Evo] { evolutions.filter { $0.from == companion.dex && $0.way == .item && allows($0, companion, now) } }
    func tradeEvolution(_ now: Date) -> Evo? { evolutions.first { $0.from == companion.dex && $0.way == .trade && allows($0, companion, now) } }
    /// Items the companion could evolve with (for the W shop).
    func evolutionItems() -> [String] { Array(Set(evolutions.filter { $0.from == companion.dex }.compactMap(\.item))).sorted() }
    mutating func evolve(_ e: Evo) {
        if let i = e.item { if let k = bag.firstIndex(of: i) { bag.remove(at: k) } else if let k = items.firstIndex(of: i) { items.remove(at: k) } }
        companion.dex = e.to; own(e.to, shiny: companion.shiny)
        if e.to == 291 { _ = keep(Mon(dex: 292, level: companion.level, female: false, shiny: companion.shiny)) }   // 토중몬 -> 아이스크 leaves a 껍질몬 behind
    }

    /// Steps = keys + clicks since the last poll. Same boot and a counter that only grew => the gap (also while the app was quit) counts;
    /// anything else (reboot, logout, first run) just re-baselines.
    /// Returns true when the companion levelled up.
    @discardableResult mutating func sync(counter c: UInt32, boot b: Double, at now: Date) -> Bool {
        defer { counter = c; boot = b }
        return walk(b == boot && c >= counter ? Int(c - counter) : 0, at: now)
    }

    mutating func spend(_ w: Int) -> Bool { guard watts >= w else { return false }; watts -= w; return true }

    /// The walker's draw: rarest carried slot first, "far enough and rand(100) < chance" wins, the commonest is the fallback.
    /// chain = radar chain length: each link makes the A/B slots 25 % likelier (up to 4 links). Boosts (chain, weather) stop at 90 % so it never
    /// collapses onto one species (a 75 % B slot used to hit 100 % at 2 links and shut the rest out).
    func encounter<R: RandomNumberGenerator>(_ r: inout R, chain: Int = 0) -> Slot {
        let boost = (weather ?? .sunny).types
        for i in picks {
            let s = here.slots[i], rare = i < 4 ? 1 + 0.25 * Double(min(chain, 4)) : 1
            let boosted = s.chance * rare * (monTypes[s.dex].contains { boost.contains($0) } ? 1.5 : 1)
            let chance = boosted > s.chance ? min(boosted, max(s.chance, 90)) : s.chance
            if effSteps >= s.steps, Double.random(in: 0..<100, using: &r) < chance { return s }
        }
        return here.slots[picks[2]]
    }
    func dowse<R: RandomNumberGenerator>(_ r: inout R) -> String {
        for f in here.items { if effSteps >= f.steps, Int.random(in: 0..<100, using: &r) < f.chance { return f.item } }
        return here.items.last!.item
    }

    /// Returns false when the walker was full and it went straight to the box / bag.
    mutating func keep(_ m: Mon) -> Bool { own(m.dex, shiny: m.shiny); if caught.count < 3 { caught.append(m); return true }; box.append(m); return false }
    mutating func keep(_ i: String) -> Bool { if items.count < 3 { items.append(i); return true }; bag.append(i); return false }
    mutating func connect() { box += caught; bag += items; caught = []; items = [] }

    mutating func setCourse<R: RandomNumberGenerator>(_ i: Int, _ r: inout R) {
        connect(); course = i; courseSteps = 0; newGrass(&r)
    }
    /// Which of each group's two the grass holds: rolled on every pairing and every new game day (with the weather).
    mutating func newGrass<R: RandomNumberGenerator>(_ r: inout R) { picks = [Int.random(in: 0...1, using: &r), Int.random(in: 2...3, using: &r), Int.random(in: 4...5, using: &r)] }
    /// Walk with box[i] (or, onWalker, caught[i]) instead; the old companion takes its place. Course progress stays
    /// (the real device re-pairs and restarts the course, which just punishes trying a new partner).
    mutating func pair(_ i: Int, onWalker: Bool = false) {
        let m = onWalker ? caught[i] : box[i]
        if onWalker { caught[i] = companion } else { box[i] = companion }
        companion = m
    }
}

extension DateFormatter {
    static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = Calendar.current; f.timeZone = .current; return f }()
}

// MARK: - battle: 4 HP each; attack / evade / throw a ball / run
enum Move: Int, CaseIterable { case attack, evade, capture, run }
enum Beat: Equatable {
    case appear                                      // the encounter itself (plays before the first menu)
    case hit(crit: Bool), missed                     // our attack
    case struck, dodged                              // its attack: landed / we evaded it
    case thrown, broke, caught, fled, ran            // ball, ball broke free, got it, it ran, we ran
    case won, lost                                   // it fainted (no catch), we fainted
    var ends: Bool { [.caught, .fled, .ran, .won, .lost].contains(self) }
    var length: Double {                             // seconds on screen
        switch self {
        case .appear: 1.6
        case .broke: 2.0
        case .caught: 2.6
        case .thrown: 1.25
        case .won, .lost: 1.4
        default: 1.2
        }
    }
}
struct Battle: Equatable {
    var wild: Mon
    var wildHP = 4, myHP = 4
    var edge = 0                                     // -1 ... 2: (our level - its level) / 10; see `edge(_:_:)`
    var chain = 0                                    // radar chain this fight belongs to
    var hard = false                                 // a legend: balls work half as well

    static func edge(_ me: Int, _ it: Int) -> Int { min(2, max(-1, (me - it) / 10)) }

    /// Replays one beat's HP effect (the UI shows HP dropping mid-exchange, not all at once).
    mutating func apply(_ b: Beat) {
        if case .hit(let crit) = b { wildHP = max(0, wildHP - (crit ? 2 : 1)) }
        if b == .struck { myHP = max(0, myHP - 1) }
    }

    /// One exchange. The last beat `ends` the battle when it's over.
    mutating func act<R: RandomNumberGenerator>(_ m: Move, _ r: inout R) -> [Beat] {
        var out: [Beat] = []
        func itsTurn(evading: Bool) {
            guard Int.random(in: 0..<10, using: &r) < 5 - edge else { return }             // it attacks half the time; 30 % if we're far above it, 60 % if below
            if evading { out.append(.dodged); return }
            out.append(.struck); myHP -= 1
            if myHP <= 0 { out.append(.lost) }
        }
        switch m {
        case .run: return [.ran]
        case .attack:
            if Int.random(in: 0..<20, using: &r) < 4 - edge { out.append(.missed) }       // 20 % miss; 10 % far above, 25 % below
            else { let crit = Int.random(in: 0..<8, using: &r) == 0; wildHP -= crit ? 2 : 1; out.append(.hit(crit: crit)) }
            if wildHP <= 0 { wildHP = 0; out.append(.won); return out }
            itsTurn(evading: false)
        case .evade:
            itsTurn(evading: true)
            if Int.random(in: 0..<5, using: &r) == 0 { out.append(.fled) }
        case .capture:
            out.append(.thrown)
            if Double.random(in: 0..<1, using: &r) < Double(5 - wildHP) / (hard ? 10 : 5) { out.append(.caught); return out }   // 4 HP 20 % ... 1 HP 80 % (legends half)
            out.append(.broke)
            if Int.random(in: 0..<4, using: &r) == 0 { out.append(.fled); return out }
            itsTurn(evading: false)
        }
        return out
    }
}

// MARK: - save
enum Store {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PokeWalker", isDirectory: true)
    static let file = dir.appendingPathComponent("state.json")
    static let bak = dir.appendingPathComponent("state.json.bak")

    /// `file` first, then `bak`. An unreadable `file` is kept as `state.corrupt-<unix>.json` so the next save can't rotate it over the good `bak`.
    static func load(file: URL = Store.file, bak: URL = Store.bak) -> Walk {
        func read(_ u: URL) -> Walk? {
            guard let d = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(Walk.self, from: d), s.version == Walk().version else { return nil }
            return s
        }
        let main = read(file)
        if main == nil, FileManager.default.fileExists(atPath: file.path) {
            let corrupt = file.deletingLastPathComponent().appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: corrupt)
            NSLog("pokewalker: %@ unreadable, kept as %@", file.path, corrupt.lastPathComponent)
        }
        return main ?? read(bak) ?? Walk()
    }
    static func save(_ s: Walk, file: URL = Store.file, bak: URL = Store.bak) {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        guard let data = try? enc.encode(s) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: bak); try? fm.copyItem(at: file, to: bak)
        do { try data.write(to: file, options: .atomic) } catch { NSLog("pokewalker: save failed: %@", "\(error)") }
    }
}
