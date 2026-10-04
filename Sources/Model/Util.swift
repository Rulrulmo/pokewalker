import Foundation
// Small helpers: the day key, Korean particles, safe indexing.

extension DateFormatter {
    static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = Calendar.current; f.timeZone = .current; return f }()
}

/// 을/를, 이/가, 은/는 by the last syllable's final consonant.
func josa(_ w: String, _ with: String, _ without: String) -> String {
    guard let u = w.unicodeScalars.last?.value else { return w + without }
    let digit: [UInt32: UInt32] = [0x30: 21, 0x31: 8, 0x33: 16, 0x36: 1, 0x37: 8, 0x38: 8]          // a trailing digit as read: 영 일 삼 육 칠 팔 end in a consonant (ID zz100411 → 일)
    guard (0xAC00...0xD7A3).contains(u) || (0x30...0x39).contains(u) else { return w + without }
    let jong = (0x30...0x39).contains(u) ? digit[u] ?? 0 : (u - 0xAC00) % 28
    return w + (jong != 0 && !(with == "으로" && jong == 8) ? with : without)                    // ㄹ takes 로, not 으로
}

/// SplitMix64: the app's dice (seeded at random; tests seed it to replay exactly).
struct Seeded: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}
extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
