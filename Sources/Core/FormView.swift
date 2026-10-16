import Foundation
// 5.0 (docs/plans/18 §9.6, §5 · §5.1, content5): the key items that change a Pokémon — 로토무카탈로그 (로토무's form: 원래 모습 + 5, each bringing its
// move) and 유전자쐐기 (큐레무 with a 레시라무 · 제크로무 of the walker's or the box's, or 분리). Reached as any targeted item: the bag's 쓰기 → who,
// or a Pokémon's 도구 주기; then this page (도구 주기's rows, a Pokémon's icon on each), ● sends the server's MonOp.

extension Walker {
    struct FormOption: Equatable { var label: String; var note: String; var why: String?; var dex: Int; var form: Int?; var op: MonOp? }
    /// What the item can do for the one at ref, a row each (why: not that one, dimmed).
    func formOptions(_ ref: Int, _ item: String) -> [FormOption] {
        guard let m = state.mon(ref), let u = m.uid else { return [] }
        if item == "로토무카탈로그" {
            return ([nil] + (1...5).map { Optional($0) }).map { f in
                let mv = f.flatMap { moveTable[Walk.rotomMoves[$0 - 1]]?.name }
                return FormOption(label: f.flatMap { Forms.of(479, $0)?.name } ?? "로토무", note: mv.map { "기술: " + $0 } ?? "폼 기술이 빠져요",
                                  why: (m.form ?? 0) == (f ?? 0) ? "지금 모습이에요" : nil, dex: 479, form: f, op: .rotom(uid: u, form: f))
            }
        }
        if let p = m.fused?.first {
            return [FormOption(label: "분리하기", note: josa(monNames[p.dex], "은", "는") + " 상자로 돌아가요", why: nil, dex: p.dex, form: nil, op: .unfuse(uid: u))]
        }
        return itemRefs.compactMap { r -> FormOption? in
            guard r != ref, let p = state.mon(r), [643, 644].contains(p.dex), let pu = p.uid else { return nil }
            return FormOption(label: monNames[p.dex] + " Lv.\(p.level)", note: (Forms.of(646, p.dex == 643 ? 2 : 1)?.name).map { $0 + "가 돼요" } ?? "",
                              why: r == -1 ? "함께 걷는 중이에요" : nil, dex: p.dex, form: nil, op: .fuse(uid: u, with: pu))
        }
    }
    /// 5.0 (the user: 큐레무 합체 · 로토무 모습을 어디서 하는지 몰라서): what this one's page offers straight off — its key item, the page's link,
    /// the LCD menu's word — while the bag has the item (로토무 + 로토무카탈로그, 큐레무 + 유전자쐐기).
    func formAction(_ ref: Int) -> (item: String, label: String, short: String)? {
        guard Content.gen6, let m = state.mon(ref) else { return nil }
        let has = { (i: String) in (self.state.bag + self.state.items).contains(i) }
        if m.dex == 479, has("로토무카탈로그") { return ("로토무카탈로그", "모습 바꾸기", "모습") }
        if m.dex == 646, has("유전자쐐기") { return m.fused == nil ? ("유전자쐐기", "합체하기", "합체") : ("유전자쐐기", "분리하기", "분리") }
        return nil
    }
    /// Instead of using it at once: this item asks what next (true = this page is up).
    func keyItemOn(_ item: String, _ ref: Int) -> Bool {
        guard ["로토무카탈로그", "유전자쐐기"].contains(item) else { return false }
        let o = formOptions(ref, item)
        screen = .formPick(ref: ref, item: item, sel: o.firstIndex { $0.why == nil } ?? 0); return true
    }
    func formPickPane(_ ref: Int, _ item: String, _ sel: Int) -> PaneContent {
        guard let m = state.mon(ref) else { return PaneContent() }
        let o = formOptions(ref, item), s = min(sel, max(0, o.count - 1)), r = o[safe: s]
        let rows = o.map { HoldModel.Row(name: $0.label, count: 0, note: $0.note, take: false, use: true, why: $0.why, dex: $0.dex, form: $0.form) }
        let action = r.flatMap { $0.why == nil ? (item == "유전자쐐기" ? ($0.op.map { if case .unfuse = $0 { "분리하기" } else { "합체하기" } } ?? nil) : josa($0.label, "으로", "로") + " 바꾸기") : nil }
        let hint = o.isEmpty ? "워커나 상자에 레시라무 · 제크로무가 없어요" : r.map { $0.why ?? $0.note } ?? ""
        return PaneContent(hold: HoldModel(who: monNames[m.dex] + " Lv.\(m.level)", now: formName(m) ?? m.fused?.first.map { "합체: " + monNames[$0.dex] } ?? "원래 모습", rows: rows, sel: s, action: action, hint: hint, picks: true))
    }
    func formPickLCD(_ fb: inout FB, _ ref: Int, _ item: String, _ sel: Int, _ now: Date) {
        guard let m = state.mon(ref) else { return }
        let o = formOptions(ref, item)
        fb.text(item == "유전자쐐기" ? (m.fused == nil ? "합체" : "분리") : "로토무의 모습", 2, 1, 3, small: true); fb.fill(0, 10, 96, 1, 2)
        if o.isEmpty { fb.text("레시라무 · 제크로무가", 0, 24, 2, center: true, small: true); fb.text("워커나 상자에 없어요", 0, 35, 2, center: true, small: true); return }
        if lcdFocus { formFocusLCD(&fb, m, o, sel); return }                                      // 5.0 (prototype): the form it'd make, big (FocusView.swift)
        let top = max(0, min(o.count - 5, sel - 2))
        for (k, x) in o[top..<min(o.count, top + 5)].enumerated() {
            let y = 13 + 10 * k
            fb.text(x.label, 2, y, x.why == nil ? 3 : 1, small: true)
            if x.why == "지금 모습이에요" { fb.text("지금", 94, y, 2, right: true, small: true) }
            if top + k == sel { fb.invert(0, y - 1, 96, 10) }
        }
    }
    /// ◀ ▶ a row, ● does it (the server's): the new form, the fusion, the 분리 — then its page (found again by uid: a box index may move).
    func formPickPress(_ k: Int, _ ref: Int, _ item: String, _ sel: Int, _ now: Date) {
        let o = formOptions(ref, item), n = o.count
        guard n > 0, let m = state.mon(ref), let u = m.uid else { if k == 1 { screen = .box(ref, act: nil, confirm: false, detail: true) }; return }
        if k != 1 { screen = .formPick(ref: ref, item: item, sel: ((sel + (k == 0 ? -1 : 1)) % n + n) % n); return }
        guard let x = o[safe: min(sel, n - 1)], let op = x.op else { return }
        let here = Screen.formPick(ref: ref, item: item, sel: sel)
        if let why = x.why { screen = .say([why], next: here, since: now); return }
        let name = monNames[m.dex], partner = m.fused?.first.map { monNames[$0.dex] }
        act(.mon(op: op), back: here, now) { [weak self] _, now in
            let lines: [String] = switch op {
            case .rotom(_, let f): f == nil ? [josa(name, "은", "는") + " 원래 모습으로", "돌아왔다!"] : [josa(name, "은", "는"), josa(x.label, "으로", "로") + " 바뀌었다!"]
            case .fuse: [josa(name, "과", "와") + " " + josa(x.label.components(separatedBy: " ").first ?? "", "이", "가"), "합체했다!"]
            default: [josa(name, "과", "와") + " " + josa(partner ?? "", "의", "의"), "합체를 풀었다!"]
            }
            let back = self?.state.ref(uid: u) ?? -1
            return .say(lines, next: .box(back, act: nil, confirm: false, detail: true), since: now)
        }
    }
    func formPickTap(_ code: Int, _ now: Date) {
        guard case .formPick(let ref, let item, let sel) = screen else { return }
        switch code {
        case 5980..<5995: let n = formOptions(ref, item).count, top = max(0, min(sel - 2, n - 6)); screen = .formPick(ref: ref, item: item, sel: min(n - 1, top + code - 5980))
        case 5999: formPickPress(1, ref, item, sel, now)
        default: return
        }
    }
}
