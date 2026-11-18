import AppKit
import Foundation

/// 정리 흐름: 확인 → 정리 → 이력 저장 → 다시 스캔.
extension AppState {
    var isCleaning: Bool { cleanupPhase == .cleaning }

    var canStartCleanup: Bool {
        scanResults.selectedItemCount > 0 && !isScanning && !isCleaning
    }

    /// 선택된 항목을 대상별로 묶는다(대상 순서 유지).
    var cleanupSelections: [CleanupSelection] {
        scanResults.targets.compactMap { target in
            let items = scanResults.status(of: target.id).items.filter { scanResults.isSelected(target.id, $0.id) }
            return items.isEmpty ? nil : CleanupSelection(target: target, items: items)
        }
    }

    /// 확인 창에 보여 줄 정보: DerivedData가 선택되어 있고 Xcode가 실행 중이면 경고한다.
    func requestCleanup() {
        guard canStartCleanup else { return }
        let includesDerivedData = cleanupSelections.contains { $0.target.id == BuiltinTargets.derivedData.id }
        cleanupPhase = .confirming(xcodeRunningWarning: includesDerivedData && cleanup.xcode.isXcodeRunning())
    }

    /// 선택에 명령(휴지통을 거치지 않음)으로 정리하는 대상이 있는가.
    var selectionIncludesCommandTarget: Bool {
        cleanupSelections.contains { $0.target.selectsAsGroup }
    }

    func dismissCleanupConfirmation() {
        if case .confirming = cleanupPhase { cleanupPhase = .idle }
    }

    func confirmCleanup() {
        guard case .confirming = cleanupPhase else { return }
        let selections = cleanupSelections
        let cleaner = cleanup.cleaner
        cleanupPhase = .cleaning
        cleanupTask = Task { [weak self] in
            // 파일 이동이 메인 스레드를 막지 않게 분리하고, 바깥 Task 취소를 안쪽 작업에 전달한다.
            let work = Task.detached(priority: .utility) { await cleaner.clean(selections) }
            let outcome = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            self?.finishCleanup(outcome)
        }
    }

    func cancelCleanup() {
        cleanupTask?.cancel()
    }

    func dismissCleanupResult() {
        if case .finished = cleanupPhase { cleanupPhase = .idle }
    }

    /// 휴지통을 Finder에서 연다. 비우기는 사용자가 Finder에서 직접 한다.
    func openTrash() {
        let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".Trash")
        NSWorkspace.shared.open(trash)
    }

    private func finishCleanup(_ outcome: CleanupOutcome) {
        cleanupTask = nil
        cleanupPhase = .finished(outcome)
        if !outcome.cleaned.isEmpty {
            let record = CleanupRecord(id: UUID(), date: Date(), items: outcome.cleaned)
            history = CleanupHistory.appending(record, to: history)
            try? cleanup.history.save(history)
        }
        startScan()
    }
}
