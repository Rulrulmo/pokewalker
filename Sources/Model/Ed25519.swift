import Foundation
// Ed25519 signature checks (RFC 8032) in pure Swift, like Sign.swift's SHA-256 (Windows has no CryptoKit): updates are signed on the release Mac
// (tools/release-key.swift holds the private key there, nowhere else) and checked here — by the app before it installs one, and by the server's
// publish step. Verification only. A port of TweetNaCl's crypto_sign_open (field elements as 16 limbs of 16 bits in Int64); not constant-time,
// which verification of public data doesn't need.

func sha512(_ data: [UInt8]) -> [UInt8] {
    let k: [UInt64] = [0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538, 0x59f111f1b605d019,
                       0x923f82a4af194f9b, 0xab1c5ed5da6d8118, 0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
                       0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3,
                       0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65, 0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
                       0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725,
                       0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
                       0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b, 0xa2bfe8a14cf10364, 0xa81a664bbc423001,
                       0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
                       0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb,
                       0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3, 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
                       0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b, 0xca273eceea26619c, 0xd186b8c721c0c207,
                       0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
                       0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a,
                       0x5fcb6fab3ad6faec, 0x6c44198c4a475817]
    var h: [UInt64] = [0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f,
                       0x1f83d9abfb41bd6b, 0x5be0cd19137e2179]
    func rotr64(_ x: UInt64, _ n: UInt64) -> UInt64 { x >> n | x << (64 - n) }
    var m = data; let bits = UInt64(data.count) &* 8
    m.append(0x80); while m.count % 128 != 112 { m.append(0) }
    m += [UInt8](repeating: 0, count: 8)                                                       // the length's high 64 bits
    for i in (0..<8).reversed() { m.append(UInt8(truncatingIfNeeded: bits >> (UInt64(i) * 8))) }
    var w = [UInt64](repeating: 0, count: 80)
    for c in stride(from: 0, to: m.count, by: 128) {
        for i in 0..<16 { var v: UInt64 = 0; for j in 0..<8 { v = v << 8 | UInt64(m[c + 8 * i + j]) }; w[i] = v }
        for i in 16..<80 {
            let s0: UInt64 = rotr64(w[i - 15], 1) ^ rotr64(w[i - 15], 8) ^ (w[i - 15] >> 7)
            let s1: UInt64 = rotr64(w[i - 2], 19) ^ rotr64(w[i - 2], 61) ^ (w[i - 2] >> 6)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = h[0], b = h[1], cc = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
        for i in 0..<80 {
            let S1: UInt64 = rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41), ch: UInt64 = (e & f) ^ (~e & g)
            let t1: UInt64 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
            let S0: UInt64 = rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39), maj: UInt64 = (a & b) ^ (a & cc) ^ (b & cc)
            hh = g; g = f; f = e; e = d &+ t1; d = cc; cc = b; b = a; a = t1 &+ (S0 &+ maj)
        }
        h[0] &+= a; h[1] &+= b; h[2] &+= cc; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
    }
    return h.flatMap { v in (0..<8).reversed().map { UInt8(truncatingIfNeeded: v >> (UInt64($0) * 8)) } }
}

/// "0a1b…" → its bytes; nil = not hex.
func unhex(_ s: String) -> [UInt8]? {
    let c = Array(s.utf8)
    guard c.count % 2 == 0 else { return nil }
    func v(_ x: UInt8) -> UInt8? { switch x { case 48...57: x - 48; case 97...102: x - 87; case 65...70: x - 55; default: nil } }
    var out: [UInt8] = []; out.reserveCapacity(c.count / 2)
    for i in stride(from: 0, to: c.count, by: 2) { guard let hi = v(c[i]), let lo = v(c[i + 1]) else { return nil }; out.append(hi << 4 | lo) }
    return out
}

enum Ed25519 {
    typealias GF = [Int64]                                                                      // mod 2^255 - 19, 16 limbs of 16 bits
    static let zero: GF = .init(repeating: 0, count: 16), one: GF = [1] + .init(repeating: 0, count: 15)
    static let D: GF = [0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070, 0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203]
    static let D2: GF = [0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0, 0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406]
    static let X: GF = [0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c, 0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169]
    static let Y: GF = [0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666]
    static let I: GF = [0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43, 0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83]
    static let L: [Int64] = [0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14] + .init(repeating: 0, count: 15) + [0x10]

