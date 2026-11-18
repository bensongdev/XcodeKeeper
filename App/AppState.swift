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
    private var scanTask: Task<Void, Never>?

    var selectedSection: ScannerSection? = .junk
    private(set) var availableBytes: Int64?
    var scanResults: ScanResults
    private(set) var lastScanDate: Date?

    init(diskSpace: any DiskSpaceProviding, scanner: JunkScanner) {
        self.diskSpace = diskSpace
        self.scanner = scanner
        self.scanResults = ScanResults(targets: scanner.targets)
        refreshDiskSpace()
    }

    var isScanning: Bool { scanTask != nil }

    func refreshDiskSpace() {
        availableBytes = diskSpace.availableBytes()
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

    let isUITest: Bool
    /// UI 테스트에서 시작 시 열 창: "scanner" 또는 "settings".
    let windowToOpen: String?

    static func current(_ defaults: UserDefaults = .standard) -> LaunchConfiguration {
        let isUITest = defaults.bool(forKey: uiTestModeKey)
        return LaunchConfiguration(
            isUITest: isUITest,
            windowToOpen: isUITest ? defaults.string(forKey: openWindowKey) : nil
        )
    }

    @MainActor
    func makeAppState() -> AppState {
        if isUITest {
            // 실제 디스크나 명령을 건드리지 않는 가짜 대상을 쓴다.
            return AppState(
                diskSpace: FixedDiskSpaceProvider(bytes: Self.uiTestAvailableBytes),
                scanner: JunkScanner(targets: UITestFixtures.targets, environment: UITestFixtures.environment)
            )
        }
        return AppState(
            diskSpace: VolumeDiskSpaceProvider(),
            scanner: JunkScanner(targets: BuiltinTargets.all, environment: .live())
        )
    }
}
