import Foundation
// 3.9 (docs/plans/15 §2, §6 A · D): the 우편함 — gifts and notices from the server: the list, one mail, a pick (14연승's held item, 100연승's legend).

/// Where the 우편함 is: the list (sel = a row of the server's order), one mail, or a pick of one of its gifts (at = the one under the cursor;
/// ask = 받을까요? up, true = 예 highlighted).
enum MailStep: Equatable {
    case list(sel: Int)
    case open(id: Int)
    case pick(id: Int, at: Int, ask: Bool?)
}

extension Walker {
    var mails: [Mail] { cloud?.mail?.mails ?? [] }
    func mail(_ id: Int) -> Mail? { mails.first { $0.id == id } }
    /// A mail with a gift still to take.
    static func claimable(_ m: Mail) -> Bool { !m.claimed && !m.gifts.isEmpty }
    /// Not opened yet (here or before: the server's read, or opened since its last list).
    func unread(_ m: Mail) -> Bool { !m.read && !mailOpened.contains(m.id) }
    /// 우편함's red dot: a mail not opened yet, or a gift not yet taken.
    var mailDot: Bool { cloud?.mail.map { r in r.mails.contains { unread($0) || Walker.claimable($0) } } ?? false }
    /// 우편함's line on the menu.
    var mailNote: String {
        guard cloud?.mail != nil else { return "보상 · 공지" }
        let take = mails.filter(Walker.claimable).count, new = mails.filter(unread).count
        return take > 0 ? "받을 우편 \(take)통" : new > 0 ? "새 우편 \(new)통" : mails.isEmpty ? "보상 · 공지" : "우편 \(mails.count)통"
    }
    func openMail(_ now: Date) {
        guard let c = cloud, c.online else { screen = .say(Walker.offlineLines, next: menuFor("우편함"), since: now); return }
        c.mailDue = true; screen = .mail(.list(sel: 0))
    }
    /// One opened: read (the server hears with the next list).
    func openOne(_ id: Int) { mailOpened.insert(id); cloud?.mailRead.insert(id); screen = .mail(.open(id: id)) }
    /// news mailNew: no screen — the 우편함's red dot (the list read now), and a notification.
    func mailNews(_ title: String) { cloud?.mailDue = true; notify("mail", "우편이 왔어요", title) }

    // MARK: words for gifts
    func giftName(_ g: Gift) -> String {
        switch g {
        case .mon(let m, _): return (m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)"
        case .items(let n, let k): return k > 1 ? "\(n) ×\(k)" : n
        case .bp(let n): return "\(n.formatted())BP"
        case .watts(let n): return "\(n.formatted())W"
        case .title(let n): return "칭호 「\(n)」"
        case .deco(let k): return Walker.decoName(k)
        case .pickItem: return "지닌 도구 1개 고르기"
        case .pickLegend(_, let lv, let shiny): return (shiny ? "이로치 " : "") + "전설 1마리 고르기 · Lv.\(lv)"
        }
    }
    /// A row's chip: what's in it, short.
    func giftChip(_ g: Gift) -> String {
        switch g {
        case .mon(let m, _): return "Lv.\(m.level)"
        case .items(let n, let k): return k > 1 ? "×\(k)" : String(n.prefix(5))
        case .bp(let n): return "\(n)BP"
        case .watts(let n): return "\(n)W"
        case .title: return "칭호"
        case .deco(let k): return k == "gold" ? "금장식" : "은장식"
        case .pickItem, .pickLegend: return "고르기"
        }
    }
    /// 3.9 (15 §6 E): a streak reward under its number on the lobby's strip.
    static func rewardShort(_ gs: [Gift]) -> String {
        switch gs.first {
        case .items(let n, let k)?: return n == "이상한사탕" ? "사탕×\(k)" : n == "은색병뚜껑" ? "은뚜껑" : n == "금색병뚜껑" ? "금뚜껑" : n
        case .pickItem?: return "도구"
        case .bp(let n)?: return "\(n)BP"
        case .deco(let k)?: return k == "gold" ? "금장식" : "은장식"
        case .title?: return "전설"
        default: return ""
        }
    }
    /// A streak reward mailed already (the save's towerRewards; a server before 3.9: whatever the best streak passed).
    func towerGot(_ wins: Int) -> Bool { state.towerRewards.map { $0.contains(wins) } ?? false }
    var towerNextReward: (wins: Int, gifts: [Gift])? { Tower.rewards.first { !towerGot($0.wins) } }
    static func decoName(_ k: String) -> String { k == "gold" ? "트레이너 카드 금장식" : "트레이너 카드 은장식" }
    /// What a gift's 받기 says.
    func giftLine(_ g: Gift) -> String {
        switch g {
        case .mon(let m, _): return josa(monNames[m.dex], "을", "를") + " 받았다!"
        case .title(let n): return "칭호 「\(n)」을 받았다!"
        default: return josa(giftName(g), "을", "를") + " 받았다!"
        }
    }
    func mailFrom(_ m: Mail, _ now: Date) -> String { m.from + " · " + ago(max(60, Int(now.timeIntervalSince1970) - m.at)) }

