import Foundation
// 5.3 (docs/plans/19 §12, content53; the user via 회사 11-07: "이대로 진행" — the mockups lcd-mockups docs/mockups/v5.3, 1bcc13d): 전설 원정's
// 협동 (레시라무 · 제크로무 → 큐레무) and 스토리 (칼로스 이야기 1~4장 → 제르네아스 · 이벨타르, then 5장) on the Model's steps (pair · trainer ·
// dex · pick) and the server's pairs and scenes (/v2/expedition: PairView, StoryScene). 협동: 짝 청하기 from the 협동 tab or a friend's card
// (the friends; one in a pair or before 5.3 dimmed), an ask taken with my dragon (two cards), walking together (one bar: mine red, theirs
// blue, each one's 30,000, the days left), 짝 풀기 · 거두기 · 거절 (pairCancel), alone while there's no pair. 스토리: the chapters as five steps
// (1~4장 · 결전), the 칼로스 도감 gate, 플레어단's trainers (1–3 of ours, as often as it takes), the pick of two (expPick), the final fight
// (5.2's boss: it comes with the win), its scenes — two lines a page, the speaker's picture on the LCD — each once when its stage comes or
// its fight is won (이야기 다시 보기: the stage's again). The tabs: 지금 · 배회 · 시련 · 수집 · 협동 · 스토리 · 팀 (no 예정: all 19 open).

/// The story's speakers' pictures (frames.bin: Pokémon Showdown's trainer sprites — tools/gen.py, README's credits).
let storyFrames: [String: String] = ["플레어단 조무래기": "flaregrunt", "플레어단 간부": "mable", "플레어단 과학자": "xerosic", "플레어단 보스 플라드리": "lysandre",
                                     "플라드리": "lysandre", "플라타느 박사": "sycamore"]

extension Walker {
    // MARK: what 5.3 owns
    var pairs: [PairView] { cloud?.expedition?.pairs ?? [] }
    func pairOn(_ id: String) -> PairView? { pairs.first { $0.state == "on" && $0.mine == id } }
    func pairSent(_ id: String) -> PairView? { pairs.first { $0.state == "sent" && $0.mine == id } }
    var pairAsks: [PairView] { pairs.filter { $0.state == "got" } }
    var pairWalking: PairView? { pairs.first { $0.state == "on" } }
    static let dragons = [643, 644]                                                                    // 레시라무 · 제크로무: their expeditions' ids are their names
    func dragonDex(_ id: String?) -> Int { id.flatMap { Expeditions.of($0)?.legend } ?? (id == "제크로무" ? 644 : 643) }
    func daysLeft(_ ends: Int, _ now: Date = Date()) -> Int { max(1, (ends - Int(now.timeIntervalSince1970) + 86_399) / 86_400) }
    /// The 5.3 screens' own: the story, a dragon on its pair step (its boss and balls are 5.2's).
    func exp53Owns(_ e: Expedition) -> Bool { e.kind == .story || (e.kind == .pair && e.legend != 646 && (expStage(e)?.s.kind ?? .pair) == .pair) }
    func expRowName(_ e: Expedition) -> String { e.kind == .story ? e.title : monNames[e.legend] }
    /// 5장's legend: the one not picked in 칼로스 이야기 (the Model's rule).
    var story5Legend: Int { let p = state.expeditions?[Expeditions.story]?.pick; return Expeditions.storyPicks.first { $0 != p } ?? 717 }
    func expRowDex(_ e: Expedition) -> [Int] {
        if e.id == Expeditions.story5 { return [story5Legend] }
        if e.kind == .story { return expProgress(e).pick.map { [$0] } ?? Expeditions.storyPicks }
        return [e.legend]
    }
    func kalosCaught(_ s: ExpStage) -> Int { (state.owned ?? []).filter { (s.region ?? Expeditions.kalos).contains($0) }.count }
    func short(_ trainer: String) -> String { trainer.replacingOccurrences(of: "플레어단 ", with: "").replacingOccurrences(of: "보스 ", with: "") }   // 조무래기 · 간부 · 과학자 · 플라드리
    /// A friend's name where a line has little room: as is up to 6 letters, else "친구" (the full name is on the lines with room).
    func pal(_ name: String) -> String { name.count <= 6 ? name : "친구" }
    func storyNextTrainer(_ e: Expedition, _ k: Int) -> String? { e.steps.dropFirst(k).first { $0.kind == .trainer }?.trainer }

