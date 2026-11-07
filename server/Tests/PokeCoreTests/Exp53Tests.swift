import Foundation
import Testing
@testable import PokeCore

// docs/plans/19 §12 (5.3, content53): 협동 (레시라무 · 제크로무 with a friend or alone → 큐레무) and 스토리 (칼로스 이야기 → 5장).

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// One trainer's engine side (the clock a second an act; `day()` moves it a day on), as Exp52Tests' Desk.
private struct Desk {
    var w: Walk, p = Play(), r = Seeded(s: 11), ids = Issued(next: firstUID + 1), clock = 0.0
    init(_ w: Walk = Engine.fresh(now: t0, starter: firstUID)) { self.w = w }
    @discardableResult mutating func act(_ a: Act, steps: Int = 0) -> Outcome {
        clock += 1
        return Engine.apply(a, steps: steps, walk: &w, play: &p, rng: &r, now: t0.addingTimeInterval(clock), ids: &ids)
    }
    mutating func day() { clock += 86_400 }
    func x(_ id: String) -> ExpProgress? { w.expeditions?[id] }
    /// The fight on, every one of theirs at 1 HP, hit until it ends.
    mutating func win() -> Outcome {
        for i in p.battle!.theirs.indices { p.battle!.theirs[i].hp = 1 }
        var last = Outcome()
        for _ in 0..<20 where p.battle != nil { last = act(.battle(cmd: .fight(slot: 0))); if p.battle?.mustReplace == true { _ = act(.battle(cmd: .replace(to: 0))) } }
        return last
    }
}
private func on53<T>(_ body: () throws -> T) rethrows -> T {
    try Content.$testing.withValue(true) { try Content.$testing51.withValue(true) { try Content.$testing52.withValue(true) { try Content.$testing53.withValue(true) { try body() } } } }
}
private func course(_ f: (Course) -> Bool) -> Int { courses.firstIndex(where: f)! }
private var kalos: Int { course { $0.region == 650...721 } }
private func strong(_ dex: Int, _ moves: [Int]) -> Mon { var m = Mon(dex: dex, level: 100, female: false); m.known = moves; m.uid = 9_000 + dex; return m }

