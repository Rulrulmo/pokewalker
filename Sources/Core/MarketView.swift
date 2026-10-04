import Foundation
// docs/plans/12 §3.3 (3.5): the 교환 게시판 — everyone's posts (a box Pokémon, up to 3 species wished for: shown only), offers on them (one of
// my box's), the poster picks one and the server swaps both (as a 1:1 trade did: new uids, 어버이, a trade evolution). The board is the
// server's (Cloud.market, /v2/market); the walker shows it, makes posts and offers, and plays what comes back (traded, tradeClosed).

/// The 게시판's pages.
enum MarketStep {
    case board(tab: Int, sel: Int)                                     // 전체 · 내 글 · 내 제안; the pick
    case post(id: Int, sel: Int?)                                      // one in full; mine: the offer picked (its Pokémon on the LCD)
    case pick(MarketPick)                                              // putting one up (mine, then what I wish for) or offering one of mine on a post
}
/// Putting one up (listing nil: give from my box, wish up to 3 species — side 1 is the species seen) or an offer on post `listing` (give).
struct MarketPick: Equatable { var listing: Int? = nil; var give: Int? = nil; var wish: [Int] = []; var side = 0; var at = 0 }

extension Walker {
    static let marketTabs = ["전체", "내 글", "내 제안"], marketDays = 3, marketPosts = 3, marketBids = 5
    var market: MarketReply? { cloud?.market }
    func listing(_ id: Int) -> Listing? { market?.listings.first { $0.id == id } }
    func myBid(on id: Int) -> Bid? { market?.myBids.first { $0.listing == id } }
    func offers(on id: Int) -> [Bid] { market?.offers.filter { $0.listing == id } ?? [] }
    var myPosts: [Listing] { market?.listings.filter(\.mine) ?? [] }
    var offersIn: Int { market?.offers.count ?? 0 }
    /// Box Pokémon of mine already up or offered (the server takes each once).
    var marketUsed: Set<Int> { Set(myPosts.compactMap(\.mon.uid) + (market?.myBids.compactMap(\.mon.uid) ?? [])) }
    static func isMarket(_ a: Act) -> Bool { switch a { case .marketList, .marketUnlist, .marketBid, .marketWithdraw, .marketAccept: true; default: false } }
    func wishText(_ w: [Int]) -> String { w.isEmpty ? "아무거나" : w.map { monNames[$0] }.joined(separator: " · ") }
    func marketLeft(_ at: Int, _ now: Date = Date()) -> String {
        let s = max(0, at + Walker.marketDays * 86400 - Int(now.timeIntervalSince1970))
        return s >= 86400 ? "\(s / 86400)일 남음" : s >= 3600 ? "\(s / 3600)시간 남음" : "\(max(1, s / 60))분 남음"
    }
    /// A tab's posts, as its rows go: 전체 = every post (newest first); 내 글 = mine; 내 제안 = the posts I offered on.
    func boardRows(_ tab: Int) -> [Listing] {
        let all = market?.listings ?? []
        switch tab {
        case 1: return all.filter(\.mine)
        case 2: return (market?.myBids ?? []).compactMap { b in all.first { $0.id == b.listing } }
        default: return all
        }
    }
    var marketNote: String {
        guard let m = market else { return "모두의 게시판" }
        return offersIn > 0 ? "받은 제안 \(offersIn)건" : "글 \(m.listings.count)개 · 내 글 \(myPosts.count)/\(Walker.marketPosts)"
    }

