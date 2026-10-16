import Foundation
// 5.0 (the LCD's focus pages: FocusView.swift): an item's own picture — PokeAPI's item sprites by its Korean name (tools/gen.py: items.bin, cut
// to their pixels, at most 30 x 30); the mints, 로토무카탈로그 and 순백떡 (none there) drawn here; anything else a gem.

let itemData = resource("items.bin") ?? Data()
/// items.bin's names (→ their index) and where its offsets start; read once.
private let itemTable: (names: [String: Int], offsets: Int) = {
    let a = itemData
    guard a.count >= 4 else { return ([:], 0) }
    let n = Int(a[0]) | Int(a[1]) << 8 | Int(a[2]) << 16 | Int(a[3]) << 24
    var names: [String: Int] = [:], p = 4
    for k in 0..<n {
        guard p < a.count, p + 1 + Int(a[p]) <= a.count else { return ([:], 0) }
        names[String(decoding: a[(p + 1)..<(p + 1 + Int(a[p]))], as: UTF8.self)] = k; p += 1 + Int(a[p])
    }
    return (names, p)
}()
@MainActor var itemPics: [String: Pic] = [:]
/// The item's picture (cached): items.bin's, else drawn.
@MainActor func itemPic(_ name: String) -> Pic {
    if let p = itemPics[name] { return p }
    let p = packedItem(name) ?? drawnItem(name)
    itemPics[name] = p; return p
}
/// Whether items.bin has it (the self-test: every ware and bag item has a picture of its own).
func itemPacked(_ name: String) -> Bool { itemTable.names[name] != nil }
private func packedItem(_ name: String) -> Pic? {
    guard let k = itemTable.names[name] else { return nil }
    let a = itemData, o = itemTable.offsets
    func u32(_ i: Int) -> Int { Int(a[i]) | Int(a[i + 1]) << 8 | Int(a[i + 2]) << 16 | Int(a[i + 3]) << 24 }
    guard o + 4 * k + 8 <= a.count else { return nil }
    let s = u32(o + 4 * k), e = u32(o + 4 * k + 4)
    guard s < e, e <= a.count, let u = inflate(a.subdata(in: s..<e)), u.count >= 2 else { return nil }
    let w = Int(u[0]), h = Int(u[1])
    guard w > 0, h > 0, u.count >= 2 + 4 * w * h else { return nil }
    var p = Pic(w: w, h: h)
    for i in 0..<w * h where u[5 + 4 * i] != 0 { p.px[i] = rgb(u[2 + 4 * i], u[3 + 4 * i], u[4 + 4 * i]) }
    return p
}
/// What PokeAPI hasn't: a mint (SwSh's leaf, in the colour of the stat it raises), 로토무카탈로그 (an orange catalogue, Rotom's bolt), 순백떡 (a
/// white mochi on its leaf), else a gem.
private func drawnItem(_ name: String) -> Pic {
    let o = rgb(40, 44, 52)
    if case .mint(let k) = ItemKind.of(name) {
        let up = natures[k].up == natures[k].down ? -1 : natures[k].up
        let c = [rgb(240, 96, 96), rgb(244, 168, 64), rgb(96, 140, 236), rgb(96, 196, 110), rgb(236, 120, 200)][safe: up - 1] ?? rgb(200, 220, 90)
        return Pic(["......oo....", ".....oLLo...", "....oLLmmo..", "...oLLmmmo..", "..oLLmmmmo..", "..oLmmmdmo..", ".oLmmmdmmo..", ".oLmmdmmmo..", ".oLmdmmmo...",
                    ".oLdmmmmo...", "..odmmmo....", "..odooo.....", ".od.........", "od.........."], ["o": o, "L": lerpRGB(c, rgb(255, 255, 255), 0.55), "m": c, "d": lerpRGB(c, rgb(0, 0, 0), 0.3)])
    }
    if name == "로토무카탈로그" {
        return Pic(["..oooooooooooooo..", ".goRRRRRRRRRRRRRo..", "gGoRRRRRRRRRRRRRRo.", ".goRRoooooooooRRRo.", "gGoRRowwwwwwwwoRRo.", ".goRRowwBBwwwwoRRo.", "gGoRRowBBwwwwwoRRo.",
                    ".goRRowwBBBwwwoRRo.", "gGoRRowwwwBBwwoRRo.", ".goRRowwwBBwwwoRRo.", "gGoRRowwBBwwwwoRRo.", ".goRRowwwwwwwwoRRo.", "gGoRRoooooooooRRRo.", ".goRRRRRRRRRRRRRRo.",
                    "gGoRRRRYYYYYRRRRRo.", ".goRRRRRRRRRRRRRRo.", "gGoRRRRRRRRRRRRRRo.", ".goooooooooooooooo.", "..sssssssssssssss.."],
                   ["o": o, "R": rgb(236, 112, 56), "w": rgb(255, 250, 236), "B": rgb(70, 140, 236), "Y": rgb(255, 214, 90), "g": rgb(150, 156, 170), "G": rgb(210, 214, 222), "s": argb(70, rgb(40, 40, 50))])   // (its rings, its cover's window: Rotom's bolt)
    }
    if name == "특성패치" {                                                                          // 5.1 (plan 19 §3): PokeAPI has no sprite — a stitched patch, a star
        return Pic(["....oooooo....", "..ooMMMMMMoo..", ".oMsMsMsMsMMo.", ".oMMLLLLLLMso.", "oMsLLLYYLLLMMo", "oMMLLYYYYLLsMo", "oMsLYYYYYYLMMo", "oMMLLYYYYLLsMo", "oMsLLYLLYLLMMo",
                    ".oMMLLLLLLMso.", ".oMsMsMsMsMMo.", "..ooMMMMMMoo..", "....oooooo...."],
                   ["o": o, "M": rgb(160, 92, 196), "s": rgb(240, 214, 250), "L": rgb(212, 164, 232), "Y": rgb(255, 214, 90)])
    }
    if name == "지가르데셀" {                                                                        // 5.1 (plan 19 §1.4): a cell — no sprite anywhere (a count, never a bag item)
        return Pic(["....ooooo....", "..ooLLGGGoo..", ".oLLLGGGGGDo.", ".oLLooooGGDo.", "oLLoHHHHoGGDo", "oLGoHWHHoGDDo", "oGGoHHHHoGDDo", "oGGGooooGGDDo", ".oGGGGGGGDDo.", ".oDGGGGGDDDo.", "..ooDDDDDoo..", "....ooooo...."],
                   ["o": rgb(28, 60, 36), "L": rgb(150, 236, 120), "G": rgb(76, 196, 84), "D": rgb(40, 140, 60), "H": rgb(30, 110, 50), "W": rgb(200, 255, 170)])
    }
    if name == "순백떡" {
        return Pic(["....oooooo....", "..ooWWWWWWoo..", ".oWWWWWWWWWWo.", "oWWWWWWWWWWWWo", "oWWWWWPWWWWWSo", "oWWWWWWWWWWSSo", ".oSWWWWWWWSSo.", "GGooSSSSSSooGG", ".GGGooooooGGG.", "...GGGGGGGG..."],
                   ["o": o, "W": rgb(255, 255, 250), "S": rgb(222, 222, 214), "P": rgb(255, 170, 190), "G": rgb(110, 176, 92)])
    }
    return Pic(["...ooo...", "..oHLLo..", ".oHLLMMo.", "oHLLMMMDo", "oLLMMMDDo", ".oMMMDDo.", "..oMDDo..", "...ooo..."],
               ["o": o, "H": rgb(230, 244, 255), "L": rgb(140, 180, 245), "M": rgb(86, 120, 220), "D": rgb(50, 70, 160)])
}