    // MARK: the rows
    func exp53Rows(_ tab: Int) -> [ExpRow] {
        let all = Expeditions.personal, asks = pairAsks.map { ExpRow.ask($0) }
        switch Walker.expTabs[safe: tab] ?? "" {
        case "지금":
            let begun = all.filter(expBegun), team = teamEvent().map { [ExpRow.team($0)] } ?? []
            return team + asks + (begun.filter { expProgress($0).on } + begun.filter { !expProgress($0).on }).map { .exp($0) }
        case "배회": return all.filter { $0.kind == .roam }.map { .exp($0) }
        case "시련": return all.filter { $0.kind == .trial }.map { .exp($0) }
        case "수집": return all.filter { $0.kind == .collect }.map { .exp($0) }
        case "협동": return asks + all.filter { $0.kind == .pair }.map { .exp($0) }
        case "스토리": return all.filter { $0.kind == .story }.map { .exp($0) }
        default: return (cloud?.expedition?.events ?? []).prefix(Walker.expPerTab).map { .team($0) }
        }
    }
    func askRow(_ a: PairView) -> ExpModel.Row {
        .init(name: a.with, chip: "협동 · 받음", note: "짝 청하기 · " + a.theirs + " · \(daysLeft(a.ends))일 안에", dex: [dragonDex(a.theirs)], frac: 0, ready: true)
    }
    func askDetail(_ a: PairView) -> (lines: [String], go: String?, act: ExpGo?, go2: String?) {
        let going = expGoing.map(expRowName)
        return ([josa(a.with, "이", "가") + " " + josa(a.theirs, "으로", "로") + " 짝을 청했어요", "나는 내 용을 골라요(같은 용도 돼요)",
                 "받으면 14일 안에 둘이 30만 걸음 · 각자 3만 이상 · 어느 코스든",
                 going.map { "받으면 " + $0 + " 원정은 멈춰요 · 모은 것은 그대로" } ?? "원정은 한 번에 하나 · 받으면 협동이 지금 원정이 돼요"], "받기 · 내 용 고르기", .pick, "거절")
    }
    func askLCD(_ fb: inout FB, _ a: PairView) {
        fb.mon(Mon(dex: dragonDex(a.theirs), level: 50, female: false), 0, 0, 2)
        fb.runs.removeAll { $0.y < 12 }; fb.name(a.with, 2, 0, 92)                                                   // (its title: who asks, the whole width)
        fb.name("짝 청하기", 44, 13, 50); fb.line(josa(a.theirs, "으로", "로"), 44, 26, 50, 2); fb.line("\(daysLeft(a.ends))일 안에", 44, 35, 50, 1); fb.line("● 받기", 44, 48, 50, 3)
    }
    func exp53Words(_ e: Expedition, _ now: Date) -> (chip: String, note: String, frac: Double, hp: Bool, ready: Bool, done: Bool, off: Bool) {
        let x = expProgress(e), kind = expKindName(e)
        if expLocked(e) { return (kind + " · 잠김", (e.id == Expeditions.story5 ? "칼로스 이야기" : expAfterWho(e)) + "를 먼저", 0, false, false, false, true) }
        if e.kind == .pair {
            let sent = pairSent(e.id)
            if x.mon == nil {
                if let s = sent { return (kind + " · 청함", pal(s.with) + " 대답 기다림 · \(daysLeft(s.ends))일", 0, false, false, false, false) }
                return x.done > 0 ? (kind + " · 끝냄", "잡았어요 ✓ · 다시 할 수 있어요", 1, false, false, true, false) : (kind, "시작 전", 0, false, false, false, false)
            }
            if let p = pairOn(e.id) { let sum = p.steps + p.theirSteps; return (kind + " · 지금", "둘이 \(man(sum))/\(man(p.goal)) · \(daysLeft(p.ends))일", Double(sum) / Double(p.goal), false, false, false, false) }
            let solo = "혼자 \(man(x.steps))/\(man(Expeditions.soloGoal))"
            return (kind + " · " + (x.on ? "지금" : "멈춤"), solo + (sent.map { " · " + pal($0.with) + "에게 청함" } ?? ""), Double(x.steps) / Double(Expeditions.soloGoal), false, false, false, false)
        }
        if x.mon == nil { return x.done > 0 ? (kind + " · 끝냄", "끝냈어요 ✓ · 다시 할 수 있어요", 1, false, false, true, false) : (kind, "시작 전", 0, false, false, false, false) }
        guard let (_, s) = expStage(e) else { return (kind, "", 0, false, false, false, false) }
        let lead = "\(s.chapter)장 · ", on = x.on ? "지금" : "멈춤"
        switch s.kind {
        case .walk: return (kind + " · " + on, lead + "칼로스 \(man(x.steps))/\(man(s.need))", Double(x.steps) / Double(max(1, s.need)), false, false, false, false)
        case .trainer: return (kind + " · 배틀", lead + josa(short(s.trainer), "과", "와") + " 배틀", 1, false, x.on, false, false)
        case .dex: let n = kalosCaught(s); return (kind + " · " + on, lead + "칼로스 도감 \(n)/\(s.need)종", Double(n) / Double(max(1, s.need)), false, false, false, false)
        case .pick: return (kind + " · 고르기", "4장 · 결전 상대를 골라요", 1, false, x.on, false, false)
        case .fight: return (kind + " · 결전", (x.mon.map { monNames[$0.dex] } ?? "") + " · " + (expFought(x, now) ? "내일 다시" : "오늘 1번"), 1, false, x.on && !expFought(x, now), false, false)
        default: return (kind, "", 0, false, false, false, false)
        }
    }
    /// Something waits on the one going on (the menu's red dot): a friend's ask, a story fight or pick.
    var exp53Dot: Bool {
        if !pairAsks.isEmpty { return true }
        guard let e = expGoing, e.kind == .story, let (_, s) = expStage(e) else { return false }
        return s.kind == .trainer || s.kind == .pick || (s.kind == .fight && !expFought(expProgress(e)))
    }
    /// The steps under the rows: a dragon's 함께 걷기 → 보스전 → 볼; the story's chapters (1~4장, 결전); 5장's 도감 → 걷기 → 결전.
    func exp53Strip(_ e: Expedition, _ now: Date) -> [ExpModel.Step] {
        let x = expProgress(e), k = x.mon == nil ? -1 : (x.stage ?? 0), locked = expLocked(e)
        func st(cur: Bool, done: Bool) -> Int { locked || k < 0 ? 0 : done ? 2 : cur ? 1 : 0 }
        if e.kind == .pair {
            let p = pairOn(e.id)
            let walk = p.map { man($0.steps + $0.theirSteps) + "/30만" } ?? (k == 0 ? "혼자 " + man(x.steps) + "/20만" : "둘이 30만 · 혼자 20만")
            return [ExpModel.Step(title: p != nil ? "둘이 걷기" : "함께 걷기", sub: walk, state: st(cur: k == 0, done: k > 0)),
                    ExpModel.Step(title: "보스전", sub: k == 1 && x.balls == nil ? (expFought(x, now) ? "내일 다시" : "오늘 1번") : "하루 1번", state: st(cur: k == 1 && x.balls == nil, done: k > 1 || x.balls != nil)),
                    ExpModel.Step(title: "볼 5개", sub: x.balls.map { "남은 \($0)개" } ?? "한 개 30%", state: st(cur: x.balls != nil, done: false))]
        }
        if e.id == Expeditions.story5 {
            let other = monNames[story5Legend]
            return e.steps.enumerated().map { i, s in
                let t: (String, String) = s.kind == .dex ? ("칼로스 도감", k == i ? "\(kalosCaught(s))/\(s.need)종" : "\(s.need)종") : s.kind == .walk ? ("칼로스 코스", k == i ? man(x.steps) + "/" + man(s.need) : man(s.need) + "걸음") : ("결전", other)
                return ExpModel.Step(title: t.0, sub: t.1, state: st(cur: k == i, done: k > i))
            }
        }
        let chapterNow = e.steps[safe: max(0, k)]?.chapter ?? 1, s = e.steps[safe: max(0, k)]
        let finale = s.map { $0.kind == .pick || $0.kind == .fight } ?? false
        var out: [ExpModel.Step] = (1...4).map { c in
            let cur = k >= 0 && c == chapterNow && !finale, done = k >= 0 && (c < chapterNow || (c == 4 && finale))
            var sub = done ? "끝" : c == 3 ? "도감 5종" : "2만걸음"
            if cur, let s {
                switch s.kind {
                case .walk: sub = man(x.steps)
                case .trainer: sub = "배틀"
                case .dex: sub = "\(kalosCaught(s))/\(s.need)종"
                default: break
                }
            }
            return ExpModel.Step(title: "\(c)장", sub: sub, state: st(cur: cur, done: done))
        }
        out.append(ExpModel.Step(title: "결전", sub: finale ? (s?.kind == .pick ? "고르기" : expFought(x, now) ? "내일" : "오늘") : "택 1", state: st(cur: finale, done: false)))
        return out
    }
    /// The pick's lines, its two buttons and what they do, the pair's panel.
    func exp53Detail(_ e: Expedition, _ now: Date) -> (lines: [String], go: String?, act: ExpGo?, go2: String?, act2: ExpGo?, pair: PairPanel?) {
        let x = expProgress(e), name = expRowName(e), g = expGoing.flatMap { $0.id == e.id ? nil : $0 }, going = g.map(expRowName)
        if expLocked(e) {
            return (e.id == Expeditions.story5 ? ["칼로스 이야기(1~4장)를 끝내면 열려요", "고르지 않은 전설(" + monNames[story5Legend] + ")과 결전 · 칼로스 도감 10종 · 칼로스 4만 걸음"] : [expAfterWho(e) + " 잡으면 열려요"], nil, nil, nil, nil, nil)
        }
        if e.kind == .pair {
            let sent = pairSent(e.id), p = pairOn(e.id)
            let sentLine = sent.map { $0.with + "에게 청했어요 · \(daysLeft($0.ends))일 안에 받으면 짝이 돼요" }
            if let p {
                let panel = PairPanel(with: p.with, theirDex: dragonDex(p.theirs), mine: p.steps, theirs: p.theirSteps, goal: p.goal, least: p.min, days: daysLeft(p.ends, now))
                let short = max(0, p.min - p.steps)
                return ([short > 0 ? "내 몫이 3만이 안 돼요 · \(man(short))걸음 더 걸어야 해요" : "내 몫 3만은 넘었어요 · 둘이 30만이면 각자 보스전",
                         "어느 코스든 세요 · 다른 원정으로 바꾸면 짝이 풀리고 둘의 걸음은 사라져요"], nil, nil, "짝 풀기", .cancel, panel)
            }
            if x.mon != nil, x.on {
                let panel = PairPanel(with: nil, theirDex: nil, mine: x.steps, theirs: 0, goal: Expeditions.soloGoal, least: 0, days: nil)
                return ([sentLine ?? "혼자 걷는 중 · 어느 코스든 · 기한은 없어요", "짝을 지으면 둘이 30만(14일) · 그동안 혼자 걸음은 쉬어요"],
                        sent == nil ? "짝 청하기" : nil, sent == nil ? .invite : nil, sent == nil ? nil : "청하기 거두기", sent == nil ? nil : .cancel, panel)
            }
            if x.mon != nil { return (["멈춘 원정 · 혼자 걸은 \(man(x.steps))걸음은 그대로예요", "멈춘 동안은 걸음이 쌓이지 않아요"] + (sentLine.map { [$0] } ?? []), "이어 하기", .start, sent == nil ? "짝 청하기" : nil, sent == nil ? .invite : nil, nil) }
            var lines = ["친구와 짝을 지어 14일 안에 둘이 30만 걸음 · 각자 3만 이상", "혼자 하면 20만 걸음 · 기한 없음 · 어느 코스든"]
            if let s = sentLine { lines.append(s); lines.append("청하기는 자리를 차지하지 않아요" + (going.map { " · " + $0 + "은 그대로" } ?? "")) }
            else { lines.append(going.map { "청하기는 자리를 차지하지 않아요 · " + $0 + " 원정은 그대로" } ?? "친구는 레시라무 · 제크로무 중 하나를 골라요(같아도 돼요)") }
            return (lines, sent == nil ? "짝 청하기" : "청하기 거두기", sent == nil ? .invite : .cancel, going == nil ? "혼자 시작" : "혼자 시작 · 바꾸기", .start, nil)
        }
        // 스토리
        if x.mon == nil {
            let first = e.id == Expeditions.story5
                ? ["칼로스 도감 10종 → 칼로스 4만 걸음 → " + josa(monNames[story5Legend], "과", "와") + " 결전", "이기면 반드시 와요"]
                : ["칼로스에서 플레어단을 쫓는 이야기 · 1~4장", "장마다 칼로스 코스 2만 걸음 → 플레어단 트레이너와 배틀", "4장 끝에 제르네아스 · 이벨타르 중 하나와 결전 · 이기면 꼭 와요"]
            return (first + (going.map { ["원정은 한 번에 하나 · 지금: " + $0] } ?? []), x.done > 0 ? "다시 하기" : g != nil ? "바꾸기 · 지금 것은 멈춰요" : "시작하기", .start, nil, nil, nil)
        }
        if !x.on { return (["멈춘 원정 · " + "\(expStage(e)?.s.chapter ?? 1)장의 걸음은 그대로예요", "멈춘 동안은 걸음이 쌓이지 않아요"], g.flatMap { pairOn($0.id) } != nil ? "이어 하기 · 짝이 풀려요" : "이어 하기", .start, nil, nil, nil) }
        guard let (k, s) = expStage(e) else { return ([], nil, nil, nil, nil, nil) }
        let again = "이야기 다시 보기"
        switch s.kind {
        case .walk:
            let here = s.counts(state.here), next = storyNextTrainer(e, k)
            return ([here ? "\(s.chapter)장 · 지금 \(state.here.name) · 남은 \(man(s.need - x.steps))걸음" : "\(s.chapter)장 · 지금 코스(\(state.here.name))는 세지 않아요",
                     "칼로스 코스 어디서든 · 다 걸으면 " + (next.map { josa(short($0), "과", "와") + " 배틀" } ?? "결전")],
                    here ? again : "칼로스 코스로", here ? .talk : expCourse(e, s).map { .course($0) }, here ? nil : again, here ? nil : .talk, nil)
        case .trainer:
            return ([s.trainer + " · " + s.foes.map { monNames[$0] }.joined(separator: " · ") + " Lv.\(s.level)", "내 포켓몬 1~3마리 · 몇 번이든 · 지면 다시 해요"],
                    "배틀 · " + short(s.trainer), .trainer, again, .talk, nil)
        case .dex:
            let n = kalosCaught(s)
            return (["칼로스 도감 \(n)/\(s.need)종 · \(s.need)종이 되면 저절로 \(s.chapter)장이 열려요", "칼로스 코스의 레이더에서 만나요 · 칼로스 들판은 처음부터 열려 있어요"],
                    "칼로스 도감 보기", .dex, again, .talk, nil)
        case .pick:
            return (["플라드리를 이겼어요! 결전 상대를 골라요", "고른 쪽과 결전 · 이기면 반드시 와요 · 바꿀 수 없어요", "다른 하나는 5장에서 만나요"], "결전 상대 고르기", .pick, again, .talk, nil)
        case .fight:
            let m = x.mon.map { monNames[$0.dex] } ?? name
            if expFought(x, now) { return (["오늘은 싸웠어요 · 내일 0시부터 다시 싸워요", "지면 그날은 끝 · " + josa(m, "은", "는") + " 그대로 기다려요"], nil, nil, again, .talk, nil) }
            return ([m + " Lv.\(s.level) · 바 \(s.bars)개 · 내 포켓몬 1~3마리", "이기면 반드시 와요 · 하루 1번 · 지면 다음 날"], "결전 · 오늘 1번", .boss, again, .talk, nil)
        default: return ([], nil, nil, nil, nil, nil)
        }
    }
    func exp53LCD(_ fb: inout FB, _ e: Expedition, _ now: Date) {
        let x = expProgress(e), xx = 44, grey: (UInt8, UInt32) = (3, rgb(150, 156, 168))
        func bar(_ y: Int, _ a: Double, _ b: Double = 0) {                                                 // mine red, the friend's blue after it
            let len = 94 - xx, da = min(len, Int(Double(len) * max(0, min(1, a)))), db = min(len - da, Int(Double(len) * max(0, min(1, b))))
            for k in 0..<len { for dy in 0..<3 { fb.set(xx + k, y + dy, k < da + db ? 3 : 1, k < da ? rgb(232, 72, 56) : k < da + db ? rgb(70, 120, 220) : 0) } }
        }
        let locked = expLocked(e), name = e.kind == .story ? (e.id == Expeditions.story5 ? "5장" : "칼로스 이야기") : monNames[e.legend]
        if e.kind == .pair {
            fb.mon(Mon(dex: e.legend, level: 50, female: false), 0, 0, 2, tint: locked ? grey : nil); fb.name(name, xx, 13, 94 - xx)
            if let pr = pairOn(e.id) {
                bar(26, Double(pr.steps) / Double(pr.goal), Double(pr.theirSteps) / Double(pr.goal))
                fb.line("둘 \(man(pr.steps + pr.theirSteps))", xx, 31, 94 - xx, 2); fb.line("/\(man(pr.goal))걸음", xx, 40, 94 - xx, 2); fb.line("\(daysLeft(pr.ends, now))일 남음", xx, 49, 94 - xx, daysLeft(pr.ends, now) <= 3 ? 3 : 1)
                return
            }
            if let s = pairSent(e.id), x.mon == nil { fb.line("청함", xx, 26, 94 - xx, 1); fb.line("대답 기다림", xx, 37, 94 - xx, 2); fb.line("\(daysLeft(s.ends))일 안에", xx, 46, 94 - xx, 1); return }
            if x.mon == nil { fb.line(x.done > 0 ? "잡았다 ✓" : "시작 전", xx, 26, 94 - xx, 1); fb.line("● 짝 청하기", xx, 40, 94 - xx, 3); return }
            bar(26, Double(x.steps) / Double(Expeditions.soloGoal)); fb.line("혼자 \(man(x.steps))", xx, 31, 94 - xx, 2); fb.line("/\(man(Expeditions.soloGoal))걸음", xx, 40, 94 - xx, 2)
            fb.line(x.on ? "기한 없음" : "멈춤", xx, 49, 94 - xx, 1); return
        }
        guard let (k, s) = expStage(e) else { return }
        let tr = s.kind == .trainer ? s.trainer : storyNextTrainer(e, k)                                   // the chapter's trainer (dim until its fight); the legends at the end
        if locked || s.kind == .pick || s.kind == .fight || tr == nil || e.id == Expeditions.story5 {
            let d = s.kind == .fight ? (x.mon?.dex ?? 716) : e.id == Expeditions.story5 ? story5Legend : 716
            fb.mon(Mon(dex: d, level: 50, female: false), 0, 0, 2, tint: locked || (s.kind != .fight && e.id == Expeditions.story5) ? grey : nil)
        } else if let f = tr.flatMap({ storyFrames[$0] }) { fb.pic("trainer " + f, 40, 84, alpha: s.kind == .trainer ? 1 : 0.35, clip: [0, 26, 88, 102]) { framePic(f) } }
        fb.name(name, xx, 13, 94 - xx)
        if locked { fb.line("잠김", xx, 26, 94 - xx, 1); fb.line("1~4장", xx, 37, 94 - xx); fb.line("먼저", xx, 46, 94 - xx); return }
        if x.mon == nil { fb.line("시작 전", xx, 26, 94 - xx, 1); fb.line(expGoing != nil ? "● 바꾸기" : "● 시작하기", xx, 40, 94 - xx, 3); return }
        if !x.on { fb.line("\(s.chapter)장 · 멈춤", xx, 26, 94 - xx, 1); fb.line("● 이어 하기", xx, 40, 94 - xx, 3); return }
        switch s.kind {
        case .walk: bar(26, Double(x.steps) / Double(max(1, s.need))); fb.line("\(s.chapter)장 칼로스", xx, 31, 94 - xx, 2); fb.line("\(man(x.steps))/\(man(s.need))", xx, 40, 94 - xx, 2); fb.line(tr.map { "다음 " + short($0) } ?? "다음 결전", xx, 49, 94 - xx, 1)
        case .trainer: fb.line("\(s.chapter)장 배틀", xx, 26, 94 - xx, 2); fb.line(short(s.trainer), xx, 35, 94 - xx, 3); fb.line("● 배틀", xx, 48, 94 - xx, 3)
        case .dex: let n = kalosCaught(s); bar(26, Double(n) / Double(max(1, s.need))); fb.line("칼로스 도감", xx, 31, 94 - xx, 2); fb.line("\(n)/\(s.need)종", xx, 40, 94 - xx, 3); fb.line("\(s.chapter)장 앞", xx, 49, 94 - xx, 1)
        case .pick: fb.line("결전", xx, 26, 94 - xx, 3); fb.line("하나를", xx, 37, 94 - xx, 2); fb.line("● 고르기", xx, 48, 94 - xx, 3)
        case .fight: fb.line("결전 · 바 \(s.bars)", xx, 26, 94 - xx, 2); fb.line(expFought(x, now) ? "내일 다시" : "오늘 1번", xx, 37, 94 - xx, expFought(x, now) ? 1 : 2); if !expFought(x, now) { fb.line("● 싸우기", xx, 48, 94 - xx, 3) }
        default: break
        }
    }

