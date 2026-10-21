import Foundation
import Hummingbird

// The guide (GET /guide, 10-21): raising Pokémon in this game, for teammates who don't know Pokémon — the 회사 session's text (5.1.5), its numbers
// checked against the code. Opens like the page (behind DOWNLOAD_PASSWORD with it), never indexed.
// Its pictures are GUIDE_DIR (default /var/lib/pokewalker/guide) as server/guide.sh leaves it: docs/guide/img/ (the Mac's app renders, PNG as WebP)
// and docs/guide/README.md (their captions). A picture's section is its name's first two digits (06-mint-after.webp → 06), its place the names'
// order, a -before / -after pair one figure side by side, its caption the README's line that names it; its place a section's <!--figs 06-05 …-->
// that names it (a name up to a "-"), else the section's <!--figs-->, else its end. No folder, and the guide goes without.

struct GuidePicture: Equatable, Sendable { let file: String, caption: String }
enum GuideFigure: Equatable, Sendable {
    case one(GuidePicture), pair(GuidePicture, GuidePicture)                                                // pair: before, after
    var stems: [String] { switch self { case .one(let p): [guideStem(p.file)]; case .pair(let b, let a): [guideStem(b.file), guideStem(a.file)] } }
}

/// A guide picture's name: letters, digits, - _ . only (no path, no dotfile) and a picture's extension.
func guideName(_ name: String) -> Bool {
    ["webp", "png", "jpg", "jpeg"].contains((name as NSString).pathExtension.lowercased()) && !name.hasPrefix(".") && !name.contains("..")
        && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
}
func guideStem(_ s: some StringProtocol) -> String { let t = String(s); return ((t.split(separator: "/").last.map(String.init) ?? t) as NSString).deletingPathExtension }

