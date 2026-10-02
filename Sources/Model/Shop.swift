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
    /// The ball a throw turns out to be — all free (1.10): 몬스터볼 70 · 슈퍼볼 22 · 하이퍼볼 7.5 · 마스터볼 0.5 %, each radar chain link moving 3 points
    /// from the 몬스터볼 to the better ones (10 links and up: 40 · 38 · 20 · 2). boost = the catch multiplier (마스터볼: a sure catch).
    static func rollBall<R: RandomNumberGenerator>(chain: Int, _ r: inout R) -> (name: String, boost: Double) {
        let c = Double(min(chain, 10)), w = [70 - 3 * c, 22 + 1.6 * c, 7.5 + 1.25 * c, 0.5 + 0.15 * c]
        let balls: [(name: String, boost: Double)] = [("몬스터볼", 1), ("슈퍼볼", 1.5), ("하이퍼볼", 2), ("마스터볼", 255)]
        var k = Double.random(in: 0..<100, using: &r)
        for (b, x) in zip(balls, w) { if k < x { return b }; k -= x }
        return balls[0]
    }
    /// 1.10, once: balls bought or found before throws were free go back as W (슈퍼볼 40, 하이퍼볼 100, 힐볼 & co. 40). Returns (balls, W).
    mutating func refundBalls() -> (count: Int, watts: Int)? {
        guard ballsRefunded != true else { return nil }
        ballsRefunded = true
        let balls = Array(Set(inventory.filter { $0.hasSuffix("볼") }))
        guard !balls.isEmpty else { return nil }
        let n = (bag + items).filter { $0.hasSuffix("볼") }.count
        return (n, balls.reduce(0) { $0 + sell($1) })
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
    /// 순백떡: every EV back to 0. Used up only when there were some.
    mutating func resetEVs() -> Bool {
        guard (companion.evs ?? []).reduce(0, +) > 0, take("순백떡") else { return false }
        companion.evs = Array(repeating: 0, count: 6); return true
    }
    /// 대단한 특훈 (Gen VII's Hyper Training, at SV's Lv.50): 은색병뚜껑 makes one IV count as 31, 금색병뚜껑 all six.
    /// The IVs themselves stay (잠재파워 keeps its type). Used up only when it does something.
    static let hyperLevel = 50
    mutating func hyperTrain(_ stat: Int?) -> Bool {
        let iv = companion.effectiveIVs, todo = stat.map { [$0] } ?? Array(0..<6)
        guard companion.level >= Walk.hyperLevel, todo.contains(where: { iv[$0] < 31 }), take(stat == nil ? "금색병뚜껑" : "은색병뚜껑") else { return false }
        companion.hyper = Array(Set((companion.hyper ?? []) + todo.filter { iv[$0] < 31 })).sorted(); return true
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
    static let shop: [(item: String, watts: Int)] = [("상처약", 20), ("좋은상처약", 60), ("고급상처약", 150), ("풀회복약", 300), ("회복약", 400), ("기력의조각", 200), 
        ("해독제", 10), ("마비치료제", 20), ("잠깨는약", 25), ("화상치료제", 25), ("얼음상태치료제", 25), ("만병통치제", 60), ("PP에이드", 120),
        ("플러스파워", 50), ("디펜드업", 55), ("스페셜업", 35), ("스페셜가드", 35), ("스피드업", 35), ("잘-맞히기", 95), ("크리티컬커터", 65), ("이펙트가드", 70),
        ("맥스업", 100), ("타우린", 100), ("사포닌", 100), ("리보플라빈", 100), ("키토산", 100), ("알칼로이드", 100),
        ("유석열매", 20), ("시마열매", 20), ("파비열매", 20), ("로매열매", 20), ("또뽀열매", 20), ("토망열매", 20), ("순백떡", 200)]
    static let bpShop: [(item: String, bp: Int)] = [("고급상처약", 3), ("풀회복약", 5), ("회복약", 6), ("부활초", 6), ("PP에이더", 4), ("PP맥스", 8), ("이상한사탕", 8),
        ("맥스업", 1), ("타우린", 1), ("사포닌", 1), ("리보플라빈", 1), ("키토산", 1), ("알칼로이드", 1), ("은색병뚜껑", 25), ("금색병뚜껑", 120)]
    /// Two legends for the patient: 칠색조 for a full tank of watts (9,999 is the cap), 뮤츠 for 300 BP (~30 tower sets). As often as you can pay (a shiny, better IVs).
    static let legendShop: [(dex: Int, level: Int, watts: Int, bp: Int)] = [(250, 50, 9999, 0), (150, 70, 0, 300)]
    func legendBought(_ dex: Int) -> Bool { (bought ?? []).contains("legend:\(dex)") }
    mutating func buyLegend(_ i: Int) -> Mon? {
        let l = Walk.legendShop[i]
        guard watts >= l.watts, (bp ?? 0) >= l.bp else { return nil }
        watts -= l.watts; bp = (bp ?? 0) - l.bp; if !legendBought(l.dex) { bought = (bought ?? []) + ["legend:\(l.dex)"] }
        var g = SystemRandomNumberGenerator(); let m = Mon.wild(l.dex, level: l.level, shiny: Int.random(in: 0..<shinyOdds, using: &g) == 0 ? true : nil, perfect: 3, &g); _ = keep(m); return m   // legends: 3 IVs at 31, a shiny now and then
    }
    /// Evolution items for the companion, sold in the 상점 (HGSS traded them for Pokéathlon points).
    static let evoItemPrice = 1000

    /// One row of the 상점 (W) or the BP 교환소.
    struct Ware: Equatable {
        enum Kind: Equatable { case item(String), legend(Int), shell(String) }   // legend = Walk.legendShop index; shell = a device colour's name
        var kind: Kind; var price: Int
        var once: Bool { if case .item = kind { return false }; return true }              // one at a time, with 정말 살까? (a device colour also only ever once)
    }
    enum Bought: Equatable { case items(String, Int), legend(Mon), shell(String) }
    /// The rows, in order: the goods, then (상점) the companion's evolution items, then the once-only ones. `shells` = the device colours sold for BP.
    func wares(bp: Bool, shells: [(name: String, bp: Int)]) -> [Ware] {
        if bp {
            return Walk.bpShop.map { Ware(kind: .item($0.item), price: $0.bp) } + shells.map { Ware(kind: .shell($0.name), price: $0.bp) }
                + Walk.legendShop.indices.filter { Walk.legendShop[$0].bp > 0 }.map { Ware(kind: .legend($0), price: Walk.legendShop[$0].bp) }
        }
        return Walk.shop.map { Ware(kind: .item($0.item), price: $0.watts) } + evolutionItems().map { Ware(kind: .item($0), price: Walk.evoItemPrice) }
            + Walk.legendShop.indices.filter { Walk.legendShop[$0].watts > 0 }.map { Ware(kind: .legend($0), price: Walk.legendShop[$0].watts) }
    }
    func wareName(_ w: Ware) -> String {
        switch w.kind { case .item(let i): i; case .legend(let k): monNames[Walk.legendShop[k].dex] + " (전설)"; case .shell(let s): s + " (기기 색)" }
    }
    func wareNote(_ w: Ware) -> String {
        switch w.kind { case .item(let i): ItemKind.of(i).summary; case .legend(let k): "Lv.\(Walk.legendShop[k].level) · 3V · 여러 번 살 수 있어요"; case .shell: "기기 색 바꾸기 · 한 번만" }
    }
    /// How many are carried (once-only: 1 when bought).
    func owned(_ w: Ware) -> Int {
        switch w.kind { case .item(let i): count(i); case .legend: 0; case .shell(let s): (bought ?? []).contains(s) ? 1 : 0 }   // a legend can be bought again
    }
    /// How many of it can be bought right now: what the money covers, up to 99 at a time (once-only: 0 or 1).
    func canBuy(_ w: Ware, bp useBP: Bool) -> Int {
        let money = useBP ? bp ?? 0 : watts, n = w.price > 0 ? money / w.price : 99
        return w.once ? (owned(w) == 0 && n >= 1 ? 1 : 0) : min(99, n)
    }
    /// Buys n at once; nil when it can't (not enough, or once-only and already had).
    mutating func purchase(_ w: Ware, _ n: Int, bp useBP: Bool) -> Bought? {
        guard n >= 1, n <= canBuy(w, bp: useBP) else { return nil }
        switch w.kind {
        case .item(let i):
            if useBP { bp = (bp ?? 0) - w.price * n } else { watts -= w.price * n }
            bag += Array(repeating: i, count: n); return .items(i, n)
        case .legend(let k): return buyLegend(k).map { .legend($0) }
        case .shell(let s): bp = (bp ?? 0) - w.price; bought = (bought ?? []) + [s]; return .shell(s)
        }
    }

    // MARK: Battle Tower: 3 against a trainer's 3, 50 W to enter, BP per win
    static let towerFee = 50
    /// The party: the companion and the two strongest others (walker + box) — or the player's own (towerPick), whoever of it is still here, topped up the same way.
    /// ref -1 = companion, -2-i = caught[i], i = box[i].
    func party() -> [(ref: Int, mon: Mon)] {
        let others = caught.enumerated().map { (-2 - $0.offset, $0.element.points) } + box.enumerated().map { ($0.offset, $0.element.points) }
        var refs: [Int] = []
        for r in (towerPick ?? []).compactMap({ ref(uid: $0) }) + [-1] + others.sorted(by: { $0.1 > $1.1 }).map(\.0) where refs.count < 3 && !refs.contains(r) { refs.append(r) }
        return refs.map { (ref: $0, mon: mon($0)!) }
    }
    /// Who can go up the tower, for the lobby's picker: everyone (the companion, the walker's, the box) by level, then dex number (EXP alone would reorder it every step).
    var towerCandidates: [Int] {
        let all = [-1] + caught.indices.map { -2 - $0 } + Array(box.indices), key = all.map { r in let m = mon(r)!; return (-m.level, m.dex) }
        return all.indices.sorted { key[$0] != key[$1] ? key[$0] < key[$1] : $0 < $1 }.map { all[$0] }
    }
    /// The lobby's picker: the one at `r` goes in party slot `slot` (one already in the party swaps places with it). The recommended party again = no pick.
    mutating func towerSet(_ slot: Int, _ r: Int) {
        var refs = party().map(\.ref)
        guard refs.indices.contains(slot), mon(r) != nil else { return }
        if let j = refs.firstIndex(of: r) { refs.swapAt(slot, j) } else { refs[slot] = r }
        towerPick = nil
        if refs != party().map(\.ref) { towerPick = refs.compactMap { id($0) } }
    }
    /// Writes a fight's EXP back to whoever took part, found by uid wherever they are now (gone or evolved = skipped), and queues what they learn.
    mutating func writeBack(_ uids: [Int], _ mons: [Mon]) {
        for (u, m) in zip(uids, mons) {
            guard let r = ref(uid: u), let old = mon(r), old.dex == m.dex else { continue }
            var m = m; m.uid = u; setMon(r, m); queueMoves(r, from: old.level)
        }
    }
    /// The uid of the one at `ref`, handing one out the first time.
    mutating func id(_ ref: Int) -> Int? {
        guard var m = mon(ref) else { return nil }
        if m.uid == nil { lastUID = (lastUID ?? 0) + 1; m.uid = lastUID; setMon(ref, m) }
        return m.uid
    }
    /// Where that one is now: -1 companion, -2-i caught[i], i box[i].
    func ref(uid: Int) -> Int? {
        if companion.uid == uid { return -1 }
        if let i = caught.firstIndex(where: { $0.uid == uid }) { return -2 - i }
        return box.firstIndex { $0.uid == uid }
    }
    func mon(_ ref: Int) -> Mon? { ref == -1 ? companion : ref <= -2 ? caught[safe: -2 - ref] : box[safe: ref] }
    mutating func setMon(_ ref: Int, _ m: Mon) { if ref == -1 { companion = m } else if ref <= -2 { caught[-2 - ref] = m } else { box[ref] = m } }
    /// Moves the one at `ref` reached since level `lv`, waiting to be learned (see `learning`).
    mutating func queueMoves(_ ref: Int, from lv: Int) {
        guard let m = mon(ref), m.level > lv else { return }
        let new = m.newMoves(from: lv, to: m.level)
        guard !new.isEmpty, let u = id(ref) else { return }
        learning = (learning ?? []) + new.flatMap { [u, $0] }
    }
    /// The first queued move whose Pokémon is still here (queued ones for released Pokémon are dropped): where it is, and the move.
    mutating func nextToLearn() -> (ref: Int, move: Int)? {
        while let q = learning, q.count >= 2 { if let r = ref(uid: q[0]) { return (r, q[1]) }; learning = Array(q.dropFirst(2)) }
        return nil
    }
    mutating func learned() { if let q = learning, q.count >= 2 { learning = Array(q.dropFirst(2)) } }
    /// The tower is Lv.50 (docs/plans/09): ours over 50 fight as 50 (under it, as they are); its trainers' are 50, better every 7 wins.
    static let towerLevel = 50
    /// By wins so far, 7 a tier: 0 as caught · 1 IVs 15+ · 2 + EVs 252/252 · 3 3V, a fitting nature, 좋은 4개, AI less random · 4 5V, AI never random · 5 6V, base stats 450+.
    static func towerTier(_ streak: Int) -> Int { min(5, streak / 7) }
    static let towerAIRandom = [5, 5, 5, 10, 0, 0]                                                   // Battle.aiRandom per tier
    /// The next trainer: 3 fully evolved non-legends at Lv.50, stronger by tier (towerTier).
    func towerFoes<R: RandomNumberGenerator>(_ r: inout R) -> (trainer: String, foes: [Mon]) {
        let tier = Walk.towerTier(towerStreak ?? 0), lv = Walk.towerLevel
        let legends = Set(courses.flatMap(\.legends) + Walk.legendShop.map(\.dex))           // shop legends too: never a tower foe
        let names = ["엘리트 트레이너", "베테랑", "아가씨", "등산가", "연구원", "격투가", "사이킥", "드래곤 조련사", "모범 소년", "레인저"]
        let he = ["민수", "현우", "도윤", "준호", "태양"], she = ["지은", "서연", "하은", "유나", "보라"]      // a one-sex class gets a name to match (its sprite: trainerFrame)
        let pool = (1...493).filter { d in !legends.contains(d) && d != 292 && !evolutions.contains { $0.from == d } && (tier < 5 || baseStats[d].reduce(0, +) >= 450) }   // fully evolved
        let foes = (0..<3).map { _ -> Mon in
            let d = pool.randomElement(using: &r)!, phys = baseStats[d][1] >= baseStats[d][3]           // 물리형 or 특수형
            var m = Mon.wild(d, level: lv, perfect: [0, 0, 0, 3, 5, 6][tier], &r)
            if (1...2).contains(tier) { m.ivs = (0..<6).map { _ in Int.random(in: 15...31, using: &r) } }
            if tier >= 2 { var ev = [0, 0, 0, 0, 0, 0]; ev[phys ? 1 : 3] = 252; ev[5] = 252; if tier >= 3 { ev[0] = 6 }; m.evs = ev }
            if tier >= 3 {
                m.nature = (phys ? [3, 13] : [15, 10]).randomElement(using: &r)!                 // 고집 · 명랑 / 조심 · 겁쟁이
                m.known = m.towerMoves()
            }
            return m
        }
        let cls = names.randomElement(using: &r)!, given = cls == "아가씨" ? she : ["등산가", "연구원", "드래곤 조련사", "모범 소년"].contains(cls) ? he : he + she
        return (cls + " " + given.randomElement(using: &r)!, foes)
    }
    /// A win: streak + 1, BP = 1 (+1 per full 7 already won), +3 on every 7th. Returns the BP.
    mutating func towerWin() -> Int {
        let s = (towerStreak ?? 0) + 1; towerStreak = s; towerBest = max(towerBest ?? 0, s)
        let g = 1 + (s - 1) / 7 + (s % 7 == 0 ? 3 : 0); bp = (bp ?? 0) + g; return g
    }
    mutating func towerEnd() { towerBest = max(towerBest ?? 0, towerStreak ?? 0); towerStreak = 0 }

}
