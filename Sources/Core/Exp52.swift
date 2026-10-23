import Foundation
// 5.2 (docs/plans/19 §11, content52; the user via 회사 10-23: "1. A 2. 내 원정 먼저 3. 야생 빼자"; lcd-mockups docs/mockups/v5.2): 전설 원정 with
// the eight in steps (Expedition.steps: collect · walk · meet · fight · companion) — the page's kinds as tabs (지금 · 배회 · 시련 · 수집 · 팀 ·
// 예정), the pick's steps ① → ② → ③ under the rows, a roamer's HP and where it is today, its lines and its button; the LCD; 홈's row (the one
// going on before the team event). The fights: a meeting with the roamer (a wild fight, its HP and status carried, gone after 3 turns), the
// boss once a day (1–3 of ours, 3 bars, the raid's battle screens) and its ball stage (5 balls of 30 %, kept when left: 나중에 던지기).
// 5.1's page (ExpView.swift) is the one with content52 off.

/// One row of the 5.2 page.
enum ExpRow: Equatable { case team(TeamEventView), exp(Expedition), later(kind: String, name: String, dex: [Int]) }
/// What the pick's button does: start (or switch to, go on with) it, claim it, meet the roamer, the boss (its party first), its balls, a
/// course where its steps count, the 포켓몬 grid (케르디오's companion).
enum ExpGo: Equatable { case start, claim, meet, boss, balls, course(Int), companion }

extension Walker {
    static let expTabs = ["지금", "배회", "시련", "수집", "팀", "예정"], expPerTab = 5
    /// 5.3's kinds (예정).
    static let expLater53: [ExpRow] = [.later(kind: "협동", name: "레시라무 · 제크로무", dex: [643, 644]), .later(kind: "스토리", name: "제르네아스 · 이벨타르", dex: [716, 717])]

    // MARK: what a step is
    /// The step on (nil: none — done, or not one of its steps).
    func expStage(_ e: Expedition) -> (k: Int, s: ExpStage)? { let st = e.steps, k = expProgress(e).stage ?? 0; return st.indices.contains(k) ? (k, st[k]) : nil }
    func expBegun(_ e: Expedition) -> Bool { expProgress(e).mon != nil }
    /// Waiting for others to be finished first (랜드로스, 케르디오).
    func expLocked(_ e: Expedition) -> Bool { e.after.contains { (state.expeditions?[$0]?.done ?? 0) == 0 } }
    func expAfterWho(_ e: Expedition) -> String { e.after.count == 3 ? "세 검사를" : josa(e.after.joined(separator: " · "), "을", "를") }
    /// Where a step's steps count, in a word: 동굴 · 산 · 숲, 하나, 칼로스 (nil: anywhere).
    func expPlace(_ s: ExpStage) -> String? {
        if let a = s.arts { let names: [(Art, String)] = [(.mountain, "산"), (.cave, "동굴"), (.forest, "숲")]; return names.filter { a.contains($0.0) }.map(\.1).joined(separator: " · ") }
        if s.region == Expeditions.unova { return "하나" }
        return s.region.map { _ in "칼로스" }
    }
    /// 배회: the roamer's course today (Expeditions.roamCourse, the server's own).
    func roamCourse(_ e: Expedition, _ now: Date = Date()) -> Int? { Expeditions.roamCourse(e.id, day: Walk.key(now), open: { state.unlocked($0) }) }
    /// The first open course where s's steps count (the roamer: today's).
    func expCourse(_ e: Expedition, _ s: ExpStage) -> Int? {
        if s.kind == .meet { return roamCourse(e) }
        return courses.indices.first { s.counts(courses[$0]) && state.unlocked($0) }
    }
    func expHere(_ e: Expedition, _ s: ExpStage) -> Bool { s.kind == .meet ? s.counts(state.here) : s.kind == .companion ? s.with.contains(state.companion.dex) : s.counts(state.here) }
    func expFought(_ x: ExpProgress, _ now: Date = Date()) -> Bool { x.fought == Walk.key(now) }
    /// A roamer's HP left, 0…1 (nil: full).
    func roamHP(_ e: Expedition, _ x: ExpProgress) -> Double {
        guard let hp = x.hp, let m = x.mon else { return 1 }
        var f = m; f.form = nil; return Double(hp) / Double(max(1, f.stats[0]))
    }
    func pct(_ v: Double) -> Int { Int((v * 100).rounded()) }

