import Foundation
import Hummingbird

// The team's download page (GET /): what the game is, the latest Mac and Windows builds and the patch notes, behind one team password (DOWNLOAD_PASSWORD).
// What it shows is RELEASE_DIR as server/publish.sh leaves it: release.json, patch-notes.txt, the two zips and shots/ (the windows run's renders of
// the release's commit, as WebP; none, and the page goes without). /v1 (the app's API) is untouched.

struct Release: Codable, Sendable {
    struct Build: Codable, Sendable { let file: String; let size: Int; let sha256: String }
    let version: String, build: String, commit: String, published: Int
    let mac: Build?, windows: Build?
    var windowsSetup: Build? = nil                                     // the Windows installer (when the release has one: its button, the zip kept for updates)
    func build(_ kind: String) -> Build? { kind == "mac" ? mac : kind == "windows" ? windows : kind == "windows-setup" ? windowsSetup : nil }
}

struct DownloadSite: Sendable {
    let dir: URL, password: String
    /// The cookie that says the password was given: an HMAC of the password, so a new password logs everyone out and nothing is kept server-side.
    var token: String { hex(hmacSHA256(key: Array(password.utf8), Array("pokewalker download v1".utf8))) }
    var release: Release? { (try? Data(contentsOf: dir.appendingPathComponent("release.json"))).flatMap { try? JSONDecoder().decode(Release.self, from: $0) } }
    var notes: String? { try? String(contentsOf: dir.appendingPathComponent("patch-notes.txt"), encoding: .utf8) }
    func authorized(_ r: Request) -> Bool { cookie(r, "pw_dl") == token }
    /// A screenshot's file: lower-case letters, digits, _ and . only (no path), and there.
    func shotFile(_ name: String) -> URL? {
        guard name.hasSuffix(".webp"), !name.contains(".."), name.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_" || $0 == ".") }) else { return nil }
        let u = dir.appendingPathComponent("shots", isDirectory: true).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

func cookie(_ r: Request, _ name: String) -> String? {
    for field in r.headers where field.name.canonicalName == "cookie" {
        for part in field.value.split(separator: ";") {
            let kv = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == name { return kv[1] }
        }
    }
    return nil
}
/// application/x-www-form-urlencoded → its fields.
func formFields(_ body: String) -> [String: String] {
    var out: [String: String] = [:]
    for pair in body.split(separator: "&") {
        let kv = pair.split(separator: "=", maxSplits: 1).map { $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "" }
        if let k = kv.first { out[k] = kv.count > 1 ? kv[1] : "" }
    }
    return out
}
func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}
func html(_ body: String, status: HTTPResponse.Status = .ok, headers more: HTTPFields = [:]) -> Response {
    var headers = more
    headers[.contentType] = "text/html; charset=utf-8"
    headers[.cacheControl] = "no-store"
    return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(string: body)))
}

func addDownloadPage(_ router: Router<BasicRequestContext>, _ site: DownloadSite) {
    router.get("/") { request, _ in site.authorized(request) ? html(site.page()) : html(loginPage(wrong: false)) }
    router.post("/login") { request, _ -> Response in
        var request = request
        let body = (try? await request.collectBody(upTo: 4096)).map { String(buffer: $0) } ?? ""
        guard formFields(body)["password"] == site.password else {
            try? await Task.sleep(for: .seconds(1))                                               // a guess a second per connection
            return html(loginPage(wrong: true), status: .unauthorized)
        }
        var headers = HTTPFields()
        headers[.location] = "/"
        headers[.setCookie] = "pw_dl=\(site.token); Path=/; Max-Age=2592000; HttpOnly; Secure; SameSite=Lax"   // 30 days
        return Response(status: .seeOther, headers: headers)
    }
    router.get("/download/:kind") { request, context -> Response in
        guard site.authorized(request) else { var h = HTTPFields(); h[.location] = "/"; return Response(status: .seeOther, headers: h) }
        let kind = context.parameters.get("kind") ?? ""
        guard let r = site.release, let b = r.build(kind) else { return html(notFoundPage(), status: .notFound) }
        let setup = kind == "windows-setup"
        var headers = HTTPFields()
        headers[.contentType] = setup ? "application/vnd.microsoft.portable-executable" : "application/zip"
        headers[.contentLength] = String(b.size)
        headers[.contentDisposition] = setup ? "attachment; filename=\"PokeWalker-\(r.version)-setup.exe\"" : "attachment; filename=\"PokeWalker-\(r.version)-\(kind).zip\""
        headers[.cacheControl] = "no-store"
        context.logger.info("download \(kind) \(r.version)")
        return Response(status: .ok, headers: headers, body: try await FileIO().loadFile(path: site.dir.appendingPathComponent(b.file).path, context: context))
    }
    router.get("/shot/:name") { request, context -> Response in
        guard site.authorized(request), let u = site.shotFile(context.parameters.get("name") ?? "") else { return html(notFoundPage(), status: .notFound) }
        var headers = HTTPFields()
        headers[.contentType] = "image/webp"
        headers[.cacheControl] = "private, max-age=604800"                                        // the page asks with ?v=<build>: a new release, new URLs
        return Response(status: .ok, headers: headers, body: try await FileIO().loadFile(path: u.path, context: context))
    }
    router.get("/robots.txt") { _, _ in Response(status: .ok, headers: [.contentType: "text/plain"], body: .init(byteBuffer: ByteBuffer(string: "User-agent: *\nDisallow: /\n"))) }
}

