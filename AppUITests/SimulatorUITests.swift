import XCTest

/// M3 시뮬레이터 UI 테스트. 가짜 simctl(UITestFixtures.FakeSimulatorManager, SDK 27.0)을 쓴다.
/// 런타임(용량 내림차순): iOS 26.5 8.4GB, iOS 27.0 8.0GB(현재 사용 중, 기기 2), iOS 17.0 7.0GB, watchOS 11.0 3.2GB(삭제 불가)
/// 기기: 사용 가능 3개 + 사용 불가 2개(iPhone 14, iPhone SE)
final class SimulatorUITests: UITestCase {
    private let ios27 = "9E08F66B-9997-4064-B010-AAAB27BE9601"
    private let ios265 = "385429F5-8FC2-4504-8348-245503EDCEE3"
    private let ios17 = "11111111-2222-3333-4444-555555555555"
    private let watch = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    private let unavailable = ["AAAA1111-0000-0000-0000-000000000001", "AAAA1111-0000-0000-0000-000000000002"]

    private func label(_ identifier: String) -> String {
        text(of: app.staticTexts[identifier])
    }

    private func openSimulators(_ extra: [String] = []) {
        launch(openWindow: "scanner", extraArguments: extra)
        let sidebar = app.descendants(matching: .any)["sidebar.simulators"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "스캐너 창이 나타나지 않았습니다")
        sidebar.click()
    }

    private func waitForList() {
        XCTAssertTrue(app.staticTexts["simulators.runtimes.header"].waitForExistence(timeout: 10), "목록이 없습니다")
    }

