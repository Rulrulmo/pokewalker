import Foundation
import Hummingbird

// The team's download page (GET /): the latest Mac and Windows builds and the patch notes, behind one team password (DOWNLOAD_PASSWORD).
// What it shows is RELEASE_DIR as server/publish.sh leaves it: release.json, patch-notes.txt and the two zips. /v1 (the app's API) is untouched.

struct Release: Codable, Sendable {
    struct Build: Codable, Sendable { let file: String; let size: Int; let sha256: String }
    let version: String, build: String, commit: String, published: Int
    let mac: Build?, windows: Build?
}

struct DownloadSite: Sendable {
    let dir: URL, password: String
    /// The cookie that says the password was given: an HMAC of the password, so a new password logs everyone out and nothing is kept server-side.
    var token: String { hex(hmacSHA256(key: Array(password.utf8), Array("pokewalker download v1".utf8))) }
    var release: Release? { (try? Data(contentsOf: dir.appendingPathComponent("release.json"))).flatMap { try? JSONDecoder().decode(Release.self, from: $0) } }
    var notes: String? { try? String(contentsOf: dir.appendingPathComponent("patch-notes.txt"), encoding: .utf8) }
    func authorized(_ r: Request) -> Bool { cookie(r, "pw_dl") == token }
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
        guard let r = site.release, let b = kind == "mac" ? r.mac : kind == "windows" ? r.windows : nil else { return html(notFoundPage(), status: .notFound) }
        var headers = HTTPFields()
        headers[.contentType] = "application/zip"
        headers[.contentLength] = String(b.size)
        headers[.contentDisposition] = "attachment; filename=\"PokeWalker-\(r.version)-\(kind).zip\""
        headers[.cacheControl] = "no-store"
        context.logger.info("download \(kind) \(r.version)")
        return Response(status: .ok, headers: headers, body: try await FileIO().loadFile(path: site.dir.appendingPathComponent(b.file).path, context: context))
    }
    router.get("/robots.txt") { _, _ in Response(status: .ok, headers: [.contentType: "text/plain"], body: .init(byteBuffer: ByteBuffer(string: "User-agent: *\nDisallow: /\n"))) }
}

// MARK: - the pages

let pageStyle = """
    :root { --bg: #f4f1ec; --card: #ffffff; --ink: #1d1d1f; --mute: #6b6b70; --line: #e4e0d8; --red: #e3350d; --red-ink: #ffffff; --tag: #fbe3dc; --tag-ink: #a3260a; }
    @media (prefers-color-scheme: dark) { :root { --bg: #151517; --card: #1f1f22; --ink: #ececef; --mute: #9a9aa2; --line: #2e2e33; --red: #ff5a36; --red-ink: #1a0600; --tag: #3a1d16; --tag-ink: #ff9b84; } }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Malgun Gothic", "Segoe UI", sans-serif; }
    main { max-width: 720px; margin: 0 auto; padding: 32px 16px 64px; }
    .brand { display: flex; align-items: center; gap: 10px; font-weight: 700; font-size: 18px; margin-bottom: 20px; }
    .ball { width: 26px; height: 26px; border-radius: 50%; border: 2.5px solid var(--ink); background: linear-gradient(var(--red) 0 44%, var(--ink) 44% 56%, var(--card) 56%); position: relative; }
    .ball::after { content: ""; position: absolute; inset: 0; margin: auto; width: 9px; height: 9px; border-radius: 50%; background: var(--card); border: 2.5px solid var(--ink); }
    .card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 24px; margin-bottom: 20px; }
    .ver { font-size: 34px; font-weight: 800; letter-spacing: -0.5px; }
    .meta { color: var(--mute); font-size: 13px; }
    .dl { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin: 20px 0 8px; }
    @media (max-width: 520px) { .dl { grid-template-columns: 1fr; } }
    .btn { display: block; text-decoration: none; background: var(--red); color: var(--red-ink); border-radius: 10px; padding: 14px 16px; font-weight: 700; font-size: 16px; }
    .btn small { display: block; font-weight: 400; font-size: 12px; opacity: .85; }
    .btn.off { background: var(--line); color: var(--mute); pointer-events: none; }
    .sum { font-size: 11px; color: var(--mute); word-break: break-all; margin-top: 6px; }
    details > summary { cursor: pointer; font-weight: 600; }
    .howto { margin-top: 16px; font-size: 14px; } .howto ol { padding-left: 20px; margin: 8px 0; } .howto h4 { margin: 12px 0 4px; }
    code { background: var(--bg); padding: 1px 5px; border-radius: 4px; font-size: 13px; }
    h2 { font-size: 18px; margin: 0 0 12px; }
    .rel { border-top: 1px solid var(--line); padding: 12px 0; } .rel:first-of-type { border-top: 0; }
    .rel > summary { font-size: 16px; } .rel > summary .date { color: var(--mute); font-weight: 400; font-size: 13px; margin-left: 6px; }
    .rel h4 { margin: 14px 0 6px; font-size: 14px; } .tag { display: inline-block; background: var(--tag); color: var(--tag-ink); border-radius: 6px; padding: 0 7px; margin-right: 6px; font-size: 12px; }
    .rel ul { margin: 4px 0; padding-left: 20px; } .rel li { margin: 2px 0; } .rel li ul { padding-left: 16px; color: var(--mute); }
    .intro { color: var(--mute); font-size: 13px; margin: -4px 0 8px; }
    form { display: flex; gap: 8px; margin-top: 16px; } input { flex: 1; min-width: 0; font: inherit; padding: 10px 12px; border-radius: 8px; border: 1px solid var(--line); background: var(--bg); color: var(--ink); }
    button { font: inherit; font-weight: 700; padding: 10px 18px; border: 0; border-radius: 8px; background: var(--red); color: var(--red-ink); cursor: pointer; }
    .err { color: var(--red); font-size: 14px; margin-top: 10px; }
    """

