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
        XCTAssertEqual(text(of: freeSpace), "여유 16.2GB · 업데이트까지 약 14GB 부족")
        XCTAssertEqual(text(of: app.staticTexts["menu.memory.pressure"]), "정상")
        XCTAssertEqual(text(of: app.staticTexts["menu.memory.swap"]), "스왑 0.5GB")
        XCTAssertEqual(text(of: app.staticTexts["menu.cleanable.empty"]), "아직 스캔하지 않았습니다")
        // 프로세스 행은 버튼이라 이름과 용량이 버튼 라벨 하나로 합쳐진다.
        let process = app.buttons["menu.process.0"]
        XCTAssertTrue(process.waitForExistence(timeout: 7), "상위 프로세스가 없습니다")
        XCTAssertEqual(process.label, "Xcode, 2.1GB")
        XCTAssertTrue(app.buttons["menu.openScanner"].exists)
        XCTAssertTrue(app.buttons["menu.quit"].exists)
        // MenuBarExtra(.window)의 팝오버는 접근성 트리에서 Dialog로 노출된다.
        let popover = app.dialogs.containing(.staticText, identifier: "menu.freeSpace").firstMatch
        XCTAssertTrue(popover.exists)
        XCTAssertEqual(popover.frame.width, 320, accuracy: 1)
        capture(popover, "03-menubar-popover")
    }

    /// 팝오버의 "스캐너 열기"·"설정…"은 팝오버를 닫고 창을 연다. 닫힌 뒤 아이콘 한 번으로 다시 열린다.
    func testPopoverButtonsClosePopover() {
        launch(openWindow: nil)
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "메뉴바 아이콘이 없습니다")
        let popover = app.dialogs.containing(.staticText, identifier: "menu.freeSpace").firstMatch

        statusItem.click()
        XCTAssertTrue(popover.waitForExistence(timeout: 5), "팝오버가 열리지 않았습니다")
        app.buttons["menu.openScanner"].click()
        XCTAssertTrue(popover.waitForNonExistence(timeout: 5), "스캐너 열기 후에도 팝오버가 남아 있습니다")
        let title = app.staticTexts["detail.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "스캐너 창이 열리지 않았습니다")
        XCTAssertEqual(text(of: title), "개발 찌꺼기")
        capture(app.windows.containing(.staticText, identifier: "detail.title").firstMatch, "05-after-open-scanner")

        statusItem.click()
        XCTAssertTrue(popover.waitForExistence(timeout: 5), "닫힌 뒤 아이콘을 한 번 눌러 팝오버가 다시 열리지 않았습니다")
        app.buttons["menu.settings"].click()
        XCTAssertTrue(popover.waitForNonExistence(timeout: 5), "설정 후에도 팝오버가 남아 있습니다")
        let toggle = app.switches["settings.showFreeSpace"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "설정 창이 열리지 않았습니다")
        let settingsWindow = app.windows.containing(.switch, identifier: "settings.showFreeSpace").firstMatch
        capture(settingsWindow, "06-after-open-settings")

        statusItem.click()
        XCTAssertTrue(popover.waitForExistence(timeout: 5), "설정 창을 연 뒤 팝오버가 다시 열리지 않았습니다")
    }

    func testSettingsWindowShowsMenuBarToggle() {
        launch(openWindow: "settings")

        let toggle = app.switches["settings.showFreeSpace"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "설정 창이 나타나지 않았습니다")
        XCTAssertEqual(toggle.value as? Int, 1, "기본값은 켬이어야 합니다")
        capture(app.windows.firstMatch, "04-settings-window")
    }
}
