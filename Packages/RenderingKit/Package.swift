// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "RenderingKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RenderingKit", targets: ["RenderingKit"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
    ],
    targets: [
        .target(
            name: "RenderingKit",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
            ],
            resources: [
                .process("Shaders"),
            ]
        ),
        .testTarget(name: "RenderingKitTests", dependencies: ["RenderingKit"]),
    ],
    swiftLanguageModes: [.v6]
)
