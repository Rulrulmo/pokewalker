import AppKit
// Home: the companion's HGSS walking sprite goes along the course picture while steps come in (the faster they come, the faster),
// turning at the ends; when they stop it turns to face us.

/// The HGSS following Pokémon (tools/gen.py walk.bin): 494 uint32 offsets (species d = off[d - 1] ..< off[d]; empty = none), then per species a
/// raw-DEFLATE block: size (32, or 64 for the big ones), 15 normal + 15 shiny RGB, then left, right, down x 4 frames, size x size at 4 bpp.
let walkData = resource("walk.bin") ?? Data()
struct WalkSprite {
    let size: Int, bytes: [UInt8]
    /// Direction 0 left, 1 right, 2 down (facing us); frame 0...3.
    func pic(_ dir: Int, _ f: Int, shiny: Bool) -> Pic {
        var p = Pic(w: size, h: size); let at = 91 + (dir * 4 + f) * size * size / 2
        for k in 0..<size * size {
            let b = bytes[at + k / 2], i = Int(k % 2 == 0 ? b >> 4 : b & 15)
            if i > 0 { let c = 1 + (shiny ? 45 : 0) + (i - 1) * 3; p.px[k] = rgb(bytes[c], bytes[c + 1], bytes[c + 2]) }
        }
        return p
    }
}
@MainActor var walkCache: [Int: WalkSprite?] = [:]
/// A species' walking sprite (nil = none), unpacked the first time it's wanted.
@MainActor func walkSprite(_ dex: Int) -> WalkSprite? {
    if let w = walkCache[dex] { return w }
    if walkCache.count >= 8 { walkCache.removeAll() }
    var w: WalkSprite? = nil
    if let u = block(walkData, dex).flatMap(inflate) {
        let size = Int(u.first ?? 0)
        if size > 0, u.count >= 91 + 12 * size * size / 2 { w = WalkSprite(size: size, bytes: u) }
    }
    walkCache[dex] = w; return w
}

extension WalkerView {
    /// Steps are coming in: it's walking (drawn at the tick's 10 fps: typing is walking, so it mustn't cost much).
    func strolling(_ now: Date) -> Bool { now.timeIntervalSince(lastStep) < 1.2 }
    /// Where it may go: its middle, in half-dots, inside the picture's window.
    var strollRange: ClosedRange<Double> { Double(2 * courseBox.x + 16)...Double(2 * (courseBox.x + courseBox.w) - 16) }
    /// One frame of it: along the path, turning at the ends; still, it looks the other way now and then (facing us meanwhile). It waits while the big one does its HGSS animation.
    func stroll(_ now: Date) {
        let dt = min(0.2, max(0, now.timeIntervalSince(strollAt))); strollAt = now
        switch screen { case .home, .menu: break; default: return }
        guard !animating else { return }
        if strolling(now) {
            strollX += (strollRight ? 1 : -1) * min(36, 12 + 2 * stepRate) * dt                   // half-dots a second
            if strollX > strollRange.upperBound { strollX = strollRange.upperBound; strollRight = false } else if strollX < strollRange.lowerBound { strollX = strollRange.lowerBound; strollRight = true }
        } else if now > strollTurnAt {
            strollTurnAt = now.addingTimeInterval(Double.random(in: 6...14))                        // the system's dice, as perk's: flows stay seeded
            if Bool.random() { strollRight.toggle() }
        }
    }
    /// The walking sprite on the path of a course picture at `box` (home's, or 포켓 레이더's): its steps while it walks (quicker with the pace), facing us
    /// when it stands; at = its middle (half-dots) when it isn't home's stroll (then it stands). Returns its feet (half-dots).
    @discardableResult func walker(_ fb: inout FB, _ m: Mon, _ now: Date, box: (x: Int, y: Int, w: Int, h: Int) = courseBox, at: Int? = nil) -> (x: Int, y: Int) {
        let feet = (x: at ?? Int(strollX.rounded()), y: 2 * (box.y + box.h) - 7)
        guard let w = walkSprite(m.dex) else { return feet }
        let t = now.timeIntervalSinceReferenceDate, moving = at == nil && strolling(now) && !animating, dir = moving ? (strollRight ? 1 : 0) : 2
        let frame = moving ? Int(t * min(12, 6 + stepRate / 2)) % 4 : Int(t / 0.6) % 2 == 0 ? 0 : 1 // HGSS's step cycle; standing, a slow shuffle
        let scale = w.size > 32 ? 0.5 : 1.0, shiny = m.shiny == true
        fb.pic("walk|\(m.dex)|\(dir)|\(frame)|\(shiny)", feet.x, feet.y - Int(Double(w.size) * scale / 2), scale: scale, behind: true,
               clip: [2 * box.x + 3, 2 * box.y + 3, 2 * box.w - 6, 2 * box.h - 6]) { w.pic(dir, frame, shiny: shiny) }
        return feet
    }
}
