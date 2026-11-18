import XCTest
@testable import XcodeKeeper

final class ScanResultsTests: XCTestCase {
    private let safe = makeTarget("safe", safety: .safe)
    private let caution = makeTarget("caution", safety: .caution)
    private let info = makeTarget("info", safety: .infoOnly, method: .none)
    private let group = makeTarget("group", method: .command(["simctl", "delete", "unavailable"]))
    private let optional = makeTarget("optional", hideWhenEmpty: true)

    private func results() -> ScanResults {
        var results = ScanResults(targets: [safe, caution, info, group, optional])
        results.beginScan()
        return results
    }

    func testBeginScanMarksAllScanning() {
        let results = results()
        XCTAssertTrue(results.isScanning)
        for id in ["safe", "caution", "info", "group", "optional"] {
            XCTAssertEqual(results.status(of: id), .scanning)
        }
    }

    func testSafeItemsAreSelectedByDefaultCautionAndInfoAreNot() {
        var results = results()
        results.apply(.finished(targetID: "safe", items: [makeItem("a", bytes: 100), makeItem("b", bytes: 50)]))
        results.apply(.finished(targetID: "caution", items: [makeItem("c", bytes: 1_000)]))
        results.apply(.finished(targetID: "info", items: [ScanItem(id: "snap", name: "snap")]))

        XCTAssertTrue(results.isSelected("safe", "/tmp/a"))
        XCTAssertTrue(results.isSelected("safe", "/tmp/b"))
        XCTAssertFalse(results.isSelected("caution", "/tmp/c"))
        XCTAssertFalse(results.isSelected("info", "snap"))
        XCTAssertEqual(results.selectedBytes, 150)
        XCTAssertEqual(results.totalBytes(of: "caution"), 1_000)
    }

    func testToggleItemAndAllUpdatesSelectedBytes() {
        var results = results()
        results.apply(.finished(targetID: "caution", items: [makeItem("c1", bytes: 10), makeItem("c2", bytes: 20)]))
        results.setSelected(true, targetID: "caution", itemID: "/tmp/c2")
        XCTAssertEqual(results.selectedBytes, 20)
        results.setAllSelected(true, targetID: "caution")
        XCTAssertEqual(results.selectedBytes, 30)
        results.setAllSelected(false, targetID: "caution")
        XCTAssertEqual(results.selectedBytes, 0)
    }

    func testInfoOnlyCannotBeSelected() {
        var results = results()
        results.apply(.finished(targetID: "info", items: [ScanItem(id: "snap", name: "snap")]))
        results.setSelected(true, targetID: "info", itemID: "snap")
        results.setAllSelected(true, targetID: "info")
        XCTAssertEqual(results.selectedItemCount, 0)
    }

    func testGroupTargetTogglesAllItemsTogether() {
        var results = results()
        results.apply(.finished(targetID: "group", items: [makeItem("d1", bytes: 1), makeItem("d2", bytes: 2)]))
        XCTAssertEqual(results.selectedBytes, 3, "안전 대상이라 기본 선택")
        results.setSelected(false, targetID: "group", itemID: "/tmp/d1")
        XCTAssertFalse(results.isSelected("group", "/tmp/d2"), "그룹 단위 대상은 하나만 해제할 수 없음")
        XCTAssertEqual(results.selectedBytes, 0)
    }

    func testHideWhenEmptyVisibility() {
        var results = results()
        XCTAssertFalse(results.visibleTargets.map(\.id).contains("optional"), "스캔 중에는 숨김")
        results.apply(.finished(targetID: "optional", items: []))
        XCTAssertFalse(results.visibleTargets.map(\.id).contains("optional"), "항목이 없으면 숨김")
        results.apply(.finished(targetID: "optional", items: [makeItem("o", bytes: 1)]))
        XCTAssertTrue(results.visibleTargets.map(\.id).contains("optional"))
        results.apply(.failed(targetID: "optional", failure: .commandFailed("x")))
        XCTAssertTrue(results.visibleTargets.map(\.id).contains("optional"), "실패는 보여 줌")
        XCTAssertEqual(results.visibleTargets.prefix(4).map(\.id), ["safe", "caution", "info", "group"])
    }

