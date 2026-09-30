import AppKit
// The course picture on the home screen and the ground a fight stands on.

extension FB {
    /// 32x24 picture of the course, framed.
    mutating func course(_ a: Art, _ x: Int, _ y: Int, weather w: Weather = .sunny, t: Double = 0, hour: Double = 12, season: Season = .summer) {
        // colour: sky above the course's horizon, its ground/water below
        let horizon = [Art.field: 14, .forest: 17, .mountain: 19, .beach: 10, .lake: 12, .town: 19, .cave: 0][a]!
        let grey = w == .rain || w == .fog || w == .snow && a != .cave
        // game clock: dawn 4-6, day, dusk 17-20, night 20-4 (as for evolutions); overcast greys the sky and hides the sun / moon
        let night = hour < 4 || hour >= 20, dawn = (4..<6).contains(hour), dusk = (17..<20).contains(hour)
        let clear = night ? rgb(34, 44, 92) : dawn ? rgb(250, 196, 170) : dusk ? rgb(248, 150, 104) : rgb(160, 208, 250)
        let orb = night ? rgb(236, 232, 196) : dusk || dawn ? rgb(255, 120, 70) : rgb(255, 222, 96)
        let sky = [grey ? (night ? rgb(70, 76, 92) : rgb(172, 182, 196)) : clear, grey ? (night ? rgb(80, 86, 100) : rgb(200, 204, 212)) : orb, rgb(70, 150, 80), rgb(36, 44, 56)]
        let ground: [UInt32] = switch a {
        case .field, .forest, .town: [rgb(130, 204, 96), rgb(100, 180, 80), rgb(70, 150, 64), rgb(36, 80, 44)]
        case .mountain: [rgb(186, 156, 112), rgb(160, 130, 96), rgb(128, 100, 72), rgb(60, 44, 36)]
        case .beach, .lake: [rgb(96, 170, 240), rgb(80, 150, 230), rgb(96, 170, 96), rgb(40, 90, 180)]
        case .cave: [rgb(90, 76, 70), rgb(110, 96, 88), rgb(128, 108, 96), rgb(40, 32, 30)]
        }
        func p(_ dx: Int, _ dy: Int, _ s: UInt8) {
            guard (0..<32).contains(dx), (0..<24).contains(dy) else { return }
            var c = (dy < horizon ? sky : ground)[Int(s)]
            let green = [.field, .forest, .town].contains(a)
            switch season {                                                                                   // the land by season
            case .spring: if green, dy >= horizon, s == 2, (dx + dy) % 3 == 0 { c = rgb(244, 150, 190) }         // flowers
            case .autumn:
                if green, dy >= horizon { c = [rgb(214, 178, 96), rgb(196, 150, 72), rgb(170, 112, 50), rgb(90, 60, 30)][Int(s)] }
                if a == .forest, dy < horizon, s == 2 { c = (dx + dy) % 2 == 0 ? rgb(222, 120, 48) : rgb(200, 70, 40) }   // red and orange trees
            case .winter:
                if green || a == .mountain, dy >= horizon { c = [rgb(246, 248, 252), rgb(226, 232, 242), rgb(198, 208, 222), rgb(110, 120, 140)][Int(s)] }   // snow cover
                if a == .forest, dy < horizon, s == 2 { c = dy % 3 == 0 ? rgb(240, 244, 250) : rgb(52, 100, 76) }   // snow on the firs
                if a == .mountain, dy < horizon, s == 1 { c = rgb(236, 240, 246) }                                // white peaks
            case .summer: break
            }
            if night, dy >= horizon || a == .cave { c = dim(c, 0.55) }                                           // the ground darkens too
            if night, !grey, dy < horizon, s == 0, (dx * 7 + dy * 13) % 23 == 0 { c = rgb(250, 250, 220) }        // stars
            if a == .mountain, dy < horizon, s == 1 { c = rgb(150, 132, 118) }                                     // rock faces, not sun
            if a == .beach, dy >= 18 { c = [rgb(242, 222, 160), c, rgb(206, 176, 116), c][Int(s)] }                  // sand
            if a == .town, dy < horizon, s == 2 { c = rgb(210, 84, 70) }                                          // roofs
            set(x + dx, y + dy, s, c)
        }
        for dy in 0..<24 { for dx in 0..<32 { p(dx, dy, 0) } }
        func tree(_ cx: Int, _ top: Int) { for i in 0..<9 { for dx in -i / 2...i / 2 { p(cx + dx, top + i, i == 8 || abs(dx) == i / 2 ? 3 : 2) } }; p(cx, top + 9, 3); p(cx, top + 10, 3) }
        func peak(_ cx: Int, _ top: Int, _ h: Int) { for i in 0..<h { for dx in -i...i { p(cx + dx, top + i, abs(dx) == i ? 3 : (i < 3 ? 0 : 1)) } } }
        switch a {
        case .field:
            for dx in 0..<32 { p(dx, 14, 3) }; for dy in 15..<24 { for dx in 0..<32 where (dx * 3 + dy * 5) % 7 == 0 { p(dx, dy, 2) } }
            for dx in [4, 11, 18, 25] { p(dx, 15, 3); p(dx - 1, 16, 3); p(dx + 1, 16, 3) }
            for dy in 3..<7 { for dx in 23..<27 { p(dx, dy, 1) } }
        case .forest: tree(6, 5); tree(16, 2); tree(26, 6); for dx in 0..<32 { p(dx, 17, 3) }; for dy in 18..<24 { for dx in 0..<32 where (dx + dy) % 4 == 0 { p(dx, dy, 1) } }
        case .mountain: peak(10, 4, 15); peak(23, 8, 11); for dx in 0..<32 { p(dx, 19, 3) }; for dy in 20..<24 { for dx in 0..<32 where dx % 3 == dy % 3 { p(dx, dy, 2) } }
        case .beach, .lake:
            let water = a == .beach ? 10 : 12
            for dy in water..<24 { for dx in 0..<32 { p(dx, dy, a == .lake && (dx < 3 || dx > 28) ? 2 : ((dx + dy * 2) % 6 == 0 ? 3 : 1)) } }
            if a == .beach { for dy in 18..<24 { for dx in 0..<32 { p(dx, dy, (dx * 7 + dy) % 5 == 0 ? 2 : 0) } } }
            for dy in 2..<7 { for dx in 3..<8 where !(dy == 2 || dy == 6) || (dx > 3 && dx < 7) { p(dx, dy, 2) } }
        case .town:
            for (hx, hw) in [(3, 11), (17, 12)] {
                for i in 0..<5 { for dx in hx + 2 - i...hx + hw - 3 + i { p(dx, 6 + i, i == 4 || dx == hx + 2 - i || dx == hx + hw - 3 + i ? 3 : 2) } }
                for dy in 11..<19 { for dx in hx..<hx + hw { p(dx, dy, dx == hx || dx == hx + hw - 1 || dy == 18 ? 3 : 0) } }
                for dy in 14..<18 { p(hx + hw / 2, dy, 3); p(hx + hw / 2 + 1, dy, 3) }
            }
            for dx in 0..<32 { p(dx, 19, 3) }
        case .cave:
            for dy in 0..<24 { for dx in 0..<32 { p(dx, dy, (dx * 5 + dy * 3) % 7 == 0 ? 3 : 2) } }
            for dy in 6..<24 { for dx in 8..<24 { let ex = Double(dx) - 15.5, ey = Double(dy) - 24; if ex * ex / 64 + ey * ey / 324 < 1 { p(dx, dy, 3) } } }
        }
        weatherFX(w, x + 1, y + 1, 30, 22, t, cave: a == .cave)
        for dx in 0..<32 { p(dx, 0, 3); p(dx, 23, 3) }; for dy in 0..<24 { p(0, dy, 3); p(31, dy, 3) }
    }
    /// Under a fight: the pads each side stands on (feet at at[s].y + 32, centre x + 16), by season.
    mutating func battleGround(_ at: [Side: (x: Int, y: Int)], art: Art, hour: Double, season: Season, weather: Weather, indoor: Bool) {
        let pad: (UInt32, UInt32) = switch season {
        case .spring: (rgb(150, 206, 120), rgb(196, 230, 160)); case .summer: (rgb(130, 190, 96), rgb(176, 216, 136))
        case .autumn: (rgb(200, 150, 80), rgb(226, 190, 120)); case .winter: (rgb(200, 212, 228), rgb(236, 242, 250))
        }
        for (s, rx, ry) in [(Side.it, 20.0, 3.4), (.me, 22.0, 4.0)] {
            let cx = at[s]!.x + 16, cy = at[s]!.y + 31                                                      // under the feet (every frame stands on its box's bottom)
            for y in cy - 4...cy + 4 { for x in cx - 23...cx + 23 { let ex = Double(x - cx) / rx, ey = Double(y - cy) / ry; if ex * ex + ey * ey < 1 { set(x, y, 1, ex * ex + ey * ey > 0.7 ? pad.0 : pad.1) } } }
        }
    }
}
/// Self-test checks for this file's drawing (run by selftest()).
@MainActor func routeChecks() -> [(Bool, String)] { [] }
