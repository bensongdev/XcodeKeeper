import Foundation

/// 시뮬레이터 런타임 하나(표의 한 행).
struct SimRuntime: Identifiable, Sendable, Equatable {
    /// 런타임 이미지 UUID. `simctl runtime delete`에 넘기는 값.
    let id: String
    /// `com.apple.CoreSimulator.SimRuntime.iOS-27-0`
    let runtimeIdentifier: String
    let platform: String
    let version: String
    let build: String?
    let sizeBytes: Int64
    let deviceCount: Int
    let lastUsedAt: Date?
    let isDeletable: Bool
    /// 현재 Xcode의 기본 런타임
    let isCurrent: Bool

    var displayName: String { "\(platform) \(version)" }
}

/// 시뮬레이터 기기 하나.
struct SimDevice: Identifiable, Sendable, Equatable {
    /// UDID. `simctl delete`에 넘기는 값.
    let id: String
    let name: String
    let runtimeName: String
    let isAvailable: Bool
    let state: String?
    let lastUsedAt: Date?

    /// simctl 상태를 한국어로. 모르는 상태는 원문 그대로.
    var stateText: String {
        switch state {
        case "Shutdown": String(localized: "꺼짐")
        case "Booted": String(localized: "실행 중")
        case "Booting": String(localized: "켜는 중")
        case "Shutting Down": String(localized: "끄는 중")
        case "Creating": String(localized: "만드는 중")
        case .none: ""
        case .some(let other): other
        }
    }
}

/// 시뮬레이터 화면에 보여 줄 런타임·기기 목록. 순수 값 타입이라 단위 테스트한다.
struct SimulatorInventory: Sendable, Equatable {
    let runtimes: [SimRuntime]
    let devices: [SimDevice]

    var unavailableDevices: [SimDevice] { devices.filter { !$0.isAvailable } }

    /// simctl 출력으로 목록을 만든다.
    /// - 런타임은 용량 내림차순, 기기는 사용 가능 먼저·런타임·이름 순.
    /// - 현재 런타임: `sdkVersion`과 버전이 같은 iOS 런타임. 없거나 SDK를 모르면 가장 높은 iOS 버전.
    static func make(
        runtimes entries: [SimctlJSON.RuntimeEntry], devices list: SimctlJSON.DeviceList, sdkVersion: String?
    ) -> SimulatorInventory {
        let deviceCounts: [String: Int] = list.devices.mapValues { $0.count }
        let current = currentRuntimeID(entries, sdkVersion: sdkVersion)
        let runtimes: [SimRuntime] = entries
            .map { runtime(from: $0, deviceCount: deviceCounts[$0.runtimeIdentifier] ?? 0, currentID: current) }
            .sorted(by: isLargerRuntime)
        var devices: [SimDevice] = []
        for (runtimeID, entries) in list.devices {
            devices += entries.map { device(from: $0, runtimeID: runtimeID) }
        }
        devices.sort(by: isListedBefore)
        return SimulatorInventory(runtimes: runtimes, devices: devices)
    }

    private static func runtime(
        from entry: SimctlJSON.RuntimeEntry, deviceCount: Int, currentID: String?
    ) -> SimRuntime {
        SimRuntime(
            id: entry.identifier,
            runtimeIdentifier: entry.runtimeIdentifier,
            platform: platform(of: entry.runtimeIdentifier),
            version: entry.version,
            build: entry.build,
            sizeBytes: entry.sizeBytes ?? 0,
            deviceCount: deviceCount,
            lastUsedAt: SimctlJSON.parseDate(entry.lastUsedAt),
            isDeletable: entry.deletable ?? false,
            isCurrent: entry.identifier == currentID
        )
    }

    private static func device(from device: SimctlJSON.Device, runtimeID: String) -> SimDevice {
        SimDevice(
            id: device.udid, name: device.name, runtimeName: SimctlJSON.runtimeName(runtimeID),
            isAvailable: device.isAvailable, state: device.state, lastUsedAt: SimctlJSON.parseDate(device.lastUsedAt)
        )
    }

    /// 용량 내림차순, 같으면 id 순(결과가 항상 같게).
    private static func isLargerRuntime(_ lhs: SimRuntime, _ rhs: SimRuntime) -> Bool {
        lhs.sizeBytes != rhs.sizeBytes ? lhs.sizeBytes > rhs.sizeBytes : lhs.id < rhs.id
    }

    /// 사용 가능 먼저, 런타임 이름 내림차순(최신 먼저), 이름 순.
    private static func isListedBefore(_ lhs: SimDevice, _ rhs: SimDevice) -> Bool {
        if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
        if lhs.runtimeName != rhs.runtimeName {
            return compareVersions(lhs.runtimeName, rhs.runtimeName) == .orderedDescending
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-27-0` → `iOS`
    static func platform(of runtimeIdentifier: String) -> String {
        SimctlJSON.runtimeName(runtimeIdentifier).split(separator: " ").first.map(String.init) ?? runtimeIdentifier
    }

    private static func currentRuntimeID(_ entries: [SimctlJSON.RuntimeEntry], sdkVersion: String?) -> String? {
        let iOS = entries.filter { platform(of: $0.runtimeIdentifier) == "iOS" }
        if let sdkVersion, let match = iOS.first(where: { $0.version == sdkVersion }) {
            return match.identifier
        }
        return iOS.max { compareVersions($0.version, $1.version) == .orderedAscending }?.identifier
    }

    /// "17.0" < "17.4" < "26.5" < "27.0" (숫자 단위 비교)
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}
