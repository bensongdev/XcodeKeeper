import Foundation

/// 스캔 진행 이벤트. 대상마다 `started` 뒤에 `finished` 또는 `failed`가 온다.
enum ScanEvent: Sendable, Equatable {
    case started(targetID: String)
    case finished(targetID: String, items: [ScanItem])
    case failed(targetID: String, failure: ScanFailure)
}

/// 대상들을 병렬로 스캔해 끝나는 대로 이벤트를 낸다.
/// 스트림 소비를 멈추거나 소비 Task를 취소하면 남은 스캔도 취소된다.
struct JunkScanner: Sendable {
    let targets: [CleanupTarget]
    let environment: ScanEnvironment

    func scan() -> AsyncStream<ScanEvent> {
        let targets = targets
        let environment = environment
        return AsyncStream { continuation in
            let task = Task(priority: .utility) {
                await withTaskGroup(of: Void.self) { group in
                    for target in targets {
                        group.addTask(priority: .utility) {
                            continuation.yield(.started(targetID: target.id))
                            if let event = await Self.scan(target, environment) {
                                continuation.yield(event)
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 대상 하나를 스캔한다. 취소되면 nil.
    private static func scan(_ target: CleanupTarget, _ environment: ScanEnvironment) async -> ScanEvent? {
        do {
            let items = try await target.locate(environment)
            try Task.checkCancellation()
            return .finished(targetID: target.id, items: items.sorted { $0.bytes > $1.bytes })
        } catch is CancellationError {
            return nil
        } catch let failure as ScanFailure {
            return .failed(targetID: target.id, failure: failure)
        } catch {
            return Task.isCancelled ? nil : .failed(targetID: target.id, failure: .other(error.localizedDescription))
        }
    }
}