// MARK: - the pages

// The card's own colours (the renders'): the red top, the black band, the LCD's cream. Galmuri (the app's pixel font, SIL OFL) for the wordmark and
// the numbers, Pretendard for the rest; both from jsDelivr, with system fonts behind them.
let pageFonts = """
    <link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/variable/pretendardvariable-dynamic-subset.min.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/galmuri@2/dist/galmuri.css">
    """

let pageStyle = """
    :root { --red: #d62e2a; --band: #22252d; --bg: #fbfaf7; --card: #ffffff; --paper: #f6f3ea; --ink: #1c1d21; --mute: #6b6e76; --line: #e8e5dd;
        --soft: #f3f1ec; --dot: rgba(34, 37, 45, .09); --tag: #fde4e1; --tag-ink: #a8231f; }
    @media (prefers-color-scheme: dark) { :root { --band: #0b0c0f; --bg: #121316; --card: #1b1d22; --paper: #1f2126; --ink: #ececef; --mute: #9b9ea7;
        --line: #2b2e35; --soft: #23262c; --dot: rgba(255, 255, 255, .07); --tag: #3a1c1b; --tag-ink: #ff8f86; } }
    * { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }
    body { margin: 0; background: var(--bg); color: var(--ink); word-break: keep-all; overflow-wrap: anywhere;
        font: 16px/1.65 "Pretendard Variable", Pretendard, -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Malgun Gothic", "Segoe UI", sans-serif; }
    a { color: inherit; }
    .wrap { max-width: 1040px; margin: 0 auto; padding: 0 20px; }
    .pixel { font-family: Galmuri11, "Pretendard Variable", Pretendard, monospace; font-weight: 400; }
    .ball { flex: none; width: 30px; height: 30px; border-radius: 50%; border: 3px solid var(--band); position: relative;
        background: linear-gradient(#fff 0 43%, var(--band) 43% 57%, #fff 57%); }
    .ball::after { content: ""; position: absolute; inset: 0; margin: auto; width: 10px; height: 10px; border-radius: 50%; background: #fff; border: 3px solid var(--band); }
    .brand { display: flex; align-items: center; gap: 12px; font-size: 21px; letter-spacing: .3px; }

    /* the top: the card's red, its dot paper */
    .hero { background: var(--red); color: #fff; position: relative; overflow-x: clip; }
    .hero::before { content: ""; position: absolute; inset: 0; pointer-events: none;
        background-image: radial-gradient(rgba(255, 255, 255, .13) 1.3px, transparent 1.5px); background-size: 18px 18px; }
    .hero-in { position: relative; display: grid; grid-template-columns: 1.1fr .9fr; gap: 32px; align-items: center; padding-top: 48px; padding-bottom: 36px; }
    .hero h1 { font-size: clamp(34px, 5.2vw, 52px); line-height: 1.18; font-weight: 800; letter-spacing: -.025em; margin: 28px 0 16px; }
    .lede { font-size: 17px; line-height: 1.7; margin: 0; max-width: 31em; color: rgba(255, 255, 255, .92); }
    .dl { display: flex; flex-wrap: wrap; gap: 12px; margin: 30px 0 16px; }
    .btn { display: flex; flex-direction: column; min-width: 210px; padding: 13px 20px 12px; border-radius: 14px; background: #fff; color: #1c1d21;
        text-decoration: none; font-weight: 800; font-size: 17px; box-shadow: 0 5px 0 rgba(0, 0, 0, .2); transition: transform .12s, box-shadow .12s; }
    .btn:hover { transform: translateY(-2px); box-shadow: 0 7px 0 rgba(0, 0, 0, .2); }
    .btn:active { transform: translateY(3px); box-shadow: 0 2px 0 rgba(0, 0, 0, .2); }
    .btn small { font-weight: 500; font-size: 12.5px; color: #6b6e76; margin-top: 1px; }
    .dl.picked .btn:not(.primary) { background: transparent; color: #fff; box-shadow: inset 0 0 0 2px rgba(255, 255, 255, .65); }
    .dl.picked .btn:not(.primary) small { color: rgba(255, 255, 255, .8); }
    .btn.off { opacity: .55; pointer-events: none; }
    .hero .meta { font-size: 13px; color: rgba(255, 255, 255, .78); }
    .shots { position: relative; height: 430px; margin-bottom: -150px; z-index: 2; }
    .shots img { position: absolute; top: 0; left: 50%; width: 236px; height: auto; filter: drop-shadow(0 20px 28px rgba(0, 0, 0, .32)); }
    .shots .back { top: 60px; transform: translateX(-112%) rotate(-7deg); }
    .shots .front { transform: translateX(-14%) rotate(4deg); }
    /* the band across, with the ball's button */
    .band { height: 22px; background: var(--band); position: relative; }
    .band::after { content: ""; position: absolute; left: 50%; top: 50%; width: 62px; height: 62px; transform: translate(-50%, -50%); border-radius: 50%;
        background: var(--bg); border: 8px solid var(--band); box-shadow: inset 0 0 0 5px var(--bg), inset 0 0 0 8px var(--line); }

    main.wrap { padding-top: 116px; padding-bottom: 24px; }
    section { margin-bottom: 84px; }
    .eyebrow { font-size: 13px; color: var(--red); letter-spacing: .4px; margin: 0; }
    h2 { font-size: clamp(25px, 3.3vw, 33px); line-height: 1.3; font-weight: 800; letter-spacing: -.02em; margin: 8px 0 10px; }
    .sub { color: var(--mute); max-width: 38em; margin: 0 0 30px; }

    .stats { display: grid; grid-template-columns: repeat(4, 1fr); background: var(--card); border: 1px solid var(--line); border-radius: 20px; margin-bottom: 84px; }
    .stats div { padding: 22px 12px 18px; text-align: center; }
    .stats div + div { border-left: 1px solid var(--line); }
    .stats b { display: block; font-size: 30px; line-height: 1.2; color: var(--red); }
    .stats span { font-size: 14px; color: var(--mute); }

    .features { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
    .feat { background: var(--card); border: 1px solid var(--line); border-radius: 22px; overflow: hidden; display: flex; flex-direction: column; }
    .feat .pic { height: 262px; overflow: hidden; display: flex; justify-content: center; align-items: flex-start; padding-top: 24px; border-bottom: 1px solid var(--line);
        background: var(--paper) radial-gradient(var(--dot) 1.3px, transparent 1.5px) 0 0 / 14px 14px; }
    .feat .pic img { width: 204px; height: auto; filter: drop-shadow(0 10px 16px rgba(0, 0, 0, .16)); transition: transform .35s ease; }
    .feat:hover .pic img { transform: translateY(-6px); }
    .feat .txt { padding: 18px 22px 22px; }
    .feat h3 { margin: 0 0 6px; font-size: 18px; letter-spacing: -.01em; }
    .feat p { margin: 0; color: var(--mute); font-size: 14.5px; line-height: 1.65; }

    .perks { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-top: 20px; }
    .perk { display: flex; gap: 14px; padding: 20px 22px; background: var(--soft); border-radius: 18px; }
    .perk svg { flex: none; width: 26px; height: 26px; color: var(--red); margin-top: 2px; }
    .perk h3 { margin: 0 0 4px; font-size: 16px; }
    .perk p { margin: 0; color: var(--mute); font-size: 14px; line-height: 1.6; }

    .steps { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
    .step { background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: 22px 22px 20px; }
    .step .n { width: 34px; height: 34px; border-radius: 50%; background: var(--red); color: #fff; display: grid; place-items: center; font-size: 15px; margin-bottom: 14px; }
    .step h3 { margin: 0 0 8px; font-size: 18px; }
    .step p { margin: 0 0 6px; color: var(--mute); font-size: 14.5px; line-height: 1.65; }
    .step p b { color: var(--ink); }
    kbd, code { font: 12.5px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: var(--soft); border: 1px solid var(--line); border-radius: 5px; padding: 0 5px; }
    .more { margin-top: 20px; background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: 4px 22px; }
    .more > summary, .rel > summary { list-style: none; cursor: pointer; display: flex; align-items: center; gap: 10px; }
    .more > summary::-webkit-details-marker, .rel > summary::-webkit-details-marker { display: none; }
    .more > summary::after, .rel > summary::after { content: "+"; margin-left: auto; font-size: 20px; font-weight: 400; color: var(--mute); }
    .more[open] > summary::after, .rel[open] > summary::after { content: "−"; }
    .more > summary { font-weight: 700; padding: 14px 0; }
    .more .cols { display: grid; grid-template-columns: repeat(3, 1fr); gap: 28px; padding: 4px 0 18px; font-size: 14.5px; }
    .more h4 { margin: 0 0 6px; font-size: 15px; }
    .more ol, .more ul { margin: 0; padding-left: 19px; color: var(--mute); }
    .more li { margin: 3px 0; } .more li b { color: var(--ink); }

    .notes { background: var(--card); border: 1px solid var(--line); border-radius: 22px; padding: 6px 26px; }
    .intro { color: var(--mute); font-size: 14px; margin: 16px 0 4px; }
    .rel { border-top: 1px solid var(--line); padding: 4px 0; }
    .intro + .rel, .notes > .rel:first-child { border-top: 0; }
    .rel > summary { padding: 14px 0; font-weight: 800; font-size: 19px; }
    .rel > summary .date { color: var(--mute); font-weight: 500; font-size: 13.5px; }
    .notes > .rel:first-of-type > summary .date::after { content: "최신"; margin-left: 10px; padding: 2px 8px; border-radius: 99px; background: var(--red); color: #fff; font-size: 11.5px; font-weight: 700; }
    .rel h4 { margin: 14px 0 6px; font-size: 15px; }
    .rel p { margin: 6px 0; color: var(--mute); font-size: 14.5px; }
    .tag { display: inline-block; background: var(--tag); color: var(--tag-ink); border-radius: 6px; padding: 1px 8px; margin-right: 8px; font-size: 12px; font-weight: 700; vertical-align: 1px; }
    .rel ul { margin: 4px 0 10px; padding-left: 20px; font-size: 14.5px; }
    .rel li { margin: 3px 0; }
    .rel li ul { margin: 2px 0 4px; padding-left: 16px; color: var(--mute); }
    .rel > :last-child { margin-bottom: 18px; }
    .older { border-top: 1px solid var(--line); }
    .older > summary { list-style: none; cursor: pointer; display: flex; align-items: center; gap: 10px; padding: 16px 0; font-weight: 700; color: var(--mute); }
    .older > summary::-webkit-details-marker { display: none; }
    .older > summary::after { content: "+"; margin-left: auto; font-size: 20px; font-weight: 400; }
    .older[open] > summary::after { content: "−"; }
    .older > summary .date { font-weight: 500; font-size: 13.5px; }
    .older .rel > summary { padding: 10px 0; font-size: 16px; }
    .older .rel:first-of-type { border-top: 0; }

    footer { border-top: 1px solid var(--line); padding: 28px 0 56px; color: var(--mute); font-size: 13px; }
    footer p { margin: 0 0 8px; }
    footer summary { cursor: pointer; }
    .sum { font: 11.5px/1.7 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; word-break: break-all; margin-top: 6px; }

    @media (max-width: 860px) {
        .hero-in { grid-template-columns: 1fr; gap: 8px; padding-top: 36px; }
        .shots { height: 400px; margin-bottom: -170px; }
        .features { grid-template-columns: repeat(2, 1fr); }
        .perks, .steps, .more .cols { grid-template-columns: 1fr; }
        main.wrap { padding-top: 176px; }
    }
    @media (max-width: 560px) {
        .btn { flex: 1 1 100%; }
        .shots img { width: 196px; } .shots { height: 350px; margin-bottom: -150px; }
        .shots .back { transform: translateX(-92%) rotate(-7deg); } .shots .front { transform: translateX(-22%) rotate(4deg); }
        .stats { grid-template-columns: repeat(2, 1fr); }
        .stats div:nth-child(3) { border-left: 0; } .stats div:nth-child(n+3) { border-top: 1px solid var(--line); }
        .features { grid-template-columns: 1fr; }
        main.wrap { padding-top: 156px; }
        .notes { padding: 4px 18px; }
    }

    /* the gate (login, nothing yet): a small card of the ball itself, on the dot paper */
    .gate { min-height: 100vh; min-height: 100dvh; display: grid; place-items: center; padding: 24px 16px;
        background: var(--bg) radial-gradient(var(--dot) 1.3px, transparent 1.5px) 0 0 / 18px 18px; }
    .gate-card { width: 100%; max-width: 380px; border-radius: 26px; overflow: hidden; background: var(--card); border: 1px solid var(--line);
        box-shadow: 0 24px 60px rgba(0, 0, 0, .12); }
    .gate-top { background: var(--red); color: #fff; padding: 26px 26px 30px; }
    .gate-top p { margin: 14px 0 0; color: rgba(255, 255, 255, .88); font-size: 14.5px; }
    .gate .band::after { width: 50px; height: 50px; border-width: 7px; background: var(--card); box-shadow: inset 0 0 0 4px var(--card), inset 0 0 0 7px var(--line); }
    .gate-body { padding: 34px 26px 26px; }
    .gate-body label { display: block; font-size: 13px; font-weight: 700; margin-bottom: 8px; }
    .gate-body .row { display: flex; gap: 8px; }
    .gate-body input { flex: 1; min-width: 0; font: inherit; padding: 11px 14px; border-radius: 12px; border: 1px solid var(--line); background: var(--soft); color: var(--ink); }
    .gate-body input:focus { outline: 2px solid var(--red); outline-offset: 1px; }
    .gate-body button { font: inherit; font-weight: 800; padding: 11px 20px; border: 0; border-radius: 12px; background: var(--red); color: #fff; cursor: pointer; }
    .gate-body .err { color: var(--red); font-size: 14px; margin: 12px 0 0; }
    .gate-body .note { color: var(--mute); font-size: 14.5px; margin: 0; }
    """

