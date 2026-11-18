import Foundation

/// `xcrun simctl ... -j` 출력 디코딩. M1은 기기 목록만 쓰고, 런타임 관리는 M3(F2)에서 추가한다.
enum SimctlJSON {
    struct DeviceList: Decodable, Sendable {
        /// 런타임 식별자 → 기기 목록
        let devices: [String: [Device]]
    }

    struct Device: Decodable, Sendable, Equatable {
        let udid: String
        let name: String
        let isAvailable: Bool
        let dataPath: String?
        let lastUsedAt: String?
    }

    static func decodeDevices(_ json: String) throws -> DeviceList {
        do {
            return try JSONDecoder().decode(DeviceList.self, from: Data(json.utf8))
        } catch {
            throw ScanFailure.other(String(localized: "simctl 출력을 읽지 못했습니다"))
        }
    }

    /// 런타임 식별자를 읽기 쉬운 이름으로: `com.apple.CoreSimulator.SimRuntime.iOS-17-0` → `iOS 17.0`
    static func runtimeName(_ identifier: String) -> String {
        let suffix = identifier.split(separator: ".").last.map(String.init) ?? identifier
        var parts = suffix.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return suffix }
        let platform = parts.removeFirst()
        return "\(platform) \(parts.joined(separator: "."))"
    }
}
