import Foundation
// What the logic asks of the platform it runs on. A platform sets `settings` and `host` first thing at launch (the Mac's: Sources/Mac/MacHost.swift).

/// The menu's choices, kept between launches by key; each read passes the default the app has always had. The Mac: UserDefaults (the same keys as ever).
protocol Settings {
    func bool(_ key: String, _ def: Bool) -> Bool
    func int(_ key: String, _ def: Int) -> Int
    func string(_ key: String, _ def: String) -> String
    func data(_ key: String) -> Data?
    func set(_ key: String, _ v: Bool); func set(_ key: String, _ v: Int); func set(_ key: String, _ v: String); func set(_ key: String, _ v: Data)
}
@MainActor var settings: (any Settings)! = nil

/// The platform's services the walker calls on.
@MainActor protocol Host {
    /// A banner from the app: title over body.
    func notify(_ title: String, _ body: String)
    /// Keys pressed + mouse clicks this login (it may wrap): the step counter Walk.sync reads.
    func counter() -> UInt32
    /// When this boot began (seconds since 1970): a new boot re-baselines the counter.
    func boot() -> Double
}
@MainActor var host: (any Host)! = nil

/// A bundled file's bytes by name ("hgss.bin", "Galmuri9.ttf"), from the app's Resources (the Mac's .app: Bundle.main); nil = missing.
func resource(_ name: String) -> Data? { Bundle.main.resourceURL.flatMap { try? Data(contentsOf: $0.appendingPathComponent(name), options: .mappedIfSafe) } }
