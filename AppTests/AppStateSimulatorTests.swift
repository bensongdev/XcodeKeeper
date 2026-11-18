import XCTest
@testable import XcodeKeeper

@MainActor
final class AppStateSimulatorTests: XCTestCase {
    private var fake: FakeSimulators!
    private var state: AppState!

    private func runtime(_ id: String, current: Bool = false, deletable: Bool = true) -> SimRuntime {
        SimRuntime(id: id, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0", platform: "iOS",
                   version: "27.0", build: nil, sizeBytes: 1, deviceCount: 0, lastUsedAt: nil,
                   isDeletable: deletable, isCurrent: current)
    }

    private let device = SimDevice(id: "68EEEBAF-CAE2-4AD3-AB38-31634CAB8C4D", name: "iPhone 17 Pro",
                                   runtimeName: "iOS 26.5", isAvailable: true, state: nil, lastUsedAt: nil)

    override func setUp() async throws {
        fake = FakeSimulators()
        state = AppState(
            diskSpace: FixedDiskSpaceProvider(bytes: 1), scanner: makeScanner([]),
            cleanup: makeCleanupServices(), simulators: fake
        )
    }

    func testLoadSuccessAndToolMissingAndFailure() async {
        XCTAssertEqual(state.simulatorState, .notLoaded)
        await state.loadSimulators()
        XCTAssertEqual(state.simulatorState, .loaded(SimulatorInventory(runtimes: [], devices: [])))

        fake.loadError = .toolMissing("xcrun: error: invalid active developer path")
        await state.loadSimulators()
        XCTAssertEqual(state.simulatorState, .toolMissing("xcrun: error: invalid active developer path"))

        fake.loadError = .unreadableOutput
        await state.loadSimulators()
        XCTAssertEqual(state.simulatorState, .failed("simctl 출력을 읽지 못했습니다"))
    }

    func testRuntimeDeletionNeedsConfirmationThenReloads() async {
        let target = runtime("385429F5-8FC2-4504-8348-245503EDCEE3")
        state.requestSimulatorDeletion(.runtime(target))
        XCTAssertEqual(state.simulatorConfirmation, SimulatorConfirmation(deletion: .runtime(target)))
        XCTAssertEqual(fake.calls, [], "확인 전에는 실행하지 않음")

        await state.confirmSimulatorDeletion()
        XCTAssertNil(state.simulatorConfirmation)
        XCTAssertEqual(fake.calls, ["deleteRuntime 385429F5-8FC2-4504-8348-245503EDCEE3", "load"])
        XCTAssertFalse(state.isSimulatorBusy)
    }

    func testCurrentRuntimeNeedsSecondConfirmation() async {
        let current = runtime("9E08F66B-9997-4064-B010-AAAB27BE9601", current: true)
        state.requestSimulatorDeletion(.runtime(current))
        await state.confirmSimulatorDeletion()
        XCTAssertEqual(state.simulatorConfirmation?.isSecondStep, true, "첫 확인 뒤에는 두 번째 확인")
        XCTAssertEqual(fake.calls, [])

        await state.confirmSimulatorDeletion()
        XCTAssertEqual(fake.calls.first, "deleteRuntime 9E08F66B-9997-4064-B010-AAAB27BE9601")
    }

    func testCancelAtSecondStepDeletesNothing() async {
        state.requestSimulatorDeletion(.runtime(runtime("9E08F66B-9997-4064-B010-AAAB27BE9601", current: true)))
        await state.confirmSimulatorDeletion()
        state.cancelSimulatorDeletion()
        XCTAssertNil(state.simulatorConfirmation)
        await state.confirmSimulatorDeletion()
        XCTAssertEqual(fake.calls, [])
    }

    func testNonDeletableRuntimeAndEmptyUnavailableAreIgnored() {
        state.requestSimulatorDeletion(.runtime(runtime("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", deletable: false)))
        XCTAssertNil(state.simulatorConfirmation)
        state.requestSimulatorDeletion(.unavailableDevices(count: 0))
        XCTAssertNil(state.simulatorConfirmation)
    }

    func testFailureShowsStderrAndDoesNotReload() async {
        fake.deleteError = .commandFailed("Unable to delete runtime: in use.")
        state.requestSimulatorDeletion(.device(device))
        await state.confirmSimulatorDeletion()
        XCTAssertEqual(state.simulatorError, "Unable to delete runtime: in use.")
        XCTAssertEqual(fake.calls, ["deleteDevice 68EEEBAF-CAE2-4AD3-AB38-31634CAB8C4D"])

        // 새 삭제 요청은 이전 오류를 지운다
        fake.deleteError = nil
        state.requestSimulatorDeletion(.unavailableDevices(count: 2))
        XCTAssertNil(state.simulatorError)
        await state.confirmSimulatorDeletion()
        XCTAssertEqual(fake.calls.suffix(2), ["deleteUnavailable", "load"])
    }

    func testToolMissingDuringDeleteSwitchesScreen() async {
        fake.deleteError = .toolMissing("xcrun: error")
        state.requestSimulatorDeletion(.device(device))
        await state.confirmSimulatorDeletion()
        XCTAssertEqual(state.simulatorState, .toolMissing("xcrun: error"))
    }
}
