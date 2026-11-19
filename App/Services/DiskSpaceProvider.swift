import Foundation

/// 여유 공간을 읽는다. 테스트와 UI 테스트에서는 고정값 구현을 쓴다.
protocol DiskSpaceProviding: Sendable {
    /// 사용 가능한 바이트 수. 읽지 못하면 nil.
    func availableBytes() -> Int64?
    /// 볼륨 전체 크기. 읽지 못하면 nil.
    func totalBytes() -> Int64?
}

/// 홈 디렉터리가 있는 볼륨의 "중요한 용도로 사용 가능한 용량"을 읽는다(Finder와 같은 기준).
struct VolumeDiskSpaceProvider: DiskSpaceProviding {
    var volumeURL = URL(fileURLWithPath: NSHomeDirectory())

    func availableBytes() -> Int64? {
        let values = try? volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    func totalBytes() -> Int64? {
        let values = try? volumeURL.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return values?.volumeTotalCapacity.map(Int64.init)
    }
}

struct FixedDiskSpaceProvider: DiskSpaceProviding {
    let bytes: Int64?
    var total: Int64?

    func availableBytes() -> Int64? { bytes }
    func totalBytes() -> Int64? { total }
}
