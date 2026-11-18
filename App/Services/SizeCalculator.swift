import Foundation

/// 폴더의 실제 점유 용량을 계산한다.
/// `totalFileAllocatedSize` 합계이고, 하드링크로 같은 파일을 여러 번 가리키면 한 번만 센다.
struct SizeCalculator: Sendable {
    /// 취소 확인 간격(파일 수).
    private static let cancellationCheckInterval = 512

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .linkCountKey, .fileResourceIdentifierKey
    ]

    /// `url`이 파일이면 그 파일의, 폴더면 하위 전체의 점유 용량.
    /// - Throws: 루트를 읽을 수 없으면 `ScanFailure.permissionDenied`, 취소되면 `CancellationError`.
    func allocatedSize(of url: URL) throws -> Int64 {
        let root = url.resolvingSymlinksInPath()
        let rootValues = try Self.values(of: root)
        guard rootValues.isDirectory == true else {
            return Int64(rootValues.totalFileAllocatedSize ?? rootValues.fileAllocatedSize ?? 0)
        }
        // 루트 폴더 자체를 읽을 수 없으면 권한 문제로 본다(열거자는 이 경우 조용히 빈 결과를 낸다).
        guard FileManager.default.isReadableFile(atPath: root.path),
              (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil else {
            throw ScanFailure.permissionDenied
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Self.keys, options: [], errorHandler: { _, _ in true }
        ) else {
            throw ScanFailure.permissionDenied
        }

        var total: Int64 = 0
        var seenHardLinks = Set<NSObject>()
        var count = 0
        for case let fileURL as URL in enumerator {
            count += 1
            if count % Self.cancellationCheckInterval == 0, Task.isCancelled { throw CancellationError() }
            guard let values = try? fileURL.resourceValues(forKeys: Set(Self.keys)),
                  values.isRegularFile == true else { continue }
            if (values.linkCount ?? 1) > 1, let identifier = values.fileResourceIdentifier as? NSObject {
                guard seenHardLinks.insert(identifier).inserted else { continue }
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        if Task.isCancelled { throw CancellationError() }
        return total
    }

    private static func values(of url: URL) throws -> URLResourceValues {
        do {
            return try url.resourceValues(forKeys: Set(keys))
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw ScanFailure.permissionDenied
        }
    }
}
