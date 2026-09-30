#if os(Windows)
import Foundation
import WinSDK
// Windows' launch (App/main.swift calls it): --selftest for now; the window, tray, menu and steps come in P3 (docs/windows-port.md).

/// A Resources folder next to PokeWalker.exe: Core/Platform.swift's resource() (the Mac's: the .app's).
let resourceDir: URL? = {
    var path = [WCHAR](repeating: 0, count: 32768)                                               // the longest path Windows has
    let n = Int(GetModuleFileNameW(nil, &path, DWORD(path.count)))
    guard n > 0 else { return nil }
    return URL(fileURLWithPath: String(decoding: path[..<n], as: UTF16.self)).deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true)
}()

/// Settings held in memory, gone at exit: the self-test's (P3: %APPDATA%\PokeWalker\settings.json).
final class MemorySettings: Settings {
    var values: [String: Int] = [:]
    func bool(_ key: String, _ def: Bool) -> Bool { values[key].map { $0 != 0 } ?? def }
    func int(_ key: String, _ def: Int) -> Int { values[key] ?? def }
    func set(_ key: String, _ v: Bool) { values[key] = v ? 1 : 0 }
    func set(_ key: String, _ v: Int) { values[key] = v }
}

@MainActor func windowsMain() -> Never {
    SetConsoleOutputCP(UINT(CP_UTF8))                                                             // the Korean check names, readable in a console / the CI log
    settings = MemorySettings()                                                                   // before anything reads a setting (the look's globals)
    let f = WinFonts(); fonts = f                                                                 // before anything lays out text
    if CommandLine.arguments.contains("--selftest") {
        print("fonts: " + [FontSpec(size: 12), FontSpec(size: 10, face: .galmuri9), FontSpec(size: 8, face: .galmuri7)].map(f.face).joined(separator: " · ")   // what GDI picked (a missing face falls back silently)
              + " · 가…하 at 9 pt \(f.width("가나다라마바사아자차카타파하", FontSpec(size: 9))) (the Mac 108.99) · 0…g \(f.width("0123456789 ABCDEFG abcdefg", FontSpec(size: 9))) (140.81)")
        exit(selftest() ? 0 : 1)
    }
    print("PokeWalker for Windows: the window comes in P3")
    exit(0)
}
#endif
