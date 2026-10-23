import Foundation
// 5.2 (the 준쵸리 report 10-21, the Mac's ①~④; the user via 회사 10-23: "5.2에 다 포함할거야"): the update's install, checked on a scratch update
// folder — ① the app's own lines (app.log) after the installer's in the report's installLog, a give-up saying what it found; ③ a launch right
// after the app quit for its installer waits while the installer is at work (Windows: Launch.waiting); ④ a failed version once more after a day
// (or at once when urgent), never a third time.

@MainActor func update52Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let fm = FileManager.default, dir = fm.temporaryDirectory.appendingPathComponent("pokewalker-update52-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    try? fm.removeItem(at: dir); try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    // ④: when it failed, urgent, the one retry
    let now = Date(), day = 86_400.0
    try? "5.1.4\n5.1.5 \(Int(now.timeIntervalSince1970 - 2 * 3600))\n5.1.6 \(Int(now.timeIntervalSince1970 - 2 * day))\n".write(to: dir.appendingPathComponent("failed"), atomically: true, encoding: .utf8)
    let calm = Update.blocked(dir, urgent: false, now: now), hurry = Update.blocked(dir, urgent: true, now: now)
    Update.retrying("5.1.6", dir); Update.retrying("5.2", dir)
    let after = Update.blocked(dir, urgent: true, now: now)
    let retry = Update.failed(dir) == ["5.1.4", "5.1.5", "5.1.6"] && calm == ["5.1.5"] && hurry.isEmpty && after == ["5.1.6"]
    // ①: the installer's lines (UTF-16LE), then the app's
    var log = Data([0xFF, 0xFE]); for u in "started 5.2\r\nclosing 5.2: PokeWalker, if it runs\r\n".utf16 { log.append(UInt8(u & 0xFF)); log.append(UInt8(u >> 8)) }
    try? log.write(to: dir.appendingPathComponent("install.log"))
    Update.note("5.2's setup didn't start: an error", dir)
    let merged = Update.installLog(dir) == "started 5.2 | closing 5.2: PokeWalker, if it runs | app: 5.2's setup didn't start: an error"
    // ③: busy while under 3 minutes and the installer's last line isn't an end
    let busy = Update.setupBusy(attemptAge: 20, lastLine: "closing 5.2: PokeWalker, if it runs") && Update.setupBusy(attemptAge: 40, lastLine: nil)
        && !Update.setupBusy(attemptAge: 20, lastLine: "installed 5.2") && !Update.setupBusy(attemptAge: 20, lastLine: "failed 5.2: files couldn't be written") && !Update.setupBusy(attemptAge: 400, lastLine: "writing 5.2: x")
    c.append((retry && merged && busy, "5.2 update ①③④: a failed version once more a day after (at once when urgent), never a third time; the app's own line after the installer's in installLog; a relaunch waits while the installer is at work (under 3 minutes, no end line)"
              + (retry && merged && busy ? "" : " — \(calm) \(hurry) \(after) \(String(describing: Update.installLog(dir))) \(busy)")))
    return c
}
