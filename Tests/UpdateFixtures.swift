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
    var manifest: String? = fixtureManifest99, sig: String? = fixtureSig99, zip = Data(fixtureZip99.mac), paths: [String] = []
    func post(_ path: String, _ json: Data, done: @escaping @Sendable (Int, Data) -> Void) {
        paths.append(path)
        done(200, (try? JSONSerialization.data(withJSONObject: ["manifest": (manifest as Any?) ?? NSNull(), "sig": (sig as Any?) ?? NSNull()])) ?? Data())
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

    let srv = FakeCloud(); srv.old = "9.0"                                                          // the save server answers 426
    let uw = Walker(state: Walk()); uw.persist = false
    let uc = Cloud(link: srv, dir: tmp.appendingPathComponent("c"), on: true); uc.seat.trainerID = "zz000009"; uw.startCloud(uc)
    let link3 = FakeUpdates(); link3.manifest = nil; link3.sig = nil
    uw.updater = Updater(link: link3, dir: tmp.appendingPathComponent("u5"), app: shipped, platform: "mac", now: t0)
    for k in 0..<4 { uw.tick(t0 + 0.5 * Double(k)) }
    c.append((uc.phase == .oldApp && link3.paths == ["v1/update"], "update: 426 from the save server (새 버전이 필요해요) asks for an update at once"))
    return c
}
