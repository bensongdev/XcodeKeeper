import AppKit
import Foundation

/// 휴지통 이동을 추상화한다. 실제 구현은 `FileManager.trashItem`만 쓰고, 테스트는 가짜를 쓴다.
protocol Trashing: Sendable {
    func moveToTrash(_ url: URL) throws
}

/// 실제 휴지통. 영구 삭제는 하지 않는다.
struct SystemTrash: Trashing {
    func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

/// 정리 실행. UI 테스트에서는 가짜 정리기를 쓴다.
protocol Cleaning: Sendable {
    func clean(_ selections: [CleanupSelection]) async -> CleanupOutcome
}

/// 이 앱에서 파일을 정리하는 유일한 곳.
/// 휴지통 대상은 `PathGuard` 검증 후 `Trashing`으로 옮기고, 명령 대상은 `xcrun`으로 실행한다.
struct Cleaner: Cleaning {
    let environment: ScanEnvironment
    let trash: any Trashing

    func clean(_ selections: [CleanupSelection]) async -> CleanupOutcome {
        var outcome = CleanupOutcome()
        for selection in selections where !selection.items.isEmpty {
            if Task.isCancelled {
                outcome.wasCancelled = true
                break
            }
            switch selection.target.method {
            case .trash:
                trashItems(of: selection, into: &outcome)
            case .command(let arguments):
                await runCommand(arguments, for: selection, into: &outcome)
            case .none:
                continue
            }
        }
        if Task.isCancelled { outcome.wasCancelled = true }
        return outcome
    }

    private func trashItems(of selection: CleanupSelection, into outcome: inout CleanupOutcome) {
        let target = selection.target
        let roots = target.allowedRoots(environment)
        for item in selection.items {
            if Task.isCancelled { return }
            guard let url = item.url else {
                outcome.failures.append(failure(target, item, String(localized: "경로가 없는 항목")))
                continue
            }
            do {
                try PathGuard.validate(url, allowedRoots: roots, home: environment.home)
                try trash.moveToTrash(url)
                outcome.cleaned.append(cleaned(target, item))
            } catch let rejection as PathGuard.Rejection {
                outcome.failures.append(failure(target, item, Self.reason(for: rejection)))
            } catch {
                outcome.failures.append(failure(target, item, error.localizedDescription))
            }
        }
    }

    private func runCommand(
        _ arguments: [String], for selection: CleanupSelection, into outcome: inout CleanupOutcome
    ) async {
        let target = selection.target
        do {
            let result = try await environment.shell.run(environment.xcrunURL, arguments: arguments)
            if result.exitCode == 0 {
                outcome.cleaned += selection.items.map { cleaned(target, $0) }
            } else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = stderr.isEmpty ? "exit \(result.exitCode)" : stderr
                outcome.failures += selection.items.map { failure(target, $0, reason) }
            }
        } catch is CancellationError {
            outcome.wasCancelled = true
        } catch {
            outcome.failures += selection.items.map { failure(target, $0, String(describing: error)) }
        }
    }

    private func cleaned(_ target: CleanupTarget, _ item: ScanItem) -> CleanedItem {
        CleanedItem(targetID: target.id, targetTitle: target.title, itemName: item.name, bytes: item.bytes)
    }

    private func failure(_ target: CleanupTarget, _ item: ScanItem, _ reason: String) -> CleanupFailure {
        CleanupFailure(targetTitle: target.title, itemName: item.name, reason: reason)
    }

    static func reason(for rejection: PathGuard.Rejection) -> String {
        switch rejection {
        case .missing: String(localized: "이미 없음")
        case .notFileURL, .containsParentReference, .outsideAllowedRoots, .unsafeRoot:
            String(localized: "허용되지 않은 경로")
        }
    }
}

/// 실제 Xcode 실행 여부.
struct SystemXcodeChecker: XcodeRunningChecking {
    static let bundleIdentifier = "com.apple.dt.Xcode"

    func isXcodeRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }
}

struct FixedXcodeChecker: XcodeRunningChecking {
    let isRunning: Bool

    func isXcodeRunning() -> Bool { isRunning }
}
