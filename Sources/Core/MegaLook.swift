import Foundation
// 5.2 (the user via 회사 10-23: "메가진화가 있어도 배틀에서 뒷모습 밖에 못보잖아 … 홈화면 같은데서 볼수 있으면", "메가 모습은 괜찮을것같네", "5. ㅇㅇ
// 괜찮아"; lcd-mockups docs/mockups/v5.2 mega-*): a Mega's front. 홈: the companion holding its own stone (an orb: its primal; 레쿠쟈 knowing
// 화룡점정) shows as its Mega — the big sticker and the card's picture — a purple 메가 pill by its name turns it off and on (setting
// ui.megaHome, on at first). A Pokémon's page: 메가 모습 보기 (a species with a Mega or primal form, its stone held or not) — its front big on the
// LCD, its types and ability, its base stats against the species' (what it gains in purple), the stone (held · in the bag · from the Mega raid),
// 홈's switch for the companion, ▶ the other (X · Y). The 도감's entry already turns its forms (5.0).

/// 메가 모습 보기: the Mega's name and kind, types, ability, the species' and its base stats, its stone and where it is, 홈's switch, the other.
struct MegaLookModel: Equatable {
    var name, kind: String; var types: [String]; var ability, abilityNote: String
    var base, mega: [Int]
    var stoneLabel, stone, stoneNote: String; var stoneState: Int     // 0 none (where to get it), 1 in the bag, 2 held (or 화룡점정 known)
    var home: Bool? = nil, homeNote: String? = nil                     // the companion holding it: 홈's switch; else (the companion) what it'd take
    var next: String? = nil                                            // the other Mega (X · Y), its button
}

extension Walker {
    /// A species' Mega (and primal) forms, by number.
    static func megaForms(_ dex: Int) -> [Int] { (monForms[dex] ?? []).enumerated().compactMap { $0.element.kind == .mega || $0.element.kind == .primal ? $0.offset + 1 : nil } }
    /// The Mega it shows: holding its own stone (or orb); 레쿠쟈 knowing 화룡점정.
    func megaLook(_ m: Mon) -> Int? {
        guard Content.gen6 else { return nil }
        if m.dex == 384 { return m.moves.contains(620) ? 1 : nil }
        return Forms.mega(m.dex, holding: m.item)?.n
    }
    /// The companion as 홈 shows it.
    var homeLook: Mon { var m = state.companion; if megaHome, let n = megaLook(m) { m.form = n }; return m }
    /// 홈's 메가 pill: on → off → on.
    func toggleMegaHome() { megaHome.toggle(); rimDex = -1; host?.redraw(.all) }

    func megaLookModel(_ m: Mon, _ n: Int, ref: Int) -> MegaLookModel? {
        guard let f = Forms.of(m.dex, n) else { return nil }
        var mm = m; mm.form = n
        let held = megaLook(m) == n, stone = m.dex == 384 ? "화룡점정" : f.item ?? "", inBag = !held && state.count(stone) > 0
        var x = MegaLookModel(name: f.name, kind: f.kind == .primal ? "원시회귀" : "메가진화", types: mm.typing, ability: mm.abilityName, abilityNote: abilityDescs[mm.abilityID] ?? "",
                              base: baseStats[m.dex], mega: mm.baseStat, stoneLabel: m.dex == 384 ? "기술" : f.kind == .primal ? "구슬" : "스톤", stone: stone,
                              stoneNote: held ? (m.dex == 384 ? "알고 있어요 ✓" : "지니고 있어요 ✓") : m.dex == 384 ? "레쿠쟈 원정을 끝내면 배워요" : inBag ? "가방에 있어요" : f.kind == .primal ? "아직 없어요" : "메가 레이드에서 모아요",
                              stoneState: held ? 2 : inBag ? 1 : 0)
        if ref == -1 { if held { x.home = megaHome } else { x.homeNote = m.dex == 384 ? "화룡점정을 알면 홈에서도 메가 모습" : "스톤을 지니면 홈에서도 메가 모습" } }
        x.next = Walker.megaForms(m.dex).first { $0 != n }.flatMap { Forms.of(m.dex, $0)?.name }.map { $0 + " ▶" }
        return x
    }
    /// ● (or the button) back to its page; ◀ ▶ the other Mega (X · Y).
    func megaLookPress(_ k: Int, _ ref: Int) {
        guard let m = state.mon(ref), let n = megaLookForm else { return }
        let forms = Walker.megaForms(m.dex)
        if k != 1 { if forms.count > 1, let i = forms.firstIndex(of: n) { megaLookForm = forms[(i + (k == 0 ? forms.count - 1 : 1)) % forms.count] }; return }
        megaLookForm = nil
    }
}
