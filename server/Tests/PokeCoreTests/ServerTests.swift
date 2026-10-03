import Foundation
import Testing
@testable import PokeCore

// 08b §8: the trainer ID, versions, the save rules (판정 7–13) row by row, busy, bytes kept as sent, history and pruning, legacy, opening.
// Every test has its own database file; `now` is passed in, so the clock is the test's. Awaited values are taken first, then checked.

func tempDB() throws -> (SaveDB, String) {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("pokeserver-test-\(UUID().uuidString).db").path
    return (try SaveDB(path: path, create: true), path)
}
func fields(_ r: Reply) -> [String: Any] { (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:] }
func string(_ r: Reply, _ k: String) -> String? { fields(r)[k] as? String }
func number(_ r: Reply, _ k: String) -> Int? { (fields(r)[k] as? NSNumber)?.intValue }
func flag(_ r: Reply, _ k: String) -> Bool? { fields(r)[k] as? Bool }
func sample() -> String { try! sampleWalk() }
let nfdMin = String(String.UnicodeScalarView([0x1106, 0x1175, 0x11AB, 0x1109, 0x116E].map { Unicode.Scalar($0)! }))   // 민수, as the Mac may hand it over

extension SaveDB {
    func count(_ sql: String, _ args: [String: SQLValue] = [:]) throws -> Int { try db.rows(sql, args).first?.int("n") ?? -1 }
    func copies(_ key: String, _ reason: String) throws -> Int {
        try count("SELECT count(*) AS n FROM history WHERE key = :k AND reason = :r", ["k": .text(key), "r": .text(reason)])
    }
}

/// create → the session
func make(_ db: SaveDB, _ id: String, device: String = "pc-a", now: Int = 1_000) async throws -> String {
    let r = await db.create(CreateReq(id: id, device: device, device_name: device.uppercased()), now: now)
    #expect(r.status == 200, "create \(id)")
    return try #require(string(r, "session"))
}
/// The route's order: precheck, then the database.
func save(_ db: SaveDB, _ id: String, _ session: String, base: Int, walk: String? = nil, app: String = "2.0", now: Int) async -> Reply {
    let r = SaveReq(id: id, session: session, app: app, base: base, walk: walk ?? sample())
    if let early = SaveDB.precheck(r) { return early }
    return await db.save(r, now: now)
}
func login(_ db: SaveDB, _ id: String, device: String, app: String? = "2.0", force: Bool = false, now: Int) async -> Reply {
    await db.login(LoginReq(id: id, device: device, device_name: device.uppercased(), app: app, force: force), now: now)
}