    // MARK: the rows
    func expRows(_ tab: Int) -> [ExpRow] {
        let all = Expeditions.personal
        switch tab {
        case 0:
            let begun = all.filter(expBegun), team = teamEvent().map { [ExpRow.team($0)] } ?? []
            return team + (begun.filter { expProgress($0).on } + begun.filter { !expProgress($0).on }).map { .exp($0) }
        case 1: return all.filter { $0.kind == .roam }.map { .exp($0) }
        case 2: return all.filter { $0.kind == .trial }.map { .exp($0) }
        case 3: return all.filter { $0.kind == .collect }.map { .exp($0) }
        case 4: return (cloud?.expedition?.events ?? []).prefix(Walker.expPerTab).map { .team($0) }
        default: return Walker.expLater53
        }
    }
    func expKindName(_ e: Expedition) -> String { switch e.kind { case .roam: "배회"; case .trial: "시련"; case .collect: "수집"; case .team: "팀"; case .pair: "협동"; case .story: "스토리" } }
    /// A row's chip and short line, its bar (a roamer's: HP), what's red (something to do now), done, dimmed.
    func exp52Words(_ e: Expedition, _ now: Date = Date()) -> (chip: String, note: String, frac: Double, hp: Bool, ready: Bool, done: Bool, off: Bool) {
        let x = expProgress(e), kind = expKindName(e)
        if expLocked(e) { return (kind + " · 잠김", expAfterWho(e) + " 먼저", 0, false, false, false, true) }
        if x.mon == nil { return x.done > 0 ? (kind + " · 끝냄", "잡았어요 ✓ · 다시 할 수 있어요", 1, false, false, true, false) : (kind, "시작 전", 0, false, false, false, false) }
        guard let (k, s) = expStage(e) else { return (kind, "", 0, false, false, false, false) }
        let state = x.on ? "지금" : "멈춤", lead = e.steps.count > 2 ? "\(k + 1)단계 · " : ""
        switch s.kind {
        case .meet:
            let hp = roamHP(e, x)
            return (kind + " · " + state, "HP \(pct(hp))% · 만남 \(x.meets ?? 0)/\(Expeditions.meetsMax)", hp, true, x.on && (x.meets ?? 0) > 0, false, false)
        case .collect:
            let unit = s.piece.components(separatedBy: " ").last ?? "", full = x.n >= s.need
            if full, k == e.steps.count - 1 { return (kind + " · " + state, "\(x.n)/\(s.need) · " + (e.legend == 718 ? "조립할 수 있어요" : "받을 수 있어요"), 1, false, true, false, false) }
            return (kind + " · " + state, lead + "\(unit) \(x.n)/\(s.need)" + (x.on && e.steps.count == 1 ? " · 다음 \(max(0, s.stepsPer - x.steps).formatted())걸음" : ""), Double(x.n) / Double(max(1, s.need)), false, false, false, false)
        case .walk:
            if x.steps >= s.need, k == e.steps.count - 1 { return (kind + " · " + state, "받을 수 있어요", 1, false, true, false, false) }
            return (kind + " · " + state, lead + (expPlace(s) ?? "") + " \(man(x.steps))/\(man(s.need))", Double(x.steps) / Double(max(1, s.need)), false, false, false, false)
        case .companion:
            if x.steps >= s.need { return (kind + " · " + state, "받을 수 있어요", 1, false, true, false, false) }
            return (kind + " · " + state, "동행 \(man(x.steps))/\(man(s.need))", Double(x.steps) / Double(max(1, s.need)), false, false, false, false)
        case .fight:
            let fight = e.legend == 384 ? "결전" : "보스전"
            if let b = x.balls { return (kind + " · 볼", x.on ? "볼 \(b)/\(s.balls) · 던질 수 있어요" : "볼 \(b)개 남음 · 멈춤", 1, false, x.on, false, false) }
            return (kind + " · " + fight, expFought(x, now) ? "오늘은 싸웠어요" : x.on ? "오늘 1번 싸울 수 있어요" : "멈춤", 1, false, x.on && !expFought(x, now), false, false)
        }
    }
    /// The pick's steps (two or more): ① a walk → ② the boss → ③ its balls …, each with its count now.
    func expStrip(_ e: Expedition, _ now: Date = Date()) -> [ExpModel.Step] {
        var items: [(title: String, sub: String, at: Int, balls: Bool)] = []
        for (i, s) in e.steps.enumerated() {
            switch s.kind {
            case .collect: items.append((s.piece, "\(s.need)개", i, false))
            case .walk: items.append(((expPlace(s) ?? "") + " 코스", "\(man(s.need))걸음", i, false))
            case .companion: items.append(("검사와 걷기", "\(man(s.need))걸음", i, false))
            case .meet: items.append(("만남", "5,000걸음마다", i, false))
            case .fight:
                items.append((e.legend == 384 ? "결전" : "보스전", e.legend == 384 ? "Lv.\(s.level)" : "하루 1번", i, false))
                if s.balls > 0 { items.append(("볼 \(s.balls)개", "한 개 \(Int(RaidRules.newOdds * 100))%", i, true)) }
            }
        }
        guard items.count > 1 else { return [] }
        let x = expProgress(e), locked = expLocked(e), k = x.stage ?? 0, onBalls = x.balls != nil
        return items.map { it in
            let cur = it.at == k && (it.balls == onBalls)
            let st = locked || x.mon == nil ? (x.mon == nil && x.done > 0 && !locked ? 2 : 0) : it.at < k || (it.at == k && !it.balls && onBalls) ? 2 : cur ? 1 : 0
            var sub = it.sub
            if st == 1, let s = e.steps[safe: it.at] {
                switch s.kind {
                case .walk, .companion: sub = "\(man(x.steps))/\(man(s.need))"
                case .collect: sub = "\(x.n)/\(s.need)"
                case .fight: sub = it.balls ? "남은 \(x.balls ?? 0)개" : expFought(x, now) ? "내일 다시" : "오늘 1번"
                case .meet: break
                }
            }
            return ExpModel.Step(title: it.title, sub: sub, state: st)
        }
    }
    /// The pick's lines under the rows, its button (nil: none) and what the button does.
    func exp52Detail(_ r: ExpRow, _ now: Date = Date()) -> (lines: [String], go: String?, act: ExpGo?) {
        switch r {
        case .team(let t): let d = expDetail(.team(t)); return (d.lines, d.go, nil)
        case .later: return (["5.3 업데이트에 열려요"], nil, nil)
        case .exp(let e):
            let x = expProgress(e), name = monNames[e.legend]
            if expLocked(e) {
                let gives = [e.item, e.gift.map { $0 + "(\(expKindName(e)) 첫 완료)" }].compactMap { $0 }
                return ([(e.after.count == 3 ? "세 검사(코바르온 · 테라키온 · 비리디온)를" : expAfterWho(e)) + " 잡으면 열려요"] + (gives.isEmpty ? [] : ["끝내면 " + gives.joined(separator: " · ")]), nil, nil)
            }
            let roamer = e.steps.count == 1 && e.steps[0].kind == .meet
            let intro = roamer ? "\(name): 하나 코스를 돌아다녀요 · 5,000걸음마다 만남" : "\(name): " + expStrip(e).map { $0.title }.joined(separator: " → ")
            guard let (k, s) = expStage(e) else { return ([], nil, nil) }
            if let g = expGoing, g.id != e.id {
                if x.mon != nil, expClaimable(e) { return (["멈춘 원정이지만 받을 수 있어요"], expClaimLabel(e), .claim) }   // (a claim: going on or stopped, as 5.1)
                return (["원정은 한 번에 하나 · 지금: " + monNames[g.legend], "바꾸면 지금 것은 멈추고, 나중에 이어 할 수 있어요"] + (x.mon == nil ? [intro] : []),
                        (x.mon != nil ? "이어 하기" : "바꾸기") + " · 지금 것은 멈춰요", .start)
            }
            if x.mon == nil { return ([roamer ? "하나 코스를 돌아다녀요 · 5,000걸음마다 만남 1번" : intro, "원정은 한 번에 하나만 할 수 있어요"], x.done > 0 ? "다시 하기" : "시작하기", .start) }
            if !x.on { return (["멈춘 원정 · 모은 것은 그대로예요", "멈춘 동안은 걸음이 쌓이지 않아요"] + (x.balls != nil ? ["볼 \(x.balls ?? 0)개가 남아 있어요"] : []), "이어 하기", .start) }
            if expClaimable(e) { return ([s.kind == .companion ? "세 검사와 \(man(s.need))걸음을 걸었어요" : s.kind == .collect ? "모은 \(s.piece) \(s.need)개로 " + josa(name, "을", "를") + " 조립해요" : "\(man(s.need))걸음을 다 걸었어요"], expClaimLabel(e), .claim) }
            switch s.kind {
            case .meet:
                let rc = roamCourse(e), place = rc.map { courses[$0].name }, here = rc == state.course, meets = x.meets ?? 0
                let first = !s.counts(state.here) ? "지금 \(state.here.name) · 만남은 하나 코스에서만 쌓여요"
                    : meets >= Expeditions.meetsMax ? "만남이 가득 찼어요(\(Expeditions.meetsMax)번) · 만나러 가요" : "다음 만남까지 \(max(0, s.stepsPer - x.steps).formatted())걸음 · 만남은 \(Expeditions.meetsMax)번까지 모여요"
                let lines = [first, (place.map { $0 + " 레이더에서도 가끔 나와요" } ?? "") + (here ? " · 지금 여기예요" : ""), "쓰러뜨리면 다음엔 HP가 가득 · 깎아서 잡아요"]
                if meets > 0 { return (lines, "만나기 · 만남 \(meets)번", .meet) }
                return (lines, here ? nil : place.map { josa($0, "으로", "로") }, here ? nil : rc.map { .course($0) })
            case .walk:
                let p = expPlace(s) ?? "", here = s.counts(state.here), c = expCourse(e, s)
                return ([here ? "지금 \(state.here.name) · 남은 \(man(s.need - x.steps))걸음" : "지금 코스(\(state.here.name))는 세지 않아요",
                         p + " 코스에서 걸은 만큼 쌓여요" + (s.region == nil ? " · 어느 지방이든 돼요" : "")] + (!here && c == nil ? [p + " 코스는 메뉴 ▸ 모험 ▸ 코스에서 열어요"] : [])
                         + (k + 1 < e.steps.count ? ["다 걸으면 " + (e.legend == 384 ? "결전" : "보스전") + "이에요"] : []),
                        here || c == nil ? nil : p + " 코스로", here ? nil : c.map { .course($0) })
            case .collect:
                if e.steps.count == 1 && e.stages.isEmpty {                                            // 지가르데: 5.1's lines
                    let d = expDetail(.personal(e)), c = d.go == "칼로스 코스로" ? expCourse(e, s) : nil
                    return (d.lines, d.go, c.map { .course($0) })
                }
                let p = expPlace(s) ?? "", here = s.counts(state.here), c = expCourse(e, s), first = p.components(separatedBy: " · ").first ?? p
                return (["다음 \(s.piece.components(separatedBy: " ").last ?? "")까지 \(max(0, s.stepsPer - x.steps).formatted())걸음 · \(s.need)개면 다음 단계예요",
                         p + " 코스 \(s.stepsPer.formatted())걸음마다 1개 · 그 코스의 레이더에서도 가끔"] + (!here && c == nil ? [p + " 코스는 메뉴 ▸ 모험 ▸ 코스에서 열어요"] : []), here || c == nil ? nil : first + " 코스로", here ? nil : c.map { .course($0) })
            case .companion:
                let ok = s.with.contains(state.companion.dex)
                return (["지금 동행 " + monNames[state.companion.dex] + (ok ? " · 어느 코스든 세요" : " · 걸음이 쌓이지 않아요"),
                         s.with.sorted().map { monNames[$0] }.joined(separator: " · ") + " 중 하나와 함께 걸어요"], ok ? nil : "동행 바꾸기", ok ? nil : .companion)
            case .fight:
                let fight = e.legend == 384 ? "결전" : "보스전"
                if let b = x.balls { return (["볼 \(b)개 · 한 개에 \(Int(RaidRules.newOdds * 100))% · 다 놓치면 내일 \(fight)부터", "앱을 닫아도 남은 볼은 그대로예요"], "볼 던지기 · 남은 \(b)개", .balls) }
                if expFought(x, now) { return (["오늘은 싸웠어요 · 내일 0시부터 다시 싸워요", "지면 그날은 끝 · 전설은 그대로 기다려요"], nil, nil) }
                return ((e.legend == 384 ? ["이기면 화룡점정을 아는 레쿠쟈가 꼭 와요"] : []) + ["\(name) Lv.\(s.level) · 바 \(s.bars)개 · 내 포켓몬 1~3마리", "하루 1번 · 레이드 파워는 쓰지 않아요"], fight + " · 오늘 1번", .boss)
            }
        }
    }
    /// Its last step done, waiting for expClaim (지가르데's cells, 케르디오's walk).
    func expClaimable(_ e: Expedition) -> Bool {
        let x = expProgress(e)
        guard x.mon != nil, let (k, s) = expStage(e), k == e.steps.count - 1 else { return false }
        return s.kind == .collect ? x.n >= s.need : (s.kind == .walk || s.kind == .companion) && x.steps >= s.need
    }
    func expClaimLabel(_ e: Expedition) -> String { e.legend == 718 ? "조립하기" : "받기 · " + monNames[e.legend] }

