import Foundation

// pokeserver <command>: the server (serve) and the admin tools (08b §7), one binary over the same SQLite file.
// Run them as the pokewalker user (sudo -u pokewalker): a root-owned -wal / -shm would lock the server out.

let usage = """
    usage: pokeserver <command> [--db <path>]
      serve                              the API on 127.0.0.1:$PORT (env APP_KEY, PORT=8787, DB_PATH), and the team's download page at /
                                         (RELEASE_DIR=/var/lib/pokewalker/release, server/publish.sh fills it; DOWNLOAD_PASSWORD set: behind it)
                                         and its guide at /guide (GUIDE_DIR=/var/lib/pokewalker/guide: its pictures, server/guide.sh fills it)
      init                               make the database file and its tables (the only command that creates it)
      list                               every trainer, today's steps first
      show <id>                          one trainer: the row, its history and legacy copies
      walk <id> [<rev> <reason>]         the save's JSON (or a history copy's) on stdout
      rollback <id> <rev> <reason>       put a history copy back as a new rev
      set <id> <json-path> <json-value>  change one value: set 민 '$.watts' 0
      rename <id> <new id>               a new name (a new key logs the old PCs out)
      delete <id> --yes                  remove a trainer (the save is kept as a file next to the database)
      legacy [<id>]                      pre-server saves
      suspects [<days>]                  trainers whose saves the checks flagged (docs/plans/10 §2), and the busiest walkers (default 7 days)
      flags <id> [<n>]                   one trainer's flagged saves, newest first (default 30)
      pin-reset <id>                     forget the trainer's PIN and every PC's trust: the next login sets a new one
      mons <id>                          the Pokémon the server issued to a trainer (uid, species, kind, state, 이로치, IV total) and its grants
      actions <id> [<n>]                 3.0: a trainer's acts (steps cut, refusals), what's on now, today's steps (default 30)
      prune                              drop old history now (the server does it hourly)
      sample                             a new save's JSON (Walk(), the one-time checks marked done)
      verify-release <dir>               a release folder: manifest.sig checks with the release key, each zip's size and SHA-256 (publish.sh)
      mail <id|--all> --title <t> [--body <b>] [--item <name> <n>]… [--bp <n>] [--watts <n>] [--title-gift <칭호>] [--deco silver|gold]
           [--mon <dex> <level>]…      3.9 (docs/plans/15): a mail to one trainer or all (test IDs left out); no gifts = a notice
                                         --mon (5.1.3): one made as an egg hatches (wild IVs · nature · ability slot · gender, 이로치 1/64), at that level
                                     after it (10-23): --perfect <0-6> IVs at 31 or --ivs h,a,b,c,d,s; --shiny yes|no (else the 1/64);
                                     --nature <성격>; --evs h,a,b,c,d,s (≤255 each, 510); --ability <slot>; --moves <a,b,c,d> (its 기술 바꾸기's)
      mail-log [<n>]                     the last mails sent, newest first (default 30)
      raid-runs [on | <unix>]            4.0 (docs/plans/16): when the raid's runs start for the team (on = now; test IDs have them always)
      raid-log [<n>]                     the last raid runs: who, the tier, the boss (★ shiny), bars down, won, balls left, caught (default 30)
      tower-reset [--yes]                4.1 (docs/plans/17), once: every tower streak, best and first-time reward back to zero, runs ended
                                         (without --yes: who, nothing changed; with it: stop the service first)
      tm-cleanup [--yes]                 5.2.1, once: 기술머신 in bags and on walkers — a number not had yet had (tms), the other copies out of the
                                         save and back as one mail of W each (50 a copy); test IDs left out (without --yes: who, nothing changed)
      content5 [on|off]                  5.0 (docs/plans/18): the Gen V–VI switch (the running server takes it within 10 s; the app at its next login)
      relogin [now|off|<unix>]           5.0 apps' sessions from before then log in once more, at their next steps act (not mid-fight, chain or live battle)
      versions                           5.0: each trainer's app as last seen, its oldest allowed, what its updater said last
      update-hint urgent|calm [<iso>]    5.0: /v1/update's hint outside the signed manifest — urgent (and install by when)
      content51 [on|off]                 5.1 (docs/plans/19): the 전설 원정 switch, on top of content5 (the server within 10 s, the app at its next login)
      content52 [on|off]                 5.2 (docs/plans/19 §11): 배회 · 시련 · 레쿠쟈 원정, 기술머신, 일루전 · 프리폴, on top of content51 — for 5.2 apps' requests only (test IDs: always)
      events                             5.1: the team events — each week, the team's steps against its goal, who walked enough, who got the mythical
      event-schedule <yyyy-MM-dd>        5.1: the six weeks from that day (0:00 KST), every other week, and the encore two weeks after the last
      event-cancel <id>                  5.1: one not begun goes; one on ends now
      raid-daily [on|off]                5.1 (docs/plans/20): both raids by the day — bosses each day, 2칸 at 0:00 + 1 a 10,000 steps, 10 runs a day
      rollout [off|<n>%|<id>[,<id>…]]    docs/plans/22: release-next (NEXT_RELEASE_DIR) to these first — only apps already at the stable version
      update-note [on|off]               docs/plans/22: "update": {v, urgent} first in each reply to an app with a newer version for it
      slot-odds [on|off]                 docs/plans/21: a course's Pokémon without steps — group A 20 · B 30 · C 50 %, a radar chain to A 52 · B 38 · C 10
      evo-choice [on|off]                5.1.3 (docs/plans/23): 배루키 waits at Lv.20 for the player's pick (on with 5.1.3 out: older apps can't pick)
      duel-mega [on|off]                 5.1.4 (docs/plans/24): 메가진화 in live battles — a duel started with both apps 5.1.4 on allows it
    --db: else $DB_PATH, else /var/lib/pokewalker/pokewalker.db
    """

