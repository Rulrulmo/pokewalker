import Foundation
import Testing
@testable import PokeCore

// docs/plans/20 (5.1, raid-daily): both raids by the day — 2칸 at 0:00 and 1 a 10,000 steps, gone at the next; the bosses each day; 10 runs
// a day; the lobby's ends · next · today.max; a run only from a lobby fetched since 0:00 (or a Mega boss named by dex and form).

private let base = Date(timeIntervalSince1970: 2_000_000_000)                                   // 2033-05-18, a Wednesday
private var cal: Calendar { var c = Calendar(identifier: .iso8601); c.timeZone = .current; return c }
private func noon(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: base))!.addingTimeInterval(12 * 3600) }

@Test func raidDailyPower() {
    Content.$testingDaily.withValue(true) {
        var w = Walk(); w.rollover(noon(0))
        #expect(w.raidPower == 20_000)                                                            // a day's 2칸
        w.walk(35_000, at: noon(0)); #expect(w.raidPower == 55_000)
        w.walk(90_000, at: noon(0)); #expect(w.raidPower == Engine.raidPowerMax && Engine.raidPowerMax == 100_000)   // 10칸 at most
        w.raidPower = 30_000; w.rollover(noon(1)); #expect(w.raidPower == 20_000)                // yesterday's gone: 2칸 again
    }
    var w = Walk(); w.raidPower = 30_000; w.rollover(noon(1))                                   // off: banked as before (3칸 at most)
    #expect(w.raidPower == 30_000 && Engine.raidPowerMax == 30_000)
}

@Test func raidDailyBosses() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    try await db.sql("INSERT INTO settings (name, value) VALUES ('content5_since', :v)", ["v": .text(String(Int(noon(-3).timeIntervalSince1970)))])
    try await Content.$testing.withValue(true) {
        try await Content.$testingDaily.withValue(true) {
            let week = (0..<7).map { raidDex(noon($0)) }
            #expect(Set(week) == Set(raidRotation) && raidDex(noon(7)) == week[0])               // 7 in 7 days, then again
            #expect(raidDex(cal.startOfDay(for: noon(1)).addingTimeInterval(-1)) == week[0] && raidDex(cal.startOfDay(for: noon(1))) == week[1])   // at 0:00
            let m0 = await db.megaWeek(noon(0)), m1 = await db.megaWeek(noon(1))
            #expect(m0 == MegaRaid.week(3) && m1 == MegaRaid.week(4) && m0.count == 2)            // the 4th day since content5's: its 4th pair
            #expect(raidEnds(noon(0)) == Int(cal.startOfDay(for: noon(1)).timeIntervalSince1970) && raidNext(noon(0)) == noon(1))
        }
        let m = await db.megaWeek(noon(0))                                                         // off: by the week
        #expect(m == MegaRaid.week(MegaRaid.round(noon(0), from: noon(-3), cal)))
    }
}

@Test func raidDailyLobbyAndStart() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    let s = try #require(string(await db.create(CreateReq(id: "앨리스", device: "mac", device_name: "MAC", app: "5.0", pin: "2468"), now: Int(noon(0).timeIntervalSince1970)), "session"))
    try await db.setRaidRunsFrom(0)
    try await db.sql("INSERT INTO settings (name, value) VALUES ('content5_since', :v)", ["v": .text(String(Int(noon(-3).timeIntervalSince1970)))])
    try await Content.$testing.withValue(true) {
        try await Content.$testingDaily.withValue(true) {
            // the legend raid: no lobby fetched today → refused; fetched → a boss; tomorrow → refused again until fetched
            var x = try await db.raidStart("앨리스", tier: 1, app: "5.0", now: noon(0))
            #expect(x.why == raidStaleWhy && x.boss == nil)
            let r = await db.raidLobby(RaidReq(id: "앨리스", session: s, app: "5.0"), now: noon(0))
            let l = try JSONDecoder().decode(RaidLobby.self, from: r.body)
            #expect(l.today.max == 10 && l.ends == raidEnds(noon(0)) && l.next == raidDex(noon(1)) && l.boss.dex == raidDex(noon(0)))
            let keys = Set((try JSONSerialization.jsonObject(with: r.body) as? [String: Any] ?? [:]).keys)   // 5.0.1 stops on a missing one (the Mac)
            #expect(["week", "boss", "next", "ends", "today", "resetAt", "mine", "runs", "friends", "tiers"].allSatisfy(keys.contains))
            x = try await db.raidStart("앨리스", tier: 1, app: "5.0", now: noon(0))
            #expect(x.why == nil && x.boss?.boss.dex == raidDex(noon(0)))
            x = try await db.raidStart("앨리스", tier: 1, app: "5.0", now: noon(1))
            #expect(x.why == raidStaleWhy)
            // the Mega raid: 0 / 1 of a stale lobby refused; named by (dex, form) one of today's goes, another day's is refused
            let today = await db.megaWeek(noon(1))
            var y = try await db.raidStart("앨리스", tier: 1, app: "5.0", now: noon(1), mega: 1)
            #expect(y.why == raidStaleWhy)
            y = try await db.raidStart("앨리스", tier: 1, app: "5.1", now: noon(1), mega: 0, megaDex: (today[1].dex, today[1].form))
            #expect(y.why == nil && y.boss?.mega == today[1].form && y.boss?.boss.dex == today[1].dex)   // (0 sent, its own named)
            let yesterday = await db.megaWeek(noon(0))
            let other = yesterday.first { b in !today.contains { $0.dex == b.dex && $0.form == b.form } }!
            y = try await db.raidStart("앨리스", tier: 1, app: "5.1", now: noon(1), mega: 0, megaDex: (other.dex, other.form))
            #expect(y.why == raidStaleWhy)
            let ml = try JSONDecoder().decode(MegaRaidLobby.self, from: await db.raidLobby(RaidReq(id: "앨리스", session: s, app: "5.0", kind: "mega"), now: noon(1)).body)
            let tomorrow = await db.megaWeek(noon(2))
            #expect(ml.bosses.count == 2 && ml.today.max == 10 && ml.ends == raidEnds(noon(1)) && ml.next.map(\.stone) == tomorrow.map(\.stone))
            y = try await db.raidStart("앨리스", tier: 1, app: "5.0", now: noon(1), mega: 1)
            #expect(y.why == nil && y.boss?.boss.dex == today[1].dex)
            // 10 runs a day
            for _ in 0..<10 { try await db.sql("INSERT INTO raid_runs (week, key, day, tier, boss, party, at, ended_at, kind) VALUES ('w', '앨리스', :d, 1, '{}', '[]', 0, 0, 'mega')", ["d": .text(Walk.key(noon(1)))]) }
            y = try await db.raidStart("앨리스", tier: 1, app: "5.0", now: noon(1), mega: 1)
            #expect(y.why == "오늘은 10판을\n다 했어요")
        }
        // off: 3 a day and no lobby needed, as before
        let z = try await db.raidStart("앨리스", tier: 1, app: "5.0", now: noon(5))
        #expect(z.why == nil)
    }
}

@Test func raidDailySwitch() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    #expect(try await db.raidDaily() == false)
    _ = try await db.setRaidDaily(true); #expect(try await db.raidDaily() == true)
    _ = try await db.setRaidDaily(false); #expect(try await db.raidDaily() == false)
}