    // MARK: the buttons
    /// 짝 청하기 (the friends), 거두기 · 풀기 (asked first), 플레어단전 (the party), 고르기 (two cards), 이야기 다시 보기, 칼로스 도감.
    func exp53Go(_ a: ExpGo, _ e: Expedition, _ sel: Int, _ now: Date) {
        let here = Screen.expedition(sel)
        switch a {
        case .invite: screen = .pairPick(dex: e.legend, sel: 0)
        case .cancel:
            if let p = pairOn(e.id) {
                guard host?.confirm(josa(p.with, "과", "와") + "의 짝을 풀까요?", "둘이 걸은 \(man(p.steps + p.theirSteps))걸음은 사라져요. " + josa(p.with, "도", "도") + " 짝이 풀려요.\n" + monNames[e.legend] + " 원정은 지금 원정으로 남아서 혼자 걷거나 다시 청할 수 있어요.", ok: "짝 풀기") == true else { return }
                pairAct(.pairCancel(pair: p.id), back: here, now) { [p.with.count > 6 ? "짝을 풀었다" : josa(p.with, "과", "와") + "의 짝을 풀었다", "혼자 걸음이 이어져요"] }
            } else if let p = pairSent(e.id) {
                guard host?.confirm(p.with + "에게 보낸 청하기를 거둘까요?", "다른 친구에게 다시 청할 수 있어요.", ok: "거두기") == true else { return }
                pairAct(.pairCancel(pair: p.id), back: here, now) { ["청하기를 거뒀다"] }
            }
        case .trainer: screen = .squad(Squad(kind: .exp(id: e.id), picked: raidLast, at: 0))
        case .pick: screen = .twoPick(kind: 1, sel: 0)
        case .talk:
            if let k = expProgress(e).stage, let sc = cloud?.expedition?.story?.last(where: { $0.id == e.id && $0.stage <= k }) { storyScene = sc; storyQueue = []; storyThen = here; screen = .talk(0) }
        case .dex: screen = .dex(650, filter: 0, detail: false)
        default: break
        }
    }
    /// The grey button (9231): 거절 on a friend's ask, else the pick's second (혼자 시작 · 짝 청하기 · 거두기 · 풀기 · 이야기 다시 보기).
    func exp53Second(_ sel: Int, _ now: Date) {
        let here = Screen.expedition(sel)
        if case .ask(let p)? = expRows(expTab)[safe: sel] {
            guard host?.confirm(p.with + "의 짝 청하기를 거절할까요?", josa(p.with, "에게", "에게") + " 거절했다고 알려 줘요.", ok: "거절") == true else { return }
            pairAct(.pairCancel(pair: p.id), back: here, now) { ["짝 청하기를 거절했다"] }
            return
        }
        guard case .exp(let e)? = expRows(expTab)[safe: sel], exp53Owns(e), let a = exp53Detail(e, now).act2 else { return }
        if a == .start { expStartGo(e, sel, now); return }
        exp53Go(a, e, sel, now)
    }
    /// A pair's act (ask · take · take back · say no · end): the server's answer refreshes the pairs; its lines said.
    func pairAct(_ a: Act, back: Screen, _ now: Date, next: Screen? = nil, _ lines: @escaping @MainActor () -> [String]) {
        act(a, back: back, now) { [weak self] _, now in
            self?.cloud?.expeditionDue = true
            return .say(lines(), next: next ?? back, since: now)
        }
    }

