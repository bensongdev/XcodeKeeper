import Foundation

/// 대상 정의가 항목을 찾을 때 쓰는 환경. 테스트에서는 임시 홈과 가짜 셸을 넣는다.
struct ScanEnvironment: Sendable {
    let home: URL
    let sizes: SizeCalculator
    let shell: any ShellRunning
    /// `xcrun` 위치(macOS 기본 경로).
    var xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    /// Homebrew 설치 후보 경로(Apple Silicon 우선).
    var brewCandidates = [URL(fileURLWithPath: "/opt/homebrew/bin/brew"), URL(fileURLWithPath: "/usr/local/bin/brew")]

    static func live() -> ScanEnvironment {
        ScanEnvironment(
            home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
            sizes: SizeCalculator(),
            shell: ShellRunner()
        )
    }

    func url(_ relativePath: String) -> URL {
        home.appending(path: relativePath, directoryHint: .isDirectory)
    }

    /// 폴더의 바로 아래 항목들을 용량과 함께 돌려준다. 폴더가 없으면 빈 배열.
    /// 숨김 파일(`.DS_Store` 등)은 제외한다.
    func childItems(of directory: URL, name: (URL) -> String = { $0.lastPathComponent }) throws -> [ScanItem] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            )
        } catch {
            throw ScanFailure.permissionDenied
        }
        return try children.map { try item(at: $0, name: name($0)) }
    }

    /// 경로 하나를 항목으로 돌려준다. 없으면 빈 배열.
    func singleItem(at url: URL, name: String? = nil) throws -> [ScanItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return [try item(at: url, name: name ?? url.lastPathComponent)]
    }

    private func item(at url: URL, name: String) throws -> ScanItem {
        try Task.checkCancellation()
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return ScanItem(url: url, name: name, bytes: try sizes.allocatedSize(of: url), lastModified: modified)
    }

    /// 외부 명령을 실행하고 stdout을 돌려준다. 실패하면 stderr를 담은 `commandFailed`.
    func output(of executable: URL, _ arguments: [String]) async throws -> String {
        let result: ShellResult
        do {
            result = try await shell.run(executable, arguments: arguments)
        } catch let error as ShellError {
            throw ScanFailure.commandFailed(String(describing: error))
        }
        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScanFailure.commandFailed(message.isEmpty ? "exit \(result.exitCode)" : message)
        }
        return result.stdout
    }
}
