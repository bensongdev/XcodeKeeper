import Foundation

/// 모니터·알림·백그라운드 작업에 쓰는 서비스 묶음.
struct MonitorServices: Sendable {
    var system: any SystemMonitoring
    var notifier: any Notifying
    var power: any PowerStateProviding
    var loginItem: any LoginItemControlling

    /// 시스템을 건드리지 않는 고정값 묶음(단위 테스트 기본값).
    static func fixed(
        memory: MemorySnapshot? = nil, processes: [ProcessMemory] = [],
        notifier: any Notifying = RecordingNotifier(), power: PowerState = PowerState(isLowPowerMode: false),
        loginItem: any LoginItemControlling = FakeLoginItem()
    ) -> MonitorServices {
        MonitorServices(
            system: FixedSystemMonitor(memory: memory, processes: processes), notifier: notifier,
            power: FixedPowerState(state: power), loginItem: loginItem
        )
    }

    static func live() -> MonitorServices {
        MonitorServices(
            system: LiveSystemMonitor(), notifier: UserNotifier(), power: SystemPowerState(),
            loginItem: SystemLoginItem()
        )
    }
}

/// 백그라운드 스캔 결과(테스트에서 확인).
enum BackgroundScanOutcome: Sendable, Equatable {
    case disabled
    case skippedPower
    /// 스캔·정리 중이거나 스캐너 창이 열려 있어 사용자의 선택을 덮지 않으려고 건너뜀.
    case busy
    case scanned(alertSent: Bool)
}

extension AppState {
    static let monitorInterval: Duration = .seconds(5)
    /// 팝오버가 닫혀 있을 때 여유 공간은 이 간격으로만 읽는다.
    /// `volumeAvailableCapacityForImportantUsage`는 호출마다 CPU 약 6ms가 들어 5초마다 읽으면 유휴 CPU 기준을 넘는다.
    static let closedDiskInterval: TimeInterval = 60
    static let backgroundScanInterval: TimeInterval = 6 * 60 * 60
    static let backgroundScanTolerance: TimeInterval = 60 * 60
    nonisolated static let processCount = 5
    static let popoverTopCount = 3

    // MARK: - 모니터

    /// 메뉴바 아이콘 색.
    var statusLevel: StatusLevel {
        StatusLevel.evaluate(
            availableBytes: availableBytes, memory: memory,
            freeSpaceThresholdBytes: settings.freeSpaceThresholdBytes, swapThresholdBytes: settings.swapThresholdBytes
        )
    }

