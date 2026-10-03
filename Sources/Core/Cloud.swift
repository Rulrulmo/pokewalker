import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking                                                                       // URLSession on Windows (swift-corelibs)
#endif
// The save server's client (docs/plans/08 §4, 08b §4 / §10): login, create, save and legacy, one request at a time. Replies land in a locked inbox
// from URLSession's queue; tick (the walker's 10 Hz, on the main thread) takes them. No Task / MainActor hops: they may not run on Windows.
// Off unless the `cloud` setting is on (2.0 flips it), and always with persist == false: then nothing goes out and the app is 1.x.
// The walker's hooks, the launch and the UI: P2 step 2b.

/// The wire: POST json to path; done(status, body) on any thread. status 0 = no answer (network error, timeout).
protocol CloudLink: Sendable { func post(_ path: String, _ json: Data, done: @escaping @Sendable (Int, Data) -> Void) }

/// The real one: https://pokewalker.rulrulmo.work (08b's api.<domain>), 15 s to answer.
struct HTTPLink: CloudLink {
    static let base = URL(string: "https://pokewalker.rulrulmo.work")!
    static let appKey = "6b0b5cdf9410adc1ed7d10ae86dd2013"                                       // not a secret (08 §2-1): it keeps the internet's scanners from making trainers
    func post(_ path: String, _ json: Data, done: @escaping @Sendable (Int, Data) -> Void) {
        var r = URLRequest(url: HTTPLink.base.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        r.httpMethod = "POST"; r.httpBody = json
        for (k, v) in ["Content-Type": "application/json", "X-App-Key": HTTPLink.appKey, "User-Agent": "PokeWalker/\(appVersion) (\(appPlatform))"] { r.setValue(v, forHTTPHeaderField: k) }
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
    enum Phase: Equatable { case off, needsID, login, busy(device: String, at: Int), new(String), on, replaced, oldApp }
    /// A request out, kept to read its reply by.
    enum Ask: Sendable, Equatable { case login(force: Bool, resume: Bool), create, save(total: Int, hash: String), legacy }
    /// This PC's, in cloud.json next to the save: the ID as typed, the server's session, a random id made once, whether the 1.x save went up.
    struct Seat: Codable, Equatable { var trainerID: String? = nil, session: String? = nil, device: String? = nil, legacyUploaded: Bool? = nil }
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
    static func app(persist: Bool) -> Cloud { Cloud(link: HTTPLink(), dir: Store.dir, on: persist && settings.bool("cloud", false)) }

    // MARK: what the walker and its UI call
    /// Launch: log in with this PC's ID, or ask for one.
    func start() { guard phase != .off else { return }; if seat.trainerID == nil { phase = .needsID } else { ask(.login(force: false, resume: false)) } }
    /// The ID box's answer (nil = this PC's ID again), or 가져올까요? answered yes (force). false = not an ID (2-12 of 가-힣 A-Z a-z 0-9 _).
    @discardableResult func login(_ raw: String? = nil, force: Bool = false) -> Bool {
        guard phase != .off else { return false }
        if let raw {
            guard let id = trainerID(raw) else { return false }
            if id.key != seat.trainerID.flatMap(trainerID)?.key { seat.session = nil }
            seat.trainerID = id.name
        }
        guard seat.trainerID != nil else { return false }
        ask(.login(force: force, resume: false)); return true
    }
    /// 여기서 계속, after replaced: the session back, and the server's save as it is.
    func resume() { if phase == .replaced { ask(.login(force: true, resume: true)) } }
    /// 새 트레이너로 시작, after new: the server makes the ID and this PC starts a new walker (08 §5: new IDs start new).
    func create() { if case .new = phase { ask(.create) } }
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
    static func locks(_ p: Phase) -> Bool { p == .needsID || p == .replaced || p == .oldApp }

    /// The walker's tick: replies taken; the server's save taken once home allows (canTake); then what's due goes, if nothing is out.
    /// Non-nil: the server's save was taken (true = the companion levelled up walking ours on top).
    @discardableResult func tick(_ w: inout Walk, _ now: Date, canTake: Bool = true) -> Bool? {
        guard phase != .off else { return nil }
        take(&w, now)
        var took: Bool? = nil
        if canTake, let h = head { head = nil; took = apply(h, &w, now) }
        guard inFlight == nil, now >= retryAt else { return took }
        if let a = asking { asking = nil; send(a) }
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
        case .login(let force, _): post(a, "v1/login", ["id": id, "device": device, "device_name": deviceName, "app": appVersion, "force": force])
        case .create: post(a, "v1/create", ["id": id, "device": device, "device_name": deviceName])
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
            case (_, 426): phase = .oldApp; NSLog("pokewalker: cloud: the server wants app %@ (this is %@)", j["need"] as? String ?? "?", appVersion)
            case (.login(_, let resume), 200): loggedIn(j, resume: resume, &w, now)
            case (.create, 200) where j["session"] is String: seat.session = j["session"] as? String; phase = .on; head = (Walk(), 0, nil, .fresh)
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
                switch a { case .login, .create: asking = a; case .legacy: legacy = nil; case .save: break }
            }
        }
    }
    /// The launch rules (08b §10 ①–④) on a login's answer.
    private func loggedIn(_ j: [String: Any], resume: Bool, _ w: inout Walk, _ now: Date) {
        if j["exists"] as? Bool == false { phase = .new(seat.trainerID ?? ""); return }
        if j["busy"] as? Bool == true { phase = .busy(device: j["last_device"] as? String ?? "", at: j["updated_at"] as? Int ?? 0); return }
        guard let session = j["session"] as? String, let rev = j["rev"] as? Int else { asking = .login(force: resume, resume: resume); retryAt = now.addingTimeInterval(Cloud.period); return }
        seat.session = session; phase = .on; nextSave = now; lastSaved = now                   // (in step with the server from here, but for what's changed)
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
    func lockPress() { switch cloud?.phase { case .needsID?: askID(); case .replaced?: resumeCloud(); default: break } }
    /// The ID box until an ID or 취소 (08 §2): log in with it, or (change, ID 바꾸기) switch to it. A non-ID asks again with the rule. false = 취소.
    @discardableResult func askID(change: Bool = false) -> Bool {
        guard let h = host, let c = cloud, !cloudAsking else { return false }
        cloudAsking = true; defer { cloudAsking = false }
        var note = "2–12자, 한글·영문·숫자·_ (대소문자는 같은 ID)"
        while let raw = h.askText(title: change ? "ID 바꾸기" : "트레이너 ID를 입력해 주세요", message: note) {
            if trainerID(raw) != nil { if change { switchID(raw) } else { c.login(raw) }; return true }
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
        default: nil
        }
        if let lines { towerRun = false; growthThen = nil; heldSteps = 0; screen = .say(lines, next: .home, since: .distantFuture) }   // (a fight going on is dropped)
        else if cloudShown.map(Cloud.locks) == true { screen = .home }
        refreshPane(Date(), force: true); host?.redraw(.all)
    }
    /// The pane while the server holds the game.
    var loginModel: LoginModel? {
        switch cloud?.phase {
        case .needsID?: LoginModel(title: "로그인이 필요해요", lines: ["트레이너 ID로 서버의 세이브를 불러와요.", "2–12자, 한글·영문·숫자·_"], button: "ID 입력")
        case .replaced?: LoginModel(title: "다른 PC에서 접속했어요", lines: ["그 PC가 하는 동안 여기선 걸음을 세지 않아요.", "여기서 하려면 아래를 눌러요."], button: "여기서 계속")
        case .oldApp?: LoginModel(title: "새 버전이 필요해요", lines: ["서버가 이 버전(\(appVersion))을 받지 않아요.", "pokewalker.rulrulmo.work에서", "새 버전을 받아 주세요."], button: nil)
        default: nil
        }
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
        default: "서버에 연결하는 중"
        }
        return "트레이너: \(c.seat.trainerID ?? "-") · " + when
    }
    /// Woken from sleep: what changed goes up (a stale reply brings the server's).
    func woke() { cloud?.soon(Date()) }
    /// ID 바꾸기 (step 3's box): what isn't up goes up first; another trainer's rev, total and hash don't carry over. false = not an ID.
    @discardableResult func switchID(_ raw: String) -> Bool {
        guard let c = cloud, let id = trainerID(raw) else { return false }
        if c.seat.trainerID.flatMap(trainerID)?.key != id.key { c.flush(&state); (state.cloudRev, state.cloudTotal, state.sentHash) = (nil, nil, nil) }
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
        if c.phase != cloudShown { showCloud(c.phase); cloudShown = c.phase }
        seen = state
        cloudQuestion(c)
    }
    /// 새 트레이너? / 가져올까요? — once per answer the server gave (step 3 brings the ID box and the buttons). A tick may come during the question: not twice.
    func cloudQuestion(_ c: Cloud) {
        if c.phase == .needsID, !idBoxShown, host != nil, !cloudAsking { idBoxShown = true; askID(); return }   // by itself once a launch; then ● / the pane's button
        guard let h = host, !cloudAsking, c.phase != cloudAsked else { return }
        let q: (title: String, body: String, ok: String)? = switch c.phase {
        case .new(let id): ("새 트레이너", josa("'\(id)'", "은", "는") + " 서버에 없는 ID예요. 이 ID로 새로 시작할까요?", "새로 시작")
        case .busy(let device, let at): ("다른 PC에서 하고 있었어요", "\(device)에서 \(max(0, Int(Date().timeIntervalSince1970) - at) / 60)분 전까지 하고 있었어요. 여기로 가져올까요?", "가져오기")
        default: nil
        }
        guard let q else { return }
        cloudAsking = true; cloudAsked = c.phase
        let yes = h.confirm(q.title, q.body, ok: q.ok)
        cloudAsking = false
        guard yes else { c.decline(); return }
        if case .new = c.phase { c.create() } else if case .busy = c.phase { c.login(force: true) }
    }
    /// The title row's note while the server isn't plain sailing.
    var cloudNote: String? {
        switch cloud?.phase {
        case .needsID?: "로그인이 필요해요"
        case .login?, .new?, .busy?: "서버에 연결하는 중"
        case .replaced?: "다른 PC에서 접속했어요"
        case .oldApp?: "새 버전이 필요해요"
        default: nil
        }
    }
}