func shell(_ title: String, _ body: String) -> String {
    """
    <!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow"><meta name="theme-color" content="#d62e2a"><title>\(esc(title))</title>\(pageFonts)<style>\(pageStyle)</style></head>
    <body>\(body)</body></html>
    """
}

let brandHTML = "<div class=\"brand pixel\"><span class=\"ball\"></span>PokeWalker</div>"

/// The gate: the ball's red top, its band, a white bottom with what to do.
func gate(_ top: String, _ bottom: String) -> String {
    shell("PokeWalker", """
        <div class="gate"><div class="gate-card"><div class="gate-top">\(brandHTML)<p>\(top)</p></div><div class="band"></div>
        <div class="gate-body">\(bottom)</div></div></div>
        """)
}

func loginPage(wrong: Bool) -> String {
    gate("팀 배포 페이지예요. 비밀번호를 넣으면 게임 소개, 최신 빌드, 패치 내역을 볼 수 있어요.", """
        <form method="post" action="/login"><label for="pw">팀 비밀번호</label>
        <div class="row"><input id="pw" type="password" name="password" placeholder="비밀번호" autocomplete="current-password" autofocus required><button>열기</button></div></form>
        \(wrong ? "<p class=\"err\">비밀번호가 맞지 않아요.</p>" : "")
        """)
}
func notFoundPage() -> String { gate("팀 배포 페이지", "<p class=\"note\">찾는 파일이 없어요. <a href=\"/\">처음으로</a></p>") }

