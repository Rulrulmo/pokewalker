import Foundation
// App versions as the server and the app compare them (the save server's 426, the app's updates): 2.10 > 2.9, 2.0 == 2.0.0.

/// An app version as numbers: 숫자(.숫자){0,3}; nil = not one.
func versionParts(_ v: String) -> [Int]? {
    let parts = v.split(separator: ".", omittingEmptySubsequences: false)
    let nums = parts.compactMap { p in p.allSatisfy { $0.isASCII && $0.isNumber } ? Int(p) : nil }
    return (1...4).contains(parts.count) && nums.count == parts.count ? nums : nil
}
/// -1 / 0 / 1 by number, missing parts as 0: 2.10 > 2.9, 2.0 == 2.0.0. nil = either isn't a version.
func verCmp(_ a: String, _ b: String) -> Int? {
    guard let x = versionParts(a), let y = versionParts(b) else { return nil }
    for i in 0..<4 {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p < q ? -1 : 1 }
    }
    return 0
}
