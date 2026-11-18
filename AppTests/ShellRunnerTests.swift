import XCTest
@testable import XcodeKeeper

final class ShellRunnerTests: XCTestCase {
    private let runner = ShellRunner()

    func testDefaultTimeoutIsThirtySeconds() {
        XCTAssertEqual(ShellRunner.defaultTimeout, 30)
    }

    func testSuccessReturnsStdoutAndZeroExit() async throws {
        let result = try await runner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"])
        XCTAssertEqual(result, ShellResult(exitCode: 0, stdout: "hello\n", stderr: ""))
    }

    func testNonZeroExitKeepsStderr() async throws {
        let result = try await runner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo oops >&2; exit 3"]
        )
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(result.stderr, "oops\n")
        XCTAssertEqual(result.stdout, "")
    }

    func testArgumentsAreNotInterpretedByShell() async throws {
        let result = try await runner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["$HOME; ls"])
        XCTAssertEqual(result.stdout, "$HOME; ls\n")
    }

    func testLargeOutputDoesNotDeadlock() async throws {
        // 파이프 버퍼(64KB)보다 큰 출력
        let result = try await runner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' 'a'"],
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.utf8.count, 300_000)
    }

    func testTimeoutTerminatesProcess() async {
        let start = Date()
        do {
            _ = try await runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.5)
            XCTFail("타임아웃 오류가 나야 합니다")
        } catch {
            XCTAssertEqual(error as? ShellError, .timedOut(seconds: 0.5))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testCancellationTerminatesProcess() async {
        let start = Date()
        let task = Task { [runner] in
            try await runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 30)
        }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("취소 오류가 나야 합니다")
        } catch {
            XCTAssertTrue(error is CancellationError, "실제 오류: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testMissingExecutableThrowsLaunchFailed() async {
        do {
            _ = try await runner.run(URL(fileURLWithPath: "/nonexistent/tool"), arguments: [])
            XCTFail("실행 실패 오류가 나야 합니다")
        } catch {
            guard case .launchFailed = error as? ShellError else {
                return XCTFail("launchFailed가 아님: \(error)")
            }
        }
    }
}
