import Foundation
// What each bag item does.

/// What a bag item does here. The real walker only ferried items to the game; this app has no game, so they get jobs of their own.
enum ItemKind: Equatable {
    case heal(Int)                 // battle: restores this many HP (999 = all)
    case battle(ItemUse)           // battle: status cures, 회복약, PP, X items
    case revive(Int)               // used by itself when the last one faints: back up with this % of max HP
    case candy                     // 이상한사탕: +1 level
    case vitamin(Int, Int)         // fed: that stat's EVs ± 10 (영양제 up to 100, 노력치 내리는 열매 down)
    case evReset                   // 순백떡 (SV's Fresh Start Mochi): every EV back to 0
    case bottleCap(Bool)           // 대단한 특훈 from Lv.50: 은색병뚜껑 one IV to 31, 금색병뚜껑 (true) all six
    case berry                     // fed: +500 friendship steps
    case evolution                 // stones and held items
    case sell(Int)                 // watts at the exchange

    /// One line on what it does (the bag list, the shops).
    var summary: String {
        switch self {
        case .heal(let n): "배틀 HP +\(n)"; case .revive(let n): "쓰러지면 HP \(n)%로 부활";
        case .candy: "레벨 +1"; case .evReset: "노력치 전부 0"; case .bottleCap(let gold): gold ? "특훈: 모든 개체값 → 31 (Lv.50부터)" : "특훈: 개체값 하나 → 31 (Lv.50부터)"
        case .vitamin(let k, let d): "\(["HP", "공격", "방어", "특공", "특방", "스피드"][k]) 노력치 \(d > 0 ? "+" : "−")10"; case .berry: "친밀도 +500걸음"; case .evolution: "진화 도구"; case .sell(let p): "팔면 \(p)W"
        case .battle(let u):
            switch u { case .cure(let s, let conf): s.count >= 5 ? "배틀 상태이상 전부 회복" : s.isEmpty && conf ? "배틀 혼란 회복" : "배틀 " + s.map(\.badge).joined(separator: "·") + " 회복"
            case .restore: "배틀 HP·상태 전부 회복"; case .pp(let n, let all): (all ? "모든 기술" : "기술 하나") + " PP " + (n >= 99 ? "전부" : "+\(n)")
            case .x(let k, _): "배틀 \(statNames[k]) +1"; case .guardSpec: "배틀 능력 저하 막기 (5턴)"; case .direHit: "배틀 급소율 +"; case .heal: "" }
        }
    }
    static func of(_ i: String) -> ItemKind {
        let all: [Status] = [.poison, .burn, .paralysis, .sleep, .freeze]
        let use: [String: ItemUse] = ["해독제": .cure([.poison], confusion: false), "화상치료제": .cure([.burn], confusion: false), "마비치료제": .cure([.paralysis], confusion: false),
            "잠깨는약": .cure([.sleep], confusion: false), "얼음상태치료제": .cure([.freeze], confusion: false), "만병통치제": .cure(all, confusion: true), "숲의양갱": .cure(all, confusion: true),
            "용암전병": .cure(all, confusion: true), "버치열매": .cure([.paralysis], confusion: false), "유루열매": .cure([.sleep], confusion: false), "복슝열매": .cure([.poison], confusion: false),
            "복분열매": .cure([.burn], confusion: false), "배리열매": .cure([.freeze], confusion: false), "시몬열매": .cure([], confusion: true), "리샘열매": .cure(all, confusion: true),
            "회복약": .restore, "PP에이드": .pp(10, all: false), "PP회복": .pp(99, all: false), "PP에이더": .pp(10, all: true), "PP맥스": .pp(99, all: true),
            "플러스파워": .x(1, 1), "디펜드업": .x(2, 1), "스페셜업": .x(3, 1), "스페셜가드": .x(4, 1), "스피드업": .x(5, 1), "잘-맞히기": .x(6, 1), "크리티컬커터": .direHit, "이펙트가드": .guardSpec]
        if let u = use[i] { return .battle(u) }
        if let k = ["맥스업", "타우린", "사포닌", "리보플라빈", "키토산", "알칼로이드"].firstIndex(of: i) { return .vitamin(k, 10) }
        if let k = ["유석열매", "시마열매", "파비열매", "로매열매", "또뽀열매", "토망열매"].firstIndex(of: i) { return .vitamin(k, -10) }
        if i == "순백떡" { return .evReset }
        if i == "은색병뚜껑" || i == "금색병뚜껑" { return .bottleCap(i == "금색병뚜껑") }
        let heal = ["상처약": 20, "좋은상처약": 50, "고급상처약": 200, "풀회복약": 999, "오랭열매": 10, "자뭉열매": 30, "맛있는물": 50, "미네랄사이다": 60,
                    "후르츠밀크": 80, "튼튼밀크": 100, "힘의가루": 50, "힘의뿌리": 200]   // Gen IV amounts
        if let n = heal[i] { return .heal(n) }
        if i == "기력의조각" { return .revive(50) }
        if i == "부활초" { return .revive(100) }
        if i == "하이퍼볼" { return .sell(100) }                                                   // (1.10: every throw is free, the ball by chance: Walk.rollBall)
        if i.hasSuffix("볼") { return .sell(40) }                                                  // 슈퍼볼, 힐볼 the companion finds …
        if i == "이상한사탕" { return .candy }
        if evolutions.contains(where: { $0.item == i }) { return .evolution }
        if i.hasSuffix("열매") { return .berry }
        let price = ["금구슬": 100, "큰진주": 80, "별의조각": 60, "하트비늘": 30, "진주": 30, "큰버섯": 30, "별의모래": 20, "작은버섯": 10]
        if let p = price[i] { return .sell(p) }
        if i.hasPrefix("기술머신") { return .sell(50) }
        if i == "포인트업" { return .sell(20) }
        return .sell(10)
    }
}
