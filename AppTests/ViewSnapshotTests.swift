import SwiftUI
import XCTest
@testable import XcodeKeeper

/// 주요 화면의 화면 밖 스냅샷. UI 테스트와 같은 가짜 데이터(`-UITestMode`의 고정값)를 쓰고,
/// 실제 디스크·명령·휴지통은 건드리지 않는다.
final class ViewSnapshotTests: SnapshotTestCase {
    private func makeFixtureState() -> AppState {
        LaunchConfiguration(isUITest: true, windowToOpen: nil).makeAppState()
    }

    /// UI 테스트 기본 상태: 스캔 전, 여유 16.2GB(기준 30GB 미만), 메모리 정상.
    func testMenuBarPanel() async {
        let state = makeFixtureState()
        state.isPopoverVisible = true
        await state.refreshMonitor()
        XCTAssertEqual(state.availableBytes, LaunchConfiguration.uiTestAvailableBytes)
        XCTAssertNil(state.lastScanDate)
        XCTAssertEqual(state.memory?.pressure, .normal)
        XCTAssertEqual(state.topProcesses.count, 5)
        XCTAssertEqual(state.statusLevel, .warning)
        snapshot(MenuBarView().environment(state), name: "01-menubar-panel")
    }

    /// 여유 공간 충분, 메모리 정상, 스캔 완료: 아이콘 기본색.
    func testPopoverNormal() async {
        let fixture = makeFixtureState()
        let state = AppState(
            diskSpace: FixedDiskSpaceProvider(bytes: 52_400_000_000, total: UITestFixtures.diskTotalBytes),
            scanner: JunkScanner(targets: UITestFixtures.targets, environment: UITestFixtures.environment),
            cleanup: fixture.cleanup, simulators: fixture.simulatorManager,
            monitor: UITestFixtures.monitorServices(memoryScenario: nil)
        )
        state.isPopoverVisible = true
        await state.refreshMonitor()
        state.startScan()
        await state.waitForScan()
        XCTAssertEqual(state.statusLevel, .normal)
        XCTAssertNil(FreeSpaceAlert.shortageText(availableBytes: state.availableBytes,
                                                 thresholdBytes: state.settings.freeSpaceThresholdBytes))
        XCTAssertEqual(state.scanResults.topCleanable(limit: 3).count, 3)
        snapshot(MenuBarView().environment(state), name: "05-popover-normal")
    }

    /// 여유 16.2GB(기준 미만) + 메모리 압박 위험 + 스왑 3.4GB: 아이콘 빨강.
    func testPopoverWarning() async {
        let config = LaunchConfiguration(isUITest: true, windowToOpen: nil, memoryScenario: "critical")
        let state = config.makeAppState()
        state.isPopoverVisible = true
        await state.refreshMonitor()
        state.startScan()
        await state.waitForScan()
        XCTAssertEqual(state.memory?.pressure, .critical)
        XCTAssertEqual(state.statusLevel, .critical)
        XCTAssertEqual(FreeSpaceAlert.shortageText(availableBytes: state.availableBytes,
                                                   thresholdBytes: state.settings.freeSpaceThresholdBytes),
                       "업데이트까지 약 14GB 부족")
        snapshot(MenuBarView().environment(state), name: "06-popover-warning")
    }

    func testMenuBarIconColors() {
        XCTAssertNil(StatusLevel.normal.color)
        XCTAssertEqual(StatusLevel.warning.color, .systemYellow)
        XCTAssertEqual(StatusLevel.critical.color, .systemRed)
        let icons = HStack(spacing: 16) {
            ForEach([StatusLevel.normal, .warning, .critical], id: \.self) { level in
                MenuBarLabel.icon(for: level)
            }
        }
        .padding(6)
        .background(Color.white)
        .scaleEffect(3)
        .frame(width: 240, height: 90)
        snapshot(icons, name: "08-menubar-icon-levels")
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
        let state = makeFixtureState()
        state.refreshLoginItemStatus()
        XCTAssertEqual(state.settings.freeSpaceThresholdGB, 30)
        XCTAssertEqual(state.settings.swapThresholdGB, 2)
        XCTAssertTrue(state.settings.backgroundScanEnabled)
        XCTAssertEqual(state.loginItemStatus, .disabled)
        snapshot(SettingsView().environment(state), name: "04-settings")
    }

    /// 로그인 항목을 켰지만 시스템 설정에서 허용이 필요한 상태.
    func testSettingsLoginItemNeedsApproval() {
        let fixture = makeFixtureState()
        let state = AppState(
            diskSpace: FixedDiskSpaceProvider(bytes: 1), scanner: makeScanner([]), cleanup: fixture.cleanup,
            simulators: fixture.simulatorManager,
            monitor: .fixed(loginItem: FakeLoginItem(requiresApprovalOnEnable: true))
        )
        state.setLoginItemEnabled(true)
        XCTAssertEqual(state.loginItemStatus, .requiresApproval)
        snapshot(SettingsView().environment(state), name: "07-settings-login-approval")
    }
}