    static func carry(_ a: GF) -> GF {
        var o = a
        for i in 0..<16 {
            o[i] += 1 << 16
            let c = o[i] >> 16
            if i < 15 { o[i + 1] += c - 1 } else { o[0] += 38 * (c - 1) }
            o[i] -= c << 16
        }
        return o
    }
    static func add(_ a: GF, _ b: GF) -> GF { (0..<16).map { a[$0] + b[$0] } }
    static func sub(_ a: GF, _ b: GF) -> GF { (0..<16).map { a[$0] - b[$0] } }
    static func mul(_ a: GF, _ b: GF) -> GF {
        var t = [Int64](repeating: 0, count: 31)
        for i in 0..<16 { for j in 0..<16 { t[i + j] += a[i] * b[j] } }
        for i in 0..<15 { t[i] += 38 * t[i + 16] }
        return carry(carry(Array(t[0..<16])))
    }
    static func sq(_ a: GF) -> GF { mul(a, a) }
    static func inv(_ i: GF) -> GF { var c = i; for a in stride(from: 253, through: 0, by: -1) { c = sq(c); if a != 2 && a != 4 { c = mul(c, i) } }; return c }
    static func pow2523(_ i: GF) -> GF { var c = i; for a in stride(from: 250, through: 0, by: -1) { c = sq(c); if a != 1 { c = mul(c, i) } }; return c }
    static func pack(_ n: GF) -> [UInt8] {
        var t = carry(carry(carry(n)))
        for _ in 0..<2 {
            var m = GF(repeating: 0, count: 16)
            m[0] = t[0] - 0xffed
            for i in 1..<15 { m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1); m[i - 1] &= 0xffff }
            m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1)
            let b = (m[15] >> 16) & 1
            m[14] &= 0xffff
            if b == 0 { t = m }                                                                 // t - p didn't go below zero: that's the value
        }
        return t.flatMap { [UInt8(truncatingIfNeeded: $0 & 0xff), UInt8(truncatingIfNeeded: $0 >> 8)] }
    }
    static func unpack(_ n: [UInt8]) -> GF {
        var o: GF = (0..<16).map { Int64(n[2 * $0]) + Int64(n[2 * $0 + 1]) << 8 }
        o[15] &= 0x7fff
        return o
    }
    static func parity(_ a: GF) -> UInt8 { pack(a)[0] & 1 }
    static func same(_ a: GF, _ b: GF) -> Bool { pack(a) == pack(b) }

    /// A point (x, y, z, t), extended coordinates: p + q.
    static func plus(_ p: [GF], _ q: [GF]) -> [GF] {
        let a = mul(sub(p[1], p[0]), sub(q[1], q[0])), b = mul(add(p[0], p[1]), add(q[0], q[1]))
        let c = mul(mul(p[3], q[3]), D2), d0 = mul(p[2], q[2]), d = add(d0, d0)
        let e = sub(b, a), f = sub(d, c), g = add(d, c), h = add(b, a)
        return [mul(e, f), mul(h, g), mul(g, f), mul(e, h)]
    }
    /// s · q (s little-endian, 32 bytes).
    static func times(_ q0: [GF], _ s: [UInt8]) -> [GF] {
        var p: [GF] = [zero, one, one, zero], q = q0
        for i in stride(from: 255, through: 0, by: -1) {
            let bit = (s[i / 8] >> UInt8(i & 7)) & 1
            if bit == 1 { swap(&p, &q) }
            q = plus(q, p); p = plus(p, p)
            if bit == 1 { swap(&p, &q) }
        }
        return p
    }
    static func packPoint(_ p: [GF]) -> [UInt8] {
        let zi = inv(p[2]), tx = mul(p[0], zi), ty = mul(p[1], zi)
        var r = pack(ty); r[31] ^= parity(tx) << 7
        return r
    }
    /// The public key as a point, negated (what the check needs); nil = not a point on the curve.
    static func unpackNeg(_ k: [UInt8]) -> [GF]? {
        let z = one, y = unpack(k)
        var num = sq(y)
        var den = mul(num, D)
        num = sub(num, z); den = add(z, den)
        let den2 = sq(den), den4 = sq(den2), den6 = mul(den4, den2)
        var t = mul(mul(den6, num), den)
        t = mul(mul(mul(pow2523(t), num), den), den)
        var x = mul(t, den)
        if !same(mul(sq(x), den), num) { x = mul(x, I) }
        if !same(mul(sq(x), den), num) { return nil }
        if parity(x) == k[31] >> 7 { x = sub(zero, x) }
        return [x, y, z, mul(x, y)]
    }
    /// h (64 bytes) mod L, the group's order.
    static func reduce(_ h: [UInt8]) -> [UInt8] {
        var x: [Int64] = h.map { Int64($0) }
        for i in stride(from: 63, through: 32, by: -1) {
            var carry: Int64 = 0, j = i - 32
            while j < i - 12 {
                x[j] = x[j] &+ carry &- 16 &* x[i] &* L[j - (i - 32)]
                carry = (x[j] + 128) >> 8
                x[j] -= carry << 8
                j += 1
            }
            x[j] += carry; x[i] = 0
        }
        var carry: Int64 = 0
        for j in 0..<32 { x[j] = x[j] &+ carry &- (x[31] >> 4) &* L[j]; carry = x[j] >> 8; x[j] &= 255 }
        for j in 0..<32 { x[j] = x[j] &- carry &* L[j] }
        var r = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { x[i + 1] += x[i] >> 8; r[i] = UInt8(truncatingIfNeeded: x[i] & 255) }
        return r
    }
}

