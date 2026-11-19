import Foundation
import Observation

/// 사용자 설정. 값을 바꾸면 바로 UserDefaults에 저장한다.
/// UI 테스트·단위 테스트·스냅샷은 실제 사용자 설정 대신 `ephemeral()` 저장소를 쓴다.
@MainActor
@Observable
final class AppSettings {
    enum Key {
        // M0부터 쓰던 키를 그대로 쓴다(마이그레이션 없음).
        static let showFreeSpaceInMenuBar = "showFreeSpaceInMenuBar"
        static let freeSpaceThresholdGB = "freeSpaceThresholdGB"
        static let swapThresholdGB = "swapThresholdGB"
        static let backgroundScanEnabled = "backgroundScanEnabled"
        static let lastFreeSpaceAlertAt = "lastFreeSpaceAlertAt"
    }

    static let freeSpaceThresholdRange = 5...200
    static let swapThresholdRange = 1...32

    @ObservationIgnored let defaults: UserDefaults

    var showFreeSpaceInMenuBar: Bool {
        didSet { defaults.set(showFreeSpaceInMenuBar, forKey: Key.showFreeSpaceInMenuBar) }
    }
    var freeSpaceThresholdGB: Int {
        didSet { defaults.set(freeSpaceThresholdGB, forKey: Key.freeSpaceThresholdGB) }
    }
    var swapThresholdGB: Int {
        didSet { defaults.set(swapThresholdGB, forKey: Key.swapThresholdGB) }
    }
    var backgroundScanEnabled: Bool {
        didSet { defaults.set(backgroundScanEnabled, forKey: Key.backgroundScanEnabled) }
    }
    /// 마지막 여유 공간 알림 시각(24시간 쿨다운).
    var lastFreeSpaceAlertAt: Date? {
        didSet { defaults.set(lastFreeSpaceAlertAt, forKey: Key.lastFreeSpaceAlertAt) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showFreeSpaceInMenuBar: true,
            Key.freeSpaceThresholdGB: 30,
            Key.swapThresholdGB: 2,
            Key.backgroundScanEnabled: true
        ])
        showFreeSpaceInMenuBar = defaults.bool(forKey: Key.showFreeSpaceInMenuBar)
        freeSpaceThresholdGB = Self.clamp(
            defaults.integer(forKey: Key.freeSpaceThresholdGB), Self.freeSpaceThresholdRange
        )
        swapThresholdGB = Self.clamp(defaults.integer(forKey: Key.swapThresholdGB), Self.swapThresholdRange)
        backgroundScanEnabled = defaults.bool(forKey: Key.backgroundScanEnabled)
        lastFreeSpaceAlertAt = defaults.object(forKey: Key.lastFreeSpaceAlertAt) as? Date
    }

    var freeSpaceThresholdBytes: Int64 { Int64(freeSpaceThresholdGB) * 1_000_000_000 }
    var swapThresholdBytes: Int64 { Int64(swapThresholdGB) * 1_000_000_000 }

    /// 실행할 때마다 비워지는 테스트용 저장소. 실제 사용자 설정(앱 도메인)은 건드리지 않는다.
    static func ephemeral(suiteName: String = "com.bensongdev.XcodeKeeper.ephemeral") -> AppSettings {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
