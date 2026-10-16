import Foundation
// 5.1.1 (10-16, krackde's dump: Walk.here trapped before the window — a 하나 · 칼로스 course, 35+, read with content5 not known yet): self-test
// checks (run by selftest()) — the course from the whole list and unlocked never past the list's end, the course page clamped, the launch's
// switches as last heard (the settings) or as the save says (a new install), the login's kept for the next launch; such a save opened and drawn
// with content5 off, as 5.1's launch did.

@MainActor func launch511Checks() -> [(Bool, String)] {
    var c: [(Bool, String)] = []
    let was = (Content.on, Content.on51, Content.onDaily), keys = ["content5", "content51", "raidDaily"], kept = keys.map { settings.int($0, 0) }
    defer { (Content.on, Content.on51, Content.onDaily) = was; for (k, v) in zip(keys, kept) { settings.set(k, v) } }
    func flags(_ a: Bool, _ b: Bool, _ d: Bool) { settings.set("content5", a); settings.set("content51", b); settings.set("raidDaily", d) }
    var kalos = Walk(); kalos.course = 41; kalos.courseSteps = 7247; kalos.companion = Mon(dex: 310, level: 40, female: false)
    var kanto = Walk(); kanto.course = 3; kanto.companion = Mon(dex: 25, level: 20, female: false)
    var sixth = kanto; sixth.companion = Mon(dex: 650, level: 20, female: false)
    // Walk.here, unlocked, the course page with content5 off
    var here = false, page = false
    Content.$testing.withValue(false) {
        var w = kalos; here = w.here.name == coursesGen6[41].name && !w.unlocked(41) && w.unlocked(0)
        w.course = 999; here = here && w.here.name == coursesGen6[0].name
        let v = Walker(state: kalos); v.persist = false; v.host = TestHost()
        v.screen = .course(41); page = v.paneContent(Date()).course != nil; _ = v.compose(Date())     // (the LCD too)
        v.openFeature("코스"); _ = v.compose(Date()); page = page && v.paneContent(Date()).course != nil
    }
    // the launch: as last heard; a new install: as the save says
    Content.on = false; flags(false, false, false); Content.atLaunch(kalos); let fromCourse = Content.on
    Content.on = false; Content.atLaunch(sixth); let fromMon = Content.on
    Content.on = true; Content.atLaunch(kanto); let plain = !Content.on && !Content.on51 && !Content.onDaily
    flags(true, true, true); Content.atLaunch(kanto); let heard = Content.on && Content.on51 && Content.onDaily
    // a login keeps what it says
    flags(false, false, false)
    let sv = FakeCloud(); sv.content5 = true; sv.content51 = true; sv.raidDaily = false
    let w = online(kanto, server: sv); _ = w
    let keptLogin = settings.bool("content5", false) && settings.bool("content51", false) && !settings.bool("raidDaily", true)
    // 5.1's launch, but fixed: the Kalos save opened and drawn before any login, with the switches off (none heard, the old way)
    var drawn = false
    Content.on = false; Content.on51 = false; Content.onDaily = false
    do {
        let v = Walker(state: kalos); v.persist = false; v.host = TestHost()
        v.state.dex(); v.awaySteps(counter: 0, boot: Date().timeIntervalSince1970); v.refreshPane(Date(), force: true)
        _ = v.compose(Date()); v.tick(Date()); let t = v.title(); drawn = v.state.course == 41 && v.state.courseSteps == 7247 && !t.title.isEmpty
        if !drawn { print("launch511 drawn: course \(v.state.course) steps \(v.state.courseSteps) title \(t)") }
    }
    c.append((here && page && fromCourse && fromMon && plain && heard && keptLogin && drawn,
              "5.1.1 launch: Walk.here from the whole list (course 41 with content5 off: its own; 999: the first), unlocked past the end: no, the course page clamped; at launch the switches as last heard, a new install's content5 from the save (course 35+, a Pokémon past 493); the login's kept; a Kalos save opened and drawn with the switches off, its course kept"))
    if !(here && page && fromCourse && fromMon && plain && heard && keptLogin && drawn) { print("launch511: \(here) \(page) \(fromCourse) \(fromMon) \(plain) \(heard) \(keptLogin) \(drawn)") }
    return c
}
