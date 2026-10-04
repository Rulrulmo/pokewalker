import Foundation
// Live battles (docs/plans/12 §5): two players, one Battle on the server, run from the first player's side (mine = theirs' theirs). The second
// player sees it mirrored: the sides swapped, the beats' sides flipped, and the engine's lines re-worded ("상대 X" ↔ "X").

extension Battle {
    /// What that side has to use this turn, whatever it picks (charging, rampaging, biding, recharging, 앵콜): the menu's 공격 goes straight to it.
    func forcedMove(_ s: Side) -> Int? {
        let x = f(s)
        if x.charging != 0 { return x.charging }; if x.lock > 0 { return x.lockMove }; if x.bide > 0 { return 117 }
        if x.recharge { return x.lastMove }; if x.encore > 0 { return x.encoreMove }
        return nil
    }
    /// That side is mid-move: only 공격 (or giving up).
    func locked(_ s: Side) -> Bool { let x = f(s); return x.charging != 0 || x.lock > 0 || x.bide > 0 || x.recharge }
    /// Why that side can't switch out now (nil = it can).
    func switchBlock(_ s: Side) -> String? {
        if locked(s) { return "지금은 교체할 수 없다!" }
        return trapped(s) ? josa(nm(s), "은", "는") + " 돌아올 수 없다!" : nil
    }

    /// The second player's view: its party as ours. `name` = the first player's (the "trainer" it faces).
    func mirrored(name: String) -> Battle {
        var b = self
        (b.mine, b.theirs, b.me, b.it) = (theirs, mine, it, me)
        b.sides = [sides[1], sides[0]]; b.planned = [planned[1], planned[0]]
        (b.mustReplace, b.foeMustReplace) = (foeMustReplace == true, mustReplace ? true : nil)
        b.trainer = name; b.out = []; b.foeNext = nil; b.faced = [b.me]
        return b
    }
}

extension Beat {
    /// The same beat seen from the other side (12 §5): sides swapped, won ↔ lost, the lines re-worded by `words`.
    func flipped(_ words: (String) -> String) -> Beat {
        func o(_ s: Side) -> Side { s == .me ? .it : .me }
        switch self {
        case .sendOut(let s, let i): return .sendOut(o(s), i)
        case .use(let s, let m): return .use(o(s), move: m)
        case .hit(let s, let m, let d, let e, let c): return .hit(o(s), move: m, damage: d, effect: e, crit: c)
        case .hurt(let s, let d, let t): return .hurt(o(s), damage: d, text: words(t))
        case .heal(let s, let a, let t): return .heal(o(s), amount: a, text: words(t))
        case .status(let s, let st, let t): return .status(o(s), st, text: words(t))
        case .note(let s, let t): return .note(o(s), text: words(t))
        case .retype(let s, let t): return .retype(o(s), t)
        case .fainted(let s): return .fainted(o(s))
        case .won: return .lost
        case .lost: return .won
        default: return self
        }
    }
}

/// The engine's lines are worded from the first player's side: its own as "X", the other's as "상대 X". For the second player, `ours` (the first
/// player's species) become "상대 X" and "상대 Y" of `theirs` (the second's) become "Y". Longest first, so 뮤츠 isn't read as 뮤. (A trainer's name
/// stays: "민수는 X를 돌아오게 했다!" reads the same from both sides.)
func duelWords(ours: [Int], theirs: [Int]) -> (String) -> String {
    let mine = Set(ours.map { monNames[$0] }), other = Set(theirs.map { monNames[$0] })
    let tokens = (mine.map { ($0, "상대 " + $0) } + other.map { ("상대 " + $0, $0) }).sorted { $0.0.count > $1.0.count }
    return { text in
        var out = "", i = text.startIndex
        scan: while i < text.endIndex {
            for (from, to) in tokens where !from.isEmpty && text[i...].hasPrefix(from) {
                out += to; i = text.index(i, offsetBy: from.count); continue scan
            }
            out.append(text[i]); i = text.index(after: i)
        }
        return out
    }
}
