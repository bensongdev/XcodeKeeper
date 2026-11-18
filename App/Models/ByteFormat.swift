import Foundation

/// 용량 표시 형식. Finder와 같이 10^9 바이트를 1GB로 본다.
enum ByteFormat {
    static let bytesPerGB: Double = 1_000_000_000

    /// 메뉴바용 짧은 표기. 내림한 정수 GB, 예: 16_200_000_000 → "16G". 값이 없으면 "—".
    static func menuBarLabel(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        return "\(Int64((Double(bytes) / bytesPerGB).rounded(.down)))G"
    }

    /// 소수 첫째 자리까지의 GB 표기(내림), 예: 16_290_000_000 → "16.2GB". 값이 없으면 "—".
    static func gigabytes(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        let tenths = Int64((Double(bytes) / bytesPerGB * 10).rounded(.down))
        return "\(tenths / 10).\(tenths % 10)GB"
    }

    /// 목록 행용 표기. 1GB 이상은 "3.2GB", 미만은 내림한 정수 MB("450MB"), 1MB 미만은 "1MB 미만".
    static func size(_ bytes: Int64) -> String {
        if Double(bytes) >= bytesPerGB { return gigabytes(bytes) }
        let megabytes = bytes / 1_000_000
        return megabytes >= 1 ? "\(megabytes)MB" : String(localized: "1MB 미만")
    }
}
