// swift-tools-version:6.0
// server/Package.swift — the save server (Linux, systemd, behind cloudflared). Sources/PokeCore/Game = build.sh's copy of ../Sources/{Model,Data,Battle}.
import PackageDescription
let package = Package(name: "PokeServer", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")],
    targets: [.systemLibrary(name: "CSQLite", path: "Sources/CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
              .target(name: "PokeCore", dependencies: ["CSQLite", .product(name: "Hummingbird", package: "hummingbird")]),
              .executableTarget(name: "pokeserver", dependencies: ["PokeCore"]), .testTarget(name: "PokeCoreTests", dependencies: ["PokeCore"])])
