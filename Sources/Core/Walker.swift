import Foundation
// The walker: its state, the clock tick, the keys, the pane's page and the title row as data. What the buttons do: Core/Flow.swift; the LCD: Core/Compose.swift; the card drawn: Core/Card.swift.
// Whatever shows it is its host (Core/Platform.swift): the Mac's is WalkerView. No host = headless (the self-test): nothing drawn, no steps counted.

@MainActor final class Walker {
    var state: Walk
    var screen = Screen.home
    weak var host: (any Host)?
    var lastInput = Date(), lastStep = Date.distantPast, lastSave = Date()
    var boxSort = 0                                                        // the 상자 grid's order: 번호순 / 레벨순 / V순 / 최근
    var chainNote: String? = nil                                           // "+6W · 기력의조각" under "연쇄 3!"
    var keyShown: Bool?? = .none                                           // the 메뉴 / 홈 key as last shown (see homeKey)
    var strollX = 54.0, strollRight = false, strollAt = Date(), strollTurnAt = Date(), stepRate = 0.0   // home: the walking sprite's middle in the course picture (half-dots), which way it goes, the pace
    var usedItem = "몬스터볼"                                                // the potion / ball / revive the current beat names
    var towerRun = false                                                   // a tower run is on (the server's: it ends with the session)
    var growthThen: Screen? = nil                                      // where a fight's end goes once home's news have played (settle): the lobby
    var sideOn = false                                                     // the pane carries the battle's text (the app; not --selftest): the LCD shows the stage only
    var emote: (kind: Int, until: Date)? = nil                             // ♪ ♥ ! bubble over the companion
    var animOn: (who: String, dex: Int, since: Date)? = nil                // the entry animation playing (Anim.swift): home's companion or a page's Pokémon
    lazy var rewarded = dexCount                                           // dex count already celebrated (no fanfare for old progress)
    var dexCount: Int { (state.owned ?? []).count }
    var rng = Seeded(s: .random(in: .min ... .max))
    var pane = PaneContent(), paneAt = Date.distantPast                    // the pane's page as shown, when it was last refreshed
    var cardH = Layout.idle                                                // the card's height now (card points): the page's
    var hud: SideModel? = nil                                              // a fight's HP boxes, drawn over the LCD
    var savedSigned = settings.bool("saveSigned", false)                     // this machine has written a signed save (Store.loadChecked)
    var gate = StepGate()                                                  // the step filter
    var statusOpen = settings.bool("homePanel", true)                     // the title row's ⌄: the status sheet under the band where no page is up (open unless folded)
    var battleSpeed: Double { Double(settings.int("battleSpeed", 3)) / 2 }     // 배틀 속도 (the right-click's): 보통 x1, 빠르게 x1.5 (the default), 아주 빠르게 x2
    var titleShown = ""                                                    // the title row as last shown: a change redraws it
    var persist = true                                                     // false in --selftest: flows must never touch the real save (nor notify)
    var cloud: Cloud? = nil                                                // the save server (Core/Cloud.swift): set at launch (startCloud); the self-test's walkers get a fake's
    var cloudAsked: Cloud.Phase? = nil, cloudAsking = false                // the question asked
    var cloudShown: Cloud.Phase? = nil, idBoxShown = false                 // the server's state the LCD shows; the ID box opened by itself (once a launch)
    var updater: Updater? = nil, shuttingDown = false                      // auto-update (Core/Update.swift): set at launch; a logout / shutdown puts nothing in at quit
    var relaunchAfterQuit = false, notedUpdate: String? = nil, updateNotices = 0   // the menu's 업데이트 설치: the quit starts the new version; the version a banner said was ready
    var installWhenStaged = false, installAt: Date? = nil                  // 업데이트 확인 · 설치 clicked: what it finds goes in; the install's moment (after the LCD says so)
    /// What the quit runs to put a staged update in (relaunch: start it after); the self-test's stub records it instead.
    var installUpdate: @MainActor (_ relaunch: Bool) -> Bool = { r in Update.appURL.map { Update.install(dir: Update.dir, app: $0, relaunch: r) } ?? false }
    /// An act out (docs/plans/11, Core/Act.swift): keys held until the server answers; `then` = the screen its answer brings, `back` = where a
    /// "not now" goes; quiet: the act shows its own level-ups.
    struct Waiting { var act: Act; var back: Screen; var since: Date; var quiet: Bool; var then: @MainActor (Outcome, Date) -> Screen? }
    var waiting: Waiting? = nil
    var news: [News] = []                                                  // the server's, shown at home one at a time (settle)
    var fight: Battle? = nil, fightEnd: BattleEnd? = nil                   // the fight as the server last sent it; its end, once its beats have played
    var drag: (from: Int, at: CGPoint)? = nil                              // 포켓몬's grid: a Pokémon dragged (the page's code it began on, the pointer in page points)
    var chainNext: Int? = nil                                              // a chain holds (its length): its next bush is asked for once home's news are shown
    var trainRef = -1, itemFor: String? = nil
    var duel: DuelView? = nil, duelOn = false, duelSeen = 0, duelShown: Battle? = nil, duelWait = false   // 12 §5: the live battle's last view, polling, turns played, the battle shown, our pick in                              // 3.6: who 대단한 특훈 is on; an item whose target the fight's party screen asks for
    var raidOn = false, raidThen: Screen? = nil, raidPicked: [Int] = []   // 12 (M3): a raid fight is on (its menu, lines, HUD); where a raid ball's show goes after; 3.8: the last raid party (uids), offered first

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

