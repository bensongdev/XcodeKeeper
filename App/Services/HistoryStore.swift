import Foundation

/// 정리 이력 저장소. 실제는 JSON 파일, UI 테스트는 메모리.
protocol HistoryStoring: Sendable {
    func load() -> [CleanupRecord]
    func save(_ records: [CleanupRecord]) throws
}

/// `~/Library/Application Support/XcodeKeeper/history.json`에 최신순 최대 100건을 저장한다.
struct FileHistoryStore: HistoryStoring {
    let fileURL: URL

    static func live() -> FileHistoryStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileHistoryStore(fileURL: support.appending(path: "XcodeKeeper/history.json"))
    }

    /// 파일이 없으면 빈 이력. 읽지 못하면(손상) 덮어쓰기 전에 `history-corrupt-<시각>.json`으로 옮겨 둔다.
    func load() -> [CleanupRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try Self.decoder.decode([CleanupRecord].self, from: data)
        } catch {
            preserveCorruptFile()
            return []
        }
    }

    func save(_ records: [CleanupRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(Array(records.prefix(CleanupHistory.limit)))
        try data.write(to: fileURL, options: .atomic)
    }

    private func preserveCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent().appending(path: "history-corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// 디스크에 쓰지 않는 이력(UI 테스트용).
final class InMemoryHistoryStore: HistoryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [CleanupRecord]

    init(records: [CleanupRecord] = []) {
        self.records = records
    }

    func load() -> [CleanupRecord] { lock.withLock { records } }

    func save(_ records: [CleanupRecord]) throws {
        lock.withLock { self.records = records }
    }
}
