import Foundation

// docs/plans/19 §1.4-6 (5.1, content51): the team events — a week each, every other week, one of the six mythicals (TeamEvents.mythicals).
// The steps the server takes from each trainer in that week count (exp_event_steps); once the team's reach the goal, everyone who walked the
// least (TeamEvents.min) gets the mythical by mail (kind "event": Lv.50, 3V, 이로치 1/32, its own move, and its item), once a legend a trainer
// (exp_gifts). The encore week (legend 0) gives each who walks the least there every mythical of the weeks before that it hasn't had, no team
// goal. Test IDs walk a team of their own (the raid's way). The personal expeditions are the engine's (Model/ExpeditionRules.swift).

let expeditionSchema = """
    CREATE TABLE IF NOT EXISTS exp_events (id INTEGER PRIMARY KEY AUTOINCREMENT, legend INTEGER NOT NULL, starts INTEGER NOT NULL, ends INTEGER NOT NULL,
      goal INTEGER NOT NULL, min INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS exp_event_steps (event INTEGER NOT NULL, key TEXT NOT NULL, steps INTEGER NOT NULL, PRIMARY KEY (event, key));
    CREATE TABLE IF NOT EXISTS exp_gifts (key TEXT NOT NULL, legend INTEGER NOT NULL, event INTEGER NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (key, legend));
    """

struct TeamEventRow { let id, legend, starts, ends, goal, min: Int }

extension SaveDB {
    func teamEvents(_ sql: String = "1 = 1", _ args: [String: SQLValue] = [:]) throws -> [TeamEventRow] {
        try db.rows("SELECT id, legend, starts, ends, goal, min FROM exp_events WHERE " + sql + " ORDER BY starts, id", args).compactMap { r in
            guard let id = r.int("id"), let l = r.int("legend"), let s = r.int("starts"), let e = r.int("ends") else { return nil }
            return TeamEventRow(id: id, legend: l, starts: s, ends: e, goal: r.int("goal") ?? 0, min: r.int("min") ?? 0)
        }
    }
    /// Every act's steps taken while a week is on (content51).
    func teamEventSteps(_ key: String, _ n: Int, now: Int) throws {
        guard Content.v51, n > 0 else { return }
        for e in try teamEvents("starts <= :now AND :now < ends", ["now": .int(now)]) {
            try db.rows("INSERT INTO exp_event_steps (event, key, steps) VALUES (:e, :k, :n) ON CONFLICT (event, key) DO UPDATE SET steps = steps + :n",
                        ["e": .int(e.id), "k": .text(key), "n": .int(n)])
        }
    }
    /// A week's steps: the team's (the real trainers', or the test IDs' for a test ID) and this trainer's.
    func teamEventSteps(_ event: Int, for key: String) throws -> (team: Int, mine: Int) {
        let test = isTestID(key)
        var team = 0, mine = 0
        for r in try db.rows("SELECT key, steps FROM exp_event_steps WHERE event = :e", ["e": .int(event)]) {
            guard let k = r.text("key"), isTestID(k) == test else { continue }
            let n = r.int("steps") ?? 0; team += n; if k == key { mine = n }
        }
        return (team, mine)
    }
    func teamEventGot(_ key: String) throws -> Set<Int> { Set(try db.rows("SELECT legend FROM exp_gifts WHERE key = :k", ["k": .text(key)]).compactMap { $0.int("legend") }) }
    /// The mythicals an encore week can still give this trainer: those of the weeks before it not had yet.
    func encoreLeft(_ e: TeamEventRow, key: String, got: Set<Int>) throws -> [Int] {
        try teamEvents("legend > 0 AND starts < :s", ["s": .int(e.starts)]).map(\.legend).filter { !got.contains($0) }
    }

    /// After every act (content51): each week this trainer has walked enough of whose goal the team reached, and whose mythical it hasn't had.
    func teamEventGifts(_ key: String, now: Int) throws {
        guard Content.v51 else { return }
        var got = try teamEventGot(key)
        for e in try teamEvents("starts <= :now", ["now": .int(now)]) {
            let s = try teamEventSteps(e.id, for: key)
            guard s.mine >= e.min else { continue }
            let due = e.legend > 0 ? (s.team >= e.goal && !got.contains(e.legend) ? [e.legend] : []) : try encoreLeft(e, key: key, got: got)
            for dex in due {
                var g = SystemRandomNumberGenerator()
                let m = Expeditions.legend(dex, &g), name = monNames[dex]
                try sendMail(key, kind: "event", from: "팀 이벤트", title: "팀 이벤트: \(name)",                          // (short: 5.0's LCD band traps at 86–94 dots)
                             body: e.legend > 0 ? "팀이 함께 \(e.goal / 10_000)만 걸음을 걸어서 " + josa(name, "이", "가") + " 왔어요." : "앙코르 주에 " + josa(name, "이", "가") + " 왔어요.",
                             gifts: [.mon(mon: m)] + TeamEvents.extras(dex), now: now)
                try db.rows("INSERT INTO exp_gifts (key, legend, event, at) VALUES (:k, :l, :e, :now)", ["k": .text(key), "l": .int(dex), "e": .int(e.id), "now": .int(now)])
                got.insert(dex)
            }
        }
    }

