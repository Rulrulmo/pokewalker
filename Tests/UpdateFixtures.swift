import Foundation
// Public test data for the updater (auto-update U3): a release manifest for a made-up 9.9, written as ./build.sh publish writes them (compact, keys
// sorted, no newline at the end) and signed by the release key (swift tools/release-key.swift sign). Its "zips" are short texts, so a download
// that matches (fixtureZip99) and one that doesn't can both be checked; the commit is made up.

let fixtureManifest99 = #"{"build":"99","commit":"0123456789abcdef0123456789abcdef01234567","mac":{"file":"PokeWalker-mac.zip","sha256":"bf5ba371f96fb7f9510010a81bab68186b626413c095fb1aa614af4d6755ef95","size":19},"version":"9.9","windows":{"file":"PokeWalker-windows-x64.zip","sha256":"bab148b3d12b398bc10bbf7dde53796fa1ddf3d0903ca5f3acbfad7f8ae5a8d9","size":23}}"#
let fixtureSig99 = "fca8c07933621bdc02d62c1aee0616cc7d42f055d4e4a01bb11eb52939ec3d525e1049d6eaf218196c32fbfff0b41ed660fd37963cf7016dc49dff23ae49d201"
let fixtureZip99 = (mac: Array("pokewalker 9.9 mac\n".utf8), windows: Array("pokewalker 9.9 windows\n".utf8))

func updateFixtureChecks() -> [(Bool, String)] {
    let m = Array(fixtureManifest99.utf8), sig = unhex(fixtureSig99) ?? []
    var changed = m; changed[changed.count - 3] ^= 1                                              // a byte of the windows size
    let fields = (try? JSONSerialization.jsonObject(with: Data(m))) as? [String: Any], mac = fields?["mac"] as? [String: Any]
    return [(ed25519Verify(sig, m, releaseKey) && !ed25519Verify(sig, changed, releaseKey), "update fixtures: the made-up 9.9 manifest is the release key's; a changed byte isn't"),
            (fields?["version"] as? String == "9.9" && mac?["sha256"] as? String == hex(sha256(fixtureZip99.mac)) && mac?["size"] as? Int == fixtureZip99.mac.count,
             "update fixtures: its mac entry is fixtureZip99.mac's sha256 and size")]
}
