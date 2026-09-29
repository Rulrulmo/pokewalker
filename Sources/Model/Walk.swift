import Foundation
// The saved state and the walker's rules: steps, watts, companion events, radar draws, box, weather, dex, evolution.

/// An egg carried on the walker: hatches after `left` more steps (egg cycles x 255, Gen IV).
struct Egg: Codable, Equatable { var dex: Int; var left: Int }
enum PetFind: Equatable { case item(String), egg(Int) }
let legendOdds = (base: 0.02, perChain: 0.01)          // a legend course's radar: 2 % + 1 % per chain link (up to 4)

/// Everything the device remembers, plus the "game" side (box/bag) that Connect sends things to.
struct Walk: Codable, Equatable {
    var version = 1
    var companion = Mon(dex: 25, level: 5, female: false)
    var course = 0
    var courseSteps = 0                    // since the course was set; gates the rarer slots and items
    var today = 0, total = 0, watts = 0, earned = 0     // earned = lifetime watts (unlocks courses); watts = spendable, max 9999
    var remainder = 0                      // steps towards the next watt (20 per watt)
    var day = ""                           // yyyy-MM-dd that `today` belongs to
    var history: [Int] = []                // previous days' steps, newest first, max 7 (missed days = 0)
    var days = 1                           // days walked with this device
    var caught: [Mon] = [], items: [String] = []        // on the walker, max 3 each
    var box: [Mon] = [], bag: [String] = []             // sent back by Connect; overflow goes straight here
    var learning: [Int]? = nil                          // moves waiting to be learned: (uid, move) pairs
    var lastUID: Int? = nil
    var counter: UInt32 = 0, boot: Double = 0           // system input-event counter at the last poll, and the boot it belongs to
    var seen: [Int]? = nil, owned: [Int]? = nil         // Pokédex, sorted; Optional so older saves decode (see `dex()`)
    var shinyOwned: [Int]? = nil                        // species ever owned as 이로치 (the dex shows those colours too)
    var weather: Weather? = nil, weatherAt: Int? = nil  // nil = sunny; total steps at the last roll
    var nextEvent: Int? = nil                           // total steps of the companion's next little event
    var egg: Egg? = nil
    var bestChain: Int? = nil
    var bp: Int? = nil, towerStreak: Int? = nil, towerBest: Int? = nil   // Battle Tower points, current and best win streak
    var bought: [String]? = nil                                        // one-off BP buys (device colours)

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
        let lv = companion.level
        guard companion.gain(n) else { return false }
        queueMoves(-1, from: lv); return true
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
        let m = Mon.wild(egg!.dex, level: 1, shiny: Int.random(in: 0..<shinyOdds, using: &r) == 0 ? true : nil, &r)
        egg = nil; _ = keep(m); return m
    }
    /// On a legend course the radar sometimes turns up one you don't have yet.
    func legend<R: RandomNumberGenerator>(_ r: inout R, chain: Int) -> Int? {
        let left = here.legends.filter { !(owned ?? []).contains($0) }
        guard !left.isEmpty, Double.random(in: 0..<1, using: &r) < legendOdds.base + legendOdds.perChain * Double(min(chain, 4)) else { return nil }
        return left.randomElement(using: &r)
    }

    // MARK: radar chains
    /// After a catch / KO at chain length `chain`, does the grass rustle again? 85 %, then 8 points less per link, never under 35 %.
    static func chainGoesOn(_ chain: Int) -> Double { max(0.35, 0.85 - 0.08 * Double(chain)) }
    /// The reward for reaching link `n`: 2n watts, and every 5th link the course's rarest item. Returns the item, if any.
    mutating func chainReward(_ n: Int) -> String? {
        watts = min(9999, watts + 2 * n); bestChain = max(bestChain ?? 0, n)
        guard n % 5 == 0 else { return nil }
        let i = here.items[0].item; _ = keep(i); return i
    }
    /// IVs sure to be 31 at chain length `chain` (like Gen VII's SOS chains, scaled to how rarely a chain here gets long): 3 → 1, 5 → 2, 7 → 3, 9 → 4.
    static func chainPerfectIVs(_ chain: Int) -> Int { chain >= 9 ? 4 : chain >= 7 ? 3 : chain >= 5 ? 2 : chain >= 3 ? 1 : 0 }
    /// 1/128 at the start, x(1 + n/2) better per link, capped at 10 links (1/21). 1/(128/(2n+1)) handed out 이로치 far too easily.
    static func chainShinyOdds(_ chain: Int) -> Int { let better: Double = 1 + 0.5 * Double(min(chain, 10)); return Int(Double(shinyOdds) / better) }

    // MARK: box
    /// Which box entries of that species 중복 놓아주기 lets go: all but the 이로치, the 3V-and-up ones, and the single best —
    /// most V, then most EXP (not the IV total: that would trade a Lv.60 for any fresh catch, and old ones' 15s aren't a real roll).
    func duplicates(of dex: Int) -> [Int] {
        func rank(_ m: Mon) -> (Int, Int) { (m.perfectIVs, m.points) }
        let plain = box.indices.filter { box[$0].dex == dex && box[$0].shiny != true }
        guard let best = plain.max(by: { rank(box[$0]) < rank(box[$1]) }) else { return [] }
        return plain.filter { $0 != best && box[$0].perfectIVs < 3 }
    }
    /// Lets duplicates(of:) go. Returns (how many, watts).
    mutating func releaseDuplicates(of dex: Int) -> (count: Int, watts: Int) {
        var n = 0, w = 0
        for i in duplicates(of: dex).sorted(by: >) { w += release(i); n += 1 }                              // from the back, so indices stay valid
        return (n, w)
    }
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
        if companion.known == nil { companion.known = companion.moves }
        companion.dex = e.to; own(e.to, shiny: companion.shiny)
        queueMoves(-1, from: companion.level - 1)                                                  // the new form's move at this level
        if e.to == 291 { var g = SystemRandomNumberGenerator(), m = Mon.wild(292, level: companion.level, shiny: companion.shiny, &g); m.known = companion.known; _ = keep(m) }   // 토중몬 -> 아이스크 leaves a 껍질몬 behind
    }

    /// Steps = keys + clicks since the last poll. Same boot and a counter that only grew => the gap (also while the app was quit) counts;
    /// anything else (reboot, logout, first run) just re-baselines.
    /// Returns true when the companion levelled up.
    @discardableResult mutating func sync(counter c: UInt32, boot b: Double, at now: Date) -> Bool {
        defer { counter = c; boot = b }
        return walk(b == boot && c >= counter ? Int(c - counter) : 0, at: now)
    }

    mutating func spend(_ w: Int) -> Bool { guard watts >= w else { return false }; watts -= w; return true }

    /// The draw: 10 % a habitat guest; else the walker's own order, rarest group first — "some of its candidates are far enough and
    /// rand(100) < their mean chance" picks the group — and then any candidate of it that's far enough, the weather's types 1.5x as likely.
    /// chain = radar chain length: +20 % per link on the A/B groups (up to 8 links), stopping at 90 % so no group shuts the rest out.
    func encounter<R: RandomNumberGenerator>(_ r: inout R, chain: Int = 0, guests: Bool = true) -> Slot {
        if guests, !here.guests.isEmpty, Double.random(in: 0..<1, using: &r) < guestOdds {       // a visitor, at the C group's level + 2
            return Slot(dex: here.guests.randomElement(using: &r)!, level: here.slots[4].level + 2, steps: 0, chance: 100, female: Bool.random(using: &r))
        }
        let boost = (weather ?? .sunny).types
        func pick(_ c: [Slot]) -> Slot {
            let w = c.map { monTypes[$0.dex].contains { boost.contains($0) } ? 1.5 : 1.0 }
            var k = Double.random(in: 0..<w.reduce(0, +), using: &r)
            for (s, x) in zip(c, w) { if k < x { return s }; k -= x }
            return c.last!
        }
        for g in 0..<2 {
            let c = here.group(g).filter { effSteps >= $0.steps }
            guard !c.isEmpty else { continue }
            let mean = c.map(\.chance).reduce(0, +) / Double(c.count)
            if Double.random(in: 0..<100, using: &r) < min(mean * (1 + 0.2 * Double(min(chain, 8))), max(mean, 90)) { return pick(c) }
        }
        return pick(here.group(2).filter { effSteps >= $0.steps })
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
        connect(); course = i; courseSteps = 0
    }
    /// Walk with box[i] (or, onWalker, caught[i]) instead; the old companion takes its place. Course progress stays
    /// (the real device re-pairs and restarts the course, which just punishes trying a new partner).
    mutating func pair(_ i: Int, onWalker: Bool = false) {
        let m = onWalker ? caught[i] : box[i]
        if onWalker { caught[i] = companion } else { box[i] = companion }
        companion = m
    }
}
