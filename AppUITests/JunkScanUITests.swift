import XCTest

/// M1 스캐너 UI 테스트. 가짜 대상(UITestFixtures)을 쓰며, Archives는 3초 늦게 끝난다.
/// 기본 선택 합계(안전): DerivedData 4.3 + Xcode 0.6 + SwiftPM 0.3 + 사용 불가 기기 1.5 + Homebrew 0.2 = 6.9GB
final class JunkScanUITests: UITestCase {
    private func status(_ targetID: String) -> XCUIElement {
        app.staticTexts["target.\(targetID).status"]
    }

    private func checkbox(_ targetID: String) -> XCUIElement {
        app.checkBoxes["target.\(targetID).checkbox"]
    }

    func testScanShowsProgressThenDefaultSelectionAndExplanation() {
        launch(openWindow: "scanner")
        let window = app.windows.firstMatch

        // 스캔 전
        let scanButton = app.buttons["scan.start"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 10), "스캐너 창이 나타나지 않았습니다")
        XCTAssertEqual(scanButton.label, "스캔")
        XCTAssertEqual(text(of: app.staticTexts["selection.total"]), "선택 0.0GB")
        XCTAssertFalse(status("derivedData").exists, "스캔 전에는 대상 목록이 없어야 함")
        capture(window, "01-before-scan")

        // 스캔 중: 끝난 대상은 용량, Archives는 아직 진행 중
        scanButton.click()
        XCTAssertTrue(waitForText(status("derivedData"), "4.3GB"), "DerivedData: \(text(of: status("derivedData")))")
        XCTAssertEqual(text(of: status("archives")), "스캔 중")
        XCTAssertEqual(checkboxValue(checkbox("archives")), 0, "스캔 중인 대상은 체크되어 보이면 안 됨")
        XCTAssertFalse(checkbox("archives").isEnabled)
        XCTAssertTrue(app.buttons["scan.cancel"].exists)
        capture(window, "02-scan-in-progress")

        // 완료: 기본 선택(안전=선택, 주의=미선택), 있을 때만 표시 대상은 숨김
        XCTAssertTrue(waitForText(status("archives"), "450MB", timeout: 10),
                      "Archives: \(text(of: status("archives")))")
        XCTAssertTrue(waitForText(app.staticTexts["selection.total"], "선택 6.9GB"))
        XCTAssertEqual(checkboxValue(checkbox("derivedData")), 1)
        XCTAssertEqual(checkboxValue(checkbox("unavailableSimulators")), 1)
        XCTAssertEqual(checkboxValue(checkbox("iOSDeviceSupport")), 0)
        XCTAssertEqual(checkboxValue(checkbox("archives")), 0)
        XCTAssertFalse(checkbox("localSnapshots").exists, "정보만 대상은 체크박스가 없음")
        XCTAssertEqual(text(of: status("localSnapshots")), "2개")
        XCTAssertFalse(status("cocoaPodsCache").exists, "항목이 없는 CocoaPods 캐시는 숨김")
        XCTAssertFalse(status("otherDeviceSupport").exists, "항목이 없는 기타 DeviceSupport는 숨김")
        XCTAssertEqual(text(of: status("homebrewCache")), "200MB")
        XCTAssertEqual(scanButton.label, "다시 스캔")
        XCTAssertFalse(app.buttons["scan.cancel"].exists)
        // DerivedData를 펼치면 프로젝트별 항목과 용량이 보인다(용량 내림차순)
        app.buttons["target.derivedData.expand"].click()
        let firstItem = app.staticTexts["item.derivedData.XcodeKeeper"]
        XCTAssertTrue(firstItem.waitForExistence(timeout: 5), "DerivedData 하위 항목이 없습니다")
        XCTAssertEqual(text(of: app.staticTexts["item.derivedData.XcodeKeeper.size"]), "3.2GB")
        XCTAssertEqual(text(of: app.staticTexts["item.derivedData.HelloMac.size"]), "1.1GB")
        XCTAssertLessThan(firstItem.frame.minY, app.staticTexts["item.derivedData.HelloMac"].frame.minY)
        capture(window, "03-scan-complete-default-selection")

        // 설명 팝오버
        app.buttons["target.derivedData.info"].click()
        let explanation = app.staticTexts["target.derivedData.explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5), "설명 팝오버가 열리지 않았습니다")
        XCTAssertEqual(text(of: explanation), "Xcode 빌드 중간 산출물과 인덱스입니다. 지워도 안전하며, "
            + "다음 빌드 때 다시 만들어집니다. 지운 직후 첫 빌드와 인덱싱이 느려집니다.")
        capture(window, "04-explanation-popover")

        // 주의 대상을 직접 선택하면 합계가 늘어난다
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(explanation))
        checkbox("iOSDeviceSupport").click()
        XCTAssertEqual(checkboxValue(checkbox("iOSDeviceSupport")), 1)
        XCTAssertTrue(waitForText(app.staticTexts["selection.total"], "선택 9.7GB"))
        capture(window, "05-after-select-caution")
    }

    func testCancelScanMarksUnfinishedTargets() {
        launch(openWindow: "scanner")
        let scanButton = app.buttons["scan.start"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 10))
        scanButton.click()
        XCTAssertTrue(waitForText(status("derivedData"), "4.3GB"))
        XCTAssertEqual(text(of: status("archives")), "스캔 중")

        app.buttons["scan.cancel"].click()
        XCTAssertTrue(waitForText(status("archives"), "취소됨"))
        XCTAssertEqual(checkboxValue(checkbox("archives")), 0, "취소된 대상은 체크되어 보이면 안 됨")
        XCTAssertEqual(text(of: status("derivedData")), "4.3GB", "끝난 대상은 결과를 유지")
        XCTAssertFalse(app.buttons["scan.cancel"].exists)
        XCTAssertEqual(scanButton.label, "스캔", "완료되지 않았으므로 '다시 스캔'이 아님")
        capture(app.windows.firstMatch, "01-scan-cancelled")
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !element.exists
    }
}