@Test func trainerIDs() {
    #expect(trainerID("Min")?.key == trainerID("min")?.key)
    #expect(trainerID("Min")?.name == "Min")
    #expect(trainerID(nfdMin)?.key.unicodeScalars.map(\.value) == [0xBBFC, 0xC218])                  // NFC: 2 letters, not 5
    #expect(trainerID("민") == nil)                                                                 // one letter: under 2
    #expect(trainerID(" 민수 ")?.name == "민수")
    for bad in ["a", "abcdefghijklm", "민 수", "ㅋㅋ", "min!", "ＡＢ", "", "  "] { #expect(trainerID(bad) == nil, "\(bad)") }
    #expect(trainerID("abcdefghijkl") != nil)                                                     // 12 is fine
    #expect(trainerID("트레이너_1") != nil)
}

@Test func versions() {
    #expect(verCmp("2.10", "2.9") == 1)
    #expect(verCmp("2.0", "2.0.0") == 0)
    #expect(verCmp("1.9", "1.13") == -1)
    #expect(verCmp("2.x", "2.0") == nil)
    for bad in ["", "2.", ".2", "1.2.3.4.5", "2.0-beta", "v2"] { #expect(versionParts(bad) == nil, "\(bad)") }
    #expect(versionParts("1.2.3.4") == [1, 2, 3, 4])
}

@Test func sampleIsANewSave() throws {
    let w = try JSONDecoder().decode(Walk.self, from: Data(sample().utf8))
    #expect(w.version == 1 && w.audited == 2 && w.ballsRefunded == true && w.counter == 0 && w.counterKind == nil)
    #expect(walkDecodes(sample()))
    #expect(!walkDecodes("{}"))
}

@Test func saveRules() async throws {
    let (db, _) = try tempDB()
    let a = try await make(db, "Ash")
    // 10, then 12: the same request again (its reply was lost)
    var r = await save(db, "ash", a, base: 0, now: 1_010)
    #expect(r.status == 200 && number(r, "rev") == 1)
    r = await save(db, "ash", a, base: 0, now: 1_020)
    #expect(r.status == 200 && number(r, "rev") == 2)
    // 9: B takes it (force); A's next save is replaced and kept as a conflict
    let b = try #require(string(await login(db, "ash", device: "pc-b", force: true, now: 1_030), "session"))
    r = await save(db, "ash", a, base: 2, now: 1_040)
    #expect(r.status == 409 && string(r, "error") == "conflict" && string(r, "reason") == "replaced")
    var conflicts = try await db.copies("ash", "conflict")
    #expect(conflicts == 1)
    r = await save(db, "ash", b, base: 2, now: 1_050)
    #expect(r.status == 200 && number(r, "rev") == 3)
    // 13: an admin's rollback → B's older base is stale (with the server's rev and save), B then saves on it
    _ = try await db.rollback("ash", rev: 1, reason: "hourly", now: 1_060)
    let t = try #require(try await db.trainer("ash"))
    #expect(t.rev == 4 && t.writer == "admin")
    r = await save(db, "ash", b, base: 3, now: 1_070)
    #expect(r.status == 409 && string(r, "reason") == "stale" && number(r, "rev") == 4 && string(r, "walk") != nil)
    conflicts = try await db.copies("ash", "conflict")
    #expect(conflicts == 2)
    r = await save(db, "ash", b, base: 4, now: 1_080)
    #expect(r.status == 200 && number(r, "rev") == 5)
    // 11: base ahead of the server (it lost saves) is taken whoever wrote last
    _ = try await db.rollback("ash", rev: 1, reason: "hourly", now: 1_090)
    r = await save(db, "ash", b, base: 9, now: 1_100)
    #expect(r.status == 200 && number(r, "rev") == 10)
    let n = try await make(db, "neo")                                                              // rev 0, no save yet
    r = await save(db, "neo", n, base: 3, now: 1_110)
    #expect(r.status == 200 && number(r, "rev") == 4)
    // 8: an older app than the highest that saved here
    let v = try await make(db, "ver")
    r = await save(db, "ver", v, base: 0, app: "1.9", now: 1_120)                                   // (versions under 2.1: no PIN asked, pins() covers that)
    #expect(r.status == 200 && number(r, "rev") == 1)
    r = await save(db, "ver", v, base: 1, app: "1.8", now: 1_130)
    #expect(r.status == 426 && string(r, "error") == "old_app" && string(r, "need") == "1.9")
    r = await login(db, "ver", device: "pc-a", app: "1.8", now: 1_140)
    #expect(r.status == 426)
    r = await save(db, "ver", v, base: 1, app: "1.10", now: 1_150)                                  // 1.10 > 1.9: taken, and the bar moves up
    let ver = try await db.trainer("ver")
    #expect(r.status == 200 && ver?.app == "1.10")
    // 7, and 2–6 before the database
    r = await save(db, "nobody", "x", base: 0, now: 1_160)
    #expect(r.status == 404 && string(r, "error") == "no_trainer")
    r = await save(db, "ash", b, base: 10, walk: "{}", now: 1_170)
    #expect(string(r, "error") == "bad_walk")
    r = await save(db, "ash", b, base: 10, walk: sample().replacingOccurrences(of: "\"version\":1", with: "\"version\":2"), now: 1_170)
    #expect(string(r, "error") == "bad_walk")
    r = await save(db, "ash", b, base: 10, walk: String(repeating: "x", count: walkLimit + 1), now: 1_170)
    #expect(r.status == 413 && string(r, "error") == "too_big")
    r = await save(db, "a!", b, base: 10, now: 1_170)
    #expect(string(r, "error") == "bad_id")
    r = await save(db, "ash", b, base: -1, now: 1_170)
    #expect(string(r, "error") == "bad_request")
    r = await save(db, "ash", b, base: 10, app: "2.x", now: 1_170)
    #expect(string(r, "error") == "bad_app")
    let still = try await db.trainer("ash")
    #expect(still?.rev == 10)                                                                      // none of those wrote
    // conflicts: the newest 10 per trainer
    for i in 0..<12 { _ = await save(db, "ash", a, base: 100 + i, now: 1_200 + i) }
    conflicts = try await db.copies("ash", "conflict")
    let oldest = try await db.count("SELECT min(rev) AS n FROM history WHERE key = 'ash' AND reason = 'conflict'")
    #expect(conflicts == 10 && oldest == 102)
}

@Test func busy() async throws {
    let (db, _) = try tempDB()
    let a = try await make(db, "busy", device: "pc-a", now: 9_000)
    var r = await save(db, "busy", a, base: 0, now: 10_000)
    #expect(r.status == 200)
    r = await login(db, "busy", device: "pc-b", now: 10_299)                                       // A saved 299 s ago
    #expect(flag(r, "busy") == true && string(r, "last_device") == "PC-A" && number(r, "updated_at") == 10_000 && string(r, "session") == nil)
    let kept = try await db.trainer("busy")
    #expect(kept?.session == a)
    r = await login(db, "busy", device: "pc-b", now: 10_301)                                       // 301 s: it moves
    let b = try #require(string(r, "session"))
    #expect(flag(r, "busy") == nil && number(r, "rev") == 1 && string(r, "last_device") == "PC-A")
    r = await save(db, "busy", b, base: 1, now: 10_400)
    #expect(r.status == 200)
    r = await login(db, "busy", device: "pc-c", force: true, now: 10_401)                          // force: at once
    #expect(string(r, "session") != nil && string(r, "last_device") == "PC-B")
    r = await login(db, "busy", device: "pc-c", now: 10_402)                                       // the PC that has it: never busy
    #expect(string(r, "session") != nil)
    r = await login(db, "nobody", device: "pc-a", now: 10_403)
    #expect(r.status == 200 && flag(r, "exists") == false)
    r = await login(db, "busy", device: "", now: 10_404)
    #expect(string(r, "error") == "bad_request")
    r = await db.create(CreateReq(id: "BUSY", device: "pc-z", device_name: "Z"), now: 10_405)
    #expect(r.status == 409 && string(r, "error") == "exists")
}

@Test func bytesKept() async throws {
    let (db, _) = try tempDB()
    let s = try await make(db, "bytes")
    var walk = sample().replacingOccurrences(of: "\"day\":\"\"", with: "\"day\":\"\(nfdMin)  x\"")
    walk = "{ \"version\" : 1 ,  " + walk.dropFirst().replacingOccurrences(of: "\"version\":1,", with: "")    // keys out of order, spaces
    #expect(walkDecodes(walk))
    let saved = await save(db, "bytes", s, base: 0, walk: walk, now: 2_000)
    #expect(saved.status == 200)
    struct Back: Decodable { let walk: String? }
    let reply = await login(db, "bytes", device: "pc-a", now: 2_010)
    let back = try #require(try JSONDecoder().decode(Back.self, from: reply.body).walk)
    let stored = try #require(try await db.trainer("bytes")?.walk)
    #expect(Array(back.utf8) == Array(walk.utf8))                                                  // String == would call NFD and NFC equal
    #expect(Array(stored.utf8) == Array(walk.utf8))
    _ = try await make(db, "fresh")
    let r = await login(db, "fresh", device: "pc-a", now: 2_020)
    #expect(fields(r)["walk"] is NSNull && number(r, "rev") == 0)                                  // "walk": null before the first save
}

@Test func historyAndPrune() async throws {
    let (db, _) = try tempDB()
    let s = try await make(db, "hist")
    let hour = 1_800_000_000 - 1_800_000_000 % 3600
    _ = await save(db, "hist", s, base: 0, now: hour + 100)
    _ = await save(db, "hist", s, base: 1, now: hour + 200)
    var hourly = try await db.copies("hist", "hourly")
    #expect(hourly == 1)
    _ = await save(db, "hist", s, base: 2, now: hour + 3600)
    hourly = try await db.copies("hist", "hourly")
    #expect(hourly == 2)
    // a KST day turns at 15:00 UTC
    let midnight = 1_800_000_000 - (1_800_000_000 + 32400) % 86400 + 86400
    let d = try await make(db, "daily")
    _ = await save(db, "daily", d, base: 0, now: midnight - 20)
    _ = await save(db, "daily", d, base: 1, now: midnight - 10)
    var daily = try await db.copies("daily", "daily")
    #expect(daily == 1)
    _ = await save(db, "daily", d, base: 2, now: midnight + 10)
    daily = try await db.copies("daily", "daily")
    #expect(daily == 2)
    // prune: hourly after 48 h, conflicts after 30 days, daily after 90; admin copies stay
    _ = await save(db, "hist", "not-the-session", base: 0, now: hour + 3700)                       // a conflict
    _ = try await db.set("hist", path: "$.watts", value: "7", now: hour + 3800)                    // an admin copy
    try await db.prune(now: hour + 3600 + 49 * 3600)
    var counts = try await (db.copies("hist", "hourly"), db.copies("hist", "daily"), db.copies("hist", "conflict"), db.copies("hist", "admin"))
    #expect(counts == (0, 1, 1, 1))
    try await db.prune(now: hour + 3700 + 31 * 86400)
    counts = try await (db.copies("hist", "hourly"), db.copies("hist", "daily"), db.copies("hist", "conflict"), db.copies("hist", "admin"))
    #expect(counts == (0, 1, 0, 1))
    try await db.prune(now: hour + 100 * 86400)
    counts = try await (db.copies("hist", "hourly"), db.copies("hist", "daily"), db.copies("hist", "conflict"), db.copies("hist", "admin"))
    #expect(counts == (0, 0, 0, 1))
}

@Test func legacySaves() async throws {
    let (db, _) = try tempDB()
    _ = try await make(db, "old")
    var r = await db.legacy(LegacyReq(id: "old", device: "mac", walk: "{\"total\":5}"), now: 3_000)
    #expect(flag(r, "stored") == true)
    r = await db.legacy(LegacyReq(id: "old", device: "mac", walk: "{\"total\":9}"), now: 3_010)
    #expect(flag(r, "stored") == false)
    let first = try await db.count("SELECT json_extract(walk, '$.total') AS n FROM legacy WHERE key = 'old' AND device = 'mac'")
    #expect(first == 5)                                                                            // never overwritten
    for (i, pc) in ["win", "pc3", "pc4"].enumerated() {
        r = await db.legacy(LegacyReq(id: "old", device: pc, walk: "{}"), now: 3_020 + i)
        #expect(flag(r, "stored") == true)
    }
    r = await db.legacy(LegacyReq(id: "old", device: "pc5", walk: "{}"), now: 3_030)
    let rows = try await db.count("SELECT count(*) AS n FROM legacy WHERE key = 'old'")
    #expect(flag(r, "stored") == false && rows == 4)
    r = await db.legacy(LegacyReq(id: "nobody", device: "mac", walk: "{}"), now: 3_040)
    #expect(r.status == 404)
    r = await db.legacy(LegacyReq(id: "old", device: "mac", walk: "[1]"), now: 3_050)
    #expect(string(r, "error") == "bad_walk")
}

@Test func opening() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("pokeserver-missing-\(UUID().uuidString).db").path
    #expect(throws: (any Error).self) { try SaveDB(path: path) }
    #expect(!FileManager.default.fileExists(atPath: path))
    _ = try SaveDB(path: path, create: true)
    _ = try SaveDB(path: path, create: true)                                                       // init again: there already, tables checked
    _ = try SaveDB(path: path)
}

@Test func adminTools() async throws {
    let (db, path) = try tempDB()
    let s = try await make(db, "Admin")
    _ = await save(db, "admin", s, base: 0, now: 4_000)
    _ = try await db.set("admin", path: "$.watts", value: "123", now: 4_010)
    let watts = try await db.count("SELECT json_extract(walk, '$.watts') AS n FROM trainers WHERE key = 'admin'")
    var t = try await db.trainer("admin")
    var copies = try await db.copies("admin", "admin")
    #expect(watts == 123 && t?.rev == 2 && t?.writer == "admin" && copies == 1)
    await #expect(throws: (any Error).self) { try await db.set("admin", path: "$.version", value: "2", now: 4_020) }    // not a save the app loads
    t = try await db.trainer("admin")
    #expect(t?.rev == 2)                                                                           // nothing changed
    var r = await save(db, "admin", s, base: 1, now: 4_030)
    #expect(string(r, "reason") == "stale")                                                        // the PC follows the admin
    // rename: a new key ends the session; the old PC gets no_trainer
    _ = try await db.rename("admin", to: "Boss")
    let gone = try await db.trainer("admin"), boss = try await db.trainer("boss")
    copies = try await db.copies("boss", "admin")
    #expect(gone == nil && boss?.session == nil && boss?.name == "Boss" && copies == 1)
    r = await save(db, "admin", s, base: 2, now: 4_040)
    #expect(r.status == 404)
    _ = try await db.rename("boss", to: "BOSS")                                                    // case only: the name
    t = try await db.trainer("boss")
    #expect(t?.name == "BOSS")
    // delete: the save kept next to the database, legacy kept
    _ = await db.legacy(LegacyReq(id: "boss", device: "mac", walk: "{}"), now: 4_050)
    _ = try await db.delete("boss", now: 4_060)
    t = try await db.trainer("boss")
    copies = try await db.copies("boss", "admin")
    let legacy = try await db.count("SELECT count(*) AS n FROM legacy WHERE key = 'boss'")
    #expect(t == nil && copies == 0 && legacy == 1)
    let kept = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("deleted-boss-4060.json")
    #expect(walkDecodes(try String(contentsOf: kept, encoding: .utf8)))
    try? FileManager.default.removeItem(at: kept)
    let list = try await db.list()
    #expect(list.hasSuffix("0 trainer(s)"))
}

@Test func patchNotesPage() {
    let text = "PokeWalker 패치 내역\n최신 버전이 맨 위에 있어요.\n\n\n■ 1.2 · 2026-10-02\n\n[바뀐 점] 타워 <Lv.50>\n- 하나\n  · 둘\n    이어지는 줄\n- 셋\n\n■ 1.1 · 2026-10-01\n\n- 넷\n"
    let h = notesHTML(text, open: nil)
    #expect(h.contains("<p class=\"intro\">최신 버전이 맨 위에 있어요.</p>") && !h.contains("PokeWalker 패치 내역"))
    #expect(h.contains("<details class=\"rel\" open><summary>1.2<span class=\"date\">2026-10-02</span>") && h.contains("<details class=\"rel\"><summary>1.1"))
    #expect(h.contains("<h4><span class=\"tag\">바뀐 점</span>타워 &lt;Lv.50&gt;</h4>"))
    #expect(h.contains("<li>하나<ul><li>둘<br>이어지는 줄</li></ul></li><li>셋</li>"))
    #expect(notesHTML(text, open: "1.1").contains("<details class=\"rel\" open><summary>1.1"))
    #expect(formFields("password=a+b%2Bc&x=") == ["password": "a b+c", "x": ""])
}

@Test func releaseSignatures() {
    for (ok, name) in ed25519Checks() + signChecks() { #expect(ok, "\(name)") }                 // Model/Ed25519.swift on Linux: what publish.sh's check runs
}

@Test func releaseFolders() throws {
    // the release Mac's signature of its test file checks; a release folder is refused unless its manifest is signed and each zip matches
    #expect(ReleaseFiles.signed("pokewalker test 2.0\n\n", "f3ed48409038bcdc51ca4ccccacbda9c7e1dd299e05ea3e86fcc7e01de2416bd3333754b4ace0512f2d28f1c9c490833cad6993118db4ae0ea6f769168427507"))
    #expect(!ReleaseFiles.signed("pokewalker test 2.1\n\n", "f3ed48409038bcdc51ca4ccccacbda9c7e1dd299e05ea3e86fcc7e01de2416bd3333754b4ace0512f2d28f1c9c490833cad6993118db4ae0ea6f769168427507"))
    #expect(!ReleaseFiles.signed("anything", "not hex"))
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pokeserver-release-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(throws: (any Error).self) { try ReleaseFiles.verify(dir) }                             // empty
    let zip = Data("zip".utf8)
    try zip.write(to: dir.appendingPathComponent("PokeWalker-mac.zip"))
    let manifest = "{\"build\":\"17\",\"commit\":\"\(String(repeating: "a", count: 40))\",\"mac\":{\"file\":\"PokeWalker-mac.zip\",\"sha256\":\"\(hex(sha256(Array(zip))))\",\"size\":3},\"version\":\"2.0\"}"
    try Data(manifest.utf8).write(to: dir.appendingPathComponent("manifest.json"))
    try Data((String(repeating: "0", count: 128) + "\n").utf8).write(to: dir.appendingPathComponent("manifest.sig"))
    #expect(throws: (any Error).self) { try ReleaseFiles.verify(dir) }                             // well formed, sizes right, but not signed by the release key
    #expect(ReleaseFiles.parse(manifest)?.mac?.size == 3 && ReleaseFiles.parse(manifest)?.windows == nil)
    #expect(ReleaseFiles(dir: dir).signature == String(repeating: "0", count: 128))                // trimmed
}

@Test func saveChecks() async throws {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var g = Seeded(s: 7), a = Walk(); a.audited = 2; a.bag = ["금구슬", "상처약", "상처약"]
    a.box = [Mon.wild(16, level: 10, &g), Mon.wild(19, level: 7, &g)]; for i in a.box.indices { a.box[i].uid = i + 1 }; a.lastUID = 2
    #expect(SaveCheck.values(a).isEmpty, "\(SaveCheck.values(a))")
    // play: 3,000 steps in 10 minutes, sell the 금구슬 (100 W), release one, buy two 상처약 in the shop
    var b = a; _ = b.walk(3000, at: t0); _ = b.sell("금구슬"); _ = b.release(0); b.watts -= 40; b.bag += ["상처약", "상처약"]
    #expect(SaveCheck.changes(from: a, to: b, seconds: 600).isEmpty, "\(SaveCheck.changes(from: a, to: b, seconds: 600))")
    // made up: W from nowhere, steps faster than hands, IVs over 31, an item no one sells, the same uid twice, BP out of thin air
    var c = b; c.watts = 9999
    #expect(SaveCheck.changes(from: b, to: c, seconds: 60).contains { $0.hasPrefix("W ") })
    var d = b; _ = d.walk(20_000, at: t0)
    #expect(SaveCheck.changes(from: b, to: d, seconds: 60).contains { $0.contains("steps in 60 s") })
    var e = b; e.box[0].ivs = [31, 31, 31, 31, 31, 40]; e.bag.append("치트도구"); e.box.append(e.box[0]); e.bp = 500
    let ev = SaveCheck.values(e), ec = SaveCheck.changes(from: b, to: e, seconds: 60)
    #expect(ev.contains { $0.hasPrefix("IVs") } && ev.contains("item 치트도구") && ev.contains("a uid twice") && ec.contains { $0.hasPrefix("BP") })
    var chained = b; chained.bestChain = 4; chained.watts += 8                                       // a chain's 4th link (+8 W) in a save 7 s after the last: fine
    #expect(SaveCheck.changes(from: b, to: chained, seconds: 7).isEmpty, "\(SaveCheck.changes(from: b, to: chained, seconds: 7))")
    var f = b; f.earned += 500
    #expect(SaveCheck.changes(from: b, to: f, seconds: 3600).contains { $0.contains("earned W") })
}

@Test func checkModes() async throws {
    let (db, _) = try tempDB()
    let s = try await make(db, "chk")
    var w = Walk(); w.audited = 2; w.ballsRefunded = true
    func text(_ w: Walk) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return String(decoding: try! e.encode(w), as: UTF8.self) }
    var r = await save(db, "chk", s, base: 0, walk: text(w), now: 5_000)
    #expect(r.status == 200 && r.note == nil)
    var rich = w; rich.watts = 9999                                                                // W from nowhere: taken, but recorded (log mode)
    r = await save(db, "chk", s, base: 1, walk: text(rich), now: 5_060)
    let flagged = try await db.count("SELECT count(*) AS n FROM flags WHERE key = 'chk'")
    #expect(r.status == 200 && r.note?.hasPrefix("flagged") == true && flagged == 1)
    let strict = try SaveDB(path: FileManager.default.temporaryDirectory.appendingPathComponent("pokeserver-strict-\(UUID().uuidString).db").path, create: true, reject: true)
    let s2 = try await make(strict, "chk")
    _ = await save(strict, "chk", s2, base: 0, walk: text(w), now: 5_000)
    r = await save(strict, "chk", s2, base: 1, walk: text(rich), now: 5_060)
    let kept = try await strict.trainer("chk")
    #expect(r.status == 422 && string(r, "error") == "implausible" && kept?.rev == 1)        // refused: the server keeps rev 1
    #expect(number(r, "rev") == 1 && string(r, "walk") == text(w) && string(r, "reasons")?.hasPrefix("W ") == true)   // and hands its save back
}

@Test func pins() async throws {
    let (db, _) = try tempDB()
    func pinLogin(_ id: String, _ device: String, pin: String? = nil, trust: String? = nil, app: String = "2.1", now: Int) async -> Reply {
        await db.login(LoginReq(id: id, device: device, device_name: device.uppercased(), app: app, force: true, pin: pin, trust: trust), now: now)
    }
    // 2.1 makes a trainer with its PIN; that PC gets a trust token and isn't asked again
    var r = await db.create(CreateReq(id: "pinny", device: "mac", device_name: "MAC", app: "2.1", pin: nil), now: 6_000)
    #expect(string(r, "error") == "bad_pin")                                                       // 2.1 on: no PIN, no trainer
    r = await db.create(CreateReq(id: "pinny", device: "mac", device_name: "MAC", app: "2.1", pin: "12a4"), now: 6_000)
    #expect(string(r, "error") == "bad_pin")
    r = await db.create(CreateReq(id: "pinny", device: "mac", device_name: "MAC", app: "2.1", pin: "0420"), now: 6_000)
    let macTrust = try #require(string(r, "trust"))
    r = await pinLogin("pinny", "mac", trust: macTrust, now: 6_010)
    #expect(r.status == 200 && string(r, "session") != nil && string(r, "trust") == nil)           // trusted: no PIN, no new token
    // another PC: the PIN, then its own trust; the old app can't get round it
    r = await pinLogin("pinny", "win", now: 6_020)
    #expect(r.status == 401 && string(r, "error") == "pin")
    r = await pinLogin("pinny", "win", trust: macTrust, now: 6_021)                                 // another PC's token isn't this one's
    #expect(r.status == 401)
    r = await pinLogin("pinny", "win", pin: "0420", now: 6_022)
    #expect(r.status == 200 && string(r, "trust") != nil)
    r = await pinLogin("pinny", "old", app: "2.0", now: 6_023)
    #expect(r.status == 401)                                                                       // a PIN once set holds for 2.0 too
    // 5 wrong PINs in 10 minutes: locked until the first ages out
    for i in 0..<5 { r = await pinLogin("pinny", "evil", pin: "9999", now: 7_000 + i) }
    #expect(r.status == 401)
    r = await pinLogin("pinny", "evil", pin: "0420", now: 7_010)
    #expect(r.status == 429 && string(r, "error") == "pin_locked" && number(r, "retry_after") == 590)
    r = await pinLogin("pinny", "evil", pin: "0420", now: 7_601)
    #expect(r.status == 200)
    // a 2.0 trainer (no PIN) on 2.1: logged in with pin_needed, saves wait for /v1/pin; on 2.0 it plays on as before
    let s = try await make(db, "older")
    r = await save(db, "older", s, base: 0, app: "2.0", now: 8_000)
    #expect(r.status == 200)
    r = await pinLogin("older", "pc-a", now: 8_010)
    let session = try #require(string(r, "session")), rev = try #require(number(r, "rev"))      // (its first 2.1 login stamped uids: rev + 1)
    #expect(flag(r, "pin_needed") == true)
    r = await save(db, "older", session, base: rev, app: "2.1", now: 8_020)
    #expect(r.status == 403 && string(r, "error") == "pin_needed")
    r = await db.setPIN(PinReq(id: "older", session: "nope", pin: "1111"), now: 8_030)
    #expect(r.status == 409)
    r = await db.setPIN(PinReq(id: "older", session: session, pin: "1111"), now: 8_031)
    #expect(r.status == 200 && string(r, "trust") != nil)
    r = await db.setPIN(PinReq(id: "older", session: session, pin: "2222"), now: 8_032)
    #expect(string(r, "error") == "pin_set")                                                       // once; the admin's pin-reset to change it
    r = await save(db, "older", session, base: rev, app: "2.1", now: 8_040)
    #expect(r.status == 200)
    _ = try await db.pinReset("older")
    let has = try await db.hasPIN("older")
    #expect(!has)
}

@Test func minting() async throws {
    let (db, _) = try tempDB()
    func text(_ w: Walk) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return String(decoding: try! e.encode(w), as: UTF8.self) }
    func mon(_ r: Reply) -> Mon? { string(r, "mon").flatMap { try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) } }
    var g = SystemRandomNumberGenerator()
    // a 2.1 trainer: its starter is issued (uid 1,000,000)
    var r = await db.create(CreateReq(id: "minty", device: "mac", device_name: "MAC", app: "2.1", pin: "4321"), now: 10_000)
    let s = try #require(string(r, "session"))
    #expect(number(r, "starter") == firstUID)
    var w = Walk(); w.audited = 2; w.ballsRefunded = true; w.companion.uid = firstUID; w.lastUID = firstUID
    r = await save(db, "minty", s, base: 0, walk: text(w), app: "2.1", now: 10_010)
    #expect(r.status == 200 && r.note == nil, "\(r.note ?? "")")
    // the radar: 10 W, a Pokémon only the server rolls; a catch keeps it, the chain may go on (then the next radar is free)
    _ = w.walk(400, at: Date(timeIntervalSince1970: 1_800_000_000))                                // 20 W
    r = await db.radar(RadarReq(id: "minty", session: s, walk: text(w)), now: 10_100)
    let wild = try #require(mon(r))
    #expect(r.status == 200 && (wild.uid ?? 0) > firstUID && flag(r, "free") == false)
    r = await db.radarResult(ResultReq(id: "minty", session: s, uid: wild.uid!, result: "caught"), now: 10_130)
    let chain = number(r, "chain") ?? -1, bonus = number(r, "bonus") ?? -1
    #expect(r.status == 200 && (chain == 0 || chain == 1) && bonus == 2 * chain)
    // the save with it: taken clean; the same save with a made-up one (or the caught one's IVs changed) is flagged
    var withIt = w; withIt.watts -= 10; withIt.watts += bonus; withIt.box.append(wild); withIt.lastUID = wild.uid
    r = await save(db, "minty", s, base: 1, walk: text(withIt), app: "2.1", now: 10_140)
    #expect(r.status == 200 && r.note == nil, "\(r.note ?? "")")
    var forged = withIt; var fake = Mon.wild(150, level: 70, shiny: true, perfect: 6, &g); fake.uid = 1_000_999; forged.box.append(fake); forged.lastUID = 1_000_999
    forged.box[0].ivs = [31, 31, 31, 31, 31, 31]
    r = await save(db, "minty", s, base: 2, walk: text(forged), app: "2.1", now: 10_150)
    let note = r.note ?? ""
    #expect(note.contains("#150 Lv.70 wasn't issued") && note.contains("traits changed"), "\(note)")
    // a radar left open ends the chain; the next costs 10 W again
    r = await db.radar(RadarReq(id: "minty", session: s, walk: text(withIt)), now: 10_200)
    r = await db.radar(RadarReq(id: "minty", session: s, walk: text(withIt)), now: 10_210)
    #expect(flag(r, "free") == false && number(r, "chain") == 0)
    var poor = withIt; poor.watts = 5
    r = await db.radar(RadarReq(id: "minty", session: s, walk: text(poor)), now: 10_220)
    #expect(r.status == 402)
    // an egg hatches once; the legend shop sells 칠색조 for 9,999 W; 토중몬 → 아이스크 issues a 껍질몬
    var eggy = withIt; eggy.egg = Egg(dex: eggPool[0], left: 0)
    r = await db.hatch(HatchReq(id: "minty", session: s, walk: text(eggy)), now: 10_300)
    #expect(r.status == 200 && mon(r)?.level == 1 && mon(r)?.dex == eggPool[0])
    r = await db.hatch(HatchReq(id: "minty", session: s, walk: text(eggy)), now: 10_301)
    #expect(string(r, "error") == "hatched")
    var rich = withIt; rich.watts = 9999
    r = await db.buy(BuyReq(id: "minty", session: s, walk: text(rich), index: 0), now: 10_400)
    #expect(mon(r)?.dex == 250 && mon(r)?.level == 50 && (mon(r)?.ivs?.filter { $0 == 31 }.count ?? 0) >= 3)
    r = await db.buy(BuyReq(id: "minty", session: s, walk: text(withIt), index: 0), now: 10_401)
    #expect(r.status == 402)
    let nincada = try await db.nextUID("minty")
    var nin = Mon.wild(290, level: 20, &g); nin.uid = nincada
    try await db.record("minty", nin, kind: "test", now: 10_499)                                     // a 토중몬 on record (no roll)
    r = await db.evolve(EvolveReq(id: "minty", session: s, uid: nincada, to: 291, level: 20), now: 10_500)
    let shed = string(r, "shedinja").flatMap { try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) }
    #expect(shed?.dex == 292 && shed?.level == 20 && shed?.shiny == nin.shiny)
    r = await db.evolve(EvolveReq(id: "minty", session: s, uid: nincada, to: 150, level: 20), now: 10_501)
    #expect(string(r, "error") == "no_evolution")
    // a create that sends a PIN without "app" is 2.1's too: its starter is issued
    r = await db.create(CreateReq(id: "noapp", device: "mac", device_name: "MAC", app: nil, pin: "1212"), now: 10_600)
    let noapp = try await db.minting("noapp")
    #expect(number(r, "starter") == firstUID && noapp)
    // a 2.0 trainer's first 2.1 login: its Pokémon taken as issued, uids stamped (rev + 1)
    let old = try await make(db, "veteran")
    r = await db.radar(RadarReq(id: "veteran", session: old, walk: text(Walk())), now: 10_900)
    #expect(r.status == 403)                                                                       // no PIN yet; with one and nothing on record: relogin
    var vw = Walk(); vw.audited = 2; vw.box = [Mon.wild(16, level: 9, &g)]
    _ = await save(db, "veteran", old, base: 0, walk: text(vw), app: "2.0", now: 11_000)
    r = await db.login(LoginReq(id: "veteran", device: "pc-a", device_name: "PC-A", app: "2.1", force: true), now: 11_010)
    let back = string(r, "walk").flatMap(decodeWalk)
    #expect(number(r, "rev") == 2 && back?.box.first?.uid != nil && back?.companion.uid != nil)
    let issued = try await db.minting("veteran")
    #expect(issued)
}

@Test func rejectForTestIDsOnly() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("pokeserver-zz-\(UUID().uuidString).db").path
    let db = try SaveDB(path: path, create: true, rejectTests: true)
    func text(_ w: Walk) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return String(decoding: try! e.encode(w), as: UTF8.self) }
    var w = Walk(); w.audited = 2; var rich = w; rich.watts = 9999
    for (id, refused) in [("zz123456", true), ("player", false), ("zz12345", false), ("zzabcdef", false)] {
        let s = try await make(db, id)
        _ = await save(db, id, s, base: 0, walk: text(w), now: 5_000)
        let r = await save(db, id, s, base: 1, walk: text(rich), now: 5_060)
        #expect((r.status == 422) == refused, "\(id): \(r.status)")
    }
}
