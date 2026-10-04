import Foundation
// Held items (docs/plans/13 ⑤): Gen IV's, by their Korean names. What each does in battle is in Battle/Holding.swift; here the tables,
// the one-line notes, and giving / taking one back.

enum Held {
    /// ×1.2 to that type's moves: the type items, the incenses, the plates (on 아르세우스 the plate is also its type, and 심판의뭉치's).
    static let typeBoost: [String: String] = [
        "은빛가루": "bug", "금속코트": "steel", "부드러운모래": "ground", "딱딱한돌": "rock", "기적의씨": "grass", "검은안경": "dark", "검은띠": "fighting",
        "자석": "electric", "신비의물방울": "water", "예리한부리": "flying", "독바늘": "poison", "녹지않는얼음": "ice", "저주의부적": "ghost", "휘어진스푼": "psychic",
        "목탄": "fire", "용의이빨": "dragon", "실크스카프": "normal", "바닷물향로": "water", "괴상한향로": "psychic", "암석향로": "rock", "잔물결향로": "water", "꽃향로": "grass",
    ].merging(plates) { a, _ in a }
    static let plates: [String: String] = [
        "불구슬플레이트": "fire", "물방울플레이트": "water", "우레플레이트": "electric", "초록플레이트": "grass", "고드름플레이트": "ice", "주먹플레이트": "fighting",
        "맹독플레이트": "poison", "대지플레이트": "ground", "푸른하늘플레이트": "flying", "이상한플레이트": "psychic", "비단벌레플레이트": "bug", "암석플레이트": "rock",
        "원령플레이트": "ghost", "용의플레이트": "dragon", "공포플레이트": "dark", "강철플레이트": "steel",
    ]
    /// Halve one super-effective hit of that type (카리열매: any Normal hit), then they're eaten.
    static let resist: [String: String] = [
        "오카열매": "fire", "꼬시개열매": "water", "초나열매": "electric", "린드열매": "grass", "플카열매": "ice", "로플열매": "fighting", "으름열매": "poison",
        "슈캐열매": "ground", "바코열매": "flying", "야파열매": "psychic", "리체열매": "bug", "루미열매": "rock", "수불열매": "ghost", "하반열매": "dragon",
        "마코열매": "dark", "바리비열매": "steel", "카리열매": "normal",
    ]
    /// At 1/4 HP (먹보: 1/2): +1 to that stat. 랑사 = 급소율, 스타 = a random one +2, 미클 = the next move's accuracy, 애슈 = moves first once.
    static let pinch: [String: Int] = ["치리열매": 1, "용아열매": 2, "캄라열매": 5, "야타비열매": 3, "규살열매": 4]
    /// At 1/2 HP: 1/8 back; a nature that lowers this stat dislikes the taste (혼란).
    static let flavor: [String: Int] = ["무화열매": 1, "위키열매": 3, "마고열매": 5, "아바열매": 4, "파야열매": 2]
    /// The status berries: what each cures (confusion: 시몬 · 리샘).
    static let cures: [String: (sts: [Status], confusion: Bool)] = [
        "버치열매": ([.paralysis], false), "유루열매": ([.sleep], false), "복슝열매": ([.poison, .toxic], false), "복분열매": ([.burn], false),
        "배리열매": ([.freeze], false), "시몬열매": ([], true), "리샘열매": ([.poison, .toxic, .burn, .paralysis, .sleep, .freeze], true),
    ]
    /// 파워 계열: +4 of that stat's EVs a KO (and half speed in battle).
    static let power: [String: Int] = ["파워웨이트": 0, "파워리스트": 1, "파워벨트": 2, "파워렌즈": 3, "파워밴드": 4, "파워앵클릿": 5]
    /// Species items: who they're for.
    static let species: [String: Set<Int>] = ["전기구슬": [25], "굵은뼈": [104, 105], "심해의이빨": [366], "심해의비늘": [366], "금속파우더": [132], "스피드파우더": [132],
                                         "마음의물방울": [380, 381], "금강옥": [483], "백옥": [484], "백금옥": [487], "럭키펀치": [113], "대파": [83]]
    /// 내던지기's power (berries 10); nil = can't be thrown.
    static func fling(_ i: String) -> Int? {
        if i.hasSuffix("열매") { return 10 }
        if plates[i] != nil { return 90 }
        return ["금강옥": 60, "백옥": 60, "백금옥": 60, "반짝가루": 10, "하양허브": 10, "교정깁스": 60, "선제공격손톱": 80, "평온의방울": 10, "멘탈허브": 10, "구애머리띠": 10,
                "왕의징표석": 30, "은빛가루": 10, "부적금화": 30, "순결의부적": 30, "마음의물방울": 30, "심해의이빨": 90, "심해의비늘": 30, "연막탄": 30, "변함없는돌": 30,
                "기합의머리띠": 10, "행복의알": 30, "초점렌즈": 30, "금속코트": 30, "먹다남은음식": 10, "용의비늘": 30, "전기구슬": 30, "부드러운모래": 10, "딱딱한돌": 100,
                "기적의씨": 30, "검은안경": 30, "검은띠": 30, "자석": 30, "신비의물방울": 30, "예리한부리": 50, "독바늘": 70, "녹지않는얼음": 30, "저주의부적": 30,
                "휘어진스푼": 30, "목탄": 30, "용의이빨": 70, "실크스카프": 10, "업그레이드": 30, "조개껍질방울": 30, "바닷물향로": 10, "무사태평향로": 10, "럭키펀치": 40,
                "금속파우더": 10, "굵은뼈": 90, "대파": 60, "광각렌즈": 10, "힘의머리띠": 10, "박식안경": 10, "달인의띠": 10, "빛의점토": 30, "생명의구슬": 30,
                "파워풀허브": 10, "맹독구슬": 30, "화염구슬": 30, "스피드파우더": 10, "기합의띠": 10, "포커스렌즈": 10, "메트로놈": 30, "검은철구": 130, "느림보꼬리": 10,
                "빨간실": 10, "검은오물": 30, "차가운바위": 40, "보송보송바위": 10, "뜨거운바위": 60, "축축한바위": 60, "끈기갈고리손톱": 90, "구애스카프": 10,
                "끈적끈적바늘": 80, "파워리스트": 70, "파워벨트": 70, "파워렌즈": 70, "파워밴드": 70, "파워앵클릿": 70, "파워웨이트": 70, "아름다운허물": 10, "큰뿌리": 10,
                "구애안경": 10, "괴상한향로": 10, "암석향로": 10, "만복향로": 10, "잔물결향로": 10, "꽃향로": 10, "행운의향로": 10, "순결의향로": 10, "프로텍터": 80,
                "에레키부스터": 80, "마그마부스터": 80, "괴상한패치": 50, "영계의천": 10, "예리한손톱": 80, "예리한이빨": 30, "동글동글돌": 80][i]
    }
    /// 자연의은혜: the berry's type and power (Gen IV's).
    static let gift: [String: (type: String, power: Int)] = [
        "버치열매": ("fire", 60), "유루열매": ("water", 60), "복슝열매": ("electric", 60), "복분열매": ("grass", 60), "배리열매": ("ice", 60), "과사열매": ("fighting", 60),
        "오랭열매": ("poison", 60), "시몬열매": ("ground", 60), "리샘열매": ("flying", 60), "자뭉열매": ("psychic", 60), "무화열매": ("bug", 60), "위키열매": ("rock", 60),
        "마고열매": ("ghost", 60), "아바열매": ("dragon", 60), "파야열매": ("dark", 60), "라즈열매": ("steel", 60), "블리열매": ("fire", 70), "나나열매": ("water", 70),
        "서배열매": ("electric", 70), "파인열매": ("grass", 70), "유석열매": ("ice", 70), "시마열매": ("fighting", 70), "파비열매": ("poison", 70), "로매열매": ("ground", 70),
        "또뽀열매": ("flying", 70), "토망열매": ("psychic", 70), "수숙열매": ("bug", 70), "고스티열매": ("rock", 70), "라부탐열매": ("ghost", 70), "노멜열매": ("dragon", 70),
        "메호키열매": ("dark", 70), "자야열매": ("steel", 70), "슈박열매": ("fire", 80), "두리열매": ("water", 80), "루베열매": ("electric", 80), "오카열매": ("fire", 60),
        "꼬시개열매": ("water", 60), "초나열매": ("electric", 60), "린드열매": ("grass", 60), "플카열매": ("ice", 60), "로플열매": ("fighting", 60), "으름열매": ("poison", 60),
        "슈캐열매": ("ground", 60), "바코열매": ("flying", 60), "야파열매": ("psychic", 60), "리체열매": ("bug", 60), "루미열매": ("rock", 60), "수불열매": ("ghost", 60),
        "하반열매": ("dragon", 60), "마코열매": ("dark", 60), "바리비열매": ("steel", 60), "카리열매": ("normal", 60), "치리열매": ("grass", 80), "용아열매": ("ice", 80),
        "캄라열매": ("fighting", 80), "야타비열매": ("poison", 80), "규살열매": ("ground", 80), "랑사열매": ("flying", 80), "스타열매": ("psychic", 80), "의문열매": ("bug", 80),
        "미클열매": ("rock", 80), "애슈열매": ("ghost", 80), "자보열매": ("dragon", 80), "애터열매": ("dark", 80),
    ]
    /// The trade / level evolutions that take a held item (they can still be used from the bag, as before).
    static let evolution: Set<String> = ["왕의징표석", "금속코트", "용의비늘", "업그레이드", "프로텍터", "에레키부스터", "마그마부스터", "괴상한패치", "영계의천",
                                        "심해의이빨", "심해의비늘", "동글동글돌", "예리한손톱", "예리한이빨"]

