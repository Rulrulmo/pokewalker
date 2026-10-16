import Foundation
import Testing
@testable import PokeCore

// docs/plans/22 (5.1.2): rollout — the candidate (release-next) to some trainers first, only to apps already at the stable version; a download
// told apart by its User-Agent's version; update-note — "update": {v, urgent} first in a reply to an app with a newer version for it.

private func plan(_ p: RolloutPlan?, kinds: Set<String> = ["mac", "windows-setup"], note: Bool = true) -> RolloutNow {
    RolloutNow(stable: "5.1.1", next: "5.1.2", nextKinds: kinds, plan: p, note: note, urgent: true)
}

@Test func rolloutOffer() {
    let named = plan(RolloutPlan(names: ["앨리스"]))
    #expect(named.offer(key: "앨리스", app: "5.1.1", platform: "mac") == "5.1.2")
    #expect(named.offer(key: "앨리스", app: "5.1.2", platform: "windows") == "5.1.2")              // already there: nothing newer
    #expect(named.offer(key: "앨리스", app: "5.0.1", platform: "mac") == "5.1.1")                  // an older app: the stable first
    #expect(named.offer(key: "밥", app: "5.1.1", platform: "mac") == "5.1.1")
    #expect(named.offer(key: nil, app: "5.1.1", platform: "mac") == "5.1.1")                       // no trainer said (before 5.0): the stable
    #expect(plan(nil).offer(key: "앨리스", app: "5.1.1", platform: "mac") == "5.1.1")               // off
    #expect(plan(RolloutPlan(names: ["앨리스"]), kinds: ["mac"]).offer(key: "앨리스", app: "5.1.1", platform: "windows") == "5.1.1")   // no installer there
    var same = named; same.next = "5.1.1"
    #expect(same.offer(key: "앨리스", app: "5.1.1", platform: "mac") == "5.1.1" && !same.nextAhead)  // promoted: nothing to roll out
    #expect(RolloutNow().offer(key: "앨리스", app: "5.1.1", platform: "mac") == nil)                 // nothing signed
    #expect(plan(RolloutPlan(percent: 100)).offer(key: "아무나", app: "5.1.1", platform: "windows") == "5.1.2")
    #expect(plan(RolloutPlan(percent: 0)).offer(key: "아무나", app: "5.1.1", platform: "windows") == "5.1.1")
}

@Test func rolloutShare() {
    let keys = (0..<2000).map { "트레이너\($0)" }
    let p = plan(RolloutPlan(percent: 20))
    let n = keys.filter(p.targets).count
    #expect(abs(n - 400) < 60)                                                                     // about a fifth
    #expect(keys.filter(p.targets) == keys.filter(p.targets))                                    // the same ones each time
    var later = p; later.next = "5.1.3"
    #expect(Set(keys.filter(p.targets)) != Set(keys.filter(later.targets)))                       // another version: others first
    var wider = p; wider.plan = RolloutPlan(percent: 50)
    #expect(Set(keys.filter(p.targets)).isSubset(of: Set(keys.filter(wider.targets))))           // widening keeps the first ones
}

@Test func rolloutDownloads() {
    let p = plan(RolloutPlan(names: ["앨리스"]))
    #expect(p.downloadsNext(app: "5.1.1") && !p.downloadsNext(app: "5.0.1") && !p.downloadsNext(app: "5.1.2") && !p.downloadsNext(app: nil))
    #expect(plan(nil).downloadsNext(app: "5.1.1"))                                               // by the version alone: offered while on, fetched after
    #expect(!RolloutNow(stable: "5.1.1").downloadsNext(app: "5.1.1"))                             // no candidate
}