    // MARK: POST /v2/expedition
    /// The team events as this trainer sees them: the one on (else the next), the later ones, then the past ones, newest first.
    func expeditionList(_ r: ExpReq, now: Date) -> Reply {
        readGate(r.id, r.session) { key in
            let unix = Int(now.timeIntervalSince1970), all = try teamEvents(), got = try teamEventGot(key)
            let on = all.first { $0.starts <= unix && unix < $0.ends } ?? all.first { $0.starts > unix }
            let order = (on.map { [$0] } ?? []) + all.filter { $0.starts > unix && $0.id != on?.id } + all.filter { $0.ends <= unix && $0.id != on?.id }.reversed()
            let views = try order.map { e -> TeamEventView in
                let s = try teamEventSteps(e.id, for: key)
                return TeamEventView(id: e.id, legend: e.legend, starts: e.starts, ends: e.ends, goal: e.goal, min: e.min, team: s.team, mine: s.mine,
                                     got: e.legend > 0 ? got.contains(e.legend) : (try encoreLeft(e, key: key, got: got)).isEmpty && s.mine >= e.min,
                                     encore: e.legend > 0 ? nil : try encoreLeft(e, key: key, got: got))
            }
            return try JSONEncoder().encode(ExpReply(events: views))
        }
    }

    // MARK: operators
    /// `pokeserver event-schedule <yyyy-MM-dd>`: the six weeks from that day (0:00 KST), every other week, and the encore two weeks after the last.
    func scheduleTeamEvents(from day: String) throws -> String {
        guard try teamEvents().isEmpty else { throw ServerError(description: "event-schedule: there are events already (pokeserver events; event-cancel <id>)") }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Asia/Seoul"); f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: day) else { throw ServerError(description: "event-schedule: \(day) isn't yyyy-MM-dd") }
        let start = Int(d.timeIntervalSince1970), week = TeamEvents.days * 86400, step = TeamEvents.every * 86400
        for (k, dex) in (TeamEvents.mythicals + [0]).enumerated() {
            let s = start + k * step
            try db.rows("INSERT INTO exp_events (legend, starts, ends, goal, min) VALUES (:l, :s, :e, :g, :m)",
                        ["l": .int(dex), "s": .int(s), "e": .int(s + week), "g": .int(dex > 0 ? TeamEvents.goal : 0), "m": .int(TeamEvents.min)])
        }
        return try teamEventsReport(now: unixNow())
    }
    /// `pokeserver event-cancel <id>`: one not begun goes; one on ends now (what it counted stays, its gifts still come); one over can't.
    func cancelTeamEvent(_ id: Int, now: Int) throws -> String {
        guard let e = try teamEvents("id = :i", ["i": .int(id)]).first else { throw ServerError(description: "event-cancel: no event \(id)") }
        if e.starts > now { try db.rows("DELETE FROM exp_events WHERE id = :i", ["i": .int(id)]); return "event \(id) (\(e.legend > 0 ? monNames[e.legend] : "앙코르")) removed" }
        guard e.ends > now else { throw ServerError(description: "event-cancel: event \(id) is over") }
        try db.rows("UPDATE exp_events SET ends = :now WHERE id = :i", ["now": .int(now), "i": .int(id)])
        return "event \(id) (\(e.legend > 0 ? monNames[e.legend] : "앙코르")) ended now"
    }
    /// `pokeserver events`: each week, the team's steps (real trainers), how many walked the least, how many got their mythical.
    func teamEventsReport(now: Int) throws -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; f.timeZone = TimeZone(identifier: "Asia/Seoul")
        func when(_ t: Int) -> String { f.string(from: Date(timeIntervalSince1970: TimeInterval(t))) }
        let rows = try teamEvents().map { e -> [String] in
            let steps = try db.rows("SELECT key, steps FROM exp_event_steps WHERE event = :e", ["e": .int(e.id)]).filter { !isTestID($0.text("key") ?? "") }
            let gifts = try db.rows("SELECT count(*) AS n FROM exp_gifts WHERE event = :e", ["e": .int(e.id)]).first?.int("n") ?? 0
            let state = now < e.starts ? "next" : now < e.ends ? "on" : "over"
            return [String(e.id), e.legend > 0 ? monNames[e.legend] : "앙코르", when(e.starts) + " ~ " + when(e.ends), state,
                    "\((steps.reduce(0) { $0 + ($1.int("steps") ?? 0) }).formatted()) / \(e.goal.formatted())", String(steps.filter { ($0.int("steps") ?? 0) >= e.min }.count), String(gifts)]
        }
        return table(["id", "legend", "week (KST)", "state", "team steps / goal", "walked enough", "mailed"], rows)
            + "\ncontent51 " + ((try content51()) ? "on" : "off")
    }
}
