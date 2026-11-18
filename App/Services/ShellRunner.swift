import Foundation

/// 외부 명령 실행 결과.
struct ShellResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ShellError: Error, Equatable {
    /// 제한 시간을 넘겨 프로세스를 종료했다.
    case timedOut(seconds: TimeInterval)
    /// 실행 파일을 시작하지 못했다(없음, 권한 없음 등).
    case launchFailed(String)
}

/// 외부 명령 실행을 추상화한다. 테스트에서는 가짜 구현으로 바꾼다.
protocol ShellRunning: Sendable {
    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async throws -> ShellResult
}

extension ShellRunning {
    func run(_ executable: URL, arguments: [String]) async throws -> ShellResult {
        try await run(executable, arguments: arguments, timeout: ShellRunner.defaultTimeout)
    }
}

/// `Process` 래퍼. 셸을 거치지 않고 실행 파일 + 인자 배열로만 실행한다.
/// 타임아웃이나 호출 Task 취소 시 프로세스를 종료한다.
struct ShellRunner: ShellRunning {
    static let defaultTimeout: TimeInterval = 30

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async throws -> ShellResult {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let (exitStream, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(error.localizedDescription)
        }

        let handle = ProcessHandle(process)
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled { handle.terminate(dueToTimeout: true) }
        }
        defer { timeoutTask.cancel() }

        let outReader = outPipe.fileHandleForReading
        let errReader = errPipe.fileHandleForReading
        let result: ShellResult = await withTaskCancellationHandler {
            async let outData = Self.readToEnd(outReader)
            async let errData = Self.readToEnd(errReader)
            var status: Int32 = -1
            for await code in exitStream { status = code }
            return ShellResult(
                exitCode: status,
                stdout: Self.decode(await outData),
                stderr: Self.decode(await errData)
            )
        } onCancel: {
            handle.terminate(dueToTimeout: false)
        }

        if handle.didTimeOut { throw ShellError.timedOut(seconds: timeout) }
        try Task.checkCancellation()
        return result
    }

    /// UTF-8로 읽고, 실패하면 모든 바이트를 표현할 수 있는 Latin-1로 읽어 출력을 잃지 않는다.
    private static func decode(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
    }

    /// 파이프를 끝까지 읽는다. 블로킹 읽기가 협력 스레드 풀을 막지 않도록 전역 큐에서 실행한다.
    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: (try? handle.readToEnd()) ?? Data())
            }
        }
    }
}

/// Sendable이 아닌 `Process`를 타임아웃/취소 핸들러에서 안전하게 종료하기 위한 상자.
private final class ProcessHandle: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var timedOut = false

    init(_ process: Process) {
        self.process = process
    }

    var didTimeOut: Bool {
        lock.withLock { timedOut }
    }

    func terminate(dueToTimeout: Bool) {
        lock.withLock {
            if dueToTimeout { timedOut = true }
            if process.isRunning { process.terminate() }
        }
    }
}
