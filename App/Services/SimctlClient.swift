import Foundation

/// `xcrun simctl ... -j` 출력 디코딩.
enum SimctlJSON {
    struct DeviceList: Decodable, Sendable {
        /// 런타임 식별자 → 기기 목록
        let devices: [String: [Device]]
    }

    struct Device: Decodable, Sendable, Equatable {
        let udid: String
        let name: String
        let isAvailable: Bool
        let dataPath: String?
        let lastUsedAt: String?
        /// "Shutdown", "Booted" 등
        var state: String?
    }

    /// `simctl runtime list -j`: 이미지 UUID → 런타임
    struct RuntimeEntry: Decodable, Sendable, Equatable {
        let identifier: String
        let runtimeIdentifier: String
        let version: String
        let build: String?
        let sizeBytes: Int64?
        let deletable: Bool?
        let lastUsedAt: String?
        let state: String?
    }

    static func decodeRuntimes(_ json: String) throws -> [RuntimeEntry] {
        do {
            return Array(try JSONDecoder().decode([String: RuntimeEntry].self, from: Data(json.utf8)).values)
        } catch {
            throw SimctlError.unreadableOutput
        }
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    static func decodeDevices(_ json: String) throws -> DeviceList {
        do {
            return try JSONDecoder().decode(DeviceList.self, from: Data(json.utf8))
        } catch {
            throw ScanFailure.other(String(localized: "simctl 출력을 읽지 못했습니다"))
        }
    }

    /// 런타임 식별자를 읽기 쉬운 이름으로: `com.apple.CoreSimulator.SimRuntime.iOS-17-0` → `iOS 17.0`
    static func runtimeName(_ identifier: String) -> String {
        let suffix = identifier.split(separator: ".").last.map(String.init) ?? identifier
        var parts = suffix.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return suffix }
        let platform = parts.removeFirst()
        return "\(platform) \(parts.joined(separator: "."))"
    }
}

/// simctl 실패 원인.
enum SimctlError: Error, Sendable, Equatable {
    /// Xcode/개발자 도구가 없거나 선택되지 않음. 원문 메시지를 담는다.
    case toolMissing(String)
    /// 명령이 0이 아닌 코드로 끝남. stderr 원문(앞뒤 공백 제거)을 담는다.
    case commandFailed(String)
    /// JSON을 읽지 못함.
    case unreadableOutput
    /// UUID 형식이 아닌 identifier/UDID. 명령을 실행하지 않았다.
    case invalidIdentifier(String)

    var message: String {
        switch self {
        case .toolMissing(let detail), .commandFailed(let detail): detail
        case .unreadableOutput: String(localized: "simctl 출력을 읽지 못했습니다")
        case .invalidIdentifier(let value): String(localized: "올바르지 않은 식별자: \(value)")
        }
    }
}

/// 시뮬레이터 목록과 삭제. UI 테스트에서는 가짜 구현을 쓴다.
protocol SimulatorManaging: Sendable {
    func loadInventory() async throws -> SimulatorInventory
    func deleteRuntime(_ identifier: String) async throws
    func deleteDevice(_ udid: String) async throws
    func deleteUnavailableDevices() async throws
}

/// `xcrun simctl` 래퍼. 삭제 명령의 인자는 UUID 형식만 허용한다
/// (`simctl runtime delete all`은 모든 런타임을 지우고, `--unusable` 같은 옵션도 받기 때문).
struct SimctlClient: SimulatorManaging {
    let shell: any ShellRunning
    var xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

    func loadInventory() async throws -> SimulatorInventory {
        let runtimes = try SimctlJSON.decodeRuntimes(try await run(["simctl", "runtime", "list", "-j"]))
        let devices: SimctlJSON.DeviceList
        do {
            devices = try SimctlJSON.decodeDevices(try await run(["simctl", "list", "devices", "-j"]))
        } catch is ScanFailure {
            throw SimctlError.unreadableOutput
        }
        // SDK 버전은 "현재 사용 중" 판정에만 쓴다. 읽지 못해도 목록은 보여 준다.
        let sdk = try? await run(["--sdk", "iphonesimulator", "--show-sdk-version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sdkVersion = sdk?.isEmpty == false ? sdk : nil
        return SimulatorInventory.make(runtimes: runtimes, devices: devices, sdkVersion: sdkVersion)
    }

    func deleteRuntime(_ identifier: String) async throws {
        try Self.requireUUID(identifier)
        _ = try await run(["simctl", "runtime", "delete", identifier])
    }

    func deleteDevice(_ udid: String) async throws {
        try Self.requireUUID(udid)
        _ = try await run(["simctl", "delete", udid])
    }

    func deleteUnavailableDevices() async throws {
        _ = try await run(["simctl", "delete", "unavailable"])
    }

    /// 8-4-4-4-12 16진수 UUID만 통과.
    static func isUUID(_ value: String) -> Bool {
        value.wholeMatch(of: /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) != nil
    }

    private static func requireUUID(_ value: String) throws {
        guard isUUID(value) else { throw SimctlError.invalidIdentifier(value) }
    }

    /// xcrun을 실행하고 stdout을 돌려준다. 실패를 도구 없음/명령 실패로 나눈다.
    private func run(_ arguments: [String]) async throws -> String {
        let result: ShellResult
        do {
            result = try await shell.run(xcrunURL, arguments: arguments)
        } catch ShellError.launchFailed(let message) {
            throw SimctlError.toolMissing(message)
        } catch let error as ShellError {
            throw SimctlError.commandFailed(String(describing: error))
        }
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isToolMissing(stderr) { throw SimctlError.toolMissing(stderr) }
            throw SimctlError.commandFailed(stderr.isEmpty ? "exit \(result.exitCode)" : stderr)
        }
        return result.stdout
    }

    /// `xcrun: error: invalid active developer path`, `unable to find utility "simctl"` 등.
    static func isToolMissing(_ stderr: String) -> Bool {
        stderr.hasPrefix("xcrun: error") || stderr.contains("xcode-select")
    }
}