    // MARK: 홈, the news
    /// 홈's row: a friend's ask first, then the one going on (the pair's days), as 5.2's.
    var exp53HomeRow: StatusModel.Row? {
        if let a = pairAsks.first { return .init(key: "전설 원정", value: josa(pal(a.with), "이", "가") + " 짝을 청했어요 · " + a.theirs, bar: nil) }
        guard let e = expGoing, exp53Owns(e) else { return nil }
        if let p = pairOn(e.id) { let sum = p.steps + p.theirSteps; return .init(key: "전설 원정", value: monNames[e.legend] + " · " + josa(pal(p.with), "과", "와") + " \(pct(Double(sum) / Double(p.goal)))% · \(daysLeft(p.ends))일", bar: Double(sum) / Double(p.goal)) }
        let w = exp53Words(e, Date())
        return .init(key: "전설 원정", value: (e.kind == .story ? "칼로스 이야기 " : monNames[e.legend] + " · ") + w.note, bar: w.frac)
    }
    /// News: a friend's ask, my ask taken, an ask or a pair over (홈's card; a 12-letter ID on a row of its own).
    func showPair(_ n: News, _ now: Date) {
        cloud?.expeditionDue = true
        switch n {
        case .pairAsked(_, let from, let id):
            screen = .say(from.count > 6 ? [from, "짝을 청했다!", josa(id, "과", "와") + " 함께 · 30만 걸음"] : [josa(from, "이", "가") + " 짝을 청했다!", josa(id, "과", "와") + " 함께 · 30만 걸음"], next: .home, since: now)
            notify("pet", josa(from, "이", "가") + " 짝을 청했어요", "모험 ▸ 전설 원정 ▸ 협동에서 받거나 거절해요")
        case .pairOn(_, let with, _):
            screen = .say((with.count > 6 ? [with, "짝을 받았다!"] : [josa(with, "이", "가") + " 짝을 받았다!"]) + ["14일 동안 둘이 30만 걸음"], next: .home, since: now)
            notify("pet", josa(with, "이", "가") + " 짝을 받았어요", "14일 동안 둘이 30만 걸음 · 각자 3만 이상")
        case .pairClosed(_, let with, let why):
            let long = with.count > 6, lines: [String] = switch why {
            case "거절": [long ? with : josa(with, "이", "가"), "짝 청하기를 거절했다"]
            case "취소": [long ? with : josa(with, "이", "가"), "짝 청하기를 거뒀다"]
            case "기한": long ? ["14일이 지나 짝이 풀렸다", with] : [josa(with, "과", "와") + "의 짝이", "14일이 지나 풀렸다"]
            default: long ? ["짝이 풀렸다", with, "둘이 걸은 걸음은 사라졌다"] : [josa(with, "과", "와") + "의 짝이 풀렸다", "둘이 걸은 걸음은 사라졌다"]
            }
            screen = .say(lines, next: .home, since: now)
            if why == "풀림" || why == "기한" { notify("pet", lines.joined(separator: " "), "혼자 걸음은 이어져요 · 다시 청할 수 있어요") }
        default: break
        }
    }