    // MARK: the page
    func exp52Pane(_ sel: Int, _ now: Date = Date()) -> PaneContent {
        let list = expRows(expTab), s = min(max(0, sel), max(0, list.count - 1))
        let rows = list.prefix(Walker.expPerTab).map { r -> ExpModel.Row in
            switch r {
            case .team(let t):
                let w = expWords(.team(t))
                return .init(name: teamName(t), chip: w.chip, note: w.note, dex: expDex(.team(t)), frac: Double(t.team) / Double(max(1, t.goal)), mine: Double(t.mine) / Double(max(1, t.min)), done: t.got || t.team >= t.goal)
            case .later(let kind, let name, let dex): return .init(name: name, chip: kind, note: "5.3 업데이트에 열려요", dex: dex, frac: 0, off: true)
            case .exp(let e):
                let w = exp52Words(e, now)
                return .init(name: monNames[e.legend], chip: w.chip, note: w.note, dex: [e.legend], frac: w.frac, ready: w.ready, done: w.done, hpBar: w.hp, locked: w.off, on: expProgress(e).on)
            }
        }
        let d: (lines: [String], go: String?, act: ExpGo?) = list[safe: s].map { exp52Detail($0, now) } ?? (expTab == 0 ? (["하고 있는 원정이 없어요", "배회 · 시련 · 수집 탭에서 골라 시작해요"], nil, nil) : ([], nil, nil))
        let got = Walker.expLegends.filter { (state.owned ?? []).contains($0) }.count
        var m = ExpModel(rows: rows, sel: s, got: "전설 \(got)/\(Walker.expLegends.count)종", detail: d.lines, go: d.go, tabs: Walker.expTabs, tab: expTab)
        if case .exp(let e)? = list[safe: s] {
            m.steps = expStrip(e, now)
            let x = expProgress(e)
            if x.mon != nil, expStage(e)?.s.kind == .meet {
                m.hp = roamHP(e, x); m.hpNote = "\(pct(m.hp ?? 1))%" + (x.status.map { " · " + $0.badge } ?? "")
                m.place = "오늘 " + monNames[e.legend] + ": " + (roamCourse(e).map { courses[$0].name } ?? "-")
            }
        }
        return PaneContent(exp: m)
    }
    func exp52LCD(_ fb: inout FB, _ sel: Int, _ now: Date = Date()) {
        let list = expRows(expTab), s = min(max(0, sel), max(0, list.count - 1)), x = 44
        fb.text("전설 원정", 2, 0); fb.text(Walker.expTabs[expTab] + (list.isEmpty ? "" : " \(s + 1)/\(list.count)"), 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
        guard let r = list[safe: s] else { fb.line("배회 · 시련 탭에서", 2, 26, 92); fb.line("골라 시작해요", 2, 37, 92); return }
        func bar(_ y: Int, _ frac: Double, hp: Bool = false) {
            let len = 94 - x, done = min(len, Int(Double(len) * max(0, min(1, frac)))), c = hp ? (frac > 0.5 ? rgb(72, 200, 96) : frac > 0.2 ? rgb(240, 192, 40) : rgb(232, 72, 56)) : LCDDeco.tones(.course).band
            for k in 0..<len { for dy in 0..<3 { fb.set(x + k, y + dy, k < done ? 3 : 1, k < done ? c : 0) } }
        }
        let grey: (UInt8, UInt32) = (3, rgb(150, 156, 168))                                                         // a shadow that shows on the colour LCD too
        switch r {
        case .team(let t):
            if let d = expDex(.team(t)).first { fb.mon(Mon(dex: d, level: 50, female: false), 0, 0, 2) }
            fb.name(teamName(t), x, 13, 94 - x); bar(26, Double(t.team) / Double(max(1, t.goal)))
            fb.line(t.got ? "받았어요" : "팀 \(teamPct(t))%", x, 31, 94 - x, t.team >= t.goal ? 3 : 2)
            fb.line("내 \(man(t.mine))/\(man(t.min))" + (t.mine >= t.min ? " ✓" : ""), x, 40, 94 - x, t.mine >= t.min ? 3 : 2)
            fb.line(teamWhen(t), x, 49, 94 - x)
        case .later(let kind, let name, let dex):
            if let d = dex.first { fb.mon(Mon(dex: d, level: 50, female: false), 0, 0, 2, tint: grey) }
            fb.name(kind, x, 13, 94 - x); fb.line(name.replacingOccurrences(of: " · ", with: "·"), x, 26, 94 - x, 1); fb.line("5.3에", x, 37, 94 - x); fb.line("열려요", x, 46, 94 - x)
        case .exp(let e):
            let p = expProgress(e), m = Mon(dex: e.legend, level: 50, female: false)                // (no 이로치: it shows when it comes, plan 19 §1.3)
            if expLocked(e) { fb.mon(m, 0, 0, 2, tint: grey) } else { fb.mon(m, 0, 0, 2) }
            fb.name(monNames[e.legend], x, 13, 94 - x)
            if expLocked(e) { fb.line("잠김", x, 26, 94 - x, 1); fb.line(e.after.count == 3 ? "세 검사" : "두 마리", x, 37, 94 - x); fb.line("먼저", x, 46, 94 - x); return }
            if p.mon == nil { fb.line(p.done > 0 ? "잡았다 ✓" : "시작 전", x, 26, 94 - x, 1); fb.line(expGoing != nil ? "● 바꾸기" : "● 시작하기", x, 40, 94 - x, 3); return }
            if !p.on { fb.line("멈춤", x, 26, 94 - x, 1); fb.line("● 이어 하기", x, 40, 94 - x, 3); return }
            guard let (_, st) = expStage(e) else { return }
            switch st.kind {
            case .meet:
                let hp = roamHP(e, p), meets = p.meets ?? 0
                bar(26, hp, hp: true); fb.line("HP \(pct(hp))%" + (p.status.map { " " + $0.badge } ?? ""), x, 31, 94 - x, 2)
                fb.line("오늘 " + (roamCourse(e).map { courses[$0].name.replacingOccurrences(of: " ", with: "") } ?? "-"), x, 40, 94 - x, 2)
                fb.line(meets > 0 ? "● 만나기 \(meets)" : "만남 0/\(Expeditions.meetsMax)", x, 49, 94 - x, meets > 0 ? 3 : 2)
            case .walk, .companion:
                if p.steps >= st.need { fb.line("다 걸었다!", x, 31, 94 - x, 3); fb.line("● 받기", x, 44, 94 - x, 3); return }
                bar(26, Double(p.steps) / Double(max(1, st.need)))
                fb.line((st.kind == .companion ? "동행" : expPlace(st) ?? "") + " \(man(p.steps))", x, 31, 94 - x, 2); fb.line("/\(man(st.need))걸음", x, 40, 94 - x, 2)
                fb.line(st.kind == .companion ? (st.with.contains(state.companion.dex) ? "세는 중" : "동행이 아님") : e.legend == 384 ? "다음 결전" : "다음 보스전", x, 49, 94 - x, st.kind == .companion && !st.with.contains(state.companion.dex) ? 3 : 1)
            case .collect:
                let unit = st.piece.components(separatedBy: " ").last ?? ""
                if expClaimable(e) { fb.line("\(unit) \(p.n)/\(st.need)", x, 31, 94 - x, 3); fb.line("● " + expClaimLabel(e), x, 44, 94 - x, 3); return }
                bar(26, Double(p.n) / Double(max(1, st.need))); fb.line("\(unit) \(p.n)/\(st.need)", x, 31, 94 - x, 2)
                fb.line("다음 \(unit)", x, 40, 94 - x); fb.line("\(max(0, st.stepsPer - p.steps).formatted())걸음", x, 49, 94 - x)
            case .fight:
                if let b = p.balls { fb.line("볼 \(b)/\(st.balls)", x, 26, 94 - x, 2); fb.line("한 개 \(Int(RaidRules.newOdds * 100))%", x, 37, 94 - x); fb.line("● 던지기", x, 48, 94 - x, 3); return }
                fb.line((e.legend == 384 ? "결전" : "보스전") + " · 바 \(st.bars)", x, 26, 94 - x, 2)
                fb.line(expFought(p, now) ? "내일 다시" : "오늘 1번", x, 37, 94 - x, expFought(p, now) ? 1 : 2)
                if !expFought(p, now) { fb.line("● 싸우기", x, 48, 94 - x, 3) }
            }
        }
    }
    /// ◀ ▶ a row (round, in the tab); ● its button; Tab (or a tab's click) the next kind.
    func exp52Press(_ k: Int, _ sel: Int, _ now: Date) {
        let list = expRows(expTab), n = max(1, min(Walker.expPerTab, list.count))
        if k != 1 { screen = .expedition((sel + (k == 0 ? -1 : 1) + n) % n); return }
        guard case .exp(let e)? = list[safe: sel], let a = exp52Detail(.exp(e), now).act else { return }
        let here = Screen.expedition(sel), name = monNames[e.legend]
        switch a {
        case .claim: expClaim52(e, back: here, now)
        case .meet: expFight(e.id, party: nil, back: here, now)
        case .boss: screen = .squad(Squad(kind: .exp(id: e.id), picked: raidLast, at: 0))
        case .balls: expBallsID = e.id; screen = .raid(.expBalls(e.id))
        case .companion: screen = .box(-1, act: nil, confirm: false)
        case .course(let c): screen = .course(c)
        case .start:
            if let g = expGoing, g.id != e.id,
               host?.confirm(name + " 원정으로 바꿀까요?", "지금 하는 " + monNames[g.legend] + " 원정은 멈추고, 모은 것은 그대로 남아요. 나중에 이어 할 수 있어요.", ok: "바꾸기") == false { return }
            let resume = expProgress(e).mon != nil
            act(.expStart(id: e.id), back: here, now) { [weak self] _, now in .say([name + " 원정을", resume ? "이어 간다!" : "시작했다!"], next: self?.expPage(e.id) ?? here, since: now) }
        }
    }
    func exp52Tab(_ t: Int) { expTab = (t + Walker.expTabs.count) % Walker.expTabs.count; screen = .expedition(0) }
    /// The page with this one picked (its tab: 지금 when it's going on).
    func expPage(_ id: String) -> Screen {
        if let k = expRows(expTab).firstIndex(where: { if case .exp(let e) = $0 { return e.id == id }; return false }) { return .expedition(k) }
        expTab = 0
        return .expedition(expRows(0).firstIndex { if case .exp(let e) = $0 { return e.id == id }; return false } ?? 0)
    }
    /// expClaim: 지가르데's show (5.1), 케르디오 said.
    func expClaim52(_ e: Expedition, back: Screen, _ now: Date) {
        let name = monNames[e.legend]
        act(.expClaim(id: e.id), back: back, now) { [weak self] o, now in
            guard let self, let m = o.mon else { return nil }
            let more = expDoneLines(e.id)
            if e.legend == 718 { expAfter = .say([josa(name, "을", "를"), "상자에 보냈다!"] + more, next: expPage(e.id), since: now); return .assemble(m, since: now) }
            return .say([josa(name, "이", "가") + " 함께 왔다!", "상자로 보냈다"] + more, next: expPage(e.id), since: now)
        }
    }
    /// What a finish gave besides its legend (its news, taken now): 특성패치, 비추는거울.
    func expDoneLines(_ id: String) -> [String] {
        var out: [String] = []
        news.removeAll { n in
            switch n {
            case .expeditionDone(let i, _, let g) where i == id: if let g { out.append(josa(g, "을", "를") + " 받았다!") }; return true
            case .expeditionGift(let i, let item) where i == id: out.append(josa(item, "을", "를") + " 받았다!"); return true
            case .expeditionStage(let i, _) where i == id: return true
            default: return false
            }
        }
        return out
    }

    /// An expedition's fight's title: 배회 · 토네로스, 시련 · 테라키온, 레쿠쟈 원정.
    func expTitle(_ id: String) -> String {
        guard let e = Expeditions.of(id) else { return "전설 원정" }
        return e.legend == 384 ? "레쿠쟈 원정" : expKindName(e) + " · " + monNames[e.legend]
    }

    // MARK: the fights
    /// A meeting (party nil) or the boss (1–3 of ours): the battle screens (the boss's as a raid's: its bars, 후퇴).
    func expFight(_ id: String, party: [Int]?, back: Screen, _ now: Date) {
        let boss = party != nil, name = Expeditions.of(id).map { monNames[$0.legend] } ?? id
        act(.expFight(id: id, party: party), back: back, now, lines: [boss ? name + "에게" : name + "을 찾아", boss ? "가는 중..." : "가는 중..."], quiet: true) { [weak self] o, now in
            guard let self, let f = o.battle else { return nil }
            fight = f; freshFight()
            return (o.beats ?? []).isEmpty ? .battle(f, sel: 0) : .beats(f, Walker.raidShown(o.beats!, from: f), since: now, from: f)
        }
    }
    /// An expedition's fight over (the server's end): the roamer — what's carried; the boss — its ball stage, or tomorrow.
    func expFightEnded(_ id: String, _ b: Battle, _ e: BattleEnd, _ now: Date) -> Screen {
        let f = b.theirs[0], name = monNames[f.mon.dex], page = expPage(id)
        if b.raidTier != nil {                                                                      // the boss
            if e.result == "won" {
                if let balls = e.balls, balls > 0 { expBallsID = id; return .say([josa(name, "을", "를") + " 이겼다!", "볼 \(balls)개 · 한 개에 \(Int(RaidRules.newOdds * 100))%"], next: .raid(.expBalls(id)), since: now) }
                return .say([josa(name, "을", "를") + " 잡았다!", "화룡점정을 알고 있다!", "상자로 보냈다"] + expDoneLines(id), next: page, since: now)   // 레쿠쟈 (R2): it comes with the win
            }
            return .say([e.result == "ran" ? "결전에서 물러났다" : josa(name, "에게", "에게") + " 졌다...", "오늘은 끝 · 내일 다시"], next: page, since: now)
        }
        let back: Screen
        if let n = e.chain, n > 0 { chainNext = n; back = .home } else { back = page }              // found by the radar on a chain: the next bush after
        let left = "남은 HP \(pct(Double(f.hp) / Double(max(1, f.maxHP))))%는"
        switch e.result {
        case "caught": return .say([josa(name, "을", "를") + " 잡았다!", "원정을 끝냈다"] + expDoneLines(id), next: back, since: now)
        case "won": return .say(["쓰러뜨렸다", "다음 만남엔 HP가 가득 · 깎아서 잡아요"], next: back, since: now)
        case "lost": return .say(["눈앞이 캄캄해졌다", josa(name, "은", "는") + " 그대로 기다려요"], next: back, since: now)
        default: return .say([left, "다음 만남에 이어져요"], next: back, since: now)              // fled · ran
        }
    }
    /// The boss's ball stage (the save's: ExpProgress.balls).
    func expBallsPane(_ id: String) -> PaneContent {
        guard let e = Expeditions.of(id), let x = state.expeditions?[id], let m = x.mon, let s = e.steps.first(where: { $0.kind == .fight }) else { return PaneContent() }
        var r = RaidBallsModel(bars: s.bars, total: s.bars, dex: m.dex, shiny: m.shiny == true, name: monNames[m.dex] + " Lv.\(m.level)", note: "잡히면 Lv.\(m.level) · \(m.perfectIVs)V",
                               balls: x.balls ?? 0, of: s.balls, won: true, foot: ["다 놓치면 내일 " + (e.legend == 384 ? "결전" : "보스전") + "부터 다시예요.", "전설과 이로치는 시작 때 정해져 그대로예요."])
        r.exp = true
        return PaneContent(raidBalls: r)
    }
    func expBallsLCD(_ fb: inout FB, _ id: String, _ now: Date) {
        guard let e = Expeditions.of(id), let x = state.expeditions?[id], let m = x.mon, let s = e.steps.first(where: { $0.kind == .fight }) else { return }
        let b = Battle(wild: m, companion: state.companion)
        stage(&fb, b, now, .idle)
        for k in 0..<s.balls { fb.draw(caughtMark, 2 + 7 * k, 2, k < (x.balls ?? 0) ? ballPal : [ballPal[3], rgb(120, 124, 132), rgb(120, 124, 132), ballPal[3]]) }
    }
    /// One ball (the server's dice): the throw on the stage, then caught, the stage again, or — the last missed — tomorrow's boss.
    func expBall(_ id: String, _ now: Date) {
        guard let x = state.expeditions?[id], let m = x.mon, (x.balls ?? 0) > 0, calm else { return }
        act(.expBall(id: id), back: .raid(.expBalls(id)), now, lines: ["볼을", "던질 준비..."]) { [weak self] o, now in
            guard let self, let t = o.raidThrow else { return nil }
            let name = monNames[m.dex]
            if t.caught { raidThen = .say([josa(name, "을", "를") + " 잡았다!", "상자로 보냈다"] + expDoneLines(id), next: expPage(id), since: .distantFuture); expBallsID = nil }
            else if t.balls > 0 { raidThen = .say(["놓쳤다...", "남은 볼 \(t.balls)개"], next: .raid(.expBalls(id)), since: .distantFuture) }
            else { raidThen = .say(["놓쳤다...", "내일 보스전부터 다시"], next: expPage(id), since: .distantFuture); expBallsID = nil }
            usedItem = "몬스터볼"
            let b = Battle(wild: t.mon ?? m, companion: state.companion)
            return .beats(b, [.thrown(shakes: t.caught ? 3 : t.shakes), t.caught ? .caught : .broke], since: now, from: b)
        }
    }
    /// 나중에 던지기 (↩ too): the balls stay in the save; back to the page.
    func expBallsLeave(_ id: String) { expBallsID = nil; screen = expPage(id) }

    // MARK: 홈 and the menu
    /// 홈's row (the user: "내 원정 먼저"): the one going on, else the team event, else one to claim, else a nudge.
    var exp52HomeRow: StatusModel.Row? {
        if let e = expGoing, let (_, s) = expStage(e) {
            let x = expProgress(e), name = monNames[e.legend]
            switch s.kind {
            case .meet: return .init(key: "전설 원정", value: name + " · 오늘 " + (roamCourse(e).map { courses[$0].name } ?? "-") + " · 만남 \(x.meets ?? 0)", bar: roamHP(e, x))
            case .fight:
                if let b = x.balls { return .init(key: "전설 원정", value: name + " · 볼 \(b)개 남았어요", bar: 1) }
                return .init(key: "전설 원정", value: name + " " + (e.legend == 384 ? "결전" : "보스전") + (expFought(x) ? " · 내일 다시" : " · 오늘 1번"), bar: 1)
            default:
                let w = exp52Words(e)
                return .init(key: "전설 원정", value: name + " · " + w.note, bar: w.frac)
            }
        }
        if let t = teamEvent(), Int(Date().timeIntervalSince1970) >= t.starts, !t.got {
            return .init(key: "전설 원정", value: "\(teamName(t)) " + (t.team >= t.goal ? "달성!" : "\(teamPct(t))%") + " · " + teamWhen(t).replacingOccurrences(of: " 남음", with: ""), bar: Double(t.team) / Double(max(1, t.goal)))
        }
        if let e = Expeditions.personal.first(where: expClaimable) { return .init(key: "전설 원정", value: monNames[e.legend] + " 받을 수 있어요", bar: 1) }
        return .init(key: "전설 원정", value: "원정을 골라 시작해요")
    }
    var exp52Note: String {
        if let e = Expeditions.personal.first(where: expClaimable) { return monNames[e.legend] + " 받을 수 있어요" }
        if let e = expGoing { return monNames[e.legend] + " · " + exp52Words(e).note }
        return teamEvent().map { teamName($0) + " 팀 \(teamPct($0))%" } ?? "원정을 골라 시작해요"
    }
    /// The red dot: a claim, or the one going on's balls or meeting waiting.
    var exp52Dot: Bool {
        Expeditions.personal.contains(where: expClaimable) || expGoing.map { e in let x = expProgress(e); return x.balls != nil || (x.meets ?? 0) > 0 } == true
    }
    /// News: a step done (홈's card and a notification), a piece or a meeting (5.1's card for 지가르데's cells).
    func showExpStage(_ id: String, _ stage: Int, _ now: Date) {
        guard let e = Expeditions.of(id) else { return }
        let name = monNames[e.legend], next = e.steps[safe: stage]
        let line: String = next.map { s in
            switch s.kind {
            case .fight: return (e.legend == 384 ? "결전" : "보스전") + "이 열렸다!"
            case .walk: return (expPlace(s) ?? "") + " 코스를 걸을 차례!"
            case .companion: return "검사와 함께 걸을 차례!"
            default: return "다음 단계가 열렸다!"
            }
        } ?? "받을 수 있다!"
        screen = .say([name + " 원정", line], next: .home, since: now)
        notify("pet", name + " 원정: " + line.replacingOccurrences(of: "!", with: ""), "모험 ▸ 전설 원정에서 이어 가요")
    }
}
