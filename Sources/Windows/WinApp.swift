#if os(Windows)
import Foundation
import WinSDK
// Windows' launch (App/main.swift calls it): --selftest, --render <dir> (the CI's shots), or the app — one card per login (a second launch shows the
// first's), per-monitor DPI, the save and the settings in %APPDATA%\PokeWalker, the card (Windows/WinCard.swift) and its message loop.

/// A Resources folder next to PokeWalker.exe: Core/Platform.swift's resource() (the Mac's: the .app's).
let resourceDir: URL? = {
    var path = [WCHAR](repeating: 0, count: 32768)                                               // the longest path Windows has
    let n = Int(GetModuleFileNameW(nil, &path, DWORD(path.count)))
    guard n > 0 else { return nil }
    return URL(fileURLWithPath: String(decoding: path[..<n], as: UTF16.self)).deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true)
}()

@MainActor func windowsMain() -> Never {
    SetConsoleOutputCP(UINT(CP_UTF8))                                                             // the Korean check names, readable in a console / the CI log
    let args = CommandLine.arguments
    if args.contains("--selftest") || args.contains("--render") {                                 // headless: settings in memory, never the save
        settings = JSONSettings(file: nil)                                                        // before anything reads a setting (the look's globals)
        let f = WinFonts(); fonts = f; textMasks = f                                              // before anything lays out text
        if let i = args.firstIndex(of: "--render") { print("rendered \(renderShots(args.count > i + 1 ? args[i + 1] : "renders")) shots"); exit(0) }   // Windows/WinRender.swift
        print("fonts: " + [FontSpec(size: 12), FontSpec(size: 10, face: .galmuri9), FontSpec(size: 8, face: .galmuri7)].map(f.face).joined(separator: " · ")   // what GDI picked (a missing face falls back silently)
              + " · 가…하 at 9 pt \(f.width("가나다라마바사아자차카타파하", FontSpec(size: 9))) (the Mac 108.99) · 0…g \(f.width("0123456789 ABCDEFG abcdefg", FontSpec(size: 9))) (140.81)")
        print("metrics (ascender, cap height) at 10 / 13 / 16 pt: " + ([10, 13, 16] as [CGFloat]).map { "\(f.metrics(FontSpec(size: $0)))" }.joined(separator: " · ") + " (the Mac's SF: 9.67 7.05 · 12.57 9.16 · 15.47 11.27)")
        print("store: \(Store.file.path) (Foundation's application support: \(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? "-"))")
        exit(selftest() ? 0 : 1)
    }
    _ = wide("Local\\dev.khmin.pokewalker") { CreateMutexW(nil, false, $0) }                      // one card per login: a second launch shows the first's
    if GetLastError() == DWORD(ERROR_ALREADY_EXISTS) { secondLaunch() }                          // 5.1.2: the first comes forward, or this starts in its place (WinOnce.swift)
    noteRunning()
    _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4))                      // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: sharp on every monitor
    settings = JSONSettings(file: Store.dir.appendingPathComponent("settings.json"))
    let launch = Update.atLaunch()                                                                // a downloaded update goes in first: the helper starts it once this exits
    if launch == .installing { exit(0) }
    if launch == .waiting { sayInstalling(); exit(0) }                                            // 5.2 (③): its installer still at work (a launch right after the app quit for it)
    let f = WinFonts(); fonts = f; textMasks = f
    let loaded = Store.loadChecked(signedBefore: settings.bool("saveSigned", false))           // a save changed by hand: the last one the app made
    Content.atLaunch(loaded.walk)                                                               // 5.1.1: the server's switches as last heard, before the save is used
    let walker = Walker(state: loaded.walk), c = WinCard(walker: walker); card = c              // the card is the walker's host
    walker.startCloud(Cloud.app(persist: walker.persist))                                         // the save server, if on: a 1.x save goes aside first (08 §5)
    walker.updater = Updater.app(persist: walker.persist)
    walker.state.dex()
    walker.awaySteps(counter: c.counter(), boot: c.boot())                                       // a new launch only baselines: steps while it was closed can't be seen
    if case .updated(let v) = launch { walker.announceUpdate(v) }
    walker.lookForOldApps()                                                                      // 5.0: once, a zip's old folder may go
    walker.tipsOn = walker.persist; walker.tipBits = settings.int("tips5", 0)                   // 5.0: the first-time tips (Tips.swift)
    walker.save()
    walker.refreshPane(Date(), force: true)                                                      // the page it opens on (the status sheet)
    c.open(); settings.set("hidden", false)                                                      // a launch always shows it
    var msg = MSG()
    while Bool(GetMessageW(&msg, nil, 0, 0)) { _ = TranslateMessage(&msg); _ = DispatchMessageW(&msg) }
    walker.save()
    exit(0)
}
#endif
