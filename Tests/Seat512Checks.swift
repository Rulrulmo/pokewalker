import Foundation
// 5.1.2 (10-16: krackde's cloud.json lost three times in a day, a new device ID each; settings.json the same way): self-test checks (run by
// selftest()) — a cloud.json that doesn't decode kept aside and the bak's login back (its device, no steps), none: the ID box says why; one that
// won't read (a lock) never written over, and taken once it reads; cloud.json gone, the bak's; the bak written with the login, not the steps;
// settings.json the same; install.log's last lines (UTF-16LE from the installer, UTF-8 from the Mac's helper) for the update report.

@MainActor func seat512Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let fm = FileManager.default
    func tmp(_ n: String) -> URL { let u = fm.temporaryDirectory.appendingPathComponent("pokewalker-seat512-\(ProcessInfo.processInfo.processIdentifier)-\(n)", isDirectory: true); try? fm.removeItem(at: u); try? fm.createDirectory(at: u, withIntermediateDirectories: true); return u }
    func put(_ u: URL, _ s: String) { try? s.write(to: u, atomically: true, encoding: .utf8) }
    func bads(_ d: URL, _ name: String) -> Int { ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).filter { $0.hasPrefix(name + ".bad-") }.count }
    let login = #"{"device":"d0d0","session":"s1","trainerID":"zz900512","trust":"t1"}"#
    // a cloud.json that doesn't decode, the bak there
    let a = tmp("a"); put(a.appendingPathComponent("cloud.json"), "{\"trainerID\":"); put(a.appendingPathComponent("cloud.json.bak"), login)
    let ca = Cloud(link: FakeCloud(), dir: a)
    let fromBak = ca.seat.trainerID == "zz900512" && ca.seat.device == "d0d0" && ca.seat.steps == nil && bads(a, "cloud.json") == 1 && ca.seatNote != nil && !ca.firstRun
    // … no bak: a fresh seat, the ID box says why, nothing lost
    let b = tmp("b"); put(b.appendingPathComponent("cloud.json"), "garbage")
    let cb = Cloud(link: FakeCloud(), dir: b), h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h; w.cloud = cb
    h.texts = []; _ = w.askID()
    let fresh = cb.seat.trainerID == nil && bads(b, "cloud.json") == 1 && !cb.firstRun && h.boxes.first?.contains("읽지 못했어요") == true
    // one that won't read (a folder where the file should be: as a lock): not written over; once it reads, it's this PC's
    let d = tmp("d"); try? fm.createDirectory(at: d.appendingPathComponent("cloud.json"), withIntermediateDirectories: true)
    let cd = Cloud(link: FakeCloud(), dir: d)
    var isDir: ObjCBool = false
    let held = fm.fileExists(atPath: d.appendingPathComponent("cloud.json").path, isDirectory: &isDir) && isDir.boolValue && cd.seatNote != nil && cd.seat.trainerID == nil
    try? fm.removeItem(at: d.appendingPathComponent("cloud.json")); put(d.appendingPathComponent("cloud.json"), login)   // the lock let go
    cd.seat.legacyUploaded = true                                                                // any write: it reads it first
    let taken = cd.seat.trainerID == "zz900512" && cd.seat.device == "d0d0" && cd.seatNote == nil && bads(d, "cloud.json") == 0
    // cloud.json gone, the bak there: the bak's, quietly; the bak follows the login, not the steps
    let e = tmp("e"); put(e.appendingPathComponent("cloud.json.bak"), login)
    let ce = Cloud(link: FakeCloud(), dir: e)
    let gone = ce.seat.trainerID == "zz900512" && ce.seatNote == nil && !ce.firstRun
    ce.seat.steps = 42
    let bakText = (try? String(contentsOf: e.appendingPathComponent("cloud.json.bak"), encoding: .utf8)) ?? ""
    let bak = (try? String(contentsOf: e.appendingPathComponent("cloud.json"), encoding: .utf8))?.contains("42") == true && !bakText.contains("42") && bakText.contains("zz900512")
    let f = tmp("f"), cf = Cloud(link: FakeCloud(), dir: f), first = cf.firstRun && cf.seatNote == nil                         // a new PC: as ever
    // settings.json: one that doesn't decode kept aside; one that won't read never written over, merged once it reads
    let g = tmp("g"), sf = g.appendingPathComponent("settings.json"); put(sf, "{oops")
    let s1 = JSONSettings(file: sf), setAside = s1.int("win.x", -1) == -1 && bads(g, "settings.json") == 1
    s1.set("win.x", 5); let wrote = (try? String(contentsOf: sf, encoding: .utf8))?.contains("win.x") == true
    let k = tmp("k"), kf = k.appendingPathComponent("settings.json"); try? fm.createDirectory(at: kf, withIntermediateDirectories: true)
    let s2 = JSONSettings(file: kf); s2.set("hidden", 0)
    let notOver = fm.fileExists(atPath: kf.path, isDirectory: &isDir) && isDir.boolValue
    try? fm.removeItem(at: kf); put(kf, #"{"saveSigned":1,"win.x":7}"#); s2.set("tips5", 3)
    let kv: [String: Int] = (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: kf))) ?? [:]
    let merged = kv["saveSigned"] == 1 && kv["win.x"] == 7 && kv["tips5"] == 3 && kv["hidden"] == 0
    // install.log: the installer's UTF-16LE (a BOM or not), the helper's UTF-8
    let l = tmp("l"), lf = l.appendingPathComponent("install.log")
    try? (Data([0xFF, 0xFE]) + "installed 5.1\r\nfailed 5.1.1: files couldn't be written to C:\\x\r\n".data(using: .utf16LittleEndian)!).write(to: lf)
    let w16 = Update.installLog(l) == "installed 5.1 | failed 5.1.1: files couldn't be written to C:\\x"
    put(lf, "start 5.1\nfailed 5.1: the old app is back\n"); let w8 = Update.installLog(l) == "start 5.1 | failed 5.1: the old app is back"
    try? fm.removeItem(at: lf); let none = Update.installLog(l) == nil
    for u in [a, b, d, e, f, g, k, l] { try? fm.removeItem(at: u) }
    let seatOK = fromBak && fresh && held && taken && gone && bak && first, filesOK = setAside && wrote && notOver && merged, logOK = w16 && w8 && none
    let ok = seatOK && filesOK && logOK
    c.append((ok, "5.1.2 login file: cloud.json that doesn't decode kept aside, the bak's login back (its device, no steps; none: the ID box says why); one that won't read never written over and taken once it reads; gone: the bak's; the bak follows the login, not the steps; settings.json the same (aside; held, then merged); install.log's last lines, UTF-16LE or UTF-8"))
    if !ok { print("seat512: \(fromBak) \(fresh) \(held) \(taken) \(gone) \(bak) \(first) \(setAside) \(wrote) \(notOver) \(merged) \(w16) \(w8) \(none) — \(String(describing: Update.installLog(l)))") }
    return c
}
