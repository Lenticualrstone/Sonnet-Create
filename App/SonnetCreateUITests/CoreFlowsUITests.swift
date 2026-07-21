import XCTest

/// 지시서 7단계 UI 자동화 — 핵심 흐름.
/// 앱은 `--uitest` + UITEST_WORKSPACE(임시 격리 경로)로 기동돼
/// 사용자 워크스페이스·온보딩 플래그를 건드리지 않는다.
/// 참고: 라이트·다크 전환/Reduce Motion은 실제 저장이 사용자 설정(UserDefaults 공유)을
/// 오염시키므로 자동화에서 제외 — draft 검증(설정 저장·취소 흐름)으로 갈음한다.
final class CoreFlowsUITests: XCTestCase {
    private var workspace: URL!

    override func setUp() {
        continueAfterFailure = false
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonnetCreateUITests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        // 실패한 케이스가 인스턴스를 남기면 다음 케이스가 엉뚱한 pid에 붙는다 — 확실히 종료
        XCUIApplication().terminate()
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
    }

    private func launchApp(onboarding: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launchEnvironment["UITEST_WORKSPACE"] = workspace.path
        app.launchEnvironment["UITEST_ONBOARDING"] = onboarding ? "1" : "0"
        app.launch()
        return app
    }

    /// 흐름 1 — 첫 실행 온보딩: 3걸음 진행 후 '독립 문서로 시작'으로 홈에 도달.
    func testFirstRunOnboardingFlow() {
        let app = launchApp(onboarding: true)

        // 1걸음: 환영 + 저장 위치
        XCTAssertTrue(
            app.staticTexts["Sonnet Create에 오신 것을 환영합니다"].waitForExistence(timeout: 10),
            "온보딩 환영 화면이 나타나야 한다"
        )
        app.buttons["다음"].click()

        // 2걸음: 네 가지 문서
        XCTAssertTrue(app.staticTexts["네 가지 문서"].waitForExistence(timeout: 5))
        app.buttons["다음"].click()

        // 3걸음: 시작 선택 → 독립 문서
        XCTAssertTrue(app.staticTexts["어떻게 시작할까요?"].waitForExistence(timeout: 5))
        let solo = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "독립 문서로 시작")
        ).firstMatch
        XCTAssertTrue(solo.exists)
        solo.click()

        // 온보딩이 닫히고 홈(빠른 시작)이 보인다
        XCTAssertTrue(app.staticTexts["빠른 시작"].waitForExistence(timeout: 5))
    }

    /// 흐름 1(변형) — 건너뛰기: 첫 걸음에서 바로 탈출할 수 있어야 한다.
    func testOnboardingSkip() {
        let app = launchApp(onboarding: true)
        XCTAssertTrue(
            app.staticTexts["Sonnet Create에 오신 것을 환영합니다"].waitForExistence(timeout: 10)
        )
        app.buttons["건너뛰기"].click()
        XCTAssertTrue(app.staticTexts["빠른 시작"].waitForExistence(timeout: 5))
    }

    /// 흐름 2+3 — ⌘K 팔레트로 프로젝트와 네 종류 문서를 생성하고 탭 등장을 확인.
    func testCreateProjectAndFourDocumentKinds() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["빠른 시작"].waitForExistence(timeout: 10))

        // 프로젝트 생성 (⌘K → 새 프로젝트)
        runPaletteAction(app, named: "새 프로젝트")

        // 네 종류 문서 — 생성 후 탭 칩 제목으로 확인
        for title in ["새 시나리오", "새 마인드맵", "새 페이지", "새 캐릭터"] {
            runPaletteAction(app, named: title)
            XCTAssertTrue(
                app.staticTexts[title].waitForExistence(timeout: 8),
                "\(title) 탭이 열려야 한다"
            )
        }
    }

    /// 흐름 10 — 설정 저장·취소: draft 변경 → 변경 건수 표시 → 되돌리기로 폐기.
    /// (저장 버튼은 실제 UserDefaults를 바꾸므로 자동화에서는 누르지 않는다.)
    func testSettingsDraftAndRevert() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["빠른 시작"].waitForExistence(timeout: 10))

        // 메뉴 바 경로가 키보드 단축키보다 안정적
        app.menuBarItems.element(boundBy: 1).click()
        let settingsItem = app.menuItems.containing(
            NSPredicate(format: "title CONTAINS %@ OR title CONTAINS %@", "설정", "Settings")
        ).firstMatch
        if settingsItem.waitForExistence(timeout: 4) {
            settingsItem.click()
        }

        // Toggle의 AX 표현이 checkBox/switch 중 무엇이 될지는 OS 버전에 따라 달라 둘 다 시도
        let candidates = [
            app.checkBoxes["자동 저장"].firstMatch,
            app.switches["자동 저장"].firstMatch,
        ]
        guard let autosave = candidates.first(where: { $0.waitForExistence(timeout: 4) }) else {
            dumpTree(app, name: "settings")
            XCTFail("설정 창의 자동 저장 토글을 찾지 못함")
            return
        }
        autosave.click()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "변경 1건"))
                .firstMatch.waitForExistence(timeout: 5),
            "변경 건수 문구가 나타나야 한다"
        )

        app.buttons["되돌리기"].firstMatch.click()
        let gone = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "변경 1건"))
            .firstMatch
        XCTAssertTrue(waitForDisappearance(gone, timeout: 5), "되돌리기 후 변경 문구가 사라져야 한다")

        app.typeKey("w", modifierFlags: .command)
    }

    // MARK: 헬퍼

    /// 진단용 — 접근성 트리를 파일로 남긴다 (NSLog는 잘려서).
    private func dumpTree(_ app: XCUIApplication, name: String) {
        try? app.debugDescription.write(
            toFile: "/tmp/uitest-tree-\(name).txt", atomically: true, encoding: .utf8
        )
    }

    /// 홈 탭으로 이동 — 타이틀바의 '홈' 탭 칩 클릭.
    private func goHome(_ app: XCUIApplication) {
        let homeChip = app.staticTexts["홈"].firstMatch
        if homeChip.waitForExistence(timeout: 4) { homeChip.click() }
    }

    /// 팔레트를 열고(홈 검색 트리거 클릭 — 키 이벤트보다 안정적) 명령 행을 클릭한다.
    private func runPaletteAction(_ app: XCUIApplication, named title: String) {
        goHome(app)
        let trigger = app.staticTexts["프로젝트, 문서, 캐릭터 검색..."].firstMatch
        if !trigger.waitForExistence(timeout: 5) {
            dumpTree(app, name: "no-trigger")
            XCTFail("홈의 ⌘K 검색 트리거를 찾지 못함")
            return
        }
        trigger.click()
        let row = app.staticTexts[title].firstMatch
        if !row.waitForExistence(timeout: 6) {
            dumpTree(app, name: "no-\(title)")
            XCTFail("⌘K에 '\(title)' 명령이 보여야 한다")
            return
        }
        row.click()
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
