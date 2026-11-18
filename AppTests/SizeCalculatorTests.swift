import XCTest
@testable import XcodeKeeper

final class SizeCalculatorTests: XCTestCase {
    private let calculator = SizeCalculator()

    func testSumsAllocatedSizeOfNestedFiles() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFile("root/a.bin", bytes: 1_000_000)
        try temp.makeFile("root/sub/b.bin", bytes: 2_000_000)
        try temp.makeFile("root/sub/deeper/c.bin", bytes: 500_000)

        let size = try calculator.allocatedSize(of: temp.url.appending(path: "root"))
        // 점유 용량은 블록 단위로 올림되므로 논리 크기 이상, 블록 3개 이하 차이
        XCTAssertGreaterThanOrEqual(size, 3_500_000)
        XCTAssertLessThan(size, 3_500_000 + 3 * 16_384)
    }

    func testMatchesDuWithinFivePercent() async throws {
        let temp = try TemporaryDirectory()
        for index in 0..<20 {
            try temp.makeFile("tree/dir\(index % 4)/file\(index).bin", bytes: 150_000 + index * 7_919)
        }
        let root = temp.url.appending(path: "tree")
        let ours = try calculator.allocatedSize(of: root)

        let du = try await ShellRunner().run(URL(fileURLWithPath: "/usr/bin/du"), arguments: ["-sk", root.path])
        XCTAssertEqual(du.exitCode, 0, du.stderr)
        let duKB = try XCTUnwrap(Int64(du.stdout.split(separator: "\t").first ?? ""))
        let duBytes = duKB * 1024
        let difference = abs(Double(ours - duBytes)) / Double(duBytes)
        XCTAssertLessThanOrEqual(difference, 0.05, "ours=\(ours) du=\(duBytes)")
    }

    func testHardLinkedFileIsCountedOnce() throws {
        let temp = try TemporaryDirectory()
        let original = try temp.makeFile("root/original.bin", bytes: 1_000_000)
        try FileManager.default.linkItem(at: original, to: temp.url.appending(path: "root/link.bin"))
        try FileManager.default.createDirectory(
            at: temp.url.appending(path: "root/other"), withIntermediateDirectories: true
        )
        try FileManager.default.linkItem(at: original, to: temp.url.appending(path: "root/other/link2.bin"))

        let size = try calculator.allocatedSize(of: temp.url.appending(path: "root"))
        XCTAssertGreaterThanOrEqual(size, 1_000_000)
        XCTAssertLessThan(size, 2_000_000, "하드링크가 중복으로 합산됨: \(size)")
    }

    func testSymlinkPointingOutsideIsNotFollowed() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFile("outside/big.bin", bytes: 3_000_000)
        try temp.makeFile("root/small.bin", bytes: 100_000)
        try FileManager.default.createSymbolicLink(
            at: temp.url.appending(path: "root/link"), withDestinationURL: temp.url.appending(path: "outside")
        )
        let size = try calculator.allocatedSize(of: temp.url.appending(path: "root"))
        XCTAssertLessThan(size, 1_000_000, "심볼릭 링크 너머를 셈: \(size)")
    }

    func testSingleFileReturnsItsAllocatedSize() throws {
        let temp = try TemporaryDirectory()
        let file = try temp.makeFile("one.bin", bytes: 40_000)
        let size = try calculator.allocatedSize(of: file)
        XCTAssertGreaterThanOrEqual(size, 40_000)
        XCTAssertLessThan(size, 40_000 + 16_384)
    }

    func testEmptyDirectoryIsZero() throws {
        let temp = try TemporaryDirectory()
        XCTAssertEqual(try calculator.allocatedSize(of: try temp.makeDirectory("empty")), 0)
    }

    func testUnreadableDirectoryThrowsPermissionDenied() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFile("locked/secret.bin", bytes: 10_000)
        let locked = temp.url.appending(path: "locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        XCTAssertThrowsError(try calculator.allocatedSize(of: locked)) { error in
            XCTAssertEqual(error as? ScanFailure, .permissionDenied)
        }
    }

    func testCancelledTaskStopsCounting() async throws {
        let temp = try TemporaryDirectory()
        for index in 0..<1_100 {
            try temp.makeFile("many/f\(index)", bytes: 10)
        }
        let root = temp.url.appending(path: "many")
        let task = Task.detached { [calculator] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try calculator.allocatedSize(of: root)
        }
        do {
            _ = try await task.value
            XCTFail("취소 오류가 나야 합니다")
        } catch {
            XCTAssertTrue(error is CancellationError, "실제 오류: \(error)")
        }
    }
}
