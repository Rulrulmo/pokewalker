import Foundation
// Using items, the shops and the Battle Tower.

extension Walk {
    // MARK: using items (walker's 3 first, then the bag)
    func count(_ i: String) -> Int { (items + bag).filter { $0 == i }.count }
    mutating func take(_ i: String) -> Bool {
        if let k = items.firstIndex(of: i) { items.remove(at: k); return true }
        if let k = bag.firstIndex(of: i) { bag.remove(at: k); return true }
        return false
    }
    var inventory: [String] { Array(Set(items + bag)).sorted() }
    /// The smallest potion that fills the gap, else the biggest there is. Used up.
    mutating func useHeal(missing: Int) -> (item: String, hp: Int)? {
        let heals = inventory.compactMap { i -> (String, Int)? in if case .heal(let n) = ItemKind.of(i) { return (i, n) }; return nil }.sorted { $0.1 < $1.1 }
        guard let pick = heals.first(where: { $0.1 >= missing }) ?? heals.last, take(pick.0) else { return nil }
        return (pick.0, min(pick.1, missing))
    }
    mutating func useRevive() -> (item: String, pct: Int)? {
        let r = inventory.compactMap { i -> (String, Int)? in if case .revive(let n) = ItemKind.of(i) { return (i, n) }; return nil }.sorted { $0.1 < $1.1 }
        guard let pick = r.first, take(pick.0) else { return nil }                              // the cheaper one first
        return pick
    }
    mutating func useBall() -> (item: String, boost: Double)? {
        let b = inventory.compactMap { i -> (String, Double)? in if case .ball(let x) = ItemKind.of(i) { return (i, x) }; return nil }.sorted { $0.1 > $1.1 }
        guard let pick = b.first, take(pick.0) else { return nil }
        return pick
    }
    mutating func feedCandy() -> Bool {
        guard companion.level < 100, take("이상한사탕") else { return false }
        let e = expTable[growthRate[companion.dex]][companion.level + 1], lv = companion.level
        if companion.known == nil { companion.known = companion.moves }
        companion.exp = e; companion.level = Mon.level(dex: companion.dex, exp: e); queueMoves(-1, from: lv); return true          // levels, not steps: friendship untouched
    }
    /// Gen IV: a vitamin adds 10 while that stat is under 100 (and the total under 510); an EV berry drops it to 100, then 10 at a time.
    /// Used up only when it does something. Returns the new EV.
    mutating func feedVitamin(_ i: String) -> Int? {
        guard case .vitamin(let k, let d) = ItemKind.of(i) else { return nil }
        var ev = companion.evs ?? Array(repeating: 0, count: 6); let e = ev[k]
        let new = d > 0 ? min(100, e + min(10, 510 - ev.reduce(0, +))) : e > 100 ? 100 : max(0, e - 10)
        guard d > 0 ? e < 100 && new > e : e > 0, take(i) else { return nil }
        ev[k] = new; companion.evs = ev; return new
    }
    mutating func feedBerry(_ i: String) -> Bool {
        guard ItemKind.of(i) == .berry, take(i) else { return false }
        companion.walked = (companion.walked ?? 0) + 500; return true
    }
    /// Sells every one of `i`; returns the watts.
    mutating func sell(_ i: String) -> Int {
        guard case .sell(let p) = ItemKind.of(i) else { return 0 }
        var n = 0; while take(i) { n += 1 }
        watts = min(9999, watts + n * p); return n * p
    }

    // MARK: shops
    static let shop: [(item: String, watts: Int)] = [("상처약", 20), ("좋은상처약", 60), ("고급상처약", 150), ("풀회복약", 300), ("회복약", 400), ("기력의조각", 200), ("슈퍼볼", 40), ("하이퍼볼", 100),
        ("해독제", 10), ("마비치료제", 20), ("잠깨는약", 25), ("화상치료제", 25), ("얼음상태치료제", 25), ("만병통치제", 60), ("PP에이드", 120),
        ("플러스파워", 50), ("디펜드업", 55), ("스페셜업", 35), ("스페셜가드", 35), ("스피드업", 35), ("잘-맞히기", 95), ("크리티컬커터", 65), ("이펙트가드", 70),
        ("맥스업", 100), ("타우린", 100), ("사포닌", 100), ("리보플라빈", 100), ("키토산", 100), ("알칼로이드", 100),
        ("유석열매", 20), ("시마열매", 20), ("파비열매", 20), ("로매열매", 20), ("또뽀열매", 20), ("토망열매", 20)]
    static let bpShop: [(item: String, bp: Int)] = [("하이퍼볼", 2), ("고급상처약", 3), ("풀회복약", 5), ("회복약", 6), ("부활초", 6), ("PP에이더", 4), ("PP맥스", 8), ("이상한사탕", 8),
        ("맥스업", 1), ("타우린", 1), ("사포닌", 1), ("리보플라빈", 1), ("키토산", 1), ("알칼로이드", 1)]
    /// Two legends for the patient: 칠색조 for a full tank of watts (9,999 is the cap), 뮤츠 for 300 BP (~30 tower sets). Once each.
    static let legendShop: [(dex: Int, level: Int, watts: Int, bp: Int)] = [(250, 50, 9999, 0), (150, 70, 0, 300)]
    func legendBought(_ dex: Int) -> Bool { (bought ?? []).contains("legend:\(dex)") }
    mutating func buyLegend(_ i: Int) -> Mon? {
        let l = Walk.legendShop[i]
        guard !legendBought(l.dex), watts >= l.watts, (bp ?? 0) >= l.bp else { return nil }
        watts -= l.watts; bp = (bp ?? 0) - l.bp; bought = (bought ?? []) + ["legend:\(l.dex)"]
        var g = SystemRandomNumberGenerator(); let m = Mon.wild(l.dex, level: l.level, &g); _ = keep(m); return m
    }
    mutating func buy(_ item: String, watts price: Int) -> Bool { guard spend(price) else { return false }; bag.append(item); return true }
    mutating func buy(_ item: String, bp price: Int) -> Bool { guard (bp ?? 0) >= price else { return false }; bp = (bp ?? 0) - price; bag.append(item); return true }