/// What the game is: a render (server/publish.sh's shots), a name, a line.
let featureList: [(shot: String, alt: String, title: String, text: String)] = [
    ("home_night_kraft", "밤의 홈 화면: 크라프트지 수첩 위 폴라로이드 속 길을 걷는 피카츄",
     "입력이 곧 걸음", "키 한 번에 1걸음, 클릭 한 번에 5걸음, 20걸음마다 1W. 동료는 폴라로이드 속 길을 걷고, 1,000걸음이 하루, 7일이면 계절이 바뀌어요."),
    ("radar_live", "포켓 레이더: 흔들리는 풀숲 넷 중 하나를 고르는 화면",
     "포켓 레이더와 연쇄", "10W로 풀숲을 흔들어 포켓몬을 찾아요. 잡거나 이기면 연쇄가 이어지고, 길어질수록 희귀한 포켓몬과 이로치, 좋은 개체값이 잘 나와요."),
    ("move_use", "야생 배틀: 리자몽의 용의분노가 피카츄에게 날아가는 장면",
     "4세대 배틀 그대로", "HGSS 싱글 배틀 규칙에 기술 467개, 특성 123개. 상태이상, 날씨, 랭크, 교체, 4세대 포획 공식까지 그대로 들어 있어요."),
    ("dex_grid", "도감: 1번부터 30번까지의 아이콘 격자",
     "493종 도감", "원작 20개 코스에 이벤트·전설 코스를 더한 35개 코스. 알과 전설 구매까지 더하면 1번부터 493번까지 전부 모을 수 있어요."),
    ("page_box", "포켓몬 상세: 이브이의 성격, 특성, 개체값과 노력치 육각형",
     "개체값 · 성격 · 특성", "만나는 포켓몬마다 개체값, 성격, 특성이 달라요. 노력치를 쌓고, 진화시키고, 기술을 고르고, 병뚜껑으로 특훈해요."),
    ("tower_intro_2.5", "배틀 타워: 엘리트 트레이너가 갸라도스를 내보내는 장면",
     "배틀 타워", "세 마리 파티로 연승에 도전해요. 모두 Lv.50으로 맞춰 싸우고, 모은 BP로 도구와 뮤츠를 바꿀 수 있어요."),
]

