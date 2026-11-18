import XCTest
@testable import XcodeKeeper

final class SimctlClientTests: XCTestCase {
    private let runtimeUUID = "385429F5-8FC2-4504-8348-245503EDCEE3"
    private let deviceUDID = "68EEEBAF-CAE2-4AD3-AB38-31634CAB8C4D"

    func testUUIDValidation() {
        XCTAssertTrue(SimctlClient.isUUID(runtimeUUID))
        XCTAssertTrue(SimctlClient.isUUID("aaaa1111-0000-0000-0000-000000000001"))
        for bad in ["all", "--unusable", "-d", "", "385429F5-8FC2-4504-8348-245503EDCEE3 all",
                    "385429F5-8FC2-4504-8348-245503EDCEE", "unavailable", "booted",
                    "385429F5-8FC2-4504-8348-245503EDCEE3\n--all"] {
            XCTAssertFalse(SimctlClient.isUUID(bad), "통과하면 안 됨: \(bad)")
        }
    }

    func testDeleteCommandsUseExactArguments() async throws {
        let shell = FakeShell(stdout: "")
        let client = SimctlClient(shell: shell)
        try await client.deleteRuntime(runtimeUUID)
        try await client.deleteDevice(deviceUDID)
        try await client.deleteUnavailableDevices()
        XCTAssertEqual(shell.calls, [
            ["xcrun", "simctl", "runtime", "delete", runtimeUUID],
            ["xcrun", "simctl", "delete", deviceUDID],
            ["xcrun", "simctl", "delete", "unavailable"]
        ])
    }

    func testDangerousIdentifiersNeverReachSimctl() async {
        let shell = FakeShell(stdout: "")
        let client = SimctlClient(shell: shell)
        for bad in ["all", "--unusable", "--notUsedSinceDays"] {
            do {
                try await client.deleteRuntime(bad)
                XCTFail("거부해야 함: \(bad)")
            } catch {
                XCTAssertEqual(error as? SimctlError, .invalidIdentifier(bad))
            }
        }
        do {
            try await client.deleteDevice("all")
            XCTFail("거부해야 함")
        } catch {
            XCTAssertEqual(error as? SimctlError, .invalidIdentifier("all"))
        }
        XCTAssertEqual(shell.calls, [], "명령이 한 번도 실행되지 않아야 함")
    }

    func testFailureKeepsStderrVerbatim() async {
        let firstLine = "An error was encountered processing the command "
            + "(domain=com.apple.CoreSimulator.SimError, code=405):"
        let stderr = firstLine + "\nUnable to delete runtime: in use.\n"
        let client = SimctlClient(shell: FakeShell(stdout: "", exitCode: 1, stderr: stderr))
        do {
            try await client.deleteRuntime(runtimeUUID)
            XCTFail("실패해야 함")
        } catch {
            XCTAssertEqual(error as? SimctlError, .commandFailed(firstLine + "\nUnable to delete runtime: in use."))
        }
    }

    func testMissingDeveloperToolsIsDetected() async {
        let missing = "xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools)"
        let shell = FakeShell(stdout: "", exitCode: 72, stderr: missing)
        do {
            _ = try await SimctlClient(shell: shell).loadInventory()
            XCTFail("실패해야 함")
        } catch {
            guard case .toolMissing(let message) = error as? SimctlError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.hasPrefix("xcrun: error"))
        }
        let launch = FakeShell { _, _ in throw ShellError.launchFailed("no such file") }
        do {
            _ = try await SimctlClient(shell: launch).loadInventory()
            XCTFail("실패해야 함")
        } catch {
            XCTAssertEqual(error as? SimctlError, .toolMissing("no such file"))
        }
    }

    func testLoadInventoryRunsReadOnlyCommandsAndUsesSDKVersion() async throws {
        let runtimes = try loadFixture("simctl-runtime-list")
        let devices = try loadFixture("simctl-devices-all")
        let shell = FakeShell { _, arguments in
            switch arguments {
            case ["simctl", "runtime", "list", "-j"]: ShellResult(exitCode: 0, stdout: runtimes, stderr: "")
            case ["simctl", "list", "devices", "-j"]: ShellResult(exitCode: 0, stdout: devices, stderr: "")
            case ["--sdk", "iphonesimulator", "--show-sdk-version"]:
                ShellResult(exitCode: 0, stdout: "26.5\n", stderr: "")
            default: ShellResult(exitCode: 1, stdout: "", stderr: "unexpected")
            }
        }
        let inventory = try await SimctlClient(shell: shell).loadInventory()
        XCTAssertEqual(shell.calls.map { Array($0.dropFirst()) }, [
            ["simctl", "runtime", "list", "-j"],
            ["simctl", "list", "devices", "-j"],
            ["--sdk", "iphonesimulator", "--show-sdk-version"]
        ])
        XCTAssertEqual(inventory.runtimes.first { $0.isCurrent }?.version, "26.5")
        XCTAssertEqual(inventory.devices.count, 4)
    }

    func testUnreadableDevicesJSON() async {
        let shell = FakeShell { _, arguments in
            arguments.contains("runtime") ? ShellResult(exitCode: 0, stdout: "{}", stderr: "")
                : ShellResult(exitCode: 0, stdout: "garbage", stderr: "")
        }
        do {
            _ = try await SimctlClient(shell: shell).loadInventory()
            XCTFail("실패해야 함")
        } catch {
            XCTAssertEqual(error as? SimctlError, .unreadableOutput)
        }
    }
}
