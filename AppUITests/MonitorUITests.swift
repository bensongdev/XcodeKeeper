import XCTest

/// M4 UI 테스트. 고정 메모리 값(UITestFixtures.normalMemory/criticalMemory)과 기록만 하는 알림기를 쓴다.
/// 실제 알림 센터는 자동 테스트로 누를 수 없으므로 `-UITestAlertClick`으로 알림 클릭 처리기를 직접 부른다.
final class MonitorUITests: UITestCase {
    func testAlertClickOpensScannerWithTargetsSelected() {
        launch(openWindow: nil, extraArguments: ["-UITestAlertClick", "derivedData,archives"])
        let title = app.staticTexts["detail.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "스캐너 창이 열리지 않았습니다")
        XCTAssertEqual(text(of: title), "개발 찌꺼기")
        // Archives는 3초 늦게 끝난다. 끝난 뒤 알림의 대상이 선택된다.
        XCTAssertTrue(waitForText(app.staticTexts["target.archives.status"], "450MB", timeout: 10))
        let archives = app.checkBoxes["target.archives.checkbox"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1"), object: archives)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "주의 대상인 Archives가 선택되지 않음")
        XCTAssertEqual(checkboxValue(app.checkBoxes["target.derivedData.checkbox"]), 1)
        XCTAssertEqual(checkboxValue(app.checkBoxes["target.iOSDeviceSupport.checkbox"]), 0, "알림에 없는 주의 대상은 그대로")
        capture(app.windows.firstMatch, "01-notification-click-selected")
    }

    func testCriticalMemoryPopover() {
        launch(openWindow: nil, extraArguments: ["-UITestMemory", "critical"])
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "메뉴바 아이콘이 없습니다")
        statusItem.click()
        let pressure = app.staticTexts["menu.memory.pressure"]
        XCTAssertTrue(pressure.waitForExistence(timeout: 5), "팝오버가 열리지 않았습니다")
        XCTAssertEqual(text(of: pressure), "위험")
        XCTAssertEqual(text(of: app.staticTexts["menu.memory.swap"]), "스왑 3.4GB")
        XCTAssertEqual(text(of: app.staticTexts["menu.memory.app"]), "App 4.6GB")
        let popover = app.dialogs.containing(.staticText, identifier: "menu.memory.pressure").firstMatch
        capture(popover, "01-popover-memory-critical")
    }
}
