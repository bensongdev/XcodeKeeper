import Foundation
import UserNotifications

/// 사용자 알림. 테스트와 UI 테스트에서는 기록만 하는 구현을 쓴다.
protocol Notifying: Sendable {
    /// 알림을 보낸다. 권한이 없거나 실패하면 false.
    func send(_ content: AlertContent) async -> Bool
}

/// `UNUserNotificationCenter`로 보낸다. 권한은 처음 보낼 때 요청한다(이미 정했으면 창이 다시 뜨지 않는다).
struct UserNotifier: Notifying {
    static let targetIDsKey = "targetIDs"
    static let requestIdentifier = "freeSpace"

    func send(_ content: AlertContent) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.userInfo = [Self.targetIDsKey: content.targetIDs]
        // 같은 식별자를 쓰면 알림 센터에 이전 알림이 쌓이지 않고 바뀐다.
        let request = UNNotificationRequest(identifier: Self.requestIdentifier, content: notification, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}

/// 보낸 알림을 기록만 한다.
final class RecordingNotifier: Notifying, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [AlertContent] = []
    private let succeeds: Bool

    init(succeeds: Bool = true) {
        self.succeeds = succeeds
    }

    var sent: [AlertContent] { lock.withLock { stored } }

    func send(_ content: AlertContent) async -> Bool {
        lock.withLock { stored.append(content) }
        return succeeds
    }
}
