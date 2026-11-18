import XCTest
@testable import XcodeKeeper

final class HistoryStoreTests: XCTestCase {
    private func record(_ bytes: Int64, at seconds: TimeInterval = 1_790_000_000) -> CleanupRecord {
        CleanupRecord(
            id: UUID(), date: Date(timeIntervalSince1970: seconds),
            items: [CleanedItem(targetID: "derivedData", targetTitle: "DerivedData", itemName: "App", bytes: bytes)]
        )
    }

    func testAppendingKeepsNewestFirstAndCapsAt100() {
        var records: [CleanupRecord] = []
        for index in 0..<105 {
            records = CleanupHistory.appending(record(Int64(index)), to: records)
        }
        XCTAssertEqual(records.count, 100)
        XCTAssertEqual(records.first?.freedBytes, 104, "최신이 맨 앞")
        XCTAssertEqual(records.last?.freedBytes, 5, "가장 오래된 5건은 버림")
        XCTAssertEqual(CleanupHistory.totalFreed([record(3), record(4)]), 7)
    }

    func testFileStoreRoundTrip() throws {
        let temp = try TemporaryDirectory()
        let store = FileHistoryStore(fileURL: temp.url.appending(path: "Support/XcodeKeeper/history.json"))
        XCTAssertEqual(store.load(), [], "파일이 없으면 빈 이력")

        let records = [record(10, at: 1_790_000_100), record(20, at: 1_790_000_000)]
        try store.save(records)
        XCTAssertEqual(store.load(), records)
    }

    func testSaveCapsAt100() throws {
        let temp = try TemporaryDirectory()
        let store = FileHistoryStore(fileURL: temp.url.appending(path: "history.json"))
        try store.save((0..<150).map { record(Int64($0)) })
        XCTAssertEqual(store.load().count, 100)
    }

    func testCorruptFileIsPreservedBeforeOverwrite() throws {
        let temp = try TemporaryDirectory()
        let file = temp.url.appending(path: "history.json")
        try Data("not json".utf8).write(to: file)
        let store = FileHistoryStore(fileURL: file)

        XCTAssertEqual(store.load(), [])
        let backups = try FileManager.default.contentsOfDirectory(atPath: temp.url.path)
            .filter { $0.hasPrefix("history-corrupt-") }
        XCTAssertEqual(backups.count, 1, "손상 파일을 옮겨 둬야 함")
        let backup = temp.url.appending(path: backups[0])
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "not json")

        try store.save([record(1)])
        XCTAssertEqual(store.load().count, 1)
    }

    func testInMemoryStore() throws {
        let store = InMemoryHistoryStore()
        try store.save([record(5)])
        XCTAssertEqual(store.load().map(\.freedBytes), [5])
    }
}
