import Foundation
// Public test data for the updater (auto-update U3): a release manifest for a made-up 9.9, written as ./build.sh publish writes them (compact, keys
// sorted, no newline at the end) and signed by the release key (swift tools/release-key.swift sign). Its "zips" are short texts, so a download
// that matches (fixtureZip99) and one that doesn't can both be checked; the commit is made up.

let fixtureManifest99 = #"{"build":"99","commit":"0123456789abcdef0123456789abcdef01234567","mac":{"file":"PokeWalker-mac.zip","sha256":"bf5ba371f96fb7f9510010a81bab68186b626413c095fb1aa614af4d6755ef95","size":19},"version":"9.9","windows":{"file":"PokeWalker-windows-x64.zip","sha256":"bab148b3d12b398bc10bbf7dde53796fa1ddf3d0903ca5f3acbfad7f8ae5a8d9","size":23}}"#
let fixtureSig99 = "fca8c07933621bdc02d62c1aee0616cc7d42f055d4e4a01bb11eb52939ec3d525e1049d6eaf218196c32fbfff0b41ed660fd37963cf7016dc49dff23ae49d201"
let fixtureZip99 = (mac: Array("pokewalker 9.9 mac\n".utf8), windows: Array("pokewalker 9.9 windows\n".utf8))

func updateFixtureChecks() -> [(Bool, String)] {
    let m = Array(fixtureManifest99.utf8), sig = unhex(fixtureSig99) ?? []
    var changed = m; changed[changed.count - 3] ^= 1                                              // a byte of the windows size
    let fields = (try? JSONSerialization.jsonObject(with: Data(m))) as? [String: Any], mac = fields?["mac"] as? [String: Any]
    return [(ed25519Verify(sig, m, releaseKey) && !ed25519Verify(sig, changed, releaseKey), "update fixtures: the made-up 9.9 manifest is the release key's; a changed byte isn't"),
            (fields?["version"] as? String == "9.9" && mac?["sha256"] as? String == hex(sha256(fixtureZip99.mac)) && mac?["size"] as? Int == fixtureZip99.mac.count,
             "update fixtures: its mac entry is fixtureZip99.mac's sha256 and size")]
}

/// The save server's update API in a few lines: the manifest and signature it gives (nil = no release), the zip it sends; what was asked.
final class FakeUpdates: CloudLink, @unchecked Sendable {
    var manifest: String? = fixtureManifest99, sig: String? = fixtureSig99, zip = Data(fixtureZip99.mac), paths: [String] = [], down = false   // down: no answer
    var bodies: [[String: Any]] = [], hints: [String: Any] = [:]                                   // 5.0: what was asked with; the unsigned hints given
    func post(_ path: String, _ json: Data, done: @escaping @Sendable (Int, Data) -> Void) {
        paths.append(path); bodies.append((try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:])
        if down { done(0, Data()); return }
        done(200, (try? JSONSerialization.data(withJSONObject: hints.merging(["manifest": (manifest as Any?) ?? NSNull(), "sig": (sig as Any?) ?? NSNull()]) { $1 })) ?? Data())
    }
    func get(_ path: String, done: @escaping @Sendable (Int, Data) -> Void) { paths.append(path); done(200, zip) }
}