func fail(_ message: String) -> Int32 {
    FileHandle.standardError.write(Data("pokeserver: \(message)\n".utf8))
    return 1
}

/// MIN_APP as the service has it, for the commands (sudo -u clears the environment): the environment's, else server.env's line
/// (the running server took its value at its start: an edit counts after the restart).
func configuredMinApp(_ env: [String: String], file: String = "/etc/pokewalker/server.env") -> String? {
    let v = env["MIN_APP"] ?? (try? String(contentsOfFile: file, encoding: .utf8))?.split(separator: "\n").last { $0.hasPrefix("MIN_APP=") }.map { String($0.dropFirst(8)) }
    return v.flatMap { $0.isEmpty || versionParts($0) == nil ? nil : $0 }
}

/// Columns padded to the terminal width of their text (Hangul and other wide letters count 2).
func table(_ header: [String], _ rows: [[String]]) -> String {
    func width(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { n, u in
            let v = u.value
            let wide = (0x1100...0x115F).contains(v) || (0x2E80...0xA4CF).contains(v) || (0xAC00...0xD7A3).contains(v)
                || (0xF900...0xFAFF).contains(v) || (0xFE30...0xFE4F).contains(v) || (0xFF00...0xFF60).contains(v) || (0xFFE0...0xFFE6).contains(v)
            return n + (wide ? 2 : 1)
        }
    }
    let all = [header] + rows
    let widths = header.indices.map { c in all.map { width($0[c]) }.max() ?? 0 }
    return all.map { r in
        r.indices.map { c in r[c] + String(repeating: " ", count: widths[c] - width(r[c])) }.joined(separator: "  ").replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }.joined(separator: "\n")
}

/// A new trainer's save (08 §5): the app's Walk(), the one-time checks (1.7 audit, 1.10 ball refund) already done, the starter's issued uid;
/// the device's fields empty.
func sampleWalk() throws -> String {
    var w = Walk()
    w.audited = 2; w.ballsRefunded = true
    w.companion.uid = firstUID; w.lastUID = firstUID                                             // the starter as 2.1's create issues it (10 §4.1)
    let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
    return String(decoding: try enc.encode(w), as: UTF8.self)
}

extension SaveDB {
    func key(_ id: String) throws -> String {
        guard let t = trainerID(id) else { throw ServerError(description: "\(id): not a trainer ID (2–12 of 가-힣 A-Z a-z 0-9 _)") }
        guard try trainer(t.key) != nil else { throw ServerError(description: "\(id): no such trainer") }
        return t.key
    }

    func list() throws -> String {
        let rows = try db.rows("""
            SELECT name, key, rev, json_extract(walk, '$.day') AS day,
              CASE WHEN json_extract(walk, '$.day') = date('now', 'localtime') THEN json_extract(walk, '$.today') ELSE 0 END AS today,
              json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts,
              datetime(updated_at, 'unixepoch', 'localtime') AS saved, last_device
            FROM trainers ORDER BY today DESC, total DESC, key
            """)
        let cols = ["name", "key", "rev", "day", "today", "total", "watts", "saved", "last_device"]
        return table(cols, rows.map { r in cols.map(r.show) }) + "\n\(rows.count) trainer(s)"
    }

    func show(_ id: String) throws -> String {
        let k = try key(id)
        let t = try db.rows("""
            SELECT name, key, rev, app, writer, device, last_device, json_extract(walk, '$.day') AS day, json_extract(walk, '$.today') AS today,
              json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts, json_extract(walk, '$.bp') AS bp,
              json_array_length(walk, '$.box') AS box, length(walk) AS bytes,
              datetime(created_at, 'unixepoch', 'localtime') AS created, datetime(updated_at, 'unixepoch', 'localtime') AS saved
            FROM trainers WHERE key = :k
            """, ["k": .text(k)])[0]
        func dash(_ c: String) -> String { let v = t.show(c); return v.isEmpty ? "-" : v }
        let writer = t.text("writer").map { $0 == "admin" ? "admin" : String($0.prefix(8)) + "…" } ?? "-"
        var out = """
            \(t.show("name")) (key \(t.show("key"))) · rev \(t.show("rev")) · app \(t.text("app") ?? "-") · writer \(writer)
            PC \(t.text("last_device") ?? "-") (\(t.text("device") ?? "no session")) · saved \(t.show("saved")) · created \(t.show("created"))
            day \(dash("day")) · today \(dash("today")) · total \(dash("total")) · watts \(dash("watts")) · bp \(dash("bp")) · box \(dash("box")) · \(dash("bytes")) bytes
            """
        let h = try db.rows("""
            SELECT rev, reason, datetime(at, 'unixepoch', 'localtime') AS at, json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts
            FROM history WHERE key = :k ORDER BY at DESC, rev DESC
            """, ["k": .text(k)])
        out += "\n\nhistory (\(h.count))\n" + table(["rev", "reason", "at", "total", "watts"], h.map { r in ["rev", "reason", "at", "total", "watts"].map(r.show) })
        let l = try db.rows("""
            SELECT device, datetime(at, 'unixepoch', 'localtime') AS at, json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts
            FROM legacy WHERE key = :k ORDER BY at
            """, ["k": .text(k)])
        if !l.isEmpty { out += "\n\nlegacy (\(l.count))\n" + table(["device", "at", "total", "watts"], l.map { r in ["device", "at", "total", "watts"].map(r.show) }) }
        return out
    }

    /// The save (or a history copy) as stored.
    func walkText(_ id: String, rev: Int? = nil, reason: String? = nil) throws -> String {
        let k = try key(id)
        if let rev, let reason {
            guard let w = try db.rows("SELECT walk FROM history WHERE key = :k AND rev = :r AND reason = :why", ["k": .text(k), "r": .int(rev), "why": .text(reason)]).first?.text("walk")
            else { throw ServerError(description: "\(id): no history copy (\(rev), \(reason)) — see pokeserver show \(id)") }
            return w
        }
        guard let w = try trainer(k)?.walk else { throw ServerError(description: "\(id): no save yet (rev 0)") }
        return w
    }

