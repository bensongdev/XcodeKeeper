import XCTest
@testable import XcodeKeeper

final class FreeSpaceAlertTests: XCTestCase {
    private let gb: Int64 = 1_000_000_000
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    func testShouldNotifyBelowThresholdWithCooldown() {
        func should(_ available: Int64?, lastSent: Date?) -> Bool {
            FreeSpaceAlert.shouldNotify(
                availableBytes: available, thresholdBytes: 30 * gb, lastSentAt: lastSent, now: now
            )
        }
        XCTAssertTrue(should(16 * gb, lastSent: nil))
        XCTAssertFalse(should(30 * gb, lastSent: nil), "기준과 같으면 보내지 않음")
        XCTAssertFalse(should(nil, lastSent: nil), "읽지 못하면 보내지 않음")
        XCTAssertFalse(should(16 * gb, lastSent: now.addingTimeInterval(-(24 * 3600 - 1))), "24시간 안")
        XCTAssertTrue(should(16 * gb, lastSent: now.addingTimeInterval(-24 * 3600)), "정확히 24시간 뒤")
        XCTAssertTrue(should(16 * gb, lastSent: now.addingTimeInterval(-48 * 3600)))
    }

    func testContentListsTopTwo() {
        let top = [
            CleanableSummary(targetID: "derivedData", title: "DerivedData", bytes: 4_200_000_000),
            CleanableSummary(targetID: "simulatorCaches", title: "시뮬레이터 캐시", bytes: 1_100_000_000),
            CleanableSummary(targetID: "spm", title: "SwiftPM 캐시", bytes: 900_000_000)
        ]
        let content = FreeSpaceAlert.content(availableBytes: 16_200_000_000, top: top)
        XCTAssertEqual(content.title, "여유 공간이 16.2GB 남았습니다")
        XCTAssertEqual(content.body, "정리 가능: DerivedData 4.2GB, 시뮬레이터 캐시 1.1GB")
        XCTAssertEqual(content.targetIDs, ["derivedData", "simulatorCaches"])

        let empty = FreeSpaceAlert.content(availableBytes: 16_200_000_000, top: [])
        XCTAssertEqual(empty.body, "스캐너에서 정리할 항목을 확인하세요")
        XCTAssertEqual(empty.targetIDs, [])
    }

    func testShortageText() {
        XCTAssertEqual(FreeSpaceAlert.shortageText(availableBytes: 16_200_000_000, thresholdBytes: 30 * gb),
                       "업데이트까지 약 14GB 부족", "13.8GB는 반올림해 14GB")
        XCTAssertEqual(FreeSpaceAlert.shortageText(availableBytes: 29_900_000_000, thresholdBytes: 30 * gb),
                       "업데이트까지 약 1GB 부족", "1GB 미만도 최소 1GB로 표시")
        XCTAssertNil(FreeSpaceAlert.shortageText(availableBytes: 30 * gb, thresholdBytes: 30 * gb))
        XCTAssertNil(FreeSpaceAlert.shortageText(availableBytes: nil, thresholdBytes: 30 * gb))
    }

    func testTopCleanableSkipsInfoOnlyUnscannedAndEmpty() {
        let big = makeTarget("big", safety: .caution)
        let small = makeTarget("small")
        let info = makeTarget("info", safety: .infoOnly, method: .none)
        let empty = makeTarget("empty")
        let unscanned = makeTarget("unscanned")
        var results = ScanResults(targets: [small, big, info, empty, unscanned])
        results.beginScan()
        results.apply(.finished(targetID: "big", items: [makeItem("b1", bytes: 700), makeItem("b2", bytes: 300)]))
        results.apply(.finished(targetID: "small", items: [makeItem("s", bytes: 200)]))
        results.apply(.finished(targetID: "info", items: [makeItem("i", bytes: 5_000)]))
        results.apply(.finished(targetID: "empty", items: []))
        XCTAssertEqual(results.topCleanable(limit: 3).map(\.targetID), ["big", "small"])
        XCTAssertEqual(results.topCleanable(limit: 3).first?.bytes, 1_000)
        XCTAssertEqual(results.topCleanable(limit: 1).map(\.targetID), ["big"])
    }

    func testPowerStateSkipRules() {
        XCTAssertFalse(PowerState(isLowPowerMode: false, batteryPercent: nil).shouldSkipBackgroundWork, "배터리 없는 Mac")
        XCTAssertFalse(PowerState(isLowPowerMode: false, batteryPercent: 21).shouldSkipBackgroundWork)
        XCTAssertTrue(PowerState(isLowPowerMode: false, batteryPercent: 20).shouldSkipBackgroundWork, "20% 이하")
        XCTAssertTrue(PowerState(isLowPowerMode: true, batteryPercent: 90).shouldSkipBackgroundWork, "저전력 모드")
        XCTAssertTrue(PowerState(isLowPowerMode: true, batteryPercent: nil).shouldSkipBackgroundWork)
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    private let suite = "com.bensongdev.XcodeKeeper.AppSettingsTests"

    override func tearDown() async throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    func testDefaultsPersistenceAndClamping() throws {
        let settings = AppSettings.ephemeral(suiteName: suite)
        XCTAssertTrue(settings.showFreeSpaceInMenuBar)
        XCTAssertEqual(settings.freeSpaceThresholdGB, 30)
        XCTAssertEqual(settings.swapThresholdGB, 2)
        XCTAssertTrue(settings.backgroundScanEnabled)
        XCTAssertNil(settings.lastFreeSpaceAlertAt)
        XCTAssertEqual(settings.freeSpaceThresholdBytes, 30_000_000_000)

        let sent = Date(timeIntervalSince1970: 1_794_000_000)
        settings.freeSpaceThresholdGB = 45
        settings.swapThresholdGB = 4
        settings.backgroundScanEnabled = false
        settings.showFreeSpaceInMenuBar = false
        settings.lastFreeSpaceAlertAt = sent

        let reloaded = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(reloaded.freeSpaceThresholdGB, 45)
        XCTAssertEqual(reloaded.swapThresholdGB, 4)
        XCTAssertFalse(reloaded.backgroundScanEnabled)
        XCTAssertFalse(reloaded.showFreeSpaceInMenuBar)
        XCTAssertEqual(reloaded.lastFreeSpaceAlertAt, sent)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(999, forKey: AppSettings.Key.freeSpaceThresholdGB)
        defaults.set(0, forKey: AppSettings.Key.swapThresholdGB)
        let clamped = AppSettings(defaults: defaults)
        XCTAssertEqual(clamped.freeSpaceThresholdGB, 200, "범위 밖 값은 범위 안으로")
        XCTAssertEqual(clamped.swapThresholdGB, 1)
    }

    func testEphemeralStartsEmpty() {
        let first = AppSettings.ephemeral(suiteName: suite)
        first.freeSpaceThresholdGB = 50
        XCTAssertEqual(AppSettings.ephemeral(suiteName: suite).freeSpaceThresholdGB, 30, "실행마다 비워짐")
    }
}
