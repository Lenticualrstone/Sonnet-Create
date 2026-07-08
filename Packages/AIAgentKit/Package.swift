// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "AIAgentKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AIAgentKit", targets: ["AIAgentKit"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(path: "../DocumentKit"),
    ],
    targets: [
        .target(
            name: "AIAgentKit",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "DocumentKit", package: "DocumentKit"),
            ]
        ),
        .testTarget(name: "AIAgentKitTests", dependencies: ["AIAgentKit"]),
    ],
    swiftLanguageModes: [.v6]
)
