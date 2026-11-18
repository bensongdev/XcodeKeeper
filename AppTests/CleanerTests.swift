import XCTest
@testable import XcodeKeeper

final class CleanerTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var home: URL!
    private var trash: FakeTrash!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        home = try temp.makeDirectory("home")
        trash = FakeTrash(directory: temp.url.appending(path: "trash"))
    }

    private func cleaner(shell: any ShellRunning = FakeShell(stdout: "")) -> Cleaner {
        Cleaner(environment: makeEnvironment(home: home, shell: shell), trash: trash)
    }

    private func derivedDataItem(_ name: String, bytes: Int = 1_000) throws -> ScanItem {
        let url = try temp.makeDirectory("home/Library/Developer/Xcode/DerivedData/\(name)")
        try temp.makeFile("home/Library/Developer/Xcode/DerivedData/\(name)/file", bytes: bytes)
        return ScanItem(url: url, name: name, bytes: Int64(bytes), lastModified: nil)
    }

    func testTrashTargetMovesOnlySelectedItems() async throws {
        let first = try derivedDataItem("A")
        let second = try derivedDataItem("B")
        let kept = try derivedDataItem("C")

        let outcome = await cleaner().clean([
            CleanupSelection(target: BuiltinTargets.derivedData, items: [first, second])
        ])

        XCTAssertEqual(outcome.cleaned.map(\.itemName), ["A", "B"])
        XCTAssertEqual(outcome.failures, [])
        XCTAssertEqual(outcome.freedBytes, 2_000)
        XCTAssertFalse(outcome.wasCancelled)
        XCTAssertEqual(trash.movedURLs.map(\.lastPathComponent), ["A", "B"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(first.url).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(kept.url).path), "선택하지 않은 항목은 그대로")
    }

    func testItemOutsideAllowedRootIsNotTouched() async throws {
        let outside = try temp.makeDirectory("home/Documents/Precious")
        let forged = ScanItem(url: outside, name: "Precious", bytes: 1, lastModified: nil)
        let good = try derivedDataItem("Good")

        let outcome = await cleaner().clean([
            CleanupSelection(target: BuiltinTargets.derivedData, items: [forged, good])
        ])

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "허용 루트 밖은 절대 옮기지 않음")
        XCTAssertEqual(outcome.failures, [
            CleanupFailure(targetTitle: "DerivedData", itemName: "Precious", reason: "허용되지 않은 경로")
        ])
        XCTAssertEqual(outcome.cleaned.map(\.itemName), ["Good"], "하나가 실패해도 나머지는 계속")
    }

    func testSymlinkEscapeIsNotTouched() async throws {
        let outside = try temp.makeDirectory("home/Documents/Project")
        let link = home.appending(path: "Library/Developer/Xcode/DerivedData/Escape")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let item = ScanItem(url: link, name: "Escape", bytes: 1, lastModified: nil)

        let outcome = await cleaner().clean([CleanupSelection(target: BuiltinTargets.derivedData, items: [item])])

        XCTAssertEqual(outcome.failures.map(\.reason), ["허용되지 않은 경로"])
        XCTAssertTrue(trash.movedURLs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testTrashErrorIsReportedAndOthersContinue() async throws {
        let broken = try derivedDataItem("Broken")
        let fine = try derivedDataItem("Fine")
        trash.failingNames = ["Broken"]

        let outcome = await cleaner().clean([
            CleanupSelection(target: BuiltinTargets.derivedData, items: [broken, fine])
        ])

        XCTAssertEqual(outcome.failures.map(\.itemName), ["Broken"])
        XCTAssertFalse(outcome.failures[0].reason.isEmpty)
        XCTAssertEqual(outcome.cleaned.map(\.itemName), ["Fine"])
    }

    func testAlreadyMissingItemIsReported() async throws {
        let item = try derivedDataItem("Gone")
        try FileManager.default.removeItem(at: try XCTUnwrap(item.url)) // 테스트 임시 폴더 안
        let outcome = await cleaner().clean([CleanupSelection(target: BuiltinTargets.derivedData, items: [item])])
        XCTAssertEqual(outcome.failures.map(\.reason), ["이미 없음"])
    }

    func testCommandTargetRunsXcrunOnceForAllItems() async throws {
        let shell = FakeShell(stdout: "")
        let items = [makeItem("d1", bytes: 10), makeItem("d2", bytes: 20)]

        let outcome = await cleaner(shell: shell).clean([
            CleanupSelection(target: BuiltinTargets.unavailableSimulators, items: items)
        ])

        XCTAssertEqual(shell.calls, [["xcrun", "simctl", "delete", "unavailable"]])
        XCTAssertEqual(outcome.freedBytes, 30)
        XCTAssertTrue(trash.movedURLs.isEmpty, "명령 대상은 휴지통을 쓰지 않음")
    }

    func testCommandFailureShowsStderr() async throws {
        let shell = FakeShell(stdout: "", exitCode: 1, stderr: "simctl: device busy\n")
        let outcome = await cleaner(shell: shell).clean([
            CleanupSelection(target: BuiltinTargets.unavailableSimulators, items: [makeItem("d1", bytes: 10)])
        ])
        XCTAssertEqual(outcome.cleaned, [])
        XCTAssertEqual(outcome.failures.map(\.reason), ["simctl: device busy"])
    }

    func testInfoOnlyTargetIsSkipped() async {
        let shell = FakeShell(stdout: "")
        let outcome = await cleaner(shell: shell).clean([
            CleanupSelection(target: BuiltinTargets.localSnapshots, items: [ScanItem(id: "snap", name: "snap")])
        ])
        XCTAssertEqual(outcome, CleanupOutcome())
        XCTAssertEqual(shell.calls, [])
    }

    func testCancelledBeforeStartTouchesNothing() async throws {
        let item = try derivedDataItem("Keep")
        let cleaner = cleaner()
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return await cleaner.clean([CleanupSelection(target: BuiltinTargets.derivedData, items: [item])])
        }
        let outcome = await task.value
        XCTAssertTrue(outcome.wasCancelled)
        XCTAssertEqual(outcome.cleaned, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(item.url).path))
    }
}