    /// An admin's change, in one transaction: the current save kept as history('admin'), the new one at rev + 1 by writer 'admin'
    /// (the PC's next save then gets 409 stale and takes this one). A text the app couldn't decode rolls it all back.
    private func adminWrite(_ k: String, _ make: () throws -> String, now: Int) throws -> (from: Int, to: Int) {
        try db.transaction {
            guard let t = try trainer(k) else { throw ServerError(description: "\(k): no such trainer") }
            let walk = try make()
            guard walkDecodes(walk) else { throw ServerError(description: "the result isn't a save the app can load (Walk, version 1) — nothing changed") }
            if let old = t.walk {
                try db.rows("INSERT OR REPLACE INTO history (key, rev, reason, at, walk) VALUES (:k, :r, 'admin', :now, :w)",
                            ["k": .text(k), "r": .int(t.rev), "now": .int(now), "w": .text(old)])
            }
            try db.rows("UPDATE trainers SET walk = :w, rev = :r, writer = 'admin' WHERE key = :k", ["w": .text(walk), "r": .int(t.rev + 1), "k": .text(k)])
            return (t.rev, t.rev + 1)
        }
    }

    func rollback(_ id: String, rev: Int, reason: String, now: Int) throws -> String {
        let k = try key(id), copy = try walkText(id, rev: rev, reason: reason)
        let r = try adminWrite(k, { copy }, now: now)
        return "\(k): history (\(rev), \(reason)) is rev \(r.to) now (rev \(r.from) kept as admin)"
    }

    /// docs/plans/17 (4.1, the user — once, with that release): every trainer's Battle Tower from zero. The save's streak, best and first-time
    /// rewards taken (towerStreak 0, towerBest 0, towerRewards []; rev + 1, the old one kept as admin), tower_rewards emptied, a run on ended
    /// (a tower fight on: void). What was paid stays: BP, items, legends, 장식, 칭호, mail not claimed yet. One transaction; run it with the
    /// service stopped (an act in between could write an old best back, and its rewards would mail again). dry: who, and nothing changed.
    func towerReset(now: Int, dry: Bool) throws -> String {
        try db.transaction {
            var lines: [String] = [], n = 0
            for row in try db.rows("SELECT t.key AS k, t.name AS name, t.walk AS walk, t.rev AS rev, p.state AS state FROM trainers t LEFT JOIN play p ON p.key = t.key ORDER BY t.key") {
                guard let k = row.text("k"), let text = row.text("walk"), let w = decodeWalk(text), let rev = row.int("rev") else { continue }
                var play = row.text("state").flatMap { try? JSONDecoder().decode(Play.self, from: Data($0.utf8)) }
                let paid = try db.rows("SELECT wins FROM tower_rewards WHERE key = :k ORDER BY wins", ["k": .text(k)]).compactMap { $0.int("wins") }
                let on = play?.tower == true, fight = on && play?.battle?.trainer != nil
                guard (w.towerStreak ?? 0) != 0 || (w.towerBest ?? 0) != 0 || !(w.towerRewards ?? []).isEmpty || !paid.isEmpty || on else { continue }
                n += 1
                lines.append("\(row.text("name") ?? k): streak \(w.towerStreak ?? 0) · best \(w.towerBest ?? 0) · rewards \(paid.map(String.init).joined(separator: ","))"
                             + (fight ? " · a tower fight on (void)" : on ? " · a run on (ended)" : ""))
                if dry { continue }
                guard let reset = try db.rows("SELECT json_set(walk, '$.towerStreak', 0, '$.towerBest', 0, '$.towerRewards', json('[]')) AS w FROM trainers WHERE key = :k",
                                              ["k": .text(k)]).first?.text("w"), walkDecodes(reset) else { throw ServerError(description: "\(k): the reset save doesn't load — nothing changed") }
                try db.rows("INSERT OR REPLACE INTO history (key, rev, reason, at, walk) VALUES (:k, :r, 'admin', :now, :w)", ["k": .text(k), "r": .int(rev), "now": .int(now), "w": .text(text)])
                try db.rows("UPDATE trainers SET walk = :w, rev = :r, writer = 'admin' WHERE key = :k", ["w": .text(reset), "r": .int(rev + 1), "k": .text(k)])
                if on, var p = play {
                    if fight { p.battle = nil; p.party = nil }
                    p.tower = false; play = p
                    try db.rows("UPDATE play SET state = :s WHERE key = :k", ["s": .text(String(decoding: try JSONEncoder().encode(p), as: UTF8.self)), "k": .text(k)])
                }
            }
            if !dry { try db.rows("DELETE FROM tower_rewards") }
            return (lines + ["\(n) trainer(s)" + (dry ? " would be reset (nothing changed: add --yes, with the service stopped)" : " reset; tower_rewards emptied")]).joined(separator: "\n")
        }
    }

