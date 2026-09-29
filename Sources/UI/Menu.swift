import AppKit
// The right-click / menu-bar menu and its actions.

extension WalkerView {
    func sexMark(_ m: Mon) -> String { genderRate[m.dex] < 0 ? "" : m.female ? " ♀" : " ♂" }
    func movesLine(_ m: Mon) -> String { "기술: " + m.moves.map { moveTable[$0]!.name }.joined(separator: " · ") }
    /// 능력치 / 개체값 / 노력치, one line each (HP 공격 방어 특공 특방 스피드).
    func statLines(_ m: Mon) -> [String] {
        func row(_ v: [Int]) -> String { zip(["HP", "공격", "방어", "특공", "특방", "스피드"], v).map { "\($0) \($1)" }.joined(separator: " · ") }
        let ev = m.evs ?? Array(repeating: 0, count: 6)
        return ["능력치  " + row(m.stats), "개체값  " + row(m.ivs ?? Array(repeating: 15, count: 6)) + (m.ivs == nil ? " (예전 포켓몬)" : ""), "노력치  " + row(ev) + " · 합 \(ev.reduce(0, +))/510"]
    }
    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: window?.isVisible == false ? "워커 보이기" : "메뉴 막대로 숨기기", action: #selector(toggleShown(_:)), keyEquivalent: "").target = self
        m.addItem(withTitle: "\(state.here.name) · 오늘 \(state.today)걸음 · \(state.watts)W", action: nil, keyEquivalent: "")
        m.addItem(.separator())
        let ch = m.addItem(withTitle: "코스 · \(state.here.name)", action: nil, keyEquivalent: ""), cm = NSMenu()
        for (i, c) in courses.enumerated() {
            let it = cm.addItem(withTitle: state.unlocked(i) ? c.name : c.dex > 0 ? "\(c.name) — 도감 \(c.dex)" : "\(c.name) — \(c.watts)W", action: state.unlocked(i) ? #selector(setCourse(_:)) : nil, keyEquivalent: "")
            it.target = self; it.tag = i; it.state = i == state.course ? .on : .off
        }
        ch.submenu = cm
        let ph = m.addItem(withTitle: "함께 걷기 · \(state.companion.shiny == true ? "★ " : "")\(monNames[state.companion.dex])", action: nil, keyEquivalent: ""), pm = NSMenu()
        let c = state.companion                                                                  // who's walking now: nature, ability, moves
        pm.addItem(withTitle: "\(monNames[c.dex]) Lv.\(c.level)\(sexMark(c)) · \(c.natureName) · \(c.abilityName)", action: nil, keyEquivalent: "")
        for l in [movesLine(c)] + statLines(c) { pm.addItem(withTitle: l, action: nil, keyEquivalent: "") }
        pm.addItem(.separator())
        if state.box.isEmpty && state.caught.isEmpty { pm.addItem(withTitle: "잡은 포켓몬이 없다", action: nil, keyEquivalent: "") }
        let all = state.caught.enumerated().map { (-1 - $0, $1, " · 워커") } + state.box.enumerated().map { ($0, $1, "") }   // tag < 0 = on the walker
        func individual(_ into: NSMenu, _ e: (Int, Mon, String), named: Bool, count: Int = 1) {
            let (tag, b, whereIs) = e
            let it = into.addItem(withTitle: "\(b.shiny == true ? "★ " : "")\(named ? monNames[b.dex] + " " : "")Lv.\(b.level)\(sexMark(b)) · \(b.natureName) · \(b.abilityName)\(whereIs)\(count > 1 ? " ×\(count)" : "")", action: #selector(pair(_:)), keyEquivalent: "")
            it.target = self; it.tag = tag; it.toolTip = ([movesLine(b)] + statLines(b)).joined(separator: "\n")
        }
        func species(_ into: NSMenu, _ groups: [(key: Int, value: [(Int, Mon, String)])]) {        // one row per species, the individuals inside
            for (dex, group) in groups {
                let head = into.addItem(withTitle: "\(monNames[dex])\(group.contains { $0.1.shiny == true } ? " ★" : "") · \(group.count)", action: nil, keyEquivalent: ""), sm = NSMenu()
                // look-alikes (same level, sex, 이로치, place) are one row "×n"; picking it takes the one with the most EXP
                func key(_ e: (Int, Mon, String)) -> String { let m = e.1; return "\(m.shiny == true)|\(m.level)|\(m.female)|\(m.nature ?? 0)|\(m.abilityID)|\(e.2)" }
                func rank(_ m: Mon) -> (Int, Int) { (m.shiny == true ? 1 : 0, m.points) }
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
                let dupes = state.box.filter { $0.dex == dex && $0.shiny != true }.count - 1
                if dupes > 0 {
                    sm.addItem(.separator())
                    let it = sm.addItem(withTitle: "중복 놓아주기 · 상자의 \(dupes)마리", action: #selector(releaseDupes(_:)), keyEquivalent: ""); it.target = self; it.tag = dex
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
            pm.addItem(.separator())
            for (bucket, g) in Dictionary(grouping: groups, by: { ($0.key - 1) / 50 }).sorted(by: { $0.key < $1.key }) {
                let head = pm.addItem(withTitle: String(format: "No.%03d–%03d · %d종", bucket * 50 + 1, bucket * 50 + 50, g.count), action: nil, keyEquivalent: ""), sm = NSMenu()
                species(sm, g); head.submenu = sm
            }
        }
        ph.submenu = pm
        let now = Date(), stones = state.stoneEvolutions(now)
        if !stones.isEmpty {
            let sh = m.addItem(withTitle: "진화의 돌 쓰기", action: nil, keyEquivalent: ""), sm = NSMenu()
            for (i, e) in stones.enumerated() { let it = sm.addItem(withTitle: "\(e.item!) → \(monNames[e.to])", action: #selector(useStone(_:)), keyEquivalent: ""); it.target = self; it.tag = i }
            sh.submenu = sm
        }
        let sh = m.addItem(withTitle: "상점 · \(state.watts)W", action: nil, keyEquivalent: ""), shm = NSMenu()
        for (i, w) in Walk.shop.enumerated() {
            let it = shm.addItem(withTitle: "\(w.item) — \(w.watts)W", action: state.watts >= w.watts ? #selector(buyShop(_:)) : nil, keyEquivalent: ""); it.target = self; it.tag = i
        }
        for (i, l) in Walk.legendShop.enumerated() where l.watts > 0 { shm.addItem(.separator()); legendItem(shm, i, l.dex, "\(l.watts.formatted())W", state.watts >= l.watts) }
        sh.submenu = shm
        let bh2 = m.addItem(withTitle: "BP 교환소 · \(state.bp ?? 0)BP", action: nil, keyEquivalent: ""), bpm = NSMenu()
        for (i, w) in Walk.bpShop.enumerated() {
            let it = bpm.addItem(withTitle: "\(w.item) — \(w.bp)BP", action: (state.bp ?? 0) >= w.bp ? #selector(buyBP(_:)) : nil, keyEquivalent: ""); it.target = self; it.tag = i
        }
        for (i, s) in shells.enumerated() where s.bp > 0 {
            let owned = (state.bought ?? []).contains(s.name)
            let it = bpm.addItem(withTitle: "기기 색: \(s.name) — \(owned ? "보유" : "\(s.bp)BP")", action: !owned && (state.bp ?? 0) >= s.bp ? #selector(buyShell(_:)) : nil, keyEquivalent: ""); it.target = self; it.tag = i
        }
        for (i, l) in Walk.legendShop.enumerated() where l.bp > 0 { bpm.addItem(.separator()); legendItem(bpm, i, l.dex, "\(l.bp)BP", (state.bp ?? 0) >= l.bp) }
        bh2.submenu = bpm
        let wares = state.evolutionItems()
        if !wares.isEmpty {                                                                     // HGSS sold these for Pokéathlon points; here, watts
            let xh = m.addItem(withTitle: "교환소 · \(price)W", action: nil, keyEquivalent: ""), xm = NSMenu()
            for (i, w) in wares.enumerated() { let it = xm.addItem(withTitle: "\(w)\(state.bag.contains(w) ? " (있음)" : "")", action: state.watts >= price ? #selector(buy(_:)) : nil, keyEquivalent: ""); it.target = self; it.tag = i }
            xh.submenu = xm
        }
        let inv = state.inventory
        if !inv.isEmpty {                                                                         // everything carried: walker + bag
            let bh = m.addItem(withTitle: "가방 · \(state.items.count + state.bag.count)개", action: nil, keyEquivalent: ""), bm = NSMenu()
            if state.count("이상한사탕") > 0 { bm.addItem(withTitle: "이상한사탕 먹이기 (×\(state.count("이상한사탕")))", action: #selector(useCandy(_:)), keyEquivalent: "").target = self }
            let vits = inv.compactMap { i -> (String, Int, Int)? in if case .vitamin(let k, let d) = ItemKind.of(i) { return (i, k, d) }; return nil }
            if !vits.isEmpty {
                let ev = state.companion.evs ?? Array(repeating: 0, count: 6), names = ["HP", "공격", "방어", "특공", "특방", "스피드"]
                let vh = bm.addItem(withTitle: "영양제 · 노력치 (\(monNames[state.companion.dex]) 합 \(ev.reduce(0, +))/510)", action: nil, keyEquivalent: ""), vm = NSMenu()
                for (i, k, d) in vits {
                    let it = vm.addItem(withTitle: "\(i) ×\(state.count(i)) · \(names[k]) \(d > 0 ? "+" : "−")10 (지금 \(ev[k]))", action: #selector(useVitamin(_:)), keyEquivalent: "")
                    it.target = self; it.representedObject = i
                }
                vh.submenu = vm
            }
            let berries = inv.filter { ItemKind.of($0) == .berry }
            if !berries.isEmpty {
                let fh = bm.addItem(withTitle: "열매 먹이기 · 친밀도 +500걸음", action: nil, keyEquivalent: ""), fm = NSMenu()
                for b in berries { let it = fm.addItem(withTitle: "\(b) ×\(state.count(b))", action: #selector(useBerry(_:)), keyEquivalent: ""); it.target = self; it.representedObject = b }
                fh.submenu = fm
            }
            let wares = inv.compactMap { i -> (String, Int)? in if case .sell(let p) = ItemKind.of(i) { return (i, p) }; return nil }
            if !wares.isEmpty {
                let total = wares.reduce(0) { $0 + $1.1 * state.count($1.0) }
                let sh = bm.addItem(withTitle: "팔기 · 전부 \(total)W", action: nil, keyEquivalent: ""), sm = NSMenu()
                sm.addItem(withTitle: "전부 팔기 (\(total)W)", action: #selector(sellAll(_:)), keyEquivalent: "").target = self
                sm.addItem(.separator())
                for (i, p) in wares { let it = sm.addItem(withTitle: "\(i) ×\(state.count(i)) — \(p * state.count(i))W", action: #selector(sellOne(_:)), keyEquivalent: ""); it.target = self; it.representedObject = i }
                sh.submenu = sm
            }
            bm.addItem(.separator())
            for i in inv {
                let use: String = switch ItemKind.of(i) {
                case .heal(let n): "배틀 HP +\(n)"; case .revive(let n): "쓰러지면 HP \(n)로 부활"; case .ball(let x): "포획 ×\(x == 2 ? "2" : "1.5")"
                case .candy: "레벨 +1"; case .vitamin(let k, let d): "\(["HP", "공격", "방어", "특공", "특방", "스피드"][k]) 노력치 \(d > 0 ? "+" : "−")10"; case .berry: "친밀도 +500걸음"; case .evolution: "진화"; case .sell(let p): "\(p)W"
                case .battle(let u): switch u { case .cure: "배틀 상태이상 회복"; case .restore: "배틀 HP·상태 전부 회복"; case .pp: "배틀 PP 회복"; case .x: "배틀 능력 +1"
                    case .guardSpec: "배틀 능력 저하 막기"; case .direHit: "배틀 급소율 +"; case .heal: "" }
                }
                bm.addItem(withTitle: "\(i) ×\(state.count(i)) · \(use)", action: nil, keyEquivalent: "")
            }
            bh.submenu = bm
        }
        func sub(_ title: String, _ items: [(String, Int)], _ current: Int, _ sel: Selector) {
            let head = m.addItem(withTitle: "\(title) · \(items.first { $0.1 == current }?.0 ?? "")", action: nil, keyEquivalent: ""), sm = NSMenu()
            for (t, tag) in items { let i = sm.addItem(withTitle: t, action: sel, keyEquivalent: ""); i.target = self; i.tag = tag; i.state = tag == current ? .on : .off }
            head.submenu = sm
        }
        m.addItem(.separator())
        sub("크기", [("보통", 2), ("크게", 3), ("아주 크게", 4)], Int(PX), #selector(setSize(_:)))
        sub("기기", shells.enumerated().map { ($1.dex > dexCount ? "\($1.name) — 도감 \($1.dex)" : !shellOpen($1) ? "\($1.name) — \($1.bp)BP" : $1.name, $0) }, theme, #selector(setTheme(_:)))
        sub("화면", lcds.enumerated().map { ($1.name, $0) }, lcdStyle, #selector(setLCD(_:)))
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
        let dex = i.tag, n = state.box.filter { $0.dex == dex && $0.shiny != true }.count - 1
        guard n > 0 else { return }
        NSApp.activate(ignoringOtherApps: true)                                                   // the only time it takes focus: a real confirmation
        let a = NSAlert(); a.messageText = "\(monNames[dex]) \(n)마리를 놓아줄까요?"
        a.informativeText = "상자에서 이로치와 가장 레벨이 높은 1마리만 남아요. 되돌릴 수 없어요."
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
        if w.isVisible { screen = .home; w.orderOut(nil) } else { shown = nil; w.orderFrontRegardless() }
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
    func legendItem(_ menu: NSMenu, _ i: Int, _ dex: Int, _ cost: String, _ afford: Bool) {
        let owned = state.legendBought(dex)
        let it = menu.addItem(withTitle: "전설: \(monNames[dex]) Lv.\(Walk.legendShop[i].level) — \(owned ? "보유" : cost)", action: !owned && afford ? #selector(buyLegend(_:)) : nil, keyEquivalent: "")
        it.target = self; it.tag = i
    }
    @objc func buyLegend(_ i: NSMenuItem) {
        let l = Walk.legendShop[i.tag]
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "\(monNames[l.dex])을(를) 데려올까요?"
        a.informativeText = (l.watts > 0 ? "\(l.watts.formatted())W" : "\(l.bp)BP") + "가 들어요. 한 번만 살 수 있어요."
        a.addButton(withTitle: "데려오기"); a.addButton(withTitle: "취소")
        guard a.runModal() == .alertFirstButtonReturn, let m = state.buyLegend(i.tag) else { return }
        screen = .say(["전설의 " + monNames[m.dex] + "!", "Lv.\(m.level) · 워커에 왔다"], next: .home, since: Date()); save(nil)
        notify("unlock", "전설의 \(monNames[m.dex])", "Lv.\(m.level)이 워커에 왔어요")
    }
    @objc func buyShop(_ i: NSMenuItem) { let w = Walk.shop[i.tag]; guard state.buy(w.item, watts: w.watts) else { return }; screen = .say([josa(w.item, "을", "를"), "샀다! (-\(w.watts)W)"], next: .home, since: Date()); save(nil) }
    @objc func buyBP(_ i: NSMenuItem) { let w = Walk.bpShop[i.tag]; guard state.buy(w.item, bp: w.bp) else { return }; screen = .say([josa(w.item, "을", "를"), "받았다! (-\(w.bp)BP)"], next: .home, since: Date()); save(nil) }
    @objc func buyShell(_ i: NSMenuItem) {
        let s = shells[i.tag]; guard (state.bp ?? 0) >= s.bp else { return }
        state.bp = (state.bp ?? 0) - s.bp; state.bought = (state.bought ?? []) + [s.name]; theme = i.tag; UserDefaults.standard.set(theme, forKey: "shell")
        screen = .say(["기기 색", s.name + " 획득!"], next: .home, since: Date()); save(nil)
    }
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
    @objc func buy(_ i: NSMenuItem) {
        let w = state.evolutionItems(); guard w.indices.contains(i.tag), state.spend(price) else { return }
        state.bag.append(w[i.tag]); screen = .say([josa(w[i.tag], "을", "를"), "받았다!"], next: .home, since: Date()); save(nil)
    }
    @objc func pair(_ i: NSMenuItem) {
        if i.tag < 0 { guard state.caught.indices.contains(-1 - i.tag) else { return }; state.pair(-1 - i.tag, onWalker: true) }
        else { guard state.box.indices.contains(i.tag) else { return }; state.pair(i.tag) }
        screen = .say([josa(monNames[state.companion.dex], "과", "와"), "함께 걷는다!"], next: .home, since: Date()); save(nil)
    }
    @objc func setSize(_ item: NSMenuItem) {                     // keeps the top-right corner
        guard let w = window else { return }
        var f = w.frame; f.origin.x += f.width - CGFloat(item.tag) * dev.w; f.origin.y += f.height - CGFloat(item.tag) * dev.h
        PX = CGFloat(item.tag); UserDefaults.standard.set(item.tag, forKey: "px")
        f.size = devSize
        if let s = w.screen?.visibleFrame { f.origin.x = min(max(f.origin.x, s.minX), s.maxX - f.width); f.origin.y = min(max(f.origin.y, s.minY), s.maxY - f.height) }
        w.setFrame(f, display: true); setFrameSize(devSize); window?.invalidateCursorRects(for: self); needsDisplay = true
    }
    func shellOpen(_ s: Shell) -> Bool { s.dex <= dexCount && (s.bp == 0 || (state.bought ?? []).contains(s.name)) }
    @objc func setTheme(_ item: NSMenuItem) { guard shellOpen(shells[item.tag]) else { return }; theme = item.tag; UserDefaults.standard.set(theme, forKey: "shell"); needsDisplay = true }
    @objc func setTextStyle(_ item: NSMenuItem) { smoothText = item.tag == 1; UserDefaults.standard.set(smoothText, forKey: "smoothText"); shown = nil; needsDisplay = true }
    @objc func setLCD(_ item: NSMenuItem) { shown = nil; lcdStyle = item.tag; UserDefaults.standard.set(lcdStyle, forKey: "lcd"); needsDisplay = true }
}