/// The README's caption for a picture: an image's alt (![…](img/06-x.png)), else the rest of the first line that names it (a list item, a table
/// row) — by the stem, since the README names the PNG the folder keeps as WebP.
func guideCaption(_ file: String, _ readme: String) -> String {
    let stem = guideStem(file)
    for raw in readme.components(separatedBy: "\n") {
        let line = raw.replacingOccurrences(of: #"^\s*(?:[-*+]|\d+\.)\s+"#, with: "", options: .regularExpression)
        if let open = line.range(of: "!["), let mid = line.range(of: "](", range: open.upperBound..<line.endIndex),
           let close = line[mid.upperBound...].firstIndex(of: ")"), guideStem(line[mid.upperBound..<close]) == stem {
            return String(line[open.upperBound..<mid.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        var words = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "|" }).map(String.init)
        guard let hit = words.firstIndex(where: { guideStem($0.trimmingCharacters(in: CharacterSet(charactersIn: "`*[]()<>:,"))) == stem }) else { continue }
        words.remove(at: hit)
        return words.joined(separator: " ").replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -—–:|#>"))
    }
    return ""
}

/// A caption's ①, ②, …: the numbers in the picture (red dots, like the picture's own), one line each after what comes before them.
func guideCaptionHTML(_ caption: String) -> String {
    let order = Array("①②③④⑤⑥⑦⑧⑨⑩⑪⑫"), marks = Set(order)
    guard caption.contains(where: marks.contains) else { return esc(caption) }
    var lead = "", items: [(mark: Character, text: String)] = []
    for ch in caption {
        if marks.contains(ch) { items.append((ch, "")) } else if items.isEmpty { lead.append(ch) } else { items[items.count - 1].text.append(ch) }
    }
    let lis = items.map { "<li><span>\((order.firstIndex(of: $0.mark) ?? 0) + 1)</span>\(esc($0.text.trimmingCharacters(in: .whitespaces)))</li>" }.joined()
    return esc(lead.trimmingCharacters(in: .whitespaces)) + "<ol class=\"marks\">\(lis)</ol>"
}

/// The pictures by section ("06"), each in name order; a -before / -after pair one figure where its first name stands.
func guideFigures(_ files: [String], readme: String) -> [String: [GuideFigure]] {
    func half(_ stem: String) -> (base: String, after: Bool)? {
        for (s, after) in [("-before", false), ("_before", false), ("-after", true), ("_after", true)] where stem.hasSuffix(s) { return (String(stem.dropLast(s.count)), after) }
        return nil
    }
    let names = files.filter(guideName).sorted()
    var out: [String: [GuideFigure]] = [:], done = Set<String>()
    for f in names where !done.contains(f) {
        let stem = guideStem(f), section = String(stem.prefix(2))
        guard section.count == 2, section.allSatisfy(\.isNumber) else { continue }
        let pic = GuidePicture(file: f, caption: guideCaption(f, readme))
        if let h = half(stem), let other = names.first(where: { o in o != f && !done.contains(o) && half(guideStem(o)).map { $0.base == h.base && $0.after != h.after } == true }) {
            let o = GuidePicture(file: other, caption: guideCaption(other, readme))
            out[section, default: []].append(h.after ? .pair(o, pic) : .pair(pic, o))
            done.insert(other)
        } else { out[section, default: []].append(.one(pic)) }
        done.insert(f)
    }
    return out
}

extension DownloadSite {
    /// A guide picture's file: a plain name, and there.
    func guideFile(_ name: String) -> URL? {
        guard let g = guide, guideName(name) else { return nil }
        let u = g.appendingPathComponent("img", isDirectory: true).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    var guideFigs: [String: [GuideFigure]] {
        guard let g = guide, let files = try? FileManager.default.contentsOfDirectory(atPath: g.appendingPathComponent("img").path) else { return [:] }
        return guideFigures(files, readme: (try? String(contentsOf: g.appendingPathComponent("README.md"), encoding: .utf8)) ?? "")
    }

    func guidePage() -> String {
        let figs = guideFigs
        func img(_ p: GuidePicture) -> String {
            let at = guideFile(p.file).flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
            return "<img src=\"/guide/img/\(esc(p.file))?v=\(at.map { Int($0.timeIntervalSince1970) } ?? 0)\" alt=\"\(esc(p.caption))\" loading=\"lazy\" decoding=\"async\">"
        }
        func figures(_ fs: [GuideFigure]) -> String {
            let solo = fs.count == 1 && fs[0].stems.count == 1                                            // one picture alone: its caption beside it
            return fs.isEmpty ? "" : "<div class=\"figs n\(fs.count)\(solo ? " solo" : "")\">" + fs.map { f in
                switch f {
                case .one(let p):
                    return "<figure class=\"fig\"><div class=\"frame\">\(img(p))</div>\(p.caption.isEmpty ? "" : "<figcaption>\(guideCaptionHTML(p.caption))</figcaption>")</figure>"
                case .pair(let b, let a):
                    let cap = [("전", b.caption), ("후", a.caption)].filter { !$0.1.isEmpty }.map { "<b>\($0.0)</b> \(esc($0.1))" }.joined(separator: "<br>")
                    return "<figure class=\"fig pair\"><div class=\"frame\"><div class=\"side\">\(img(b))<span class=\"chip\">전</span></div><span class=\"arrow\" aria-hidden=\"true\">→</span>"
                        + "<div class=\"side\">\(img(a))<span class=\"chip after\">후</span></div></div>\(cap.isEmpty ? "" : "<figcaption>\(cap)</figcaption>")</figure>"
                }
            }.joined() + "</div>"
        }
        let toc = guideSections.map { "<a href=\"#\($0.id)\"><span class=\"pixel\">\($0.no)</span>\($0.title)</a>" }.joined()
        let sections = guideSections.map { s in
            var left = figs[s.no] ?? [], body = s.body
            while let r = body.range(of: #"<!--figs( [0-9A-Za-z_-]+)+-->"#, options: .regularExpression) {     // "<!--figs 06-05 06-06-->": those, here
                let names = body[r].dropFirst(9).dropLast(3).split(separator: " ").map(String.init)
                let mine = left.filter { f in f.stems.contains { st in names.contains { st == $0 || st.hasPrefix($0 + "-") } } }
                left.removeAll { mine.contains($0) }
                body.replaceSubrange(r, with: figures(mine))
            }
            let rest = figures(left)                                                                      // the rest: <!--figs--> or the end
            body = body.contains(figsHere) ? body.replacingOccurrences(of: figsHere, with: rest) : body + rest
            return "<section id=\"\(s.id)\" class=\"g\"><h2><span class=\"no pixel\">\(s.no)</span>\(s.title)</h2>\(body)</section>"
        }.joined()
        let hero = """
            <header class="hero">\(topBar("/guide"))<div class="wrap ghead"><p class="kicker pixel">GUIDE · 5.1.5</p><h1>육성 가이드</h1>
            <p class="lede">포켓몬을 몰라도 괜찮아요. 이 게임에서 포켓몬을 잡고, 키우고, 강하게 만드는 법을 처음부터 순서대로 정리했어요.</p>
            <nav class="toc" id="toc" aria-label="목차">\(toc)</nav></div></header><div class="band"></div>
            """
        let footer = """
            <footer><div class="wrap guide-foot"><p>PokeWalker 5.1.5 기준. 숫자와 규칙은 업데이트에 따라 바뀔 수 있어요.</p>
            <p>팀 안에서만 쓰는 페이지예요. 링크를 밖으로 공유하지 말아 주세요.</p>
            <p>포켓몬 이미지와 데이터의 저작권은 Nintendo · Creatures · GAME FREAK · The Pokémon Company에 있어요. 글꼴 Galmuri(이민서, SIL OFL 1.1).</p>
            <p><a href="/">← 다운로드 페이지로</a></p></div></footer><a class="fab" href="#toc">목차</a>
            """
        return shell("육성 가이드 · PokeWalker", hero + "<main class=\"wrap guide\">" + sections + "</main>" + footer, style: guideStyle)
    }
}

/// The top of both pages: the brand (home), the two pages; the one you're on filled (on a phone, only the other).
func topBar(_ here: String) -> String {
    func link(_ href: String, _ label: String) -> String { "<a href=\"\(href)\"\(href == here ? " aria-current=\"page\"" : "")>\(label)</a>" }
    return "<div class=\"wrap top\"><a class=\"home\" href=\"/\">\(brandHTML)</a><nav>\(link("/", "다운로드"))\(link("/guide", "육성 가이드"))</nav></div>"
}

// MARK: - the text

struct GuideSection: Sendable { let id: String, no: String, title: String, body: String }
let figsHere = "<!--figs-->"                                                                   // where a section's other pictures go (none: its end)

/// A table; on a phone each row a card, its cells labelled by the head.
func gTable(_ head: [String], _ rows: [[String]]) -> String {
    let th: String = head.map { "<th>\($0)</th>" }.joined()
    let trs: String = rows.map { (row: [String]) -> String in
        let tds: String = zip(head, row).map { (h: String, cell: String) -> String in "<td data-label=\"\(h)\">\(cell)</td>" }.joined()
        return "<tr>\(tds)</tr>"
    }.joined()
    return "<div class=\"tbl\"><table><thead><tr>\(th)</tr></thead><tbody>\(trs)</tbody></table></div>"
}
func gNote(_ text: String) -> String { "<div class=\"callout\">\(iconInfo)<p>\(text)</p></div>" }
func nb(_ n: Int) -> String { "<span class=\"nb pixel\">\(n)</span>" }
let iconInfo = "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M12 11v5\"/><circle cx=\"12\" cy=\"7.6\" r=\".6\" fill=\"currentColor\"/></svg>"

/// 06's picture of a stat: the base stat (×2), the IV and the EV ÷ 4 summed, by the level, then the nature — the pictures' 이상해꽃's Sp. Atk at Lv.50,
/// nothing looked after against everything (Battle's stat formula: ((2B + IV + EV/4) × L / 100 + 5) × nature).
let statFigure = """
    <figure class="formula" aria-label="능력치가 정해지는 방법">
    <div class="fx"><span class="b">종족값 ×2</span><i>+</i><span class="i">개체값</span><i>+</i><span class="e">노력치 ÷4</span><i>→</i><span class="l">× 레벨</span><i>→</i><span class="l">성격 ±10%</span><i>=</i><span class="r">능력치</span></div>
    <div class="bars">
    <div class="brow"><div class="bwho">아무것도 안 챙긴 이상해꽃<small>개체값 0 · 노력치 0 · 특공 내리는 성격</small></div>
    <div class="bar"><span class="seg b" style="flex: 200">종족값 100×2</span><span class="pad" style="flex: 94"></span></div><b class="bval pixel">94<small>특공</small></b></div>
    <div class="brow"><div class="bwho">다 챙긴 이상해꽃<small>개체값 31 · 노력치 252 · 특공 올리는 성격</small></div>
    <div class="bar"><span class="seg b" style="flex: 200">종족값 100×2</span><span class="seg i" style="flex: 31">31</span><span class="seg e" style="flex: 63">63</span></div><b class="bval pixel">167<small>특공</small></b></div>
    </div>
    <div class="legend">
    <div style="--k: var(--c-base)"><b>종족값</b>종마다 정해져 있어요. 이상해꽃의 특공은 100. 바꿀 수 없어요.</div>
    <div style="--k: var(--red)"><b>개체값</b>타고나요. 0~31. 연쇄로 31을 확정하고, 병뚜껑으로 31로 채워요.</div>
    <div style="--k: var(--c-ev)"><b>노력치</b>키우면서 쌓아요. 4마다 1씩 더해져서, 한 능력에 252면 충분해요.</div>
    <div style="--k: var(--mute)"><b>레벨 · 성격</b>합에 레벨/100을 곱하고 5를 더한 뒤, 성격으로 ±10%. 성격은 민트로 바꿔요.</div>
    </div>
    <figcaption>같은 이상해꽃, 같은 Lv.50인데 특공이 <b>94</b>와 <b>167</b>로 크게 달라요. 막대는 레벨과 성격을 곱하기 전의 합이에요.</figcaption>
    </figure>
    """

// The text: 회사's (5.1.5), with what the code says where it differed (10-21: a click 5 steps, the egg's steps, the power reset, the weather re-rolled,
// the day's 100,000, the neutral natures, EVs 255 (252 counts), the guest's 10% first, the legend's 2% + 1%p a link, the trade under 친구 ▸ 교환,
// 원정 지가르데 for now, 뮤츠 in the BP 교환소, the everstone and stones, steps' day and night, rare candies evolving, mega stones only from Mega raids,
// a raid ball's 30% / 10%, the tower's firsts, the Mega raid's tiers, the red dot from 21:00, Sylveon by any Fairy move).
let guideSections: [GuideSection] = [basicsSection, wordsSection, catchSection, levelSection, evolveSection, strongSection, routineSection, playSection, mistakesSection]

let basicsTable: String = gTable(["쌓이는 것", "비율", "어디에 쓰나"], [
    ["W (와트)", "20걸음 = 1W", "상점, 레이더(10W), 배틀 타워(도전할 때 50W). 지갑은 9,999W까지"],
    ["누적 W", "걸어서 번 W만", "기본 코스 열기. 써도 줄지 않고, 팔거나 우편으로 받은 W와 연쇄 보너스는 안 쳐요"],
    ["동료의 경험치", "1걸음 = 1", "함께 걷는 포켓몬 1마리가 레벨업"],
    ["워커의 경험치", "2걸음 = 1", "워커에 넣어 둔 포켓몬(최대 3마리)이 각자 받아요"],
    ["알", "종마다 2,550~10,200걸음", "한 번에 하나. 다 걸으면 Lv.1로 부화해 상자로 가요"],
    ["레이드 파워", "10,000걸음 = 1칸", "매일 0시에 2칸으로 다시 맞춰져요. 레이드 · 메가 레이드 합쳐 하루 10판"],
    ["게임 시간", "1,000걸음 = 하루", "낮(4~20시) · 밤(20~4시)이 바뀌어요. 진화 조건에 쓰여요"],
    ["날씨", "1,000걸음마다", "맑음 · 비 · 눈 · 안개 중에서 다시 정해요. 날씨에 맞는 타입이 1.5배 잘 나와요"],
])
let basicsSection = GuideSection(id: "basics", no: "01", title: "걸음이 하는 일", body: """
    <p>이 앱에서 '걸음'은 실제로 걷는 게 아니라 <strong>키보드와 마우스를 누른 횟수</strong>예요. 키를 한 번 누르면 1걸음, 마우스를 클릭하면(왼쪽 · 오른쪽) 5걸음이에요. 마우스를 움직이거나 휠을 굴리는 건 세지 않고, 무엇을 눌렀는지도 보지 않아요. 걸음 하나로 여러 가지가 동시에 쌓여요.</p>
    \(basicsTable)
    \(gNote("매크로나 자동 클릭은 걸음으로 세지 않아요. 초당 15걸음, 분당 600걸음까지만 세고, 기계처럼 일정한 입력이 2분 넘게 이어지면 걸음이 멈춰요. 1분 동안 손을 떼면 다시 세요. 하루에는 10만 걸음까지 세요."))
    """)

let wordsSection = GuideSection(id: "words", no: "02", title: "꼭 알아야 할 말", body: """
    <dl class="terms">
    <div><dt>동료</dt><dd>지금 함께 걷는 포켓몬 1마리. 걸음이 그대로 경험치가 돼요.</dd></div>
    <div><dt>워커</dt><dd>동료 말고 같이 데리고 다니는 최대 3마리. 걸음의 절반을 경험치로 받아요.</dd></div>
    <div><dt>상자</dt><dd>새로 잡거나 부화한 포켓몬이 모두 들어가는 보관함이에요.</dd></div>
    <div><dt>타입</dt><dd>불 · 물 · 풀 같은 속성 18가지. 서로 상성이 있어요. 물은 불에 강하고, 불은 풀에 강해요.</dd></div>
    <div><dt>레벨</dt><dd>1~100. 높을수록 능력치가 올라가요.</dd></div>
    <div><dt>기술</dt><dd>배틀에서 쓰는 공격이나 보조 동작. 한 마리가 4개까지 알아요.</dd></div>
    <div><dt>특성</dt><dd>포켓몬마다 붙는 고유 능력. 같은 종이라도 특성이 다를 수 있어요. 드물게 '숨겨진특성'도 있어요.</dd></div>
    <div><dt>성격</dt><dd>25가지. 그중 20가지는 능력치 하나를 10% 올리고 하나를 10% 내려요. 5가지는 아무것도 바꾸지 않아요.</dd></div>
    <div><dt>개체값 (V)</dt><dd>타고난 재능. 능력치마다 0~31이고, 31을 'V'라고 불러요. 3V는 31이 세 개라는 뜻이에요.</dd></div>
    <div><dt>노력치</dt><dd>키우면서 쌓는 능력치. 한 능력 255, 전부 합쳐 510까지예요. 4마다 1씩 반영돼서 252면 충분해요.</dd></div>
    <div><dt>이로치 ★</dt><dd>색이 다른 희귀한 개체. 기본 확률은 1/64이에요. 능력은 같고 모습만 달라요.</dd></div>
    <div><dt>전설</dt><dd>루기아, 뮤츠 같은 특별한 포켓몬. 전설 코스, 레이드, 원정, 상점, BP 교환소에서 얻어요.</dd></div>
    <div><dt>메가진화</dt><dd>메가스톤을 지닌 포켓몬이 배틀 중 한 번 더 강해지는 변신. 배틀마다 한 번만 써요.</dd></div>
    <div><dt>BP</dt><dd>배틀 타워 · 레이드 · 대전에서 버는 점수. BP 교환소에서 좋은 도구로 바꿔요.</dd></div>
    </dl>
    """)

let chainTable: String = gTable(["연쇄", "좋아지는 것"], [
    ["매번", "W 보너스(+2 × 연쇄), 야생 레벨 +2(최대 +20), 희귀한 포켓몬이 더 잘 나옴"],
    ["3 · 5 · 7 · 9", "개체값 31이 1 · 2 · 3 · 4개 확정"],
    ["5+ / 10+", "숨겨진특성이 10% / 25% 확률"],
    ["10+", "이로치 확률 1/64 → 1/10 (이어질수록 조금씩 올라요)"],
    ["5마다", "그 코스에서 가장 희귀한 도구"],
])
let catchSection = GuideSection(id: "catch", no: "03", title: "포켓몬 잡기", body: """
    <h3>포켓 레이더 (10W)</h3>
    <p>메뉴에서 포켓 레이더를 누르면 아래 패널에 풀숲 4개가 나와요. 흔들리는 풀숲(!)을 시간 안에 누르면 배틀이 시작돼요. 상대를 약하게 만든 뒤 볼을 던지면 잡을 수 있어요. 볼은 공짜예요.</p>
    <!--figs 03-1 03-2 03-3-->
    <h3>연쇄</h3>
    <p>잡거나 쓰러뜨리면 확률로 레이더가 무료로 이어져요. 처음엔 85%로 이어지고, 한 번마다 8%씩 줄어서 최저 35%예요. 도망치거나 지면 끊겨요.</p>
    \(chainTable)
    <h3>코스</h3>
    <p>코스마다 나오는 포켓몬이 달라요. 손님 포켓몬이 먼저 10% 확률로 나오고, 나머지를 그룹 A(희귀) 20% · B 30% · C(흔함) 50%로 나눠요. 코스는 누적 W나 잡은 종 수로 하나씩 열려요. 전설 코스(도감 150종부터)에서는 레이더가 2% 확률로 전설을 만나고, 연쇄 1번마다 1%씩 올라 최대 6%예요.</p>
    <h3>그 밖에 얻는 길</h3>
    <ul class="ways">
    <li><b>알</b>알이 없을 때 동료가 가끔 주워 와요. 걸으면 부화해요.</li>
    <li><b>레이드</b>보스를 이기면 볼 5개(지면 3개)를 던져요. 볼 하나마다 처음 잡는 종이면 30%, 이미 있는 종이면 10%로 잡혀요.</li>
    <li><b>교환 <span class="path">친구 ▸ 교환</span></b>교환 게시판에서 다른 사람과 바꿔요.</li>
    <li><b>전설 원정 <span class="path">모험 ▸ 전설 원정</span></b>걸어서 전설을 받아요. 지금은 지가르데 원정이 열려 있고, 팀 이벤트로 환상 포켓몬도 와요.</li>
    <li><b>상점 · BP 교환소</b>칠색조(상점 9,999W), 뮤츠(BP 교환소 300BP)는 여기서만 얻어요.</li>
    </ul>
    """)

let levelSection = GuideSection(id: "level", no: "04", title: "레벨 올리기", body: """
    <p>레벨과 다음 레벨까지 남은 경험치는 홈의 동료 줄에서 보여요. 레벨을 올리는 길은 다섯 가지예요.</p>
    \(figsHere)
    <ul class="ways">
    <li><b>동료로 걷기 <span class="path">포켓몬 ▸ 칸 ▸ 함께 걷기</span></b>가장 기본이에요. 1걸음이 경험치 1이에요.</li>
    <li><b>워커에 넣기 <span class="path">포켓몬 ▸ 칸 ▸ 자세히 ▸ 워커로</span></b>워커가 3마리보다 적을 때 보낼 수 있어요. 2걸음당 1씩 자라고, 야생 배틀에 안 나가도 경험치를 절반 받아요.</li>
    <li><b>야생 배틀 <span class="path">포켓 레이더</span></b>이기거나 잡으면 경험치. 상대 레벨이 높을수록 많이 받아요.</li>
    <li><b>이상한사탕 <span class="path">포켓몬 ▸ 도구 ▸ 육성</span></b>한 번에 1레벨. BP 교환소 8BP, 도감 업적 · 타워 연승 · 레이드 주간 보상으로도 와요.</li>
    <li><b>맡겨 키우기 <span class="path">친구 카드 ▸ 맡기기</span></b>지금 걷는 친구에게 5시간 맡기면, 친구가 걷는 만큼 경험치가 쌓여요. 우편함으로 돌아와요.</li>
    </ul>
    \(gNote("Lv.100이 된 포켓몬에게 간 경험치는 쓰이지 않아요. 다 키웠으면 동료와 워커를 다른 포켓몬으로 바꿔 주세요."))
    """)

let evolveTable: String = gTable(["방식", "조건", "예"], [
    ["레벨", "정한 레벨이 되면", "파이리 → 리자드 (Lv.16)"],
    ["친밀도", "동료로 함께 1만 걸음 뒤 레벨업", "피츄 → 피카츄"],
    ["시간대", "친밀도 + 낮이나 밤에 레벨업 (걸음으로 흐르는 게임 시간)", "이브이 → 에브이(낮) · 블래키(밤)"],
    ["진화의 돌", "도구를 쓰면 바로", "피카츄 + 천둥의돌 → 라이츄"],
    ["장소", "그 코스에서 레벨업", "이브이 → 리피아(숲 코스) · 글레이시아(얼음 산길)"],
    ["교환", "교환 게시판으로 받을 때 (받는 쪽에서)", "윤겔라 → 후딘"],
    ["직접 고르기", "Lv.20부터 셋 중 하나 골라요", "배루키 → 시라소몬 · 홍수몬 · 카포에라"],
])
let evolveSection = GuideSection(id: "evolve", no: "05", title: "진화", body: """
    <p>진화는 포켓몬이 다른 모습으로 바뀌는 거예요. 대부분 더 강해지고, 되돌릴 수 없어요. 진화하기 싫으면 변함없는돌을 지니게 하면 돼요(상점 200W). 다만 진화의 돌은 써도 그대로 진화해요.</p>
    \(evolveTable)
    <p>진화 방법은 포켓몬 페이지의 진화 줄에 나와요. 돌은 쓰는 즉시, 교환은 받을 때, 배루키는 직접 고를 때 진화해요. 나머지는 레벨이 오르는 순간(이상한사탕 포함) 조건이 맞으면 진화해요.</p>
    """)

let strongTable: String = gTable(["무엇", "바꾸는 방법", "얻는 곳"], [
    [nb(2) + "성격", "민트를 쓰면 능력치가 그 성격대로 계산돼요(원래 성격 표시는 그대로)", "상점 1,000W, 도감 업적 보상"],
    [nb(3) + "특성", "특성패치로 숨겨진특성 ↔ 첫 번째 특성 (숨겨진특성이 있는 종만)", "BP 교환소 100BP, 지가르데 원정 첫 완료"],
    [nb(4) + "개체값", "만날 때 정해져요. 연쇄 3 · 5 · 7 · 9에서 1~4V 확정. Lv.50부터는 은색병뚜껑(하나를 31로) · 금색병뚜껑(전부 31로)", "BP 교환소 25 · 120BP, 타워 연승 · 레이드 · 도감 보상"],
    [nb(5) + "노력치", "영양제로 +10, 노력치를 내리는 열매로 −10, 순백떡으로 전부 0. 야생 배틀로도 쌓여요", "영양제 상점 100W · BP 교환소 1BP, 열매 · 순백떡은 상점"],
    [nb(6) + "지닌 도구", "포켓몬마다 하나. 생명의구슬, 먹다남은음식, 메가스톤 같은 것", "상점, BP 교환소, 메가스톤은 메가 레이드에서만"],
])
let strongSection = GuideSection(id: "strong", no: "06", title: "강하게 만들기", body: """
    <p>레벨이 같아도 아래 다섯 가지에 따라 실력이 크게 달라요. 타워나 대전에 쓸 포켓몬이라면 하나씩 챙기면 좋아요.</p>
    \(statFigure)
    <h3>포켓몬 페이지에서 한눈에</h3>
    <p>포켓몬에서 한 마리를 고르고 '자세히'를 누르면 다섯 가지가 다 보여요. 그림의 번호가 아래 표와 설명의 번호예요.</p>
    <!--figs 06-01-->
    \(strongTable)
    <h3>\(nb(2))성격 · 민트</h3>
    <p>민트를 쓰면 능력치가 민트의 성격대로 계산돼요. 성격 이름은 그대로 보이고 옆에 '(민트: …)'가 붙어요.</p>
    <!--figs 06-03-->
    <!--figs 06-04-->
    <h3>\(nb(3))특성 · 특성패치</h3>
    <p>숨겨진특성이 있는 종에게 쓰면 숨겨진특성과 첫 번째 특성이 서로 바뀌어요.</p>
    <!--figs 06-08-->
    <h3>\(nb(4))개체값 · 병뚜껑</h3>
    <p>Lv.50부터 써요. 은색병뚜껑은 고른 능력 하나를, 금색병뚜껑은 31이 아닌 능력을 전부 31로 계산해요. 병뚜껑으로 올린 값은 금색 숫자로 보여요.</p>
    <!--figs 06-05-->
    <!--figs 06-06 06-07-->
    <h3>\(nb(5))노력치 · 영양제</h3>
    <p>영양제 한 번에 그 능력의 노력치가 10 올라요. 능력마다 영양제가 달라요: 맥스업 HP · 타우린 공격 · 사포닌 방어 · 리보플라빈 특공 · 키토산 특방 · 알칼로이드 스피드.</p>
    <!--figs 06-02-->
    <h3>\(nb(6))지닌 도구 · 메가진화</h3>
    <p>포켓몬 페이지의 '도구 주기'로 도구 하나를 지니게 해요. 메가스톤을 지닌 포켓몬은 배틀에서 메가진화 버튼을 눌러 한 번 더 강해져요. 메가진화는 배틀마다 한 번이에요.</p>
    <!--figs 06-09 06-11-->
    <h3>\(nb(7))기술 고르기</h3>
    <p>레벨이 오르면 새 기술을 배워요. 4개가 꽉 차면 잊을 기술을 고르거나 배우지 않을 수 있어요. 포켓몬 페이지의 기술 바꾸기에서 지금 레벨까지 배우는 기술을 언제든 공짜로 다시 고를 수 있어요. 자기 타입과 같은 공격 기술은 위력이 1.5배라서, 보통 같은 타입 공격 2개 + 다른 타입 1개 + 보조 1개로 맞춰요.</p>
    <!--figs 06-10-->
    """)

let routineSection = GuideSection(id: "routine", no: "07", title: "추천 육성 순서", body: """
    <p>처음 키우는 사람에게 권하는 순서예요. 꼭 지킬 필요는 없어요.</p>
    <ol class="route">
    <li>마음에 드는 포켓몬 하나를 동료로 정해요. 걷기만 해도 자라요.</li>
    <li>레이더로 같은 종을 연쇄로 다시 잡아요. 연쇄를 7 이상 이으면 3V, 9 이상이면 4V인 좋은 개체가 나와요. 그 개체를 새 동료로 바꿔요.</li>
    <li>진화시켜요. 포켓몬 페이지의 진화 줄을 보고 조건을 맞춰요. 원치 않는 모습이 될 수 있으면 변함없는돌을 먼저 지니게 해요.</li>
    <li>레벨을 50 넘게 올려요. 워커, 이상한사탕, 맡겨 키우기를 같이 쓰면 빨라요.</li>
    <li>성격 · 노력치 · 개체값을 다듬어요. 민트로 성격을 맞추고, 영양제로 강한 능력에 노력치를 몰아요. Lv.50이 넘으면 병뚜껑으로 개체값을 31로 채워요.</li>
    <li>배틀 타워에 도전해요. 타워에서는 모두 Lv.50으로 맞춰 싸워요. 연승할수록 1승의 BP가 늘고, 7승째마다 보너스 BP를 더 받아요.</li>
    </ol>
    """)

let playTable: String = gTable(["콘텐츠", "규칙", "보상"], [
    ["배틀 타워", "도전할 때 50W, 3대3, 모두 Lv.50, 전설 · 환상은 1마리까지", "BP, 처음 이룬 연승 보상(이상한사탕 · 병뚜껑, 100연승은 이로치 전설 하나 고르기)"],
    ["레이드", "파워 1칸으로 한 판. 보스는 매일 바뀌어요. ★1~★5 난이도, 내 포켓몬 1~3마리를 그 레벨 그대로", "BP, 볼 5개(지면 3개): 하나마다 처음 잡는 종 30% · 있는 종 10%"],
    ["메가 레이드", "매일 보스 둘. 잡기는 없어요", "메가스톤(★1 3% ~ ★4 10% · ★5 20%, 스톤 없이 같은 보스 20승이면 확정), BP"],
    ["실시간 대전", "친구나 랜덤 상대와 3대3, Lv.50. 대전 파티(3~6마리)에서 상대를 보고 3마리를 골라요", "이기면 3BP"],
    ["전설 원정", "한 번에 하나. 지금은 지가르데: 칼로스 코스 3,000걸음마다 셀 1개, 50개 모으면 끝", "지가르데, 처음 한 번은 특성패치도"],
    ["팀 이벤트", "2주마다 7일 동안 팀 전체 150만 걸음, 각자 2만 걸음", "환상 포켓몬 1마리"],
    ["도감 업적", "잡은 종 수와 지역 도감을 채우면", "이상한사탕 · 병뚜껑 · 민트 · BP. 지역을 다 채우면 그 지역 포켓몬의 이로치 확률이 약 2배(레이더 · 알)"],
])
let playSection = GuideSection(id: "play", no: "08", title: "키운 포켓몬 쓰는 곳", body: playTable)

let mistakesSection = GuideSection(id: "mistakes", no: "09", title: "자주 하는 실수", body: """
    <ul class="warn">
    <li>진화와 놓아주기는 되돌릴 수 없어요. 진화를 막고 싶으면 변함없는돌을 지니게 하세요(진화의 돌은 막지 못해요).</li>
    <li>레이드 파워는 매일 0시에 2칸으로 다시 맞춰져요. 남은 칸은 다음 날로 넘어가지 않아요. 21시부터 칸이 남아 있으면 빨간 점으로 알려 줘요.</li>
    <li>레이드에서 볼 화면을 나가면 남은 볼은 사라져요. 다 던지고 나오세요.</li>
    <li>이브이는 숲 코스나 얼음 산길에서 레벨업하면 레벨과 상관없이 리피아 · 글레이시아가 돼요. 블래키나 에브이를 원하면 다른 코스에서 레벨업하세요. 친밀도가 찼고 페어리 기술(천사의키스 등)을 알면 님피아가 먼저예요.</li>
    <li>ID 입력 창이 나오면 새로 만들지 마세요. 원래 ID와 PIN으로 로그인하면 진행이 그대로 돌아와요.</li>
    <li>앱을 켜 두면 업데이트가 알아서 들어와요. 안 켜지면 이 사이트에서 설치 파일을 받아 다시 설치하면 돼요. 세이브는 서버에 있어서 그대로예요.</li>
    </ul>
    """)

// MARK: - its look (on top of pageStyle)

let guideStyle = """
    :root { --c-base: #5d6472; --c-ev: #e8a317; }
    @media (prefers-color-scheme: dark) { :root { --c-base: #8a91a0; } }
    html { scroll-behavior: smooth; }
    .ghead { position: relative; padding-top: 26px; padding-bottom: 48px; }
    .ghead .kicker { margin: 0; font-size: 13px; letter-spacing: .4px; color: rgba(255, 255, 255, .8); }
    .ghead h1 { font-size: clamp(32px, 5vw, 46px); line-height: 1.2; font-weight: 800; letter-spacing: -.025em; margin: 6px 0 12px; }
    .ghead .lede { max-width: 34em; }
    .toc { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 26px; max-width: 880px; }
    .toc a { display: inline-flex; align-items: center; gap: 8px; text-decoration: none; color: #fff; background: rgba(255, 255, 255, .14);
        border-radius: 99px; padding: 5px 14px 5px 6px; font-size: 14px; font-weight: 600; }
    .toc a:hover { background: rgba(255, 255, 255, .26); }
    .toc a span { display: grid; place-items: center; min-width: 30px; height: 24px; padding: 0 6px; border-radius: 99px; background: #fff; color: var(--red); font-size: 11.5px; }

    main.guide { max-width: 880px; padding-top: 72px; padding-bottom: 8px; }
    .g { margin-bottom: 76px; scroll-margin-top: 16px; }
    .g h2 { display: flex; align-items: center; gap: 14px; margin: 0 0 16px; }
    .g h2 .no { flex: none; width: 46px; height: 46px; border-radius: 50%; background: var(--red); color: #fff; display: grid; place-items: center; font-size: 16px; letter-spacing: 0; }
    .g h3 { font-size: 18.5px; letter-spacing: -.01em; margin: 34px 0 8px; }
    .g p { margin: 0 0 14px; }
    .g strong { background: linear-gradient(transparent 58%, var(--tag) 58%); }

    .tbl { background: var(--card); border: 1px solid var(--line); border-radius: 18px; overflow: hidden; margin: 18px 0 22px; }
    .tbl table { width: 100%; border-collapse: collapse; font-size: 15px; line-height: 1.6; }
    .tbl th { text-align: left; background: var(--soft); color: var(--mute); font-size: 13px; font-weight: 700; padding: 10px 18px; }
    .tbl td { padding: 13px 18px; border-top: 1px solid var(--line); vertical-align: top; }
    .tbl td:first-child { font-weight: 700; white-space: nowrap; }
    .tbl td + td { color: var(--ink); }
    .nb { display: inline-grid; place-items: center; width: 22px; height: 22px; border-radius: 50%; background: var(--red); color: #fff; font-size: 11px; margin-right: 8px; vertical-align: 1px; }

    .callout { display: flex; gap: 12px; background: var(--soft); border-radius: 16px; padding: 14px 18px; margin: 16px 0; }
    .callout svg { flex: none; width: 22px; height: 22px; color: var(--red); margin-top: 1px; }
    .callout p { margin: 0; font-size: 14.5px; }

    .terms { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; margin: 0; }
    .terms div { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 14px 18px; }
    .terms dt { font-weight: 800; margin-bottom: 2px; }
    .terms dd { margin: 0; color: var(--mute); font-size: 14.5px; line-height: 1.6; }

    .ways { list-style: none; padding: 0; margin: 14px 0; display: grid; gap: 10px; }
    .ways li { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 14px 18px; font-size: 15px; color: var(--mute); }
    .ways li b { display: block; color: var(--ink); font-size: 16px; margin-bottom: 2px; }
    .path { display: inline-block; margin-left: 6px; padding: 1px 9px; border-radius: 6px; background: var(--tag); color: var(--tag-ink); font-size: 12.5px; font-weight: 700; vertical-align: 1px; }

    .route { list-style: none; counter-reset: r; padding: 0; margin: 18px 0; display: grid; gap: 10px; }
    .route li { counter-increment: r; position: relative; padding: 14px 18px 14px 62px; background: var(--card); border: 1px solid var(--line); border-radius: 16px; font-size: 15px; }
    .route li::before { content: counter(r); position: absolute; left: 16px; top: 13px; width: 30px; height: 30px; border-radius: 50%; background: var(--red); color: #fff;
        display: grid; place-items: center; font: 13px Galmuri11, monospace; }

    .warn { list-style: none; padding: 0; margin: 0; display: grid; gap: 10px; }
    .warn li { background: var(--card); border: 1px solid var(--line); border-left: 4px solid var(--red); border-radius: 14px; padding: 13px 18px; font-size: 15px; }

    .formula { margin: 22px 0; background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: 20px 22px 16px; }
    .fx { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; font-size: 14px; font-weight: 700; }
    .fx span { border-radius: 8px; padding: 3px 10px; color: #fff; }
    .fx .b { background: var(--c-base); } .fx .i { background: var(--red); } .fx .e { background: var(--c-ev); color: #2b1d00; }
    .fx .l { color: var(--ink); box-shadow: inset 0 0 0 1.5px var(--line); } .fx .r { background: var(--ink); color: var(--bg); }
    .fx i { font-style: normal; color: var(--mute); }
    .bars { display: grid; gap: 14px; margin-top: 20px; }
    .brow { display: grid; grid-template-columns: 200px 1fr 64px; gap: 14px; align-items: center; }
    .bwho { font-weight: 700; font-size: 14.5px; line-height: 1.4; }
    .bwho small { display: block; color: var(--mute); font-weight: 500; font-size: 12.5px; }
    .bar { display: flex; height: 32px; border-radius: 8px; overflow: hidden; background: var(--soft); }
    .seg { display: grid; place-items: center; min-width: 0; overflow: hidden; white-space: nowrap; color: #fff; font-size: 12px; font-weight: 700; }
    .seg.b { background: var(--c-base); } .seg.i { background: var(--red); } .seg.e { background: var(--c-ev); color: #2b1d00; }
    .bval { text-align: right; font-size: 24px; line-height: 1.1; color: var(--red); }
    .bval small { display: block; color: var(--mute); font: 11.5px "Pretendard Variable", Pretendard, sans-serif; }
    .legend { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-top: 18px; }
    .legend div { background: var(--soft); border-radius: 12px; padding: 10px 12px; color: var(--mute); font-size: 13px; line-height: 1.55; }
    .legend b { display: flex; align-items: center; gap: 6px; color: var(--ink); font-size: 14px; margin-bottom: 2px; }
    .legend b::before { content: ""; width: 10px; height: 10px; border-radius: 3px; background: var(--k); }
    .formula figcaption { margin-top: 14px; color: var(--mute); font-size: 14px; }
    .formula figcaption b { color: var(--ink); }

    .figs { display: flex; flex-wrap: wrap; gap: 16px; margin: 18px 0 22px; }
    .fig { flex: 1 1 260px; max-width: 420px; margin: 0; }
    .fig.pair { flex: 1 1 100%; max-width: 100%; }
    .fig .frame { display: flex; justify-content: center; align-items: center; gap: 14px; padding: 16px; border: 1px solid var(--line); border-radius: 18px;
        background: var(--paper) radial-gradient(var(--dot) 1.3px, transparent 1.5px) 0 0 / 14px 14px; }
    .fig img { display: block; width: 100%; max-width: 420px; height: auto; border-radius: 6px; }
    .fig .side { position: relative; flex: 1 1 0; min-width: 0; max-width: 420px; }
    .fig .chip { position: absolute; top: -8px; left: -8px; padding: 1px 10px; border-radius: 99px; background: var(--band); color: #fff; font-size: 12px; font-weight: 700; }
    .fig .chip.after { background: var(--red); }
    .fig .arrow { flex: none; color: var(--mute); font-size: 22px; font-weight: 700; }
    .fig figcaption { margin-top: 8px; color: var(--mute); font-size: 13.5px; line-height: 1.6; }
    .fig figcaption b { color: var(--ink); margin-right: 4px; }
    .marks { list-style: none; margin: 6px 0 0; padding: 0; }
    .marks li { display: flex; gap: 6px; margin: 3px 0; }
    .marks span { flex: none; display: grid; place-items: center; width: 18px; height: 18px; margin-top: 2px; border-radius: 50%; background: var(--red); color: #fff;
        font-size: 11px; font-weight: 800; line-height: 1; }
    @media (min-width: 601px) { .figs.n2 .fig:not(.pair), .figs.n4 .fig:not(.pair) { flex-basis: calc(50% - 8px); } }   /* two or four: two a row (three: three) */
    @media (min-width: 700px) {
        .figs.solo .fig { flex: 1 1 100%; max-width: 100%; display: grid; grid-template-columns: minmax(0, 360px) 1fr; gap: 24px; align-items: start; }
        .figs.solo figcaption { margin-top: 4px; font-size: 14.5px; color: var(--ink); }
        .figs.solo .marks li { margin: 6px 0; }
    }

    .guide-foot a { color: var(--ink); font-weight: 700; }
    .fab { position: fixed; right: 16px; bottom: 16px; z-index: 10; padding: 9px 16px; border-radius: 99px; background: var(--band); color: #fff; text-decoration: none;
        font-size: 14px; font-weight: 700; box-shadow: 0 6px 18px rgba(0, 0, 0, .25); }

    @media (max-width: 860px) {
        .legend { grid-template-columns: repeat(2, 1fr); }
        .brow { grid-template-columns: 1fr 58px; gap: 6px 12px; } .bwho { grid-column: 1 / -1; }
    }
    @media (max-width: 600px) {
        .ghead { padding-bottom: 40px; }
        main.guide { padding-top: 60px; }
        .g { margin-bottom: 60px; }
        .g h2 .no { width: 40px; height: 40px; font-size: 14px; }
        .terms { grid-template-columns: 1fr; }
        .tbl thead { display: none; }
        .tbl tr { display: block; padding: 12px 16px; border-top: 1px solid var(--line); }
        .tbl tbody tr:first-child { border-top: 0; }
        .tbl td { display: grid; grid-template-columns: 74px 1fr; gap: 10px; padding: 3px 0; border: 0; font-size: 14.5px; }
        .tbl td:first-child { display: block; font-size: 16px; padding-bottom: 6px; white-space: normal; }
        .tbl td + td::before { content: attr(data-label); color: var(--mute); font-size: 12.5px; font-weight: 700; padding-top: 2px; }
        .formula { padding: 16px 16px 14px; }
        .fig.pair .frame { flex-direction: column; } .fig .arrow { transform: rotate(90deg); }
        .legend { grid-template-columns: 1fr; }
    }
    """
