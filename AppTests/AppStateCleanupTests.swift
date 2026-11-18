import XCTest
@testable import XcodeKeeper

/// 통합: 임시 홈에 가짜 DerivedData 트리를 만들고 스캔 → 정리 → 재스캔.
@MainActor
final class AppStateCleanupTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var trash: FakeTrash!
    private var history: InMemoryHistoryStore!

    override func setUp() async throws {
        temp = try TemporaryDirectory()
        trash = FakeTrash(directory: temp.url.appending(path: "trash"))
        history = InMemoryHistoryStore()
        let hash = "abcdefghijklmnopqrstuvwxyzab"
        try temp.makeFile("home/Library/Developer/Xcode/DerivedData/Alpha-\(hash)/a.bin", bytes: 2_000_000)
        try temp.makeFile("home/Library/Developer/Xcode/DerivedData/Beta-\(hash)/b.bin", bytes: 1_000_000)
        try temp.makeFile("home/Library/Developer/Xcode/Archives/2026-10-01/app.xcarchive", bytes: 500_000)
    }

    private func makeState(xcodeRunning: Bool = false) -> AppState {
        let environment = makeEnvironment(home: temp.url.appending(path: "home"))
        let targets = [BuiltinTargets.derivedData, BuiltinTargets.archives]
        return AppState(
            diskSpace: FixedDiskSpaceProvider(bytes: 1),
            scanner: JunkScanner(targets: targets, environment: environment),
            cleanup: makeCleanupServices(
                cleaner: Cleaner(environment: environment, trash: trash), history: history, xcodeRunning: xcodeRunning
            )
        )
    }

    private func scanned(xcodeRunning: Bool = false) async -> AppState {
        let state = makeState(xcodeRunning: xcodeRunning)
        state.startScan()
        await state.waitForScan()
        return state
    }

    private func waitForCleanup(_ state: AppState) async {
        await state.cleanupTask?.value
        await state.waitForScan()
    }

    func testScanCleanRescanRemovesOnlySafeSelection() async throws {
        let state = await scanned()
        XCTAssertEqual(state.scanResults.status(of: "derivedData").items.count, 2)
        XCTAssertTrue(state.canStartCleanup)

        state.requestCleanup()
        XCTAssertEqual(state.cleanupPhase, .confirming(xcodeRunningWarning: false))
        state.confirmCleanup()
        XCTAssertTrue(state.isCleaning)
        await waitForCleanup(state)

        guard case .finished(let outcome) = state.cleanupPhase else {
            return XCTFail("결과 단계가 아님: \(state.cleanupPhase)")
        }
        XCTAssertEqual(Set(outcome.cleaned.map(\.itemName)), ["Alpha", "Beta"])
        XCTAssertGreaterThanOrEqual(outcome.freedBytes, 3_000_000)
        XCTAssertEqual(trash.movedURLs.count, 2)
        // 재스캔: DerivedData는 비고, 기본 미선택이던 Archives는 그대로
        XCTAssertEqual(state.scanResults.status(of: "derivedData"), .done([]))
        XCTAssertEqual(state.scanResults.status(of: "archives").items.count, 1)
        // 이력 저장
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(history.load().first?.items.count, 2)
    }

    func testDismissConfirmationChangesNothing() async {
        let state = await scanned()
        state.requestCleanup()
        state.dismissCleanupConfirmation()
        XCTAssertEqual(state.cleanupPhase, .idle)
        state.confirmCleanup()
        XCTAssertEqual(state.cleanupPhase, .idle, "확인 없이 정리하지 않음")
        XCTAssertTrue(trash.movedURLs.isEmpty)
        XCTAssertEqual(state.history, [])
    }

    func testXcodeRunningWarningOnlyWhenDerivedDataSelected() async {
        let state = await scanned(xcodeRunning: true)
        state.requestCleanup()
        XCTAssertEqual(state.cleanupPhase, .confirming(xcodeRunningWarning: true))
        state.dismissCleanupConfirmation()

        state.scanResults.setAllSelected(false, targetID: "derivedData")
        state.scanResults.setAllSelected(true, targetID: "archives")
        state.requestCleanup()
        XCTAssertEqual(state.cleanupPhase, .confirming(xcodeRunningWarning: false), "DerivedData가 없으면 경고 없음")
    }

    func testCannotStartWithoutSelection() async {
        let state = await scanned()
        state.scanResults.setAllSelected(false, targetID: "derivedData")
        XCTAssertFalse(state.canStartCleanup)
        state.requestCleanup()
        XCTAssertEqual(state.cleanupPhase, .idle)
    }

    func testSelectionsGroupByTargetAndCommandFlag() async {
        let state = await scanned()
        XCTAssertEqual(state.cleanupSelections.map(\.target.id), ["derivedData"])
        XCTAssertEqual(state.cleanupSelections.first?.items.count, 2)
        XCTAssertFalse(state.selectionIncludesCommandTarget)
    }

    func testFailedOnlyCleanupDoesNotAddHistory() async throws {
        trash.failingNames = ["Alpha-abcdefghijklmnopqrstuvwxyzab", "Beta-abcdefghijklmnopqrstuvwxyzab"]
        let state = await scanned()
        state.requestCleanup()
        state.confirmCleanup()
        await waitForCleanup(state)
        guard case .finished(let outcome) = state.cleanupPhase else { return XCTFail("결과 없음") }
        XCTAssertEqual(outcome.failures.count, 2)
        XCTAssertEqual(state.history, [], "확보한 것이 없으면 이력을 남기지 않음")
    }
}