    // MARK: the pane
    func mailPane(_ s: MailStep, _ now: Date) -> PaneContent {
        switch s {
        case .list(let sel):
            let ms = mails, sel = min(sel, max(0, ms.count - 1)), per = MailListModel.perPage, first = sel / per * per
            let rows = ms[min(first, ms.count)..<min(ms.count, first + per)].map { m -> MailListModel.Row in
                let mon = m.gifts.lazy.compactMap { g -> Mon? in if case .mon(let x, _) = g { return x }; return nil }.first
                let icon: MailListModel.Icon = mon.map { .mon(dex: $0.dex, shiny: $0.shiny == true) } ?? (m.gifts.isEmpty ? .letter : .gift)
                return .init(icon: icon, title: m.title, sub: mailFrom(m, now), chips: m.claimed ? ["받음"] : Array(m.gifts.prefix(2).map(giftChip)), unread: unread(m) || Walker.claimable(m), done: m.claimed || (m.gifts.isEmpty && !unread(m)))
            }
            let take = ms.filter { Walker.claimable($0) && !$0.picks }.count
            let note = cloud?.mail == nil ? (cloud?.online == false ? "연결되면 볼 수 있어요" : "불러오는 중…") : "받을 우편 \(ms.filter(Walker.claimable).count)통 · 전체 \(ms.count)통"
            return PaneContent(mailList: MailListModel(rows: rows, sel: ms.isEmpty ? nil : sel, first: first, count: ms.count, note: note,
                                                       all: take > 0 ? "모두 받기 · \(take)통" : nil, empty: cloud?.mail == nil ? note : "우편이 없어요"))
        case .open(let id):
            guard let m = mail(id) else { return mailPane(.list(sel: 0), now) }
            let gifts = m.gifts.map { g -> MailOpenModel.Gift in
                switch g {
                case .mon(let x, let steps): return .init(icon: .mon(dex: x.dex, shiny: x.shiny == true), name: giftName(g), note: [x.natureName, x.perfectIVs > 0 ? "\(x.perfectIVs)V" : nil, x.item.map { $0 + " 지님" }, steps.map { "키운 걸음 \($0.formatted())" }].compactMap { $0 }.joined(separator: " · "))
                case .deco(let k): return .init(icon: .medal(gold: k == "gold"), name: giftName(g), note: "트레이너 카드 · 친구 목록에 보여요")
                case .title: return .init(icon: .medal(gold: true), name: giftName(g), note: "트레이너 카드에 보여요")
                case .pickItem(let xs): return .init(icon: .gem, name: giftName(g), note: "\(xs.count)가지 중에서")
                case .pickLegend(let xs, _, _): return .init(icon: .gift, name: giftName(g), note: "\(xs.count)종 중에서 · 4V")
                default: return .init(icon: .gem, name: giftName(g), note: "")
                }
            }
            let button: String? = m.gifts.isEmpty ? nil : m.claimed ? nil : m.picks ? "고르기" : "받기"
            return PaneContent(mailOpen: MailOpenModel(title: m.title, from: mailFrom(m, now), body: m.body ?? "", gifts: gifts, button: button,
                                                       off: m.gifts.isEmpty ? "공지 · 받을 것이 없는 우편이에요" : "받았어요"))
        case .pick(let id, let at, let ask):
            guard let m = mail(id), let g = m.gifts.first(where: { if case .pickItem = $0 { return true }; if case .pickLegend = $0 { return true }; return false }) else { return mailPane(.list(sel: 0), now) }
            switch g {
            case .pickItem(let xs):
                return PaneContent(mailPick: MailPickModel(title: "지닌 도구 고르기", note: "하나만 받을 수 있어요", rows: xs.map { .init(name: $0, note: Held.summary($0) ?? "") }, cells: [], sel: at, first: 0, count: xs.count,
                                                           go: xs[safe: at].map { "\($0) 받기" }, ask: ask))
            case .pickLegend(let xs, let lv, let shiny):
                let per = MailPickModel.perPage, at = min(at, max(0, xs.count - 1)), first = at / per * per
                let cells = xs[min(first, xs.count)..<min(xs.count, first + per)].map { GridModel.Cell(dex: $0, look: 2, shiny: shiny, level: lv) }   // owned or not, the same (15 ④)
                return PaneContent(mailPick: MailPickModel(title: (shiny ? "이로치 " : "") + "전설 고르기", note: "Lv.\(lv) · 4V · 한 마리만", rows: [], cells: cells, sel: at, first: first, count: xs.count,
                                                           go: xs[safe: at].map { monNames[$0] + " 받기" }, ask: ask))
            default: return mailPane(.list(sel: 0), now)
            }
        }
    }