/// Core/Update.swift: what's taken, the round, the download's checks, staging, the launch's step, 426. Nothing here starts the helper.
@MainActor func updateChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let fm = FileManager.default, tmp = fm.temporaryDirectory.appendingPathComponent("pokewalker-update-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? fm.removeItem(at: tmp) }
    let m = fixtureManifest99, sig = fixtureSig99, t0 = Date(timeIntervalSinceReferenceDate: 812_000_000)
    let mac = Update.accept(m, sig, platform: "mac", over: "1.15", failed: []), win = Update.accept(m, sig, platform: "windows", over: "2.0", failed: [])
    c.append((mac == Update.Entry(version: "9.9", sha256: hex(sha256(fixtureZip99.mac)), size: 19) && win?.size == 23, "update: a signed newer release is taken (9.9 over 1.15 / 2.0, each platform's zip)"))
    let bad = (sig.first == "0" ? "1" : "0") + sig.dropFirst()
    let not = [Update.accept(m, sig, platform: "mac", over: "9.9", failed: []), Update.accept(m, sig, platform: "mac", over: "10.0", failed: []),
               Update.accept(m, bad, platform: "mac", over: "1.15", failed: []), Update.accept(m + " ", sig, platform: "mac", over: "1.15", failed: []),
               Update.accept(m, sig, platform: "linux", over: "1.15", failed: []), Update.accept(m, sig, platform: "mac", over: "1.15", failed: ["9.9"])]
    c.append((not.allSatisfy { $0 == nil }, "update: not the same or a lower version, a bad signature, a changed manifest, no zip for this platform, a version that failed here"))

    let repo = tmp.appendingPathComponent("repo", isDirectory: true), shipped = tmp.appendingPathComponent("Applications/PokeWalker.app", isDirectory: true)
    for d in [repo.appendingPathComponent("PokeWalker.app"), repo.appendingPathComponent("dist/PokeWalker.app"), shipped] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
    fm.createFile(atPath: repo.appendingPathComponent("build.sh").path, contents: Data())
    c.append((!Update.allowed(repo.appendingPathComponent("PokeWalker.app")) && !Update.allowed(repo.appendingPathComponent("dist/PokeWalker.app"))
              && !Update.allowed(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/A1/d/PokeWalker.app")) && Update.allowed(shipped),
              "update: never a dev build (beside build.sh or its dist/) or App Translocation's copy; an installed app may"))

    let link = FakeUpdates(), u = Updater(link: link, dir: tmp.appendingPathComponent("u1"), app: shipped, platform: "mac", now: t0)
    u.tick(t0 + 10); let early = link.paths.isEmpty
    u.tick(t0 + 31); u.tick(t0 + 32); u.tick(t0 + 33)                                               // the question; its answer → the download; the download's verdict
    c.append((early && link.paths == ["v1/update", "v1/download/mac"] && !u.busy && u.nextCheck == t0 + 31 + Updater.period,
              "update: asked ~30 s after launch (then every 6 h); a signed newer one is downloaded"))
    let linkB = FakeUpdates(), uB = Updater(link: linkB, dir: tmp.appendingPathComponent("uB"), app: shipped, platform: "mac", now: t0, blocked: "앱을 응용 프로그램 폴더로 옮겨 주세요")
    uB.tick(t0 + 31); uB.tick(t0 + 32); uB.tick(t0 + 33)
    c.append((linkB.paths == ["v1/update"] && uB.available == "9.9" && uB.heard == .available && !uB.busy && Update.ready(tmp.appendingPathComponent("uB")) == nil
              && Update.blocker(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/A1/d/PokeWalker.app")) == "앱을 응용 프로그램 폴더로 옮겨 주세요"
              && Update.blocker(repo.appendingPathComponent("PokeWalker.app")) == "개발 빌드" && Update.blocker(shipped) == nil,
              "3.8.5: where it can't install (translocated, a folder it can't write) it still asks — a newer one is noted, never downloaded; the menu's why"))
    let link2 = FakeUpdates(); link2.zip = Data("pokewalker 9.9 maC\n".utf8)                       // the size, not the bytes
    let d2 = tmp.appendingPathComponent("u2"), u2 = Updater(link: link2, dir: d2, app: shipped, platform: "mac", now: t0)
    u2.tick(t0 + 31); u2.tick(t0 + 32); u2.tick(t0 + 33)
    c.append((link2.paths.count == 2 && ((try? fm.contentsOfDirectory(atPath: d2.path)) ?? []).isEmpty && !u2.busy && Update.ready(d2) == nil,
              "update: a download whose bytes aren't the signed manifest's is thrown away (again next round)"))
    #if os(macOS)
    let src = tmp.appendingPathComponent("src/PokeWalker.app/Contents", isDirectory: true), zip = tmp.appendingPathComponent("src.zip")
    try? fm.createDirectory(at: src, withIntermediateDirectories: true)
    try? PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "9.9"], format: .xml, options: 0).write(to: src.appendingPathComponent("Info.plist"))
    let ditto = Process(); ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); ditto.arguments = ["-c", "-k", "--keepParent", src.deletingLastPathComponent().path, zip.path]
    try? ditto.run(); ditto.waitUntilExit()
    let d3 = tmp.appendingPathComponent("u3"), d4 = tmp.appendingPathComponent("u4"), staged = Update.stage(zip, version: "9.9", dir: d3), wrong = Update.stage(zip, version: "9.8", dir: d4)
    c.append((staged != nil && Update.ready(d3) == Update.Ready(version: "9.9", staged: staged ?? "") && fm.fileExists(atPath: (staged ?? "") + "/Contents/Info.plist") && wrong == nil && Update.ready(d4) == nil,
              "update: the zip unpacks into staging, the app's version checked, ready.json written (an app of another version isn't staged)"))
    #endif

    func readyIn(_ name: String, _ v: String) -> URL {
        let d = tmp.appendingPathComponent(name); try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        try? JSONEncoder().encode(Update.Ready(version: v, staged: d.path)).write(to: d.appendingPathComponent("ready.json")); return d
    }
    let l1 = readyIn("l1", appVersion), l2 = readyIn("l2", "0.1"), l3 = readyIn("l3", "99.0")
    let a1 = Update.atLaunch(dir: l1, app: shipped), a2 = Update.atLaunch(dir: l2, app: shipped), a3 = Update.atLaunch(dir: l3, app: repo.appendingPathComponent("PokeWalker.app"))
    c.append((a1 == .updated(appVersion) && !fm.fileExists(atPath: l1.path) && a2 == .none && Update.ready(l2) == nil && a3 == .none && Update.ready(l3) != nil,
              "update at launch: the version just installed is announced (the folder cleared); an older staged one is dropped; a dev build installs nothing"))

    // 3.9.1 (Jyo's, 2026-10-08): an install tried for a version, and the app still the old one at the next launch → that version failed, never again,
    // and the app starts as it is (a launch never only hands off to an install that can't happen); an older one staged (a zip's from before) is cleared
    let g1 = readyIn("g1", "99.0"); try? Data("99.0".utf8).write(to: g1.appendingPathComponent("attempt"))
    try? Data().write(to: g1.appendingPathComponent("PokeWalker-setup.exe"))
    let ga = Update.atLaunch(dir: g1, app: shipped), gaAgain = Update.atLaunch(dir: g1, app: shipped)
    let g2 = readyIn("g2", "0.1"); try? fm.createDirectory(at: g2.appendingPathComponent("staging"), withIntermediateDirectories: true); _ = Update.atLaunch(dir: g2, app: shipped)
    c.append((ga == .none && gaAgain == .none && Update.ready(g1) == nil && Update.failed(g1) == ["99.0"] && Update.attempted(g1) == nil && !fm.fileExists(atPath: g1.appendingPathComponent("PokeWalker-setup.exe").path)
              && !fm.fileExists(atPath: g2.appendingPathComponent("staging").path) && Update.ready(g2) == nil,
              "3.9.1 update at launch: an install already tried for 99.0 and this still the old app → 99.0 failed (never again), what was staged cleared, the app starts; an older staged one is cleared"))
    let sEntry = Update.Entry(version: "9.9", sha256: hex(sha256(Array("setup".utf8))), size: 5), sd = tmp.appendingPathComponent("s1")
    let setupPath = Update.prepare(Data("setup".utf8), sEntry, dir: sd, setup: true), badSetup = Update.prepare(Data("setuq".utf8), sEntry, dir: tmp.appendingPathComponent("s2"), setup: true)
    c.append((setupPath?.hasSuffix("PokeWalker-setup.exe") == true && Update.ready(sd) == Update.Ready(version: "9.9", staged: setupPath ?? "") && (try? Data(contentsOf: URL(fileURLWithPath: setupPath ?? ""))) == Data("setup".utf8)
              && badSetup == nil && Update.downloadPath("windowsSetup") == "v1/download/windows-setup" && Update.downloadPath("mac") == "v1/download/mac"
              && Update.canWrite(tmp) && !Update.canWrite(tmp.appendingPathComponent("no-such-folder")),
              "3.9.1 Windows: the installer staged as it came (its size and SHA-256 the signed manifest's windowsSetup), from /v1/download/windows-setup; a folder's writable by writing in it"))

    let srv = FakeCloud(); srv.old = "9.0"                                                          // the save server answers 426
    let uw = Walker(state: Walk()); uw.persist = false
    let uc = Cloud(link: srv, dir: tmp.appendingPathComponent("c")); uc.seat.trainerID = "zz000009"; uw.startCloud(uc)
    let link3 = FakeUpdates(); link3.manifest = nil; link3.sig = nil
    uw.updater = Updater(link: link3, dir: tmp.appendingPathComponent("u5"), app: shipped, platform: "mac", now: t0)
    for k in 0..<4 { uw.tick(t0 + 0.5 * Double(k)) }
    c.append((uc.phase == .oldApp && link3.paths == ["v1/update"], "update: 426 from the save server (새 버전이 필요해요) asks for an update at once"))

    // the menu's update row: a staged one installs at a click (no question); else one click checks, downloads and installs; greyed while busy
    let ih = TestHost(), iw = Walker(state: Walk()); iw.persist = false; iw.host = ih
    let idir = tmp.appendingPathComponent("menu", isDirectory: true)
    iw.updater = Updater(link: FakeUpdates(), dir: idir, app: shipped, platform: "mac", now: t0)
    var installs: [Bool] = []; iw.installUpdate = { installs.append($0); return true }
    func updateRow(_ w: Walker) -> MenuItem? { w.menu().first { $0.title.hasPrefix("업데이트") } }
    func says(_ w: Walker, _ l: [String]) -> Bool { if case .say(let s, _, _) = w.screen { return s == l }; return false }
    let plain = Walker(state: Walk()), noRow = updateRow(plain) == nil, checkRow = updateRow(iw)
    _ = readyIn("menu", "99.0"); let row = updateRow(iw)
    iw.towerRun = true; let blockedRow = updateRow(iw); iw.towerRun = false
    updateRow(iw)?.action?(); let saysFirst = says(iw, ["99.0로", "업데이트할게요"]) && ih.quits == 0 && ih.asked.isEmpty
    let clickedAt = Date(); iw.tick(clickedAt + 1); let notYet = ih.quits == 0; iw.tick(clickedAt + 2)   // (a menu click: the real clock)
    let accepted = ih.quits == 1 && iw.relaunchAfterQuit
    iw.quitSave()
    c.append((noRow && checkRow?.title == "업데이트 확인 · 설치" && checkRow?.enabled == true && row?.enabled == true && row?.title == "업데이트 설치 (다시 시작) · 99.0"
              && blockedRow?.enabled == false && blockedRow?.title.contains("배틀이 끝나면") == true && saysFirst && notYet && accepted && installs == [true],
              "update row: 업데이트 확인 · 설치 with the updater on; staged: 업데이트 설치 (다시 시작) · v, greyed mid-run; a click (no question) says so, then the quit's path installs it to start again"))
    iw.updater?.staged = "99.0"; iw.tick(t0); iw.updater?.staged = "99.0"; iw.tick(t0 + 1); iw.updater?.staged = "99.1"; iw.tick(t0 + 2)
    c.append((iw.updateNotices == 2 && iw.notedUpdate == "99.1", "update: a staged download says so once a version (업데이트를 받아 두었어요)"))

    /// A walker whose 업데이트 확인 · 설치 was just clicked, against that link.
    func clicked(_ name: String, _ link: FakeUpdates) -> (Walker, TestHost) {
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h; w.installUpdate = { _ in true }
        w.updater = Updater(link: link, dir: tmp.appendingPathComponent(name, isDirectory: true), app: shipped, platform: "mac", now: t0)
        updateRow(w)?.action?(); return (w, h)
    }
    let same = FakeUpdates(); same.manifest = fixtureManifest99.replacingOccurrences(of: "\"9.9\"", with: "\"1.0\"")   // (its signature no longer checks: not asked)
    let (nw, nh) = clicked("c1", same); nw.tick(t0 + 1); let checking = updateRow(nw)?.title == "업데이트 확인 중…" && updateRow(nw)?.enabled == false
    nw.tick(t0 + 2)
    let newest = checking && says(nw, ["최신 버전이에요", appVersion]) && !nw.installWhenStaged && nh.quits == 0 && updateRow(nw)?.title == "업데이트 확인 · 설치"
    let none = FakeUpdates(); none.manifest = nil; none.sig = nil
    let (ew, _) = clicked("c2", none); ew.tick(t0 + 1); ew.tick(t0 + 2)
    c.append((newest && says(ew, ["최신 버전이에요", appVersion]) && same.paths == ["v1/update"],
              "update row: a click asks at once (greyed: 업데이트 확인 중…); nothing newer (or nothing released) → 최신 버전이에요 · this version, nothing downloaded"))
    let badZip = FakeUpdates(); badZip.zip = Data("x".utf8)
    let (fw, fh) = clicked("c3", badZip); fw.tick(t0 + 1); fw.tick(t0 + 2); let fetching = updateRow(fw)?.title == "업데이트 받는 중… · 9.9"
    fw.tick(t0 + 3)
    let off = FakeUpdates(); off.down = true
    let (ow, _) = clicked("c4", off); ow.tick(t0 + 1); ow.tick(t0 + 2)
    c.append((fetching && says(fw, ["업데이트를", "확인하지 못했어요"]) && !fw.installWhenStaged && fh.quits == 0 && says(ow, ["업데이트를", "확인하지 못했어요"]) && !ow.installWhenStaged,
              "update row: a newer one downloading (받는 중… · v); bytes that don't check out, or no answer → 업데이트를 확인하지 못했어요, and nothing goes in"))
    let (sw, sh) = clicked("c5", FakeUpdates()); sw.tick(t0 + 1); _ = readyIn("c5", "9.9")   // what the check finds is staged (a download, as far as the walker sees)
    sw.towerRun = true; sw.tick(t0 + 2); sw.tick(t0 + 5); let held = sh.quits == 0 && sw.installWhenStaged && updateRow(sw)?.enabled == false
    sw.towerRun = false; sw.tick(t0 + 6); let said = says(sw, ["9.9로", "업데이트할게요"]); sw.tick(t0 + 8)
    c.append((held && said && sh.quits == 1 && sw.relaunchAfterQuit && sw.updateNotices == 0,
              "update row: what a click finds staged goes in by itself (no banner) — after the tower run it came during, the LCD saying so first"))

    // 5.0 (docs/plans/18 §9.8): what /v1/update hears (the server's app_reports) and the hints it gives back
    let hl = FakeUpdates(); hl.manifest = nil; hl.sig = nil; hl.hints = ["urgent": true, "installBy": "2026-10-20T00:00:00Z"]
    let hu = Updater(link: hl, dir: tmp.appendingPathComponent("h1"), app: shipped, platform: "mac", now: t0)
    hu.tick(t0 + 31) { ["trainer": "zz123456", "staged": "99.0", "where": "applications"] }; hu.tick(t0 + 32)
    let sent = hl.bodies.first.map { $0["trainer"] as? String == "zz123456" && $0["staged"] as? String == "99.0" && $0["app"] as? String == appVersion && $0["platform"] as? String == appPlatform } == true
    let hinted = hu.urgent && hu.installBy == ISO8601DateFormatter().date(from: "2026-10-20T00:00:00Z")
    hu.tick(t0 + 32 + 3599); let hourly = hl.bodies.count == 1; hu.tick(t0 + 32 + 3601); hu.tick(t0 + 32 + 3602)
    let rw = Walker(state: Walk()); rw.persist = false
    rw.updater = Updater(link: FakeUpdates(), dir: readyIn("r1", "99.0"), app: shipped, platform: "mac", now: t0)
    try? "98.0\n".write(to: tmp.appendingPathComponent("r1/failed"), atomically: true, encoding: .utf8)
    let rep = rw.updateReport
    let report = rep["staged"] as? String == "99.0" && rep["blocked"] == nil && rep["failed"] as? [String] == ["98.0"] && rep["where"] as? String == "applications" && rep["trainer"] == nil
    let kinds = Update.whereKind(URL(fileURLWithPath: "/Users/a/Downloads/PokeWalker.app")) == "downloads" && Update.whereKind(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/A1/d/PokeWalker.app")) == "downloads"
        && Update.whereKind(URL(fileURLWithPath: "/C:/Users/a/AppData/Local/Programs/PokeWalker/PokeWalker.exe")) == "applications" && Update.whereKind(URL(fileURLWithPath: "/Users/a/Desktop/PokeWalker.app")) == "other"
        && Update.blockKind(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/A1/d/PokeWalker.app")) == "translocated" && Update.blockKind(repo.appendingPathComponent("PokeWalker.app")) == "dev" && Update.blockKind(shipped) == nil
    let okR = sent && hinted && hourly && hl.bodies.count == 2 && report && kinds
    c.append((okR, "5.0 update: /v1/update hears trainer · staged · blocked · failed · where (app and platform kept); urgent and installBy taken (then asked hourly); where's and why's words"
              + (okR ? "" : " — \(sent) \(hinted) \(hourly) \(hl.bodies.count) \(report) \(rep) \(kinds) \(hl.bodies)")))

    // 5.0: a staged one goes in by itself when nobody's at it (home, nothing on, no step or click for 3 minutes; 30 s urgent), started again quietly;
    // never mid-fight; the server wanting a newer app (426): at once; a day staged and still waiting: the banner again
    func autoWalker(_ name: String) -> (Walker, TestHost) {
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h; w.installUpdate = { _ in true }
        let l = FakeUpdates(); l.manifest = nil; l.sig = nil
        w.updater = Updater(link: l, dir: readyIn(name, "99.0"), app: shipped, platform: "mac", now: t0)
        w.screen = .home; w.lastInput = t0; w.lastStep = t0; return (w, h)
    }
    let (aw, ah) = autoWalker("a1")
    aw.tick(t0 + 120); let waits = !says(aw, ["99.0로", "업데이트할게요"])
    aw.tick(t0 + 181); let goes = says(aw, ["99.0로", "업데이트할게요"]) && Update.quiet; aw.tick(t0 + 184)
    let auto = waits && goes && ah.quits == 1 && aw.relaunchAfterQuit
    let (bw, bh) = autoWalker("a2"); bw.towerRun = true; bw.screen = .tower(pick: nil); bw.tick(t0 + 400); bw.tick(t0 + 403)
    let (uw2, uh2) = autoWalker("a3"); uw2.updater?.urgent = true; uw2.tick(t0 + 31); uw2.tick(t0 + 34)
    let auto426: Bool = {
        _ = readyIn("u5", "99.0"); let h = TestHost(); uw.host = h; uw.installUpdate = { _ in true }; uw.lastInput = Date(); uw.lastStep = Date()
        uw.tick(Date()); let said = says(uw, ["99.0로", "업데이트할게요"]) && !Update.quiet; uw.tick(Date() + 2); return said && h.quits == 1
    }()
    let (dw, _) = autoWalker("a4"); dw.notedUpdate = "99.0"; dw.notedAt = t0 - 90_000; dw.lastInput = t0 + 10; dw.tick(t0 + 20)
    let tagged = dw.updateWaits == "99.0" && dw.compose(t0 + 20).pics.contains { $0.key.hasPrefix("nb|new|") } && !{ let x = Walker(state: Walk()); x.persist = false; x.screen = .home; return x }().compose(t0).pics.contains { $0.key.hasPrefix("nb|new|") }
    c.append((auto && bh.quits == 0 && !says(bw, ["99.0로", "업데이트할게요"]) && uh2.quits == 1 && auto426 && dw.updateNotices == 1 && dw.notedAt == t0 + 20 && tagged,
              "5.0 update: in by itself at a lull (3 min on home; 30 s urgent), started again quietly; never mid-run; 426: at once; a day waiting: the banner again; home's NEW tag while one waits"))
    Update.quiet = false
    return c
}
