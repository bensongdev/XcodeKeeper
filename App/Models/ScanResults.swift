import Foundation

/// 대상 하나의 스캔 상태.
enum TargetScanStatus: Sendable, Equatable {
    case notScanned
    case scanning
    case done([ScanItem])
    case failed(ScanFailure)
    case cancelled

    var items: [ScanItem] {
        if case .done(let items) = self { return items }
        return []
    }
}

/// 선택 단위: 대상 id + 항목 id.
struct ItemKey: Hashable, Sendable {
    let targetID: String
    let itemID: String
}

/// 스캔 결과와 선택 상태. 뷰와 분리된 순수 값 타입이라 단위 테스트한다.
struct ScanResults: Sendable, Equatable {
    let targets: [CleanupTarget]
    private(set) var statuses: [String: TargetScanStatus] = [:]
    private(set) var selection: Set<ItemKey> = []

    init(targets: [CleanupTarget]) {
        self.targets = targets
    }

    static func == (lhs: ScanResults, rhs: ScanResults) -> Bool {
        lhs.targets.map(\.id) == rhs.targets.map(\.id) && lhs.statuses == rhs.statuses
            && lhs.selection == rhs.selection
    }

    func status(of targetID: String) -> TargetScanStatus {
        statuses[targetID] ?? .notScanned
    }

    var isScanning: Bool {
        statuses.values.contains(.scanning)
    }

    /// 화면에 보일 대상. "있을 때만 표시" 대상은 항목을 찾았거나 실패했을 때만 보인다.
    var visibleTargets: [CleanupTarget] {
        targets.filter { target in
            guard target.hideWhenEmpty else { return true }
            switch status(of: target.id) {
            case .done(let items): return !items.isEmpty
            case .failed: return true
            case .notScanned, .scanning, .cancelled: return false
            }
        }
    }

    // MARK: - 스캔 진행

    mutating func beginScan() {
        selection = []
        for target in targets { statuses[target.id] = .scanning }
    }

    mutating func apply(_ event: ScanEvent) {
        switch event {
        case .started(let id):
            statuses[id] = .scanning
        case .finished(let id, let items):
            statuses[id] = .done(items)
            if let target = target(id), target.isSelectedByDefault {
                for item in items { selection.insert(ItemKey(targetID: id, itemID: item.id)) }
            }
        case .failed(let id, let failure):
            statuses[id] = .failed(failure)
        }
    }

    /// 끝나지 않은 대상을 "취소됨"으로 바꾼다.
    mutating func markUnfinishedCancelled() {
        for (id, status) in statuses where status == .scanning { statuses[id] = .cancelled }
    }

    // MARK: - 합계

    func totalBytes(of targetID: String) -> Int64 {
        status(of: targetID).items.reduce(0) { $0 + $1.bytes }
    }

    /// 선택한 항목의 합계 용량.
    var selectedBytes: Int64 {
        targets.reduce(0) { sum, target in
            sum + status(of: target.id).items
                .filter { selection.contains(ItemKey(targetID: target.id, itemID: $0.id)) }
                .reduce(0) { $0 + $1.bytes }
        }
    }

    var selectedItemCount: Int { selection.count }

    // MARK: - 선택

    func isSelected(_ targetID: String, _ itemID: String) -> Bool {
        selection.contains(ItemKey(targetID: targetID, itemID: itemID))
    }

    /// 항목 하나의 선택을 바꾼다. 그룹 단위 대상이면 그룹 전체를 바꾼다.
    mutating func setSelected(_ selected: Bool, targetID: String, itemID: String) {
        guard let target = target(targetID), target.isSelectable else { return }
        if target.selectsAsGroup {
            setAllSelected(selected, targetID: targetID)
            return
        }
        let key = ItemKey(targetID: targetID, itemID: itemID)
        if selected { selection.insert(key) } else { selection.remove(key) }
    }

    mutating func setAllSelected(_ selected: Bool, targetID: String) {
        guard let target = target(targetID), target.isSelectable else { return }
        for item in status(of: targetID).items {
            let key = ItemKey(targetID: targetID, itemID: item.id)
            if selected { selection.insert(key) } else { selection.remove(key) }
        }
    }

    private func target(_ id: String) -> CleanupTarget? {
        targets.first { $0.id == id }
    }
}

/// 그룹 행 오른쪽에 보여 줄 상태 문구.
enum TargetStatusText {
    static func text(for status: TargetScanStatus, safety: Safety) -> String {
        switch status {
        case .notScanned: "—"
        case .scanning: String(localized: "스캔 중")
        case .cancelled: String(localized: "취소됨")
        case .failed(let failure): failure.title
        case .done(let items) where safety == .infoOnly: String(localized: "\(items.count)개")
        case .done(let items) where items.isEmpty: String(localized: "없음")
        case .done(let items): ByteFormat.size(items.reduce(0) { $0 + $1.bytes })
        }
    }
}
