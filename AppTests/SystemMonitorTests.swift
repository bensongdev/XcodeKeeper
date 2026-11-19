import XCTest
@testable import XcodeKeeper

final class SystemMonitorTests: XCTestCase {
    func testPressureLevelMapping() {
        XCTAssertEqual(MemoryPressure(sysctlLevel: 1), .normal)
        XCTAssertEqual(MemoryPressure(sysctlLevel: 2), .warning)
        XCTAssertEqual(MemoryPressure(sysctlLevel: 4), .critical)
        XCTAssertEqual(MemoryPressure(sysctlLevel: 0), .normal, "모르는 값은 정상")
        XCTAssertEqual(MemoryPressure(sysctlLevel: 3), .normal)
        XCTAssertEqual(MemoryPressure(sysctlLevel: nil), .normal, "읽지 못하면 정상")
    }

    func testSnapshotFromPagesAndSwap() {
        let snapshot = MemorySnapshot.make(
            totalBytes: 8_589_934_592, pageSize: 16_384,
            pages: .init(internalPages: 200_000, purgeablePages: 10_000, wiredPages: 80_000, compressedPages: 50_000),
            swap: SwapUsage(used: 2_147_483_648, total: 3_221_225_472), pressureLevel: 2
        )
        XCTAssertEqual(snapshot.totalBytes, 8_589_934_592)
        XCTAssertEqual(snapshot.appBytes, 190_000 * 16_384, "App = internal − purgeable")
        XCTAssertEqual(snapshot.wiredBytes, 80_000 * 16_384)
        XCTAssertEqual(snapshot.compressedBytes, 50_000 * 16_384)
        XCTAssertEqual(snapshot.swapUsedBytes, 2_147_483_648)
        XCTAssertEqual(snapshot.swapTotalBytes, 3_221_225_472)
        XCTAssertEqual(snapshot.pressure, .warning)
        XCTAssertEqual(snapshot.usedBytes, (190_000 + 80_000 + 50_000) * 16_384)
    }

    func testSnapshotEdgeCases() {
        let snapshot = MemorySnapshot.make(
            totalBytes: 1, pageSize: 4_096,
            pages: .init(internalPages: 5, purgeablePages: 9, wiredPages: 0, compressedPages: 0),
            swap: nil, pressureLevel: nil
        )
        XCTAssertEqual(snapshot.appBytes, 0, "purgeable이 더 크면 0")
        XCTAssertEqual(snapshot.swapUsedBytes, 0, "스왑을 읽지 못하면 0")
        XCTAssertEqual(snapshot.pressure, .normal)
    }

    func testTopProcessesSortedAndLimited() {
        let processes = [
            ProcessMemory(pid: 3, name: "c", bytes: 300), ProcessMemory(pid: 1, name: "a", bytes: 900),
            ProcessMemory(pid: 7, name: "zero", bytes: 0), ProcessMemory(pid: 2, name: "b", bytes: 300),
            ProcessMemory(pid: 4, name: "d", bytes: 100), ProcessMemory(pid: 5, name: "e", bytes: 50),
            ProcessMemory(pid: 6, name: "f", bytes: 10)
        ]
        XCTAssertEqual(ProcessMemory.top(processes, limit: 5).map(\.name), ["a", "b", "c", "d", "e"],
                       "용량 내림차순, 같으면 pid 오름차순, 0바이트 제외")
        XCTAssertEqual(ProcessMemory.top(processes, limit: 2).map(\.pid), [1, 2])
        XCTAssertEqual(ProcessMemory.top([], limit: 5), [])
    }

    /// 실제 시스템 값 읽기(읽기 전용). 값 자체는 로그에 남기지 않고 관계만 확인한다.
    func testLiveMonitorReadsPlausibleValues() throws {
        let monitor = LiveSystemMonitor()
        let snapshot = try XCTUnwrap(monitor.snapshot(), "메모리 통계를 읽지 못함")
        XCTAssertEqual(snapshot.totalBytes, Int64(ProcessInfo.processInfo.physicalMemory))
        XCTAssertGreaterThan(snapshot.appBytes, 0)
        XCTAssertGreaterThan(snapshot.wiredBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.usedBytes, snapshot.totalBytes, "App+Wired+압축은 전체 이하")
        XCTAssertLessThanOrEqual(snapshot.swapUsedBytes, snapshot.swapTotalBytes)

        let top = monitor.topProcesses(limit: 5)
        XCTAssertFalse(top.isEmpty, "같은 사용자 프로세스는 읽혀야 함")
        XCTAssertLessThanOrEqual(top.count, 5)
        XCTAssertEqual(top.map(\.bytes), top.map(\.bytes).sorted(by: >))
        XCTAssertTrue(top.allSatisfy { !$0.name.isEmpty })
    }
}

final class StatusLevelTests: XCTestCase {
    private let gb: Int64 = 1_000_000_000

    private func memory(swap: Int64 = 0, pressure: MemoryPressure = .normal) -> MemorySnapshot {
        MemorySnapshot(totalBytes: 8 * gb, appBytes: gb, wiredBytes: gb, compressedBytes: 0,
                       swapUsedBytes: swap, swapTotalBytes: 4 * gb, pressure: pressure)
    }

    private func level(_ available: Int64?, _ memory: MemorySnapshot?) -> StatusLevel {
        StatusLevel.evaluate(availableBytes: available, memory: memory,
                             freeSpaceThresholdBytes: 30 * gb, swapThresholdBytes: 2 * gb)
    }

    func testNormal() {
        XCTAssertEqual(level(30 * gb, memory()), .normal, "기준과 같으면 정상")
        XCTAssertEqual(level(50 * gb, memory(swap: 2 * gb)), .normal, "스왑이 기준과 같으면 정상(초과만 경고)")
        XCTAssertEqual(level(nil, nil), .normal, "읽지 못한 값은 판단에서 뺀다")
    }

    func testWarning() {
        XCTAssertEqual(level(30 * gb - 1, memory()), .warning, "여유 공간이 기준 미만")
        XCTAssertEqual(level(10 * gb, memory()), .warning, "10GB는 빨강이 아님")
        XCTAssertEqual(level(50 * gb, memory(swap: 2 * gb + 1)), .warning, "스왑 기준 초과")
        XCTAssertEqual(level(50 * gb, memory(pressure: .warning)), .normal, "압박 경고만으로는 바꾸지 않음(PRD)")
        XCTAssertEqual(level(nil, memory(swap: 3 * gb)), .warning)
    }

    func testCritical() {
        XCTAssertEqual(level(10 * gb - 1, memory()), .critical, "여유 10GB 미만")
        XCTAssertEqual(level(50 * gb, memory(pressure: .critical)), .critical, "압박 위험")
        XCTAssertEqual(level(5 * gb, memory(swap: 3 * gb)), .critical, "빨강이 노랑보다 우선")
    }
}
