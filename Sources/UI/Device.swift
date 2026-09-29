import AppKit
import UserNotifications
// The device: geometry in dots, shells, LCD palettes, notification switches.

// MARK: - geometry (points; flipped view). All in device dots x PX, so the size menu scales everything.
@MainActor var PX = CGFloat(max(2, UserDefaults.standard.integer(forKey: "px")))    // 2 / 3 / 4
let dev = (w: CGFloat(144), h: CGFloat(144))                                                  // a Poké Ball: 144-dot circle, screen where the button would be
@MainActor var devSize: NSSize { NSSize(width: dev.w * PX, height: dev.h * PX) }
@MainActor var lcdRect: NSRect { NSRect(x: 24 * PX, y: 40 * PX, width: 96 * PX, height: 64 * PX) }      // 96x64 dots, 4 greys, like the real one; centred on the ball
@MainActor var buttons: [(c: NSPoint, r: CGFloat)] {   // left, enter, right on the white half following its curve; home tucked under enter
    [(NSPoint(x: 49 * PX, y: 120 * PX), 4.6 * PX), (NSPoint(x: 72 * PX, y: 123 * PX), 6 * PX), (NSPoint(x: 95 * PX, y: 120 * PX), 4.6 * PX), (NSPoint(x: 72 * PX, y: 136.5 * PX), 3.4 * PX)]
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
