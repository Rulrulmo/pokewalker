import Foundation
// docs/plans/14 §4–5 (3.8): several of ours, in order — the 대전 파티 (3 to 6, from the companion, the walker and the box), a raid fight's party
// (1 to 3, as they are), a live battle's three of my six (the other's six shown by species). A click (or ●) picks or drops one; the strip on top
// is the order they go in; the button (or ● past the last one) sends it.

enum SquadFor: Equatable { case duelParty, raid, duelPick(id: Int) }
/// picked: uids (a duel's pick: slots of my six), in order; at: the cursor (= the count: on the button).
struct Squad: Equatable { var kind: SquadFor; var picked: [Int]; var at: Int }

extension Walker {
    /// What can be picked: ours by uid (the companion, the walker, the box as 포켓몬 shows it), or a duel's six by slot.
    func squadKeys(_ s: Squad) -> [Int] {
        if case .duelPick = s.kind { return Array((duel?.parties?.mine ?? []).indices) }
        return ([-1] + state.caught.indices.map { -2 - $0 } + boxOrder).compactMap { state.mon($0)?.uid }
    }
    func squadMon(_ s: Squad, _ key: Int) -> Mon? {
        if case .duelPick = s.kind { return duel?.parties?.mine[safe: key] }
        return state.ref(uid: key).flatMap { state.mon($0) }
    }
    func squadRange(_ k: SquadFor) -> ClosedRange<Int> { switch k { case .duelParty: 3...6; case .raid: 1...3; case .duelPick: 3...3 } }
    /// A duel's three already sent (the server's): nothing more to change.
    func squadSent(_ s: Squad) -> [Int]? { if case .duelPick = s.kind { return duel?.parties?.picked }; return nil }
    func squadOf(_ s: Squad) -> [Int] { squadSent(s) ?? s.picked }

    /// The registered 대전 파티 as it stands (one let go or traded drops out).
    var duelSix: [Mon] { (state.duelParty ?? []).compactMap { state.ref(uid: $0).flatMap { state.mon($0) } } }
    /// A raid's last pick (still ours), else the tower's three.
    var raidLast: [Int] {
        let kept = raidPicked.filter { state.ref(uid: $0) != nil }
        return kept.isEmpty ? state.party().compactMap { $0.mon.uid } : kept
    }