    /// 5.2.1 (the user via 회사 10-26: "기술머신 들고 있던거 다 W로 바꾸고 소유 기술머신에 넣어주면", "W는 우편 형태로 전달하자"), once: every
    /// trainer's 기술머신 · 비전머신 in the bag and on the walker — a number not had yet is had (Walk.tms, one copy: adoptMachines's), every
    /// other copy leaves the save and comes back as one mail of W (Walk.machineSale each). Test IDs left out. One transaction (an act waits for
    /// it: the service can run), each changed save at rev + 1 with the old one kept as history('admin'). dry: who and what, nothing changed.
    func machineCleanup(now: Int, dry: Bool) throws -> String {
        try db.transaction {
            var lines: [String] = [], n = 0, copies = 0, mailed = 0, total = 0, over = 0
            for row in try db.rows("SELECT key AS k, name, walk, rev FROM trainers ORDER BY key") {
                guard let k = row.text("k"), !isTestID(k), let text = row.text("walk"), var w = decodeWalk(text), let rev = row.int("rev") else { continue }
                let c = w.machineCleanup()
                guard !c.adopted.isEmpty || c.extra > 0 else { continue }
                n += 1; copies += c.extra
                let W = c.extra * Walk.machineSale, full = W > 0 && w.watts + W > 9_999                      // (a claim keeps 9,999 at most: the mail says to spend first)
                if full { over += 1 }
                lines.append("\(row.text("name") ?? k): " + [c.adopted.isEmpty ? nil : "had now " + c.adopted.map(Machines.name).joined(separator: ","),
                                                             c.extra > 0 ? "\(c.extra) more → \(W) W by mail" + (full ? " (W \(w.watts) now: over 9,999)" : "") : nil]
                                                                .compactMap { $0 }.joined(separator: " · "))
                if dry { continue }
                let out = savedText(w)
                guard walkDecodes(out) else { throw ServerError(description: "\(k): the cleaned save doesn't load — nothing changed") }
                try db.rows("INSERT OR REPLACE INTO history (key, rev, reason, at, walk) VALUES (:k, :r, 'admin', :now, :w)", ["k": .text(k), "r": .int(rev), "now": .int(now), "w": .text(text)])
                try db.rows("UPDATE trainers SET walk = :w, rev = :r, writer = 'admin' WHERE key = :k", ["w": .text(out), "r": .int(rev + 1), "k": .text(k)])
                if c.extra > 0 {
                    try sendMail(k, kind: "admin", from: "운영자", title: "기술머신 정리",
                                 body: "코스에서 기술머신이 더 이상 나오지 않아요.\n이미 가진 기술머신 \(c.extra)장을 W로 바꿔 드려요 (장당 \(Walk.machineSale)W).\nW는 9,999까지 모여요. 가득 차 있으면 쓰고 받아 주세요.",
                                 gifts: [.watts(amount: W)], now: now)
                    mailed += 1; total += W
                }
            }
            return (lines + ["\(n) trainer(s), \(copies) copies, \(copies * Walk.machineSale) W, \(over) over 9,999 W with it"
                             + (dry ? " (nothing changed: add --yes)" : " — saves changed, \(mailed) mail(s) sent, \(total) W")]).joined(separator: "\n")
        }
    }

    func set(_ id: String, path: String, value: String, now: Int) throws -> String {
        let k = try key(id)
        let r = try adminWrite(k, {
            guard let w = try db.rows("SELECT json_set(coalesce(walk, '{}'), :p, json(:v)) AS w FROM trainers WHERE key = :k",
                                      ["p": .text(path), "v": .text(value), "k": .text(k)]).first?.text("w")
            else { throw ServerError(description: "json_set gave nothing") }
            return w
        }, now: now)
        return "\(k): \(path) = \(value) → rev \(r.to) (rev \(r.from) kept as admin)"
    }

    /// A new name; a new key moves the trainer, its history and legacy rows (a legacy row whose (key, device) is taken stays put) and ends the session.
    /// 5.0's tables by trainer (plan 18): a rename takes them along, a delete takes them away (else a new trainer of that name had its pity, its paid 도감 업적).
    private var fiveTables: [String] { ["mega_wins", "mega_clears", "dex_rewards", "app_reports"] }
    func rename(_ id: String, to newID: String) throws -> String {
        let k = try key(id)
        guard let n = trainerID(newID) else { throw ServerError(description: "\(newID): not a trainer ID (2–12 of 가-힣 A-Z a-z 0-9 _)") }
        return try db.transaction {
            if n.key == k {
                try db.rows("UPDATE trainers SET name = :n WHERE key = :k", ["n": .text(n.name), "k": .text(k)])
                return "\(k): name is \(n.name) now (same key, the session stays)"
            }
            guard try trainer(n.key) == nil else { throw ServerError(description: "\(newID): already a trainer") }
            let a: [String: SQLValue] = ["k": .text(k), "nk": .text(n.key)]
            try db.rows("UPDATE trainers SET key = :nk, name = :n, session = NULL, device = NULL WHERE key = :k", a.merging(["n": .text(n.name)]) { $1 })
            try db.rows("UPDATE history SET key = :nk WHERE key = :k", a)
            try db.rows("UPDATE OR IGNORE legacy SET key = :nk WHERE key = :k", a)
            for t in ["pins", "flags", "mons", "chains", "grants", "steps_day", "actions", "raid_hits", "raid_catch", "raid_runs", "mail", "tower_rewards"] + fiveTables { try db.rows("UPDATE \(t) SET key = :nk WHERE key = :k", a) }
            for t in ["trust", "pin_fails", "play"] { try db.rows("DELETE FROM \(t) WHERE key = :k", ["k": .text(k)]) }   // play: the session ends anyway
            for (t, c) in [("inbox", "to_key"), ("inbox", "from_key"), ("trades", "to_key"), ("trades", "from_key"), ("friends", "a"), ("friends", "b"), ("listings", "key"), ("bids", "key"), ("duels", "a"), ("duels", "b"),
                           ("claims", "key"), ("visits", "owner"), ("visits", "host")] {
                try db.rows("UPDATE \(t) SET \(c) = :nk WHERE \(c) = :k", a)
            }
            return "\(k) → \(n.key) (\(n.name)); its PC gets no_trainer on its next save and asks for an ID"
        }
    }

