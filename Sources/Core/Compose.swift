import Foundation
// Drawing each screen into the frame buffer; the Pokédex panel's model.

extension Walker {
    func compose(_ now: Date) -> FB {
        var fb = FB()
        let t = now.timeIntervalSinceReferenceDate, half = Int(t * 2) % 2, me = state.companion
        /// "3V" in the right column; from 3V an amber diamond beside it (the sparkle stays 이로치's).
        func vLabel(_ m: Mon, _ y: Int) {
            guard m.perfectIVs > 0 else { return }
            let w = fb.text("\(m.perfectIVs)V", 94, y, m.perfectIVs >= 3 ? 3 : 2, right: true, small: true)
            if m.perfectIVs >= 3 { fb.draw(vDiamond, 94 - w - 7, y + 2, vPal) }
        }
        func header(_ title: String) { if fb.text(title, 2, 0) < 62 { fb.text("\(state.watts)W", 94, 1, 2, right: true, small: true) }; fb.fill(0, 12, 96, 1, 2) }   // long names win over the W
        switch screen {
        case .home, .menu: home(&fb, now)                                                            // the notebook page (Notebook.swift); the menu is the pane's: the LCD stays home
        case .radar(_, _, let since, let chain):                                                    // which patch and the cursor are the pane's; here, the companion waiting in the grass
            let u = now.timeIntervalSince(since), window = radarWindow(chain), live = (1.5...(1.5 + window)).contains(u)
            let box = (x: 22, y: 12, w: courseBox.w, h: courseBox.h)                                   // the course picture, the companion standing in it
            fb.course(state.here.art, box.x, box.y, weather: state.weather ?? .sunny, t: t, hour: state.hour, season: state.season)
            let feet = walker(&fb, me, now, box: box, at: 2 * box.x + box.w)
            fb.radarFX(feet: feet, live: live ? u - 1.5 : nil, u: u)
            if live { hpBar(&fb, box.x, 52, box.w, Int(((1.5 + window - u) * 1000).rounded()), Int(window * 1000)) }   // the time left to pick one
            if chain > 0 { fb.text(u < 1.5 ? "연쇄 \(chain)!" : "연쇄 \(chain)", 2, 1, 3, small: u >= 1.5) }
            if chain > 0, u < 1.5, let n = chainNote { fb.text(n, 0, 51, 2, center: true, small: true) }   // under the picture, where the time bar goes next
        case .battle(let b, _) where sideOn, .moves(let b, _) where sideOn, .party(let b, _) where sideOn, .bagBattle(let b, _) where sideOn, .forfeit(let b, _) where sideOn:
            stage(&fb, b, now, .idle, hud: false)                                                   // the side panel carries names, HP, menus
        case .beats where sideOn:
            let s = beatState(now)!
            stage(&fb, s.hp, now, pose(s.beat, s.u, s.hp), hud: false, pending: s.pending, beat: (s.beat, s.u))
            if case .hit(_, _, _, _, true) = s.beat, s.u < 0.15 { fb.invert(0, 0, 96, 64) }
            if s.beat == .appear, legendDex.contains(s.from.wild.dex), s.u < 0.5, Int(s.u * 10) % 2 == 0 { fb.invert(0, 0, 96, 64) }
        case .forfeit(let b, let yes):
            stage(&fb, b, now, .idle)
            fb.text("기권할까?", 2, 52, 3, small: true)
            for (k, o) in ["아니오", "예"].enumerated() { let x = 48 + 24 * k, w = fb.text(o, x + 1, 52, 3, small: true); if (k == 1) == yes { fb.invert(x, 52, w + 2, 12) } }
        case .battle(let b, _) where duelWait:
            stage(&fb, b, now, .idle)
            fb.text("상대를 기다리는 중" + String(repeating: ".", count: Int(now.timeIntervalSinceReferenceDate * 2) % 4), 2, 52, 3, small: true)
        case .battle(let b, let sel):
            stage(&fb, b, now, .idle)
            let opts = battleMenu(b)
            for (k, r) in menuRanges(opts).enumerated() { fb.text(opts[k], r.lowerBound + 1, 52, 3, small: true); if k == sel { fb.invert(r.lowerBound, 52, r.count, 12) } }
        case .moves(let b, let sel):
            stage(&fb, b, now, .idle)
            let x = b.mine[b.me], ms = x.moves
            fb.fill(0, 37, 96, 27, 0); for y in 37..<64 { for x in 0..<96 { fb.col[y * 96 + x] = 0 } }; fb.fill(0, 37, 96, 1, 2)
            let x0 = x
            for (k, id) in ms.enumerated() {                                                          // 2 x 2: name (dim at 0 PP), then ▲ super effective / ▼ not very / × none
                let m = moveTable[id]!, x = (k % 2) * 48, y = 39 + (k / 2) * 12, e = b.hint(id, b.moveType(.me, m).type)
                let w = fb.text(m.name, x + 2, y, x0.pp[k] > 0 ? 3 : 1, small: true)
                fb.text(e == 0 ? "×" : e > 1 ? "▲" : e < 1 ? "▼" : "", x + 46, y, 2, right: true, small: true)
                if k == sel { fb.invert(x, y - 1, max(w + 3, 47), 11) }
            }
        case .party(let b, let sel):
            stage(&fb, b, now, .idle)
            fb.fill(0, 13, 96, 51, 0); for y in 13..<64 { for x in 0..<96 { fb.col[y * 96 + x] = 0 } }; fb.fill(0, 13, 96, 1, 2)
            for (k, f) in b.mine.enumerated() {
                let y = 16 + 15 * k
                fb.text((k == b.me ? "▶" : "") + monNames[f.mon.dex] + " Lv.\(f.mon.level)" + (f.status.map { " " + $0.badge } ?? ""), 2, y, f.alive ? 3 : 1, small: true)
                hpBar(&fb, 2, y + 9, 60, f.hp, f.maxHP); fb.text("\(f.hp)/\(f.maxHP)", 94, y + 3, 2, right: true, small: true)
                if k == sel { fb.invert(0, y - 1, 96, 14) }
            }
        case .bagBattle(let b, let sel):
            stage(&fb, b, now, .idle)
            fb.fill(0, 13, 96, 51, 0); for y in 13..<64 { for x in 0..<96 { fb.col[y * 96 + x] = 0 } }; fb.fill(0, 13, 96, 1, 2)
            let list = battleItems(b), top = max(0, min(sel - 2, list.count - 5))                // 5 rows, the pick kept in view
            for (k, it) in list.enumerated() where k >= top && k < top + 5 {
                let y = 15 + 10 * (k - top)
                fb.text(it.name, 2, y, 3, small: true); fb.text("×\(state.count(it.name))", 94, y, 2, right: true, small: true)
                if k == sel { fb.invert(0, y - 1, 96, 10) }
            }
        case .shop(let bp, let sel, let qty):
            func fit(_ s: String, _ w: Int) -> String {                                              // cut to w dots, with … (small text)
                guard textWidth(s, small: true) > w else { return s }
                var t = s; while t.count > 1, textWidth(t + "…", small: true) > w { t.removeLast() }; return t + "…"
            }
            let ws = wares(bp), unit = bp ? "BP" : "W", money = bp ? state.bp ?? 0 : state.watts
            fb.text(bp ? "BP 교환소" : "상점", 2, 0); fb.text("\(money)\(unit)", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)   // plain numbers, like the rest of the LCD
            if let q = qty, let w = ws[safe: sel] {                                                  // how many: ◀ ▶, ● buys, ↩ back
                let have = "보유 \(state.owned(w))"
                fb.text(fit(state.wareName(w), 88 - textWidth(have, small: true)), 2, 14, 3, small: true); fb.text(have, 94, 14, 2, right: true, small: true)
                fb.text(fit(state.wareNote(w), 92), 2, 23, 2, small: true)
                fb.text("◀", 14, 34, w.once ? 1 : 2); fb.text("× \(q)", 0, 34, 3, center: true); fb.text("▶", 82, 34, w.once ? 1 : 2, right: true)
                fb.fill(0, 50, 96, 1, 2)
                fb.text("\(w.price * q)\(unit) → 남음 \(money - w.price * q)\(unit)", 0, 53, 2, center: true, small: true)
            } else {
                let top = max(0, min(sel - 2, ws.count - 5))                                          // 5 rows, the pick kept in view
                for (k, w) in ws.enumerated() where k >= top && k < top + 5 {
                    let y = 14 + 10 * (k - top), can = state.canBuy(w, bp: bp) > 0, had = w.once && state.owned(w) > 0
                    let price = had ? "보유" : "\(w.price)\(unit)", pw = textWidth(price, small: true)
                    fb.text(fit(state.wareName(w), 88 - pw), 2, y, can ? 3 : 1, small: true); fb.text(price, 94, y, can ? 2 : 1, right: true, small: true)
                    if k == sel { fb.invert(0, y - 1, 96, 10) }
                }
            }
        case .shopConfirm(let bp, let sel, let yes):
            let unit = bp ? "BP" : "W"
            fb.text(bp ? "BP 교환소" : "상점", 2, 0); fb.text("\(bp ? state.bp ?? 0 : state.watts)\(unit)", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
            if let w = wares(bp)[safe: sel] {
                fb.text(state.wareName(w), 0, 16, 3, center: true, small: true); fb.text("\(w.price)\(unit) · 정말 살까?", 0, 27, 2, center: true, small: true)
                for (k, o) in ["아니오", "예"].enumerated() { let x = 14 + 40 * k, tw = fb.text(o, x + 2, 44, 3, small: true); if (k == 1) == yes { fb.invert(x, 43, tw + 4, 11) } }
            }
        case .learn(let sel):
            var st = state
            if let (ref, id) = st.nextToLearn(), let m = state.mon(ref) {
                fb.text("새 기술: " + moveTable[id]!.name, 2, 1, 3, small: true); fb.fill(0, 10, 96, 1, 2)
                for (k, label) in (m.moves.map { moveTable[$0]!.name } + ["배우지 않는다"]).enumerated() {
                    let y = 13 + 10 * k
                    fb.text(label, 2, y, 3, small: true)
                    if k < 4 { let mv = moveTable[m.moves[k]]!; fb.text((typeKo[mv.type] ?? "") + (mv.power > 0 ? " \(mv.power)" : ""), 94, y, 2, right: true, small: true) }
                    if k == sel { fb.invert(0, y - 1, 96, 10) }
                }
            }
        case .relearn(let r, let s, let at):
            guard let m = state.mon(r) else { break }
            func note(_ mv: MoveInfo) -> String { (typeKo[mv.type] ?? "") + (mv.power > 0 ? " \(mv.power)" : "") }
            if let at {                                                                            // what goes in slot s: five rows round the pick (its own marked with their slot)
                let all = m.relearnable, i = all.firstIndex(of: at) ?? 0, top = max(0, min(all.count - 5, i - 2))
                fb.text(m.moves[safe: s].map { "\(s + 1)번 " + moveTable[$0]!.name + " →" } ?? "빈 칸 →", 2, 1, 3, small: true); fb.fill(0, 10, 96, 1, 2)
                for (k, id) in all[top..<min(all.count, top + 5)].enumerated() {
                    let y = 13 + 10 * k, mv = moveTable[id]!
                    fb.text(mv.name, 2, y, 3, small: true); fb.text(m.moves.firstIndex(of: id).map { "\($0 + 1)번" } ?? note(mv), 94, y, 2, right: true, small: true)
                    if top + k == i { fb.invert(0, y - 1, 96, 10) }
                }
            } else {                                                                               // its slots (a free one while it knows fewer than 4)
                fb.text(monNames[m.dex] + "의 기술", 2, 1, 3, small: true); fb.fill(0, 10, 96, 1, 2)
                for k in 0..<min(4, m.moves.count + 1) {
                    let y = 13 + 10 * k
                    if let mv = m.moves[safe: k].flatMap({ moveTable[$0] }) { fb.text(mv.name, 2, y, 3, small: true); fb.text(note(mv), 94, y, 2, right: true, small: true) }
                    else { fb.text("빈 칸", 2, y, 2, small: true) }
                    if k == s { fb.invert(0, y - 1, 96, 10) }
                }
            }
        case .beats:
            let s = beatState(now)!
            stage(&fb, s.hp, now, pose(s.beat, s.u, s.hp), pending: s.pending, beat: (s.beat, s.u))
            fb.text(message(s.beat, s.u, s.names), 2, 52)
            if case .hit(_, _, _, _, true) = s.beat, s.u < 0.15 { fb.invert(0, 0, 96, 64) }           // critical: the whole screen flashes
            if s.beat == .appear, legendDex.contains(s.from.wild.dex), s.u < 0.5, Int(s.u * 10) % 2 == 0 { fb.invert(0, 0, 96, 64) }   // a legend: two flashes first
        case .tower:
            fb.text("배틀 타워", 2, 0); fb.text("\(state.bp ?? 0)BP", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
            fb.text(towerRun ? "\(state.towerStreak ?? 0)연승 중 · 최고 \(state.towerBest ?? 0)" : "최고 \(state.towerBest ?? 0)연승", 2, 14, 2, small: true)
            if sideOn { fb.towerHall(state.party().map(\.mon.dex), t); break }                        // the pane has the list and the buttons: the LCD shows the hall
            for (k, p) in state.party().enumerated() { fb.text((p.mon.shiny == true ? "★" : "") + monNames[p.mon.dex] +  " Lv.\(p.mon.level)" + (p.mon.level != Walk.towerLevel ? "→\(Walk.towerLevel)" : ""), 2, 24 + 9 * k, 3, small: true) }
            fb.fill(0, 51, 96, 1, 2)
            fb.text(towerRun ? "● 다음 상대  ↩ 나가기" : "● 도전 \(Walk.towerFee)W", 0, 53, 3, center: true, small: true)
        case .team(let sel, let tab, _): teamLCD(&fb, sel, tab, now)
        case .trade(let s): tradeLCD(&fb, s, now)
        case .itemOn(let p): itemOnLCD(&fb, p, now)
        case .duel(let s): duelLCD(&fb, s, now)
        case .hold(let ref, let sel): holdLCD(&fb, ref, sel, now)
        case .raid: raidLCD(&fb, now)
        case .market(let s): marketLCD(&fb, s, now)
        case .traded(let gave, let got, _, let since): tradedLCD(&fb, gave, got, since, now)
        case .card(let p):
            header(p == 0 ? cardTitle : ["트레이너 카드", "최근 7일", "알"][p])
            if p == 2 {
                if let e = state.egg {
                    fb.cardEgg(close: e.left < 500, t: t)
                    fb.text(e.left > 0 ? "앞으로 \(e.left)걸음" : "곧 태어난다!", 0, 52, 3, center: true)
                } else { fb.text("갖고 있지 않다", 0, 30, 2, center: true) }
            } else if p == 0 {
                fb.text(state.here.name, 2, 14)
                if state.corrected == true { fb.text("기록 보정됨", 94, 15, 1, right: true, small: true) }   // 1.7 took back a macro's gains
                fb.text("오늘  \(state.today)걸음", 2, 26)
                fb.text("\(state.season.name) \(state.gameDay % seasonDays + 1)일째 · " + (state.hour < 4 || state.hour >= 20 ? "밤" : state.hour < 6 ? "새벽" : state.hour >= 17 ? "저녁" : "낮"), 2, 38)
                let w = state.weather ?? .sunny
                fb.text("날씨 \(w.name) · " + w.types.map { typeKo[$0] ?? $0 }.joined(separator: "·") + "↑", 2, 50, 2)
            } else {
                let days = Array(([state.today] + state.history).prefix(8)), top = max(1, days.max()!)
                for (k, v) in days.enumerated() { let h = v * 34 / top, x = 84 - 11 * k; fb.fill(x, 60 - h, 8, h, k == 0 ? 3 : 2); fb.fill(x, 61, 8, 1, 1) }
                fb.text("\(top)", 94, 23, 1, right: true, small: true)
                fb.text("합계 \(state.total)" + (state.bestChain.map { " · 최고 연쇄 \($0)" } ?? ""), 2, 14, 2, small: true)
            }
        case .course(let i):                                                                       // 코스: the pick's picture and name (and what opens it)
            let c = courses[i], open = state.unlocked(i)
            header("코스")
            fb.course(c.art, 22, 15, weather: i == state.course ? state.weather ?? .sunny : .sunny, t: t, hour: state.hour, season: state.season)
            fb.text(c.name + (i == state.course ? " · 지금" : open ? "" : " · 잠김"), 48, 52, open ? 3 : 1, center: true, small: true)
        case .train(let k):                                                                        // 대단한 특훈: that one's IVs (trainRef), the pick
            header("대단한 특훈")
            let c = state.mon(trainRef) ?? state.companion, iv = c.effectiveIVs, names = ["HP", "공격", "방어", "특공", "특방", "스피드"]
            fb.text(monNames[c.dex] + " Lv.\(c.level)", 2, 15)
            for j in 0..<6 { let s = "\(names[j]) \(iv[j])"; fb.text(s, 2 + (j % 3) * 32, 30 + (j / 3) * 10, j == k ? 3 : 2, small: true); if j == k { fb.invert(1 + (j % 3) * 32, 29 + (j / 3) * 10, textWidth(s, small: true) + 2, 9) } }
            fb.text("은색병뚜껑 ×\(state.count("은색병뚜껑"))", 2, 52, 2, small: true)
        case .items(let sel):                                                                        // 도구: the pick (the pane has the list and its use)
            header("도구")
            let rows = state.inventory
            guard let n = rows[safe: min(sel, rows.count - 1)] else { fb.text("없음", 0, 30, 2, center: true); break }
            fb.draw(gem, 4, 20, gemPal); fb.text(n, 12, 16)
            fb.text("×\(state.count(n))" + (state.items.contains(n) ? " · 워커 \(state.items.filter { $0 == n }.count)" : ""), 12, 28, 2, small: true)
            fb.text(ItemKind.of(n).summary.replacingOccurrences(of: "지니게 하기: ", with: ""), 2, 40, 2, small: true)
            fb.text("\(min(sel, rows.count - 1) + 1)/\(rows.count)", 94, 52, 1, right: true, small: true)
        case .dex(let d, let f, _):
            let list = dexList(f), owned = (state.owned ?? []).contains(d)
            guard list.contains(d) else { fb.text("도감", 2, 0); fb.fill(0, 12, 96, 1, 2); fb.text(f == 2 ? "모두 잡았다!" : "없음", 0, 30, 2, center: true); break }   // an empty tab
            guard seenList.contains(d) else {                                                                // 전체 / 이 코스 show the ones not met yet: no picture, no name
                fb.text(String(format: "No.%03d ???", d), 2, 0); fb.fill(0, 12, 96, 1, 2)
                fb.text("아직 만나지 못했다", 0, 30, 2, center: true); fb.text("\((list.firstIndex(of: d) ?? 0) + 1)/\(list.count)", 94, 52, 1, right: true, small: true); break
            }
            fb.text(String(format: "No.%03d ", d) + monNames[d], 2, 0)
            if owned { fb.draw(ball, 88, 2, ballPal) }
            fb.fill(0, 12, 96, 1, 2)
            let m = Mon(dex: d, level: 1, female: false)
            let shinyNow = (state.shinyOwned ?? []).contains(d) && Int(t / 2) % 2 == 1                        // caught as 이로치: both colours, 2 s each
            let u = animT("dex", d, now)
            if owned { fb.mon(Mon(dex: d, level: 1, female: false, shiny: shinyNow ? true : nil), half, 0, 2, anim: u) } else { fb.mon(m, 0, 0, 2, tint: (3, rgb(70, 74, 84)), anim: u) }   // only seen: a shadow
            if shinyNow { fb.text("★이로치", 94, 32, 3, right: true, small: true) }
            fb.text(monTypes[d].map { typeKo[$0] ?? $0 }.joined(separator: "·"), 94, 16, 2, right: true, small: true)
            fb.text(owned ? "잡음" : "봤음", 94, 42, 2, right: true, small: true)
            fb.text("\((list.firstIndex(of: d) ?? 0) + 1)/\(list.count)", 94, 52, 1, right: true, small: true)
        case .box(let i, let act, let confirm, let detail):
            guard let m = state.mon(i) else { header("포켓몬"); break }
            header((m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)")
            fb.mon(m, half, 0, 2, anim: animT("box \(i)", m.dex, now))
            fb.text(i == -1 ? "함께" : i < -1 ? "워커 \(-1 - i)" : "상자 \((boxOrder.firstIndex(of: i) ?? 0) + 1)/\(state.box.count)", 94, 15, 2, right: true, small: true)   // where it is
            if genderRate[m.dex] >= 0 { fb.text(m.female ? "암컷" : "수컷", 94, 26, 2, right: true, small: true) }; vLabel(m, 36)   // genderless: nothing (the games show no symbol)
            if let a = act {
                fb.fill(0, 50, 96, 14, 0); fb.fill(0, 50, 96, 1, 2)
                let opts = confirm ? ["놓아줄까?", "아니오", "예"] : boxActs(i)
                var x = 1
                for (k, o) in opts.enumerated() {
                    let w = fb.text(o, x + 1, 52, 3, small: true) + 2
                    if confirm ? k - 1 == a : k == a { fb.invert(x, 52, w, 11) }
                    x += w + 1
                }
            } else { fb.text(detail && i == -1 ? "함께 걷는 중" : detail ? "● 메뉴" : "● 자세히", 94, 52, 2, right: true, small: true) }   // the grid's ● opens its page; the page's opens 함께 / 상자로 or 놓아주기
        case .hatch(let m, let since):
            let u = now.timeIntervalSince(since)
            fb.hatchFX(m, u, bob: half)                                                                    // rocks, cracks, bursts; the Pokémon out of the light at 3 s
            fb.fill(0, 50, 96, 1, 2)
            if u < 3.05 { fb.text("어라...?", 0, 52, 3, center: true) } else { fb.text(josa(monNames[m.dex], "이", "가") + " 태어났다!", 2, 52) }
        case .evolve(let from, let to, let since):
            let u = now.timeIntervalSince(since)
            fb.evolveFX(from, to, u, bob: half)                                                            // glows (1.2), the shapes take turns (4.0), white (4.4), the new form
            fb.fill(0, 50, 96, 1, 2)
            fb.text(u < 4.4 ? "어라...? " + josa(monNames[from.dex], "이", "가") + "...!" : josa(monNames[to.dex], "으로", "로") + " 진화했다!", 2, 52)
        case .say(let lines, let next, _):
            switch next {                                                                             // a fight's own message is on the pane: the LCD keeps the stage
            case .battle(let b, _) where sideOn, .moves(let b, _) where sideOn, .party(let b, _) where sideOn, .bagBattle(let b, _) where sideOn, .forfeit(let b, _) where sideOn:
                stage(&fb, b, now, .idle, hud: false)
            default: for (k, l) in lines.enumerated() { fb.text(l, 0, 32 - lines.count * 7 + 14 * k, center: true) }
            }
        }
        if let w = waiting, now.timeIntervalSince(w.since) > 0.3 {                                  // an act's answer on the way (docs/plans/11 §5): dots in the corner, one more each third of a second
            for k in 0...(Int(now.timeIntervalSince(w.since) * 3) % 3) { fb.fill(85 + 4 * k, 1, 2, 2, 3) }
        }
        return fb
    }
    func evoText(_ e: Evo) -> String {
        let when = e.time.map { $0 == "day" ? "낮" : "밤" }, sex = e.female.map { $0 ? "♀" : "♂" }
        let place = e.place.map { ["cave": "동굴 코스", "forest": "숲 코스"][$0] ?? "얼음 산길" }
        switch e.way {
        case .level: let parts = [e.level > 0 ? "Lv.\(e.level)" : nil, when, sex, place, e.item.map { $0 + " 소지" }, e.party.map { monNames[$0] + " 보유" }].compactMap { $0 }; return parts.isEmpty ? "레벨 업" : parts.joined(separator: " · ")
        case .friend: return (["친밀도(함께 1만 걸음)"] + [when].compactMap { $0 }).joined(separator: " · ")
        case .item: return e.item! + " 사용" + (sex.map { " · " + $0 } ?? "")
        case .trade: return "교환" + (e.item.map { " · " + $0 + " 소지" } ?? "")              // at a real trade (12 §3), at its new trainer; the item from the giver's bag
        }
    }
    /// The pane's 도감 entry page (● on the grid); nil elsewhere.
    func dexModel() -> DexModel? {
        guard case .dex(let d, _, true) = screen else { return nil }
        let owned = Set(state.owned ?? []), seen = Set(seenList), st = owned.contains(d) ? 2 : seen.contains(d) ? 1 : 0
        var found: [String] = [], evos: [String] = []
        if st > 0 {
            for (ci, c) in courses.enumerated() {
                let tag = c.legends.contains(d) ? "전설" : c.slots.contains { $0.dex == d } ? "" : c.extra.contains { $0.dex == d } ? "추가" : c.guests.contains(d) ? "손님" : nil
                if let tag { found.append((state.unlocked(ci) ? "" : "🔒") + c.name + (tag.isEmpty ? "" : " (\(tag))")) }
            }
            if eggPool.contains(d) { found.append("알에서 부화") }
            if let l = Walk.legendShop.first(where: { $0.dex == d }) { found.append(l.watts > 0 ? "상점 · \(l.watts.formatted())W" : "BP 교환소 · \(l.bp)BP") }
            for e in evolutions where e.to == d { found.append(monNames[e.from] + "에서 진화") }
            if d == 292 { found.append("토중몬 → 아이스크 진화 때") }
            if found.count > 3 { let n = found.count - 2; found = Array(found.prefix(2)) + ["외 \(n)곳"] }
            let mine = evolutions.filter { $0.from == d }                                          // one line per target, its ways joined (리피아: 숲 코스 / 리프의돌)
            evos = mine.map(\.to).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.map { to in "→ " + monNames[to] + " · " + mine.filter { $0.to == to }.map(evoText).joined(separator: " / ") }
            if evos.count > 2 { let n = evos.count - 1; evos = [evos[0], "외 \(n)갈래"] }
        }
        return DexModel(num: d, status: st, stats: st > 0 ? baseStats[d] : [], found: found, evos: evos)
    }
    /// The 도감 / 상자 grid page (and through their messages: 놓아주기's); nil elsewhere.
    func gridModel(_ now: Date) -> GridModel? {
        var sc = screen; if case .say(_, let next, _) = sc { sc = next }
        let bob = Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0, per = GridModel.perPage
        func page(_ n: Int, _ at: Int) -> (first: Int, page: Int, pages: Int) { (at / per * per, at / per + 1, max(1, (n + per - 1) / per)) }
        switch sc {
        case .dex(let d, let f, false):
            let l = dexList(f), owned = Set(state.owned ?? []), seen = Set(seenList), shiny = Set(state.shinyOwned ?? []), i = l.firstIndex(of: d), p = page(l.count, i ?? 0)
            return GridModel(tabs: ["전체", "잡음", "못 잡음", "이 코스"], tab: f,
                             cells: l[p.first..<min(l.count, p.first + per)].map { .init(dex: $0, look: owned.contains($0) ? 2 : seen.contains($0) ? 1 : 0, shiny: shiny.contains($0)) },
                             first: p.first, sel: i.map { $0 - p.first }, page: p.page, pages: p.pages, empty: f == 2 ? "모두 잡았다!" : "아직 없다", bob: bob)
        case .box(let i, _, _, false):                                                              // 포켓몬: the companion and the walker's over the box
            let o = boxOrder, b = state.box, at = o.firstIndex(of: i), p = page(o.count, at ?? 0), party = [state.companion] + state.caught
            return GridModel(tabs: ["번호순", "레벨순", "V순", "최근"], tab: boxSort,
                             cells: o[p.first..<min(o.count, p.first + per)].map { .init(dex: b[$0].dex, look: 2, shiny: b[$0].shiny == true, v3: b[$0].perfectIVs >= 3, held: b[$0].item != nil) },
                             first: p.first, sel: at.map { $0 - p.first }, page: p.page, pages: p.pages, empty: "상자가 비어 있다", bob: bob,
                             party: party.map { .init(dex: $0.dex, look: 2, shiny: $0.shiny == true, v3: $0.perfectIVs >= 3, level: $0.level, held: $0.item != nil) }, partySel: i < 0 ? -1 - i : nil, items: state.items.count + state.bag.count)
        default: return nil
        }
    }
    /// A click on a grid page: 10000 + k = the list's k-th (opens its page), 4100 + t = a tab, 4200 / 4201 = a page back / on;
    /// 포켓몬: 4500 + k the row above the box (the companion, the walker's), 4510 the items; a Pokémon's page: 4400 함께 걷기, 4404 상자로 보내기 (the walker's),
    /// 4401 놓아주기 → 4402 아니오 / 4403 예 (the box's), 4409 기술 바꾸기 (anyone's).
    /// A click on a page still up under its own message (산 뒤, 연승!, W가 부족하다 …): the message ends and the click counts.
    func throughSay() {
        guard case .say(_, let next, _) = screen else { return }
        switch next { case .menu, .shop, .shopConfirm, .dex, .box, .tower, .items, .card, .course, .train, .relearn, .trade, .raid, .market, .team, .itemOn, .duel, .hold: screen = next; default: break }
    }
    func gridTap(_ code: Int) {
        guard !frozen, waiting == nil else { return }
        throughSay()
        lastInput = Date(); host?.redraw(.all)
        switch (screen, code) {
        case (.dex(let pick, let f, _), 10000...):                                                 // a cell: the first click picks it (the LCD shows it), a click on the pick opens its entry
            guard let n = dexList(f)[safe: code - 10000] else { return }
            screen = .dex(n, filter: f, detail: n == pick)
        case (.dex(let d, _, _), 4100...4103):
            let f = code - 4100, l = dexList(f); screen = .dex(l.contains(d) ? d : l.first ?? d, filter: f, detail: false)   // the pick stays if it's on the new tab
        case (.box(let pick, _, _, _), 10000...):                                                  // the same: picked first, its page on a second click
            guard let j = boxOrder[safe: code - 10000] else { return }
            screen = .box(j, act: nil, confirm: false, detail: j == pick)
        case (.box(let pick, _, _, _), 4500...4503):                                               // the row above: -1 the companion, then the walker's
            let ref = -1 - (code - 4500); guard state.mon(ref) != nil else { return }
            screen = .box(ref, act: nil, confirm: false, detail: ref == pick)
        case (.box, 4510): screen = .items(0)
        case (.box(let i, _, _, _), 4100...4103): boxSort = code - 4100; screen = .box(i, act: nil, confirm: false)
        case (.box(let i, _, _, true), 4400) where i != -1: screen = .box(i, act: 0, confirm: false, detail: true); press(1)      // = ● 함께
        case (.box(let i, _, _, true), 4404) where i < -1: screen = .box(i, act: 1, confirm: false, detail: true); press(1)       // the walker's: 상자로 보내기
        case (.box(let i, _, _, true), 4407) where i >= 0: guard let a = boxActs(i).firstIndex(of: "워커로") else { return }; screen = .box(i, act: a, confirm: false, detail: true); press(1)   // the box's: back onto the walker
        case (.box(-1, _, _, true), 4406): if let e = companionEvolution() { evolveNow(e, back: screen) }                              // the companion: a stone now
        case (.box(let i, _, _, true), 4401) where i >= 0: screen = .box(i, act: 0, confirm: true, detail: true)     // 놓아줄까? 아니오 first
        case (.box(let i, _, _, true), 4402): screen = .box(i, act: nil, confirm: false, detail: true)
        case (.box(let i, _, true, true), 4403): screen = .box(i, act: 1, confirm: true, detail: true); press(1)
        case (.box(let i, _, _, true), 4409): screen = .relearn(ref: i, slot: 0, at: nil)                                          // 기술 바꾸기
        case (.box(let i, _, _, true), 4410): screen = .hold(ref: i, sel: 0)                                                       // 3.7: 지니게 하기 · 빼기
        case (.box(let i, _, true, true), 4408) where state.box.indices.contains(i): askReleaseDupes(state.box[i].dex)            // 중복 n마리: asks (who stays) first
        case (_, 4200), (_, 4201): gridStep(code == 4200 ? -GridModel.perPage : GridModel.perPage, ends: true)
        default: return
        }
    }
    /// What the pane's page shows: the battle, 도감 (grid or entry), 상자 (grid or one Pokémon), 상점 or 메뉴 page; elsewhere the status sheet, unless it's folded.
    func paneContent(_ now: Date) -> PaneContent {
        if let l = loginModel { return PaneContent(login: l) }
        if let b = sideModel(now) { return PaneContent(battle: b) }
        if let d = dexModel() { return PaneContent(dex: d) }
        if let g = gridModel(now) { return PaneContent(grid: g) }
        if let m = monModel() { return PaneContent(mon: m) }
        if case .items(let sel) = { () -> Screen in if case .say(_, let n, _) = screen { return n }; return screen }() { return PaneContent(items: itemsModel(sel)) }
        if let s = shopModel() { return PaneContent(shop: s) }
        var sc = screen; if case .say(_, let next, _) = sc { sc = next }                       // a menu page's message (W가 부족하다 …): the list stays
        if case .team(let sel, let tab, let card) = sc { return teamPane(sel, tab, card) }
        if case .trade(let s) = sc { return tradePane(s, now) }
        if case .raid(let tab) = sc { return raidPane(tab, now) }
        if case .market(let s) = sc { return marketPane(s, now) }
        if case .itemOn(let p) = sc { return itemOnPane(p, now) }
        if case .duel(let s) = sc { return duelPane(s, now) }
        if case .hold(let ref, let sel) = sc { return holdPane(ref, sel) }
        if case .menu(let i) = sc {
            let off = cloud.map { !$0.online } ?? false, needs: Set = ["포켓 레이더", "상점", "BP 교환소", "배틀 타워", "친구", "교환", "레이드"]   // offline: what needs the server, dimmed
            let walking = (cloud?.team?.cards ?? []).filter { Walker.walkingNow($0) && !isMe($0) }.count
            let notes = ["포켓 레이더": "10W", "코스": state.here.name, "트레이너 카드": "오늘 \(state.today.formatted())걸음", "포켓몬": "워커 \(state.caught.count) · 상자 \(state.box.count.formatted())", "도감": "\(dexCount) / 493", "상점": "W로 사기", "BP 교환소": "\((state.bp ?? 0).formatted())BP로 교환", "배틀 타워": "최고 \(state.towerBest ?? 0)연승", "친구": friendRequestsIn > 0 ? "친구 신청 \(friendRequestsIn)건" : walking > 0 ? "지금 걷는 중 \(walking)명" : "친구 · 이번 주 순위", "교환": marketNote,
                         "레이드": raidNote]
            return PaneContent(menu: MenuModel(rows: menuItems.map { off && needs.contains($0) ? .init(name: $0, note: "연결되면 할 수 있어요", off: true) : .init(name: $0, note: notes[$0] ?? "") }, sel: i))
        }
        switch sc {                                                                               // the rest of the walker's pages: what you press is here, the LCD shows it
        case .radar(let b, let c, let since, let chain):
            let u = Date().timeIntervalSince(since)
            return PaneContent(radar: RadarModel(live: (1.5...(1.5 + radarWindow(chain))).contains(u) ? b : nil, cursor: c, chain: chain, season: state.season))
        case .card(let p): return PaneContent(card: CardModel(page: p))
        case .learn(let sel):
            var st = state
            guard let (ref, id) = st.nextToLearn(), let m = state.mon(ref), let new = moveTable[id] else { break }
            func mv(_ x: MoveInfo) -> LearnModel.Move { .init(name: x.name, type: x.type, power: x.power, pp: x.pp) }
            return PaneContent(learn: LearnModel(who: monNames[m.dex], new: mv(new), known: m.moves.compactMap { moveTable[$0] }.map(mv), sel: sel))
        case .relearn(let r, let s, let at):
            guard let m = state.mon(r) else { break }
            func mv(_ id: Int) -> LearnModel.Move { let x = moveTable[id]!; return .init(name: x.name, type: x.type, power: x.power, pp: x.pp) }
            let pick = at.map { at -> RelearnModel.Pick in
                let all = m.relearnable, per = RelearnModel.perPage, sel = all.firstIndex(of: at) ?? 0, first = sel / per * per
                return .init(sel: sel, count: all.count, first: first, rows: all[first..<min(all.count, first + per)].map { .init(move: mv($0), level: m.learnLevel($0), slot: m.moves.firstIndex(of: $0)) })
            }
            return PaneContent(relearn: RelearnModel(who: (m.shiny == true ? "★ " : "") + monNames[m.dex], slots: m.moves.map(mv), slot: s, pick: pick))
        case .course(let i):
            let per = CourseModel.perPage, first = i / per * per
            let rows = (first..<min(courses.count, first + per)).map { k -> CourseModel.Row in
                let c = courses[k], open = state.unlocked(k), kinds = courseSpecies(k), owned = Set(state.owned ?? [])
                return .init(name: c.name, note: open ? "잡음 \(kinds.filter(owned.contains).count)/\(kinds.count)" : c.dex > 0 ? "도감 \(c.dex)종" : "누적 \(c.watts.formatted())W", open: open, here: k == state.course)
            }
            let go = state.unlocked(i) && i != state.course ? josa(courses[i].name, "으로", "로") + " 가기" : nil
            let lv = courses[i].all.map(\.level), about = "Lv.\(lv.min() ?? 1)–\(lv.max() ?? 1) · " + courses[i].types.map { typeKo[$0] ?? $0 }.joined(separator: " · ")
            return PaneContent(course: CourseModel(rows: rows, sel: i, first: first, count: courses.count, opened: courses.indices.filter(state.unlocked).count, go: go, about: about))
        case .train(let k):
            let c = state.mon(trainRef) ?? state.companion, iv = c.effectiveIVs, raw = c.ivs ?? Array(repeating: 15, count: 6), names = ["HP", "공격", "방어", "특공", "특방", "스피드"]
            let ready = c.level >= Walk.hyperLevel, caps = state.count("은색병뚜껑")
            let go = ready && iv[k] < 31 && caps > 0 ? "\(names[k]) \(iv[k]) → 31 특훈" : nil
            let note = !ready ? "Lv.\(Walk.hyperLevel)부터 특훈할 수 있어요" : caps == 0 ? "은색병뚜껑이 없어요" : iv[k] >= 31 ? "이미 최고예요" : ""
            return PaneContent(train: TrainModel(who: monNames[c.dex] + " Lv.\(c.level)", caps: caps, rows: (0..<6).map { .init(name: names[$0], iv: raw[$0], hyper: (c.hyper ?? []).contains($0)) },
                                                 sel: k, go: go, note: note, v: c.perfectIVs))
        case .tower(let p):
            let party = state.party(), per = TowerModel.perPage
            let pick = p.map { p -> TowerModel.Pick in
                let all = state.towerCandidates, sel = all.firstIndex(of: p.at) ?? 0, first = sel / per * per
                return .init(slot: p.slot, sel: sel, count: all.count, first: first, rows: all[first..<min(all.count, first + per)].map { r in
                    let m = state.mon(r)!; return .init(name: monNames[m.dex], level: m.level, slot: party.firstIndex { $0.ref == r }, shiny: m.shiny == true) })
            }
            return PaneContent(tower: TowerModel(run: towerRun, streak: state.towerStreak ?? 0, best: state.towerBest ?? 0, bp: state.bp ?? 0, fee: Walk.towerFee,
                                                 party: party.map { .init(dex: $0.mon.dex, name: monNames[$0.mon.dex], level: $0.mon.level, shiny: $0.mon.shiny == true) }, custom: state.towerPick != nil, pick: pick))
        default: break
        }
        return statusOpen ? PaneContent(status: statusModel()) : PaneContent()
    }
    /// A click on a walker page that isn't a grid: 5000 + k a radar bush, 5200 + p a card page, 5300 + k a move to forget (4 = don't),
    /// 5400 / 5401 the tower's 도전 / 나가기, 5410 + i its party row i (who goes there instead), 5420 추천으로, then its picker: 5430 + k a row of the page,
    /// 5440 / 5441 the page before / after (round); 기술 바꾸기: 5500 + k a slot, then 5530 + k a move of the page, 5540 / 5541 its pages. One click does it, as ● would.
    func pageTap(_ code: Int) {
        if code == 5950 { press(1); return }                                                     // the server's lock: its button (ID 입력 / 여기서 계속), as ●
        guard !frozen, waiting == nil else { return }
        throughSay(); lastInput = Date(); host?.redraw(.all)
        switch (screen, code) {
        case (.radar(let b, _, let since, let chain), 5000...5003): screen = .radar(bush: b, cursor: code - 5000, since: since, chain: chain); press(1)
        case (.card, 5200...5202): screen = .card(code - 5200)
        case (.team(let sel, _, _), 6000...6004): screen = .team(sel: code - 6000 == 0 ? sel : 0, tab: code - 6000, card: false)   // a tab (a rank tab from its top; 4 = 신청)
        case (.team(let sel, let tab, true), 6031): if let c = teamRows(tab)[safe: sel]?.card, !isMe(c) { unfriend(c.name) }   // 친구 끊기
        case (.team(let sel, 4, false), 6200..<6216):                                             // 신청: 수락 (or 거두기, mine) · 거절
            if let r = friendReqRows[safe: sel / FriendReqModel.perPage * FriendReqModel.perPage + (code - 6200) % 10] { friendReq(r, accept: code < 6210, Date()) }
        case (.team(let sel, 4, false), 6230...6231):
            let per = FriendReqModel.perPage, n = friendReqRows.count, pages = max(1, (n + per - 1) / per)
            screen = .team(sel: min(max(0, n - 1), ((sel / per + (code == 6230 ? pages - 1 : 1)) % pages) * per), tab: 4, card: false)
        case (.team(_, 4, false), 6240): askFriend()
        case (.market, 8000...8199): marketTap(code, Date())
        case (.itemOn, 8300...8399): itemOnTap(code, Date())
        case (.duel, 6300...6301): duelTap(code, Date())
        case (.hold, 5980...5999): holdTap(code, Date())
        case (.team(let sel, let tab, true), 6032): if let c = teamRows(tab)[safe: sel]?.card, !isMe(c), Walker.walkingNow(c) { challenge(c.name) }   // 대전 신청
        case (.trade, 6000...6199): tradeTap(code, Date())
        case (.raid, 7000...7010): raidTap(code, Date())
        case (.team(let sel, let tab, _), 6010...6015):                                          // a row: the first click picks it, a click on the pick opens its card
            let at = sel / TeamModel.perPage * TeamModel.perPage + code - 6010
            guard at < teamRows(tab).count else { return }
            screen = .team(sel: at, tab: tab, card: at == sel)
        case (.team(let sel, let tab, _), 6020), (.team(let sel, let tab, _), 6021):             // ◀ ▶ a page, round
            let per = TeamModel.perPage, n = teamRows(tab).count, pages = max(1, (n + per - 1) / per)
            screen = .team(sel: min(n - 1, ((sel / per + (code == 6020 ? pages - 1 : 1)) % pages) * per), tab: tab, card: false)
        case (.team(let sel, let tab, true), 6030): if let c = teamRows(tab)[safe: sel]?.card { greet(c.name, back: .team(sel: sel, tab: tab, card: true)) }
        case (.learn, 5300...5304): screen = .learn(sel: code - 5300); press(1)
        case (.items, 5600..<5700): screen = .items(code - 5600)
        case (.items, 5700): press(1)
        case (.items, 5711): sellAll(back: .items(0))                                                // 팔 수 있는 것 전부 팔기
        case (.course(let i), 5800..<5805): screen = .course(i / CourseModel.perPage * CourseModel.perPage + code - 5800)   // a click picks one (its picture on the LCD); 가기 walks it
        case (.course(let i), 5810...5811):
            let per = CourseModel.perPage, pages = (courses.count + per - 1) / per
            screen = .course(min(courses.count - 1, (i / per + (code == 5810 ? pages - 1 : 1)) % pages * per))
        case (.course, 5820): press(1)
        case (.train, 5900..<5906): screen = .train(code - 5900)
        case (.train, 5910): press(1)
        case (.tower(nil), 5400): press(1)
        case (.tower(nil), 5401): press(3)
        case (.tower(nil), 5410...5412):
            if let r = state.party()[safe: code - 5410]?.ref { screen = .tower(pick: (code - 5410, r)) }
        case (.tower(nil), 5420): act(.towerReset, back: .tower(pick: nil)) { _, _ in .tower(pick: nil) }   // 추천으로
        case (.tower(let p?), 5430..<5445):                                                     // a row of the page in view, or its ◀ ▶ (round)
            let per = TowerModel.perPage, all = state.towerCandidates, page = (all.firstIndex(of: p.at) ?? 0) / per, pages = (all.count + per - 1) / per
            if code >= 5440 { screen = .tower(pick: (p.slot, all[min(all.count - 1, (page + (code == 5440 ? pages - 1 : 1)) % pages * per)])) }
            else if let r = all[safe: page * per + code - 5430] { screen = .tower(pick: (p.slot, r)); press(1) }
        case (.relearn(let r, _, nil), 5500...5503): screen = .relearn(ref: r, slot: code - 5500, at: nil); press(1)   // a slot: what goes there
        case (.relearn(let r, let s, let at?), 5530..<5545):                                    // a move of the page in view (into the slot), or its ◀ ▶ (round)
            guard let all = state.mon(r)?.relearnable else { return }
            let per = RelearnModel.perPage, page = (all.firstIndex(of: at) ?? 0) / per, pages = (all.count + per - 1) / per
            if code >= 5540 { screen = .relearn(ref: r, slot: s, at: all[min(all.count - 1, (page + (code == 5540 ? pages - 1 : 1)) % pages * per)]) }
            else if let id = all[safe: page * per + code - 5530] { screen = .relearn(ref: r, slot: s, at: id); press(1) }
        default: return
        }
    }
    /// 포켓몬's one-Pokémon page: its nature and ability with what they do, IVs (as battles use them) and EVs, what it can do from where it is; nil elsewhere.
    func monModel() -> MonModel? {
        var sc = screen; if case .say(_, let next, _) = sc { sc = next }
        guard case .box(let i, let act, let confirm, true) = sc, let m = state.mon(i) else { return nil }
        var p = monPage(m, act: act, confirm: confirm); p.place = i == -1 ? 0 : i < -1 ? 1 : 2
        p.fetch = i >= 0 && state.caught.count < 3; p.dupes = i >= 0 ? state.duplicates(of: state.box[i].dex).count : 0; p.sel = act.flatMap { $0 < boxActs(i).count - 1 ? $0 : nil }   // the LCD's pick = a button (닫기 has none)
        let mine = evolutions.filter { $0.from == m.dex }, targets = mine.map(\.to).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
        p.evos = targets.map { to in "→ " + monNames[to] + " · " + mine.filter { $0.to == to }.map { e in evoText(e).replacingOccurrences(of: " 소지", with: "") + (e.item.map { state.count($0) > 0 ? " (있음)" : " (없음)" } ?? "") }.joined(separator: " / ") }
        if p.evos.count > 2 { p.evos = [p.evos[0], "외 \(p.evos.count - 1)갈래"] }
        if p.evos.isEmpty { p.evos = ["더 진화하지 않아요"] }
        else if mine.contains(where: { $0.way == .trade }) { p.evos.append("교환하면 받는 쪽에서 진화해요") }
        else if i != -1, mine.contains(where: { $0.way == .item }) { p.evos.append("도구 진화는 동료일 때 (함께 걷기 후)") }
        if i == -1, let e = companionEvolution() { p.evoAction = e.item! + " 쓰기 → " + monNames[e.to] }
        p.held = m.item; p.heldNote = m.item.flatMap(Held.summary)
        return p
    }
    /// The ● menu on a Pokémon's page (the LCD's row; the pane's buttons are the same, less 닫기): what it can do from where it is.
    func boxActs(_ i: Int) -> [String] { i < -1 ? ["함께", "상자로", "닫기"] : i >= 0 ? ["함께"] + (state.caught.count < 3 ? ["워커로"] : []) + ["놓아주기", "닫기"] : [] }
    /// What would evolve the companion right now from its page: a stone in the bag (a trade evolution: a real trade, 12 §3).
    func companionEvolution() -> Evo? { state.stoneEvolutions(Date()).first }
    /// 도구: every kind carried, the pick's use and a line about it.
    func itemsModel(_ sel: Int) -> ItemsModel {
        let names = state.inventory, s = min(sel, max(0, names.count - 1)), me = monNames[state.companion.dex]
        let rows = names.map { n in ItemsModel.Row(name: n, count: state.count(n), onWalker: state.items.filter { $0 == n }.count) }
        guard let n = names[safe: s] else { return ItemsModel(rows: [], sel: 0, walker: 0, bag: 0, action: nil, hint: "") }
        let (action, note) = itemUse(n)
        let sell = names.reduce(0) { sum, i in if case .sell(let p) = ItemKind.of(i) { return sum + p * state.count(i) }; return sum }
        return ItemsModel(rows: rows, sel: s, walker: state.items.count, bag: state.bag.count, action: action, hint: ItemKind.of(n).summary + (note.isEmpty ? "" : " · " + note).replacingOccurrences(of: "{동료}", with: me),
                          sellAll: sell > 0 ? sell : nil)
    }
    /// What 도구's button does for item n (nil = nothing here), and a note ({동료} = the companion's name).
    func itemUse(_ n: String) -> (String?, String) {
        let c = state.companion, kind = ItemKind.of(n)
        if Walker.targeted(kind) {                                                                 // 3.6 (docs/plans/13): any of ours — who gets it is asked next
            let who = itemRefs.filter { itemNot(n, $0) == nil }.count
            if who == 0 { return (nil, itemNot(n, -1).map { "동료: " + $0 } ?? "쓸 수 있는 포켓몬이 없어요") }
            if case .held = kind { return ("지니게 할 포켓몬 고르기", "") }                          // (its line is the summary already)
            if case .evolution = kind, let e = state.stoneEvolutions(Date()).first(where: { $0.item == n }) { return ("쓸 포켓몬 고르기", "동료는 \(monNames[e.to])(으)로 진화") }
            return ("쓸 포켓몬 고르기", "쓸 수 있는 포켓몬 \(who)마리")
        }
        switch kind {
        case .candy: return c.level < 100 ? ("{동료}에게 먹이기".replacingOccurrences(of: "{동료}", with: monNames[c.dex]), "지금 Lv.\(c.level)") : (nil, "이미 Lv.100")
        case .vitamin(let k, _): return ("{동료}에게 먹이기".replacingOccurrences(of: "{동료}", with: monNames[c.dex]), "지금 \(c.evs?[k] ?? 0) · 합 \((c.evs ?? []).reduce(0, +))/510")
        case .evReset: return ("{동료}에게 먹이기".replacingOccurrences(of: "{동료}", with: monNames[c.dex]), "지금 합 \((c.evs ?? []).reduce(0, +))")
        case .berry: return ("{동료}에게 먹이기".replacingOccurrences(of: "{동료}", with: monNames[c.dex]), "")
        case .sell(let p): return ("전부 팔기 +\((p * state.count(n)).formatted())W", "")
        case .evolution:
            if let e = state.stoneEvolutions(Date()).first(where: { $0.item == n }) { return ("\(monNames[e.to])(으)로 진화", "{동료}에게 써요") }
            let uses = evolutions.filter { $0.item == n }.prefix(2).map { monNames[$0.from] + "→" + monNames[$0.to] + ($0.way == .trade ? " (교환)" : "") }
            return (nil, uses.joined(separator: ", "))
        case .bottleCap(let gold):
            let iv = c.effectiveIVs, open = iv.contains { $0 < 31 }
            if c.level < Walk.hyperLevel { return (nil, "Lv.\(Walk.hyperLevel)부터 특훈할 수 있어요 (지금 Lv.\(c.level))") }
            if !open { return (nil, "이미 모든 능력이 최고예요") }
            return gold ? ("\(monNames[c.dex]) 특훈 · 모두 31로", "지금 \(c.perfectIVs)V") : ("\(monNames[c.dex]) 특훈할 능력 고르기", "지금 \(c.perfectIVs)V")
        case .mint(let k): return (c.mint ?? c.nature ?? 0) == k ? (nil, "이미 그 성격 효과예요") : ("{동료}에게 쓰기".replacingOccurrences(of: "{동료}", with: monNames[c.dex]), "지금 " + natures[c.mint ?? c.nature ?? 0].name)   // (minimal: the per-Pokémon target is the Mac's, docs/plans/13)
        case .revive: return (nil, "배틀 중 기절한 포켓몬에게")
        case .held: return (nil, "포켓몬에게 지니게 해요")                                          // (held ones are targeted: the case above)
        case .heal, .battle: return (nil, "배틀에서 도구로")
        }
    }
    /// A Pokémon in full, for its page.
    func monPage(_ m: Mon, act: Int? = nil, confirm: Bool = false) -> MonModel {
        let n = natures[m.mint ?? m.nature ?? 0], neutral = n.up == n.down, name = ["HP", "공격", "방어", "특공", "특방", "스피드"]   // the chips' and hexagons' names: every note fits its line; a mint's nature drives them (3.6)
        let note = neutral ? "능력치에 영향을 주지 않는 성격" : josa(name[n.up], "이", "가") + " 10% 높고 " + josa(name[n.down], "이", "가") + " 10% 낮은 성격"
        var p = MonModel(nature: m.natureName + (m.mint.map { $0 != (m.nature ?? 0) ? " (민트: " + natures[$0].name + ")" : "" } ?? ""), natureNote: note, ability: m.abilityName, abilityNote: abilityDescs[m.abilityID] ?? "", up: neutral ? nil : n.up, down: neutral ? nil : n.down,
                        ivs: m.effectiveIVs, evs: m.evs ?? Array(repeating: 0, count: 6), hyper: m.hyper ?? [], v: m.perfectIVs, evTotal: (m.evs ?? []).reduce(0, +), confirm: confirm && act != nil, sel: act.flatMap { $0 < 2 ? $0 : nil })
        p.moves = m.moves.compactMap { moveTable[$0]?.name }; return p
    }
    /// 홈 (and the other screens): where, the companion, today, then egg / tower / totals / dex.
    func statusModel() -> StatusModel {
        var m = state.companion
        if case .evolve(let from, _, let since) = screen, from.uid == m.uid, Date().timeIntervalSince(since) < 4.4 { m = from }   // no spoiler before the LCD's reveal (the companion's own)
        let t = expTable[growthRate[m.dex]], lo = t[m.level], hi = t[min(100, m.level + 1)]
        let exp: CGFloat = m.level >= 100 || hi <= lo ? 1 : CGFloat(m.points - lo) / CGFloat(hi - lo)
        return StatusModel(dex: m.dex, name: (m.shiny == true ? "★ " : "") + monNames[m.dex], sex: sexMark(m).trimmingCharacters(in: .whitespaces), level: "Lv.\(m.level)",
                           toNext: m.level >= 100 ? "최고 레벨" : "\((hi - m.points).formatted()) EXP", nature: "\(m.natureName) · \(m.abilityName)", female: m.female, v: m.perfectIVs, exp: exp,
                           numbers: [.init(key: "오늘 걸음", value: state.today.formatted()), .init(key: "와트", value: "\(state.watts.formatted())W"), .init(key: "누적 걸음", value: state.total.formatted())],
                           rows: [.init(key: "알", value: state.egg.map { $0.left > 0 ? "앞으로 \($0.left.formatted())걸음" : "곧 태어난다!" } ?? "없음"),
                                  .init(key: "배틀 타워", value: "최고 \(state.towerBest ?? 0)연승 · \((state.bp ?? 0).formatted())BP"),
                                  .init(key: "도감", value: "잡음 \(dexCount) · 봤음 \(seenList.count)"),
                                  .init(key: "레이드", value: raidStatus),
                                  .init(key: "친구", value: friendStatus)])
    }
    /// A click on a 메뉴 tile: open it (as ● on it would).
    func menuTap(_ i: Int) {
        guard !frozen, waiting == nil else { return }
        throughSay()
        guard case .menu = screen, menuItems.indices.contains(i) else { return }
        lastInput = Date(); host?.redraw(.all)
        screen = .menu(i); press(1)
    }
    /// What the side panel shows on a shop screen; nil elsewhere.
    func shopModel() -> ShopModel? {
        var sc = screen, said: String? = nil
        if case .say(let lines, let next, _) = sc, case .shop = next { said = lines.joined(separator: " "); sc = next }   // the shop's own messages keep the panel up
        let bp: Bool, sel: Int, qty: Int?, ask: Bool?
        switch sc {
        case .shop(let b, let s, let q): bp = b; sel = s; qty = q; ask = nil
        case .shopConfirm(let b, let s, let y): bp = b; sel = s; qty = nil; ask = y
        default: return nil
        }
        let ws = wares(bp), unit = bp ? "BP" : "W", w = ws[safe: sel], tab = shopTab(bp, sel), ids = shopRows(bp, tab)
        let rows = ids.map { ws[$0] }.map { w in ShopModel.Row(name: state.wareName(w), note: state.wareNote(w), price: w.once && state.owned(w) > 0 ? "보유" : "\(w.price.formatted())\(unit)",
                                                 owned: state.owned(w), can: state.canBuy(w, bp: bp) > 0, once: w.once) }
        let cost = (w?.price ?? 0) * (qty ?? 0)
        let hint = said ?? w.map { w in
            w.once && state.owned(w) > 0 ? "이미 가지고 있어요" : state.canBuy(w, bp: bp) == 0 ? "\(unit)가 부족해요 · \(w.price.formatted())\(unit) 필요" : "클릭하거나 ●를 누르면 몇 개 살지 정해요"
        } ?? ""
        let spend = ask != nil ? w?.price ?? 0 : cost
        return ShopModel(title: bp ? "BP 교환소" : "상점", rows: rows, sel: ids.firstIndex(of: sel) ?? 0, qty: qty, most: w.map { max(1, state.canBuy($0, bp: bp)) } ?? 1,
                         total: "\(spend.formatted())\(unit)", hint: hint, ask: ask, tabs: shopTabs(bp), tab: tab, ids: ids)
    }
}

// MARK: - a Pokémon in words (the status sheet, the menu)
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
