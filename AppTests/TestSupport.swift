import Foundation
import XCTest
@testable import XcodeKeeper

/// 테스트마다 만드는 임시 폴더. 실제 ~/Library는 건드리지 않는다.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "XcodeKeeperTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        // 권한을 막아 둔 하위 폴더도 지울 수 있게 되돌린 뒤 삭제한다(테스트가 만든 임시 폴더만).
        if let enumerator = FileManager.default.enumerator(atPath: url.path) {
            for case let path as String in enumerator {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: url.appending(path: path).path
                )
            }
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// `relativePath` 위치에 `bytes` 크기의 파일을 만든다(중간 폴더 포함).
    @discardableResult
    func makeFile(_ relativePath: String, bytes: Int, modified: Date? = nil) throws -> URL {
        let file = url.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0x61, count: bytes).write(to: file)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        }
        return file
    }

    @discardableResult
    func makeDirectory(_ relativePath: String) throws -> URL {
        let directory = url.appending(path: relativePath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// 외부 명령을 실행하지 않는 가짜 셸. 호출을 기록하고 정해진 결과를 돌려준다.
final class FakeShell: ShellRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let handler: @Sendable (URL, [String]) throws -> ShellResult

    init(handler: @escaping @Sendable (URL, [String]) throws -> ShellResult) {
        self.handler = handler
    }

    convenience init(stdout: String, exitCode: Int32 = 0, stderr: String = "") {
        self.init { _, _ in ShellResult(exitCode: exitCode, stdout: stdout, stderr: stderr) }
    }

    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async throws -> ShellResult {
        lock.withLock { recorded.append([executable.lastPathComponent] + arguments) }
        return try handler(executable, arguments)
    }
}

/// 테스트용 대상. 정해진 항목을 (지연 후) 돌려주거나 실패한다.
func makeTarget(
    _ id: String,
    safety: Safety = .safe,
    method: CleanupMethod = .trash,
    hideWhenEmpty: Bool = false,
    delay: Duration? = nil,
    result: Result<[ScanItem], ScanFailure> = .success([])
) -> CleanupTarget {
    CleanupTarget(
        id: id, title: id, explanation: "설명", safety: safety, method: method, hideWhenEmpty: hideWhenEmpty,
        locate: { _ in
            if let delay { try await Task.sleep(for: delay) }
            return try result.get()
        }
    )
}

func makeItem(_ id: String, bytes: Int64) -> ScanItem {
    ScanItem(url: URL(fileURLWithPath: "/tmp/\(id)"), name: id, bytes: bytes, lastModified: nil)
}

func makeEnvironment(home: URL, shell: any ShellRunning = FakeShell(stdout: "")) -> ScanEnvironment {
    ScanEnvironment(home: home, sizes: SizeCalculator(), shell: shell)
}

func loadFixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
    let bundle = Bundle(for: TemporaryDirectory.self)
    let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), file: file, line: line)
    return try String(contentsOf: url, encoding: .utf8)
}

func makeScanner(_ targets: [CleanupTarget]) -> JunkScanner {
    JunkScanner(targets: targets, environment: makeEnvironment(home: FileManager.default.temporaryDirectory))
}

/// 실제 휴지통 대신 테스트 임시 폴더로 옮기는 가짜 휴지통. 옮긴 경로를 기록한다.
final class FakeTrash: Trashing, @unchecked Sendable {
    private let lock = NSLock()
    private var moved: [URL] = []
    let directory: URL
    /// 이 이름의 항목은 이동에 실패한다.
    var failingNames: Set<String> = []

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var movedURLs: [URL] { lock.withLock { moved } }

    func moveToTrash(_ url: URL) throws {
        if failingNames.contains(url.lastPathComponent) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.moveItem(at: url, to: directory.appending(path: UUID().uuidString))
        lock.withLock { moved.append(url) }
    }
}

/// 테스트용 정리 서비스(가짜 휴지통·메모리 이력·고정 Xcode 상태).
func makeCleanupServices(
    cleaner: any Cleaning = Cleaner(
        environment: makeEnvironment(home: FileManager.default.temporaryDirectory),
        trash: FakeTrash(directory: FileManager.default.temporaryDirectory.appending(path: "unused-trash"))
    ),
    history: any HistoryStoring = InMemoryHistoryStore(),
    xcodeRunning: Bool = false
) -> CleanupServices {
    CleanupServices(cleaner: cleaner, history: history, xcode: FixedXcodeChecker(isRunning: xcodeRunning))
}

/// 실행 기록을 남기는 가짜 시뮬레이터 관리자.
final class FakeSimulators: SimulatorManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var inventory = SimulatorInventory(runtimes: [], devices: [])
    var loadError: SimctlError?
    var deleteError: SimctlError?

    var calls: [String] { lock.withLock { recorded } }

    private func record(_ call: String) { lock.withLock { recorded.append(call) } }

    func loadInventory() async throws -> SimulatorInventory {
        record("load")
        if let loadError { throw loadError }
        return inventory
    }

    func deleteRuntime(_ identifier: String) async throws {
        record("deleteRuntime \(identifier)")
        if let deleteError { throw deleteError }
    }

    func deleteDevice(_ udid: String) async throws {
        record("deleteDevice \(udid)")
        if let deleteError { throw deleteError }
    }

    func deleteUnavailableDevices() async throws {
        record("deleteUnavailable")
        if let deleteError { throw deleteError }
    }
}
