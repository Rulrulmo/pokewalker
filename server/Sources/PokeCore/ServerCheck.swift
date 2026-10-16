import Foundation

// docs/plans/10-anti-cheat.md §2: what's implausible about a save — its own values, and the change from the last save the server took.
// [] = nothing. The server logs and records what it finds (flags); CHECK_MODE=reject refuses the save instead (10 §5 R, after a few days of logs).
// The rules use the app's own game code and data (Game/: courses, shops, items, species), so they read the save as the app does.

enum SaveCheck {
    static let stepsPerSecond = 15, daySteps = 100_000, awaySlack = 3_000
    static let secondsPerLink = 20, secondsPerTowerFight = 30, maxBPPerWin = 4, stepsPerFind = 150

    static func mons(_ w: Walk) -> [Mon] { let all = [w.companion] + w.caught + w.box; return all + all.flatMap { $0.fused ?? [] } }   // (5.0: a 큐레무's partner too)

    /// Things no play can make (10 §2.1).
    static func values(_ w: Walk) -> [String] {
        var out: [String] = []
        func bad(_ s: String) { if !out.contains(s) { out.append(s) } }
        for m in mons(w) {
            guard (1...dexMax).contains(m.dex) else { bad("species \(m.dex)"); continue }
            if let f = m.form, !(Content.gen6 && (1...(monForms[m.dex]?.count ?? 0)).contains(f)) { bad("form \(f) of #\(m.dex)") }   // 5.0
            if let x = m.fused, !(Content.gen6 && m.dex == 646 && x.count == 1 && [643, 644].contains(x[0].dex) && x[0].fused == nil && m.form == (x[0].dex == 643 ? 2 : 1)) { bad("fused into #\(m.dex)") }
            if !(1...100).contains(m.level) { bad("level \(m.level)") }
            if let iv = m.ivs, iv.count != 6 || iv.contains(where: { !(0...31).contains($0) }) { bad("IVs \(iv)") }
            if let ev = m.evs, ev.count != 6 || ev.contains(where: { !(0...255).contains($0) }) || ev.reduce(0, +) > 510 { bad("EVs \(ev)") }
            if let n = m.nature, !(0..<25).contains(n) { bad("nature \(n)") }
            if let a = m.ability, !(0..<abilitySlots[m.dex].count).contains(a), !(Content.gen6 && a == 2 && hiddenAbility[m.dex] > 0) { bad("ability slot \(a) of #\(m.dex)") }   // (5.0: 2 = hidden)
            if let h = m.hyper, h.contains(where: { !(0...5).contains($0) }) || m.level < 50 { bad("hyper training \(h) at Lv.\(m.level)") }
        }
        let uids = mons(w).compactMap(\.uid)
        if Set(uids).count != uids.count { bad("a uid twice") }
        if let top = uids.max(), top > (w.lastUID ?? 0) { bad("uid \(top) above lastUID \(w.lastUID ?? 0)") }
        if !(0...9999).contains(w.watts) { bad("watts \(w.watts)") }
        if (w.bp ?? 0) < 0 { bad("BP \(w.bp ?? 0)") }
        if w.earned < 0 || w.total < 0 || w.today < 0 { bad("negative counts") }
        if w.caught.count > 3 || w.items.count > 3 { bad("more than 3 on the walker") }
        if let e = w.egg, !eggPool.contains(e.dex) { bad("an egg of #\(e.dex)") }
        if !(0..<courses.count).contains(w.course) { bad("course \(w.course)") } else if !w.unlocked(w.course) { bad("course \(w.course) not unlocked") }
        for i in Set(w.items + w.bag) where !knownItems.contains(i) { bad("item \(i)") }
        return out
    }
    /// Every item a save can hold: finds and chain rewards (the courses), the shops, evolution items, and 1.x's balls (1.10 refunded them).
    static var knownItems: Set<String> { Content.gen6 ? knownItemsGen6 : knownItemsGen4 }
    /// 5.0: the new courses' finds, the catalog, Gen V–VI's held items, the evolution items of Gen V–VI, the stones and orbs, the important ones.
    static let knownItemsGen6: Set<String> = knownItemsGen4.union(coursesGen6.flatMap { $0.items.map(\.item) }).union(Walk.heldBPGen6.map(\.item)).union(Walk.heldWGen6.map(\.item))
        .union(evolutionsGen6.compactMap(\.item)).union(Forms.stones).union(ItemKind.keys).union(Held.drives.keys)
        .union(Walk.bpShop51.map(\.item)).union(Walk.shop51.map(\.item))                                   // 5.1 (plan 19): 특성패치, 그라시데아꽃
    static let knownItemsGen4: Set<String> = {
        var s = Set<String>(coursesGen4.flatMap { (c: Course) -> [String] in c.items.map(\.item) })
        s.formUnion(Walk.shopGen4.map(\.item)); s.formUnion(Walk.bpShop.map(\.item)); s.formUnion(evolutionsGen4.compactMap(\.item))
        s.formUnion(["몬스터볼", "슈퍼볼", "하이퍼볼", "달의돌"])
        return s
    }()

