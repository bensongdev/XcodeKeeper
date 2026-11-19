import XCTest
@testable import XcodeKeeper

@MainActor
final class AppStateMonitorTests: XCTestCase {
    private let gb: Int64 = 1_000_000_000
    private let now = Date(timeIntervalSince1970: 1_794_000_000)
    private let derived = makeTarget("derived", result: .success([
        makeItem("d1", bytes: 3_000_000_000), makeItem("d2", bytes: 1_200_000_000)
    ]))
    private let caution = makeTarget("archives", safety: .caution, result: .success([
        makeItem("a1", bytes: 2_000_000_000)
    ]))
    private let small = makeTarget("small", result: .success([makeItem("s1", bytes: 10_000_000)]))

    private func makeState(
        available: Int64? = 16_200_000_000, notifier: RecordingNotifier = RecordingNotifier(),
        power: PowerState = PowerState(isLowPowerMode: false), loginItem: FakeLoginItem = FakeLoginItem()
    ) -> AppState {
        AppState(
            diskSpace: FixedDiskSpaceProvider(bytes: available, total: 245 * gb),
            scanner: makeScanner([derived, caution, small]), cleanup: makeCleanupServices(),
            simulators: FakeSimulators(),
            monitor: .fixed(memory: UITestFixtures.criticalMemory, processes: UITestFixtures.processes,
                            notifier: notifier, power: power, loginItem: loginItem)
        )
    }

    func testRefreshReadsProcessesOnlyWhenPopoverVisible() async {
        let state = makeState()
        XCTAssertEqual(state.totalBytes, 245 * gb)
        await state.refreshMonitor()
        XCTAssertEqual(state.memory, UITestFixtures.criticalMemory)
        XCTAssertEqual(state.topProcesses, [], "팝오버가 닫혀 있으면 프로세스를 읽지 않음")

        state.isPopoverVisible = true
        await state.refreshMonitor()
        XCTAssertEqual(state.topProcesses.map(\.name),
                       ["Xcode", "Simulator", "Safari", "swift-frontend", "WindowServer"])
        XCTAssertEqual(state.statusLevel, .critical)
    }

    /// 팝오버가 닫혀 있으면 아이콘 색·메뉴바 숫자가 바뀔 때만 상태를 바꾼다(유휴 CPU).
    func testClosedPopoverUpdatesStateOnlyWhenIconChanges() async {
        let system = MutableSystemMonitor(UITestFixtures.normalMemory)
        let disk = MutableDiskSpace(40_200_000_000)
        let state = AppState(
            diskSpace: disk, scanner: makeScanner([]), cleanup: makeCleanupServices(), simulators: FakeSimulators(),
            monitor: MonitorServices(system: system, notifier: RecordingNotifier(),
                                     power: FixedPowerState(), loginItem: FakeLoginItem())
        )
        await state.refreshMonitor()
        XCTAssertEqual(state.memory, UITestFixtures.normalMemory, "처음 값은 반영")

        var slightlyMore = UITestFixtures.normalMemory
        slightlyMore.swapUsedBytes = 600_000_000
        system.memory = slightlyMore
        disk.bytes = 40_700_000_000
        state.lastDiskReadAt = nil
        await state.refreshMonitor()
        XCTAssertEqual(state.memory, UITestFixtures.normalMemory, "색이 그대로면 반영하지 않음")
        XCTAssertEqual(state.availableBytes, 40_200_000_000, "메뉴바 숫자(40G)가 그대로면 반영하지 않음")

        disk.bytes = 39_900_000_000
        await state.refreshMonitor()
        XCTAssertEqual(state.availableBytes, 40_200_000_000, "닫혀 있으면 여유 공간은 60초에 한 번만 읽음")
        state.lastDiskReadAt = Date().addingTimeInterval(-AppState.closedDiskInterval)
        await state.refreshMonitor()
        XCTAssertEqual(state.availableBytes, 39_900_000_000, "60초 뒤에 읽고, 40G → 39G라 반영")

        var swapping = UITestFixtures.normalMemory
        swapping.swapUsedBytes = 3_000_000_000
        system.memory = swapping
        await state.refreshMonitor()
        XCTAssertEqual(state.memory, swapping, "스왑 기준 초과로 색이 바뀌면 반영")
        XCTAssertEqual(state.statusLevel, .warning)

        state.isPopoverVisible = true
        system.memory = slightlyMore
        await state.refreshMonitor()
        XCTAssertEqual(state.memory, slightlyMore, "팝오버가 열려 있으면 항상 반영")
    }

    func testStatusLevelFollowsSettings() async {
        let state = AppState(
            diskSpace: FixedDiskSpaceProvider(bytes: 40 * gb), scanner: makeScanner([]),
            cleanup: makeCleanupServices(), simulators: FakeSimulators(),
            monitor: .fixed(memory: UITestFixtures.normalMemory)
        )
        await state.refreshMonitor()
        XCTAssertEqual(state.statusLevel, .normal, "40GB 여유, 스왑 0.5GB")
        state.settings.freeSpaceThresholdGB = 50
        XCTAssertEqual(state.statusLevel, .warning, "기준을 올리면 바로 노랑")
    }

