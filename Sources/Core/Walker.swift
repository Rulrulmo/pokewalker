import Foundation
// The walker: its state, the clock tick, the keys, the pane's page and the title row as data. What the buttons do: Core/Flow.swift; the LCD: Core/Compose.swift; the card drawn: Core/Card.swift.
// Whatever shows it is its host (Core/Platform.swift): the Mac's is WalkerView. No host = headless (the self-test): nothing drawn, no steps counted.

@MainActor final class Walker {
    var state: Walk
    var screen = Screen.home
    weak var host: (any Host)?
    var lastInput = Date(), lastStep = Date.distantPast, lastSave = Date(), levelled = false
    var boxSort = 0                                                        // the 상자 grid's order: 번호순 / 레벨순 / V순 / 최근
    var chainNote: String? = nil                                           // "+6W · 기력의조각" under "연쇄 3!"
    var keyShown: Bool?? = .none                                           // the 메뉴 / 홈 key as last shown (see homeKey)
    var strollX = 54.0, strollRight = false, strollAt = Date(), strollTurnAt = Date(), stepRate = 0.0   // home: the walking sprite's middle in the course picture (half-dots), which way it goes, the pace
    var usedItem = "몬스터볼"                                                // the potion / ball / revive the current beat names
    var partyRefs: [Int] = [], towerRun = false                        // partyRefs: the uids of ours in the fight (written back after it)
    var sideOn = false                                                     // the pane carries the battle's text (the app; not --selftest): the LCD shows the stage only
    lazy var lastSeason = state.season
    var emote: (kind: Int, until: Date)? = nil                             // ♪ ♥ ! bubble over the companion
    var animOn: (who: String, dex: Int, since: Date)? = nil                // the entry animation playing (Anim.swift): home's companion or a page's Pokémon
    lazy var rewarded = dexCount                                           // dex count already celebrated (no fanfare for old progress)
    var dexCount: Int { (state.owned ?? []).count }
    var rng = Seeded(s: .random(in: .min ... .max))
    var pane = PaneContent(), paneAt = Date.distantPast                    // the pane's page as shown, when it was last refreshed
    var cardH = Layout.idle                                                // the card's height now (card points): the page's
    var hud: SideModel? = nil                                              // a fight's HP boxes, drawn over the LCD
    var battleSpeed: Double { Double(settings.int("battleSpeed", 3)) / 2 }     // 배틀 속도 (the right-click's): 보통 x1, 빠르게 x1.5 (the default), 아주 빠르게 x2
    var titleShown = ""                                                    // the title row as last shown: a change redraws it
    var persist = true                                                     // false in --selftest: flows must never touch the real save (nor notify)
    lazy var unlockedAt = state.earned                                     // lifetime watts already announced

    init(state: Walk) { self.state = state }

    /// The pane now: its page (and the card's height), the LCD's HP boxes, the 메뉴 / 홈 key, the title row; the host redraws what changed.
    func refreshPane(_ now: Date, force: Bool = false) {
        let c = paneContent(now)
        if force || c.status == nil || pane.status == nil || now.timeIntervalSince(paneAt) >= 1 {  // steps tick the 상태 sheet: once a second is plenty
            if c != pane { pane = c; host?.redraw(.page) }
            paneAt = now
        }
        let h = pane.height
        if h != cardH { cardH = h; host?.resized() }
        let hb = sideOn ? c.battle : nil
        if hb != hud { hud = hb; host?.redraw(.lcd) }
        if homeKey() != keyShown { keyShown = homeKey(); host?.redraw(.key) }                   // the 메뉴 / 홈 key's face
        let t = title(), key = t.title + "|" + t.meta
        if key != titleShown { titleShown = key; host?.redraw(.title) }
    }

