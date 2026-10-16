import Foundation
// 5.1 (docs/plans/19 §1 · §9, content51; the user via 회사 10-16: "추천대로", the mockups' 모험 ▸ and 홈's sixth row — lcd-mockups exp-5.1): 전설 원정 —
// 모험 ▸ 전설 원정, one page for every expedition, a row each (its legends, its kind, a bar, what's next), the LCD showing the one picked as 도감 업적
// does. The team event (the server's /v2/expedition: Cloud.expedition) first, then the personal ones (Expeditions.personal, their progress in
// Walk.expeditions: 지금 · 멈춤 · 시작 전 — one going at a time), then what the next updates open, dimmed. ● starts one (or switches to it: the one
// going stops, kept), puts 지가르데 together (the cells' show, Screen.assemble), or goes to a 칼로스 course. 홈 has its own row (expHomeRow).

/// One row of the page.
enum ExpEntry: Equatable {
    case team(TeamEventView)                                           // the server's: the one on (or the next)
    case personal(Expedition)                                          // ours: its progress in the save
    case later(kind: String, name: String, dex: [Int], opens: String)  // what a later update opens (dimmed)
}

struct ExpModel: Equatable {
    struct Row: Equatable { var name, chip, note: String; var dex: [Int]; var frac: Double; var mine: Double? = nil; var off = false, ready = false, done = false }
    var rows: [Row]; var sel: Int; var got: String; var detail: [String]; var go: String?
}

