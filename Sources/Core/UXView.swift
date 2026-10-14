import Foundation
// 5.0's quality pass, the panel's ease (the user: "하단패널 내가 원한건 디자인 뿐만 아니라 편의성도 개선했으면 했던건데") — a prototype behind
// uxV2 (the shots' UX_V2=1), for the user to pick from: fewer clicks for what's done most. 홈's sheet with quick buttons (포켓 레이더 · 포켓몬
// · 도구 · 우편함, its red dot) and its rows opening their pages; the menu back on the tile last used, each tile's number key; the box's pick
// with its actions under the grid (함께 걷기 · 도구 주기 · 자세히) — no second click for its page; the shop's amount 최대; the 도감's
// 찾기 (a name or a number). Docs: lcd-mockups docs/mockups/ux-5.0.

@MainActor var uxV2 = false

extension Walker {
    /// 홈's quick buttons: a feature each, its red dot (something waits there).
    static let quick = ["포켓 레이더", "포켓몬", "도구", "우편함"]
    /// 홈's rows → the page each opens (the status sheet's 알 · 배틀 타워 · 도감 · 레이드 · 친구).
    static let homeLinks: [String: String] = ["알": "트레이너 카드", "배틀 타워": "배틀 타워", "도감": "도감", "레이드": "레이드", "친구": "친구"]
    func quickOpen(_ name: String) {
        guard !frozen, waiting == nil else { return }
        lastInput = Date(); host?.redraw(.all)
        switch name {
        case "도구": screen = .items(0)
        case "트레이너 카드": screen = .card(2)                                                       // (알: its page)
        default: if menuItems.contains(name) { open(name) }
        }
    }
    /// The shop's amount typed (1 … what can be bought).
    func shopAmount() {
        guard case .shop(let bp, let sel, .some) = screen, let w = wares(bp)[safe: sel], let h = host else { return }
        let most = max(1, state.canBuy(w, bp: bp))
        guard let raw = h.askText(title: "몇 개 살까요?", message: "1 ~ \(most)개"), let n = Int(raw.trimmingCharacters(in: .whitespaces)) else { return }
        screen = .shop(bp: bp, sel: sel, qty: max(1, min(most, n))); lastInput = Date(); host?.redraw(.all)
    }
    /// The 도감's 찾기: a name (its start, or in it) or a number → that one's entry (on 전국 · 전체, so it's in the list).
    func dexFind() {
        guard let h = host, let raw = h.askText(title: "도감 찾기", message: "포켓몬 이름이나 번호") else { return }
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        dexRegion = 0
        let all = dexList(0), found = Int(q).flatMap { n in all.contains(n) ? n : nil }
            ?? all.first { monNames[$0].hasPrefix(q) } ?? all.first { monNames[$0].contains(q) }
        guard let d = found else { screen = .say([josa("'\(q)'", "을", "를"), "찾지 못했어요"], next: screen, since: Date()); return }
        screen = .dex(d, filter: 0, detail: true)
    }
}
