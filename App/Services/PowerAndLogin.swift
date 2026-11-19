import Foundation
import IOKit.ps
import ServiceManagement

/// 저전력 모드와 배터리 잔량.
protocol PowerStateProviding: Sendable {
    func current() -> PowerState
}

struct SystemPowerState: PowerStateProviding {
    func current() -> PowerState {
        PowerState(isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, batteryPercent: Self.batteryPercent())
    }

    /// 내장 배터리 잔량(%). 배터리가 없으면 nil.
    private static func batteryPercent() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return current * 100 / max
        }
        return nil
    }
}

struct FixedPowerState: PowerStateProviding {
    var state = PowerState(isLowPowerMode: false, batteryPercent: nil)

    func current() -> PowerState { state }
}

/// 로그인 시 실행 상태.
enum LoginItemStatus: Sendable, Equatable {
    case enabled
    case disabled
    /// 등록했지만 사용자가 시스템 설정에서 허용해야 한다.
    case requiresApproval
}

protocol LoginItemControlling: Sendable {
    func status() -> LoginItemStatus
    func setEnabled(_ enabled: Bool) throws
}

/// `SMAppService.mainApp`으로 이 앱을 로그인 항목에 등록한다.
struct SystemLoginItem: LoginItemControlling {
    func status() -> LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// 상태만 바꾸는 가짜. `failure`가 있으면 그 오류로 실패한다.
final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var current: LoginItemStatus
    private let failure: (any Error)?
    private let requiresApprovalOnEnable: Bool

    init(status: LoginItemStatus = .disabled, failure: (any Error)? = nil, requiresApprovalOnEnable: Bool = false) {
        self.current = status
        self.failure = failure
        self.requiresApprovalOnEnable = requiresApprovalOnEnable
    }

    func status() -> LoginItemStatus { lock.withLock { current } }

    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        lock.withLock {
            current = enabled ? (requiresApprovalOnEnable ? .requiresApproval : .enabled) : .disabled
        }
    }
}
