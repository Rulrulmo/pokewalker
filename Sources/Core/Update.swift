import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking                                                                       // URLSession on Windows (swift-corelibs)
#endif
// Auto-update (2.0). The release Mac signs each release (./build.sh publish, tools/release-key.swift); the save server only mirrors it. The app takes an
// update only when manifest.sig checks with releaseKey (Model/Ed25519.swift) over the manifest's exact bytes, it's newer than this app, it names this
// platform's zip, and that version never failed to go in here. The zip comes down quietly into Store.dir/update (its size and SHA-256 the manifest's,
// unpacked, the staged app's version checked) and goes in at the next quit or launch: a detached helper waits for this app to exit and swaps the new
// one in — the old one kept until it's in place, put back on failure, and that version noted as failed (no retry). Never in the self-test or a dev
// build (beside build.sh, App Translocation), nor where the app can't be replaced; until 2.0, only with the `cloud` setting, as the save server.

/// What doesn't need the main thread: the manifest's verdict, the download's checks and staging, the helper, the launch's step.
enum Update {
    /// This platform's line of a signed manifest.
    struct Entry: Equatable, Sendable { var version, sha256: String; var size: Int }
    /// A staged update (ready.json): its version and where the unpacked app is.
    struct Ready: Codable, Equatable { var version: String; var staged: String }
    enum Launch: Equatable { case none, installing, updated(String) }

    static var dir: URL { Store.dir.appendingPathComponent("update", isDirectory: true) }
    /// What a swap replaces: the Mac's .app, Windows' folder with PokeWalker.exe in it.
    static var appURL: URL? {
        #if os(Windows)
        resourceDir?.deletingLastPathComponent()
        #else
        Bundle.main.bundleURL
        #endif
    }
    /// The staged app inside the unpacked zip (the Mac's: PokeWalker.app at its top; Windows': a PokeWalker folder).
    static func stagedApp(_ staging: URL) -> URL {
        #if os(Windows)
        staging.appendingPathComponent("PokeWalker", isDirectory: true)
        #else
        staging.appendingPathComponent("PokeWalker.app", isDirectory: true)
        #endif
    }

