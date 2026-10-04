import Foundation

// docs/plans/12 M3: the co-op raid. One boss a week (KST, Monday on), made once and kept; the team's HP from how many fought last week; every
// fight's damage (the engine's, capped at what's left) adds up; once it's 0, everyone who fought gets a few balls and the clear reward.
// Test IDs (zz + 6 digits) have their own raid each week, so a test never touches the team's.

let raidSchema = """
    CREATE TABLE IF NOT EXISTS raids (week TEXT PRIMARY KEY, dex INTEGER NOT NULL, boss TEXT NOT NULL, hp_total INTEGER NOT NULL, bar_hp INTEGER NOT NULL,
      basis INTEGER NOT NULL, created_at INTEGER NOT NULL, cleared_at INTEGER);
    CREATE TABLE IF NOT EXISTS raid_hits (week TEXT NOT NULL, key TEXT NOT NULL, name TEXT NOT NULL, dex INTEGER NOT NULL, dealt INTEGER NOT NULL, at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS raid_hits_week ON raid_hits (week, key);
    CREATE TABLE IF NOT EXISTS raid_catch (week TEXT NOT NULL, key TEXT NOT NULL, balls INTEGER NOT NULL, caught INTEGER NOT NULL, claimed INTEGER NOT NULL,
      PRIMARY KEY (week, key));
    """
let raidRotation = [249, 382, 383, 384, 483, 484, 487]                    // 루기아 가이오가 그란돈 레쿠쟈 디아루가 펄기아 기라티나 (ISO week % 7)
let raidLevel = 70, raidBarsPerFighter = 14, raidCatchOdds = 0.30, raidApp = "3.4"

struct RaidRow { let week: String, dex: Int, boss: Mon, total: Int, bar: Int, cleared: Int? }

/// The week's boss species (and next week's): by the ISO week number.
func raidDex(_ now: Date) -> Int {
    var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
    return raidRotation[cal.component(.weekOfYear, from: now) % raidRotation.count]
}
/// The raid this trainer is in this week: the team's, or (a test ID) the testers'.
func raidWeek(_ key: String, _ now: Date) -> String { weekDays(now).key + (isTestID(key) ? "-test" : "") }

extension SaveDB {
    /// This week's raid, made the first time anyone asks: the boss (4V, the server's dice), the HP from last week's fighters.
    func raid(_ key: String, now: Date) throws -> RaidRow {
        let week = raidWeek(key, now)
        if let r = try db.rows("SELECT dex, boss, hp_total, bar_hp, cleared_at FROM raids WHERE week = :w", ["w": .text(week)]).first,
           let boss = r.text("boss").flatMap({ try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }) {
            return RaidRow(week: week, dex: r.int("dex") ?? boss.dex, boss: boss, total: r.int("hp_total") ?? 0, bar: r.int("bar_hp") ?? 1, cleared: r.int("cleared_at"))
        }
        let test = isTestID(key), last = raidWeek(key, now.addingTimeInterval(-7 * 86400))
        var basis = try db.rows("SELECT count(DISTINCT key) AS n FROM raid_hits WHERE week = :w", ["w": .text(last)]).first?.int("n") ?? 0
        if basis == 0 {                                                                          // the first week: who walked on 3.0 lately
            let since = Walk.key(now.addingTimeInterval(-6 * 86400))
            basis = try db.rows("SELECT DISTINCT s.key AS key FROM steps_day s JOIN trainers t ON t.key = s.key WHERE s.day >= :d AND t.app >= '3'", ["d": .text(since)])
                .filter { r in r.text("key").map { isTestID($0) == test } ?? false }.count
        }
        var g = SystemRandomNumberGenerator()
        let dex = raidDex(now), boss = Mon.wild(dex, level: raidLevel, perfect: 4, &g)
        let bar = boss.stats[0], total = bar * raidBarsPerFighter * max(1, basis)
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        try db.rows("INSERT INTO raids (week, dex, boss, hp_total, bar_hp, basis, created_at) VALUES (:w, :d, :b, :t, :h, :n, :now)",
                    ["w": .text(week), "d": .int(dex), "b": .text(String(decoding: try e.encode(boss), as: UTF8.self)), "t": .int(total), "h": .int(bar),
                     "n": .int(max(1, basis)), "now": .int(Int(now.timeIntervalSince1970))])
        return RaidRow(week: week, dex: dex, boss: boss, total: total, bar: bar, cleared: nil)
    }
    func raidDealt(_ week: String) throws -> Int { try db.rows("SELECT ifnull(sum(dealt), 0) AS n FROM raid_hits WHERE week = :w", ["w": .text(week)]).first?.int("n") ?? 0 }
    /// What a raid act needs from the server before the engine runs: the boss and what's left.
    func raidBoss(_ key: String, now: Date) throws -> RaidBoss {
        let r = try raid(key, now: now)
        return RaidBoss(week: r.week, boss: r.boss, left: max(0, r.total - (try raidDealt(r.week))))
    }

