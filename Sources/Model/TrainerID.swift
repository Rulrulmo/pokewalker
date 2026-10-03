// Sources/Model/TrainerID.swift — shared with server/ (build.sh copies Sources/Model). docs/plans/08-server-save.md §2.
import Foundation
/// A trainer ID as typed: 2-12 of 가-힣, A-Z a-z, 0-9, _ — after trimming and NFC (the Mac may hand Hangul over as NFD).
/// name = what screens show; key = name lowercased, the server's primary key. nil = not a valid ID.
func trainerID(_ raw: String) -> (name: String, key: String)? {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    let ok = name.unicodeScalars.allSatisfy { s in let v = s.value
        return (0xAC00...0xD7A3).contains(v) || (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0x30...0x39).contains(v) || v == 0x5F }
    return ok && (2...12).contains(name.unicodeScalars.count) ? (name, name.lowercased()) : nil
}
