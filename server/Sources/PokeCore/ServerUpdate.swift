import Foundation
import Hummingbird

// The app's updates (signed on the release Mac: tools/release-key.swift). POST /v1/update gives the release's manifest.json as signed and its
// signature; GET /v1/download/<mac|windows> the zip it names — both with the app key. The app checks the signature with releaseKey and the zip
// against the manifest itself: this server only mirrors what `pokeserver verify-release` passed (publish.sh), so it can't make an update up.

struct UpdateReq: Codable, Sendable { let app: String?; let platform: String? }

/// RELEASE_DIR's signed files: manifest.json, manifest.sig and the zips the manifest names.
struct ReleaseFiles: Sendable {
    struct Entry: Codable, Sendable { let file: String; let sha256: String; let size: Int }
    struct Manifest: Codable, Sendable { let build, commit, version: String; let mac, windows: Entry? }
    let dir: URL

    var manifestText: String? { try? String(contentsOf: dir.appendingPathComponent("manifest.json"), encoding: .utf8) }
    var signature: String? {
        (try? String(contentsOf: dir.appendingPathComponent("manifest.sig"), encoding: .utf8)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    static func parse(_ text: String) -> Manifest? { try? JSONDecoder().decode(Manifest.self, from: Data(text.utf8)) }
    /// The release key's signature of these exact bytes.
    static func signed(_ text: String, _ sig: String) -> Bool { unhex(sig).map { ed25519Verify($0, Array(text.utf8), releaseKey) } ?? false }

    /// A release folder as the release Mac made it: the signature checks with releaseKey, the manifest reads, and each zip it names is there with
    /// that size and SHA-256. Throws what's wrong; nothing is trusted before this passes.
    static func verify(_ dir: URL) throws -> Manifest {
        let f = ReleaseFiles(dir: dir)
        guard let text = f.manifestText else { throw ServerError(description: "\(dir.path): no manifest.json") }
        guard let sig = f.signature else { throw ServerError(description: "\(dir.path): no manifest.sig") }
        guard signed(text, sig) else { throw ServerError(description: "manifest.sig doesn't check with the release key: not the release Mac's manifest") }
        guard let m = parse(text), versionParts(m.version) != nil else { throw ServerError(description: "manifest.json doesn't read as a release manifest") }
        guard m.mac != nil || m.windows != nil else { throw ServerError(description: "manifest.json names no zip") }
        for (kind, e) in [("mac", m.mac), ("windows", m.windows)] {
            guard let e else { continue }
            guard !e.file.contains("/"), !e.file.contains(".."), let d = try? Data(contentsOf: dir.appendingPathComponent(e.file)) else { throw ServerError(description: "\(kind): \(e.file) isn't there") }
            guard d.count == e.size else { throw ServerError(description: "\(kind): \(e.file) is \(d.count) bytes, the manifest says \(e.size)") }
            guard hex(sha256(Array(d))) == e.sha256.lowercased() else { throw ServerError(description: "\(kind): \(e.file)'s SHA-256 isn't the manifest's") }
        }
        return m
    }
}

func hasAppKey(_ r: Request, _ appKey: String) -> Bool { r.headers.first(where: { $0.name.canonicalName == "x-app-key" })?.value == appKey }

func addUpdates(_ router: Router<BasicRequestContext>, _ files: ReleaseFiles, appKey: String) {
    post(router, "/v1/update", appKey: appKey, id: { (_: UpdateReq) in "" }) { _ in
        guard let m = files.manifestText, let s = files.signature else { return Reply(200, ["manifest": .null, "sig": .null]) }   // nothing signed yet
        return Reply(200, ["manifest": .s(m), "sig": .s(s)])
    }
    router.get("/v1/download/:kind") { request, context -> Response in
        guard hasAppKey(request, appKey) else { return respond(.error(401, "app_key")) }
        let kind = context.parameters.get("kind") ?? ""
        guard let m = files.manifestText.flatMap(ReleaseFiles.parse), let e = kind == "mac" ? m.mac : kind == "windows" ? m.windows : nil
        else { return respond(.error(404, "no_release")) }
        var headers = HTTPFields()
        headers[.contentType] = "application/zip"
        headers[.contentLength] = String(e.size)
        headers[.cacheControl] = "no-store"
        context.logger.info("update download \(kind) \(m.version)")
        return Response(status: .ok, headers: headers, body: try await FileIO().loadFile(path: files.dir.appendingPathComponent(e.file).path, context: context))
    }
}
