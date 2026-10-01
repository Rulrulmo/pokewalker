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
    var syncedAt: Double? = nil                          // when that poll was (seconds since 2001): the gap while the app was quit
    var seen: [Int]? = nil, owned: [Int]? = nil         // Pokédex, sorted; Optional so older saves decode (see `dex()`)
    var shinyOwned: [Int]? = nil                        // species ever owned as 이로치 (the dex shows those colours too)
    var weather: Weather? = nil, weatherAt: Int? = nil  // nil = sunny; total steps at the last roll
    var nextEvent: Int? = nil                           // total steps of the companion's next little event
    var egg: Egg? = nil
    var bestChain: Int? = nil
    var bp: Int? = nil, towerStreak: Int? = nil, towerBest: Int? = nil   // Battle Tower points, current and best win streak
    var towerPick: [Int]? = nil                                        // the tower party the player chose (uids, the lead first); nil = the recommended one
    var evolving: [Int]? = nil                                         // uids of ours (not the companion) that levelled in a fight: they evolve once home
    var audited: Int? = nil, corrected: Bool? = nil                    // 1.7's one-time check ran; it took back a macro's gains (the trainer card says so)
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
        let i = courseItem(&r); _ = keep(i); return .item(i)
    }
    var hatchDue: Bool { (egg?.left ?? 1) <= 0 }
    mutating func hatch<R: RandomNumberGenerator>(_ r: inout R) -> Mon {
        let m = Mon.wild(egg!.dex, level: 1, shiny: Int.random(in: 0..<shinyOdds, using: &r) == 0 ? true : nil, &r)
        egg = nil; _ = keep(m); return m
    }
    /// On a legend course the radar sometimes turns up one you don't have yet.
    func legend<R: RandomNumberGenerator>(_ r: inout R, chain: Int) -> Int? {
        let all = here.legends, left = all.filter { !(owned ?? []).contains($0) }
        guard !all.isEmpty else { return nil }
        let odds = (legendOdds.base + legendOdds.perChain * Double(min(chain, 4))) * (left.isEmpty ? 0.5 : 1)   // all caught: they still turn up, half as often (a shiny, better IVs)
        guard Double.random(in: 0..<1, using: &r) < odds else { return nil }
        return (left.isEmpty ? all : left).randomElement(using: &r)                             // the ones not caught yet first
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
    /// What the companion (or the one at ref) becomes on this level-up, if anything. Several fits (Wurmple, Tyrogue): picked by its steps, fixed per moment.
    func levelEvolution(_ now: Date, ref: Int = -1) -> Evo? {
        guard let m = mon(ref) else { return nil }
        let fits = evolutions.filter { $0.from == m.dex && ($0.way == .level && m.level >= $0.level || $0.way == .friend && (m.walked ?? 0) >= friendSteps) && allows($0, m, now) }
        return fits.isEmpty ? nil : fits[(m.walked ?? 0) % fits.count]
    }
    func stoneEvolutions(_ now: Date) -> [Evo] { evolutions.filter { $0.from == companion.dex && $0.way == .item && allows($0, companion, now) } }
    func tradeEvolution(_ now: Date) -> Evo? { evolutions.first { $0.from == companion.dex && $0.way == .trade && allows($0, companion, now) } }
    /// Items the companion could evolve with (for the W shop).
    func evolutionItems() -> [String] { Array(Set(evolutions.filter { $0.from == companion.dex }.compactMap(\.item))).sorted() }
    mutating func evolve(_ e: Evo, ref: Int = -1) {
        guard var m = mon(ref) else { return }
        if let i = e.item { if let k = bag.firstIndex(of: i) { bag.remove(at: k) } else if let k = items.firstIndex(of: i) { items.remove(at: k) } }
        if m.known == nil { m.known = m.moves }                                                    // its moves stay (the new form's defaults would replace them)
        m.dex = e.to; setMon(ref, m); own(e.to, shiny: m.shiny)
        queueMoves(ref, from: m.level - 1)                                                         // the new form's move at this level
        if e.to == 291 { var g = SystemRandomNumberGenerator(), s = Mon.wild(292, level: m.level, shiny: m.shiny, &g); s.known = m.known; _ = keep(s) }   // 토중몬 -> 아이스크 leaves a 껍질몬 behind
    }

    /// Steps = keys + clicks since the last poll. Same boot and a counter that only grew => the gap (also while the app was quit) counts;
    /// anything else (reboot, logout, first run) just re-baselines.
    /// Returns true when the companion levelled up.
    @discardableResult mutating func sync(counter c: UInt32, boot b: Double, at now: Date, away: Bool = false) -> Bool {
        let gap = syncedAt.map { now.timeIntervalSinceReferenceDate - $0 } ?? 3600
        let n = take(counter: c, boot: b, at: now)
        return walk(roomToday(away ? min(n, Int(max(0, gap) / 3600 * 3000)) : n), at: now)   // away = typed while the app was quit: at most 3,000 an hour count
    }
    static let dayCap = 100_000                                        // steps a day at most: more than anyone types (a macro would; StepGate stops most)
    /// n steps, less whatever would take today past dayCap.
    func roomToday(_ n: Int) -> Int { max(0, min(n, Walk.dayCap - today)) }
    /// Once at launch (1.7: a macro's earnings; 1.8: an edited file's contradictions). A save that earned more W than its days allow (100,000 steps =
    /// 5,000 W a day, + 2,000 for chains and sales) is a macro's; one that holds more W than it ever earned, more 칠색조 than its W could buy (9,999
    /// each), or values no game makes (IVs over 31, EVs over 255 / 510, levels outside 1-100, unknown species) was edited. Then W goes to 0, the
    /// 칠색조 beyond what was really paid for go (the best stay: 이로치, IVs, EXP; a 칠색조 companion hands over first) and impossible values are
    /// put back in range. Returns how many 칠색조 went and whether it was a macro's (nil: the save was fine, or already checked).
    mutating func audit() -> (gone: Int, macro: Bool)? {
        let from = audited ?? 0
        guard from < 2 else { return nil }
        audited = 2
        let price = Walk.legendShop[0].watts, dex = Walk.legendShop[0].dex, macroBudget = days * Walk.dayCap / 20 + 2_000
        let macro = from < 1 && earned > macroBudget
        let budget = macro ? macroBudget : earned + 2_000                                          // the W this save could really have spent
        let refs = ([-1] + caught.indices.map { -2 - $0 } + Array(box.indices)).filter { mon($0)?.dex == dex }
        let fixed = repairValues()
        guard macro || fixed || watts > earned + 3_000 || refs.count * price > budget else { return nil }
        watts = 0; corrected = true
        func rank(_ m: Mon) -> (Int, Int, Int) { (m.shiny == true ? 1 : 0, m.perfectIVs, m.points) }
        let gone = refs.sorted { rank(mon($0)!) > rank(mon($1)!) }.dropFirst(budget / price)
        if gone.contains(-1) {                                                                    // the companion goes: the first other one walks
            if let i = caught.indices.first(where: { !gone.contains(-2 - $0) }) { pair(i, onWalker: true); return (audit(removing: gone.map { $0 == -1 ? -2 - i : $0 }), macro) }
            if let i = box.indices.first(where: { !gone.contains($0) }) { let m = box[i]; box[i] = companion; companion = m; return (audit(removing: gone.map { $0 == -1 ? i : $0 }), macro) }
            return (audit(removing: gone.filter { $0 != -1 }), macro)                              // no one else: it stays
        }
        return (audit(removing: Array(gone)), macro)
    }
    /// Values no game makes, back in range; true if any was out.
    mutating func repairValues() -> Bool {
        var out = false
        func fix(_ m: inout Mon) {
            if !(1...493).contains(m.dex) { m.dex = 25; out = true }
            if !(1...100).contains(m.level) { m.level = max(1, min(100, m.level)); m.exp = nil; out = true }
            if let iv = m.ivs, iv.count != 6 || iv.contains(where: { !(0...31).contains($0) }) { m.ivs = (0..<6).map { max(0, min(31, iv[safe: $0] ?? 0)) }; out = true }
            if let ev = m.evs, ev.count != 6 || ev.contains(where: { !(0...255).contains($0) }) || ev.reduce(0, +) > 510 { m.evs = Array(repeating: 0, count: 6); out = true }
            if let n = m.nature, !(0..<25).contains(n) { m.nature = 0; out = true }
        }
        fix(&companion); for i in caught.indices { fix(&caught[i]) }; for i in box.indices { fix(&box[i]) }
        if watts > 9999 || watts < 0 { watts = max(0, min(9999, watts)); out = true }
        return out
    }
    private mutating func audit(removing refs: [Int]) -> Int {
        for i in refs.filter({ $0 >= 0 }).sorted(by: >) { box.remove(at: i) }                     // from the back, so indices hold (no W for these)
        for r in refs.filter({ $0 <= -2 }).sorted() { caught.remove(at: -2 - r) }                 // -2 - i from the largest i down
        return refs.count
    }
    /// The raw keys + clicks since the last poll (the baseline moves on); 0 after a reboot / a counter that went back.
    mutating func take(counter c: UInt32, boot b: Double, at now: Date) -> Int {
        defer { counter = c; boot = b; syncedAt = now.timeIntervalSinceReferenceDate }
        return b == boot && c >= counter ? Int(c - counter) : 0
    }

    mutating func spend(_ w: Int) -> Bool { guard watts >= w else { return false }; watts -= w; return true }

    /// The draw: 10 % a habitat guest; else the walker's own order, rarest group first — "some of its candidates are far enough and
    /// rand(100) < their mean chance" picks the group — and then any candidate of it that's far enough, the weather's types 1.5x as likely.
    /// chain = radar chain length: +20 % per link on the A/B groups (up to 8 links), stopping at 90 % so no group shuts the rest out.
    func encounter<R: RandomNumberGenerator>(_ r: inout R, chain: Int = 0, guests: Bool = true) -> Slot {
        if guests, !here.guests.isEmpty, Double.random(in: 0..<1, using: &r) < guestOdds {       // a visitor, at the C group's level + 2
            let d = here.guests.randomElement(using: &r)!
            return Slot(dex: d, level: here.slots[4].level + 2, steps: 0, chance: 100, female: Int.random(in: 0..<8, using: &r) < genderRate[d])   // by its species' ratio (genderless / male-only: never)
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
    /// One of the course's 10 items (what the companion picks up): rarest first, by the course's steps.
    func courseItem<R: RandomNumberGenerator>(_ r: inout R) -> String {
        for f in here.items { if effSteps >= f.steps, Int.random(in: 0..<100, using: &r) < f.chance { return f.item } }
        return here.items.last!.item
    }

    /// Returns false when the walker was full and it went straight to the box / bag.
    mutating func keep(_ m: Mon) -> Bool { own(m.dex, shiny: m.shiny); box.append(m); return false }   // every catch / hatch / buy goes to the box: the walker takes only who the player sends (워커로)
    mutating func keep(_ i: String) -> Bool { if items.count < 3 { items.append(i); return true }; bag.append(i); return false }
    /// One of the walker's to the box (포켓몬's 상자로 보내기).
    mutating func store(_ i: Int) { box.append(caught.remove(at: i)) }
    /// One of the box's back onto the walker (while it holds fewer than 3).
    mutating func fetch(_ i: Int) { guard caught.count < 3, box.indices.contains(i) else { return }; caught.append(box.remove(at: i)) }

    mutating func setCourse<R: RandomNumberGenerator>(_ i: Int, _ r: inout R) {
        course = i; courseSteps = 0                                                              // the walker's team and items come along
    }
    /// Walk with box[i] (or, onWalker, caught[i]) instead; the old companion takes its place on the walker, or goes to the box's end
    /// (the box stays in arrival order: the 상자 grid's 최근). Course progress stays (the real device re-pairs and restarts the course,
    /// which just punishes trying a new partner).
    mutating func pair(_ i: Int, onWalker: Bool = false) {
        let m = onWalker ? caught[i] : box[i]
        if onWalker { caught[i] = companion } else { box.remove(at: i); box.append(companion) }
        companion = m
    }
}