    /// The clock (the host's, 10 a second): steps, the companion's finds, weather, unlocks, level-ups; screens that time out; the minute's save.
    func tick(_ now: Date) {
        let before = state.total
        if let h = host, !inBattle, state.sync(counter: h.counter(), boot: h.boot(), at: now) { levelled = true }   // not mid-fight: the fight's copy would overwrite those steps' EXP; they count once it's over
        perk(now, stepped: state.total != before)                                               // the companion's animation now and then
        if state.total != before { lastStep = now }
        stepRate = stepRate * 0.8 + Double(min(50, state.total - before)) * 10 * 0.2               // steps a second, smoothed (the tick is 10 Hz)
        if state.season != lastSeason {
            lastSeason = state.season
            notify("weather", state.season.name + "이 왔어요", ["꽃이 피었어요", "햇볕이 쨍쨍해요", "단풍이 들었어요", "눈이 쌓여요"][state.season.rawValue] + " · 게임 속 \(seasonDays)일마다 계절이 바뀌어요")
            if case .home = screen { screen = .say([state.season.name + "이 왔다!"], next: .home, since: now) }
        }
        if state.weatherDue, state.rollWeather(&rng) {
            let w = state.weather ?? .sunny
            notify("weather", w.news, w.types.map { typeKo[$0] ?? $0 }.joined(separator: "·") + " 타입이 자주 나와요 · " + state.here.name)
            if case .home = screen { screen = .say([w.news], next: .home, since: now) }
        }
        if case .home = screen, state.eventDue {
            switch state.petEvent(&rng) {
            case .item(let item):
                screen = .say([josa(monNames[state.companion.dex], "이", "가") + " 무언가를", "주워왔다!", item], next: .home, since: now)
                notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 무언가를 주워왔어요", item)
            case .egg:
                screen = .say([josa(monNames[state.companion.dex], "이", "가") + " 무언가를", "주워왔다!", "포켓몬의 알"], next: .home, since: now)
                notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 알을 주워왔어요", "앞으로 \(state.egg?.left ?? 0)걸음 걸으면 태어나요")
            case nil: if state.total > 0 { emote = (Int.random(in: 0..<3, using: &rng), now.addingTimeInterval(3)) }
            }
        }
        if case .home = screen, state.hatchDue {
            let m = state.hatch(&rng); screen = .hatch(m, since: now); save()
            notify("hatch", "알에서 " + josa(monNames[m.dex], "이", "가") + " 태어났어요!" + (m.shiny == true ? " ✦" : ""), m.shiny == true ? "이로치예요! 상자에 있어요" : "Lv.1 · 상자에 있어요")
        }
        if state.earned > unlockedAt {                                                           // lifetime watts opened a course
            let new = courses.enumerated().filter { $0.element.watts > unlockedAt && $0.element.watts <= state.earned && state.unlocked($0.offset) }.map(\.element.name)
            unlockedAt = state.earned
            if let n = new.first {
                notify("unlock", "새 코스가 열렸어요", n + " · 메뉴 → 코스")
                if case .home = screen { screen = .say(["새 코스 해금!", n], next: .home, since: now) }
            }
        }
        if case .home = screen, dexCount > rewarded {                                            // Pokédex milestones: event courses and two shells
            let got = courses.filter { (rewarded + 1...dexCount).contains($0.dex) }.map { $0.name + " 코스" } + shells.filter { (rewarded + 1...dexCount).contains($0.dex) }.map { $0.name + " 기기" }
            rewarded = dexCount
            if let g = got.first { screen = .say(["도감 \(dexCount)종 달성!", g + " 해금"] + got.dropFirst().prefix(1), next: .home, since: now); notify("unlock", "도감 \(dexCount)종 달성!", got.joined(separator: " · ") + " 해금") }
        }
        if levelled, case .home = screen {                                                    // shown when it's back home, not mid-menu
            levelled = false
            let name = monNames[state.companion.dex]
            if let e = state.levelEvolution(now) { startEvolving(e, now); notify("grow", "어라...? " + josa(name, "의", "의") + " 모습이...!", josa(name, "이", "가") + " " + josa(monNames[e.to], "으로", "로") + " 진화했어요!") }
            else {
                screen = .say(["레벨 업!", name + " Lv.\(state.companion.level)"], next: .home, since: now)
                if state.companion.level % 5 == 0 { notify("grow", "레벨 업!", name + " Lv.\(state.companion.level)") }
            }
        }
        if case .home = screen, var q = state.evolving, !q.isEmpty {                                // ours that levelled in a fight: one at a time, home in between
            let u = q.removeFirst(); state.evolving = q.isEmpty ? nil : q
            if let r = state.ref(uid: u), let e = state.levelEvolution(now, ref: r) {
                let name = monNames[state.mon(r)!.dex]
                startEvolving(e, now, ref: r); notify("grow", "어라...? " + josa(name, "의", "의") + " 모습이...!", josa(name, "이", "가") + " " + josa(monNames[e.to], "으로", "로") + " 진화했어요!")
            }
        }
        if case .home = screen, (state.learning ?? []).count >= 2 { nextLearn(now) }
        switch screen {
        case .radar(_, _, let since, let chain) where now.timeIntervalSince(since) > 1.5 + radarWindow(chain):
            screen = .say(chain > 0 ? ["...!", "연쇄가 끊겼다 (\(chain))"] : ["...!", "사라져버렸다"], next: .home, since: now)
        case .beats(let bt, let beats, let since, _) where now.timeIntervalSince(since) * battleSpeed >= beats.map(\.length).reduce(0, +):
            screen = beats.last!.ends ? after(bt, beats.last!, now) : bt.mustReplace ? .party(bt, sel: bt.mine.indices.first { bt.mine[$0].alive } ?? 0) : .battle(bt, sel: 0)
        case .say(_, let next, let since) where now.timeIntervalSince(since) > 3: screen = next
        case .evolve(_, _, let since) where now.timeIntervalSince(since) > 6.5: screen = .home
        case .hatch(_, let since) where now.timeIntervalSince(since) > 5.5: screen = .home
        case .menu, .card, .items, .dex, .box, .tower, .shop, .shopConfirm, .course, .train: if now.timeIntervalSince(lastInput) > 20 { screen = .home }
        default: break
        }
        if now.timeIntervalSince(lastSave) > 60 { save() }
    }
    /// Fights, shows and animations play at 30 fps; the rest (the walking sprite too: HGSS steps it every 0.15 s) at the tick's 10.
    var busy: Bool { switch screen { case .beats, .hatch, .evolve, .radar: true; default: animating } }

