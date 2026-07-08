// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "BackupKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BackupKit", targets: ["BackupKit"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(path: "../DocumentKit"),
    ],
    targets: [
        .target(
            name: "BackupKit",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "DocumentKit", package: "DocumentKit"),
            ]
        ),
        .testTarget(name: "BackupKitTests", dependencies: ["BackupKit"]),
    ],
    swiftLanguageModes: [.v6]
)
