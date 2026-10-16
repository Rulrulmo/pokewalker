import Foundation

// docs/plans/22 (5.1.2): a new version to some first — pokeserver rollout — and a note in each reply that a newer one is there for this app
// (pokeserver update-note), so it looks at once instead of at its hourly check. The candidate is a second release folder, release-next
// (RELEASE_DIR=/var/lib/pokewalker/release-next server/publish.sh v<ver>: signed and checked the same way); `release` stays everyone's and the
// page's. Who: the trainer (its key) — named, or a share of all by a hash of the key and the candidate's version. Only an app already at the
// stable version is offered the candidate (an older one comes up to the stable first), so a download is told apart by its User-Agent alone: an
// app at the stable version or newer and below the candidate gets the candidate's file (it was offered it), any other the stable's.
// Both off (no settings rows): /v1/update, the downloads and every reply exactly as before.

/// settings 'rollout' (JSON): a share in % of all trainers, or these trainers (keys) only. No row: off.
struct RolloutPlan: Codable, Equatable, Sendable {
    var percent: Int? = nil, names: [String]? = nil
    var label: String { names.map { "names " + $0.joined(separator: ",") } ?? percent.map { "\($0)%" } ?? "off" }
}

/// What the running server goes by (refreshed with the content switches): the two releases' versions, the plan, the note's switch.
struct RolloutNow: Sendable, Equatable {
    var stable: String? = nil                 // release's (signed)
    var next: String? = nil                   // release-next's (signed), nil: none
    var nextKinds: Set<String> = []           // the candidate's updater files: mac, windows-setup
    var plan: RolloutPlan? = nil
    var note = false, urgent = false

    /// 0..<100 for a trainer and a candidate: the same trainers first for one version, others for the next.
    static func bucket(_ key: String, _ version: String) -> Int {
        let h = sha256(Array("\(key)|\(version)".utf8))
        return Int((UInt32(h[0]) << 24 | UInt32(h[1]) << 16 | UInt32(h[2]) << 8 | UInt32(h[3])) % 100)
    }
    static func updaterKind(_ platform: String?) -> String { platform?.lowercased() == "windows" ? "windows-setup" : "mac" }
    /// The candidate's for this trainer: named, or in its share.
    func targets(_ key: String) -> Bool {
        guard let p = plan, let n = next else { return false }
        if let names = p.names { return names.contains(key) }
        return Self.bucket(key, n) < min(100, max(0, p.percent ?? 0))
    }
    /// The candidate is newer than the stable one.
    var nextAhead: Bool { stable.flatMap { s in next.flatMap { verCmp($0, s) } } == 1 }
    /// The version /v1/update gives this app: the candidate to a target already at the stable version (and its platform's updater file there), else the stable.
    func offer(key: String?, app: String?, platform: String?) -> String? {
        guard let s = stable else { return nil }
        guard nextAhead, let n = next, let key, targets(key), let app, (verCmp(app, s) ?? -1) >= 0, nextKinds.contains(Self.updaterKind(platform)) else { return s }
        return n
    }
    /// A download from an app at this version comes from the candidate's folder: at the stable version or newer, below the candidate.
    func downloadsNext(app: String?) -> Bool {
        guard nextAhead, let s = stable, let n = next, let app else { return false }
        return (verCmp(app, s) ?? -1) >= 0 && verCmp(n, app) == 1
    }
    /// update-note on: {"v": …, "urgent": …} when what this app is offered is newer than it — it checks /v1/update then (5.1.2 on).
    func noteJSON(key: String?, app: String?, platform: String?) -> String? {
        guard note, let app, !brokenWindowsUpdater(app: app, platform: platform), let v = offer(key: key, app: app, platform: platform), verCmp(v, app) == 1 else { return nil }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        return (try? e.encode(UpdateNote(v: v, urgent: urgent))).map { String(decoding: $0, as: UTF8.self) }
    }
}

/// The running server's RolloutNow (route handlers read it, the refresh sets it).
final class RolloutBox: @unchecked Sendable {
    private let lock = NSLock(); private var value = RolloutNow()
    var now: RolloutNow { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: RolloutNow) { lock.lock(); value = v; lock.unlock() }
}
let rolloutNow = RolloutBox()

