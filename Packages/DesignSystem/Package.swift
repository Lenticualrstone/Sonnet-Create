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
                .process("Shaders"), // .metal → 번들 metallib 컴파일 (AI 스피어 플라즈마)
            ]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    ],
    swiftLanguageModes: [.v6]
)
