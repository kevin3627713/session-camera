// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SessionCore",
    products: [.library(name: "SessionCore", targets: ["SessionCore"])],
    targets: [
        .target(name: "SessionCore"),
        .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore"])
    ]
)
