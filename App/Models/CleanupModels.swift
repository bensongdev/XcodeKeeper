import Foundation

/// 정리할 대상과 그 대상에서 고른 항목.
struct CleanupSelection: Sendable {
    let target: CleanupTarget
    let items: [ScanItem]
}

/// 정리한 항목 하나(이력에 저장한다).
struct CleanedItem: Codable, Sendable, Equatable {
    let targetID: String
    let targetTitle: String
    let itemName: String
    let bytes: Int64
}

/// 정리하지 못한 항목과 이유.
struct CleanupFailure: Sendable, Equatable {
    let targetTitle: String
    let itemName: String
    let reason: String
}

/// 정리 한 번의 결과.
struct CleanupOutcome: Sendable, Equatable {
    var cleaned: [CleanedItem] = []
    var failures: [CleanupFailure] = []
    var wasCancelled = false

    var freedBytes: Int64 { cleaned.reduce(0) { $0 + $1.bytes } }
}

/// 정리 이력 한 건.
struct CleanupRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let items: [CleanedItem]

    var freedBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

/// 이력 규칙: 최신순, 최대 100건.
enum CleanupHistory {
    static let limit = 100

    static func appending(_ record: CleanupRecord, to records: [CleanupRecord]) -> [CleanupRecord] {
        Array(([record] + records).prefix(limit))
    }

    static func totalFreed(_ records: [CleanupRecord]) -> Int64 {
        records.reduce(0) { $0 + $1.freedBytes }
    }
}

/// 정리 진행 단계.
enum CleanupPhase: Sendable, Equatable {
    case idle
    /// 확인 창을 띄운 상태. Xcode 실행 경고 여부를 담는다.
    case confirming(xcodeRunningWarning: Bool)
    case cleaning
    case finished(CleanupOutcome)
}

/// Xcode 실행 여부 확인. UI 테스트에서는 고정값을 쓴다.
protocol XcodeRunningChecking: Sendable {
    func isXcodeRunning() -> Bool
}
