#if os(macOS)
import AppKit
// The public site's 육성 가이드 (docs/guide/): the app's own screens for it, one example save throughout — 이상해꽃 Lv.55 walking with
// 트레이너, 배루키 · 피카츄 · 이브이 on the walker, an egg, friends on a fake server. Not part of the app: tools/guide-shots/README.md says how
// it's run (a copy of the repository, this file in its Tests/, `GUIDE=1 PokeWalker --shots <dir>`). Each screen as <name>.png at 2x and
// <name>.json (its words and where they are, in points) for tools/guide-shots/annotate.swift.

@MainActor func guideShots(_ dir: String) -> Int {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var n = 0
    func take(_ name: String, _ v: Walker, _ set: (Walker) -> Void) {
        let view = WalkerView(walker: v); set(v)
        drawnTexts = []
        v.refreshPane(Date(), force: true); view.fitWindow(); view.shown = v.compose(Date()); view.page.needsDisplay = true
        let b = view.bounds, s = CGFloat(Double(ProcessInfo.processInfo.environment["GUIDE_SCALE"] ?? "") ?? 4)   // 4: the card at 크기 2 (보통), 2x
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b.width * s), pixelsHigh: Int(b.height * s), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = b.size
        view.cacheDisplay(in: b, to: rep)
        let pageY = view.page.frame.minY
        let texts: [[String: Any]] = (drawnTexts ?? []).map { t in
            let surf = Int((t.r.minY + 50_000) / 100_000), y = t.r.minY - CGFloat(surf) * 100_000 + (surf == 2 ? pageY : 0)
            return ["s": t.s, "x": t.r.minX, "y": y, "w": t.r.width, "h": t.r.height, "surf": surf]
        }
        drawnTexts = nil
        let url = URL(fileURLWithPath: dir)
        let meta: [String: Any] = ["w": b.width, "h": b.height, "pageY": pageY, "texts": texts]
        try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]).write(to: url.appendingPathComponent(name + ".json"))
        if (try? rep.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent(name + ".png"))) != nil { n += 1 }
    }
    /// online(), with the trainer's name the pages show (트레이너, not a test's zz ID).
    func walker(_ s: Walk, _ srv: FakeCloud) -> Walker {
        let key = "트레이너", dir = FileManager.default.temporaryDirectory.appendingPathComponent("pokewalker-guide-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        srv.add(key, s)
        let c = Cloud(link: srv, dir: dir); c.seat.trainerID = key
        let v = Walker(state: s); v.persist = false; let h = TestHost(); v.host = h; h.keys = 0
        v.startCloud(c); drain(v)
        return v
    }
    func with(_ body: () -> Void) {
        Content.$testing.withValue(true) { Content.$testing51.withValue(true) { Content.$testingDaily.withValue(true) { Content.$testingSlots.withValue(true) {
            Content.$testingChoice.withValue(true) { Content.$testingDuelMega.withValue(true) { body() } } } } } }
    }
    with {
        var r = Seeded(s: 21)
        // 이상해꽃: 고집 (공격 ↑ 특공 ↓ — 조심민트 turns it around), 심록 (특성패치: 엽록소), 3V, a few EVs, 기적의씨, four moves
        var saur = Mon(dex: 3, level: 55, female: false)
        saur.nature = 3; saur.ability = 0; saur.ivs = [31, 14, 31, 24, 31, 19]; saur.evs = [52, 0, 0, 0, 0, 60]; saur.known = [76, 188, 79, 202]; saur.item = "기적의씨"
        let t = expTable[growthRate[3]]; saur.exp = t[55] + (t[56] - t[55]) * 62 / 100; saur.walked = 48_000
        var tyrogue = Mon(dex: 236, level: 20, female: false); tyrogue.ability = 2
        let save: Walk = {
            var s = Walk()
            s.companion = saur
            s.caught = [tyrogue, Mon.wild(25, level: 24, &r), Mon.wild(133, level: 18, &r)]
            s.box = [1, 4, 7, 16, 19, 41, 52, 63, 66, 74, 92, 129, 147, 158, 175, 246].map { Mon.wild($0, level: 8 + $0 % 23, &r) }
            s.items = ["상처약", "좋은상처약"]
            s.bag = ["리보플라빈", "리보플라빈", "리보플라빈", "조심민트", "은색병뚜껑", "은색병뚜껑", "금색병뚜껑", "특성패치", "이상해꽃나이트", "이상한사탕", "이상한사탕",
                     "몬스터볼", "몬스터볼", "하이퍼볼", "구애안경", "먹다남은음식", "라즈열매", "기력의조각"]
            s.watts = 12_480; s.earned = 640_000; s.bp = 120; s.weather = .sunny; s.egg = Egg(dex: 175, left: 1_200)
            s.towerBest = 21; s.towerStreak = 0; s.towerRewards = [7, 14, 21]
            s.today = 6_240; s.total = 412_300; s.history = [8_120, 5_400, 9_870, 3_210, 7_650, 6_020]
            s.owned = Array(1...9) + [16, 19, 25, 41, 52, 63, 66, 74, 92, 129, 133, 147, 158, 175, 236, 246]
            s.seen = Array(10...40) + [54, 60, 77, 95, 111, 130, 143, 149, 150, 249]
            s.raidPower = 46_800; s.day = Walk.key(Date())
            s.dex()
            return s
        }()
        // the server: friends (홈's 친구, the raids' lists), this week's raids, the Mega raid's week, a team event (전설 원정), 배루키's pick
        let srv = FakeCloud(); srv.megaWeekNo = 0; srv.evoChoice = true
        let v = walker(save, srv), me = "트레이너"
        let friends: [(String, Int, Int, Int)] = [("민수", 6, 52, 9_876), ("지은", 282, 47, 7_420), ("도윤", 448, 61, 5_310), ("서연", 133, 30, 3_020)]
        let ts = Int(Date().timeIntervalSince1970), today = Walk.key(Date())
        for (k, f) in friends.enumerated() {
            var w = Walk(), fr = Seeded(s: UInt64(k + 40)); w.companion = Mon.wild(f.1, level: f.2, &fr); w.today = f.3; w.owned = Array(1...(60 + 20 * k)); w.towerBest = 10 + 7 * k
            srv.add(f.0, w); srv.lastAct[f.0] = k < 2 ? Date() : Date().addingTimeInterval(-3600); srv.befriend(me, f.0)
            let boss = Mon(dex: 249, level: RaidRules.tiers[2].level, female: false)
            srv.raidRuns[f.0.lowercased()] = (0..<(3 - k % 3)).map { j in .init(tier: 3, boss: boss, day: today, at: ts - 3600 * (j + 1), bars: 10, balls: 3, won: true, caught: j == 0, ended: true) }
        }
        let lugia = Mon(dex: 249, level: RaidRules.tiers[2].level, female: false)
        srv.raidRuns[me] = [.init(tier: 3, boss: lugia, day: today, at: ts - 5400, bars: 10, balls: 3, won: true, caught: true, ended: true),
                            .init(tier: 3, boss: lugia, day: today, at: ts - 1800, bars: 7, balls: 0, won: false, caught: false, ended: true)]
        let megaBoss = Mon(dex: MegaRaid.week(0)[0].dex, level: 20, female: false)
        srv.raidRuns[me]! += (0..<3).map { k in .init(tier: k + 1, boss: megaBoss, day: today, at: ts - 7200 * (k + 1), bars: 10, won: true, ended: true, mega: true) }
        srv.megaWins[me] = [MegaRaid.week(0)[0].stone: 7]
        srv.expEvents = [TeamEventView(id: 1, legend: 494, starts: ts - 4 * 86_400, ends: ts + 3 * 86_400 - 600, goal: 1_500_000, min: 20_000, team: 931_200, mine: 12_400, got: false)]
        v.cloud!.teamDue = true; v.cloud!.raidDue = true; v.cloud!.expeditionDue = true; drain(v); drain(v)
        func page(_ ref: Int) -> Screen { .box(ref, act: nil, confirm: false, detail: true) }
        @MainActor func fix(_ change: (inout Mon) -> Void) { change(&v.state.companion) }

        // 01 걸음: 홈, the menu's first page
        take("home", v) { v in v.screen = .home }
        take("menu", v) { v in v.screen = .menu(group: nil, sel: 0) }
        // 03 잡기: the radar (a bush shaking, a chain going), a wild one's menu, the ball rocking
        take("radar", v) { v in v.screen = .radar(bush: 2, cursor: 2, since: Date().addingTimeInterval(-2.0), chain: 3) }
        var wr = Seeded(s: 9), eevee = Mon.wild(133, level: 22, &wr); eevee.female = true
        var wild = Battle(wild: eevee, companion: v.state.companion, chain: 0); _ = wild.begin(weather: nil, &wr); wild.theirs[0].hp = max(1, wild.theirs[0].maxHP / 4)
        take("battle_menu", v) { v in v.animOn = ("foe 0", 133, Date().addingTimeInterval(-60)); v.fight = wild; v.screen = .battle(wild, sel: 1) }
        for u in [0.6, 1.0, 1.4, 1.8, 2.2, 2.6] {
            take("battle_throw_\(Int(u * 10))", v) { v in v.usedItem = "몬스터볼"; v.fight = wild; v.screen = .beats(wild, [.thrown(shakes: 3), .caught], since: Date().addingTimeInterval(-u / v.battleSpeed), from: wild) }
        }
        v.fight = nil
        // 05 진화: 배루키's pick (the walker's)
        let tu = v.state.caught[0].uid ?? 0
        take("evo_pick", v) { v in v.screen = .evoPick(uid: tu, at: 0, ask: nil) }
        // 06 강하게 만들기: the page; each change before and after; the screens that make them
        take("page", v) { v in v.screen = page(-1) }
        take("evs_after", v) { v in v.state.companion.evs = [52, 0, 0, 100, 0, 60]; v.screen = page(-1) }
        fix { $0.evs = [52, 0, 0, 0, 0, 60] }
        take("mint_pick", v) { v in v.screen = .itemOn(ItemOn(item: "조심민트", pick: -1, at: 0)) }
        take("mint_after", v) { v in v.state.companion.mint = 15; v.screen = page(-1) }
        fix { $0.mint = nil }
        take("cap_pick", v) { v in v.trainRef = -1; v.screen = .train(3) }
        take("silver_after", v) { v in v.state.companion.hyper = [3]; v.screen = page(-1) }
        take("gold_after", v) { v in v.state.companion.hyper = [1, 3, 5]; v.screen = page(-1) }
        fix { $0.hyper = nil }
        take("patch_pick", v) { v in v.screen = .itemOn(ItemOn(item: "특성패치", pick: -1, at: 0)) }
        take("patch_after", v) { v in v.state.companion.ability = 2; v.screen = page(-1) }
        fix { $0.ability = 0 }
        take("hold", v) { v in v.screen = .hold(ref: -1, sel: max(0, v.holdRows(-1).firstIndex { $0.name == "이상해꽃나이트" } ?? 0)) }
        take("hold_after", v) { v in v.state.bag.removeAll { $0 == "이상해꽃나이트" }; v.state.bag.append("기적의씨"); v.state.companion.item = "이상해꽃나이트"; v.screen = page(-1) }
        let relearn = v.state.companion.relearnable
        take("moves", v) { v in v.screen = .relearn(ref: -1, slot: 3, at: relearn.first { moveTable[$0]?.name == "꽃잎댄스" } ?? relearn.first) }
        var gr = Seeded(s: 10), mega = v.state.companion; mega.item = "이상해꽃나이트"
        var gyara = Mon.wild(130, level: 50, &gr); gyara.female = false
        var mb = Battle(wild: gyara, companion: mega, chain: 0); _ = mb.begin(weather: nil, &gr)
        take("mega", v) { v in v.state.companion = mega; v.megaOn = true; v.animOn = ("foe 0", 130, Date().addingTimeInterval(-60)); v.fight = mb; v.screen = .moves(mb, sel: 0) }
        v.megaOn = false; v.fight = nil; v.state.companion = saur
        // 08 쓰는 곳: the tower's lobby, the raids' (by the day), the Mega raid's, 전설 원정
        take("tower", v) { v in v.towerRun = false; v.screen = .tower(pick: nil) }
        take("raid", v) { v in v.screen = .raid(.lobby(tab: 0)) }
        v.openFeature("메가 레이드"); drain(v); drain(v); v.cloud!.megaRaidDue = true; drain(v)
        take("mega_raid", v) { v in v.screen = .raid(.lobby(tab: 0)) }
        v.raidMega = false
        take("expedition", v) { v in v.screen = .expedition(0) }
    }
    return n
}
#endif
