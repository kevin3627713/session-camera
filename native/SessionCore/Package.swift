// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SessionCore",
    platforms: [.macOS(.v12), .iOS(.v17)],
    products: [.library(name: "SessionCore", targets: ["SessionCore"]),
               .library(name: "PhotoCore", targets: ["PhotoCore"])],
    targets: [
        .target(name: "SessionCore"),
        .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore"]),
        .target(name: "PhotoCore"),
        .testTarget(name: "PhotoCoreTests", dependencies: ["PhotoCore"])
    ]
)
