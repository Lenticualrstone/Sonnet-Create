// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "PersistenceKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PersistenceKit", targets: ["PersistenceKit"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
    ],
    targets: [
        .target(
            name: "PersistenceKit",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
            ]
        ),
        .testTarget(name: "PersistenceKitTests", dependencies: ["PersistenceKit"]),
    ],
    swiftLanguageModes: [.v6]
)
