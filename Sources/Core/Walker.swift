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
    var growthThen: Screen? = nil                                      // where a fight's end goes once its evolutions and new moves have played (settle)
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
    var savedSigned = settings.bool("saveSigned", false)                     // this machine has written a signed save (Store.loadChecked)
    var gate = StepGate(), heldSteps = 0                                   // the step filter; steps made during a fight, counted after it
    var statusOpen = settings.bool("homePanel", true)                     // the title row's ⌄: the status sheet under the band where no page is up (open unless folded)
    var battleSpeed: Double { Double(settings.int("battleSpeed", 3)) / 2 }     // 배틀 속도 (the right-click's): 보통 x1, 빠르게 x1.5 (the default), 아주 빠르게 x2
    var titleShown = ""                                                    // the title row as last shown: a change redraws it
    var persist = true                                                     // false in --selftest: flows must never touch the real save (nor notify)
    lazy var unlockedAt = state.earned                                     // lifetime watts already announced
    var cloud: Cloud? = nil                                                // the save server (Core/Cloud.swift): set at launch (startCloud), never in the self-test's walkers
    var seen = Walk(), cloudAsked: Cloud.Phase? = nil, cloudAsking = false  // the state as the last tick left it (a change since = the player's); the question asked
    var cloudShown: Cloud.Phase? = nil, idBoxShown = false                 // the server's state the LCD shows; the ID box opened by itself (once a launch)
    var updater: Updater? = nil, shuttingDown = false                      // auto-update (Core/Update.swift): set at launch; a logout / shutdown puts nothing in at quit
    var relaunchAfterQuit = false, notedUpdate: String? = nil, updateNotices = 0   // the menu's 업데이트 설치: the quit starts the new version; the version a banner said was ready
    var installWhenStaged = false, installAt: Date? = nil                  // 업데이트 확인 · 설치 clicked: what it finds goes in; the install's moment (after the LCD says so)
    /// What the quit runs to put a staged update in (relaunch: start it after); the self-test's stub records it instead.
    var installUpdate: @MainActor (_ relaunch: Bool) -> Bool = { r in Update.appURL.map { Update.install(dir: Update.dir, app: $0, relaunch: r) } ?? false }
    var mintWaiting: Cloud.MintAsk? = nil, mintBack: Screen? = nil         // a Pokémon asked of the server (10 §4): the LCD waits, keys held; where a "no" goes back to
    var radarMon: Mon? = nil, chainWas = 0                                 // the server's radar find on the bushes now; the chain a result was asked at
    var hatchAsked = false, hatchAt = Date.distantPast                     // an egg's hatch asked of the server; not before (offline: the egg waits)

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
        let t = title(), key = t.title + "|" + t.meta + "|" + "\(chevron.map { $0 ? 1 : 0 } ?? 2)"
        if key != titleShown { titleShown = key; host?.redraw(.title) }
    }

    /// The clock (the host's, 10 a second): steps, the companion's finds, weather, unlocks, level-ups; screens that time out; the minute's save.
    func tick(_ now: Date) {
        let acted = cloud != nil && state != seen                                                  // between ticks only the player changes the save: up soon (steps come here)
        let before = state.total
        if let h = host {                                                                          // keys + clicks, the way a person makes them (StepGate)
            state.rollover(now)                                                                    // (a capped day still turns at midnight)
            let taken = state.take(counter: h.counter(), boot: h.boot(), at: now)
            if frozen { heldSteps = 0 }                                                            // another PC has the trainer: the baseline follows, nothing walks (08 §2-1)
            else {
                let n = state.roomToday(gate.pass(taken, now.timeIntervalSinceReferenceDate) + heldSteps) - heldSteps   // (today's cap counts the fight's held ones)
                if inBattle { heldSteps += n }                                                     // mid-fight: the fight's copy would overwrite their EXP; they count once it's over
                else if n + heldSteps > 0 { if state.walk(n + heldSteps, at: now) { levelled = true }; heldSteps = 0 }
            }
        }
        let stepped: Walk? = cloud == nil ? nil : state                                            // what the rest of the tick changes (a fight's end, a find, a hatch …) goes up soon too
        perk(now, stepped: state.total != before)                                               // the companion's animation now and then
        if state.total != before { lastStep = now }
        stepRate = stepRate * 0.8 + Double(min(50, state.total - before)) * 10 * 0.2               // steps a second, smoothed (the tick is 10 Hz)
        switch screen {
        case .radar(_, _, let since, let chain) where now.timeIntervalSince(since) > 1.5 + radarWindow(chain):
            radarMissed(now); screen = .say(chain > 0 ? ["...!", "연쇄가 끊겼다 (\(chain))"] : ["...!", "사라져버렸다"], next: .home, since: now)
        case .beats(let bt, let beats, let since, _) where now.timeIntervalSince(since) * battleSpeed >= beats.map(\.length).reduce(0, +):
            screen = beats.last!.ends ? after(bt, beats.last!, now) : bt.mustReplace ? .party(bt, sel: bt.mine.indices.first { bt.mine[$0].alive } ?? 0) : .battle(bt, sel: 0)
        case .say(_, let next, let since) where now.timeIntervalSince(since) > 3: screen = next
        case .evolve(_, _, let since) where now.timeIntervalSince(since) > 6.5: screen = .home
        case .hatch(_, let since) where now.timeIntervalSince(since) > 5.5: screen = .home
        case .menu, .card, .items, .dex, .box, .tower, .shop, .shopConfirm, .course, .train, .relearn: if now.timeIntervalSince(lastInput) > 20 { screen = .home }
        default: break
        }
        settle(now)                                                                                // home: what a fight brought, then where it was going (before home's own news)
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
            if let c = cloud { if !hatchAsked, now >= hatchAt { hatchAsked = true; c.mint(.hatch, walk: state, now: now) } }   // the server's egg (10 §4); offline it waits
            else { let m = state.hatch(&rng); screen = .hatch(m, since: now); save(); notifyHatch(m) }
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
        if now.timeIntervalSince(lastSave) > 60 { save() }
        if cloud != nil { cloudTick(now, acted: acted || stepped != state) }
        updater?.tick(now); updateTick(now)
    }
    /// Fights, shows and animations play at 30 fps; the rest (the walking sprite too: HGSS steps it every 0.15 s) at the tick's 10.
    var busy: Bool { switch screen { case .beats, .hatch, .evolve, .radar: true; default: animating } }

    /// The keys as the walker knows them: ◀ ▶ ↑ ↓, page up / down, tab, ● (return / space), ↩ (esc), 메뉴 / 홈 (M).
    enum Key { case left, right, up, down, pageUp, pageDown, tab, enter, back, menu }
    /// A key down (held: the key's repeat): in a shop ↑ ↓ = a row, or ±10; in a grid ↑ ↓ a row, page up / down a page; tab a grid's next tab
    /// (shift: the one before). false = not the walker's (the platform passes it on).
    func key(_ k: Key, shift: Bool = false, held: Bool = false) -> Bool {
        if frozen { if k == .enter, !held { press(1) }; return true }                              // another PC has it: ● = 여기서 계속, nothing else
        if mintWaiting != nil { return true }                                                      // the server's Pokémon on the way
        if case .shop(_, _, let q) = screen, let d = [Key.up: -1, .down: 1][k] { shopStep(q == nil ? d : -10 * d); return true }
        if case .tower(_?) = screen, let d = [Key.up: -1, .down: 1, .pageUp: -TowerModel.perPage, .pageDown: TowerModel.perPage][k] { towerStep(d); return true }   // the tower's picker: ↑ ↓ a row, page up / down a page
        switch screen { case .course, .train, .relearn: if let d = [Key.up: -1, .down: 1, .pageUp: -CourseModel.perPage, .pageDown: CourseModel.perPage][k] { listRow(d); return true }; default: break }   // the lists: the same
        switch screen { case .dex(_, _, false), .box(_, .none, _, false): if let d = [Key.up: -6, .down: 6, .pageUp: -30, .pageDown: 30][k] { gridStep(d, ends: abs(d) == 30); return true }; default: break }   // the grids: ↑ ↓ a row, page up / down a page
        if k == .tab {
            switch screen {
            case .dex(_, let f, false): gridTap(4100 + (f + (shift ? 3 : 1)) % 4)
            case .box(_, .none, _, false): gridTap(4100 + (boxSort + (shift ? 3 : 1)) % 4)
            default: if chevron != nil { toggleStatus() }                                   // where the status sheet is: fold / unfold it
            }
            return true
        }
        switch screen { case .shop, .shopConfirm, .tower, .radar, .items, .train, .relearn, .learn, .menu, .box: if held, k == .enter { return true }; default: break }   // a held return / space doesn't keep buying, pay into the tower after a pick, pick a bush too early, or go on from 포켓몬 to a page and its 진화 / 함께
        guard let i = [Key.left: 0, .enter: 1, .right: 2, .back: 3, .menu: 4][k] else { return false }
        press(i); return true
    }

    /// The status sheet folded or open (the title row's ⌄, or Tab), kept for next time.
    func toggleStatus() { statusOpen.toggle(); if persist { settings.set("homePanel", statusOpen) }; refreshPane(Date(), force: true) }
    /// The title row's ⌄ / ⌃ where the pane has no page of its own (home and its messages): true = open; nil = none.
    var chevron: Bool? { pane.status != nil || pane == PaneContent() ? statusOpen : nil }

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
        case .relearn(let r, _, _): return ("기술 바꾸기", state.mon(r).map { monNames[$0.dex] + " Lv.\($0.level)" } ?? "")
        case .course: return ("코스", "\(courses.indices.filter(state.unlocked).count) / \(courses.count) 열림")
        case .train: return ("대단한 특훈", "은색병뚜껑 ×\(state.count("은색병뚜껑"))")
        case .tower: return ("배틀 타워", "\((state.bp ?? 0).formatted())BP")
        default: return (state.here.name, cloudNote ?? (gate.held ? "자동 입력 감지 · 걸음 멈춤" : when))                                                 // screens without a page of their own: the status sheet
        }
    }
}