/// The release key's public half. Its private half is on the release Mac only (~/.config/pokewalker/release-ed25519.key, tools/release-key.swift);
/// it signs each release's manifest.json, and an update is installed only when this key checks that signature and the manifest's SHA-256 of the zip.
let releaseKey: [UInt8] = unhex("81e440251e4e8e7153aeb593c5453d87b23af1d6a45a9466dd1c201f17fa1ea1")!

/// true = sig (64 bytes) is pub's (32 bytes) Ed25519 signature of msg: [S]B = R + [SHA-512(R ‖ A ‖ M)]A.
func ed25519Verify(_ sig: [UInt8], _ msg: [UInt8], _ pub: [UInt8]) -> Bool {
    guard sig.count == 64, pub.count == 32, sig[63] & 0xe0 == 0, let negA = Ed25519.unpackNeg(pub) else { return false }   // S < 2^253 (RFC 8032 §5.1.7)
    let h = Ed25519.reduce(sha512(Array(sig[0..<32]) + pub + msg))
    let p = Ed25519.plus(Ed25519.times(negA, h), Ed25519.times([Ed25519.X, Ed25519.Y, Ed25519.one, Ed25519.mul(Ed25519.X, Ed25519.Y)], Array(sig[32..<64])))
    return Ed25519.packPoint(p) == Array(sig[0..<32])
}

func ed25519Checks() -> [(Bool, String)] {
    func v(_ pub: String, _ msg: String, _ sig: String) -> Bool { ed25519Verify(unhex(sig)!, unhex(msg)!, unhex(pub)!) }
    let k1 = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    let s1 = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
    let k2 = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
    let s2 = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
    let k3 = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"
    let s3 = "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"
    var bad = unhex(s3)!; bad[10] ^= 1
    return [(hex(sha512(Array("abc".utf8))) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", "SHA-512 (the FIPS 180-2 \"abc\" vector)"),
            (v(k1, "", s1) && v(k2, "72", s2) && v(k3, "af82", s3), "Ed25519: RFC 8032 tests 1-3 check"),
            (ed25519Verify(unhex("f3ed48409038bcdc51ca4ccccacbda9c7e1dd299e05ea3e86fcc7e01de2416bd3333754b4ace0512f2d28f1c9c490833cad6993118db4ae0ea6f769168427507")!,
                           Array("pokewalker test 2.0\n\n".utf8), releaseKey), "Ed25519: the release key checks the release Mac's signature (CryptoKit's) of its test file"),
            (!v(k2, "73", s2) && !ed25519Verify(bad, [0xaf, 0x82], unhex(k3)!) && !v(k1, "", s2) && !ed25519Verify(Array(unhex(s1)!.prefix(63)), [], unhex(k1)!),
             "Ed25519: another message, a flipped bit, another key or a short signature don't")]
}