    /// The save goes to deleted-<key>-<unix>.json next to the database first; legacy rows stay.
    func delete(_ id: String, now: Int) throws -> String {
        let k = try key(id)
        return try db.transaction {
            var kept = "no save to keep (rev 0)"
            if let w = try trainer(k)?.walk {
                let file = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("deleted-\(k)-\(now).json")
                try Data(w.utf8).write(to: file, options: .atomic)
                kept = "save kept as \(file.path)"
            }
            for t in ["history", "trainers", "pins", "trust", "pin_fails", "mons", "chains", "grants", "play", "steps_day", "actions", "raid_hits", "raid_catch", "raid_runs"] + fiveTables { try db.rows("DELETE FROM \(t) WHERE key = :k", ["k": .text(k)]) }
            for t in ["inbox", "trades"] { try db.rows("DELETE FROM \(t) WHERE to_key = :k OR from_key = :k", ["k": .text(k)]) }
            try db.rows("DELETE FROM friends WHERE a = :k OR b = :k", ["k": .text(k)])
            for l in try listings("key = :k AND state = 'open'", ["k": .text(k)]) {                    // 3.8: others' Pokémon held by its posts or raised by it go home first
                try closeListing(l, "cancelled", now: now); try declineBids(on: l, why: "상대가 떠났어요", now: now)
            }
            for v in try visitRows("host = :k AND state = 'on'", ["k": .text(k)]) { try endVisit(v, now: now) }
            try db.rows("DELETE FROM visits WHERE owner = :k OR host = :k", ["k": .text(k)])
            try db.rows("DELETE FROM claims WHERE key = :k", ["k": .text(k)])
            for t in ["mail", "tower_rewards"] { try db.rows("DELETE FROM \(t) WHERE key = :k", ["k": .text(k)]) }
            try db.rows("DELETE FROM bids WHERE key = :k OR listing IN (SELECT id FROM listings WHERE key = :k)", ["k": .text(k)])
            try db.rows("DELETE FROM listings WHERE key = :k", ["k": .text(k)])
            try db.rows("DELETE FROM duels WHERE a = :k OR b = :k", ["k": .text(k)])
            return "\(k): deleted, \(kept)"
        }
    }

    /// 10 §2.3: who the checks flagged in the last `days` (how often, the latest reasons), then today's walkers by steps.
    func suspects(days: Int, now: Int) throws -> String {
        let since = now - days * 86_400
        let f = try db.rows("""
            SELECT t.name, f.key, count(*) AS saves, datetime(max(f.at), 'unixepoch', 'localtime') AS last,
              (SELECT reasons FROM flags g WHERE g.key = f.key ORDER BY g.at DESC LIMIT 1) AS latest
            FROM flags f LEFT JOIN trainers t ON t.key = f.key WHERE f.at >= :since GROUP BY f.key ORDER BY saves DESC
            """, ["since": .int(since)])
        var out = "flagged in \(days) day(s): \(f.count)\n" + table(["name", "key", "saves", "last", "latest"], f.map { r in
            ["name", "key", "saves", "last"].map(r.show) + [String(r.show("latest").prefix(90))] })
        let w = try db.rows("""
            SELECT name, key, json_extract(walk, '$.today') AS today, json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts,
              json_extract(walk, '$.bp') AS bp, json_array_length(walk, '$.box') AS box
            FROM trainers WHERE json_extract(walk, '$.day') = date('now', 'localtime') ORDER BY today DESC LIMIT 10
            """)
        out += "\n\ntoday's walkers (a day's cap is \(SaveCheck.daySteps))\n" + table(["name", "key", "today", "total", "watts", "bp", "box"], w.map { r in ["name", "key", "today", "total", "watts", "bp", "box"].map(r.show) })
        return out
    }
    func monsList(_ id: String) throws -> String {
        let k = try key(id)
        let rows = try db.rows("""
            SELECT uid, dex, level, kind, state, json_extract(traits, '$.shiny') AS shiny,
              (SELECT sum(value) FROM json_each(json_extract(traits, '$.ivs'))) AS ivs, datetime(at, 'unixepoch', 'localtime') AS at
            FROM mons WHERE key = :k ORDER BY uid
            """, ["k": .text(k)])
        let g = try db.rows("SELECT datetime(at, 'unixepoch', 'localtime') AS at, watts, bp, item, why FROM grants WHERE key = :k ORDER BY at DESC LIMIT 20", ["k": .text(k)])
        return table(["uid", "dex", "level", "kind", "state", "shiny", "ivs", "at"], rows.map { r in ["uid", "dex", "level", "kind", "state", "shiny", "ivs", "at"].map(r.show) })
            + "\n\(rows.count) issued\n\ngrants (latest 20)\n" + table(["at", "watts", "bp", "item", "why"], g.map { r in ["at", "watts", "bp", "item", "why"].map(r.show) })
    }
    /// Plan 11: a 3.0 trainer's acts (newest first: steps cut, refusals), what's on now (radar, fight, tower run, held steps) and today's steps.
    func actionsList(_ id: String, last n: Int) throws -> String {
        let k = try key(id)
        let rows = try db.rows("SELECT datetime(at, 'unixepoch', 'localtime') AS at, seq, act, asked, taken, note FROM actions WHERE key = :k ORDER BY at DESC, seq DESC LIMIT :n",
                               ["k": .text(k), "n": .int(n)])
        var out = table(["at", "seq", "act", "asked", "taken", "note"], rows.map { r in ["at", "seq", "act", "asked", "taken", "note"].map(r.show) })
        if let p = try db.rows("SELECT seq, bank, state FROM play WHERE key = :k", ["k": .text(k)]).first,
           let play = p.text("state").flatMap({ try? JSONDecoder().decode(Play.self, from: Data($0.utf8)) }) {
            var on: [String] = []
            if let r = play.radar { on.append("radar (bush \(r.bush), chain \(r.chain), #\(r.mon.dex))") }
            if let c = play.chain { on.append("a chain held at \(c)") }
            if let b = play.battle { on.append(b.trainer.map { "a tower fight vs \($0)" } ?? "a wild fight vs #\(b.wild.dex)") }
            if play.tower { on.append("a tower run") }
            if play.held > 0 { on.append("\(play.held) steps held") }
            out += "\n\nnow: " + (on.isEmpty ? "nothing" : on.joined(separator: " · ")) + " · last seq \(p.show("seq")) · step allowance \(Int(p.real("bank") ?? 0))"
        }
        let today = try db.rows("SELECT n FROM steps_day WHERE key = :k AND day = :d", ["k": .text(k), "d": .text(Walk.key(Date()))]).first?.int("n") ?? 0
        return out + "\ntoday's steps (the server's count): \(today) of \(Walk.dayCap)"
    }
    func pinReset(_ id: String) throws -> String {
        let k = try key(id)
        return try db.transaction {
            for t in ["pins", "trust", "pin_fails"] { try db.rows("DELETE FROM \(t) WHERE key = :k", ["k": .text(k)]) }
            return "\(k): PIN and trusted PCs forgotten; the next login (app 2.1 on) sets a new PIN"
        }
    }
    func flags(_ id: String, last n: Int) throws -> String {
        let k = try key(id)
        let rows = try db.rows("SELECT rev, datetime(at, 'unixepoch', 'localtime') AS at, reasons FROM flags WHERE key = :k ORDER BY at DESC, rev DESC LIMIT :n",
                               ["k": .text(k), "n": .int(n)])
        return rows.isEmpty ? "\(k): no flagged saves" : rows.map { "rev \($0.show("rev")) · \($0.show("at")) · \($0.show("reasons"))" }.joined(separator: "\n")
    }

