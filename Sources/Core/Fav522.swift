import Foundation
// 5.2.2 (docs/plans/25; the user via 회사 10-23: "포켓몬 메뉴에 즐겨찾기 기능 있었으면" → "ㅇㅇ", the mockups lcd-mockups docs/mockups/v5.2.1 as
// decided 10-26: "추천안 대로", then the worst cases): 즐겨찾기 — Mon.fav, the server's (.mon(op: .fav)). Its ♥ on every grid of mine (the box, the
// party row, the trade · board · visit · tower · duel picks) and on the LCD (the picture's top left); the 상자's ♥ chip (찾기 즐겨찾기); the
// page's ♡ / ♥ first in its buttons (not in a fight: the server says no); a ♥ one let go of in one go (풀고 놓아주기: .fav off, then .release —
// the server refuses a ♥ one's release); 중복 n마리 without the ♥ (Walk.releasableDuplicates, the server's own count); asked once more before
// one goes to someone else (글 올리기 · 제안 · 1:1 신청 · 수락s) — never for 맡기기 (it comes back with its ♥).

extension Walker {
    /// The page's ♡ / ♥ (4417): on ↔ off, the page stays (the radar and a chain go on: the server's keepsChain).
    func toggleFav(_ ref: Int, _ now: Date = Date()) {
        guard let m = state.mon(ref), let u = m.uid else { return }
        let here = Screen.box(ref, act: nil, confirm: false, detail: true)
        act(.mon(op: .fav(uid: u, on: m.fav != true)), back: here, now, quiet: true) { _, _ in nil }
    }
    /// The 상자's ♥ chip (4174): 찾기 "즐겨찾기" in one click, again: all (as ★).
    func boxFavChip() {
        boxQuery = boxQuery == "즐겨찾기" ? "" : "즐겨찾기"
        screen = .box(boxShown.first ?? -1, act: nil, confirm: false); lastInput = Date(); host?.redraw(.all)
    }
    /// 중복 n마리: the ones the server would let go of (not the best one, nor 이로치 · 3V · ♥).
    func releasable(_ dex: Int) -> [Int] { state.releasableDuplicates(of: dex) }
    /// 놓아줄까? → 예 on box[i]: a ♥ one is let go of first (풀고 놓아주기), then released; `go` is the release itself.
    func releaseMaybeFav(_ i: Int, back: Screen, _ now: Date, _ go: @escaping @MainActor (Date) -> Void) {
        guard state.box.indices.contains(i), state.box[i].fav == true, let u = state.box[i].uid else { go(now); return }
        act(.mon(op: .fav(uid: u, on: false)), back: back, now) { _, now in go(now); return nil }
    }
    /// One ask before m goes to someone else: its ♥ and its held item in one window (5.2.2), or the item's alone (3.7). `verb` is the button
    /// (올리기 · 제안하기 · 신청하기 · 교환), `how` says when it's gone ("교환되면", "민수가 받으면 교환되고" …), `question` the last line.
    func sendAsk(_ m: Mon?, _ verb: String, how: String, question: String) -> Bool {
        guard let m else { return true }
        let name = monNames[m.dex]
        if m.fav == true {
            let item = m.item.map { josa($0, "을", "를") + " 지니고 있어요. 교환되면 " + josa($0, "도", "도") + " 함께 가요.\n" } ?? ""
            return host?.confirm(josa(name, "은", "는") + " 즐겨찾기한 포켓몬이에요", item + how + ", 즐겨찾기는 풀려요.\n" + question, ok: verb) ?? true
        }
        return holdsAlong(m, verb)
    }
    /// The 수락s' own "교환할까요?": its line when mine is a ♥ one ("" if not).
    func favLine(_ m: Mon?) -> String {
        guard let m, m.fav == true else { return "" }
        return "\n" + josa(monNames[m.dex], "은", "는") + " 즐겨찾기한 포켓몬이에요. 교환되면 즐겨찾기는 풀려요."
    }
}
