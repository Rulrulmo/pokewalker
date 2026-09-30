import AppKit
// Drawing each screen into the frame buffer; the Pokédex panel's model.

extension WalkerView {
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
        case .home:
            let f = now.timeIntervalSince(lastStep) < 3 ? half : Int(t) % 2        // steps coming in => walks twice as fast
            fb.mon(me, f, 32, 0)
            if let e = emote, now < e.until, Int(t * 3) % 3 != 0 { let y = max(0, 48 - (80 - spriteTop(me.dex)) / 2 - 9); fb.draw(bubble, 38, y, ballPal); fb.draw(emotes[e.kind], 41, y + 2, redPal) }   // by its head
            fb.course(state.here.art, 1, 22, weather: state.weather ?? .sunny, t: t, hour: state.hour, season: state.season)
            fb.text("\(state.watts)W", 1, 1, 2, small: true)
            for i in 0..<state.caught.count { fb.draw(ball, 1 + 8 * i, 13, ballPal) }
            for i in 0..<state.items.count { fb.draw(gem, 26 + 4 * i, 15, gemPal) }
            fb.fill(0, 49, 96, 1, 2)
            fb.draw(foot, 2, 54)
            fb.text("Lv.\(me.level)", 11, 53, 2, small: true)
            if let e = state.egg { fb.draw(eggArt, 42 + (e.left < 500 && Int(t * 4) % 2 == 0 ? 1 : 0), 52, eggPal) }   // wobbles when it's close
            fb.text("\(state.today)", 94, 52, 3, right: true)
        case .menu(let i):
            fb.text("◀", 1, 26, 2); fb.text("▶", 95, 26, 2, right: true)
            fb.text(menuItems[i], 0, 20, center: true)
            let sub = [" 10W", " 3W", "상자로 보내기", "", "", "\(state.box.count)마리", "\(dexCount) / 493", "W로 사기", "\(state.bp ?? 0)BP로 교환", "\(state.bp ?? 0)BP"][i]
            if !sub.isEmpty { fb.text(sub.trimmingCharacters(in: .whitespaces), 0, 34, 2, center: true) }
            fb.text("\(state.watts)W", 94, 1, 2, right: true, small: true)
            let x0 = 48 - (5 * menuItems.count - 2) / 2                                                 // page dots, centred
            for k in 0..<menuItems.count { fb.fill(x0 + 5 * k, 58, 3, 3, k == i ? 3 : 1) }
        case .radar(let b, let c, let since, let chain):
            let u = now.timeIntervalSince(since), live = (1.5...(1.5 + radarWindow(chain))).contains(u)
            if chain > 0, u < 1.5 { fb.text("연쇄 \(chain)!", 0, 13, 3, center: true); if let n = chainNote { fb.text(n, 0, 25, 2, center: true, small: true) } }   // between the bush rows
            for k in 0..<4 {
                let x = 14 + (k % 2) * 56, y = 8 + (k / 2) * 28, shake = live && k == b ? (half == 0 ? -1 : 1) : 0
                fb.draw(bush, x + shake, y, greens)
                if live && k == b && Int(t * 6) % 2 == 0 { fb.draw(bang, x + 15, y - 6, redPal) }
                if k == c { fb.text("▶", x - 2, y, 3, right: true) }
            }
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
                let m = moveTable[id]!, x = (k % 2) * 48, y = 39 + (k / 2) * 12, e = m.isStatus ? 1 : b.typeEff(b.moveType(.me, m).type, .it, by: .me)
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
        case .beats:
            let s = beatState(now)!
            stage(&fb, s.hp, now, pose(s.beat, s.u, s.hp), pending: s.pending, beat: (s.beat, s.u))
            fb.text(message(s.beat, s.u, s.names), 2, 52)
            if case .hit(_, _, _, _, true) = s.beat, s.u < 0.15 { fb.invert(0, 0, 96, 64) }           // critical: the whole screen flashes
            if s.beat == .appear, legendDex.contains(s.from.wild.dex), s.u < 0.5, Int(s.u * 10) % 2 == 0 { fb.invert(0, 0, 96, 64) }   // a legend: two flashes first
        case .tower:
            fb.text("배틀 타워", 2, 0); fb.text("\(state.bp ?? 0)BP", 94, 1, 2, right: true, small: true); fb.fill(0, 12, 96, 1, 2)
            fb.text(towerRun ? "\(state.towerStreak ?? 0)연승 중 · 최고 \(state.towerBest ?? 0)" : "최고 \(state.towerBest ?? 0)연승", 2, 14, 2, small: true)
            for (k, p) in state.party().enumerated() { fb.text(monNames[p.mon.dex] + " Lv.\(p.mon.level)", 2, 24 + 9 * k, 3, small: true) }
            fb.fill(0, 51, 96, 1, 2)
            fb.text(towerRun ? "● 다음 상대  ↩ 나가기" : "● 도전 \(Walk.towerFee)W", 0, 53, 3, center: true, small: true)
        case .dowse(let c, _, let tries, let hint):
            fb.text(hint ?? "어디에 있을까?", 0, 2, center: true)
            for k in 0..<6 { let x = 2 + 16 * k; fb.draw(bush, x, 28, greens); if k == c { fb.text("▼", x + 6, 16, 3, center: false) } }
            for k in 0..<tries { fb.draw(pip.full, 88 - 5 * k, 56) }
        case .card(let p):
            header(["트레이너 카드", "최근 7일", "알"][p])
            if p == 2 {
                if let e = state.egg {
                    fb.draw(eggArt, 40, 18, eggPal, scale: 2)
                    fb.text(e.left > 0 ? "앞으로 \(e.left)걸음" : "곧 태어난다!", 0, 52, 3, center: true)
                } else { fb.text("갖고 있지 않다", 0, 30, 2, center: true) }
            } else if p == 0 {
                fb.text(state.here.name, 2, 14)
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
        case .bag(let p):                                                                            // 0 = the companion, then the walker's Pokémon, then the items
            let m = p == 0 ? state.companion : p < bagPages - 1 ? state.caught[safe: p - 1] : nil
            header(m.map { ($0.shiny == true ? "★" : "") + monNames[$0.dex] + " Lv.\($0.level)" } ?? "도구")
            if let m {
                fb.mon(m, half, 0, 2)
                fb.text("\(p + 1)/\(bagPages - 1)", 94, 15, 2, right: true, small: true); vLabel(m, 24)
                if p == 0 { fb.text("함께", 94, 42, 2, right: true, small: true); fb.text("걷는 중", 94, 51, 2, right: true, small: true) }
                else { fb.text("● 함께", 94, 42, 2, right: true, small: true); fb.text("걷기", 94, 51, 2, right: true, small: true) }
            } else {
                if state.items.isEmpty { fb.text("없음", 0, 30, 2, center: true) }
                for (k, it) in state.items.enumerated() { fb.draw(gem, 4, 18 + 12 * k, gemPal); fb.text(it, 12, 14 + 12 * k) }
            }
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
            if owned { fb.mon(Mon(dex: d, level: 1, female: false, shiny: shinyNow ? true : nil), half, 0, 2) } else { fb.mon(m, 0, 0, 2, tint: (3, rgb(70, 74, 84))) }   // only seen: a shadow
            if shinyNow { fb.text("★이로치", 94, 32, 3, right: true, small: true) }
            fb.text(monTypes[d].map { typeKo[$0] ?? $0 }.joined(separator: "·"), 94, 16, 2, right: true, small: true)
            fb.text(owned ? "잡음" : "봤음", 94, 42, 2, right: true, small: true)
            fb.text("\((list.firstIndex(of: d) ?? 0) + 1)/\(list.count)", 94, 52, 1, right: true, small: true)
        case .box(let i, let act, let confirm, let detail):
            guard let m = state.box[safe: i] else { header("상자"); fb.text("상자가 비어 있다", 0, 30, 2, center: true); break }
            header((m.shiny == true ? "★" : "") + monNames[m.dex] + " Lv.\(m.level)")
            fb.mon(m, half, 0, 2)
            fb.text("\((boxOrder.firstIndex(of: i) ?? 0) + 1)/\(state.box.count)", 94, 15, 2, right: true, small: true)
            if genderRate[m.dex] >= 0 { fb.text(m.female ? "암컷" : "수컷", 94, 26, 2, right: true, small: true) }; vLabel(m, 36)   // genderless: nothing (the games show no symbol)
            if let a = act {
                fb.fill(0, 50, 96, 14, 0); fb.fill(0, 50, 96, 1, 2)
                let opts = confirm ? ["놓아줄까?", "아니오", "예"] : ["함께", "놓아주기", "닫기"]
                var x = 1
                for (k, o) in opts.enumerated() {
                    let w = fb.text(o, x + 1, 52, 3, small: true) + 2
                    if confirm ? k - 1 == a : k == a { fb.invert(x, 52, w, 11) }
                    x += w + 1
                }
            } else { fb.text(detail ? "● 메뉴" : "● 자세히", 94, 52, 2, right: true, small: true) }   // the grid's ● opens its page; the page's opens 함께 / 놓아주기
        case .hatch(let m, let since):
            let u = now.timeIntervalSince(since)
            if u < 2.6 {                                                                                    // the egg rocks, harder and harder, then cracks
                let k = u / 2.6, dx = Int(sin(u * (8 + 30 * k)) * (1 + 3 * k))
                fb.draw(u > 2.0 ? eggCrack : eggArt, 38 + dx, 12, eggPal, scale: 3)
                fb.text("어라...?", 0, 52, 3, center: true)
            } else if u < 2.9 { for y in 0..<50 { for x in 0..<96 { fb.set(x, y, 0, rgb(255, 255, 255)) } } }
            else {
                fb.mon(m, half, 16, 1)
                if m.shiny == true { for (k, (sx, sy)) in [(8, 6), (70, 10), (30, 2), (78, 34)].enumerated() where (Int(u * 4) + k) % 3 == 0 { fb.draw(spark, sx, sy, sparkPal) } }
                fb.text(josa(monNames[m.dex], "이", "가") + " 태어났다!", 2, 52)
            }
            fb.fill(0, 50, 96, 1, 2)
        case .evolve(let from, let to, let since):
            let u = now.timeIntervalSince(since)
            for y in 0..<50 { for x in 0..<96 { fb.set(x, y, 3, rgb(22, 26, 44)) } }                         // lights down
            if u < 1.2 { fb.mon(from, half, 16, 1) }
            else if u < 4.0 {                                                                                // flicker between the two shapes, faster and faster
                let k = (u - 1.2) / 2.8, phase = Int(pow(k, 2) * 40) % 2
                fb.mon(phase == 0 ? from : to, 0, 16, 1, tint: (0, rgb(255, 255, 255)))
            } else if u < 4.4 { fb.fill(0, 0, 96, 50, 0); for y in 0..<50 { for x in 0..<96 { fb.set(x, y, 0, rgb(255, 255, 255)) } } }
            else { fb.mon(to, half, 16, 1); for (k, (sx, sy)) in [(8, 6), (70, 10), (30, 2), (78, 34), (4, 30)].enumerated() where (Int(u * 4) + k) % 3 == 0 { fb.draw(spark, sx, sy, sparkPal) } }
            fb.fill(0, 50, 96, 1, 2)
            fb.text(u < 4.4 ? "어라...? " + josa(monNames[from.dex], "이", "가") + "...!" : josa(monNames[to.dex], "으로", "로") + " 진화했다!", 2, 52)
        case .say(let lines, let next, _):
            switch next {                                                                             // a fight's own message is on the pane: the LCD keeps the stage
            case .battle(let b, _) where sideOn, .moves(let b, _) where sideOn, .party(let b, _) where sideOn, .bagBattle(let b, _) where sideOn, .forfeit(let b, _) where sideOn:
                stage(&fb, b, now, .idle, hud: false)
            default: for (k, l) in lines.enumerated() { fb.text(l, 0, 32 - lines.count * 7 + 14 * k, center: true) }
            }
        }
        return fb
    }
    var bagPages: Int { state.caught.count + 2 }                                                  // the companion, the walker's Pokémon, the items
    func evoText(_ e: Evo) -> String {
        let when = e.time.map { $0 == "day" ? "낮" : "밤" }, sex = e.female.map { $0 ? "♀" : "♂" }
        let place = e.place.map { ["cave": "동굴 코스", "forest": "숲 코스"][$0] ?? "얼음 산길" }
        switch e.way {
        case .level: let parts = [e.level > 0 ? "Lv.\(e.level)" : nil, when, sex, place, e.item.map { $0 + " 소지" }, e.party.map { monNames[$0] + " 보유" }].compactMap { $0 }; return parts.isEmpty ? "레벨 업" : parts.joined(separator: " · ")
        case .friend: return (["친밀도(함께 1만 걸음)"] + [when].compactMap { $0 }).joined(separator: " · ")
        case .item: return e.item! + " 사용" + (sex.map { " · " + $0 } ?? "")
        case .trade: return "커넥트(통신)" + (e.item.map { " · " + $0 + " 소지" } ?? "")
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
        case .box(let i, _, _, false):
            let o = boxOrder, b = state.box, at = o.firstIndex(of: i), p = page(o.count, at ?? 0)
            return GridModel(tabs: ["번호순", "레벨순", "V순", "최근"], tab: boxSort,
                             cells: o[p.first..<min(o.count, p.first + per)].map { .init(dex: b[$0].dex, look: 2, shiny: b[$0].shiny == true, v3: b[$0].perfectIVs >= 3) },
                             first: p.first, sel: at.map { $0 - p.first }, page: p.page, pages: p.pages, empty: "상자가 비어 있다", bob: bob)
        default: return nil
        }
    }
    /// A click on a grid page: 10000 + k = the list's k-th (opens its page), 4100 + t = a tab, 4200 / 4201 = a page back / on;
    /// a box Pokémon's page: 4400 함께 걷기, 4401 놓아주기 → 4402 아니오 / 4403 예.
    /// A click on a page still up under its own message (산 뒤, 연승!, W가 부족하다 …): the message ends and the click counts.
    func throughSay() {
        guard case .say(_, let next, _) = screen else { return }
        switch next { case .menu, .shop, .shopConfirm, .dex, .box, .tower, .bag, .card: screen = next; default: break }
    }
    func gridTap(_ code: Int) {
        throughSay()
        lastInput = Date(); shown = nil; needsDisplay = true
        switch (screen, code) {
        case (.dex(_, let f, _), 10000...):
            guard let n = dexList(f)[safe: code - 10000] else { return }
            screen = .dex(n, filter: f, detail: true)
        case (.dex(let d, _, _), 4100...4103):
            let f = code - 4100, l = dexList(f); screen = .dex(l.contains(d) ? d : l.first ?? d, filter: f, detail: false)   // the pick stays if it's on the new tab
        case (.box, 10000...):
            guard let j = boxOrder[safe: code - 10000] else { return }
            screen = .box(j, act: nil, confirm: false, detail: true)
        case (.box(let i, _, _, _), 4100...4103): boxSort = code - 4100; screen = .box(i, act: nil, confirm: false)
        case (.box(let i, _, _, true), 4400): screen = .box(i, act: 0, confirm: false, detail: true); press(1)      // = ● 함께
        case (.box(let i, _, _, true), 4401): screen = .box(i, act: 0, confirm: true, detail: true)                  // 놓아줄까? 아니오 first
        case (.box(let i, _, _, true), 4402): screen = .box(i, act: nil, confirm: false, detail: true)
        case (.box(let i, _, true, true), 4403): screen = .box(i, act: 1, confirm: true, detail: true); press(1)
        case (_, 4200), (_, 4201): gridStep(code == 4200 ? -GridModel.perPage : GridModel.perPage, ends: true)
        default: return
        }
    }
    /// What the pane's page shows: the battle, 도감 (grid or entry), 상자 (grid or one Pokémon), 상점 or 메뉴 page; elsewhere the status sheet if it's open.
    func paneContent(_ now: Date) -> PaneContent {
        if let b = sideModel(now) { return PaneContent(battle: b) }
        if let d = dexModel() { return PaneContent(dex: d) }
        if let g = gridModel(now) { return PaneContent(grid: g) }
        if let m = monModel() { return PaneContent(mon: m) }
        if let b = bagModel() { return PaneContent(bag: b) }
        if let s = shopModel() { return PaneContent(shop: s) }
        var sc = screen; if case .say(_, let next, _) = sc { sc = next }                       // a menu page's message (W가 부족하다, 커넥트): the list stays
        if case .menu(let i) = sc {
            let bp = (state.bp ?? 0).formatted(), notes = ["10W", "3W", "상자로 보내기", "오늘 \(state.today.formatted())걸음", "워커 \(state.caught.count)마리 · 도구 \(state.items.count)",
                                         "\(state.box.count.formatted())마리", "\(dexCount) / 493", "W로 사기", "\(bp)BP로 교환", "최고 \(state.towerBest ?? 0)연승"]
            return PaneContent(menu: MenuModel(rows: menuItems.indices.map { .init(name: menuItems[$0], note: notes[safe: $0] ?? "") }, sel: i))
        }
        switch sc {                                                                               // the rest of the walker's pages: what you press is here, the LCD shows it
        case .radar(let b, let c, let since, let chain):
            let u = Date().timeIntervalSince(since)
            return PaneContent(radar: RadarModel(live: (1.5...(1.5 + radarWindow(chain))).contains(u) ? b : nil, cursor: c, chain: chain))
        case .dowse(let c, _, let tries, let hint): return PaneContent(dowse: DowseModel(cursor: c, tries: tries, hint: hint))
        case .card(let p): return PaneContent(card: CardModel(page: p))
        case .learn(let sel):
            var st = state
            guard let (ref, id) = st.nextToLearn(), let m = state.mon(ref), let new = moveTable[id] else { break }
            func mv(_ x: MoveInfo) -> LearnModel.Move { .init(name: x.name, type: x.type, power: x.power, pp: x.pp) }
            return PaneContent(learn: LearnModel(who: monNames[m.dex], new: mv(new), known: m.moves.compactMap { moveTable[$0] }.map(mv), sel: sel))
        case .tower:
            return PaneContent(tower: TowerModel(run: towerRun, streak: state.towerStreak ?? 0, best: state.towerBest ?? 0, bp: state.bp ?? 0, fee: Walk.towerFee,
                                                 party: state.party().map { .init(dex: $0.mon.dex, name: monNames[$0.mon.dex], level: $0.mon.level) }))
        default: break
        }
        return statusOpen ? PaneContent(status: statusModel()) : PaneContent()
    }
    /// 포켓몬 · 도구: the companion first, then the walker's Pokémon; the picked one in full (the last chip = the items).
    func bagModel() -> BagModel? {
        var sc = screen; if case .say(_, let next, _) = sc { sc = next }
        guard case .bag(let p) = sc else { return nil }
        let mons = [state.companion] + state.caught
        let chips = mons.enumerated().map { BagModel.Chip(dex: $1.dex, name: monNames[$1.dex], level: $1.level, companion: $0 == 0) }
        return BagModel(chips: chips, sel: min(p, chips.count), mon: mons[safe: p].map { monPage($0) }, items: state.items)
    }
    /// A click on a walker page that isn't a grid: 5000 + k a radar bush, 5100 + k a dowsing spot, 5200 + p a card page, 5300 + k a move to forget (4 = don't),
    /// 5400 / 5401 the tower's 도전 / 나가기, 5500 + k a 포켓몬 · 도구 chip, 5510 its 함께 걷기. One click does it, as ● would.
    func pageTap(_ code: Int) {
        throughSay(); lastInput = Date(); shown = nil; needsDisplay = true
        switch (screen, code) {
        case (.radar(let b, _, let since, let chain), 5000...5003): screen = .radar(bush: b, cursor: code - 5000, since: since, chain: chain); press(1)
        case (.dowse(_, let prize, let tries, _), 5100...5105): screen = .dowse(cursor: code - 5100, prize: prize, tries: tries, hint: nil); press(1)
        case (.card, 5200...5202): screen = .card(code - 5200)
        case (.learn, 5300...5304): screen = .learn(sel: code - 5300); press(1)
        case (.tower, 5400): press(1)
        case (.tower, 5401): press(3)
        case (.bag, 5500..<5510): screen = .bag(min(code - 5500, bagPages - 1))
        case (.bag(let p), 5510) where p > 0 && p < bagPages - 1: press(1)
        default: return
        }
    }
    /// The 상자's one-Pokémon page: its nature and ability with what they do, IVs (as battles use them) and EVs; nil elsewhere.
    func monModel() -> MonModel? {
        var sc = screen; if case .say(_, let next, _) = sc { sc = next }
        guard case .box(let i, let act, let confirm, true) = sc, let m = state.box[safe: i] else { return nil }
        return monPage(m, act: act, confirm: confirm)
    }
    /// A Pokémon in full, for its page.
    func monPage(_ m: Mon, act: Int? = nil, confirm: Bool = false) -> MonModel {
        let n = natures[m.nature ?? 0], neutral = n.up == n.down, name = ["HP", "공격", "방어", "특공", "특방", "스피드"]   // the chips' and hexagons' names: every note fits its line
        let note = neutral ? "능력치에 영향을 주지 않는 성격" : josa(name[n.up], "이", "가") + " 10% 높고 " + josa(name[n.down], "이", "가") + " 10% 낮은 성격"
        return MonModel(nature: m.natureName, natureNote: note, ability: m.abilityName, abilityNote: abilityDescs[m.abilityID] ?? "", up: neutral ? nil : n.up, down: neutral ? nil : n.down,
                        ivs: m.effectiveIVs, evs: m.evs ?? Array(repeating: 0, count: 6), hyper: m.hyper ?? [], v: m.perfectIVs, evTotal: (m.evs ?? []).reduce(0, +), confirm: confirm && act != nil, sel: act.flatMap { $0 < 2 ? $0 : nil })
    }
    /// 홈 (and the other screens): where, the companion, today, then egg / tower / totals / dex.
    func statusModel() -> StatusModel {
        var m = state.companion
        if case .evolve(let from, _, let since) = screen, Date().timeIntervalSince(since) < 4.4 { m = from }   // no spoiler before the LCD's reveal
        let t = expTable[growthRate[m.dex]], lo = t[m.level], hi = t[min(100, m.level + 1)]
        let exp: CGFloat = m.level >= 100 || hi <= lo ? 1 : CGFloat(m.points - lo) / CGFloat(hi - lo)
        return StatusModel(dex: m.dex, name: (m.shiny == true ? "★ " : "") + monNames[m.dex], sex: sexMark(m).trimmingCharacters(in: .whitespaces), level: "Lv.\(m.level)",
                           toNext: m.level >= 100 ? "최고 레벨" : "\((hi - m.points).formatted()) EXP", nature: "\(m.natureName) · \(m.abilityName)", female: m.female, v: m.perfectIVs, exp: exp,
                           numbers: [.init(key: "오늘 걸음", value: state.today.formatted()), .init(key: "와트", value: "\(state.watts.formatted())W"), .init(key: "누적 걸음", value: state.total.formatted())],
                           rows: [.init(key: "알", value: state.egg.map { $0.left > 0 ? "앞으로 \($0.left.formatted())걸음" : "곧 태어난다!" } ?? "없음"),
                                  .init(key: "배틀 타워", value: "최고 \(state.towerBest ?? 0)연승 · \((state.bp ?? 0).formatted())BP"),
                                  .init(key: "도감", value: "잡음 \(dexCount) · 봤음 \(seenList.count)")])
    }
    /// A click on a 메뉴 tile: open it (as ● on it would).
    func menuTap(_ i: Int) {
        throughSay()
        guard case .menu = screen, menuItems.indices.contains(i) else { return }
        lastInput = Date(); shown = nil; needsDisplay = true
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
        let ws = wares(bp), unit = bp ? "BP" : "W", money = bp ? state.bp ?? 0 : state.watts, w = ws[safe: sel]
        let rows = ws.map { w in ShopModel.Row(name: state.wareName(w), note: state.wareNote(w), price: w.once && state.owned(w) > 0 ? "보유" : "\(w.price.formatted())\(unit)",
                                                 owned: state.owned(w), can: state.canBuy(w, bp: bp) > 0, once: w.once) }
        let cost = (w?.price ?? 0) * (qty ?? 0)
        let hint = said ?? w.map { w in
            w.once && state.owned(w) > 0 ? "이미 가지고 있어요" : state.canBuy(w, bp: bp) == 0 ? "\(unit)가 부족해요 · \(w.price.formatted())\(unit) 필요" : "클릭하거나 ●를 누르면 몇 개 살지 정해요"
        } ?? ""
        let spend = ask != nil ? w?.price ?? 0 : cost
        return ShopModel(title: bp ? "BP 교환소" : "상점", rows: rows, sel: sel, qty: qty, most: w.map { max(1, state.canBuy($0, bp: bp)) } ?? 1,
                         total: "\(spend.formatted())\(unit)", hint: hint, ask: ask)
    }
}
