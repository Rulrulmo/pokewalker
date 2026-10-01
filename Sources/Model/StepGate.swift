import Foundation
// Steps the way a person makes them (against macros, auto-clickers and a held key): at most 15 a second and 600 a minute count, and input that
// keeps coming every second at a near-constant rate is a machine's: nothing counts until a minute without any. Only counts are seen, never which key.

struct StepGate {
    static let perSecond = 15, perMinute = 600, window = 120, quiet = 60
    var raw = [Int](repeating: 0, count: StepGate.window)       // the last 120 seconds' raw counts (a ring by second)
    var credited = [Int](repeating: 0, count: 60)                 // what counted in each of the last 60 seconds
    var second = -1, seen = 0, held = false                       // the second now, how many whole seconds watched, a macro caught
    /// n raw key downs / clicks at `now` (seconds): how many of them count.
    mutating func pass(_ n: Int, _ now: Double) -> Int {
        let s = Int(now.rounded(.down))
        if second < 0 { second = s }
        if s > second {                                           // whole seconds went by: judge them, then clear their slots
            for k in (second + 1)...min(s, second + StepGate.window) { raw[k % StepGate.window] = 0; credited[k % 60] = 0 }
            seen += s - second; second = s
            judge()
        }
        raw[s % StepGate.window] += max(0, n)
        guard !held, n > 0 else { return 0 }
        let c = min(n, StepGate.perSecond - credited[s % 60], StepGate.perMinute - credited.reduce(0, +))
        guard c > 0 else { return 0 }
        credited[s % 60] += c; return c
    }
    /// The last whole seconds: a macro is input in (nearly) every one of 120 at a steady rate; it lets go after 60 without any.
    mutating func judge() {
        let past = (1...StepGate.window).map { raw[(second - $0 + StepGate.window * 2) % StepGate.window] }   // newest first, the second now left out
        if held { if past.prefix(StepGate.quiet).allSatisfy({ $0 == 0 }) { held = false }; return }
        guard seen > StepGate.window else { return }
        let mean = Double(past.reduce(0, +)) / Double(past.count), busy = Double(past.filter { $0 > 0 }.count) / Double(past.count)
        let sd = (past.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(past.count)).squareRoot()
        if busy >= 0.98, mean >= 2, sd / mean < 0.3 { held = true }    // people pause and type in bursts; a loop doesn't
    }
}

@MainActor func stepGateChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    var g = StepGate(), got = 0
    for t in 0..<100 { got += g.pass(3, Double(t) / 10) }          // 30 a second for 10 s (a key held down)
    c.append((got == 150, "steps: at most 15 a second count (\(got))"))
    g = StepGate(); got = 0
    for t in 0..<700 { got += g.pass(2, Double(t) / 10) }          // 20 a second for 70 s
    c.append((got <= 600 + 15 * 10 && got >= 600, "steps: at most 600 a minute (\(got) in 70 s)"))
    g = StepGate(); got = 0; var late = 0
    for t in 0..<1300 { let n = g.pass(t % 2 == 0 ? 1 : 0, Double(t) / 10); if t >= 1220 { late += n } else { got += n } }   // 5 a second, like clockwork
    let caught = g.held
    var back = 0
    for t in 1300..<2000 { back += g.pass(t >= 1950 && t % 2 == 0 ? 1 : 0, Double(t) / 10) }   // hands off a minute, then a key
    c.append((caught && late == 0 && back > 0 && !g.held, "steps: a steady machine rate for 2 minutes stops counting, a minute's pause lets go"))
    g = StepGate(); got = 0; var r = Seeded(s: 9)
    for t in 0..<6000 {                                            // 10 minutes of people typing: bursts and pauses
        let sec = t / 10, burst = sec % 7 < 4, n = burst ? Int.random(in: 0...2, using: &r) : (Int.random(in: 0..<10, using: &r) == 0 ? 1 : 0)
        got += g.pass(n, Double(t) / 10)
    }
    c.append((!g.held && got > 1500, "steps: people typing in bursts are never caught (\(got) counted)"))
    return c
}