// MARK: - the self-test's: a save server in a few lines (08b §4's 13 rows, as far as the app sees them)
/// One table of trainers. down = no answer; html = that status with a page (Cloudflare's); lose = the next reply lost after the server acted;
/// hold = replies wait for release(); old = 426 with that need.
final class FakeCloud: CloudLink, @unchecked Sendable {
    struct Row { var name: String; var rev = 0; var walk: String? = nil; var session = ""; var writer: String? = nil; var device = ""; var at = 0 }
    var rows: [String: Row] = [:], paths: [String] = [], held: [() -> Void] = [], clock = 10_000
    var down = false, html: Int? = nil, lose = false, hold = false, old: String? = nil
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
        guard var r = rows[id.key] else {
            if path == "v1/create" { rows[id.key] = Row(name: id.name, session: session, device: device, at: clock); return (200, ["rev": 0, "session": session]) }
            return path == "v1/login" ? (200, ["exists": false]) : (404, ["error": "no_trainer"])
        }
        switch path {
        case "v1/create": return (409, ["error": "exists"])
        case "v1/login":
            let was = r
            if j["force"] as? Bool != true, r.device != device, clock - r.at < 300 { return (200, ["exists": true, "busy": true, "name": r.name, "last_device": r.device, "updated_at": r.at]) }
            r.session = session; r.device = device; rows[id.key] = r
            return (200, ["exists": true, "name": r.name, "rev": r.rev, "walk": (r.walk as Any?) ?? NSNull(), "session": session, "last_device": was.device, "updated_at": was.at])
        case "v1/save":
            let base = j["base"] as? Int ?? -1, mine = j["session"] as? String
            guard mine == r.session else { return (409, ["error": "conflict", "reason": "replaced"]) }                         // row 9
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
    a.create(); let fresh = run(a, &w, t0)
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
    o.login("zz000002"); _ = run(o, &wo, t); o.create(); _ = run(o, &wo, t)
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
    var mt = ticks(mw, t + 5000, 5)
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
    let boxed = mw.state.box.count; mh.keys += 10; mw.tick(mt); mt += 0.5
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
    uh.texts = ["민", " zz000005 "]; uw.pageTap(5950); ut = ticks(uw, ut, 3)                        // the pane's button: a one-letter ID asks again with the rule, then a good one
    let reasked = uh.boxes.count == 3 && uh.boxes[2].contains("쓸 수 없어요") && uh.asked.last == "새 트레이너"
    c.append((locked0 && once && reasked && uc.phase == .on && uc.seat.trainerID == "zz000005" && { if case .home = uw.screen { return true }; return false }() && uw.pane.login == nil,
              "cloud UI: no ID → the box once by itself; 취소 → 로그인이 필요해요 on the LCD, ID 입력 on the pane, no steps, no keys; a non-ID asks again with the rule; then in"))
    let plainWalker = Walker(state: Walk()), rows = uw.menu().map(\.title), plain = plainWalker.menu().map(\.title)
    c.append((rows.contains { $0.hasPrefix("트레이너: zz000005 · ") } && rows.contains("지금 저장") && rows.contains("ID 바꾸기…") && !plain.contains { $0.hasPrefix("트레이너:") || $0 == "ID 바꾸기…" }
              && uw.cardTitle == "zz000005" && plainWalker.cardTitle == "트레이너 카드",
              "cloud UI: the right-click menu has 트레이너: ID · n분 전 저장, 지금 저장, ID 바꾸기… and the trainer card heads with the ID (only with the cloud)"))
    uw.screen = .home; uw.state.walk(40, at: ut); ut = ticks(uw, ut, 4)
    let upBefore = srv.rows["zz000005"]?.walk == text(uw.state.shared)
    uw.state.watts += 7; n = sent(); uh.texts = ["zz000006"]; uw.askID(change: true)            // ID 바꾸기: ours goes up first, then the other trainer
    let flushed = sent() == n + 1 && srv.rows["zz000005"]?.walk == text(uw.state.shared), cleared = uw.state.cloudRev == nil && uw.state.cloudTotal == nil && uw.state.sentHash == nil
    uh.answer = false; ut = ticks(uw, ut, 3)                                                       // 새 트레이너? no → back to the box (by itself only once: not again)
    c.append((upBefore && flushed && cleared && uc.phase == .needsID && uc.seat.trainerID == nil && uh.boxes.count == 4,
              "cloud UI: ID 바꾸기 sends what isn't up, then forgets the old trainer's rev / total / hash; 새 트레이너? no → 로그인이 필요해요"))
    uh.answer = true; uh.texts = ["zz000005"]; uw.press(1); ut = ticks(uw, ut, 3)                    // ● = ID 입력: back to the first, the server's save
    c.append((uc.phase == .on && uc.seat.trainerID == "zz000005" && uw.state.cloudRev == srv.rows["zz000005"]?.rev && uw.state.watts == (Cloud.walk(srv.rows["zz000005"]?.walk ?? "")?.watts ?? -1),
              "cloud UI: ● on 로그인이 필요해요 opens the box; the first trainer again: its save from the server"))
    srv.old = "9.0"; uw.state.watts += 1; uw.cloud?.saveNow(); ut = ticks(uw, ut, 2); srv.old = nil
    let oldSays = { if case .say(let l, _, _) = uw.screen { return l.joined().contains("rulrulmo.work") }; return false }()
    c.append((uc.phase == .oldApp && uw.frozen && oldSays && uw.pane.login?.title == "새 버전이 필요해요" && uw.pane.login?.button == nil && uw.title().meta == "새 버전이 필요해요",
              "cloud UI: 426 → 새 버전이 필요해요 on the LCD (the download page's address) and the pane; the game is held"))
    return c
}