    func testRuntimeListThenInUseRuntimeNeedsSecondConfirmation() {
        openSimulators()
        waitForList()
        XCTAssertEqual(label("simulators.runtimes.header"), "런타임 4개 · 26.7GB")
        // 용량 내림차순
        let order = [ios265, ios27, ios17, watch].map { app.staticTexts["runtime.\($0).name"].frame.minY }
        XCTAssertEqual(order, order.sorted(), "용량 내림차순이 아님: \(order)")
        XCTAssertEqual([ios265, ios27, ios17, watch].map { label("runtime.\($0).size") },
                       ["8.4GB", "8.0GB", "7.0GB", "3.2GB"])
        XCTAssertEqual(label("runtime.\(ios27).name"), "iOS 27.0")
        XCTAssertTrue(app.staticTexts["runtime.\(ios27).current"].exists, "현재 사용 중 배지 없음")
        XCTAssertFalse(app.staticTexts["runtime.\(ios265).current"].exists)
        XCTAssertEqual(label("runtime.\(ios27).devices"), "기기 2개")
        XCTAssertFalse(app.buttons["runtime.\(watch).delete"].isEnabled, "삭제 불가 런타임")
        XCTAssertEqual(label("simulators.devices.header"), "기기 5개")
        for udid in unavailable {
            XCTAssertTrue(app.staticTexts["device.\(udid).unavailable"].exists, "사용 불가 배지 없음: \(udid)")
        }
        XCTAssertEqual(app.buttons["simulators.deleteUnavailable"].label, "사용 불가 기기 모두 삭제 (2)")
        XCTAssertEqual(label("device.1C9A210B-DB3E-403E-AC4F-1E7F9AA350D9.state"), "꺼짐")
        // 행이 창보다 넓어져 삭제 버튼이 밀려나지 않았는지
        for id in [ios265, ios27, ios17, watch] {
            XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["runtime.\(id).delete"].frame),
                          "삭제 버튼이 창 밖: \(id)")
        }
        assertLaidOutInsideWindow()
        capture(app.windows.firstMatch, "01-runtime-list")

        // 현재 사용 중 런타임: 첫 확인
        app.buttons["runtime.\(ios27).delete"].click()
        XCTAssertTrue(app.staticTexts["simulators.confirm.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(label("simulators.confirm.title"), "iOS 27.0 런타임을 삭제할까요?")
        XCTAssertEqual(label("simulators.confirm.detail"), "용량 8.0GB · 연결된 기기 2개")
        XCTAssertEqual(label("simulators.confirm.permanent"), "휴지통을 거치지 않고 바로 삭제됩니다. 되돌릴 수 없습니다.")
        XCTAssertFalse(app.staticTexts["simulators.confirm.inUseWarning"].exists)
        XCTAssertEqual(app.buttons["simulators.confirm.ok"].label, "삭제")

        // 두 번째 확인
        app.buttons["simulators.confirm.ok"].click()
        let warning = app.staticTexts["simulators.confirm.inUseWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "두 번째 확인이 나타나지 않았습니다")
        XCTAssertEqual(text(of: warning), "현재 Xcode가 기본으로 쓰는 런타임입니다. 지우면 이 버전의 시뮬레이터에서 "
            + "앱을 실행할 수 없고, 다시 쓰려면 수 GB를 다시 내려받아야 합니다.")
        XCTAssertEqual(app.buttons["simulators.confirm.ok"].label, "그래도 삭제")
        capture(app.windows.firstMatch, "02-in-use-reconfirm")

        // 취소하면 남아 있다
        app.buttons["simulators.confirm.cancel"].click()
        XCTAssertTrue(waitForDisappearance(app.staticTexts["simulators.confirm.title"]))
        XCTAssertTrue(app.staticTexts["runtime.\(ios27).name"].exists)
        XCTAssertEqual(label("simulators.runtimes.header"), "런타임 4개 · 26.7GB")
    }

    func testDeleteRuntimeAndUnavailableDevicesReloadsList() {
        openSimulators()
        waitForList()

        app.buttons["runtime.\(ios17).delete"].click()
        XCTAssertTrue(app.staticTexts["simulators.confirm.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(label("simulators.confirm.title"), "iOS 17.0 런타임을 삭제할까요?")
        app.buttons["simulators.confirm.ok"].click()
        XCTAssertTrue(waitForText(app.staticTexts["simulators.runtimes.header"], "런타임 3개 · 19.7GB", timeout: 10))
        XCTAssertFalse(app.staticTexts["runtime.\(ios17).name"].exists)

        app.buttons["simulators.deleteUnavailable"].click()
        XCTAssertTrue(app.staticTexts["simulators.confirm.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(label("simulators.confirm.title"), "사용 불가 기기 2개를 삭제할까요?")
        XCTAssertEqual(label("simulators.confirm.detail"), "xcrun simctl delete unavailable")
        app.buttons["simulators.confirm.ok"].click()
        XCTAssertTrue(waitForText(app.staticTexts["simulators.devices.header"], "기기 3개", timeout: 10))
        for udid in unavailable {
            XCTAssertFalse(app.staticTexts["device.\(udid).name"].exists, "사용 불가 기기가 남음: \(udid)")
        }
        XCTAssertEqual(app.buttons["simulators.deleteUnavailable"].label, "사용 불가 기기 모두 삭제 (0)")
        XCTAssertFalse(app.buttons["simulators.deleteUnavailable"].isEnabled)
        XCTAssertFalse(app.staticTexts["simulators.error.stderr"].exists)
        capture(app.windows.firstMatch, "01-after-delete-unavailable")
    }

    func testDeleteFailureShowsStderrVerbatim() {
        openSimulators(["-UITestSimctl", "deleteFails"])
        waitForList()
        app.buttons["runtime.\(ios265).delete"].click()
        XCTAssertTrue(app.staticTexts["simulators.confirm.title"].waitForExistence(timeout: 5))
        app.buttons["simulators.confirm.ok"].click()

        let stderr = app.staticTexts["simulators.error.stderr"]
        XCTAssertTrue(stderr.waitForExistence(timeout: 10), "오류가 표시되지 않았습니다")
        XCTAssertEqual(text(of: stderr),
                       "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, "
                       + "code=405):\nUnable to delete runtime: the runtime is in use by a booted device.")
        XCTAssertTrue(app.staticTexts["runtime.\(ios265).name"].exists, "실패한 런타임은 남아 있어야 함")
        assertLaidOutInsideWindow()
        XCTAssertTrue(app.windows.firstMatch.frame.contains(stderr.frame), "stderr가 창 밖으로 잘림")
        XCTAssertEqual(label("simulators.runtimes.header"), "런타임 4개 · 26.7GB")
        capture(app.windows.firstMatch, "01-delete-error-stderr")
    }

    func testMissingDeveloperToolsDisablesFeature() {
        openSimulators(["-UITestSimctl", "missing"])
        let guide = app.staticTexts["simulators.toolMissing.guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10), "도구 없음 안내가 없습니다")
        XCTAssertEqual(text(of: guide), "시뮬레이터를 관리하려면 Xcode가 설치되어 있고 선택되어 있어야 합니다. "
            + "Xcode를 설치한 뒤 터미널에서 sudo xcode-select -s /Applications/Xcode.app/Contents/Developer 를 실행하세요.")
        XCTAssertEqual(label("simulators.toolMissing.detail"),
                       "xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools)")
        XCTAssertFalse(app.staticTexts["simulators.runtimes.header"].exists)
        XCTAssertFalse(app.buttons["simulators.deleteUnavailable"].exists)
        assertLaidOutInsideWindow()
        capture(app.windows.firstMatch, "01-clt-missing")
    }

    /// 머리글과 사이드바가 창 안에 있는지(레이아웃이 창보다 커져 밀려나지 않았는지) 확인한다.
    private func assertLaidOutInsideWindow(file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        for identifier in ["detail.title", "sidebar.junk", "sidebar.history"] {
            let frame = app.descendants(matching: .any)[identifier].frame
            XCTAssertTrue(window.contains(frame), "\(identifier)가 창 밖에 있음: \(frame) / 창 \(window)",
                          file: file, line: line)
        }
    }
}
