import Foundation
import Hummingbird

// HTTP (08b §4): POST /v1/{login,create,save,legacy} with X-App-Key, GET /v1/ping; 3.0's POST /v2/act (plan 11). Bound to 127.0.0.1 only: cloudflared is the way in.

func unixNow() -> Int { Int(Date().timeIntervalSince1970) }

func respond(_ r: Reply) -> Response {
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    return Response(status: .init(code: r.status), headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: r.body)))
}

/// A POST route: the app key, the body (4 MiB at most), the request's JSON, then `handle`; a reply's note is logged with the trainer's key.
func post<R: Decodable & Sendable>(_ router: Router<BasicRequestContext>, _ path: String, appKey: String, id: @escaping @Sendable (R) -> String,
                                   _ handle: @escaping @Sendable (R) async -> Reply) {
    router.post(RouterPath(path)) { request, context -> Response in
        guard hasAppKey(request, appKey) else { return respond(.error(401, "app_key")) }
        var request = request
        let body: ByteBuffer
        do { body = try await request.collectBody(upTo: bodyLimit) }
        catch let e as any HTTPResponseError where e.status == .contentTooLarge { return respond(.error(413, "too_big")) }   // NIOTooManyBytesError or HTTPError, by version
        catch { return respond(.error(400, "bad_request")) }
        guard let r = try? JSONDecoder().decode(R.self, from: Data(body.readableBytesView)) else { return respond(.error(400, "bad_request")) }
        let reply = await handle(r)
        if let note = reply.note { context.logger.info("\(path) \(trainerID(id(r))?.key ?? "-"): \(reply.status) \(note)") }
        return respond(reply)
    }
}

func serve(db: SaveDB, appKey: String, port: Int, site: DownloadSite?, release: URL) async throws {
    let router = Router()
    router.addMiddleware { LogRequestsMiddleware(.info) }
    if let site { addDownloadPage(router, site) }                                         // GET / (ServerPage.swift); none without DOWNLOAD_PASSWORD
    addUpdates(router, ReleaseFiles(dir: release), appKey: appKey)                        // the app's updates (ServerUpdate.swift)
    router.get("/v1/ping") { _, _ in respond(Reply(200, ["ok": .b(true)])) }
    post(router, "/v1/login", appKey: appKey, id: { (r: LoginReq) in r.id }) { r in await db.login(r, now: unixNow()) }
    post(router, "/v1/create", appKey: appKey, id: { (r: CreateReq) in r.id }) { r in await db.create(r, now: unixNow()) }
    post(router, "/v1/save", appKey: appKey, id: { (r: SaveReq) in r.id }) { r in
        if let early = SaveDB.precheck(r) { return early }
        return await db.save(r, now: unixNow())
    }
    post(router, "/v1/legacy", appKey: appKey, id: { (r: LegacyReq) in r.id }) { r in await db.legacy(r, now: unixNow()) }
    post(router, "/v1/pin", appKey: appKey, id: { (r: PinReq) in r.id }) { r in await db.setPIN(r, now: unixNow()) }
    post(router, "/v1/radar", appKey: appKey, id: { (r: RadarReq) in r.id }) { r in await db.radar(r, now: unixNow()) }           // 10 §4: the server's Pokémon
    post(router, "/v1/radar/result", appKey: appKey, id: { (r: ResultReq) in r.id }) { r in await db.radarResult(r, now: unixNow()) }
    post(router, "/v1/hatch", appKey: appKey, id: { (r: HatchReq) in r.id }) { r in await db.hatch(r, now: unixNow()) }
    post(router, "/v1/buy", appKey: appKey, id: { (r: BuyReq) in r.id }) { r in await db.buy(r, now: unixNow()) }
    post(router, "/v1/evolve", appKey: appKey, id: { (r: EvolveReq) in r.id }) { r in await db.evolve(r, now: unixNow()) }
    post(router, "/v2/act", appKey: appKey, id: { (r: ActReq) in r.id }) { r in await db.act(r, now: Date()) }   // plan 11 (3.0): ServerPlay.swift
    post(router, "/v2/team", appKey: appKey, id: { (r: TeamReq) in r.id }) { r in await db.team(r, now: Date()) }   // plan 12 M1: ServerTeam.swift

    let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: port), serverName: "pokeserver"))
    let log = app.logger
    let pruning = Task {                                                                   // at start, then hourly
        while !Task.isCancelled {
            do {
                let n = try await db.prune(now: unixNow())
                if n > 0 { log.info("prune: \(n) history rows") }
            } catch { log.error("prune: \(error)") }
            try? await Task.sleep(for: .seconds(3600))
        }
    }
    defer { pruning.cancel() }
    try await app.runService()                                                             // SIGTERM / SIGINT: a graceful stop
}