func shell(_ title: String, _ body: String) -> String {
    """
    <!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow"><title>\(esc(title))</title><style>\(pageStyle)</style></head>
    <body><main><div class="brand"><span class="ball"></span>PokeWalker</div>\(body)</main></body></html>
    """
}

func loginPage(wrong: Bool) -> String {
    shell("PokeWalker", """
        <div class="card"><h2>팀 배포 페이지</h2><div class="meta">팀 비밀번호를 넣으면 최신 빌드와 패치 내역을 볼 수 있어요.</div>
        <form method="post" action="/login"><input type="password" name="password" placeholder="비밀번호" autocomplete="current-password" autofocus required><button>열기</button></form>
        \(wrong ? "<div class=\"err\">비밀번호가 맞지 않아요.</div>" : "")</div>
        """)
}
func notFoundPage() -> String { shell("PokeWalker", "<div class=\"card\">아직 올라온 빌드가 없어요. <a href=\"/\">돌아가기</a></div>") }

extension DownloadSite {
    func page() -> String {
        guard let r = release else { return shell("PokeWalker", "<div class=\"card\">아직 올라온 빌드가 없어요.</div>" + notesSection()) }
        let when = Date(timeIntervalSince1970: TimeInterval(r.published)).formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().locale(Locale(identifier: "ko_KR")))
        func button(_ kind: String, _ label: String, _ what: String, _ b: Release.Build?) -> String {
            guard let b else { return "<span class=\"btn off\">\(label)<small>\(what) · 준비 중</small></span>" }
            return "<a class=\"btn\" href=\"/download/\(kind)\">\(label)<small>\(what) · \(String(format: "%.1f", Double(b.size) / 1_048_576)) MB</small></a>"
        }
        let sums = [("Mac", r.mac), ("Windows", r.windows)].compactMap { n, b in b.map { "\(n) SHA-256 \($0.sha256)" } }.joined(separator: "<br>")
        return shell("PokeWalker \(r.version)", """
            <div class="card"><div class="meta">최신 버전</div><div class="ver">\(esc(r.version))</div>
            <div class="meta">\(esc(when)) 올림 · 빌드 \(esc(r.build)) · 커밋 \(esc(String(r.commit.prefix(7))))</div>
            <div class="dl">\(button("mac", "Mac 다운로드", "Apple Silicon · Intel, macOS 13 이상", r.mac))\(button("windows", "Windows 다운로드", "Windows 10 · 11, x64", r.windows))</div>
            <div class="sum">\(sums)</div>
            <details class="howto"><summary>설치 · 업데이트 방법</summary>
            <h4>Mac</h4><ol><li>압축을 풀고 <code>PokeWalker.app</code>을 응용 프로그램 폴더로 옮겨요.</li>
            <li>처음 한 번은 <b>우클릭 → 열기 → 열기</b>(Apple 개발자 서명이 없어서 더블클릭하면 막혀요). macOS 15 이상에서 그래도 막히면 한 번 실행해 본 뒤 <b>시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기</b>.</li>
            <li>알림 허용을 물으면 허용해요.</li></ol>
            <h4>Windows</h4><ol><li>압축을 풀면 나오는 <code>PokeWalker</code> 폴더를 통째로 원하는 곳에 두고 <code>PokeWalker.exe</code>를 실행해요.</li>
            <li>SmartScreen이 막으면 <b>추가 정보 → 실행</b>.</li>
            <li>로그인할 때 자동으로 켜려면 <code>Win+R</code> → <code>shell:startup</code> 폴더에 바로 가기를 넣어요.</li></ol>
            <h4>업데이트</h4><p>앱을 끄고 새 zip으로 앱(Windows는 폴더)을 덮어쓰면 돼요. 세이브는 그대로 남아요.</p></details></div>
            """ + notesSection(latest: r.version))
    }

    func notesSection(latest: String? = nil) -> String {
        guard let text = notes else { return "" }
        return "<div class=\"card\"><h2>패치 내역</h2>" + notesHTML(text, open: latest) + "</div>"
    }
}

/// docs/patch-notes.txt → HTML: "■ 1.15 · 2026-10-02" a version (the newest open), "[바뀐 점] …" a heading, "- " an item, "  · " an item under it,
/// another indented line the item's next line, anything else a paragraph; the lines before the first ■ (after the title) an intro.
func notesHTML(_ text: String, open: String?) -> String {
    var intro: [String] = [], versions: [(head: String, lines: [String])] = []
    for (i, raw) in text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n").enumerated() {
        if raw.hasPrefix("■") { versions.append((raw.dropFirst().trimmingCharacters(in: .whitespaces), [])) }
        else if versions.isEmpty { if i > 0, !raw.trimmingCharacters(in: .whitespaces).isEmpty { intro.append(raw) } }
        else { versions[versions.count - 1].lines.append(raw) }
    }
    var out = intro.map { "<p class=\"intro\">\(esc($0))</p>" }.joined()
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
        out += "<details class=\"rel\"\(isOpen ? " open" : "")><summary>\(esc(ver))<span class=\"date\">\(esc(date))</span></summary>\(body)</details>"
    }
    return out
}
