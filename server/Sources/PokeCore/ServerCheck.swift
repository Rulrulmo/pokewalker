import Foundation

// docs/plans/10-anti-cheat.md §2: what's implausible about a save — its own values, and the change from the last save the server took.
// [] = nothing. The server logs and records what it finds (flags); CHECK_MODE=reject refuses the save instead (10 §5 R, after a few days of logs).
// The rules use the app's own game code and data (Game/: courses, shops, items, species), so they read the save as the app does.

enum SaveCheck {
    static let stepsPerSecond = 15, daySteps = 100_000, awaySlack = 3_000
    static let secondsPerLink = 20, secondsPerTowerFight = 30, maxBPPerWin = 4, stepsPerFind = 150

    static func mons(_ w: Walk) -> [Mon] { [w.companion] + w.caught + w.box }

    /// Things no play can make (10 §2.1).
    static func values(_ w: Walk) -> [String] {
        var out: [String] = []
        func bad(_ s: String) { if !out.contains(s) { out.append(s) } }
        for m in mons(w) {
            guard (1...493).contains(m.dex) else { bad("species \(m.dex)"); continue }
            if !(1...100).contains(m.level) { bad("level \(m.level)") }
            if let iv = m.ivs, iv.count != 6 || iv.contains(where: { !(0...31).contains($0) }) { bad("IVs \(iv)") }
            if let ev = m.evs, ev.count != 6 || ev.contains(where: { !(0...255).contains($0) }) || ev.reduce(0, +) > 510 { bad("EVs \(ev)") }
            if let n = m.nature, !(0..<25).contains(n) { bad("nature \(n)") }
            if let a = m.ability, !(0..<abilitySlots[m.dex].count).contains(a) { bad("ability slot \(a) of #\(m.dex)") }
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
    static let knownItems: Set<String> = {
        var s = Set<String>(courses.flatMap { (c: Course) -> [String] in c.items.map(\.item) })
        s.formUnion(Walk.shop.map(\.item)); s.formUnion(Walk.bpShop.map(\.item)); s.formUnion(evolutions.compactMap(\.item))
        s.formUnion(["몬스터볼", "슈퍼볼", "하이퍼볼", "달의돌"])
        return s
    }()

    /// The change from `old` (the last save the server took) to `new`, `seconds` apart on the server's clock (10 §2.2). minted: new Pokémon the
    /// server issued in between (level 2; until then nil, and a time bound stands in).
    static func changes(from old: Walk, to new: Walk, seconds: Int, minted: Int? = nil) -> [String] {
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
        let links = dt / secondsPerLink, linkBonus = 2 * max(10, new.bestChain ?? 0)     // a chain link pays 2 × its length; one at most every 20 s

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
        if found > max(0, steps) / stepsPerFind + links / 5 + 1 { out.append("\(found) items found in \(steps) steps") }
        let budget = min(9999, old.watts + max(0, earned) + links * linkBonus + sales + releases)
        if new.watts + wCost > budget { out.append("W \(old.watts) → \(new.watts) (+\(wCost) spent in shops) over what came in (\(budget))") }
        let bpIn = (dt / secondsPerTowerFight) * maxBPPerWin + 3
        if (new.bp ?? 0) + bpCost > (old.bp ?? 0) + bpIn { out.append("BP \(old.bp ?? 0) → \(new.bp ?? 0) (+\(bpCost) spent) in \(dt) s") }

        // new Pokémon: issued by the server (level 2), or at most one per 20 s
        let oldUIDs = Set(mons(old).compactMap(\.uid))
        let fresh = kept.filter { m in m.uid.map { !oldUIDs.contains($0) } ?? !mons(old).contains(m) }.count
        if fresh > (minted ?? dt / 20 + 1) { out.append("\(fresh) new Pokémon in \(dt) s") }
        return out
    }
}
