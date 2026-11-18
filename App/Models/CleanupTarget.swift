import Foundation

/// 지워도 되는 정도.
enum Safety: Sendable, Equatable {
    /// 다시 만들어지는 캐시. 기본 선택.
    case safe
    /// 다시 받거나 만들기 번거로운 것. 기본 미선택.
    case caution
    /// 정보만 보여 주고 정리하지 않는다.
    case infoOnly

    var title: String {
        switch self {
        case .safe: String(localized: "안전")
        case .caution: String(localized: "주의")
        case .infoOnly: String(localized: "정보만")
        }
    }
}

/// 정리 방식. 실제 정리는 M2의 `Cleaner`가 한다.
enum CleanupMethod: Sendable, Equatable {
    /// `FileManager.trashItem`으로 휴지통에 옮긴다.
    case trash
    /// 공식 CLI를 실행한다. 예: `["simctl", "delete", "unavailable"]` (`xcrun` 인자)
    case command([String])
    /// 정리하지 않는다(정보만).
    case none
}

/// 스캔 대상 정의. 새 대상은 `BuiltinTargets.all`에 하나만 추가하면 된다.
struct CleanupTarget: Identifiable, Sendable {
    let id: String
    let title: String
    /// 지워도 되는 이유와 지우면 생기는 일.
    let explanation: String
    let safety: Safety
    let method: CleanupMethod
    /// 찾은 항목이 없으면 목록에서 숨긴다(있을 때만 표시하는 대상).
    var hideWhenEmpty = false
    /// 휴지통으로 옮겨도 되는 위치(이 경로와 같거나 그 안). `PathGuard`가 정리 직전에 검증한다.
    var allowedRoots: @Sendable (ScanEnvironment) -> [URL] = { _ in [] }
    let locate: @Sendable (ScanEnvironment) async throws -> [ScanItem]

    /// 선택할 수 있는 대상인가. 정보만 보여 주는 대상은 선택할 수 없다.
    var isSelectable: Bool { safety != .infoOnly && method != .none }

    /// 스캔이 끝났을 때 기본으로 선택하는가.
    var isSelectedByDefault: Bool { isSelectable && safety == .safe }

    /// 그룹 단위로만 선택하는가(명령 하나로 모두 정리하는 대상).
    var selectsAsGroup: Bool {
        if case .command = method { return true }
        return false
    }
}

/// 스캔으로 찾은 항목 하나.
struct ScanItem: Identifiable, Sendable, Equatable {
    /// 대상 안에서 고유한 값. 보통 경로.
    let id: String
    let name: String
    /// 실제 점유 용량(allocated size).
    let bytes: Int64
    let lastModified: Date?
    /// Finder에서 보기와 휴지통 이동에 쓰는 위치. 경로가 없는 항목(스냅샷 등)은 nil.
    let url: URL?

    init(url: URL, name: String? = nil, bytes: Int64, lastModified: Date?) {
        self.id = url.path
        self.name = name ?? url.lastPathComponent
        self.bytes = bytes
        self.lastModified = lastModified
        self.url = url
    }

    init(id: String, name: String, bytes: Int64 = 0, lastModified: Date? = nil) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.lastModified = lastModified
        self.url = nil
    }
}

/// 대상별 스캔 실패 원인.
enum ScanFailure: Error, Sendable, Equatable {
    case permissionDenied
    /// 외부 명령이 실패했다(도구 없음, 비정상 종료 등). stderr 등 원문을 담는다.
    case commandFailed(String)
    case other(String)

    var title: String {
        switch self {
        case .permissionDenied: String(localized: "권한 없음")
        case .commandFailed, .other: String(localized: "확인 불가")
        }
    }
}