@Test func storyChapters() throws {
    try on53 {
        var d = Desk(); let s = Expeditions.story
        let me = strong(150, [85, 94, 247, 58]); d.w.box = [me]
        #expect(d.act(.expStart(id: s)).cannot == nil)
        let rolled = try #require(d.x(s)?.mon)
        #expect(rolled.dex == 716 && d.x(s)?.pick == nil)
        // 1장: 칼로스 steps only, then its trainer (any time; a loss keeps the step)
        d.w.course = 0; d.act(.steps, steps: 30_000)
        #expect(d.x(s)?.steps == 0)
        d.w.course = kalos; var o = d.act(.steps, steps: 20_000)
        #expect(d.x(s)?.stage == 1 && o.news.contains(.expeditionStage(id: s, stage: 1)))
        o = d.act(.expFight(id: s, party: [me.uid!]))
        let b = try #require(o.battle)
        #expect(b.trainer == "플레어단 조무래기" && b.expedition == s && b.raidTier == nil && b.theirs.map(\.mon.dex) == [228, 453] && b.theirs[0].mon.level == 35)
        #expect(b.mine[0].mon.level == 100)                                                          // our own, at its own level
        o = d.act(.battle(cmd: .forfeit))
        #expect(d.p.battle == nil && d.x(s)?.stage == 1)
        #expect(d.act(.expFight(id: s, party: [me.uid!])).cannot == nil)                             // again the same day: no limit
        o = d.win()
        #expect(o.end?.result == "won" && d.x(s)?.stage == 2 && o.news.contains(.expeditionStage(id: s, stage: 2)) && o.end?.bp == nil)
        // 2장, then the dex gate (칼로스 도감 5) before 3장
        d.act(.steps, steps: 20_000); d.act(.expFight(id: s, party: [me.uid!])); o = d.win()
        #expect(d.x(s)?.stage == 4)
        d.w.owned = (d.w.owned ?? []).filter { !(650...721).contains($0) } + [650, 653, 656, 659]
        #expect(d.act(.expFight(id: s)).cannot == "칼로스 도감이\n5종 있어야 해요")
        d.act(.steps, steps: 5_000)
        #expect(d.x(s)?.stage == 4 && d.x(s)?.steps == 0)                                            // no steps kept at a gate
        d.w.owned?.append(661)
        o = d.act(.steps)
        #expect(d.x(s)?.stage == 5 && o.news.contains(.expeditionStage(id: s, stage: 5)))
        // 3장 · 4장 (플라드리 Lv.65, four), then the pick
        d.act(.steps, steps: 20_000); d.act(.expFight(id: s, party: [me.uid!])); _ = d.win()
        d.act(.steps, steps: 20_000)
        o = d.act(.expFight(id: s, party: [me.uid!]))
        #expect(o.battle?.trainer == "플레어단 보스 플라드리" && o.battle?.theirs.count == 4 && o.battle?.theirs[0].mon.level == 65)
        _ = d.win()
        #expect(d.x(s)?.stage == 9)
        #expect(d.act(.expFight(id: s)).cannot == "먼저 골라 주세요")
        #expect(d.act(.expPick(id: s, dex: 718)).cannot == "고를 수 없는\n포켓몬이에요")
        #expect(d.act(.expPick(id: "레시라무", dex: 716)).cannot == "고를 때가\n아니에요")
        #expect(d.act(.expPick(id: s, dex: 717)).cannot == nil)
        #expect(d.x(s)?.pick == 717 && d.x(s)?.mon?.dex == 717 && d.x(s)?.mon?.shiny == rolled.shiny && d.x(s)?.stage == 10)
        // the final fight: Lv.70, 3 bars, once a day; a win — it comes, no balls
        o = d.act(.expFight(id: s, party: [me.uid!]))
        #expect(o.battle?.wild.dex == 717 && o.battle?.wild.level == 70 && o.battle?.theirs.count == 3 && o.battle?.wild.moves.contains(613) == true)
        o = d.win()
        #expect(o.end?.result == "won" && o.end?.balls == nil && o.mon?.dex == 717 && o.mon?.level == 50 && o.mon?.moves.contains(620) == false)
        #expect(d.x(s) == ExpProgress(done: 1, pick: 717) && d.w.bag.contains("특성패치"))
        // 5장: the other one (716), after the story; 칼로스 도감 10, 40,000 steps
        var e = Desk(); e.w.expeditions = [:]
        #expect(e.act(.expStart(id: Expeditions.story5)).cannot == "칼로스 이야기를\n먼저 끝내 주세요")
        #expect(d.act(.expStart(id: Expeditions.story5)).cannot == nil)
        let s5 = Expeditions.story5
        #expect(d.x(s5)?.mon?.dex == 716 && d.x(s5)?.stage == nil)
        d.w.owned! += [662, 664, 667, 669, 672]
        d.act(.steps)
        #expect(d.x(s5)?.stage == 1)
        d.act(.steps, steps: 40_000)
        #expect(d.x(s5)?.stage == 2)
        d.act(.expFight(id: s5, party: [me.uid!])); o = d.win()
        #expect(o.mon?.dex == 716 && d.x(s5) == ExpProgress(done: 1) && d.w.bag.filter { $0 == "특성패치" }.count == 1)
    }
}

