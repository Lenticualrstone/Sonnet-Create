// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
    ],
    targets: [
        .target(name: "AppCore"),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
    ],
    swiftLanguageModes: [.v6]
)
