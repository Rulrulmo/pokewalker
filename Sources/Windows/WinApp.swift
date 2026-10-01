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

/// The menu's choices as JSON (the Mac's UserDefaults keys; bools 0 / 1), written on each change; no file = in memory (the self-test, --render).
final class JSONSettings: Settings {
    var values: [String: Int] = [:]
    let file: URL?
    init(file: URL?) {
        self.file = file
        if let file, let d = try? Data(contentsOf: file), let v = try? JSONDecoder().decode([String: Int].self, from: d) { values = v }
    }
    func bool(_ key: String, _ def: Bool) -> Bool { values[key].map { $0 != 0 } ?? def }
    func int(_ key: String, _ def: Int) -> Int { values[key] ?? def }
    func set(_ key: String, _ v: Bool) { set(key, v ? 1 : 0) }
    func set(_ key: String, _ v: Int) {
        guard values[key] != v else { return }
        values[key] = v
        guard let file else { return }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .prettyPrinted]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? e.encode(values).write(to: file, options: .atomic)
    }
}

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
    if GetLastError() == DWORD(ERROR_ALREADY_EXISTS) {
        if let h = wide("PokeWalker", { FindWindowW($0, nil) }) { _ = PostMessageW(h, wmShow, 0, 0) }
        exit(0)
    }
    _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4))                      // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: sharp on every monitor
    settings = JSONSettings(file: Store.dir.appendingPathComponent("settings.json"))
    let f = WinFonts(); fonts = f; textMasks = f
    let walker = Walker(state: Store.load()), c = WinCard(walker: walker); card = c              // the card is the walker's host
    walker.state.dex()
    walker.levelled = walker.state.sync(counter: c.counter(), boot: c.boot(), at: Date())        // a new launch only baselines: steps while it was closed can't be seen
    walker.save()
    walker.refreshPane(Date(), force: true)                                                      // the page it opens on (the status sheet)
    c.open(); settings.set("hidden", false)                                                      // a launch always shows it
    walker.sideOn = true
    var msg = MSG()
    while Bool(GetMessageW(&msg, nil, 0, 0)) { _ = TranslateMessage(&msg); _ = DispatchMessageW(&msg) }
    walker.save()
    exit(0)
}
#endif