    /// One line on what it does when held (the bag, the shops, a Pokémon's page); nil = not something to hold.
    static func summary(_ i: String) -> String? {
        if let t = plates[i] { return "\(typeKo[t] ?? t) 기술 위력 1.2배 · 아르세우스는 \(typeKo[t] ?? t) 타입으로" }
        if let t = typeBoost[i] { return "\(typeKo[t] ?? t) 기술 위력 1.2배" }
        if let t = resist[i] { return t == "normal" ? "노말 기술 한 번 위력 반감" : "효과가 굉장한 \(typeKo[t] ?? t) 기술 한 번 위력 반감" }
        if let k = pinch[i] { return "HP 1/4 이하에서 \(statNames[k]) +1" }
        if let k = flavor[i] { return "HP 1/2 이하에서 HP 1/8 회복 (\(statNames[k]) 내리는 성격은 혼란)" }
        if let c = cures[i] { return c.sts.count >= 5 ? "상태이상·혼란을 바로 회복" : c.sts.isEmpty ? "혼란을 바로 회복" : josa(c.sts[0].badge, "을", "를") + " 바로 회복" }
        if let k = power[i] { return "\(["HP", "공격", "방어", "특공", "특방", "스피드"][k]) 노력치 +4 · 배틀 스피드 절반" }
        let notes = [
            "구애머리띠": "공격 1.5배 · 처음 고른 기술만", "구애안경": "특수공격 1.5배 · 처음 고른 기술만", "구애스카프": "스피드 1.5배 · 처음 고른 기술만",
            "생명의구슬": "기술 위력 1.3배 · 공격할 때마다 HP 1/10 깎임", "달인의띠": "효과가 굉장한 기술 1.2배", "힘의머리띠": "물리 기술 1.1배", "박식안경": "특수 기술 1.1배",
            "메트로놈": "같은 기술을 이어 쓰면 위력 최대 2배", "먹다남은음식": "매 턴 HP 1/16 회복", "검은오물": "독 타입은 매 턴 HP 1/16 회복 · 다른 타입은 1/8 깎임",
            "조개껍질방울": "준 데미지의 1/8 회복", "기합의띠": "HP가 가득할 때 한 번 HP 1로 버팀", "기합의머리띠": "가끔 HP 1로 버팀",
            "선제공격손톱": "가끔 먼저 행동", "느림보꼬리": "항상 나중에 행동", "만복향로": "항상 나중에 행동", "초점렌즈": "급소율 +1", "예리한손톱": "급소율 +1 · 진화 도구",
            "왕의징표석": "공격하면 가끔 풀죽게 함 · 진화 도구", "예리한이빨": "공격하면 가끔 풀죽게 함 · 진화 도구",
            "광각렌즈": "명중률 1.1배", "포커스렌즈": "상대 다음에 움직이면 명중률 1.2배", "반짝가루": "상대 명중률 0.9배", "무사태평향로": "상대 명중률 0.9배",
            "하양허브": "떨어진 능력을 한 번 되돌림", "멘탈허브": "헤롱헤롱을 한 번 풂", "파워풀허브": "모으는 기술을 한 번 바로", "빨간실": "헤롱헤롱해지면 상대도",
            "빛의점토": "리플렉터·빛의장막 8턴", "축축한바위": "비바라기 8턴", "뜨거운바위": "쾌청 8턴", "보송보송바위": "모래바람 8턴", "차가운바위": "싸라기눈 8턴",
            "끈기갈고리손톱": "조이기 같은 기술이 5턴", "큰뿌리": "흡수하는 기술의 회복 1.3배", "아름다운허물": "언제든 교체할 수 있음", "연막탄": "야생 배틀에서 꼭 도망침",
            "검은철구": "스피드 절반 · 땅 기술에 맞음", "끈적끈적바늘": "매 턴 HP 1/8 깎임 · 접촉하면 옮겨 감", "맹독구슬": "턴이 끝나면 맹독", "화염구슬": "턴이 끝나면 화상",
            "교정깁스": "얻는 노력치 2배 · 배틀 스피드 절반", "행복의알": "배틀 경험치 1.5배", "학습장치": "배틀에 안 나가도 경험치를 나눠 받음",
            "평온의방울": "친밀도가 1.5배 빨리 오름", "변함없는돌": "진화하지 않음", "부적금화": "연쇄 보상 W 2배", "행운의향로": "연쇄 보상 W 2배",
            "순결의부적": "효과 없음 (이 게임엔 야생 조우가 없어요)", "순결의향로": "효과 없음 (이 게임엔 야생 조우가 없어요)",
            "전기구슬": "피카츄: 공격·특수공격 2배", "굵은뼈": "탕구리·텅구리: 공격 2배", "심해의이빨": "진주몽: 특수공격 2배 · 진화 도구",
            "심해의비늘": "진주몽: 특수방어 2배 · 진화 도구", "금속파우더": "메타몽: 방어 2배", "스피드파우더": "메타몽: 스피드 2배",
            "마음의물방울": "라티아스·라티오스: 특수공격·특수방어 1.5배", "금강옥": "디아루가: 드래곤·강철 기술 1.2배", "백옥": "펄기아: 드래곤·물 기술 1.2배",
            "백금옥": "기라티나: 드래곤·고스트 기술 1.2배", "럭키펀치": "럭키: 급소율 +2", "대파": "파오리: 급소율 +2",
            "과사열매": "PP가 0이 된 기술 PP 10 회복", "오랭열매": "HP 1/2 이하에서 HP 10 회복", "자뭉열매": "HP 1/2 이하에서 HP 1/4 회복",
            "랑사열매": "HP 1/4 이하에서 급소율 +2", "스타열매": "HP 1/4 이하에서 능력 하나 +2", "미클열매": "HP 1/4 이하에서 다음 기술 명중률 1.2배",
            "애슈열매": "HP 1/4 이하에서 한 번 먼저 행동", "의문열매": "효과가 굉장한 기술을 맞으면 HP 1/4 회복",
            "자보열매": "물리 기술을 맞으면 상대 HP 1/8 깎음", "애터열매": "특수 기술을 맞으면 상대 HP 1/8 깎음",
        ]
        if let n = notes[i] { return n }
        if evolution.contains(i) { return "진화 도구 (지니고 교환)" }
        if let g = gift[i] { return "자연의은혜: \(typeKo[g.type] ?? g.type) \(g.power)" }
        return nil
    }
    static func holdable(_ i: String) -> Bool { summary(i) != nil }
    /// The ones that do nothing but be held (ItemKind.held: the bag never sells or feeds them).
    static func only(_ i: String) -> Bool { holdable(i) && !i.hasSuffix("열매") && !evolution.contains(i) }
}

extension Walk {
    /// 지니게 하기 (docs/plans/13 ⑤): item from the bag onto the one at ref (what it held goes back), or nil = take it back.
    mutating func hold(_ item: String?, _ ref: Int) -> Bool {
        guard var m = mon(ref) else { return false }
        if let i = item {
            guard Held.holdable(i), m.item != i, take(i) else { return false }
            if let old = m.item { bag.append(old) }
            m.item = i
        } else {
            guard let old = m.item else { return false }
            bag.append(old); m.item = nil
        }
        setMon(ref, m); return true
    }
}