    func testMarkUnfinishedCancelled() {
        var results = results()
        results.apply(.finished(targetID: "safe", items: []))
        results.markUnfinishedCancelled()
        XCTAssertEqual(results.status(of: "safe"), .done([]))
        XCTAssertEqual(results.status(of: "caution"), .cancelled)
        XCTAssertFalse(results.isScanning)
    }

    func testNewScanClearsSelection() {
        var results = results()
        results.apply(.finished(targetID: "safe", items: [makeItem("a", bytes: 1)]))
        results.beginScan()
        XCTAssertEqual(results.selectedItemCount, 0)
    }
}

@MainActor
final class AppStateScanTests: XCTestCase {
    private func makeState(_ targets: [CleanupTarget]) -> AppState {
        AppState(
            diskSpace: FixedDiskSpaceProvider(bytes: 1),
            scanner: makeScanner(targets), cleanup: makeCleanupServices(),
            simulators: FakeSimulators()
        )
    }

    func testScanCompletesAndRecordsDate() async {
        let state = makeState([
            makeTarget("a", result: .success([makeItem("x", bytes: 7)])),
            makeTarget("b", safety: .caution, result: .success([makeItem("y", bytes: 9)]))
        ])
        XCTAssertNil(state.lastScanDate)
        state.startScan()
        XCTAssertTrue(state.isScanning)
        await state.waitForScan()

        XCTAssertFalse(state.isScanning)
        XCTAssertNotNil(state.lastScanDate)
        XCTAssertEqual(state.scanResults.status(of: "a"), .done([makeItem("x", bytes: 7)]))
        XCTAssertEqual(state.scanResults.selectedBytes, 7)
    }

    func testCancelScanMarksUnfinishedTargets() async throws {
        let state = makeState([
            makeTarget("fast", result: .success([])),
            makeTarget("slow", delay: .seconds(10))
        ])
        state.startScan()
        try await Task.sleep(for: .milliseconds(300))
        state.cancelScan()

        XCTAssertFalse(state.isScanning)
        XCTAssertEqual(state.scanResults.status(of: "slow"), .cancelled)
        XCTAssertEqual(state.scanResults.status(of: "fast"), .done([]))
        XCTAssertNil(state.lastScanDate, "취소한 스캔은 완료 시각을 남기지 않음")
    }
}

final class TargetStatusTextTests: XCTestCase {
    func testStatusTexts() {
        XCTAssertEqual(TargetStatusText.text(for: .notScanned, safety: .safe), "—")
        XCTAssertEqual(TargetStatusText.text(for: .scanning, safety: .safe), "스캔 중")
        XCTAssertEqual(TargetStatusText.text(for: .cancelled, safety: .safe), "취소됨")
        XCTAssertEqual(TargetStatusText.text(for: .failed(.permissionDenied), safety: .safe), "권한 없음")
        XCTAssertEqual(TargetStatusText.text(for: .failed(.commandFailed("x")), safety: .safe), "확인 불가")
        XCTAssertEqual(TargetStatusText.text(for: .done([]), safety: .caution), "없음", "빈 대상은 '1MB 미만'이 아님")
        XCTAssertEqual(TargetStatusText.text(for: .done([makeItem("a", bytes: 3_200_000_000)]), safety: .safe), "3.2GB")
        XCTAssertEqual(
            TargetStatusText.text(for: .done([ScanItem(id: "s", name: "s"), ScanItem(id: "t", name: "t")]),
                                  safety: .infoOnly),
            "2개"
        )
        XCTAssertEqual(TargetStatusText.text(for: .done([]), safety: .infoOnly), "0개")
    }
}
