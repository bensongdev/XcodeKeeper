import Foundation

/// 정리 직전 경로 검증. 허용 루트와 같거나 그 안에 있는 경로만 통과시킨다.
/// 심볼릭 링크를 푼 실제 경로로도 다시 확인해, 링크를 통해 루트 밖을 가리키는 경우를 막는다.
enum PathGuard {
    enum Rejection: Error, Equatable, Sendable {
        case notFileURL
        case containsParentReference
        case missing
        case outsideAllowedRoots
        case unsafeRoot
    }

    /// 루트로 쓸 수 없는 위치. 대상 정의가 잘못되어도 홈이나 시스템 폴더 전체를 지우지 않게 한다.
    private static func isUnsafeRoot(_ path: String, home: String) -> Bool {
        let blocked = ["/", "/System", "/Library", "/Applications", "/Users", "/private", "/usr", "/bin", "/sbin"]
        let homeLevel = [home, home + "/Library", home + "/Library/Caches", home + "/Library/Developer",
                         home + "/Library/Developer/Xcode", home + "/Documents", home + "/Desktop"]
        return blocked.contains(path) || homeLevel.contains(path)
    }

    /// `url`이 `roots` 중 하나와 같거나 그 안에 있으면 통과. 아니면 이유를 던진다.
    static func validate(_ url: URL, allowedRoots roots: [URL], home: URL) throws {
        guard url.isFileURL else { throw Rejection.notFileURL }
        guard !url.pathComponents.contains("..") else { throw Rejection.containsParentReference }
        // 링크 자체가 있는지 본다(링크가 가리키는 대상이 없어도 링크는 존재할 수 있다).
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { throw Rejection.missing }

        let homePath = home.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedRoots = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        guard !resolvedRoots.isEmpty else { throw Rejection.outsideAllowedRoots }
        if resolvedRoots.contains(where: { isUnsafeRoot($0, home: homePath) }) { throw Rejection.unsafeRoot }

        let literal = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        let literalRoots = roots.map { $0.standardizedFileURL.path }
        // 링크를 풀기 전 경로와 푼 뒤 경로가 모두 루트 안이어야 한다.
        guard isInside(literal, anyOf: literalRoots + resolvedRoots),
              isInside(resolved, anyOf: resolvedRoots) else {
            throw Rejection.outsideAllowedRoots
        }
    }

    /// `path`가 루트와 같거나 "루트/" 로 시작하는가. `/a/Derived`와 `/a/DerivedData2`를 구분한다.
    static func isInside(_ path: String, anyOf roots: [String]) -> Bool {
        roots.contains { root in path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/") }
    }
}