    /// The update a server's answer offers, or nil: the release key's signature over these exact bytes, a manifest, newer than `over`, this
    /// platform's zip named, not a version that failed here before.
    static func accept(_ manifest: String, _ sig: String, platform: String, over app: String, failed: [String]) -> Entry? {
        guard let s = unhex(sig.trimmingCharacters(in: .whitespacesAndNewlines)), ed25519Verify(s, Array(manifest.utf8), releaseKey),
              let m = (try? JSONSerialization.jsonObject(with: Data(manifest.utf8))) as? [String: Any], let v = m["version"] as? String,
              verCmp(v, app) == 1, !failed.contains(v),
              let e = m[platform] as? [String: Any], let sha = e["sha256"] as? String, let size = e["size"] as? Int else { return nil }
        return Entry(version: v, sha256: sha.lowercased(), size: size)
    }
    /// Versions whose install failed here (the helper notes them): never tried again.
    static func failed(_ dir: URL) -> [String] {
        ((try? String(contentsOf: dir.appendingPathComponent("failed"), encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    }
    /// A manifest's version is newer than `app` — unchecked: only for what 업데이트 확인 says when it isn't taken (nothing newer, or it didn't check out).
    static func newer(_ manifest: String, than app: String) -> Bool {
        (((try? JSONSerialization.jsonObject(with: Data(manifest.utf8))) as? [String: Any])?["version"] as? String).map { verCmp($0, app) == 1 } ?? false
    }
    static func ready(_ dir: URL) -> Ready? { (try? Data(contentsOf: dir.appendingPathComponent("ready.json"))).flatMap { try? JSONDecoder().decode(Ready.self, from: $0) } }
    /// A downloaded zip: thrown away unless its size and SHA-256 are the signed manifest's, then staged. The staged app's path, or nil. (Off the main thread.)
    static func prepare(_ bytes: Data, _ e: Entry, dir: URL) -> String? {
        guard bytes.count == e.size, hex(sha256(Array(bytes))) == e.sha256 else { return nil }
        let zip = dir.appendingPathComponent("download.zip")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: zip) }
        guard (try? bytes.write(to: zip, options: .atomic)) != nil else { return nil }
        return stage(zip, version: e.version, dir: dir)
    }
    /// The zip unpacked into dir/staging and its app checked (the Mac's: Info.plist says `version`; Windows': PokeWalker.exe is there); ready.json written.
    static func stage(_ zip: URL, version: String, dir: URL) -> String? {
        let fm = FileManager.default, staging = dir.appendingPathComponent("staging", isDirectory: true), app = stagedApp(staging)
        try? fm.removeItem(at: staging); try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
        guard unpack(zip, to: staging), stagedVersion(app).map({ $0 == version }) ?? fm.fileExists(atPath: app.appendingPathComponent("PokeWalker.exe").path),
              let d = try? JSONEncoder().encode(Ready(version: version, staged: app.path)), (try? d.write(to: dir.appendingPathComponent("ready.json"), options: .atomic)) != nil
        else { try? fm.removeItem(at: staging); return nil }
        return app.path
    }
    /// The Mac's staged app's version (Contents/Info.plist); nil on Windows (its exe has no plist).
    static func stagedVersion(_ app: URL) -> String? {
        #if os(Windows)
        return nil
        #else
        guard let d = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let p = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any] else { return "" }   // "": not the version, whatever it was
        return p["CFBundleShortVersionString"] as? String ?? ""
        #endif
    }
    static func native(_ u: URL) -> String { u.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? u.path }
    static func unpack(_ zip: URL, to dest: URL) -> Bool {
        let p = Process()
        #if os(Windows)
        p.executableURL = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows") + "\\System32\\tar.exe")
        p.arguments = ["-xf", native(zip), "-C", native(dest)]
        #else
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); p.arguments = ["-x", "-k", native(zip), native(dest)]
        #endif
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit(); return p.terminationStatus == 0
    }
    /// Whether this app may update itself: not a dev build (build.sh beside it, or beside its dist/), not run from App Translocation (a random
    /// read-only copy of a download), and its folder writable (the swap renames it).
    static func allowed(_ app: URL) -> Bool {
        let fm = FileManager.default, parent = app.deletingLastPathComponent()
        if app.path.contains("/AppTranslocation/") { return false }
        if Store.devBuild(app) { return false }
        return fm.isWritableFile(atPath: parent.path) && fm.isWritableFile(atPath: app.path)
    }

    /// Launch, before any UI: a staged newer version goes in (the helper starts it again once this one exits: the caller exits), or the one just
    /// installed is announced and the update folder cleared. A dev build leaves it all alone.
    static func atLaunch(dir: URL = Update.dir, app: URL? = Update.appURL) -> Launch {
        guard let r = ready(dir), let app, allowed(app) else { return .none }
        switch verCmp(r.version, appVersion) {
        case 1?: return install(dir: dir, app: app, relaunch: true) ? .installing : .none
        case 0?: try? FileManager.default.removeItem(at: dir); return .updated(r.version)
        default: try? FileManager.default.removeItem(at: dir.appendingPathComponent("ready.json")); return .none   // older than this app: gone by
        }
    }
    /// The detached helper for a staged newer version: it waits for this process to exit, then swaps. relaunch: start the new app after (at launch;
    /// not at quit — the user quit). false = nothing staged, or it couldn't start.
    static func install(dir: URL, app: URL, relaunch: Bool) -> Bool {
        guard allowed(app), let r = ready(dir), verCmp(r.version, appVersion) == 1, FileManager.default.fileExists(atPath: r.staged) else { return false }
        let pid = String(ProcessInfo.processInfo.processIdentifier), p = Process()
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        #if os(Windows)
        let script = dir.appendingPathComponent("install.ps1")
        guard (try? Data(windowsHelper.utf8).write(to: script, options: .atomic)) != nil else { return false }
        p.executableURL = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows") + "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")
        p.arguments = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", native(script), "-ProcessId", pid, "-App", native(app),
                       "-New", native(URL(fileURLWithPath: r.staged)), "-Dir", native(dir), "-Version", r.version, "-Again", relaunch ? "1" : "0"]
        #else
        let script = dir.appendingPathComponent("install.sh")
        guard (try? Data(macHelper.utf8).write(to: script, options: .atomic)) != nil else { return false }
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, pid, app.path, r.staged, dir.path, r.version, relaunch ? "1" : "0"]
        #endif
        return (try? p.run()) != nil
    }
    /// --stage-update <zip>: a local build's zip (./build.sh dist) staged as if it had come down — no network, no signature (it's this Mac's own) —
    /// to try the install: the next quit or launch puts it in. The Mac's only (the version comes from its Info.plist).
    static func stageLocal(_ zip: URL, dir: URL = Update.dir) -> Bool {
        let probe = dir.appendingPathComponent("probe", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: probe) }
        try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
        guard unpack(zip, to: probe), let v = stagedVersion(stagedApp(probe)), verCmp(v, appVersion) == 1 else { return false }
        return stage(zip, version: v, dir: dir) != nil
    }

    static let macHelper = #"""
        #!/bin/sh
        # PokeWalker's installer (Core/Update.swift): $1 the app's pid, $2 the app, $3 the staged one, $4 the update folder, $5 its version, $6 = 1: open it
        # after. Once the app has exited the staged one takes its place; the old one is kept until it has, and put back on failure (the version noted as failed).
        pid=$1 app=$2 new=$3 dir=$4 ver=$5 again=$6 old="$2.old-update"
        exec > "$dir/install.log" 2>&1
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "$old"
        if mv "$app" "$old" && mv "$new" "$app"; then rm -rf "$old"; echo "installed $ver"
        else [ -e "$app" ] || mv "$old" "$app"; echo "$ver" >> "$dir/failed"; rm -f "$dir/ready.json"; echo "failed $ver: the old app is back"; fi
        [ "$again" = 1 ] && open "$app"
        exit 0
        """#
    static let windowsHelper = #"""
        param([int]$ProcessId, [string]$App, [string]$New, [string]$Dir, [string]$Version, [int]$Again)
        # PokeWalker's installer (Core/Update.swift): once the app has exited, $New takes $App's place; the old one is kept until it has, and put back
        # on failure (the version noted as failed: no retry). -Again 1: start the new one after.
        Start-Transcript -Path (Join-Path $Dir 'install.log') -Force | Out-Null
        Wait-Process -Id $ProcessId -ErrorAction SilentlyContinue
        $old = "$App.old-update"; $ok = $false
        Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 20 -and -not (Test-Path -LiteralPath $old); $i++) {
            try { Rename-Item -LiteralPath $App -NewName (Split-Path $old -Leaf) -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 }
        }
        if (Test-Path -LiteralPath $old) {
            try { Copy-Item -LiteralPath $New -Destination $App -Recurse -ErrorAction Stop; $ok = Test-Path -LiteralPath (Join-Path $App 'PokeWalker.exe') } catch { }
        }
        if ($ok) { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $New -Recurse -Force -ErrorAction SilentlyContinue; "installed $Version" }
        else {
            if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $App -Recurse -Force -ErrorAction SilentlyContinue; Rename-Item -LiteralPath $old -NewName (Split-Path $App -Leaf) }
            Add-Content -LiteralPath (Join-Path $Dir 'failed') -Value $Version
            Remove-Item -LiteralPath (Join-Path $Dir 'ready.json') -ErrorAction SilentlyContinue
            "failed $Version: the old app is back"
        }
        Stop-Transcript | Out-Null
        if ($Again -eq 1) { Start-Process -FilePath (Join-Path $App 'PokeWalker.exe') }
        """#
}

/// Replies as they come (URLSession's queue), taken on the main thread.
final class UpdateInbox: @unchecked Sendable {
    enum Item: Sendable { case answer(Int, Data), staged(String, String?) }
    private let lock = NSLock(); private var items: [Item] = []
    func put(_ x: Item) { lock.lock(); items.append(x); lock.unlock() }
    func take() -> [Item] { lock.lock(); defer { lock.unlock() }; let t = items; items = []; return t }
}

/// The walker's: asks ~30 s after launch, then every 6 h (and at once on 426: a newer app is out), downloads and stages. What's staged goes in at the
/// quit (Walker.quitSave) or the next launch (Update.atLaunch), with the cloud setting or not: only a signed download (or --stage-update) stages.
@MainActor final class Updater {
    static let first: TimeInterval = 30, period: TimeInterval = 6 * 3600
    let link: any CloudLink, dir: URL, app: URL, platform: String, inbox = UpdateInbox()
    private(set) var nextCheck: Date, busy = false
    var staged: String? = nil                                              // a version just staged: the walker's banner (once a version)
    /// How a check ended with nothing staged: nothing newer, or it didn't work (offline, an error, a download that didn't check out).
    enum Heard: Equatable { case newest, failed }
    var heard: Heard? = nil                                                // the last check's, for 업데이트 확인 (the walker clears it)
    private(set) var fetching: String? = nil                               // the version downloading

    init(link: any CloudLink, dir: URL, app: URL, platform: String = appPlatform, now: Date = Date()) {
        self.link = link; self.dir = dir; self.app = app; self.platform = platform; nextCheck = now.addingTimeInterval(Updater.first)
    }
    /// The app's: never with persist == false (the self-test, renders), a dev build, an app it can't replace, or (until 2.0) the `cloud` setting off.
    static func app(persist: Bool) -> Updater? {
        guard persist, settings.bool("cloud", true), let a = Update.appURL, Update.allowed(a) else { return nil }
        return Updater(link: HTTPLink(), dir: Update.dir, app: a)
    }
    func tick(_ now: Date) {
        for r in inbox.take() { take(r) }
        guard !busy, now >= nextCheck else { return }
        nextCheck = now.addingTimeInterval(Updater.period); busy = true; heard = nil
        let body = (try? JSONSerialization.data(withJSONObject: ["app": appVersion, "platform": platform])) ?? Data()
        link.post("v1/update", body) { [inbox] s, d in inbox.put(.answer(s, d)) }
    }
    /// 426 from the save server: a newer app is out — ask now.
    func checkNow() { nextCheck = .distantPast }

    private func take(_ r: UpdateInbox.Item) {
        switch r {
        case .answer(let s, let d):
            guard let j = s == 200 ? (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] : nil else { busy = false; heard = .failed; return }   // offline: the next round
            guard let m = j["manifest"] as? String, let sig = j["sig"] as? String else { busy = false; heard = .newest; return }        // nothing released yet
            guard let e = Update.accept(m, sig, platform: platform, over: appVersion, failed: Update.failed(dir)) else {
                busy = false; heard = Update.newer(m, than: appVersion) ? .failed : .newest; return                                   // a newer one not taken: bad signature, no zip here …
            }
            guard Update.ready(dir)?.version != e.version else { busy = false; return }           // staged already
            fetching = e.version
            let (dir, inbox) = (self.dir, self.inbox)
            link.get("v1/download/\(platform)") { s, d in inbox.put(.staged(e.version, s == 200 ? Update.prepare(d, e, dir: dir) : nil)) }   // the SHA-256 and the unpacking here, off the main thread
        case .staged(let v, let path):
            busy = false; fetching = nil; if path != nil { staged = v } else { heard = .failed }
            NSLog(path != nil ? "pokewalker: update %@ is ready: it goes in at the next quit or launch" : "pokewalker: update %@ didn't check out: again next round", v)
        }
    }
}

extension Walker {
    /// A staged update newer than this app, the updater on: the menu's 업데이트 설치 offers it.
    var stagedUpdate: String? { updater.flatMap { Update.ready($0.dir) }.flatMap { verCmp($0.version, appVersion) == 1 ? $0.version : nil } }
    /// Why not now (the row is greyed with it): a fight, a show or a tower run on — nothing in progress is lost to a restart.
    var installBlocker: String? {
        if inBattle || towerRun { return "배틀이 끝나면" }
        switch screen { case .beats, .evolve, .hatch, .radar: return "지금 하는 게 끝나면"; default: break }
        return waiting != nil ? "지금 하는 게 끝나면" : nil
    }
    /// The menu's row (no question asked: the click is the consent): a staged one installs; else one click checks, downloads and installs
    /// (installWhenStaged); greyed while a check or a download is on, or with a fight or a show on.
    func updateRow(_ u: Updater) -> MenuItem {
        if let v = stagedUpdate {
            if let why = installBlocker { return MenuItem("업데이트 설치 · \(v) — \(why)", enabled: false) }
            return MenuItem("업데이트 설치 (다시 시작) · \(v)", action: { self.installSoon(v, Date()) })
        }
        if u.busy || installWhenStaged { return MenuItem(u.fetching.map { "업데이트 받는 중… · \($0)" } ?? "업데이트 확인 중…", enabled: false) }
        return MenuItem("업데이트 확인 · 설치", action: { self.checkAndInstall() })
    }
    /// 업데이트 확인 · 설치: asked now; what it finds goes in (updateTick).
    func checkAndInstall() { guard let u = updater, !u.busy else { return }; installWhenStaged = true; u.heard = nil; u.checkNow() }
    /// The LCD says so, then (installAt) the quit's own path (steps, a save, the server's answers, a flush) and the helper, which starts the new one.
    func installSoon(_ v: String, _ now: Date) {
        installWhenStaged = false; screen = .say([v + "로", "업데이트할게요"], next: .home, since: now); installAt = now.addingTimeInterval(1.5)
    }
    /// The tick's: a click's check answered — staged: in (once nothing's in progress); nothing newer, or it didn't work: said. Then the install itself.
    func updateTick(_ now: Date) {
        guard let u = updater else { return }
        if let v = u.staged { u.staged = nil; if !installWhenStaged { noteStaged(v) } }                // (a click's own download: no banner, it goes in)
        if installWhenStaged {
            if let v = stagedUpdate { if installBlocker == nil { installSoon(v, now) } }
            else if let h = u.heard {
                u.heard = nil; installWhenStaged = false
                let lines = h == .newest ? ["최신 버전이에요", appVersion] : ["업데이트를", "확인하지 못했어요"]
                if installBlocker == nil { screen = .say(lines, next: screen, since: now) } else { notify("update", lines.joined(separator: " "), "") }
            }
        }
        if let at = installAt, now >= at, installBlocker == nil, let h = host { installAt = nil; relaunchAfterQuit = true; h.quit() }
    }
    /// A download just staged: a banner, once a version.
    func noteStaged(_ v: String) {
        guard v != notedUpdate else { return }
        notedUpdate = v; updateNotices += 1
        notify("update", "\(v) 업데이트를 받아 두었어요", "우클릭 → 업데이트 설치로 바로 바꿀 수 있어요. 다음에 끄거나 켤 때도 바뀌어요.")
    }
    /// The first launch of a new version: it says so, on the LCD and as a banner.
    func announceUpdate(_ v: String) {
        screen = .say([v + "로", "업데이트했어요"], next: screen, since: Date())
        notify("unlock", v + "로 업데이트했어요", "PokeWalker가 새 버전이 되었어요")
    }
}
