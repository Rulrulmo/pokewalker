// swift-tools-version:6.0
// SwiftPM: the Windows build (CI: .github/workflows/windows.yml); `swift build` works on the Mac too. The Mac app itself is still ./build.sh.
// One target over Sources + Tests, one module like build.sh's swiftc; the platform files are #if os(macOS) / #if os(Windows).
import PackageDescription

let package = Package(
    name: "PokeWalker",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "PokeWalker", path: ".", exclude: ["docs", "tools", "Resources", "README.md", "Info.plist", "build.sh"], sources: ["Sources", "Tests"],   // Resources: copied next to the exe
                                linkerSettings: [.unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"], .when(platforms: [.windows]))])]   // a window app: no console of its own
)