/// Small line icons (stroke = currentColor) for the perks.
let iconCloud = "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M7 18h10a4 4 0 0 0 .6-7.96A6 6 0 0 0 6.1 9.1 4.5 4.5 0 0 0 7 18z\"/></svg>"
let iconRefresh = "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M20 11a8 8 0 0 0-14.6-4.5L4 8\"/><path d=\"M4 4v4h4\"/><path d=\"M4 13a8 8 0 0 0 14.6 4.5L20 16\"/><path d=\"M20 20v-4h-4\"/></svg>"
let iconPin = "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"4\" y=\"4\" width=\"16\" height=\"16\" rx=\"4\"/><path d=\"M4 12h16\"/><circle cx=\"12\" cy=\"12\" r=\"2.5\" fill=\"currentColor\"/></svg>"

/// The detected OS's button goes first and stays white; the other turns to an outline. No match (a phone), no change.
let pickScript = """
    <script>(function () { var u = navigator.userAgent, k = /Windows/.test(u) ? "windows" : (/Macintosh|Mac OS X/.test(u) && !/iPhone|iPad/.test(u)) ? "mac" : null;
    if (!k) return; document.querySelectorAll(".dl").forEach(function (d) { var b = d.querySelector('[data-os="' + k + '"]'); if (!b) return;
    b.classList.add("primary"); d.insertBefore(b, d.firstChild); d.classList.add("picked"); }); })();</script>
    """

