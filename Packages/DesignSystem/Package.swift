// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
            ],
            resources: [
                .copy("Fonts"),
            ]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    ],
    swiftLanguageModes: [.v6]
)
