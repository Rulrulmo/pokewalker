import Foundation
// docs/plans/19 §11.4 (5.2, content52): 기술머신 — ORAS's 100 TMs and 7 HMs less 순서미루기 (TM60: doubles only), 106 with 프리폴 (TM58).
// Bought once at the W 상점, kept for good: a trainer's are numbers in the save (Walk.tms), not bag items — a course's second copy of one stays
// a bag item to sell (50 W) as before, and a 5.1.x app never sees them to sell. Taught at 기술 바꾸기: Walk.relearnable(_:), the one list the
// server's check and the app's screens read. The tables: Data/Machines.swift (tools/oras_tms.py --swift).

enum Machines {
    static let skipped: Set<Int> = [60]                                  // 순서미루기
    static let hm = 100                                                  // 101-107 = 비전머신01-07
    /// What the shop sells, in number order: every machine whose move this engine plays.
    static var sold: [Int] { (1...107).filter { !skipped.contains($0) && Moves.supported(machineMoves[$0]) } }
    static func move(_ no: Int) -> Int { machineMoves.indices.contains(no) ? machineMoves[no] : 0 }
    /// "기술머신07" · "비전머신03" (a course's bag item has the same name).
    static func name(_ no: Int) -> String { no > hm ? "비전머신" + two(no - hm) : "기술머신" + two(no) }
    static func number(_ name: String) -> Int? {
        if name.hasPrefix("기술머신"), let n = Int(name.dropFirst(4)), (1...hm).contains(n) { return n }
        if name.hasPrefix("비전머신"), let n = Int(name.dropFirst(4)), (1...7).contains(n) { return hm + n }
        return nil
    }
    private static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    /// Its price (plan 19 §2.2): 3,000 W at power 90 on; 2,000 W at 60–89, the variable-power hits (화풀이 은혜갚기 내던지기 자이로볼 풀묶기) and
    /// four strong status moves (명상 칼춤 벌크업 맹독); 1,000 W for the rest of the status moves and the weaker hits.
    static func price(_ no: Int) -> Int {
        guard let m = moveTable[move(no)] else { return 3000 }
        if m.isStatus { return [347, 14, 339, 92].contains(m.id) ? 2000 : 1000 }
        if m.power == 0 || (60..<90).contains(m.power) { return 2000 }
        return m.power >= 90 ? 3000 : 1000
    }
    /// Species dex learns machine no (ORAS; a form as its species).
    static func learns(_ dex: Int, _ no: Int) -> Bool {
        guard machineLearners.indices.contains(dex), (1...107).contains(no) else { return false }
        let hex = Array(machineLearners[dex]), at = hex.count - 1 - no / 4
        guard at >= 0, let digit = Int(String(hex[at]), radix: 16) else { return false }
        return digit >> (no % 4) & 1 == 1
    }
}

extension Walk {
    /// The machines this trainer has (none before 5.2).
    var machines: Set<Int> { Set(tms ?? []) }
    /// 기술 바꾸기's list (plan 19 §11.4): what it learns by level and the added signature moves (Mon.relearnable), then — content52 — the moves
    /// of the machines this trainer has that its species learns, and 레쿠쟈's 화룡점정 once the 레쿠쟈 원정 is done. The server's check and the
    /// app's screens read this one; the tower's foes keep Mon.relearnable (no machines).
    func relearnable(_ m: Mon) -> [Int] {
        var out = m.relearnable
        guard Content.v52 else { return out }
        for mv in machineMoves(m) where !out.contains(mv) { out.append(mv) }
        if m.dex == 384, (expeditions?["레쿠쟈"]?.done ?? 0) > 0, !out.contains(620) { out.append(620) }
        return out
    }
    /// Of those, the ones from this trainer's machines (the list's "TM" mark), in number order.
    func machineMoves(_ m: Mon) -> [Int] {
        guard Content.v52 else { return [] }
        return (tms ?? []).sorted().filter { !Machines.skipped.contains($0) && Machines.learns(m.dex, $0) }.map(Machines.move).filter(Moves.supported)
    }
}

extension Walk {
    /// A 기술머신 row's note: its move's type and power ("땅 · 위력 100 · 명중 100"; a status move: "변화").
    static func machineNote(_ no: Int) -> String {
        guard let m = moveTable[Machines.move(no)] else { return "" }
        let t = typeKo[m.type] ?? m.type
        return m.isStatus ? t + " · 변화" : t + " · 위력 " + (m.power > 0 ? "\(m.power)" : "-") + (m.accuracy > 0 ? " · 명중 \(m.accuracy)" : "")
    }
    /// 5.2 (plan 19 §11.4), content52: a machine in the bag (a course's, from before or found now) that isn't had yet becomes one had — one copy
    /// of each number; the others stay in the bag to sell. True when the save changed.
    @discardableResult mutating func adoptMachines() -> Bool {
        guard Content.v52 else { return false }
        var had = machines, changed = false
        for (k, i) in bag.enumerated().reversed() {
            guard let no = Machines.number(i), !Machines.skipped.contains(no), !had.contains(no) else { continue }
            bag.remove(at: k); had.insert(no); changed = true
        }
        if changed { tms = had.sorted() }
        return changed
    }
}
