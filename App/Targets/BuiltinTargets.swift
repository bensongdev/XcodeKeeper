import Foundation

/// PRD F1 표의 대상 정의. 새 대상은 `all`에 항목 하나만 추가하면 된다.
/// 시뮬레이터 런타임은 시뮬레이터 화면(F2)에서 다룬다.
enum BuiltinTargets {
    static let all: [CleanupTarget] = [
        derivedData, iOSDeviceSupport, otherDeviceSupport, archives, xcodeCache, swiftPMCache,
        unavailableSimulators, cocoaPodsCache, homebrewCache, localSnapshots
    ]

    static let derivedData = CleanupTarget(
        id: "derivedData",
        title: "DerivedData",
        explanation: String(localized: """
            Xcode 빌드 중간 산출물과 인덱스입니다. 지워도 안전하며, 다음 빌드 때 다시 만들어집니다. \
            지운 직후 첫 빌드와 인덱싱이 느려집니다.
            """),
        safety: .safe,
        method: .trash,
        locate: { env in
            try env.childItems(of: env.url("Library/Developer/Xcode/DerivedData")) {
                projectName(fromDerivedDataFolder: $0.lastPathComponent)
            }
        }
    )

    static let iOSDeviceSupport = CleanupTarget(
        id: "iOSDeviceSupport",
        title: "iOS DeviceSupport",
        explanation: String(localized: """
            실제 iPhone을 연결해 디버깅할 때 기기에서 복사한 심볼입니다. 버전별로 수 GB를 차지합니다. \
            지우면 그 버전 기기를 다음에 연결할 때 다시 복사하느라 몇 분 걸립니다.
            """),
        safety: .caution,
        method: .trash,
        locate: { env in try env.childItems(of: env.url("Library/Developer/Xcode/iOS DeviceSupport")) }
    )

    static let otherDeviceSupport = CleanupTarget(
        id: "otherDeviceSupport",
        title: String(localized: "watchOS/tvOS DeviceSupport"),
        explanation: String(localized: """
            Apple Watch, Apple TV 등 다른 기기의 디버깅 심볼입니다. 지우면 해당 기기를 다시 연결할 때 다시 복사합니다.
            """),
        safety: .caution,
        method: .trash,
        hideWhenEmpty: true,
        locate: { env in
            let xcode = env.url("Library/Developer/Xcode")
            let folders = (try? FileManager.default.contentsOfDirectory(atPath: xcode.path)) ?? []
            return try folders.filter(isOtherDeviceSupportFolder).sorted().flatMap { folder in
                try env.childItems(of: xcode.appending(path: folder, directoryHint: .isDirectory)) {
                    "\(folder.replacingOccurrences(of: " DeviceSupport", with: "")) \($0.lastPathComponent)"
                }
            }
        }
    )

    static let archives = CleanupTarget(
        id: "archives",
        title: "Archives",
        explanation: String(localized: """
            Xcode에서 Archive로 만든 배포용 빌드입니다. 배포한 앱의 크래시 로그를 해석하는 데 dSYM이 필요할 수 있으니 \
            배포 이력이 있는 날짜는 남겨 두세요. 다시 만들 수 없습니다.
            """),
        safety: .caution,
        method: .trash,
        locate: { env in try env.childItems(of: env.url("Library/Developer/Xcode/Archives")) }
    )

    static let xcodeCache = CleanupTarget(
        id: "xcodeCache",
        title: String(localized: "Xcode 캐시"),
        explanation: String(localized: "Xcode가 쓰는 일반 캐시입니다. 지워도 안전하며 필요하면 다시 만들어집니다."),
        safety: .safe,
        method: .trash,
        locate: { env in try env.singleItem(at: env.url("Library/Caches/com.apple.dt.Xcode")) }
    )

    static let swiftPMCache = CleanupTarget(
        id: "swiftPMCache",
        title: String(localized: "SwiftPM 캐시"),
        explanation: String(localized: """
            Swift Package Manager가 내려받은 패키지 캐시입니다. 지워도 안전하며, 다음 빌드에서 다시 받습니다(네트워크 필요).
            """),
        safety: .safe,
        method: .trash,
        locate: { env in
            try env.singleItem(at: env.url("Library/Caches/org.swift.swiftpm"), name: "Caches/org.swift.swiftpm")
                + env.singleItem(at: env.url("Library/org.swift.swiftpm"), name: "Library/org.swift.swiftpm")
        }
    )