    /// A raid fight just ended (the engine's end.dealt): counted against its week's boss, capped at what was left; at 0, the week is beaten
    /// and everyone who fought hears it. Returns the damage counted.
    func raidHit(_ week: String, key: String, name: String, lead: Int, dealt: Int, now: Int) throws -> Int {
        guard let r = try db.rows("SELECT hp_total, dex, cleared_at FROM raids WHERE week = :w", ["w": .text(week)]).first, let total = r.int("hp_total") else { return 0 }
        let left = max(0, total - (try raidDealt(week))), counted = min(dealt, left)
        try db.rows("INSERT INTO raid_hits (week, key, name, dex, dealt, at) VALUES (:w, :k, :n, :d, :x, :now)",
                    ["w": .text(week), "k": .text(key), "n": .text(name), "d": .int(lead), "x": .int(counted), "now": .int(now)])
        if left > 0, counted >= left, r.int("cleared_at") == nil {
            try db.rows("UPDATE raids SET cleared_at = :now WHERE week = :w", ["now": .int(now), "w": .text(week)])
            for f in try db.rows("SELECT DISTINCT key FROM raid_hits WHERE week = :w", ["w": .text(week)]) {
                if let k = f.text("key") { try post(.raidCleared(dex: r.int("dex") ?? 0), to: k, from: key, fromName: name, app: raidApp, now: now) }
            }
        }
        return counted
    }