@Test func pairAlone() throws {
    try on53 {
        var d = Desk()
        #expect(d.act(.expStart(id: "레시라무")).cannot == nil)
        #expect(d.x("레시라무")?.mon?.dex == 643)
        d.p.paired = true; d.act(.steps, steps: 50_000)
        #expect(d.x("레시라무")?.steps == 0)                                                          // paired: the pair's (the server's), not alone
        d.p.paired = nil; d.act(.steps, steps: 150_000)
        #expect(d.x("레시라무")?.steps == 150_000 && d.x("레시라무")?.stage == nil)
        let o = d.act(.steps, steps: 60_000)
        #expect(d.x("레시라무")?.stage == 1 && d.x("레시라무")?.steps == 0 && o.news.contains(.expeditionStage(id: "레시라무", stage: 1)))
        #expect(d.w.pairCan("레시라무") == "이미 함께 걷기를\n끝낸 원정이에요" && d.w.pairCan("제크로무") == nil && d.w.pairCan("큐레무") != nil)
        // the boss: Lv.60, 5 balls; 큐레무 after both, a cave course of any region
        let me = strong(150, [85, 94, 247, 58]); d.w.box = [me]
        #expect(d.act(.expFight(id: "레시라무", party: [me.uid!])).battle?.wild.moves.contains(558) == true)
        #expect(d.win().end?.balls == 5)
        #expect(d.act(.expStart(id: "큐레무")).cannot == "레시라무와 제크로무를\n먼저 잡아 주세요")
        d.w.expeditions?["레시라무"] = ExpProgress(done: 1); d.w.expeditions?["제크로무"] = ExpProgress(done: 1)
        #expect(d.act(.expStart(id: "큐레무")).cannot == nil)
        d.w.course = course { $0.art == .cave && $0.region == nil }; d.act(.steps, steps: 30_000)
        #expect(d.x("큐레무")?.stage == 1)
        d.act(.expFight(id: "큐레무", party: [me.uid!])); _ = d.win()
        var got: Outcome? = nil
        for _ in 0..<5 where got == nil { let t = d.act(.expBall(id: "큐레무")); if t.raidThrow?.caught == true { got = t } }
        if let g = got { #expect(g.mon?.dex == 646 && d.w.bag.contains("유전자쐐기") && d.w.bag.contains("특성패치")) }
    }
}

@Test func content53Off() throws {
    try Content.$testing.withValue(true) { try Content.$testing51.withValue(true) { try Content.$testing52.withValue(true) {
        var d = Desk()
        #expect(!Expeditions.personal.contains { $0.id == "레시라무" })
        #expect(d.act(.expStart(id: "레시라무")).cannot == "없는 원정이에요")
        #expect(d.act(.expStart(id: Expeditions.story)).cannot == "없는 원정이에요")
        #expect(d.act(.expPick(id: Expeditions.story, dex: 716)).cannot == "고를 때가\n아니에요")
        #expect(d.w.pairCan("레시라무") != nil)
        #expect(d.act(.expStart(id: "토네로스")).cannot == nil)                                       // 5.2 as it was
    } } }
}

// MARK: the server's pairs (ServerPair.swift), through the acts

private let base = Date(timeIntervalSince1970: 2_000_000_000)
private func reply(_ r: Reply) throws -> ActReply { try JSONDecoder().decode(ActReply.self, from: r.body) }

@Test func pairsThroughTheServer() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    try await Content.$testing.withValue(true) { try await Content.$testing51.withValue(true) {
        let a = "zz530001", b = "zz530002", c = "zz530003"
        var s: [String: String] = [:], seq: [String: Int] = [:]
        for k in [a, b, c] {
            let r = await db.create(CreateReq(id: k, device: "mac", device_name: "MAC", app: "5.3", pin: "2468"), now: Int(base.timeIntervalSince1970))
            s[k] = try #require(string(r, "session"))
        }
        var clock = 60.0
        func go(_ k: String, _ x: Act, app: String = "5.3") async throws -> ActReply {
            seq[k, default: 0] += 1; clock += 1
            return try reply(await db.act(ActReq(id: k, session: s[k]!, seq: seq[k]!, act: x, app: app), now: base.addingTimeInterval(clock)))
        }
        for k in [a, b, c] { _ = try await go(k, .steps) }
        #expect(try await go(a, .pairInvite(to: b, id: "레시라무")).out.cannot == "친구에게만\n청할 수 있어요")
        for k in [b, c] { _ = try await go(a, .friendRequest(to: k)); _ = try await go(k, .friendAccept(from: a)) }
        #expect(try await go(a, .pairInvite(to: b, id: "큐레무")).out.cannot == "레시라무 · 제크로무만\n고를 수 있어요")
        #expect(try await go(a, .pairInvite(to: b, id: "레시라무"), app: "5.2.2").out.cannot == "5.3부터예요")   // a 5.2 app: off for it
        #expect(try await go(a, .pairInvite(to: b, id: "레시라무")).out.cannot == nil)
        // the ask takes no place: A's 지가르데 goes on
        #expect(try await go(a, .expStart(id: "지가르데")).out.cannot == nil)
        let asked = try await go(b, .steps)
        guard case .pairAsked(let pid, _, "레시라무")? = asked.out.news.first(where: { if case .pairAsked = $0 { true } else { false } }) else { Issue.record("\(asked.out.news)"); return }
        let views = try JSONDecoder().decode(ExpReply.self, from: await db.expeditionList(ExpReq(id: b, session: s[b]!), now: base.addingTimeInterval(clock)).body)
        #expect(views.pairs?.first?.state == "got" && views.pairs?.first?.mine == nil && views.pairs?.first?.theirs == "레시라무" && views.story?.isEmpty == false)
        // B takes it with 제크로무: both on their dragons now (A's 지가르데 stopped), 14 days
        let took = try await go(b, .pairAccept(pair: pid, id: "제크로무"))
        #expect(took.out.cannot == nil && took.walk?.expeditions?["제크로무"]?.on == true)
        let heard = try await go(a, .steps)
        #expect(heard.out.news.contains(.pairOn(pair: pid, with: b, id: "제크로무")))
        let wa = try #require(heard.walk)
        #expect(wa.expeditions?["레시라무"]?.on == true && wa.expeditions?["지가르데"]?.on == false)
        #expect(try await go(c, .pairInvite(to: a, id: "제크로무")).out.cannot?.hasSuffix(" 이미\n짝이 있어요") == true)
        // the steps: 300,000 between them, 30,000 each — A 280,000 and B 20,000 isn't yet
        try await db.pairSteps(a, 280_000, now: Int(base.timeIntervalSince1970) + 100)
        try await db.pairSteps(b, 20_000, now: Int(base.timeIntervalSince1970) + 100)
        #expect(try await db.pairOn(a) != nil)
        try await db.pairSteps(b, 10_000, now: Int(base.timeIntervalSince1970) + 100)
        #expect(try await db.pairOn(a) == nil)
        let doneA = try await go(a, .steps), doneB = try await go(b, .steps)
        #expect(doneA.out.news.contains(.expeditionStage(id: "레시라무", stage: 1)) && doneA.walk?.expeditions?["레시라무"]?.stage == 1)
        #expect(doneB.out.news.contains(.expeditionStage(id: "제크로무", stage: 1)))
        #expect(try await go(a, .steps).out.news.allSatisfy { if case .expeditionStage = $0 { false } else { true } })   // once
        // a new pair (A 제크로무 · C 레시라무), ended by A starting another expedition: C told, the steps gone
        #expect(try await go(c, .pairInvite(to: a, id: "레시라무")).out.cannot == nil)
        guard case .pairAsked(let p2, _, _)? = try await go(a, .steps).out.news.first(where: { if case .pairAsked = $0 { true } else { false } }) else { Issue.record("no ask"); return }
        #expect(try await go(a, .pairAccept(pair: p2, id: "레시라무")).out.cannot == "이미 함께 걷기를\n끝낸 원정이에요")
        #expect(try await go(a, .pairAccept(pair: p2, id: "제크로무")).out.cannot == nil)
        try await db.pairSteps(c, 5_000, now: Int(base.timeIntervalSince1970) + 200)
        let left = try await go(a, .expStart(id: "지가르데"))
        #expect(left.out.cannot == nil && left.out.news.contains(.pairClosed(pair: p2, with: c, why: "풀림")))
        #expect(try await go(c, .steps).out.news.contains(.pairClosed(pair: p2, with: a, why: "풀림")))
        // asks: a no, and one past its 3 days
        #expect(try await go(b, .pairInvite(to: a, id: "제크로무")).out.cannot == "이미 함께 걷기를\n끝낸 원정이에요")
        #expect(try await go(c, .pairInvite(to: a, id: "제크로무")).out.cannot == nil)
        guard case .pairAsked(let p3, _, _)? = try await go(a, .steps).out.news.first(where: { if case .pairAsked = $0 { true } else { false } }) else { Issue.record("no ask 3"); return }
        #expect(try await go(a, .pairCancel(pair: p3)).out.cannot == nil)
        #expect(try await go(c, .steps).out.news.contains(.pairClosed(pair: p3, with: a, why: "거절")))
        #expect(try await go(a, .pairCancel(pair: p3)).out.cannot == "없는 짝이에요")
        #expect(try await go(c, .pairInvite(to: a, id: "제크로무")).out.cannot == nil)
        clock += Double(Expeditions.inviteDays * 86_400)
        #expect(try await go(c, .steps).out.news.contains { if case .pairClosed(_, _, "기한") = $0 { true } else { false } })
        let late = try await go(a, .steps)
        #expect(late.out.news.allSatisfy { if case .pairAsked = $0 { false } else { true } })
        let report = try await db.pairsReport(now: Int(base.timeIntervalSince1970) + Int(clock))
        #expect(report.contains("closed") && report.contains("done"))
        #expect(try await db.pairRows("state IN ('asked', 'on')").isEmpty)
    } }
}
