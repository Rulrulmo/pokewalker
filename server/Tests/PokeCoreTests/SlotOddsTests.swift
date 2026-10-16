import Foundation
import Testing
@testable import PokeCore

// docs/plans/21 (slot-odds): a course's Pokémon without steps — the group by share (A 20 · B 30 · C 50 %, a radar chain moving C's to A and B),
// every slot from the first step; off, the walker's own steps gates and mean chances exactly as before.

private struct SlotRNG: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }

/// The group (0 A · 1 B · 2 C) of a draw on course c, nil for a guest.
private func groupOf(_ s: Slot, _ c: Course) -> Int? { (0..<3).first { g in c.group(g).contains { $0.dex == s.dex && $0.level == s.level } } }

@Test func slotOddsShares() {
    #expect(Walk.groupShares(0) == [20, 30, 50] && Walk.groupShares(8) == [52, 38, 10] && Walk.groupShares(20) == Walk.groupShares(8) && Walk.groupShares(-1) == [20, 30, 50])
    #expect((0...12).allSatisfy { Walk.groupShares($0).reduce(0, +) == 100 && Walk.groupShares($0).allSatisfy { $0 > 0 } })
}

@Test func slotOddsDraw() {
    Content.$testing.withValue(true) {
        let k = courses.firstIndex { $0.name == "칼로스 산" }!                                    // A at 10,000 steps, B at 3,000
        var w = Walk(); w.course = k; w.courseSteps = 0
        var r = SlotRNG(s: 21), n = [0, 0, 0]
        Content.$testingSlots.withValue(true) {
            for _ in 0..<20_000 { n[groupOf(w.encounter(&r, guests: false), w.here)!] += 1 }
        }
        #expect(abs(n[0] - 4_000) < 300 && abs(n[1] - 6_000) < 300 && abs(n[2] - 10_000) < 300)   // 20 · 30 · 50 % on the first step
        n = [0, 0, 0]
        Content.$testingSlots.withValue(true) {
            for _ in 0..<20_000 { n[groupOf(w.encounter(&r, chain: 8, guests: false), w.here)!] += 1 }
        }
        #expect(abs(n[0] - 10_400) < 300 && abs(n[1] - 7_600) < 300 && abs(n[2] - 2_000) < 300)   // 8 links: 52 · 38 · 10
        var g = 0
        Content.$testingSlots.withValue(true) { for _ in 0..<10_000 where groupOf(w.encounter(&r), w.here) == nil { g += 1 } }
        #expect(abs(g - 1_000) < 150)                                                             // the guests' 10 % first, as before
        n = [0, 0, 0]                                                                              // off: the steps gate A and B as before
        for _ in 0..<5_000 { n[groupOf(w.encounter(&r, guests: false), w.here)!] += 1 }
        #expect(n[0] == 0 && n[1] == 0)
        w.courseSteps = 10_000; n = [0, 0, 0]
        for _ in 0..<20_000 { n[groupOf(w.encounter(&r, guests: false), w.here)!] += 1 }
        #expect(n[0] > 9_000)                                                                      // (A's mean 50 %: the rarest the commonest, the user's point)
    }
}

@Test func slotOddsSwitch() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    #expect(try await db.slotOdds() == false)
    _ = try await db.setSlotOdds(true); #expect(try await db.slotOdds() == true)
    _ = try await db.setSlotOdds(false); #expect(try await db.slotOdds() == false)
}

