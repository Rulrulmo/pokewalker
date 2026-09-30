import AppKit
// The HGSS entry animations (tools/gen.py anims.bin): what each species does as it appears, played in place of its sprite, then the sprite again.

/// 494 uint32 offsets (species d = off[d - 1] ..< off[d]; empty = none), then per species a raw-DEFLATE block: x, y (int16), w, h, n (uint8),
/// n x uint16 ms, n frames w x h at 4 bpp (hgss.bin's colour slots; 0 = clear).
let animData: Data = Bundle.main.url(forResource: "anims", withExtension: "bin").flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) } ?? Data()
/// One species' animation: its frames' box in the sprite's 80x80 frame (top-left x, y: may be < 0 or past 79: a jump, a stretch), each frame's time.
struct Anim {
    let dex, x, y, w, h: Int, ms: [Int]
    let bytes: [UInt8], start: Int                                         // the block, and where its frames begin
    var length: Double { Double(ms.reduce(0, +)) / 1000 }
    /// The frame t seconds after it started; nil before it or once it's over (the static sprite: its rest pose).
    func frame(at t: Double) -> Int? {
        guard t >= 0 else { return nil }
        var end = 0
        for (k, m) in ms.enumerated() { end += m; if t < Double(end) / 1000 { return k } }       // whole ms summed: the last frame ends exactly at length
        return nil
    }
    /// Frame f's pixel at (x, y) of its box, as spritePixel gives the sprite's: 0 = clear, else 0xFFRRGGBB.
    func pixel(_ f: Int, _ x: Int, _ y: Int, shiny: Bool) -> UInt32 {
        let k = (f * h + y) * w + x, b = bytes[start + k / 2], i = Int(k % 2 == 0 ? b >> 4 : b & 15)
        guard i > 0 else { return 0 }
        let p = (dex - 1) * 6490 + (shiny ? 45 : 0) + (i - 1) * 3
        return rgb(hgssData[p], hgssData[p + 1], hgssData[p + 2])
    }
}
@MainActor var animCache: [Int: Anim?] = [:]
/// A species' animation (nil = none: the static sprite stays), unpacked the first time it's wanted; the last few kept.
@MainActor func anim(_ dex: Int) -> Anim? {
    if let a = animCache[dex] { return a }
    if animCache.count >= 8 { animCache.removeAll() }                                        // one species a page: a handful is plenty
    func off(_ i: Int) -> Int { Int(animData[i * 4]) | Int(animData[i * 4 + 1]) << 8 | Int(animData[i * 4 + 2]) << 16 | Int(animData[i * 4 + 3]) << 24 }
    var a: Anim? = nil
    if (1...493).contains(dex), animData.count > 494 * 4, off(dex - 1) < off(dex), off(dex) <= animData.count,
       let d = try? (animData.subdata(in: off(dex - 1)..<off(dex)) as NSData).decompressed(using: .zlib), d.length >= 7 {
        let u = [UInt8](d as Data), w = Int(u[4]), h = Int(u[5]), n = Int(u[6]), p = 7 + 2 * n
        if n > 0, u.count >= p + n * w * h / 2 {
            a = Anim(dex: dex, x: Int(Int16(bitPattern: UInt16(u[0]) | UInt16(u[1]) << 8)), y: Int(Int16(bitPattern: UInt16(u[2]) | UInt16(u[3]) << 8)), w: w, h: h,
                     ms: (0..<n).map { Int(u[7 + 2 * $0]) | Int(u[8 + 2 * $0]) << 8 }, bytes: u, start: p)
        }
    }
    animCache[dex] = a; return a
}
/// The run's animation, when it shows one of its frames (nil = the static sprite).
@MainActor func playing(_ r: SpriteRun) -> Anim? { r.frame.flatMap { f in anim(r.dex).flatMap { f < $0.ms.count && !r.back ? $0 : nil } } }