    /// The keys as the walker knows them: ◀ ▶ ↑ ↓, page up / down, tab, ● (return / space), ↩ (esc), 메뉴 / 홈 (M).
    enum Key { case left, right, up, down, pageUp, pageDown, tab, enter, back, menu }
    /// A key down (held: the key's repeat): in a shop ↑ ↓ = a row, or ±10; in a grid ↑ ↓ a row, page up / down a page; tab a grid's next tab
    /// (shift: the one before). false = not the walker's (the platform passes it on).
    func key(_ k: Key, shift: Bool = false, held: Bool = false) -> Bool {
        if case .shop(_, _, let q) = screen, let d = [Key.up: -1, .down: 1][k] { shopStep(q == nil ? d : -10 * d); return true }
        if case .tower(_?) = screen, let d = [Key.up: -1, .down: 1, .pageUp: -TowerModel.perPage, .pageDown: TowerModel.perPage][k] { towerStep(d); return true }   // the tower's picker: ↑ ↓ a row, page up / down a page
        switch screen { case .course, .train: if let d = [Key.up: -1, .down: 1, .pageUp: -CourseModel.perPage, .pageDown: CourseModel.perPage][k] { listRow(d); return true }; default: break }   // the lists: the same
        switch screen { case .dex(_, _, false), .box(_, .none, _, false): if let d = [Key.up: -6, .down: 6, .pageUp: -30, .pageDown: 30][k] { gridStep(d, ends: abs(d) == 30); return true }; default: break }   // the grids: ↑ ↓ a row, page up / down a page
        if k == .tab {
            switch screen {
            case .dex(_, let f, false): gridTap(4100 + (f + (shift ? 3 : 1)) % 4)
            case .box(_, .none, _, false): gridTap(4100 + (boxSort + (shift ? 3 : 1)) % 4)
            default: break
            }
            return true
        }
        switch screen { case .shop, .shopConfirm, .tower, .radar, .items, .train: if held, k == .enter { return true }; default: break }   // a held return / space doesn't keep buying, pay into the tower after a pick, or pick a bush too early
        guard let i = [Key.left: 0, .enter: 1, .right: 2, .back: 3, .menu: 4][k] else { return false }
        press(i); return true
    }

    /// The title row for this screen: what it is, and one line of what the LCD doesn't show.
    func title() -> (title: String, meta: String) {
        var sc = screen; if case .say(_, let next, _) = sc { sc = next }
        let fight: Battle? = switch sc { case .battle(let b, _), .moves(let b, _), .party(let b, _), .bagBattle(let b, _), .forfeit(let b, _), .beats(let b, _, _, _): b; default: nil }
        if let b = fight {
            guard let tr = b.trainer else { return ("야생 배틀", state.here.name) }
            let left = { (fs: [Fighter]) in fs.filter(\.alive).count }
            return (tr, "배틀 타워 · 남은 \(left(b.theirs)) : \(left(b.mine))")
        }
        let when = "\(state.season.name) \(state.gameDay % seasonDays + 1)일째 · \((state.weather ?? .sunny).name)"
        switch sc {
        case .dex: return ("도감", "잡음 \(dexCount) · 봤음 \(seenList.count)")
        case .box, .items: return ("포켓몬", "워커 \(state.caught.count) · 상자 \(state.box.count.formatted()) · 도구 \(state.items.count + state.bag.count)")
        case .menu: return ("메뉴", "")
        case .shop(let bp, _, _), .shopConfirm(let bp, _, _): return (bp ? "BP 교환소" : "상점", "")
        case .radar: return ("포켓 레이더", state.here.name)
        case .card: return ("트레이너 카드", "")
        case .learn: return ("기술 배우기", "")
        case .course: return ("코스", "\(courses.indices.filter(state.unlocked).count) / \(courses.count) 열림")
        case .train: return ("대단한 특훈", "은색병뚜껑 ×\(state.count("은색병뚜껑"))")
        case .tower: return ("배틀 타워", "\((state.bp ?? 0).formatted())BP")
        default: return (state.here.name, when)                                                 // screens without a page of their own: the status sheet
        }
    }
}
