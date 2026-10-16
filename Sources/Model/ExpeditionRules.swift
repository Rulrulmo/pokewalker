import Foundation
// docs/plans/19 §1 (5.1, content51): the personal 전설 원정's acts and what the walk and the radar bring them (Expedition.swift's data).
// In the order of Expeditions.personal, so the server's dice go the same way every time.

extension EngineRun {
    /// expStart: begin (or, once done, begin again) — its legend rolled now and kept in the progress.
    mutating func expStart(_ id: String) -> String? {
        guard Content.v51, let e = Expeditions.of(id) else { return "없는 원정이에요" }
        var x = w.expeditions?[id] ?? ExpProgress()
        guard !x.on else { return "이미 하고 있는\n원정이에요" }
        x.on = true; x.n = 0; x.steps = 0; x.mon = Expeditions.legend(e.legend, &r)
        w.expeditions = (w.expeditions ?? [:]).merging([id: x]) { $1 }
        return nil
    }
    /// expClaim: all gathered — its legend into the box (Outcome.mon), the progress back to the start (done + 1); a kind's first finish: its gift.
    mutating func expClaim(_ id: String) -> String? {
        guard Content.v51, let e = Expeditions.of(id), var x = w.expeditions?[id], x.on else { return "하고 있는 원정이\n아니에요" }
        guard x.n >= e.need else { return "아직 모자라요\n(\(x.n)/\(e.need))" }
        var m = x.mon ?? Expeditions.legend(e.legend, &r)
        issue(&m, "expedition"); _ = w.keep(m); out.mon = m
        x.on = false; x.n = 0; x.steps = 0; x.mon = nil; x.done += 1
        let gift = x.done == 1 ? e.gift : nil
        if let g = gift { w.bag.append(g) }
        w.expeditions?[id] = x
        events.append(.expeditionDone(id: id, dex: m.dex, gift: gift))
        return nil
    }
    /// n steps walked on this course: each collect expedition it counts for gathers one a `stepsPer` (the rest carried; none past `need`).
    mutating func expSteps(_ n: Int) {
        guard Content.v51, n > 0, w.expeditions != nil else { return }
        for e in Expeditions.personal where e.kind == .collect && e.counts(w.here) {
            guard var x = w.expeditions?[e.id], x.on, x.n < e.need else { continue }
            x.steps += n
            let got = min(e.need - x.n, x.steps / e.stepsPer)
            x.n += got; x.steps = x.n >= e.need ? 0 : x.steps - got * e.stepsPer
            w.expeditions?[e.id] = x
            if got > 0 { events.append(.expedition(id: e.id, n: x.n, need: e.need)) }
        }
    }
    /// A radar find on this course: each collect expedition it counts for, one more at its odds.
    mutating func expRadar() {
        guard Content.v51, w.expeditions != nil else { return }
        for e in Expeditions.personal where e.kind == .collect && e.radarOdds > 0 && e.counts(w.here) {
            guard var x = w.expeditions?[e.id], x.on, x.n < e.need, Double.random(in: 0..<1, using: &r) < e.radarOdds else { continue }
            x.n += 1; if x.n >= e.need { x.steps = 0 }
            w.expeditions?[e.id] = x
            events.append(.expedition(id: e.id, n: x.n, need: e.need))
        }
    }
}
