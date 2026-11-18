import XCTest
@testable import XcodeKeeper

final class AppStateTests: XCTestCase {
    func testFixedDiskSpaceProvider() {
        XCTAssertEqual(FixedDiskSpaceProvider(bytes: 42).availableBytes(), 42)
        XCTAssertNil(FixedDiskSpaceProvider(bytes: nil).availableBytes())
    }

    @MainActor
    func testAppStateReadsDiskSpaceOnInit() {
        let state = AppState(diskSpace: FixedDiskSpaceProvider(bytes: 16_200_000_000))
        XCTAssertEqual(state.availableBytes, 16_200_000_000)
        XCTAssertEqual(state.selectedSection, .junk)
    }

    func testLaunchConfigurationReadsUITestArguments() {
        let defaults = UserDefaults(suiteName: "AppStateTests.\(UUID().uuidString)")!
        XCTAssertFalse(LaunchConfiguration.current(defaults).isUITest)
        defaults.set(true, forKey: LaunchConfiguration.uiTestModeKey)
        defaults.set("scanner", forKey: LaunchConfiguration.openWindowKey)
        let config = LaunchConfiguration.current(defaults)
        XCTAssertTrue(config.isUITest)
        XCTAssertEqual(config.windowToOpen, "scanner")
    }
}
