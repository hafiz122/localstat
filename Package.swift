// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalStat",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LocalStat", targets: ["LocalStat"])],
    targets: [
        .target(name: "SASCore"),
        .executableTarget(name: "LocalStat", dependencies: ["SASCore"]),
        .testTarget(name: "SASCoreTests", dependencies: ["SASCore"])
    ]
)