extension Walker {
    /// The kinds the next updates open (plan 19 §1.6: 5.2 roaming · trials, 5.3 the pair · the story), shown dimmed (the user: "양호").
    static let expLater: [ExpEntry] = [.later(kind: "배회", name: "토네로스 · 볼트로스", dex: [641, 642], opens: "5.2"), .later(kind: "시련", name: "성검사 셋", dex: [638, 639, 640], opens: "5.2"),
                                       .later(kind: "협동", name: "레시라무 · 제크로무", dex: [643, 644], opens: "5.3"), .later(kind: "스토리", name: "제르네아스 · 이벨타르", dex: [716, 717], opens: "5.3")]
    /// The 19 Gen V–VI legends an expedition gives (the header's n/19: those caught).
    static let expLegends: Set<Int> = [494, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 716, 717, 718, 719, 720, 721]
    /// The team event to show: the server's first (the one on, else the next), unless it's over.
    func teamEvent(_ now: Date = Date()) -> TeamEventView? { cloud?.expedition?.events.first.flatMap { $0.ends > Int(now.timeIntervalSince1970) ? $0 : nil } }
    var expEntries: [ExpEntry] { (teamEvent().map { [.team($0)] } ?? []) + Expeditions.personal.map { .personal($0) } + Walker.expLater }
    func expProgress(_ e: Expedition) -> ExpProgress { state.expeditions?[e.id] ?? ExpProgress() }
    /// The personal one going now (one at a time: plan 19 §6.3).
    var expGoing: Expedition? { Expeditions.personal.first { expProgress($0).on } }
    func expReady(_ e: Expedition) -> Bool { let p = expProgress(e); return p.mon != nil && p.n >= e.need }
    var expDot: Bool { Content.v51 && Expeditions.personal.contains(where: expReady) }
    func teamName(_ t: TeamEventView) -> String { t.legend > 0 ? monNames[t.legend] : "앙코르" }
    func teamPct(_ t: TeamEventView) -> Int { min(100, t.team * 100 / max(1, t.goal)) }
    /// Its days left (or how soon it starts).
    func teamWhen(_ t: TeamEventView, _ now: Date = Date()) -> String {
        let n = Int(now.timeIntervalSince1970)
        if n < t.starts { return "\(max(1, (t.starts - n + 86_399) / 86_400))일 뒤 시작" }
        return "\(max(1, (t.ends - n + 86_399) / 86_400))일 남음"
    }
    /// 10,000 → "1만", 12,400 → "1.2만", 931,200 → "93만".
    func man(_ n: Int) -> String {
        guard n >= 10_000 else { return n.formatted() }
        let v = Double(n) / 10_000; return (v >= 10 || v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)) + "만"
    }
    /// A row's kind chip and its short line.
    func expWords(_ x: ExpEntry) -> (chip: String, note: String) {
        switch x {
        case .team(let t):
            if t.got { return ("팀 이벤트", "받았어요 · 우편함에서") }
            return ("팀 이벤트 · " + teamWhen(t), (t.team >= t.goal ? "달성!" : "팀 \(teamPct(t))%") + " · 내 \(man(t.mine))/\(man(t.min))" + (t.mine >= t.min ? " ✓" : ""))
        case .later(let kind, _, _, let opens): return (kind, "\(opens) 업데이트에 열려요")
        case .personal(let e):
            let p = expProgress(e), unit = e.piece.components(separatedBy: " ").last ?? ""
            if p.mon == nil { return (e.kind == .collect ? "수집" : "원정", "시작 전") }
            if !p.on { return ("수집 · 멈춤", "\(unit) \(p.n)/\(e.need) · 멈춤") }
            return ("수집 · 지금", expReady(e) ? "\(p.n)/\(e.need) · 조립할 수 있어요" : "\(unit) \(p.n)/\(e.need) · 다음 \(max(0, e.stepsPer - p.steps).formatted())걸음")
        }
    }
    func expName(_ x: ExpEntry) -> String {
        switch x { case .team(let t): teamName(t); case .personal(let e): monNames[e.legend]; case .later(_, let name, _, _): name }
    }
    func expDex(_ x: ExpEntry) -> [Int] {
        switch x { case .team(let t): t.legend > 0 ? [t.legend] : Array((t.encore ?? []).prefix(3)); case .personal(let e): [e.legend]; case .later(_, _, let d, _): d }
    }
    /// The pick's two lines under the rows, and its button (nil: none).
    func expDetail(_ x: ExpEntry) -> (lines: [String], go: String?) {
        switch x {
        case .team(let t):
            if t.got { return (["팀 이벤트 보상을 받았어요", "우편함에서 받아요"], nil) }
            return (["7일 동안 \(man(t.min))걸음 넘게 걸으면 모두 받아요", t.team >= t.goal ? "팀 목표 달성! 끝나는 날 우편으로 와요" : "팀 목표 \(man(t.goal))걸음 · 남은 \(man(max(0, t.goal - t.team)))걸음"], nil)
        case .later(_, _, _, let opens): return (["\(opens) 업데이트에 열려요"], nil)
        case .personal(let e):
            let p = expProgress(e), going = expGoing.flatMap { $0.id == e.id ? nil : $0 }
            if expReady(e) { return (["모은 \(e.piece) \(e.need)개로 " + josa(monNames[e.legend], "을", "를") + " 조립해요"], "조립하기") }
            if let g = going, !p.on { return (["원정은 한 번에 하나 · 지금: \(monNames[g.legend])", "바꾸면 지금 것은 멈추고, 나중에 이어 할 수 있어요"], (p.mon != nil ? "이어 하기" : "바꾸기") + " · 지금 것은 멈춰요") }
            if p.mon != nil, !p.on { return (["멈춘 원정 · 모은 \(e.piece.components(separatedBy: " ").last ?? "")은 그대로예요", "멈춘 동안은 걸음이 쌓이지 않아요"], "이어 하기") }
            if p.mon == nil { return (["칼로스 코스 \(e.stepsPer.formatted())걸음마다 \(e.piece) 1개 · \(e.need)개면 \(monNames[e.legend])", "원정은 한 번에 하나만 할 수 있어요"], "시작하기") }
            let here = e.counts(state.here), left = max(0, e.stepsPer - p.steps).formatted()
            return (["칼로스 코스 \(e.stepsPer.formatted())걸음마다 1개 · 칼로스 레이더에서도 가끔", here ? "다음까지 \(left)걸음 · 지금 칼로스 코스예요" : "다음까지 \(left)걸음 · 지금 코스는 칼로스가 아니에요"], here ? nil : "칼로스 코스로")
        }
    }
    func expPane(_ sel: Int) -> PaneContent {
        let list = expEntries, s = min(max(0, sel), list.count - 1)
        let rows = list.map { x -> ExpModel.Row in
            let w = expWords(x)
            switch x {
            case .team(let t):
                return .init(name: expName(x), chip: w.chip, note: w.note, dex: expDex(x), frac: Double(t.team) / Double(max(1, t.goal)), mine: Double(t.mine) / Double(max(1, t.min)), done: t.got || t.team >= t.goal)
            case .personal(let e):
                let p = expProgress(e)
                return .init(name: expName(x), chip: w.chip, note: w.note, dex: expDex(x), frac: Double(p.n) / Double(max(1, e.need)), ready: expReady(e))
            case .later: return .init(name: expName(x), chip: w.chip, note: w.note, dex: expDex(x), frac: 0, off: true)
            }
        }
        let d: (lines: [String], go: String?) = list[safe: s].map(expDetail) ?? ([], nil), got = Walker.expLegends.filter { (state.owned ?? []).contains($0) }.count
        return PaneContent(exp: ExpModel(rows: rows, sel: s, got: "전설 \(got)/\(Walker.expLegends.count)종", detail: d.lines, go: d.go))
    }
    func expLCD(_ fb: inout FB, _ sel: Int) {
        let list = expEntries, s = min(max(0, sel), list.count - 1), x = 44
        fb.text("전설 원정", 2, 0); fb.text("\(s + 1)/\(list.count)", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
        guard let e = list[safe: s] else { return }
        func bar(_ y: Int, _ have: Int, _ of: Int) {
            let len = 94 - x, done = of > 0 ? min(len, len * have / of) : 0, c = LCDDeco.tones(.course).band
            for k in 0..<len { for dy in 0..<3 { fb.set(x + k, y + dy, k < done ? 3 : 1, k < done ? c : 0) } }
        }
        if let d = expDex(e).first {
            let m = Mon(dex: d, level: 50, female: false)                                          // (no 이로치 here: it shows when it comes, plan 19 §1.3)
            if case .later = e { fb.mon(m, 0, 0, 2, tint: (1, 0)) } else { fb.mon(m, 0, 0, 2) }
        }
        switch e {
        case .team(let t):
            fb.name(teamName(t), x, 13, 94 - x)
            bar(26, t.team, t.goal)
            fb.line(t.got ? "받았어요" : "팀 \(teamPct(t))%", x, 31, 94 - x, t.team >= t.goal ? 3 : 2)
            fb.line("내 \(man(t.mine))/\(man(t.min))" + (t.mine >= t.min ? " ✓" : ""), x, 40, 94 - x, t.mine >= t.min ? 3 : 2)
            fb.line(teamWhen(t), x, 49, 94 - x)
        case .later(let kind, let name, _, let opens):
            fb.name(kind, x, 13, 94 - x); fb.line(name.replacingOccurrences(of: " · ", with: "·"), x, 26, 94 - x, 1)
            fb.line(opens + "에", x, 37, 94 - x); fb.line("열려요", x, 46, 94 - x)
        case .personal(let pe):
            let p = expProgress(pe), unit = pe.piece.components(separatedBy: " ").last ?? ""
            fb.name(monNames[pe.legend], x, 13, 94 - x)
            if p.mon == nil { fb.line("시작 전", x, 26, 94 - x, 1); fb.line(expGoing != nil ? "● 바꾸기" : "● 시작하기", x, 40, 94 - x, 3); return }
            bar(26, p.n, pe.need)
            fb.line("\(unit) \(p.n)/\(pe.need)", x, 31, 94 - x, expReady(pe) ? 3 : p.on ? 2 : 1)
            if expReady(pe) { fb.line("● 조립하기", x, 44, 94 - x, 3) }
            else if !p.on { fb.line("멈춤", x, 40, 94 - x, 1); fb.line("● 이어 하기", x, 49, 94 - x, 3) }
            else { fb.line("다음 \(unit)", x, 40, 94 - x); fb.line("\(max(0, pe.stepsPer - p.steps).formatted())걸음", x, 49, 94 - x) }
        }
    }
    /// ◀ ▶ a row; ● its button: start (or switch to it: the one going stops, asked first), put it together (its show), or a 칼로스 course.
    func expPress(_ k: Int, _ sel: Int, _ now: Date) {
        let list = expEntries, n = max(1, list.count)
        if k != 1 { screen = .expedition((sel + (k == 0 ? -1 : 1) + n) % n); return }
        guard case .personal(let e)? = list[safe: sel], let go = expDetail(.personal(e)).go else { return }
        let here = Screen.expedition(sel), name = monNames[e.legend]
        switch go {
        case "조립하기":
            act(.expClaim(id: e.id), back: here, now) { [weak self] o, now in
                guard let self, let m = o.mon else { return nil }
                let gift = o.news.lazy.compactMap { n -> String? in if case .expeditionDone(_, _, let g) = n { return g }; return nil }.first ?? nil
                self.expAfter = .say([josa(name, "을", "를"), "상자에 보냈다!"] + (gift.map { [josa($0, "을", "를") + " 받았다!"] } ?? []), next: here, since: now)
                return .assemble(m, since: now)
            }
        case "칼로스 코스로":
            screen = .course(courses.indices.first { courses[$0].region == e.region && state.unlocked($0) } ?? state.course)
        default:
            if let g = expGoing, g.id != e.id,
               host?.confirm(name + " 원정으로 바꿀까요?", "지금 하는 " + monNames[g.legend] + " 원정은 멈추고, 모은 것은 그대로 남아요. 나중에 이어 할 수 있어요.", ok: "바꾸기") == false { return }
            let resume = expProgress(e).mon != nil
            act(.expStart(id: e.id), back: here, now) { _, now in .say([name + " 원정을", resume ? "이어 간다!" : "시작했다!"], next: here, since: now) }
        }
    }
    /// 홈's sixth row (the user: "그냥 한줄 늘리는게 낫지 않아?"): the team event's bar while one is on, else the personal one going (its cells), else a nudge.
    var expHomeRow: StatusModel.Row? {
        guard Content.v51 else { return nil }
        if let t = teamEvent(), Int(Date().timeIntervalSince1970) >= t.starts, !t.got {
            return .init(key: "전설 원정", value: "\(teamName(t)) " + (t.team >= t.goal ? "달성!" : "\(teamPct(t))%") + " · " + teamWhen(t).replacingOccurrences(of: " 남음", with: ""), bar: Double(t.team) / Double(max(1, t.goal)))
        }
        if let e = Expeditions.personal.first(where: expReady) { return .init(key: "전설 원정", value: monNames[e.legend] + " 조립할 수 있어요", bar: 1) }
        if let e = expGoing { let p = expProgress(e); return .init(key: "전설 원정", value: e.piece + " \(p.n)/\(e.need)", bar: Double(p.n) / Double(max(1, e.need))) }
        return .init(key: "전설 원정", value: "원정을 골라 시작해요")
    }
    /// The menu's line for 전설 원정.
    var expNote: String {
        if let e = Expeditions.personal.first(where: expReady) { return monNames[e.legend] + " 조립할 수 있어요" }
        let team = teamEvent().map { teamName($0) + " 팀 \(teamPct($0))%" }, mine = expGoing.map { e in "\(e.piece.components(separatedBy: " ").last ?? "") \(expProgress(e).n)/\(e.need)" }
        return [team, mine].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "원정을 골라 시작해요"
    }
    /// A cell came (News.expedition): 홈's card with the cell big.
    func showExpedition(_ id: String, _ n: Int, _ need: Int, _ now: Date) {
        guard let e = Expeditions.of(id) else { return }
        let lines = [josa(e.piece, "을", "를"), "모았다!", "\(n)/\(need)"]
        sayStone = (lines, "지가르데셀"); screen = .say(lines, next: .home, since: now)
        if n == need { notify("pet", "\(e.piece) \(need)개가 모였어요", "모험 ▸ 전설 원정에서 " + josa(monNames[e.legend], "을", "를") + " 조립할 수 있어요") }
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

extension FB {
    /// 지가르데 셀이 모인다 (5.5 s): the cells come in from the stage's edges, round and round (to 2.2 s); they glow as one (to 2.6 s); white;
    /// 지가르데 out of the light, sparkling (hatchFX's light). The message row is the caller's.
    mutating func assembleFX(_ m: Mon, _ u: Double, bob: Int) {
        let cx = 96, cy = 50, glow = rgb(150, 240, 140)
        if u < 2.6 {
            let n = 14
            for i in 0..<n {
                let start = Double(i) * 0.06, p = max(0, min(1, (u - start) / (2.2 - start))), ease = p * p * (3 - 2 * p)
                let a = Double(i) / Double(n) * 2 * .pi + ease * 2.6, r = (1 - ease) * (70 + 18 * hash01(i + 11)) + 2
                if u < 2.35 || i % 3 == 0 { pic("w.cell", cx + Int(cos(a) * r * 1.25), cy + Int(sin(a) * r * 0.62), scale: 1.0 - 0.35 * ease, alpha: min(1, u / 0.3)) { itemPic("지가르데셀") } }
            }
            if u > 1.4 { stageGlow("cells", cx, cy, 30, 26, glow, hot: true, alpha: min(1, (u - 1.4) / 0.8)) }
        } else if u < 2.9 { pic("w.glow|cells", cx, cy, scale: min(1, 0.4 + (u - 2.6) / 0.2 * 0.6)) { glowPic(96, 46, glow, hot: true) } }
        if u >= 2.95 {
            let g = min(1, (u - 2.95) / 0.45), s = 0.3 + 0.7 * (1 - (1 - g) * (1 - g)), top = spriteTop(m.art)
            if u < 3.9 { stageGlow("zyg", 96, 98 - (80 - top) / 2, 40, 36, glow, hot: true, alpha: min(1, (3.9 - u) / 0.6)) }
            showMon(m, scale: s, bob: u > 3.8 ? bob : 0, anim: u > 3.8 ? u - 3.8 : nil)
            if u < 3.75 { showMon(m, scale: s, alpha: min(1, (3.75 - u) / 0.4), tint: rgb(255, 255, 255)) }
        }
        whiteOut(u < 2.7 ? 0 : u < 2.85 ? (u - 2.7) / 0.15 : u < 3.0 ? 1 : 1 - (u - 3.0) / 0.45)
        if u > 3.3 { let top = spriteTop(m.art); sparkles(u - 3.3, 96, 98 - (80 - top) / 2, Double(80 - top) / 2 + 14, n: m.shiny == true ? 8 : 6, big: m.shiny == true || u < 4.6) }
    }
}
