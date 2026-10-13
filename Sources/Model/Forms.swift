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
    /// Every Mega stone and primal orb (47 + 2): what the Mega raid gives.
    static let stones: [String] = monForms.keys.sorted().flatMap { d in monForms[d]!.compactMap { $0.kind == .mega || $0.kind == .primal ? $0.item : nil } }
}
