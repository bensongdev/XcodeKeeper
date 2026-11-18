import XCTest

/// M2 정리 UI 테스트. 가짜 정리기(실제 휴지통·명령·이력 파일 사용 안 함)를 쓴다.
/// 기본 선택(안전) 9개 = DerivedData 4 + Xcode 캐시 1 + SwiftPM 1 + 사용 불가 기기 2 + Homebrew 1, 합계 6.9GB
final class CleanupUITests: UITestCase {
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func label(_ identifier: String) -> String {
        text(of: app.staticTexts[identifier])
    }

    /// 스캔하고 모든 대상이 끝날 때까지 기다린다(Archives가 3초 늦게 끝남).
    private func scanToCompletion() {
        let scan = app.buttons["scan.start"]
        XCTAssertTrue(scan.waitForExistence(timeout: 10), "스캐너 창이 나타나지 않았습니다")
        scan.click()
        XCTAssertTrue(waitForText(app.staticTexts["target.archives.status"], "450MB", timeout: 10))
        XCTAssertTrue(waitForText(app.staticTexts["selection.total"], "선택 6.9GB"))
    }

    private func openConfirmation() {
        let start = app.buttons["cleanup.start"]
        XCTAssertTrue(start.isEnabled)
        start.click()
        XCTAssertTrue(app.staticTexts["cleanup.confirm.title"].waitForExistence(timeout: 5), "확인 창이 열리지 않았습니다")
    }

    func testConfirmCleanThenHistory() {
        launch(openWindow: "scanner")
        let window = app.windows.firstMatch
        scanToCompletion()

        // 확인 창
        openConfirmation()
        XCTAssertEqual(label("cleanup.confirm.title"), "선택한 항목을 정리할까요?")
        XCTAssertEqual(label("cleanup.confirm.count"), "항목 9개")
        XCTAssertEqual(label("cleanup.confirm.bytes"), "예상 확보 용량 6.9GB")
        XCTAssertEqual(label("cleanup.confirm.commandNote"),
                       "사용 불가 시뮬레이터 기기는 휴지통을 거치지 않고 xcrun simctl delete unavailable로 바로 삭제됩니다.")
        XCTAssertFalse(app.staticTexts["cleanup.confirm.xcodeWarning"].exists, "Xcode가 실행 중이 아니면 경고 없음")
        XCTAssertEqual(app.buttons["cleanup.confirm.ok"].label, "휴지통으로 정리")
        capture(window, "01-confirm-dialog")

        // 정리 후: 결과, 휴지통 안내, 자동 재스캔
        app.buttons["cleanup.confirm.ok"].click()
        XCTAssertTrue(waitForText(app.staticTexts["cleanup.result.freed"], "확보됨 6.9GB", timeout: 10))
        XCTAssertEqual(label("cleanup.result.trashNote"), "휴지통을 비워야 실제로 공간이 확보됩니다.")
        XCTAssertTrue(app.buttons["cleanup.result.openTrash"].exists)
        XCTAssertFalse(app.staticTexts["cleanup.result.failures"].exists)
        XCTAssertTrue(waitForText(app.staticTexts["target.archives.status"], "450MB", timeout: 10), "재스캔 완료")
        XCTAssertEqual(label("target.derivedData.status"), "없음")
        XCTAssertEqual(label("target.iOSDeviceSupport.status"), "2.8GB", "주의 항목은 남음")
        XCTAssertEqual(label("selection.total"), "선택 0.0GB")
        XCTAssertFalse(app.buttons["cleanup.start"].isEnabled, "선택이 없으면 정리 버튼 비활성")
        capture(window, "02-after-cleanup")

        // 정리 이력
        element("sidebar.history").click()
        XCTAssertTrue(waitForText(app.staticTexts["history.total"], "누적 확보 6.9GB"))
        XCTAssertEqual(label("history.row.0.count"), "항목 9개")
        XCTAssertEqual(label("history.row.0.bytes"), "6.9GB")
        XCTAssertEqual(label("history.row.0.targets"),
                       "DerivedData, Xcode 캐시, SwiftPM 캐시, 사용 불가 시뮬레이터 기기, Homebrew 캐시")
        XCTAssertFalse(app.staticTexts["history.row.1.count"].exists)
        capture(window, "03-history")
    }

    func testXcodeRunningWarningAndCancel() {
        launch(openWindow: "scanner", extraArguments: ["-UITestXcodeRunning", "YES"])
        scanToCompletion()

        openConfirmation()
        XCTAssertEqual(label("cleanup.confirm.xcodeWarning"),
                       "Xcode가 실행 중입니다. DerivedData를 정리하기 전에 Xcode를 종료하는 것이 좋습니다. "
                       + "열려 있는 프로젝트의 빌드와 인덱싱이 깨질 수 있습니다.")
        XCTAssertEqual(app.buttons["cleanup.confirm.ok"].label, "그래도 정리")
        capture(app.windows.firstMatch, "01-xcode-running-warning")

        // 취소하면 아무것도 바뀌지 않는다
        app.buttons["cleanup.confirm.cancel"].click()
        XCTAssertTrue(waitForDisappearance(app.staticTexts["cleanup.confirm.title"]))
        XCTAssertFalse(app.staticTexts["cleanup.result.freed"].exists)
        XCTAssertEqual(label("target.derivedData.status"), "4.3GB")
        XCTAssertEqual(label("selection.total"), "선택 6.9GB")
    }

    func testPartialFailureIsReported() {
        launch(openWindow: "scanner", extraArguments: ["-UITestCleanupFailure", "YES"])
        scanToCompletion()
        openConfirmation()
        app.buttons["cleanup.confirm.ok"].click()

        XCTAssertTrue(waitForText(app.staticTexts["cleanup.result.freed"], "확보됨 6.7GB", timeout: 10))
        XCTAssertEqual(label("cleanup.result.failures"), "1개 항목을 정리하지 못했습니다")
        XCTAssertEqual(label("cleanup.result.failure.0"), "Homebrew 캐시 · Homebrew: 허용되지 않은 경로")
        XCTAssertTrue(waitForText(app.staticTexts["target.archives.status"], "450MB", timeout: 10), "재스캔 완료")
        XCTAssertEqual(label("target.homebrewCache.status"), "200MB", "실패한 항목은 남아 있음")
        XCTAssertEqual(label("target.derivedData.status"), "없음")
        capture(app.windows.firstMatch, "01-cleanup-partial-failure")
    }

    func testHistoryEmptyState() {
        launch(openWindow: "scanner")
        let sidebar = element("sidebar.history")
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        sidebar.click()
        XCTAssertTrue(element("history.empty").waitForExistence(timeout: 5), "빈 상태 안내가 없습니다")
        XCTAssertEqual(label("history.total"), "누적 확보 0.0GB")
        capture(app.windows.firstMatch, "01-history-empty")
    }
}
