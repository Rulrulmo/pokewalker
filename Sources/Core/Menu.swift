import Foundation
// The right-click / menu-bar menu as data over the walker's state; each row's action is a closure on the walker (Flow.swift, the look's setters below).
// The Mac shows it as its native menu (Mac/MenuBar.swift).

/// A row: its title, on or off (off = a dim note), ✓, a submenu, what it does; strong = the part shown bold in amber (3V and up), key = a shortcut
/// (종료: q), tip = a hover note. A separator is a line between groups.
struct MenuItem {
    var title: String, enabled: Bool, checked: Bool, key: String, tip: String?, strong: String? = nil, isSeparator = false
    var children: [MenuItem]?, action: (@MainActor () -> Void)?
    /// On unless `enabled` says: the rows that do something or open a submenu (the rest are notes).
    init(_ title: String, checked: Bool = false, enabled: Bool? = nil, key: String = "", tip: String? = nil, _ children: [MenuItem]? = nil, action: (@MainActor () -> Void)? = nil) {
        self.title = title; self.checked = checked; self.key = key; self.tip = tip; self.children = children; self.action = action
        self.enabled = enabled ?? (action != nil || children != nil)
    }
    static var separator: MenuItem { var m = MenuItem(""); m.isSeparator = true; return m }
    /// 3V and up in amber, bold, so the rare ones stand out in long lists (the title's last "nV"); 1V / 2V stay plain.
    func emphasized(_ n: Int) -> MenuItem { var m = self; if n >= 3, title.contains("\(n)V") { m.strong = "\(n)V" }; return m }
}

