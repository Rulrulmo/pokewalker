import Foundation
// docs/plans/12 §3 (M2): 교환 — the open offers (팀's 교환 tab), one offer in full (수락 · 거절, or 거두기), making one from a teammate's card
// (their box: what to ask for, or 아무거나; mine: what to give), answering a 아무거나 one (mine to pick), and the trade's show. The offers and a
// teammate's box are the server's (Cloud.trades / Cloud.box: /v2/trades, /v2/box); so is the swap (both saves at once, a trade evolution).

/// 교환's pages.
enum TradeStep {
    case list(Int)                                                     // the open offers, to me first, then mine; the pick
    case offer(id: Int, act: Int?)                                     // one in full; act = the ● row's pick (offerActs)
    case pick(TradePick)                                               // making an offer, or answering a 아무거나 one
}
/// An offer being made (offer nil) or a 아무거나 one answered (offer = its id: theirs is set, mine to pick). Pokémon by uid; side = the box
/// shown (0 mine, 1 theirs), at = the cursor in it.
struct TradePick: Equatable {
    var to: String; var offer: Int? = nil
    var give: Int? = nil, want: Int? = nil
    var side = 1, at = 0
}

extension Walker {
    static let tradeHours = 24
    /// The open offers as the 교환 tab lists them: to me (oldest first), then mine.
    var tradeRows: [TradeOffer] { (cloud?.trades?.incoming ?? []) + (cloud?.trades?.outgoing ?? []) }
    var tradesIn: Int { cloud?.trades?.incoming.count ?? 0 }
    func tradeOffer(_ id: Int) -> TradeOffer? { tradeRows.first { $0.id == id } }
    func mineOffer(_ o: TradeOffer) -> Bool { trainerID(o.from)?.key == trainerID(myName)?.key }
    /// Box Pokémon of mine already in an offer of mine (the server takes each in one at a time).
    var offeredUIDs: Set<Int> { Set((cloud?.trades?.outgoing ?? []).compactMap(\.mon.uid)) }
    /// The 팀 tabs as shown: 교환's with how many wait for me.
    var teamTabLabels: [String] { Array(Walker.teamTabs.dropLast()) + [tradesIn > 0 ? "교환 \(tradesIn)" : "교환"] }
    static func isTrade(_ a: Act) -> Bool { switch a { case .tradeOffer, .tradeAccept, .tradeDecline, .tradeCancel: true; default: false } }
    func monLine(_ m: Mon) -> String { (m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)" }
    /// What's left of an offer's day.
    func tradeLeft(_ o: TradeOffer, _ now: Date = Date()) -> String {
        let left = max(0, o.at + Walker.tradeHours * 3600 - Int(now.timeIntervalSince1970))
        return left >= 3600 ? "\(left / 3600)시간 남음" : "\(max(1, left / 60))분 남음"
    }

    // MARK: the boxes a pick shows
    /// Mine: the box in the 포켓몬 grid's order.
    var myTradeBox: [Mon] { boxOrder.compactMap { state.box[safe: $0] } }
    /// Theirs, by number (nil: not here yet, or the server has none to show).
    func theirBox(_ name: String) -> [Mon]? {
        guard let b = cloud?.box, trainerID(b.name)?.key == trainerID(name)?.key else { return nil }
        return b.box.sorted { ($0.dex, -$0.level, $0.uid ?? 0) < ($1.dex, -$1.level, $1.uid ?? 0) }
    }
    func pickList(_ p: TradePick) -> [Mon] { p.side == 0 ? myTradeBox : theirBox(p.to) ?? [] }
    /// What goes each way: mine (my box) and theirs (their box, or the offer's when answering one).
    func picked(_ p: TradePick) -> (mine: Mon?, theirs: Mon?) {
        let mine = p.give.flatMap { u in state.box.first { $0.uid == u } }
        if let id = p.offer { return (mine, tradeOffer(id)?.mon) }
        return (mine, p.want.flatMap { u in theirBox(p.to)?.first { $0.uid == u } })
    }

    // MARK: the pane
    func tradePane(_ s: TradeStep, _ now: Date) -> PaneContent {
        switch s {
        case .list(let sel):
            let rows = tradeRows, sel = min(sel, max(0, rows.count - 1)), per = TradeListModel.perPage, first = sel / per * per
            let page = rows[min(first, rows.count)..<min(rows.count, first + per)].map { o -> TradeListModel.Row in
                let mine = mineOffer(o)
                return .init(mine: mine, line: mine ? monLine(o.mon) + " → " + o.to : josa(o.from, "의", "의") + " " + monLine(o.mon),
                             sub: "↔ " + (o.want.map(monLine) ?? (mine ? "아무거나" : "내가 골라요")) + " · " + tradeLeft(o, now), dex: o.mon.dex, shiny: o.mon.shiny == true)
            }
            let out = cloud?.trades?.outgoing.count ?? 0
            let note = cloud?.trades == nil ? (cloud?.online == false ? "연결되면 볼 수 있어요" : "불러오는 중…") : "받은 신청 \(tradesIn) · 보낸 신청 \(out)/5"
            return PaneContent(trades: TradeListModel(tabs: teamTabLabels, rows: page, sel: sel, first: first, count: rows.count, note: note))
        case .offer(let id, let act):
            guard let o = tradeOffer(id) else { return tradePane(.list(0), now) }
            let mine = mineOffer(o)
            func slot(_ label: String, _ m: Mon?, _ none: String) -> TradeSlot {
                m.map { TradeSlot(label: label, dex: $0.dex, level: $0.level, shiny: $0.shiny == true, name: monNames[$0.dex], v: $0.perfectIVs) } ?? TradeSlot(label: label, name: none)
            }
            let give = mine ? slot("줄 포켓몬", o.mon, "") : slot("줄 포켓몬", o.want, "내가 골라요")
            let get = mine ? slot("받을 포켓몬", o.want, "아무거나") : slot("받을 포켓몬", o.mon, "")
            let full = mine ? o.want ?? o.mon : o.mon
            let buttons = mine ? ["거두기"] : ["수락", "거절"]
            return PaneContent(offer: TradeOfferModel(title: mine ? o.to + "에게 보낸 신청" : josa(o.from, "의", "의") + " 교환 신청", note: tradeLeft(o, now), give: give, get: get,
                                                      mon: monPage(full), buttons: buttons, sel: act.flatMap { $0 < buttons.count ? $0 : nil }))
        case .pick(let p):
            let list = pickList(p), per = TradePickModel.perPage, at = min(p.at, max(0, list.count - 1)), first = at / per * per
            let offered = p.side == 0 ? offeredUIDs : [], pick = p.side == 0 ? p.give : p.want
            let cells = list[min(first, list.count)..<min(list.count, first + per)].map { m in
                GridModel.Cell(dex: m.dex, look: offered.contains(m.uid ?? -1) ? 1 : 2, shiny: m.shiny == true, v3: m.perfectIVs >= 3, level: m.level)
            }
            let (mine, theirs) = picked(p), answering = p.offer != nil, offer = p.offer.flatMap(tradeOffer)
            func slot(_ label: String, _ m: Mon?, _ none: String) -> TradeSlot {
                m.map { TradeSlot(label: label, dex: $0.dex, level: $0.level, shiny: $0.shiny == true, name: monNames[$0.dex], v: $0.perfectIVs) } ?? TradeSlot(label: label, name: none)
            }
            let theirsLoaded = theirBox(p.to) != nil, gone = cloud?.boxGone.map { trainerID($0)?.key == trainerID(p.to)?.key } == true
            let boxTitle = p.side == 0 ? "내 상자 · \(list.count.formatted())마리" : gone ? josa(p.to, "의", "의") + " 상자를 볼 수 없어요" : !theirsLoaded ? josa(p.to, "의", "의") + " 상자 · 불러오는 중…" : josa(p.to, "의", "의") + " 상자 · \(list.count.formatted())마리"
            let empty = p.side == 0 ? "상자가 비어 있어요\n워커의 포켓몬은 상자로 보낸 뒤에 교환할 수 있어요" : theirsLoaded ? "상자가 비어 있어요" : ""
            let go: String? = p.give == nil ? nil : answering ? "이 포켓몬으로 교환" : p.want == nil ? "교환 신청 (아무거나)" : "교환 신청"
            let hint = p.give == nil ? "내 상자에서 줄 포켓몬을 골라 주세요" : ""
            return PaneContent(pick: TradePickModel(title: answering ? josa(offer?.from ?? p.to, "의", "의") + " 신청에 답하기" : p.to + "에게 교환 신청", note: answering ? offer.map { tradeLeft($0, now) } ?? "" : "보낸 신청 \(cloud?.trades?.outgoing.count ?? 0)/5",
                                                    mine: slot("내가 줄 포켓몬", mine, "골라 주세요"), theirs: slot(answering ? "받을 포켓몬" : "받고 싶은 포켓몬", theirs, "아무거나"),
                                                    side: p.side, fixed: answering, boxTitle: boxTitle, cells: cells, sel: list.isEmpty ? nil : at - first,
                                                    picked: list[min(first, list.count)..<min(list.count, first + per)].firstIndex { $0.uid != nil && $0.uid == pick }.map { $0 - first },
                                                    first: first, count: list.count, empty: empty, any: answering || p.side == 0 ? nil : p.want == nil, go: go, hint: hint,
                                                    bob: Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0))
        }
    }
    /// The ● row on an offer's LCD (the pane's buttons, then 닫기).
    func offerActs(_ o: TradeOffer) -> [String] { mineOffer(o) ? ["거두기", "닫기"] : ["수락", "거절", "닫기"] }

    // MARK: the LCD
    func tradeLCD(_ fb: inout FB, _ s: TradeStep, _ now: Date) {
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        func head(_ t: String) { fb.text(t, 2, 0); fb.fill(0, 12, 96, 1, 2) }
        func vLabel(_ m: Mon, _ y: Int) {
            guard m.perfectIVs > 0 else { return }
            let w = fb.text("\(m.perfectIVs)V", 94, y, m.perfectIVs >= 3 ? 3 : 2, right: true, small: true)
            if m.perfectIVs >= 3 { fb.draw(vDiamond, 94 - w - 7, y + 2, vPal) }
        }
        func show(_ m: Mon, _ key: String, _ lines: [String]) {
            head((m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)")
            fb.mon(m, half, 0, 2, anim: animT(key, m.dex, now))
            for (k, l) in lines.enumerated() { fb.text(l, 94, 15 + 11 * k, 2, right: true, small: true) }
            vLabel(m, 15 + 11 * lines.count)
        }
        switch s {
        case .list(let sel):
            let rows = tradeRows
            guard let o = rows[safe: min(sel, max(0, rows.count - 1))] else { head("교환"); fb.text(cloud?.trades == nil ? "불러오는 중..." : "걸린 교환이 없다", 0, 30, 2, center: true); return }
            show(o.mon, "trade \(o.id)", mineOffer(o) ? ["보냄", "→ " + o.to] : ["받음", o.from])
            fb.text("\(min(sel, rows.count - 1) + 1)/\(rows.count)", 94, 52, 1, right: true, small: true)
        case .offer(let id, let act):
            guard let o = tradeOffer(id) else { head("교환"); fb.text("그 교환은 이제 없다", 0, 30, 2, center: true); return }
            let m = mineOffer(o) ? o.want ?? o.mon : o.mon
            show(m, "trade \(id)", [mineOffer(o) ? (o.want == nil ? "내 것" : "받을 것") : "받을 것", genderRate[m.dex] >= 0 ? (m.female ? "암컷" : "수컷") : ""].filter { !$0.isEmpty })
            if let a = act {                                                                          // the ● row: 수락 · 거절 · 닫기 (or 거두기 · 닫기)
                fb.fill(0, 50, 96, 14, 0); fb.fill(0, 50, 96, 1, 2)
                var x = 1
                for (k, t) in offerActs(o).enumerated() { let w = fb.text(t, x + 1, 52, 3, small: true) + 2; if k == a { fb.invert(x, 52, w, 11) }; x += w + 1 }
            } else { fb.text("● 메뉴", 94, 52, 2, right: true, small: true) }
        case .pick(let p):
            let list = pickList(p)
            guard let m = list[safe: min(p.at, max(0, list.count - 1))] else {
                head(p.side == 0 ? "내 상자" : josa(p.to, "의", "의") + " 상자")
                fb.text(p.side == 1 && theirBox(p.to) == nil ? "불러오는 중..." : "비어 있다", 0, 30, 2, center: true); return
            }
            let pick = (p.side == 0 ? p.give : p.want) == m.uid, offered = p.side == 0 && offeredUIDs.contains(m.uid ?? -1)
            show(m, "pick \(p.side) \(m.uid ?? 0)", [p.side == 0 ? "내 상자" : "상대 상자", "\(min(p.at, list.count - 1) + 1)/\(list.count)"])
            let (mine, _) = picked(p), ready = mine != nil
            fb.text(offered ? "교환에 걸려 있다" : pick ? (ready ? "● 신청" : "고름 ✓") : "● 고르기", 94, 52, offered ? 1 : 2, right: true, small: true)
        }
    }

    // MARK: what you press
    /// ◀ ▶ ● on 교환's pages: the list's pick / its offer; an offer's ● row; a box's cursor / its pick (● on the pick, once both are there: send).
    func tradePress(_ k: Int, _ s: TradeStep, _ now: Date) {
        switch s {
        case .list(let sel):
            let n = tradeRows.count; guard n > 0 else { return }
            if k != 1 { screen = .trade(.list(((sel + (k == 0 ? -1 : 1)) % n + n) % n)); return }
            if let o = tradeRows[safe: sel] { screen = .trade(.offer(id: o.id, act: nil)) }
        case .offer(let id, let act):
            guard let o = tradeOffer(id) else { screen = .trade(.list(0)); return }
            let acts = offerActs(o), n = acts.count
            if k != 1 { let cur = act ?? (k == 0 ? 0 : n - 1); screen = .trade(.offer(id: id, act: (cur + (k == 0 ? -1 : 1) + n) % n)); return }
            guard let a = act else { screen = .trade(.offer(id: id, act: 0)); return }
            offerDo(o, acts[a], now)
        case .pick(var p):
            let n = pickList(p).count; guard n > 0 else { return }
            if k != 1 { p.at = ((min(p.at, n - 1) + (k == 0 ? -1 : 1)) % n + n) % n; screen = .trade(.pick(p)); return }
            pickCell(p, min(p.at, n - 1), now, press: true)
        }
    }
    /// ↑ ↓ (a row of the box, or of the list), page up / down, tab (the other box; on the list: 팀's tabs).
    func tradeKey(_ k: Key, shift: Bool) -> Bool {
        guard case .trade(let s) = screen else { return false }
        lastInput = Date(); host?.redraw(.all)
        switch s {
        case .list(let sel):
            let n = tradeRows.count
            if k == .tab { screen = .team(sel: 0, tab: shift ? 3 : 0, card: false); return true }
            if let d = [Key.up: -1, .down: 1, .pageUp: -TradeListModel.perPage, .pageDown: TradeListModel.perPage][k] { if n > 0 { screen = .trade(.list(max(0, min(n - 1, sel + d)))) }; return true }
        case .pick(var p):
            let n = pickList(p).count
            if k == .tab { if p.offer == nil { p.side = 1 - p.side; p.at = 0; screen = .trade(.pick(p)) }; return true }
            if let d = [Key.up: -TradePickModel.columns, .down: TradePickModel.columns, .pageUp: -TradePickModel.perPage, .pageDown: TradePickModel.perPage][k] { if n > 0 { p.at = max(0, min(n - 1, p.at + d)); screen = .trade(.pick(p)) }; return true }
        case .offer: break
        }
        return false
    }
    /// ↩: an offer → the list; making one → the teammate's card; answering → its offer; the list → the menu.
    func tradeBack(_ s: TradeStep) -> Screen {
        switch s {
        case .list: return .menu(menuAt("팀"))
        case .offer(let id, _): return .trade(.list(tradeRows.firstIndex { $0.id == id } ?? 0))
        case .pick(let p):
            if let id = p.offer { return .trade(.offer(id: id, act: nil)) }
            let i = teamRows(0).firstIndex { trainerID($0.card.name)?.key == trainerID(p.to)?.key }
            return i.map { .team(sel: $0, tab: 0, card: true) } ?? .team(sel: 0, tab: 0, card: false)
        }
    }
    /// A click on 교환's pages: 6004 the 교환 tab (from 팀's), 6110 + i a row of the list's page, 6120 / 6121 its pages; an offer's 6130 수락 ·
    /// 6131 거절 · 6132 거두기; a pick's 6140 / 6141 a side (mine / theirs), 6142 아무거나, 6150 + k a cell of the page, 6180 / 6181 its pages, 6190 the button.
    func tradeTap(_ code: Int, _ now: Date) {
        guard case .trade(let s) = screen else { return }
        switch (s, code) {
        case (.list, 6000...6003): screen = .team(sel: 0, tab: code - 6000, card: false)
        case (.list(let sel), 6110..<6120):
            let at = sel / TradeListModel.perPage * TradeListModel.perPage + code - 6110
            guard let o = tradeRows[safe: at] else { return }
            screen = at == sel ? .trade(.offer(id: o.id, act: nil)) : .trade(.list(at))                // the first click picks, a click on the pick opens it
        case (.list(let sel), 6120...6121):
            let per = TradeListModel.perPage, n = tradeRows.count, pages = max(1, (n + per - 1) / per)
            screen = .trade(.list(min(max(0, n - 1), ((sel / per + (code == 6120 ? pages - 1 : 1)) % pages) * per)))
        case (.offer(let id, _), 6130...6132):
            guard let o = tradeOffer(id) else { return }
            offerDo(o, ["수락", "거절", "거두기"][code - 6130], now)
        case (.pick(var p), 6140...6141):
            guard p.offer == nil || code == 6140 else { return }
            if p.side != code - 6140 { p.side = code - 6140; p.at = 0 }; screen = .trade(.pick(p))
        case (.pick(var p), 6142): p.want = nil; screen = .trade(.pick(p))
        case (.pick(let p), 6150..<6180):
            let at = min(p.at, max(0, pickList(p).count - 1)) / TradePickModel.perPage * TradePickModel.perPage + code - 6150
            pickCell(p, at, now, press: false)
        case (.pick(var p), 6180...6181):
            let per = TradePickModel.perPage, n = pickList(p).count, pages = max(1, (n + per - 1) / per)
            p.at = min(max(0, n - 1), ((min(p.at, max(0, n - 1)) / per + (code == 6180 ? pages - 1 : 1)) % pages) * per); screen = .trade(.pick(p))
        case (.pick(let p), 6190): sendPick(p, now)
        default: return
        }
    }
    /// A Pokémon of the box shown, picked for its side (theirs picked first, mine still to go: my box next). press: ● (on the pick, once
    /// both are there: it goes); a click only picks.
    func pickCell(_ p0: TradePick, _ k: Int, _ now: Date, press: Bool) {
        var p = p0
        guard let m = pickList(p)[safe: k], let u = m.uid else { return }
        p.at = k
        if p.side == 0, offeredUIDs.contains(u) { screen = .say(["이미 교환에", "걸어 둔 포켓몬이에요"], next: .trade(.pick(p)), since: now); return }
        if (p.side == 0 ? p.give : p.want) == u { if press, p.give != nil { sendPick(p, now) } else { screen = .trade(.pick(p)) }; return }
        if p.side == 0 { p.give = u } else { p.want = u; if p.give == nil { p.side = 0; p.at = 0 } }
        screen = .trade(.pick(p))
    }

    // MARK: the acts (the server's: Core/Act.swift's act())
    /// 교환 신청 from a teammate's card: their box asked for; theirs first (or 아무거나), then mine.
    func startTrade(_ name: String, _ now: Date = Date()) {
        guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: screen, since: now); return }
        guard trainerID(name)?.key != trainerID(myName)?.key else { return }
        c.wantBox(name); c.tradesDue = true
        screen = .trade(.pick(TradePick(to: name)))
    }
    /// The pick's button: an offer made (to the list, where it waits), or a 아무거나 one answered (asked first: there's no undo).
    func sendPick(_ p: TradePick, _ now: Date) {
        guard let g = p.give else { return }
        if let id = p.offer { if let o = tradeOffer(id) { accept(o, give: g, back: .trade(.pick(p)), now) }; return }
        act(.tradeOffer(to: p.to, give: g, want: p.want), back: .trade(.pick(p)), now) { [weak self] _, now in
            self?.cloud?.tradesDue = true
            return .say([p.to + "에게", "교환을 신청했다!"], next: .trade(.list((self?.cloud?.trades?.incoming.count ?? 0))), since: now)
        }
    }
    /// An offer's button: 수락 (a 아무거나 one: mine to pick first), 거절, 거두기, 닫기.
    func offerDo(_ o: TradeOffer, _ what: String, _ now: Date) {
        let back = Screen.trade(.offer(id: o.id, act: nil))
        switch what {
        case "수락":
            guard !mineOffer(o) else { return }
            if o.want == nil { screen = .trade(.pick(TradePick(to: o.from, offer: o.id, side: 0))) } else { accept(o, give: nil, back: back, now) }
        case "거절", "거두기":
            let mine = what == "거두기"; guard mine == mineOffer(o) else { return }
            act(mine ? .tradeCancel(id: o.id) : .tradeDecline(id: o.id), back: back, now) { [weak self] _, now in
                self?.cloud?.forgetOffer(o.id); self?.cloud?.tradesDue = true
                return .say(mine ? ["교환 신청을", "거뒀다"] : [josa(o.from, "의", "의") + " 신청을", "거절했다"], next: .trade(.list(0)), since: now)
            }
        default: screen = .trade(.list(tradeRows.firstIndex { $0.id == o.id } ?? 0))
        }
    }
    /// 수락: asked once (it can't be undone), then the server swaps both; its news (traded, an evolution) play at home.
    func accept(_ o: TradeOffer, give: Int?, back: Screen, _ now: Date) {
        let mine = o.want ?? give.flatMap { u in state.box.first { $0.uid == u } }
        let body = josa(o.from, "의", "의") + " " + monLine(o.mon) + " ↔ 내 " + (mine.map(monLine) ?? "포켓몬") + "\n교환하면 되돌릴 수 없어요."
        guard host?.confirm("교환할까요?", body, ok: "교환") ?? true else { return }
        act(.tradeAccept(id: o.id, give: o.want == nil ? give : nil), back: back, now, lines: ["교환 중..."]) { [weak self] _, _ in
            self?.cloud?.forgetOffer(o.id); self?.cloud?.tradesDue = true
            return .home
        }
    }

