// docs/plans/18 §5 · §6 (5.0, content5): a species' other forms (tools/gen.py's `monForms`, as of ORAS). Mon.form picks one (1...; nil or 0 = the
// species itself). What a form doesn't list is the species': a Mega's HP, 로토무's level-up moves, an 안농's everything but its picture.

enum FormKind {
    case look      // the picture only (안농 B, 비비용's patterns, 깝질무 동쪽바다 ...)
    case stored    // kept on the Mon (로토무 5, 테오키스 3, 영물폼, 큐레무 블랙 · 화이트, 냐오닉스 ♀ ...)
    case battle    // for a fight only, back after it (메로엣타 스텝폼, 킬가르도 블레이드폼, 달마모드, 캐스퐁 ...)
    case mega      // a held stone, once a fight (메가레쿠쟈: 화룡점정)
    case primal    // 원시회귀: 쪽빛구슬 · 주홍구슬, on coming out
}

struct MonForm {
    let name: String; let kind: FormKind
    var types: [String]? = nil, stats: [Int]? = nil, abilities: [Int]? = nil, hidden: Int? = nil, weight: Double? = nil
    var item: String? = nil              // a Mega's stone, a primal's orb
    var learnset: [Int]? = nil           // its own level-up moves (테오키스, 큐레무, 냐오닉스 ♀ ...), as `learnsets`
}

enum Forms {
    /// A species' form `n` (1...), if it has one.
    static func of(_ dex: Int, _ n: Int?) -> MonForm? { guard let n, n > 0, let fs = monForms[dex], n <= fs.count else { return nil }; return fs[n - 1] }
    /// The Mega (or primal) form a species turns into holding `item`, and its number.
    static func mega(_ dex: Int, holding item: String?) -> (n: Int, form: MonForm)? {
        guard let item, let fs = monForms[dex], let i = fs.firstIndex(where: { ($0.kind == .mega || $0.kind == .primal) && $0.item == item }) else { return nil }
        return (i + 1, fs[i])
    }
    /// Forms by the Pokémon's sex: 탱그릴 · 탱탱겔 · 화염레오 (a look), 냐오닉스 (its own moves and hidden ability too).
    static let genderForm: [Int: Int] = [592: 1, 593: 1, 668: 1, 678: 1]
    /// Forms a wild one gets at random: 안농's letter, 깝질무 · 트리토돈's sea, 바스라오's stripe, 비비용's pattern, 플라베베's flower, 호바귀's size.
    static let randomForms: Set<Int> = [201, 422, 423, 550, 666, 669, 670, 671, 710, 711]
    /// A newly met one's form (Mon.wild, content5 only).
    static func wildForm<R: RandomNumberGenerator>(_ dex: Int, female: Bool, _ r: inout R) -> Int? {
        if let g = genderForm[dex] { return female ? g : nil }
        guard randomForms.contains(dex), let n = monForms[dex]?.count else { return nil }
        let k = Int.random(in: 0...n, using: &r); return k == 0 ? nil : k
    }
    /// The radar's find, by where and when it's met (0 = the species' own; nil = no such rule): 사철록 · 바라철록 by the walk's season,
    /// 도롱충이 · 도롱마담 by the course (cave · mountain 모래땅, town 슈레, else 초목), and the sex forms again (its sex is the slot's).
    static func placeForm(_ m: Mon, season: Season, art: Art) -> Int? {
        if let g = genderForm[m.dex] { return m.female ? g : 0 }
        switch m.dex {
        case 585, 586: return season.rawValue
        case 412, 413: return art == .cave || art == .mountain ? 1 : art == .town ? 2 : 0
        default: return nil
        }
    }
    /// The form it has after evolving into `to`: the same one where both have it (도롱마담 트리토돈 바라철록 플라엣테 플라제스 펌킨인),
    /// the sex form, 비비용's pattern (fixed by who it is).
    static func evolved(_ m: Mon, into to: Int) -> Int? {
        if let g = genderForm[to] { return m.female ? g : nil }
        if to == 666 { let k = (m.uid ?? m.walked ?? 0) % 20; return k == 0 ? nil : k }
        guard let f = m.form, f > 0, let n = monForms[to]?.count, f <= n else { return nil }
        return f
    }
    /// Whose stone (or orb) it is.
    static func stoneFor(_ item: String) -> String? { monForms.first { $0.value.contains { $0.item == item } }.map { monNames[$0.key] } }
    /// Every Mega stone and primal orb (47 + 2): what the Mega raid gives.
    static let stones: [String] = monForms.keys.sorted().flatMap { d in monForms[d]!.compactMap { $0.kind == .mega || $0.kind == .primal ? $0.item : nil } }
}

