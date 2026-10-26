import Foundation
// 5.2.2 (Fav522.swift, docs/plans/25): self-test checks (run by selftest()) — 즐겨찾기: the page's ♡ / ♥ (on, off; the server's save), the ♥ on
// every grid of mine and the LCD, the 상자's ♥ chip and short sorts; a ♥ one let go of in one go (풀고 놓아주기); 중복 n마리 without the ♥; the
// asks before one goes (글 올리기 · 제안 · 1:1 신청 · 수락s, an item in the same window), none for 맡기기; the worst cases laid out (중복 12마리 ·
// 110마리 · a form on the LCD), words where they can be read at 크기 2 · 3 · 4 and the LCD 15 % wider.

@MainActor func fav522Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    func check(_ ok: Bool, _ name: String, _ why: @autoclosure () -> String = "") { c.append((ok, ok ? name : name + " — " + why())) }
    func says(_ w: Walker) -> [String] { if case .say(let l, _, _) = w.screen { return l }; return [] }
    Content.$testing.withValue(true) { Content.$testing51.withValue(true) { Content.$testing52.withValue(true) {
        var r = Seeded(s: 522), uid = 522_000
        func mon(_ d: Int, _ l: Int, ivs: [Int] = [10, 10, 10, 10, 10, 10]) -> Mon { var m = Mon.wild(d, level: l, &r); m.ivs = ivs; m.shiny = nil; uid += 1; m.uid = uid; return m }
        var s = Walk(); s.companion = mon(3, 55); s.caught = [mon(236, 20), mon(133, 18)]
        var squirtle = mon(7, 15); squirtle.item = "먹다남은음식"
        var rotom = mon(479, 40); rotom.form = 1
        s.box = [squirtle, mon(25, 9, ivs: [31, 10, 10, 10, 10, 10]), mon(25, 11, ivs: [0, 0, 0, 0, 0, 0]), mon(25, 15), mon(25, 16), rotom, mon(19, 12)]
        s.owned = Array(1...500); s.seen = s.owned
        let host = TestHost(), w = online(s, host: host), (srv, key) = server(w)                    // (host: weak on the walker — kept here)
        @MainActor func box(_ dex: Int, _ nth: Int = 0) -> Int { w.state.box.indices.filter { w.state.box[$0].dex == dex }[nth] }
        @MainActor func page(_ i: Int) -> MonModel? { w.screen = .box(i, act: nil, confirm: false, detail: true); return w.paneContent(Date()).mon }

        // the page's ♡ / ♥: on (the server's save, the page, the LCD's ♥), off
        let off0 = page(box(7))?.fav == false
        w.paneTap(4417); drain(w)
        let on = w.state.box[box(7)].fav == true && served(w)?.box.first { $0.dex == 7 }?.fav == true && page(box(7))?.fav == true
        w.paneTap(4417); drain(w)
        let offAgain = w.state.box[box(7)].fav == nil && served(w)?.box.first { $0.dex == 7 }?.fav == nil
        check(off0 && on && offAgain, "5.2.2 즐겨찾기: the page's ♡ → ♥ (Mon.fav on the server's save, the page), ♥ → ♡ (nil again)", "\(off0) \(on) \(offAgain)")

        // ♥ on three of them (꼬부기, 피카츄 Lv.11 — not the best one —, 로토무) and the companion, by the act
        for u in [w.state.box[box(7)].uid, w.state.box[box(25, 1)].uid, w.state.box[box(479)].uid, w.state.companion.uid].compactMap({ $0 }) { _ = w.cloud!.act(.mon(op: .fav(uid: u, on: true))); drain(w) }
        w.screen = .box(-1, act: nil, confirm: false)
        let grid = w.paneContent(Date()).grid
        let favCells = grid?.cells.filter(\.fav).count == 3 && grid?.party.first?.fav == true && grid?.party.dropFirst().allSatisfy { !$0.fav } == true
        let sorts = grid?.tabs == ["번호", "레벨", "V", "최근"]
        w.paneTap(4174); let chip = w.boxQuery == "즐겨찾기" && w.boxShown.count == 3 && w.boxShown.allSatisfy { w.state.box[$0].fav == true }
        w.paneTap(4174); let chipOff = w.boxQuery.isEmpty && w.boxShown.count == w.state.box.count
        w.boxQuery = "♥ 전기"; let words = Set(w.boxShown.map { w.state.box[$0].dex }) == [25, 479]; w.boxQuery = ""   // (히트로토무: 전기 · 불꽃)
        check(favCells && sorts && chip && chipOff && words, "5.2.2 즐겨찾기: the ♥ on the box's cells and the party row, the sorts 번호 · 레벨 · V · 최근, the ♥ chip (찾기 즐겨찾기: the three; again: all), 찾기 '♥ 전기'",
              "\(String(describing: grid?.cells.map(\.fav))) \(String(describing: grid?.tabs)) \(chip) \(chipOff) \(words)")

        // the picks: the board's and 1:1's (mine only), 맡기기, the tower's (a pick's number takes the corner)
        w.screen = .market(.pick(MarketPick(listing: nil, give: nil, wish: [], side: 0, at: 0)))
        let market = w.paneContent(Date()).pick?.cells.filter(\.fav).count == 3
        w.screen = .visitPick(ItemOn(item: "민수", pick: nil, at: 0))
        let visit = w.paneContent(Date()).pick?.cells.contains(where: \.fav) == true
        w.screen = .squad(Squad(kind: .tower, picked: [], at: 0))
        let tower = w.paneContent(Date()).squad?.cells.contains(where: \.fav) == true
        check(market && visit && tower, "5.2.2 즐겨찾기: the ♥ on the picks — 글 올리기, 맡기기, 타워", "\(market) \(visit) \(tower)")

        // 놓아주기: 중복 n마리 without the ♥; a ♥ one: 풀고 놓아줄까? → 풀고 놓아주기 (.fav off, then .release)
        let pikaFav = box(25, 1), dupes = page(pikaFav).map { _ in w.paneContent(Date()).mon?.dupes } ?? nil
        w.screen = .box(pikaFav, act: 0, confirm: true, detail: true)
        let lcdAsk = w.compose(Date()).runs.contains { $0.s == "풀고 놓아줄까?" }, gone = w.state.box[pikaFav].uid
        w.paneTap(4403); drain(w); drain(w)
        let released = !(served(w)?.box.contains { $0.uid == gone } ?? true) && says(w).first?.hasSuffix("풀숲으로") == true
        check(dupes == 2 && lcdAsk && released, "5.2.2 즐겨찾기: 중복 n마리 without the ♥ (2 of 피카츄's 4: the best one and the ♥ stay), a ♥ one's 풀고 놓아줄까? → 풀고 놓아주기: let go of, then released",
              "\(String(describing: dupes)) \(lcdAsk) \(released) \(says(w))")
        while case .say = w.screen { w.press(1) }
        var pk = mon(25, 30); pk.fav = true; let pkUID = pk.uid; serve(w) { $0.box.append(pk) }; drain(w)
        host.asked = []; host.bodies = []; host.answer = true
        w.askReleaseDupes(25); drain(w)
        let askedDupes = host.asked.first == "피카츄 2마리를 놓아줄까요?" && host.bodies.first?.contains("즐겨찾기(♥)는 모두 남고") == true && host.bodies.first?.contains("♥Lv.30") == true
        let keptFav = served(w)?.box.contains { $0.uid == pkUID } == true && served(w)?.box.filter { $0.dex == 25 }.count == 2
        check(askedDupes && keptFav, "5.2.2 즐겨찾기: 중복 놓아주기 asks with the ♥ ones staying (♥Lv.30), the server keeps them", "\(host.asked) \(host.bodies) \(String(describing: served(w)?.box.filter { $0.dex == 25 }.map(\.level)))")
        while case .say = w.screen { w.press(1) }

        // the asks: 글 올리기 (♥ with its item: one window), 제안, 1:1 신청, the 수락s' 교환할까요? (a line), none for 맡기기; 취소 sends nothing
        let sq = w.state.box[box(7)].uid
        host.asked = []; host.bodies = []; host.answer = false
        w.sendMarketPick(MarketPick(listing: nil, give: sq, wish: [], side: 0, at: 0), Date()); drain(w)
        let post = host.asked == ["꼬부기는 즐겨찾기한 포켓몬이에요"] && host.bodies.first?.contains("먹다남은음식을 지니고 있어요") == true && host.bodies.first?.contains("즐겨찾기는 풀려요") == true
            && !srv.listings.contains { $0.l.mon.uid == sq }
        srv.listings.append((Listing(id: srv.nextListing, from: "민수", mon: mon(133, 20), wish: [], at: 0, bids: 0, mine: false, note: nil), "민수", true)); srv.nextListing += 1
        w.cloud!.marketDue = true; drain(w)
        let theirs = srv.listings.last!.l.id
        w.sendMarketPick(MarketPick(listing: theirs, give: sq, wish: [], side: 0, at: 0), Date()); drain(w)
        let bid = host.asked.last == "꼬부기는 즐겨찾기한 포켓몬이에요" && host.bodies.last?.contains("민수가 이 제안을 고르면 교환되고") == true
        w.sendPick(TradePick(to: "지은", give: sq), Date()); drain(w)
        let offer = host.asked.last == "꼬부기는 즐겨찾기한 포켓몬이에요" && host.bodies.last?.contains("지은이 받으면 교환되고") == true
        var mine = w.state.box[box(7)]; mine.fav = true
        w.accept(TradeOffer(id: 9, from: "지은", to: key, mon: mon(16, 20), want: mine, at: 0, state: "open"), give: nil, back: .home, Date())
        let accept = host.asked.last == "교환할까요?" && host.bodies.last?.contains("꼬부기는 즐겨찾기한 포켓몬이에요. 교환되면 즐겨찾기는 풀려요.") == true
        srv.listings.append((Listing(id: srv.nextListing, from: key, mon: mine, wish: [], at: 0, bids: 1, mine: true, note: nil), key, true))
        srv.bids.append((Bid(id: srv.nextBid, listing: srv.nextListing, from: "도윤", mon: mon(41, 12), at: 0, state: "open"), "도윤", key)); srv.nextListing += 1; srv.nextBid += 1
        w.cloud!.marketDue = true; drain(w)
        if let l = w.market?.listings.first(where: { $0.mine && $0.mon.uid == sq }) { w.postDo(l, "이 제안으로 교환", 0, Date()) }
        let boardAccept = host.asked.last == "교환할까요?" && host.bodies.last?.contains("즐겨찾기는 풀려요") == true
        let before = host.asked.count
        w.visitSend(ItemOn(item: "민수", pick: box(7), at: 0), Date()); drain(w)
        let noVisitAsk = host.asked.count == before
        host.answer = true
        check(post && bid && offer && accept && boardAccept && noVisitAsk,
              "5.2.2 즐겨찾기: asked before it goes — 글 올리기 (♥ and its item: one window), 제안 (민수가 이 제안을 고르면), 1:1 신청 (지은이 받으면), the 수락s' 교환할까요? (its line: 1:1, the board's), 취소 sends nothing; 맡기기 not asked",
              "\(post) \(bid) \(offer) \(accept) \(boardAccept) \(noVisitAsk) \(host.asked) \(host.bodies.suffix(2))")

        // the worst cases: 중복 12 · 110마리 with a ♥ one, a ♥ form on the LCD — words where they can be read
        let size = SIZE; defer { SIZE = size; textWidthScale = 1 }
        var bad: [String] = []
        for n in [14, 112] {
            var ws = Walk(); ws.companion = mon(3, 55)
            ws.box = (0..<n).map { k in var m = mon(25, 5 + k % 40, ivs: k == 1 ? [31, 10, 10, 10, 10, 10] : [10, 10, 10, 10, 10, 10]); if k == 0 { m.fav = true; m.ivs = [0, 0, 0, 0, 0, 0] }; return m }
            var viv = mon(666, 30); viv.form = 3; viv.fav = true; ws.box.append(viv); ws.box.append(rotom); ws.box[ws.box.count - 1].fav = true
            let v = online(ws)
            for scr in [Screen.box(0, act: 0, confirm: true, detail: true), .box(n, act: nil, confirm: false, detail: true), .box(n + 1, act: nil, confirm: false, detail: true)] {
                v.screen = scr
                for px in [2, 3, 4] as [CGFloat] { SIZE = px; bad += paneOverflow(v).map { "\(n) ×\(Int(px)) \($0)" } }
                SIZE = size
                for k in [1.0, 1.15] { textWidthScale = k; let fb = v.compose(Date()); bad += fb.runs.filter { $0.x < 0 || $0.x + $0.w > 96 }.map { "\(n) LCD \(k) \($0.s)" } + runClashes(fb.runs).map { "\(n) LCD \(k) \($0)" } }
                textWidthScale = 1
            }
            v.screen = .box(0, act: 0, confirm: true, detail: true)
            if v.paneContent(Date()).mon?.dupes != n - 2 { bad.append("\(n): 중복 \(String(describing: v.paneContent(Date()).mon?.dupes))") }
        }
        let fw = favShotsWalker()                                                                  // ♡ / ♥ and three buttons (함께 걷기 · 워커로 · 놓아주기: room on the walker)
        for scr in [Screen.box(0, act: nil, confirm: false, detail: true), .box(2, act: nil, confirm: false, detail: true), .box(-2, act: nil, confirm: false, detail: true), .box(-1, act: nil, confirm: false, detail: true)] {
            fw.screen = scr
            for px in [2, 3, 4] as [CGFloat] { SIZE = px; bad += paneOverflow(fw).map { "page ×\(Int(px)) \($0)" } }
            SIZE = size
        }
        check(bad.isEmpty, "5.2.2 즐겨찾기, the worst cases: a ♥ one's 아니오 · 풀고 놓아주기 · 중복 12 · 110마리, ♡ / ♥ with 함께 걷기 · 워커로 · 놓아주기, a ♥ form on the LCD (설원의 모양, genderless 히트) — no words over words, past the page, cut or across a button (크기 2 · 3 · 4), the LCD inside and clear (15 % wider too)",
              "\(bad.prefix(10))")
    } } }
    return c
}

