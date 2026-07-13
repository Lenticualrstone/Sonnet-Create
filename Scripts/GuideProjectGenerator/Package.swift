// swift-tools-version: 6.3
import PackageDescription

// 개발용 도구: DocumentKit의 실제 저장 API를 그대로 사용해 언어별 가이드(튜토리얼) 프로젝트
// 번들을 생성한다. 앱에는 포함되지 않으며, GitHub 릴리스 자산으로 첨부할 .scproj를
// 재생성할 때만 실행한다.
// 사용: swift run --package-path Scripts/GuideProjectGenerator GuideProjectGenerator <출력 디렉토리> <ko|ja|en> [whatsnew 파일 경로]
let package = Package(
    name: "GuideProjectGenerator",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../Packages/AppCore"),
        .package(path: "../../Packages/PersistenceKit"),
        .package(path: "../../Packages/DocumentKit"),
    ],
    targets: [
        .executableTarget(
            name: "GuideProjectGenerator",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "PersistenceKit", package: "PersistenceKit"),
                .product(name: "DocumentKit", package: "DocumentKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