// MARK: the panel's own pictures (5.0's UI dots): a gift, a letter, a medal, the menu's marks
enum PanelArt {
    static let o = rgb(40, 44, 52)
    /// A present (16 x 15): a red box, its gold ribbon and bow, lit along its top.
    static let gift = Pic(["...yy....yy.....", "..y..y..y..y....", "...yy.yy.yy.....", "oooooooyyooooooo", "oRRRRRRyyRRRRRRo", "oLLLLLLyyLLLLLLo", "oooooooyyooooooo",
                           ".oRRRRRyyRRRRRo.", ".oRRRRRyyRRRRRo.", ".oRRRRRyyRRRRRo.", ".oDDDDDyyDDDDDo.", ".oRRRRRyyRRRRRo.", ".oRRRRRyyRRRRRo.", ".oDDDDDYYDDDDDo.", ".oooooooooooooo."],
                          ["o": o, "R": rgb(226, 66, 58), "L": rgb(248, 120, 108), "D": rgb(176, 40, 36), "y": rgb(250, 206, 70), "Y": rgb(214, 160, 30)])
    /// A letter (16 x 12): a cream envelope, its flap's lines, a red seal.
    static let letter = Pic(["oooooooooooooooo", "oWo..........oWo", "oWWo........oWWo", "oWWWo......oWWWo", "oWWWWo....oWWWWo", "oWWWWWo..oWWWWWo", "oWWWWWWrrWWWWWWo",
                             "oWWWWWWrrWWWWWWo", "oWWWWWWWWWWWWWWo", "oSSSSSSSSSSSSSSo", "oSSSSSSSSSSSSSSo", "oooooooooooooooo"],
                            ["o": o, "W": rgb(252, 248, 234), ".": rgb(236, 230, 210), "S": rgb(226, 218, 196), "r": rgb(214, 60, 52)])
    /// A medal (12 x 16): its ribbon (red and blue), the disc in gold or silver, a star on it.
    static func medal(gold: Bool) -> Pic {
        let d = gold ? (rgb(250, 206, 70), rgb(214, 150, 30), rgb(255, 240, 170)) : (rgb(214, 220, 232), rgb(150, 158, 176), rgb(250, 252, 255))
        return Pic(["oRRo..oBBo..", "oRRRooBBBo..", ".oRRRBBBo...", "..oRRBBo....", "...oooo.....", "..oMMMMo....", ".oMHMMMMo...", "oMHMMSMMMo..",
                    "oMMMSSSMMo..", "oMMMMSMMMo..", "oMMMMMMMDo..", ".oMMMMMDo...", "..oDDDDo....", "...oooo.....", "............", "............"],
                   ["o": o, "R": rgb(214, 60, 52), "B": rgb(70, 110, 210), "M": d.0, "D": d.1, "H": d.2, "S": d.2])
    }
    /// A bush rustling (14 x 14): the 포켓 레이더's tile.
    static let radar = Pic(["......!.......", "......!.......", "..............", "......!.......", "...oooooooo...", "..oGGGLGGGGo..", ".oGLGGGGLGGGo.",
                            "oGGGGLGGGGGLGo", "oGLGGGGGLGGGGo", "oGGGGGLGGGGGGo", ".oGGGGGGGGGGo.", "..oooooooooo..", ".dd.d..d.dd.d.", ".............."],
                           ["o": rgb(40, 80, 40), "G": rgb(96, 178, 80), "L": rgb(150, 214, 110), "!": rgb(214, 60, 52), "d": rgb(150, 120, 80)])
    /// The menu's mark for a feature or a group's tile (its LCD group's, the radar's bush).
    static func menuMark(_ name: String) -> Pic? {
        let g: PageGroup? = switch name {
        case "포켓 레이더": nil
        case "코스", "모험", "전설 원정": .course; case "포켓몬": .pokemon; case "기록", "도감", "도감 업적": .dex; case "트레이너 카드": .card
        case "배틀", "배틀 타워", "대전": .tower; case "레이드": .raid; case "메가 레이드": .mega
        case "친구", "교환": .social; case "상점", "BP 교환소": .shop; case "우편함": .mail
        default: nil
        }
        if name == "포켓 레이더" { return radar }
        return g.map(LCDScenes.mark)
    }
}