    func testBackgroundScanSendsAlertOnceWithin24Hours() async {
        let notifier = RecordingNotifier()
        let state = makeState(notifier: notifier)

        let first = await state.runBackgroundScan(now: now)
        XCTAssertEqual(first, .scanned(alertSent: true))
        XCTAssertEqual(notifier.sent, [AlertContent(
            title: "여유 공간이 16.2GB 남았습니다", body: "정리 가능: derived 4.2GB, archives 2.0GB",
            targetIDs: ["derived", "archives"]
        )])
        XCTAssertEqual(state.settings.lastFreeSpaceAlertAt, now)

        let second = await state.runBackgroundScan(now: now.addingTimeInterval(3_600))
        XCTAssertEqual(second, .scanned(alertSent: false), "24시간 안에는 다시 보내지 않음")
        let third = await state.runBackgroundScan(now: now.addingTimeInterval(24 * 3_600))
        XCTAssertEqual(third, .scanned(alertSent: true))
        XCTAssertEqual(notifier.sent.count, 2)
    }

    func testNoAlertAboveThresholdOrWhenPermissionDenied() async {
        let enough = makeState(available: 31 * gb)
        let outcome = await enough.runBackgroundScan(now: now)
        XCTAssertEqual(outcome, .scanned(alertSent: false))

        let denied = RecordingNotifier(succeeds: false)
        let state = makeState(notifier: denied)
        let deniedOutcome = await state.runBackgroundScan(now: now)
        XCTAssertEqual(deniedOutcome, .scanned(alertSent: false))
        XCTAssertEqual(denied.sent.count, 1, "보내려고는 함")
        XCTAssertNil(state.settings.lastFreeSpaceAlertAt, "실패하면 쿨다운을 기록하지 않음")
    }

    func testBackgroundScanSkipConditions() async {
        let disabled = makeState()
        disabled.settings.backgroundScanEnabled = false
        let disabledOutcome = await disabled.runBackgroundScan(now: now)
        XCTAssertEqual(disabledOutcome, .disabled)
        XCTAssertNil(disabled.lastScanDate)

        let lowPower = makeState(power: PowerState(isLowPowerMode: true))
        let lowPowerOutcome = await lowPower.runBackgroundScan(now: now)
        XCTAssertEqual(lowPowerOutcome, .skippedPower)
        let battery = makeState(power: PowerState(isLowPowerMode: false, batteryPercent: 15))
        let batteryOutcome = await battery.runBackgroundScan(now: now)
        XCTAssertEqual(batteryOutcome, .skippedPower)
        XCTAssertNil(battery.lastScanDate, "건너뛰면 스캔하지 않음")

        let windowOpen = makeState()
        windowOpen.isScannerWindowVisible = true
        let windowOutcome = await windowOpen.runBackgroundScan(now: now)
        XCTAssertEqual(windowOutcome, .busy, "열린 창의 선택을 덮지 않음")

        let cleaning = makeState()
        cleaning.cleanupPhase = .cleaning
        let cleaningOutcome = await cleaning.runBackgroundScan(now: now)
        XCTAssertEqual(cleaningOutcome, .busy)
    }

    func testAlertClickOpensScannerAndSelectsTargets() async {
        let state = makeState()
        state.selectedSection = .history
        await state.handleAlertClick(targetIDs: ["derived", "archives"])
        XCTAssertEqual(state.selectedSection, .junk)
        XCTAssertEqual(state.scannerWindowRequest, 1)
        XCTAssertNotNil(state.lastScanDate, "스캔 결과가 없으면 먼저 스캔")
        XCTAssertTrue(state.scanResults.isSelected("archives", "/tmp/a1"), "주의 대상도 알림에 있으면 선택")
        XCTAssertTrue(state.scanResults.isSelected("derived", "/tmp/d1"))
        XCTAssertTrue(state.scanResults.isSelected("derived", "/tmp/d2"))
        XCTAssertTrue(state.scanResults.isSelected("small", "/tmp/s1"), "기본 선택은 그대로")

        // 이미 스캔한 결과가 있으면 다시 스캔하지 않는다.
        let scannedAt = state.lastScanDate
        state.scanResults.setAllSelected(false, targetID: "archives")
        await state.handleAlertClick(targetIDs: ["archives"])
        XCTAssertEqual(state.lastScanDate, scannedAt)
        XCTAssertTrue(state.scanResults.isSelected("archives", "/tmp/a1"))
        XCTAssertEqual(state.scannerWindowRequest, 2)
    }

    func testLoginItemToggleApprovalAndFailure() {
        let item = FakeLoginItem()
        let state = makeState(loginItem: item)
        state.refreshLoginItemStatus()
        XCTAssertEqual(state.loginItemStatus, .disabled)
        state.setLoginItemEnabled(true)
        XCTAssertEqual(state.loginItemStatus, .enabled)
        XCTAssertNil(state.loginItemError)
        state.setLoginItemEnabled(false)
        XCTAssertEqual(state.loginItemStatus, .disabled)

        let approval = makeState(loginItem: FakeLoginItem(requiresApprovalOnEnable: true))
        approval.setLoginItemEnabled(true)
        XCTAssertEqual(approval.loginItemStatus, .requiresApproval)

        let failure = NSError(domain: "SMAppServiceErrorDomain", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        let failing = makeState(loginItem: FakeLoginItem(failure: failure))
        failing.setLoginItemEnabled(true)
        XCTAssertEqual(failing.loginItemError, "Operation not permitted")
        XCTAssertEqual(failing.loginItemStatus, .disabled)
    }
}

private final class MutableSystemMonitor: SystemMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: MemorySnapshot

    init(_ memory: MemorySnapshot) { stored = memory }

    var memory: MemorySnapshot {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func snapshot() -> MemorySnapshot? { memory }
    func topProcesses(limit: Int) -> [ProcessMemory] { [] }
}

private final class MutableDiskSpace: DiskSpaceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int64

    init(_ bytes: Int64) { stored = bytes }

    var bytes: Int64 {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func availableBytes() -> Int64? { bytes }
    func totalBytes() -> Int64? { 245_000_000_000 }
}