extension WalkerView {
    /// Seconds into the animation of the Pokémon shown as `who` (home's companion, a page's); nil = none on (the static sprite).
    /// start: another one on screen starts its own (the pages: opening one, ◀ ▶); home's waits for a pat or a perk.
    func animT(_ who: String, _ dex: Int, _ now: Date, start: Bool = true) -> Double? {
        if start, animOn?.who != who || animOn?.dex != dex { animOn = (who, dex, now) }
        guard let a = animOn, a.who == who, a.dex == dex else { return nil }
        return now.timeIntervalSince(a.since)
    }
    /// An animation is playing: the screen draws at 30 fps.
    var animating: Bool { animOn.map { Date().timeIntervalSince($0.since) < (anim($0.dex)?.length ?? 0) } ?? false }
    /// Home, now and then by itself: steps coming in after a quiet spell (before lastStep moves on), and at random while idle (about once a minute).
    func perk(_ now: Date, stepped: Bool) {
        switch screen { case .home, .menu: break; default: return }
        guard !animating, stepped ? now.timeIntervalSince(lastStep) > 20 : Double.random(in: 0..<1) < 1.0 / 600 else { return }   // the system's dice, not rng: flows stay seeded
        animOn = ("home", state.companion.dex, now)
    }
}

/// Self-test checks for this file (run by selftest()).
@MainActor func animChecks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let pk = anim(25)
    c.append((pk.map { $0.ms.count > 5 && (0.3...5).contains($0.length) && $0.w <= 160 && $0.h <= 160 } == true, "anims.bin: 피카츄 has its entry animation"))
    c.append(([1, 6, 25, 94, 150, 249].allSatisfy { d in                                   // its last frame = the sprite as it stands (same place, same colours)
        guard let a = anim(d) else { return false }
        var same = 0, all = 0; let f = a.ms.count - 1
        for y in 0..<80 { for x in 0..<80 {
            let s = spritePixel(d, back: false, x, y, shiny: false), ax = x - a.x, ay = y - a.y
            let p = (0..<a.w).contains(ax) && (0..<a.h).contains(ay) ? a.pixel(f, ax, ay, shiny: false) : 0
            if s != 0 || p != 0 { all += 1; if s == p { same += 1 } }
        } }
        return Double(same) / Double(max(1, all)) > 0.95
    }, "each animation ends on the static sprite's pose and colours"))
    if let a = pk { c.append((a.frame(at: 0) == 0 && a.frame(at: a.length - 0.001) == a.ms.count - 1 && a.frame(at: a.length) == nil && a.frame(at: -0.1) == nil, "an animation's frame by time: none before it starts or once it's over")) }
    let v = WalkerView(state: { var s = Walk(); s.owned = [6, 25]; return s }()); v.persist = false; v.screen = .home
    let now = Date(), idle = v.compose(now).sprites.first?.frame == nil
    v.press(1); let t0 = v.animOn?.since ?? now
    let on = v.compose(t0.addingTimeInterval(0.05)).sprites.first?.frame != nil && v.animating, off = v.compose(t0.addingTimeInterval(10)).sprites.first?.frame == nil
    c.append((idle && on && off && v.emote?.kind == 1, "home ●: the companion plays its animation (♥ too), then stands still again"))
    v.screen = .dex(25, filter: 0, detail: false); let d0 = v.compose(now).sprites.first?.frame
    v.screen = .dex(6, filter: 0, detail: false); let d1 = v.compose(now.addingTimeInterval(5)).sprites.first?.frame   // ▶: the next one plays from its start
    c.append((d0 == 0 && d1 == 0 && v.compose(now.addingTimeInterval(20)).sprites.first?.frame == nil, "도감: the shown Pokémon plays once when it changes"))
    v.screen = .dex(25, filter: 0, detail: true); v.tick(nil); let fast = v.fast != nil
    v.animOn = ("dex", 25, .distantPast); v.tick(nil)
    c.append((fast && v.fast == nil, "an animation plays at 30 fps, then back to the tick's 10"))
    return c
}