extension Walker {
    /// Menu actions that jump the walker to another screen wait until the fight is over (they used to end it in one click).
    func game(_ f: @escaping @MainActor () -> Void) -> (@MainActor () -> Void)? { inBattle ? nil : f }
    func menu() -> [MenuItem] {
        let state = self.state
        var m = [MenuItem(host?.windowHidden == true ? "워커 보이기" : "메뉴 막대로 숨기기", action: { self.host?.toggleShown() }),
                 MenuItem("\(state.here.name) · 오늘 \(state.today)걸음 · \(state.watts)W")]
        if inBattle { m.append(MenuItem("⚔ 배틀 중 — 코스·동료·가방은 끝나고 쓸 수 있어요")) }
        m.append(.separator)
        m.append(MenuItem("코스 · \(state.here.name)", courses.enumerated().map { i, c in
            MenuItem(state.unlocked(i) ? c.name : c.dex > 0 ? "\(c.name) — 도감 \(c.dex)" : "\(c.name) — \(c.watts)W", checked: i == state.course, action: state.unlocked(i) ? game { self.setCourse(i) } : nil)
        }))
        let c = state.companion                                                                  // who's walking now: nature, ability, moves
        var pm = [MenuItem("\(monNames[c.dex]) Lv.\(c.level)\(sexMark(c)) · \(c.natureName) · \(c.abilityName)\(vMark(c))").emphasized(c.perfectIVs)]
        pm += ([movesLine(c)] + statLines(c)).map { MenuItem($0) }
        pm.append(.separator)
        if state.box.isEmpty && state.caught.isEmpty { pm.append(MenuItem("잡은 포켓몬이 없다")) }
        let all = state.caught.enumerated().map { (-1 - $0, $1, " · 워커") } + state.box.enumerated().map { ($0, $1, "") }   // tag < 0 = on the walker
        func individual(_ e: (Int, Mon, String), named: Bool, count: Int = 1) -> MenuItem {
            let (tag, b, whereIs) = e
            return MenuItem("\(b.shiny == true ? "★ " : "")\(named ? monNames[b.dex] + " " : "")Lv.\(b.level)\(sexMark(b)) · \(b.natureName) · \(b.abilityName)\(vMark(b))\(whereIs)\(count > 1 ? " ×\(count)" : "")",
                            tip: ([movesLine(b)] + statLines(b)).joined(separator: "\n"), action: game { self.pair(tag) }).emphasized(b.perfectIVs)
        }
        func species(_ groups: [(key: Int, value: [(Int, Mon, String)])]) -> [MenuItem] {       // one row per species, the individuals inside
            groups.map { dex, group in
                let bestV = group.map(\.1.perfectIVs).max() ?? 0                                        // the species row flags a 3V+ inside
                // look-alikes (same level, sex, 이로치, nature, ability, V count, place) are one row "×n"; picking it takes the one with the most EXP
                func key(_ e: (Int, Mon, String)) -> String { let m = e.1; return "\(m.shiny == true)|\(m.level)|\(m.female)|\(m.nature ?? 0)|\(m.abilityID)|\(m.perfectIVs)|\(e.2)" }
                func rank(_ m: Mon) -> (Int, Int, Int) { (m.shiny == true ? 1 : 0, m.perfectIVs >= 3 ? m.perfectIVs : 0, m.points) }   // 3V+ first (as emphasised); 1V / 2V don't push higher levels into 그 밖
                let rows: [(best: (Int, Mon, String), n: Int)] = Dictionary(grouping: group, by: key).values
                    .map { g in (best: g.max { $0.1.points < $1.1.points }!, n: g.count) }
                    .sorted { rank($0.best.1) > rank($1.best.1) }
                var sm = rows.prefix(rows.count > 10 ? 8 : 10).map { individual($0.best, named: false, count: $0.n) }
                if rows.count > 10 {                                                                   // the long tail, by level band
                    let rest = rows.dropFirst(8)
                    sm.append(MenuItem("그 밖 \(rest.reduce(0) { $0 + $1.n })마리", Dictionary(grouping: rest, by: { ($0.best.1.level - 1) / 10 }).sorted(by: { $0.key > $1.key }).map { band, rs in
                        MenuItem("Lv.\(band * 10 + 1)–\(band * 10 + 10) · \(rs.reduce(0) { $0 + $1.n })마리", rs.map { individual($0.best, named: false, count: $0.n) })
                    }))
                }
                let dupes = state.duplicates(of: dex).count
                if dupes > 0 { sm += [.separator, MenuItem("중복 놓아주기 · 상자의 \(dupes)마리", action: game { self.askReleaseDupes(dex) })] }
                return MenuItem("\(monNames[dex])\(group.contains { $0.1.shiny == true } ? " ★" : "") · \(group.count)\(bestV >= 3 ? " · 최고 \(bestV)V" : "")", sm).emphasized(bestV)
            }
        }
        let groups = Dictionary(grouping: all, by: { $0.1.dex }).sorted(by: { $0.key < $1.key })
        if groups.count <= 12 { pm += species(groups) }
        else {                                                                                   // many species: recent + shinies up top, the rest by dex number in 50s
            pm.append(MenuItem("최근 잡은 포켓몬"))
            let recent: [(Int, Mon, String)] = Array(state.caught.enumerated().map { (-1 - $0.offset, $0.element, " · 워커") }.reversed()) + Array(state.box.enumerated().map { ($0.offset, $0.element, "") }.reversed())
            pm += recent.prefix(5).map { individual($0, named: true) }
            let shinies = all.filter { $0.1.shiny == true }
            if !shinies.isEmpty { pm.append(MenuItem("★ 이로치 · \(shinies.count)", shinies.sorted(by: { $0.1.dex < $1.1.dex }).map { individual($0, named: true) })) }
            let strong = all.filter { $0.1.perfectIVs >= 3 }                                        // 3V+ get a list of their own, like 이로치
            if !strong.isEmpty { pm.append(MenuItem("3V 이상 · \(strong.count)", strong.sorted(by: { ($0.1.perfectIVs, $0.1.points) > ($1.1.perfectIVs, $1.1.points) }).map { individual($0, named: true) }).emphasized(3)) }
            pm.append(.separator)
            for (bucket, g) in Dictionary(grouping: groups, by: { ($0.key - 1) / 50 }).sorted(by: { $0.key < $1.key }) {
                let bv = g.flatMap(\.value).map(\.1.perfectIVs).max() ?? 0
                pm.append(MenuItem(String(format: "No.%03d–%03d · %d종", bucket * 50 + 1, bucket * 50 + 50, g.count) + (bv >= 3 ? " · 최고 \(bv)V" : ""), species(g)).emphasized(bv))
            }
        }
        m.append(MenuItem("함께 걷기 · \(state.companion.shiny == true ? "★ " : "")\(monNames[state.companion.dex])", pm))
        let now = Date(), stones = state.stoneEvolutions(now)
        if !stones.isEmpty { m.append(MenuItem("진화의 돌 쓰기", stones.enumerated().map { i, e in MenuItem("\(e.item!) → \(monNames[e.to])", action: game { self.useStone(i) }) })) }
        let inv = state.inventory
        if !inv.isEmpty {                                                                         // everything carried: walker + bag
            var bm: [MenuItem] = []
            if state.count("이상한사탕") > 0 { bm.append(MenuItem("이상한사탕 먹이기 (×\(state.count("이상한사탕")))", action: game { self.useCandy() })) }
            let vits = inv.compactMap { i -> (String, Int, Int)? in if case .vitamin(let k, let d) = ItemKind.of(i) { return (i, k, d) }; return nil }
            if !vits.isEmpty || state.count("순백떡") > 0 {
                let ev = state.companion.evs ?? Array(repeating: 0, count: 6), names = ["HP", "공격", "방어", "특공", "특방", "스피드"]
                var vm = vits.map { i, k, d in MenuItem("\(i) ×\(state.count(i)) · \(names[k]) \(d > 0 ? "+" : "−")10 (지금 \(ev[k]))", action: game { self.useVitamin(i) }) }
                if state.count("순백떡") > 0 {
                    if !vits.isEmpty { vm.append(.separator) }
                    vm.append(MenuItem("순백떡 ×\(state.count("순백떡")) · 노력치 전부 0으로", action: game { self.useReset() }))
                }
                bm.append(MenuItem("영양제 · 노력치 (\(monNames[state.companion.dex]) 합 \(ev.reduce(0, +))/510)", vm))
            }
            let caps = (silver: state.count("은색병뚜껑"), gold: state.count("금색병뚜껑"))
            if caps.silver + caps.gold > 0 {                                                      // 대단한 특훈: the companion, from Lv.50
                let c = state.companion, iv = c.effectiveIVs, names = ["HP", "공격", "방어", "특공", "특방", "스피드"], ready = c.level >= Walk.hyperLevel
                var hm: [MenuItem] = []
                if !ready { hm.append(MenuItem("Lv.\(Walk.hyperLevel)부터 특훈할 수 있어요 (지금 Lv.\(c.level))")) }
                for k in 0..<6 where caps.silver > 0 {
                    hm.append(MenuItem("은색병뚜껑 ×\(caps.silver) · \(names[k]) \(iv[k])\(iv[k] < 31 ? " → 31" : " (최고)")", action: ready && iv[k] < 31 ? game { self.useCap(k) } : nil))
                }
                if caps.gold > 0 {
                    if caps.silver > 0 { hm.append(.separator) }
                    hm.append(MenuItem("금색병뚜껑 ×\(caps.gold) · 모든 능력 → 31", action: ready && iv.contains { $0 < 31 } ? game { self.useCap(nil) } : nil))   // nil = all
                }
                bm.append(MenuItem("병뚜껑 · 대단한 특훈 (\(monNames[c.dex])\(vMark(c)))", hm))
            }
            let berries = inv.filter { ItemKind.of($0) == .berry }
            if !berries.isEmpty { bm.append(MenuItem("열매 먹이기 · 친밀도 +500걸음", berries.map { b in MenuItem("\(b) ×\(state.count(b))", action: game { self.useBerry(b) }) })) }
            let wares = inv.compactMap { i -> (String, Int)? in if case .sell(let p) = ItemKind.of(i) { return (i, p) }; return nil }
            if !wares.isEmpty {
                let total = wares.reduce(0) { $0 + $1.1 * state.count($1.0) }
                bm.append(MenuItem("팔기 · 전부 \(total)W", [MenuItem("전부 팔기 (\(total)W)", action: game { self.sellAll() }), .separator]
                    + wares.map { i, p in MenuItem("\(i) ×\(state.count(i)) — \(p * state.count(i))W", action: game { self.sellOne(i) }) }))
            }
            bm.append(.separator)
            bm += inv.map { MenuItem("\($0) ×\(state.count($0)) · \(ItemKind.of($0).summary)") }
            m.append(MenuItem("가방 · \(state.items.count + state.bag.count)개", bm))
        }
        func sub(_ title: String, _ items: [(String, Int)], _ current: Int, fits: ((Int) -> Bool)? = nil, _ set: @escaping @MainActor (Int) -> Void) -> MenuItem {
            MenuItem("\(title) · \(items.first { $0.1 == current }?.0 ?? "")", items.map { t, tag in MenuItem(t, checked: tag == current, enabled: fits.map { $0(tag) }, action: { set(tag) }) })
        }
        m.append(.separator)
        m.append(sub("크기", [("보통", 2), ("크게", 3), ("아주 크게", 4)], Int(SIZE), fits: { self.host?.fits(size: CGFloat($0)) ?? true }) { self.setSize($0) })   // a size whose tallest page won't fit this screen: off
        m.append(sub("기기", shells.enumerated().map { ($1.dex > dexCount ? "\($1.name) — 도감 \($1.dex)" : !shellOpen($1) ? "\($1.name) — \($1.bp)BP" : $1.name, $0) }, theme) { self.setTheme($0) })
        m.append(sub("화면", lcds.enumerated().map { ($1.name, $0) }, lcdStyle) { self.setLCD($0) })
        m.append(sub("수첩 배경", paperNames.enumerated().map { ($1, $0) }, paperStyle) { self.setPaper($0) })
        m.append(sub("화면 글씨", [("매끈하게", 1), ("도트", 0)], smoothText ? 1 : 0) { self.setTextStyle($0 == 1) })
        m.append(.separator)
        m.append(MenuItem("알림", notifyKinds.enumerated().map { i, kn in MenuItem(kn.1, checked: notifyOn(kn.0), action: { self.toggleNotify(i) }) }
            + [.separator, MenuItem("테스트 알림 보내기", action: { self.testNotify() })]))
        m.append(.separator)
        m.append(MenuItem("종료", key: "q", action: { self.host?.quit() }))
        return m
    }