/// A JSON object reply with "update" put first (the text spliced: the rest of the body byte for byte as it was).
func withUpdateNote(_ body: Data, _ note: String) -> Data {
    guard body.first == UInt8(ascii: "{") else { return body }
    let rest = body.dropFirst()
    let empty = rest.first(where: { ![UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t")].contains($0) }) == UInt8(ascii: "}")
    return Data("{\"update\":\(note)".utf8) + (empty ? Data() : Data(",".utf8)) + rest
}

/// The release folders: RELEASE_DIR (the page's and everyone's) and NEXT_RELEASE_DIR (else RELEASE_DIR + "-next").
func releaseDirs(_ env: [String: String]) -> (release: URL, next: URL) {
    let r = env["RELEASE_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "/var/lib/pokewalker/release"
    let n = env["NEXT_RELEASE_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? r + "-next"
    return (URL(fileURLWithPath: r, isDirectory: true), URL(fileURLWithPath: n, isDirectory: true))
}

/// A folder's signed manifest (the release key's signature of its exact text), or nil.
func signedManifest(_ f: ReleaseFiles) -> ReleaseFiles.Manifest? {
    guard let t = f.manifestText, let s = f.signature, ReleaseFiles.signed(t, s) else { return nil }
    return ReleaseFiles.parse(t)
}

extension SaveDB {
    func rolloutPlan() throws -> RolloutPlan? {
        try db.rows("SELECT value FROM settings WHERE name = 'rollout'").first?.text("value").flatMap { try? JSONDecoder().decode(RolloutPlan.self, from: Data($0.utf8)) }
    }
    func setRolloutPlan(_ p: RolloutPlan?) throws {
        guard let p else { try db.rows("DELETE FROM settings WHERE name = 'rollout'"); return }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        try db.rows("INSERT INTO settings (name, value) VALUES ('rollout', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(String(decoding: try e.encode(p), as: UTF8.self))])
    }
    func updateNote() throws -> Bool { try db.rows("SELECT value FROM settings WHERE name = 'update_note'").first?.text("value") == "on" }
    func setUpdateNote(_ on: Bool) throws -> String {
        try db.rows("INSERT INTO settings (name, value) VALUES ('update_note', :v) ON CONFLICT (name) DO UPDATE SET value = :v", ["v": .text(on ? "on" : "off")])
        return "update-note " + (on ? "on" : "off") + " — the running server takes it within \(content5Every) s"
    }
    /// The running server's RolloutNow: the two folders' signed manifests, the plan, the note, the urgent hint.
    func rolloutState(release: URL, next: URL) -> RolloutNow {
        var n = RolloutNow()
        n.stable = signedManifest(ReleaseFiles(dir: release))?.version
        if let m = signedManifest(ReleaseFiles(dir: next)) {
            n.next = m.version
            n.nextKinds = Set(["mac", "windows-setup"].filter { m.entry($0) != nil })
        }
        n.plan = (try? rolloutPlan()) ?? nil
        n.note = (try? updateNote()) ?? false
        n.urgent = (try? updateHint())?.urgent ?? false
        return n
    }

    /// pokeserver rollout: the two versions, the plan, and each trainer seen this week — the candidate's or not, the app it has.
    func rolloutReport(release: URL, next: URL, now: Int) throws -> String {
        let s = rolloutState(release: release, next: next)
        var out = "stable \(s.stable ?? "-") (\(release.path)) · next \(s.next ?? "none") (\(next.path))" + (s.next != nil && !s.nextAhead ? " — not newer: nothing to roll out" : "")
        out += "\nrollout \(s.plan?.label ?? "off") · update-note \(s.note ? "on" : "off") · urgent \(s.urgent ? "yes" : "no")"
        guard s.next != nil else { return out }
        let rows = try db.rows("SELECT key, app_seen FROM trainers WHERE updated_at > :t AND key NOT LIKE 'zz%' ORDER BY key", ["t": .int(now - 7 * 86400)])
        let mine = rows.filter { r in r.text("key").map(s.targets) ?? false }
        out += "\nthe candidate's (\(mine.count) of \(rows.count) seen this week): " + mine.map { "\($0.show("key")) (\($0.show("app_seen")))" }.joined(separator: ", ")
        return out
    }
    /// pokeserver rollout off | <n>% | <id>[,<id>…]: names must be trainers.
    func setRollout(_ arg: String) throws -> String {
        if arg == "off" { try setRolloutPlan(nil); return "rollout off — /v1/update gives the stable release to everyone (an app already on the candidate keeps it)" }
        if arg.hasSuffix("%"), let p = Int(arg.dropLast()), (0...100).contains(p) { try setRolloutPlan(RolloutPlan(percent: p)); return "rollout \(p)% of trainers (by key and the candidate's version)" }
        let ids = arg.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !ids.isEmpty else { throw ServerError(description: "rollout: off | <0-100>% | <id>[,<id>…]") }
        let keys = try ids.map { i -> String in
            guard let k = trainerID(i)?.key, try trainer(k) != nil else { throw ServerError(description: "rollout: no trainer \(i)") }
            return k
        }
        try setRolloutPlan(RolloutPlan(names: keys))
        return "rollout to \(keys.joined(separator: ", ")) only"
    }
}