// MARK: - forms changed by hand (docs/plans/18 §5, §5.1)
extension Walk {
    /// Each 로토무 form's own move: 히트 오버히트, 워시 하이드로펌프, 프로스트 눈보라, 스핀 에어슬래시, 커트 리프스톰.
    static let rotomMoves = [315, 56, 59, 403, 437]
    /// 로토무카탈로그: the 로토무 at ref changes form (nil = back to its own); its old form's move becomes the new one's (or goes; 전기쇼크 if
    /// that leaves nothing), a new one added in a free slot or the last.
    mutating func rotomForm(_ ref: Int, _ form: Int?) -> String? {
        guard Content.gen6, (bag + items).contains("로토무카탈로그") else { return "로토무카탈로그가\n없어요" }
        guard var m = mon(ref), m.dex == 479, form.map({ (1...5).contains($0) }) ?? true, m.form != form else { return "모습을 바꿀 수\n없어요" }
        let old = m.form.map { Walk.rotomMoves[$0 - 1] }, new = form.map { Walk.rotomMoves[$0 - 1] }
        var ms = m.moves
        if let o = old, let i = ms.firstIndex(of: o) { if let n = new, !ms.contains(n) { ms[i] = n } else { ms.remove(at: i) } }
        else if let n = new, !ms.contains(n) { if ms.count < 4 { ms.append(n) } else { ms[3] = n } }
        if ms.isEmpty { ms = [84] }
        m.form = form; m.known = ms; setMon(ref, m); return nil
    }
    /// 큐레무 합체 (§5.1): the 큐레무 at ref takes in the 레시라무 (화이트큐레무) or 제크로무 (블랙큐레무) at other — from the walker or the box, not
    /// the companion — which waits inside it (Mon.fused) until 분리; 얼어붙은세계 becomes 콜드플레어 / 프리즈볼트. 유전자쐐기 is kept.
    mutating func fuse(_ ref: Int, with other: Int) -> String? {
        guard Content.gen6, (bag + items).contains("유전자쐐기") else { return "유전자쐐기가\n없어요" }
        guard var k = mon(ref), k.dex == 646, k.fused == nil, other != -1, ref != other, let p = mon(other), [643, 644].contains(p.dex), p.fused == nil else { return "합체할 수\n없어요" }
        let white = p.dex == 643
        k.form = white ? 2 : 1; k.known = k.moves.map { $0 == 549 ? (white ? 554 : 553) : $0 }; k.fused = [p]
        setMon(ref, k)
        if other <= -2 { caught.remove(at: -2 - other) } else { box.remove(at: other) }
        return nil
    }
    /// 5.1 (docs/plans/19): the key items that change a form by hand (MonOp.form) — 그라시데아꽃 쉐이미 ↔ 스카이폼, 비추는거울 토네로스 · 볼트로스 ·
    /// 랜드로스 ↔ 영물폼, 굴레의항아리 후파 ↔ 굴레를 벗어난 후파 (이차원홀 ↔ 이차원러시, as the games). Kept when used; a form stays (no night or ice back).
    static let formItems: [String: Set<Int>] = ["그라시데아꽃": [492], "비추는거울": [641, 642, 645], "굴레의항아리": [720]]
    static let formMoves: [Int: (from: Int, to: Int)] = [720: (593, 621)]
    mutating func itemForm(_ ref: Int, _ item: String, _ form: Int?) -> String? {
        guard Content.v51, let dexes = Walk.formItems[item] else { return "모습을 바꾸는\n도구가 아니에요" }
        guard (bag + items).contains(item) else { return josa(item, "이", "가") + "\n없어요" }
        guard var m = mon(ref), dexes.contains(m.dex), form.map({ $0 == 1 && Forms.of(m.dex, 1) != nil }) ?? true, m.form != form else { return "모습을 바꿀 수\n없어요" }
        if let (a, b) = Walk.formMoves[m.dex] { m.known = m.moves.map { form == nil ? ($0 == b ? a : $0) : ($0 == a ? b : $0) } }
        m.form = form; setMon(ref, m); return nil
    }
    /// 분리: the one inside back to the box; 콜드플레어 / 프리즈볼트 back to 얼어붙은세계.
    mutating func unfuse(_ ref: Int) -> String? {
        guard var k = mon(ref), let p = k.fused?.first else { return "합체하지 않았어요" }
        k.form = nil; k.known = k.moves.map { [553, 554].contains($0) ? 549 : $0 }; k.fused = nil
        setMon(ref, k); box.append(p); return nil
    }
}
