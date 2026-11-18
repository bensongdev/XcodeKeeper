import XCTest

/// UI 테스트 공통 도우미. `-UITestMode YES`로 실행해 실제 디스크와 명령 대신 고정된 가짜 데이터를 쓴다.
@MainActor
class UITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    // MARK: - 도우미

    func launch(openWindow: String?) {
        app = XCUIApplication()
        // 설정 기본값을 실행 인자 영역에서 고정해 사용자 설정의 영향을 받지 않게 한다.
        app.launchArguments = ["-UITestMode", "YES", "-showFreeSpaceInMenuBar", "YES"]
        if let openWindow {
            app.launchArguments += ["-UITestOpenWindow", openWindow]
        }
        app.launch()
    }

    // macOS에서 SwiftUI Text의 문자열은 접근성 label이 아니라 value로 노출된다.
    func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    func waitForText(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if text(of: element) == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return text(of: element) == expected
    }

    func capture(_ element: XCUIElement, _ name: String) {
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

    /// 체크박스(Toggle) 값: 1 켬, 0 끔, 그 밖의 값은 혼합 상태.
    func checkboxValue(_ element: XCUIElement) -> Int? {
        element.value as? Int
    }
}
