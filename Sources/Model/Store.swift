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
    /// `file` first, then `bak`. An unreadable `file` is kept as `state.corrupt-<unix>.json` so the next save can't rotate it over the good `bak`.
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
        if main == nil, FileManager.default.fileExists(atPath: file.path) {
            let corrupt = file.deletingLastPathComponent().appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: corrupt)
            NSLog("pokewalker: %@ unreadable, kept as %@", file.path, corrupt.lastPathComponent)
        }
        if let m = good(main) { return (m, false) }
        return (good(read(bak)) ?? Walk(), main != nil)                                            // main read but failed its signature: changed by hand
    }
    static func save(_ s: Walk, file: URL = Store.file, bak: URL = Store.bak) {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        guard let data = try? enc.encode(s) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        for (from, to) in [(file, bak), (sig(file), sig(bak))] { try? fm.removeItem(at: to); try? fm.copyItem(at: from, to: to) }   // the last save, kept (signed)
        do { try data.write(to: file, options: .atomic); try saveSignature(data).write(to: sig(file), atomically: true, encoding: .utf8) }
        catch { NSLog("pokewalker: save failed: %@", "\(error)") }
    }
}