    // MARK: the LCD
    func mailLCD(_ fb: inout FB, _ s: MailStep, _ now: Date) {
        let half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        func head(_ t: String) { fb.text(t, 2, 0); fb.fill(0, 12, 96, 1, 2) }
        func gift(_ g: Gift?, _ key: String, _ m: Mail) {
            switch g {
            case .mon(let x, _)?:
                head((x.shiny == true ? "★" : "") + monNames[x.dex] + " Lv.\(x.level)"); fb.mon(x, half, 0, 2, anim: animT(key, x.dex, now))
                fb.text(m.from, 94, 15, 2, right: true, small: true)
            case .deco(let k)?: head(m.title); fb.draw(medalArt, 8, 18, k == "gold" ? goldPal : silverPal, scale: 3); fb.text(k == "gold" ? "금장식" : "은장식", 94, 26, 3, right: true)
            case .title(let n)?: head(m.title); fb.draw(medalArt, 8, 18, goldPal, scale: 3); fb.text(n, 94, 26, 3, right: true, small: true)
            case let g?: head(m.title); fb.draw(giftArt, 8, 18, giftPal, scale: 3); fb.text(giftName(g), 94, 26, 3, right: true, small: true)
            case nil: head(m.title); fb.draw(letterArt, 8, 22, letterPal, scale: 3); fb.text(m.from, 94, 26, 2, right: true, small: true)
            }
        }
        switch s {
        case .list(let sel):
            guard let m = mails[safe: min(sel, max(0, mails.count - 1))] else { head("우편함"); fb.text(cloud?.mail == nil ? "불러오는 중..." : "우편이 없다", 0, 30, 2, center: true); return }
            gift(m.gifts.first, "mail \(m.id)", m)
            fb.text(m.claimed ? "받음" : "● 열기", 94, 52, 2, right: true, small: true)
        case .open(let id):
            guard let m = mail(id) else { head("우편함"); return }
            gift(m.gifts.first, "mail \(m.id)", m)
            fb.text(m.gifts.isEmpty ? "공지" : m.claimed ? "받음" : m.picks ? "● 고르기" : "● 받기", 94, 52, 2, right: true, small: true)
        case .pick(let id, let at, let ask):
            guard let m = mail(id) else { head("우편함"); return }
            for g in m.gifts {
                switch g {
                case .pickItem(let xs):
                    guard let n = xs[safe: at] else { continue }
                    head(n); fb.draw(gem, 2, 17, gemPal, scale: 2)
                    for (k, l) in wrapDots(Held.summary(n) ?? "", 80).prefix(3).enumerated() { fb.text(l, 16, 16 + 11 * k, 3, small: true) }
                case .pickLegend(let xs, let lv, let shiny):
                    guard let d = xs[safe: min(at, xs.count - 1)] else { continue }
                    let x = Mon(dex: d, level: lv, female: false, shiny: shiny ? true : nil)
                    head((shiny ? "★" : "") + monNames[d] + " Lv.\(lv)"); fb.mon(x, half, 0, 2, anim: animT("legend \(d)", d, now))
                    fb.text(monTypes[d].map { typeKo[$0] ?? $0 }.joined(separator: "·"), 94, 15, 2, right: true, small: true)
                    if (state.owned ?? []).contains(d) { fb.text("잡음", 94, 26, 2, right: true, small: true) }
                default: continue
                }
            }
            if let yes = ask {
                fb.fill(0, 50, 96, 14, 0); fb.fill(0, 50, 96, 1, 2)
                fb.text("받을까요?", 2, 52, 3, small: true)
                for (k, o) in ["아니오", "예"].enumerated() { let x = 48 + 24 * k, w = fb.text(o, x + 1, 52, 3, small: true); if (k == 1) == yes { fb.invert(x, 52, w + 2, 12) } }
            } else { fb.text("● 고르기", 94, 52, 2, right: true, small: true) }
        }
    }
    /// A line cut to fit `w` dots of the LCD's small font, by words.
    func wrapDots(_ s: String, _ w: Int) -> [String] {
        var lines: [String] = [], cur = ""
        for word in s.split(separator: " ") {
            let t = cur.isEmpty ? String(word) : cur + " " + word
            if textDots(t, small: true).first.map({ $0.count }) ?? 0 > w, !cur.isEmpty { lines.append(cur); cur = String(word) } else { cur = t }
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    // MARK: what you press
    func mailPress(_ k: Int, _ s: MailStep, _ now: Date) {
        switch s {
        case .list(let sel):
            let n = mails.count
            if k != 1 { if n > 0 { screen = .mail(.list(sel: ((sel + (k == 0 ? -1 : 1)) % n + n) % n)) }; return }
            if let m = mails[safe: sel] { openOne(m.id) }
        case .open(let id):
            guard let m = mail(id) else { screen = .mail(.list(sel: 0)); return }
            if k != 1 {                                                                           // ◀ ▶ the next mail, as the 도감's entries go
                let ms = mails, i = ms.firstIndex { $0.id == id } ?? 0, n = ms.count
                if n > 1 { openOne(ms[((i + (k == 0 ? -1 : 1)) % n + n) % n].id) }; return
            }
            mailTake(m, now)
        case .pick(let id, let at, let ask):
            guard let m = mail(id), let n = pickCount(m) else { screen = .mail(.list(sel: 0)); return }
            if let yes = ask {
                if k != 1 { screen = .mail(.pick(id: id, at: at, ask: !yes)); return }             // ◀ ▶ 아니오 / 예
                if yes { mailClaim(m, pick: at, now) } else { screen = .mail(.pick(id: id, at: at, ask: nil)) }
                return
            }
            if k != 1 { screen = .mail(.pick(id: id, at: ((at + (k == 0 ? -1 : 1)) % n + n) % n, ask: nil)); return }
            screen = .mail(.pick(id: id, at: at, ask: false))                                     // 아니오 first
        }
    }
    func pickCount(_ m: Mail) -> Int? {
        for g in m.gifts { if case .pickItem(let xs) = g { return xs.count }; if case .pickLegend(let xs, _, _) = g { return xs.count } }
        return nil
    }
    /// 받기 on a mail: a pick first; else everything in it.
    func mailTake(_ m: Mail, _ now: Date) {
        guard Walker.claimable(m) else { return }
        if m.picks { screen = .mail(.pick(id: m.id, at: 0, ask: nil)); return }
        mailClaim(m, pick: nil, now)
    }
    func mailClaim(_ m: Mail, pick: Int?, _ now: Date) {
        let back = Screen.mail(.open(id: m.id))
        act(.mailClaim(id: m.id, pick: pick), back: back, now) { [weak self] o, now in
            guard let self else { return nil }
            cloud?.mailDue = true
            var lines = m.gifts.compactMap { g -> String? in
                switch g {
                case .pickItem(let xs): return xs[safe: pick ?? -1].map { josa($0, "을", "를") + " 받았다!" }
                case .pickLegend(let xs, _, _): return xs[safe: pick ?? -1].map { josa(monNames[$0], "을", "를") + " 받았다!" }
                default: return giftLine(g)
                }
            }
            if lines.count > 2 { lines = ["우편의 선물을", "모두 받았다!"] }
            let mon = o.mon != nil || m.gifts.contains { if case .mon = $0 { return true }; if case .pickLegend = $0 { return true }; return false }
            if mon, lines.count == 1 { lines.append("상자로 보냈다") }
            let leaves = o.news.contains { if case .evolve = $0 { return true }; return false }        // a trade evolution: home shows it
            return .say(lines, next: leaves ? .home : back, since: now)
        }
    }
    /// 모두 받기: every mail without a pick.
    func mailClaimAll(_ now: Date) {
        let n = mails.filter { Walker.claimable($0) && !$0.picks }.count
        guard n > 0 else { return }
        let back = Screen.mail(.list(sel: 0))
        act(.mailClaimAll, back: back, now) { [weak self] o, now in
            guard let self else { return nil }
            cloud?.mailDue = true
            let leaves = o.news.contains { if case .evolve = $0 { return true }; return false }
            return .say(["우편 \(n)통을", "모두 받았다!"], next: leaves ? .home : back, since: now)
        }
    }
    /// ↑ ↓ a row (the list, a pick's list), page up / down, a grid's row.
    func mailKey(_ k: Key) -> Bool {
        guard case .mail(let s) = screen else { return false }
        switch s {
        case .list(let sel):
            guard let d = [Key.up: -1, .down: 1, .pageUp: -MailListModel.perPage, .pageDown: MailListModel.perPage][k] else { return false }
            let n = mails.count; if n > 0 { screen = .mail(.list(sel: max(0, min(n - 1, sel + d)))) }
        case .pick(let id, let at, nil):
            guard let m = mail(id), let n = pickCount(m) else { return false }
            let legend = m.gifts.contains { if case .pickLegend = $0 { return true }; return false }
            let step = legend ? [Key.up: -6, .down: 6, .pageUp: -MailPickModel.perPage, .pageDown: MailPickModel.perPage] : [Key.up: -1, .down: 1]
            guard let d = step[k] else { return false }
            screen = .mail(.pick(id: id, at: max(0, min(n - 1, at + d)), ask: nil))
        default: return false
        }
        lastInput = Date(); host?.redraw(.all); return true
    }
    /// ↩: a pick → its mail (an ask: 아니오), a mail → the list on it, the list → the menu.
    func mailBack(_ s: MailStep) -> Screen {
        switch s {
        case .list: return menuFor("우편함")
        case .open(let id): return .mail(.list(sel: mails.firstIndex { $0.id == id } ?? 0))
        case .pick(let id, let at, .some): return .mail(.pick(id: id, at: at, ask: nil))
        case .pick(let id, _, nil): return .mail(.open(id: id))
        }
    }
    /// A click: 8800 + i a row of the list's page (a first click picks it, one on the pick opens), 8820 / 8821 its pages, 8830 모두 받기;
    /// a mail's 8840 받기; a pick's 8850 + i a row or cell (the same two clicks: picked, then 받을까요?), 8880 / 8881 the grid's pages, 8890 the button,
    /// 8891 / 8892 아니오 / 예.
    func mailTap(_ code: Int, _ now: Date) {
        guard case .mail(let s) = screen else { return }
        let per = MailListModel.perPage
        switch (s, code) {
        case (.list(let sel), 8800..<8810):
            let at = sel / per * per + code - 8800
            guard let m = mails[safe: at] else { return }
            if at == sel { openOne(m.id) } else { screen = .mail(.list(sel: at)) }
        case (.list(let sel), 8820...8821):
            let n = mails.count, pages = max(1, (n + per - 1) / per)
            screen = .mail(.list(sel: min(max(0, n - 1), ((sel / per + (code == 8820 ? pages - 1 : 1)) % pages) * per)))
        case (.list, 8830): mailClaimAll(now)
        case (.open(let id), 8840): if let m = mail(id) { mailTake(m, now) }
        case (.pick(let id, let at, _), 8850..<8880):
            guard let m = mail(id), let n = pickCount(m) else { return }
            let legend = m.gifts.contains { if case .pickLegend = $0 { return true }; return false }
            let k = (legend ? at / MailPickModel.perPage * MailPickModel.perPage : 0) + code - 8850
            guard k < n else { return }
            screen = .mail(.pick(id: id, at: k, ask: k == at ? false : nil))
        case (.pick(let id, let at, nil), 8880...8881):
            guard let m = mail(id), let n = pickCount(m) else { return }
            let pp = MailPickModel.perPage, pages = max(1, (n + pp - 1) / pp)
            screen = .mail(.pick(id: id, at: min(n - 1, ((at / pp + (code == 8880 ? pages - 1 : 1)) % pages) * pp), ask: nil))
        case (.pick(let id, let at, nil), 8890): screen = .mail(.pick(id: id, at: at, ask: false))
        case (.pick(let id, let at, .some), 8891): screen = .mail(.pick(id: id, at: at, ask: nil))
        case (.pick(let id, let at, .some), 8892): if let m = mail(id) { mailClaim(m, pick: at, now) }
        default: break
        }
    }
}