extension DownloadSite {
    /// A screenshot's <img>, or nothing when the release has none of that name.
    func shot(_ name: String, _ alt: String, _ build: String, cls: String = "", lazy: Bool = true) -> String {
        guard shotFile(name + ".webp") != nil else { return "" }
        let c = cls.isEmpty ? "" : " class=\"\(cls)\""
        return "<img\(c) src=\"/shot/\(esc(name)).webp?v=\(esc(build))\" alt=\"\(esc(alt))\" width=\"216\"\(lazy ? " loading=\"lazy\"" : "") decoding=\"async\">"
    }

    func page() -> String {
        guard let r = release else {
            return shell("PokeWalker", "<header class=\"hero\"><div class=\"wrap hero-in\"><div>\(brandHTML)<h1>아직 올라온<br>빌드가 없어요</h1></div></div></header><div class=\"band\"></div>"
                + "<main class=\"wrap\" style=\"padding-top: 60px\">" + notesSection() + "</main>")
        }
        let when = Date(timeIntervalSince1970: TimeInterval(r.published)).formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "ko_KR")))
        func button(_ os: String, _ kind: String, _ label: String, _ what: String, _ b: Release.Build?) -> String {
            guard let b else { return "<span class=\"btn off\" data-os=\"\(os)\">\(label)<small>\(what) · 준비 중</small></span>" }
            return "<a class=\"btn\" data-os=\"\(os)\" href=\"/download/\(kind)\">\(label)<small>\(what) · \(String(format: "%.1f", Double(b.size) / 1_048_576)) MB</small></a>"
        }
        let setup = r.windowsSetup != nil                                                            // the installer release on: its button and its steps
        let buttons = button("mac", "mac", "Mac용 받기", "Apple Silicon · Intel, macOS 13+", r.mac)
            + (setup ? button("windows", "windows-setup", "Windows용 받기", "Windows 10 · 11, x64 · 설치 프로그램", r.windowsSetup)
                     : button("windows", "windows", "Windows용 받기", "Windows 10 · 11, x64", r.windows))
        let front = shot("home", "홈 화면: 몬스터볼 카드 속 스티커 수첩과 피카츄", r.build, cls: "front", lazy: false)
        let back = shot("battle_menu", "야생 배틀: 피카츄와 리자몽", r.build, cls: "back", lazy: false)
        let shots = front.isEmpty ? "" : "<div class=\"shots\">\(back)\(front)</div>"
        let features = featureList.map { f in
            let img = shot(f.shot, f.alt, r.build)
            return "<article class=\"feat\">\(img.isEmpty ? "" : "<div class=\"pic\">\(img)</div>")<div class=\"txt\"><h3>\(f.title)</h3><p>\(f.text)</p></div></article>"
        }.joined()
        let sums = [("Mac", r.mac), ("Windows 설치 프로그램", r.windowsSetup), ("Windows zip", setup ? r.windows : nil), ("Windows", setup ? nil : r.windows)]
            .compactMap { n, b in b.map { "\(n) \($0.sha256)" } }.joined(separator: "<br>")
        let hero = """
            <header class="hero"><div class="wrap hero-in"><div>\(brandHTML)
            <h1>일하는 동안,<br>포켓몬과 함께 걸어요</h1>
            <p class="lede">키보드를 누르고 마우스를 클릭할 때마다 한 걸음. 화면 구석의 몬스터볼 카드 안에서 동료가 걷고, 모은 W로 포켓몬을 만나요. HGSS의 포켓워커를 Mac과 Windows 데스크톱으로 옮겨 왔어요.</p>
            <div class="dl">\(buttons)</div>
            <div class="meta">최신 \(esc(r.version)) · \(esc(when)) · 빌드 \(esc(r.build))</div></div>\(shots)</div></header>
            <div class="band"></div>
            """
        let about = """
            <div class="stats"><div><b class="pixel">493</b><span>포켓몬</span></div><div><b class="pixel">35</b><span>코스</span></div>
            <div><b class="pixel">467</b><span>기술</span></div><div><b class="pixel">123</b><span>특성</span></div></div>
            <section><p class="eyebrow pixel">GAME</p><h2>이런 게임이에요</h2>
            <p class="sub">원작 포켓워커처럼 걸어서 포켓몬을 만나고, 원작엔 없던 배틀과 육성까지 카드 하나에서 다 해요. 조작은 카드 아래 패널을 클릭하거나 키보드로.</p>
            <div class="features">\(features)</div>
            <div class="perks">
            <div class="perk">\(iconCloud)<div><h3>어디서나 이어서</h3><p>세이브는 서버에 있어요. 같은 트레이너 ID와 PIN이면 Mac에서도 Windows에서도 이어서 해요.</p></div></div>
            <div class="perk">\(iconRefresh)<div><h3>알아서 최신으로</h3><p>새 버전은 앱이 조용히 받아 두고 다음에 켤 때 바꿔요. 우클릭 → 업데이트 확인 · 설치로 바로도 돼요.</p></div></div>
            <div class="perk">\(iconPin)<div><h3>켜 두기만 하면</h3><p>늘 위에 떠 있는 작은 카드예요. 접거나 숨겨 둬도 걸음과 부화는 계속 쌓여요.</p></div></div>
            </div></section>
            """
        let start = """
            <section><p class="eyebrow pixel">START</p><h2>시작하기</h2><p class="sub">\(setup ? "Mac은 압축을 풀어 옮기고, Windows는 설치 프로그램을 실행해요." : "설치 프로그램 없이 압축만 풀면 돼요.") 서명되지 않은 앱이라 처음 한 번만 열어 주는 과정이 있어요.</p>
            <div class="steps">
            <div class="step"><div class="n pixel">1</div><h3>받기</h3><p>맨 위에서 내 컴퓨터에 맞는 파일을 받아요.</p><p><b>Mac</b> 압축을 풀고 PokeWalker.app을 <b>응용 프로그램</b> 폴더로 옮겨요.</p>\(setup
                ? "<p><b>Windows</b> 받은 설치 프로그램을 실행해요. 설치 위치는 바꾸지 않아도 돼요.</p>"
                : "<p><b>Windows</b> 압축을 풀고 PokeWalker 폴더를 쓰기 권한이 있는 곳에 둬요.</p>")</div>
            <div class="step"><div class="n pixel">2</div><h3>처음 열기</h3><p><b>Mac</b> 우클릭 → 열기 → 열기. 그래도 막히면 시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기.</p>\(setup
                ? "<p><b>Windows</b> 'Windows의 PC 보호' 창이 뜨면 <b>추가 정보 → 실행</b>. 설치가 끝나면 시작 메뉴의 PokeWalker로 켜요.</p>"
                : "<p><b>Windows</b> PokeWalker.exe를 실행하고, SmartScreen이 막으면 추가 정보 → 실행.</p>")</div>
            <div class="step"><div class="n pixel">3</div><h3>트레이너 ID와 PIN</h3><p>처음 켜면 트레이너 ID(2~12자)와 숫자 4자리 PIN을 정해요. 다른 PC에서도 같은 ID와 PIN으로 들어오면 이어서 해요.</p></div>
            </div>
            <details class="more"><summary>자세한 설치 방법</summary><div class="cols">
            <div><h4>Mac</h4><ol><li>다운로드 폴더에서 바로 켜면 <b>자동 업데이트가 안 돼요</b>. 꼭 응용 프로그램 폴더로 옮겨요.</li>
            <li>Apple 개발자 서명이 없어서 더블클릭하면 막혀요. 처음 한 번만 우클릭 → 열기.</li>
            <li>터미널이 편하면 <code>xattr -dr com.apple.quarantine /Applications/PokeWalker.app</code></li>
            <li>알림 허용을 물으면 허용해요. 메뉴 막대의 몬스터볼을 누르면 카드를 숨기거나 보여요.</li></ol></div>
            <div><h4>Windows</h4><ol>\(setup
                ? "<li>설치 프로그램은 내 사용자 폴더에 설치해서 관리자 권한이 필요 없고, 자동 업데이트도 돼요.</li><li>예전에 zip으로 받아 쓰던 분은 그 폴더를 지우고 설치 프로그램으로 다시 설치하면 돼요. 세이브는 서버에 있어요.</li><li>지울 때는 설정 → 앱에서 PokeWalker를 제거해요.</li>"
                : "<li>Program Files에 두면 <b>자동 업데이트가 안 돼요</b>. 쓰기 권한이 있는 폴더에 둬요.</li>")
            <li>로그인할 때 자동으로 켜려면 <kbd>Win+R</kbd> → <code>shell:startup</code> 폴더에 바로 가기를 넣어요.</li>
            <li>Windows는 앱이 켜져 있는 동안의 입력만 걸음으로 세요.</li>
            <li>알림 영역의 몬스터볼을 클릭하면 숨기기 / 보이기, 우클릭하면 메뉴예요.</li></ol></div>
            <div><h4>업데이트와 세이브</h4><ul><li>새 버전은 앱이 알아서 받아서, 다음에 끄거나 켤 때 바꿔요.</li>
            <li>바로 바꾸려면 우클릭 → <b>업데이트 확인 · 설치</b>. 한 번에 확인, 받기, 다시 시작까지 해요.</li>
            <li>세이브는 서버에 있어서 다시 받아 설치해도 그대로예요.</li>
            <li>숨기기 단축키: Mac <kbd>⌃⌥P</kbd> · Windows <kbd>Ctrl+Alt+P</kbd></li></ul></div>
            </div></details></section>
            """
        let footer = """
            <footer><div class="wrap"><p>팀 안에서만 쓰는 페이지예요. 링크와 파일을 밖으로 공유하지 말아 주세요.</p>
            <p>포켓몬 이미지와 데이터의 저작권은 Nintendo · Creatures · GAME FREAK · The Pokémon Company에 있어요. 글꼴 Galmuri(이민서, SIL OFL 1.1).</p>
            <details><summary>파일 확인값 (SHA-256) · 커밋 \(esc(String(r.commit.prefix(7))))</summary><div class="sum">\(sums)</div></details></div></footer>
            """
        return shell("PokeWalker \(r.version)", hero + "<main class=\"wrap\">" + about + start + notesSection(latest: r.version) + "</main>" + footer + pickScript)
    }

    func notesSection(latest: String? = nil) -> String {
        guard let text = notes else { return "" }
        return "<section><p class=\"eyebrow pixel\">NOTES</p><h2>패치 내역</h2><div class=\"notes\">" + notesHTML(text, open: latest) + "</div></section>"
    }
}