    static let unavailableSimulators = CleanupTarget(
        id: "unavailableSimulators",
        title: String(localized: "사용 불가 시뮬레이터 기기"),
        explanation: String(localized: """
            런타임이 지워져 더 이상 실행할 수 없는 시뮬레이터 기기입니다. \
            `xcrun simctl delete unavailable`로 한 번에 지우며, 지워도 안전합니다.
            """),
        safety: .safe,
        method: .command(["simctl", "delete", "unavailable"]),
        locate: { env in
            let json = try await env.output(of: env.xcrunURL, ["simctl", "list", "devices", "unavailable", "-j"])
            let devicesRoot = env.url("Library/Developer/CoreSimulator/Devices")
            return try SimctlJSON.decodeDevices(json).devices
                .flatMap { runtime, devices in devices.map { (runtime, $0) } }
                .filter { !$0.1.isAvailable }
                .compactMap { runtime, device in
                    let folder = devicesRoot.appending(path: device.udid, directoryHint: .isDirectory)
                    let name = "\(device.name) (\(SimctlJSON.runtimeName(runtime)))"
                    return try env.singleItem(at: folder, name: name).first
                        ?? ScanItem(id: device.udid, name: name)
                }
        }
    )

    static let cocoaPodsCache = CleanupTarget(
        id: "cocoaPodsCache",
        title: String(localized: "CocoaPods 캐시"),
        explanation: String(localized: "CocoaPods가 내려받은 Pod 캐시입니다. 지워도 안전하며, 다음 `pod install`에서 다시 받습니다."),
        safety: .safe,
        method: .trash,
        hideWhenEmpty: true,
        locate: { env in try env.singleItem(at: env.url("Library/Caches/CocoaPods")) }
    )

    static let homebrewCache = CleanupTarget(
        id: "homebrewCache",
        title: String(localized: "Homebrew 캐시"),
        explanation: String(localized: """
            Homebrew가 내려받은 설치 파일 캐시입니다(`brew --cache`). 설치된 패키지에는 영향이 없고 지워도 안전합니다.
            """),
        safety: .safe,
        method: .trash,
        hideWhenEmpty: true,
        locate: { env in
            guard let brew = env.brewCandidates.first(where: {
                FileManager.default.isExecutableFile(atPath: $0.path)
            }) else { return [] }
            let path = try await env.output(of: brew, ["--cache"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return [] }
            return try env.singleItem(at: URL(fileURLWithPath: path, isDirectory: true))
        }
    )

    static let localSnapshots = CleanupTarget(
        id: "localSnapshots",
        title: String(localized: "로컬 스냅샷"),
        explanation: String(localized: """
            Time Machine과 macOS 업데이트가 만든 APFS 로컬 스냅샷입니다. 공간이 부족해지면 macOS가 스스로 정리합니다. \
            이 앱은 지우지 않습니다. 직접 지우려면 터미널에서 `tmutil listlocalsnapshots /`로 확인한 뒤 \
            `tmutil deletelocalsnapshots <날짜>`를 쓰세요.
            """),
        safety: .infoOnly,
        method: .none,
        locate: { env in
            let output = try await env.output(of: URL(fileURLWithPath: "/usr/bin/tmutil"), ["listlocalsnapshots", "/"])
            return parseLocalSnapshots(output).map { ScanItem(id: $0, name: $0) }
        }
    )

    // MARK: - 도우미 (단위 테스트 대상)

    /// `NativeStarter-ayoaannrbgybwtgvkqdmuxqqmqsv` → `NativeStarter`. 해시 꼬리(소문자 28자)가 없으면 그대로.
    static func projectName(fromDerivedDataFolder folder: String) -> String {
        guard let dash = folder.lastIndex(of: "-") else { return folder }
        let hash = folder[folder.index(after: dash)...]
        let isHash = hash.count == 28 && hash.allSatisfy { $0.isASCII && $0.isLowercase }
        return isHash && dash > folder.startIndex ? String(folder[..<dash]) : folder
    }

    /// `watchOS DeviceSupport`, `tvOS DeviceSupport` 등. iOS는 별도 대상이라 제외한다.
    static func isOtherDeviceSupportFolder(_ name: String) -> Bool {
        name.hasSuffix("OS DeviceSupport") && name != "iOS DeviceSupport"
    }

    /// `tmutil listlocalsnapshots /` 출력에서 스냅샷 이름만 뽑는다(머리글 줄 제외).
    static func parseLocalSnapshots(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.") }
    }
}
