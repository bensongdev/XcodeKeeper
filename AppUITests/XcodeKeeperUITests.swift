import XCTest

/// M0 뼈대 UI 테스트. `-UITestMode YES`로 실행해 실제 디스크 대신 고정된 여유 공간(16.2GB)을 쓴다.
final class XcodeKeeperUITests: UITestCase {
    func testScannerWindowInitialStateAndSidebarSelection() {
        launch(openWindow: "scanner")

        let title = app.staticTexts["detail.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "스캐너 창이 나타나지 않았습니다")
        XCTAssertEqual(text(of: title), "개발 찌꺼기")
        for section in ["junk", "simulators", "history"] {
            XCTAssertTrue(app.descendants(matching: .any)["sidebar.\(section)"].exists, "사이드바 항목 없음: \(section)")
        }
        let window = app.windows.firstMatch
        XCTAssertGreaterThanOrEqual(window.frame.width, 720)
        XCTAssertGreaterThanOrEqual(window.frame.height, 520)
        capture(window, "01-initial-scanner-window")

        app.descendants(matching: .any)["sidebar.simulators"].click()
        XCTAssertTrue(waitForText(title, "시뮬레이터"), "선택한 항목으로 제목이 바뀌지 않았습니다: \(text(of: title))")
        capture(window, "02-after-select-simulator")
    }

    func testMenuBarPopoverShowsFreeSpace() {
        launch(openWindow: nil)

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "메뉴바 아이콘이 없습니다")
        statusItem.click()

        let freeSpace = app.staticTexts["menu.freeSpace"]
        XCTAssertTrue(freeSpace.waitForExistence(timeout: 5), "팝오버가 열리지 않았습니다")
        XCTAssertEqual(text(of: freeSpace), "여유 16.2GB")
        XCTAssertTrue(app.buttons["menu.openScanner"].exists)
        XCTAssertTrue(app.buttons["menu.quit"].exists)
        // MenuBarExtra(.window)의 팝오버는 접근성 트리에서 Dialog로 노출된다.
        let popover = app.dialogs.containing(.staticText, identifier: "menu.freeSpace").firstMatch
        XCTAssertTrue(popover.exists)
        XCTAssertEqual(popover.frame.width, 320, accuracy: 1)
        capture(popover, "03-menubar-popover")
    }

    func testSettingsWindowShowsMenuBarToggle() {
        launch(openWindow: "settings")

        let toggle = app.switches["settings.showFreeSpace"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "설정 창이 나타나지 않았습니다")
        XCTAssertEqual(toggle.value as? Int, 1, "기본값은 켬이어야 합니다")
        capture(app.windows.firstMatch, "04-settings-window")
    }
}