    // MARK: the pane
    func marketPane(_ s: MarketStep, _ now: Date) -> PaneContent {
        switch s {
        case .board(let tab, let sel):
            let rows = boardRows(tab), sel = min(sel, max(0, rows.count - 1)), per = MarketBoardModel.perPage, first = sel / per * per
            let page = rows[min(first, rows.count)..<min(rows.count, first + per)].map { l -> MarketBoardModel.Row in
                let mine = myBid(on: l.id)
                switch tab {
                case 2: return .init(dex: mine?.mon.dex ?? l.mon.dex, shiny: mine?.mon.shiny == true, line: "내 " + (mine.map { monLine($0.mon) } ?? "") + " → " + l.from,
                                     sub: "그 글: " + monLine(l.mon) + " · " + marketLeft(l.at, now), pill: "제안함", tint: 2)
                default:
                    return .init(dex: l.mon.dex, shiny: l.mon.shiny == true, line: (l.mine ? "내 " : josa(l.from, "의", "의") + " ") + monLine(l.mon),
                                 sub: marketLeft(l.at, now) + " · 원해요 " + wishText(l.wish),
                                 pill: l.mine ? (l.bids > 0 ? "제안 \(l.bids)" : "내 글") : mine != nil ? "제안함" : nil, tint: l.mine ? (l.bids > 0 ? 1 : 2) : 2)
                }
            }
            let tabs = ["전체", offersIn > 0 ? "내 글 \(offersIn)" : "내 글", "내 제안"]
            let note = market == nil ? (cloud?.online == false ? "연결되면 볼 수 있어요" : "불러오는 중…")
                : "글 \(market?.listings.count ?? 0)개 · 내 글 \(myPosts.count)/\(Walker.marketPosts) · 내 제안 \(market?.myBids.count ?? 0)/\(Walker.marketBids)"
            let empty = market == nil ? note : ["아직 올라온 글이 없어요", "올린 글이 없어요", "건 제안이 없어요"][tab]
            return PaneContent(board: MarketBoardModel(tabs: tabs, tab: tab, rows: page, sel: sel, first: first, count: rows.count, note: note, empty: empty,
                                                       post: market != nil && myPosts.count < Walker.marketPosts ? "글 올리기 · \(myPosts.count)/\(Walker.marketPosts)" : nil))
        case .post(let id, let sel):
            guard let l = listing(id) else { return marketPane(.board(tab: 0, sel: 0), now) }
            func slot(_ label: String, _ m: Mon) -> TradeSlot { TradeSlot(label: label, dex: m.dex, level: m.level, shiny: m.shiny == true, name: monNames[m.dex], v: m.perfectIVs) }
            let wish = l.wish.first.map { TradeSlot(label: "원하는 포켓몬", dex: $0, name: monNames[$0], more: Array(l.wish.dropFirst())) } ?? TradeSlot(label: "원하는 포켓몬", name: "아무거나")
            if l.mine {
                let os = offers(on: id).map { b in MarketPostModel.Offer(dex: b.mon.dex, shiny: b.mon.shiny == true, line: josa(b.from, "의", "의") + " " + monLine(b.mon),
                                                                         sub: b.mon.natureName + (b.mon.perfectIVs > 0 ? " · \(b.mon.perfectIVs)V" : "") + " · " + ago(max(60, Int(now.timeIntervalSince1970) - b.at))) }
                return PaneContent(post: MarketPostModel(title: "내 글", note: marketLeft(l.at, now), mon: slot("올린 포켓몬", l.mon), wish: wish, body: nil, offers: os,
                                                         sel: sel.flatMap { $0 < os.count ? $0 : nil }, buttons: ["이 제안으로 교환", "글 내리기"], strong: sel != nil && sel! < os.count ? 0 : nil))
            }
            let b = myBid(on: id)
            return PaneContent(post: MarketPostModel(title: josa(l.from, "의", "의") + " 글", note: marketLeft(l.at, now), mon: slot("받을 포켓몬", l.mon), wish: wish, body: monPage(l.mon),
                                                     offers: [], sel: nil, buttons: [b.map { "제안 거두기 · 내 " + monLine($0.mon) } ?? "내 포켓몬으로 제안"], strong: b == nil ? 0 : nil))
        case .pick(let p):
            let list = marketPickList(p), per = TradePickModel.perPage, at = min(p.at, max(0, list.count - 1)), first = at / per * per
            let used = p.side == 0 ? marketUsed : []
            let cells = list[min(first, list.count)..<min(list.count, first + per)].map { m in
                p.side == 1 ? GridModel.Cell(dex: m.dex, look: (state.owned ?? []).contains(m.dex) ? 2 : 1) : GridModel.Cell(dex: m.dex, look: used.contains(m.uid ?? -1) ? 1 : 2, shiny: m.shiny == true, v3: m.perfectIVs >= 3, level: m.level)
            }
            let mine = p.give.flatMap { u in state.box.first { $0.uid == u } }
            func slot(_ label: String, _ m: Mon?, _ none: String) -> TradeSlot {
                m.map { TradeSlot(label: label, dex: $0.dex, level: $0.level, shiny: $0.shiny == true, name: monNames[$0.dex], v: $0.perfectIVs) } ?? TradeSlot(label: label, name: none)
            }
            let onPage = { (k: Int) -> Int? in (first..<min(list.count, first + per)).contains(k) ? k - first : nil }
            let picked = p.side == 0 ? list.firstIndex { $0.uid != nil && $0.uid == p.give }.flatMap(onPage) : nil
            let marks = p.side == 1 ? p.wish.compactMap { d in list.firstIndex { $0.dex == d }.flatMap(onPage) } : []
            if let id = p.listing {
                let l = listing(id)
                return PaneContent(pick: TradePickModel(title: (l.map { josa($0.from, "의", "의") } ?? "") + " 글에 제안", note: l.map { marketLeft($0.at, now) } ?? "",
                                                        mine: slot("내가 줄 포켓몬", mine, "골라 주세요"), theirs: slot("받을 포켓몬", l?.mon, ""), side: 0, fixed: true,
                                                        boxTitle: "내 상자 · \(list.count.formatted())마리", cells: cells, sel: list.isEmpty ? nil : at - first, picked: picked, first: first, count: list.count,
                                                        empty: "상자가 비어 있어요\n워커의 포켓몬은 상자로 보낸 뒤에 제안할 수 있어요", any: nil, go: p.give == nil ? nil : "이 포켓몬으로 제안",
                                                        hint: "내 상자에서 줄 포켓몬을 골라 주세요", bob: Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0, marks: [], base: 8100))
            }
            let wish = p.wish.first.map { TradeSlot(label: "원하는 포켓몬", dex: $0, name: monNames[$0], more: Array(p.wish.dropFirst())) } ?? TradeSlot(label: "원하는 포켓몬", name: "아무거나")
            return PaneContent(pick: TradePickModel(title: "글 올리기", note: "내 글 \(myPosts.count)/\(Walker.marketPosts)", mine: slot("올릴 포켓몬", mine, "골라 주세요"), theirs: wish,
                                                    side: p.side, fixed: false, boxTitle: p.side == 0 ? "내 상자 · \(list.count.formatted())마리" : "원하는 포켓몬 · \(p.wish.count)/3 (본 적 있는 종)",
                                                    cells: cells, sel: list.isEmpty ? nil : at - first, picked: picked, first: first, count: list.count,
                                                    empty: p.side == 0 ? "상자가 비어 있어요\n워커의 포켓몬은 상자로 보낸 뒤에 올릴 수 있어요" : "아직 본 포켓몬이 없어요",
                                                    any: p.side == 1 ? p.wish.isEmpty : nil, go: p.give == nil ? nil : "글 올리기", hint: "내 상자에서 올릴 포켓몬을 골라 주세요",
                                                    bob: Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0, marks: marks, base: 8100))
        }
    }
    /// The grid a pick shows: my box (the 포켓몬 grid's order), or — wishing — the species seen (as Pokémon of that species).
    func marketPickList(_ p: MarketPick) -> [Mon] { p.side == 1 ? seenList.sorted().map { Mon(dex: $0, level: 1, female: false) } : myTradeBox }

