import XCTest
@testable import XcodeKeeper

final class SimulatorInventoryTests: XCTestCase {
    private func inventory(sdk: String?) throws -> SimulatorInventory {
        SimulatorInventory.make(
            runtimes: try SimctlJSON.decodeRuntimes(try loadFixture("simctl-runtime-list")),
            devices: try SimctlJSON.decodeDevices(try loadFixture("simctl-devices-all")),
            sdkVersion: sdk
        )
    }

    func testDecodesRealRuntimeListShape() throws {
        let entries = try SimctlJSON.decodeRuntimes(try loadFixture("simctl-runtime-list"))
        XCTAssertEqual(entries.count, 3)
        let ios27 = try XCTUnwrap(entries.first { $0.version == "27.0" })
        XCTAssertEqual(ios27.identifier, "9E08F66B-9997-4064-B010-AAAB27BE9601")
        XCTAssertEqual(ios27.runtimeIdentifier, "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
        XCTAssertEqual(ios27.sizeBytes, 8_067_000_161)
        XCTAssertEqual(ios27.deletable, true)
        XCTAssertThrowsError(try SimctlJSON.decodeRuntimes("[]")) { error in
            XCTAssertEqual(error as? SimctlError, .unreadableOutput)
        }
    }

    func testRuntimesSortedBySizeDescendingWithDeviceCounts() throws {
        let runtimes = try inventory(sdk: "27.0").runtimes
        XCTAssertEqual(runtimes.map(\.displayName), ["iOS 26.5", "iOS 27.0", "watchOS 11.0"])
        XCTAssertEqual(runtimes.map(\.deviceCount), [1, 2, 0])
        XCTAssertEqual(runtimes.map(\.isDeletable), [true, true, false])
        XCTAssertEqual(runtimes[0].build, "23F77")
        XCTAssertEqual(runtimes[0].lastUsedAt, ISO8601DateFormatter().date(from: "2026-11-09T02:42:30Z"))
        XCTAssertNil(runtimes[2].lastUsedAt)
    }

    func testCurrentRuntimeMatchesSDKVersion() throws {
        let current = try inventory(sdk: "26.5").runtimes.filter(\.isCurrent).map(\.displayName)
        XCTAssertEqual(current, ["iOS 26.5"], "SDK 버전과 같은 iOS 런타임")
    }

    func testCurrentRuntimeFallsBackToHighestIOS() throws {
        XCTAssertEqual(try inventory(sdk: nil).runtimes.filter(\.isCurrent).map(\.displayName), ["iOS 27.0"])
        XCTAssertEqual(try inventory(sdk: "99.0").runtimes.filter(\.isCurrent).map(\.displayName), ["iOS 27.0"],
                       "SDK와 맞는 런타임이 없으면 가장 높은 iOS")
    }

    func testDevicesAvailableFirstAndUnavailableListed() throws {
        let devices = try inventory(sdk: "27.0").devices
        XCTAssertEqual(devices.map(\.name), ["iPad Air 13", "iPhone 18 Pro", "iPhone 17 Pro", "iPhone 14"])
        XCTAssertEqual(devices.last?.isAvailable, false)
        XCTAssertEqual(devices.last?.runtimeName, "iOS 16.4")
        XCTAssertEqual(devices.first?.state, "Booted")
        XCTAssertEqual(try inventory(sdk: nil).unavailableDevices.map(\.id), ["AAAA1111-0000-0000-0000-000000000001"])
    }

    func testVersionComparisonIsNumeric() {
        XCTAssertEqual(SimulatorInventory.compareVersions("17.4", "17.10"), .orderedAscending)
        XCTAssertEqual(SimulatorInventory.compareVersions("27.0", "26.5"), .orderedDescending)
        XCTAssertEqual(SimulatorInventory.platform(of: "com.apple.CoreSimulator.SimRuntime.xrOS-2-0"), "xrOS")
    }

    func testDeviceStateIsKorean() {
        func device(_ state: String?) -> SimDevice {
            SimDevice(id: "x", name: "x", runtimeName: "iOS 27.0", isAvailable: true, state: state, lastUsedAt: nil)
        }
        XCTAssertEqual(device("Shutdown").stateText, "꺼짐")
        XCTAssertEqual(device("Booted").stateText, "실행 중")
        XCTAssertEqual(device("Booting").stateText, "켜는 중")
        XCTAssertEqual(device("Shutting Down").stateText, "끄는 중")
        XCTAssertEqual(device("Creating").stateText, "만드는 중")
        XCTAssertEqual(device("Unknown Future State").stateText, "Unknown Future State", "모르는 상태는 원문")
        XCTAssertEqual(device(nil).stateText, "")
    }
}
