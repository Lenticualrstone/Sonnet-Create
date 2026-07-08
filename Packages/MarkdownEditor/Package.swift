// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MarkdownEditor", targets: ["MarkdownEditor"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../DocumentKit"),
    ],
    targets: [
        .target(
            name: "MarkdownEditor",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DocumentKit", package: "DocumentKit"),
            ]
        ),
        .testTarget(name: "MarkdownEditorTests", dependencies: ["MarkdownEditor"]),
    ],
    swiftLanguageModes: [.v6]
)