    func legacyList(_ id: String?) throws -> String {
        let k = try id.map(key)
        let rows = try db.rows("""
            SELECT key, device, datetime(at, 'unixepoch', 'localtime') AS at, json_extract(walk, '$.total') AS total, json_extract(walk, '$.watts') AS watts
            FROM legacy \(k == nil ? "" : "WHERE key = :k") ORDER BY key, at
            """, k.map { ["k": .text($0)] } ?? [:])
        let cols = ["key", "device", "at", "total", "watts"]
        return table(cols, rows.map { r in cols.map(r.show) }) + "\n\(rows.count) legacy save(s)"
    }
}

/// The command line. The DB: --db, else DB_PATH, else /var/lib/pokewalker/pokewalker.db (sudo -u clears the environment: point elsewhere with --db).
public func run(_ arguments: [String]) async -> Int32 {
    var args = Array(arguments.dropFirst()), dbPath: String?
    if let i = args.firstIndex(of: "--db") {
        guard i + 1 < args.count else { return fail("--db needs a path") }
        dbPath = args[i + 1]; args.removeSubrange(i...i + 1)
    }
    let yes = args.contains("--yes"); args.removeAll { $0 == "--yes" }
    let env = ProcessInfo.processInfo.environment
    let path = dbPath ?? env["DB_PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/var/lib/pokewalker/pokewalker.db"
    guard let command = args.first else { print(usage); return 2 }
    let rest = Array(args.dropFirst())

    do {
        switch command {
        case "sample":
            print(try sampleWalk())
            return 0
        case "init":
            let existed = FileManager.default.fileExists(atPath: path)
            _ = try SaveDB(path: path, create: true)
            print(existed ? "\(path): there already; tables checked" : "\(path): made")
            return 0
        case "serve":
            guard let appKey = env["APP_KEY"], !appKey.isEmpty else { return fail("APP_KEY is empty (/etc/pokewalker/server.env)") }
            let port = env["PORT"].flatMap { Int($0) } ?? 8787
            let db = try SaveDB(path: path, reject: env["CHECK_MODE"] == "reject", rejectTests: env["CHECK_REJECT_TESTS"] == "1",
                                minApp: env["MIN_APP"].flatMap { $0.isEmpty || versionParts($0) == nil ? nil : $0 })   // (VIEW_ALL: gone, 10-16 — everyone has 전체)
            let (release, next) = releaseDirs(env)
            let site = DownloadSite(dir: release, password: env["DOWNLOAD_PASSWORD"].flatMap { $0.isEmpty ? nil : $0 },   // none: the page open (10-21)
                                    guide: URL(fileURLWithPath: env["GUIDE_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "/var/lib/pokewalker/guide", isDirectory: true))
            try await serve(db: db, appKey: appKey, port: port, site: site, release: release, next: next)
            return 0
        case "verify-release":                                                            // publish.sh: before anything goes up
            guard rest.count == 1 else { return fail("verify-release <dir>") }
            let m = try ReleaseFiles.verify(URL(fileURLWithPath: rest[0], isDirectory: true))
            print("release \(m.version) (build \(m.build), \(m.commit.prefix(7))): signed by the release key; " + [("mac", m.mac), ("windows", m.windows)].compactMap { k, e in e.map { "\(k) \($0.size) bytes ok" } }.joined(separator: ", "))
            return 0
        case "-h", "--help", "help":
            print(usage)
            return 0
        default: break
        }

        let db = try SaveDB(path: path, minApp: configuredMinApp(env))                         // (versions shows it)
        let out: String
        switch (command, rest.count) {
        case ("list", 0): out = try await db.list()
        case ("content5", 0):
            let since = try await db.content5Since().map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(.iso8601) }
            out = "content5 " + ((try await db.content5()) ? "on" : "off") + (since.map { " (first on \($0): the Mega raid's rotation counts from that week)" } ?? "")
        case ("content5", 1):
            guard ["on", "off"].contains(rest[0]) else { return fail("content5: on | off") }
            out = try await db.setContent5(rest[0] == "on")
        case ("versions", 0): out = try await db.versionsReport(now: unixNow())
        case ("content51", 0): out = "content51 " + ((try await db.content51()) ? "on" : "off")
        case ("content51", 1):
            guard ["on", "off"].contains(rest[0]) else { return fail("content51: on | off") }
            out = try await db.setContent51(rest[0] == "on")
        case ("content52", 0): out = "content52 " + ((try await db.content52()) ? "on" : "off")
        case ("content52", 1):
            guard ["on", "off"].contains(rest[0]) else { return fail("content52: on | off") }
            out = try await db.setContent52(rest[0] == "on")
        case ("raid-daily", 0): out = "raid-daily " + ((try await db.raidDaily()) ? "on" : "off")
        case ("raid-daily", 1):
            guard ["on", "off"].contains(rest[0]) else { return fail("raid-daily: on | off") }
            out = try await db.setRaidDaily(rest[0] == "on")
        case ("rollout", 0): let d = releaseDirs(env); out = try await db.rolloutReport(release: d.release, next: d.next, now: unixNow())
        case ("rollout", 1): out = try await db.setRollout(rest[0])
        case ("update-note", 0): out = "update-note " + ((try await db.updateNote()) ? "on" : "off")
        case ("update-note", 1):
            guard ["on", "off"].contains(rest[0]) else { return fail("update-note: on | off") }
            out = try await db.setUpdateNote(rest[0] == "on")
        case ("slot-odds", 0): out = "slot-odds " + ((try await db.slotOdds()) ? "on" : "off")
        case ("slot-odds", 1):
            guard ["on", "off"].contains(rest[0]) else { return fail("slot-odds: on | off") }
            out = try await db.setSlotOdds(rest[0] == "on")
        case ("evo-choice", 0): out = "evo-choice " + ((try await db.evoChoice()) ? "on" : "off")
        case ("evo-choice", 1):
            guard ["on", "off"].contains(rest[0]) else { return fail("evo-choice: on | off") }
            out = try await db.setEvoChoice(rest[0] == "on")
        case ("duel-mega", 0): out = "duel-mega " + ((try await db.duelMega()) ? "on" : "off")
        case ("duel-mega", 1):
            guard ["on", "off"].contains(rest[0]) else { return fail("duel-mega: on | off") }
            out = try await db.setDuelMega(rest[0] == "on")
        case ("events", 0): out = try await db.teamEventsReport(now: unixNow())
        case ("event-schedule", 1): out = try await db.scheduleTeamEvents(from: rest[0])
        case ("event-cancel", 1):
            guard let id = Int(rest[0]) else { return fail("event-cancel: <id> is a number") }
            out = try await db.cancelTeamEvent(id, now: unixNow())
        case ("relogin", 0): out = try await db.reloginBefore().map { "relogin: sessions from before \(Date(timeIntervalSince1970: TimeInterval($0)).formatted(.iso8601))" } ?? "relogin off"
        case ("relogin", 1):
            let at = rest[0] == "now" ? unixNow() : Int(rest[0])
            guard rest[0] == "off" || at != nil else { return fail("relogin: now | off | <unix>") }
            out = try await db.setRelogin(rest[0] == "off" ? nil : at)
        case ("update-hint", 1), ("update-hint", 2):
            guard ["urgent", "calm"].contains(rest[0]) else { return fail("update-hint: urgent | calm [<iso time>]") }
            out = try await db.setUpdateHint(urgent: rest[0] == "urgent", installBy: rest.count > 1 ? rest[1] : nil)
        case ("show", 1): out = try await db.show(rest[0])
        case ("walk", 1): out = try await db.walkText(rest[0])
        case ("walk", 3):
            guard let rev = Int(rest[1]) else { return fail("walk: <rev> is a number") }
            out = try await db.walkText(rest[0], rev: rev, reason: rest[2])
        case ("rollback", 3):
            guard let rev = Int(rest[1]) else { return fail("rollback: <rev> is a number") }
            out = try await db.rollback(rest[0], rev: rev, reason: rest[2], now: unixNow())
        case ("set", 3): out = try await db.set(rest[0], path: rest[1], value: rest[2], now: unixNow())
        case ("rename", 2): out = try await db.rename(rest[0], to: rest[1])
        case ("delete", 1):
            guard yes else { return fail("delete \(rest[0]): add --yes (the save is kept as a file, its history goes)") }
            out = try await db.delete(rest[0], now: unixNow())
        case ("legacy", 0), ("legacy", 1): out = try await db.legacyList(rest.first)
        case ("prune", 0): out = "\(try await db.prune(now: unixNow())) history row(s) dropped"
        case ("suspects", 0), ("suspects", 1):
            guard let days = rest.first.map({ Int($0) }) ?? 7 else { return fail("suspects: <days> is a number") }
            out = try await db.suspects(days: days, now: unixNow())
        case ("pin-reset", 1): out = try await db.pinReset(rest[0])
        case ("mons", 1): out = try await db.monsList(rest[0])
        case ("actions", 1), ("actions", 2):
            guard let n = rest.count > 1 ? Int(rest[1]) : 30 else { return fail("actions: <n> is a number") }
            out = try await db.actionsList(rest[0], last: n)
        case ("mail", _) where rest.count >= 3:
            await db.syncContent()                                                                 // (--mon: the species and forms as content5 has them)
            var to = rest[0], i = 1, title: String? = nil, body: String? = nil, gifts: [Gift] = []
            if to == "all" { to = "--all" }
            while i < rest.count {
                let o = rest[i], v = i + 1 < rest.count ? rest[i + 1] : nil
                switch o {
                case "--title": title = v; i += 2
                case "--body": body = v; i += 2
                case "--item":
                    guard let name = v, i + 2 < rest.count, let n = Int(rest[i + 2]), n > 0 else { return fail("mail: --item <name> <count>") }
                    gifts.append(.items(name: name, count: n)); i += 3
                case "--bp": guard let n = v.flatMap({ Int($0) }) else { return fail("mail: --bp <n>") }; gifts.append(.bp(amount: n)); i += 2
                case "--watts": guard let n = v.flatMap({ Int($0) }) else { return fail("mail: --watts <n>") }; gifts.append(.watts(amount: n)); i += 2
                case "--title-gift": guard let t = v else { return fail("mail: --title-gift <칭호>") }; gifts.append(.title(name: t)); i += 2
                case "--deco": guard let d = v, ["silver", "gold"].contains(d) else { return fail("mail: --deco silver|gold") }; gifts.append(.deco(kind: d)); i += 2
                case "--mon":
                    guard let d = v.flatMap({ Int($0) }), (1...dexMax).contains(d), i + 2 < rest.count, let lv = Int(rest[i + 2]), (1...100).contains(lv) else { return fail("mail: --mon <dex 1-\(dexMax)> <level 1-100>") }
                    i += 3; var perfect = 0, shiny: Bool? = nil, nature: Int? = nil                    // (10-23: what follows it is its own)
                    var ivs: [Int]? = nil, evs: [Int]? = nil, ability: Int? = nil, moves: [String]? = nil
                    func six(_ x: String?) -> [Int]? { x.map { $0.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } } }
                    while i < rest.count, ["--perfect", "--shiny", "--nature", "--ivs", "--evs", "--ability", "--moves"].contains(rest[i]) {
                        let x = i + 1 < rest.count ? rest[i + 1] : nil
                        switch rest[i] {
                        case "--perfect": guard let n = x.flatMap({ Int($0) }), (0...6).contains(n) else { return fail("mail: --perfect <0-6>") }; perfect = n
                        case "--shiny": guard let y = x, ["yes", "no"].contains(y) else { return fail("mail: --shiny yes|no") }; shiny = y == "yes"
                        case "--nature": guard let k = x.flatMap({ n in natures.firstIndex { $0.name == n } }) else { return fail("mail: --nature <\(natures.map(\.name).joined(separator: " "))>") }; nature = k
                        case "--ivs": guard let v = six(x) else { return fail("mail: --ivs <h,a,b,c,d,s>") }; ivs = v
                        case "--evs": guard let v = six(x) else { return fail("mail: --evs <h,a,b,c,d,s>") }; evs = v
                        case "--ability": guard let a = x.flatMap({ Int($0) }) else { return fail("mail: --ability <slot 0|1|2>") }; ability = a
                        default: guard let v = x else { return fail("mail: --moves <a,b,c,d>") }; moves = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        }
                        i += 2
                    }
                    var r = SystemRandomNumberGenerator(), m = giftMon(d, level: lv, perfect: perfect, shiny: shiny, nature: nature, &r)
                    if let why = giftMonSet(&m, ivs: ivs, evs: evs, ability: ability, moves: moves) { return fail("mail: \(why) — nothing sent") }
                    gifts.append(.mon(mon: m))
                default: return fail("mail: \(o)? (--title --body --item --bp --watts --title-gift --deco --mon [--perfect --ivs --shiny --nature --evs --ability --moves])")
                }
            }
            guard let title, !title.isEmpty else { return fail("mail: --title is needed") }
            out = try await db.adminMail(to, title: title, body: body, gifts: gifts, now: unixNow())
                + gifts.map { if case .mon(let m, _) = $0 { "\n  " + giftMonLine(m) } else { "" } }.joined()   // (--all: the same one to each; its uid at the claim)
        case ("raid-runs", 0), ("raid-runs", 1):
            if let a = rest.first {
                guard let at = a == "on" ? unixNow() : Int(a) else { return fail("raid-runs: on, or a unix time") }
                out = try await db.raidRunsSet(at, now: unixNow())
            } else { out = try await db.raidRunsShow(now: unixNow()) }
        case ("tower-reset", 0): out = try await db.towerReset(now: unixNow(), dry: !yes)
        case ("tm-cleanup", 0): out = try await db.machineCleanup(now: unixNow(), dry: !yes)
        case ("raid-log", 0), ("raid-log", 1):
            guard let n = rest.count > 0 ? Int(rest[0]) : 30 else { return fail("raid-log: <n> is a number") }
            out = try await db.raidLog(last: n)
        case ("mail-log", 0), ("mail-log", 1):
            guard let n = rest.count > 0 ? Int(rest[0]) : 30 else { return fail("mail-log: <n> is a number") }
            out = try await db.mailLog(last: n)
        case ("flags", 1), ("flags", 2):
            guard let n = rest.count > 1 ? Int(rest[1]) : 30 else { return fail("flags: <n> is a number") }
            out = try await db.flags(rest[0], last: n)
        default:
            return fail("\(([command] + rest).joined(separator: " ")): not a command (or not its arguments)\n\(usage)")
        }
        print(out)
        return 0
    } catch {
        return fail("\(error)")
    }
}

extension Walk {
    /// tm-cleanup's W for a copy: its sale price (ItemKind.of: 기술머신 50).
    static let machineSale = 50
    /// 5.2.1 (pokeserver tm-cleanup): the 기술머신 · 비전머신 in the bag and on the walker — a number not had yet is had (one copy, as
    /// adoptMachines), every other copy taken out (순서미루기's TM60, never had, stays to sell). The numbers newly had and how many copies went.
    mutating func machineCleanup() -> (adopted: [Int], extra: Int) {
        var had = machines, adopted: [Int] = [], extra = 0
        func sweep(_ list: inout [String]) {
            for (k, i) in list.enumerated().reversed() {
                guard let no = Machines.number(i), !Machines.skipped.contains(no) else { continue }
                list.remove(at: k)
                if had.insert(no).inserted { adopted.append(no) } else { extra += 1 }
            }
        }
        sweep(&bag); sweep(&items)
        if !adopted.isEmpty { tms = had.sorted() }
        return (adopted.sorted(), extra)
    }
}
