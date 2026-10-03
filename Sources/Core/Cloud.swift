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
    /// needsID: the ID box is due · login: logging in (or to try again) · busy: another PC was on it until `at` (unix): take it over? (login(force:))
    /// · new: no such trainer: start one? (create()) · on: playing · replaced: another PC took it (no steps, no keys; resume()) · oldApp: the server
    /// wants a newer app · pin: the PIN box (docs/plans/10 §3).
    enum Phase: Equatable { case needsID, login, busy(device: String, at: Int), new(String), on, replaced, oldApp, pin(PinAsk) }
    /// The PIN the server wants (docs/plans/10 §3): this trainer's (wrong: the last one wasn't), a new one (a 2.0 ID has none yet), or none for a while (too many wrong).
    enum PinAsk: Equatable { case enter(wrong: Bool), set, locked(until: Date) }
    /// A request out, kept to read its reply by: an act carries its seq.
    enum Ask: Sendable, Equatable { case login(force: Bool, resume: Bool), create, legacy, setPin, act(Int) }
    /// This PC's, in cloud.json next to the save: the ID as typed, the server's session, a random id made once, whether the 1.x save went up, the
    /// server's trust token for this PC (the PIN goes in once a PC: 10 §3), and steps walked here that haven't gone up yet (a quit while offline).
    struct Seat: Codable, Equatable { var trainerID: String? = nil, session: String? = nil, device: String? = nil, legacyUploaded: Bool? = nil, trust: String? = nil, steps: Int? = nil }
    static let period: TimeInterval = 120, stepsEvery: TimeInterval = 15, slowest: TimeInterval = 1800

    let link: any CloudLink, inbox = CloudInbox(), dir: URL
    private(set) var phase: Phase = .needsID
    var seat = Seat() { didSet { if seat != oldValue { writeSeat() } } }
    private(set) var inFlight: Ask? = nil
    var asking: Ask? = nil                                                 // a login / create / PIN to send once nothing is out
    var retryAt = Date.distantPast, backoff: TimeInterval = 0              // offline: again in 2, 4, 8 … 30 minutes
    var legacy: String? = nil                                              // the 1.x save's text, to go up once (2b: state.pre-server.json)
    var pendingPIN: String? = nil                                          // the PIN just typed: goes with the next login / create / pin until the server takes it (never stored)
    private(set) var lastSaved: Date? = nil                                // the last act the server answered (the menu's "n분 전 저장")
    private(set) var firstRun = false                                      // no cloud.json before: the server's first launch on this PC (Walker.startCloud's 08 §5 move)
    // docs/plans/11 (3.0): the server's save, and what the player did on its way to it
    private(set) var base: Walk? = nil, rev = 0                            // the save as the server last sent it (the walker shows it, our unsent steps on top)
    var rebased = false                                                    // base just came: the walker re-predicts (Walker.rebase)
    private(set) var seq = 0                                               // the session's last act the server answered
    private(set) var unsent = 0, sending = 0                               // steps not in any request yet; those in the one out
    private(set) var queued: Act? = nil                                    // the walker's act, to go once nothing is out
    private(set) var out: (seq: Int, act: Act, body: Data)? = nil          // the act out: sent again as it was (the same seq) after no answer
    var answers: [(act: Act, reply: ActReply?)] = []                       // for the walker: each act's reply, nil = none (offline, dropped …)
    var stepsAt = Date.distantPast                                         // the next steps-only act (every 15 s while there are some)
    var deviceName: String { String(appDeviceName.prefix(64)) }
    var seatFile: URL { dir.appendingPathComponent("cloud.json") }

    init(link: any CloudLink, dir: URL) {
        self.link = link; self.dir = dir
        if let d = try? Data(contentsOf: seatFile), let s = try? JSONDecoder().decode(Seat.self, from: d) { seat = s } else { firstRun = !FileManager.default.fileExists(atPath: seatFile.path) }
        if seat.device == nil { seat.device = hex((0..<16).map { _ in UInt8.random(in: .min ... .max) }); writeSeat() }   // (no didSet inside init)
        unsent = seat.steps ?? 0
    }
    /// The app's (3.0 is always on the server: docs/plans/11 §0); none with persist == false (the self-test's walkers bring their own, renders none).
    static func app(persist: Bool) -> Cloud? { persist ? Cloud(link: HTTPLink(), dir: Store.dir) : nil }

    // MARK: what the walker and its UI call
    /// Launch: log in with this PC's ID, or ask for one.
    func start() { if seat.trainerID == nil { phase = .needsID } else { ask(.login(force: false, resume: false)) } }
    /// The ID box's answer (nil = this PC's ID again), or 가져올까요? answered yes (force). false = not an ID (2-12 of 가-힣 A-Z a-z 0-9 _).
    @discardableResult func login(_ raw: String? = nil, force: Bool = false) -> Bool {
        if let raw {
            guard let id = trainerID(raw) else { return false }
            if id.key != seat.trainerID.flatMap(trainerID)?.key { seat.session = nil; seat.trust = nil; pendingPIN = nil; base = nil; unsent = 0; drop() }   // another trainer: nothing of this one's carries over
            seat.trainerID = id.name
        }
        guard seat.trainerID != nil else { return false }
        ask(.login(force: force, resume: false)); return true
    }
    /// 여기서 계속, after replaced: the session back, and the server's save.
    func resume() { if phase == .replaced { ask(.login(force: true, resume: true)) } }
    /// 새 트레이너로 시작, after new, with its PIN: the server makes the ID and its first save (08 §5: new IDs start new).
    func create(pin: String) { if case .new = phase { pendingPIN = pin; ask(.create) } }
    /// The PIN box's answer: log in with it.
    func enterPIN(_ pin: String) { if case .pin(.enter) = phase { pendingPIN = pin; ask(.login(force: false, resume: false)) } }
    /// A 2.0 ID's first PIN (pin_needed): set it on the server; acts wait for it.
    func setPIN(_ pin: String) { if phase == .pin(.set) { pendingPIN = pin; ask(.setPin) } }
    /// 새 트레이너? / 가져올까요? answered no: back to the ID box (a trainer that doesn't exist isn't kept as this PC's ID).
    func decline() {
        switch phase {
        case .new: seat.trainerID = nil; seat.session = nil; phase = .needsID
        case .busy: phase = .needsID
        default: break
        }
    }
    /// The phases that hold the game: no ID yet, another PC has it, too old an app, a PIN due.
    static func locks(_ p: Phase) -> Bool { if case .pin = p { return true }; return p == .needsID || p == .replaced || p == .oldApp }
    /// Acts can go now: logged in, and the last request didn't go unanswered.
    var online: Bool { phase == .on && backoff == 0 }
    /// Something the player did: it goes once nothing is out (after a resend), our unsent steps with it. false = not now (offline, or one already waiting).
    func act(_ a: Act) -> Bool { guard online, queued == nil else { return false }; queued = a; return true }
    /// Steps walked here (StepGate's): up with the next act, or on their own every 15 s.
    func addSteps(_ n: Int) { if n > 0 { unsent += n } }
    /// 지금 저장: the steps go up at the next tick, offline or not.
    func saveNow() { if phase == .on { stepsAt = .distantPast; retryAt = .distantPast } }
    /// Steps not yet in the server's save (unsent, and those in the request out): the walker walks them on top of base.
    var ahead: Int { unsent + sending }
    /// The walker's: what has come back (each act once).
    func takeAnswers() -> [(act: Act, reply: ActReply?)] { let t = answers; answers = []; return t }

    /// The walker's tick: replies taken; then what's due goes, if nothing is out: a login / create / PIN, an act sent again, the walker's act,
    /// the 1.x save once, the steps every 15 s.
    func tick(_ now: Date) {
        if case .pin(.locked(let until)) = phase, now >= until { phase = .pin(.enter(wrong: false)) }   // the lock's over: the box again
        take(now)
        guard inFlight == nil, now >= retryAt else { return }
        if let a = asking { asking = nil; send(a); return }
        guard phase == .on else { return }
        if let o = out { post(.act(o.seq), "v2/act", o.body); return }                          // no answer last time: the same act, the same seq (the server may have it)
        if let a = queued { queued = nil; sendAct(a, now); return }
        if legacy != nil, seat.legacyUploaded != true { send(.legacy); return }
        if unsent > 0 || base == nil, now >= stepsAt { sendAct(.steps, now) }                  // (no save yet: a new trainer's comes with its first act)
    }
    /// Quitting: the steps go up (after the act out), waiting at most `timeout`. The reply comes on URLSession's queue, so the main thread can wait.
    func flush(timeout: TimeInterval = 2) {
        if phase == .on {
            let end = Date().addingTimeInterval(timeout); var sent = false
            while Date() < end {
                take(Date())
                if inFlight == nil {
                    if let o = out, !sent { post(.act(o.seq), "v2/act", o.body); sent = true; continue }
                    if unsent == 0 || sent { break }
                    sendAct(.steps, Date()); sent = true
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        keepSteps()
    }
    /// The unsent steps as they stand, into cloud.json (the walker's save, the quit): a quit while offline keeps them for the next launch.
    func keepSteps() { seat.steps = unsent > 0 ? unsent : nil }

    // MARK: requests
    private func ask(_ a: Ask) { phase = .login; asking = a; retryAt = .distantPast }
    /// What an old session had going is gone with it (docs/plans/11 §0): its act out, the walker's waiting one. keepSteps: the server never
    /// ran the act out (409 seq): its steps go with the next session's first act.
    private func drop(keepSteps: Bool = false) {
        if let o = out { answers.append((o.act, nil)) }; if let q = queued { answers.append((q, nil)) }
        if keepSteps { unsent += sending }
        out = nil; queued = nil; sending = 0; seq = 0
    }
    private func send(_ a: Ask) {
        guard let id = seat.trainerID, let device = seat.device else { return }
        switch a {
        case .login(let force, _):
            var b: [String: Any] = ["id": id, "device": device, "device_name": deviceName, "app": appVersion, "force": force]
            if let t = seat.trust { b["trust"] = t }; if let p = pendingPIN { b["pin"] = p }                 // this PC's trust, else the PIN just typed
            post(a, "v1/login", json(b))
        case .create: post(a, "v1/create", json(["id": id, "device": device, "device_name": deviceName, "app": appVersion, "pin": pendingPIN ?? ""]))
        case .setPin: post(a, "v1/pin", json(["id": id, "session": seat.session ?? "", "pin": pendingPIN ?? ""]))
        case .legacy: post(a, "v1/legacy", json(["id": id, "device": device, "walk": legacy ?? ""]))
        case .act: break
        }
    }
    private func sendAct(_ a: Act, _ now: Date) {
        guard let id = seat.trainerID, let session = seat.session else { answers.append((a, nil)); return }
        let n = unsent, req = ActReq(id: id, session: session, seq: seq + 1, steps: n > 0 ? n : nil, act: a)
        guard let body = try? JSONEncoder().encode(req) else { answers.append((a, nil)); return }
        unsent = 0; sending = n; stepsAt = now.addingTimeInterval(Cloud.stepsEvery)
        out = (req.seq, a, body); post(.act(req.seq), "v2/act", body)
    }
    private func json(_ b: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: b)) ?? Data() }
    private func post(_ a: Ask, _ path: String, _ d: Data) {
        inFlight = a
        link.post(path, d) { [inbox] s, b in inbox.put((a, s, b)) }
    }

    // MARK: replies (08b §10's table; docs/plans/11 §3)
    private func take(_ now: Date) {
        for (a, s, body) in inbox.take() {
            inFlight = nil
            guard s != 0, s < 500, let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { offline(a, now); continue }
            backoff = 0; retryAt = .distantPast                                                  // the server answered: online
            switch (a, s) {
            case (.act(let n), 200):
                guard let o = out, o.seq == n else { continue }                                     // (an old session's: dropped already)
                out = nil; sending = 0
                guard let r = try? JSONDecoder().decode(ActReply.self, from: body) else {
                    NSLog("pokewalker: cloud: act %ld's reply doesn't decode", n); answers.append((o.act, nil)); drop(); ask(.login(force: false, resume: true)); continue   // a new session sets it straight
                }
                seq = n; rev = r.rev; lastSaved = now
                if let w = r.walk { base = w; rebased = true }
                answers.append((o.act, r))
            case (_, 426): phase = .oldApp; NSLog("pokewalker: cloud: the server wants app %@ (this is %@)", j["need"] as? String ?? "?", appVersion)
            case (.login(_, let resume), 200): loggedIn(j, resume: resume, now)
            case (.create, 200) where j["session"] is String:
                drop(); seat.session = j["session"] as? String; seat.trust = j["trust"] as? String ?? seat.trust; pendingPIN = nil
                base = nil; phase = .on; lastSaved = now; stepsAt = now                                 // its first save (the starter's) comes with the first act
            case (.create, 400) where j["error"] as? String == "bad_pin": pendingPIN = nil; phase = .new(seat.trainerID ?? "")   // (the box checks: not met)
            case (.login, 401) where j["error"] as? String == "pin":                            // no trust for this PC, or the PIN wasn't it
                seat.trust = nil; phase = .pin(.enter(wrong: pendingPIN != nil)); pendingPIN = nil
            case (.login, 429): pendingPIN = nil; phase = .pin(.locked(until: now.addingTimeInterval(Double(j["retry_after"] as? Int ?? 600))))
            case (.setPin, 200): seat.trust = j["trust"] as? String ?? seat.trust; pendingPIN = nil; phase = .on
            case (.act, 403) where j["error"] as? String == "pin_needed": phase = .pin(.set)        // (the act stays out: it goes once the PIN is set)
            case (.create, 409): ask(.login(force: false, resume: false))                     // made already (our reply lost, or someone else's): log in to it
            case (.act, 409) where j["reason"] as? String == "replaced": drop(); phase = .replaced; NSLog("pokewalker: cloud: another PC took %@", seat.trainerID ?? "")
            case (.act, 409) where j["error"] as? String == "seq":                              // out of step with the server: a new session, its save
                NSLog("pokewalker: cloud: seq %ld out of step: logging in again", seq); drop(keepSteps: true); ask(.login(force: false, resume: true))
            case (.legacy, 200): seat.legacyUploaded = true; legacy = nil                        // stored now or before: done either way
            case (_, 404): orphan(now)
            case (.login, 400) where j["error"] as? String == "bad_id": seat.trainerID = nil; phase = .needsID
            default:                                                                             // 400 / 401 / 413 (a bug, the build's key): logged, again next round
                NSLog("pokewalker: cloud: %@ → %ld %@", "\(a)", s, String(data: body.prefix(200), encoding: .utf8) ?? "")
                retryAt = now.addingTimeInterval(Cloud.period)
                switch a {
                case .login, .create: asking = a
                case .legacy: legacy = nil
                case .act: if let o = out { answers.append((o.act, nil)) }; out = nil; sending = 0   // not one the server will take: dropped
                case .setPin: pendingPIN = nil; phase = .pin(.set)
                }
            }
        }
    }
    /// The launch rules, 3.0's: the server's save is the save (docs/plans/11 §2); a new session starts over what was going on (§0).
    private func loggedIn(_ j: [String: Any], resume: Bool, _ now: Date) {
        if j["exists"] as? Bool == false { phase = .new(seat.trainerID ?? ""); return }
        if let t = j["trust"] as? String { seat.trust = t }                                   // the PIN passed: this PC is trusted from now on
        if j["busy"] as? Bool == true { phase = .busy(device: j["last_device"] as? String ?? "", at: j["updated_at"] as? Int ?? 0); return }
        guard let session = j["session"] as? String, let rev = j["rev"] as? Int else { asking = .login(force: resume, resume: resume); retryAt = now.addingTimeInterval(Cloud.period); return }
        if let text = j["walk"] as? String {
            guard let w = Cloud.walk(text) else {                                              // one this app can't read: nothing to show it with
                NSLog("pokewalker: cloud: the server's save doesn't decode"); phase = .login; asking = .login(force: resume, resume: resume); retryAt = now.addingTimeInterval(Cloud.period); return
            }
            base = w; rebased = true
        }
        drop(keepSteps: true); seat.session = session; self.rev = rev; phase = .on; lastSaved = now; pendingPIN = nil; stepsAt = now   // (the steps walked meanwhile go up first)
        if j["pin_needed"] as? Bool == true { phase = .pin(.set) }                             // a 2.0 ID: its PIN first, acts wait
    }
    /// No answer, a 5xx, or not JSON (Cloudflare's own pages: 502, 530, a 403 challenge): offline, again in 2, 4, 8 … 30 minutes. An act out
    /// stays to go again as it was; the walker hears none came (it stops waiting).
    private func offline(_ a: Ask, _ now: Date) {
        backoff = min(Cloud.slowest, backoff == 0 ? Cloud.period : backoff * 2); retryAt = now.addingTimeInterval(backoff)
        switch a {
        case .login(_, true): phase = .replaced                                               // 여기서 계속 again, once it's back
        case .login where seat.session != nil && base != nil: phase = .on; asking = a          // played here before: steps pile up, acts wait for the server
        case .login, .create: asking = a
        case .legacy: break
        case .setPin: phase = .pin(.set)                                                        // the button again, once it's back
        case .act: if let o = out { answers.append((o.act, nil)) }; if let q = queued { answers.append((q, nil)); queued = nil }
        }
    }
    /// 404: the trainer is gone (an admin deleted or renamed it). The last save we had is kept as state.orphan-<unix>.json; this PC's ID is cleared: the ID box.
    private func orphan(_ now: Date) {
        let fm = FileManager.default, stamp = "state.orphan-\(Int(now.timeIntervalSince1970))"
        var n = 0, to = dir.appendingPathComponent(stamp + ".json")
        while fm.fileExists(atPath: to.path) { n += 1; to = dir.appendingPathComponent("\(stamp)-\(n).json") }
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        if let b = base { try? fm.createDirectory(at: dir, withIntermediateDirectories: true); try? enc.encode(b).write(to: to, options: .atomic) }
        NSLog("pokewalker: cloud: %@ is gone from the server; its last save is kept as %@", seat.trainerID ?? "", to.lastPathComponent)
        seat.trainerID = nil; seat.session = nil; drop(); base = nil; unsent = 0; asking = nil; phase = .needsID
    }
    nonisolated static func walk(_ text: String) -> Walk? { (try? JSONDecoder().decode(Walk.self, from: Data(text.utf8))).flatMap { $0.version == Walk().version ? $0 : nil } }
    nonisolated static func validPIN(_ s: String) -> Bool { s.count == 4 && s.allSatisfy { $0.isASCII && $0.isNumber } }
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
    func startCloud(_ c: Cloud?, file: URL = Store.file, bak: URL = Store.bak) {
        guard let c else { return }
        cloud = c
        if c.firstRun, Store.movePreServer(file: file, bak: bak) {
            var w = Walk(); w.audited = 2; w.ballsRefunded = true                                   // nothing for 1.7's check or 1.10's refund to do
            (w.counter, w.boot, w.syncedAt, w.counterKind) = (state.counter, state.boot, state.syncedAt, state.counterKind)
            w.rollover(Date()); w.dex(); state = w
        }
        if c.seat.legacyUploaded != true, let text = try? String(contentsOf: Store.preServer(file), encoding: .utf8) { c.legacy = text }
        c.start()
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
        if let lines { dropPlay(); screen = .say(lines, next: .home, since: .distantFuture) }   // (a fight going on: a new session ends it on the server)
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
    func notifyHatch(_ m: Mon) {
        notify("hatch", "알에서 " + josa(monNames[m.dex], "이", "가") + " 태어났어요!" + (m.shiny == true ? " ✦" : ""), m.shiny == true ? "이로치예요! 상자에 있어요" : "Lv.1 · 상자에 있어요")
    }
    /// The trainer card's first page heads with the trainer ID (08 §2), once there is one.
    var cardTitle: String { cloud?.seat.trainerID ?? "트레이너 카드" }
    /// The menu's info row: 트레이너: ID · n분 전 저장 (offline: 연결 안 됨, and the steps waiting to go up).
    var cloudMenuTitle: String {
        guard let c = cloud else { return "" }
        let when: String = switch c.phase {
        case .on where !c.online: c.ahead > 0 ? "연결 안 됨 · 올릴 걸음 \(c.ahead.formatted())" : "연결 안 됨"
        case .on: c.lastSaved.map { d in let m = Int(Date().timeIntervalSince(d) / 60); return m < 1 ? "방금 저장" : m < 60 ? "\(m)분 전 저장" : "\(m / 60)시간 전 저장" } ?? "저장 전"
        case .needsID: "로그인이 필요해요"
        case .replaced: "다른 PC에서 접속 중"
        case .oldApp: "새 버전이 필요해요"
        case .pin: "PIN이 필요해요"
        default: "서버에 연결하는 중"
        }
        return "트레이너: \(c.seat.trainerID ?? "-") · " + when
    }
    /// Woken from sleep: the steps go up now.
    func woke() { cloud?.saveNow() }
    /// ID 바꾸기 (step 3's box): this trainer's steps go up first; then home, what was going on dropped (the other trainer's save comes with the login).
    /// false = not an ID.
    @discardableResult func switchID(_ raw: String) -> Bool {
        guard let c = cloud, let id = trainerID(raw) else { return false }
        if c.seat.trainerID.flatMap(trainerID)?.key != id.key { c.flush(); dropPlay(); news = []; screen = .home }
        c.login(raw); save(); return true
    }
    /// The tick's end: the server's answers (Core/Act.swift), a lock's change, a question the server's answer raises.
    func cloudTick(_ now: Date) {
        guard let c = cloud else { return }
        c.tick(now)
        actTick(c, now)
        if c.phase != cloudShown { showCloud(c.phase); cloudShown = c.phase; cloudAsked = nil }   // a new answer from the server: its question may come again
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

// MARK: - the self-test's: the save server in a few lines — v1's login, create and PIN (08b §4, 10 §3), 3.0's acts on the shared engine (docs/plans/11)
/// One table of trainers. down = no answer; html = that status with a page (Cloudflare's); lose = the next reply lost after the server acted;
/// hold = replies wait for release(); old = 426 with that need; pins = PINs asked (10 §3). An act runs Engine.apply with the server's dice (rng)
/// and clock (now: the real one unless a test sets it); the same seq again gets the stored reply; steps aren't capped here.
final class FakeCloud: CloudLink, @unchecked Sendable {
    struct Row {
        var name: String; var rev = 0; var walk: String? = nil; var session = ""; var device = ""; var at = 0
        var pin: String? = nil; var trusts: [String: String] = [:]; var fails: [Int] = []                  // its PIN, each PC's trust token, wrong PINs' times
        var play = Play(), seq = 0, reply = Data()                                                         // what goes on between acts; the session's last act, its reply
    }
    var rows: [String: Row] = [:], paths: [String] = [], acts: [Act] = [], steps: [Int] = [], held: [() -> Void] = [], clock = 10_000
    var down = false, html: Int? = nil, lose = false, hold = false, old: String? = nil, pins = false
    var rng = Seeded(s: 77), nextUID = 1_000_001, now: Date? = nil
    func release() { let h = held; held = []; h.forEach { $0() } }
    static func text(_ w: Walk) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return (try? e.encode(w)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    /// The trainer's save as the server has it; an admin's `pokeserver set` (a new rev).
    func walk(_ key: String) -> Walk? { rows[key]?.walk.flatMap(Cloud.walk) }
    func set(_ key: String, _ w: Walk) { rows[key]?.rev += 1; rows[key]?.walk = FakeCloud.text(w) }
    /// A trainer that exists already (logged into from elsewhere), with this save.
    func add(_ key: String, _ w: Walk, rev: Int = 1) { rows[key] = Row(name: key, rev: rev, walk: FakeCloud.text(w), device: "elsewhere") }
    func post(_ path: String, _ json: Data, done: @escaping @Sendable (Int, Data) -> Void) {
        paths.append(path)
        if down { done(0, Data()); return }
        if let h = html { done(h, Data("<html><body>Bad gateway</body></html>".utf8)); return }          // Cloudflare's own: the server never saw it
        var (s, d): (Int, Data)
        if path == "v2/act" { (s, d) = act(json) }
        else { let (st, body) = answer(path, (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]); (s, d) = (st, (try? JSONSerialization.data(withJSONObject: body)) ?? Data()) }
        if lose { lose = false; s = 0; d = Data() }
        let st = s, dd = d
        if hold { held.append { done(st, dd) } } else { done(st, dd) }
    }
    private func err(_ s: Int, _ b: [String: Any]) -> (Int, Data) { (s, (try? JSONSerialization.data(withJSONObject: b)) ?? Data()) }
    /// POST /v2/act: the session's next act (a resend: its stored reply), run on the trainer's save and play.
    func act(_ d: Data) -> (Int, Data) {
        guard let q = try? JSONDecoder().decode(ActReq.self, from: d), let id = trainerID(q.id) else { return err(400, ["error": "bad_action"]) }
        guard var r = rows[id.key] else { return err(404, ["error": "no_trainer"]) }
        if let need = old { return err(426, ["error": "old_app", "need": need]) }
        guard q.session == r.session else { return err(409, ["error": "conflict", "reason": "replaced"]) }
        if pins, r.pin == nil { return err(403, ["error": "pin_needed"]) }
        if q.seq == r.seq, r.seq > 0 { return (200, r.reply) }                                              // the reply was lost: the same one again
        guard q.seq == r.seq + 1 else { return err(409, ["error": "seq"]) }
        let first = r.walk == nil                                                                           // a new trainer's first act: the server makes its save
        var w = r.walk.flatMap(Cloud.walk) ?? Engine.fresh(now: now ?? Date(), starter: 1_000_000)
        var ids = Issued(next: max(nextUID, (w.lastUID ?? 0) + 1))
        let o = Engine.apply(q.act, steps: q.steps ?? 0, walk: &w, play: &r.play, rng: &rng, now: now ?? Date(), ids: &ids)
        nextUID = ids.next; acts.append(q.act); steps.append(q.steps ?? 0); clock += 1
        if o.changed || first { r.rev += 1; r.walk = FakeCloud.text(w); r.at = clock }
        let reply = (try? JSONEncoder().encode(ActReply(rev: r.rev, walk: o.changed || first ? w : nil, taken: q.steps, out: o))) ?? Data()
        r.seq = q.seq; r.reply = reply; rows[id.key] = r
        return (200, reply)
    }
    func answer(_ path: String, _ j: [String: Any]) -> (Int, [String: Any]) {
        guard let id = (j["id"] as? String).flatMap(trainerID) else { return (400, ["error": "bad_id"]) }
        clock += 1; let session = String(format: "%032x", clock), device = j["device"] as? String ?? ""
        if let need = old, path != "v1/create" { return (426, ["error": "old_app", "need": need]) }
        let token = String(format: "t%031x", clock), pin = j["pin"] as? String ?? ""
        guard var r = rows[id.key] else {
            if path == "v1/create" {
                guard !pins || Cloud.validPIN(pin) else { return (400, ["error": "bad_pin"]) }
                rows[id.key] = Row(name: id.name, session: session, device: device, at: clock, pin: pins ? pin : nil, trusts: pins ? [device: token] : [:])   // its save: at its first act
                return (200, ["rev": 0, "session": session, "trust": token, "starter": 1_000_000])
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
            r.session = session; r.device = device; r.at = clock; r.play = Play(); r.seq = 0                       // a new session: what was going on is over (11 §0)
            if var w = r.walk.flatMap(Cloud.walk) { for ref in [-1] + w.caught.indices.map({ -2 - $0 }) + Array(w.box.indices) { _ = w.id(ref) }; r.walk = FakeCloud.text(w) }   // every Pokémon a uid (3.0's first login)
            rows[id.key] = r
            var b: [String: Any] = ["exists": true, "name": r.name, "rev": r.rev, "walk": (r.walk as Any?) ?? NSNull(), "session": session, "last_device": was.device, "updated_at": was.at]
            b["trust"] = trust; if pins, r.pin == nil { b["pin_needed"] = true }
            return (200, b)
        case "v1/pin":
            guard j["session"] as? String == r.session else { return (409, ["error": "conflict", "reason": "replaced"]) }
            guard Cloud.validPIN(pin) else { return (400, ["error": "bad_pin"]) }
            r.pin = pin; r.trusts = [r.device: token]; rows[id.key] = r                                 // trusted: the PC holding the session
            return (200, ["trust": token])
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
    var quits = 0
    func quit() { quits += 1 }
}

@MainActor func cloudChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let fm = FileManager.default, tmp = fm.temporaryDirectory.appendingPathComponent("pokewalker-cloud-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    defer { try? fm.removeItem(at: tmp) }
    #if os(macOS)
    c.append(((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { $0 == windowsVersion } ?? true, "cloud: Windows' version (Core/Platform.swift) is Info.plist's"))
    #endif
    func ticks(_ wk: Walker, _ from: Date, _ secs: Double) -> Date { var at = from; while at < from + secs { wk.tick(at); at += 0.5 }; return at }
    func isHome(_ w: Walker) -> Bool { if case .home = w.screen { return true }; return false }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    func chk(_ ok: Bool, _ name: String, _ why: String) { c.append((ok, ok ? name : name + " — " + why)) }
    func beatsOut(_ w: Walker) { var n = 0; while n < 20, case .beats = w.screen { w.tick(Date() + 100); n += 1 } }

    // a new trainer: the ID box → 새 트레이너 → its PIN → made; its first act brings the server's save (docs/plans/11: the starter's)
    let srv = FakeCloud(); srv.pins = true
    let ah = TestHost(), aw = Walker(state: Walk()); aw.persist = false; aw.host = ah
    let ac = Cloud(link: srv, dir: tmp.appendingPathComponent("a", isDirectory: true)); aw.startCloud(ac)
    let noID = ac.phase == .needsID && srv.paths.isEmpty && Cloud.app(persist: false) == nil
    ah.texts = ["민", "zz000001"]; ah.pins = ["2580", "2580"]
    var t = ticks(aw, Date(), 3)
    c.append((noID && ah.boxes.count == 2 && ah.asked == ["새 트레이너"] && ac.phase == .on && aw.state.companion.uid == 1_000_000 && Array(srv.paths.prefix(3)) == ["v1/login", "v1/create", "v2/act"]
              && srv.acts.first == .steps && ac.seat.trust != nil && srv.rows["zz000001"]?.walk != nil,
              "3.0 cloud: no ID → the box (one letter isn't one) → 새 트레이너 → its PIN → made; the first act brings the server's save: the starter, uid 1,000,000"))
    for _ in 0..<8 { ah.keys += 4; t = ticks(aw, t, 0.5) }
    let shown = aw.state.total, held = ac.ahead
    t = ticks(aw, t + 16, 1)
    chk(shown > 0 && held == shown && srv.walk("zz000001")?.total == shown && ac.ahead == 0 && aw.state.total == shown && srv.steps.last == shown,
              "3.0 steps: shown at once (walk(n) on the server's save), up every 15 s; the save that comes back has them", "\(shown) \(held) \(srv.walk("zz000001")?.total ?? -1)")

    // acts: the keys wait for the answer; its steps go with it; a reply lost → offline → the same act, the same seq, again → the stored answer
    var shopW = Walk(); shopW.watts = 300
    let v = online(shopW), (vs, vk) = server(v), potion = v.wares(false).firstIndex { if case .item("상처약") = $0.kind { return true }; return false }!
    v.cloud!.addSteps(7); v.screen = .shop(bp: false, sel: potion, qty: 1); v.press(1)
    let waits = v.waiting != nil; v.press(2); let heldKeys = v.waiting != nil
    drain(v)
    let price = v.wares(false)[potion].price
    c.append((waits && heldKeys && says(v).first?.hasPrefix("상처약을") == true && v.state.count("상처약") == 1 && served(v)?.count("상처약") == 1 && v.state.watts == 300 - price
              && vs.steps.last == 7 && v.state.total == 7,
              "3.0 act: 상점's buy is the server's (keys wait meanwhile); the steps not up yet go with it; its line, the save it made"))
    vs.lose = true; v.screen = .shop(bp: false, sel: potion, qty: 1); v.press(1); drain(v, max: 3)
    let lostSays = says(v) == Walker.offlineLines, ranOnce = vs.acts.count, offlineNow = !v.cloud!.online
    v.tick(Date() + 121); drain(v)
    c.append((lostSays && offlineNow && ranOnce == 2 && vs.acts.count == 2 && v.state.count("상처약") == 2 && served(v)?.count("상처약") == 2 && v.cloud!.online,
              "3.0 act: its reply lost → 연결되면 할 수 있어요 (offline); 2 minutes on the same act goes again (the same seq): the server's stored answer, bought once"))
    vs.down = true; v.cloud!.addSteps(30); v.cloud!.saveNow(); v.tick(Date()); v.tick(Date())
    v.screen = .menu(menuAt("포켓 레이더")); let tiles = v.paneContent(Date()).menu?.rows ?? []; v.press(1)
    let refused = says(v) == Walker.offlineLines && v.waiting == nil, row = v.cloudMenuTitle
    let dimmed = tiles.filter(\.off).map(\.name) == ["포켓 레이더", "상점", "BP 교환소", "배틀 타워"] && tiles.first { $0.off }?.note == "연결되면 할 수 있어요"
    vs.down = false; v.tick(Date() + 121); drain(v)
    chk(refused && dimmed && row.hasSuffix("연결 안 됨 · 올릴 걸음 30") && served(v)?.total == 37 && v.cloud!.ahead == 0,
              "3.0 offline: what needs the server dimmed on the menu (연결되면 할 수 있어요), and says so at once; steps pile up (the right-click: 연결 안 됨 · 올릴 걸음 n); back, they go up", row)
    let bs = FakeCloud(); bs.add("zz000099", Walk())
    let bo = Cloud(link: bs, dir: tmp.appendingPathComponent("bo", isDirectory: true)); bo.seat.trainerID = "zz000099"; bo.login(force: true); var bt = Date(); bo.tick(bt); bo.tick(bt)
    var waits2: [TimeInterval] = []; bo.addSteps(5)
    for i in 0..<6 { bs.html = [403, 502][safe: i]; bs.down = i >= 2; bo.tick(bt); bo.tick(bt); waits2.append(bo.backoff); bt = bo.retryAt }
    bs.html = nil; bs.down = false; bo.tick(bt); bo.tick(bt)
    chk(waits2 == [120, 240, 480, 960, 1800, 1800] && bo.backoff == 0 && bo.ahead == 0, "3.0 offline (an HTML 403 / 502, then no answer): again in 2, 4, 8, 16, 30, 30 minutes; back, the steps go up", "\(waits2) \(bo.phase) \(bo.ahead)")

    // the server's "not now" (out.cannot): its lines on the LCD, back where it was; nothing changed but the steps
    serve(v) { w in var e = [0, 0, 0, 0, 0, 0]; e[0] = 100; w.companion.evs = e; w.bag = ["맥스업"] }
    let vRev = vs.rows[vk]?.rev; v.screen = .items(0); v.press(1); drain(v)
    chk(says(v) == ["먹어도 효과가", "없을 것 같다"] && v.state.count("맥스업") == 1 && vs.rows[vk]?.rev == vRev, "3.0 act: the server's no (맥스업 at 100: 먹어도 효과가 / 없을 것 같다) on the LCD, nothing used", "\(says(v)) \(v.screen) \(v.state.inventory) \(String(describing: vs.acts.last))")

    // the session: out of step (409 seq) → logged in again, its save; another PC took it → locked, 여기서 계속; 426; 404
    vs.rows[vk]?.seq = 40; v.screen = .home; v.cloud!.addSteps(3); v.cloud!.saveNow(); drain(v); drain(v)
    let reLogged = v.cloud!.phase == .on && v.cloud!.seq == 1 && served(v)?.total == 40
    _ = vs.answer("v1/login", ["id": vk, "device": "another", "force": true]); v.cloud!.addSteps(2); v.cloud!.saveNow(); drain(v)
    let locked = v.frozen && v.title().meta == "다른 PC에서 접속했어요" && v.cloud!.phase == .replaced
    v.press(1); drain(v)
    chk(reLogged && locked && v.cloud!.phase == .on && !v.frozen && isHome(v) && v.state.total == 40,
              "3.0 session: 409 seq → a new login (the act's steps kept), the server's save; another PC took it → locked; ● = 여기서 계속 (the steps walked meanwhile aren't sent)", "\(reLogged) \(locked) \(v.cloud!.phase) \(v.state.total) \(served(v)?.total ?? -1) \(v.screen)")
    vs.old = "9.0"; v.cloud!.addSteps(1); v.cloud!.saveNow(); drain(v); vs.old = nil
    c.append((v.cloud!.phase == .oldApp && v.frozen && says(v).joined().contains("rulrulmo.work") && v.pane.login?.title == "새 버전이 필요해요", "3.0 session: 426 → 새 버전이 필요해요, the game held"))
    let o = online(Walk()), (os, ok) = server(o); os.rows[ok] = nil; o.cloud!.addSteps(77); o.cloud!.saveNow(); drain(o)
    let orphans = ((try? fm.contentsOfDirectory(atPath: o.cloud!.dir.path)) ?? []).filter { $0.hasPrefix("state.orphan-") }
    c.append((orphans.count == 1 && o.cloud!.phase == .needsID && o.cloud!.seat.trainerID == nil && o.cloud!.ahead == 0, "3.0 session: 404 (deleted by an admin) → the last save kept as state.orphan-<unix>.json, the ID box"))

    // home: the server's news one at a time, in order; the radar's find, a fight to its end, the chain's next bush (free), a late answer
    let n = online({ var s = Walk(); s.egg = Egg(dex: 175, left: 900); return s }())
    let nu = n.state.companion.uid!
    n.news = [.find(item: "상처약"), .weather(to: .rain), .level(uid: nu, level: 6), .unlock(course: 1)]; n.screen = .home; n.tick(Date())
    var seen: [[String]] = [says(n)]; for _ in 0..<3 { n.press(1); seen.append(says(n)) }
    chk(seen.map { $0.first ?? "" } == [josa(monNames[25], "이", "가") + " 무언가를", "비가 내리기 시작했다!", "레벨 업!", "새 코스 해금!"] && n.news.isEmpty,
              "3.0 home: the server's news one by one, in order (a find, the weather, a level, a course)", "\(seen)")
    let rv = online({ var s = Walk(); s.watts = 200; s.companion = Mon(dex: 25, level: 60, female: false); return s }(), rng: 9)
    let (rs, rk) = server(rv)
    rv.screen = .menu(menuAt("포켓 레이더")); rv.press(1); drain(rv)
    var radarUp = false, fought = false, caughtUID = 0
    if case .radar(let b, _, _, let ch) = rv.screen {
        radarUp = rv.state.watts == 190 && ch == 0
        rv.screen = .radar(bush: b, cursor: b, since: Date().addingTimeInterval(-2), chain: ch); rv.press(1); drain(rv)
        if case .beats(let f, _, _, _) = rv.screen { fought = true; caughtUID = f.wild.uid ?? 0 }
        var k = 0
        while rv.inBattle, k < 20 { beatsOut(rv); if case .battle(let x, _) = rv.screen { rv.screen = .battle(x, sel: rv.battleMenu(x).firstIndex(of: "볼")!); rv.press(1); drain(rv) }; k += 1 }
        beatsOut(rv); rv.tick(Date()); drain(rv)
    }
    let kept = rv.state.box.contains { $0.uid == caughtUID }, chainHeld = rs.rows[rk]?.play.radar != nil
    var chained = false
    if chainHeld, case .radar(let b, _, _, let ch) = rv.screen { chained = ch == 1 && rv.state.watts == 192; rv.screen = .radar(bush: b, cursor: (b + 1) % 4, since: .distantPast, chain: ch); rv.press(1); drain(rv) }
    chk(radarUp && fought && caughtUID > 1_000_000 && kept && (!chainHeld || chained) && rs.rows[rk]?.play.radar == nil && rs.rows[rk]?.play.chain == nil && !rv.inBattle,
              "3.0 radar: the server's bush (10 W), its find in a fight (balls until it's in), kept; the chain's next bush asked for once home was done (free, +2 W), a wrong one gives it up",
              "\(radarUp) \(fought) \(caughtUID) \(kept) \(chainHeld) \(chained)")
    rs.lose = true; rv.screen = .menu(menuAt("포켓 레이더")); rv.press(1); drain(rv, max: 3)
    let gaveUpSays = says(rv) == Walker.offlineLines
    rv.tick(Date() + 121); drain(rv); drain(rv)
    chk(gaveUpSays && rs.acts.suffix(2) == [.radar, .radarPick(bush: -1)] && rs.rows[rk]?.play.radar == nil && !isRadar(rv.screen),
              "3.0 late: a radar whose answer came after the walker gave up (offline) is given up at once (the server hears -1)", "\(gaveUpSays) \(rs.acts.suffix(3)) \(rv.screen)")

    // the walker with the server: 08 §5's move at the first launch, the 1.x save up once as 옛 기록
    let md = tmp.appendingPathComponent("m", isDirectory: true), mf = md.appendingPathComponent("state.json"), mb = md.appendingPathComponent("state.json.bak"), mid = "zz000004"
    let t0 = Date(timeIntervalSinceReferenceDate: 812_000_000)
    var old = Walk(); old.walk(4_321, at: t0); (old.counter, old.boot, old.counterKind) = (99, 1, Walk.counterNow)
    Store.save(old, file: mf, bak: mb); old.watts += 1; Store.save(old, file: mf, bak: mb)                 // a 1.x save and its bak, signed
    let oldText = (try? String(contentsOf: mf, encoding: .utf8)) ?? ""
    let mh = TestHost(); mh.keys = 99
    let mw = Walker(state: Store.load(file: mf, bak: mb)); mw.persist = false; mw.host = mh
    let mc = Cloud(link: srv, dir: md); mc.seat.trainerID = mid; mw.startCloud(mc, file: mf, bak: mb)
    let names = Set((try? fm.contentsOfDirectory(atPath: md.path)) ?? [])
    let moved = !names.contains("state.json") && !names.contains("state.json.bak") && names.isSuperset(of: ["state.pre-server.json", "state.pre-server.json.sig", "state.pre-server.bak.json", "state.pre-server.bak.json.sig"])
        && (try? String(contentsOf: Store.preServer(mf), encoding: .utf8)) == oldText
    let blank = mw.state.total == 0 && mw.state.audited == 2 && mw.state.counter == 99 && mc.legacy == oldText
    mh.pins = ["1234", "1234"]; t = ticks(mw, t + 5000, 5)                                       // 새 트레이너 → its PIN, twice
    c.append((moved && blank && mh.asked == ["새 트레이너"] && mc.phase == .on && srv.paths.contains("v1/legacy") && mc.seat.legacyUploaded == true && mc.legacy == nil && mw.state.companion.uid == 1_000_000,
              "3.0 walker: the first launch moves the 1.x save and its bak aside (state.pre-server.json, .sig too) and starts empty; 새 트레이너? yes → create; the old save goes up once as 옛 기록"))
    Store.save(Walk(), file: mf, bak: mb)
    let mc2 = Cloud(link: srv, dir: md), mw2 = Walker(state: Walk()); mw2.persist = false; mw2.startCloud(mc2, file: mf, bak: mb)
    c.append((Store.folder == "PokeWalker Dev" && Store.dir.lastPathComponent == "PokeWalker Dev", "a build run from the repository (this self-test) keeps its own data folder: PokeWalker Dev, not the installed app's"))
    c.append((!mc2.firstRun && fm.fileExists(atPath: mf.path) && mc2.legacy == nil && (try? String(contentsOf: Store.preServer(mf), encoding: .utf8)) == oldText,
              "3.0 walker: only the first launch moves a save aside; the 옛 기록 isn't sent twice"))
    mc2.addSteps(12); mc2.keepSteps(); let mc3 = Cloud(link: srv, dir: md)
    c.append((mc3.ahead == 12, "3.0 walker: steps not up yet when the app quits (offline) stay in cloud.json for the next launch"))

    // the UI (08 §2): the ID box, the locks, the menu, the card
    let uh = TestHost(), uw = Walker(state: Walk()); uw.persist = false; uw.host = uh
    let uc = Cloud(link: srv, dir: tmp.appendingPathComponent("u", isDirectory: true)); uw.startCloud(uc)
    uh.texts = [nil]; var ut = ticks(uw, t + 9000, 2)                                              // no ID: the box by itself, 취소
    let saysLogin = says(uw).first == "로그인이"
    uh.keys += 20; ut = ticks(uw, ut, 2); uw.press(4); uw.press(0)
    let locked0 = uc.phase == .needsID && uh.boxes.count == 1 && saysLogin && uw.state.total == 0 && uw.pane.login?.button == "ID 입력" && !says(uw).isEmpty
    ut = ticks(uw, ut, 3); let once = uh.boxes.count == 1
    uh.texts = ["민", " zz000005 "]; uh.pins = ["2580", "2580"]; uw.pageTap(5950); ut = ticks(uw, ut, 3)                        // the pane's button: a one-letter ID asks again with the rule, then a good one
    let reasked = uh.boxes.count == 3 && uh.boxes[2].contains("쓸 수 없어요") && uh.asked.last == "새 트레이너"
    c.append((locked0 && once && reasked && uc.phase == .on && uc.seat.trainerID == "zz000005" && isHome(uw) && uw.pane.login == nil,
              "cloud UI: no ID → the box once by itself; 취소 → 로그인이 필요해요 on the LCD, ID 입력 on the pane, no steps, no keys; a non-ID asks again with the rule; then in"))
    let plainWalker = Walker(state: Walk()), rows = uw.menu().map(\.title), plain = plainWalker.menu().map(\.title)
    c.append((rows.contains { $0.hasPrefix("트레이너: zz000005 · ") } && rows.contains("지금 저장") && rows.contains("ID 바꾸기…") && !plain.contains { $0.hasPrefix("트레이너:") || $0 == "ID 바꾸기…" }
              && uw.cardTitle == "zz000005" && plainWalker.cardTitle == "트레이너 카드",
              "cloud UI: the right-click menu has 트레이너: ID · n분 전 저장, 지금 저장, ID 바꾸기… and the trainer card heads with the ID (only with the server)"))
    for _ in 0..<5 { uh.keys += 4; ut = ticks(uw, ut, 0.5) }
    let ahead5 = uc.ahead; uh.texts = ["zz000006"]; uw.towerRun = true; uw.screen = .card(0); uw.askID(change: true)   // ID 바꾸기 (in a tower run, a page up): ours goes up first, then the other trainer
    let flushed = ahead5 > 0 && srv.walk("zz000005")?.total == uw.state.total && !uw.towerRun && isHome(uw)
    uh.answer = false; ut = ticks(uw, ut, 3)                                                       // 새 트레이너? no → back to the box (by itself only once: not again)
    c.append((flushed && uc.phase == .needsID && uc.seat.trainerID == nil && uh.boxes.count == 4,
              "cloud UI: ID 바꾸기 sends the steps not up yet, goes home (a tower run ends); 새 트레이너? no → 로그인이 필요해요"))
    uh.answer = true; uh.texts = ["zz000005"]; uh.pins = ["2580"]; uw.press(1); ut = ticks(uw, ut, 3)   // ● = ID 입력: back to the first (its PIN: another ID dropped this PC's trust), the server's save
    chk(uc.phase == .on && uc.seat.trainerID == "zz000005" && uw.state.total == srv.walk("zz000005")?.total, "cloud UI: ● on 로그인이 필요해요 opens the box; the first trainer again: its save from the server", "\(uc.phase) \(uw.state.total) \(srv.walk("zz000005")?.total ?? -1) \(uc.ahead)")

    // PINs (docs/plans/10 §3), against a server that asks for them
    let ps = FakeCloud(); ps.pins = true
    func pinPC(_ name: String, _ id: String? = nil) -> (Walker, Cloud, TestHost) {
        let h = TestHost(), w = Walker(state: Walk()); w.persist = false; w.host = h
        let c = Cloud(link: ps, dir: tmp.appendingPathComponent(name, isDirectory: true)); c.seat.trainerID = id; w.startCloud(c); return (w, c, h)
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
    let c3 = Cloud(link: ps, dir: tmp.appendingPathComponent("p2", isDirectory: true)); w3.startCloud(c3); pt = ticks(w3, pt, 3)
    c.append((c3.phase == .on && h3.pinBoxes.isEmpty, "cloud PIN: that PC again (its trust in cloud.json): no PIN box"))
    ps.rows["zz000010"]?.fails = []                                                                  // (p2's wrong one was within the 10 minutes too)
    let (p4, c4, h4) = pinPC("p4", "zz000010"); h4.pins = ["0001", "0002", "0003", "0004", "0005"]
    pt = ticks(p4, pt, 8)
    let pinLocked: Bool = { if case .pin(.locked) = c4.phase { return true }; return false }(), boxesThen = h4.pinBoxes.count
    pt = ticks(p4, pt, 5); let lockedLines = p4.pane.login
    pt = ticks(p4, pt + 700, 1)
    chk(pinLocked && boxesThen == 5 && lockedLines?.title == "PIN을 너무 많이 틀렸어요" && lockedLines?.lines.first?.hasSuffix("분 뒤에 다시 넣을 수 있어요.") == true && p4.frozen
              && h4.pinBoxes.count == 6 && c4.phase == .pin(.enter(wrong: false)),
              "cloud PIN: 5 wrong → locked (429): no box, the pane says how long; after it, the box again", "\(pinLocked) \(boxesThen) \(String(describing: lockedLines)) \(h4.pinBoxes.count) \(c4.phase)")
    ps.add("zz000011", Walk())                                                                       // a 2.0 ID: no PIN
    let (p5, c5, h5) = pinPC("p5", "zz000011"); pt = ticks(p5, pt, 3)                                  // its box 취소'd: the button stays
    let acts5 = ps.acts.count; c5.addSteps(3); pt = ticks(p5, pt + 20, 5); let pinWaits = c5.phase == .pin(.set) && ps.acts.count == acts5
    h5.pins = ["4321", "4321"]; p5.press(1); pt = ticks(p5, pt + 20, 5)
    c.append((pinWaits && h5.pinBoxes.count == 3 && ps.rows["zz000011"]?.pin == "4321" && c5.seat.trust != nil && c5.phase == .on && ps.walk("zz000011")?.total == 3,
              "cloud PIN: a 2.0 ID (pin_needed) — its save taken, acts held until a PIN is set (취소: the button; ● = PIN 정하기, twice); then they go"))
    ps.rows["zz000010"]?.pin = nil; ps.rows["zz000010"]?.trusts = [:]                               // `pokeserver pin-reset`
    h3.pins = []; c3.addSteps(1); pt = ticks(w3, pt + 20, 5)                                        // (w3 holds that PC's session now)
    let reset = c3.phase == .pin(.set); _ = c3.login("zz000099")
    c.append((reset && c3.seat.trust == nil && c3.seat.session == nil, "cloud PIN: a PIN reset by the admin → 403 pin_needed at the next act → PIN 정하기; another ID drops this PC's trust"))
    return c
}
@MainActor private func isRadar(_ s: Screen) -> Bool { if case .radar = s { return true }; return false }