    /// 5초마다 메모리·스왑·여유 공간을 읽는다. 상위 프로세스는 팝오버가 열려 있을 때만 읽는다.
    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshMonitor()
                try? await Task.sleep(for: Self.monitorInterval)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func refreshMonitor() async {
        let system = monitor.system
        let includeProcesses = isPopoverVisible
        let (snapshot, processes) = await Task.detached(priority: .utility) {
            (system.snapshot(), includeProcesses ? system.topProcesses(limit: Self.processCount) : nil)
        }.value
        if let processes { topProcesses = processes }
        if isPopoverVisible {
            memory = snapshot
            refreshDiskSpace()
            return
        }
        // 팝오버가 닫혀 있으면 아이콘 색이나 메뉴바 숫자가 바뀔 때만 상태를 바꾼다.
        // @Observable은 같은 값을 넣어도 다시 그리므로, 5초마다 메뉴바 라벨을 다시 그리는 비용(유휴 CPU)을 줄인다.
        let now = Date()
        let readsDisk = lastDiskReadAt.map { now.timeIntervalSince($0) >= Self.closedDiskInterval } ?? true
        if readsDisk { lastDiskReadAt = now }
        let available = readsDisk ? readAvailableBytes() : availableBytes
        let newLevel = StatusLevel.evaluate(
            availableBytes: available, memory: snapshot,
            freeSpaceThresholdBytes: settings.freeSpaceThresholdBytes, swapThresholdBytes: settings.swapThresholdBytes
        )
        if newLevel != statusLevel || memory == nil {
            memory = snapshot
        }
        if newLevel != statusLevel || ByteFormat.menuBarLabel(available) != ByteFormat.menuBarLabel(availableBytes) {
            refreshDiskSpace()
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible { Task { await refreshMonitor() } }
    }

    // MARK: - 백그라운드 스캔과 알림

    /// 백그라운드 스캔을 한 번 한다. 끝나면 여유 공간 알림을 판단한다.
    @discardableResult
    func runBackgroundScan(now: Date = Date()) async -> BackgroundScanOutcome {
        guard settings.backgroundScanEnabled else { return .disabled }
        if monitor.power.current().shouldSkipBackgroundWork { return .skippedPower }
        guard !isScanning, !isCleanupInProgress, !isScannerWindowVisible else { return .busy }
        startScan()
        await waitForScan()
        return .scanned(alertSent: await evaluateFreeSpaceAlert(now: now))
    }

    /// 확인 창이나 정리 중이면 true. 결과 배너(.finished)는 진행 중이 아니다.
    private var isCleanupInProgress: Bool {
        switch cleanupPhase {
        case .confirming, .cleaning: true
        case .idle, .finished: false
        }
    }

    /// 여유 공간이 기준 미만이고 24시간 안에 보낸 적이 없으면 알림을 보낸다.
    func evaluateFreeSpaceAlert(now: Date = Date()) async -> Bool {
        refreshDiskSpace()
        guard let available = availableBytes, FreeSpaceAlert.shouldNotify(
            availableBytes: available, thresholdBytes: settings.freeSpaceThresholdBytes,
            lastSentAt: settings.lastFreeSpaceAlertAt, now: now
        ) else { return false }
        let content = FreeSpaceAlert.content(
            availableBytes: available, top: scanResults.topCleanable(limit: FreeSpaceAlert.topCount)
        )
        // 권한이 없거나 실패하면 조용히 넘어가고, 다음 스캔 때 다시 판단한다.
        guard await monitor.notifier.send(content) else { return false }
        settings.lastFreeSpaceAlertAt = now
        return true
    }

    /// 알림을 눌렀을 때: 스캐너 창을 "개발 찌꺼기"로 열고 알림에 적힌 대상의 항목을 모두 선택한다.
    func handleAlertClick(targetIDs: [String]) async {
        selectedSection = .junk
        scannerWindowRequest += 1
        let scanned = targetIDs.allSatisfy { if case .done = scanResults.status(of: $0) { true } else { false } }
        if !scanned || isScanning {
            if !isScanning { startScan() }
            await waitForScan()
        }
        for id in targetIDs {
            scanResults.setAllSelected(true, targetID: id)
        }
    }

    /// 실행 직후 한 번, 이후 6시간마다 백그라운드 스캔을 한다. 저전력·배터리 조건은 매번 확인한다.
    func startBackgroundScans() {
        guard backgroundScheduler == nil else { return }
        Task { await runBackgroundScan() }
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.bensongdev.XcodeKeeper.backgroundScan")
        scheduler.repeats = true
        scheduler.interval = Self.backgroundScanInterval
        scheduler.tolerance = Self.backgroundScanTolerance
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            let done = SendableCompletion(completion)
            Task { @MainActor in
                await self?.runBackgroundScan()
                done.call(.finished)
            }
        }
        backgroundScheduler = scheduler
    }

    // MARK: - 로그인 항목

    func refreshLoginItemStatus() {
        loginItemStatus = monitor.loginItem.status()
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        loginItemError = nil
        do {
            try monitor.loginItem.setEnabled(enabled)
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }
}

/// `NSBackgroundActivityScheduler`의 완료 처리기를 메인 액터로 넘기기 위한 상자. 한 번만 부른다.
private struct SendableCompletion: @unchecked Sendable {
    let completion: (NSBackgroundActivityScheduler.Result) -> Void

    init(_ completion: @escaping (NSBackgroundActivityScheduler.Result) -> Void) {
        self.completion = completion
    }

    func call(_ result: NSBackgroundActivityScheduler.Result) { completion(result) }
}
