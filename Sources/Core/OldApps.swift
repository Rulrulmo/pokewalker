import Foundation
// 5.0 (docs/plans/18 §9.8): everyone installs 5.0 anew (the Mac from its disk image into 응용 프로그램, Windows by its installer); what's left of the
// old ones goes only when asked. A Mac finds the other PokeWalker.app copies older than this one (Spotlight: the same bundle ID; never a dev build,
// a disk image's, the Trash's) and the menu's button puts them in the Trash; a Windows zip's folder can't be found, so 5.0's first launch says it
// may go. The save is the server's and the settings stay where they were (Application Support, %APPDATA%): nothing to sign in again.

enum OldApps {
    /// Of Spotlight's paths, the copies that may go: an app older than `version`, not this one (`me`), not a dev build (build.sh beside it, or its
    /// dist/), not on a disk image (/Volumes) or in the Trash or a translocated copy.
    static func pick(_ paths: [String], me: String, version: String, versionOf: (String) -> String?) -> [String] {
        paths.filter { p in
            guard p.hasSuffix(".app"), p != me, !p.hasPrefix("/Volumes/"), !p.contains("/.Trash/"), !p.contains("/AppTranslocation/"),
                  !Store.devBuild(URL(fileURLWithPath: p)), let v = versionOf(p) else { return false }
            return verCmp(v, version) == -1
        }.sorted()
    }
    /// An app's version (its Info.plist's CFBundleShortVersionString).
    static func version(_ app: String) -> String? {
        guard let d = FileManager.default.contents(atPath: app + "/Contents/Info.plist"),
              let p = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any] else { return nil }
        return p["CFBundleShortVersionString"] as? String
    }
    /// Spotlight's apps with this bundle ID (a Mac; none if Spotlight is off). A second or two: called off the main thread.
    static func find(_ bundleID: String) -> [String] {
        #if os(macOS)
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind"); p.arguments = ["kMDItemCFBundleIdentifier == '\(bundleID)'"]
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: d, as: UTF8.self).split(separator: "\n").map(String.init)
        #else
        return []
        #endif
    }
}

extension Walker {
    /// At launch (the app's own, never a dev build's or a test's): a Mac looks for older copies (the menu's 예전 앱 row, a banner once for
    /// what it found); Windows says once that a zip's old folder may go.
    func lookForOldApps() {
        guard persist, let me = Update.appURL, !Store.devBuild(me) else { return }
        if appPlatform == "windows" {
            guard verCmp(appVersion, "5.0") != -1, !settings.bool("oldZipNoted", false) else { return }
            settings.set("oldZipNoted", true)
            notify("update", "예전 PokeWalker 폴더는 지워도 돼요", "zip으로 받아 쓰던 PokeWalker 폴더가 남아 있다면 지워도 돼요. 기록은 서버에, 설정은 이 PC에 그대로 있어요.")
            return
        }
        let id = Bundle.main.bundleIdentifier ?? "dev.khmin.pokewalker", path = me.path
        DispatchQueue.global(qos: .utility).async {
            let found = OldApps.pick(OldApps.find(id), me: path, version: appVersion, versionOf: OldApps.version)
            DispatchQueue.main.async { [weak self] in self?.oldAppsFound(found) }
        }
    }
    func oldAppsFound(_ found: [String]) {
        oldApps = found
        let seen = found.joined(separator: "\n").utf8.reduce(5381) { ($0 &* 33 &+ Int($1)) & 0x7fff_ffff }   // (a launch-stable hash of what was found: said once)
        guard !found.isEmpty, persist, settings.int("oldAppsNoted", 0) != seen else { return }
        settings.set("oldAppsNoted", seen)
        notify("update", "예전 PokeWalker가 \(found.count)개 있어요", "우클릭 → 예전 앱 휴지통으로 · 기록은 서버에 있어서 그대로예요")
    }
    /// The menu's row while there are some: a click puts them in the Trash (what can't be moved, another admin's, stays and is said).
    var oldAppsRow: MenuItem? {
        oldApps.isEmpty ? nil : MenuItem("예전 앱 휴지통으로 (\(oldApps.count)개)", action: { self.trashOldApps(Date()) })
    }
    func trashOldApps(_ now: Date, trash: (URL) -> Bool = { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) != nil }) {
        let left = oldApps.filter { !trash(URL(fileURLWithPath: $0)) }
        let moved = oldApps.count - left.count; oldApps = left
        screen = .say(left.isEmpty ? ["예전 앱 \(moved)개를", "휴지통으로 옮겼어요"] : ["예전 앱 \(left.count)개는", "옮기지 못했어요"], next: screen, since: now)
    }
}

/// Self-test checks for this file (run by selftest()): which copies are offered, the button's moves (a fake Trash), Windows' note never in a test.
@MainActor func oldAppsChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let v = ["/Applications/PokeWalker.app": "4.1", "/Users/a/Downloads/PokeWalker.app": "3.8.6", "/Users/a/Downloads/PokeWalker 2.app": "5.0",
             "/Users/a/Desktop/old/PokeWalker.app": "4.0", "/Volumes/PokeWalker/PokeWalker.app": "4.1", "/Users/a/.Trash/PokeWalker.app": "3.0",
             "/Users/a/Downloads/PokeWalker.app/Contents/Resources/x.app": nil, "/Applications/PokeWalker 5.app": "5.1"]
    let picked = OldApps.pick(Array(v.keys) + ["/Users/a/Library/Caches/x.txt"], me: "/Applications/PokeWalker 5.app", version: "5.0", versionOf: { v[$0] ?? nil })
    c.append((picked == ["/Applications/PokeWalker.app", "/Users/a/Desktop/old/PokeWalker.app", "/Users/a/Downloads/PokeWalker.app"],
              "5.0 old apps: only copies older than this one (not itself, a newer or the same, a disk image's, the Trash's, an unreadable one)" + (picked.count == 3 ? "" : " — \(picked)")))
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    c.append((OldApps.pick([repo.appendingPathComponent("PokeWalker.app").path, repo.appendingPathComponent("dist/PokeWalker.app").path], me: "/x.app", version: "9.0", versionOf: { _ in "1.0" }).isEmpty,
              "5.0 old apps: a dev build (build.sh beside it, or its dist/) is never offered"))
    let w = Walker(state: Walk()); w.persist = false; w.screen = .home
    w.lookForOldApps(); let quiet = w.oldApps.isEmpty && w.oldAppsRow == nil
    w.oldApps = ["/a/PokeWalker.app", "/b/PokeWalker.app"]
    let row = w.oldAppsRow?.title == "예전 앱 휴지통으로 (2개)"
    var tried: [String] = []
    w.trashOldApps(Date()) { tried.append($0.path); return $0.path == "/a/PokeWalker.app" }
    let one: Bool = { if case .say(["예전 앱 1개는", "옮기지 못했어요"], _, _) = w.screen { return w.oldApps == ["/b/PokeWalker.app"] }; return false }()
    w.trashOldApps(Date()) { _ in true }
    let all: Bool = { if case .say(["예전 앱 1개를", "휴지통으로 옮겼어요"], _, _) = w.screen { return w.oldApps.isEmpty && w.oldAppsRow == nil }; return false }()
    c.append((quiet && row && tried == ["/a/PokeWalker.app", "/b/PokeWalker.app"] && one && all,
              "5.0 old apps: a test walker never looks; the menu's row moves them, says what it couldn't, and goes once they're gone"))
    return c
}
