import Foundation
// docs/plans/18 §15 (5.0, content5; the user, 10-14: "ㅇㅇ 추천대로"): 도감 업적 — small rewards by mail as the dex fills (the whole dex's
// steps, each region's half and all of it), and a region filled to its last species rolls 이로치 once more for its species (the radar, eggs).
// Counted on `owned` (ever caught: a trade away doesn't take it back). Off (4.1): none of it.

enum DexGoals {
    struct Region: Equatable { let name: String; let range: ClosedRange<Int>; var total: Int { range.count }; var half: Int { (total + 1) / 2 } }
    /// The regions, whole (the user: the 19 legends 5.0 can't give yet count too — 하나 · 칼로스 wait for them).
    static let regions: [Region] = [Region(name: "관동", range: 1...151), Region(name: "성도", range: 152...251), Region(name: "호연", range: 252...386),
                                    Region(name: "신오", range: 387...493), Region(name: "하나", range: 494...649), Region(name: "칼로스", range: 650...721)]
    static func region(of dex: Int) -> Region? { regions.first { $0.range.contains(dex) } }
    /// The whole dex's steps (species caught) and what each mails.
    static let tiers: [(count: Int, gifts: [Gift])] = [
        (25, [.items(name: "이상한사탕", count: 3)]),
        (50, [.pickItem(items: Walk.mints)]),
        (100, [.items(name: "은색병뚜껑", count: 1), .bp(amount: 20)]),
        (150, [.items(name: "이상한사탕", count: 5)]),
        (200, [.items(name: "금색병뚜껑", count: 1)]),
        (300, [.pickItem(items: Walk.mints), .items(name: "은색병뚜껑", count: 2)]),
        (400, [.items(name: "금색병뚜껑", count: 1), .bp(amount: 50)]),
        (500, [.items(name: "이상한사탕", count: 10), .items(name: "은색병뚜껑", count: 3)]),
        (600, [.items(name: "금색병뚜껑", count: 2)]),
        (700, [.items(name: "금색병뚜껑", count: 2), .bp(amount: 100)]),
        (721, [.title(name: doctor)]),
    ]
    static let doctor = "포켓몬 박사"
    static let halfGifts: [Gift] = [.items(name: "이상한사탕", count: 5)], fullGifts: [Gift] = [.items(name: "금색병뚜껑", count: 1)]   // a region's 50 % · 100 %

    /// One goal: its key (kept once mailed: "전국:100", "관동:50", "관동:100"), its mail's title and line, its gifts.
    struct Goal: Equatable { let key, title, body: String; let gifts: [Gift]
        var label: String { let p = key.split(separator: ":"); return p[0] == "전국" ? "\(p[1])종" : p[1] == "100" ? "\(p[0]) 완성" : "\(p[0]) 50 %" }   // a list's word for it
    }
    static func goals() -> [Goal] {
        tiers.map { t in Goal(key: "전국:\(t.count)", title: t.count == 721 ? "도감 완성! \(t.count)종" : "도감 업적: \(t.count)종", body: "포켓몬을 \(t.count)종 잡았어요.", gifts: t.gifts) }
        + regions.flatMap { r in [
            Goal(key: "\(r.name):50", title: "도감 업적: \(r.name) 50 %", body: "\(r.name) 포켓몬을 \(r.half)종(절반) 잡았어요.", gifts: halfGifts),
            Goal(key: "\(r.name):100", title: "\(r.name) 도감 완성!", body: "\(r.name) 포켓몬 \(r.total)종을 모두 잡았어요. 이제 \(r.name) 포켓몬은 이로치 주사위를 한 번 더 굴려요.", gifts: fullGifts),
        ] }
    }
    /// How many of a region the save has caught (and as 이로치: the screen's "이로치 n/분모", no reward).
    static func caught(_ w: Walk, _ r: Region) -> Int { Set(w.owned ?? []).filter(r.range.contains).count }
    static func shinies(_ w: Walk, _ r: Region) -> Int { Set(w.shinyOwned ?? []).filter(r.range.contains).count }
    /// The goals the save has reached (content5 only), in the table's order.
    static func reached(_ w: Walk) -> [Goal] {
        guard Content.gen6 else { return [] }
        let all = Set(w.owned ?? []).count
        var keys = Set(tiers.filter { all >= $0.count }.map { "전국:\($0.count)" })
        for r in regions { let n = caught(w, r); if n >= r.half { keys.insert("\(r.name):50") }; if n >= r.total { keys.insert("\(r.name):100") } }
        return goals().filter { keys.contains($0.key) }
    }
    /// A region filled (content5): its species roll 이로치 once more at the radar and from an egg (not the raid, the shops, a pick or a trade).
    static func complete(_ w: Walk, _ r: Region) -> Bool { Content.gen6 && caught(w, r) >= r.total }
    static func bonus(_ dex: Int, _ w: Walk) -> Bool { region(of: dex).map { complete(w, $0) } ?? false }
    /// Several goals at once (the switch-on day's catch-up, or two in one act): one mail of everything but the picks (one 고르기 a mail), merged.
    static func merged(_ gs: [Goal]) -> (gifts: [Gift], picks: [(goal: Goal, gift: Gift)]) {
        var items: [String: Int] = [:], order: [String] = [], bp = 0, rest: [Gift] = [], picks: [(goal: Goal, gift: Gift)] = []
        for g in gs { for x in g.gifts {
            switch x {
            case .items(let n, let c): if items[n] == nil { order.append(n) }; items[n, default: 0] += c
            case .bp(let a): bp += a
            case .pickItem, .pickLegend: picks.append((g, x))
            default: rest.append(x)
            }
        } }
        return (order.map { .items(name: $0, count: items[$0]!) } + (bp > 0 ? [.bp(amount: bp)] : []) + rest, picks)
    }
}
