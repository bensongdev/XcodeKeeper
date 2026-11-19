import Foundation

/// 정리 가능한 대상 요약(팝오버 "정리 가능", 알림 본문).
struct CleanableSummary: Sendable, Equatable {
    let targetID: String
    let title: String
    let bytes: Int64
}

extension ScanResults {
    /// 스캔이 끝난 정리 가능한 대상을 합계 용량 내림차순으로. 0바이트 대상은 뺀다.
    func topCleanable(limit: Int) -> [CleanableSummary] {
        let summaries = targets.compactMap { target -> CleanableSummary? in
            guard target.isSelectable, case .done = status(of: target.id) else { return nil }
            let bytes = totalBytes(of: target.id)
            return bytes > 0 ? CleanableSummary(targetID: target.id, title: target.title, bytes: bytes) : nil
        }
        return Array(summaries.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}

/// 알림 내용. `targetIDs`는 알림을 눌렀을 때 선택할 대상.
struct AlertContent: Sendable, Equatable {
    let title: String
    let body: String
    let targetIDs: [String]
}

/// 여유 공간 알림 규칙. 뷰·시스템과 분리된 순수 함수라 단위 테스트한다.
enum FreeSpaceAlert {
    static let cooldown: TimeInterval = 24 * 60 * 60
    static let topCount = 2

    /// 여유 공간이 기준 미만이고 마지막 알림에서 24시간이 지났으면 보낸다.
    static func shouldNotify(availableBytes: Int64?, thresholdBytes: Int64, lastSentAt: Date?, now: Date) -> Bool {
        guard let available = availableBytes, available < thresholdBytes else { return false }
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) >= cooldown
    }

    static func content(availableBytes: Int64, top: [CleanableSummary]) -> AlertContent {
        let title = String(localized: "여유 공간이 \(ByteFormat.gigabytes(availableBytes)) 남았습니다")
        let items = top.prefix(topCount)
        let list = items.map { "\($0.title) \(ByteFormat.size($0.bytes))" }.joined(separator: ", ")
        let body = items.isEmpty
            ? String(localized: "스캐너에서 정리할 항목을 확인하세요")
            : String(localized: "정리 가능: \(list)")
        return AlertContent(title: title, body: body, targetIDs: items.map(\.targetID))
    }

    /// 팝오버 문구: 기준까지 모자란 양(반올림 GB). 기준 이상이면 nil.
    static func shortageText(availableBytes: Int64?, thresholdBytes: Int64) -> String? {
        guard let available = availableBytes, available < thresholdBytes else { return nil }
        let gigabytes = Int64((Double(thresholdBytes - available) / ByteFormat.bytesPerGB).rounded())
        return String(localized: "업데이트까지 약 \(max(gigabytes, 1))GB 부족")
    }
}

/// 백그라운드 스캔 건너뛰기 조건.
struct PowerState: Sendable, Equatable {
    var isLowPowerMode: Bool
    /// 배터리 잔량(%). 배터리가 없는 Mac은 nil.
    var batteryPercent: Int?

    static let batteryThreshold = 20

    var shouldSkipBackgroundWork: Bool {
        isLowPowerMode || (batteryPercent.map { $0 <= Self.batteryThreshold } ?? false)
    }
}
