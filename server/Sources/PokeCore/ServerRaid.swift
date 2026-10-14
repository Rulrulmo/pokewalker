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
    CREATE TABLE IF NOT EXISTS raid_runs (id INTEGER PRIMARY KEY AUTOINCREMENT, week TEXT NOT NULL, key TEXT NOT NULL, day TEXT NOT NULL, tier INTEGER NOT NULL,
      boss TEXT NOT NULL, party TEXT NOT NULL, bars INTEGER NOT NULL DEFAULT 0, won INTEGER NOT NULL DEFAULT 0, balls INTEGER NOT NULL DEFAULT 0,
      caught INTEGER NOT NULL DEFAULT 0, at INTEGER NOT NULL, ended_at INTEGER, kind TEXT);
    CREATE INDEX IF NOT EXISTS raid_runs_key ON raid_runs (key, week);
    CREATE TABLE IF NOT EXISTS mega_wins (key TEXT NOT NULL, stone TEXT NOT NULL, wins INTEGER NOT NULL, PRIMARY KEY (key, stone));
    CREATE TABLE IF NOT EXISTS settings (name TEXT PRIMARY KEY, value TEXT NOT NULL);
    """
let raidRotation = [249, 382, 383, 384, 483, 484, 487]                    // 루기아 가이오가 그란돈 레쿠쟈 디아루가 펄기아 기라티나 (ISO week % 7)
let raidLevel = 70, raidBarsPerFighter = 4, raidCatchOdds = 0.30, raidApp = "3.4"         // 4 bars a fighter: the user, 10-04 (14 was too many; 14 §4)

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

// MARK: - 4.0: runs (docs/plans/16)
// One a day's 칸 of power, 3 a day (KST), each against a boss made for it (this week's species at the tier's level and IVs, a shiny 1 in 32); the
// fight is the engine's (10 bars, b.raidTier); its end leaves a ball stage here (raid_runs: balls > 0, not caught) for that boss only, until it's
// caught, out of balls, given up (raidQuit) or the week is over. A fight cut off (a new session) ends as fought with no bars down: its 3 balls wait.

/// A ball's odds at a run's boss: 30 % a species not caught yet (a shiny boss: not caught as shiny yet), 10 % one owned (16 §4.2).
func raidOdds(_ boss: Mon, _ w: Walk) -> Double {
    let had = boss.shiny == true ? (w.shinyOwned ?? []).contains(boss.dex) : (w.owned ?? []).contains(boss.dex)
    return had ? RaidRules.ownedOdds : RaidRules.newOdds
}
/// When runs start for the team if no one says (W43's Monday 0:00, KST): `pokeserver raid-runs on` starts them at once (the user: with 4.0's release).
let raidRunsOpen: Int = {
    var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
    return Int(cal.date(from: DateComponents(weekOfYear: 43, yearForWeekOfYear: 2026))?.timeIntervalSince1970 ?? 0)
}()
let raidUpdate = "레이드가 새로워졌어요\n업데이트해 주세요", raidPendingWhy = "남은 볼이 있어요"

extension SaveDB {
    /// Runs, not the team's boss: from the setting raid_runs_from (unix; unset: W43) for the team, at once for test IDs (their own raid, "-test").
    func raidRuns(_ key: String, _ now: Date) throws -> Bool {
        if isTestID(key) { return true }
        return Int(now.timeIntervalSince1970) >= (try raidRunsFrom())
    }
    func raidRunsFrom() throws -> Int {
        try db.rows("SELECT value FROM settings WHERE name = 'raid_runs_from'").first?.text("value").flatMap { Int($0) } ?? raidRunsOpen
    }
    func setRaidRunsFrom(_ unix: Int) throws {
        try db.rows("INSERT INTO settings (name, value) VALUES ('raid_runs_from', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(String(unix))])
    }
    /// Before a raid act: the run's boss, or why not (the act then walks its steps only). Before W43 an old app fights the team's boss as ever.
    func raidStart(_ key: String, tier: Int?, app: String?, now: Date, mega: Int? = nil) throws -> (boss: RaidBoss?, why: String?) {
        if let k = mega {                                                                         // 5.0 (plan 18 §6.4): a Mega raid run
            guard Content.gen6, knows(app, MegaRaid.app) else { return (nil, "메가 레이드는\n아직 열리지 않았어요") }
            try closeCutRuns(key, now: now)
            if try raidPending(key, now: now) != nil { return (nil, raidPendingWhy) }
            if try raidRunsToday(key, now: now) >= RaidRules.perDay { return (nil, "오늘은 \(RaidRules.perDay)판을\n다 했어요") }
            guard let t = RaidRules.tier(tier) else { return (nil, "난이도를\n골라 주세요") }
            guard let b = megaWeek(now)[safe: k] else { return (nil, "그 보스는\n이번 주에 없어요") }
            var g = SystemRandomNumberGenerator()
            return (RaidBoss(week: raidWeek(key, now), boss: MegaRaid.boss(b, t, &g), left: 1, tier: t.tier, mega: b.form), nil)
        }
        guard try raidRuns(key, now) else {
            return knows(app, RaidRules.app) ? (nil, "새 레이드는\n곧 열려요") : (try raidBoss(key, now: now), nil)
        }
        guard knows(app, RaidRules.app) else { return (nil, raidUpdate) }
        try closeCutRuns(key, now: now)
        if try raidPending(key, now: now) != nil { return (nil, raidPendingWhy) }
        if try raidRunsToday(key, now: now) >= RaidRules.perDay { return (nil, "오늘은 \(RaidRules.perDay)판을\n다 했어요") }
        guard let t = RaidRules.tier(tier) else { return (nil, "난이도를\n골라 주세요") }
        var g = SystemRandomNumberGenerator()
        let shiny = Int.random(in: 0..<RaidRules.shinyOdds, using: &g) == 0
        let boss = RaidRules.boss(raidDex(now), t, shiny: shiny, &g)
        return (RaidBoss(week: raidWeek(key, now), boss: boss, left: 1, tier: t.tier), nil)
    }
    func raidRunsToday(_ key: String, now: Date) throws -> Int {
        try db.rows("SELECT count(*) AS n FROM raid_runs WHERE key = :k AND day = :d", ["k": .text(key), "d": .text(Walk.key(now))]).first?.int("n") ?? 0
    }
    /// A run just started (the engine took the boss): its row, open until the fight ends.
    func raidRunBegan(_ key: String, _ rb: RaidBoss, party: [Int], now: Date) throws {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        try db.rows("INSERT INTO raid_runs (week, key, day, tier, boss, party, at, kind) VALUES (:w, :k, :d, :t, :b, :p, :now, :kind)",
                    ["w": .text(rb.week), "k": .text(key), "d": .text(Walk.key(now)), "t": .int(rb.tier ?? 0), "kind": rb.mega == nil ? .null : .text("mega"),
                     "b": .text(String(decoding: try e.encode(rb.boss), as: UTF8.self)), "p": .text(String(decoding: try e.encode(party), as: UTF8.self)),
                     "now": .int(Int(now.timeIntervalSince1970))])
    }
    /// The fight ended (the engine's end): bars, the win, its balls (the ball stage); a 1st · 3rd · 7th win of the week mails its reward.
    func raidRunEnded(_ key: String, end: BattleEnd, walk w: Walk? = nil, now: Int) throws {
        guard let run = try db.rows("SELECT id, week, kind, tier, boss FROM raid_runs WHERE key = :k AND ended_at IS NULL ORDER BY id DESC LIMIT 1", ["k": .text(key)]).first,
              let id = run.int("id"), let week = run.text("week") else { return }
        let won = end.result == "won", mega = run.text("kind") == "mega"
        try db.rows("UPDATE raid_runs SET bars = :b, won = :w, balls = :n, ended_at = :now WHERE id = :id",
                    ["b": .int(end.bars ?? 0), "w": .int(won ? 1 : 0), "n": .int(mega ? 0 : end.balls ?? RaidRules.balls), "now": .int(now), "id": .int(id)])   // (a Mega raid: no balls)
        if mega, won, let tier = run.int("tier"), let stone = run.text("boss").flatMap({ try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) })?.item {
            var g = SystemRandomNumberGenerator()                                                 // 5.0: the stone (the dice, or its 20th win), or BP for one had
            try megaWon(key, stone: stone, tier: tier, drop: Int.random(in: 0..<100, using: &g) < MegaRaid.stoneOdds[max(0, min(4, tier - 1))], walk: w, now: now)
        }
        try db.rows("UPDATE raid_runs SET ended_at = :now WHERE key = :k AND ended_at IS NULL", ["now": .int(now), "k": .text(key)])   // (none should be)
        guard won else { return }
        let wins = try db.rows("SELECT count(*) AS n FROM raid_runs WHERE key = :k AND week = :w AND won = 1", ["k": .text(key), "w": .text(week)]).first?.int("n") ?? 0
        if let r = RaidRules.weekly.first(where: { $0.wins == wins }) {
            try sendMail(key, kind: "raid", from: "레이드", title: "레이드 이번 주 \(wins)승 보상", gifts: r.gifts, now: now)
        }
    }
    /// Runs whose fight is gone (the app closed mid-fight, another PC): over, as fought — no bars down, 3 balls waiting.
    func closeCutRuns(_ key: String, now: Date) throws {
        try db.rows("UPDATE raid_runs SET ended_at = :now, balls = :n WHERE key = :k AND ended_at IS NULL",
                    ["now": .int(Int(now.timeIntervalSince1970)), "n": .int(RaidRules.balls), "k": .text(key)])
    }
    /// This week's ball stage not finished: the run, its boss, the balls left.
    func raidPending(_ key: String, now: Date) throws -> (id: Int, boss: Mon, tier: Int, bars: Int, won: Bool, balls: Int)? {
        guard let r = try db.rows("""
            SELECT id, boss, tier, bars, won, balls FROM raid_runs WHERE key = :k AND week = :w AND ended_at IS NOT NULL AND balls > 0 AND caught = 0
            ORDER BY id DESC LIMIT 1
            """, ["k": .text(key), "w": .text(raidWeek(key, now))]).first,
              let id = r.int("id"), let boss = r.text("boss").flatMap({ try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }) else { return nil }
        return (id, boss, r.int("tier") ?? 0, r.int("bars") ?? 0, r.int("won") == 1, r.int("balls") ?? 0)
    }
    /// A ball at the waiting run's boss (16 §4.2): 30 % a species not caught yet (a shiny boss: not caught as shiny yet), 10 % one owned.
    /// Caught: that boss as it was, into the box (the ledger's "raid"). Returns why not, or nil with out.raidThrow set (and w changed).
    func raidRunBall(_ key: String, walk w: inout Walk, out: inout Outcome, now: Date) throws -> String? {
        try closeCutRuns(key, now: now)
        guard let p = try raidPending(key, now: now) else { return "던질 볼이 없어요" }
        var g = SystemRandomNumberGenerator()
        let caught = Double.random(in: 0..<1, using: &g) < raidOdds(p.boss, w)
        var mon: Mon? = nil
        if caught {
            var m = p.boss
            if m.level > RaidRules.caughtMax { m.level = RaidRules.caughtMax; m.exp = nil }        // ★5 fights at 120, comes in at 100 (the user)
            m.uid = try nextUID(key, w); try record(key, m, kind: "raid", now: Int(now.timeIntervalSince1970)); _ = w.keep(m); mon = m
        }
        try db.rows("UPDATE raid_runs SET balls = :b, caught = :c WHERE id = :id", ["b": .int(p.balls - 1), "c": .int(caught ? 1 : 0), "id": .int(p.id)])
        out.raidThrow = RaidThrow(caught: caught, shakes: caught ? 3 : Int.random(in: 0...2, using: &g), balls: p.balls - 1, mon: mon)
        return nil
    }
    /// raidQuit: the waiting ball stage given up (its balls gone: 놓침). Nothing waiting: nothing to do.
    func raidRunQuit(_ key: String, now: Date) throws {
        try closeCutRuns(key, now: now)
        if let p = try raidPending(key, now: now) { try db.rows("UPDATE raid_runs SET balls = 0 WHERE id = :id", ["id": .int(p.id)]) }
    }
    /// A trainer's week of runs (nil: none) — the lobby's, a friend's, a TeamCard's.
    func raidWeekOf(_ key: String, now: Date) throws -> RaidWeek? {
        guard let r = try db.rows("""
            SELECT count(*) AS runs, ifnull(sum(won), 0) AS wins, ifnull(sum(caught), 0) AS caught,
              ifnull(sum(CASE WHEN caught = 1 AND boss LIKE '%"shiny":true%' THEN 1 ELSE 0 END), 0) AS shiny,
              max(CASE WHEN won = 1 THEN tier END) AS best FROM raid_runs WHERE key = :k AND week = :w
            """, ["k": .text(key), "w": .text(raidWeek(key, now))]).first, let runs = r.int("runs"), runs > 0 else { return nil }
        return RaidWeek(runs: runs, wins: r.int("wins") ?? 0, caught: r.int("caught") ?? 0, shiny: r.int("shiny") ?? 0, best: r.int("best"))
    }

    /// POST /v2/raid from 4.0 (16 §5): the lobby. A fight on in this session stays open; one cut off is over (its balls wait).
    func raidRunLobby(_ r: RaidReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            let p = try db.rows("SELECT session, state FROM play WHERE key = :k", ["k": .text(key)]).first
            let fighting = p?.text("session") == r.session && (p?.text("state").flatMap { try? JSONDecoder().decode(Play.self, from: Data($0.utf8)) }?.battle?.raidTier != nil)
            if !fighting { try closeCutRuns(key, now: now) }
            let open = try raidRuns(key, now), week = raidWeek(key, now)
            var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
            let ends = Int(cal.dateInterval(of: .weekOfYear, for: now)?.end.timeIntervalSince1970 ?? now.timeIntervalSince1970)
            let reset = Int(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))?.timeIntervalSince1970 ?? now.timeIntervalSince1970)
            let runs = try db.rows("SELECT boss, tier, bars, won, caught, at FROM raid_runs WHERE key = :k AND week = :w AND ended_at IS NOT NULL AND kind IS NULL ORDER BY id DESC",
                                   ["k": .text(key), "w": .text(week)]).compactMap { x -> RaidRunRow? in
                guard let b = x.text("boss").flatMap({ try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }) else { return nil }
                return RaidRunRow(dex: b.dex, tier: x.int("tier") ?? 0, shiny: b.shiny == true, bars: x.int("bars") ?? 0, won: x.int("won") == 1, caught: x.int("caught") == 1, at: x.int("at") ?? 0)
            }
            let friends = try ([key] + friendKeys(key)).compactMap { k -> RaidFriend? in
                guard let t = try db.rows("SELECT name, walk FROM trainers WHERE key = :k", ["k": .text(k)]).first else { return nil }
                let wk = try raidWeekOf(k, now: now) ?? RaidWeek(), dex = t.text("walk").flatMap(decodeWalk)?.companion.dex ?? 0
                return RaidFriend(name: t.text("name") ?? k, dex: dex, runs: wk.runs, wins: wk.wins, caught: wk.caught, shiny: wk.shiny, best: wk.best)
            }
            let pend = try raidPending(key, now: now).map { RaidPending(boss: $0.boss, tier: $0.tier, bars: $0.bars, won: $0.won, balls: $0.balls) }
            let lobby = RaidLobby(week: week, boss: Mon(dex: raidDex(now), level: raidLevel, female: false), next: raidDex(now.addingTimeInterval(7 * 86400)), ends: ends,
                                  today: RaidToday(used: open ? try raidRunsToday(key, now: now) : 0, max: open ? RaidRules.perDay : 0), resetAt: reset,
                                  mine: try raidWeekOf(key, now: now) ?? RaidWeek(), runs: runs, friends: friends, pending: pend, tiers: RaidRules.tiers,
                                  opens: open ? nil : try raidRunsFrom())
            let e = JSONEncoder(); e.outputFormatting = .sortedKeys
            return try e.encode(lobby)
        }
    }
    /// An app before 4.0 once runs are on: the old lobby's shape, harmless (one bar, nothing fought) — its 도전 and ball are refused at the act.
    func raidOldLobby(_ r: RaidReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
            let ends = Int(cal.dateInterval(of: .weekOfYear, for: now)?.end.timeIntervalSince1970 ?? now.timeIntervalSince1970)
            return try JSONEncoder().encode(RaidReply(week: raidWeek(key, now), boss: Mon(dex: raidDex(now), level: raidLevel, female: false), next: raidDex(now.addingTimeInterval(7 * 86400)),
                                                       hpTotal: 1, hpLeft: 1, barHP: 1, ends: ends, fighters: [], recent: [],
                                                       mine: RaidMine(dealt: 0, fights: 0, balls: nil, caught: false, canCatch: false)))
        }
    }
    /// POST /v2/raid: by the app (the body's `app`): 4.0's lobby, or the old one (the team's boss before W43; harmless after).
    func raidLobby(_ r: RaidReq, now: Date) -> Reply {
        if r.kind == "mega", Content.gen6, knows(r.app, MegaRaid.app) { return megaRaidLobby(r, now: now) }   // 5.0
        if knows(r.app, RaidRules.app) { return raidRunLobby(r, now: now) }
        guard let id = trainerID(r.id), (try? raidRuns(id.key, now)) == false else { return raidOldLobby(r, now: now) }
        return raidLobby(TeamReq(id: r.id, session: r.session), now: now)
    }

    // MARK: the operator's (pokeserver raid-runs · raid-log)
    func raidRunsSet(_ at: Int, now: Int) throws -> String { try setRaidRunsFrom(at); return try raidRunsShow(now: now) }
    func raidRunsShow(now: Int) throws -> String {
        let at = try raidRunsFrom(), f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return "raid runs for the team from \(f.string(from: Date(timeIntervalSince1970: TimeInterval(at)))) KST (\(at)): " + (now >= at ? "on" : "not yet") + " — test IDs always"
    }
    func raidLog(last n: Int) throws -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; f.timeZone = TimeZone(identifier: "Asia/Seoul")
        let rows = try db.rows("SELECT r.*, t.name FROM raid_runs r LEFT JOIN trainers t ON t.key = r.key ORDER BY r.id DESC LIMIT :n", ["n": .int(n)]).map { r -> [String] in
            let b = r.text("boss").flatMap { try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }
            return [String(r.int("id") ?? 0), f.string(from: Date(timeIntervalSince1970: TimeInterval(r.int("at") ?? 0))), r.text("name") ?? r.text("key") ?? "?", r.text("week") ?? "",
                    "★\(r.int("tier") ?? 0)", (b?.shiny == true ? "★" : "") + (b.map { "\(monNames[$0.dex]) \($0.level)" } ?? "?"),
                    r.int("ended_at") == nil ? "fighting" : "\(r.int("bars") ?? 0)/\(RaidRules.bars)", r.int("won") == 1 ? "won" : "-",
                    String(r.int("balls") ?? 0), r.int("caught") == 1 ? "caught" : "-"]
        }
        return table(["id", "at", "who", "week", "tier", "boss", "bars", "won", "balls", "caught"], rows)
    }

    // MARK: 5.0: the Mega raid (docs/plans/18 §6.4)
    /// This ISO week's two Mega raid bosses (the legend raid's own week number).
    func megaWeek(_ now: Date) -> [MegaBoss] {                                                // the rotation from content5's first week (MegaRaid.round)
        var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
        let since = ((try? content5Since()) ?? nil).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? now
        return MegaRaid.week(MegaRaid.round(now, from: since, cal))
    }
    /// Each boss's count (by its stone): wins on it while its stone was missing, since that stone last came (the user, 10-14: "보스별로 20번").
    func megaWins(_ key: String) throws -> [String: Int] {
        Dictionary(try db.rows("SELECT stone, wins FROM mega_wins WHERE key = :k", ["k": .text(key)]).compactMap { r in r.text("stone").map { ($0, r.int("wins") ?? 0) } }) { $1 }
    }
    /// The stones a trainer has or has coming: theirs (MegaRaid.stonesHad) and the ones in mail not claimed yet.
    func megaHad(_ key: String, _ w: Walk?) throws -> Set<String> {
        let mailed = try db.rows("SELECT gifts FROM mail WHERE key = :k AND claimed_at IS NULL", ["k": .text(key)]).flatMap { r -> [String] in
            (r.text("gifts").flatMap { try? JSONDecoder().decode([Gift].self, from: Data($0.utf8)) } ?? []).compactMap { if case .items(let n, _) = $0 { n } else { nil } }
        }
        return (w.map(MegaRaid.stonesHad) ?? []).union(mailed.filter(Forms.stones.contains))
    }
    /// A Mega raid win on the boss holding `stone` (drop: the dice's). One had (or on its way): no count, the dice give ★×5 BP. Missing: +1, and
    /// the dice or the bossWins-th win mail the stone (its count back to 0, should it ever go missing again).
    func megaWon(_ key: String, stone: String, tier: Int, drop: Bool, walk w: Walk?, now: Int) throws {
        if try megaHad(key, w).contains(stone) {
            if drop { try sendMail(key, kind: "raid", from: "메가 레이드", title: MegaRaid.mailTitle(stone, had: true), gifts: [.bp(amount: MegaRaid.duplicateBP(tier))], now: now) }
            return
        }
        let n = (try megaWins(key)[stone] ?? 0) + 1, full = n >= MegaRaid.bossWins
        if drop || full {
            try sendMail(key, kind: "raid", from: "메가 레이드", title: drop ? MegaRaid.mailTitle(stone, had: false) : MegaRaid.winsTitle(stone),
                         body: drop ? nil : MegaRaid.bosses.first { $0.stone == stone }.map(MegaRaid.winsBody), gifts: [.items(name: stone, count: 1)], now: now)
        }
        try db.rows("INSERT INTO mega_wins (key, stone, wins) VALUES (:k, :s, :n) ON CONFLICT (key, stone) DO UPDATE SET wins = :n",
                    ["k": .text(key), "s": .text(stone), "n": .int(drop || full ? 0 : n)])
    }
    /// POST /v2/raid, kind "mega": the Mega raid's lobby.
    func megaRaidLobby(_ r: RaidReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            try closeCutRuns(key, now: now)
            let week = raidWeek(key, now), had = try megaHad(key, try db.rows("SELECT walk FROM trainers WHERE key = :k", ["k": .text(key)]).first?.text("walk").flatMap(decodeWalk))
            let wins = try megaWins(key)
            var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
            let ends = Int(cal.dateInterval(of: .weekOfYear, for: now)?.end.timeIntervalSince1970 ?? now.timeIntervalSince1970)
            let reset = Int(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))?.timeIntervalSince1970 ?? now.timeIntervalSince1970)
            let rows = try db.rows("SELECT boss, tier, bars, won, caught, at FROM raid_runs WHERE key = :k AND week = :w AND ended_at IS NOT NULL AND kind = 'mega' ORDER BY id DESC",
                                   ["k": .text(key), "w": .text(week)])
            let runs = rows.compactMap { x -> RaidRunRow? in
                guard let b = x.text("boss").flatMap({ try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }) else { return nil }
                return RaidRunRow(dex: b.dex, tier: x.int("tier") ?? 0, shiny: false, bars: x.int("bars") ?? 0, won: x.int("won") == 1, caught: false, at: x.int("at") ?? 0)
            }
            let mine = RaidWeek(runs: runs.count, wins: runs.filter(\.won).count, best: runs.filter(\.won).map(\.tier).max())
            func mark(_ bs: [MegaBoss]) -> [MegaBoss] { bs.map { var b = $0; b.had = had.contains(b.stone); b.wins = wins[b.stone] ?? 0; return b } }
            let these = mark(megaWeek(now))
            let lobby = MegaRaidLobby(week: week, bosses: these, next: mark(megaWeek(now.addingTimeInterval(7 * 86400))), ends: ends,
                                      today: RaidToday(used: try raidRunsToday(key, now: now), max: RaidRules.perDay), resetAt: reset, mine: mine, runs: runs,
                                      pity: these.filter { $0.had != true }.compactMap(\.wins).max() ?? 0, pityNeed: MegaRaid.bossWins, odds: MegaRaid.stoneOdds, tiers: RaidRules.tiers)
            let e = JSONEncoder(); e.outputFormatting = .sortedKeys
            return try e.encode(lobby)
        }
    }
}

