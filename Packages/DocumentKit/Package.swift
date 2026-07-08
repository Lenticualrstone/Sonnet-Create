// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DocumentKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DocumentKit", targets: ["DocumentKit"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(path: "../PersistenceKit"),
    ],
    targets: [
        .target(
            name: "DocumentKit",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "PersistenceKit", package: "PersistenceKit"),
            ]
        ),
        .testTarget(name: "DocumentKitTests", dependencies: ["DocumentKit"]),
    ],
    swiftLanguageModes: [.v6]
)
