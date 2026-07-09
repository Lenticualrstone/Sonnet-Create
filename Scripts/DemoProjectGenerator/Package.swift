// swift-tools-version: 6.3
import PackageDescription

// 개발용 도구: DocumentKit의 실제 저장 API를 그대로 사용해 튜토리얼(데모) 프로젝트 번들을
// 생성한다. 앱에는 포함되지 않으며, 배포용 데모 콘텐츠를 재생성할 때만 실행한다.
// 사용: swift run --package-path Scripts/DemoProjectGenerator DemoProjectGenerator <출력 디렉토리>
let package = Package(
    name: "DemoProjectGenerator",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../Packages/AppCore"),
        .package(path: "../../Packages/PersistenceKit"),
        .package(path: "../../Packages/DocumentKit"),
    ],
    targets: [
        .executableTarget(
            name: "DemoProjectGenerator",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "PersistenceKit", package: "PersistenceKit"),
                .product(name: "DocumentKit", package: "DocumentKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
