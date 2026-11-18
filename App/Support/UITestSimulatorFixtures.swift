import Foundation

extension UITestFixtures {
    /// 실제 simctl을 실행하지 않는 가짜 시뮬레이터 관리자(UI 테스트 전용).
    /// 실제 `simctl runtime list -j` / `list devices -j` 형식의 값을 `SimulatorInventory.make`로 만들고,
    /// 삭제하면 메모리 목록에서만 뺀다. SDK 버전은 27.0으로 둔다.
    final class FakeSimulatorManager: SimulatorManaging, @unchecked Sendable {
        /// 삭제 실패 시 보여 줄 stderr(가짜 데이터).
        static let deleteFailureStderr = """
            An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):
            Unable to delete runtime: the runtime is in use by a booted device.
            """
        static let missingToolMessage =
            "xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools)"

        private let lock = NSLock()
        private let scenario: String?
        private var runtimes = FakeSimulatorManager.initialRuntimes
        private var devices = FakeSimulatorManager.initialDevices

        init(scenario: String?) {
            self.scenario = scenario
        }

        func loadInventory() async throws -> SimulatorInventory {
            try await Task.sleep(for: .milliseconds(200))
            if scenario == "missing" { throw SimctlError.toolMissing(Self.missingToolMessage) }
            return lock.withLock {
                SimulatorInventory.make(runtimes: runtimes, devices: SimctlJSON.DeviceList(devices: devices),
                                        sdkVersion: "27.0")
            }
        }

        func deleteRuntime(_ identifier: String) async throws {
            try await Task.sleep(for: .milliseconds(200))
            if scenario == "deleteFails" { throw SimctlError.commandFailed(Self.deleteFailureStderr) }
            lock.withLock { runtimes.removeAll { $0.identifier == identifier } }
        }

        func deleteDevice(_ udid: String) async throws {
            try await Task.sleep(for: .milliseconds(200))
            lock.withLock {
                for key in devices.keys { devices[key]?.removeAll { $0.udid == udid } }
            }
        }

        func deleteUnavailableDevices() async throws {
            try await Task.sleep(for: .milliseconds(200))
            lock.withLock {
                for key in devices.keys { devices[key]?.removeAll { !$0.isAvailable } }
            }
        }

        private static func runtime(
            _ uuid: String, _ runtime: String, _ version: String, _ build: String, _ size: Int64
        ) -> SimctlJSON.RuntimeEntry {
            SimctlJSON.RuntimeEntry(
                identifier: uuid, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.\(runtime)",
                version: version, build: build, sizeBytes: size, deletable: true,
                lastUsedAt: "2026-11-09T06:33:21Z", state: "Ready"
            )
        }

        private static func device(_ udid: String, _ name: String, available: Bool = true) -> SimctlJSON.Device {
            SimctlJSON.Device(udid: udid, name: name, isAvailable: available, dataPath: nil,
                              lastUsedAt: "2026-11-09T06:33:20Z", state: "Shutdown")
        }

        // 정렬 결과(용량 내림차순): iOS 26.5(8.4GB) > iOS 27.0(8.0GB, 현재 사용 중) > iOS 17.0(7.0GB) > watchOS 11.0(3.2GB)
        private static let initialRuntimes = [
            runtime("9E08F66B-9997-4064-B010-AAAB27BE9601", "iOS-27-0", "27.0", "24A434", 8_067_000_161),
            runtime("385429F5-8FC2-4504-8348-245503EDCEE3", "iOS-26-5", "26.5", "23F77", 8_494_282_293),
            runtime("11111111-2222-3333-4444-555555555555", "iOS-17-0", "17.0", "21A328", 7_012_000_000),
            // 삭제할 수 없는 런타임
            SimctlJSON.RuntimeEntry(
                identifier: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.watchOS-11-0", version: "11.0",
                build: "22R349", sizeBytes: 3_200_000_000, deletable: false,
                lastUsedAt: "2026-05-01T09:00:00Z", state: "Ready"
            )
        ]

        private static let initialDevices: [String: [SimctlJSON.Device]] = [
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                device("1C9A210B-DB3E-403E-AC4F-1E7F9AA350D9", "iPhone 18 Pro"),
                device("2C9A210B-DB3E-403E-AC4F-1E7F9AA350D9", "iPad Air 13")
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                device("68EEEBAF-CAE2-4AD3-AB38-31634CAB8C4D", "iPhone 17 Pro")
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-16-4": [
                device("AAAA1111-0000-0000-0000-000000000001", "iPhone 14", available: false),
                device("AAAA1111-0000-0000-0000-000000000002", "iPhone SE", available: false)
            ]
        ]
    }
}
