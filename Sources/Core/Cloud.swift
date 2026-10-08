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
        var r = URLRequest(url: HTTPLink.base.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: path == "v2/duel" ? 35 : 15)   // (a duel's long poll holds up to 25 s)
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
    enum Ask: Sendable, Equatable { case login(force: Bool, resume: Bool), create, legacy, setPin, act(Int), team, trades, box(String), raid, market, duel }
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
    // docs/plans/12 (M1): the team, as the server last listed it (not in the act order: it reads, it changes nothing)
    private(set) var team: TeamReply? = nil, teamAt: Date? = nil
    var teamDue = false                                                    // asked for (the 팀 page opened): it goes once no act is waiting
    var teamNews = false                                                   // a new list came: the walker redraws
    static let teamEvery: TimeInterval = 180
    // 12 (M2): the open offers (mine and to me) and a teammate's box, as the server last listed them (reads, out of the act order too)
    private(set) var trades: TradesReply? = nil, box: BoxReply? = nil
    var tradesDue = false, tradesNews = false                              // asked for (the 교환 tab, a trade's act or news); a new list came
    private(set) var boxDue: String? = nil, boxGone: String? = nil          // whose box to fetch; one the server doesn't have (gone, or not on 3.0)
    // 12 (M3): the week's raid as the server last told it (a read)
    private(set) var raid: RaidReply? = nil; var raidDue = false
    // 12 §3.3 (3.5): the 교환 게시판 as the server last listed it (a read)
    private(set) var market: MarketReply? = nil; var marketDue = false
    var marketSeen: Int? = nil                                             // 3.8 (14 §2.2): one of my posts just opened — its offers count as seen (sent with the next read)
    // 12 §5 (3.6): a live battle's polls — a lane of their own (a long poll holds up to 25 s; acts and steps don't wait for it)
    var duelPoll: DuelReq? = nil                                           // the next one to send (the walker's: since, wait, version)
    private(set) var duelInFlight = false; var duelRetryAt = Date.distantPast
    var duelReplies: [DuelView?] = []                                      // for the walker, in order (nil: none open)
    var duelRecord: DuelRecords? = nil, duelRecordDue = false              // 3.8 (14 §5.4): the 전적, asked on the duel's lane while no duel is followed
    func takeDuel() -> [DuelView?] { let t = duelReplies; duelReplies = []; return t }
    // a tower run through a new session (docs/plans/12's note): the login says whether one goes on; nil = a server that doesn't keep them
    private(set) var keepsRuns = false; var towerCarried: Bool? = nil
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
    /// The team, fresh: now if it's older than 10 s (the server's own reuse), else as it is.
    func wantTeam(_ now: Date) { if teamAt.map({ now.timeIntervalSince($0) > 10 }) ?? true { teamDue = true }; tradesDue = true }
    /// A teammate's box, to pick from (12 §3.1): fetched now; another's shown till it comes is dropped.
    func wantBox(_ name: String) { if box.map({ trainerID($0.name)?.key != trainerID(name)?.key }) ?? false { box = nil }; boxGone = nil; boxDue = name }
    /// An offer the news brought (on the list at once: /v2/trades says the same once asked) …
    func noteOffer(_ o: TradeOffer) { var t = trades ?? TradesReply(incoming: [], outgoing: []); if !t.incoming.contains(where: { $0.id == o.id }) { t.incoming.append(o) }; trades = t }
    /// … and one gone through, turned down, taken back, or out of time.
    func forgetOffer(_ id: Int) { trades?.incoming.removeAll { $0.id == id }; trades?.outgoing.removeAll { $0.id == id } }
    /// The walker's: what has come back (each act once).
    func takeAnswers() -> [(act: Act, reply: ActReply?)] { let t = answers; answers = []; return t }

    /// The walker's tick: replies taken; then what's due goes, if nothing is out: a login / create / PIN, an act sent again, the walker's act,
    /// the 1.x save once, the steps every 15 s.
    func tick(_ now: Date) {
        if case .pin(.locked(let until)) = phase, now >= until { phase = .pin(.enter(wrong: false)) }   // the lock's over: the box again
        take(now)
        if phase == .on, base != nil, !duelInFlight, now >= duelRetryAt, var q = duelPoll, let id = seat.trainerID {   // the duel's lane: whatever else is out
            duelPoll = nil; q.id = id; q.session = seat.session ?? ""; duelInFlight = true
            link.post("v2/duel", (try? JSONEncoder().encode(q)) ?? Data()) { [inbox] s, b in inbox.put((.duel, s, b)) }
        }
        guard inFlight == nil, now >= retryAt else { return }
        if let a = asking { asking = nil; send(a); return }
        guard phase == .on else { return }
        if let o = out { post(.act(o.seq), "v2/act", o.body); return }                          // no answer last time: the same act, the same seq (the server may have it)
        if let a = queued { queued = nil; sendAct(a, now); return }
        if legacy != nil, seat.legacyUploaded != true { send(.legacy); return }
        if unsent > 0 || base == nil, now >= stepsAt { sendAct(.steps, now); return }           // (no save yet: a new trainer's comes with its first act)
        if base != nil, teamDue || teamAt.map({ now.timeIntervalSince($0) > Cloud.teamEvery }) ?? true { teamDue = false; teamAt = teamAt ?? now; tradesDue = true; raidDue = true; marketDue = true; send(.team); return }   // (every 3 minutes: who's walking now; the offers after it)
        if base != nil, tradesDue { tradesDue = false; send(.trades); return }
        if base != nil, let b = boxDue { boxDue = nil; send(.box(b)); return }
        if base != nil, raidDue { raidDue = false; send(.raid); return }
        if base != nil, marketDue { marketDue = false; send(.market) }
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
        case .team: post(a, "v2/team", (try? JSONEncoder().encode(TeamReq(id: id, session: seat.session ?? ""))) ?? Data())
        case .market: post(a, "v2/market", (try? JSONEncoder().encode(MarketReq(id: id, session: seat.session ?? "", seen: marketSeen))) ?? Data()); marketSeen = nil
        case .duel: break                                                                         // (its own lane: tick)
        case .raid: post(a, "v2/raid", (try? JSONEncoder().encode(TeamReq(id: id, session: seat.session ?? ""))) ?? Data())
        case .trades: post(a, "v2/trades", (try? JSONEncoder().encode(TeamReq(id: id, session: seat.session ?? ""))) ?? Data())
        case .box(let of): post(a, "v2/box", (try? JSONEncoder().encode(BoxReq(id: id, session: seat.session ?? "", of: of))) ?? Data())
        case .act: break
        }
    }
    private func sendAct(_ a: Act, _ now: Date) {
        guard let id = seat.trainerID, let session = seat.session else { answers.append((a, nil)); return }
        let n = unsent, req = ActReq(id: id, session: session, seq: seq + 1, steps: n > 0 ? n : nil, act: a, app: appVersion)   // app: which news kinds it knows (12 §1)
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
            if a == .duel {                                                                         // the duel's lane: its own in-flight, its own retry
                duelInFlight = false
                let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                if s == 200, let r = try? JSONDecoder().decode(DuelReply.self, from: body) { duelReplies.append(r.duel); if let rec = r.record { duelRecord = rec; teamNews = true } }
                else if s == 409, j?["reason"] as? String == "replaced" { drop(); phase = .replaced }
                else { duelRetryAt = now.addingTimeInterval(3); duelReplies.append(nil) }      // (no answer: again in a moment)
                continue
            }
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
            case (.team, 200):
                if let r = try? JSONDecoder().decode(TeamReply.self, from: body) { team = r; teamAt = now; teamNews = true }
            case (.trades, 200):
                if let r = try? JSONDecoder().decode(TradesReply.self, from: body) { trades = r; tradesNews = true }
            case (.box(let of), 200):
                if let r = try? JSONDecoder().decode(BoxReply.self, from: body) { box = r; tradesNews = true } else { boxGone = of }
            case (.raid, 200): if let r = try? JSONDecoder().decode(RaidReply.self, from: body) { raid = r; tradesNews = true }
            case (.market, 200): if let r = try? JSONDecoder().decode(MarketReply.self, from: body) { market = r; tradesNews = true }
            case (.box(let of), 404): boxGone = of; tradesNews = true                              // theirs isn't there (ours being gone: the next act says so)
            case (.team, 409), (.trades, 409), (.box, 409), (.raid, 409), (.market, 409): if j["reason"] as? String == "replaced" { drop(); phase = .replaced }
            case (.team, 403), (.trades, 403), (.box, 403), (.raid, 403), (.market, 403): if j["error"] as? String == "pin_needed" { phase = .pin(.set) }
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
                case .team, .trades, .box, .raid, .market, .duel: break                                             // (again in 3 minutes; a box when asked again)
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
        keepsRuns = j["tower"] is Bool; towerCarried = j["tower"] as? Bool ?? false               // a tower run between fights goes on in the new session (a server that says so)
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
        case .legacy, .team, .trades, .box, .raid, .market, .duel: break
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
    func startCloud(_ c: Cloud?, file f: URL? = nil, bak b: URL? = nil) {
        guard let c else { return }
        cloud = c
        let file = f ?? (persist ? Store.file : c.dir.appendingPathComponent("state.json")), bak = b ?? (persist ? Store.bak : c.dir.appendingPathComponent("state.json.bak"))   // a test's walker: never the app's folder
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
        if c.teamNews || c.tradesNews { c.teamNews = false; c.tradesNews = false; refreshPane(now, force: true); host?.redraw(.all) }   // a new team list, offers, a box: the pages, the menu's tile
        if let t = c.towerCarried { c.towerCarried = nil; towerRun = t; fightGone(now) }   // (a login: a fight on is over at the server — 3.8.6)
        duelRecordTick(c); duelTick(c, now)                                                       // 12 §5: a live battle's polls and what they bring                          // a login: a tower run goes on (the server kept it) or none does
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
    var rng = Seeded(s: 77), nextUID = 1_000_001, now: Date? = nil, stepCap: Int? = nil       // stepCap: the steps allowance (the real one fills at 15 a second)
    var lastAct: [String: Date] = [:], inbox: [String: [News]] = [:], greeted: [String: Date] = [:]   // 12 §2 (M1): each trainer's last act, its undelivered 인사, a pair's last one
    // 12 §4 (M3): this week's raid — the boss, the team's HP (total 0: none set up yet), each fighter's damage and fights, the last hits,
    // balls left, who caught it, who had the clear reward; odds = the next throws' results (empty: 30 % on the server's dice)
    var raidBoss = Mon(dex: 249, level: 70, female: false), raidTotal = 0, raidLeft = 0, raidDealt: [String: Int] = [:], raidFights: [String: Int] = [:]
    var raidRecent: [RaidHit] = [], raidBalls: [String: Int] = [:], raidCaught: Set<String> = [], raidRewarded: Set<String> = [], raidOdds: [Bool] = []
    func raidOpen(_ total: Int) { raidTotal = total; raidLeft = total; raidDealt = [:]; raidFights = [:]; raidRecent = []; raidBalls = [:]; raidCaught = []; raidRewarded = [] }
    var offers: [(o: TradeOffer, from: String, to: String)] = [], nextOffer = 1, mail: [String: [News]] = [:], stale: Set<String> = []   // 12 §3 (M2): offers (keys), 3.3's news, saves another's trade changed
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
        if path == "v2/duel" { duelRead(json, done); return }                                                   // (its long poll may wait: its own answer)
        if path == "v2/act" { (s, d) = act(json); flushDuelWaiters() } else if path == "v2/team" { (s, d) = team(json) } else if path == "v2/trades" { (s, d) = trades(json) } else if path == "v2/box" { (s, d) = box(json) } else if path == "v2/raid" { (s, d) = raidLobby(json) } else if path == "v2/market" { (s, d) = marketBoard(json) }
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
        let taken = min(q.steps ?? 0, stepCap ?? .max)
        if case .raid = q.act, raidTotal > 0 { r.play.raidBoss = RaidBoss(week: "2026-W40", boss: raidBoss, left: raidLeft) }   // (the server's, before a raid act)
        var o = Engine.apply(q.act, steps: taken, walk: &w, play: &r.play, rng: &rng, now: now ?? Date(), ids: &ids)
        nextUID = ids.next; acts.append(q.act); steps.append(q.steps ?? 0); clock += 1; lastAct[id.key] = now ?? Date()
        if case .greet(let to) = q.act, o.cannot == nil {                                                  // 12 §2.3: into their inbox, once an hour a pair
            if let t = trainerID(to), t.key != id.key, rows[t.key]?.walk != nil, !isFriend(id.key, t.key) { o = .no("친구에게만\n인사할 수 있어요") }
            else if let t = trainerID(to), t.key != id.key, rows[t.key]?.walk != nil {
                let pair = id.key + ">" + t.key
                if let g = greeted[pair], (now ?? Date()).timeIntervalSince(g) < 3600 { o = .no("조금 뒤에 다시\n인사할 수 있어요") }
                else { greeted[pair] = now ?? Date(); inbox[t.key, default: []].append(.hello(from: r.name, dex: w.companion.dex, shiny: w.companion.shiny == true)) }
            } else { o = .no("인사할 수 없는\n트레이너예요") }
        }
        raided(q.act, id.key, r.name, &w, &o)
        let preDuel = w
        if o.cannot == nil, let why = duelAct(q.act, id.key, r.name, &w, &o) { o.cannot = why }
        if w != preDuel { o.changed = true }                                                               // a duel over: this side's BP and record
        if o.cannot == nil, let why = social(q.act, id.key, r.name, &w, &o.news) { o.cannot = why } else if o.cannot == nil { switch q.act { case .marketAccept, .marketList, .marketBid, .marketUnlist, .marketWithdraw, .claim: o.changed = true; default: break } }
        if o.cannot == nil, let why = trade(q.act, id.key, r.name, &w, &o.news) { o.cannot = why } else if case .tradeAccept = q.act, o.cannot == nil { o.changed = true }
        let preVisit = w
        if o.cannot == nil, let why = visitAct(q.act, id.key, r.name, &w, &o.news) { o.cannot = why }
        visitTick(id.key, steps: o.cannot == nil ? taken : 0, &w, &o.news)
        if w != preVisit { o.changed = true }
        if let a = q.app, verCmp(a, "3.2").map({ $0 >= 0 }) == true, let mail = inbox.removeValue(forKey: id.key) { o.news += mail }   // (3.2 on: hello)
        if let a = q.app, verCmp(a, "3.3").map({ $0 >= 0 }) == true, let m = mail.removeValue(forKey: id.key) { o.news += m }        // (3.3 on: 교환's)
        let carried = stale.remove(id.key) != nil                                                          // another's trade changed this save: the reply carries it
        if o.changed || first { r.rev += 1; r.walk = FakeCloud.text(w); r.at = clock }
        let reply = (try? JSONEncoder().encode(ActReply(rev: r.rev, walk: o.changed || first || carried ? w : nil, taken: q.steps.map { _ in taken }, out: o))) ?? Data()
        r.seq = q.seq; r.reply = reply; rows[id.key] = r
        return (200, reply)
    }
    /// POST /v2/team: every trainer with a save, as cards (idle: since its last act here).
    func team(_ d: Data) -> (Int, Data) {
        guard let q = try? JSONDecoder().decode(TeamReq.self, from: d), let id = trainerID(q.id), let r = rows[id.key] else { return err(404, ["error": "no_trainer"]) }
        guard q.session == r.session else { return err(409, ["error": "conflict", "reason": "replaced"]) }
        if pins, r.pin == nil { return err(403, ["error": "pin_needed"]) }
        let at = now ?? Date()
        let cards = rows.keys.sorted().compactMap { k -> TeamCard? in
            guard k == id.key || isFriend(id.key, k), let row = rows[k], let w = row.walk.flatMap(Cloud.walk) else { return nil }   // 3.5: me and my friends
            return TeamCard(name: row.name, walk: w, today: w.today, week: w.today, idle: lastAct[k].map { Int(at.timeIntervalSince($0)) } ?? 999_999)
        }
        let asked = (friendAsks[id.key] ?? []).sorted().compactMap { rows[$0]?.name }, sent = friendAsks.filter { $0.value.contains(id.key) }.keys.sorted().compactMap { rows[$0]?.name }
        let all = viewAll.contains(id.key) ? rows.keys.sorted().compactMap { k -> TeamCard? in
            guard let row = rows[k], let w = row.walk.flatMap(Cloud.walk) else { return nil }
            return TeamCard(name: row.name, walk: w, today: w.today, week: w.today, idle: lastAct[k].map { Int(at.timeIntervalSince($0)) } ?? 999_999)
        } : nil
        return (200, (try? JSONEncoder().encode(TeamReply(week: "2026-W40", cards: cards, requests: asked, sent: sent, visits: visitsOf(id.key), all: all))) ?? Data())
    }
    /// 12 §3: 교환's acts on the acting trainer's save (w; its news), the other's save here (rev + 1, its next reply brings it). A reason = cannot.
    func trade(_ a: Act, _ key: String, _ name: String, _ w: inout Walk, _ news: inout [News]) -> String? {
        func row(_ id: Int) -> Int? { offers.firstIndex { $0.o.id == id && $0.o.state == "open" } }
        func close(_ i: Int, _ s: String) { offers[i].o.state = s }
        switch a {
        case .tradeOffer(let raw, let give, let want):
            guard let to = trainerID(raw), to.key != key, let them = rows[to.key], let theirs = them.walk.flatMap(Cloud.walk) else { return "교환할 수 없는\n트레이너예요" }
            guard let r = w.ref(uid: give), r >= 0, let mon = w.mon(r) else { return "상자의 포켓몬만\n교환할 수 있어요" }
            var wanted: Mon? = nil
            if let want { guard let r2 = theirs.ref(uid: want), r2 >= 0 else { return "상대 상자에\n없는 포켓몬이에요" }; wanted = theirs.mon(r2) }
            let open = offers.filter { $0.from == key && $0.o.state == "open" }
            guard open.count < 5 else { return "걸어 둔 교환이\n너무 많아요 (5개)" }
            guard !open.contains(where: { $0.o.mon.uid == give }) else { return "이미 교환에\n걸어 둔 포켓몬이에요" }
            let o = TradeOffer(id: nextOffer, from: name, to: them.name, mon: mon, want: wanted, at: Int((now ?? Date()).timeIntervalSince1970), state: "open"); nextOffer += 1
            offers.append((o, key, to.key)); mail[to.key, default: []].append(.tradeOffer(id: o.id, from: name, mon: mon, want: wanted))
        case .tradeDecline(let id), .tradeCancel(let id):
            let mine: Bool = { if case .tradeCancel = a { return true }; return false }()
            guard let i = row(id), (mine ? offers[i].from : offers[i].to) == key else { return "그 교환은 이제\n없어요" }
            close(i, mine ? "cancelled" : "declined")
            mail[mine ? offers[i].to : offers[i].from, default: []].append(.tradeClosed(id: id, with: name, why: mine ? "상대가 거뒀어요" : "상대가 거절했어요"))
        case .tradeAccept(let id, let giveRaw):
            guard let i = row(id), offers[i].to == key else { return "그 교환은 이제\n없어요" }
            let t = offers[i]
            guard let give = t.o.want?.uid ?? giveRaw, w.ref(uid: give).map({ $0 >= 0 }) == true else { return t.o.want == nil ? "줄 포켓몬을\n골라 주세요" : "그 포켓몬이\n상자에 없어요" }
            guard let theirs = rows[t.from]?.walk.flatMap(Cloud.walk), let u2 = t.o.mon.uid, theirs.ref(uid: u2).map({ $0 >= 0 }) == true else {
                close(i, "failed"); mail[t.from, default: []].append(.tradeClosed(id: id, with: name, why: "포켓몬이 상자에 없어요")); return "상대 포켓몬이\n상자에 없어요"
            }
            close(i, "done")
            _ = exchange(id: id, key, name, &w, mine: give, other: t.from, theirs: u2, &news)
        default: break
        }
        return nil
    }
    /// 12 §3.2: one of w's box (mine) for one of `other`'s (theirs), both saves at once — new uids, 어버이, a trade evolution at the receiver
    /// (the item from the giver's bag). This side's news in `news`, the other's in its mail (its next reply brings its save); offers, posts and
    /// bids with either Pokémon close. false: one isn't in its box.
    func exchange(id: Int, _ key: String, _ name: String, _ w: inout Walk, mine: Int, other: String, theirs u2: Int, _ news: inout [News]) -> Bool {
        guard let r = w.ref(uid: mine), r >= 0, var theirs = rows[other]?.walk.flatMap(Cloud.walk), let r2 = theirs.ref(uid: u2), r2 >= 0 else { return false }
        let otherName = rows[other]?.name ?? other
        let mineOut = w.box.remove(at: r), theirsOut = theirs.box.remove(at: r2)
        func receive(_ m0: Mon, _ giver: inout Walk, _ giverName: String, _ into: inout Walk) -> (Mon, [News]) {
            var m = m0; m.uid = nextUID; nextUID += 1; m.ot = m.ot ?? giverName; _ = into.keep(m)
            guard let e = Walk.tradeEvolution(of: m, giverBag: giver.items + giver.bag), let ref = into.ref(uid: m.uid!) else { return (m, []) }
            if let item = e.item { _ = giver.take(item) }
            into.evolve(Evo(from: e.from, to: e.to, way: e.way, level: e.level, item: nil, female: e.female, time: e.time, place: e.place, party: e.party), ref: ref, shed: false)
            let after = into.mon(ref) ?? m; return (after, [.evolve(uid: m.uid!, from: m.dex, to: after.dex, shed: nil)])
        }
        let (got, gotNews) = receive(theirsOut, &theirs, otherName, &w), (sent, sentNews) = receive(mineOut, &w, name, &theirs)
        func moved(_ k: String, _ u: Int?) -> Bool { (k == key && u == mine) || (k == other && u == u2) }
        for k in offers.indices where offers[k].o.state == "open" && moved(offers[k].from, offers[k].o.mon.uid) {
            offers[k].o.state = "failed"; mail[offers[k].from == key ? offers[k].to : offers[k].from, default: []].append(.tradeClosed(id: offers[k].o.id, with: name, why: "포켓몬이 교환됐어요"))
        }
        for k in listings.indices where listings[k].open && moved(listings[k].key, listings[k].l.mon.uid) {
            listings[k].open = false; for b in bids.indices where bids[b].b.listing == listings[k].l.id && bids[b].b.state == "open" { bids[b].b.state = "failed"; mail[bids[b].key, default: []].append(.tradeClosed(id: listings[k].l.id, with: name, why: "포켓몬이 교환됐어요")) }
        }
        for b in bids.indices where bids[b].b.state == "open" && moved(bids[b].key, bids[b].b.mon.uid) {
            bids[b].b.state = "failed"; mail[bids[b].poster, default: []].append(.tradeClosed(id: bids[b].b.listing, with: name, why: "포켓몬이 교환됐어요"))
        }
        news += [.traded(id: id, with: otherName, gave: mineOut, got: got)] + gotNews
        mail[other, default: []] += [.traded(id: id, with: name, gave: theirsOut, got: sent)] + sentNews
        rows[other]?.rev += 1; rows[other]?.walk = FakeCloud.text(theirs); stale.insert(other)
        return true
    }
    // 12 §5 (3.6): live battles — one Battle from the challenger's side (pvp: the other's pick is foePlan), the other sees it mirrored
    struct FakeDuel {
        var id: Int; var a, b, aName, bName: String; var state: String; var battle: Battle? = nil; var turns: [[Beat]] = []
        var planA: BattleCmd? = nil, planB: BattleCmd? = nil, needA: String? = nil, needB: String? = nil, idleA = 0, idleB = 0
        var deadline: Int; var version = 0; var winner: String? = nil, why: String? = nil
        var partyA: [Mon]? = nil, partyB: [Mon]? = nil, pickA: [Int]? = nil, pickB: [Int]? = nil, at = 0, endedAt: Int? = nil   // 3.8: the sixes, the threes picked
    }
    static let duelOpen = ["queued", "invited", "picking", "active"]
    /// 14 §5.1: the 대전 파티 as it fights — the registered ones still here, as Lv.50 copies; nil under three.
    static func duelSix(_ x: Walk) -> [Mon]? {
        let ms = (x.duelParty ?? []).compactMap { x.ref(uid: $0).flatMap(x.mon) }.map { m -> Mon in var m = m; if m.known == nil { m.known = m.moves }; m.level = Walk.towerLevel; return m }
        return ms.count >= 3 ? Array(ms.prefix(6)) : nil
    }
    func startDuel(_ i: Int) {
        guard let pa = duels[i].pickA, let pb = duels[i].pickB, let xa = duels[i].partyA, let xb = duels[i].partyB else { return }
        var b = Battle(party: pa.compactMap { xa[safe: $0] }, trainer: duels[i].bName, foes: pb.compactMap { xb[safe: $0] }); b.pvp = true; b.seed = rng.next()
        duels[i].turns = [b.begin(weather: nil, &rng)]; duels[i].battle = b
        duels[i].state = "active"; (duels[i].needA, duels[i].needB) = ("move", "move"); duels[i].deadline = clockNow + 30
    }
    func duelRecords(_ key: String) -> DuelRecords {
        let over = duels.filter { ($0.a == key || $0.b == key) && $0.state == "over" }.reversed()
        let wins = over.filter { $0.winner == key }.count
        return DuelRecords(wins: wins, losses: over.count - wins, recent: over.prefix(20).map { d in
            let first = d.a == key
            return DuelRecord(id: d.id, opponent: first ? d.bName : d.aName, won: d.winner == key, why: d.why ?? "faint", at: d.endedAt ?? d.at,
                              mine: (first ? d.battle?.mine : d.battle?.theirs)?.map(\.mon.dex) ?? [], theirs: (first ? d.battle?.theirs : d.battle?.mine)?.map(\.mon.dex) ?? [])
        })
    }
    var duels: [FakeDuel] = [], nextDuel = 1, duelWaiters: [(key: String, since: Int, version: Int, done: @Sendable (Int, Data) -> Void)] = []
    var clockNow: Int { Int((now ?? Date()).timeIntervalSince1970) }
    func duelIndex(_ key: String) -> Int? { duels.lastIndex { ($0.a == key || $0.b == key) && FakeCloud.duelOpen.contains($0.state) } ?? duels.lastIndex { $0.a == key || $0.b == key } }
    func duelAct(_ act: Act, _ key: String, _ name: String, _ w: inout Walk, _ o: inout Outcome) -> String? {
        if let i = duelIndex(key) { duelTick(i, actor: key, &w) }
        switch act {
        case .duelChallenge(let raw):
            guard let to = trainerID(raw), to.key != key, let them = rows[to.key], them.walk != nil else { return "대전할 수 없는\n트레이너예요" }
            guard isFriend(key, to.key) else { return "친구와만\n대전할 수 있어요" }
            guard FakeCloud.duelSix(w) != nil else { return "대전 파티를\n먼저 정해 주세요" }
            guard them.walk.flatMap(Cloud.walk).flatMap(FakeCloud.duelSix) != nil else { return "상대가 대전 파티를\n아직 정하지 않았어요" }
            for k in [key, to.key] where duels.contains(where: { ($0.a == k || $0.b == k) && FakeCloud.duelOpen.contains($0.state) }) { return k == key ? "이미 대전 중이에요" : "상대가 대전 중이에요" }
            duels.append(FakeDuel(id: nextDuel, a: key, b: to.key, aName: name, bName: them.name, state: "invited", deadline: clockNow + 60, at: clockNow)); nextDuel += 1
            mail[to.key, default: []].append(.duelInvite(id: nextDuel - 1, from: name)); o.duel = duelView(duels.count - 1, key, since: 0)
        case .duelAccept(let id), .duelDecline(let id), .duelCancel(let id):
            guard let i = duels.firstIndex(where: { $0.id == id }), duels[i].state == "invited" else { return "그 대전은 이제\n없어요" }
            switch act {
            case .duelCancel: guard duels[i].a == key else { return "그 대전은 이제\n없어요" }; duels[i].state = "cancelled"
            case .duelDecline: guard duels[i].b == key else { return "그 대전은 이제\n없어요" }; duels[i].state = "declined"
            default:                                                                                // 3.8: both sixes in, a minute to pick 3
                guard duels[i].b == key else { return "그 대전은 이제\n없어요" }
                guard let mine = FakeCloud.duelSix(w) else { return "대전 파티를\n먼저 정해 주세요" }
                guard let six = rows[duels[i].a]?.walk.flatMap(Cloud.walk).flatMap(FakeCloud.duelSix) else { return "그 대전은 이제\n없어요" }
                (duels[i].partyA, duels[i].partyB) = (six, mine); duels[i].state = "picking"; duels[i].deadline = clockNow + 60
            }
            if !["picking", "active"].contains(duels[i].state) { duels[i].endedAt = clockNow }
            duels[i].version += 1; o.duel = duelView(i, key, since: 0)
        case .duelQueue:                                                                            // 14 §5.2: whoever else is waiting
            guard let mine = FakeCloud.duelSix(w) else { return "대전 파티를\n먼저 정해 주세요" }
            if let i = duelIndex(key), FakeCloud.duelOpen.contains(duels[i].state) {
                if duels[i].state == "queued" { o.duel = duelView(i, key, since: 0); return nil }
                return "이미 대전 중이에요"
            }
            if let i = duels.firstIndex(where: { $0.state == "queued" && $0.a != key && $0.deadline >= clockNow }),
               let six = rows[duels[i].a]?.walk.flatMap(Cloud.walk).flatMap(FakeCloud.duelSix) {
                duels[i].b = key; duels[i].bName = name; (duels[i].partyA, duels[i].partyB) = (six, mine); duels[i].state = "picking"; duels[i].deadline = clockNow + 60; duels[i].version += 1
                o.duel = duelView(i, key, since: 0); return nil
            }
            duels.append(FakeDuel(id: nextDuel, a: key, b: "", aName: name, bName: "", state: "queued", deadline: clockNow + 60, at: clockNow)); nextDuel += 1
            o.duel = duelView(duels.count - 1, key, since: 0)
        case .duelQueueCancel:
            guard let i = duelIndex(key), duels[i].state == "queued", duels[i].a == key else { return "기다리는 중이 아니에요" }
            duels[i].state = "cancelled"; duels[i].endedAt = clockNow; duels[i].version += 1; o.duel = duelView(i, key, since: 0)
        case .duelPick(let id, let slots):
            guard let i = duels.firstIndex(where: { $0.id == id }), duels[i].state == "picking", duels[i].a == key || duels[i].b == key else { return "그 대전은 이제\n없어요" }
            let first = duels[i].a == key, six = (first ? duels[i].partyA : duels[i].partyB) ?? []
            guard slots.count == 3, Set(slots).count == 3, slots.allSatisfy({ six.indices.contains($0) }) else { return "3마리를\n골라 주세요" }
            guard (first ? duels[i].pickA : duels[i].pickB) == nil else { return "이미 골랐어요" }
            if first { duels[i].pickA = slots } else { duels[i].pickB = slots }
            duels[i].version += 1; startDuel(i); o.duel = duelView(i, key, since: 0)
        case .duelMove(let id, let cmd):
            guard let i = duels.firstIndex(where: { $0.id == id }), duels[i].state == "active", let b = duels[i].battle else { return "그 대전은 이제\n없어요" }
            let first = duels[i].a == key
            guard first || duels[i].b == key else { return "그 대전은 이제\n없어요" }
            guard let need = first ? duels[i].needA : duels[i].needB else { return "상대를 기다리는 중이에요" }
            let s: Side = first ? .me : .it, mine = first ? b.mine : b.theirs, cur = first ? b.me : b.it
            switch (need, cmd) {
            case ("move", .forfeit): break
            case ("move", .fight(let slot)): if b.forcedMove(s) == nil, b.f(s).pp[safe: slot] == 0 { return "기술의 남은\nPP가 없다!" }
            case ("move", .swap(let k)), ("replace", .replace(let k)): guard mine.indices.contains(k), mine[k].alive, k != cur else { return "교체할 수 없어요" }; if need == "move", let why = b.switchBlock(s) { return why }
            default: return need == "replace" ? "다음 포켓몬을\n골라 주세요" : "대전에서는 쓸 수 없어요"
            }
            if first { duels[i].planA = cmd; duels[i].needA = nil; duels[i].idleA = 0 } else { duels[i].planB = cmd; duels[i].needB = nil; duels[i].idleB = 0 }
            duels[i].version += 1
            duelResolve(i, actor: key, &w)
            o.duel = duelView(i, key, since: duels[i].turns.count - 1)
        default: return nil
        }
        return nil
    }
    /// Picks not made in time are made (two in a row: that side gives up); an invitation past its minute goes.
    func duelTick(_ i: Int, actor: String?, _ w: inout Walk) {
        guard clockNow > duels[i].deadline else { return }
        if duels[i].state == "invited" { duels[i].state = "expired"; duels[i].endedAt = clockNow; duels[i].version += 1; return }
        if duels[i].state == "queued" { duels[i].state = "unmatched"; duels[i].endedAt = clockNow; duels[i].version += 1; return }
        if duels[i].state == "picking" {                                                           // a minute's up: the first three for whoever didn't pick
            if duels[i].pickA == nil { duels[i].pickA = [0, 1, 2] }; if duels[i].pickB == nil { duels[i].pickB = [0, 1, 2] }
            duels[i].version += 1; startDuel(i); return
        }
        guard duels[i].state == "active", let b = duels[i].battle else { return }
        for first in [true, false] {
            guard let need = first ? duels[i].needA : duels[i].needB else { continue }
            let s: Side = first ? .me : .it, mine = first ? b.mine : b.theirs, cur = first ? b.me : b.it, idle = (first ? duels[i].idleA : duels[i].idleB) + 1
            let pick: BattleCmd = idle >= 2 ? .forfeit : need == "replace" ? .replace(to: mine.indices.first { mine[$0].alive && $0 != cur } ?? cur)
                : .fight(slot: b.f(s).moves.indices.first { b.usable(s).contains(b.f(s).moves[$0]) } ?? 0)
            if first { duels[i].planA = pick; duels[i].needA = nil; duels[i].idleA = idle } else { duels[i].planB = pick; duels[i].needB = nil; duels[i].idleB = idle }
        }
        duels[i].version += 1; duelResolve(i, actor: actor, &w, timedOut: true)
    }
    /// Both picks in: the turn (or the replacements), the next needs, or the end (the winner's BP, both records).
    func duelResolve(_ i: Int, actor: String?, _ w: inout Walk, timedOut: Bool = false) {
        guard duels[i].state == "active", duels[i].needA == nil, duels[i].needB == nil, var b = duels[i].battle else { return }
        func finish(_ winner: String, _ why: String) {
            duels[i].state = "over"; duels[i].winner = winner; duels[i].why = why; (duels[i].needA, duels[i].needB) = (nil, nil); duels[i].version += 1; duels[i].endedAt = clockNow
            for k in [duels[i].a, duels[i].b] {
                func change(_ x: inout Walk) { if k == winner { x.bp = (x.bp ?? 0) + 3; x.duelWins = (x.duelWins ?? 0) + 1 } else { x.duelLosses = (x.duelLosses ?? 0) + 1 } }
                if k == actor { change(&w); continue }
                guard var x = rows[k]?.walk.flatMap(Cloud.walk) else { continue }
                change(&x); rows[k]?.rev += 1; rows[k]?.walk = FakeCloud.text(x); stale.insert(k)
            }
        }
        if duels[i].planA == .forfeit || duels[i].planB == .forfeit {
            let aQuit = duels[i].planA == .forfeit
            finish(aQuit ? duels[i].b : duels[i].a, timedOut && (aQuit ? duels[i].idleA : duels[i].idleB) >= 2 ? "timeout" : "forfeit"); return
        }
        var beats: [Beat] = []
        if b.mustReplace || b.foeMustReplace == true {
            if case .replace(let k)? = duels[i].planA, b.mustReplace { beats += b.replace(k) }
            if case .replace(let k)? = duels[i].planB, b.foeMustReplace == true { beats += b.replaceFoe(k) }
        } else {
            var mine: Move = .fight(165)
            switch duels[i].planA { case .fight(let slot)?: mine = .fight(b.forcedMove(.me) ?? b.f(.me).moves[safe: slot] ?? 165); case .swap(let k)?: mine = .swap(k); default: break }
            switch duels[i].planB { case .fight(let slot)?: b.foePlan = .fight(b.forcedMove(.it) ?? b.f(.it).moves[safe: slot] ?? 165); case .swap(let k)?: b.foePlan = .swap(k); default: b.foePlan = .fight(165) }
            if case .fight(let id) = mine, b.usable(.me).isEmpty, b.forcedMove(.me) == nil, id != 165 { mine = .fight(165) }
            beats = b.turn(mine, &rng); b.foePlan = nil
        }
        duels[i].turns.append(beats); duels[i].battle = b; (duels[i].planA, duels[i].planB) = (nil, nil); duels[i].version += 1
        if b.over { finish(beats.last == .won ? duels[i].a : duels[i].b, "faint"); return }
        switch (b.mustReplace, b.foeMustReplace == true) {
        case (false, false): (duels[i].needA, duels[i].needB) = ("move", "move")
        case (let x, let y): (duels[i].needA, duels[i].needB) = (x ? "replace" : nil, y ? "replace" : nil)
        }
        duels[i].deadline = clockNow + 30
    }
    /// The battle as `key` sees it: the turns after `since`, its side first, the lines worded for it.
    func duelView(_ i: Int, _ key: String, since: Int) -> DuelView? {
        let d = duels[i], first = d.a == key
        var v = DuelView(id: d.id, state: d.state, opponent: first ? d.bName : d.aName, challenger: first, turn: d.turns.count,
                         need: first ? d.needA : d.needB, deadline: FakeCloud.duelOpen.contains(d.state) ? d.deadline : nil, version: d.version)
        if d.state == "picking", let xa = d.partyA, let xb = d.partyB {
            let (mine, theirs) = first ? (xa, xb) : (xb, xa)
            v.parties = DuelParties(mine: mine, theirs: theirs.map { DuelMon(dex: $0.dex, female: $0.female, shiny: $0.shiny == true) }, picked: first ? d.pickA : d.pickB, theyPicked: (first ? d.pickB : d.pickA) != nil)
        }
        let fresh = Array(d.turns.dropFirst(max(0, since)).joined())
        if let b = d.battle {
            if first { v.battle = b; v.beats = fresh }
            else { let words = duelWords(ours: b.mine.map(\.mon.dex), theirs: b.theirs.map(\.mon.dex)); v.battle = b.mirrored(name: d.aName); v.beats = fresh.map { $0.flipped(words) } }
        }
        if d.state == "over", let wnr = d.winner { v.result = DuelResult(won: wnr == key, why: d.why ?? "faint", bp: wnr == key ? 3 : 0) }
        return v
    }
    /// POST /v2/duel: my live battle; with wait and an unchanged version, the answer waits for the next change (flushDuelWaiters).
    func duelRead(_ d: Data, _ done: @escaping @Sendable (Int, Data) -> Void) {
        guard let q = try? JSONDecoder().decode(DuelReq.self, from: d), let id = trainerID(q.id), let r = rows[id.key] else { done(404, Data()); return }
        guard q.session == r.session else { let (s, b) = err(409, ["error": "conflict", "reason": "replaced"]); done(s, b); return }
        let record = q.record == true ? duelRecords(id.key) : nil
        guard let i = duelIndex(id.key) else { done(200, (try? JSONEncoder().encode(DuelReply(duel: nil, record: record))) ?? Data()); return }
        var none = Walk(); duelTick(i, actor: nil, &none)
        if q.wait == true, let v = q.version, v == duels[i].version { duelWaiters.append((id.key, q.since ?? 0, v, done)); return }
        done(200, (try? JSONEncoder().encode(DuelReply(duel: duelView(i, id.key, since: q.since ?? 0), record: record))) ?? Data())
    }
    func flushDuelWaiters() {
        let waiting = duelWaiters; duelWaiters = []
        for x in waiting {
            guard let i = duelIndex(x.key), duels[i].version != x.version else { duelWaiters.append(x); continue }
            x.done(200, (try? JSONEncoder().encode(DuelReply(duel: duelView(i, x.key, since: x.since)))) ?? Data())
        }
    }
    // 3.8 (14 §3): 맡겨 키우기 — one away per owner, three guests per host; the host's steps raise it; home through the 받기 함
    struct FakeVisit { var id: Int; var owner, ownerName, host, hostName: String; var mon: Mon; var steps = 0; var on = true; var ends: Int; var bp = 0; var paid = false }
    var visitList: [FakeVisit] = [], nextVisit = 1, visitSteps: [Int: Int] = [:], viewAll: Set<String> = []
    func visitAct(_ a: Act, _ key: String, _ name: String, _ w: inout Walk, _ news: inout [News]) -> String? {
        switch a {
        case .visitSend(let raw, let uid):
            guard let to = trainerID(raw), to.key != key, let host = rows[to.key], host.walk != nil else { return "보낼 수 없는\n트레이너예요" }
            guard isFriend(key, to.key) else { return "친구에게만\n보낼 수 있어요" }
            guard let seen = lastAct[to.key], (now ?? Date()).timeIntervalSince(seen) < 60 else { return "지금 걷고 있는 친구에게만\n보낼 수 있어요" }
            guard !visitList.contains(where: { $0.on && $0.owner == key && $0.host == to.key }) else { return josa(host.name, "에게", "에게") + " 이미\n맡긴 포켓몬이 있어요" }   // (3.8.5: one a friend)
            guard let ref = w.ref(uid: uid) else { return "그 포켓몬은\n없어요" }
            guard ref != -1 else { return "동료는 보낼 수 없어요" }
            guard visitList.filter({ $0.on && $0.host == to.key }).count < Walker.guestsMax else { return josa(host.name, "은", "는") + " 이미\n\(Walker.guestsMax)마리를 맡고 있어요" }
            guard let m = w.mon(ref) else { return "그 포켓몬은\n없어요" }
            if ref <= -2 { w.caught.remove(at: -2 - ref) } else { w.box.remove(at: ref) }
            w.duelParty = w.duelParty?.filter { $0 != uid }
            visitList.append(FakeVisit(id: nextVisit, owner: key, ownerName: name, host: to.key, hostName: host.name, mon: m, ends: clockNow + 5 * 3600)); nextVisit += 1
            mail[to.key, default: []].append(.visitCame(id: nextVisit - 1, owner: name, dex: m.dex, shiny: m.shiny == true))
        case .visitEnd(let id):
            guard let i = visitList.firstIndex(where: { $0.id == id && $0.on }), visitList[i].owner == key || visitList[i].host == key else { return "그 포켓몬은 이제\n여기 없어요" }
            endVisit(i); payVisits(key, &w, &news)
        default: break
        }
        return nil
    }
    func endVisit(_ i: Int) {
        visitList[i].on = false; visitList[i].bp = min(5, visitList[i].steps / 2000)
        giveClaim(visitList[i].owner, "visit", from: visitList[i].hostName, visitList[i].mon); visitSteps[nextClaim - 1] = visitList[i].steps
    }
    func visitTick(_ key: String, steps: Int, _ w: inout Walk, _ news: inout [News]) {
        for i in visitList.indices where visitList[i].on && visitList[i].host == key && visitList[i].ends >= clockNow { visitList[i].steps += steps }
        for i in visitList.indices where visitList[i].on && (visitList[i].host == key || visitList[i].owner == key) && visitList[i].ends < clockNow { endVisit(i) }
        payVisits(key, &w, &news)
    }
    func payVisits(_ key: String, _ w: inout Walk, _ news: inout [News]) {
        for i in visitList.indices where !visitList[i].on && !visitList[i].paid && visitList[i].host == key {
            let v = visitList[i]; if v.bp > 0 { w.bp = (w.bp ?? 0) + v.bp }
            news.append(.visitDone(owner: v.ownerName, dex: v.mon.dex, steps: v.steps, bp: v.bp)); visitList[i].paid = true
        }
    }
    func visitsOf(_ key: String) -> Visits {
        func view(_ v: FakeVisit) -> Visit { Visit(id: v.id, owner: v.ownerName, host: v.hostName, mon: v.mon, steps: v.steps, ends: v.ends) }
        return Visits(away: visitList.last { $0.on && $0.owner == key }.map(view), guests: visitList.filter { $0.on && $0.host == key }.map(view),
                      out: visitList.filter { $0.on && $0.owner == key }.map(view))
    }
    // 12 §2.4 (3.5): 친구 — pairs, requests (to → from)
    var friends: Set<String> = [], friendAsks: [String: Set<String>] = [:]
    static func pair(_ a: String, _ b: String) -> String { a < b ? a + "|" + b : b + "|" + a }
    func befriend(_ a: String, _ b: String) { friends.insert(FakeCloud.pair(a.lowercased(), b.lowercased())) }
    func isFriend(_ a: String, _ b: String) -> Bool { friends.contains(FakeCloud.pair(a, b)) }
    // 12 §3.3 (3.5): the 교환 게시판 — posts (the poster's key, open), offers on them (the bidder's key, the poster's)
    var listings: [(l: Listing, key: String, open: Bool)] = [], bids: [(b: Bid, key: String, poster: String)] = [], nextListing = 1, nextBid = 1
    // 3.8 (14 §2): what waits in each one's 받기 함 (traded · returned · visit), offers seen by the poster
    var claimBox: [String: [Claim]] = [:], nextClaim = 1, seenBids: Set<Int> = []
    func giveClaim(_ key: String, _ kind: String, from: String, _ m: Mon, note: String? = nil) {
        claimBox[key, default: []].append(Claim(id: nextClaim, kind: kind, from: from, mon: m, at: clockNow, note: note)); nextClaim += 1
        mail[key, default: []].append(.claimReady(id: nextClaim - 1, kind: kind))
    }
    /// The one held out of the box (a post's, an offer's): straight back into it (its own act).
    func backToBox(_ m: Mon, _ w: inout Walk) { _ = w.keep(m) }
    /// 친구 and the 게시판's acts (the server's: other trainers, the board), on the acting trainer's save (w) and its news. A reason = cannot.
    func social(_ a: Act, _ key: String, _ name: String, _ w: inout Walk, _ news: inout [News]) -> String? {
        let at = Int((now ?? Date()).timeIntervalSince1970)
        func used(_ u: Int) -> Bool { listings.contains { $0.open && $0.key == key && $0.l.mon.uid == u } || bids.contains { $0.b.state == "open" && $0.key == key && $0.b.mon.uid == u } }
        switch a {
        case .friendRequest(let raw):
            guard let t = trainerID(raw), t.key != key, let them = rows[t.key], them.walk != nil else { return "친구를 맺을 수 없는\n트레이너예요" }
            if isFriend(key, t.key) { return "이미 친구예요" }
            if friendAsks[t.key]?.contains(key) == true { return "이미 신청했어요" }
            if friendAsks[key]?.remove(t.key) != nil { befriend(key, t.key); news.append(.friendAdded(name: them.name)); mail[t.key, default: []].append(.friendAdded(name: name)); return nil }   // they'd asked me: friends at once
            friendAsks[t.key, default: []].insert(key); mail[t.key, default: []].append(.friendRequest(from: name))
        case .friendAccept(let raw):
            guard let f = trainerID(raw), friendAsks[key]?.remove(f.key) != nil else { return "그 신청은 이제\n없어요" }
            befriend(key, f.key); mail[f.key, default: []].append(.friendAdded(name: name))
        case .friendDecline(let raw):
            guard let f = trainerID(raw), friendAsks[key]?.remove(f.key) != nil else { return "그 신청은 이제\n없어요" }
        case .friendRemove(let raw):
            guard let f = trainerID(raw) else { return "친구가 아니에요" }
            if friendAsks[f.key]?.remove(key) != nil { return nil }                                       // my own request, taken back
            guard friends.remove(FakeCloud.pair(key, f.key)) != nil else { return "친구가 아니에요" }
        case .marketList(let give, let wish, let note):
            guard let r = w.ref(uid: give), r >= 0, let mon = w.mon(r) else { return "상자의 포켓몬만\n올릴 수 있어요" }
            guard !used(give) else { return "이미 올리거나\n제안한 포켓몬이에요" }
            guard listings.filter({ $0.open && $0.key == key }).count < 3 else { return "올린 글이\n너무 많아요 (3개)" }
            let n = note.map { String($0.trimmingCharacters(in: .whitespaces).prefix(20)) }.flatMap { $0.isEmpty ? nil : $0 }
            w.box.remove(at: r)                                                                            // 3.8: held out of the box while it's up
            listings.append((Listing(id: nextListing, from: name, mon: mon, wish: Array(wish.prefix(3)), at: at, bids: 0, mine: false, note: n), key, true)); nextListing += 1
        case .marketUnlist(let id):
            guard let i = listings.firstIndex(where: { $0.l.id == id && $0.open && $0.key == key }) else { return "그 글은 이제\n없어요" }
            listings[i].open = false; backToBox(listings[i].l.mon, &w)
            for b in bids.indices where bids[b].b.listing == id && bids[b].b.state == "open" {
                bids[b].b.state = "declined"; mail[bids[b].key, default: []].append(.tradeClosed(id: id, with: name, why: "상대가 글을 내렸어요")); giveClaim(bids[b].key, "returned", from: name, bids[b].b.mon)
            }
        case .marketBid(let id, let give):
            guard let i = listings.firstIndex(where: { $0.l.id == id && $0.open }) else { return "그 글은 이제\n없어요" }
            guard listings[i].key != key else { return "내 글에는\n제안할 수 없어요" }
            guard let r = w.ref(uid: give), r >= 0, let mon = w.mon(r) else { return "상자의 포켓몬만\n제안할 수 있어요" }
            guard !used(give) else { return "이미 올리거나\n제안한 포켓몬이에요" }
            guard !bids.contains(where: { $0.b.listing == id && $0.key == key && $0.b.state == "open" }) else { return "이 글에는 이미\n제안했어요" }
            guard bids.filter({ $0.key == key && $0.b.state == "open" }).count < 5 else { return "걸어 둔 제안이\n너무 많아요 (5개)" }
            w.box.remove(at: r)                                                                            // 3.8: held out of the box while it's offered
            bids.append((Bid(id: nextBid, listing: id, from: name, mon: mon, at: at, state: "open"), key, listings[i].key)); nextBid += 1
            mail[listings[i].key, default: []].append(.marketBid(listing: id, from: name, mon: mon))
        case .marketWithdraw(let id):
            guard let b = bids.firstIndex(where: { $0.b.id == id && $0.key == key && $0.b.state == "open" }) else { return "그 제안은 이제\n없어요" }
            bids[b].b.state = "cancelled"; backToBox(bids[b].b.mon, &w); mail[bids[b].poster, default: []].append(.tradeClosed(id: bids[b].b.listing, with: name, why: "제안을 거뒀어요"))
        case .marketAccept(let id):
            guard let b = bids.firstIndex(where: { $0.b.id == id && $0.poster == key && $0.b.state == "open" }), let i = listings.firstIndex(where: { $0.l.id == bids[b].b.listing && $0.open }) else { return "그 제안은 이제\n없어요" }
            let post = listings[i], bid = bids[b]
            listings[i].open = false; bids[b].b.state = "done"
            for k in bids.indices where bids[k].b.listing == post.l.id && bids[k].b.state == "open" {
                bids[k].b.state = "declined"; mail[bids[k].key, default: []].append(.tradeClosed(id: post.l.id, with: name, why: "다른 제안이 선택됐어요")); giveClaim(bids[k].key, "returned", from: name, bids[k].b.mon)
            }
            var got = bid.b.mon; got.uid = nextUID; nextUID += 1; got.ot = got.ot ?? bid.b.from; _ = w.keep(got)          // 3.8: the poster's comes now (its act) …
            if let e = Walk.tradeEvolution(of: got, giverBag: got.item.map { [$0] } ?? []), let ref = w.ref(uid: got.uid!) {   // (a trade evolution: by the held item only, if it needs one)
                w.evolve(Evo(from: e.from, to: e.to, way: e.way, level: e.level, item: nil, female: e.female, time: e.time, place: e.place, party: e.party), ref: ref, shed: false)
                if var m = w.mon(ref), e.item != nil { m.item = nil; w.setMon(ref, m) }
                news.append(.evolve(uid: got.uid!, from: e.from, to: e.to, shed: nil))
            }
            news.append(.traded(id: post.l.id, with: bid.b.from, gave: post.l.mon, got: w.mon(w.ref(uid: got.uid!) ?? 0) ?? got))
            giveClaim(bid.key, "traded", from: name, post.l.mon)                                          // … the bidder's waits in its 받기 함
            mail[bid.key, default: []].append(.traded(id: post.l.id, with: name, gave: bid.b.mon, got: post.l.mon))
        case .claim(let id):
            guard let i = claimBox[key]?.firstIndex(where: { $0.id == id }), let k = claimBox[key]?.remove(at: i) else { return "이미 받았어요" }
            var m = k.mon; let from = m.level
            if k.kind == "traded" { m.uid = nextUID; nextUID += 1; m.ot = m.ot ?? k.from }                 // (its own, back: the same uid)
            if k.kind == "visit", let s = visitSteps.removeValue(forKey: k.id), s > 0 { _ = m.gainBattleExp(s) }
            _ = w.keep(m)
            if m.level > from, let ref = w.ref(uid: m.uid!) { w.queueMoves(ref, from: from); news.append(.level(uid: m.uid!, level: m.level)) }
            if k.kind == "traded", let e = Walk.tradeEvolution(of: m, giverBag: m.item.map { [$0] } ?? []), let ref = w.ref(uid: m.uid!) {
                w.evolve(Evo(from: e.from, to: e.to, way: e.way, level: e.level, item: nil, female: e.female, time: e.time, place: e.place, party: e.party), ref: ref, shed: false)
                news.append(.evolve(uid: m.uid!, from: e.from, to: e.to, shed: nil))
            }
        default: break
        }
        return nil
    }
    /// POST /v2/market: every open post (newest first), the offers on mine, mine on others'.
    func marketBoard(_ d: Data) -> (Int, Data) {
        guard let q = try? JSONDecoder().decode(MarketReq.self, from: d), let id = trainerID(q.id), let r = rows[id.key] else { return err(404, ["error": "no_trainer"]) }
        guard q.session == r.session else { return err(409, ["error": "conflict", "reason": "replaced"]) }
        let k = id.key, open = bids.filter { $0.b.state == "open" }
        if let s = q.seen { for b in open where b.b.listing == s && b.poster == k { seenBids.insert(b.b.id) } }   // 3.8: that post opened — its offers seen
        let ls = listings.filter(\.open).reversed().map { p -> Listing in var l = p.l; l.mine = p.key == k; l.bids = open.filter { $0.b.listing == p.l.id }.count; return l }
        let reply = MarketReply(listings: Array(ls), offers: open.filter { $0.poster == k }.map(\.b), myBids: open.filter { $0.key == k }.map(\.b),
                                claims: claimBox[k] ?? [], unseen: open.filter { $0.poster == k && !seenBids.contains($0.b.id) }.count)
        return (200, (try? JSONEncoder().encode(reply)) ?? Data())
    }
    /// 12 §4: a raid fight's end counted (its damage up to what's left; the team's clear told to every fighter — this one in its reply) and a ball.
    func raided(_ a: Act, _ key: String, _ name: String, _ w: inout Walk, _ o: inout Outcome) {
        if let d0 = o.end?.dealt, raidTotal > 0 {
            let d = min(d0, raidLeft); o.end?.dealt = d
            raidLeft -= d; raidDealt[key, default: 0] += d; raidFights[key, default: 0] += 1
            raidRecent.insert(RaidHit(name: name, dex: w.party().first?.mon.dex ?? w.companion.dex, dealt: d, at: Int((now ?? Date()).timeIntervalSince1970)), at: 0); raidRecent = Array(raidRecent.prefix(10))
            if raidLeft == 0, d > 0 { for f in raidDealt.keys { if f == key { o.news.append(.raidCleared(dex: raidBoss.dex)) } else { mail[f, default: []].append(.raidCleared(dex: raidBoss.dex)) } } }
        }
        guard case .raidBall = a, o.cannot == nil else { return }
        guard raidTotal > 0, raidLeft == 0 else { o.cannot = "아직 보스가\n쓰러지지 않았어요"; return }
        guard let mine = raidDealt[key] else { o.cannot = "이번 주에 싸워야\n잡을 수 있어요"; return }
        guard !raidCaught.contains(key) else { o.cannot = "이미 잡았어요"; return }
        let top = raidDealt.values.max() ?? 0, fair = Double(mine) * Double(max(1, raidDealt.count)) >= Double(raidTotal)
        let left = raidBalls[key] ?? (3 + (fair ? 1 : 0) + (mine == top ? 1 : 0))
        guard left > 0 else { o.cannot = "볼이 남아 있지\n않아요"; return }
        let reward = !raidRewarded.contains(key)
        if reward { raidRewarded.insert(key); w.bp = (w.bp ?? 0) + 25; for _ in 0..<5 { _ = w.keep("이상한사탕") }; _ = w.keep("은색병뚜껑") }
        let caught = raidOdds.isEmpty ? Double(rng.next() % 100) < 30 : raidOdds.removeFirst()
        var mon: Mon? = nil
        if caught { var m = Mon.wild(raidBoss.dex, level: 70, &rng); m.uid = nextUID; nextUID += 1; _ = w.keep(m); raidCaught.insert(key); mon = m }
        raidBalls[key] = left - 1
        o.raidThrow = RaidThrow(caught: caught, shakes: caught ? 3 : Int(rng.next() % 3), balls: left - 1, mon: mon, reward: reward); o.changed = true
    }
    /// POST /v2/raid: the week's boss, the team's HP, who dealt what, the last hits, mine.
    func raidLobby(_ d: Data) -> (Int, Data) {
        guard let q = try? JSONDecoder().decode(TeamReq.self, from: d), let id = trainerID(q.id), let r = rows[id.key] else { return err(404, ["error": "no_trainer"]) }
        guard q.session == r.session else { return err(409, ["error": "conflict", "reason": "replaced"]) }
        if raidTotal == 0 { raidOpen(1_000_000) }
        let k = id.key, mine = raidDealt[k], caught = raidCaught.contains(k)
        let reply = RaidReply(week: "2026-W40", boss: raidBoss, next: 382, hpTotal: raidTotal, hpLeft: raidLeft, barHP: Fighter(raidBoss).maxHP,
                              ends: Int((now ?? Date()).timeIntervalSince1970) + 3 * 86400 + 5 * 3600,
                              fighters: raidDealt.map { RaidFighter(name: rows[$0.key]?.name ?? $0.key, dealt: $0.value) }.sorted { $0.dealt != $1.dealt ? $0.dealt > $1.dealt : $0.name < $1.name },
                              recent: raidRecent, mine: RaidMine(dealt: mine ?? 0, fights: raidFights[k] ?? 0, balls: raidBalls[k], caught: caught, canCatch: raidLeft == 0 && mine != nil && !caught))
        return (200, (try? JSONEncoder().encode(reply)) ?? Data())
    }
    /// POST /v2/trades: the trainer's open offers, to it and its own.
    func trades(_ d: Data) -> (Int, Data) {
        guard let q = try? JSONDecoder().decode(TeamReq.self, from: d), let id = trainerID(q.id), let r = rows[id.key] else { return err(404, ["error": "no_trainer"]) }
        guard q.session == r.session else { return err(409, ["error": "conflict", "reason": "replaced"]) }
        let open = offers.filter { $0.o.state == "open" }
        return (200, (try? JSONEncoder().encode(TradesReply(incoming: open.filter { $0.to == id.key }.map(\.o), outgoing: open.filter { $0.from == id.key }.map(\.o)))) ?? Data())
    }
    /// POST /v2/box: a teammate's box (404: no such trainer, or none on 3.0).
    func box(_ d: Data) -> (Int, Data) {
        guard let q = try? JSONDecoder().decode(BoxReq.self, from: d), let id = trainerID(q.id), let r = rows[id.key] else { return err(404, ["error": "no_trainer"]) }
        guard q.session == r.session else { return err(409, ["error": "conflict", "reason": "replaced"]) }
        guard let of = trainerID(q.of), let t = rows[of.key], let w = t.walk.flatMap(Cloud.walk) else { return err(404, ["error": "no_trainer"]) }
        return (200, (try? JSONEncoder().encode(BoxReply(name: t.name, box: w.box))) ?? Data())
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
            let carry = r.play.tower && r.play.battle == nil                                                       // a tower run between fights goes on (a fight on: it ends)
            r.session = session; r.device = device; r.at = clock; r.play = Play(); r.play.tower = carry; r.seq = 0   // a new session: what was going on is over (11 §0)
            if var w = r.walk.flatMap(Cloud.walk) { for ref in [-1] + w.caught.indices.map({ -2 - $0 }) + Array(w.box.indices) { _ = w.id(ref) }; r.walk = FakeCloud.text(w) }   // every Pokémon a uid (3.0's first login)
            rows[id.key] = r
            var b: [String: Any] = ["exists": true, "name": r.name, "rev": r.rev, "walk": (r.walk as Any?) ?? NSNull(), "session": session, "last_device": was.device, "updated_at": was.at, "tower": carry]
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
    var banners: [String] = []
    func notify(_ title: String, _ body: String) { banners.append(title) }
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
              "3.0 cloud: no ID → the box (one letter isn't one) → 새 트레이너 → its PIN → made; the first act brings the server's save: the starter, uid 1,000,000"
))
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
    v.screen = menuFor("포켓 레이더"); let tiles = v.paneContent(Date()).menu?.rows ?? []; v.press(1)
    let refused = says(v) == Walker.offlineLines && v.waiting == nil, row = v.cloudMenuTitle
    v.screen = menuFor("도감"); let inRecord = v.paneContent(Date()).menu?.rows.filter(\.off) ?? []; v.screen = menuFor("배틀 타워"); let inBattle = v.paneContent(Date()).menu?.rows.filter(\.off).count
    let dimmed = tiles.filter(\.off).map(\.name) == ["포켓 레이더", "배틀", "친구", "상점", "우편함"] && tiles.first { $0.off }?.note == "연결되면 할 수 있어요" && inRecord.isEmpty && inBattle == 3
    vs.down = false; v.tick(Date() + 121); drain(v)
    chk(refused && dimmed && row.hasSuffix("연결 안 됨 · 올릴 걸음 30") && served(v)?.total == 37 && v.cloud!.ahead == 0,
              "3.0 offline: what needs the server dimmed on the menu (연결되면 할 수 있어요; 3.9: a group only when all of it does — 기록 not, 배틀 and its three), and says so at once; steps pile up (the right-click: 연결 안 됨 · 올릴 걸음 n); back, they go up", row)
    let bs = FakeCloud(); bs.add("zz000099", Walk())
    let bo = Cloud(link: bs, dir: tmp.appendingPathComponent("bo", isDirectory: true)); bo.seat.trainerID = "zz000099"; bo.login(force: true); var bt = Date(); bo.tick(bt); bo.tick(bt)
    var waits2: [TimeInterval] = []; bo.addSteps(5)
    for i in 0..<6 { bs.html = [403, 502][safe: i]; bs.down = i >= 2; bo.tick(bt); bo.tick(bt); waits2.append(bo.backoff); bt = bo.retryAt }
    bs.html = nil; bs.down = false; bo.tick(bt); bo.tick(bt)
    chk(waits2 == [120, 240, 480, 960, 1800, 1800] && bo.backoff == 0 && bo.ahead == 0, "3.0 offline (an HTML 403 / 502, then no answer): again in 2, 4, 8, 16, 30, 30 minutes; back, the steps go up", "\(waits2) \(bo.phase) \(bo.ahead)")

    // the server's "not now" (out.cannot): its lines on the LCD, back where it was; nothing changed but the steps
    serve(v) { w in var e = [0, 0, 0, 0, 0, 0]; e[0] = Walk.vitaminCap; w.companion.evs = e; w.bag = ["맥스업"] }
    let vRev = vs.rows[vk]?.rev; v.screen = .items(0); v.useItem("맥스업", back: .items(0)); drain(v)   // (3.6's page wouldn't offer it: the server's no, asked anyway)
    chk(says(v) == ["먹어도 효과가", "없을 것 같다"] && v.state.count("맥스업") == 1 && vs.rows[vk]?.rev == vRev, "3.0 act: the server's no (맥스업 at 255: 먹어도 효과가 / 없을 것 같다) on the LCD, nothing used", "\(says(v)) \(v.screen) \(v.state.inventory) \(String(describing: vs.acts.last))")

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
    rv.openFeature("포켓 레이더"); drain(rv)
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
    rs.lose = true; rv.openFeature("포켓 레이더"); drain(rv, max: 3)
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
