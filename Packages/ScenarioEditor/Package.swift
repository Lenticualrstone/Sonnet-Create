// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ScenarioEditor",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScenarioEditor", targets: ["ScenarioEditor"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../DocumentKit"),
        .package(path: "../AIAgentKit"),
    ],
    targets: [
        .target(
            name: "ScenarioEditor",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DocumentKit", package: "DocumentKit"),
                .product(name: "AIAgentKit", package: "AIAgentKit"),
            ]
        ),
        .testTarget(name: "ScenarioEditorTests", dependencies: ["ScenarioEditor"]),
    ],
    swiftLanguageModes: [.v6]
)
