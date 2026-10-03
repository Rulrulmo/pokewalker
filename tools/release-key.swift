#!/usr/bin/env swift
// The release signing key (Ed25519, CryptoKit; the Mac only): swift tools/release-key.swift new | pub | sign <file> | verify <file> <sighex> [<pubhex>]
// The private key lives only on this Mac, as hex in ~/.config/pokewalker/release-ed25519.key (dir 700, file 600) — never in the repository. Back it up
// (a password manager, an offline copy): without it no later release can update anyone. The public key is built into the app (Model/Ed25519.swift
// verifies); the server only mirrors what was signed here, so a broken-into server can't push code to the team.
// CryptoKit's signatures are randomized: the same file signs differently each time, and every one verifies.
import CryptoKit
import Foundation

let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/pokewalker", isDirectory: true)
let keyFile = dir.appendingPathComponent("release-ed25519.key")
func hex(_ d: some DataProtocol) -> String { d.map { String(format: "%02x", $0) }.joined() }
func bytes(_ h: String) -> Data? {
    let s = Array(h.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    guard s.count % 2 == 0 else { return nil }
    var d = Data()
    for i in stride(from: 0, to: s.count, by: 2) { guard let b = UInt8(String(decoding: s[i..<i + 2], as: UTF8.self), radix: 16) else { return nil }; d.append(b) }
    return d
}
func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(2) }
func key() -> Curve25519.Signing.PrivateKey {
    guard let h = try? String(contentsOf: keyFile, encoding: .utf8) else { fail("no key: \(keyFile.path) (run: new)") }
    guard let d = bytes(h), let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: d) else { fail("\(keyFile.path) isn't a 32-byte hex key") }
    return k
}
func file(_ p: String) -> Data { guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)) else { fail("can't read \(p)") }; return d }

let a = CommandLine.arguments.dropFirst()
switch (a.first, a.count) {
case ("new", 1):
    guard !FileManager.default.fileExists(atPath: keyFile.path) else { fail("\(keyFile.path) exists: not making another (the app trusts that one)") }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    let k = Curve25519.Signing.PrivateKey()
    guard FileManager.default.createFile(atPath: keyFile.path, contents: Data((hex(k.rawRepresentation) + "\n").utf8), attributes: [.posixPermissions: 0o600]) else { fail("can't write \(keyFile.path)") }
    print(hex(k.publicKey.rawRepresentation))
    FileHandle.standardError.write(Data("private key: \(keyFile.path) — back it up now; the line above is the public key\n".utf8))
case ("pub", 1): print(hex(key().publicKey.rawRepresentation))
case ("sign", 2):
    guard let sig = try? key().signature(for: file(a[a.startIndex + 1])) else { fail("signing failed") }
    print(hex(sig))
case ("verify", 3), ("verify", 4):
    let i = a.startIndex, data = file(a[i + 1])
    guard let sig = bytes(a[i + 2]), sig.count == 64 else { fail("the signature: 64 bytes as hex") }
    let pub: Curve25519.Signing.PublicKey
    if a.count == 4 {
        guard let p = bytes(a[i + 3]).flatMap({ try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }) else { fail("the public key: 32 bytes as hex") }
        pub = p
    } else { pub = key().publicKey }
    let ok = pub.isValidSignature(sig, for: data)
    print(ok ? "ok" : "BAD"); exit(ok ? 0 : 1)
default: fail("usage: swift tools/release-key.swift new | pub | sign <file> | verify <file> <sighex> [<pubhex>]")
}