@Test func rolloutNote() {
    let p = plan(RolloutPlan(names: ["앨리스"]))
    #expect(p.noteJSON(key: "앨리스", app: "5.1.1", platform: "mac") == #"{"urgent":true,"v":"5.1.2"}"#)
    #expect(p.noteJSON(key: "밥", app: "5.1.1", platform: "mac") == nil)                          // up to date
    #expect(p.noteJSON(key: "밥", app: "5.0.1", platform: "windows") == #"{"urgent":true,"v":"5.1.1"}"#)
    #expect(p.noteJSON(key: "밥", app: "3.9", platform: "windows") == nil)                        // a broken updater: never told
    #expect(plan(RolloutPlan(names: ["앨리스"]), note: false).noteJSON(key: "앨리스", app: "5.0.1", platform: "mac") == nil)   // update-note off
    let note = #"{"urgent":true,"v":"5.1.2"}"#
    #expect(withUpdateNote(Data("{}".utf8), note) == Data(#"{"update":{"urgent":true,"v":"5.1.2"}}"#.utf8))
    let body = Data(#"{"out":{"changed":true},"rev":7}"#.utf8), spliced = withUpdateNote(body, note)
    #expect(spliced == Data(#"{"update":{"urgent":true,"v":"5.1.2"},"out":{"changed":true},"rev":7}"#.utf8))
    let j = try? JSONSerialization.jsonObject(with: spliced) as? [String: Any]
    #expect((j?["rev"] as? Int) == 7 && ((j?["update"] as? [String: Any])?["v"] as? String) == "5.1.2")
    #expect(withUpdateNote(Data("[1]".utf8), note) == Data("[1]".utf8))
    let act = try? JSONEncoder().encode(ActReply(rev: 3, out: Outcome()))                         // the app's ActReply reads it (and an old one skips it)
    let read = act.flatMap { try? JSONDecoder().decode(ActReply.self, from: withUpdateNote($0, note)) }
    #expect(read?.update == UpdateNote(v: "5.1.2", urgent: true) && read?.rev == 3)
    struct OldActReply: Decodable { var rev: Int; var out: Outcome }
    #expect(act.flatMap { try? JSONDecoder().decode(OldActReply.self, from: withUpdateNote($0, note)) }?.rev == 3)
}

@Test func rolloutSettings() async throws {
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    _ = await db.create(CreateReq(id: "앨리스", device: "mac", device_name: "MAC", app: "5.1", pin: "2468"), now: 100)
    _ = await db.create(CreateReq(id: "밥밥", device: "mac", device_name: "MAC", app: "5.1", pin: "2468"), now: 100)
    let p0 = try await db.rolloutPlan(), n0 = try await db.updateNote()
    #expect(p0 == nil && !n0)
    _ = try await db.setRollout("20%"); #expect(try await db.rolloutPlan() == RolloutPlan(percent: 20))
    _ = try await db.setRollout("앨리스,밥밥"); #expect(try await db.rolloutPlan() == RolloutPlan(names: ["앨리스", "밥밥"]))
    await #expect(throws: (any Error).self) { try await db.setRollout("앨리스,없는사람") }
    await #expect(throws: (any Error).self) { try await db.setRollout("120%") }
    #expect(try await db.rolloutPlan() == RolloutPlan(names: ["앨리스", "밥밥"]))                  // a refused one leaves it as it was
    _ = try await db.setRollout("off"); #expect(try await db.rolloutPlan() == nil)
    _ = try await db.setUpdateNote(true); let n1 = try await db.updateNote(); #expect(n1)
    let none = URL(fileURLWithPath: path + "-norelease"), s = await db.rolloutState(release: none, next: none)
    #expect(s.stable == nil && s.next == nil && s.note)                                          // no signed manifest: nothing offered
}

// 5.1.2: /v1/update's installLog — install.log's last lines, kept per trainer (a report without one keeps the last), shown in pokeserver versions.
@Test func installLogKept() async throws {
    #expect(installLogLine("a\r\nb\n\n  c \u{7}\n") == "a ⏎ b ⏎ c" && installLogLine("\n \n") == nil && installLogLine(String(repeating: "x", count: 500))?.count == 300)
    let r = try JSONDecoder().decode(UpdateReq.self, from: Data(#"{"app":"5.1.2","platform":"windows","trainer":"앨리스","installLog":"wait 1234\nswap failed"}"#.utf8))
    #expect(r.installLog == "wait 1234\nswap failed")
    let (db, path) = try tempDB(); defer { try? FileManager.default.removeItem(atPath: path) }
    _ = await db.create(CreateReq(id: "앨리스", device: "pc", device_name: "PC", app: "5.1.1", pin: "2468"), now: 100)
    try await db.recordUpdateReport(r, now: 200)
    try await db.recordUpdateReport(UpdateReq(app: "5.1.2", platform: "windows", trainer: "앨리스"), now: 300)   // the next hour's, none sent
    let v = try await db.versionsReport(now: 400)
    #expect(v.contains("앨리스") && v.contains("wait 1234 ⏎ swap failed"))
}
