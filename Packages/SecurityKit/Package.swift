// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SecurityKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SecurityKit", targets: ["SecurityKit"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
    ],
    targets: [
        .target(
            name: "SecurityKit",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
            ]
        ),
        .testTarget(name: "SecurityKitTests", dependencies: ["SecurityKit"]),
    ],
    swiftLanguageModes: [.v6]
)