    /// The change from `old` (the last save the server took) to `new`, `seconds` apart on the server's clock (10 §2.2). granted: what the server
    /// handed out in between (10 §4: a chain's W and reward items, less a radar fee or a legend's price) — exact, where a 2.0 save gets a bound
    /// from the time (a link every 20 s) and a cap on new Pokémon (2.1's are checked against what was issued instead).
    static func changes(from old: Walk, to new: Walk, seconds: Int, granted: (watts: Int, bp: Int, items: [String])? = nil) -> [String] {
        var out: [String] = []
        let dt = max(0, seconds), steps = new.total - old.total
        if steps < 0 { out.append("total went down \(old.total) → \(new.total)") }
        if steps > dt * stepsPerSecond + 600 { out.append("\(steps) steps in \(dt) s") }
        if steps > (dt / 86_400 + 1) * (daySteps + awaySlack) || new.today > daySteps + awaySlack { out.append("over a day's steps (\(new.today) today, +\(steps))") }
        let earned = new.earned - old.earned
        if earned > (max(0, steps) + 19) / 20 + 1 { out.append("+\(earned) earned W for \(steps) steps") }

        // what came and went: items (as a multiset) and box Pokémon (by uid, else by value)
        func count(_ a: [String]) -> [String: Int] { a.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
        let was = count(old.items + old.bag), now = count(new.items + new.bag)
        var gone: [String: Int] = [:], came: [String: Int] = [:]
        for (k, n) in was where n > (now[k] ?? 0) { gone[k] = n - (now[k] ?? 0) }
        for (k, n) in now where n > (was[k] ?? 0) { came[k] = n - (was[k] ?? 0) }
        let sales = gone.reduce(0) { s, e in if case .sell(let p) = ItemKind.of(e.key) { s + p * e.value } else { s } }
        let kept = mons(new), keptUIDs = Set(kept.compactMap(\.uid))
        let released = old.box.filter { m in m.uid.map { !keptUIDs.contains($0) } ?? !kept.contains(m) }
        let releases = released.reduce(0) { $0 + max(1, $1.level / 2) }
        let links = dt / secondsPerLink + 1, linkBonus = 2 * max(10, new.bestChain ?? 0) // a chain link pays 2 × its length: one per 20 s, and one in any save (saves come seconds apart after actions)

        // items: a find (the courses' tables, chain rewards) comes free; a shop item costs W, a BP-shop item BP
        let finds = Set<String>(courses.flatMap { (c: Course) -> [String] in c.items.map(\.item) }), wPrice = Dictionary(Walk.shop.map { ($0.item, $0.watts) }, uniquingKeysWith: min)
        let bpPrice = Dictionary(Walk.bpShop.map { ($0.item, $0.bp) }, uniquingKeysWith: min)
        var found = 0, wCost = 0, bpCost = 0
        for (k, n) in came {
            if finds.contains(k) { found += n }
            else if let p = wPrice[k] { wCost += p * n }
            else if let p = bpPrice[k] { bpCost += p * n }
            else if evolutions.contains(where: { $0.item == k }) { wCost += Walk.evoItemPrice * n }
            else { found += n }
        }
        let rewards = granted.map { $0.items.count } ?? links / 5, chainW = granted.map(\.watts) ?? links * linkBonus
        if found > max(0, steps) / stepsPerFind + rewards + 1 { out.append("\(found) items found in \(steps) steps") }
        let budget = min(9999, old.watts + max(0, earned) + chainW + sales + releases)
        if new.watts + wCost > budget { out.append("W \(old.watts) → \(new.watts) (+\(wCost) spent in shops) over what came in (\(budget))") }
        let bpIn = (dt / secondsPerTowerFight) * maxBPPerWin + 3 + (granted?.bp ?? 0)
        if (new.bp ?? 0) + bpCost > (old.bp ?? 0) + bpIn { out.append("BP \(old.bp ?? 0) → \(new.bp ?? 0) (+\(bpCost) spent) in \(dt) s") }

        // new Pokémon (2.0 saves): at most one per 20 s; 2.1's are checked against what was issued (SaveDB.mintProblems)
        if granted == nil {
            let oldUIDs = Set(mons(old).compactMap(\.uid))
            let fresh = kept.filter { m in m.uid.map { !oldUIDs.contains($0) } ?? !mons(old).contains(m) }.count
            if fresh > dt / 20 + 1 { out.append("\(fresh) new Pokémon in \(dt) s") }
        }
        return out
    }
}
