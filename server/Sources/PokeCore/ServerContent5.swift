import Foundation

// docs/plans/18 §10 (5.0): the content5 switch (pokeserver content5 on|off: the settings row, read by the running server every few seconds and sent
// at login), old apps turned away on every route (426: the User-Agent's version under the trainer's oldest), a trainer's oldest raised to 5.0 once
// a 5.0 app plays with content5 on (its other PCs' old apps stop too), and the update hints: /v1/update's urgent · installBy (outside the signed
// manifest: pokeserver update-hint) and what 5.0 apps say back (staged, blocked, failed, where) for pokeserver versions.

let content5App = "5.0"

extension SaveDB {
    // MARK: the switch
    func content5() throws -> Bool { try db.rows("SELECT value FROM settings WHERE name = 'content5'").first?.text("value") == "on" }
    func setContent5(_ on: Bool) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('content5', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(on ? "on" : "off")])
        return "content5 " + (on ? "on" : "off") + " — the running server takes it within \(content5Every) s"
    }
    /// Content.on from the setting: at start, then every few seconds (pokeserver content5 runs in another process).
    func syncContent() { Content.on = (try? content5()) ?? false }

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
    func setUpdateHint(urgent: Bool, installBy: String?) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('update_urgent', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(urgent ? "1" : "0")])
        try db.rows("INSERT INTO settings (name, value) VALUES ('update_install_by', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(installBy ?? "")])
        return "update hint: " + (urgent ? "urgent" : "calm") + (installBy.map { ", install by \($0)" } ?? "")
    }
    /// What a 5.0 app's /v1/update says of itself.
    func recordUpdateReport(_ r: UpdateReq, now: Int) throws {
        guard let raw = r.trainer, let id = trainerID(raw) else { return }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        try db.rows("""
            INSERT INTO app_reports (key, at, app, platform, staged, blocked, failed, place) VALUES (:k, :at, :a, :p, :s, :b, :f, :w)
            ON CONFLICT (key) DO UPDATE SET at = :at, app = :a, platform = :p, staged = :s, blocked = :b, failed = :f, place = :w
            """, ["k": .text(id.key), "at": .int(now), "a": r.app.map(SQLValue.text) ?? .null, "p": r.platform.map(SQLValue.text) ?? .null,
                  "s": r.staged.map(SQLValue.text) ?? .null, "b": r.blocked.map(SQLValue.text) ?? .null,
                  "f": r.failed.map { .text(String(decoding: (try? e.encode($0)) ?? Data(), as: UTF8.self)) } ?? .null, "w": r.place.map(SQLValue.text) ?? .null])
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
        return table(["who", "app", "oldest", "last", "report", "platform", "staged", "blocked", "failed", "where"], rows)
            + "\ncontent5 " + ((try content5()) ? "on" : "off") + (minApp.map { ", MIN_APP \($0)" } ?? ", no MIN_APP")
    }

    // MARK: 큐레무 합체 (plan 18 §5.1)
    /// One fused (a 큐레무 with its partner inside) can't be traded, put on the board, offered, or sent to raise.
    static func fusedWhy(_ w: Walk, _ uid: Int) -> String? { w.ref(uid: uid).flatMap(w.mon)?.fused != nil ? "합체를 먼저\n풀어 주세요" : nil }
}
let content5Every = 10
let appReportsSchema = """
    CREATE TABLE IF NOT EXISTS app_reports (key TEXT PRIMARY KEY, at INTEGER NOT NULL, app TEXT, platform TEXT, staged TEXT, blocked TEXT, failed TEXT, place TEXT);
    """
