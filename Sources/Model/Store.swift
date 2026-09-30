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

    /// `file` first, then `bak`. An unreadable `file` is kept as `state.corrupt-<unix>.json` so the next save can't rotate it over the good `bak`.
    static func load(file: URL = Store.file, bak: URL = Store.bak) -> Walk {
        func read(_ u: URL) -> Walk? {
            guard let d = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(Walk.self, from: d), s.version == Walk().version else { return nil }
            return s
        }
        let main = read(file)
        if main == nil, FileManager.default.fileExists(atPath: file.path) {
            let corrupt = file.deletingLastPathComponent().appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: corrupt)
            NSLog("pokewalker: %@ unreadable, kept as %@", file.path, corrupt.lastPathComponent)
        }
        return main ?? read(bak) ?? Walk()
    }
    static func save(_ s: Walk, file: URL = Store.file, bak: URL = Store.bak) {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        guard let data = try? enc.encode(s) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: bak); try? fm.copyItem(at: file, to: bak)
        do { try data.write(to: file, options: .atomic) } catch { NSLog("pokewalker: save failed: %@", "\(error)") }
    }
}
