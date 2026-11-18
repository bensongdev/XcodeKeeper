import XCTest
@testable import XcodeKeeper

final class JunkScannerTests: XCTestCase {
    private func scanner(_ targets: [CleanupTarget]) throws -> JunkScanner {
        makeScanner(targets)
    }

    func testEmitsFinishedEventsProgressivelyAndSortsItems() async throws {
        let fast = makeTarget("fast", result: .success([makeItem("small", bytes: 1), makeItem("big", bytes: 9)]))
        let slow = makeTarget("slow", delay: .milliseconds(600), result: .success([makeItem("s", bytes: 5)]))

        var events: [ScanEvent] = []
        for await event in try scanner([slow, fast]).scan() { events.append(event) }

        let finishes = events.compactMap { event -> String? in
            if case .finished(let id, _) = event { return id }
            return nil
        }
        XCTAssertEqual(finishes, ["fast", "slow"], "먼저 끝난 대상이 먼저 와야 함")
        XCTAssertTrue(events.contains(.started(targetID: "slow")))
        XCTAssertTrue(events.contains(.finished(targetID: "fast", items: [makeItem("big", bytes: 9),
                                                                          makeItem("small", bytes: 1)])),
                      "용량 내림차순 정렬")
        let fastFinished = try XCTUnwrap(events.firstIndex(of: .finished(targetID: "fast", items: [
            makeItem("big", bytes: 9), makeItem("small", bytes: 1)
        ])))
        let slowFinished = try XCTUnwrap(events.firstIndex {
            if case .finished("slow", _) = $0 { true } else { false }
        })
        XCTAssertLessThan(fastFinished, slowFinished)
    }

    func testFailureIsIsolatedToItsTarget() async throws {
        let broken = makeTarget("broken", result: .failure(.permissionDenied))
        let fine = makeTarget("fine", result: .success([makeItem("a", bytes: 1)]))

        var events: [ScanEvent] = []
        for await event in try scanner([broken, fine]).scan() { events.append(event) }

        XCTAssertTrue(events.contains(.failed(targetID: "broken", failure: .permissionDenied)))
        XCTAssertTrue(events.contains(.finished(targetID: "fine", items: [makeItem("a", bytes: 1)])))
    }

    func testStoppingConsumptionCancelsRemainingTargets() async throws {
        let start = Date()
        let slow = makeTarget("slow", delay: .seconds(10))
        let stream = try scanner([slow]).scan()
        let consumer = Task {
            var events: [ScanEvent] = []
            for await event in stream { events.append(event) }
            return events
        }
        try await Task.sleep(for: .milliseconds(200))
        consumer.cancel()
        let events = await consumer.value
        XCTAssertFalse(events.contains { if case .finished = $0 { true } else { false } })
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