/// The renders' 즐겨찾기 walker (Shots.swift's fav522_*, WinRender's w522_*): ♥ on the companion, 배루키 (its 진화 dot beside), 꼬부기 (holding
/// 먹다남은음식), 히트로토무, 설원의 모양 비비용 and 피카츄 Lv.11 of three (중복: the best and the ♥ stay); 미뇽 이로치 and 파이리 3V without.
@MainActor func favShotsWalker() -> Walker {
    var r = Seeded(s: 5221), uid = 522_100
    func mon(_ d: Int, _ l: Int, fav: Bool = false, ivs: [Int] = [12, 14, 10, 9, 11, 13]) -> Mon { var m = Mon.wild(d, level: l, &r); m.ivs = ivs; m.shiny = nil; uid += 1; m.uid = uid; m.fav = fav ? true : nil; return m }
    var s = Walk()
    s.companion = mon(3, 55, fav: true); s.caught = [mon(236, 20, fav: true), mon(25, 24)]
    var sq = mon(7, 15, fav: true); sq.item = "먹다남은음식"
    var dratini = mon(147, 25); dratini.shiny = true
    var rotom = mon(479, 40, fav: true); rotom.form = 1
    var viv = mon(666, 30, fav: true); viv.form = 3
    s.box = [sq, dratini, mon(4, 12, ivs: [31, 31, 31, 8, 9, 10]), rotom, viv, mon(25, 9, ivs: [31, 10, 10, 10, 10, 10]), mon(25, 11, fav: true), mon(25, 15), mon(19, 12)]
    s.watts = 2_480; s.owned = Array(1...500); s.seen = s.owned; s.dex()
    return online(s)
}
