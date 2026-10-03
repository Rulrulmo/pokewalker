import Foundation

// MARK: - save
enum Store {
    #if os(Windows)
    static let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APPDATA"] ?? NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("PokeWalker", isDirectory: true)   // %APPDATA%\PokeWalker (Roaming, next to settings.json)
    #else
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PokeWalker", isDirectory: true)
    #endif
    static let file = dir.appendingPathComponent("state.json")
    static let bak = dir.appendingPathComponent("state.json.bak")

    static func sig(_ u: URL) -> URL { u.deletingLastPathComponent().appendingPathComponent(u.lastPathComponent + ".sig") }
    /// `file` first, then `bak`. A file that isn't loaded is moved aside (state.corrupt-<unix>.json: unreadable; state.rejected-<unix>.json: its signature
    /// is off; `.bak.json` for the bak), with its .sig, so the saves that follow can't rotate it away: nothing the player had is ever deleted.
    static func load(file: URL = Store.file, bak: URL = Store.bak) -> Walk { loadChecked(file: file, bak: bak, signedBefore: false).walk }
    /// load, signatures checked: once this machine has signed a save (signedBefore), a `file` without a matching signature was changed outside
    /// the app — the last save the app made (`bak`) comes back instead (tampered = true), or, when that's no good either, a fresh walker.
    /// An unsigned save is fine until then (one from before 1.8, or brought from another machine without its .sig).
    static func loadChecked(file: URL = Store.file, bak: URL = Store.bak, signedBefore: Bool) -> (walk: Walk, tampered: Bool) {
        func read(_ u: URL) -> (s: Walk, signed: Bool?)? {
            guard let d = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(Walk.self, from: d), s.version == Walk().version else { return nil }
            return (s, (try? String(contentsOf: sig(u), encoding: .utf8)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) == saveSignature(d) })
        }
        func good(_ r: (s: Walk, signed: Bool?)?) -> Walk? { r.flatMap { $0.signed == true || ($0.signed == nil && !signedBefore) ? $0.s : nil } }
        let main = read(file)
        if let m = good(main) { return (m, false) }
        if FileManager.default.fileExists(atPath: file.path) { setAside(file, main == nil ? "corrupt" : "rejected") }   // read but its signature is off: changed by hand
        let back = read(bak)
        if let b = good(back) { return (b, main != nil) }
        if FileManager.default.fileExists(atPath: bak.path) { setAside(bak, back == nil ? "corrupt" : "rejected", suffix: ".bak") }
        return (Walk(), main != nil)
    }
    /// u (and its .sig) → state.<why>-<unix>[-n]<suffix>.json next to it.
    static func setAside(_ u: URL, _ why: String, suffix: String = "") {
        let fm = FileManager.default, dir = u.deletingLastPathComponent(), stamp = "state.\(why)-\(Int(Date().timeIntervalSince1970))"
        var n = 0, to = dir.appendingPathComponent(stamp + suffix + ".json")
        while fm.fileExists(atPath: to.path) { n += 1; to = dir.appendingPathComponent("\(stamp)-\(n)\(suffix).json") }   // two in one second: neither lost
        try? fm.moveItem(at: u, to: to)
        if fm.fileExists(atPath: sig(u).path) { try? fm.moveItem(at: sig(u), to: sig(to)) }
        NSLog("pokewalker: %@ not loaded (%@), kept as %@", u.path, why, to.lastPathComponent)
    }
    /// The save from before the server (docs/plans/08 §5), kept as it was: the game never reads it again; it goes up once as the trainer's 옛 기록.
    static func preServer(_ file: URL = Store.file) -> URL { file.deletingLastPathComponent().appendingPathComponent("state.pre-server.json") }
    /// The server's first launch here: a save that was never the server's (no cloudRev) goes aside with its .sig as state.pre-server.json, its bak as
    /// state.pre-server.bak.json — never over ones already there. true = it went.
    static func movePreServer(file: URL = Store.file, bak: URL = Store.bak) -> Bool {
        let fm = FileManager.default, to = preServer(file), bto = file.deletingLastPathComponent().appendingPathComponent("state.pre-server.bak.json")
        guard !fm.fileExists(atPath: to.path), let d = try? Data(contentsOf: file) else { return false }
        if let w = try? JSONDecoder().decode(Walk.self, from: d), w.cloudRev != nil { return false }      // the server's already
        func move(_ u: URL, _ v: URL) { try? fm.moveItem(at: u, to: v); if fm.fileExists(atPath: sig(u).path) { try? fm.moveItem(at: sig(u), to: sig(v)) } }
        move(file, to)
        if fm.fileExists(atPath: bak.path), !fm.fileExists(atPath: bto.path) { move(bak, bto) }
        return true
    }
    static func save(_ s: Walk, file: URL = Store.file, bak: URL = Store.bak) {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        guard let data = try? enc.encode(s) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: file.path) {                                                      // the last save, kept (signed); none (set aside at launch): the bak stays
            for (from, to) in [(file, bak), (sig(file), sig(bak))] { try? fm.removeItem(at: to); try? fm.copyItem(at: from, to: to) }
        }
        do { try data.write(to: file, options: .atomic); try saveSignature(data).write(to: sig(file), atomically: true, encoding: .utf8) }
        catch { NSLog("pokewalker: save failed: %@", "\(error)") }
    }
}
