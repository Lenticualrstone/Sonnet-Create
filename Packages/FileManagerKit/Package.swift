// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "FileManagerKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FileManagerKit", targets: ["FileManagerKit"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../DocumentKit"),
        .package(path: "../PersistenceKit"),
    ],
    targets: [
        .target(
            name: "FileManagerKit",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DocumentKit", package: "DocumentKit"),
                .product(name: "PersistenceKit", package: "PersistenceKit"),
            ]
        ),
        .testTarget(name: "FileManagerKitTests", dependencies: ["FileManagerKit"]),
    ],
    swiftLanguageModes: [.v6]
)
