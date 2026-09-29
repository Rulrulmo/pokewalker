import Foundation
// Small helpers: the day key, Korean particles, safe indexing.

extension DateFormatter {
    static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = Calendar.current; f.timeZone = .current; return f }()
}

/// 을/를, 이/가, 은/는 by the last syllable's final consonant.
func josa(_ w: String, _ with: String, _ without: String) -> String {
    guard let u = w.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(u) else { return w + without }
    let jong = (u - 0xAC00) % 28
    return w + (jong != 0 && !(with == "으로" && jong == 8) ? with : without)                    // ㄹ takes 로, not 으로
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