/// docs/patch-notes.txt → HTML: "■ 1.15 · 2026-10-02" a version (the newest open), "[바뀐 점] …" a heading, "- " an item, "  · " an item under it,
/// another indented line the item's next line, anything else a paragraph; the lines before the first ■ (after the title) an intro.
/// The newest `shown` stand alone; the rest fold into one 이전 버전 (open when it holds the open one).
func notesHTML(_ text: String, open: String?, shown: Int = 3) -> String {
    var intro: [String] = [], versions: [(head: String, lines: [String])] = []
    for (i, raw) in text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n").enumerated() {
        if raw.hasPrefix("■") { versions.append((raw.dropFirst().trimmingCharacters(in: .whitespaces), [])) }
        else if versions.isEmpty { if i > 0, !raw.trimmingCharacters(in: .whitespaces).isEmpty { intro.append(raw) } }
        else { versions[versions.count - 1].lines.append(raw) }
    }
    var out = intro.map { "<p class=\"intro\">\(esc($0))</p>" }.joined(), older = "", olderOpen = false
    for (n, v) in versions.enumerated() {
        let parts = v.head.components(separatedBy: " · "), ver = parts[0], date = parts.dropFirst().joined(separator: " · ")
        var body = "", items: [(text: String, subs: [String])] = []
        func flush() {
            guard !items.isEmpty else { return }
            body += "<ul>"
            for item in items {
                let subs: String = item.subs.isEmpty ? "" : "<ul>" + item.subs.map { (s: String) -> String in "<li>\(s)</li>" }.joined() + "</ul>"
                body += "<li>\(item.text)\(subs)</li>"
            }
            body += "</ul>"
            items = []
        }
        for line in v.lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if line.hasPrefix("- ") { items.append((esc(String(line.dropFirst(2))), [])) }
            else if line.hasPrefix("  · "), !items.isEmpty { items[items.count - 1].subs.append(esc(String(line.dropFirst(4)))) }
            else if line.hasPrefix(" "), !items.isEmpty {                                          // a wrapped line: under the last item
                if items[items.count - 1].subs.isEmpty { items[items.count - 1].text += "<br>" + esc(t) } else { items[items.count - 1].subs[items[items.count - 1].subs.count - 1] += "<br>" + esc(t) }
            }
            else if t.hasPrefix("["), let close = t.firstIndex(of: "]") {
                flush()
                let label = t[t.index(after: t.startIndex)..<close], rest = t[t.index(after: close)...].trimmingCharacters(in: .whitespaces)
                body += "<h4><span class=\"tag\">\(esc(String(label)))</span>\(esc(rest))</h4>"
            }
            else { flush(); body += "<p>\(esc(t))</p>" }
        }
        flush()
        let isOpen = open.map { $0 == ver } ?? (n == 0)
        let one = "<details class=\"rel\"\(isOpen ? " open" : "")><summary>\(esc(ver))<span class=\"date\">\(esc(date))</span></summary>\(body)</details>"
        if n < shown { out += one } else { older += one; olderOpen = olderOpen || isOpen }
    }
    if versions.count > shown {
        let span = esc(versions[shown].head.components(separatedBy: " · ")[0]) + " ~ " + esc(versions[versions.count - 1].head.components(separatedBy: " · ")[0])
        out += "<details class=\"older\"\(olderOpen ? " open" : "")><summary>이전 버전 \(versions.count - shown)개<span class=\"date\">\(span)</span></summary>\(older)</details>"
    }
    return out
}
