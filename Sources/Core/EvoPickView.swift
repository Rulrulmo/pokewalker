import Foundation
// 5.1.3 (docs/plans/23, the user via 회사 10-17: "배루키는 알에서밖에 못얻는데 진화 조건도 저렇게 빡세면 너무 힘들것같으데" → "A로가자"): with
// evo-choice on, 배루키 at Lv.20+ (the companion, the walker's or the box's; not holding 변함없는돌) waits for the player's pick — 시라소몬 ·
// 홍수몬 · 카포에라 (Walk.evoChoices, the server's Model). Its page's 진화 고르기 (the companion's ●, the LCD's ● menu 진화) opens this page: a card
// each (picture, type, ability, 공격 · 방어), ● then 진화할까요? 아니오 / 예, MonOp.evolve; the answer's .evolve news plays the usual show at home.
// A new one ready (Walk.evoReady in a save, against the one before): a notification, the 포켓몬 dot, and for the companion the LCD's "어라...?"
// into this page.

extension Walker {
    /// What the one with this uid may become now (empty: gone, evolved, 변함없는돌, or evo-choice off).
    func evoChoices(_ uid: Int) -> [Evo] { state.ref(uid: uid).map { state.evoChoices(Date(), ref: $0) } ?? [] }
    /// The page for the one at ref, if it can pick now (false: nothing opened).
    @discardableResult func openEvoPick(_ ref: Int) -> Bool {
        guard let u = state.mon(ref)?.uid, !state.evoChoices(Date(), ref: ref).isEmpty else { return false }
        screen = .evoPick(uid: u, at: 0, ask: nil); return true
    }
    /// One of the three as its card shows it: its ability by the slot it carries over (as the games), its 공격 · 방어.
    func evoCard(_ m: Mon, _ to: Int) -> EvoPickModel.Card {
        var x = m; x.dex = to; x.form = nil
        let st = baseStats[to], hidden = m.ability == 2 && Content.gen6 && hiddenAbility[to] > 0
        return .init(dex: to, name: monNames[to], types: x.typing, ability: x.abilityName, hidden: hidden, atk: st[1], def: st[2])
    }
    func evoPickPane(_ uid: Int, _ at: Int, _ ask: Bool?) -> PaneContent {
        guard let r = state.ref(uid: uid), let m = state.mon(r) else { return PaneContent() }
        let cards = state.evoChoices(Date(), ref: r).map { evoCard(m, $0.to) }, s = min(at, max(0, cards.count - 1))
        var x = m; if let c = cards[safe: s] { x.dex = c.dex; x.form = nil }
        return PaneContent(evoPick: EvoPickModel(who: monNames[m.dex] + " Lv.\(m.level)", cards: cards, sel: s, stats: cards.isEmpty ? [] : baseStats[x.dex],
                                                 abilityNote: cards.isEmpty ? "" : abilityDescs[x.abilityID] ?? "", shiny: m.shiny == true, ask: cards.isEmpty ? nil : ask))
    }
    func evoPickLCD(_ fb: inout FB, _ uid: Int, _ at: Int, _ ask: Bool?, _ now: Date) {
        guard let r = state.ref(uid: uid), let m = state.mon(r) else { return }
        let es = state.evoChoices(now, ref: r), half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        guard let e = es[safe: min(at, max(0, es.count - 1))] else {
            fb.text(monNames[m.dex] + "의 진화", 2, 0); fb.fill(0, 12, 96, 1, 2); fb.text("지금은 고를 수 없다", 0, 30, 2, center: true, small: true); return
        }
        var x = m; x.dex = e.to; x.form = nil
        fb.text((m.shiny == true ? "★" : "") + monNames[e.to], 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(x, half, 0, 2, anim: animT("evo \(e.to)", x.art, now))
        fb.text(x.typing.map { typeKo[$0] ?? $0 }.joined(separator: "·"), 94, 15, 2, right: true, small: true)
        fb.text(x.abilityName, 94, 26, 2, right: true, small: true)
        let st = baseStats[e.to]; fb.text("공\(st[1]) 방\(st[2])", 94, 37, 2, right: true, small: true)
        if let yes = ask {                                                                          // 진화할까? 아니오 / 예 (아니오 first)
            fb.fill(0, 50, 96, 14, 0); fb.fill(0, 50, 96, 1, 2)
            fb.text("진화할까?", 2, 52, 3, small: true)
            for (k, o) in ["아니오", "예"].enumerated() { let x = 48 + 24 * k, w = fb.text(o, x + 1, 52, 3, small: true); if (k == 1) == yes { fb.invert(x, 52, w + 2, 12) } }
        } else {
            fb.text("\(min(at, es.count - 1) + 1)/\(es.count)", 2, 52, 1, small: true)
            fb.text("● 고르기", 94, 52, 2, right: true, small: true)
        }
    }
    /// ◀ ▶ the next of the three (asked: 아니오 / 예), ● asks (아니오 first), then 예 sends it.
    func evoPickPress(_ k: Int, _ uid: Int, _ at: Int, _ ask: Bool?, _ now: Date) {
        let es = evoChoices(uid), n = es.count
        guard n > 0 else { if k == 1 { screen = evoBack(uid) }; return }
        if let yes = ask {
            if k != 1 { screen = .evoPick(uid: uid, at: at, ask: !yes); return }
            if yes { evolvePicked(uid, es[min(at, n - 1)].to, at, now) } else { screen = .evoPick(uid: uid, at: at, ask: nil) }
            return
        }
        if k != 1 { screen = .evoPick(uid: uid, at: ((at + (k == 0 ? -1 : 1)) % n + n) % n, ask: nil); return }
        screen = .evoPick(uid: uid, at: at, ask: false)
    }
    /// The server's (MonOp.evolve): its answer's .evolve plays at home, then its moves and the 도감 as any evolution's.
    func evolvePicked(_ uid: Int, _ to: Int, _ at: Int, _ now: Date) {
        act(.mon(op: .evolve(uid: uid, to: to)), back: .evoPick(uid: uid, at: at, ask: nil), now) { _, _ in .home }
    }
    /// ↩: an ask → the cards; the cards → its page (gone: home).
    func evoBack(_ uid: Int) -> Screen { state.ref(uid: uid).map { .box($0, act: nil, confirm: false, detail: true) } ?? .home }
    /// The pane's: a card (5960+: picked; again, 진화할까요?), the button (5970), 아니오 · 예 (5971 · 5972).
    func evoPickTap(_ code: Int, _ now: Date) {
        guard case .evoPick(let uid, let at, let ask) = screen else { return }
        let n = evoChoices(uid).count
        switch code {
        case 5960..<5963 where code - 5960 < n: let i = code - 5960; screen = .evoPick(uid: uid, at: i, ask: i == at && ask == nil ? false : nil)
        case 5970 where n > 0: screen = .evoPick(uid: uid, at: at, ask: false)
        case 5971: screen = .evoPick(uid: uid, at: at, ask: nil)
        case 5972 where ask != nil: evoPickPress(1, uid, at, true, now)
        default: return
        }
    }

    // MARK: who became ready (docs/plans/23 §5: no news of its own — a save's evoReady against the one before)
    /// Each save taken (rebase): the ones ready now that weren't (a level-up, a mail's or a trade's, 변함없는돌 taken off) — a notification, and
    /// the companion's "어라...?" at home (evoPrompt). The session's first save sets what was ready already: its dot says it, not a notification.
    func evoWatch(_ now: Date) {
        let ready = state.evoReady(now)
        defer { evoSeen = Set(ready) }
        guard let seen = evoSeen else { return }
        let new = ready.filter { !seen.contains($0) }
        guard !new.isEmpty else { return }
        evoNew += new
        if let u = state.companion.uid, new.contains(u) { evoPrompt = u }
        let ref = state.ref(uid: new[0]), name = monNames[ref.flatMap { state.mon($0)?.dex } ?? 236], to = ref.map { state.evoChoices(now, ref: $0).map { monNames[$0.to] } } ?? []
        notify("grow", new.count > 1 ? "\(name) \(new.count)마리가 진화할 수 있어요" : josa(name, "이", "가") + " 진화할 수 있어요",
               to.joined(separator: " · ") + " 중에서 골라 주세요 · 포켓몬")
    }
    /// At home, once the news is shown: the companion's "어라...? 배루키의 모습이...!", then the cards.
    func evoPromptShow(_ now: Date) -> Bool {
        guard let u = evoPrompt else { return false }
        evoPrompt = nil
        guard u == state.companion.uid, !evoChoices(u).isEmpty else { return false }
        lastInput = now                                                                             // (its minute starts here)
        screen = .say(["어라...?", monNames[state.companion.dex] + "의 모습이...!"], next: .evoPick(uid: u, at: 0, ask: nil), since: now); return true
    }
}