    // MARK: the scenes
    /// A scene shown is kept (the settings) so it isn't shown again by itself this time through (다시 하기: its finishes count, so again then).
    func sceneKey(_ s: StoryScene) -> String { "story|\(s.id)|\(state.expeditions?[s.id]?.done ?? 0)|\(s.stage)|\(s.at)" }
    func scene(_ id: String, _ stage: Int, _ at: String) -> StoryScene? { cloud?.expedition?.story?.first { $0.id == id && $0.stage == stage && $0.at == at } }
    /// Where a stage's start scene leads: its fight's party, the pick, else the page.
    func sceneThen(_ id: String, _ stage: Int) -> Screen {
        switch Expeditions.of(id)?.steps[safe: stage]?.kind {
        case .trainer?: return .squad(Squad(kind: .exp(id: id), picked: raidLast, at: 0))
        case .pick?: return .twoPick(kind: 1, sel: 0)
        default: return expPage(id)
        }
    }
    /// The scenes not shown yet, one after another, then `then`: the first one's screen (nil: none to show).
    func playScenes(_ list: [StoryScene?], then: Screen) -> Screen? {
        let new = list.compactMap { $0 }.filter { !settings.bool(sceneKey($0), false) }
        guard let first = new.first else { return nil }
        for s in new { settings.set(sceneKey(s), true) }
        storyScene = first; storyQueue = Array(new.dropFirst()); storyThen = then
        return .talk(0)
    }
    /// A story's stage came (its news): its start scene (once), else 5.2's card.
    func showStoryStage(_ e: Expedition, _ stage: Int, _ now: Date) -> Bool {
        guard e.kind == .story, let s = playScenes([scene(e.id, stage, "start")], then: sceneThen(e.id, stage)) else { return false }
        screen = s
        notify("pet", e.title + ": " + (e.steps[safe: stage].map { st in st.kind == .trainer ? josa(st.trainer, "과", "와") + " 배틀" : st.kind == .pick ? "결전 상대를 골라요" : st.kind == .fight ? "결전" : "\(st.chapter)장" } ?? ""), "모험 ▸ 전설 원정에서 이어 가요")
        return true
    }
    /// A 플레어단 fight over: won — its scene after and the next stage's (the news that came with it, taken now); lost — again any time.
    func storyFightEnded(_ id: String, _ t: String, _ e: BattleEnd, _ now: Date) -> Screen {
        let page = expPage(id)
        guard e.result == "won" else { return .say([josa(t, "에게", "에게") + " 졌다...", "다시 도전할 수 있어요"], next: page, since: now) }
        var next: Int? = nil
        news.removeAll { n in if case .expeditionStage(let i, let st) = n, i == id { next = st; return true }; return false }
        let k = next ?? (expProgress(Expeditions.of(id) ?? Expeditions.since53[3]).stage ?? 1)
        let then = playScenes([scene(id, k - 1, "won"), scene(id, k, "start")], then: sceneThen(id, k)) ?? page
        return .say([josa(t, "을", "를") + " 이겼다!"], next: then, since: now)
    }
    /// The story's final fight won (5.2's boss, no balls): its legend came — its lines, then the scene after.
    func storyFinalWon(_ id: String, _ name: String, _ now: Date) -> Screen {
        let more = expDoneLines(id), last = (Expeditions.of(id)?.steps.count ?? 1) - 1
        return .say([josa(name, "을", "를") + " 잡았다!", "상자로 보냈다"] + more, next: playScenes([scene(id, last, "won")], then: expPage(id)) ?? expPage(id), since: now)
    }
    var storyTalkMeta: String {
        guard case .talk(let p) = screen, let sc = storyScene else { return "" }
        let ch = Expeditions.of(sc.id)?.steps[safe: sc.stage]?.chapter ?? 0
        return "\(ch)장 · " + (sc.at == "won" ? "이긴 뒤 " : "") + "\(p + 1)/\(sc.pages.count)"
    }
    func talkPane(_ page: Int) -> PaneContent {
        guard let sc = storyScene, !sc.pages.isEmpty else { return PaneContent() }
        let p = min(max(0, page), sc.pages.count - 1), st = Expeditions.of(sc.id)?.steps[safe: sc.stage], last = p == sc.pages.count - 1
        let head = "\(st?.chapter ?? 0)장 · " + (sc.title.map { $0 + (sc.at == "won" ? " · 이긴 뒤" : "") } ?? (sc.at == "won" ? "이긴 뒤" : st.map { s in s.kind == .trainer ? short(s.trainer) : s.kind == .walk ? "칼로스 걷기" : s.kind == .dex ? "칼로스 도감" : s.kind == .pick ? "고르기" : "결전" } ?? ""))
        let end: String = !storyQueue.isEmpty ? "다음 이야기 ▼" : { switch storyThen { case .squad?: "배틀 준비 · 파티 고르기"; case .twoPick?: "결전 상대 고르기"; default: "닫기" } }()
        return PaneContent(talk: TalkModel(chapter: head, page: p, of: sc.pages.count, who: sc.pages[p].who ?? "", lines: sc.pages[p].lines,
                                           log: sc.pages.prefix(p).suffix(3).map { TalkModel.Said(who: $0.who ?? "", lines: $0.lines) }, go: last ? end : "다음 ▼", skip: !last))
    }
    func talkLCD(_ fb: inout FB, _ page: Int, _ now: Date) {
        guard let sc = storyScene, !sc.pages.isEmpty else { return }
        let p = min(max(0, page), sc.pages.count - 1), s = sc.pages[p], ch = Expeditions.of(sc.id)?.steps[safe: sc.stage]?.chapter ?? 0
        fb.text(s.who ?? "\(ch)장", 2, 0); fb.text("\(p + 1)/\(sc.pages.count)", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
        if let f = s.who.flatMap({ storyFrames[$0] }) { fb.pic("trainer " + f, 96, 66, clip: [0, 26, 192, 56]) { framePic(f) } }       // (its feet under the box)
        else if Expeditions.of(sc.id)?.steps[safe: sc.stage]?.kind == .pick { for (k, d) in Expeditions.storyPicks.enumerated() { fb.pic("icon \(d)", 64 + 64 * k, 54, scale: 1.5) { iconPic(d) } } }   // (the two lights)
        else if sc.id == Expeditions.story5 || Expeditions.of(sc.id)?.steps[safe: sc.stage]?.kind == .fight { let d = sc.id == Expeditions.story5 ? story5Legend : (state.expeditions?[sc.id]?.mon?.dex ?? 716); fb.pic("icon \(d)", 96, 54, scale: 1.5) { iconPic(d) } }
        else { let a = state.companion.art; fb.pic("icon \(a)", 96, 54, scale: 1.5) { iconPic(a) } }                     // (the narration: ours)
        fb.fill(0, 41, 96, 1, 2)
        for (k, l) in s.lines.prefix(2).enumerated() { fb.line(l, 3, 43 + 10 * k, 90, 3) }
        if Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0 { fb.draw(art(["#####", "_###_", "__#__"]), 89, 59) }
    }
    /// ● (다음 ▼): the next page; past the last, the next scene queued, else where it leads.
    func talkNext(_ page: Int, _ now: Date) {
        if let sc = storyScene, page + 1 < sc.pages.count { screen = .talk(page + 1); return }
        talkEnd()
    }
    /// 건너뛰기: this scene's end.
    func talkEnd() {
        if let n = storyQueue.first { storyQueue.removeFirst(); storyScene = n; screen = .talk(0); return }
        let then = storyThen ?? .expedition(0); storyThen = nil; storyScene = nil
        screen = then
    }

    // MARK: 짝 청하기 — the friends (맡기기's list: the same cards; one in a pair or before 5.3 dimmed)
    func pairFriends() -> [TeamCard] { teamRows(0).map(\.card).filter { !isMe($0) } }
    func pairPickPane(_ d: Int, _ sel: Int) -> PaneContent {
        let cards = pairFriends(), s = min(max(0, sel), max(0, cards.count - 1))
        let rows = cards.map { c in
            let paired = c.pair == true, old = c.app53 == false
            return PairPickModel.Row(name: c.name, dex: c.companion.dex, value: "이번 주 " + man(c.week) + "걸음", walking: Walker.walkingNow(c),
                                     pill: paired ? "짝 있음" : old ? "5.3 아님" : nil, off: paired || old)
        }
        let pick = rows[safe: s]
        let lines = pick.map { r in r.off ? [r.pill == "5.3 아님" ? "앱이 5.3이 아니에요 · 업데이트하면 청할 수 있어요" : "지금 다른 친구와 짝이에요 · 끝나면 청할 수 있어요"]
                                          : ["3일 안에 받으면 둘 다 협동이 지금 원정이 돼요", "14일 안에 둘이 30만 걸음 · 각자 3만 이상 · 어느 코스든", "걷는 중이 아니어도 청할 수 있어요 · 청하기는 하나만"] } ?? ["친구가 없어요 · 혼자 시작해도 돼요"]
        return PaneContent(pairPick: PairPickModel(title: "누구와 짝을 지을까요?", note: "친구 \(cards.count)명 · 걷는 중 \(cards.filter { Walker.walkingNow($0) }.count)명", rows: rows, sel: s, lines: lines,
                                                   go: pick.flatMap { $0.off ? nil : $0.name + "에게 청하기" }, dex: d))
    }
    func pairPickLCD(_ fb: inout FB, _ d: Int, _ sel: Int, _ now: Date) {
        let cards = pairFriends()
        fb.text("짝 청하기", 2, 0); fb.text(monNames[d], 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
        guard let c = cards[safe: min(sel, max(0, cards.count - 1))] else { fb.text("친구가 없다", 0, 30, 2, center: true); return }
        let off = c.pair == true || c.app53 == false
        fb.mon(c.companion, Int(now.timeIntervalSinceReferenceDate * 2) % 2, 0, 2)
        fb.text(c.name, 94, 15, 3, right: true, small: true); fb.text("이번 주 " + man(c.week), 94, 26, 2, right: true, small: true)
        fb.text(off ? (c.pair == true ? "짝 있음" : "5.3 아님") : "● 청하기", 94, 52, off ? 1 : 3, right: true, small: true)
    }
    func pairPickPress(_ k: Int, _ d: Int, _ sel: Int, _ now: Date) {
        let cards = pairFriends(), n = max(1, cards.count)
        if k != 1 { screen = .pairPick(dex: d, sel: (sel + (k == 0 ? -1 : 1) + n) % n); return }
        guard let c = cards[safe: sel], c.pair != true, c.app53 != false else { return }
        pairInvite(c.name, monNames[d], back: .pairPick(dex: d, sel: sel), now)
    }
    /// 짝 청하기 (asked first): one ask out at a time — a new one takes the last back.
    func pairInvite(_ to: String, _ id: String, back: Screen, _ now: Date) {
        guard host?.confirm(to + "에게 짝을 청할까요?", id + " · 14일 안에 둘이 30만 걸음(각자 3만 이상).\n" + josa(to, "이", "가") + " 3일 안에 받으면 둘 다 협동이 지금 원정이 되고, 하던 원정은 멈춰요.", ok: "청하기") == true else { return }
        pairAct(.pairInvite(to: to, id: id), back: back, now, next: expPage(id)) { [to.count > 6 ? "짝을 청했다!" : josa(to, "에게", "에게") + " 짝을 청했다!", "3일 안에 받으면 짝이 돼요"] }
    }
    /// A friend's card's 짝 청하기 (5.3, Q1): its state — 짝 청하기, or why not (nil: no button).
    func pairCardButton(_ c: TeamCard) -> String? {
        guard Content.v53, isFriend(c.name), !isMe(c) else { return nil }
        if pairs.contains(where: { $0.state == "sent" && $0.with == c.name }) { return "청했어요" }
        if c.pair == true { return "짝 있음" }
        if c.app53 == false { return "5.3 아님" }
        if pairWalking != nil { return "짝 걷는 중" }
        return "짝 청하기"
    }

    // MARK: a pick of two — my dragon (taking a friend's ask, or asking from a friend's card), the story's 결전
    func twoPickPane(_ kind: Int, _ sel: Int) -> PaneContent {
        if kind == 0 || kind == 2 {
            let going = expGoing.map(expRowName), ask = kind == 0 ? pairAsk : nil, theirs = ask.map { dragonDex($0.theirs) }
            let cards = [(643, ["dragon", "fire"], "진실을 찾는 하얀 용"), (644, ["dragon", "electric"], "이상을 좇는 검은 용")].map { d, t, s in
                let x = state.expeditions?[monNames[d]]
                let note = state.pairCan(monNames[d]) != nil ? "보스전 단계 · 고를 수 없어요" : (x?.done ?? 0) > 0 && x?.mon == nil ? "잡았어요 ✓ · 다시 해도 돼요" : x?.mon != nil ? "혼자 \(man(x?.steps ?? 0)) 걸었어요" : "아직 없어요"
                return TwoPickModel.Card(dex: d, name: monNames[d], types: t, sub: s, note: note, mark: d == theirs ? pal(ask?.with ?? "") + "의 용" : nil)
            }
            let pick = cards[min(1, max(0, sel))], who = ask?.with ?? pairTo ?? ""
            let lines = kind == 0
                ? [josa(who, "은", "는") + " " + josa(ask?.theirs ?? "", "을", "를") + " 골랐어요", "같은 용을 골라도 돼요 · 다 걸으면 각자 고른 용과 보스전"] + (going.map { ["받으면 " + $0 + " 원정은 멈춰요 · 모은 것은 그대로"] } ?? [])
                : [who + "에게 청해요 · 친구는 받을 때 자기 용을 골라요", "3일 안에 받으면 14일 동안 둘이 30만 걸음 · 각자 3만 이상"]
            return PaneContent(twoPick: TwoPickModel(title: kind == 0 ? "내 용 고르기" : "어느 용으로 청할까요?", note: "14일 · 둘이 30만", cards: cards, sel: sel, lines: lines,
                                                     go: josa(pick.name, "으로", "로") + (kind == 0 ? " 짝 짓기" : " 청하기"), go2: kind == 0 ? "거절" : nil))
        }
        let other = sel == 0 ? 717 : 716
        let cards = [(716, ["fairy"], "생명을 나누어 주는 전설"), (717, ["dark", "flying"], "생명을 거두어 가는 전설")].map { d, t, s in
            TwoPickModel.Card(dex: d, name: monNames[d], types: t, sub: s, note: "결전 Lv.70 · 바 3개", mark: nil)
        }
        return PaneContent(twoPick: TwoPickModel(title: "누구와 결전할까요?", note: "바꿀 수 없어요", cards: cards, sel: sel,
                                                 lines: ["이기면 반드시 와요 · 볼 단계가 없어요", "결전은 하루 1번 · 지면 다음 날 다시", josa(monNames[other], "은", "는") + " 5장에서 · 칼로스 도감 10종 + 칼로스 4만 걸음"],
                                                 go: josa(monNames[sel == 0 ? 716 : 717], "과", "와") + " 결전", go2: nil))
    }
    func twoPickLCD(_ fb: inout FB, _ kind: Int, _ sel: Int, _ now: Date) {
        let d = kind == 1 ? Expeditions.storyPicks[min(1, sel)] : Walker.dragons[min(1, sel)]
        fb.text(kind == 0 ? "내 용 고르기" : kind == 2 ? "청할 용" : "결전 상대", 2, 0); fb.text("\(sel + 1)/2", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
        fb.mon(Mon(dex: d, level: 50, female: false), Int(now.timeIntervalSinceReferenceDate * 2) % 2, 0, 2)
        fb.name(monNames[d], 44, 13, 50)
        fb.line(kind == 1 ? (d == 716 ? "페어리" : "악 · 비행") : (d == 643 ? "드래곤 · 불꽃" : "드래곤 · 전기"), 44, 26, 50, 2)
        fb.line("◀ ▶ 바꾸기", 44, 37, 50, 1); fb.line(kind == 0 ? "● 짝 짓기" : kind == 2 ? "● 청하기" : "● 결전", 44, 48, 50, 3)
    }
    /// The pick's button (9660 · ●): take the ask with this dragon, ask with it, or the 결전 (asked first, each).
    func twoPickGo(_ kind: Int, _ sel: Int, _ now: Date) {
        let back = Screen.twoPick(kind: kind, sel: sel)
        switch kind {
        case 0:
            guard let a = pairAsk else { return }
            let id = monNames[Walker.dragons[min(1, sel)]], going = expGoing.flatMap { $0.id == id ? nil : expRowName($0) }
            guard host?.confirm(josa(id, "으로", "로") + " 짝을 지을까요?", (going.map { "지금 하는 " + $0 + " 원정은 멈추고, 모은 것은 그대로 남아요.\n" } ?? "") + "짝을 지은 동안 다른 원정으로 바꾸면 짝이 풀리고, 둘이 걸은 걸음은 사라져요.", ok: "짝 짓기") == true else { return }
            pairAct(.pairAccept(pair: a.id, id: id), back: back, now, next: expPage(id)) { [a.with.count > 6 ? "짝을 지었다!" : josa(a.with, "과", "와") + " 짝을 지었다!", "14일 동안 둘이 30만 걸음"] }
            pairAsk = nil
        case 2:
            guard let to = pairTo else { return }
            pairInvite(to, monNames[Walker.dragons[min(1, sel)]], back: back, now)
        default:
            let d = Expeditions.storyPicks[min(1, sel)], me = monNames[d], other = monNames[Expeditions.storyPicks[1 - min(1, sel)]], id = Expeditions.story
            guard host?.confirm(josa(me, "과", "와") + " 결전할까요?", "한 번 고르면 바꿀 수 없어요.\n" + josa(other, "은", "는") + " 5장(칼로스 도감 10종 · 칼로스 4만 걸음)에서 만나요.", ok: "결전") == true else { return }
            act(.expPick(id: id, dex: d), back: back, now) { [weak self] _, now in
                guard let self else { return nil }
                let k = self.expProgress(Expeditions.of(id) ?? Expeditions.since53[3]).stage ?? 0
                return self.playScenes([self.scene(id, k, "start")], then: self.expPage(id)) ?? .say([josa(me, "과", "와") + " 결전!", "하루 1번 · 이기면 반드시 와요"], next: self.expPage(id), since: now)
            }
        }
    }
    /// The pick's second (9661): 거절 (a friend's ask), else back.
    func twoPickSecond(_ kind: Int, _ now: Date) {
        guard kind == 0, let a = pairAsk else { screen = kind == 2 ? .home : .expedition(0); return }
        guard host?.confirm(a.with + "의 짝 청하기를 거절할까요?", josa(a.with, "에게", "에게") + " 거절했다고 알려 줘요.", ok: "거절") == true else { return }
        pairAct(.pairCancel(pair: a.id), back: .twoPick(kind: kind, sel: 0), now, next: .expedition(0)) { ["짝 청하기를 거절했다"] }
        pairAsk = nil
    }
}

// MARK: - the pages' models
struct PairPickModel: Equatable {
    struct Row: Equatable { var name: String; var dex: Int; var value: String; var walking: Bool; var pill: String?; var off: Bool }
    var title: String; var note: String; var rows: [Row]; var sel: Int; var lines: [String]; var go: String?; var dex: Int
}
struct TwoPickModel: Equatable {
    struct Card: Equatable { var dex: Int; var name: String; var types: [String]; var sub: String; var note: String; var mark: String? }
    var title: String; var note: String; var cards: [Card]; var sel: Int; var lines: [String]; var go: String; var go2: String?
}
struct TalkModel: Equatable {
    struct Said: Equatable { var who: String; var lines: [String] }
    var chapter: String; var page: Int; var of: Int; var who: String; var lines: [String]; var log: [Said]; var go: String; var skip: Bool
}