    /// The clock (the host's, 10 a second): steps (up to the server, shown at once), screens that time out, home's news, the server's answers.
    func tick(_ now: Date) {
        let before = state.total
        if let h = host {                                                                          // keys + clicks, the way a person makes them (StepGate)
            state.rollover(now)                                                                    // (a capped day still turns at midnight)
            let taken = state.take(counter: h.counter(), boot: h.boot(), at: now)
            if !frozen {                                                                           // another PC has the trainer: the baseline follows, nothing walks (08 §2-1)
                let n = state.roomToday(gate.pass(taken, now.timeIntervalSinceReferenceDate))
                if n > 0 { cloud?.addSteps(n); if !inBattle { _ = state.walk(n, at: now) } }        // mid-fight the server holds them till its end
            }
        }
        perk(now, stepped: state.total != before)                                               // the companion's animation now and then
        if state.total != before { lastStep = now }
        stepRate = stepRate * 0.8 + Double(min(50, state.total - before)) * 10 * 0.2               // steps a second, smoothed (the tick is 10 Hz)
        switch screen {
        case .radar(_, _, let since, let chain) where now.timeIntervalSince(since) > 1.5 + radarWindow(chain):
            giveUpRadar(); screen = .say(chain > 0 ? ["...!", "연쇄가 끊겼다 (\(chain))"] : ["...!", "사라져버렸다"], next: .home, since: now)
        case .beats(let bt, let beats, let since, _) where now.timeIntervalSince(since) * battleSpeed >= beats.map(\.length).reduce(0, +):
            screen = beatsDone(bt, beats.last!, now)
        case .say(_, let next, let since) where now.timeIntervalSince(since) > 3: screen = next
        case .evolve(_, _, let since) where now.timeIntervalSince(since) > 6.5: screen = .home
        case .hatch(_, let since) where now.timeIntervalSince(since) > 5.5: screen = .home
        case .traded(_, _, _, let since) where now.timeIntervalSince(since) > 6: screen = .home
        case .menu, .card, .items, .dex, .box, .tower, .shop, .shopConfirm, .course, .train, .team, .relearn, .raid, .itemOn, .hold, .visitPick: if now.timeIntervalSince(lastInput) > 20 { screen = .home }
        case .trade, .market: if now.timeIntervalSince(lastInput) > 60 { screen = .home }       // (a trade is weighed up: longer)
        default: break
        }
        cloudTick(now)                                                                             // the server's answers (their screens, the save) …
        settle(now)                                                                                // … and at home its news, then where a fight was going on to
        if now.timeIntervalSince(lastSave) > 60 { save() }
        updater?.tick(now); updateTick(now)
    }
    /// Fights, shows and animations play at 30 fps; the rest (the walking sprite too: HGSS steps it every 0.15 s) at the tick's 10.
    var busy: Bool { switch screen { case .beats, .hatch, .evolve, .radar, .traded: true; default: animating || waiting != nil } }   // (an act out: its dots)

