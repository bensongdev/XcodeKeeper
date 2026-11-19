import Foundation
import Observation

/// 스캐너 창 사이드바 항목.
enum ScannerSection: String, CaseIterable, Identifiable, Sendable {
    case junk
    case simulators
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .junk: String(localized: "개발 찌꺼기")
        case .simulators: String(localized: "시뮬레이터")
        case .history: String(localized: "정리 이력")
        }
    }

    var systemImage: String {
        switch self {
        case .junk: "trash"
        case .simulators: "iphone"
        case .history: "clock.arrow.circlepath"
        }
    }
}

/// 앱 전체 상태. UI는 이 객체만 구독하고, 시스템 호출은 주입된 서비스가 맡는다.
@MainActor
@Observable
final class AppState {
    private let diskSpace: any DiskSpaceProviding
    private let scanner: JunkScanner
    let cleanup: CleanupServices
    private var scanTask: Task<Void, Never>?
    /// 정리 실행 Task(AppState+Cleanup.swift에서 관리).
    var cleanupTask: Task<Void, Never>?

    var selectedSection: ScannerSection? = .junk
    private(set) var availableBytes: Int64?
    var scanResults: ScanResults
    private(set) var lastScanDate: Date?
    var cleanupPhase: CleanupPhase = .idle
    var history: [CleanupRecord]

    // 시뮬레이터 화면(AppState+Simulators.swift)
    let simulatorManager: any SimulatorManaging
    var simulatorState: SimulatorScreenState = .notLoaded
    var simulatorConfirmation: SimulatorConfirmation?
    var isSimulatorBusy = false
    /// 마지막 삭제 명령의 실패 메시지(stderr 원문).
    var simulatorError: String?

    // 모니터·알림·설정(AppState+Monitor.swift)
    let settings: AppSettings
    let monitor: MonitorServices
    private(set) var totalBytes: Int64?
    var memory: MemorySnapshot?
    var topProcesses: [ProcessMemory] = []
    var isPopoverVisible = false
    var isScannerWindowVisible = false
    /// 값이 바뀌면 메뉴바 라벨이 스캐너 창을 연다(AppKit 알림 처리기에서 창을 열기 위해).
    var scannerWindowRequest = 0
    var loginItemStatus: LoginItemStatus = .disabled
    var loginItemError: String?
    @ObservationIgnored var monitorTask: Task<Void, Never>?
    /// 팝오버가 닫혀 있을 때 마지막으로 여유 공간을 읽은 시각.
    @ObservationIgnored var lastDiskReadAt: Date?
    @ObservationIgnored var backgroundScheduler: NSBackgroundActivityScheduler?

    init(
        diskSpace: any DiskSpaceProviding, scanner: JunkScanner, cleanup: CleanupServices,
        simulators: any SimulatorManaging, monitor: MonitorServices = .fixed(), settings: AppSettings? = nil
    ) {
        self.diskSpace = diskSpace
        self.scanner = scanner
        self.cleanup = cleanup
        self.simulatorManager = simulators
        self.monitor = monitor
        self.settings = settings ?? .ephemeral()
        self.scanResults = ScanResults(targets: scanner.targets)
        self.history = cleanup.history.load()
        refreshDiskSpace()
    }

    var isScanning: Bool { scanTask != nil }

    func refreshDiskSpace() {
        availableBytes = diskSpace.availableBytes()
        totalBytes = diskSpace.totalBytes()
    }

    /// 여유 공간을 읽기만 하고 상태에는 반영하지 않는다(모니터가 바뀐 경우에만 반영하려고).
    func readAvailableBytes() -> Int64? {
        diskSpace.availableBytes()
    }

    /// 스캔을 시작한다. 진행 중인 스캔이 있으면 취소하고 새로 시작한다.
    func startScan() {
        scanTask?.cancel()
        scanResults.beginScan()
        let stream = scanner.scan()
        scanTask = Task { [weak self] in
            for await event in stream {
                // 취소된 이전 스캔의 늦은 이벤트가 새 결과를 덮지 않게 한다.
                guard !Task.isCancelled else { break }
                self?.scanResults.apply(event)
            }
            guard let self, !Task.isCancelled else { return }
            self.lastScanDate = Date()
            self.scanTask = nil
            self.refreshDiskSpace()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanResults.markUnfinishedCancelled()
    }

    /// 스캔이 끝날 때까지 기다린다(테스트용).
    func waitForScan() async {
        await scanTask?.value
    }
}

/// 실행 인자로 결정되는 실행 환경. `-UITestMode YES`이면 실제 시스템 대신 고정값을 쓴다.
struct LaunchConfiguration: Sendable {
    static let uiTestModeKey = "UITestMode"
    static let openWindowKey = "UITestOpenWindow"
    /// UI 테스트에서 쓰는 고정 여유 공간(16.2GB).
    static let uiTestAvailableBytes: Int64 = 16_200_000_000

