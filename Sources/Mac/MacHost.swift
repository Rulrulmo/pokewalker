#if os(macOS)
import AppKit
import UserNotifications
// The Mac's side of Core/Platform.swift: settings in UserDefaults; the walker's host is its view, WalkerView (its redraws: Mac/WalkerView.swift), with the banners,
// the step counter and the window's dialogs here.

extension UserDefaults: Settings {
    func bool(_ key: String, _ def: Bool) -> Bool { object(forKey: key) == nil ? def : bool(forKey: key) }
    func int(_ key: String, _ def: Int) -> Int { object(forKey: key) == nil ? def : integer(forKey: key) }
    func set(_ key: String, _ v: Bool) { set(v, forKey: key) }
    func set(_ key: String, _ v: Int) { set(v, forKey: key) }
}

nonisolated(unsafe) var useOsascript = false                                                  // set once at launch, read on the main thread
final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }
}
extension WalkerView: Host {
    func notify(_ title: String, _ body: String) {
        if useOsascript {                                                                        // shows as "스크립트 편집기" in Notification Center
            func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "display notification \(q(body)) with title \(q("PokeWalker")) subtitle \(q(title))"]
            try? p.run(); return
        }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    func counter() -> UInt32 {
        func n(_ t: CGEventType) -> UInt32 { CGEventSource.counterForEventType(.hidSystemState, eventType: t) }   // the keyboard's and mouse's own: what an app posts doesn't count
        return n(.keyDown) &+ UInt32(Walk.clickSteps) &* (n(.leftMouseDown) &+ n(.rightMouseDown))
    }
    func boot() -> Double { var tv = timeval(), n = MemoryLayout<timeval>.size; sysctlbyname("kern.boottime", &tv, &n, nil, 0); return Double(tv.tv_sec) }
    // the window's: Mac/MenuBar.swift (toggleShown(_:), fits(size:))
    var windowHidden: Bool { window?.isVisible == false }
    func toggleShown() { toggleShown(nil) }
    func beep() { NSSound.beep() }
    func confirm(_ title: String, _ body: String, ok: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)                                                   // the only time it takes focus: a real confirmation
        let a = NSAlert(); a.messageText = title; a.informativeText = body
        a.addButton(withTitle: ok); a.addButton(withTitle: "취소")
        return a.runModal() == .alertFirstButtonReturn
    }
    func quit() { NSApp.terminate(nil) }
}
#endif
