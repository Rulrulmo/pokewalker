import AppKit
import UserNotifications
// The device: geometry in dots, shells, LCD palettes, notification switches.

// MARK: - geometry (points; flipped view). One body: the Poké Ball on the left (140 dots, the LCD in its middle, no buttons),
// the pane on the right (the page on top, the ◀ ● ▶ ↩ deck under it). Everything is in dots x PX, so the size menu scales it all.
@MainActor var SIZE = CGFloat(min(4, max(2, UserDefaults.standard.integer(forKey: "px"))))   // the 크기 menu: 2 보통 / 3 크게 / 4 아주 크게
@MainActor var PX: CGFloat { SIZE * 1.25 }                                                   // points per dot: 2.5 / 3.75 / 5 — the LCD 1.25x the old device's (the user's pick; on a 1x screen dots are 2-3 px)
let dev = (w: CGFloat(140), h: CGFloat(140))                                                  // the ball, in dots
@MainActor var paneUnit: CGFloat { PX * 1.7 / 3 }                                             // the pane's layout unit (1.42 pt at 보통), in step with the ball
@MainActor var ballOrigin: NSPoint { NSPoint(x: (5 * PX).rounded(), y: (5 * PX).rounded()) }
@MainActor var paneRect: NSRect { NSRect(x: ballOrigin.x + ((dev.w + 4) * PX).rounded(), y: ballOrigin.y, width: (140 * paneUnit).rounded(), height: dev.h * PX) }   // whole points: a crisp window edge
@MainActor var pageRect: NSRect { NSRect(x: paneRect.minX, y: paneRect.minY, width: paneRect.width, height: (186 * paneUnit).rounded()) }   // battle / 도감 / 상점 / 메뉴 / 상태
@MainActor var deckRect: NSRect { let u = paneUnit; return NSRect(x: paneRect.minX + 6 * u, y: pageRect.maxY, width: paneRect.width - 12 * u, height: paneRect.maxY - pageRect.maxY - 6 * u) }
@MainActor var devSize: NSSize { NSSize(width: (paneRect.maxX + 5 * PX).rounded(), height: (paneRect.maxY + 5 * PX).rounded()) }   // the window: 584 x 376 pt at 보통
@MainActor var lcdRect: NSRect { NSRect(x: ballOrigin.x + 22 * PX, y: ballOrigin.y + 38 * PX, width: 96 * PX, height: 64 * PX) }   // 96x64 dots, 4 greys, like the real one; centred on the ball
@MainActor var buttons: [(c: NSPoint, r: CGFloat)] {                                          // left, enter, right on an arc, back tucked under enter — on the pane's deck
    let u = paneUnit, cx = deckRect.midX, cy = deckRect.minY + 17.5 * u
    return [(NSPoint(x: cx - 40 * u, y: cy - 2 * u), 10.5 * u), (NSPoint(x: cx, y: cy), 13 * u), (NSPoint(x: cx + 40 * u, y: cy - 2 * u), 10.5 * u), (NSPoint(x: cx, y: cy + 23.5 * u), 8.2 * u)]
}

struct Shell { let name: String; let top: NSColor; var band = NSColor(white: 0.10, alpha: 1); var dex = 0; var bp = 0 }   // bp > 0: bought at the BP exchange   // top half, band; the bottom is always white. dex = Pokédex count to unlock
let shells: [Shell] = [
    Shell(name: "몬스터볼", top: NSColor(red: 0.89, green: 0.20, blue: 0.19, alpha: 1)),
    Shell(name: "슈퍼볼", top: NSColor(red: 0.22, green: 0.46, blue: 0.86, alpha: 1)),
    Shell(name: "하이퍼볼", top: NSColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)),
    Shell(name: "마스터볼", top: NSColor(red: 0.47, green: 0.27, blue: 0.66, alpha: 1)),
    Shell(name: "프리미어볼", top: NSColor(white: 0.97, alpha: 1), band: NSColor(red: 0.86, green: 0.20, blue: 0.18, alpha: 1), dex: 15),
    Shell(name: "럭셔리볼", top: NSColor(white: 0.13, alpha: 1), band: NSColor(red: 0.80, green: 0.16, blue: 0.14, alpha: 1), dex: 50),
    Shell(name: "배틀 골드", top: NSColor(red: 0.86, green: 0.68, blue: 0.24, alpha: 1), band: NSColor(white: 0.12, alpha: 1), bp: 40),
]
@MainActor var theme = min(max(UserDefaults.standard.integer(forKey: "shell"), 0), shells.count - 1)
struct LCD { let name: String; let shades: [NSColor]; var color = false }   // shade 0 (blank) ... 3 (black); `color` = sprites in their HGSS colours
let lcds: [LCD] = [
    LCD(name: "컬러", shades: [(0.97, 0.96, 0.92), (0.80, 0.80, 0.76), (0.47, 0.49, 0.53), (0.12, 0.13, 0.16)].map { NSColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }, color: true),
    LCD(name: "원작", shades: [(0.78, 0.82, 0.72), (0.58, 0.63, 0.54), (0.35, 0.39, 0.33), (0.11, 0.13, 0.11)].map { NSColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }),
    LCD(name: "백라이트", shades: [(0.62, 0.80, 0.96), (0.42, 0.60, 0.82), (0.22, 0.34, 0.55), (0.05, 0.09, 0.20)].map { NSColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }),
]
@MainActor var lcdStyle = min(max(UserDefaults.standard.integer(forKey: "lcd"), 0), lcds.count - 1)

// MARK: - notifications (macOS banners); each kind can be switched off in the menu
let notifyKinds = [("pet", "동료가 주워 온 것"), ("hatch", "알 부화"), ("grow", "진화 · 레벨(5의 배수)"), ("weather", "날씨 변화"), ("unlock", "해금 (코스 · 기기)")]
nonisolated(unsafe) var useOsascript = false                                                  // set once at launch, read on the main thread
func notifyOn(_ k: String) -> Bool { UserDefaults.standard.object(forKey: "notify.\(k)") as? Bool ?? true }
final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }
}
final class Panel: NSPanel { override var canBecomeKey: Bool { true } }                    // arrow keys work after a click; still never activates the app
@MainActor var statusItem: NSStatusItem? = nil