    // MARK: the page
    func squadPane(_ s: Squad, _ now: Date) -> PaneContent {
        let keys = squadKeys(s), n = keys.count, per = SquadModel.perPage, first = min(s.at, max(0, n - 1)) / per * per
        let picked = squadOf(s), range = squadRange(s.kind), sent = squadSent(s) != nil
        let fifty: Bool = { if case .raid = s.kind { return false }; return true }()
        let page = Array(keys[min(first, n)..<min(n, first + per)])
        let cells = page.compactMap { squadMon(s, $0) }.map { GridModel.Cell(dex: $0.dex, look: 2, shiny: $0.shiny == true, v3: $0.perfectIVs >= 3, level: $0.level, held: $0.item != nil) }
        let strip = (0..<range.upperBound).map { i in picked[safe: i].flatMap { squadMon(s, $0) }.map { SquadModel.Slot(dex: $0.dex, shiny: $0.shiny == true, level: "Lv.\(fifty ? Walk.towerLevel : $0.level)") } }
        var m = SquadModel(title: "", note: "\(picked.count)/\(range.upperBound)", strip: strip, theirs: nil, boxTitle: "동료 · 워커 · 상자 · \(n.formatted())마리", cells: cells,
                           order: page.map { k in picked.firstIndex(of: k).map { $0 + 1 } }, sel: s.at < n && s.at >= first ? s.at - first : nil, first: first, count: n,
                           empty: "포켓몬이 없어요", go: nil, goSel: s.at >= n, hint: "")
        switch s.kind {
        case .duelParty:
            m.title = "대전 파티"; m.hint = "3~6마리를 순서대로 골라 주세요 · 대전은 모두 Lv.50"
            if range.contains(picked.count) { m.go = "이 \(picked.count)마리로 정하기" }
        case .raid:
            m.title = "레이드 출전"; m.note = "파워 1칸 · \(picked.count)/3"; m.hint = "1~3마리를 골라 주세요 · 제 레벨로 싸워요"
            if range.contains(picked.count) { m.go = "이 \(picked.count)마리로 도전" }
        case .duelPick:
            let p = duel?.parties
            m.title = "vs " + (duel?.opponent ?? ""); m.note = duelLeft(now).map { "\($0)초 남음" } ?? ""
            m.theirs = (p?.theirs ?? []).map { GridModel.Cell(dex: $0.dex, look: 2, shiny: $0.shiny, v3: false, level: Walk.towerLevel, held: false) }
            m.boxTitle = "내 대전 파티 · 나갈 3마리를 순서대로"
            m.hint = sent ? (p?.theyPicked == true ? "곧 시작해요…" : "상대가 고르는 중…") : "시간이 지나면 앞의 3마리가 나가요"
            if !sent, picked.count == 3 { m.go = "이 3마리로 대전" }
            m.off = sent ? "골랐어요 · 상대를 기다리는 중" : "3마리를 골라 주세요"
        }
        let focus = s.at < n ? keys[s.at] : picked.last
        m.detail = focus.flatMap { squadMon(s, $0) }.map { squadDetail($0, fifty: fifty) }
        return PaneContent(squad: m)
    }
    /// 3.8.1 (14 §9): what to pick by — nature (its mint) · ability · held item, IVs (특훈's → 31), EVs, moves; a duel's at Lv.50.
    func squadDetail(_ m: Mon, fifty: Bool) -> SquadModel.Detail {
        let iv0 = m.ivs ?? Array(repeating: 15, count: 6), ev = m.evs ?? Array(repeating: 0, count: 6)
        let iv = iv0.indices.map { m.hyper?.contains($0) == true ? 31 : iv0[$0] }
        let lv = fifty && m.level != Walk.towerLevel ? "Lv.\(m.level) → \(Walk.towerLevel)" : "Lv.\(m.level)"
        let nature = m.natureName + (m.mint.map { $0 != (m.nature ?? 0) ? "(민트: " + natures[$0].name + ")" : "" } ?? "")
        return .init(dex: m.dex, shiny: m.shiny == true, title: (m.shiny == true ? "★" : "") + monNames[m.dex] + " " + lv,
                     sub: nature + " · " + m.abilityName, item: m.item ?? "도구 없음", moves: m.moves.compactMap { moveTable[$0]?.name }.joined(separator: " · "),
                     ivs: iv, evs: ev, best: iv.map { $0 == 31 }, v: m.perfectIVs)
    }
    func squadLCD(_ fb: inout FB, _ s: Squad, _ now: Date) {
        let keys = squadKeys(s), picked = squadOf(s), half = Int(now.timeIntervalSinceReferenceDate * 2) % 2
        let title: String = { switch s.kind { case .duelParty: "대전 파티"; case .raid: "레이드 출전"; case .duelPick: "3마리 고르기" } }()
        guard s.at < keys.count, let m = squadMon(s, keys[s.at]) else {                          // on the button: the first picked, the count, the button
            fb.text(title, 2, 0); fb.fill(0, 12, 96, 1, 2)
            if let f = picked.first.flatMap({ squadMon(s, $0) }) { fb.mon(f, half, 0, 2, anim: animT("squad", f.dex, now)) }
            fb.text("\(picked.count)마리", 94, 15, 2, right: true, small: true)
            if case .duelPick = s.kind, let l = duelLeft(now) { fb.text("\(l)초", 94, 26, 2, right: true, small: true) }
            let ok = squadRange(s.kind).contains(picked.count) && squadSent(s) == nil
            fb.text(ok ? "● 결정" : squadSent(s) != nil ? "기다리는 중" : "더 골라 주세요", 94, 52, ok ? 3 : 2, right: true, small: true)
            return
        }
        fb.text((m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)", 2, 0); fb.fill(0, 12, 96, 1, 2)
        fb.mon(m, half, 0, 2, anim: animT("squad \(keys[s.at])", m.dex, now))
        let i = picked.firstIndex(of: keys[s.at])
        fb.text(title, 94, 15, 2, right: true, small: true)
        if let i { fb.text("\(i + 1)번째", 94, 26, 3, right: true, small: true) }
        if case .duelPick = s.kind, let l = duelLeft(now) { fb.text("\(l)초", 94, 37, 2, right: true, small: true) }
        if squadSent(s) == nil { fb.text(i == nil ? "● 고르기" : "● 빼기", 94, 52, 2, right: true, small: true) }
    }

    // MARK: what you press
    /// ◀ ▶ the cursor (past the last one: the button), ● picks / drops the one under it, or on the button sends.
    func squadPress(_ k: Int, _ s0: Squad, _ now: Date) {
        var s = s0; let keys = squadKeys(s), n = keys.count
        if k != 1 { s.at = ((min(s.at, n) + (k == 0 ? -1 : 1)) % (n + 1) + n + 1) % (n + 1); screen = .squad(s); return }
        if s.at >= n { squadGo(s, now); return }
        squadToggle(&s, keys[s.at], n); screen = .squad(s)
    }
    func squadToggle(_ s: inout Squad, _ key: Int, _ n: Int) {
        guard squadSent(s) == nil else { return }
        if let i = s.picked.firstIndex(of: key) { s.picked.remove(at: i); return }
        guard s.picked.count < squadRange(s.kind).upperBound else { host?.beep(); return }
        s.picked.append(key)
        if s.picked.count == min(n, squadRange(s.kind).upperBound) { s.at = n }                  // all in (or all there are): onto the button
    }
    func squadTap(_ code: Int, _ now: Date) {
        guard case .squad(var s) = screen else { return }
        let keys = squadKeys(s), n = keys.count, per = SquadModel.perPage
        switch code {
        case 8740..<8746: if squadSent(s) == nil, s.picked.indices.contains(code - 8740) { s.picked.remove(at: code - 8740) }; screen = .squad(s)
        case 8750..<8768:                                                                          // a first click looks (the card above), a click on it picks or drops it
            let at = min(s.at, max(0, n - 1)) / per * per + code - 8750
            guard let key = keys[safe: at] else { return }
            if s.at == at { squadToggle(&s, key, n) } else { s.at = at }
            screen = .squad(s)
        case 8780...8781:
            let pages = max(1, (n + per - 1) / per)
            s.at = min(max(0, n - 1), ((min(s.at, max(0, n - 1)) / per + (code == 8780 ? pages - 1 : 1)) % pages) * per); screen = .squad(s)
        case 8790: squadGo(s, now)
        default: return
        }
    }
    /// The button: the 대전 파티 kept, a raid fight with these, or a duel's three sent (then the other's is waited for).
    func squadGo(_ s: Squad, _ now: Date) {
        guard squadSent(s) == nil else { return }
        guard squadRange(s.kind).contains(s.picked.count) else {
            let l: [String] = { switch s.kind { case .duelParty: ["3~6마리를", "골라 주세요"]; case .raid: ["1~3마리를", "골라 주세요"]; case .duelPick: ["3마리를", "골라 주세요"] } }()
            screen = .say(l, next: .squad(s), since: now); return
        }
        switch s.kind {
        case .duelParty:
            act(.duelParty(uids: s.picked), back: .squad(s), now) { _, now in .say(["대전 파티를", "정했다!"], next: .duel(.hub(tab: 0, sel: 0)), since: now) }
        case .raid:
            raidPicked = s.picked; raidFight(0, party: s.picked, back: .squad(s), now)
        case .duelPick(let id):
            act(.duelPick(id: id, slots: s.picked), back: .squad(s), now) { [weak self] o, now in
                guard let self else { return nil }
                if case .beats = screen { return nil }                                              // the poll brought the start first: it's playing
                if let v = o.duel, v.version >= (duel?.version ?? 0) { var kept = v; kept.beats = []; kept.turn = min(v.turn, duelSeen); duel = kept }   // its state (never its beats)
                cloud?.duelPoll = nil
                return .squad(s)
            }
        }
    }
    /// 레이드's 도전: who goes (the last pick, else the tower's three), then the fight.
    func raidPick(_ now: Date) {
        let last = raidLast
        screen = .squad(Squad(kind: .raid, picked: last, at: squadKeys(Squad(kind: .raid, picked: [], at: 0)).count))
    }
    /// 대전 파티 (from the 대전 menu): the registered ones first.
    func duelPartyPick() {
        let six = (state.duelParty ?? []).filter { state.ref(uid: $0) != nil }
        screen = .squad(Squad(kind: .duelParty, picked: six, at: 0))
    }
}
