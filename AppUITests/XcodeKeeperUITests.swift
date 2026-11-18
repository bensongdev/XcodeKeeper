import XCTest

/// M0 뼈대 UI 테스트. `-UITestMode YES`로 실행해 실제 디스크 대신 고정된 여유 공간(16.2GB)을 쓴다.
@MainActor
final class XcodeKeeperUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
    }

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

    // MARK: - 도우미

    private func launch(openWindow: String?) {
        app = XCUIApplication()
        // 설정 기본값을 실행 인자 영역에서 고정해 사용자 설정의 영향을 받지 않게 한다.
        app.launchArguments = ["-UITestMode", "YES", "-showFreeSpaceInMenuBar", "YES"]
        if let openWindow {
            app.launchArguments += ["-UITestOpenWindow", openWindow]
        }
        app.launch()
    }

    // macOS에서 SwiftUI Text의 문자열은 접근성 label이 아니라 value로 노출된다.
    private func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private func waitForText(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if text(of: element) == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return text(of: element) == expected
    }

    private func capture(_ element: XCUIElement, _ name: String) {
        // 메뉴바 앱(LSUIElement)의 창은 다른 앱 뒤에서 열릴 수 있다. 전면으로 올리고,
        // 창이 나타나는 애니메이션이 끝날 때까지 기다린 뒤 찍어야 다른 창이 증거에 섞이지 않는다.
        if element.elementType == .window { app.activate() }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "캡처 대상이 없습니다: \(name)")
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
