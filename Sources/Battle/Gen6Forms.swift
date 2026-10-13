import Foundation
// docs/plans/18 §5 · §6 (5.0, content5): forms in a fight. Mega Evolution (a held stone, once a side a fight; 메가레쿠쟈 by 화룡점정),
// 원시회귀 (쪽빛구슬 · 주홍구슬 on coming out) and its weathers (시작의바다 · 끝의대지 · 델타스트림: only while their bringer is out), and the
// forms for now: 메로엣타 (옛노래), 킬가르도 (배틀스위치), 불비달마 (달마모드). A Mega stays one through switches; a form for now goes on switching.

extension Battle {
    // MARK: Mega Evolution
    /// The Mega form s's one would become (its number and data): the stone it holds, or 화룡점정 for 레쿠쟈.
    func megaForm(_ s: Side) -> (n: Int, form: MonForm)? {
        let x = f(s)
        if x.mon.dex == 384, x.moves.contains(620), let m = Forms.of(384, 1) { return (1, m) }
        guard let r = Forms.mega(x.mon.dex, holding: x.item), r.form.kind == .mega else { return nil }
        return r
    }
    /// s may Mega Evolve now: content5, its side hasn't this fight, it isn't one already (nor 변신'd), and it has a Mega form to become.
    func canMega(_ s: Side) -> Bool {
        Content.gen6 && megaUsed?[si(s)] != true && f(s).mega == nil && f(s).form == nil && f(s).alive && megaForm(s) != nil
    }
    mutating func megaEvolve(_ s: Side) {
        guard canMega(s), let (n, fm) = megaForm(s) else { return }
        var used = megaUsed ?? [false, false]; used[si(s)] = true; megaUsed = used
        let who = nm(s)
        let glow = f(s).mon.dex == 384 ? josa(who, "은", "는") + " 화룡점정의 힘에 휩싸였다!" : josa(who + "의 " + (fm.item ?? ""), "이", "가") + " 빛나기 시작했다!"
        out.append(.mega(s, form: n, text: glow + "\n" + josa(who, "은", "는") + " " + josa(fm.name, "으로", "로") + " 메가진화했다!")); apply(out.last!)
        retyped(s); entryAbility(s)                                                                  // its new ability comes in (가뭄, 위협 ...)
    }
    /// At a turn's start, before anyone moves (the order was already set by speed as it was): ours if asked, a trainer's as soon as it can
    /// (a live player's when it asked); the faster first.
    mutating func megas(ours: Bool, theirs: Bool) {
        let a = ours && canMega(.me), b = theirs && canMega(.it)
        if a, b, speed(.it) > speed(.me) { megaEvolve(.it); megaEvolve(.me); return }
        if a { megaEvolve(.me) }; if b { megaEvolve(.it) }
    }

    // MARK: 원시회귀 and its weathers
    mutating func primalReversion(_ s: Side) {
        let x = f(s)
        guard Content.gen6, x.alive, x.mega == nil, x.form == nil, let r = Forms.mega(x.mon.dex, holding: x.item), r.form.kind == .primal else { return }
        out.append(.mega(s, form: r.n, text: josa(nm(s), "의", "의") + " 원시회귀!\n고대의 모습을 되찾았다!")); apply(out.last!); retyped(s)
    }
    /// 시작의바다 · 끝의대지 · 델타스트림 end once their bringer isn't out.
    mutating func extremeWeatherCheck() {
        guard let e = extreme, !over else { return }
        if [mine[me], theirs[it]].contains(where: { $0.alive && $0.has(e) }) { return }
        extreme = nil; sky = .clear; skyTurns = 0
        say(.it, [189: "강한 비가 그쳤다!", 190: "강렬한 햇살이 약해졌다!", 191: "수수께끼의 난기류가 멈췄다!"][e] ?? ""); forecast()
    }
    /// Under 시작의바다 a damaging Fire move fizzles; under 끝의대지 a Water one.
    mutating func extremeFizzles(_ s: Side, type: String) -> Bool {
        if extreme == 189, type == "fire" { say(s, "강한 비 때문에 불꽃 공격이 사라졌다!"); return true }
        if extreme == 190, type == "water" { say(s, "강렬한 햇살 때문에 물 공격이 증발했다!"); return true }
        return false
    }

    // MARK: forms for now
    mutating func reform(_ s: Side, _ n: Int?, _ text: String) { out.append(.reform(s, form: n ?? 0, text: text)); apply(out.last!); retyped(s) }
    /// 배틀스위치: 킬가르도 turns to 블레이드폼 for an attack, back to 실드폼 for 킹실드.
    mutating func stanceChange(_ s: Side, _ m: MoveInfo) {
        guard f(s).mon.dex == 681, f(s).has(176), f(s).form == nil else { return }
        if m.power > 0 || Moves.fixedOrVariable.contains(m.id), f(s).battleForm != 1 { reform(s, 1, josa(nm(s), "은", "는") + " 블레이드폼으로 체인지했다!") }
        else if m.id == 588, f(s).battleForm == 1 { reform(s, nil, josa(nm(s), "은", "는") + " 실드폼으로 체인지했다!") }
    }
    /// 달마모드: 불비달마 at half its HP or less, back above it (at a turn's end).
    mutating func zenMode(_ s: Side) {
        guard f(s).alive, f(s).mon.dex == 555, f(s).mon.abilityID == 161, f(s).abilityOver == nil, f(s).form == nil else { return }
        let low = f(s).hp * 2 <= f(s).maxHP
        if low, f(s).battleForm != 1 { reform(s, 1, josa(nm(s), "은", "는") + " 달마모드가 되었다!") }
        else if !low, f(s).battleForm == 1 { reform(s, nil, josa(nm(s), "은", "는") + " 노말모드로 돌아왔다!") }
    }
    /// 옛노래: 메로엣타 steps between 보이스폼 and 스텝폼.
    mutating func relicSong(_ s: Side) {
        guard f(s).alive, f(s).mon.dex == 648, f(s).form == nil else { return }
        let step = f(s).battleForm != 1
        reform(s, step ? 1 : nil, josa(nm(s), "은", "는") + (step ? " 스텝폼" : " 보이스폼") + "으로 체인지했다!")
    }
}
