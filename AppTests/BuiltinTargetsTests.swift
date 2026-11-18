import XCTest
@testable import XcodeKeeper

final class BuiltinTargetsTests: XCTestCase {
    // MARK: - 정의 유효성

    func testTargetDefinitionsAreValid() {
        let ids = BuiltinTargets.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "대상 id가 중복됨")
        XCTAssertEqual(ids, [
            "derivedData", "iOSDeviceSupport", "otherDeviceSupport", "archives", "xcodeCache", "swiftPMCache",
            "unavailableSimulators", "cocoaPodsCache", "homebrewCache", "localSnapshots"
        ])
        for target in BuiltinTargets.all {
            XCTAssertFalse(target.title.isEmpty, target.id)
            XCTAssertFalse(target.explanation.isEmpty, target.id)
        }
    }

    func testSafetyAndMethodMatchPRD() {
        func check(_ target: CleanupTarget, _ safety: Safety, _ method: CleanupMethod, hide: Bool = false) {
            XCTAssertEqual(target.safety, safety, target.id)
            XCTAssertEqual(target.method, method, target.id)
            XCTAssertEqual(target.hideWhenEmpty, hide, target.id)
        }
        check(BuiltinTargets.derivedData, .safe, .trash)
        check(BuiltinTargets.iOSDeviceSupport, .caution, .trash)
        check(BuiltinTargets.otherDeviceSupport, .caution, .trash, hide: true)
        check(BuiltinTargets.archives, .caution, .trash)
        check(BuiltinTargets.xcodeCache, .safe, .trash)
        check(BuiltinTargets.swiftPMCache, .safe, .trash)
        check(BuiltinTargets.unavailableSimulators, .safe, .command(["simctl", "delete", "unavailable"]))
        check(BuiltinTargets.cocoaPodsCache, .safe, .trash, hide: true)
        check(BuiltinTargets.homebrewCache, .safe, .trash, hide: true)
        check(BuiltinTargets.localSnapshots, .infoOnly, .none)
    }

    func testDefaultSelectionRules() {
        XCTAssertTrue(BuiltinTargets.derivedData.isSelectedByDefault)
        XCTAssertFalse(BuiltinTargets.iOSDeviceSupport.isSelectedByDefault)
        XCTAssertFalse(BuiltinTargets.archives.isSelectedByDefault)
        XCTAssertFalse(BuiltinTargets.localSnapshots.isSelectable)
        XCTAssertFalse(BuiltinTargets.localSnapshots.isSelectedByDefault)
        XCTAssertTrue(BuiltinTargets.unavailableSimulators.selectsAsGroup)
        XCTAssertFalse(BuiltinTargets.derivedData.selectsAsGroup)
    }

    // MARK: - 도우미

    func testProjectNameStripsDerivedDataHash() {
        XCTAssertEqual(BuiltinTargets.projectName(fromDerivedDataFolder: "NativeStarter-ayoaannrbgybwtgvkqdmuxqqmqsv"),
                       "NativeStarter")
        XCTAssertEqual(
            BuiltinTargets.projectName(fromDerivedDataFolder: "My-App-ayoaannrbgybwtgvkqdmuxqqmqsv"), "My-App"
        )
        XCTAssertEqual(BuiltinTargets.projectName(fromDerivedDataFolder: "ModuleCache.noindex"), "ModuleCache.noindex")
        XCTAssertEqual(BuiltinTargets.projectName(fromDerivedDataFolder: "Foo-short"), "Foo-short")
        XCTAssertEqual(BuiltinTargets.projectName(fromDerivedDataFolder: "-ayoaannrbgybwtgvkqdmuxqqmqsv"),
                       "-ayoaannrbgybwtgvkqdmuxqqmqsv")
    }

    func testOtherDeviceSupportFolderMatching() {
        XCTAssertTrue(BuiltinTargets.isOtherDeviceSupportFolder("watchOS DeviceSupport"))
        XCTAssertTrue(BuiltinTargets.isOtherDeviceSupportFolder("tvOS DeviceSupport"))
        XCTAssertFalse(BuiltinTargets.isOtherDeviceSupportFolder("iOS DeviceSupport"))
        XCTAssertFalse(BuiltinTargets.isOtherDeviceSupportFolder("DerivedData"))
    }

    func testParseLocalSnapshots() {
        let output = """
            Snapshots for volume group containing disk /:
            com.apple.os.update-6058742
            com.apple.TimeMachine.2026-11-18-090000.local

            """
        XCTAssertEqual(BuiltinTargets.parseLocalSnapshots(output),
                       ["com.apple.os.update-6058742", "com.apple.TimeMachine.2026-11-18-090000.local"])
        XCTAssertEqual(BuiltinTargets.parseLocalSnapshots("Snapshots for disk /:\n"), [])
    }

    func testSimctlRuntimeNameAndDecoding() throws {
        XCTAssertEqual(SimctlJSON.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-17-0"), "iOS 17.0")
        XCTAssertEqual(SimctlJSON.runtimeName("com.apple.CoreSimulator.SimRuntime.watchOS-11-2"), "watchOS 11.2")
        let list = try SimctlJSON.decodeDevices(try loadFixture("simctl-devices-unavailable"))
        let devices = list.devices["com.apple.CoreSimulator.SimRuntime.iOS-17-0"] ?? []
        XCTAssertEqual(devices.map(\.name), ["iPhone 15", "iPad Air"])
        XCTAssertEqual(devices.map(\.isAvailable), [false, false])
        XCTAssertEqual(list.devices["com.apple.CoreSimulator.SimRuntime.iOS-27-0"], [])
        XCTAssertThrowsError(try SimctlJSON.decodeDevices("not json"))
    }

    // MARK: - 임시 홈에서 찾기 (통합)

    func testDerivedDataItemsInFakeHome() async throws {
        let home = try TemporaryDirectory()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let derived = "Library/Developer/Xcode/DerivedData"
        let hash = "abcdefghijklmnopqrstuvwxyzab"
        try home.makeFile("\(derived)/Big-\(hash)/b.bin", bytes: 2_000_000)
        try home.makeFile("\(derived)/Small-\(hash)/s.bin", bytes: 100_000)
        try home.makeFile("\(derived)/.DS_Store", bytes: 10)
        try FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: home.url.appending(path: "\(derived)/Big-\(hash)").path
        )

        let items = try await BuiltinTargets.derivedData.locate(makeEnvironment(home: home.url))
            .sorted { $0.bytes > $1.bytes }
        XCTAssertEqual(items.map(\.name), ["Big", "Small"], "숨김 파일은 제외되어야 함")
        XCTAssertGreaterThanOrEqual(items[0].bytes, 2_000_000)
        XCTAssertEqual(items[0].lastModified, date)
        XCTAssertEqual(items[0].url?.lastPathComponent, "Big-abcdefghijklmnopqrstuvwxyzab")
    }

    func testMissingFoldersYieldNoItems() async throws {
        let home = try TemporaryDirectory()
        let env = makeEnvironment(home: home.url)
        let targets: [CleanupTarget] = [
            BuiltinTargets.derivedData, BuiltinTargets.iOSDeviceSupport, BuiltinTargets.otherDeviceSupport,
            BuiltinTargets.archives, BuiltinTargets.xcodeCache, BuiltinTargets.swiftPMCache,
            BuiltinTargets.cocoaPodsCache
        ]
        for target in targets {
            let items = try await target.locate(env)
            XCTAssertEqual(items, [], target.id)
        }
    }

    func testDeviceSupportAndCaches() async throws {
        let home = try TemporaryDirectory()
        try home.makeFile("Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 18.1 (22B83)/sym", bytes: 1_000)
        try home.makeFile("Library/Developer/Xcode/watchOS DeviceSupport/Watch7,1 11.0 (22R)/sym", bytes: 1_000)
        try home.makeFile("Library/Caches/org.swift.swiftpm/repo", bytes: 1_000)
        try home.makeFile("Library/org.swift.swiftpm/config", bytes: 1_000)
        try home.makeFile("Library/Caches/com.apple.dt.Xcode/cache.db", bytes: 1_000)
        let env = makeEnvironment(home: home.url)

        let ios = try await BuiltinTargets.iOSDeviceSupport.locate(env)
        XCTAssertEqual(ios.map(\.name), ["iPhone15,2 18.1 (22B83)"])
        let other = try await BuiltinTargets.otherDeviceSupport.locate(env)
        XCTAssertEqual(other.map(\.name), ["watchOS Watch7,1 11.0 (22R)"])
        let swiftPM = try await BuiltinTargets.swiftPMCache.locate(env)
        XCTAssertEqual(swiftPM.map(\.name), ["Caches/org.swift.swiftpm", "Library/org.swift.swiftpm"])
        let xcode = try await BuiltinTargets.xcodeCache.locate(env)
        XCTAssertEqual(xcode.count, 1)
    }

    func testUnavailableSimulatorsUsesSimctlAndDeviceFolders() async throws {
        let home = try TemporaryDirectory()
        try home.makeFile(
            "Library/Developer/CoreSimulator/Devices/AAAA1111-0000-0000-0000-000000000001/data/file", bytes: 500_000
        )
        let shell = FakeShell(stdout: try loadFixture("simctl-devices-unavailable"))

        let items = try await BuiltinTargets.unavailableSimulators.locate(makeEnvironment(home: home.url, shell: shell))
            .sorted { $0.bytes > $1.bytes }
        XCTAssertEqual(shell.calls, [["xcrun", "simctl", "list", "devices", "unavailable", "-j"]])
        XCTAssertEqual(items.map(\.name), ["iPhone 15 (iOS 17.0)", "iPad Air (iOS 17.0)"])
        XCTAssertGreaterThanOrEqual(items[0].bytes, 500_000)
        XCTAssertNotNil(items[0].url)
        XCTAssertEqual(items[1].bytes, 0, "폴더가 없는 기기는 용량 0으로 표시")
    }

    func testCommandFailureIsReportedWithStderr() async throws {
        let home = try TemporaryDirectory()
        let shell = FakeShell(stdout: "", exitCode: 72, stderr: "xcrun: error: invalid active developer path\n")
        do {
            _ = try await BuiltinTargets.unavailableSimulators.locate(makeEnvironment(home: home.url, shell: shell))
            XCTFail("실패해야 합니다")
        } catch {
            XCTAssertEqual(error as? ScanFailure, .commandFailed("xcrun: error: invalid active developer path"))
        }
    }

    func testHomebrewCacheOnlyWhenBrewExists() async throws {
        let home = try TemporaryDirectory()
        let cache = try home.makeDirectory("BrewCache")
        try home.makeFile("BrewCache/bottle.tar.gz", bytes: 300_000)
        let shell = FakeShell(stdout: cache.path + "\n")

        var env = makeEnvironment(home: home.url, shell: shell)
        env.brewCandidates = [home.url.appending(path: "no-brew")]
        let none = try await BuiltinTargets.homebrewCache.locate(env)
        XCTAssertEqual(none, [])
        XCTAssertEqual(shell.calls, [], "brew가 없으면 실행하지 않음")

        let brew = try home.makeFile("bin/brew", bytes: 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        env.brewCandidates = [brew]
        let items = try await BuiltinTargets.homebrewCache.locate(env)
        XCTAssertEqual(shell.calls, [["brew", "--cache"]])
        XCTAssertEqual(items.map(\.name), ["BrewCache"])
        XCTAssertGreaterThanOrEqual(items.first?.bytes ?? 0, 300_000)
    }

    func testLocalSnapshotsAreInfoItems() async throws {
        let home = try TemporaryDirectory()
        let shell = FakeShell(stdout: "Snapshots for disk /:\ncom.apple.TimeMachine.2026-11-18-090000.local\n")
        let items = try await BuiltinTargets.localSnapshots.locate(makeEnvironment(home: home.url, shell: shell))
        XCTAssertEqual(shell.calls, [["tmutil", "listlocalsnapshots", "/"]])
        XCTAssertEqual(items.map(\.name), ["com.apple.TimeMachine.2026-11-18-090000.local"])
        XCTAssertNil(items.first?.url)
    }
}
