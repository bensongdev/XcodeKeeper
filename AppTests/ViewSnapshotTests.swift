import SwiftUI
import XCTest
@testable import XcodeKeeper

/// 주요 화면의 화면 밖 스냅샷. UI 테스트와 같은 가짜 데이터(`-UITestMode`의 고정값)를 쓰고,
/// 실제 디스크·명령·휴지통은 건드리지 않는다.
final class ViewSnapshotTests: SnapshotTestCase {
    private func makeFixtureState() -> AppState {
        LaunchConfiguration(isUITest: true, windowToOpen: nil).makeAppState()
    }

    func testMenuBarPanel() {
        let state = makeFixtureState()
        XCTAssertEqual(state.availableBytes, LaunchConfiguration.uiTestAvailableBytes)
        snapshot(MenuBarView().environment(state), name: "01-menubar-panel")
    }

    /// 스캐너 창(760x540)에서 사이드바를 뺀 상세 영역 크기.
    private let detailSize = CGSize(width: 570, height: 540)

    func testScannerJunkAfterScan() async {
        let state = makeFixtureState()
        state.startScan()
        await state.waitForScan()
        XCTAssertFalse(state.scanResults.isScanning)
        XCTAssertFalse(state.scanResults.visibleTargets.isEmpty)
        snapshot(JunkListView().environment(state), name: "02-scanner-junk-scanned", size: detailSize)
    }

    func testScannerSimulators() async {
        let state = makeFixtureState()
        await state.loadSimulators()
        XCTAssertNotNil(state.simulatorState.inventory)
        snapshot(SimulatorView().environment(state), name: "03-scanner-simulators", size: detailSize)
    }

    func testSettings() {
        snapshot(SettingsView(), name: "04-settings")
    }
}
