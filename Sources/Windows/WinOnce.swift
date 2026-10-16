#if os(Windows)
import Foundation
import WinSDK
// 5.1.2 (10-16: sskim's and 문쏘's cards alive for hours yet unseen, every launch after silent — a second launch only posted "show" and went, and the
// first showed only a hidden card): one card per login, and a launch is never silent. The first is asked to come forward and must answer within
// 5 s (WinCard.comeForward). No answer (hung, or no window: quitting, stuck): an installer at work says so; else the first — found by its window or
// by running.pid, this exe's own copy — is ended and this one starts in its place; one it can't end or find is named, with what to do.

/// The card's process, for a second launch to find (written once this launch holds the mutex).
var runningFile: URL { Store.dir.appendingPathComponent("running.pid") }
func noteRunning() {
    try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
    try? "\(GetCurrentProcessId())\n\(exePath())".write(to: runningFile, atomically: true, encoding: .utf8)
}

/// A second launch (the mutex was there): returns only to start in the first's place.
@MainActor func secondLaunch() {
    var pids: [DWORD] = []
    if let h = wide("PokeWalker", { FindWindowW($0, nil) }) {
        var pid: DWORD = 0; _ = GetWindowThreadProcessId(h, &pid)
        _ = AllowSetForegroundWindow(pid)                                                         // its card may come to the front
        var answer: DWORD_PTR = 0
        if SendMessageTimeoutW(h, wmShow, 0, 0, UINT(SMTO_ABORTIFHUNG | SMTO_BLOCK), 5000, &answer) != 0, answer == 1 { exit(0) }
        if pid != 0 { pids.append(pid) }
    }
    if let at = (try? FileManager.default.attributesOfItem(atPath: Update.dir.appendingPathComponent("attempt").path))?[.modificationDate] as? Date,
       Date().timeIntervalSince(at) < 120 {                                                       // the installer started a moment ago: it starts the app itself
        say("PokeWalker 업데이트를 설치하는 중이에요.\n잠시 뒤에 다시 켜 주세요."); exit(0)
    }
    if let t = try? String(contentsOf: runningFile, encoding: .utf8), let p = t.split(separator: "\n").first.flatMap({ DWORD($0) }), !pids.contains(p) { pids.append(p) }
    let mine = exePath().lowercased()
    var ended = 0, stuck = false
    for p in pids where p != GetCurrentProcessId() {
        guard let path = imagePath(p)?.lowercased() else { continue }                             // gone already (or not ours to see)
        guard (path as NSString).lastPathComponent.hasPrefix("pokewalker") else { continue }      // the pid reused by something else
        if path == mine, end(p) { ended += 1 } else { stuck = true }
    }
    if stuck || ended == 0 && pids.isEmpty {
        say("PokeWalker가 이미 켜져 있는데 대답하지 않아요.\n작업 관리자 → 세부 정보에서 PokeWalker.exe를 끝낸 뒤 다시 켜 주세요."); exit(0)
    }
    NSLog("pokewalker: the card before didn't answer: %d ended, this one starts", ended)
}

private func say(_ text: String) {
    _ = wide(text) { b in wide("PokeWalker") { t in MessageBoxW(nil, b, t, UINT(MB_OK) | UINT(MB_ICONINFORMATION) | UINT(MB_TOPMOST) | UINT(MB_SETFOREGROUND)) } }
}
private func exePath() -> String {
    var path = [WCHAR](repeating: 0, count: 32768)
    let n = Int(GetModuleFileNameW(nil, &path, DWORD(path.count)))
    return String(decoding: path[..<n], as: UTF16.self)
}
private func imagePath(_ pid: DWORD) -> String? {
    guard let h = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return nil }
    defer { _ = CloseHandle(h) }
    var buf = [WCHAR](repeating: 0, count: 32768), n = DWORD(buf.count)
    guard QueryFullProcessImageNameW(h, 0, &buf, &n) else { return nil }
    return String(decoding: buf[..<Int(n)], as: UTF16.self)
}
/// Ended and waited for (5 s at most); true = it's gone.
private func end(_ pid: DWORD) -> Bool {
    guard let h = OpenProcess(DWORD(PROCESS_TERMINATE) | DWORD(SYNCHRONIZE), false, pid) else { return false }
    defer { _ = CloseHandle(h) }
    _ = TerminateProcess(h, 1)
    return WaitForSingleObject(h, 5000) == 0                                                      // WAIT_OBJECT_0
}
#endif
