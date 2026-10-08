import Foundation
// 3.9 (docs/plans/15 §2, §6 A): the 우편함 — gifts and notices from the server.

extension Walker {
    /// 우편함's red dot: unread mail, or gifts not yet taken.
    var mailDot: Bool { false }
    /// 우편함's line on the menu.
    var mailNote: String { "보상 · 공지" }
    func openMail(_ now: Date) { screen = .say(["우편함은 준비 중이에요"], next: menuFor("우편함"), since: now) }
}