    // MARK: home: the news
    func tradeNews(_ n: News, _ now: Date) {
        cloud?.tradesDue = true
        switch n {
        case .tradeOffer(let id, let from, let m, let want):
            if news.contains(where: { if case .tradeClosed(id, _, _) = $0 { return true }; return false }) { return }   // taken back already: its close says so
            cloud?.noteOffer(TradeOffer(id: id, from: from, to: myName, mon: m, want: want, at: Int(now.timeIntervalSince1970), state: "open"))
            screen = .say([josa(from, "이", "가") + " 교환을 신청했다!", monLine(m)], next: .trade(.offer(id: id, act: nil)), since: now)
            notify("pet", josa(from, "이", "가") + " 교환을 신청했어요", monLine(m) + " ↔ " + (want.map(monLine) ?? "아무거나") + " · 메뉴 → 팀 → 교환")
        case .traded(let id, let with, let gave, let got):
            cloud?.forgetOffer(id)
            var shown = got
            for k in news.indices { if case .evolve(let u, let from, _, _) = news[k], u == got.uid { shown.dex = from; break } }   // it evolves here: the show brings the old form
            screen = .traded(gave: gave, got: shown, with: with, since: now)
            notify("pet", josa(with, "과", "와") + "의 교환 성립!", monNames[gave.dex] + " → " + monLine(got))
        case .tradeClosed(let id, let with, let why):
            cloud?.forgetOffer(id)
            screen = .say([josa(with, "과", "와") + "의 교환", why], next: .home, since: now)
        default: break
        }
    }
    /// The trade's show (6 s): ours goes, theirs comes; the LCD's line says which.
    func tradedLCD(_ fb: inout FB, _ gave: Mon, _ got: Mon, _ since: Date, _ now: Date) {
        let u = now.timeIntervalSince(since)
        fb.tradeFX(gave, got, u, bob: Int(now.timeIntervalSinceReferenceDate * 2) % 2)
        fb.fill(0, 50, 96, 1, 2)
        fb.text(u < 1.9 ? josa(monNames[gave.dex], "을", "를") + " 보냈다" : u < 3.4 ? "교환 중..." : josa(monNames[got.dex], "이", "가") + " 왔다!", 2, 52)
    }
}

