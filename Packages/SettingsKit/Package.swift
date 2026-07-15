// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SettingsKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../RenderingKit"),
        .package(path: "../AIAgentKit"),
    ],
    targets: [
        .target(
            name: "SettingsKit",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "RenderingKit", package: "RenderingKit"),
                .product(name: "AIAgentKit", package: "AIAgentKit"),
            ]
        ),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),
    ],
    swiftLanguageModes: [.v6]
)