    /// A raid ball (12 §4.3): the week beaten and this one fought; balls 3 (+1 for a fair share, +1 for the most); 30 % each (half for a species
    /// already caught); the clear reward with the first. Returns why not, or nil with out.raidThrow set (and w changed).
    func raidBall(_ key: String, walk w: inout Walk, out: inout Outcome, now: Date) throws -> String? {
        let r = try raid(key, now: now), unix = Int(now.timeIntervalSince1970)
        guard r.cleared != nil else { return "아직 보스가\n쓰러지지 않았어요" }
        let hits = try db.rows("SELECT key, sum(dealt) AS d FROM raid_hits WHERE week = :w GROUP BY key ORDER BY d DESC", ["w": .text(r.week)])
        guard let mine = hits.first(where: { $0.text("key") == key })?.int("d") else { return "이번 주에 싸워야\n잡을 수 있어요" }
        var row = try db.rows("SELECT balls, caught, claimed FROM raid_catch WHERE week = :w AND key = :k", ["w": .text(r.week), "k": .text(key)]).first
        if row == nil {
            let fair = mine * hits.count >= r.total ? 1 : 0, top = hits.first?.text("key") == key ? 1 : 0
            try db.rows("INSERT INTO raid_catch (week, key, balls, caught, claimed) VALUES (:w, :k, :b, 0, 0)", ["w": .text(r.week), "k": .text(key), "b": .int(3 + fair + top)])
            row = try db.rows("SELECT balls, caught, claimed FROM raid_catch WHERE week = :w AND key = :k", ["w": .text(r.week), "k": .text(key)]).first
        }
        guard let row, row.int("caught") == 0 else { return "이미 잡았어요" }
        let balls = row.int("balls") ?? 0
        guard balls > 0 else { return "볼이 남아 있지\n않아요" }
        var g = SystemRandomNumberGenerator()
        let reward = row.int("claimed") == 0
        if reward { w.bp = (w.bp ?? 0) + 25; w.bag += Array(repeating: "이상한사탕", count: 5) + ["은색병뚜껑"] }
        let odds = (w.owned ?? []).contains(r.dex) ? raidCatchOdds / 2 : raidCatchOdds, caught = Double.random(in: 0..<1, using: &g) < odds
        var mon: Mon? = nil
        if caught {
            var m = Mon.wild(r.dex, level: raidLevel, shiny: Int.random(in: 0..<shinyOdds, using: &g) == 0 ? true : nil, perfect: 4, &g)
            m.uid = try nextUID(key, w); try record(key, m, kind: "raid", now: unix); _ = w.keep(m); mon = m
        }
        try db.rows("UPDATE raid_catch SET balls = :b, caught = :c, claimed = 1 WHERE week = :w AND key = :k",
                    ["b": .int(balls - 1), "c": .int(caught ? 1 : 0), "w": .text(r.week), "k": .text(key)])
        out.raidThrow = RaidThrow(caught: caught, shakes: caught ? 3 : Int.random(in: 0...2, using: &g), balls: balls - 1, mon: mon, reward: reward)
        return nil
    }

    /// POST /v2/raid: the lobby.
    func raidLobby(_ r: TeamReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            let raid = try raid(key, now: now), dealt = try raidDealt(raid.week)
            let fighters = try db.rows("SELECT name, sum(dealt) AS d FROM raid_hits WHERE week = :w GROUP BY key ORDER BY d DESC", ["w": .text(raid.week)])
                .map { RaidFighter(name: $0.text("name") ?? "?", dealt: $0.int("d") ?? 0) }
            let recent = try db.rows("SELECT name, dex, dealt, at FROM raid_hits WHERE week = :w ORDER BY at DESC, rowid DESC LIMIT 10", ["w": .text(raid.week)])
                .map { RaidHit(name: $0.text("name") ?? "?", dex: $0.int("dex") ?? 0, dealt: $0.int("dealt") ?? 0, at: $0.int("at") ?? 0) }
            let mine = try db.rows("SELECT ifnull(sum(dealt), 0) AS d, count(*) AS n FROM raid_hits WHERE week = :w AND key = :k", ["w": .text(raid.week), "k": .text(key)]).first
            let c = try db.rows("SELECT balls, caught FROM raid_catch WHERE week = :w AND key = :k", ["w": .text(raid.week), "k": .text(key)]).first
            var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
            let ends = Int(cal.dateInterval(of: .weekOfYear, for: now)?.end.timeIntervalSince1970 ?? now.timeIntervalSince1970)
            let fought = (mine?.int("n") ?? 0) > 0
            let me = RaidMine(dealt: mine?.int("d") ?? 0, fights: mine?.int("n") ?? 0, balls: c?.int("balls"), caught: c?.int("caught") == 1,
                              canCatch: raid.cleared != nil && fought && c?.int("caught") != 1 && (c?.int("balls") ?? 1) > 0)
            return try JSONEncoder().encode(RaidReply(week: raid.week, boss: raid.boss, next: raidDex(now.addingTimeInterval(7 * 86400)), hpTotal: raid.total,
                                                       hpLeft: max(0, raid.total - dealt), barHP: raid.bar, ends: ends, fighters: fighters, recent: recent, mine: me))
        }
    }
}
