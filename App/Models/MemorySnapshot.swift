import Foundation

/// 메모리 압박 단계(`kern.memorystatus_vm_pressure_level`).
enum MemoryPressure: Sendable, Equatable {
    case normal
    case warning
    case critical

    /// sysctl 값: 1 정상, 2 경고, 4 위험. 모르는 값은 정상으로 본다.
    init(sysctlLevel: Int32?) {
        switch sysctlLevel {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    var title: String {
        switch self {
        case .normal: String(localized: "정상")
        case .warning: String(localized: "경고")
        case .critical: String(localized: "위험")
        }
    }
}

/// 한 시점의 메모리·스왑 상태.
struct MemorySnapshot: Sendable, Equatable {
    var totalBytes: Int64
    /// 앱 메모리 = 내부 페이지 − 비울 수 있는 페이지(활성 모니터와 같은 기준).
    var appBytes: Int64
    var wiredBytes: Int64
    var compressedBytes: Int64
    var swapUsedBytes: Int64
    var swapTotalBytes: Int64
    var pressure: MemoryPressure

    var usedBytes: Int64 { appBytes + wiredBytes + compressedBytes }

    /// `host_statistics64(HOST_VM_INFO64)`의 페이지 수.
    struct PageCounts: Sendable, Equatable {
        var internalPages: UInt64
        var purgeablePages: UInt64
        var wiredPages: UInt64
        var compressedPages: UInt64
    }

    /// 페이지 수에서 바이트로 바꾼다. purgeable이 internal보다 크면 0으로 둔다.
    static func make(
        totalBytes: UInt64, pageSize: UInt64, pages: PageCounts, swap: SwapUsage?, pressureLevel: Int32?
    ) -> MemorySnapshot {
        let appPages = pages.internalPages > pages.purgeablePages ? pages.internalPages - pages.purgeablePages : 0
        return MemorySnapshot(
            totalBytes: Int64(clamping: totalBytes),
            appBytes: Int64(clamping: appPages &* pageSize),
            wiredBytes: Int64(clamping: pages.wiredPages &* pageSize),
            compressedBytes: Int64(clamping: pages.compressedPages &* pageSize),
            swapUsedBytes: Int64(clamping: swap?.used ?? 0),
            swapTotalBytes: Int64(clamping: swap?.total ?? 0),
            pressure: MemoryPressure(sysctlLevel: pressureLevel)
        )
    }
}

/// `vm.swapusage`(`xsw_usage`)에서 읽은 값.
struct SwapUsage: Sendable, Equatable {
    var used: UInt64
    var total: UInt64
}

/// 프로세스별 메모리(`ri_phys_footprint`).
struct ProcessMemory: Sendable, Equatable, Identifiable {
    let pid: Int32
    let name: String
    let bytes: Int64

    var id: Int32 { pid }

    /// 메모리 내림차순 상위 `limit`개. 같으면 pid 오름차순으로 순서를 고정한다.
    static func top(_ processes: [ProcessMemory], limit: Int) -> [ProcessMemory] {
        Array(processes.filter { $0.bytes > 0 }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.pid < $1.pid }
            .prefix(limit))
    }
}

/// 메뉴바 아이콘 색 단계.
enum StatusLevel: Sendable, Equatable {
    case normal
    case warning
    case critical

    static let criticalFreeBytes: Int64 = 10_000_000_000

    /// 빨강: 여유 10GB 미만 또는 압박 "위험". 노랑: 여유가 알림 기준 미만 또는 스왑이 기준 초과.
    /// 읽지 못한 값(nil)은 판단에서 뺀다.
    static func evaluate(
        availableBytes: Int64?, memory: MemorySnapshot?, freeSpaceThresholdBytes: Int64, swapThresholdBytes: Int64
    ) -> StatusLevel {
        if let available = availableBytes, available < criticalFreeBytes { return .critical }
        if memory?.pressure == .critical { return .critical }
        if let available = availableBytes, available < freeSpaceThresholdBytes { return .warning }
        if let swap = memory?.swapUsedBytes, swap > swapThresholdBytes { return .warning }
        return .normal
    }
}