    /// The keys as the walker knows them: ◀ ▶ ↑ ↓, page up / down, tab, ● (return / space), ↩ (esc), 메뉴 / 홈 (M).
    enum Key { case left, right, up, down, pageUp, pageDown, tab, enter, back, menu }
    /// A key down (held: the key's repeat): in a shop ↑ ↓ = a row, or ±10; in a grid ↑ ↓ a row, page up / down a page; tab a grid's next tab
    /// (shift: the one before). false = not the walker's (the platform passes it on).
    func key(_ k: Key, shift: Bool = false, held: Bool = false) -> Bool {
        if frozen { if k == .enter, !held { press(1) }; return true }                              // another PC has it: ● = 여기서 계속, nothing else
        if waiting != nil { return true }                                                          // an act's answer on the way
        if case .shop(_, _, let q) = screen, let d = [Key.up: -1, .down: 1][k] { shopStep(q == nil ? d : -10 * d); return true }
        if case .shop(let bp, let sel, nil) = screen, k == .tab {                                    // 3.6: the next tab (shift: the one before), its first row
            let n = max(1, shopTabs(bp).count), t = (shopTab(bp, sel) + (shift ? n - 1 : 1)) % n
            if let first = shopRows(bp, t).first { screen = .shop(bp: bp, sel: first, qty: nil); lastInput = Date(); host?.redraw(.all) }
            return true
        }
        if case .tower(_?) = screen, let d = [Key.up: -1, .down: 1, .pageUp: -TowerModel.perPage, .pageDown: TowerModel.perPage][k] { towerStep(d); return true }   // the tower's picker: ↑ ↓ a row, page up / down a page
        switch screen { case .course, .train, .relearn: if let d = [Key.up: -1, .down: 1, .pageUp: -CourseModel.perPage, .pageDown: CourseModel.perPage][k] { listRow(d); return true }; default: break }   // the lists: the same
        if case .items = screen, let d = [Key.up: -1, .down: 1, .pageUp: -6, .pageDown: 6][k] { listRow(d); return true }   // 도구: six rows in view
        if case .hold(let r, let s) = screen, let d = [Key.up: -1, .down: 1, .pageUp: -6, .pageDown: 6][k] { let n = holdRows(r).count; if n > 0 { screen = .hold(ref: r, sel: max(0, min(n - 1, s + d))); lastInput = Date(); host?.redraw(.all) }; return true }
        if case .team(let s, let t, false) = screen {                                             // 팀: ↑ ↓ a row, page up / down a page, tab the next tab
            if let d = [Key.up: -1, .down: 1, .pageUp: -TeamModel.perPage, .pageDown: TeamModel.perPage][k] { teamStep(d, wrap: false); return true }
            if k == .tab { let n = teamTabCount; screen = .team(sel: 0, tab: (t + (shift ? n - 1 : 1)) % n, card: false); _ = s; host?.redraw(.all); return true }
        }
        if case .trade = screen, tradeKey(k, shift: shift) { return true }
        if case .market = screen, marketKey(k, shift: shift) { return true }                    // 교환 게시판: its rows, tabs, the pick's grid
        if case .raid(let t) = screen, k == .tab { screen = .raid(tab: 1 - t); host?.redraw(.all); return true }   // 레이드: its two tabs                       // 교환: its lists' rows and pages, tab (the other box; 팀's tabs)
        switch screen { case .dex(_, _, false), .box(_, .none, _, false): if let d = [Key.up: -6, .down: 6, .pageUp: -30, .pageDown: 30][k] { gridStep(d, ends: abs(d) == 30); return true }; default: break }   // the grids: ↑ ↓ a row, page up / down a page
        if k == .tab {
            switch screen {
            case .dex(_, let f, false): gridTap(4100 + (f + (shift ? 3 : 1)) % 4)
            case .box(_, .none, _, false): gridTap(4100 + (boxSort + (shift ? 3 : 1)) % 4)
            default: if chevron != nil { toggleStatus() }                                   // where the status sheet is: fold / unfold it
            }
            return true
        }
        switch screen { case .shop, .shopConfirm, .tower, .radar, .items, .train, .relearn, .learn, .menu, .box, .trade, .team, .raid, .market, .itemOn, .duel, .hold, .visitPick, .squad: if held, k == .enter { return true }; default: break }   // a held return / space doesn't keep buying, pay into the tower after a pick, pick a bush too early, go on from 포켓몬 to a page and its 진화 / 함께, or pick and send a trade
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
            if raidThen != nil { return ("레이드", "볼 던지기") }
            if duelOn { return ("실시간 대전", "vs \(duel?.opponent ?? "")" + (duelLeft().map { " · \($0)초" } ?? "")) }                                       // a raid ball's throw on the battle stage
            if raidOn { return ("레이드 배틀", "남은 줄 \(b.theirs.filter(\.alive).count) / \(b.theirs.count) · \(min(b.turnNo + 1, Engine.raidTurns))/\(Engine.raidTurns)턴") }
            guard let tr = b.trainer else { return ("야생 배틀", state.here.name) }
            let left = { (fs: [Fighter]) in fs.filter(\.alive).count }
            return (tr, "배틀 타워 · 남은 \(left(b.theirs)) : \(left(b.mine))")
        }
        let when = "\(state.season.name) \(state.gameDay % seasonDays + 1)일째 · \((state.weather ?? .sunny).name)"
        switch sc {
        case .dex: return ("도감", "잡음 \(dexCount) · 봤음 \(seenList.count)")
        case .box(let i, _, _, true) where state.mon(i)?.ot != nil: return ("포켓몬", "어버이: " + (state.mon(i)?.ot ?? ""))   // a traded one: who it came from first
        case .box, .items: return ("포켓몬", "워커 \(state.caught.count) · 상자 \(state.box.count.formatted()) · 도구 \(state.items.count + state.bag.count)")
        case .menu: return ("메뉴", "")
        case .shop(let bp, _, _), .shopConfirm(let bp, _, _): return (bp ? "BP 교환소" : "상점", "")
        case .radar: return ("포켓 레이더", state.here.name)
        case .card: return ("트레이너 카드", "")
        case .team(_, let t, let card): return ("친구", card ? "" : t == 0 ? "지금 걷는 중이 위" : t == 4 ? "친구 신청" : t == 5 ? "맡겨 키우기 · 5시간" : t == 6 ? "모든 트레이너" : "이번 주 순위 · \(Walker.teamTabs[t])")
        case .visitPick: return ("맡겨 키우기", "5시간 · 키운 걸음만큼 경험치")
        case .trade(.list): return ("교환", "받은 신청")
        case .market(.board(3, _)): return ("교환 게시판", "받기 함")
        case .market(.board): return ("교환 게시판", "모두의 글 · 3일 동안")
        case .market(.post(let id, _)): return ("교환 게시판", listing(id).map { $0.mine ? "내 글 · 제안 \($0.bids)개" : "제안은 하나만" } ?? "")
        case .market(.pick(let p)): return ("교환 게시판", p.listing == nil ? "원하는 종은 3개까지" : "내 상자에서 골라 주세요")
        case .trade(.offer(let id, _)): return ("교환", tradeOffer(id).map { mineOffer($0) ? "보낸 신청" : "받은 신청" } ?? "")
        case .trade(.pick(let p)): return ("교환", p.offer == nil ? "상자의 포켓몬끼리" : "내 상자에서 골라 주세요")
        case .learn: return ("기술 배우기", "")
        case .relearn(let r, _, _): return ("기술 바꾸기", state.mon(r).map { monNames[$0.dex] + " Lv.\($0.level)" } ?? "")
        case .course: return ("코스", "\(courses.indices.filter(state.unlocked).count) / \(courses.count) 열림")
        case .train: return ("대단한 특훈", "은색병뚜껑 ×\(state.count("은색병뚜껑"))")
        case .itemOn(let p): return ("도구", p.item)
        case .duel(.hub(let t, _)): return ("대전", t == 0 ? "Lv.50 · 3마리씩" : "최근 20판")
        case .duel(.queued): return ("랜덤 매칭", duelLeft().map { "\($0)초 남음" } ?? "")
        case .duel: return ("실시간 대전", duelLeft().map { "\($0)초 남음" } ?? "")
        case .squad(let s): switch s.kind { case .duelParty: return ("대전 파티", "3~6마리 · 대전은 Lv.50"); case .raid: return ("레이드", "출전할 1~3마리"); case .duelPick: return ("실시간 대전", "3마리 고르기" + (duelLeft().map { " · \($0)초" } ?? "")) }
        case .hold(let r, _): return ("지니게 하기", state.mon(r).map { monNames[$0.dex] + " Lv.\($0.level)" } ?? "")
        case .tower: return ("배틀 타워", "\((state.bp ?? 0).formatted())BP")
        case .raid: return ("레이드", cloud?.raid.map { "다음 주 " + monNames[$0.next] } ?? "")
        default: return (state.here.name, cloudNote ?? (gate.held ? "자동 입력 감지 · 걸음 멈춤" : when))                                                 // screens without a page of their own: the status sheet
        }
    }
}