    // MARK: the LCD
    func marketLCD(_ fb: inout FB, _ s: MarketStep, _ now: Date) {
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        func head(_ t: String) { fb.text(t, 2, 0); fb.fill(0, 12, 96, 1, 2) }
        func show(_ m: Mon, _ key: String, _ lines: [String]) {
            head((m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)")
            fb.mon(m, half, 0, 2, anim: animT(key, m.dex, now))
            for (k, l) in lines.enumerated() { fb.text(l, 94, 15 + 11 * k, 2, right: true, small: true) }
            if m.perfectIVs > 0 { let w = fb.text("\(m.perfectIVs)V", 94, 15 + 11 * lines.count, m.perfectIVs >= 3 ? 3 : 2, right: true, small: true); if m.perfectIVs >= 3 { fb.draw(vDiamond, 94 - w - 7, 17 + 11 * lines.count, vPal) } }
        }
        switch s {
        case .board(let tab, let sel):
            let rows = boardRows(tab)
            guard let l = rows[safe: min(sel, max(0, rows.count - 1))] else { head("교환 게시판"); fb.text(market == nil ? "불러오는 중..." : "글이 없다", 0, 30, 2, center: true); return }
            show(l.mon, "post \(l.id)", [l.mine ? "내 글" : l.from, l.mine ? "제안 \(l.bids)" : "원해요 \(l.wish.count == 0 ? "-" : "\(l.wish.count)")"])
            fb.text("\(min(sel, rows.count - 1) + 1)/\(rows.count)", 94, 52, 1, right: true, small: true)
        case .post(let id, let sel):
            guard let l = listing(id) else { head("교환 게시판"); fb.text("그 글은 이제 없다", 0, 30, 2, center: true); return }
            let os = offers(on: id)
            if l.mine, let k = sel, let b = os[safe: k] { show(b.mon, "bid \(b.id)", [b.from, "제안 \(k + 1)/\(os.count)"]); fb.text("● 교환", 94, 52, 2, right: true, small: true); return }
            show(l.mon, "post \(l.id)", [l.mine ? "내 글" : l.from, genderRate[l.mon.dex] >= 0 ? (l.mon.female ? "암컷" : "수컷") : ""].filter { !$0.isEmpty })
            fb.text(l.mine ? (os.isEmpty ? "제안 없음" : "◀ ▶ 제안") : myBid(on: id) != nil ? "제안함" : "● 제안", 94, 52, 2, right: true, small: true)
        case .pick(let p):
            let list = marketPickList(p)
            guard let m = list[safe: min(p.at, max(0, list.count - 1))] else { head(p.side == 0 ? "내 상자" : "원하는 포켓몬"); fb.text("비어 있다", 0, 30, 2, center: true); return }
            if p.side == 1 {
                head(String(format: "No.%03d ", m.dex) + monNames[m.dex]); fb.mon(m, half, 0, 2, anim: animT("wish \(m.dex)", m.dex, now))
                fb.text(p.wish.contains(m.dex) ? "원해요 ✓" : "● 고르기", 94, 52, 2, right: true, small: true); return
            }
            let used = marketUsed.contains(m.uid ?? -1), pick = p.give == m.uid
            show(m, "mpick \(m.uid ?? 0)", ["내 상자", "\(min(p.at, list.count - 1) + 1)/\(list.count)"])
            fb.text(used ? "올리거나 제안함" : pick ? "● " + (p.listing == nil ? "올리기" : "제안") : "● 고르기", 94, 52, used ? 1 : 2, right: true, small: true)
        }
    }

    // MARK: what you press
    func marketPress(_ k: Int, _ s: MarketStep, _ now: Date) {
        switch s {
        case .board(let tab, let sel):
            let n = boardRows(tab).count
            if k != 1 { if n > 0 { screen = .market(.board(tab: tab, sel: ((sel + (k == 0 ? -1 : 1)) % n + n) % n)) }; return }
            if let l = boardRows(tab)[safe: sel] { screen = .market(.post(id: l.id, sel: nil)) } else if tab == 1 { startPost(now) }
        case .post(let id, let sel):
            guard let l = listing(id) else { screen = .market(.board(tab: 0, sel: 0)); return }
            if l.mine {
                let n = offers(on: id).count
                if k != 1 { if n > 0 { screen = .market(.post(id: id, sel: ((sel ?? (k == 0 ? 0 : -1)) + (k == 0 ? -1 : 1) + n) % n)) }; return }
                if let s = sel { postDo(l, "이 제안으로 교환", s, now) } else if n > 0 { screen = .market(.post(id: id, sel: 0)) }
            } else if k == 1 { postDo(l, myBid(on: id) == nil ? "내 포켓몬으로 제안" : "제안 거두기", nil, now) }
        case .pick(var p):
            let n = marketPickList(p).count; guard n > 0 else { return }
            if k != 1 { p.at = ((min(p.at, n - 1) + (k == 0 ? -1 : 1)) % n + n) % n; screen = .market(.pick(p)); return }
            marketCell(p, min(p.at, n - 1), now, press: true)
        }
    }
    /// ↑ ↓ (a row, or a row of the grid), page up / down, tab (the board's tabs; putting one up: mine / what I wish for).
    func marketKey(_ k: Key, shift: Bool) -> Bool {
        guard case .market(let s) = screen else { return false }
        lastInput = Date(); host?.redraw(.all)
        switch s {
        case .board(let tab, let sel):
            if k == .tab { screen = .market(.board(tab: (tab + (shift ? 2 : 1)) % 3, sel: 0)); return true }
            let n = boardRows(tab).count
            if let d = [Key.up: -1, .down: 1, .pageUp: -MarketBoardModel.perPage, .pageDown: MarketBoardModel.perPage][k] { if n > 0 { screen = .market(.board(tab: tab, sel: max(0, min(n - 1, sel + d)))) }; return true }
        case .pick(var p):
            if k == .tab { if p.listing == nil { p.side = 1 - p.side; p.at = 0; screen = .market(.pick(p)) }; return true }
            let n = marketPickList(p).count
            if let d = [Key.up: -TradePickModel.columns, .down: TradePickModel.columns, .pageUp: -TradePickModel.perPage, .pageDown: TradePickModel.perPage][k] { if n > 0 { p.at = max(0, min(n - 1, p.at + d)); screen = .market(.pick(p)) }; return true }
        case .post(let id, let sel):
            let n = offers(on: id).count
            if listing(id)?.mine == true, let d = [Key.up: -1, .down: 1][k] { if n > 0 { screen = .market(.post(id: id, sel: max(0, min(n - 1, (sel ?? -1) + d)))) }; return true }
        }
        return false
    }
    /// ↩: a post → its board (the tab it's on); an offer being made → its post; one being put up → 내 글; the board → the menu.
    func marketBack(_ s: MarketStep) -> Screen {
        switch s {
        case .board: return .menu(menuAt("교환"))
        case .post(let id, _):
            let tab = listing(id)?.mine == true ? 1 : myBid(on: id) != nil ? 2 : 0
            return .market(.board(tab: tab, sel: boardRows(tab).firstIndex { $0.id == id } ?? 0))
        case .pick(let p): return p.listing.map { .market(.post(id: $0, sel: nil)) } ?? .market(.board(tab: 1, sel: 0))
        }
    }
    /// A click on the 게시판's pages: 8000 + t a tab, 8010 + i a row of the page (picks; the pick opens), 8020 / 8021 its pages, 8030 글 올리기;
    /// a post's 8110 + i an offer (mine: picks it), 8130 + k its button k; a pick's 8140 / 8141 a side, 8142 아무거나, 8150 + k a cell, 8180 / 8181 its pages, 8190 the button.
    func marketTap(_ code: Int, _ now: Date) {
        guard case .market(let s) = screen else { return }
        switch (s, code) {
        case (.board, 8000...8002): screen = .market(.board(tab: code - 8000, sel: 0))
        case (.board(let tab, let sel), 8010..<8020):
            let at = sel / MarketBoardModel.perPage * MarketBoardModel.perPage + code - 8010
            guard let l = boardRows(tab)[safe: at] else { return }
            screen = at == sel ? .market(.post(id: l.id, sel: nil)) : .market(.board(tab: tab, sel: at))
        case (.board(let tab, let sel), 8020...8021):
            let per = MarketBoardModel.perPage, n = boardRows(tab).count, pages = max(1, (n + per - 1) / per)
            screen = .market(.board(tab: tab, sel: min(max(0, n - 1), ((sel / per + (code == 8020 ? pages - 1 : 1)) % pages) * per)))
        case (.board, 8030): startPost(now)
        case (.post(let id, _), 8110..<8120): if listing(id)?.mine == true, code - 8110 < offers(on: id).count { screen = .market(.post(id: id, sel: code - 8110)) }
        case (.post(let id, let sel), 8130...8131):
            guard let l = listing(id) else { return }
            let label = l.mine ? ["이 제안으로 교환", "글 내리기"][code - 8130] : myBid(on: id) == nil ? "내 포켓몬으로 제안" : "제안 거두기"
            postDo(l, label, sel, now)
        case (.pick(var p), 8140...8141):
            guard p.listing == nil || code == 8140 else { return }
            if p.side != code - 8140 { p.side = code - 8140; p.at = 0 }; screen = .market(.pick(p))
        case (.pick(var p), 8142): p.wish = []; screen = .market(.pick(p))
        case (.pick(let p), 8150..<8180):
            let at = min(p.at, max(0, marketPickList(p).count - 1)) / TradePickModel.perPage * TradePickModel.perPage + code - 8150
            marketCell(p, at, now, press: false)
        case (.pick(var p), 8180...8181):
            let per = TradePickModel.perPage, n = marketPickList(p).count, pages = max(1, (n + per - 1) / per)
            p.at = min(max(0, n - 1), ((min(p.at, max(0, n - 1)) / per + (code == 8180 ? pages - 1 : 1)) % pages) * per); screen = .market(.pick(p))
        case (.pick(let p), 8190): sendMarketPick(p, now)
        default: return
        }
    }
    /// A cell of the grid: mine (what goes up, or what I offer; one already up or offered is said so) or a species wished for (up to 3, a
    /// click on one wished takes it back). Mine picked while putting one up: on to what I wish for. press: ● (on the pick, once ready: it goes).
    func marketCell(_ p0: MarketPick, _ k: Int, _ now: Date, press: Bool) {
        var p = p0
        guard let m = marketPickList(p)[safe: k] else { return }
        p.at = k
        if p.side == 1 {
            if let i = p.wish.firstIndex(of: m.dex) { p.wish.remove(at: i) } else if p.wish.count < 3 { p.wish.append(m.dex) }
            else { screen = .say(["원하는 포켓몬은", "3종까지예요"], next: .market(.pick(p)), since: now); return }
            screen = .market(.pick(p)); return
        }
        guard let u = m.uid else { return }
        if marketUsed.contains(u) { screen = .say(["이미 올리거나", "제안한 포켓몬이에요"], next: .market(.pick(p)), since: now); return }
        if p.give == u { if press { sendMarketPick(p, now) } else { screen = .market(.pick(p)) }; return }
        p.give = u
        if p.listing == nil, p.wish.isEmpty, !press { p.side = 1; p.at = 0 }                           // (a click: on to the wish; ● stays to send)
        screen = .market(.pick(p))
    }

    // MARK: the acts (the server's)
    /// 글 올리기: my box first (3 posts each).
    func startPost(_ now: Date) {
        guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: screen, since: now); return }
        guard myPosts.count < Walker.marketPosts else { screen = .say(["올린 글은", "3개까지예요"], next: screen, since: now); return }
        screen = .market(.pick(MarketPick()))
    }
    /// The pick's button: a post up (to 내 글), or an offer on one (to that post).
    func sendMarketPick(_ p: MarketPick, _ now: Date) {
        guard let g = p.give, holdsAlong(state.box.first { $0.uid == g }, p.listing == nil ? "올리기" : "제안하기") else { return }
        let back = Screen.market(.pick(p))
        if let id = p.listing {
            act(.marketBid(listing: id, give: g), back: back, now) { [weak self] _, now in
                self?.cloud?.marketDue = true
                return .say(["교환을 제안했다!", "글쓴이가 고르면 교환돼요"], next: .market(.post(id: id, sel: nil)), since: now)
            }
        } else {
            act(.marketList(give: g, wish: p.wish), back: back, now) { [weak self] _, now in
                self?.cloud?.marketDue = true
                return .say(["게시판에", "글을 올렸다!"], next: .market(.board(tab: 1, sel: 0)), since: now)
            }
        }
    }
    /// A post's button: 이 제안으로 교환 (asked once: no undo), 글 내리기, 내 포켓몬으로 제안, 제안 거두기.
    func postDo(_ l: Listing, _ what: String, _ sel: Int?, _ now: Date) {
        let back = Screen.market(.post(id: l.id, sel: sel))
        switch what {
        case "이 제안으로 교환":
            guard l.mine, let k = sel, let b = offers(on: l.id)[safe: k] else { return }
            let along = [l.mon.item.map { "내 " + monNames[l.mon.dex] + "의 " + $0 }, b.mon.item.map { josa(b.from, "의", "의") + " " + monNames[b.mon.dex] + "의 " + $0 }].compactMap { $0 }
            guard host?.confirm("교환할까요?", "내 " + monLine(l.mon) + " ↔ " + josa(b.from, "의", "의") + " " + monLine(b.mon) + (along.isEmpty ? "" : "\n지닌 도구도 함께 가요: " + along.joined(separator: ", ")) + "\n다른 제안은 모두 닫히고, 되돌릴 수 없어요.", ok: "교환") ?? true else { return }
            act(.marketAccept(bid: b.id), back: back, now, lines: ["교환 중..."]) { [weak self] _, _ in self?.cloud?.marketDue = true; self?.dropBidNews(l.id); return .home }
        case "글 내리기":
            guard l.mine else { return }
            act(.marketUnlist(id: l.id), back: back, now) { [weak self] _, now in
                self?.cloud?.marketDue = true; self?.dropBidNews(l.id); return .say(["글을 내렸다"], next: .market(.board(tab: 1, sel: 0)), since: now)
            }
        case "내 포켓몬으로 제안":
            guard !l.mine else { return }
            screen = .market(.pick(MarketPick(listing: l.id)))
        default:                                                                                   // 제안 거두기
            guard let b = myBid(on: l.id) else { return }
            act(.marketWithdraw(bid: b.id), back: back, now) { [weak self] _, now in
                self?.cloud?.marketDue = true; return .say(["제안을 거뒀다"], next: .market(.post(id: l.id, sel: nil)), since: now)
            }
        }
    }
    /// Offers on a post now settled (picked, taken down), still waiting for home: not said any more.
    func dropBidNews(_ id: Int) { news.removeAll { if case .marketBid(id, _, _) = $0 { return true }; return false } }
    /// An offer on my post came (news): said, then that post with its offers — unless its withdrawal came with it (that says it).
    func marketNews(_ listing: Int, _ from: String, _ m: Mon, _ now: Date) {
        cloud?.marketDue = true
        if news.contains(where: { if case .tradeClosed(listing, let w, _) = $0 { return w == from }; return false }) { return }
        screen = .say([josa(from, "이", "가") + " 교환을 제안했다!", monLine(m)], next: .market(.post(id: listing, sel: nil)), since: now)
        notify("pet", josa(from, "이", "가") + " 교환을 제안했어요", monLine(m) + " · 메뉴 → 교환 → 내 글")
    }
}
