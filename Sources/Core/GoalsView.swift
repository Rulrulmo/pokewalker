import Foundation
// 5.0 (docs/plans/18 §15, content5; the user, 10-14: "ㅇㅇ 추천대로"): 도감 업적 — 기록 ▸ 도감 업적, one page: 전국 (n/721, the next step and
// what it mails, the steps paid), the six regions (n/분모, 50 % and 완성 — a region filled rolls 이로치 once more, ✦ — and its 이로치 n/분모),
// 해금 (the device colours and the courses the 도감 opens). The LCD shows the row picked as the focus pages do (its picture on the stage: the
// next reward, the region's legend — 이로치 once it's filled —, a device colour); the panel lists them all. ● on a region opens its 도감.

extension Walker {
    /// The rows: 전국, the six regions, 해금.
    var goalRows: Int { DexGoals.regions.count + 2 }
    /// Each region's legend, on its row (이로치 once the region is filled: its bonus).
    static let regionLegends = [151, 249, 384, 483, 643, 716]
    /// The device colours and the courses the 도감 opens (the 해금 row): its name, what it asks, whether it's open.
    func dexUnlocks() -> [(name: String, need: String, open: Bool)] {
        let n = dexCount
        let colours = shells.filter { $0.dex > 0 }.map { ("기기 색 " + $0.name, "\($0.dex)종", n >= $0.dex) }
        let routes = courses.indices.filter { courses[$0].dex > 0 }.map { i -> (String, String, Bool) in
            let c = courses[i], region = c.region.flatMap { r in DexGoals.regions.first { $0.range == r }?.name }
            return ("코스 " + c.name, (region.map { $0 + " " } ?? "") + "\(c.dex)종", state.unlocked(i))
        }
        return colours + routes
    }
    /// A goal's gifts, short: 이상한사탕 ×5 · 민트 고르기 · 50BP · 칭호 포켓몬 박사.
    func goalGifts(_ gs: [Gift]) -> String {
        gs.map { g -> String in
            switch g {
            case .items(let n, let k): k > 1 ? "\(n) ×\(k)" : n
            case .bp(let a): "\(a)BP"
            case .pickItem(let xs): xs.allSatisfy { $0.hasSuffix("민트") } ? "민트 고르기" : "도구 고르기"
            case .title(let n): "칭호 " + n
            default: giftName(g)
            }
        }.joined(separator: " · ")
    }
    func goalsLCD(_ fb: inout FB, _ sel: Int) {
        let w = state, x = 44, s = min(max(0, sel), goalRows - 1)
        fb.text("도감 업적", 2, 0); fb.text("\(s + 1)/\(goalRows)", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
        func bar(_ y: Int, _ have: Int, _ of: Int, half: Int? = nil) {                         // a progress bar across the words' column, its half marked
            let len = 94 - x, done = of > 0 ? min(len, len * have / of) : 0, c = LCDDeco.tones(.dex).band
            for k in 0..<len { for dy in 0..<3 { fb.set(x + k, y + dy, k < done ? 3 : 1, k < done ? c : 0) } }
            if let h = half, of > 0 { let hx = x + len * h / of; for dy in -1...3 { fb.set(hx, y + dy, 3) } }
        }
        switch s {
        case 0:                                                                                   // 전국: the next step and its gift
            let all = dexCount, next = DexGoals.tiers.first { $0.count > all }
            switch next?.gifts.first {
            case .items(let n, _)?: fb.focusPic("item|" + n) { itemPic(n) }
            case .pickItem(let xs)?: if let n = xs.first { fb.focusPic("item|" + n) { itemPic(n) } }
            default: fb.mon(Mon(dex: 151, level: 50, female: false), 0, 0, 2)
            }
            fb.name("전국 \(all)/\(dexMax)", x, 13, 94 - x)
            bar(26, all, dexMax)
            fb.text(next.map { "다음 \($0.count)종" } ?? "모두 잡았다!", x, 31, 2, small: true)
            fb.wrap(next.map { goalGifts($0.gifts) } ?? "칭호 " + DexGoals.doctor, x, 40, 94 - x, lines: 2, 3)
        case 1...DexGoals.regions.count:                                                          // a region: its count, half, whole, 이로치
            let r = DexGoals.regions[s - 1], n = DexGoals.caught(w, r), done = n >= r.total
            fb.mon(Mon(dex: Walker.regionLegends[s - 1], level: 50, female: false, shiny: done ? true : nil), 0, 0, 2)
            fb.name(r.name + (done ? " ✦" : ""), x, 13, 94 - x)
            fb.text("\(n)/\(r.total)", 94, 14, 2, right: true, small: true)
            bar(26, n, r.total, half: r.half)
            fb.text((n >= r.half ? "50% ✓" : "50% \(r.half)") + " · " + (done ? "완성 ✓" : "완성 \(r.total)"), x, 31, 2, small: true)
            fb.text(done ? "✦ 이로치 한 번 더" : "이로치 \(DexGoals.shinies(w, r))/\(r.total)", x, 41, done ? 3 : 2, small: true)
            fb.text("● 이 지역 도감", x, 52, 1, small: true)
        default:                                                                                  // 해금: what the 도감 opens
            let u = dexUnlocks(), open = u.filter(\.open).count
            fb.focusPic("shell|럭셔리볼") { shellPic("럭셔리볼") }
            fb.name("해금 \(open)/\(u.count)", x, 13, 94 - x)
            for (k, e) in u.filter({ !$0.open }).prefix(3).enumerated() { fb.wrap(e.need + " " + e.name.replacingOccurrences(of: "기기 색 ", with: "").replacingOccurrences(of: "코스 ", with: ""), x, 26 + 9 * k, 94 - x, lines: 1) }   // (what it asks first: a long name cut)
            if u.allSatisfy(\.open) { fb.text("모두 열렸다!", x, 26, 3, small: true) }
        }
    }
    func goalsModel(_ sel: Int) -> GoalsModel {
        let w = state, all = dexCount, paid = Set(w.dexRewards ?? []), s = min(max(0, sel), goalRows - 1)
        let next = DexGoals.tiers.first { $0.count > all }
        var rows: [GoalsModel.Row] = [.init(name: "전국", have: all, of: dexMax, half: nil, note: next.map { "\($0.count)종: " + goalGifts($0.gifts) } ?? "칭호 " + DexGoals.doctor,
                                            marks: DexGoals.tiers.filter { paid.contains("전국:\($0.count)") || all >= $0.count }.count, of2: DexGoals.tiers.count, shiny: nil, done: next == nil)]
        for r in DexGoals.regions {
            let n = DexGoals.caught(w, r)
            rows.append(.init(name: r.name, have: n, of: r.total, half: r.half, note: n >= r.total ? "✦ 이로치 한 번 더" : n >= r.half ? "완성: " + goalGifts(DexGoals.fullGifts) : "50%: " + goalGifts(DexGoals.halfGifts),
                              marks: nil, of2: nil, shiny: "이로치 \(DexGoals.shinies(w, r))/\(r.total)", done: n >= r.total))
        }
        let u = dexUnlocks()
        rows.append(.init(name: "해금", have: u.filter(\.open).count, of: u.count, half: nil, note: u.first { !$0.open }.map { $0.need + " " + $0.name.replacingOccurrences(of: "코스 ", with: "") } ?? "모두 열렸다", marks: nil, of2: nil, shiny: nil, done: u.allSatisfy(\.open)))
        return GoalsModel(rows: rows, sel: s, paid: paid.count, hint: "")
    }
    /// ◀ ▶ a row; ● on a region (or 전국) opens its 도감.
    func goalsPress(_ k: Int, _ sel: Int) {
        if k != 1 { screen = .goals(((sel + (k == 0 ? -1 : 1)) % goalRows + goalRows) % goalRows); return }
        guard sel <= DexGoals.regions.count else { return }
        dexRegion = sel
        let list = dexList(0)
        screen = .dex(list.first ?? 1, filter: 0, detail: false)
    }
}

/// Self-test checks for this file (run by selftest()): the rows (전국 · six regions · 해금) as the save has them; a region's ● opens its 도감;
/// the LCD's words and picture clear of each other, nothing past its edge.
@MainActor func goalsChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    Content.$testing.withValue(true) {
        var st = Walk(); st.owned = Array(1...151) + Array(152...200); st.shinyOwned = [25, 6]; st.dex()
        let w = Walker(state: st); w.persist = false; w.screen = .goals(0)
        let m = w.goalsModel(1)
        let rows = m.rows.count == 8 && m.rows[0].have == 200 && m.rows[1].done && m.rows[1].shiny == "이로치 2/151" && m.rows[2].have == 49 && m.rows[2].half == 50 && !m.rows[2].done
        var bad: [String] = []
        for s in 0..<w.goalRows { w.screen = .goals(s); let fb = w.compose(Date()); bad += lcdOverlaps(fb) + fb.runs.filter { $0.x < 0 || $0.x + $0.w > 96 }.map { "past the edge: \($0.s)" } }
        w.screen = .goals(2); w.press(1)
        let opened: Bool = { if case .dex(let d, 0, false) = w.screen { return w.dexRegion == 2 && (152...251).contains(d) }; return false }()
        c.append((rows && bad.isEmpty && opened, "5.0 도감 업적: 전국 · six regions (관동 완성 ✦, 이로치 n/151) · 해금; every row's LCD clear and inside; ● on 성도 opens its 도감" + (bad.isEmpty ? "" : " — \(bad.prefix(4))")))
    }
    return c
}