// ENC_SIM=1: per course, a day's radar finds (ENC_RATE a 1,000 steps, default 5; each a chain going on at Walk.chainGoesOn) at 10,000 and
// 30,000 steps — as now (moved there that morning: courseSteps from 0; settled: every gate open) and with slot-odds — the guests · A · B · C,
// the 이로치 by group (expected, Walk.chainShinyOdds), and the finds until the course's 12 slot species are all seen (from courseSteps 0).
@Test func encounterSim() {
    let env = ProcessInfo.processInfo.environment
    guard env["ENC_SIM"] != nil else { return }
    let rate = Double(env["ENC_RATE"] ?? "") ?? 5, days = Int(env["ENC_DAYS"] ?? "") ?? 200
    Content.$testing.withValue(true) {
        var r = SlotRNG(s: 2026_10_16)
        struct Day { var n = [0.0, 0.0, 0.0, 0.0]; var shiny = [0.0, 0.0, 0.0, 0.0] }     // guests, A, B, C
        func day(_ k: Int, steps: Int, from: Int, slots: Bool) -> Day {
            var w = Walk(); w.course = k; var d = Day()
            let finds = Int(Double(steps) * rate / 1000)
            var chain = 0
            for j in 0..<finds {
                w.courseSteps = from + Int((Double(j) + 0.5) * 1000 / rate)
                let s = Content.$testingSlots.withValue(slots) { w.encounter(&r, chain: chain) }
                let g = groupOf(s, w.here).map { $0 + 1 } ?? 0
                d.n[g] += 1; d.shiny[g] += 1 / Double(Walk.chainShinyOdds(chain))
                chain = Walk.chainContinues(chain, &r) ? chain + 1 : 0
            }
            return d
        }
        func mean(_ k: Int, steps: Int, from: Int, slots: Bool) -> Day {
            var t = Day()
            for _ in 0..<days { let d = day(k, steps: steps, from: from, slots: slots); for i in 0..<4 { t.n[i] += d.n[i] / Double(days); t.shiny[i] += d.shiny[i] / Double(days) } }
            return t
        }
        func complete(_ k: Int, slots: Bool) -> Double {                                       // finds until all 12 slot species are seen
            var total = 0.0
            for _ in 0..<days {
                var w = Walk(); w.course = k; var seen = Set<Int>(), f = 0, chain = 0
                let want = Set(w.here.all.map(\.dex))
                while !want.isSubset(of: seen), f < 5_000 {
                    w.courseSteps = Int((Double(f) + 0.5) * 1000 / rate)
                    seen.insert(Content.$testingSlots.withValue(slots) { w.encounter(&r, chain: chain) }.dex); f += 1
                    chain = Walk.chainContinues(chain, &r) ? chain + 1 : 0
                }
                total += Double(f)
            }
            return total / Double(days)
        }
        func abc(_ d: Day) -> String { d.n[1...3].map { String(format: "%5.1f", $0) }.joined(separator: " ") }
        print("ENCSIM rate \(rate)/1k steps, \(days) days each; per day: A B C (guests apart) — now moved-in | now settled | slot-odds; then 이로치 A share, finds to see all 12")
        var sum = [String: [Double]]()
        for k in courses.indices {
            let c = courses[k]
            for steps in [10_000, 30_000] {
                let a = mean(k, steps: steps, from: 0, slots: false), b = mean(k, steps: steps, from: 1_000_000, slots: false), n = mean(k, steps: steps, from: 0, slots: true)
                let sa = a.shiny[1] / max(1e-9, a.shiny[1...3].reduce(0, +)), sn = n.shiny[1] / max(1e-9, n.shiny[1...3].reduce(0, +))
                print("ENCSIM \(c.name) \(steps / 1000)k: " + abc(a) + " | " + abc(b) + " | " + abc(n) + String(format: " | 이로치 A %.0f%% → %.0f%%", 100 * sa, 100 * sn))
                for (key, d) in [("now\(steps)", a), ("settled\(steps)", b), ("new\(steps)", n)] { sum[key, default: [0, 0, 0, 0]] = zip(sum[key, default: [0, 0, 0, 0]], d.n).map { $0 + $1 / Double(courses.count) } }
            }
            print("ENCSIM \(c.name) gates A \(c.group(0).map(\.steps).max()!) B \(c.group(1).map(\.steps).max()!) · all 12 seen after " + String(format: "%.0f → %.0f finds", complete(k, slots: false), complete(k, slots: true)))
        }
        for key in ["now10000", "settled10000", "new10000", "now30000", "settled30000", "new30000"] {
            let d = sum[key]!; print("ENCSIM mean \(key): guests " + String(format: "%.1f", d[0]) + " · A B C " + d[1...3].map { String(format: "%.1f", $0) }.joined(separator: " "))
        }
    }
}