    // MARK: Battle Tower: 3 against a trainer's 3, 50 W to enter, BP per win
    static let towerFee = 50
    /// The party: the companion and the two strongest others (walker + box). ref -1 = companion, -2-i = caught[i], i = box[i].
    func party() -> [(ref: Int, mon: Mon)] {
        let others = caught.enumerated().map { (-2 - $0.offset, $0.element) } + box.enumerated().map { ($0.offset, $0.element) }
        return [(-1, companion)] + others.sorted { $0.1.points > $1.1.points }.prefix(2).map { (ref: $0.0, mon: $0.1) }
    }
    /// Writes a fight's EXP back to whoever took part (skips a ref that no longer points at the same species), and queues what they learn.
    mutating func writeBack(_ refs: [Int], _ mons: [Mon]) {
        for (r, m) in zip(refs, mons) { guard let old = mon(r), old.dex == m.dex else { continue }; setMon(r, m); queueMoves(r, from: old.level) }
    }
    func mon(_ ref: Int) -> Mon? { ref == -1 ? companion : ref <= -2 ? caught[safe: -2 - ref] : box[safe: ref] }
    mutating func setMon(_ ref: Int, _ m: Mon) { if ref == -1 { companion = m } else if ref <= -2 { caught[-2 - ref] = m } else { box[ref] = m } }
    /// Moves the one at `ref` reached since level `lv`, waiting to be learned (see `learn`).
    mutating func queueMoves(_ ref: Int, from lv: Int) {
        guard let m = mon(ref), m.level > lv else { return }
        learn = (learn ?? []) + m.newMoves(from: lv, to: m.level).flatMap { [ref, $0] }
    }
    /// The next trainer: 3 non-legends at the party's average level + streak / 3 (+0-2), fully evolved from Lv.30.
    func towerFoes<R: RandomNumberGenerator>(_ r: inout R) -> (trainer: String, foes: [Mon]) {
        let ps = party().map(\.mon), avg = ps.map(\.level).reduce(0, +) / max(1, ps.count)
        let legends = Set(courses.flatMap(\.legends) + Walk.legendShop.map(\.dex))           // shop legends too: never a tower foe
        let names = ["엘리트 트레이너", "베테랑", "아가씨", "등산가", "연구원", "격투가", "사이킥", "드래곤 조련사", "모범 소년", "레인저"]
        let given = ["민수", "지은", "현우", "서연", "도윤", "하은", "준호", "유나", "태양", "보라"]
        let foes = (0..<3).map { _ -> Mon in
            let lv = min(100, max(5, avg + (towerStreak ?? 0) / 3 + Int.random(in: 0...2, using: &r)))
            let pool = (1...493).filter { d in !legends.contains(d) && d != 292 && (stageOf[d] == 0 || stageOf[d] == 1 && lv >= 20 || stageOf[d] >= 2 && lv >= 35)
                                              && (lv < 30 || !evolutions.contains { $0.from == d }) }
            return Mon.wild(pool.randomElement(using: &r)!, level: lv, &r)
        }
        return (names.randomElement(using: &r)! + " " + given.randomElement(using: &r)!, foes)
    }
    /// A win: streak + 1, BP = 1 (+1 per full 7 already won), +3 on every 7th. Returns the BP.
    mutating func towerWin() -> Int {
        let s = (towerStreak ?? 0) + 1; towerStreak = s; towerBest = max(towerBest ?? 0, s)
        let g = 1 + (s - 1) / 7 + (s % 7 == 0 ? 3 : 0); bp = (bp ?? 0) + g; return g
    }
    mutating func towerEnd() { towerBest = max(towerBest ?? 0, towerStreak ?? 0); towerStreak = 0 }

}
