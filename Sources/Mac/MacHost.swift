import AppKit
import UserNotifications
// The Mac's side of Core/Platform.swift: settings in UserDefaults, banners, the step counter.

extension UserDefaults: Settings {
    func bool(_ key: String, _ def: Bool) -> Bool { object(forKey: key) == nil ? def : bool(forKey: key) }
    func int(_ key: String, _ def: Int) -> Int { object(forKey: key) == nil ? def : integer(forKey: key) }
    func string(_ key: String, _ def: String) -> String { string(forKey: key) ?? def }
    func data(_ key: String) -> Data? { data(forKey: key) }
    func set(_ key: String, _ v: Bool) { set(v, forKey: key) }
    func set(_ key: String, _ v: Int) { set(v, forKey: key) }
    func set(_ key: String, _ v: String) { set(v, forKey: key) }
    func set(_ key: String, _ v: Data) { set(v, forKey: key) }
}

nonisolated(unsafe) var useOsascript = false                                                  // set once at launch, read on the main thread
final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }
}
final class MacHost: Host {
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
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown].reduce(UInt32(0)) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }
    func boot() -> Double { var tv = timeval(), n = MemoryLayout<timeval>.size; sysctlbyname("kern.boottime", &tv, &n, nil, 0); return Double(tv.tv_sec) }
}