extension FB {
    /// 교환 (6 s), a link trade cut short: ours on the stage, red into its ball, the ball off to the right; theirs' ball in from the left, a
    /// white-out, it comes out with sparkles. The message row is the caller's.
    mutating func tradeFX(_ gave: Mon, _ got: Mon, _ u: Double, bob: Int) {
        pic("w.dark|stage", 96, 50, alpha: min(1, u / 0.7), behind: true) { panelPic(192, 100, rgb(18, 22, 42)) }
        let mid = { (m: Mon) in 98 - (80 - spriteTop(m.dex)) / 2 }
        if u < 1.4 { showMon(gave, bob: bob) }
        else if u < 1.9 { let k = (u - 1.4) / 0.5; showMon(gave, scale: 1 - 0.85 * k, tint: rgb(238, 84, 72)) }
        if (1.75..<2.6).contains(u) { let k = max(0, (u - 1.9) / 0.7); pic("ball 0 0", 96 + Int(k * 130), 76 - Int(sin(k * .pi) * 34)) { ballPic(0, 0) } }
        if (2.6..<3.35).contains(u) { let k = (u - 2.6) / 0.75; pic("ball 0 0", -34 + Int(k * 130), 76 - Int(sin(k * .pi) * 34)) { ballPic(0, 0) } }
        if u >= 3.35 {
            showMon(got, scale: min(1, 0.15 + (u - 3.35) / 0.35), bob: u > 4.2 ? bob : 0, anim: u > 4.2 ? u - 4.2 : nil)
            if u > 3.5 { sparkles(u - 3.5, 96, mid(got), Double(98 - mid(got)) + 14, n: 8, big: true) }
        }
        whiteOut(u < 3.2 ? 0 : u < 3.35 ? (u - 3.2) / 0.15 : u < 3.6 ? 1 - (u - 3.35) / 0.25 : 0)
    }
}
