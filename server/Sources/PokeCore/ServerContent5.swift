import Foundation

// docs/plans/18 §10 (5.0): the content5 switch (pokeserver content5 on|off: the settings row, read by the running server every few seconds and sent
// at login), old apps turned away on every route (426: the User-Agent's version under the trainer's oldest), a trainer's oldest raised to 5.0 once
// a 5.0 app plays with content5 on (its other PCs' old apps stop too), and the update hints: /v1/update's urgent · installBy (outside the signed
// manifest: pokeserver update-hint) and what 5.0 apps say back (staged, blocked, failed, where) for pokeserver versions.

let content5App = "5.0"
let content52App = "5.2"                                                   // docs/plans/19 §11.6: the app that plays 5.2's rules (an older one's requests as before)
/// 5.2 (plan 19 §11.6): this request by 5.2's rules or not — the app's version (5.2 on; a 5.1.x one plays as before) and a test ID's switch
/// (on with content52 off). Around the engine's run.
func content52Scope<T>(_ key: String, app: String?, _ body: () throws -> T) rethrows -> T {
    try Content.$app52.withValue(knows(app, content52App)) { try Content.$testing52.withValue(isTestID(key) ? true : nil, operation: body) }
}

extension SaveDB {
    // MARK: the switch
    func content5() throws -> Bool { try db.rows("SELECT value FROM settings WHERE name = 'content5'").first?.text("value") == "on" }
    func setContent5(_ on: Bool, now: Int = Int(Date().timeIntervalSince1970)) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('content5', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(on ? "on" : "off")])
        if on { try db.rows("INSERT OR IGNORE INTO settings (name, value) VALUES ('content5_since', :v)", ["v": .text(String(now))]) }   // the first time only
        return "content5 " + (on ? "on" : "off") + " — the running server takes it within \(content5Every) s"
    }
    /// When content5 first went on (unix; nil: never): the Mega raid's rotation counts its weeks from that one (MegaRaid.round).
    func content5Since() throws -> Int? { try db.rows("SELECT value FROM settings WHERE name = 'content5_since'").first?.text("value").flatMap { Int($0) } }
    /// Content.on (and 5.1's on51) from the settings: at start, then every few seconds (pokeserver content5 runs in another process).
    func syncContent() { Content.on = (try? content5()) ?? false; Content.on51 = (try? content51()) ?? false; Content.onDaily = (try? raidDaily()) ?? false; Content.onSlots = (try? slotOdds()) ?? false; Content.onChoice = (try? evoChoice()) ?? false; Content.onDuelMega = (try? duelMega()) ?? false; Content.on52 = (try? content52()) ?? false }

    // MARK: 5.1's raids by the day (docs/plans/20): bosses each day, 2칸 at 0:00, 10 runs a day
    func raidDaily() throws -> Bool { try db.rows("SELECT value FROM settings WHERE name = 'raid_daily'").first?.text("value") == "on" }
    func setRaidDaily(_ on: Bool) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('raid_daily', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(on ? "on" : "off")])
        return "raid-daily " + (on ? "on" : "off") + " — the running server takes it within \(content5Every) s (a save's 2칸 comes at its next 0:00)"
    }

    // MARK: the course draw by group shares (docs/plans/21): no steps before a slot, A 20 · B 30 · C 50 %
    func slotOdds() throws -> Bool { try db.rows("SELECT value FROM settings WHERE name = 'slot_odds'").first?.text("value") == "on" }
    func setSlotOdds(_ on: Bool) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('slot_odds', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(on ? "on" : "off")])
        return "slot-odds " + (on ? "on" : "off") + " — the running server takes it within \(content5Every) s (the next radar find)"
    }

    // MARK: 5.1.3's 배루키 by the player's pick (docs/plans/23): it waits at Lv.20 — every app's, so turned on with 5.1.3 out (the picker)
    func evoChoice() throws -> Bool { try db.rows("SELECT value FROM settings WHERE name = 'evo_choice'").first?.text("value") == "on" }
    func setEvoChoice(_ on: Bool) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('evo_choice', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(on ? "on" : "off")])
        return "evo-choice " + (on ? "on" : "off") + " — the running server takes it within \(content5Every) s, the app at its next login"
            + (on ? " (배루키 waits at Lv.20 on every app; only 5.1.3 on can pick)" : " (배루키 by its steps again, at its next level-up)")
    }

    // MARK: 5.1.4's Mega Evolution in live battles (docs/plans/24): a duel started with both apps 5.1.4 on allows it
    func duelMega() throws -> Bool { try db.rows("SELECT value FROM settings WHERE name = 'duel_mega'").first?.text("value") == "on" }
    func setDuelMega(_ on: Bool) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('duel_mega', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(on ? "on" : "off")])
        return "duel-mega " + (on ? "on" : "off") + " — the running server takes it within \(content5Every) s, for duels that start then"
            + (on ? " (both apps \(duelMegaApp) on; a duel with an older one has no 메가진화 on either side)" : "")
    }

    // MARK: 5.2's switch (docs/plans/19 §11): on top of content51; a request plays by it only from a 5.2 app (content52App), a test ID's always
    func content52() throws -> Bool { try db.rows("SELECT value FROM settings WHERE name = 'content52'").first?.text("value") == "on" }
    func setContent52(_ on: Bool) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('content52', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(on ? "on" : "off")])
        let five1 = try content51()
        return "content52 " + (on ? "on" : "off") + " — the running server takes it within \(content5Every) s, for \(content52App) apps' requests"
            + (on && !five1 ? " (content51 is off: nothing of it shows until that's on)" : "")
    }

    // MARK: 5.1's switch (docs/plans/19): the 전설 원정, on top of content5
    func content51() throws -> Bool { try db.rows("SELECT value FROM settings WHERE name = 'content51'").first?.text("value") == "on" }
    func setContent51(_ on: Bool) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('content51', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(on ? "on" : "off")])
        let five = try content5()
        return "content51 " + (on ? "on" : "off") + " — the running server takes it within \(content5Every) s" + (on && !five ? " (content5 is off: nothing of it shows until that's on)" : "")
    }

    // MARK: old apps
    /// The oldest app a trainer may use now (nil: no trainer, or no bound): what needApp says.
    func needAppFor(_ key: String) throws -> String? { try trainer(key).flatMap(needApp) }
    /// A 5.0 app on a trainer while content5 is on: its oldest becomes 5.0 (no going back to an old app on another PC).
    func raiseOldest(_ key: String, app: String?) throws {
        guard Content.gen6, knows(app, content5App), let t = try trainer(key), verCmp(t.app ?? "0", content5App) ?? 0 < 0 else { return }
        try db.rows("UPDATE trainers SET app = :a WHERE key = :k", ["a": .text(content5App), "k": .text(key)])
    }

    // MARK: the update hints
    func updateHint() throws -> (urgent: Bool, installBy: String?) {
        let urgent = try db.rows("SELECT value FROM settings WHERE name = 'update_urgent'").first?.text("value") == "1"
        let by = try db.rows("SELECT value FROM settings WHERE name = 'update_install_by'").first?.text("value")
        return (urgent, by.flatMap { $0.isEmpty ? nil : $0 })
    }
    /// installBy as the app reads it (ISO8601DateFormatter's default): any offset in, UTC's Z stored; one it can't read is refused.
    func setUpdateHint(urgent: Bool, installBy: String?) throws -> String {
        let f = ISO8601DateFormatter()
        let by = try installBy.map { s -> String in
            guard let d = f.date(from: s) else { throw ServerError(description: "update-hint: \(s) isn't an ISO time the app reads (e.g. 2026-10-20T09:00:00+09:00)") }
            return f.string(from: d)
        }
        try db.rows("INSERT INTO settings (name, value) VALUES ('update_urgent', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(urgent ? "1" : "0")])
        try db.rows("INSERT INTO settings (name, value) VALUES ('update_install_by', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(by ?? "")])
        return "update hint: " + (urgent ? "urgent" : "calm") + (by.map { ", install by \($0)" } ?? "")
    }
    /// What a 5.0 app's /v1/update says of itself.
    func recordUpdateReport(_ r: UpdateReq, now: Int) throws {
        guard let raw = r.trainer, let id = trainerID(raw) else { return }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        try db.rows("""
            INSERT INTO app_reports (key, at, app, platform, staged, blocked, failed, place, install_log) VALUES (:k, :at, :a, :p, :s, :b, :f, :w, :l)
            ON CONFLICT (key) DO UPDATE SET at = :at, app = :a, platform = :p, staged = :s, blocked = :b, failed = :f, place = :w, install_log = COALESCE(:l, install_log)
            """, ["k": .text(id.key), "at": .int(now), "a": r.app.map(SQLValue.text) ?? .null, "p": r.platform.map(SQLValue.text) ?? .null,
                  "s": r.staged.map(SQLValue.text) ?? .null, "b": r.blocked.map(SQLValue.text) ?? .null,
                  "f": r.failed.map { .text(String(decoding: (try? e.encode($0)) ?? Data(), as: UTF8.self)) } ?? .null, "w": r.place.map(SQLValue.text) ?? .null,
                  "l": r.installLog.flatMap(installLogLine).map(SQLValue.text) ?? .null])
    }
    /// pokeserver versions: each trainer's app as last seen, its oldest allowed, and what its updater said last (5.0 on).
    func versionsReport(now: Int) throws -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; f.timeZone = TimeZone(identifier: "Asia/Seoul")
        func when(_ t: Int?) -> String { t.map { f.string(from: Date(timeIntervalSince1970: TimeInterval($0))) } ?? "-" }
        let rows = try db.rows("""
            SELECT t.name, t.key, t.app, t.app_seen, t.updated_at, r.at, r.platform, r.staged, r.blocked, r.failed, r.place FROM trainers t
            LEFT JOIN app_reports r ON r.key = t.key ORDER BY t.updated_at DESC
            """).filter { !isTestID($0.text("key") ?? "") }.map { r -> [String] in
            [r.text("name") ?? "?", r.text("app_seen") ?? "-", r.text("app") ?? "-", when(r.int("updated_at")), when(r.int("at")), r.text("platform") ?? "-",
             r.text("staged") ?? "-", r.text("blocked") ?? "-", r.text("failed") ?? "-", r.text("place") ?? "-"]
        }
        let logs = try db.rows("SELECT r.key, t.name, r.at, r.install_log FROM app_reports r JOIN trainers t ON t.key = r.key WHERE r.install_log IS NOT NULL ORDER BY r.at DESC")
            .filter { !isTestID($0.text("key") ?? "") }.map { "  \($0.text("name") ?? "?") (\(when($0.int("at")))): \($0.text("install_log") ?? "")" }   // 5.1.2: what the updater's log ended with
        return table(["who", "app", "oldest", "last", "report", "platform", "staged", "blocked", "failed", "where"], rows)
            + "\ncontent5 " + ((try content5()) ? "on" : "off") + (minApp.map { ", MIN_APP \($0)" } ?? ", no MIN_APP")
            + (logs.isEmpty ? "" : "\ninstall.log (the last lines each app sent):\n" + logs.joined(separator: "\n"))
    }

    // MARK: once more through the login (10-15, the user: "현재 켜져있는 인원들 전부다 한번 껐다키도록")
    /// pokeserver relogin now|off|<unix>: a 5.0 app's session from before that time gets one 409 seq on a plain steps act — the app logs in
    /// again (its steps kept for the next act) and reads the switch anew. Not while the session holds what a new one drops: a fight
    /// (a tower · raid one ends), the radar shown or a chain; nor in a live battle. The new session is from after it: never twice.
    func reloginBefore() throws -> Int? { try db.rows("SELECT value FROM settings WHERE name = 'relogin_before'").first?.text("value").flatMap { Int($0) } }
    func setRelogin(_ at: Int?) throws -> String {
        guard let at else { try db.rows("DELETE FROM settings WHERE name = 'relogin_before'"); return "relogin off" }
        try db.rows("INSERT INTO settings (name, value) VALUES ('relogin_before', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(String(at))])
        return "relogin: 5.0 sessions from before \(Date(timeIntervalSince1970: TimeInterval(at)).formatted(.iso8601)) log in once more (at their next steps act)"
    }
    func asksRelogin(_ key: String, _ r: ActReq, _ p: Play) throws -> Bool {
        guard case .steps = r.act, knows(r.app, content5App), p.battle == nil, p.radar == nil, (p.chain ?? 0) == 0, let before = try reloginBefore(),
              (try db.rows("SELECT session_at FROM trainers WHERE key = :k", ["k": .text(key)]).first?.int("session_at") ?? 0) < before else { return false }
        return try db.rows("SELECT 1 AS n FROM duels WHERE (a = :k OR b = :k) AND state IN ('picking', 'active')", ["k": .text(key)]).isEmpty
    }

    // MARK: 큐레무 합체 (plan 18 §5.1)
    /// One fused (a 큐레무 with its partner inside) can't be traded, put on the board, offered, or sent to raise.
    static func fusedWhy(_ w: Walk, _ uid: Int) -> String? { w.ref(uid: uid).flatMap(w.mon)?.fused != nil ? "합체를 먼저\n풀어 주세요" : nil }
}
let content5Every = 10
/// 5.1.2's installLog as kept: one line (its line breaks as " ⏎ ", other control characters gone), 300 characters at most; nil when empty.
func installLogLine(_ s: String) -> String? {
    let t = s.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true)
        .map { String($0.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }.joined(separator: " ⏎ ")
    return t.isEmpty ? nil : String(t.prefix(300))
}
let appReportsSchema = """
    CREATE TABLE IF NOT EXISTS app_reports (key TEXT PRIMARY KEY, at INTEGER NOT NULL, app TEXT, platform TEXT, staged TEXT, blocked TEXT, failed TEXT, place TEXT);
    """
