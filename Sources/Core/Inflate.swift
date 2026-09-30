import Foundation
// Raw DEFLATE (RFC 1951) in plain Swift: anims.bin's and walk.bin's blocks (tools/gen.py), without Apple's own zlib (Foundation's decompression is Apple-only).

/// A canonical Huffman code: how many codes of each length 1...15, and the symbols in code order.
private struct Huff {
    var count = [Int](repeating: 0, count: 16), symbol: [Int] = []
    /// From each symbol's code length (0 = unused); nil = over-subscribed (more codes than the lengths allow).
    init?(_ lens: [Int]) {
        for l in lens { count[l] += 1 }
        count[0] = 0; var left = 1
        for l in 1...15 { left = left * 2 - count[l]; if left < 0 { return nil } }         // an incomplete code is fine (one distance code, say)
        var offs = [Int](repeating: 0, count: 16)
        for l in 1..<15 { offs[l + 1] = offs[l] + count[l] }
        symbol = [Int](repeating: 0, count: lens.count)
        for (s, l) in lens.enumerated() where l > 0 { symbol[offs[l]] = s; offs[l] += 1 }
    }
}
private let lenBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
private let lenExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
private let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
private let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
private let fixedLit = Huff((0..<288).map { $0 < 144 ? 8 : $0 < 256 ? 9 : $0 < 280 ? 7 : 8 })!, fixedDist = Huff([Int](repeating: 5, count: 30))!

/// A raw DEFLATE stream (no zlib header: what Apple's .zlib reads) unpacked: stored, fixed and dynamic Huffman blocks; nil = broken or cut short.
func inflate(_ data: Data) -> [UInt8]? {
    let s = [UInt8](data); var out: [UInt8] = [], at = 0, buf = 0, n = 0                       // n bits waiting in buf, the next one lowest
    func bits(_ k: Int) -> Int? {
        while n < k { guard at < s.count else { return nil }; buf |= Int(s[at]) << n; at += 1; n += 8 }
        let v = buf & ((1 << k) - 1); buf >>= k; n -= k; return v
    }
    func decode(_ h: Huff) -> Int? {                                                           // codes are packed from their top bit down
        var code = 0, first = 0, index = 0
        for l in 1...15 {
            guard let b = bits(1) else { return nil }
            code |= b; let c = h.count[l]
            if code - first < c { return h.symbol[index + code - first] }
            index += c; first = (first + c) << 1; code <<= 1
        }
        return nil
    }
    var last = false
    while !last {
        guard let fin = bits(1), let type = bits(2) else { return nil }
        last = fin == 1
        if type == 0 {                                                                         // stored: from the next byte, LEN, ~LEN, the bytes
            buf = 0; n = 0                                                                     // bits() never holds a whole byte past the one it's in
            guard at + 4 <= s.count else { return nil }
            let len = Int(s[at]) | Int(s[at + 1]) << 8, nlen = Int(s[at + 2]) | Int(s[at + 3]) << 8; at += 4
            guard len == nlen ^ 0xFFFF, at + len <= s.count else { return nil }
            out += s[at..<at + len]; at += len; continue
        }
        let lit: Huff, dist: Huff
        if type == 1 { lit = fixedLit; dist = fixedDist }
        else if type == 2 {                                                                    // dynamic: the code lengths, themselves Huffman coded
            guard let hl = bits(5), let hd = bits(5), let hc = bits(4), hl + 257 <= 286, hd + 1 <= 30 else { return nil }
            var cl = [Int](repeating: 0, count: 19)
            for i in 0..<hc + 4 { guard let v = bits(3) else { return nil }; cl[[16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15][i]] = v }
            guard let lc = Huff(cl) else { return nil }
            var lens: [Int] = []; let total = hl + 257 + hd + 1
            while lens.count < total {
                guard let sym = decode(lc) else { return nil }
                if sym < 16 { lens.append(sym); continue }
                let prev = sym == 16 ? lens.last : 0, rep = sym == 16 ? bits(2).map { $0 + 3 } : sym == 17 ? bits(3).map { $0 + 3 } : bits(7).map { $0 + 11 }
                guard let prev, let rep, lens.count + rep <= total else { return nil }
                lens += repeatElement(prev, count: rep)
            }
            guard lens[256] > 0, let l = Huff(Array(lens[..<(hl + 257)])), let d = Huff(Array(lens[(hl + 257)...])) else { return nil }
            lit = l; dist = d
        } else { return nil }
        while true {
            guard let sym = decode(lit) else { return nil }
            if sym < 256 { out.append(UInt8(sym)); continue }
            if sym == 256 { break }
            guard sym - 257 < 29, let e = bits(lenExtra[sym - 257]), let ds = decode(dist), ds < 30, let de = bits(distExtra[ds]) else { return nil }
            let len = lenBase[sym - 257] + e, d = distBase[ds] + de
            guard d <= out.count else { return nil }
            for _ in 0..<len { out.append(out[out.count - d]) }                                  // byte by byte: a copy may overlap what it writes
        }
    }
    return out
}
/// Species dex's packed block of a DEFLATE archive (anims.bin, walk.bin: 494 uint32 offsets, species d = off[d - 1] ..< off[d]); nil = none (an empty block).
func block(_ a: Data, _ dex: Int) -> Data? {
    func off(_ i: Int) -> Int { Int(a[i * 4]) | Int(a[i * 4 + 1]) << 8 | Int(a[i * 4 + 2]) << 16 | Int(a[i * 4 + 3]) << 24 }
    guard (1...493).contains(dex), a.count > 494 * 4, off(dex - 1) < off(dex), off(dex) <= a.count else { return nil }
    return a.subdata(in: off(dex - 1)..<off(dex))
}
