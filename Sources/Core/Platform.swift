import Foundation
// What the logic asks of the platform it runs on. A platform sets `settings` (and `fonts`: Core/Canvas.swift) first thing at launch and gives its Walker a host
// (the Mac's: Sources/Mac/MacHost.swift).

/// The menu's choices, kept between launches by key; each read passes the default the app has always had. The Mac: UserDefaults (the same keys as ever).
protocol Settings {
    func bool(_ key: String, _ def: Bool) -> Bool
    func int(_ key: String, _ def: Int) -> Int
    func set(_ key: String, _ v: Bool); func set(_ key: String, _ v: Int)
}
@MainActor var settings: (any Settings)! = nil

/// What the walker calls on (Walker.host): the view that shows it, its window, and the system's banners and step counter. The Mac's: WalkerView.
@MainActor protocol Host: AnyObject {
    /// A banner from the app: title over body.
    func notify(_ title: String, _ body: String)
    /// Keys pressed + 5 × mouse clicks this login (it may wrap): the step counter Walk.sync reads. A click is worth 5 (Walk.clickSteps): people who work
    /// with the mouse click far less often than others type.
    func counter() -> UInt32
    /// When this boot began (seconds since 1970): a new boot re-baselines the counter.
    func boot() -> Double
    /// Part of the card changed: draw it again (.all: the LCD composed afresh too).
    func redraw(_ part: CardPart)
    /// The card's size changed (Walker.cardH, or the 크기 menu: SIZE): the window follows.
    func resized()
    /// The card is hidden (in the menu bar); toggleShown() hides it or brings it back (the menu's first row).
    var windowHidden: Bool { get }
    func toggleShown()
    /// At this SIZE the tallest page still fits the screen the card is on (the 크기 menu); beep() when a pick can't be done.
    func fits(size: CGFloat) -> Bool
    func beep()
    /// A yes / no question in front of everything (the one real confirmation: 중복 놓아주기); true = ok was chosen.
    func confirm(_ title: String, _ body: String, ok: String) -> Bool
    /// A line of text asked for in front of everything (the trainer ID box: Korean input as the system has it, Return = 확인); nil = 취소.
    func askText(title: String, message: String) -> String?
    /// The same for a PIN: hidden as it's typed (Windows: digits only, 4 at most); nil = 취소.
    func askPIN(title: String, message: String) -> String?
    func quit()
}
/// What a redraw covers: the LCD, the pane's page, the 메뉴 / 홈 key, the title row, or the whole card.
enum CardPart { case lcd, page, key, title, all }

/// A bundled file's bytes by name ("hgss.bin", "Galmuri9.ttf"), from the app's Resources (the Mac's .app: Bundle.main; Windows: resourceDir,
/// a Resources folder next to the exe: Windows/WinApp.swift); nil = missing.
func resource(_ name: String) -> Data? { resourceDir.flatMap { try? Data(contentsOf: $0.appendingPathComponent(name), options: .mappedIfSafe) } }
#if !os(Windows)
var resourceDir: URL? { Bundle.main.resourceURL }
#endif

/// The app's version, platform and this PC's name, for the save server (Core/Cloud.swift). The Mac reads Info.plist's CFBundleShortVersionString; Windows has
/// no bundle, so it uses windowsVersion — bump it with Info.plist (the Mac's self-test fails until they match). The name is the kernel's host name / Windows'
/// COMPUTERNAME, never a DNS lookup (ProcessInfo.hostName can be one, and stall the main thread for seconds).
let windowsVersion = "3.2"
#if os(Windows)
let appVersion = windowsVersion, appPlatform = "windows", appDeviceName = ProcessInfo.processInfo.environment["COMPUTERNAME"] ?? "Windows"
#else
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? windowsVersion, appPlatform = "mac"
let appDeviceName: String = { var b = [CChar](repeating: 0, count: 256); return gethostname(&b, b.count) == 0 ? b.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : "Mac" }()
#endif
