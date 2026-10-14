import Foundation
// 5.0 (the user: 새 개념을 처음 만날 때 짧은 안내): a few words on the LCD, once on this PC, the first time each new thing comes up — 5.0's
// world switched on, a Mega stone in the bag, a Pokémon with its hidden ability, the Mega raid opened. The app's own walker only (tipsOn):
// a test's walker stays as it was.

enum Tip: Int, CaseIterable {
    case content5, megaStone, hidden, megaRaid
    var lines: [String] {
        switch self {
        case .content5: ["하나 · 칼로스 포켓몬이 왔어요!", "새 코스 · 도감 지방 탭 ·", "메가진화를 둘러보세요"]
        case .megaStone: ["메가스톤을 얻었다!", "지니게 하면 배틀의 기술에서", "메가진화를 켤 수 있어요"]
        case .hidden: ["숨겨진특성 포켓몬이다!", "레이더 연쇄가 길수록", "더 자주 만나요"]
        case .megaRaid: ["이기면 확률로 그 보스의", "메가스톤이 우편함에 와요", "30승마다 하나를 골라요"]
        }
    }
}

extension Walker {
    func tipSeen(_ t: Tip) -> Bool { tipBits & (1 << t.rawValue) != 0 }
    /// The tip, if it's new: on the LCD for 5 s (then `next`), and never again here.
    @discardableResult func showTip(_ t: Tip, next: Screen, _ now: Date) -> Bool {
        guard tipsOn, !tipSeen(t) else { return false }
        tipBits |= 1 << t.rawValue; if persist { settings.set("tips5", tipBits) }
        screen = .say(t.lines, next: next, since: now.addingTimeInterval(2)); return true
    }
    /// At home with nothing going on: the first new thing there is to say, if any.
    func tipTick(_ now: Date) {
        guard tipsOn, Content.on, case .home = screen, calm, waiting == nil, news.isEmpty, !inBattle else { return }
        if showTip(.content5, next: .home, now) { return }
        if (state.bag + state.items).contains(where: { Forms.stones.contains($0) }) || ([state.companion] + state.caught + state.box).contains(where: { $0.item.map(Forms.stones.contains) == true }) {
            if showTip(.megaStone, next: .home, now) { return }
        }
        if ([state.companion] + state.caught + state.box).contains(where: { $0.ability == 2 && (Forms.of($0.dex, $0.form)?.hidden ?? hiddenAbility[$0.dex]) > 0 }) { showTip(.hidden, next: .home, now) }
    }
}