    static let xcodeRunningKey = "UITestXcodeRunning"
    static let cleanupFailureKey = "UITestCleanupFailure"
    static let simctlScenarioKey = "UITestSimctl"
    static let memoryScenarioKey = "UITestMemory"
    static let alertClickKey = "UITestAlertClick"

    let isUITest: Bool
    /// UI 테스트에서 시작 시 열 창: "scanner" 또는 "settings".
    let windowToOpen: String?
    /// UI 테스트: Xcode가 실행 중인 것처럼 한다.
    var simulatesXcodeRunning = false
    /// UI 테스트: 정리 중 일부 항목이 실패하게 한다.
    var simulatesCleanupFailure = false
    /// UI 테스트: 가짜 simctl 상황("missing" 도구 없음, "deleteFails" 삭제 실패). nil이면 정상.
    var simctlScenario: String?
    /// UI 테스트: 가짜 메모리 상황("critical" 위험). nil이면 정상.
    var memoryScenario: String?
    /// UI 테스트: 시작 시 이 대상들(쉼표 구분)이 적힌 여유 공간 알림을 누른 것처럼 한다.
    var alertClickTargetIDs: [String]?

    /// 백그라운드 스캔·알림·로그인 항목 같은 실제 시스템 작업을 할지. UI 테스트에서는 하지 않는다.
    var runsBackgroundWork: Bool { !isUITest }

    static func current(_ defaults: UserDefaults = .standard) -> LaunchConfiguration {
        let isUITest = defaults.bool(forKey: uiTestModeKey)
        return LaunchConfiguration(
            isUITest: isUITest,
            windowToOpen: isUITest ? defaults.string(forKey: openWindowKey) : nil,
            simulatesXcodeRunning: isUITest && defaults.bool(forKey: xcodeRunningKey),
            simulatesCleanupFailure: isUITest && defaults.bool(forKey: cleanupFailureKey),
            simctlScenario: isUITest ? defaults.string(forKey: simctlScenarioKey) : nil,
            memoryScenario: isUITest ? defaults.string(forKey: memoryScenarioKey) : nil,
            alertClickTargetIDs: isUITest
                ? defaults.string(forKey: alertClickKey)?.split(separator: ",").map(String.init) : nil
        )
    }

    @MainActor
    func makeAppState() -> AppState {
        if isUITest {
            // 실제 디스크·명령·휴지통·이력 파일을 건드리지 않는 가짜를 쓴다.
            return AppState(
                diskSpace: FixedDiskSpaceProvider(
                    bytes: Self.uiTestAvailableBytes, total: UITestFixtures.diskTotalBytes
                ),
                scanner: JunkScanner(targets: UITestFixtures.targets, environment: UITestFixtures.environment),
                cleanup: CleanupServices(
                    cleaner: UITestFixtures.FakeCleaner(failsTargetID: simulatesCleanupFailure ? "homebrewCache" : nil),
                    history: InMemoryHistoryStore(),
                    xcode: FixedXcodeChecker(isRunning: simulatesXcodeRunning)
                ),
                simulators: UITestFixtures.FakeSimulatorManager(scenario: simctlScenario),
                monitor: UITestFixtures.monitorServices(memoryScenario: memoryScenario),
                settings: .ephemeral()
            )
        }
        let environment = ScanEnvironment.live()
        return AppState(
            diskSpace: VolumeDiskSpaceProvider(),
            scanner: JunkScanner(targets: BuiltinTargets.all, environment: environment),
            cleanup: CleanupServices(
                cleaner: Cleaner(environment: environment, trash: SystemTrash()),
                history: FileHistoryStore.live(),
                xcode: SystemXcodeChecker()
            ),
            simulators: SimctlClient(shell: environment.shell, xcrunURL: environment.xcrunURL),
            monitor: .live(),
            settings: AppSettings(defaults: .standard)
        )
    }
}

/// 정리에 쓰는 서비스 묶음.
struct CleanupServices: Sendable {
    let cleaner: any Cleaning
    let history: any HistoryStoring
    let xcode: any XcodeRunningChecking
}
