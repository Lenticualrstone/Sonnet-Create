// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MindMapEditor",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MindMapEditor", targets: ["MindMapEditor"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../DocumentKit"),
        .package(path: "../RenderingKit"),
    ],
    targets: [
        .target(
            name: "MindMapEditor",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DocumentKit", package: "DocumentKit"),
                .product(name: "RenderingKit", package: "RenderingKit"),
            ]
        ),
        .testTarget(name: "MindMapEditorTests", dependencies: ["MindMapEditor"]),
    ],
    swiftLanguageModes: [.v6]
)
