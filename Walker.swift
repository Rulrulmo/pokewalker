import Foundation

// MARK: - course data (instances in the generated Data.swift)
struct Slot { let dex, level, steps: Int; let chance: Double; let female: Bool }   // steps = min course steps before it can appear
struct Find { let item: String; let steps, chance: Int }
enum Art { case field, forest, mountain, beach, lake, town, cave }
struct Course { let name: String; let watts: Int; let types: [String]; let art: Art; let slots: [Slot]; let items: [Find] }   // slots: A A B B C C, items rarest first

struct Mon: Codable, Equatable { var dex: Int; var level: Int; var female: Bool }

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

    var here: Course { courses[course] }
    /// A companion of one of the course's 3 types needs 25 % fewer steps: same as walking 4/3 as far.
    var bonus: Bool { monTypes[companion.dex].contains { here.types.contains($0) } }
    var effSteps: Int { bonus ? courseSteps * 4 / 3 : courseSteps }
    func unlocked(_ i: Int) -> Bool { earned >= courses[i].watts }

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

    mutating func walk(_ n: Int, at now: Date) {
        rollover(now)
        guard n > 0 else { return }
        today += n; total += n; courseSteps += n; remainder += n
        let w = remainder / 20; remainder %= 20
        watts = min(9999, watts + w); earned += w
    }

    /// Steps = keys + clicks since the last poll. Same boot and a counter that only grew => the gap (also while the app was quit) counts;
    /// anything else (reboot, logout, first run) just re-baselines.
    mutating func sync(counter c: UInt32, boot b: Double, at now: Date) {
        walk(b == boot && c >= counter ? Int(c - counter) : 0, at: now)
        counter = c; boot = b
    }

    mutating func spend(_ w: Int) -> Bool { guard watts >= w else { return false }; watts -= w; return true }

    /// The walker's draw: rarest carried slot first, "far enough and rand(100) < chance" wins, the commonest is the fallback.
    func encounter<R: RandomNumberGenerator>(_ r: inout R) -> Slot {
        for i in picks { let s = here.slots[i]; if effSteps >= s.steps, Double.random(in: 0..<100, using: &r) < s.chance { return s } }
        return here.slots[picks[2]]
    }
    func dowse<R: RandomNumberGenerator>(_ r: inout R) -> String {
        for f in here.items { if effSteps >= f.steps, Int.random(in: 0..<100, using: &r) < f.chance { return f.item } }
        return here.items.last!.item
    }

    /// Returns false when the walker was full and it went straight to the box / bag.
    mutating func keep(_ m: Mon) -> Bool { if caught.count < 3 { caught.append(m); return true }; box.append(m); return false }
    mutating func keep(_ i: String) -> Bool { if items.count < 3 { items.append(i); return true }; bag.append(i); return false }
    mutating func connect() { box += caught; bag += items; caught = []; items = [] }

    mutating func setCourse<R: RandomNumberGenerator>(_ i: Int, _ r: inout R) {
        connect(); course = i; courseSteps = 0
        picks = [Int.random(in: 0...1, using: &r), Int.random(in: 2...3, using: &r), Int.random(in: 4...5, using: &r)]
    }
    /// Walk with box[i] instead; the old companion goes into the box. A new pairing, so the course restarts too.
    mutating func pair<R: RandomNumberGenerator>(_ i: Int, _ r: inout R) {
        let m = box.remove(at: i); box.insert(companion, at: i); companion = m
        setCourse(course, &r)
    }
}

extension DateFormatter {
    static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = Calendar.current; f.timeZone = .current; return f }()
}

// MARK: - battle: 4 HP each; attack / evade / throw a ball / run
enum Move: Int, CaseIterable { case attack, evade, capture, run }
enum Beat: Equatable {
    case hit(crit: Bool), missed                     // our attack
    case struck, dodged                              // its attack: landed / we evaded it
    case thrown, broke, caught, fled, ran            // ball, ball broke free, got it, it ran, we ran
    case won, lost                                   // it fainted (no catch), we fainted
    var ends: Bool { [.caught, .fled, .ran, .won, .lost].contains(self) }
}
struct Battle: Equatable {
    var wild: Mon
    var wildHP = 4, myHP = 4

    /// One exchange. The last beat `ends` the battle when it's over.
    mutating func act<R: RandomNumberGenerator>(_ m: Move, _ r: inout R) -> [Beat] {
        var out: [Beat] = []
        func itsTurn(evading: Bool) {
            guard Int.random(in: 0..<2, using: &r) == 0 else { return }                    // it attacks half the time
            if evading { out.append(.dodged); return }
            out.append(.struck); myHP -= 1
            if myHP <= 0 { out.append(.lost) }
        }
        switch m {
        case .run: return [.ran]
        case .attack:
            if Int.random(in: 0..<5, using: &r) == 0 { out.append(.missed) }
            else { let crit = Int.random(in: 0..<8, using: &r) == 0; wildHP -= crit ? 2 : 1; out.append(.hit(crit: crit)) }
            if wildHP <= 0 { wildHP = 0; out.append(.won); return out }
            itsTurn(evading: false)
        case .evade:
            itsTurn(evading: true)
            if Int.random(in: 0..<5, using: &r) == 0 { out.append(.fled) }
        case .capture:
            out.append(.thrown)
            if Double.random(in: 0..<1, using: &r) < Double(5 - wildHP) / 5 { out.append(.caught); return out }   // 4 HP 20 % ... 1 HP 80 %
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
