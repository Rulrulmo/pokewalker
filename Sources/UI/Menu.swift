import AppKit
// The right-click / menu-bar menu and its actions.

extension WalkerView {
    func sexMark(_ m: Mon) -> String { genderRate[m.dex] < 0 ? "" : m.female ? " ♀" : " ♂" }
    func movesLine(_ m: Mon) -> String { "기술: " + m.moves.map { moveTable[$0]!.name }.joined(separator: " · ") }
    /// 능력치 / 개체값 / 노력치, one line each (HP 공격 방어 특공 특방 스피드).
    func statLines(_ m: Mon) -> [String] {
        let names = ["HP", "공격", "방어", "특공", "특방", "스피드"]
        func row(_ v: [Int]) -> String { zip(names, v).map { "\($0) \($1)" }.joined(separator: " · ") }
        let ev = m.evs ?? Array(repeating: 0, count: 6), iv = m.ivs ?? Array(repeating: 15, count: 6)
        let ivRow = names.indices.map { k in names[k] + " " + (m.hyper?.contains(k) == true ? "\(iv[k])→31" : "\(iv[k])") }.joined(separator: " · ")   // 특훈: its own IV → 31
        return ["능력치  " + row(m.stats), "개체값\(vMark(m))  " + ivRow + (m.ivs == nil ? " (예전 포켓몬)" : ""), "노력치  " + row(ev) + " · 합 \(ev.reduce(0, +))/510"]
    }
    /// " · 3V" (31s, 특훈 included), or nothing at 0V.
    func vMark(_ m: Mon) -> String { m.perfectIVs > 0 ? " · \(m.perfectIVs)V" : "" }
    /// The 3V+ colour: amber, darker on light menus (systemOrange there is ~2:1 on white), orange on dark ones.
    static let vColor = NSColor(name: "vMark") { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .systemOrange : NSColor(red: 0.69, green: 0.40, blue: 0, alpha: 1) }
    /// 3V and up in amber, bold, so the rare ones stand out in long lists; 1V / 2V stay plain.
    func emphasize(_ it: NSMenuItem, _ v: Int) {
        guard v >= 3, let r = it.title.range(of: "\(v)V", options: .backwards) else { return }
        let base = NSFont.menuFont(ofSize: 0), s = NSMutableAttributedString(string: it.title, attributes: [.font: base])
        s.addAttributes([.foregroundColor: WalkerView.vColor, .font: NSFont.boldSystemFont(ofSize: base.pointSize)], range: NSRange(r, in: it.title))
        it.attributedTitle = s
    }
    /// A fight is on (its screens, a turn playing, or a message on the way back to one).
    var inBattle: Bool {
        func fight(_ s: Screen) -> Bool { switch s { case .battle, .moves, .party, .bagBattle, .forfeit, .beats: true; case .say(_, let n, _): fight(n); default: false } }
        return fight(screen)
    }
    /// Menu actions that jump the walker to another screen wait until the fight is over (they used to end it in one click).
    func game(_ s: Selector) -> Selector? { inBattle ? nil : s }
    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: window?.isVisible == false ? "워커 보이기" : "메뉴 막대로 숨기기", action: #selector(toggleShown(_:)), keyEquivalent: "").target = self
        m.addItem(withTitle: "\(state.here.name) · 오늘 \(state.today)걸음 · \(state.watts)W", action: nil, keyEquivalent: "")
        if inBattle { m.addItem(withTitle: "⚔ 배틀 중 — 코스·동료·가방은 끝나고 쓸 수 있어요", action: nil, keyEquivalent: "") }
        m.addItem(.separator())
        let ch = m.addItem(withTitle: "코스 · \(state.here.name)", action: nil, keyEquivalent: ""), cm = NSMenu()
        for (i, c) in courses.enumerated() {
            let it = cm.addItem(withTitle: state.unlocked(i) ? c.name : c.dex > 0 ? "\(c.name) — 도감 \(c.dex)" : "\(c.name) — \(c.watts)W", action: state.unlocked(i) ? game(#selector(setCourse(_:))) : nil, keyEquivalent: "")
            it.target = self; it.tag = i; it.state = i == state.course ? .on : .off
        }
        ch.submenu = cm
        let ph = m.addItem(withTitle: "함께 걷기 · \(state.companion.shiny == true ? "★ " : "")\(monNames[state.companion.dex])", action: nil, keyEquivalent: ""), pm = NSMenu()
        let c = state.companion                                                                  // who's walking now: nature, ability, moves
        emphasize(pm.addItem(withTitle: "\(monNames[c.dex]) Lv.\(c.level)\(sexMark(c)) · \(c.natureName) · \(c.abilityName)\(vMark(c))", action: nil, keyEquivalent: ""), c.perfectIVs)
        for l in [movesLine(c)] + statLines(c) { pm.addItem(withTitle: l, action: nil, keyEquivalent: "") }
        pm.addItem(.separator())
        if state.box.isEmpty && state.caught.isEmpty { pm.addItem(withTitle: "잡은 포켓몬이 없다", action: nil, keyEquivalent: "") }
        let all = state.caught.enumerated().map { (-1 - $0, $1, " · 워커") } + state.box.enumerated().map { ($0, $1, "") }   // tag < 0 = on the walker
        func individual(_ into: NSMenu, _ e: (Int, Mon, String), named: Bool, count: Int = 1) {
            let (tag, b, whereIs) = e
            let it = into.addItem(withTitle: "\(b.shiny == true ? "★ " : "")\(named ? monNames[b.dex] + " " : "")Lv.\(b.level)\(sexMark(b)) · \(b.natureName) · \(b.abilityName)\(vMark(b))\(whereIs)\(count > 1 ? " ×\(count)" : "")", action: game(#selector(pair(_:))), keyEquivalent: "")
            it.target = self; it.tag = tag; it.toolTip = ([movesLine(b)] + statLines(b)).joined(separator: "\n"); emphasize(it, b.perfectIVs)
        }
        func species(_ into: NSMenu, _ groups: [(key: Int, value: [(Int, Mon, String)])]) {        // one row per species, the individuals inside
            for (dex, group) in groups {
                let bestV = group.map(\.1.perfectIVs).max() ?? 0                                        // the species row flags a 3V+ inside
                let head = into.addItem(withTitle: "\(monNames[dex])\(group.contains { $0.1.shiny == true } ? " ★" : "") · \(group.count)\(bestV >= 3 ? " · 최고 \(bestV)V" : "")", action: nil, keyEquivalent: ""), sm = NSMenu()
                emphasize(head, bestV)
                // look-alikes (same level, sex, 이로치, nature, ability, V count, place) are one row "×n"; picking it takes the one with the most EXP
                func key(_ e: (Int, Mon, String)) -> String { let m = e.1; return "\(m.shiny == true)|\(m.level)|\(m.female)|\(m.nature ?? 0)|\(m.abilityID)|\(m.perfectIVs)|\(e.2)" }
                func rank(_ m: Mon) -> (Int, Int, Int) { (m.shiny == true ? 1 : 0, m.perfectIVs >= 3 ? m.perfectIVs : 0, m.points) }   // 3V+ first (as emphasised); 1V / 2V don't push higher levels into 그 밖
                let rows: [(best: (Int, Mon, String), n: Int)] = Dictionary(grouping: group, by: key).values
                    .map { g in (best: g.max { $0.1.points < $1.1.points }!, n: g.count) }
                    .sorted { rank($0.best.1) > rank($1.best.1) }
                for r in rows.prefix(rows.count > 10 ? 8 : 10) { individual(sm, r.best, named: false, count: r.n) }
                if rows.count > 10 {                                                                   // the long tail, by level band
                    let rest = rows.dropFirst(8), mh = sm.addItem(withTitle: "그 밖 \(rest.reduce(0) { $0 + $1.n })마리", action: nil, keyEquivalent: ""), mm = NSMenu()
                    for (band, rs) in Dictionary(grouping: rest, by: { ($0.best.1.level - 1) / 10 }).sorted(by: { $0.key > $1.key }) {
                        let bh = mm.addItem(withTitle: "Lv.\(band * 10 + 1)–\(band * 10 + 10) · \(rs.reduce(0) { $0 + $1.n })마리", action: nil, keyEquivalent: ""), bm = NSMenu()
                        for r in rs { individual(bm, r.best, named: false, count: r.n) }
                        bh.submenu = bm
                    }
                    mh.submenu = mm
                }
                let dupes = state.duplicates(of: dex).count
                if dupes > 0 {
                    sm.addItem(.separator())
                    let it = sm.addItem(withTitle: "중복 놓아주기 · 상자의 \(dupes)마리", action: game(#selector(releaseDupes(_:))), keyEquivalent: ""); it.target = self; it.tag = dex
                }
                head.submenu = sm
            }
        }
        let groups = Dictionary(grouping: all, by: { $0.1.dex }).sorted(by: { $0.key < $1.key })
        if groups.count <= 12 { species(pm, groups) }
        else {                                                                                   // many species: recent + shinies up top, the rest by dex number in 50s
            pm.addItem(withTitle: "최근 잡은 포켓몬", action: nil, keyEquivalent: "")
            let recent: [(Int, Mon, String)] = Array(state.caught.enumerated().map { (-1 - $0.offset, $0.element, " · 워커") }.reversed()) + Array(state.box.enumerated().map { ($0.offset, $0.element, "") }.reversed())
            for e in recent.prefix(5) { individual(pm, e, named: true) }
            let shinies = all.filter { $0.1.shiny == true }
            if !shinies.isEmpty {
                let sh = pm.addItem(withTitle: "★ 이로치 · \(shinies.count)", action: nil, keyEquivalent: ""), sm = NSMenu()
                for e in shinies.sorted(by: { $0.1.dex < $1.1.dex }) { individual(sm, e, named: true) }
                sh.submenu = sm
            }
            let strong = all.filter { $0.1.perfectIVs >= 3 }                                        // 3V+ get a list of their own, like 이로치
            if !strong.isEmpty {
                let sh = pm.addItem(withTitle: "3V 이상 · \(strong.count)", action: nil, keyEquivalent: ""), sm = NSMenu(); emphasize(sh, 3)
                for e in strong.sorted(by: { ($0.1.perfectIVs, $0.1.points) > ($1.1.perfectIVs, $1.1.points) }) { individual(sm, e, named: true) }
                sh.submenu = sm
            }
            pm.addItem(.separator())
            for (bucket, g) in Dictionary(grouping: groups, by: { ($0.key - 1) / 50 }).sorted(by: { $0.key < $1.key }) {
                let bv = g.flatMap(\.value).map(\.1.perfectIVs).max() ?? 0
                let head = pm.addItem(withTitle: String(format: "No.%03d–%03d · %d종", bucket * 50 + 1, bucket * 50 + 50, g.count) + (bv >= 3 ? " · 최고 \(bv)V" : ""), action: nil, keyEquivalent: ""), sm = NSMenu()
                emphasize(head, bv); species(sm, g); head.submenu = sm
            }
        }
        ph.submenu = pm
        let now = Date(), stones = state.stoneEvolutions(now)
        if !stones.isEmpty {
            let sh = m.addItem(withTitle: "진화의 돌 쓰기", action: nil, keyEquivalent: ""), sm = NSMenu()
            for (i, e) in stones.enumerated() { let it = sm.addItem(withTitle: "\(e.item!) → \(monNames[e.to])", action: game(#selector(useStone(_:))), keyEquivalent: ""); it.target = self; it.tag = i }
            sh.submenu = sm
        }
        let inv = state.inventory
        if !inv.isEmpty {                                                                         // everything carried: walker + bag
            let bh = m.addItem(withTitle: "가방 · \(state.items.count + state.bag.count)개", action: nil, keyEquivalent: ""), bm = NSMenu()
            if state.count("이상한사탕") > 0 { bm.addItem(withTitle: "이상한사탕 먹이기 (×\(state.count("이상한사탕")))", action: game(#selector(useCandy(_:))), keyEquivalent: "").target = self }
            let vits = inv.compactMap { i -> (String, Int, Int)? in if case .vitamin(let k, let d) = ItemKind.of(i) { return (i, k, d) }; return nil }
            if !vits.isEmpty || state.count("순백떡") > 0 {
                let ev = state.companion.evs ?? Array(repeating: 0, count: 6), names = ["HP", "공격", "방어", "특공", "특방", "스피드"]
                let vh = bm.addItem(withTitle: "영양제 · 노력치 (\(monNames[state.companion.dex]) 합 \(ev.reduce(0, +))/510)", action: nil, keyEquivalent: ""), vm = NSMenu()
                for (i, k, d) in vits {
                    let it = vm.addItem(withTitle: "\(i) ×\(state.count(i)) · \(names[k]) \(d > 0 ? "+" : "−")10 (지금 \(ev[k]))", action: game(#selector(useVitamin(_:))), keyEquivalent: "")
                    it.target = self; it.representedObject = i
                }
                if state.count("순백떡") > 0 {
                    if !vits.isEmpty { vm.addItem(.separator()) }
                    let it = vm.addItem(withTitle: "순백떡 ×\(state.count("순백떡")) · 노력치 전부 0으로", action: game(#selector(useReset(_:))), keyEquivalent: ""); it.target = self
                }
                vh.submenu = vm
            }
            let caps = (silver: state.count("은색병뚜껑"), gold: state.count("금색병뚜껑"))
            if caps.silver + caps.gold > 0 {                                                      // 대단한 특훈: the companion, from Lv.50
                let c = state.companion, iv = c.effectiveIVs, names = ["HP", "공격", "방어", "특공", "특방", "스피드"], ready = c.level >= Walk.hyperLevel
                let hh = bm.addItem(withTitle: "병뚜껑 · 대단한 특훈 (\(monNames[c.dex])\(vMark(c)))", action: nil, keyEquivalent: ""), hm = NSMenu()
                if !ready { hm.addItem(withTitle: "Lv.\(Walk.hyperLevel)부터 특훈할 수 있어요 (지금 Lv.\(c.level))", action: nil, keyEquivalent: "") }
                for k in 0..<6 where caps.silver > 0 {
                    let it = hm.addItem(withTitle: "은색병뚜껑 ×\(caps.silver) · \(names[k]) \(iv[k])\(iv[k] < 31 ? " → 31" : " (최고)")", action: ready && iv[k] < 31 ? game(#selector(useCap(_:))) : nil, keyEquivalent: "")
                    it.target = self; it.tag = k
                }
                if caps.gold > 0 {
                    if caps.silver > 0 { hm.addItem(.separator()) }
                    let it = hm.addItem(withTitle: "금색병뚜껑 ×\(caps.gold) · 모든 능력 → 31", action: ready && iv.contains { $0 < 31 } ? game(#selector(useCap(_:))) : nil, keyEquivalent: ""); it.target = self; it.tag = -1
                }
                hh.submenu = hm
            }
            let berries = inv.filter { ItemKind.of($0) == .berry }
            if !berries.isEmpty {
                let fh = bm.addItem(withTitle: "열매 먹이기 · 친밀도 +500걸음", action: nil, keyEquivalent: ""), fm = NSMenu()
                for b in berries { let it = fm.addItem(withTitle: "\(b) ×\(state.count(b))", action: game(#selector(useBerry(_:))), keyEquivalent: ""); it.target = self; it.representedObject = b }
                fh.submenu = fm
            }
            let wares = inv.compactMap { i -> (String, Int)? in if case .sell(let p) = ItemKind.of(i) { return (i, p) }; return nil }
            if !wares.isEmpty {
                let total = wares.reduce(0) { $0 + $1.1 * state.count($1.0) }
                let sh = bm.addItem(withTitle: "팔기 · 전부 \(total)W", action: nil, keyEquivalent: ""), sm = NSMenu()
                sm.addItem(withTitle: "전부 팔기 (\(total)W)", action: game(#selector(sellAll(_:))), keyEquivalent: "").target = self
                sm.addItem(.separator())
                for (i, p) in wares { let it = sm.addItem(withTitle: "\(i) ×\(state.count(i)) — \(p * state.count(i))W", action: game(#selector(sellOne(_:))), keyEquivalent: ""); it.target = self; it.representedObject = i }
                sh.submenu = sm
            }
            bm.addItem(.separator())
            for i in inv {
                bm.addItem(withTitle: "\(i) ×\(state.count(i)) · \(ItemKind.of(i).summary)", action: nil, keyEquivalent: "")
            }
            bh.submenu = bm
        }
        func sub(_ title: String, _ items: [(String, Int)], _ current: Int, _ sel: Selector) {
            let head = m.addItem(withTitle: "\(title) · \(items.first { $0.1 == current }?.0 ?? "")", action: nil, keyEquivalent: ""), sm = NSMenu()
            for (t, tag) in items { let i = sm.addItem(withTitle: t, action: sel, keyEquivalent: ""); i.target = self; i.tag = tag; i.state = tag == current ? .on : .off }
            head.submenu = sm
        }
        m.addItem(.separator())
        sub("크기", [("보통", 2), ("크게", 3), ("아주 크게", 4)], Int(SIZE), #selector(setSize(_:)))
        if let sm = m.items.last?.submenu { sm.autoenablesItems = false; for i in sm.items { i.isEnabled = sizeFits(CGFloat(i.tag)) } }   // a size whose tallest page won't fit this screen
        sub("기기", shells.enumerated().map { ($1.dex > dexCount ? "\($1.name) — 도감 \($1.dex)" : !shellOpen($1) ? "\($1.name) — \($1.bp)BP" : $1.name, $0) }, theme, #selector(setTheme(_:)))
        sub("화면", lcds.enumerated().map { ($1.name, $0) }, lcdStyle, #selector(setLCD(_:)))
        sub("수첩 배경", paperNames.enumerated().map { ($1, $0) }, paperStyle, #selector(setPaper(_:)))
        sub("화면 글씨", [("매끈하게", 1), ("도트", 0)], smoothText ? 1 : 0, #selector(setTextStyle(_:)))
        m.addItem(.separator())
        let nh = m.addItem(withTitle: "알림", action: nil, keyEquivalent: ""), nm = NSMenu()
        for (i, (k, name)) in notifyKinds.enumerated() { let it = nm.addItem(withTitle: name, action: #selector(toggleNotify(_:)), keyEquivalent: ""); it.target = self; it.tag = i; it.state = notifyOn(k) ? .on : .off }
        nm.addItem(.separator())
        nm.addItem(withTitle: "테스트 알림 보내기", action: #selector(testNotify(_:)), keyEquivalent: "").target = self
        nh.submenu = nm
        m.addItem(.separator())
        m.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        return m
    }
    @objc func releaseDupes(_ i: NSMenuItem) {
        let dex = i.tag, gone = state.duplicates(of: dex), n = gone.count
        let stay = state.box.indices.filter { state.box[$0].dex == dex && !gone.contains($0) }.map { state.box[$0] }
        let who = stay.prefix(4).map { "\($0.shiny == true ? "★" : "")Lv.\($0.level)\(sexMark($0))\(vMark($0))" }.joined(separator: ", ") + (stay.count > 4 ? " 외 \(stay.count - 4)마리" : "")
        guard n > 0 else { return }
        NSApp.activate(ignoringOtherApps: true)                                                   // the only time it takes focus: a real confirmation
        let a = NSAlert(); a.messageText = "\(monNames[dex]) \(n)마리를 놓아줄까요?"
        a.informativeText = "상자에서 이로치와 3V 이상은 모두 남고, 그 밖엔 가장 좋은 1마리(V 수 → 경험치 순)만 남아요 — 3V 이상이 있으면 그 1마리 몫도 그쪽이에요.\n남는 포켓몬: \(who)\n되돌릴 수 없어요."
        a.addButton(withTitle: "놓아주기"); a.addButton(withTitle: "취소")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let r = state.releaseDuplicates(of: dex)
        screen = .say(["\(r.count)마리를 놓아줬다", "+\(r.watts)W"], next: .home, since: Date()); save(nil)
    }
    @objc func testNotify(_ i: NSMenuItem) { notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 인사해요", "알림이 이렇게 와요 · 지금 \(state.watts)W") }
    @objc func toggleNotify(_ i: NSMenuItem) { let k = notifyKinds[i.tag].0; UserDefaults.standard.set(!notifyOn(k), forKey: "notify.\(k)") }
    /// Walker <-> menu bar. Hiding parks it on the home screen so the events (which wait for home) keep coming.
    @objc func toggleShown(_ sender: Any?) {
        guard let w = window else { return }
        if w.isVisible { if !inBattle { screen = .home }; w.orderOut(nil) } else { shown = nil; refreshPane(Date(), force: true); w.orderFrontRegardless() }   // a fight just waits while hidden; back at today's page and height
        UserDefaults.standard.set(!w.isVisible, forKey: "hidden")
    }
    func updateStatus() {
        let s = "\(state.watts)W" + (state.egg.map { $0.left < 500 ? " ·알" : "" } ?? "")                 // watts: what the radar / dowsing spend
        if s != lastStatus { lastStatus = s; statusItem?.button?.title = " " + s }
    }
    @objc func statusClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            statusItem?.menu = buildMenu(); statusItem?.button?.performClick(nil); statusItem?.menu = nil   // pop the menu once, keep left-click as the toggle
        } else { toggleShown(nil) }
    }
    @objc func setCourse(_ i: NSMenuItem) { state.setCourse(i.tag, &rng); screen = .say(["커넥트 완료", state.here.name], next: .home, since: Date()); save(nil) }
    @objc func useCandy(_ i: NSMenuItem) {
        guard state.feedCandy() else { return }
        levelled = true; screen = .home; save(nil)                                              // the home screen shows the level-up (or an evolution)
    }
    @objc func useVitamin(_ i: NSMenuItem) {
        guard let v = i.representedObject as? String else { return }
        let name = monNames[state.companion.dex]
        if let e = state.feedVitamin(v) { screen = .say([josa(name, "은", "는") + " " + josa(v, "을", "를"), "먹었다!", "노력치 \(e)"], next: .home, since: Date()); save(nil) }
        else { screen = .say([josa(v, "을", "를") + " 먹어도", "효과가 없을 것 같다"], next: .home, since: Date()) }
    }
    @objc func useReset(_ i: NSMenuItem) {
        let name = monNames[state.companion.dex]
        if state.resetEVs() { screen = .say([josa(name, "은", "는") + " 순백떡을", "먹었다!", "노력치가 0이 되었다"], next: .home, since: Date()); save(nil) }
        else { screen = .say(["노력치가 이미", "0이다"], next: .home, since: Date()) }
    }
    @objc func useCap(_ i: NSMenuItem) {                                                        // tag: the stat, -1 = 금색병뚜껑 (all)
        let name = monNames[state.companion.dex], stat: Int? = i.tag < 0 ? nil : i.tag
        guard state.hyperTrain(stat) else { screen = .say(["특훈할 수 없다"], next: .home, since: Date()); return }
        let what = stat.map { ["HP", "공격", "방어", "특공", "특방", "스피드"][$0] } ?? "모든 능력"
        screen = .say(["대단한 특훈!", josa(name, "의", "의") + " " + what, "최고가 되었다! (\(state.companion.perfectIVs)V)"], next: .home, since: Date()); save(nil)
    }
    @objc func useBerry(_ i: NSMenuItem) {
        guard let b = i.representedObject as? String, state.feedBerry(b) else { return }
        screen = .say([josa(monNames[state.companion.dex], "이", "가") + " " + josa(b, "을", "를"), "맛있게 먹었다!"], next: .home, since: Date()); save(nil)
    }
    @objc func sellOne(_ i: NSMenuItem) { guard let n = i.representedObject as? String else { return }; let w = state.sell(n); screen = .say([n + " 판매", "+\(w)W"], next: .home, since: Date()); save(nil) }
    @objc func sellAll(_ i: NSMenuItem) {
        let w = state.inventory.reduce(0) { $0 + state.sell($1) }
        screen = .say(["전부 팔았다", "+\(w)W"], next: .home, since: Date()); save(nil)
    }
    @objc func useStone(_ i: NSMenuItem) { let s = state.stoneEvolutions(Date()); guard s.indices.contains(i.tag) else { return }; startEvolving(s[i.tag], Date()) }
    @objc func pair(_ i: NSMenuItem) {
        if i.tag < 0 { guard state.caught.indices.contains(-1 - i.tag) else { return }; state.pair(-1 - i.tag, onWalker: true) }
        else { guard state.box.indices.contains(i.tag) else { return }; state.pair(i.tag) }
        screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: .home, since: Date()); save(nil)
    }
    /// The tallest page (포켓몬 · 도구) at that size fits the screen the card is on.
    func sizeFits(_ size: CGFloat) -> Bool { SideView.tallest * size / 2 <= (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? .infinity }
    @objc func setSize(_ item: NSMenuItem) {                     // keeps the top-left corner, as the card grows down
        guard sizeFits(CGFloat(item.tag)) else { NSSound.beep(); return }
        SIZE = CGFloat(item.tag); UserDefaults.standard.set(item.tag, forKey: "px")
        fitWindow(); shown = nil; needsDisplay = true
    }
    /// A frame pulled back inside a screen's visible area (the body is wide: a spot near an edge must not push it off).
    static func onScreen(_ f: NSRect, in s: NSRect?) -> NSRect {
        guard let s else { return f }
        var g = f; g.origin.x = min(max(g.minX, s.minX), s.maxX - g.width); g.origin.y = min(max(g.minY, s.minY), s.maxY - g.height); return g
    }
    func shellOpen(_ s: Shell) -> Bool { s.dex <= dexCount && (s.bp == 0 || (state.bought ?? []).contains(s.name)) }
    @objc func setTheme(_ item: NSMenuItem) { guard shellOpen(shells[item.tag]) else { return }; theme = item.tag; UserDefaults.standard.set(theme, forKey: "shell"); needsDisplay = true }
    @objc func setTextStyle(_ item: NSMenuItem) { smoothText = item.tag == 1; UserDefaults.standard.set(smoothText, forKey: "smoothText"); shown = nil; needsDisplay = true }
    @objc func setLCD(_ item: NSMenuItem) { shown = nil; lcdStyle = item.tag; UserDefaults.standard.set(lcdStyle, forKey: "lcd"); needsDisplay = true }
    @objc func setPaper(_ item: NSMenuItem) { shown = nil; paperStyle = item.tag; UserDefaults.standard.set(paperStyle, forKey: "paper"); needsDisplay = true }
}
