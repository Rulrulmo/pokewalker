import AppKit
// The device: geometry in dots, shells, LCD palettes, notification switches.

// MARK: - geometry (points; flipped view). The Poké Ball card: its red top holds a title row and the LCD in a dark bezel, the dark band
// through its middle carries ◀ ● ▶ ↩ (● = the ball's button), the white bottom is the pane's page — it grows down only as far as a screen
// needs, from a fixed top. Laid out in card points (216 wide at 보통) x K, so the size menu scales it all.
@MainActor var SIZE = CGFloat(min(4, max(2, settings.int("px", 0))))                         // the 크기 menu: 2 보통 / 3 크게 / 4 아주 크게
@MainActor var PX: CGFloat { SIZE }                                                          // points per dot: 2 / 3 / 4 — whole pixels on a 1x screen
@MainActor var K: CGFloat { SIZE / 2 }                                                       // the card's scale: 1 / 1.5 / 2; Pokémon are 1 pt a pixel at 보통
enum Layout { static let w: CGFloat = 216, top: CGFloat = 24, seam: CGFloat = 176, band: CGFloat = 8, pane: CGFloat = 189, idle: CGFloat = 199, r: CGFloat = 18 }   // card points: width, title row, band centre / height, the page's top, the idle height, corners
@MainActor var lcdRect: NSRect { NSRect(x: (12 * K).rounded(), y: (27 * K).rounded(), width: 96 * PX, height: 64 * PX) }   // 96x64 dots, 192 x 128 pt at 보통, in a 3 pt bezel; whole points (crisp at 크게 on a 1x screen)
@MainActor var buttons: [(c: NSPoint, r: CGFloat)] {                                          // ◀ ● ▶ ↩ on the band, then 메뉴 / 홈 across from ↩
    [(64, 10), (108, 13), (152, 10), (197, 10), (19, 10)].map { (NSPoint(x: $0.0 * K, y: Layout.seam * K), $0.1 * K) }
}
@MainActor var devSize: NSSize { NSSize(width: Layout.w * K, height: (Layout.idle * K).rounded()) }   // the idle card (a page makes it taller: Walker.cardH)
@MainActor var chevronRect: NSRect { NSRect(x: (Layout.w - 30) * K, y: 0, width: 30 * K, height: Layout.top * K) }   // the title row's ⌄ / ⌃: the status sheet

struct Shell { let name: String; let top: NSColor; var band = NSColor(red: 34 / 255, green: 37 / 255, blue: 45 / 255, alpha: 1); var dex = 0; var bp = 0 }   // bp > 0: bought at the BP exchange   // top half, band; the bottom is always white. dex = Pokédex count to unlock
let shells: [Shell] = [
    Shell(name: "몬스터볼", top: NSColor(red: 214 / 255, green: 46 / 255, blue: 42 / 255, alpha: 1)),
    Shell(name: "슈퍼볼", top: NSColor(red: 0.22, green: 0.46, blue: 0.86, alpha: 1)),
    Shell(name: "하이퍼볼", top: NSColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)),
    Shell(name: "마스터볼", top: NSColor(red: 0.47, green: 0.27, blue: 0.66, alpha: 1)),
    Shell(name: "프리미어볼", top: NSColor(white: 0.97, alpha: 1), band: NSColor(red: 0.86, green: 0.20, blue: 0.18, alpha: 1), dex: 15),
    Shell(name: "럭셔리볼", top: NSColor(white: 0.13, alpha: 1), band: NSColor(red: 0.80, green: 0.16, blue: 0.14, alpha: 1), dex: 50),
    Shell(name: "배틀 골드", top: NSColor(red: 0.86, green: 0.68, blue: 0.24, alpha: 1), band: NSColor(white: 0.12, alpha: 1), bp: 40),
]
@MainActor var theme = min(max(settings.int("shell", 0), 0), shells.count - 1)
struct LCD { let name: String; let shades: [NSColor]; var color = false }   // shade 0 (blank) ... 3 (black); `color` = sprites in their HGSS colours
let lcds: [LCD] = [
    LCD(name: "컬러", shades: [(0.97, 0.96, 0.92), (0.80, 0.80, 0.76), (0.47, 0.49, 0.53), (0.12, 0.13, 0.16)].map { NSColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }, color: true),
    LCD(name: "원작", shades: [(0.78, 0.82, 0.72), (0.58, 0.63, 0.54), (0.35, 0.39, 0.33), (0.11, 0.13, 0.11)].map { NSColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }),
    LCD(name: "백라이트", shades: [(0.62, 0.80, 0.96), (0.42, 0.60, 0.82), (0.22, 0.34, 0.55), (0.05, 0.09, 0.20)].map { NSColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }),
]
@MainActor var lcdStyle = min(max(settings.int("lcd", 0), 0), lcds.count - 1)

// MARK: - notifications (the host's banners); each kind can be switched off in the menu
let notifyKinds = [("pet", "동료가 주워 온 것"), ("hatch", "알 부화"), ("grow", "진화 · 레벨(5의 배수)"), ("weather", "날씨 변화"), ("unlock", "해금 (코스 · 기기)")]
@MainActor func notifyOn(_ k: String) -> Bool { settings.bool("notify.\(k)", true) }
final class Panel: NSPanel { override var canBecomeKey: Bool { true } }                    // arrow keys work after a click; still never activates the app
@MainActor var statusItem: NSStatusItem? = nil
