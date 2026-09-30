import AppKit
// Home: the companion walks the course while steps come in (the faster they come, the faster it goes), and stands about when they stop.

extension WalkerView {
    /// Steps are coming in: it's walking (and the screen draws at 30 fps).
    func strolling(_ now: Date) -> Bool { now.timeIntervalSince(lastStep) < 1.2 }
    /// One frame of it: along the path, turning at the ends; still, it looks the other way now and then. It stops while it does its HGSS animation.
    func stroll(_ now: Date) {
        let dt = min(0.2, max(0, now.timeIntervalSince(strollAt))); strollAt = now
        switch screen { case .home, .menu: break; default: return }
        guard !animating else { return }
        if strolling(now) {
            strollX += (strollRight ? 1 : -1) * min(18, 6 + 1.5 * stepRate) * dt                 // dots a second
            if strollX > 80 { strollX = 80; strollRight = false } else if strollX < 16 { strollX = 16; strollRight = true }
        } else if now > strollTurnAt {
            strollTurnAt = now.addingTimeInterval(Double.random(in: 6...14))                        // the system's dice, as perk's: flows stay seeded
            if Bool.random() { strollRight.toggle() }
        }
    }
}