    // MARK: the menu's own actions (the walker's: Flow.swift)
    /// 중복 놓아주기: asks first (who stays, that it can't be undone), then lets them go.
    func askReleaseDupes(_ dex: Int) {
        let gone = state.duplicates(of: dex), n = gone.count
        let stay = state.box.indices.filter { state.box[$0].dex == dex && !gone.contains($0) }.map { state.box[$0] }
        let who = stay.prefix(4).map { "\($0.shiny == true ? "★" : "")Lv.\($0.level)\(sexMark($0))\(vMark($0))" }.joined(separator: ", ") + (stay.count > 4 ? " 외 \(stay.count - 4)마리" : "")
        guard n > 0, host?.confirm("\(monNames[dex]) \(n)마리를 놓아줄까요?",
            "상자에서 이로치와 3V 이상은 모두 남고, 그 밖엔 가장 좋은 1마리(V 수 → 경험치 순)만 남아요 — 3V 이상이 있으면 그 1마리 몫도 그쪽이에요.\n남는 포켓몬: \(who)\n되돌릴 수 없어요.", ok: "놓아주기") == true else { return }
        releaseDupes(dex)
    }
    func testNotify() { notify("pet", josa(monNames[state.companion.dex], "이", "가") + " 인사해요", "알림이 이렇게 와요 · 지금 \(state.watts)W") }
    func toggleNotify(_ i: Int) { let k = notifyKinds[i].0; settings.set("notify.\(k)", !notifyOn(k)) }
    /// 크기: the card grows down from its top-left (the host keeps it on the screen).
    func setSize(_ size: Int) {
        guard host?.fits(size: CGFloat(size)) ?? true else { host?.beep(); return }
        SIZE = CGFloat(size); settings.set("px", size)
        host?.resized(); host?.redraw(.all)
    }
    func setTheme(_ t: Int) { guard shellOpen(shells[t]) else { return }; theme = t; settings.set("shell", theme); host?.redraw(.all) }
    func setTextStyle(_ smooth: Bool) { smoothText = smooth; settings.set("smoothText", smoothText); host?.redraw(.all) }
    func setLCD(_ i: Int) { lcdStyle = i; settings.set("lcd", lcdStyle); host?.redraw(.all) }
    func setPaper(_ i: Int) { paperStyle = i; settings.set("paper", paperStyle); host?.redraw(.all) }
}
