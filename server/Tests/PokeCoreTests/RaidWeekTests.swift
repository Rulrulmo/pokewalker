import Foundation
import Testing
@testable import PokeCore

// docs/plans/19 §5: the legend raid's boss by the weeks since 2026-W42, not the ISO week number (2026 has 53).

@Test func raidRotationCountsWeeks() {                                                           // plan 19 §5: no skip at 2026's W53
    var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
    func monday(_ w: Int, _ y: Int) -> Date { cal.date(from: DateComponents(hour: 12, weekday: 2, weekOfYear: w, yearForWeekOfYear: y))! }
    for w in 1...52 { #expect(raidDex(monday(w, 2026)) == raidRotation[w % 7]) }                    // as the ISO number gave, all of 2026's first 52
    let run = (0..<21).map { raidDex(monday(42, 2026).addingTimeInterval(Double($0) * 7 * 86400)) }   // W42 → 2027-W10: round and round
    #expect(run == (0..<21).map { raidRotation[$0 % 7] })
    #expect(raidDex(monday(53, 2026)) == 483 && raidDex(monday(1, 2027)) == 484)                      // 디아루가, then 펄기아 (not 가이오가)
}
