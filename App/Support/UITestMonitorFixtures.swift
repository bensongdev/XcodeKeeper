import Foundation

/// UI 테스트·스냅샷용 고정 메모리 값과 프로세스 목록. 실제 시스템 값은 증거에 남기지 않는다.
extension UITestFixtures {
    /// 256GB SSD의 볼륨 크기.
    static let diskTotalBytes: Int64 = 245_107_195_904

    /// 8GB Mac, 압박 정상, 스왑 0.5GB.
    static let normalMemory = MemorySnapshot(
        totalBytes: 8_589_934_592, appBytes: 3_100_000_000, wiredBytes: 1_400_000_000,
        compressedBytes: 900_000_000, swapUsedBytes: 500_000_000, swapTotalBytes: 1_073_741_824, pressure: .normal
    )

    /// 압박 위험, 스왑 3.4GB.
    static let criticalMemory = MemorySnapshot(
        totalBytes: 8_589_934_592, appBytes: 4_600_000_000, wiredBytes: 1_600_000_000,
        compressedBytes: 1_700_000_000, swapUsedBytes: 3_400_000_000, swapTotalBytes: 4_294_967_296,
        pressure: .critical
    )

    static let processes: [ProcessMemory] = [
        ProcessMemory(pid: 101, name: "Xcode", bytes: 2_100_000_000),
        ProcessMemory(pid: 102, name: "Simulator", bytes: 900_000_000),
        ProcessMemory(pid: 103, name: "Safari", bytes: 640_000_000),
        ProcessMemory(pid: 104, name: "swift-frontend", bytes: 520_000_000),
        ProcessMemory(pid: 105, name: "WindowServer", bytes: 230_000_000),
        ProcessMemory(pid: 106, name: "XcodeKeeper", bytes: 31_000_000)
    ]

    /// `-UITestMemory critical`이면 위험 상태.
    static func monitorServices(memoryScenario: String?) -> MonitorServices {
        .fixed(
            memory: memoryScenario == "critical" ? criticalMemory : normalMemory,
            processes: processes
        )
    }
}
