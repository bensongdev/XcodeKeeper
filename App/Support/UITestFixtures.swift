import Foundation

/// UI 테스트(`-UITestMode YES`)용 가짜 대상. 실제 대상과 id·제목·안전도·정리 방식이 같고,
/// `locate`는 디스크나 명령을 건드리지 않고 고정된 항목을 돌려준다.
/// Archives는 일부러 늦게 끝나 "스캔 중" 상태를 찍을 수 있게 한다.
enum UITestFixtures {
    static let slowTargetDelay: Duration = .seconds(3)
    private static let root = URL(fileURLWithPath: "/private/tmp/XcodeKeeperUITestFixtures", isDirectory: true)
    private static let referenceDate = Date(timeIntervalSince1970: 1_794_000_000) // 2026-11

    static let environment = ScanEnvironment(home: root, sizes: SizeCalculator(), shell: ShellRunner())

    static let targets: [CleanupTarget] = BuiltinTargets.all.map { target in
        let items = fixtureItems[target.id] ?? []
        let delay = target.id == BuiltinTargets.archives.id ? slowTargetDelay : nil
        return CleanupTarget(
            id: target.id, title: target.title, explanation: target.explanation, safety: target.safety,
            method: target.method, hideWhenEmpty: target.hideWhenEmpty,
            locate: { _ in
                if let delay { try await Task.sleep(for: delay) }
                return items
            }
        )
    }

    private static func item(_ path: String, _ name: String, _ bytes: Int64, daysAgo: Double) -> ScanItem {
        ScanItem(
            url: root.appending(path: path), name: name, bytes: bytes,
            lastModified: referenceDate.addingTimeInterval(-daysAgo * 86_400)
        )
    }

    /// 기본 선택 합계(안전): DerivedData 4.3 + Xcode 0.6 + SwiftPM 0.3 + 사용 불가 기기 1.5 + Homebrew 0.2 = 6.9GB
    static let expectedDefaultSelectedBytes: Int64 = 6_900_000_000

    private static let fixtureItems: [String: [ScanItem]] = [
        "derivedData": [
            item("DerivedData/XcodeKeeper-abc", "XcodeKeeper", 3_200_000_000, daysAgo: 0),
            item("DerivedData/HelloMac-def", "HelloMac", 1_100_000_000, daysAgo: 12)
        ],
        "iOSDeviceSupport": [
            item("iOS DeviceSupport/iPhone15,2 18.1 (22B83)", "iPhone15,2 18.1 (22B83)", 2_800_000_000, daysAgo: 60)
        ],
        "archives": [item("Archives/2026-10-01", "2026-10-01", 450_000_000, daysAgo: 48)],
        "xcodeCache": [item("Caches/com.apple.dt.Xcode", "com.apple.dt.Xcode", 600_000_000, daysAgo: 1)],
        "swiftPMCache": [item("Caches/org.swift.swiftpm", "Caches/org.swift.swiftpm", 300_000_000, daysAgo: 3)],
        "unavailableSimulators": [
            item("Devices/A", "iPhone 15 (iOS 17.0)", 900_000_000, daysAgo: 200),
            item("Devices/B", "iPad Air (iOS 17.0)", 600_000_000, daysAgo: 210)
        ],
        "homebrewCache": [item("Caches/Homebrew", "Homebrew", 200_000_000, daysAgo: 5)],
        "localSnapshots": [
            ScanItem(id: "snap1", name: "com.apple.TimeMachine.2026-11-18-090000.local"),
            ScanItem(id: "snap2", name: "com.apple.os.update-ABC")
        ]
    ]
}
