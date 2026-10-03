import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking                                                                       // URLSession on Windows (swift-corelibs)
#endif
// The save server's client (docs/plans/08 §4, 08b §4 / §10): login, create, save and legacy, one request at a time. Replies land in a locked inbox
// from URLSession's queue; tick (the walker's 10 Hz, on the main thread) takes them. No Task / MainActor hops: they may not run on Windows.
// On from 2.0 (the `cloud` setting, default on; off = the app as 1.x was), never with persist == false (the self-test, renders): then nothing goes out.
// The walker's hooks, the launch and the UI: P2 step 2b.

/// The wire: POST json to path, or GET it (an update's zip: Core/Update.swift); done(status, body) on any thread. status 0 = no answer (network error, timeout).
protocol CloudLink: Sendable {
    func post(_ path: String, _ json: Data, done: @escaping @Sendable (Int, Data) -> Void)
    func get(_ path: String, done: @escaping @Sendable (Int, Data) -> Void)
}
extension CloudLink { func get(_ path: String, done: @escaping @Sendable (Int, Data) -> Void) { done(404, Data()) } }   // (the save server's fakes have no downloads)

/// The real one: https://pokewalker.rulrulmo.work (08b's api.<domain>), 15 s to answer.
struct HTTPLink: CloudLink {
    static let base = URL(string: "https://pokewalker.rulrulmo.work")!
    static let appKey = "6b0b5cdf9410adc1ed7d10ae86dd2013"                                       // not a secret (08 §2-1): it keeps the internet's scanners from making trainers
    func post(_ path: String, _ json: Data, done: @escaping @Sendable (Int, Data) -> Void) {
        var r = request(path); r.httpMethod = "POST"; r.httpBody = json; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        send(r, done)
    }
    func get(_ path: String, done: @escaping @Sendable (Int, Data) -> Void) { send(request(path), done) }
    private func request(_ path: String) -> URLRequest {                                       // 15 s without a byte is no answer (a long download is fine)
        var r = URLRequest(url: HTTPLink.base.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        for (k, v) in ["X-App-Key": HTTPLink.appKey, "User-Agent": "PokeWalker/\(appVersion) (\(appPlatform))"] { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }
    private func send(_ r: URLRequest, _ done: @escaping @Sendable (Int, Data) -> Void) {
        URLSession.shared.dataTask(with: r) { d, res, _ in done((res as? HTTPURLResponse)?.statusCode ?? 0, d ?? Data()) }.resume()
    }
}

/// Replies as they come, taken on the main thread.
final class CloudInbox: @unchecked Sendable {
    private let lock = NSLock(); private var items: [(Cloud.Ask, Int, Data)] = []
    func put(_ x: (Cloud.Ask, Int, Data)) { lock.lock(); items.append(x); lock.unlock() }
    func take() -> [(Cloud.Ask, Int, Data)] { lock.lock(); defer { lock.unlock() }; let t = items; items = []; return t }
}

@MainActor final class Cloud {
    /// off: 1.x, no network · needsID: the ID box is due · login: logging in (or to try again) · busy: another PC was on it until `at` (unix): take it
    /// over? (login(force:)) · new: no such trainer: start one? (create()) · on: saving · replaced: another PC took it (no steps, no keys; resume())
    /// · oldApp: the server wants a newer app.
    enum Phase: Equatable { case off, needsID, login, busy(device: String, at: Int), new(String), on, replaced, oldApp, pin(PinAsk) }
    /// The PIN the server wants (docs/plans/10 §3): this trainer's (wrong: the last one wasn't), a new one (a 2.0 ID has none yet), or none for a while (too many wrong).
    enum PinAsk: Equatable { case enter(wrong: Bool), set, locked(until: Date) }
    /// A request out, kept to read its reply by.
    enum Ask: Sendable, Equatable { case login(force: Bool, resume: Bool), create, save(total: Int, hash: String), legacy, setPin, mint(MintAsk) }
    /// The server's Pokémon (docs/plans/10 §4): a radar's find, its result (the chain), an egg's, a legend bought, an evolution (껍질몬).
    enum MintAsk: Sendable, Equatable { case radar, result(uid: Int, result: String), hatch, buy(Int), evolve(uid: Int, to: Int, level: Int) }
    /// This PC's, in cloud.json next to the save: the ID as typed, the server's session, a random id made once, whether the 1.x save went up, and the
    /// server's trust token for this PC (the PIN goes in once a PC: 10 §3).
    struct Seat: Codable, Equatable { var trainerID: String? = nil, session: String? = nil, device: String? = nil, legacyUploaded: Bool? = nil, trust: String? = nil }
    /// How a save from the server is taken: with our steps it doesn't have walked on top (a login, stale), as it is (여기서 계속: our unsent ones
    /// lose to the other PC's, 08 §2-1), or a new trainer's (create).
    enum Take { case adopt, asIs, fresh }
    static let period: TimeInterval = 120, gather: TimeInterval = 3, slowest: TimeInterval = 1800

    let link: any CloudLink, inbox = CloudInbox(), dir: URL
    private(set) var phase: Phase
    var seat = Seat() { didSet { if seat != oldValue { writeSeat() } } }
    private(set) var inFlight: Ask? = nil
    var asking: Ask? = nil                                                 // a login / create to send once nothing is out
    var acked: String? = nil                                               // the hash of the walk text the server holds, as far as we know; nil = anything goes up
    var mustSave = false                                                   // up even unchanged: the server has none of ours yet, or lost some
    var nextSave = Date.distantPast, due: Date? = nil                      // the 2-minute save; soon()'s, 3 s gathered
    var retryAt = Date.distantPast, backoff: TimeInterval = 0              // offline: again in 2, 4, 8 … 30 minutes
    var head: (walk: Walk, rev: Int, hash: String?, how: Take)? = nil      // the server's save, waiting for home to take it (mid-fight the fight's copy would write over it)
    var legacy: String? = nil                                              // the 1.x save's text, to go up once (2b: state.pre-server.json)
    var pendingPIN: String? = nil                                          // the PIN just typed: goes with the next login / create / pin until the server takes it (never stored)
    var mints: [(ask: MintAsk, walk: String?)] = []                        // to send, before saves; their answers for the walker (status 0 = no answer, offline)
    var minted: [(ask: MintAsk, status: Int, reply: [String: Any])] = []
    var starterUID: Int? = nil                                             // create's: the new walker's companion, as the server issued it
    private(set) var lastSaved: Date? = nil
    private(set) var firstRun = false                                      // no cloud.json before: the server's first launch on this PC (Walker.startCloud's 08 §5 move)
    var deviceName: String { String(appDeviceName.prefix(64)) }
    var seatFile: URL { dir.appendingPathComponent("cloud.json") }

    init(link: any CloudLink, dir: URL, on: Bool) {
        self.link = link; self.dir = dir; phase = on ? .needsID : .off
        guard on else { return }
        if let d = try? Data(contentsOf: seatFile), let s = try? JSONDecoder().decode(Seat.self, from: d) { seat = s } else { firstRun = !FileManager.default.fileExists(atPath: seatFile.path) }
        if seat.device == nil { seat.device = hex((0..<16).map { _ in UInt8.random(in: .min ... .max) }); writeSeat() }   // (no didSet inside init)
    }
    /// The app's: on with the `cloud` setting, never with persist == false (the self-test, renders).
    static func app(persist: Bool) -> Cloud { Cloud(link: HTTPLink(), dir: Store.dir, on: persist && settings.bool("cloud", true)) }

    // MARK: what the walker and its UI call
    /// Launch: log in with this PC's ID, or ask for one.
    func start() { guard phase != .off else { return }; if seat.trainerID == nil { phase = .needsID } else { ask(.login(force: false, resume: false)) } }
    /// The ID box's answer (nil = this PC's ID again), or 가져올까요? answered yes (force). false = not an ID (2-12 of 가-힣 A-Z a-z 0-9 _).
    @discardableResult func login(_ raw: String? = nil, force: Bool = false) -> Bool {
        guard phase != .off else { return false }
        if let raw {
            guard let id = trainerID(raw) else { return false }
            if id.key != seat.trainerID.flatMap(trainerID)?.key { seat.session = nil; seat.trust = nil; pendingPIN = nil }
            seat.trainerID = id.name
        }
        guard seat.trainerID != nil else { return false }
        ask(.login(force: force, resume: false)); return true
    }
    /// 여기서 계속, after replaced: the session back, and the server's save as it is.
    func resume() { if phase == .replaced { ask(.login(force: true, resume: true)) } }
    /// 새 트레이너로 시작, after new, with its PIN: the server makes the ID and this PC starts a new walker (08 §5: new IDs start new).
    func create(pin: String) { if case .new = phase { pendingPIN = pin; ask(.create) } }
    /// The PIN box's answer: log in with it.
    func enterPIN(_ pin: String) { if case .pin(.enter) = phase { pendingPIN = pin; ask(.login(force: false, resume: false)) } }
    /// A 2.0 ID's first PIN (pin_needed): set it on the server; saves wait for it.
    func setPIN(_ pin: String) { if phase == .pin(.set) { pendingPIN = pin; ask(.setPin) } }
    /// Ask the server for a Pokémon (10 §4). Not logged in, or offline (its backoff): answered at once with no answer — the walker doesn't start
    /// the radar, buy, or hatch. walk = the save as it is now (before paying).
    func mint(_ m: MintAsk, walk: Walk?, now: Date) {
        guard phase == .on, now >= retryAt else { minted.append((m, 0, [:])); return }
        mints.append((m, walk.map { Cloud.text($0.shared) }))
    }
    /// The walker takes the answers in.
    func takeMinted() -> [(ask: MintAsk, status: Int, reply: [String: Any])] { let t = minted; minted = []; return t }
    static func text(_ w: Walk) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return (try? e.encode(w)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    static func mon(_ any: Any?) -> Mon? { (any as? String).flatMap { try? JSONDecoder().decode(Mon.self, from: Data($0.utf8)) } }
    nonisolated static func validPIN(_ s: String) -> Bool { s.count == 4 && s.allSatisfy { $0.isASCII && $0.isNumber } }
    /// After an action (a fight's end, a buy, …): up within 3 s, the actions of those 3 s in one save.
    func soon(_ now: Date) { if phase == .on, due == nil { due = now.addingTimeInterval(Cloud.gather) } }
    /// 지금 저장: up at the next tick if anything changed, offline or not.
    func saveNow() { if phase == .on { due = .distantPast; retryAt = .distantPast } }
    /// 새 트레이너? / 가져올까요? answered no: back to the ID box (a trainer that doesn't exist isn't kept as this PC's ID).
    func decline() {
        switch phase {
        case .new: seat.trainerID = nil; seat.session = nil; phase = .needsID
        case .busy: phase = .needsID
        default: break
        }
    }
    /// The phases that hold the game: no ID yet, another PC has it, too old an app.
    static func locks(_ p: Phase) -> Bool { if case .pin = p { return true }; return p == .needsID || p == .replaced || p == .oldApp }

    /// The walker's tick: replies taken; the server's save taken once home allows (canTake); then what's due goes, if nothing is out.
    /// Non-nil: the server's save was taken (true = the companion levelled up walking ours on top).
    @discardableResult func tick(_ w: inout Walk, _ now: Date, canTake: Bool = true) -> Bool? {
        guard phase != .off else { return nil }
        if case .pin(.locked(let until)) = phase, now >= until { phase = .pin(.enter(wrong: false)) }   // the lock's over: the box again
        take(&w, now)
        var took: Bool? = nil
        if canTake, let h = head { head = nil; took = apply(h, &w, now) }
        guard inFlight == nil, now >= retryAt else { return took }
        if phase != .on, !mints.isEmpty { minted += mints.map { ($0.ask, 0, [:]) }; mints = [] }   // logged out / locked: they won't go
        if let a = asking { asking = nil; send(a) }
        else if phase == .on, !mints.isEmpty { let m = mints.removeFirst(); sendMint(m.ask, m.walk) }   // a Pokémon waits on these: before saves
        else if phase == .on, head == nil {
            if legacy != nil, seat.legacyUploaded != true { send(.legacy) }
            else if mustSave || now >= nextSave || due.map({ now >= $0 }) == true { save(&w, now) }
        }
        return took
    }
    /// Quitting: what isn't up goes up (after the one out), waiting at most `timeout`. The reply comes on URLSession's queue, so the main thread can wait.
    func flush(_ w: inout Walk, timeout: TimeInterval = 2) {
        guard phase == .on else { return }
        let end = Date().addingTimeInterval(timeout); var sent = false
        while true {
            take(&w, Date())
            if inFlight == nil { if sent || head != nil || !save(&w, Date()) { return }; sent = true }
            if Date() >= end { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    // MARK: requests
    private func ask(_ a: Ask) { phase = .login; asking = a; retryAt = .distantPast }
    private func send(_ a: Ask) {
        guard let id = seat.trainerID, let device = seat.device else { return }
        switch a {
        case .login(let force, _):
            var b: [String: Any] = ["id": id, "device": device, "device_name": deviceName, "app": appVersion, "force": force]
            if let t = seat.trust { b["trust"] = t }; if let p = pendingPIN { b["pin"] = p }                 // this PC's trust, else the PIN just typed
            post(a, "v1/login", b)
        case .create: post(a, "v1/create", ["id": id, "device": device, "device_name": deviceName, "app": appVersion, "pin": pendingPIN ?? ""])   // app: the server asks 2.1 on for the PIN, and issues the starter
        case .setPin: post(a, "v1/pin", ["id": id, "session": seat.session ?? "", "pin": pendingPIN ?? ""])
        case .mint: break
        case .legacy: post(a, "v1/legacy", ["id": id, "device": device, "walk": legacy ?? ""])
        case .save: break
        }
    }
    /// Up if it changed since the server's (or must): the walk as a JSON string, shared's sorted-keys text, its hash kept as sentHash. false = nothing went.
    @discardableResult func save(_ w: inout Walk, _ now: Date) -> Bool {
        due = nil; nextSave = now.addingTimeInterval(Cloud.period)
        guard phase == .on, inFlight == nil, let id = seat.trainerID, let session = seat.session else { return false }
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        guard let d = try? enc.encode(w.shared), let text = String(data: d, encoding: .utf8) else { return false }
        let hash = hex(sha256(Array(d)))
        guard mustSave || hash != acked else { return false }
        w.sentHash = hash
        post(.save(total: w.total, hash: hash), "v1/save", ["id": id, "session": session, "app": appVersion, "base": w.cloudRev ?? 0, "walk": text])
        return true
    }
    private func sendMint(_ m: MintAsk, _ walk: String?) {
        guard let id = seat.trainerID, let session = seat.session else { minted.append((m, 0, [:])); return }
        var b: [String: Any] = ["id": id, "session": session]; if let walk { b["walk"] = walk }
        let path: String
        switch m {
        case .radar: path = "v1/radar"
        case .result(let uid, let result): path = "v1/radar/result"; b["uid"] = uid; b["result"] = result
        case .hatch: path = "v1/hatch"
        case .buy(let i): path = "v1/buy"; b["index"] = i
        case .evolve(let uid, let to, let level): path = "v1/evolve"; b["uid"] = uid; b["to"] = to; b["level"] = level
        }
        post(.mint(m), path, b)
    }
    private func post(_ a: Ask, _ path: String, _ body: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: body) else { return }
        inFlight = a
        link.post(path, d) { [inbox] s, b in inbox.put((a, s, b)) }
    }

    // MARK: replies (08b §10's table)
    private func take(_ w: inout Walk, _ now: Date) {
        for (a, s, body) in inbox.take() {
            inFlight = nil
            guard s != 0, s < 500, let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { offline(a, now); continue }
            backoff = 0
            switch (a, s) {
            case (.mint(let m), _):                                                           // the walker reads it; the session's own answers act here too
                let e = j["error"] as? String
                if e == "no_trainer" { orphan(&w, now) } else if e == "pin_needed" { phase = .pin(.set) }
                else if s == 409, j["reason"] as? String == "replaced" { phase = .replaced } else if s == 426 { phase = .oldApp }
                minted.append((m, s, j))
            case (_, 426): phase = .oldApp; NSLog("pokewalker: cloud: the server wants app %@ (this is %@)", j["need"] as? String ?? "?", appVersion)
            case (.login(_, let resume), 200): loggedIn(j, resume: resume, &w, now)
            case (.create, 200) where j["session"] is String:
                seat.session = j["session"] as? String; seat.trust = j["trust"] as? String ?? seat.trust; pendingPIN = nil; phase = .on; head = (Walk(), 0, nil, .fresh)
                starterUID = j["starter"] as? Int                                                // 10 §4.1: the starter is issued too
            case (.create, 400) where j["error"] as? String == "bad_pin": pendingPIN = nil; phase = .new(seat.trainerID ?? "")   // (the box checks: not met)
            case (.login, 401) where j["error"] as? String == "pin":                            // no trust for this PC, or the PIN wasn't it
                seat.trust = nil; phase = .pin(.enter(wrong: pendingPIN != nil)); pendingPIN = nil
            case (.login, 429): pendingPIN = nil; phase = .pin(.locked(until: now.addingTimeInterval(Double(j["retry_after"] as? Int ?? 600))))
            case (.setPin, 200): seat.trust = j["trust"] as? String ?? seat.trust; pendingPIN = nil; phase = .on; nextSave = now
            case (.save, 403) where j["error"] as? String == "pin_needed": phase = .pin(.set)
            case (.create, 409): ask(.login(force: false, resume: false))                     // made already (our reply lost, or someone else's): log in to it
            case (.save(let total, let hash), 200) where j["rev"] is Int:
                w.cloudRev = j["rev"] as? Int; w.cloudTotal = total; acked = hash; mustSave = false; lastSaved = now
            case (.save, 409) where j["reason"] as? String == "replaced": phase = .replaced; NSLog("pokewalker: cloud: another PC took %@", seat.trainerID ?? "")
            case (.save, 409) where j["rev"] is Int && j["walk"] is String:                    // stale: the server is ahead (an admin's rollback)
                let text = j["walk"] as? String ?? "", rev = j["rev"] as? Int ?? 0
                if let h = Cloud.walk(text) { head = (h, rev, hex(sha256(Array(text.utf8))), .adopt); NSLog("pokewalker: cloud: stale: the server's rev %ld taken", rev) }
                else { retryAt = now.addingTimeInterval(Cloud.period); NSLog("pokewalker: cloud: stale, and the server's save doesn't decode") }
            case (.legacy, 200): seat.legacyUploaded = true; legacy = nil                        // stored now or before: done either way
            case (_, 404): orphan(&w, now)
            case (.login, 400) where j["error"] as? String == "bad_id": seat.trainerID = nil; phase = .needsID
            default:                                                                             // 400 / 401 / 413 (a bug, the build's key): logged, again next round
                NSLog("pokewalker: cloud: %@ → %ld %@", "\(a)", s, String(data: body.prefix(200), encoding: .utf8) ?? "")
                retryAt = now.addingTimeInterval(Cloud.period)
                switch a { case .login, .create: asking = a; case .legacy: legacy = nil; case .save, .mint: break; case .setPin: pendingPIN = nil; phase = .pin(.set) }
            }
        }
    }
    /// The launch rules (08b §10 ①–④) on a login's answer.
    private func loggedIn(_ j: [String: Any], resume: Bool, _ w: inout Walk, _ now: Date) {
        if j["exists"] as? Bool == false { phase = .new(seat.trainerID ?? ""); return }
        if let t = j["trust"] as? String { seat.trust = t }                                   // the PIN passed: this PC is trusted from now on
        if j["busy"] as? Bool == true { phase = .busy(device: j["last_device"] as? String ?? "", at: j["updated_at"] as? Int ?? 0); return }
        guard let session = j["session"] as? String, let rev = j["rev"] as? Int else { asking = .login(force: resume, resume: resume); retryAt = now.addingTimeInterval(Cloud.period); return }
        seat.session = session; phase = .on; nextSave = now; lastSaved = now; pendingPIN = nil   // (in step with the server from here, but for what's changed)
        if j["pin_needed"] as? Bool == true { phase = .pin(.set) }                             // a 2.0 ID: its PIN first, saves wait (its save is taken all the same)
        guard let text = j["walk"] as? String else { acked = nil; mustSave = true; return }   // made but never saved: ours goes up (base cloudRev ?? 0)
        guard let h = Cloud.walk(text) else {                                                // one this app can't read: don't write over it
            NSLog("pokewalker: cloud: the server's save doesn't decode"); phase = .login; asking = .login(force: resume, resume: resume); retryAt = now.addingTimeInterval(Cloud.period); return
        }
        let hash = hex(sha256(Array(text.utf8)))
        if resume { head = (h, rev, hash, .asIs) }
        else if hash == w.sentHash { w.cloudRev = rev; w.cloudTotal = h.total; acked = hash }  // ② it is our last save: only its reply was lost (adopting would walk it twice)
        else if rev > (w.cloudRev ?? -1) { head = (h, rev, hash, .adopt) }                    // ③ the server's is newer: take it, ours on top
        else if rev == w.cloudRev { acked = hash }                                            // ④ up if changed since (base = rev)
        else { acked = nil; mustSave = true }                                                 // ④ the server lost ours: up even unchanged (base = cloudRev)
    }
    private func apply(_ h: (walk: Walk, rev: Int, hash: String?, how: Take), _ w: inout Walk, _ now: Date) -> Bool {
        acked = h.hash; nextSave = now
        switch h.how {
        case .adopt: return w.adopt(h.walk, rev: h.rev, at: now)
        case .asIs: w.cloudTotal = w.total; return w.adopt(h.walk, rev: h.rev, at: now)     // nothing of ours on top
        case .fresh:                                                                          // 08 §5: a new save, 1.7's check and 1.10's refund already done
            var f = Walk(); f.audited = 2; f.ballsRefunded = true
            (f.counter, f.boot, f.syncedAt, f.counterKind, f.cloudRev, f.cloudTotal) = (w.counter, w.boot, w.syncedAt, w.counterKind, 0, 0)
            if let u = starterUID { f.companion.uid = u; f.lastUID = max(f.lastUID ?? 0, u) }   // the server's uid for the first companion
            f.rollover(now); f.dex(); w = f; mustSave = true; return false
        }
    }
    /// No answer, a 5xx, or not JSON (Cloudflare's own pages: 502, 530, a 403 challenge): offline, again in 2, 4, 8 … 30 minutes.
    private func offline(_ a: Ask, _ now: Date) {
        backoff = min(Cloud.slowest, backoff == 0 ? Cloud.period : backoff * 2); retryAt = now.addingTimeInterval(backoff)
        switch a {
        case .login(_, true): phase = .replaced                                               // 여기서 계속 again, once it's back
        case .login where seat.session != nil: phase = .on                                     // logged in here before: play on, saves go with that session (08b §10)
        case .login, .create: asking = a
        case .save, .legacy: break
        case .setPin: phase = .pin(.set)                                                        // the button again, once it's back
        case .mint(let m): minted.append((m, 0, [:])); minted += mints.map { ($0.ask, 0, [:]) }; mints = []   // no answer: nothing waits on the network
        }
    }
    /// 404: the trainer is gone (an admin deleted or renamed it). The save is kept as state.orphan-<unix>.json; this PC's ID is cleared: the ID box.
    private func orphan(_ w: inout Walk, _ now: Date) {
        let fm = FileManager.default, stamp = "state.orphan-\(Int(now.timeIntervalSince1970))"
        var n = 0, to = dir.appendingPathComponent(stamp + ".json")
        while fm.fileExists(atPath: to.path) { n += 1; to = dir.appendingPathComponent("\(stamp)-\(n).json") }
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true); try? enc.encode(w).write(to: to, options: .atomic)
        NSLog("pokewalker: cloud: %@ is gone from the server; the save is kept as %@", seat.trainerID ?? "", to.lastPathComponent)
        seat.trainerID = nil; seat.session = nil; (w.cloudRev, w.cloudTotal, w.sentHash) = (nil, nil, nil)
        acked = nil; mustSave = false; head = nil; asking = nil; phase = .needsID
    }
    static func walk(_ text: String) -> Walk? { (try? JSONDecoder().decode(Walk.self, from: Data(text.utf8))).flatMap { $0.version == Walk().version ? $0 : nil } }
    private func writeSeat() {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? enc.encode(seat).write(to: seatFile, options: .atomic)
    }
}

// MARK: - the walker's side
extension Walker {
    /// Launch with the cloud on (main.swift, WinApp.swift): on the server's first launch here a 1.x save goes aside (Store.movePreServer, 08 §5) to go up
    /// once as 옛 기록, and the walker starts empty (this PC's counter kept) until the login brings the trainer's; then the login. Off: nothing, 1.x as ever.
    func startCloud(_ c: Cloud, file: URL = Store.file, bak: URL = Store.bak) {
        guard c.phase != .off else { return }
        cloud = c
        if c.firstRun, Store.movePreServer(file: file, bak: bak) {
            var w = Walk(); w.audited = 2; w.ballsRefunded = true                                   // nothing for 1.7's check or 1.10's refund to do
            (w.counter, w.boot, w.syncedAt, w.counterKind) = (state.counter, state.boot, state.syncedAt, state.counterKind)
            w.rollover(Date()); w.dex(); state = w
        }
        if c.seat.legacyUploaded != true, let text = try? String(contentsOf: Store.preServer(file), encoding: .utf8) { c.legacy = text }
        c.start(); seen = state
    }
    /// The server holds the game (08 §2): no ID yet, another PC took the trainer (§2-1), too old an app — no steps, no keys; ● is the lock's button.
    var frozen: Bool { cloud.map { Cloud.locks($0.phase) } ?? false }
    func resumeCloud() { cloud?.resume(); screen = .home; host?.redraw(.all) }               // home: the server's save is taken there
    /// ● (or the pane's button) while locked: ID 입력, 여기서 계속; nothing for too old an app.
    func lockPress() {
        guard let c = cloud, !cloudAsking else { return }
        switch c.phase {
        case .needsID: askID()
        case .replaced: resumeCloud()
        case .pin(.enter(let wrong)): cloudAsking = true; defer { cloudAsking = false }; if let p = askPIN(wrong: wrong) { c.enterPIN(p) }
        case .pin(.set): cloudAsking = true; defer { cloudAsking = false }; if let p = askNewPIN() { c.setPIN(p) }
        default: break
        }
    }
    /// The PIN box for this trainer's (wrong: the last one wasn't it): 4 digits, or nil (취소). Hidden as it's typed.
    func askPIN(wrong: Bool) -> String? {
        guard let h = host else { return nil }
        var note = "\(cloud?.seat.trainerID ?? "")의 PIN (숫자 4자리)\n이 PC에선 처음 한 번만 넣어요."              // a line a thought: the alert wraps by width only
        while let p = h.askPIN(title: wrong ? "PIN이 맞지 않아요" : "PIN을 입력해 주세요", message: note)?.trimmingCharacters(in: .whitespaces) {
            if Cloud.validPIN(p) { return p }
            note = "숫자 4자리로 넣어 주세요."
        }
        return nil
    }
    /// A new PIN (a new trainer, or a 2.0 ID's first), twice the same: 4 digits, or nil (취소).
    func askNewPIN() -> String? {
        guard let h = host else { return nil }
        var note = "숫자 4자리\n다른 PC에서 이 ID로 들어갈 때 넣어요.\n잊지 않게 적어 두세요."
        while let p = h.askPIN(title: "PIN을 정해 주세요", message: note)?.trimmingCharacters(in: .whitespaces) {
            guard Cloud.validPIN(p) else { note = "숫자 4자리로 넣어 주세요."; continue }
            guard let again = h.askPIN(title: "PIN을 한 번 더", message: "같은 PIN을 한 번 더 넣어 주세요.")?.trimmingCharacters(in: .whitespaces) else { return nil }
            if again == p { return p }
            note = "두 번 넣은 PIN이 달라요.\n처음부터 다시 정해 주세요."
        }
        return nil
    }
    /// The ID box until an ID or 취소 (08 §2), then switchID (ID 바꾸기 or not: what was here never goes up as another trainer's). A non-ID asks
    /// again with the rule. false = 취소.
    @discardableResult func askID(change: Bool = false) -> Bool {
        guard let h = host, cloud != nil, !cloudAsking else { return false }
        cloudAsking = true; defer { cloudAsking = false }
        var note = "2–12자, 한글·영문·숫자·_ (대소문자는 같은 ID)"
        while let raw = h.askText(title: change ? "ID 바꾸기" : "트레이너 ID를 입력해 주세요", message: note) {
            if trainerID(raw) != nil { switchID(raw); return true }                                 // either way: another trainer's rev / total / hash never carry over
            note = josa("'\(raw.trimmingCharacters(in: .whitespaces))'", "은", "는") + " ID로 쓸 수 없어요.\n2–12자, 한글·영문·숫자·_ 만 돼요."
        }
        return false
    }
    /// The LCD as the server's state changes: a lock's message (the pane has its button), home again once it lifts.
    func showCloud(_ p: Cloud.Phase) {
        let lines: [String]? = switch p {
        case .needsID: ["로그인이", "필요해요", "●: ID 입력"]
        case .replaced: ["다른 PC에서", "접속했어요", "●: 여기서 계속"]
        case .oldApp: ["새 버전이 필요해요", "pokewalker.", "rulrulmo.work"]
        case .pin(.enter): ["PIN을", "입력해 주세요", "●: PIN 입력"]
        case .pin(.set): ["PIN을", "정해 주세요", "●: PIN 정하기"]
        case .pin(.locked): ["PIN을 너무 많이", "틀렸어요", "잠시 뒤에 다시"]
        default: nil
        }
        if let lines { towerRun = false; growthThen = nil; heldSteps = 0; mintWaiting = nil; radarMon = nil; screen = .say(lines, next: .home, since: .distantFuture) }   // (a fight going on is dropped)
        if p == .oldApp { updater?.checkNow() }                                                  // 426: a newer app is out — the updater asks now
        else if cloudShown.map(Cloud.locks) == true { screen = .home }
        refreshPane(Date(), force: true); host?.redraw(.all)
    }
    /// The pane while the server holds the game.
    var loginModel: LoginModel? {
        switch cloud?.phase {
        case .needsID?: LoginModel(title: "로그인이 필요해요", lines: ["트레이너 ID로 서버의 세이브를 불러와요.", "2–12자, 한글·영문·숫자·_"], button: "ID 입력")
        case .replaced?: LoginModel(title: "다른 PC에서 접속했어요", lines: ["그 PC가 하는 동안 여기선 걸음을 세지 않아요.", "여기서 하려면 아래를 눌러요."], button: "여기서 계속")
        case .oldApp?: LoginModel(title: "새 버전이 필요해요", lines: ["서버가 이 버전(\(appVersion))을 받지 않아요.", "pokewalker.rulrulmo.work에서", "새 버전을 받아 주세요."], button: nil)
        case .pin(.enter(let wrong))?: LoginModel(title: wrong ? "PIN이 맞지 않아요" : "PIN을 입력해 주세요", lines: ["\(cloud?.seat.trainerID ?? "")의 숫자 4자리", "이 PC에선 처음 한 번만 넣어요."], button: "PIN 입력")
        case .pin(.set)?: LoginModel(title: "PIN을 정해 주세요", lines: ["다른 PC에서 이 ID로 들어갈 때 넣어요.", "숫자 4자리 · 잊지 않게 적어 두세요."], button: "PIN 정하기")
        case .pin(.locked(let until))?:
            LoginModel(title: "PIN을 너무 많이 틀렸어요", lines: ["\(max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up))))분 뒤에 다시 넣을 수 있어요."], button: nil)
        default: nil
        }
    }
    // MARK: the server's Pokémon (docs/plans/10 §4)
    /// Asked of the server: the LCD says so and waits (keys held, steps go on); back = where a "no" returns.
    func askMint(_ m: Cloud.MintAsk, walk: Bool, lines: [String], back: Screen) {
        guard let c = cloud else { return }
        mintWaiting = m; mintBack = back; screen = .say(lines, next: back, since: .distantFuture)
        c.mint(m, walk: walk ? state : nil, now: Date())
    }
    /// The radar's bushes went by (a wrong one, or too slow): the server's find is gone, its chain over.
    func radarMissed(_ now: Date) {
        if let c = cloud, let u = radarMon?.uid { c.mint(.result(uid: u, result: "missed"), walk: nil, now: now) }
        radarMon = nil
    }
    func notifyHatch(_ m: Mon) {
        notify("hatch", "알에서 " + josa(monNames[m.dex], "이", "가") + " 태어났어요!" + (m.shiny == true ? " ✦" : ""), m.shiny == true ? "이로치예요! 상자에 있어요" : "Lv.1 · 상자에 있어요")
    }
    /// The server's answers: the radar's find (10 W unless the chain's), a chain going on (its W and item exactly) or not, an egg's, a legend
    /// (paid now), a 껍질몬. No answer: the radar and the shop say "연결되면", the chain ends, the egg waits.
    func mintTick(_ c: Cloud, _ now: Date) {
        var changed = false
        for (m, s, j) in c.takeMinted() {
            switch m {
            case .radar:
                guard mintWaiting == .radar else { continue }
                mintWaiting = nil
                guard s == 200, let mon = Cloud.mon(j["mon"]) else {
                    chainNote = nil; screen = .say(s == 402 ? ["W가 부족하다", "(10W 필요)"] : ["연결되면", "쓸 수 있어요"], next: mintBack ?? .home, since: now); continue
                }
                if j["free"] as? Bool != true { _ = state.spend(10); changed = true }
                radarMon = mon
                let next = Screen.radar(bush: Int.random(in: 0..<4, using: &rng), cursor: 0, since: now, chain: j["chain"] as? Int ?? 0)
                if growthDue(now) { growthThen = next; screen = .home } else { screen = next }       // what the last fight brought plays first
            case .result:
                guard case .result? = mintWaiting else { continue }                                 // a missed or fled one: nothing waits on it
                mintWaiting = nil
                let n = s == 200 ? j["chain"] as? Int ?? 0 : 0
                guard n > 0 else { screen = .say(chainWas > 0 ? ["풀숲이 조용해졌다", "연쇄 \(chainWas)에서 끝"] : ["풀숲이", "조용해졌다"], next: .home, since: now); continue }
                let bonus = j["bonus"] as? Int ?? 0, reward = j["reward"] as? String
                state.watts = min(9999, state.watts + bonus); state.bestChain = max(state.bestChain ?? 0, n); if let r = reward { _ = state.keep(r) }
                chainNote = "+\(bonus)W" + (reward.map { " · " + $0 } ?? ""); changed = true
                askMint(.radar, walk: true, lines: ["연쇄 \(n)!", "풀숲이 흔들린다"], back: .home)
            case .hatch:
                hatchAsked = false
                guard s == 200, let mon = Cloud.mon(j["mon"]), state.egg != nil else { hatchAt = now.addingTimeInterval(Cloud.period); continue }
                state.hatched(mon); changed = true
                if case .home = screen { screen = .hatch(mon, since: now) }
                notifyHatch(mon)
            case .buy(let k):
                guard mintWaiting == m else { continue }
                mintWaiting = nil
                let back = mintBack ?? .home
                guard s == 200, let mon = Cloud.mon(j["mon"]), state.payLegend(k) else {
                    screen = .say(s == 402 ? [Walk.legendShop[k].bp > 0 ? "BP가 부족하다" : "W가 부족하다"] : ["연결되면", "쓸 수 있어요"], next: back, since: now); continue
                }
                _ = state.keep(mon); changed = true
                screen = .say(["전설의 " + monNames[mon.dex] + "!", "Lv.\(mon.level) · 상자에 왔다"], next: back, since: now)
                notify("unlock", "전설의 \(monNames[mon.dex])", "Lv.\(mon.level)이 상자에 왔어요")
            case .evolve:
                if s == 200, let shed = Cloud.mon(j["shedinja"]) { _ = state.keep(shed); changed = true }
            }
        }
        if changed { save(); c.soon(now) }
    }
    /// The trainer card's first page heads with the trainer ID (08 §2), once there is one.
    var cardTitle: String { cloud?.seat.trainerID ?? "트레이너 카드" }
    /// The menu's info row: 트레이너: ID · n분 전 저장 (저장 안 됨 while offline).
    var cloudMenuTitle: String {
        guard let c = cloud else { return "" }
        let when: String = switch c.phase {
        case .on: c.backoff > 0 ? "저장 안 됨" : c.lastSaved.map { d in let m = Int(Date().timeIntervalSince(d) / 60); return m < 1 ? "방금 저장" : m < 60 ? "\(m)분 전 저장" : "\(m / 60)시간 전 저장" } ?? "저장 전"
        case .needsID: "로그인이 필요해요"
        case .replaced: "다른 PC에서 접속 중"
        case .oldApp: "새 버전이 필요해요"
        case .pin: "PIN이 필요해요"
        default: "서버에 연결하는 중"
        }
        return "트레이너: \(c.seat.trainerID ?? "-") · " + when
    }
    /// Woken from sleep: what changed goes up (a stale reply brings the server's).
    func woke() { cloud?.soon(Date()) }
    /// ID 바꾸기 (step 3's box): what isn't up goes up first; another trainer's rev, total and hash don't carry over. Home at once, a tower run over:
    /// the other trainer's save is taken only there (a page left open, or a run, kept the old one up under the new ID). false = not an ID.
    @discardableResult func switchID(_ raw: String) -> Bool {
        guard let c = cloud, let id = trainerID(raw) else { return false }
        if c.seat.trainerID.flatMap(trainerID)?.key != id.key {
            c.flush(&state); (state.cloudRev, state.cloudTotal, state.sentHash) = (nil, nil, nil)
            towerRun = false; growthThen = nil; heldSteps = 0; screen = .home                    // (a fight going on is dropped: it was the other trainer's)
        }
        c.login(raw); save(); return true
    }
    /// The tick's end: what the player did goes up soon; replies; the server's save taken at home (its news quiet: it happened elsewhere), saved at once,
    /// as is a save's hash once it went; another PC taking over locks the walker; a question the server's answer raises.
    func cloudTick(_ now: Date, acted: Bool) {
        guard let c = cloud else { return }
        if acted { c.soon(now) }
        let sent = state.sentHash, rev = state.cloudRev
        let home = { if case .home = screen { return true }; return false }()
        if let up = c.tick(&state, now, canTake: home && !towerRun && heldSteps == 0) {
            if up { levelled = true }
            rewarded = dexCount; unlockedAt = state.earned; lastSeason = state.season
            queueReadyEvolutions(); save()
        } else if state.sentHash != sent || state.cloudRev != rev { save() }                     // 08b §10 ②: the sent save's hash on disk before its reply
        mintTick(c, now)
        if c.phase != cloudShown { showCloud(c.phase); cloudShown = c.phase; cloudAsked = nil }   // a new answer from the server: its question may come again
        seen = state
        cloudQuestion(c)
    }
    /// 새 트레이너? / 가져올까요? — once per answer the server gave (step 3 brings the ID box and the buttons). A tick may come during the question: not twice.
    func cloudQuestion(_ c: Cloud) {
        if c.phase == .needsID, !idBoxShown, host != nil, !cloudAsking { idBoxShown = true; askID(); return }   // by itself once a launch; then ● / the pane's button
        guard let h = host, !cloudAsking, c.phase != cloudAsked else { return }
        switch c.phase {                                                                          // the PIN boxes, once each time the server asks (취소: the pane's button)
        case .pin(.enter(let wrong)): cloudAsked = c.phase; cloudAsking = true; defer { cloudAsking = false }; if let p = askPIN(wrong: wrong) { c.enterPIN(p) }; return
        case .pin(.set): cloudAsked = c.phase; cloudAsking = true; defer { cloudAsking = false }; if let p = askNewPIN() { c.setPIN(p) }; return
        default: break
        }
        func ago(_ at: Int) -> String { let m = max(0, Int(Date().timeIntervalSince1970) - at) / 60; return m < 1 ? "방금 전" : "\(m)분 전" }
        let q: (title: String, body: String, ok: String)? = switch c.phase {
        case .new(let id): ("새 트레이너", josa("'\(id)'", "은", "는") + " 서버에 없는 ID예요. 이 ID로 새로 시작할까요?", "새로 시작")
        case .busy(let device, let at): ("다른 PC에서 하고 있었어요", "\(device)에서 \(ago(at))까지 하고 있었어요.\n여기로 가져올까요?", "가져오기")
        default: nil
        }
        guard let q else { return }
        cloudAsking = true; cloudAsked = c.phase; defer { cloudAsking = false }
        guard h.confirm(q.title, q.body, ok: q.ok) else { c.decline(); return }
        if case .new = c.phase { if let p = askNewPIN() { c.create(pin: p) } else { c.decline() } }   // a new trainer's PIN before the server makes it
        else if case .busy = c.phase { c.login(force: true) }
    }
    /// The title row's note while the server isn't plain sailing.
    var cloudNote: String? {
        switch cloud?.phase {
        case .needsID?: "로그인이 필요해요"
        case .login?, .new?, .busy?: "서버에 연결하는 중"
        case .replaced?: "다른 PC에서 접속했어요"
        case .oldApp?: "새 버전이 필요해요"
        case .pin?: "PIN이 필요해요"
        default: nil
        }
    }
}

// MARK: - the self-test's: a save server in a few lines (08b §4's 13 rows, as far as the app sees them)
/// One table of trainers. down = no answer; html = that status with a page (Cloudflare's); lose = the next reply lost after the server acted;
/// hold = replies wait for release(); old = 426 with that need; pins = PINs asked (docs/plans/10 §3: the server does for apps ≥ 2.1).
final class FakeCloud: CloudLink, @unchecked Sendable {
    struct Row {
        var name: String; var rev = 0; var walk: String? = nil; var session = ""; var writer: String? = nil; var device = ""; var at = 0
        var pin: String? = nil; var trusts: [String: String] = [:]; var fails: [Int] = []                  // its PIN, each PC's trust token, wrong PINs' times
    }
    var rows: [String: Row] = [:], paths: [String] = [], held: [() -> Void] = [], clock = 10_000
    var down = false, html: Int? = nil, lose = false, hold = false, old: String? = nil, pins = false
    var mintRng = Seeded(s: 77), nextUID = 1_000_001, pending: Int? = nil, chainN = 0, chainFree = false, chainCourse = 0, chainGoes = true   // 10 §4: the server's rolls
    func release() { let h = held; held = []; h.forEach { $0() } }
    func admin(_ key: String, _ walk: String) { rows[key]?.rev += 1; rows[key]?.walk = walk; rows[key]?.writer = "admin" }   // `pokeserver rollback`
    func post(_ path: String, _ json: Data, done: @escaping @Sendable (Int, Data) -> Void) {
        paths.append(path)
        if down { done(0, Data()); return }
        if let h = html { done(h, Data("<html><body>Bad gateway</body></html>".utf8)); return }          // Cloudflare's own: the server never saw it
        var (s, body) = answer(path, (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:])
        if lose { lose = false; s = 0; body = [:] }
        let d = s == 0 ? Data() : (try? JSONSerialization.data(withJSONObject: body)) ?? Data(), st = s
        if hold { held.append { done(st, d) } } else { done(st, d) }
    }
    func answer(_ path: String, _ j: [String: Any]) -> (Int, [String: Any]) {
        guard let id = (j["id"] as? String).flatMap(trainerID) else { return (400, ["error": "bad_id"]) }
        clock += 1; let session = String(format: "%032x", clock), device = j["device"] as? String ?? ""
        if let need = old, path != "v1/create" { return (426, ["error": "old_app", "need": need]) }
        let token = String(format: "t%031x", clock), pin = j["pin"] as? String ?? ""
        guard var r = rows[id.key] else {
            if path == "v1/create" {
                let asks = pins && (j["app"] as? String).flatMap { verCmp($0, "2.1") }.map { $0 >= 0 } == true   // as the server: 2.1 on (the request's app) asks for the PIN and issues the starter
                guard !asks || Cloud.validPIN(pin) else { return (400, ["error": "bad_pin"]) }
                rows[id.key] = Row(name: id.name, session: session, device: device, at: clock, pin: pins ? pin : nil, trusts: pins ? [device: token] : [:])
                return (200, asks ? ["rev": 0, "session": session, "trust": token, "starter": 1_000_000] : ["rev": 0, "session": session])
            }
            return path == "v1/login" ? (200, ["exists": false]) : (404, ["error": "no_trainer"])
        }
        switch path {
        case "v1/create": return (409, ["error": "exists"])
        case "v1/login":
            var trust: String? = nil                                                                  // the PIN first, then busy (10 §3)
            let trusted = (j["trust"] as? String).map { r.trusts[device] == $0 } ?? false
            if pins, let p = r.pin, !trusted {
                r.fails = r.fails.filter { clock - $0 < 600 }
                if r.fails.count >= 5 { rows[id.key] = r; return (429, ["error": "pin_locked", "retry_after": 600 - (clock - r.fails[0])]) }
                guard pin == p else {                                                                 // none sent: just asked for; a wrong one counts
                    if !pin.isEmpty { r.fails.append(clock); rows[id.key] = r }
                    return r.fails.count >= 5 ? (429, ["error": "pin_locked", "retry_after": 600]) : (401, ["error": "pin"])
                }
                trust = token; r.trusts[device] = token; rows[id.key] = r
            }
            let was = r
            if j["force"] as? Bool != true, r.device != device, clock - r.at < 300 {
                var b: [String: Any] = ["exists": true, "busy": true, "name": r.name, "last_device": r.device, "updated_at": r.at]; b["trust"] = trust; return (200, b)
            }
            r.session = session; r.device = device; rows[id.key] = r
            var b: [String: Any] = ["exists": true, "name": r.name, "rev": r.rev, "walk": (r.walk as Any?) ?? NSNull(), "session": session, "last_device": was.device, "updated_at": was.at]
            b["trust"] = trust; if pins, r.pin == nil { b["pin_needed"] = true }
            return (200, b)
        case "v1/pin":
            guard j["session"] as? String == r.session else { return (409, ["error": "conflict", "reason": "replaced"]) }
            guard Cloud.validPIN(pin) else { return (400, ["error": "bad_pin"]) }
            r.pin = pin; r.trusts = [r.device: token]; rows[id.key] = r                                 // trusted: the PC holding the session
            return (200, ["trust": token])
        case "v1/radar", "v1/radar/result", "v1/hatch", "v1/buy", "v1/evolve":
            guard j["session"] as? String == r.session else { return (409, ["error": "conflict", "reason": "replaced"]) }
            let w = (j["walk"] as? String).flatMap { try? JSONDecoder().decode(Walk.self, from: Data($0.utf8)) }
            func text(_ m: Mon) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return (try? e.encode(m)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
            func issue(_ m: Mon) -> String { var m = m; m.uid = nextUID; nextUID += 1; return text(m) }
            switch path {
            case "v1/radar":
                guard let w else { return (400, ["error": "bad_walk"]) }
                if pending != nil { pending = nil; chainN = 0; chainFree = false }                       // one left open: its chain is over
                let free = chainFree && chainN > 0
                if !free { guard w.watts >= 10 else { return (402, ["error": "watts"]) }; chainN = 0 }
                let (m, legend) = w.radarMon(&mintRng, chain: chainN), t = issue(m)
                pending = nextUID - 1; chainFree = false; chainCourse = w.course
                return (200, ["mon": t, "legend": legend, "chain": chainN, "free": free])
            case "v1/radar/result":
                guard let u = j["uid"] as? Int, u == pending else { return (409, ["error": "no_radar"]) }
                pending = nil
                guard ["caught", "defeated"].contains(j["result"] as? String ?? ""), chainGoes else { chainN = 0; chainFree = false; return (200, ["chain": 0, "bonus": 0, "reward": NSNull()]) }
                chainN += 1; chainFree = true
                return (200, ["chain": chainN, "bonus": 2 * chainN, "reward": chainN % 5 == 0 ? courses[chainCourse].items[0].item : NSNull()])
            case "v1/hatch":
                guard let w, w.hatchDue, let m = w.eggMon(&mintRng) else { return (409, ["error": "no_egg"]) }
                return (200, ["mon": issue(m)])
            case "v1/buy":
                let i = j["index"] as? Int ?? -1
                guard let w, Walk.legendShop.indices.contains(i), w.watts >= Walk.legendShop[i].watts, (w.bp ?? 0) >= Walk.legendShop[i].bp else { return (402, ["error": "price"]) }
                return (200, ["mon": issue(Walk.legendMon(i, &mintRng))])
            default:                                                                                // v1/evolve: 토중몬 → 아이스크 brings a 껍질몬
                guard j["to"] as? Int == 291 else { return (200, ["shedinja": NSNull()]) }
                return (200, ["shedinja": issue(Walk.shedinja(from: Mon(dex: 291, level: j["level"] as? Int ?? 1, female: false), &mintRng))])
            }
        case "v1/save":
            let base = j["base"] as? Int ?? -1, mine = j["session"] as? String
            guard mine == r.session else { return (409, ["error": "conflict", "reason": "replaced"]) }                         // row 9
            if pins, r.pin == nil { return (403, ["error": "pin_needed"]) }
            guard base >= r.rev || r.writer == mine else { return (409, ["error": "conflict", "reason": "stale", "rev": r.rev, "walk": (r.walk as Any?) ?? NSNull()]) }   // 13
            r.rev = max(base, r.rev) + 1; r.walk = j["walk"] as? String; r.writer = mine; r.at = clock; rows[id.key] = r           // 10-12
            return (200, ["rev": r.rev])
        default: return (200, ["stored": true])                                                                                 // v1/legacy
        }
    }
}

/// A host for the self-test: a key counter the test moves, scripted answers to confirm() and the ID box (nil = 취소; none left = 취소).
@MainActor final class TestHost: Host {
    var keys: UInt32 = 0, answer = true, asked: [String] = [], texts: [String?] = [], boxes: [String] = []
    func askText(title: String, message: String) -> String? { boxes.append(message); return texts.isEmpty ? nil : texts.removeFirst() }
    var pins: [String?] = [], pinBoxes: [String] = []                                             // the PIN box: scripted answers, what it said
    func askPIN(title: String, message: String) -> String? { pinBoxes.append(title + " · " + message); return pins.isEmpty ? nil : pins.removeFirst() }
    func notify(_ title: String, _ body: String) {}
    func counter() -> UInt32 { keys }
    func boot() -> Double { 1 }
    func redraw(_ part: CardPart) {}
    func resized() {}
    var windowHidden: Bool { false }
    func toggleShown() {}
    func fits(size: CGFloat) -> Bool { true }
    func beep() {}
    func confirm(_ title: String, _ body: String, ok: String) -> Bool { asked.append(title); return answer }
    func quit() {}
}

@MainActor func cloudChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let fm = FileManager.default, tmp = fm.temporaryDirectory.appendingPathComponent("pokewalker-cloud-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? fm.removeItem(at: tmp) }
    let srv = FakeCloud(), t0 = Date(timeIntervalSinceReferenceDate: 812_000_000), key = "zz000001"
    func pc(_ name: String, on: Bool = true) -> Cloud { Cloud(link: srv, dir: tmp.appendingPathComponent(name, isDirectory: true), on: on) }
    func run(_ cl: Cloud, _ w: inout Walk, _ t: Date, canTake: Bool = true) -> Bool? { var took: Bool? = nil; for _ in 0..<3 { if let x = cl.tick(&w, t, canTake: canTake) { took = x } }; return took }
    func text(_ w: Walk) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return (try? e.encode(w)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    func sent() -> Int { srv.paths.count }
    #if os(macOS)
    c.append(((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { $0 == windowsVersion } ?? true, "cloud: Windows' version (Core/Platform.swift) is Info.plist's"))
    #endif

    var w = Walk(); w.walk(700, at: t0)                                                          // a 1.x save
    let off = pc("off", on: false); off.start(); _ = off.login(key); off.soon(t0); _ = run(off, &w, t0); off.flush(&w)
    c.append((off.phase == .off && sent() == 0 && Cloud.app(persist: false).phase == .off && !fm.fileExists(atPath: off.seatFile.path),
              "cloud: off (the setting, or persist == false: the self-test, renders) sends and writes nothing: the app is 1.x"))

    let a = pc("a"); a.start()
    let noID = a.phase == .needsID && sent() == 0, oneLetter = !a.login("민")
    a.login(key); _ = run(a, &w, t0); let asked = a.phase == .new(key)
    a.create(pin: "0000"); let fresh = run(a, &w, t0)
    let seat = (try? Data(contentsOf: a.seatFile)).flatMap { try? JSONDecoder().decode(Cloud.Seat.self, from: $0) }
    c.append((noID && oneLetter && asked && fresh == false && w.audited == 2 && w.ballsRefunded == true && w.owned == [25] && w.total == 0 && w.cloudRev == 1 && w.cloudTotal == 0
              && srv.paths == ["v1/login", "v1/create", "v1/save"] && srv.rows[key]?.rev == 1 && srv.rows[key]?.walk == text(w.shared)
              && seat?.trainerID == key && seat?.session == srv.rows[key]?.session && seat?.device?.count == 32,
              "cloud: no ID → the ID box (one letter isn't one); a new ID → 새 트레이너? → create: a new walker (1.7's check, 1.10's refund done) up as rev 1; this PC's seat in cloud.json"))

    var n = sent(); w.walk(500, at: t0); _ = run(a, &w, t0 + 60); let early = sent() == n
    _ = run(a, &w, t0 + 121); let periodic = sent() == n + 1 && w.cloudRev == 2 && w.cloudTotal == 500 && a.lastSaved == t0 + 121
    _ = run(a, &w, t0 + 250)
    c.append((early && periodic && sent() == n + 1, "cloud: every 2 minutes, only when something changed (steps too); the rev and the sent total noted"))

    n = sent(); w.watts += 5; a.soon(t0 + 300); w.bag.append("상처약"); a.soon(t0 + 301); _ = run(a, &w, t0 + 302); let gathering = sent() == n
    _ = run(a, &w, t0 + 303)
    c.append((gathering && sent() == n + 1 && srv.rows[key]?.walk == text(w.shared), "cloud: soon() after an action: up within 3 s, two actions in one save"))

    n = sent(); srv.hold = true; w.walk(10, at: t0); a.soon(t0 + 400); _ = run(a, &w, t0 + 403)
    w.walk(10, at: t0); a.soon(t0 + 404); _ = run(a, &w, t0 + 408); _ = run(a, &w, t0 + 600)
    let waited = sent() == n + 1 && a.inFlight != nil
    srv.hold = false; srv.release(); _ = run(a, &w, t0 + 601)
    c.append((waited && sent() == n + 2 && a.inFlight == nil && srv.rows[key]?.walk == text(w.shared), "cloud: one save at a time: the next waits for the reply (however long), then goes once"))

    let rev = srv.rows[key]?.rev ?? 0
    srv.lose = true; w.walk(30, at: t0); a.soon(t0 + 700); _ = run(a, &w, t0 + 703)
    let lost = a.backoff == 120 && srv.rows[key]?.rev == rev + 1 && w.cloudRev == rev
    n = sent(); _ = run(a, &w, t0 + 760); let waits = sent() == n
    _ = run(a, &w, t0 + 823)
    c.append((lost && waits && w.cloudRev == rev + 2 && a.backoff == 0 && srv.rows[key]?.walk == text(w.shared),
              "cloud: a reply lost → offline; 2 minutes on, the resend (an older base, the same session) is taken"))

    var t = t0 + 2000, waits2: [TimeInterval] = []; w.walk(5, at: t0); a.soon(t)
    for i in 0..<6 { srv.html = [403, 502][safe: i]; srv.down = i >= 2; _ = run(a, &w, t); waits2.append(a.backoff); t = a.retryAt }
    srv.html = nil; srv.down = false; _ = run(a, &w, t)
    c.append((waits2 == [120, 240, 480, 960, 1800, 1800] && a.backoff == 0 && w.cloudTotal == w.total, "cloud: offline (an HTML 403 / 502, then no answer): again in 2, 4, 8, 16, 30, 30 minutes; back, it goes up"))

    let b = pc("b"); var wb = Walk()                                                             // another PC, the same ID typed in capitals
    b.login("ZZ000001"); _ = run(b, &wb, t); let busy = { if case .busy = b.phase { return true }; return false }()
    b.login(force: true); _ = run(b, &wb, t); let bTook = wb.total == w.total && wb.cloudRev == srv.rows[key]?.rev && b.phase == .on
    wb.walk(100, at: t0); b.soon(t); _ = run(b, &wb, t + 3)
    w.walk(40, at: t0); a.soon(t + 10); _ = run(a, &w, t + 13); let replaced = a.phase == .replaced
    n = sent(); a.soon(t + 20); _ = run(a, &w, t + 200); let quiet = sent() == n
    a.resume(); _ = run(a, &w, t + 210)
    c.append((busy && bTook && replaced && quiet && w.total == wb.total && w.cloudRev == srv.rows[key]?.rev && a.phase == .on,
              "cloud: another PC asks (busy: ours saved just now), takes over; ours hears replaced and sends nothing; 여기서 계속 takes the other's save as it is (our 40 lost)"))

    var mark = w.shared; mark.watts = 1; srv.admin(key, text(mark))                               // an admin puts an older one back
    w.walk(25, at: t0); a.soon(t + 300); _ = run(a, &w, t + 303, canTake: false)
    n = sent(); _ = run(a, &w, t + 500, canTake: false); let held = a.head != nil && w.watts != 1 && sent() == n
    let took = run(a, &w, t + 501); var want = mark; want.walk(25, at: t + 501)
    c.append((held && took != nil && w.total == mark.total + 25 && w.watts == want.watts && w.cloudRev == srv.rows[key]?.rev && srv.rows[key]?.writer != "admin" && srv.rows[key]?.walk == text(w.shared),
              "cloud: stale (an admin's rollback) → the server's save waits for home (not mid-fight), then ours on top (25 steps), then up"))

    srv.old = "9.0"; w.walk(5, at: t0); a.soon(t + 600); _ = run(a, &w, t + 603)
    n = sent(); a.soon(t + 610); _ = run(a, &w, t + 900); srv.old = nil
    c.append((a.phase == .oldApp && sent() == n, "cloud: 426 → 새 버전이 필요해요: nothing more goes up"))

    let o = pc("o"); var wo = Walk()
    o.login("zz000002"); _ = run(o, &wo, t); o.create(pin: "0000"); _ = run(o, &wo, t)
    srv.rows["zz000002"] = nil; wo.walk(77, at: t0); o.soon(t + 1); _ = run(o, &wo, t + 4)
    let orphans = ((try? fm.contentsOfDirectory(atPath: o.dir.path)) ?? []).filter { $0.hasPrefix("state.orphan-") }
    let kept = orphans.count == 1 && (try? Data(contentsOf: o.dir.appendingPathComponent(orphans[0]))).flatMap { try? JSONDecoder().decode(Walk.self, from: $0) }?.total == 77
    c.append((kept && o.phase == .needsID && o.seat.trainerID == nil && o.seat.session == nil && wo.cloudRev == nil && wo.total == 77,
              "cloud: 404 (deleted by an admin) → the save kept as state.orphan-<unix>.json, this PC's ID cleared: the ID box"))

    /// A launch on a PC with this save, the server holding rev / walk for zz000003.
    func launch(_ name: String, _ w: inout Walk, rev: Int, walk: String?) -> Int {
        srv.rows["zz000003"] = FakeCloud.Row(name: "zz000003", rev: rev, walk: walk, device: "elsewhere")
        let cl = pc(name); cl.seat.trainerID = "zz000003"; let n = sent(); cl.start(); _ = run(cl, &w, t + 1000); return sent() - n
    }
    var l1 = Walk(); l1.walk(300, at: t0); (l1.cloudRev, l1.cloudTotal) = (7, 100); let s1 = text(l1.shared); l1.sentHash = hex(sha256(Array(s1.utf8)))
    let l1n = launch("l1", &l1, rev: 8, walk: s1)
    c.append((l1n == 1 && l1.total == 300 && l1.cloudRev == 8 && l1.cloudTotal == 300, "cloud launch ②: the server holds our last save (its hash): only the reply was lost: the rev noted, nothing walked twice"))
    var other = Walk(); other.walk(400, at: t0)
    var l2 = Walk(); l2.walk(160, at: t0); (l2.cloudRev, l2.cloudTotal) = (3, 100)
    let l2n = launch("l2", &l2, rev: 5, walk: text(other.shared))
    c.append((l2n == 2 && l2.total == 460 && l2.cloudRev == 6 && srv.rows["zz000003"]?.walk == text(l2.shared), "cloud launch ③: the server is ahead: its save, our 60 not up yet on top, then up"))
    var l3 = Walk(); l3.walk(200, at: t0); (l3.cloudRev, l3.cloudTotal) = (4, 200); let s3 = text(l3.shared); l3.walk(50, at: t0)
    var l3s = Walk(); l3s.walk(200, at: t0); l3s.cloudRev = 4; l3s.cloudTotal = 200
    let l3n = launch("l3", &l3, rev: 4, walk: s3), l3sn = launch("l3s", &l3s, rev: 4, walk: text(l3s.shared))
    c.append((l3n == 2 && l3.cloudRev == 5 && l3.total == 250 && l3sn == 1 && l3s.cloudRev == 4, "cloud launch ④: the same rev: up only if changed since (base = rev)"))
    var l4 = Walk(); l4.walk(90, at: t0); (l4.cloudRev, l4.cloudTotal) = (9, 90)
    let l4n = launch("l4", &l4, rev: 6, walk: text(l4.shared))
    var l5 = Walk(); l5.walk(20, at: t0)
    let l5n = launch("l5", &l5, rev: 0, walk: nil)
    c.append((l4n == 2 && l4.cloudRev == 10 && l5n == 2 && l5.cloudRev == 1 && l5.total == 20, "cloud launch ④: the server lost ours (rev under cloudRev): up even unchanged, base cloudRev; made but never saved (walk null): up as base 0"))

    // the walker with the cloud on: 08 §5's move at the first launch, the question, the hooks, another PC taking over
    let md = tmp.appendingPathComponent("m", isDirectory: true), mf = md.appendingPathComponent("state.json"), mb = md.appendingPathComponent("state.json.bak"), mid = "zz000004"
    var old = Walk(); old.walk(4_321, at: t0); (old.counter, old.boot, old.counterKind) = (99, 1, Walk.counterNow)
    Store.save(old, file: mf, bak: mb); old.watts += 1; Store.save(old, file: mf, bak: mb)                 // a 1.x save and its bak, signed
    let oldText = (try? String(contentsOf: mf, encoding: .utf8)) ?? ""
    let mh = TestHost(); mh.keys = 99
    let mw = Walker(state: Store.load(file: mf, bak: mb)); mw.persist = false; mw.host = mh
    let mc = Cloud(link: srv, dir: md, on: true); mc.seat.trainerID = mid; mw.startCloud(mc, file: mf, bak: mb)
    let names = Set((try? fm.contentsOfDirectory(atPath: md.path)) ?? [])
    let moved = !names.contains("state.json") && !names.contains("state.json.bak") && names.isSuperset(of: ["state.pre-server.json", "state.pre-server.json.sig", "state.pre-server.bak.json", "state.pre-server.bak.json.sig"])
        && (try? String(contentsOf: Store.preServer(mf), encoding: .utf8)) == oldText
    let blank = mw.state.total == 0 && mw.state.audited == 2 && mw.state.counter == 99 && mc.legacy == oldText
    func ticks(_ wk: Walker, _ from: Date, _ secs: Double) -> Date { var at = from; while at < from + secs { wk.tick(at); at += 0.5 }; return at }
    mh.pins = ["1234", "1234"]; var mt = ticks(mw, t + 5000, 5)                                      // 새 트레이너 → its PIN, twice
    c.append((moved && blank && mh.asked == ["새 트레이너"] && mc.phase == .on && srv.paths.contains("v1/legacy") && mc.seat.legacyUploaded == true && mc.legacy == nil
              && srv.rows[mid]?.walk == text(mw.state.shared) && mw.state.audited == 2,
              "cloud walker: the first launch moves the 1.x save and its bak aside (state.pre-server.json, .sig too) and starts empty; 새 트레이너? yes → create; the old save goes up once as 옛 기록"))

    mw.state.bag = ["금구슬"]; mt = ticks(mw, mt, 5); n = sent()
    mh.keys += 10; mt = ticks(mw, mt, 1); let stepsQuiet = mc.due == nil && mw.state.total == 10 && sent() == n
    mw.sellOne("금구슬"); mw.screen = .home; mt = ticks(mw, mt, 0.5); let soonSet = mc.due != nil   // (its message times out by the real clock)
    mt = ticks(mw, mt, 3.5)
    c.append((stepsQuiet && soonSet && sent() == n + 1 && srv.rows[mid]?.walk == text(mw.state.shared),
              "cloud walker: steps wait for the 2-minute save; a menu action (not through press) goes up within 3 s"))
    mw.state.egg = Egg(dex: 175, left: 5); mt = ticks(mw, mt, 5)
    let boxed = mw.state.box.count; mh.keys += 10; mw.tick(mt); mt += 0.5; mw.tick(mt); mt += 0.5   // (the server's egg: a round trip)
    c.append((mw.state.box.count == boxed + 1 && mc.due != nil, "cloud walker: what the tick itself does (an egg hatching) goes up soon too"))

    mt = ticks(mw, mt, 5); _ = srv.answer("v1/login", ["id": mid, "device": "another", "force": true])   // another PC takes it
    mw.state.bag.append("상처약"); mt = ticks(mw, mt, 5)
    let locked = mw.frozen && mw.title().meta == "다른 PC에서 접속했어요", total = mw.state.total
    mh.keys += 30; mt = ticks(mw, mt, 3); mw.press(4); mw.press(0); let still = { if case .say = mw.screen { return true }; return false }()
    let frozenOK = locked && still && mw.state.total == total && mw.state.counter == mh.keys
    mw.press(1); mt = ticks(mw, mt, 3)
    c.append((frozenOK && mc.phase == .on && !mw.frozen && Cloud.walk(srv.rows[mid]?.walk ?? "") == mw.state.shared && { if case .home = mw.screen { return true }; return false }(),
              "cloud walker: another PC took it → locked: steps don't walk (the counter's baseline follows), keys do nothing; ● = 여기서 계속: the server's save as it is"))

    Store.save(Walk(), file: mf, bak: mb)                                                         // the next launch: a save with no cloudRev (never logged in) stays
    let mc2 = Cloud(link: srv, dir: md, on: true), mw2 = Walker(state: Walk()); mw2.persist = false; mw2.startCloud(mc2, file: mf, bak: mb)
    c.append((Store.folder == "PokeWalker Dev" && Store.dir.lastPathComponent == "PokeWalker Dev", "a build run from the repository (this self-test) keeps its own data folder: PokeWalker Dev, not the installed app's"))
    c.append((!mc2.firstRun && fm.fileExists(atPath: mf.path) && mc2.legacy == nil && (try? String(contentsOf: Store.preServer(mf), encoding: .utf8)) == oldText,
              "cloud walker: only the first launch moves a save aside; the 옛 기록 isn't sent twice"))

    // the UI (08 §2): the ID box, the locks, the menu, the card
    let uh = TestHost(), uw = Walker(state: Walk()); uw.persist = false; uw.host = uh
    let uc = Cloud(link: srv, dir: tmp.appendingPathComponent("u", isDirectory: true), on: true); uw.startCloud(uc)
    uh.texts = [nil]; var ut = ticks(uw, t + 9000, 2)                                              // no ID: the box by itself, 취소
    let saysLogin = { if case .say(let l, _, _) = uw.screen { return l.first == "로그인이" }; return false }()
    uh.keys += 20; ut = ticks(uw, ut, 2); uw.press(4); uw.press(0)
    let locked0 = uc.phase == .needsID && uh.boxes.count == 1 && saysLogin && uw.state.total == 0 && uw.pane.login?.button == "ID 입력" && { if case .say = uw.screen { return true }; return false }()
    ut = ticks(uw, ut, 3); let once = uh.boxes.count == 1
    uh.texts = ["민", " zz000005 "]; uh.pins = ["2580", "2580"]; uw.pageTap(5950); ut = ticks(uw, ut, 3)                        // the pane's button: a one-letter ID asks again with the rule, then a good one
    let reasked = uh.boxes.count == 3 && uh.boxes[2].contains("쓸 수 없어요") && uh.asked.last == "새 트레이너"
    c.append((locked0 && once && reasked && uc.phase == .on && uc.seat.trainerID == "zz000005" && { if case .home = uw.screen { return true }; return false }() && uw.pane.login == nil,
              "cloud UI: no ID → the box once by itself; 취소 → 로그인이 필요해요 on the LCD, ID 입력 on the pane, no steps, no keys; a non-ID asks again with the rule; then in"))
    let plainWalker = Walker(state: Walk()), rows = uw.menu().map(\.title), plain = plainWalker.menu().map(\.title)
    c.append((rows.contains { $0.hasPrefix("트레이너: zz000005 · ") } && rows.contains("지금 저장") && rows.contains("ID 바꾸기…") && !plain.contains { $0.hasPrefix("트레이너:") || $0 == "ID 바꾸기…" }
              && uw.cardTitle == "zz000005" && plainWalker.cardTitle == "트레이너 카드",
              "cloud UI: the right-click menu has 트레이너: ID · n분 전 저장, 지금 저장, ID 바꾸기… and the trainer card heads with the ID (only with the cloud)"))
    uw.screen = .home; uw.state.walk(40, at: ut); ut = ticks(uw, ut, 4)
    let upBefore = srv.rows["zz000005"]?.walk == text(uw.state.shared)
    uw.state.watts += 7; n = sent(); uh.texts = ["zz000006"]; uw.towerRun = true; uw.screen = .card(0); uw.askID(change: true)   // ID 바꾸기 (in a tower run, a page up): ours goes up first, then the other trainer
    let flushed = sent() == n + 1 && srv.rows["zz000005"]?.walk == text(uw.state.shared), cleared = uw.state.cloudRev == nil && uw.state.cloudTotal == nil && uw.state.sentHash == nil
        && !uw.towerRun && { if case .home = uw.screen { return true }; return false }()
    uh.answer = false; ut = ticks(uw, ut, 3)                                                       // 새 트레이너? no → back to the box (by itself only once: not again)
    c.append((upBefore && flushed && cleared && uc.phase == .needsID && uc.seat.trainerID == nil && uh.boxes.count == 4,
              "cloud UI: ID 바꾸기 sends what isn't up, then forgets the old trainer's rev / total / hash, goes home (a tower run ends: the new save is taken there); 새 트레이너? no → 로그인이 필요해요"))
    uh.answer = true; uh.texts = ["zz000005"]; uw.press(1); ut = ticks(uw, ut, 3)                    // ● = ID 입력: back to the first, the server's save
    c.append((uc.phase == .on && uc.seat.trainerID == "zz000005" && uw.state.cloudRev == srv.rows["zz000005"]?.rev && uw.state.watts == (Cloud.walk(srv.rows["zz000005"]?.walk ?? "")?.watts ?? -1),
              "cloud UI: ● on 로그인이 필요해요 opens the box; the first trainer again: its save from the server"))
    srv.old = "9.0"; uw.state.watts += 1; uw.cloud?.saveNow(); ut = ticks(uw, ut, 2); srv.old = nil
    let oldSays = { if case .say(let l, _, _) = uw.screen { return l.joined().contains("rulrulmo.work") }; return false }()
    c.append((uc.phase == .oldApp && uw.frozen && oldSays && uw.pane.login?.title == "새 버전이 필요해요" && uw.pane.login?.button == nil && uw.title().meta == "새 버전이 필요해요",
              "cloud UI: 426 → 새 버전이 필요해요 on the LCD (the download page's address) and the pane; the game is held"))
    let xh = TestHost(), xw = Walker(state: Walk()); xw.persist = false; xw.host = xh
    let xc = Cloud(link: srv, dir: tmp.appendingPathComponent("x", isDirectory: true), on: true); xw.startCloud(xc)
    (xw.state.cloudRev, xw.state.cloudTotal, xw.state.sentHash) = (9, 40, "ab"); xh.texts = ["zz000012"]; xw.askID()   // what another trainer left here (an admin's bad_id, a hand-edited seat)
    c.append((xc.seat.trainerID == "zz000012" && xw.state.cloudRev == nil && xw.state.cloudTotal == nil && xw.state.sentHash == nil,
              "cloud UI: an ID typed at 로그인이 필요해요 starts clean too — the rev / total / hash left here never go up as that trainer's"))

    // PINs (docs/plans/10 §3), against a server that asks for them
    let ps = FakeCloud(); ps.pins = true
    func pinPC(_ name: String, _ id: String? = nil) -> (Walker, Cloud, TestHost) {
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
        let c = Cloud(link: ps, dir: tmp.appendingPathComponent(name, isDirectory: true), on: true); c.seat.trainerID = id; w.startCloud(c); return (w, c, h)
    }
    func seatText(_ c: Cloud) -> String { (try? String(contentsOf: c.seatFile, encoding: .utf8)) ?? "" }
    let (p1, c1, h1) = pinPC("p1"); h1.texts = ["zz000010"]; h1.pins = ["12a4", "2580", "2580"]
    var pt = ticks(p1, t + 20000, 4)
    c.append((c1.phase == .on && c1.seat.trust != nil && ps.rows["zz000010"]?.pin == "2580" && h1.pinBoxes.count == 3 && h1.pinBoxes[1].contains("숫자 4자리로") && c1.pendingPIN == nil
              && seatText(c1).contains("\"trust\"") && !seatText(c1).contains("2580"),
              "cloud PIN: a new ID → 새 트레이너 → its PIN, twice (not 4 digits: asked again) → made with it; this PC's trust in cloud.json, the PIN itself nowhere"))
    let (p2, c2, h2) = pinPC("p2"); h2.texts = ["ZZ000010"]; h2.pins = ["1111", "2580"]
    pt = ticks(p2, pt, 6)
    c.append((c2.phase == .on && h2.pinBoxes.count == 2 && h2.pinBoxes[1].contains("맞지 않아요") && c2.seat.trust != nil && c2.seat.trust != c1.seat.trust && h2.asked == ["다른 PC에서 하고 있었어요"],
              "cloud PIN: another PC — the PIN box; a wrong one asks again (PIN이 맞지 않아요); the right one, then 가져올까요? (after the PIN), in with its own trust"))
    let h3 = TestHost(), w3 = Walker(state: Walk()); w3.persist = false; w3.host = h3
    let c3 = Cloud(link: ps, dir: tmp.appendingPathComponent("p2", isDirectory: true), on: true); w3.startCloud(c3); pt = ticks(w3, pt, 3)
    c.append((c3.phase == .on && h3.pinBoxes.isEmpty, "cloud PIN: that PC again (its trust in cloud.json): no PIN box"))
    ps.rows["zz000010"]?.fails = []                                                                  // (p2's wrong one was within the 10 minutes too)
    let (p4, c4, h4) = pinPC("p4", "zz000010"); h4.pins = ["0001", "0002", "0003", "0004", "0005"]
    pt = ticks(p4, pt, 8)
    let pinLocked: Bool = { if case .pin(.locked) = c4.phase { return true }; return false }(), boxesThen = h4.pinBoxes.count
    pt = ticks(p4, pt, 5); let lockedLines = p4.pane.login
    pt = ticks(p4, pt + 700, 1)
    c.append((pinLocked && boxesThen == 5 && lockedLines?.title == "PIN을 너무 많이 틀렸어요" && lockedLines?.lines.first?.hasSuffix("분 뒤에 다시 넣을 수 있어요.") == true && p4.frozen
              && h4.pinBoxes.count == 6 && c4.phase == .pin(.enter(wrong: false)),
              "cloud PIN: 5 wrong → locked (429): no box, the pane says how long; after it, the box again"))
    ps.rows["zz000011"] = FakeCloud.Row(name: "zz000011", rev: 1, walk: text(Walk().shared), device: "elsewhere")   // a 2.0 ID: no PIN
    let (p5, c5, h5) = pinPC("p5", "zz000011"); pt = ticks(p5, pt, 3)                                  // its box 취소'd: the button stays
    func psSaves() -> Int { ps.paths.filter { $0 == "v1/save" }.count }
    let saves5 = psSaves(); p5.state.watts += 3; pt = ticks(p5, pt, 5); let pinWaits = c5.phase == .pin(.set) && psSaves() == saves5
    h5.pins = ["4321", "4321"]; p5.press(1); pt = ticks(p5, pt, 2); p5.state.watts += 1; pt = ticks(p5, pt, 5)
    c.append((pinWaits && h5.pinBoxes.count == 3 && ps.rows["zz000011"]?.pin == "4321" && c5.seat.trust != nil && c5.phase == .on && ps.rows["zz000011"]?.walk == text(p5.state.shared),
              "cloud PIN: a 2.0 ID (pin_needed) — its save taken, then held until a PIN is set (취소: the button; ● = PIN 정하기, twice); then saves go"))
    ps.rows["zz000010"]?.pin = nil; ps.rows["zz000010"]?.trusts = [:]                               // `pokeserver pin-reset`
    h3.pins = []; w3.state.watts += 1; pt = ticks(w3, pt, 5)                                         // (w3 holds that PC's session now)
    let reset = c3.phase == .pin(.set); _ = c3.login("zz000099")
    c.append((reset && c3.seat.trust == nil && c3.seat.session == nil, "cloud PIN: a PIN reset by the admin → 403 pin_needed at the next save → PIN 정하기; another ID drops this PC's trust"))

    // the server's Pokémon (docs/plans/10 §4), against a server that issues them
    let ms = FakeCloud(); ms.pins = true
    let bh = TestHost(), bw = Walker(state: Walk()); bw.persist = false; bw.host = bh
    let bc = Cloud(link: ms, dir: tmp.appendingPathComponent("b", isDirectory: true), on: true); bw.startCloud(bc)
    bh.texts = ["zz000020"]; bh.pins = ["2468", "2468"]
    var bt = ticks(bw, t + 30000, 4)
    c.append((bc.phase == .on && bw.state.companion.uid == 1_000_000 && bw.state.lastUID == 1_000_000, "cloud mint: a new trainer's first companion has the server's uid (1,000,000)"))
    bw.state.watts = 30; bw.screen = .menu(menuAt("포켓 레이더")); bw.press(1)
    let asking = bw.mintWaiting == .radar && bw.state.watts == 30; bw.press(3); let keysHeld = bw.mintWaiting == .radar
    bt = ticks(bw, bt, 1)
    var bush = -1, since = Date.distantPast; if case .radar(let b0, _, let s0, 0) = bw.screen { bush = b0; since = s0 }
    let found = bw.radarMon
    c.append((asking && keysHeld && bush >= 0 && (found?.uid ?? 0) > 1_000_000 && bw.state.watts == 20 && ms.paths.last == "v1/radar",
              "cloud mint: the radar asks the server first (keys held meanwhile), then its find on the bushes; 10 W once it answered"))
    bw.screen = .radar(bush: bush, cursor: bush, since: since, chain: 0); bw.press(1)
    var fight: Battle? = nil; if case .beats(let b0, _, _, _) = bw.screen { fight = b0 }
    ms.chainGoes = true
    if let f = fight { bw.screen = bw.after(f, .caught, Date()) }
    bt = ticks(bw, bt, 2)
    let caughtKept = bw.state.box.contains { $0.uid == found?.uid && $0.dex == found?.dex }
    var chain1 = false; if case .radar(_, _, _, 1) = bw.screen { chain1 = true }
    c.append((fight?.wild.uid == found?.uid && caughtKept && chain1 && bw.state.watts == 22 && bw.state.bestChain == 1 && bw.chainNote == "+2W" && ms.paths.contains("v1/radar/result") && ms.paths.last == "v1/radar",
              "cloud mint: the fight is the server's Pokémon; caught → its result; the server's chain: +2 W exactly, the next radar free"))
    if case .radar(let b0, _, let s0, let ch) = bw.screen { bw.screen = .radar(bush: b0, cursor: (b0 + 1) % 4, since: s0, chain: ch); bw.press(1) }
    bt = ticks(bw, bt, 1)
    c.append((bw.radarMon == nil && ms.paths.last == "v1/radar/result" && ms.pending == nil && ms.chainN == 0, "cloud mint: a wrong bush → missed: the server ends the chain"))
    ms.down = true; let w0 = bw.state.watts; bw.screen = .menu(menuAt("포켓 레이더")); bw.press(1); bt = ticks(bw, bt, 2)
    let refused = { if case .say(let l, _, _) = bw.screen { return l == ["연결되면", "쓸 수 있어요"] }; return false }()
    c.append((refused && bw.state.watts == w0 && bw.mintWaiting == nil, "cloud mint: offline the radar doesn't start, and costs nothing"))
    bw.screen = .home; bw.state.egg = Egg(dex: 175, left: 0); bt = ticks(bw, bt, 2)
    let eggWaits = bw.state.egg != nil
    ms.down = false; bt = ticks(bw, bt + 600, 2)
    let hatchedOne = bw.state.box.last
    c.append((eggWaits && bw.state.egg == nil && hatchedOne?.dex == 175 && (hatchedOne?.uid ?? 0) > 1_000_000 && { if case .hatch = bw.screen { return true }; return false }(),
              "cloud mint: offline the egg waits (no hatch); back, the server's Pokémon hatches"))
    bw.screen = .home; bw.state.watts = 9999; let boxBefore = bw.state.box.count
    if let k = bw.wares(false).firstIndex(where: { if case .legend = $0.kind { return true }; return false }) { bw.buyWare(bw.wares(false)[k], 1, bp: false, sel: k, Date()) }
    let buyHeld = bw.mintWaiting != nil && bw.state.watts == 9999
    bt = ticks(bw, bt, 2)
    let legendOne = bw.state.box.last
    c.append((buyHeld && bw.state.watts == 0 && bw.state.box.count == boxBefore + 1 && legendOne?.dex == 250 && (legendOne?.uid ?? 0) > 1_000_000 && bw.state.legendBought(250),
              "cloud mint: the legend shop asks the server, then pays (9,999 W) and keeps its 칠색조"))
    var tz = Mon(dex: 290, level: 20, female: false); tz.uid = 1_000_090; bw.state.box.append(tz)
    let toNinjask = evolutions.first { $0.from == 290 && $0.to == 291 }!, boxN = bw.state.box.count
    bw.startEvolving(toNinjask, Date(), ref: bw.state.box.count - 1); let noLocal = bw.state.box.count == boxN
    bt = ticks(bw, bt + 10, 2)
    let shed = bw.state.box.last
    var tz2 = Mon(dex: 290, level: 20, female: false); tz2.uid = 1_000_091; bw.state.box.append(tz2); ms.down = true
    bw.startEvolving(toNinjask, Date(), ref: bw.state.box.count - 1); bt = ticks(bw, bt + 10, 2)
    c.append((noLocal && shed?.dex == 292 && (shed?.uid ?? 0) > 1_000_000 && bw.state.box.last?.dex == 291 && ms.paths.contains("v1/evolve"),
              "cloud mint: 토중몬 → 아이스크: the 껍질몬 is the server's (none rolled here); offline, none"))
    ms.down = false
    return c
}
